import '../../../core/cache/cache_providers.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../groups/providers/group_providers.dart';
import '../data/firebase_auth_repository.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/session_state.dart';
import '../../../core/models/user_role.dart';
import '../data/auth_repository.dart';
import '../data/mock_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (ref.watch(useMockBackendProvider)) return MockAuthRepository();
  return FirebaseAuthRepository(
      ref.watch(firebaseAuthProvider), ref.watch(firestoreProvider),
      cache: ref.watch(localContentCacheProvider));
});

class AuthController extends StateNotifier<SessionState> {
  AuthController(this._repo, {bool allowMockControls = false})
      : _allowMockControls = allowMockControls,
        super(SessionState(isRestoring: _repo is PersistentAuthRepository)) {
    if (_repo is PersistentAuthRepository) {
      _subscription = (_repo as PersistentAuthRepository)
          .watchUser()
          .listen(_applyUser, onError: (Object error) {
        if (mounted) state = SessionState(errorMessage: '$error');
      });
    }
  }
  final AuthRepository _repo;
  final bool _allowMockControls;
  StreamSubscription<AppUser?>? _subscription;
  int _operation = 0;

  void _applyUser(AppUser? user) {
    if (!mounted) return;
    if (user == null) {
      state = const SessionState();
      return;
    }
    final same = user.id == state.user?.id;
    state = SessionState(
        user: user,
        role: same ? state.role : UserRole.worshipTrainee,
        selectedGroupId:
            same && user.profileComplete ? state.selectedGroupId : null);
  }

  Future<void> signInWithGoogle() async {
    if (state.isLoading) return;
    final operation = ++_operation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repo.signInWithGoogle();
      if (!mounted || operation != _operation) return;
      _applyUser(result.user);
      if (_allowMockControls) state = state.copyWith(role: result.role);
    } on SignInCancelled {
      if (mounted && operation == _operation) {
        state = state.copyWith(isLoading: false, clearError: true);
      }
    } catch (error) {
      if (mounted && operation == _operation) {
        state = state.copyWith(isLoading: false, errorMessage: '$error');
      }
    }
  }

  Future<void> retrySession() async {
    final operation = ++_operation;
    state = state.copyWith(isRestoring: true, clearError: true);
    try {
      final user = await _repo.getCurrentUser();
      if (mounted && operation == _operation) _applyUser(user);
    } catch (error) {
      if (mounted && operation == _operation) {
        state = SessionState(errorMessage: '$error');
      }
    }
  }

  Future<void> completeProfile(String firstName, String lastName) async {
    final repository = _repo;
    if (repository is! AccountProfileRepository) {
      throw const AccountException(
          'Profile storage is unavailable in this development repository.');
    }
    final uid = state.user?.id;
    final user = await (repository as AccountProfileRepository)
        .completeProfile(firstName, lastName);
    if (mounted && uid == state.user?.id) _applyUser(user);
  }

  Future<void> signOut() async {
    ++_operation;
    try {
      await _repo.signOut();
      if (mounted) state = const SessionState();
    } catch (error) {
      if (mounted) {
        state =
            state.copyWith(errorMessage: 'Could not sign out. Please retry.');
      }
    }
  }

  void selectGroup(String groupId) {
    if (state.user?.profileComplete != true) return;
    state = state.copyWith(selectedGroupId: groupId);
  }

  void clearGroup() => state = state.copyWith(clearGroup: true);
  void setRoleForTesting(UserRole role) {
    if (!_allowMockControls) {
      throw StateError('Development role controls are disabled.');
    }
    state = state.copyWith(role: role);
  }

  void updateProfile(AppUser user) {
    if (!_allowMockControls) {
      throw StateError('Use the trusted profile repository.');
    }
    state = state.copyWith(user: user);
  }

  void clearError() => state = state.copyWith(clearError: true);
  @override
  void dispose() {
    _operation++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

final sessionProvider = StateNotifierProvider<AuthController, SessionState>(
    (ref) => AuthController(ref.watch(authRepositoryProvider),
        allowMockControls: ref.watch(useMockBackendProvider)));

/// Convenience getters to avoid importing SessionState everywhere.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(sessionProvider).user,
);

final currentRoleProvider = Provider<UserRole?>(
  (ref) {
    final session = ref.watch(sessionProvider);
    ref.watch(cacheChangesProvider);
    final cache = ref.watch(localContentCacheProvider);
    if (session.selectedGroupId != null &&
        cache?.isReadOnly(session.selectedGroupId!) == true) {
      return UserRole.worshipTrainee;
    }
    if (ref.watch(useMockBackendProvider)) return session.role;
    return session.selectedGroupId == null
        ? null
        : ref.watch(roleInGroupProvider(session.selectedGroupId!));
  },
);

final selectedGroupIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider).selectedGroupId,
);
