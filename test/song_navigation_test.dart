import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/core/router/route_paths.dart';
import 'package:worship_flow/features/songs/providers/song_providers.dart';
import 'package:worship_flow/features/songs/screens/song_editor_screen.dart';
import 'package:worship_flow/features/songs/screens/song_library_screen.dart';
import 'package:worship_flow/features/setlists/screens/setlists_screen.dart';
import 'song_management_test.dart' as management;

Future<void> addFromLibrary(WidgetTester tester) async {
  await tester.tap(find.byTooltip('New Song'));
  await tester.pumpAndSettle();
}

Future<void> back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back').first);
  await tester.pumpAndSettle();
}

Future<void> saveNewSong(WidgetTester tester) async {
  await addFromLibrary(tester);
  await management.enter(tester, 'Title', 'Saved navigation test');
  await management.enter(tester, 'Artist', 'Artist');
  await tester.ensureVisible(find.text('Add Arrangement'));
  await tester.tap(find.text('Add Arrangement'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
  await management.enter(tester, 'Canonical ChordPro', '{key: G}\n[G]A song');
  await tester.tap(find.text('Use Source'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save Arrangement'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save Song'));
  await tester.pumpAndSettle();
}

void main() {
  for (final systemBack in [false, true]) {
    testWidgets(
        'creation preserves Setlists → Library history for ${systemBack ? 'Android' : 'toolbar'} Back',
        (tester) async {
      final container =
          await management.launch(tester, route: RoutePaths.setlists);
      await tester.tap(find.byTooltip('Song Library'));
      await tester.pumpAndSettle();
      final originalLibrary = tester.element(find.byType(SongLibraryScreen));
      await tester.enterText(find.byType(TextField), 'Anchor');
      await tester.pumpAndSettle();
      await saveNewSong(tester);
      expect(tester.element(find.byType(SongLibraryScreen)),
          same(originalLibrary));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Anchor');
      expect(container.read(routing.appRouterProvider).canPop(), isTrue);
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      if (systemBack) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      } else {
        await back(tester);
      }
      expect(find.byType(SetlistsScreen), findsOneWidget);
      expect(find.byType(SongLibraryScreen), findsNothing);
    });

    testWidgets(
        'direct Song Library returns to Setlists with ${systemBack ? 'Android' : 'toolbar'} Back',
        (tester) async {
      final container = await management.launch(tester);
      expect(container.read(routing.appRouterProvider).canPop(), isFalse);
      expect(find.byTooltip('Back'), findsOneWidget);
      if (systemBack) {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      } else {
        await back(tester);
      }
      expect(find.byType(SetlistsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('creation from a direct library retains its Setlists fallback',
      (tester) async {
    final container = await management.launch(tester);
    await saveNewSong(tester);
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(container.read(routing.appRouterProvider).canPop(), isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SetlistsScreen), findsOneWidget);
  });

  testWidgets('Add Song preserves library history and both clean back paths',
      (tester) async {
    final container = await management.launch(tester);
    await tester.enterText(find.byType(TextField), 'Anchor');
    await tester.pumpAndSettle();
    await addFromLibrary(tester);
    expect(container.read(routing.appRouterProvider).canPop(), isTrue);
    expect(find.byTooltip('Back'), findsOneWidget);
    await back(tester);
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Anchor');
    await addFromLibrary(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(find.byType(SongEditorScreen), findsNothing);
  });

  testWidgets(
      'toolbar and Android Back confirm unsaved changes and discard only once',
      (tester) async {
    final container = await management.launch(tester);
    await addFromLibrary(tester);
    await management.enter(tester, 'Title', 'Unfinished song');
    await tester.tap(find.text('Save Song'));
    await tester.pumpAndSettle();
    expect(find.text('Required.'), findsWidgets);
    await back(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unfinished song'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
    expect(
        container
            .read(songsListProvider)
            .any((s) => s.title == 'Unfinished song'),
        isFalse);
  });

  testWidgets(
      'Edit Song has Back and reverting metadata removes the discard prompt',
      (tester) async {
    final container =
        await management.launch(tester, route: '/songs/song-1/edit');
    final original = container.read(songByIdProvider('song-1'))!.title;
    expect(find.byTooltip('Back'), findsOneWidget);
    await management.enter(tester, 'Title', 'Temporary edit');
    await back(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    await management.enter(tester, 'Title', original);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SongEditorScreen), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);
    expect(container.read(songByIdProvider('song-1'))!.title, original);
  });

  testWidgets('favorite-only edits trigger confirmation', (tester) async {
    await management.launch(tester);
    await addFromLibrary(tester);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibraryScreen), findsOneWidget);
  });

  testWidgets(
      'new-song arrangement drafts trigger confirmation even with untouched metadata',
      (tester) async {
    await management.launch(tester);
    await addFromLibrary(tester);
    await tester.ensureVisible(find.text('Add Arrangement'));
    await tester.tap(find.text('Add Arrangement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await management.enter(tester, 'Canonical ChordPro', '{key: G}\n[G]Draft');
    await tester.tap(find.text('Use Source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Arrangement'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibraryScreen), findsOneWidget);
  });

  testWidgets(
      'already-saved arrangement actions do not cause a false discard prompt',
      (tester) async {
    await management.launch(tester, route: '/songs/song-1/edit');
    await tester.ensureVisible(find.byTooltip('Manage Acoustic'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Manage Acoustic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.byType(SongEditorScreen), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);
  });

  for (final (systemBack, dirty) in [
    (false, false),
    (true, false),
    (true, true)
  ]) {
    testWidgets(
        'direct standalone route falls back to library via ${systemBack ? 'Android' : 'toolbar'} Back (${dirty ? 'dirty' : 'clean'})',
        (tester) async {
      final container = await management.launch(tester);
      final router = GoRouter(initialLocation: '/add', routes: [
        GoRoute(
            path: '/add', builder: (_, __) => const SongEditorScreen.create()),
        GoRoute(
            path: RoutePaths.songs,
            builder: (_, __) => const SongLibraryScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);
      if (systemBack) {
        if (dirty) {
          await management.enter(tester, 'Title', 'Unsaved direct link');
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        if (dirty) {
          expect(find.text('Discard changes?'), findsOneWidget);
          await tester.tap(find.text('Discard'));
          await tester.pumpAndSettle();
        }
      } else {
        await back(tester);
      }
      expect(router.routeInformationProvider.value.uri.path, RoutePaths.songs);
      expect(find.byType(SongLibraryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
