import '../../../core/cache/local_content_cache.dart';
import '../../../core/cache/content_cache_database.dart';
import '../../../core/cache/offline_reads.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/user_role.dart';
import 'auth_repository.dart';
import 'google_sign_in_failures.dart';

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
        'Firebase data is unavailable. Check configuration and retry.',
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
      profileComplete: data['profileComplete'] == true,
      allowInvitations: data['allowInvitations'] != false);
}

class FirebaseAuthRepository
    implements
        AuthRepository,
        PersistentAuthRepository,
        AccountProfileRepository {
  FirebaseAuthRepository(this.auth, this.firestore, {this.cache});
  final LocalContentCache? cache;
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  Future<void>? _googleReady;

  Future<void> _ensureAccount() async {
    final user = auth.currentUser;
    if (user == null) throw const AccountException('Please sign in again.');
    if (!user.emailVerified ||
        !user.providerData.any((p) => p.providerId == 'google.com')) {
      throw const AccountException('A verified Google account is required.');
    }
    final ref = firestore.doc('profiles/${user.uid}');
    await firestore.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) {
        final d = existing.data()!;
        if (!d.containsKey('allowInvitations')) {
          final complete = d['profileComplete'] == true;
          tx.update(ref, {
            'allowInvitations': complete,
            'updatedAt': FieldValue.serverTimestamp()
          });
          if (complete) {
            tx.set(firestore.doc('emailDirectory/${user.email!.toLowerCase()}'),
                {'uid': user.uid});
          }
        }
        return;
      }
      final parts = (user.displayName ?? '').trim().split(RegExp(r'\s+'));
      tx.set(ref, {
        'firstName': parts.first.length <= 80 ? parts.first : '',
        'lastName':
            parts.skip(1).join(' ').length <= 80 ? parts.skip(1).join(' ') : '',
        'email': user.email!,
        'profileComplete': false,
        'allowInvitations': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'completedAt': null,
      });
    });
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    var stage = 'restore';
    try {
      if (auth.currentUser == null) {
        if (kIsWeb) {
          stage = 'firebase-popup';
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
          stage = 'google-initialize';
          await (_googleReady ??= GoogleSignIn.instance.initialize(
              // Android identifies the app by package + signing certificate;
              // its serverClientId is the Web OAuth client, never the Android ID.
              clientId: defaultTargetPlatform == TargetPlatform.android ||
                      client.isEmpty
                  ? null
                  : client,
              serverClientId: server.isEmpty ? null : server));
          stage = 'google-authenticate';
          final account = await GoogleSignIn.instance.authenticate();
          final idToken = account.authentication.idToken;
          if (idToken == null) {
            throw const AccountException(
                'Google did not return an identity token. Check OAuth configuration.');
          }
          stage = 'firebase-credential';
          await auth.signInWithCredential(
              GoogleAuthProvider.credential(idToken: idToken));
        }
      }
      stage = 'profile-load';
      final user = await getCurrentUser();
      if (user == null) {
        throw const AccountException(
            'Google Sign-In did not complete. Please retry.');
      }
      return AuthResult(user: user, role: UserRole.worshipTrainee);
    } on GoogleSignInException catch (error, stack) {
      logGoogleSignInFailure(error, stack, stage);
      throw googleSignInFailure(error);
    } on FirebaseAuthException catch (error, stack) {
      logGoogleSignInFailure(error, stack, stage);
      throw firebaseGoogleSignInFailure(error);
    } catch (error, stack) {
      logGoogleSignInFailure(error, stack, stage);
      throw accountFailure(error);
    }
  }

  @override
  Future<AppUser?> getCurrentUser() async {
    if (auth.currentUser == null) return null;
    final uid = auth.currentUser!.uid;
    try {
      await _ensureAccount().timeout(const Duration(seconds: 8));
      final profile = await firestore
          .doc('profiles/$uid')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (auth.currentUser?.uid != uid) return null;
      if (!profile.exists) {
        throw const AccountException(
            'Could not load your account profile. Please retry.');
      }
      await cache?.saveMetadata('', CachedKind.profile, uid, profile.data()!);
      cache?.markIdentityFresh();
      return userFromProfile(uid, profile.data()!);
    } catch (error) {
      if (error is FirebaseException && error.code == 'permission-denied') {
        await cache?.invalidateAccount(uid);
      }
      final offline = await _offlineProfile(uid, error);
      if (offline != null) return offline;
      throw accountFailure(error);
    }
  }

  Future<AppUser?> _offlineProfile(String uid, Object error) async {
    final user = auth.currentUser;
    if (!isConnectionFailure(error) ||
        cache == null ||
        user?.uid != uid ||
        user?.emailVerified != true ||
        !user!.providerData.any((p) => p.providerId == 'google.com')) {
      return null;
    }
    try {
      final saved = (await cache!.metadata(CachedKind.profile))
          .where((d) => d['id'] == uid)
          .firstOrNull;
      if (saved == null) return null;
      final profile = userFromProfile(
          uid, Map<String, dynamic>.from(saved['value'] as Map));
      if (profile.profileComplete) {
        cache!.markIdentityOffline();
        return profile;
      }
      return null;
    } catch (_) {
      return null;
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
            await _ensureAccount().timeout(const Duration(seconds: 8));
            if (cancelled || version != generation) return;
            final initial = await firestore
                .doc('profiles/${user.uid}')
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 8));
            if (cancelled || version != generation) return;
            if (!initial.exists) {
              throw const AccountException(
                  'Profile unavailable. Sign out and retry.');
            }
            await cache?.saveMetadata(
                '', CachedKind.profile, user.uid, initial.data()!);
            cache?.markIdentityFresh();
            output.add(userFromProfile(user.uid, initial.data()!));
          } catch (error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              await cache?.invalidateAccount(user.uid);
            }
            final offline = await _offlineProfile(user.uid, error);
            if (cancelled || version != generation) return;
            if (offline == null) {
              output.addError(accountFailure(error));
              return;
            }
            output.add(offline);
          }
          try {
            profileSub = firestore
                .doc('profiles/${user.uid}')
                .snapshots(includeMetadataChanges: true)
                .listen((snapshot) {
              if (cancelled ||
                  version != generation ||
                  snapshot.metadata.isFromCache ||
                  snapshot.metadata.hasPendingWrites) {
                return;
              }
              if (snapshot.exists) {
                unawaited(cache?.saveMetadata(
                    '', CachedKind.profile, user.uid, snapshot.data()!));
                cache?.markIdentityFresh();
                output.add(userFromProfile(user.uid, snapshot.data()!));
              } else {
                unawaited(cache?.invalidateAccount(user.uid));
                output.addError(const AccountException(
                    'Profile unavailable. Sign out and retry.'));
              }
            }, onError: (Object error) {
              if (!cancelled &&
                  version == generation &&
                  !isConnectionFailure(error)) {
                if (error is FirebaseException &&
                    error.code == 'permission-denied') {
                  unawaited(cache?.invalidateAccount(user.uid));
                }
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
      final first = firstName.trim(), last = lastName.trim();
      if ([first, last].any((n) =>
          n.isEmpty ||
          n.length > 80 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(n))) {
        throw const AccountException(
            'First and last names are required (maximum 80 characters).');
      }
      await firestore.runTransaction((tx) async {
        final ref = firestore.doc('profiles/$uid');
        final doc = await tx.get(ref);
        final data = doc.data()!;
        final allow = data['profileComplete'] == true
            ? data['allowInvitations'] != false
            : true;
        tx.update(ref, {
          'firstName': first,
          'lastName': last,
          'email': auth.currentUser!.email!,
          'profileComplete': true,
          'allowInvitations': allow,
          'completedAt': data['completedAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp()
        });
        if (allow) {
          tx.set(
              firestore.doc(
                  'emailDirectory/${auth.currentUser!.email!.toLowerCase()}'),
              {'uid': uid});
        }
      });
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
