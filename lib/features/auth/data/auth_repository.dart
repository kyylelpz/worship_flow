import '../../../core/models/app_user.dart';
import '../../../core/models/user_role.dart';

typedef AppUserOrNull = AppUser?;

class AuthResult {
  const AuthResult({required this.user, required this.role});
  final AppUser user;
  final UserRole role;
}

abstract class AuthRepository {
  Future<AuthResult> signInWithGoogle();
  Future<void> signOut();
  Future<AppUserOrNull> getCurrentUser();
}