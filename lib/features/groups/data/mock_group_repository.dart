import 'dart:async';

import '../../../core/mock_data/mock_groups.dart';
import '../../../core/models/group_member.dart';
import '../../../core/mock_data/mock_users.dart';
import '../../../core/models/membership_position.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/worship_group.dart';
import 'group_repository.dart';

class MockGroupRepository implements GroupRepository, GroupCreationRepository {
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

  final _creationRequests = <String, String>{};
  @override
  Future<String> createGroupWithPosition(
      {required String name,
      required String churchName,
      required MembershipPosition position,
      String customPosition = '',
      required String requestId}) async {
    await Future<void>.delayed(delay);
    if (_creationRequests.containsKey(requestId)) {
      return _creationRequests[requestId]!;
    }
    final id = 'mock-created-${_creationRequests.length + 1}';
    final now = DateTime.now();
    _groups.add(WorshipGroup(
        id: id,
        name: name,
        churchName: churchName,
        accentColorValue: 0xff2f7a6b,
        members: [
          GroupMember(
              user: mockCurrentUser,
              role: UserRole.administrator,
              position: position,
              customPosition: customPosition,
              joinedAt: now,
              updatedAt: now)
        ]));
    _creationRequests[requestId] = id;
    _emit();
    return id;
  }

  @override
  Future<void> createGroup(String name, String churchName) async {
    await createGroupWithPosition(
        name: name,
        churchName: churchName,
        position: MembershipPosition.other,
        customPosition: 'Other',
        requestId: '${DateTime.now().microsecondsSinceEpoch}');
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
