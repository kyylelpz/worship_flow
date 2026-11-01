import 'app_user.dart';
import 'user_role.dart';
import 'membership_position.dart';

class GroupMember {
  const GroupMember({
    required this.user,
    required this.role,
    required this.joinedAt,
    this.position = MembershipPosition.other,
    this.customPosition = '',
    this.updatedAt,
    this.groupId,
  });

  final AppUser user;
  final UserRole role;
  final DateTime joinedAt;
  final MembershipPosition position;
  final String customPosition;
  final DateTime? updatedAt;
  final String? groupId;
  String get uid => user.id;
  DateTime get createdAt => joinedAt;
  String get positionLabel =>
      position == MembershipPosition.other && customPosition.isNotEmpty
          ? customPosition
          : position.label;

  GroupMember copyWith(
      {UserRole? role,
      MembershipPosition? position,
      String? customPosition,
      DateTime? updatedAt}) {
    return GroupMember(
      user: user,
      role: role ?? this.role,
      joinedAt: joinedAt,
      position: position ?? this.position,
      customPosition: customPosition ?? this.customPosition,
      updatedAt: updatedAt ?? this.updatedAt,
      groupId: groupId,
    );
  }
}
