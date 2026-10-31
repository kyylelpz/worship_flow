import '../../../core/mock_data/mock_users.dart';
import '../../../core/models/user_role.dart';
import 'auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  MockAuthRepository({this.delay = const Duration(milliseconds: 900)});

  final Duration delay;
  AppUserOrNull _current;

  @override
  Future<AuthResult> signInWithGoogle() async {
    await Future<void>.delayed(delay);
    const result = AuthResult(
      user: mockCurrentUser,
      role: UserRole.administrator,
    );
    _current = result.user;
    return result;
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    _current = null;
  }

  @override
  Future<AppUserOrNull> getCurrentUser() async => _current;
}
