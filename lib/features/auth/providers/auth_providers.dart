import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/session_state.dart';
import '../../../core/models/user_role.dart';
import '../data/auth_repository.dart';
import '../data/mock_auth_repository.dart';

/// The single source of truth for repository injection. Swap this line in
/// Phase 2 for `FirestoreAuthRepository()` — nothing else changes.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(),
);

/// Session controller — owns the app-wide session state (user + role + group).
/// Both the router and every feature read from here.
class AuthController extends StateNotifier<SessionState> {
  AuthController(this._repo) : super(const SessionState());

  final AuthRepository _repo;

  Future<void> signInWithGoogle() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repo.signInWithGoogle();
      state = state.copyWith(
        user: result.user,
        role: result.role,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sign-in failed. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const SessionState();
  }

  void selectGroup(String groupId) {
    state = state.copyWith(selectedGroupId: groupId);
  }

  void clearGroup() {
    state = state.copyWith(clearGroup: true);
  }

  /// Developer-only role switcher. Does not change the underlying user.
  void setRoleForTesting(UserRole role) {
    state = state.copyWith(role: role);
  }

  /// Used to also allow updating profile name/instrument from the Profile screen.
  void updateProfile(AppUser user) {
    state = state.copyWith(user: user);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final sessionProvider =
    StateNotifierProvider<AuthController, SessionState>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

/// Convenience getters to avoid importing SessionState everywhere.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(sessionProvider).user,
);

final currentRoleProvider = Provider<UserRole?>(
  (ref) => ref.watch(sessionProvider).role,
);

final selectedGroupIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider).selectedGroupId,
);
