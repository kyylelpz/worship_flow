import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/firebase/firebase_providers.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/models/song.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/groups/providers/group_providers.dart';
import 'package:worship_flow/features/songs/data/mock_song_repository.dart';
import 'package:worship_flow/features/songs/data/song_repository.dart';
import 'package:worship_flow/features/songs/providers/song_catalog_provider.dart';
import 'package:worship_flow/features/songs/providers/song_providers.dart';
import 'package:worship_flow/features/songs/screens/song_library_screen.dart';
import 'package:worship_flow/features/songs/screens/song_details_screen.dart';
import 'package:worship_flow/features/songs/screens/song_editor_screen.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/setlists/screens/setlists_screen.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'firebase_foundation_test.dart' as accounts;
import 'song_repository_test.dart' as data;
import 'song_management_test.dart' as forms;

class ReadFailureSongs extends MockSongRepository {
  ReadFailureSongs(data.CatalogFixture fixture, SongSession Function() session)
      : super(
            catalog: fixture.catalog,
            groups: fixture.groups,
            session: session,
            isReferenced: (g, s, a) =>
                fixture.setlists.referencesSong(g, s, arrangementId: a));
  bool denied = false;
  int subscriptions = 0;
  @override
  Stream<List<Song>> watchSongs(String groupId) {
    subscriptions++;
    return denied
        ? Stream.error(FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Previous read was denied.'))
        : super.watchSongs(groupId);
  }
}

Future<(ProviderContainer, ReadFailureSongs)> launch(
    WidgetTester t, UserRole role,
    {bool failedRead = false}) async {
  final fixture = data.CatalogFixture();
  await t.runAsync(() => fixture.groups.updateMemberRole(
      groupId: 'group-1', userId: mockCurrentUser.id, role: role));
  final account = accounts.AccountFake(mockCurrentUser);
  late ReadFailureSongs repository;
  final c = ProviderContainer(overrides: [
    useMockBackendProvider
        .overrideWithValue(false), // Exercise production membership authority.
    authRepositoryProvider.overrideWithValue(account),
    groupRepositoryProvider.overrideWithValue(fixture.groups),
    songCatalogProvider.overrideWithValue(fixture.catalog),
    setlistRepositoryProvider.overrideWithValue(fixture.setlists),
    songRepositoryProvider.overrideWith((ref) => repository = ReadFailureSongs(
        fixture,
        () => SongSession(
            userId: ref.read(currentUserProvider)?.id,
            groupId: ref.read(selectedGroupIdProvider),
            role: ref.read(currentRoleProvider)))
      ..denied = failedRead),
  ]);
  final router = c.read(routing.appRouterProvider);
  addTearDown(() =>
      {router.dispose(), c.dispose(), fixture.dispose(), account.dispose()});
  await t.pumpWidget(UncontrolledProviderScope(
      container: c, child: MaterialApp.router(routerConfig: router)));
  await t.pumpAndSettle();
  c.read(sessionProvider.notifier).selectGroup('group-1');
  await t.pumpAndSettle();
  router.go('/songs');
  await t.pumpAndSettle();
  return (c, repository);
}

void main() {
  for (final role in UserRole.values) {
    testWidgets(
        '${role.name}: library/details/setlists/rehearsal read access and scoped mutation controls',
        (t) async {
      final (c, _) = await launch(t, role);
      final router = c.read(routing.appRouterProvider);
      expect(c.read(sessionProvider).role,
          UserRole.worshipTrainee); // Global role is deliberately unrelated.
      expect(c.read(currentRoleProvider), role);
      expect(find.byType(SongLibraryScreen), findsOneWidget);
      expect(c.read(songsListProvider), isNotEmpty);
      expect(find.byTooltip('New Song'),
          role.canManageSongs ? findsOneWidget : findsNothing);
      final song = c.read(songsListProvider).first;
      router.go('/songs/${song.id}');
      await t.pumpAndSettle();
      expect(find.byType(SongDetailsScreen), findsOneWidget);
      expect(find.text('Arrangements'), findsOneWidget);
      expect(find.byTooltip('Edit'),
          role.canManageSongs ? findsOneWidget : findsNothing);
      expect(find.byTooltip('Delete Song'),
          role.canManageSongs ? findsOneWidget : findsNothing);
      router.go('/setlists');
      await t.pumpAndSettle();
      expect(find.byType(SetlistsScreen), findsOneWidget);
      expect(find.text('New Setlist'),
          role.canManageSetlists ? findsOneWidget : findsNothing);
      router.go('/setlists/setlist-1/rehearse');
      await t.pumpAndSettle();
      expect(find.byType(RehearsalScreen), findsOneWidget);
      await t.tap(find.byTooltip('Open setlist'));
      await t.pumpAndSettle();
      expect(find.text('Edit Setlist'),
          role.canManageSetlists ? findsOneWidget : findsNothing);
      router.go('/songs/new');
      await t.pumpAndSettle();
      expect(find.byType(SongEditorScreen),
          role.canManageSongs ? findsOneWidget : findsNothing);
      if (role.canManageSetlists) {
        router.go('/setlists/setlist-1/edit');
        await t.pumpAndSettle();
        expect(find.text('Publish Setlist'), findsOneWidget);
        expect(find.byTooltip('Actions'), findsOneWidget);
      }
      if (!role.canManageSongs) {
        expect(find.byType(SongLibraryScreen), findsOneWidget);
        router.go('/songs/${song.id}/edit');
        await t.pumpAndSettle();
        expect(find.byType(SongLibraryScreen), findsOneWidget);
        router.go('/setlists/setlist-1/edit');
        await t.pumpAndSettle();
        expect(find.byType(SetlistsScreen), findsOneWidget);
        expect(find.text('Publish Setlist'), findsNothing);
      }
    });
  }
  testWidgets(
      'Retry replaces a terminal permission-denied library subscription',
      (t) async {
    final (c, repository) =
        await launch(t, UserRole.worshipLeader, failedRead: true);
    expect(c.read(groupSongsProvider).hasError, isTrue);
    final previous = repository.subscriptions;
    repository.denied = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(repository.subscriptions, previous + 1);
    expect(c.read(songsListProvider), isNotEmpty);
    expect(find.text('Retry'), findsNothing);
  });
  testWidgets(
      'leader can create after a failed listener and Save recovers the library',
      (t) async {
    final (c, repository) =
        await launch(t, UserRole.worshipLeader, failedRead: true);
    final previous = repository.subscriptions;
    await t.tap(find.byTooltip('New Song'));
    await t.pumpAndSettle();
    await forms.enter(t, 'Title', 'Recovered Library');
    await forms.enter(t, 'Artist', 'Artist');
    await t.ensureVisible(find.text('Add Arrangement'));
    await t.tap(find.text('Add Arrangement'));
    await t.pumpAndSettle();
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, data.originalSource);
    await t.tap(find.byTooltip('Save'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save Arrangement'));
    await t.pumpAndSettle();
    repository.denied = false;
    await t.tap(find.text('Save Song'));
    await t.pumpAndSettle();
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(repository.subscriptions, greaterThan(previous));
    expect(c.read(groupSongsProvider).hasError, isFalse);
    expect(c.read(songsListProvider).any((s) => s.title == 'Recovered Library'),
        isTrue);
    await t.enterText(find.byType(TextField), 'Recovered Library');
    await t.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && w.data == 'Recovered Library'),
        findsOneWidget);
  });
}
