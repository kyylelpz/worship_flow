import '../../../core/models/user_role.dart';
import '../../../core/models/worship_group.dart';
import '../../../core/models/membership_position.dart';

/// Group reads are scoped to authenticated membership in Firebase mode.
abstract class GroupRepository {
  /// Emits all groups this repository is authorized to expose (own groups in Firebase).
  Stream<List<WorshipGroup>> watchGroups();

  /// Groups the given user belongs to.
  Stream<List<WorshipGroup>> watchGroupsForUser(String userId);

  Future<WorshipGroup?> getGroup(String groupId);

  /// Legacy entry point; Firebase creation uses GroupCreationRepository with an explicit position.
  Future<void> createGroup(String name, String churchName);

  /// Reserved for invitation joining; unavailable in the Firebase foundation.
  Future<void> joinGroup(String inviteCode);

  /// Legacy development control; trusted membership management is deferred.
  Future<void> updateMemberRole({
    required String groupId,
    required String userId,
    required UserRole role,
  });
}

/// Creation is an idempotent trusted operation, not an arbitrary membership write.
abstract interface class GroupCreationRepository {
  Future<String> createGroupWithPosition(
      {required String name,
      required String churchName,
      required MembershipPosition position,
      String customPosition = '',
      required String requestId});
}
