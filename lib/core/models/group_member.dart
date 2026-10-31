import 'app_user.dart';
import 'user_role.dart';

class GroupMember {
  const GroupMember({
    required this.user,
    required this.role,
    required this.joinedAt,
  });

  final AppUser user;
  final UserRole role;
  final DateTime joinedAt;

  GroupMember copyWith({UserRole? role}) {
    return GroupMember(
      user: user,
      role: role ?? this.role,
      joinedAt: joinedAt,
    );
  }
}