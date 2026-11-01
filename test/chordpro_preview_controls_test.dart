import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/core/models/vocalist_key.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/charts/widgets/chord_label.dart';
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';
import 'package:worship_flow/features/songs/screens/basic_chordpro_editor_screen.dart';
import 'package:worship_flow/features/songs/screens/song_library_screen.dart';
import 'chordpro_editor_test.dart' as editor;
import 'song_management_test.dart' as ui;

Future<void> chooseKey(WidgetTester t, String label) async {
  await t.tap(find.byKey(const ValueKey('preview-key')));
  await t.pumpAndSettle();
  await t.ensureVisible(find.text(label).last);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

Iterable<String> labels(WidgetTester t) =>
    t.widgetList<ChordLabel>(find.byType(ChordLabel)).map((w) => w.text);
void main() {
  testWidgets(
      'source key initializes 12-key selector; all controls are immediate, local and source-preserving',
      (t) async {
    final c = await ui.launch(t);
    c.read(chartSettingsProvider.notifier).update((s) => s.copyWith(
        useNashville: true, displayMode: ChartDisplayMode.lyricsOnly));
    final preferences = c.read(chartSettingsProvider);
    const draft =
        '{key: E}\n{section: Verse}\n[1]First lyric [5/1]second lyric';
    final saved = openChordProEditor(
        t.element(find.byType(SongLibraryScreen)), draft, vocalistKeys: const [
      VocalistKey(vocalistName: 'Private Vocalist', key: 'A')
    ]);
    await t.pumpAndSettle();
    final draftController = editor.controller(t);
    await t.tap(find.byTooltip('Preview'));
    await t.pumpAndSettle();
    final key = t.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('preview-key')));
    expect(key.initialValue, 'E');
    final dropdown = t.widget<DropdownButton<String>>(find.descendant(
        of: find.byKey(const ValueKey('preview-key')),
        matching: find.byType(DropdownButton<String>)));
    expect(dropdown.items, hasLength(12));
    expect(dropdown.items!.map((i) => (i.child as Text).data),
        containsAll(['C#/Db', 'F#/Gb', 'Bb']));
    expect(find.byTooltip('Apply preview key'), findsNothing);
    expect(find.textContaining('Private Vocalist'), findsNothing);
    expect(find.text('Lyrics Only'), findsNothing);
    final chart = t.widget<ChordChartView>(find.byType(ChordChartView));
    expect(chart.settings.useNashville, false);
    expect(chart.settings.displayMode, ChartDisplayMode.lyricsAndChords);
    expect(chart.sectionNavigationEnabled, false);
    expect(
        find.descendant(
            of: find.byType(ChordChartView),
            matching: find.byType(NotificationListener<ScrollEndNotification>)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byType(ChordChartView),
            matching: find
                .byWidgetPredicate((w) => w is Padding && w.key is GlobalKey)),
        findsNothing);
    expect(
        find.descendant(
            of: find.byType(ChordChartView),
            matching: find.byType(ValueListenableBuilder<String?>)),
        findsNothing);
    expect(chart.showSections, false);
    expect(chart.reserveSectionSpace, false);
    expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.startsWith('section-bubble-')),
        findsNothing);
    expect(labels(t), containsAll(['E', 'B/E']));
    await chooseKey(t, 'G');
    expect(labels(t), containsAll(['G', 'D/G']));
    await t.tap(find.text('Chords Only'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Nashville'));
    await t.tap(find.text('Nashville'));
    await t.pumpAndSettle();
    expect(labels(t), containsAll(['1', '5/1']));
    expect(
        t
            .widget<ChordChartView>(find.byType(ChordChartView))
            .settings
            .displayMode,
        ChartDisplayMode.chordsOnly);
    expect(
        t
            .widget<DropdownButtonFormField<String>>(
                find.byKey(const ValueKey('preview-key')))
            .initialValue,
        'G');
    await t.tap(find.text('Standard'));
    await t.pumpAndSettle();
    expect(labels(t), containsAll(['G', 'D/G']));
    expect(c.read(chartSettingsProvider), same(preferences));
    expect(draftController.text, draft);
    await t.tap(find.byTooltip('Save'));
    await t.pumpAndSettle();
    expect(await saved, draft);
  });
  testWidgets(
      'minor source context retains minor transposition with chromatic selector',
      (t) async {
    await editor.open(t, '{key: F#m}\n[F#m]Minor lyric');
    await t.tap(find.byTooltip('Preview'));
    await t.pumpAndSettle();
    expect(
        t
            .widget<DropdownButtonFormField<String>>(
                find.byKey(const ValueKey('preview-key')))
            .initialValue,
        'F#m');
    await chooseKey(t, 'Am');
    expect(labels(t), contains('Am'));
    expect(t.takeException(), isNull);
  });
  testWidgets('preview controls adapt on narrow scaled screens in both themes',
      (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = await ui.launch(t);
    for (final dark in [false, true]) {
      await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!),
              home: const ChordProEditorScreen(
                  source:
                      '{key: E}\n{section: Intro}\n| [1] - - - | [5/1] - - - |'))));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Preview'));
      await t.pumpAndSettle();
      expect(find.byType(ChordChartView), findsOneWidget);
      await t.ensureVisible(find.text('Chords Only'));
      await t.tap(find.text('Chords Only'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Nashville'));
      await t.tap(find.text('Nashville'));
      await t.pumpAndSettle();
      expect(
          t
              .widget<ChordChartView>(find.byType(ChordChartView))
              .settings
              .useNashville,
          true);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    }
  });
}
