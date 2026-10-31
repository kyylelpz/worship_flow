import '../models/app_user.dart';
import '../models/group_member.dart';
import '../models/user_role.dart';
import '../models/worship_group.dart';
import 'mock_users.dart';

final _now = DateTime.now();
DateTime _daysAgo(int d) => _now.subtract(Duration(days: d));

final mockGroups = <WorshipGroup>[
  WorshipGroup(
    id: 'group-1',
    name: 'Grace Community Worship',
    churchName: 'Grace Community Church',
    accentColorValue: 0xFF2563EB,
    members: [
      GroupMember(
        user: mockCurrentUser,
        role: UserRole.administrator,
        joinedAt: _daysAgo(420),
      ),
      GroupMember(
        user: mockUserTwo,
        role: UserRole.worshipLeader,
        joinedAt: _daysAgo(300),
      ),
      GroupMember(
        user: mockUserThree,
        role: UserRole.worshipTrainee,
        joinedAt: _daysAgo(90),
      ),
    ],
  ),
  WorshipGroup(
    id: 'group-2',
    name: 'Riverside Youth Band',
    churchName: 'Riverside Chapel',
    accentColorValue: 0xFF16A34A,
    members: [
      GroupMember(
        user: mockCurrentUser,
        role: UserRole.worshipLeader,
        joinedAt: _daysAgo(180),
      ),
      GroupMember(
        user: mockUserTwo,
        role: UserRole.administrator,
        joinedAt: _daysAgo(400),
      ),
    ],
  ),
];

// Convenience for lookups by id.
AppUser userById(String id) {
  for (final g in mockGroups) {
    for (final m in g.members) {
      if (m.user.id == id) return m.user;
    }
  }
  throw StateError('Unknown user id: $id');
}