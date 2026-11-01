import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/models/setlist.dart';
import 'package:worship_flow/features/setlists/screens/setlist_editor_screen.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/core/router/route_paths.dart';
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/groups/providers/group_providers.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/songs/providers/song_providers.dart';
import 'package:worship_flow/features/songs/providers/song_catalog_provider.dart';
import 'package:worship_flow/features/songs/screens/song_editor_screen.dart';
import 'package:worship_flow/features/songs/screens/song_library_screen.dart';
import 'package:worship_flow/features/songs/screens/arrangement_editor_screen.dart';
import 'song_repository_test.dart' as data;

Future<ProviderContainer> launch(WidgetTester tester,
    {String route = '/songs', UserRole role = UserRole.administrator}) async {
  final fixture = data.CatalogFixture();
  final container = ProviderContainer(overrides: [
    groupRepositoryProvider.overrideWithValue(fixture.groups),
    songCatalogProvider.overrideWithValue(fixture.catalog),
    setlistRepositoryProvider.overrideWithValue(fixture.setlists),
  ]);
  addTearDown(() {
    container.dispose();
    fixture.dispose();
  });
  final auth = container.read(sessionProvider.notifier);
  auth.updateProfile(mockCurrentUser);
  auth.setRoleForTesting(role);
  auth.selectGroup('group-1');
  final router = container.read(routing.appRouterProvider);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
  router.go(route);
  await tester.pumpAndSettle();
  return container;
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

void main() {
  testWidgets(
      'create, edit and delete song work through the forms with validation',
      (tester) async {
    final container = await launch(tester);
    await tester.tap(find.byTooltip('New Song'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Song'));
    await tester.pumpAndSettle();
    expect(find.text('Required.'), findsWidgets);
    await enter(tester, 'Title', 'Created in UI');
    await enter(tester, 'Artist', 'UI Artist');
    await tester.ensureVisible(find.text('Add Arrangement'));
    await tester.tap(find.text('Add Arrangement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, data.originalSource);
    await tester.tap(find.text('Use Source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Arrangement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Song'));
    await tester.pumpAndSettle();
    final created = container
        .read(songsListProvider)
        .singleWhere((s) => s.title == 'Created in UI');
    expect(created.primaryArrangement.chordProSource, data.originalSource);
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Created in UI');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Created in UI').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await enter(tester, 'Title', 'Renamed in UI');
    await tester.tap(find.text('Save Song'));
    await tester.pumpAndSettle();
    expect(container.read(songByIdProvider(created.id))!.primaryArrangement.id,
        created.primaryArrangement.id);
    expect(find.text('Renamed in UI'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete Song'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(songByIdProvider(created.id)), isNotNull);
    await tester.tap(find.byTooltip('Delete Song'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(container.read(songByIdProvider(created.id)), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'arrangement editor preserves references and basic source boundary returns exact text',
      (tester) async {
    final container = await launch(tester, route: '/songs/song-1/edit');
    final original =
        container.read(songByIdProvider('song-1'))!.primaryArrangement;
    await tester.ensureVisible(find.byTooltip('Manage Acoustic'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage Acoustic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(
        container
            .read(songByIdProvider('song-1'))!
            .arrangements
            .any((a) => a.name == 'Acoustic (Copy)'),
        isTrue);
    await tester.scrollUntilVisible(
        find.byTooltip('Manage Acoustic (Copy)'), 150,
        scrollable: find
            .descendant(
                of: find.byType(SongEditorScreen),
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('Acoustic (Copy)'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Manage Acoustic (Copy)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage Acoustic (Copy)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Acoustic (Copy)'), findsNothing);
    await tester.scrollUntilVisible(find.text('Full Band'), -150,
        scrollable: find
            .descendant(
                of: find.byType(SongEditorScreen),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Full Band'));
    await tester.pumpAndSettle();
    expect(find.byType(ArrangementEditorScreen), findsOneWidget);
    await enter(tester, 'Arrangement name', 'Updated Band');
    await enter(tester, 'BPM', '99');
    await tester.ensureVisible(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use Source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Arrangement'));
    await tester.pumpAndSettle();
    final saved =
        container.read(songByIdProvider('song-1'))!.primaryArrangement;
    expect(saved.id, original.id);
    expect(saved.name, 'Updated Band');
    expect(saved.bpm, 99);
    expect(saved.chordProSource, original.chordProSource);
    await tester.tap(find.byTooltip('Manage Updated Band'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('used in a published or draft setlist'),
        findsOneWidget);
    expect(container.read(songByIdProvider('song-1'))!.primaryArrangement.id,
        original.id);
  });

  testWidgets(
      'trainees cannot enter editor routes; revocation also leaves an open editor',
      (tester) async {
    final container = await launch(tester,
        route: '/songs/new', role: UserRole.worshipTrainee);
    expect(find.byType(SongEditorScreen), findsNothing);
    expect(find.byTooltip('New Song'), findsNothing);
    final router = container.read(routing.appRouterProvider);
    router.go('/songs/song-1/edit');
    await tester.pumpAndSettle();
    expect(find.byType(SongEditorScreen), findsNothing);
    container
        .read(sessionProvider.notifier)
        .setRoleForTesting(UserRole.administrator);
    await tester.pumpAndSettle();
    router.go('/songs/song-1/edit');
    await tester.pumpAndSettle();
    expect(find.byType(SongEditorScreen), findsOneWidget);
    container
        .read(sessionProvider.notifier)
        .setRoleForTesting(UserRole.worshipTrainee);
    await tester.pumpAndSettle();
    expect(find.byType(SongEditorScreen), findsNothing);
    expect(find.byType(SongLibraryScreen), findsOneWidget);
  });

  testWidgets(
      'new songs reach setlist selection and reactive metadata reaches rehearsal',
      (tester) async {
    final container = await launch(tester);
    final repo = container.read(songRepositoryProvider);
    final id = await tester
        .runAsync(() => repo.createSong('group-1', data.draftSong()));
    await tester.pumpAndSettle();
    final router = container.read(routing.appRouterProvider);
    router.go('/setlists/setlist-3/edit');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'New Song');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'New Song'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'New Song'));
    await tester.pump();
    await tester.tap(find.text('Add (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan · A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();
    final setlist = await tester.runAsync(() =>
        container.read(setlistRepositoryProvider).getSetlist('setlist-3'));
    expect(setlist!.draftItems!.last.songId, id);
    var song = container.read(songByIdProvider(id!))!;
    await tester.runAsync(() =>
        repo.updateSong('group-1', song.copyWith(title: 'Reactive title')));
    await tester.runAsync(() => repo.updateArrangement(
        'group-1',
        id,
        song.primaryArrangement.copyWith(
            name: 'Reactive arrangement',
            chordProSource: '{key: G}\n[G]Reactive source')));
    await tester.pumpAndSettle();
    router.go(RoutePaths.setlistRehearsalFor('setlist-3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open setlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reactive title'));
    await tester.pumpAndSettle();
    expect(find.byType(RehearsalScreen), findsOneWidget);
    expect(find.text('Reactive title'), findsOneWidget);
    expect(
        tester
            .widget<ChordChartView>(find.byType(ChordChartView))
            .chart
            .document
            .source,
        '{key: G}\n[G]Reactive source');
    song = container.read(songByIdProvider(id))!;
    await tester.runAsync(() => repo.updateSong(
        'group-1', song.copyWith(title: 'Live catalog change')));
    await tester.pumpAndSettle();
    expect(find.text('Live catalog change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'publishing stops when an unsaved selection was deleted from the catalog',
      (tester) async {
    final container = await launch(tester);
    final repo = container.read(songRepositoryProvider);
    final id = await tester
        .runAsync(() => repo.createSong('group-1', data.draftSong()));
    await tester.pumpAndSettle();
    container.read(routing.appRouterProvider).go('/setlists/setlist-3/edit');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'New Song');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'New Song'));
    await tester.pump();
    await tester.tap(find.text('Add (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan · A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => repo.deleteSong('group-1', id!));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Publish Setlist'), 150,
        scrollable: find
            .descendant(
                of: find.byType(SetlistEditorScreen),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Publish Setlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();
    final stored = await tester.runAsync(() =>
        container.read(setlistRepositoryProvider).getSetlist('setlist-3'));
    expect(stored!.status, SetlistStatus.draft);
    expect(stored.draftItems!.any((item) => item.songId == id), isFalse);
    expect(find.textContaining('Could not save:'), findsOneWidget);
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
  });

  testWidgets(
      'membership revocation closes a protected editor even with an admin session',
      (tester) async {
    final container = await launch(tester, route: '/songs/song-1/edit');
    expect(find.byType(SongEditorScreen), findsOneWidget);
    await tester.runAsync(() => container
        .read(groupRepositoryProvider)
        .updateMemberRole(
            groupId: 'group-1',
            userId: 'user-1',
            role: UserRole.worshipTrainee));
    await tester.pumpAndSettle();
    expect(find.byType(SongEditorScreen), findsNothing);
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(find.byTooltip('New Song'), findsNothing);
  });

  testWidgets(
      'search/category filtering remain functional and switching groups hides created songs',
      (tester) async {
    final container = await launch(tester);
    final repo = container.read(songRepositoryProvider);
    await tester.runAsync(() => repo.createSong(
        'group-1',
        data
            .draftSong()
            .copyWith(title: 'Unique catalog entry', category: 'Custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unique catalog');
    await tester.pumpAndSettle();
    expect(find.text('Unique catalog entry'), findsOneWidget);
    expect(find.text('Anchor of the Morning'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(ChoiceChip, 'Custom');
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Anchor of the Morning'), findsNothing);
    container.read(sessionProvider.notifier).selectGroup('group-2');
    await tester.pumpAndSettle();
    expect(find.text('Unique catalog entry'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Anchor of the Morning'), findsOneWidget);
  });
}
