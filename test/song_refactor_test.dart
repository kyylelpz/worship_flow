import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/core/models/setlist_item.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/models/vocalist_key.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/models/chart_document.dart';
import 'package:worship_flow/features/charts/providers/chart_providers.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/setlists/screens/setlist_editor_screen.dart';
import 'package:worship_flow/features/songs/providers/song_providers.dart';
import 'package:worship_flow/features/songs/screens/song_editor_screen.dart';
import 'package:worship_flow/features/songs/screens/song_details_screen.dart';
import 'package:worship_flow/features/songs/data/song_validation.dart';
import 'song_management_test.dart' as ui;

const engine = ChartTransformer();
List<String> labels(DisplayChart chart) => chart.sections
    .expand((s) => s.lines)
    .expand((l) => l.chords)
    .map((c) => c.text)
    .toList();

DisplayChart prepare(String source,
    {String key = 'E',
    int offset = 0,
    bool nashville = false,
    String? sourceKey}) {
  final song = mockSongs.first;
  return engine.prepare(
      song: song,
      arrangement: song.primaryArrangement.copyWith(chordProSource: source),
      item: SetlistItem(
          songId: song.id,
          arrangementId: song.primaryArrangement.id,
          performanceKey: key),
      personalSemitones: offset,
      sourceKey: sourceKey,
      settings: ChartSettings(useNashville: nashville));
}

void main() {
  test('keyless numbers resolve in item key and personal offset exactly once',
          () {
        const source = '[1]a[5m7/1]b[b7]c';
        final chart = prepare(source);
        expect(labels(chart), ['E', 'Bm7/E', 'D']);
        expect(chart.document.warnings, isEmpty);
        expect(chart.document.source, source);
        expect(labels(prepare(source, offset: 2)), ['F#', 'C#m7/F#', 'E']);
        expect(labels(prepare(source, offset: 2, nashville: true)),
            ['1', '5m7/1', 'b7']);
        expect(labels(prepare('{key: C}\n$source')), ['E', 'Bm7/E', 'D']);
        expect(labels(prepare(source, key: 'Am')), ['A', 'Em7/A', 'Gb']);
      });

  test('keyless explicit grids and arrangement meter fallback work', () {
    final chart = prepare(
        '{start_of_grid: Intro}\n| 1 - - - | 5/1 - - - |\n{end_of_grid}');
    expect(chart.document.warnings, isEmpty);
    expect(chart.grids.single.original.isValid, isTrue);
    expect(chart.grids.single.measures[1].first.text, 'B/E');
    final mixed = prepare('{key: C}\n{section: Verse}\n[1]word\n'
        '{start_of_grid: Verse}\n| C - - - |\n{end_of_grid}');
    expect(mixed.document.warnings, isEmpty);
    expect(mixed.grids.single.measures.single.first.text, 'E');
  });

  test('unknown letter source is warned and not silently transposed', () {
    final chart = prepare('[C]a[1]b[G/B]c');
    expect(labels(chart), ['C', 'E', 'G/B']);
    expect(chart.document.warnings.single, contains('no known source key'));
    expect(
        labels(prepare('[C]a[1]b[G/B]c', sourceKey: 'C')), ['E', 'E', 'B/D#']);
    expect(labels(prepare('{key: C}\n[C]a[1]b[G/B]c')), ['E', 'E', 'B/D#']);
  });

  test('preview requires an explicit key or song vocal preset', () {
    final song = mockSongs.first.copyWith(vocalistKeys: []);
    final arrangement =
    song.primaryArrangement.copyWith(chordProSource: '[1]word');
    expect(
            () =>
            engine.prepare(
                song: song,
                arrangement: arrangement,
                settings: const ChartSettings()),
        throwsArgumentError);
    expect(
        labels(engine.prepare(
            song: song,
            arrangement: arrangement,
            previewKey: 'Bb',
            settings: const ChartSettings())),
        ['Bb']);
  });

  test('fixture presets merge at song level; item copies retain leader/key',
          () {
        expect(
            mockSongs.first.vocalistKeys.map((v) => '${v.vocalistName}:${v
                .key}'),
            ['Jordan:G', 'Avery:A']);
        const item = SetlistItem(
            songId: 's',
            arrangementId: 'a',
            performanceKey: 'E',
            vocalistName: 'Jordan');
        expect(item
            .copyWith(arrangementId: 'b')
            .vocalistName, 'Jordan');
        expect(item
            .copyWith(arrangementId: 'b')
            .performanceKey, 'E');
        expect(item
            .copyWith(clearVocalist: true)
            .vocalistName, isNull);
        expect(SongValidation.referenceLink(''), isNull);
        expect(
            SongValidation.referenceLink('https://example.com/reference'),
            isNull);
        expect(SongValidation.referenceLink('ftp://example.com'), isNotNull);
      });

  testWidgets(
      'category, song presets, source boundary and reference link persist',
          (tester) async {
        final container = await ui.launch(tester, route: '/songs/song-1/edit');
        expect(find.widgetWithText(TextFormField, 'Default key'), findsNothing);
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find
            .text('Other')
            .last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save Song'));
        await tester.pumpAndSettle();
        await ui.enter(tester, 'Custom category', 'Advent');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Add Vocalist Preset'), 200,
            scrollable: find
                .descendant(
                of: find.byType(SongEditorScreen),
                matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Add Vocalist Preset'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Vocalist Preset'));
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find
            .widgetWithText(TextFormField, 'Vocalist')
            .last);
        await tester.enterText(
            find
                .widgetWithText(TextFormField, 'Vocalist')
                .last, 'Guest');
        await tester.enterText(
            find
                .widgetWithText(TextFormField, 'Preferred key')
                .last, 'Eb');
        await tester.tap(find.text('Save Song'));
        await tester.pumpAndSettle();
        final song = container.read(songByIdProvider('song-1'))!;
        expect(song.category, 'Advent');
        expect(song.vocalistKeys.length, 3);
        expect(song.vocalistKeys.last.vocalistName, 'Guest');
        container.read(routing.appRouterProvider).go('/songs/song-1/edit');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Full Band'));
        await tester.tap(find.text('Full Band'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextFormField, 'Performance key'),
            findsNothing);
        expect(find.widgetWithText(TextFormField, 'Vocalist'), findsNothing);
        final field = tester.widget<TextField>(find.descendant(
            of: find.widgetWithText(TextFormField, 'ChordPro source'),
            matching: find.byType(TextField)));
        expect(field.readOnly, isTrue);
        await ui.enter(
            tester, 'Reference link (optional)', 'https://example.com/song');
        await tester.tap(find.text('Save Arrangement'));
        await tester.pumpAndSettle();
        expect(
            container
                .read(songByIdProvider('song-1'))!
                .primaryArrangement
                .referenceLink,
            'https://example.com/song');
        expect(
            container
                .read(songByIdProvider('song-1'))!
                .primaryArrangement
                .chordProSource,
            song.primaryArrangement.chordProSource);
      });

  testWidgets('Song Details is read only with no actions',
          (tester) async {
        final container = await ui.launch(tester, route: '/songs/song-1');

        expect(find.byType(SongDetailsScreen), findsOneWidget);

        // No manage / edit / favorite controls on the details screen.
        expect(find.byTooltip('Manage Full Band'), findsNothing);
        expect(find.byTooltip('Remove favorite'), findsNothing);
        expect(find.byTooltip('Add favorite'), findsNothing);
        expect(find.byTooltip('Edit Song'), findsNothing);

        // Favorite state on the model is untouched by visiting the screen.
        final before = container.read(songByIdProvider('song-1'))!.isFavorite;
        await tester.pumpAndSettle();
        final after = container.read(songByIdProvider('song-1'))!.isFavorite;
        expect(after, before);
      });

  testWidgets(
      'nested Song Editor refreshes config without replacing unsaved setlist',
          (tester) async {
        final container =
        await ui.launch(tester, route: '/setlists/setlist-1/edit');
        await tester.enterText(
            find.widgetWithText(TextField, 'Setlist name'), 'Unsaved service');
        await tester.tap(find.text('1. Anchor of the Morning'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Avery · A'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Edit Song'));
        await tester.tap(find.text('Edit Song'));
        await tester.pumpAndSettle();
        expect(find.byType(SongEditorScreen), findsOneWidget);
        await ui.enter(tester, 'Title', 'Edited from setlist');
        await tester.tap(find.text('Save Song'));
        await tester.pumpAndSettle();
        expect(find.byType(SongEditorScreen), findsNothing);
        expect(find.text('Edited from setlist'), findsOneWidget);
        expect(
            tester
                .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, 'Avery · A'))
                .selected,
            isTrue);
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Unsaved service'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Save'));
        await tester.pumpAndSettle();
        final setlist = await tester.runAsync(() =>
            container.read(setlistRepositoryProvider).getSetlist('setlist-1'));
        expect(setlist!.draftItems!.first.performanceKey, 'A');
        expect(setlist.draftItems!.first.vocalistName, 'Avery');
        expect(setlist.draftItems!.first.arrangementId, 'song-1-arr-full');
      });

  testWidgets(
      'header popup edits song while preserving selection and personal controls',
          (tester) async {
        final container =
        await ui.launch(tester, route: '/setlists/setlist-1/rehearse');
        await tester.drag(
            find.byKey(const ValueKey('song-swipe')), const Offset(-400, 0));
        await tester.pumpAndSettle();
        container
            .read(personalTransposeProvider('song-6-arr-full').notifier)
            .state = 2;
        await tester.tap(find.byTooltip('Hide Sections'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open Hands'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Arrangement: Full Band'), findsOneWidget);
        expect(find.textContaining('Worship Leader: Not selected'),
            findsOneWidget);
        await tester.tap(find.text('Edit Song'));
        await tester.pumpAndSettle();
        await ui.enter(tester, 'Artist', 'Updated Artist');
        await tester.tap(find.text('Save Song'));
        await tester.pumpAndSettle();
        expect(find.byType(RehearsalScreen), findsOneWidget);
        expect(find.text('Open Hands'), findsOneWidget);
        expect(find.text('Updated Artist'), findsOneWidget);
        expect(find.byTooltip('Show Sections'), findsOneWidget);
        expect(container.read(personalTransposeProvider('song-6-arr-full')), 2);
        expect(find.byIcon(Icons.play_circle_outline_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      });

  testWidgets('trainee header is non-interactive and routes stay blocked',
          (tester) async {
        final container = await ui.launch(tester,
            route: '/setlists/setlist-1/rehearse',
            role: UserRole.worshipTrainee);

        // Tapping a song in rehearsal must not open an action dialog for trainees.
        await tester.tap(find.text('Anchor of the Morning'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);

        // Song Details renders, but exposes no favorite (or any) action controls.
        container.read(routing.appRouterProvider).go('/songs/song-1');
        await tester.pumpAndSettle();
        expect(find.byType(SongDetailsScreen), findsOneWidget);
        expect(find.byTooltip('Remove favorite'), findsNothing);
        expect(find.byTooltip('Add favorite'), findsNothing);
        expect(find.byTooltip('Edit Song'), findsNothing);

        // Setlist editing is still blocked for trainees.
        container.read(routing.appRouterProvider).go('/setlists/setlist-1/edit');
        await tester.pumpAndSettle();
        expect(find.byType(SetlistEditorScreen), findsNothing);
      });

  testWidgets(
      'preset edits and arrangement changes never overwrite stored item key',
          (tester) async {
        final container =
        await ui.launch(tester, route: '/setlists/setlist-1/edit');
        await tester.tap(find.text('1. Anchor of the Morning'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Avery · A'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Acoustic'));
        await tester.pumpAndSettle();
        final song = container.read(songByIdProvider('song-1'))!;
        await tester.runAsync(() =>
            container
                .read(songRepositoryProvider)
                .updateSong(
                'group-1',
                song.copyWith(vocalistKeys: const [
                  VocalistKey(vocalistName: 'Avery', key: 'Bb')
                ])));
        await tester.pumpAndSettle();
        expect(find.textContaining('Stored key: A · Avery'), findsOneWidget);
        await tester.ensureVisible(find.text('Done'));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Save'));
        await tester.pumpAndSettle();
        final setlist = await tester.runAsync(() =>
            container.read(setlistRepositoryProvider).getSetlist('setlist-1'));
        expect(setlist!.draftItems!.first.performanceKey, 'A');
        expect(setlist.draftItems!.first.arrangementId, 'song-1-arr-acoustic');
      });

  testWidgets(
      'missing presets require explicit choice; removed routes stay absent',
          (tester) async {
      final container =
      await ui.launch(tester, route: '/setlists/setlist-1/edit');
      final router = container.read(routing.appRouterProvider);
      List<String> paths(List<RouteBase> routes) =>
          routes
              .whereType<GoRoute>()
              .expand((r) => [r.path, ...paths(r.routes)])
              .toList();
      final registered = paths(router.configuration.routes);
      expect(registered.where((p) => p.contains('live')), isEmpty);
      expect(registered, isNot(contains('/setlists/:setlistId')));

      final song = container.read(songByIdProvider('song-2'))!;
      await tester.runAsync(() =>
          container
              .read(songRepositoryProvider)
              .updateSong('group-1', song.copyWith(vocalistKeys: [])));
      await tester.pumpAndSettle();

      await tester.tap(find
          .text('Add')
          .first);
      await tester.pumpAndSettle();
      await tester.enterText(find
          .byType(TextField)
          .last, song.title);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, song.title));
      await tester.pump();
      await tester.tap(find.text('Add (1)'));
      await tester.pumpAndSettle();

      // Empty-state text is unaffected by the Card wrapper.
      expect(find.textContaining('No vocal key presets.'), findsOneWidget);

      // Find the Done button robustly. There may now be multiple buttons
      // with the label "Done" (one per vocal-key bubble), so we take the
      // first and assert it's disabled.
      final doneButton = find
          .widgetWithText(FilledButton, 'Done')
          .first; // ← tolerate multiple cards
      expect(tester
          .widget<FilledButton>(doneButton)
          .onPressed, isNull);

      expect(find.text('Edit Song'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
}