import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/user_role.dart';
import 'auth_repository.dart';

AccountException accountFailure(Object error) {
  if (error is AccountException) return error;
  if (error is TimeoutException) {
    return const AccountException(
        'Connection unavailable. Check your connection and retry.');
  }
  if (error is FirebaseException) {
    return AccountException(switch (error.code) {
      'network-request-failed' ||
      'unavailable' ||
      'deadline-exceeded' =>
        'Connection unavailable. Check your connection and retry.',
      'resource-exhausted' ||
      'too-many-requests' =>
        'Too many requests. Please try again later.',
      'unauthenticated' || 'user-token-expired' => 'Please sign in again.',
      'permission-denied' =>
        'This operation requires a verified Google account and authorized membership.',
      'not-found' ||
      'unimplemented' =>
        'The Firebase foundation functions are not deployed. Follow the Firebase setup instructions.',
      _ => error.message ?? 'Firebase operation failed. Please retry.',
    });
  }
  return const AccountException(
      'Could not complete the account operation. Please retry.');
}

AppUser userFromProfile(String uid, Map<String, dynamic> data) {
  final first = data['firstName'] as String? ?? '';
  final last = data['lastName'] as String? ?? '';
  return AppUser(
      id: uid,
      firstName: first,
      lastName: last,
      email: data['email'] as String? ?? '',
      instrument: '',
      avatarInitials:
          '${first.isEmpty ? '' : String.fromCharCode(first.runes.first)}${last.isEmpty ? '' : String.fromCharCode(last.runes.first)}'
              .toUpperCase(),
      profileComplete: data['profileComplete'] == true);
}

class FirebaseAuthRepository
    implements
        AuthRepository,
        PersistentAuthRepository,
        AccountProfileRepository {
  FirebaseAuthRepository(this.auth, this.firestore, this.functions);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  Future<void>? _googleReady;

  Future<void> _ensureAccount() async {
    final user = auth.currentUser;
    if (user == null) throw const AccountException('Please sign in again.');
    if (!user.emailVerified ||
        !user.providerData.any((p) => p.providerId == 'google.com')) {
      throw const AccountException('A verified Google account is required.');
    }
    await functions.httpsCallable('ensureAccount').call<void>();
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    try {
      if (auth.currentUser == null) {
        if (kIsWeb) {
          await auth.signInWithPopup(GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}));
        } else {
          if (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux) {
            throw const AccountException(
                'Google Sign-In is available on Android, iOS, macOS and Web. Use a supported build.');
          }
          const client = String.fromEnvironment('WF_GOOGLE_CLIENT_ID');
          const server = String.fromEnvironment('WF_GOOGLE_SERVER_CLIENT_ID');
          await (_googleReady ??= GoogleSignIn.instance.initialize(
              clientId: client.isEmpty ? null : client,
              serverClientId: server.isEmpty ? null : server));
          final account = await GoogleSignIn.instance.authenticate();
          final idToken = account.authentication.idToken;
          if (idToken == null) {
            throw const AccountException(
                'Google did not return an identity token. Check OAuth configuration.');
          }
          await auth.signInWithCredential(
              GoogleAuthProvider.credential(idToken: idToken));
        }
      }
      final user = await getCurrentUser();
      if (user == null) {
        throw const AccountException(
            'Google Sign-In did not complete. Please retry.');
      }
      return AuthResult(user: user, role: UserRole.worshipTrainee);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SignInCancelled();
      }
      throw const AccountException(
          'Google Sign-In failed. Check network, signing SHA and OAuth client configuration.');
    } on FirebaseAuthException catch (error) {
      if (const [
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-cancelled'
      ].contains(error.code)) {
        throw const SignInCancelled();
      }
      throw accountFailure(error);
    } catch (error) {
      throw accountFailure(error);
    }
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    if (auth.currentUser == null) return null;
    final uid = auth.currentUser!.uid;
    try {
      await _ensureAccount();
      final profile = await firestore
          .doc('profiles/$uid')
          .get(const GetOptions(source: Source.server));
      if (auth.currentUser?.uid != uid) return null;
      if (!profile.exists) {
        throw const AccountException(
            'Could not load your account profile. Please retry.');
      }
      return userFromProfile(uid, profile.data()!);
    } catch (error) {
      throw accountFailure(error);
    }
  }

  @override
  Stream<AppUser?> watchUser() => Stream.multi((output) {
        StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? profileSub;
        var generation = 0;
        var cancelled = false;
        final authSub = auth.authStateChanges().listen((user) async {
          final version = ++generation;
          await profileSub?.cancel();
          profileSub = null;
          if (cancelled || version != generation) return;
          if (user == null) {
            output.add(null);
            return;
          }
          try {
            await _ensureAccount();
            if (cancelled || version != generation) return;
            final initial = await firestore
                .doc('profiles/${user.uid}')
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 20));
            if (cancelled || version != generation) return;
            if (!initial.exists) {
              throw const AccountException(
                  'Profile unavailable. Sign out and retry.');
            }
            output.add(userFromProfile(user.uid, initial.data()!));
            profileSub = firestore
                .doc('profiles/${user.uid}')
                .snapshots(includeMetadataChanges: true)
                .listen((snapshot) {
              if (cancelled ||
                  version != generation ||
                  snapshot.metadata.isFromCache) {
                return;
              }
              if (snapshot.exists) {
                output.add(userFromProfile(user.uid, snapshot.data()!));
              } else {
                output.addError(const AccountException(
                    'Profile unavailable. Sign out and retry.'));
              }
            }, onError: (Object error) {
              if (!cancelled && version == generation) {
                output.addError(accountFailure(error));
              }
            });
          } catch (error) {
            if (!cancelled && version == generation) {
              output.addError(accountFailure(error));
            }
          }
        }, onError: (Object error) => output.addError(accountFailure(error)));
        output.onCancel = () async {
          cancelled = true;
          generation++;
          await authSub.cancel();
          await profileSub?.cancel();
        };
      });

  @override
  Future<AppUser> completeProfile(String firstName, String lastName) async {
    try {
      final uid = auth.currentUser?.uid;
      if (uid == null) throw const AccountException('Please sign in again.');
      await functions
          .httpsCallable('completeProfile')
          .call<void>({'firstName': firstName, 'lastName': lastName});
      if (uid != auth.currentUser?.uid) {
        throw const AccountException(
            'The signed-in account changed. Please retry.');
      }
      final snapshot = await firestore
          .doc('profiles/$uid')
          .get(const GetOptions(source: Source.server));
      return userFromProfile(uid, snapshot.data()!);
    } catch (error) {
      throw accountFailure(error);
    }
  }

  @override
  Future<String> getPrivateInvitationCode() async {
    try {
      final result = await functions
          .httpsCallable('getPrivateInvitationCode')
          .call<Map<String, dynamic>>();
      final code = result.data['code'];
      if (code is! String || !RegExp(r'^[A-Z0-9]{5}$').hasMatch(code)) {
        throw const AccountException(
            'Private invitation code unavailable. Retry later.');
      }
      return code;
    } catch (error) {
      throw accountFailure(error);
    }
  }

  @override
  Future<void> signOut() async {
    // Always clear Firebase even when the Google provider's local cleanup fails.
    await auth.signOut();
    if (!kIsWeb && _googleReady != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase is already signed out; provider cleanup must not block it.
      }
    }
  }
}
