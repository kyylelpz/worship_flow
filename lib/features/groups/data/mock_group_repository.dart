import 'dart:async';

import '../../../core/mock_data/mock_groups.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/worship_group.dart';
import 'group_repository.dart';

class MockGroupRepository implements GroupRepository {
  MockGroupRepository({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;

  // Mutable copy so member role changes during a session are reflected.
  final List<WorshipGroup> _groups = List<WorshipGroup>.from(mockGroups);
  final StreamController<List<WorshipGroup>> _controller =
      StreamController<List<WorshipGroup>>.broadcast();

  List<WorshipGroup> _snapshot() => List<WorshipGroup>.unmodifiable(_groups);

  void _emit() {
    if (!_controller.isClosed) _controller.add(_snapshot());
  }

  @override
  Stream<List<WorshipGroup>> watchGroups() async* {
    await Future<void>.delayed(delay);
    yield _snapshot();
    yield* _controller.stream;
  }

  @override
  Stream<List<WorshipGroup>> watchGroupsForUser(String userId) async* {
    await Future<void>.delayed(delay);
    Iterable<WorshipGroup> filter(List<WorshipGroup> all) =>
        all.where((g) => g.members.any((m) => m.user.id == userId));
    yield List<WorshipGroup>.unmodifiable(filter(_groups));
    yield* _controller.stream
        .map((all) => List<WorshipGroup>.unmodifiable(filter(all)));
  }

  @override
  Future<WorshipGroup?> getGroup(String groupId) async {
    await Future<void>.delayed(delay);
    for (final g in _groups) {
      if (g.id == groupId) return g;
    }
    return null;
  }

  @override
  Future<void> createGroup(String name, String churchName) async {
    await Future<void>.delayed(delay);
    // Phase 1 stub — no-op until Firestore.
  }

  @override
  Future<void> joinGroup(String inviteCode) async {
    await Future<void>.delayed(delay);
    // Phase 1 stub — no-op until Firestore.
  }

  @override
  Future<void> updateMemberRole({
    required String groupId,
    required String userId,
    required UserRole role,
  }) async {
    await Future<void>.delayed(delay);

    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return;

    final group = _groups[idx];
    final updatedMembers = group.members.map((m) {
      if (m.user.id == userId) return m.copyWith(role: role);
      return m;
    }).toList();

    _groups[idx] = WorshipGroup(
      id: group.id,
      name: group.name,
      churchName: group.churchName,
      accentColorValue: group.accentColorValue,
      members: List<GroupMember>.unmodifiable(updatedMembers),
    );
    _emit();
  }

  void dispose() {
    _controller.close();
  }
}
