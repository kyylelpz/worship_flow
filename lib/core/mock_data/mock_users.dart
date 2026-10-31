import '../models/app_user.dart';
import '../models/user_role.dart';

class MockUserRecord {
  const MockUserRecord({required this.user, required this.role});
  final AppUser user;
  final UserRole role;
}

const mockCurrentUser = AppUser(
  id: 'user-1',
  firstName: 'Jordan',
  lastName: 'Rivera',
  email: 'jordan.rivera@example.com',
  instrument: 'Acoustic Guitar',
  avatarInitials: 'JR',
);

const mockUserTwo = AppUser(
  id: 'user-2',
  firstName: 'Avery',
  lastName: 'Chen',
  email: 'avery.chen@example.com',
  instrument: 'Keys',
  avatarInitials: 'AC',
);

const mockUserThree = AppUser(
  id: 'user-3',
  firstName: 'Noah',
  lastName: 'Patel',
  email: 'noah.patel@example.com',
  instrument: 'Drums',
  avatarInitials: 'NP',
);
