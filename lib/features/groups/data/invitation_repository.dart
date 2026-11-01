import '../../../core/models/membership_position.dart';
import '../../../core/models/user_role.dart';

class GroupInvitation {
  const GroupInvitation(
      {required this.groupId,
      required this.groupName,
      required this.recipientUid,
      required this.inviterUid,
      required this.role,
      required this.position,
      required this.customPosition});
  final String groupId, groupName, recipientUid, inviterUid, customPosition;
  final UserRole role;
  final MembershipPosition position;
  String get positionLabel =>
      position == MembershipPosition.other ? customPosition : position.label;
}

class MembershipNotification {
  const MembershipNotification(this.id, this.groupName);
  final String id, groupName;
}

abstract interface class InvitationRepository {
  Stream<List<GroupInvitation>> watchPending();
  Stream<List<MembershipNotification>> watchNotifications();
  Future<void> setAllowInvitations(bool allow);
  Future<void> invite(
      {required String groupId,
      required String email,
      required UserRole role,
      required MembershipPosition position,
      String customPosition = ''});
  Future<void> respond(GroupInvitation invitation, {required bool accept});
  Future<void> markRead(String notificationId);
  Future<void> updateMember(
      {required String groupId,
      required String uid,
      required UserRole role,
      required MembershipPosition position,
      String customPosition = ''});
  Future<void> removeMember({required String groupId, required String uid});
}

String? validateInvitationEmail(String? value) {
  final email = value?.trim() ?? '';
  return email.length > 320 ||
          !RegExp(r'^[^\s/@]+@[^\s/@]+\.[^\s/@]+$').hasMatch(email)
      ? 'Enter a valid Google email address.'
      : null;
}
