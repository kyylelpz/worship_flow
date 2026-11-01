import 'app_user.dart';
import 'user_role.dart';

class SessionState {
  const SessionState({
    this.user,
    this.role,
    this.selectedGroupId,
    this.isLoading = false,
    this.isRestoring = false,
    this.errorMessage,
  });

  final AppUser? user;
  final UserRole? role;
  final String? selectedGroupId;
  final bool isLoading;
  final bool isRestoring;
  final String? errorMessage;

  bool get isAuthenticated => user != null;
  bool get hasGroup => selectedGroupId != null;

  SessionState copyWith({
    AppUser? user,
    UserRole? role,
    String? selectedGroupId,
    bool? isLoading,
    bool? isRestoring,
    String? errorMessage,
    bool clearUser = false,
    bool clearGroup = false,
    bool clearError = false,
  }) {
    return SessionState(
      user: clearUser ? null : (user ?? this.user),
      role: role ?? this.role,
      selectedGroupId:
          clearGroup ? null : (selectedGroupId ?? this.selectedGroupId),
      isLoading: isLoading ?? this.isLoading,
      isRestoring: isRestoring ?? this.isRestoring,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
