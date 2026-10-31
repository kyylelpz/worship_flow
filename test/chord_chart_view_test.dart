import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/widgets/anchored_lyric_line.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/charts/providers/chart_providers.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/router/route_paths.dart';
import 'rehearsal_test.dart' as rehearsal;
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';

const engine = ChartTransformer();
const parser = ChordProParser();
Future<void> showChart(
  WidgetTester tester,
  String source, {
  ChartSettings settings = const ChartSettings(),
  double width = 360,
  double scale = 1,
  int transpose = 0,
}) async {
  final document = engine.transpose(parser.parse(source), semitones: transpose);
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
        body: Center(
            child: SizedBox(
                width: width,
                height: 550,
                child: ChordChartView(
                    chart: engine.display(document, settings),
                    settings: settings)))),
  )));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('coincident chords retain lanes and align to lyric segments',
      (tester) async {
    const source = '[Cmaj7][D/F#]Hello [G]world';
    final line = engine
        .display(parser.parse(source), const ChartSettings())
        .sections
        .single
        .lines
        .single;
    const lyricStyle = TextStyle(fontSize: 18, height: 1.4);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 400,
                child: AnchoredLyricLine(
                    line: line,
                    lyricStyle: lyricStyle,
                    chordStyle: const TextStyle(fontSize: 20))))));
    await tester.pumpAndSettle();
    final a = tester.getRect(find.byKey(const ValueKey('chord-1-0')));
    final b = tester.getRect(find.byKey(const ValueKey('chord-1-1')));
    final c = tester.getRect(find.byKey(const ValueKey('chord-1-2')));
    expect(a.left, b.left);
    expect(a.overlaps(b), isFalse);
    expect(
        a.left, tester.getTopLeft(find.byKey(const ValueKey('lyric-1-0'))).dx);
    expect(
        c.left, tester.getTopLeft(find.byKey(const ValueKey('lyric-1-6'))).dx);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chord at a soft wrap sits above the next lyric row',
      (tester) async {
    await showChart(
        tester, '{key: G}\n[G]Rise with the [D]dawn, we [Em]lift our [C]voice');
    final first = tester.getRect(find.byKey(const ValueKey('chord-2-0')));
    final last = tester.getRect(find.byKey(const ValueKey('chord-2-3')));
    expect(last.top - first.top, greaterThan(first.height + 18));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrapping and high text scale fit narrow screens',
      (tester) async {
    await showChart(
        tester,
        '{key: C}\n{section: Verse}\n'
        '[Cmaj7/G]Long words [Dsus4/F#]with many syllables [G7]wrapping through this [Am]line.',
        width: 240,
        scale: 2);
    final chartRect = tester.getRect(find.byType(AnchoredLyricLine));
    for (var i = 0; i < 4; i++) {
      final rect = tester.getRect(find.byKey(ValueKey('chord-3-$i')));
      expect(rect.left, greaterThanOrEqualTo(chartRect.left));
      expect(rect.right, lessThanOrEqualTo(chartRect.right + .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('three modes show lyrics, chords or both without invented timing',
      (tester) async {
    const source = '{key: C}\n{section: Verse}\n[C]Hello [G/B]world';
    await showChart(tester, source);
    expect(find.byType(AnchoredLyricLine), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('G/B'), findsOneWidget);
    await showChart(tester, source,
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.chordsOnly));
    expect(find.byType(AnchoredLyricLine), findsNothing);
    expect(find.text('Chord sequence · no timing'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    await showChart(tester, source,
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.lyricsOnly));
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('C'), findsNothing);
    expect(find.text('G/B'), findsNothing);
  });

  testWidgets('transposed and Nashville labels render from engine projections',
      (tester) async {
    const source = '{key: C}\n[C]Hello [G/B]world';
    await showChart(tester, source, transpose: 2);
    expect(find.text('D'), findsOneWidget);
    expect(find.text('A/C#'), findsOneWidget);
    await showChart(tester, source,
        transpose: 2, settings: const ChartSettings(useNashville: true));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('5/7'), findsOneWidget);
  });

  testWidgets(
      'chords-only displays valid measures; invalid grids warn and fall back',
      (tester) async {
    const source = '{key: D}\n{section: Verse}\n[D]One [G]two\n'
        '{start_of_grid: Verse}\n| D - G - |\n{end_of_grid}';
    await showChart(tester, source,
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.chordsOnly));
    expect(find.text('4/4 · 1 slot(s) per denominator beat'), findsOneWidget);
    expect(find.text('Chord sequence · no timing'), findsNothing);
    expect(find.text('-'), findsNWidgets(2));
    await showChart(tester, source.replaceAll('D - G -', 'D -'),
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.chordsOnly));
    expect(find.textContaining('Chart warning:'), findsWidgets);
    expect(find.text('Chord sequence · no timing'), findsOneWidget);
    expect(find.text('Invalid grid sequence · no timing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subdivided 6/8 measures fit narrow scaled screens',
      (tester) async {
    await showChart(
        tester,
        '{key: C}\n{time: 6/8}\n{grid_subdivision: 2}\n'
        '{start_of_grid: Intro}\n| C - G/B - Am - F - G7 - C - |\n{end_of_grid}',
        width: 240,
        scale: 2,
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.chordsOnly));
    expect(find.text('6/8 · 2 slot(s) per denominator beat'), findsOneWidget);
    expect(find.text('1.1'), findsOneWidget);
    expect(find.text('6.2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact controls update display and chart font settings',
      (tester) async {
    final container = await rehearsal.launch(tester,
        route: RoutePaths.setlistRehearsalFor('setlist-1'));
    await tester.tap(find.byType(DropdownButton<ChartDisplayMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ChartDisplayMode.chordsOnly.label).last);
    await tester.pumpAndSettle();
    expect(find.byType(AnchoredLyricLine), findsNothing);
    expect(container.read(chartSettingsProvider).displayMode,
        ChartDisplayMode.chordsOnly);
    final size = container.read(chartSettingsProvider).lyricsFontSize;
    await tester.ensureVisible(find.byTooltip('Larger chart text'));
    await tester.tap(find.byTooltip('Larger chart text'));
    await tester.pumpAndSettle();
    expect(container.read(chartSettingsProvider).lyricsFontSize, size + 1);
    await tester.ensureVisible(find.byTooltip('Smaller chart text'));
    await tester.tap(find.byTooltip('Smaller chart text'));
    await tester.pumpAndSettle();
    expect(container.read(chartSettingsProvider).lyricsFontSize, size);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parsed repeated sections have separate navigation targets',
      (tester) async {
    await showChart(
        tester,
        '{key: C}\n{soc: Refrain}\n[C]First\n{eoc}\n'
        '{soc: Refrain}\n[G]Second\n{eoc}');
    expect(find.widgetWithText(TextButton, 'RF1'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'RF2'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'personal transpose is separate from canonical setlist key and drawer state',
      (tester) async {
    final container = await rehearsal.launch(tester,
        route: RoutePaths.setlistRehearsalFor('setlist-1'));
    final original = mockSongs.first.primaryArrangement.chordProSource;
    await tester.ensureVisible(find.byTooltip('Transpose up'));
    await tester.tap(find.byTooltip('Transpose up'));
    await tester.pumpAndSettle();
    expect(find.text('Key Ab · 1/3'), findsOneWidget);
    expect(
        container.read(
            personalTransposeProvider(mockSongs.first.primaryArrangement.id)),
        1);
    expect(mockSongs.first.primaryArrangement.chordProSource, original);
    await rehearsal.openDrawer(tester);
    expect(find.text('G'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setlist-song-1')));
    await tester.pumpAndSettle();
    await rehearsal.openDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('setlist-song-0')));
    await tester.pumpAndSettle();
    expect(find.text('Key Ab · 1/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
