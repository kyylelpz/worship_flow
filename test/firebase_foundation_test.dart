import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/app_user.dart';
import 'package:worship_flow/core/models/group_member.dart';
import 'package:worship_flow/core/models/membership_position.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/models/worship_group.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/features/auth/data/auth_repository.dart';
import 'package:worship_flow/features/auth/data/firebase_auth_repository.dart';
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/groups/data/group_repository.dart';
import 'package:worship_flow/features/groups/data/firestore_group_repository.dart';
import 'package:worship_flow/features/groups/providers/group_providers.dart';
import 'package:worship_flow/features/groups/screens/group_selection_screen.dart';
import 'package:worship_flow/features/profile/screens/profile_completion_screen.dart';
import 'package:worship_flow/features/setlists/screens/setlists_screen.dart';

const draftUser = AppUser(
    id: 'google-user',
    firstName: 'Taylor',
    lastName: 'Rivers',
    email: 'taylor@example.test',
    instrument: '',
    avatarInitials: 'TR',
    profileComplete: false);

class AccountFake
    implements
        AuthRepository,
        PersistentAuthRepository,
        AccountProfileRepository {
  AccountFake(this.current);
  AppUser? current;
  final changes = StreamController<AppUser?>.broadcast(sync: true);
  bool cancel = false, offline = false;
  @override
  Stream<AppUser?> watchUser() async* {
    yield current;
    yield* changes.stream;
  }

  void emit(AppUser? user) {
    current = user;
    changes.add(user);
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    if (cancel) throw const SignInCancelled();
    if (offline) throw const AccountException('Connection unavailable.');
    emit(draftUser);
    // An AuthResult is not group-role authority in Firebase mode.
    return const AuthResult(user: draftUser, role: UserRole.administrator);
  }

  @override
  Future<AppUser?> getCurrentUser() async => current;
  @override
  Future<void> signOut() async => emit(null);
  @override
  Future<AppUser> completeProfile(String first, String last) async {
    if (offline) throw const AccountException('Connection unavailable.');
    final user = current!
        .copyWith(firstName: first, lastName: last, profileComplete: true);
    emit(user);
    return user;
  }

  void dispose() => unawaited(changes.close());
}

class GroupsFake implements GroupRepository, GroupCreationRepository {
  GroupsFake(this.account);
  final AccountFake account;
  final groups = <WorshipGroup>[];
  final changes = StreamController<List<WorshipGroup>>.broadcast(sync: true);
  void notify() => changes.add(List.unmodifiable(groups));
  @override
  Stream<List<WorshipGroup>> watchGroups() async* {
    yield groups.toList();
    yield* changes.stream;
  }

  @override
  Stream<List<WorshipGroup>> watchGroupsForUser(String uid) =>
      watchGroups().map((list) =>
          list.where((g) => g.members.any((m) => m.user.id == uid)).toList());
  @override
  Future<WorshipGroup?> getGroup(String id) async =>
      groups.where((g) => g.id == id).firstOrNull;
  @override
  Future<String> createGroupWithPosition(
      {required String name,
      required String churchName,
      required MembershipPosition position,
      String customPosition = '',
      required String requestId}) async {
    final user = account.current!;
    if (!user.profileComplete) {
      throw const AccountException('Complete your profile.');
    }
    final id = 'created-${groups.length}';
    groups.add(WorshipGroup(
        id: id,
        name: name,
        churchName: churchName,
        accentColorValue: 0xff2f7a6b,
        members: [
          GroupMember(
              user: user,
              role: UserRole.administrator,
              position: position,
              customPosition: customPosition,
              joinedAt: DateTime(2026),
              updatedAt: DateTime(2026))
        ]));
    notify();
    return id;
  }

  @override
  Future<void> createGroup(String name, String churchName) =>
      throw UnimplementedError();
  @override
  Future<void> joinGroup(String code) => throw UnimplementedError();
  @override
  Future<void> updateMemberRole(
          {required String groupId,
          required String userId,
          required UserRole role}) =>
      throw UnimplementedError();
  void dispose() => unawaited(changes.close());
}

Future<(ProviderContainer, AccountFake, GroupsFake)> launch(WidgetTester tester,
    {AppUser? initial}) async {
  final auth = AccountFake(initial);
  final groups = GroupsFake(auth);
  final container = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(auth),
    groupRepositoryProvider.overrideWithValue(groups)
  ]);
  final router = container.read(routing.appRouterProvider);
  addTearDown(() {
    router.dispose();
    container.dispose();
    auth.dispose();
    groups.dispose();
  });
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
  return (container, auth, groups);
}

void main() {
  test('profile mapping keeps completion and invitation privacy explicit', () {
    final user = userFromProfile('uid', {
      'firstName': 'Avery',
      'lastName': 'Chen',
      'email': 'avery@example.test',
      'profileComplete': false
    });
    expect(user.profileComplete, isFalse);
    expect(user.avatarInitials, 'AC');
    expect(user.email, 'avery@example.test');
  });
  test(
      'membership role and position are independent and invalid roles fail closed',
      () {
    final data = {
      'uid': 'u',
      'firstName': 'A',
      'lastName': 'B',
      'role': 'worshipTrainee',
      'position': 'vocalist',
      'customPosition': '',
      'createdAt': Timestamp.fromDate(DateTime(2026)),
      'updatedAt': Timestamp.fromDate(DateTime(2026))
    };
    final member = memberFromFirestore(data);
    expect(member.role.canManageSongs, isFalse);
    expect(member.position, MembershipPosition.vocalist);
    expect(member.user.email, '');
    expect(member.uid, 'u');
    expect(member.createdAt, DateTime(2026));
    expect(() => memberFromFirestore(data, expectedUid: 'different'),
        throwsA(isA<AccountException>()));
    expect(member.copyWith(role: UserRole.administrator).position,
        MembershipPosition.vocalist);
    expect(member.copyWith(position: MembershipPosition.drums).role,
        UserRole.worshipTrainee);
    expect(() => memberFromFirestore({...data, 'role': 'superuser'}),
        throwsA(isA<AccountException>()));
    expect(
        member
            .copyWith(
                position: MembershipPosition.other,
                customPosition: 'Sound Engineer')
            .positionLabel,
        'Sound Engineer');
  });
  testWidgets(
      'persistent sign-in gates incomplete profiles; fields prefill and email stays protected',
      (tester) async {
    final (container, auth, _) = await launch(tester, initial: draftUser);
    expect(find.byType(ProfileCompletionScreen), findsOneWidget);
    expect(find.text('Taylor'), findsOneWidget);
    expect(find.text('Rivers'), findsOneWidget);
    final email = tester.widget<TextField>(find.descendant(
        of: find.widgetWithText(TextFormField, 'Email'),
        matching: find.byType(TextField)));
    expect(email.readOnly, isTrue);
    container.read(routing.appRouterProvider).go('/setlists');
    await tester.pumpAndSettle();
    expect(find.byType(ProfileCompletionScreen), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'First Name'), '');
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Required.'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'First Name'), 'Edited');
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupSelectionScreen), findsOneWidget);
    expect(auth.current!.firstName, 'Edited');
    expect(find.text('Create Group'), findsOneWidget);
    expect(find.textContaining('DEV'), findsNothing);
  });
  testWidgets(
      'cancellation stays on login without error and connectivity failure is retryable',
      (tester) async {
    final (container, auth, _) = await launch(tester);
    auth.cancel = true;
    await container.read(sessionProvider.notifier).signInWithGoogle();
    await tester.pumpAndSettle();
    expect(container.read(sessionProvider).errorMessage, isNull);
    expect(container.read(currentUserProvider), isNull);
    auth.cancel = false;
    auth.offline = true;
    await container.read(sessionProvider.notifier).signInWithGoogle();
    await tester.pumpAndSettle();
    expect(find.text('Retry account loading'), findsOneWidget);
    auth.offline = false;
    await container.read(sessionProvider.notifier).signInWithGoogle();
    await tester.pumpAndSettle();
    expect(find.byType(ProfileCompletionScreen), findsOneWidget);
  });
  testWidgets(
      'group creation assigns Administrator with independent position and supports selection/sign-out',
      (tester) async {
    final (container, auth, groups) = await launch(tester,
        initial: draftUser.copyWith(profileComplete: true));
    await tester.tap(find.text('Create Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create Group'));
    await tester.pumpAndSettle();
    expect(find.text('Required.'), findsWidgets);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Group name'), 'Worship Team');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Church name'), 'Community Church');
    await tester.tap(find.byType(DropdownButtonFormField<MembershipPosition>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drums').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create Group'));
    await tester.pumpAndSettle();
    expect(groups.groups.single.members.single.role, UserRole.administrator);
    expect(
        groups.groups.single.members.single.position, MembershipPosition.drums);
    await tester.tap(find.text('Worship Team'));
    await tester.pumpAndSettle();
    expect(find.byType(SetlistsScreen), findsOneWidget);
    expect(container.read(currentRoleProvider), UserRole.administrator);
    expect(
        () => container
            .read(sessionProvider.notifier)
            .setRoleForTesting(UserRole.administrator),
        throwsStateError);
    await container.read(sessionProvider.notifier).signOut();
    await tester.pumpAndSettle();
    expect(auth.current, isNull);
    expect(container.read(selectedGroupIdProvider), isNull);
  });
  testWidgets(
      'group role is authoritative and revocation clears selected group',
      (tester) async {
    final (container, auth, groups) = await launch(tester,
        initial: draftUser.copyWith(profileComplete: true));
    await groups.createGroupWithPosition(
        name: 'Team',
        churchName: 'Church',
        position: MembershipPosition.keyboard,
        requestId: 'request-0123456789');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team'));
    await tester.pumpAndSettle();
    final group = groups.groups.single;
    groups.groups[0] = WorshipGroup(
        id: group.id,
        name: group.name,
        churchName: group.churchName,
        accentColorValue: group.accentColorValue,
        members: [
          group.members.single.copyWith(role: UserRole.worshipTrainee)
        ]);
    groups.notify();
    await tester.pumpAndSettle();
    expect(container.read(currentRoleProvider), UserRole.worshipTrainee);
    groups.groups.clear();
    groups.notify();
    await tester.pumpAndSettle();
    expect(container.read(selectedGroupIdProvider), isNull);
    expect(find.byType(GroupSelectionScreen), findsOneWidget);
    expect(auth.current!.profileComplete, isTrue);
  });
  testWidgets('switching incomplete accounts resets profile prefills',
      (tester) async {
    final (_, auth, _) = await launch(tester, initial: draftUser);
    auth.emit(const AppUser(
        id: 'different',
        firstName: 'Other',
        lastName: 'Person',
        email: 'other@example.test',
        instrument: '',
        avatarInitials: 'OP',
        profileComplete: false));
    await tester.pumpAndSettle();
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Taylor'), findsNothing);
  });
  testWidgets('group loading errors provide Retry without losing the account',
      (tester) async {
    final (_, auth, groups) = await launch(tester,
        initial: draftUser.copyWith(profileComplete: true));
    groups.changes.addError(const AccountException('Connection unavailable.'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection unavailable.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Create Group'), findsOneWidget);
    expect(auth.current!.id, draftUser.id);
    expect(tester.takeException(), isNull);
  });
}
