import '../../../core/models/user_role.dart';
import '../../../core/models/worship_group.dart';

/// Contract for group data access. Mock impl is in-memory; Firestore impl
/// in Phase 2 will subscribe to `groups/{id}` and `groups/{id}/members`.
abstract class GroupRepository {
  /// Emits the full group list on subscribe, then on every mutation.
  Stream<List<WorshipGroup>> watchGroups();

  /// Groups the given user belongs to.
  Stream<List<WorshipGroup>> watchGroupsForUser(String userId);

  Future<WorshipGroup?> getGroup(String groupId);

  /// Phase 1: no-op — join/create is a stub UI. Firestore impl will write.
  Future<void> createGroup(String name, String churchName);

  /// Phase 1: no-op.
  Future<void> joinGroup(String inviteCode);

  /// Change a member's role. Only Administrators may call this in real impls.
  Future<void> updateMemberRole({
    required String groupId,
    required String userId,
    required UserRole role,
  });
}
