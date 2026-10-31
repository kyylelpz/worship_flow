import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/group_member.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/worship_group.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/group_repository.dart';
import '../data/mock_group_repository.dart';

/// Swap to FirestoreGroupRepository in Phase 2 — no other file changes.
final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  final repo = MockGroupRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// All groups the current user belongs to.
final userGroupsProvider = StreamProvider<List<WorshipGroup>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const Stream.empty();
  return ref.watch(groupRepositoryProvider).watchGroupsForUser(user.id);
});

/// All groups (used by Group Members screen and future admin tools).
final allGroupsProvider = StreamProvider<List<WorshipGroup>>((ref) {
  return ref.watch(groupRepositoryProvider).watchGroups();
});

/// The currently selected group — null when none selected.
final selectedGroupProvider = Provider<WorshipGroup?>((ref) {
  final groupId = ref.watch(selectedGroupIdProvider);
  if (groupId == null) return null;
  final groups = ref.watch(userGroupsProvider).valueOrNull;
  if (groups == null) return null;
  for (final g in groups) {
    if (g.id == groupId) return g;
  }
  return null;
});

/// Look up a specific group by id from the all-groups stream.
final groupByIdProvider =
    Provider.family<WorshipGroup?, String>((ref, groupId) {
  final groups = ref.watch(allGroupsProvider).valueOrNull;
  if (groups == null) return null;
  for (final g in groups) {
    if (g.id == groupId) return g;
  }
  return null;
});

/// The current user's membership in a given group (null if not a member).
final currentMembershipProvider =
    Provider.family<GroupMember?, String>((ref, groupId) {
  final user = ref.watch(currentUserProvider);
  final group = ref.watch(groupByIdProvider(groupId));
  if (user == null || group == null) return null;
  for (final m in group.members) {
    if (m.user.id == user.id) return m;
  }
  return null;
});

/// Convenience: the current role *in a specific group*. This may differ from
/// the developer-selected role in session state. Used to gate group-level
/// actions such as "manage members".
final roleInGroupProvider = Provider.family<UserRole?, String>((ref, groupId) {
  return ref.watch(currentMembershipProvider(groupId))?.role;
});
