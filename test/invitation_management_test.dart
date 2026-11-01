import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/membership_position.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/models/worship_group.dart';
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/groups/data/invitation_repository.dart';
import 'package:worship_flow/features/groups/providers/group_providers.dart';
import 'package:worship_flow/features/groups/providers/invitation_providers.dart';
import 'package:worship_flow/features/groups/screens/group_members_screen.dart';
import 'package:worship_flow/features/profile/screens/profile_screen.dart';
import 'package:worship_flow/features/profile/widgets/invitation_panel.dart';
import 'firebase_foundation_test.dart' as foundation;

const request = GroupInvitation(
    groupId: 'invited-group',
    groupName: 'Sunday Team',
    recipientUid: 'google-user',
    inviterUid: 'admin',
    role: UserRole.worshipLeader,
    position: MembershipPosition.other,
    customPosition: 'Sound Engineer');

class InvitationsFake implements InvitationRepository {
  InvitationsFake(this.account);
  final foundation.AccountFake account;
  final changes = StreamController<List<GroupInvitation>>.broadcast(sync: true);
  List<GroupInvitation> pending = [request];
  List<MembershipNotification> notices = [];
  final responses = <bool>[];
  int sent = 0, updated = 0, removed = 0;
  MembershipPosition? savedPosition;
  UserRole? savedRole;
  @override
  Stream<List<GroupInvitation>> watchPending() async* {
    yield pending;
    yield* changes.stream;
  }

  @override
  Stream<List<MembershipNotification>> watchNotifications() =>
      Stream.value(notices);
  @override
  Future<void> setAllowInvitations(bool allow) async =>
      account.emit(account.current!.copyWith(allowInvitations: allow));
  @override
  Future<void> invite(
      {required String groupId,
      required String email,
      required UserRole role,
      required MembershipPosition position,
      String customPosition = ''}) async {
    sent++;
    savedPosition = position;
    savedRole = role;
  }

  @override
  Future<void> respond(GroupInvitation i, {required bool accept}) async {
    responses.add(accept);
    pending = [];
    changes.add(pending);
  }

  @override
  Future<void> markRead(String id) async {}
  @override
  Future<void> updateMember(
      {required String groupId,
      required String uid,
      required UserRole role,
      required MembershipPosition position,
      String customPosition = ''}) async {
    updated++;
    savedPosition = position;
    savedRole = role;
  }

  @override
  Future<void> removeMember(
      {required String groupId, required String uid}) async {
    removed++;
  }
}

Future<(ProviderContainer, InvitationsFake, foundation.GroupsFake)> launch(
    WidgetTester t, Widget screen,
    {UserRole role = UserRole.administrator, bool notify = false}) async {
  final account = foundation.AccountFake(
      foundation.draftUser.copyWith(profileComplete: true));
  final groups = foundation.GroupsFake(account);
  await groups.createGroupWithPosition(
      name: 'Team',
      churchName: 'Church',
      position: MembershipPosition.keyboard,
      requestId: 'req-0123456789');
  final g = groups.groups.single;
  groups.groups[0] = WorshipGroup(
      id: g.id,
      name: g.name,
      churchName: g.churchName,
      accentColorValue: g.accentColorValue,
      members: [g.members.single.copyWith(role: role)]);
  final invitations = InvitationsFake(account);
  if (notify) {
    invitations.notices = [const MembershipNotification('notice', 'Team')];
  }
  final c = ProviderContainer(overrides: [
    authRepositoryProvider.overrideWithValue(account),
    groupRepositoryProvider.overrideWithValue(groups),
    invitationRepositoryProvider.overrideWithValue(invitations)
  ]);
  addTearDown(() {
    c.dispose();
    account.dispose();
    groups.dispose();
    unawaited(invitations.changes.close());
  });
  await t.pumpWidget(UncontrolledProviderScope(
      container: c, child: MaterialApp(home: screen)));
  await t.pumpAndSettle();
  return (c, invitations, groups);
}

void main() {
  test(
      'email validation accepts normalized addresses and rejects malformed/path input',
      () {
    expect(validateInvitationEmail('  Person@Gmail.com  '), isNull);
    for (final e in ['', 'a', 'a@', 'a/b@gmail.com', 'two names@gmail.com']) {
      expect(validateInvitationEmail(e), isNotNull);
    }
  });
  testWidgets(
      'Profile is reachable without groups and production Members route is preserved',
      (t) async {
    final (container, _, groups) = await foundation.launch(t,
        initial: foundation.draftUser.copyWith(profileComplete: true));
    final router = container.read(routing.appRouterProvider);
    unawaited(router.push<void>('/profile'));
    await t.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();
    await groups.createGroupWithPosition(
        name: 'Team',
        churchName: 'Church',
        position: MembershipPosition.keyboard,
        requestId: 'routing-0123456789');
    await t.pumpAndSettle();
    await t.tap(find.text('Team'));
    await t.pumpAndSettle();
    unawaited(router.push<void>('/groups/created-0/members'));
    await t.pumpAndSettle();
    expect(find.byType(GroupMembersScreen), findsOneWidget);
    expect(find.text('Team — Members'), findsOneWidget);
  });
  testWidgets(
      'Profile privacy is enabled by default, persists changes and keeps pending invitations visible',
      (t) async {
    final (c, repo, _) = await launch(t, const ProfileScreen());
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await t.tap(find.text('Allow Invitations'));
    await t.pumpAndSettle();
    expect(c.read(currentUserProvider)!.allowInvitations, isFalse);
    expect(find.text('Sunday Team'), findsOneWidget);
    expect(repo.responses, isEmpty);
  });
  testWidgets(
      'accept/decline require confirmation; cancel does not mutate and request clears after success',
      (t) async {
    final (_, repo, _) = await launch(t,
        const Scaffold(body: SingleChildScrollView(child: InvitationPanel())));
    expect(find.text('Worship Leader · Sound Engineer'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.responses, isEmpty);
    await t.tap(find.text('Decline'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Decline'));
    await t.pumpAndSettle();
    expect(repo.responses, [false]);
    expect(find.text('Sunday Team'), findsNothing);
  });
  testWidgets(
      'accept action and inviter notification render on narrow screens with scaling',
      (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final (_, repo, _) = await launch(
        t,
        const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Scaffold(
                body: SingleChildScrollView(child: InvitationPanel()))),
        notify: true);
    expect(find.textContaining('Invitation accepted'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Accept').last);
    await t.pumpAndSettle();
    expect(repo.responses, [true]);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'admin opens Invite Member; validates email/custom position and submits selected role',
      (t) async {
    final (_, repo, _) =
        await launch(t, const GroupMembersScreen(groupId: 'created-0'));
    await t.tap(find.text('Invite Member'));
    await t.pumpAndSettle();
    await t.tap(find.text('Send Invitation'));
    await t.pumpAndSettle();
    expect(repo.sent, 0);
    expect(find.text('Enter a valid Google email address.'), findsOneWidget);
    await t.enterText(
        find.widgetWithText(TextFormField, 'Google email'), 'person@gmail.com');
    await t.tap(find.byType(DropdownButtonFormField<UserRole>));
    await t.pumpAndSettle();
    await t.tap(find.text('Worship Leader').last);
    await t.pumpAndSettle();
    await t.tap(find.byType(DropdownButtonFormField<MembershipPosition>));
    await t.pumpAndSettle();
    await t.tap(find.text('Other').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Send Invitation'));
    await t.pumpAndSettle();
    expect(repo.sent, 0);
    await t.enterText(
        find.widgetWithText(TextFormField, 'Custom position'), 'Audio');
    await t.tap(find.text('Send Invitation'));
    await t.pumpAndSettle();
    expect(repo.sent, 1);
    expect(repo.savedRole, UserRole.worshipLeader);
    expect(repo.savedPosition, MembershipPosition.other);
    expect(find.textContaining('Invitation sent.'), findsOneWidget);
  });
  testWidgets(
      'non-admin has read-only member list and cannot use direct management page',
      (t) async {
    final (_, repo, _) = await launch(
        t, const GroupMembersScreen(groupId: 'created-0'),
        role: UserRole.worshipTrainee);
    expect(find.text('Invite Member'), findsNothing);
    expect(find.text('Read-only'), findsOneWidget);
    expect(repo.sent, 0);
    await t.pumpWidget(const SizedBox.shrink());
    await launch(t, const MemberEditorScreen(groupId: 'created-0'),
        role: UserRole.worshipLeader);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(find.text('Send Invitation'), findsNothing);
  });
  testWidgets(
      'role revocation disables open editor and role/position edit remains separate',
      (t) async {
    final (_, repo, groups) =
        await launch(t, const GroupMembersScreen(groupId: 'created-0'));
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Edit role and position'));
    await t.pumpAndSettle();
    expect(find.text('Your own role cannot be changed here.'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<MembershipPosition>));
    await t.pumpAndSettle();
    await t.tap(find.text('Drums').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Save Member'));
    await t.pumpAndSettle();
    expect(repo.updated, 1);
    expect(repo.savedPosition, MembershipPosition.drums);
    expect(repo.savedRole, UserRole.administrator);
    await t.tap(find.text('Invite Member'));
    await t.pumpAndSettle();
    final g = groups.groups.single;
    groups.groups[0] = WorshipGroup(
        id: g.id,
        name: g.name,
        churchName: g.churchName,
        accentColorValue: g.accentColorValue,
        members: [g.members.single.copyWith(role: UserRole.worshipTrainee)]);
    groups.notify();
    await t.pumpAndSettle();
    expect(find.text('Administrator access is required.'), findsOneWidget);
  });
  testWidgets('member removal asks for confirmation before repository mutation',
      (t) async {
    final (_, repo, _) =
        await launch(t, const GroupMembersScreen(groupId: 'created-0'));
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove member'));
    await t.pumpAndSettle();
    expect(repo.removed, 0);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.removed, 0);
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove member'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Remove'));
    await t.pumpAndSettle();
    expect(repo.removed, 1);
  });
}
