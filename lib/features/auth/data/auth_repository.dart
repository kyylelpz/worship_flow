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

abstract interface class PersistentAuthRepository {
  Stream<AppUser?> watchUser();
}

/// Profile writes are validated by Firestore Security Rules.
abstract interface class AccountProfileRepository {
  Future<AppUser> completeProfile(String firstName, String lastName);
}

class SignInCancelled implements Exception {
  const SignInCancelled();
}

class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}
