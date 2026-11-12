import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/charts/widgets/compact_chord_grid.dart';
import 'package:worship_flow/features/charts/widgets/chord_label.dart';
import 'package:worship_flow/features/charts/widgets/anchored_lyric_line.dart';

const intro =
    '{key: E}\n{section: Intro}\n| [1] - - - | [5/1] - - - |\n| [b7/1] - - - | [4/1] - - - |\n(2x)\n(4x)';
Future<void> render(WidgetTester t, String source,
    {ChartSettings settings = const ChartSettings(),
    double width = 380,
    double scale = 1}) async {
  const engine = ChartTransformer();
  final document =
      engine.transpose(const ChordProParser().parse(source), semitones: 0);
  await t.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: width,
                      height: 520,
                      child: ChordChartView(
                          chart: engine.display(document, settings),
                          settings: settings,
                          showSections: false,
                          reserveSectionSpace: false)))))));
  await t.pumpAndSettle();
}

void main() {
  for (final mode in [
    ChartDisplayMode.lyricsAndChords,
    ChartDisplayMode.chordsOnly
  ]) {
    testWidgets(
        'ordinary Intro in $mode preserves barlines and repeats without expansion',
        (t) async {
      await render(t, intro,
          width: 500, settings: ChartSettings(displayMode: mode));
      expect(find.byType(CompactChordGrid), findsOneWidget);
      expect(find.byType(AnchoredLyricLine), findsNothing);
      expect(find.text('(2x)'), findsOneWidget);
      expect(find.text('(4x)'), findsOneWidget);
      final grid = t.widget<CompactChordGrid>(find.byType(CompactChordGrid));
      expect(grid.rows.expand((r) => r.measures), hasLength(4));
      expect(t.getTopLeft(find.byKey(const ValueKey('compact-measure-0'))).dy,
          t.getTopLeft(find.byKey(const ValueKey('compact-measure-1'))).dy);
      expect(
          t.getTopLeft(find.byKey(const ValueKey('compact-measure-2'))).dy,
          greaterThan(t
              .getTopLeft(find.byKey(const ValueKey('compact-measure-0')))
              .dy));
      expect(t.getTopLeft(find.byKey(const ValueKey('grid-bar-0-open'))).dx,
          t.getTopLeft(find.byKey(const ValueKey('grid-bar-2-open'))).dx);
      expect(
          find.byWidgetPredicate((w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal),
          findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('explicit measures pack independently and retain every beat cell',
      (t) async {
    const standard = '| - D - - | G - - - | A - - - |\n\n'
        '| - Asus4 - - | G/A - - - | D7/Db - - - |';
    const numbered = '| - [1] - - | [4] - - - | [5] - - - |\n\n'
        '| - [1M7] - - | [67/b6] - - - | [5] - - - |';
    for (final nashville in [false, true]) {
      final source = '{key: D}\n{start_of_grid: Intro}\n'
          '${nashville ? numbered : standard}\n{end_of_grid}';
      final expected = nashville
          ? [
              '-',
              '1',
              '-',
              '-',
              '4',
              '-',
              '-',
              '-',
              '5',
              '-',
              '-',
              '-',
              '-',
              '1M7',
              '-',
              '-',
              '67/b6',
              '-',
              '-',
              '-',
              '5',
              '-',
              '-',
              '-'
            ]
          : [
              '-',
              'D',
              '-',
              '-',
              'G',
              '-',
              '-',
              '-',
              'A',
              '-',
              '-',
              '-',
              '-',
              'Asus4',
              '-',
              '-',
              'G/A',
              '-',
              '-',
              '-',
              'D7/Db',
              '-',
              '-',
              '-'
            ];
      for (final width in [320.0, 360.0, 393.0, 600.0]) {
        for (final fontSize in [14.0, 24.0]) {
          await render(t, source,
              width: width,
              settings: ChartSettings(
                  chordsFontSize: fontSize,
                  chordSpacing: 0,
                  displayMode: ChartDisplayMode.chordsOnly,
                  useNashville: nashville));
          final grid = find.byType(CompactChordGrid);
          final bounds = t.getRect(grid);
          Rect measure(int index) =>
              t.getRect(find.byKey(ValueKey('compact-measure-$index')));
          expect(measure(0).width, lessThan(measure(3).width));
          expect(measure(1).width, lessThan(measure(4).width));
          expect(measure(3).top, greaterThan(measure(2).bottom));
          if (width == 600 || fontSize == 14) {
            expect(measure(2).top, measure(0).top);
          }
          for (var m = 0; m < 6; m++) {
            final measureBounds = measure(m);
            expect(measureBounds.right, lessThanOrEqualTo(bounds.right + .01));
            for (var c = 0; c < 4; c++) {
              final cell = find.byKey(ValueKey('grid-cell-$m-$c'));
              final label =
                  find.descendant(of: cell, matching: find.byType(ChordLabel));
              expect(t.widget<ChordLabel>(label).text, expected[m * 4 + c]);
              final cellBounds = t.getRect(cell);
              final labelBounds = t.getRect(label);
              expect(cellBounds.top, measureBounds.top);
              expect(
                  labelBounds.right, lessThanOrEqualTo(cellBounds.right + .01));
              expect(labelBounds.bottom,
                  lessThanOrEqualTo(cellBounds.bottom + .01));
              if (c > 0) {
                final previous =
                    t.getRect(find.byKey(ValueKey('grid-cell-$m-${c - 1}')));
                expect(cellBounds.left,
                    greaterThanOrEqualTo(previous.right - .01));
              }
            }
          }
          expect(
              find.byWidgetPredicate((w) =>
                  w is SingleChildScrollView &&
                  w.scrollDirection == Axis.horizontal),
              findsNothing);
          expect(t.takeException(), isNull);
        }
      }
    }
  });
  testWidgets('chord spacing separates labels and reflows intact measures',
      (t) async {
    for (final nashville in [false, true]) {
      final labels =
          nashville ? ['67/b6', '1M7', '4'] : ['D2/F#', 'GM7', 'CM7/D'];
      final source = '{key: D}\n{start_of_grid: Intro}\n'
          '| - [${labels[0]}] - - | [${labels[1]}] - - - | [${labels[2]}] - - - |\n'
          '{end_of_grid}';
      for (final width in [320.0, 360.0, 393.0, 600.0]) {
        var previousWidth = 0.0;
        double? tightSecondRow;
        for (final spacing in [0.0, 8.0, 16.0, 21.0, 24.0]) {
          await render(t, source,
              width: width,
              settings: ChartSettings(
                chordsFontSize: 16,
                chordSpacing: spacing,
                displayMode: ChartDisplayMode.chordsOnly,
                useNashville: nashville,
              ));
          final view = t.widget<ChordChartView>(find.byType(ChordChartView));
          final grid = view.chart.document.grids.single;
          expect(view.chart.document.source, source);
          expect(grid.isValid, isTrue);
          expect(grid.slotsPerMeasure, 4);
          expect(grid.measures.first.slots[0].sustain, isFalse);
          expect(grid.measures.first.slots[1].index, 1);
          expect(grid.measures.first.slots[1].chord, isNotNull);
          final first =
              t.getRect(find.byKey(const ValueKey('compact-measure-0')));
          final second =
              t.getRect(find.byKey(const ValueKey('compact-measure-1')));
          expect(first.width, greaterThan(previousWidth));
          previousWidth = first.width;
          tightSecondRow ??= second.top;
          if (width == 320 && spacing == 24) {
            expect(second.top, greaterThan(tightSecondRow));
          }
          for (var m = 0; m < 3; m++) {
            Rect? previousLabel;
            final measure =
                t.getRect(find.byKey(ValueKey('compact-measure-$m')));
            for (var c = 0; c < 4; c++) {
              final cell = find.byKey(ValueKey('grid-cell-$m-$c'));
              final label =
                  find.descendant(of: cell, matching: find.byType(ChordLabel));
              expect(t.widget<ChordLabel>(label).text,
                  c == (m == 0 ? 1 : 0) ? labels[m] : '-');
              final cellBounds = t.getRect(cell);
              final labelBounds = t.getRect(label);
              expect(cellBounds.top, measure.top);
              expect(
                  labelBounds.right, lessThanOrEqualTo(cellBounds.right + .01));
              expect(labelBounds.bottom,
                  lessThanOrEqualTo(cellBounds.bottom + .01));
              if (previousLabel != null) {
                expect(labelBounds.left - previousLabel.right,
                    closeTo(spacing, .01));
              }
              previousLabel = labelBounds;
            }
          }
          expect(t.takeException(), isNull);
        }
      }
    }
  });
  testWidgets('each song gets three spacing gaps per four-beat measure',
      (t) async {
    for (final chords in ['C D G C', 'Bm Dm C/E Bm', 'D2/F# GM7 CM7/D Asus4']) {
      for (final fontSize in [14.0, 24.0]) {
        double? baseWidth;
        double? barGap;
        for (final spacing in [0.0, 8.0, 16.0, 21.0, 24.0]) {
          await render(t, '{start_of_grid: Intro}\n| $chords |\n{end_of_grid}',
              width: 320,
              settings: ChartSettings(
                  chordsFontSize: fontSize,
                  chordSpacing: spacing,
                  displayMode: ChartDisplayMode.chordsOnly));
          final width =
              t.getSize(find.byKey(const ValueKey('compact-measure-0'))).width;
          baseWidth ??= width;
          expect(width, closeTo(baseWidth + 3 * spacing, .01));
          Rect label(String key) => t.getRect(find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(ChordLabel)));
          final firstGap =
              label('grid-cell-0-0').left - label('grid-bar-0-open').right;
          barGap ??= firstGap;
          expect(firstGap, closeTo(barGap, .01));
          expect(label('grid-bar-0-close').left - label('grid-cell-0-3').right,
              closeTo(barGap, .01));
          for (var i = 1; i < 4; i++) {
            expect(
                label('grid-cell-0-$i').left -
                    label('grid-cell-0-${i - 1}').right,
                closeTo(spacing, .01));
          }
          expect(t.takeException(), isNull);
        }
      }
    }
  });
  const verse =
      '{key: E}\n{section: Verse 1}\n[1]First lyric [5]second lyric\n{grid_subdivision: 1}\n{start_of_grid: Verse 1}\n| 1 - - - | 5 - - - |\n| b7 - - - | 4 - - - |\n{end_of_grid}';
  testWidgets(
      'associated timing is compact in Chords Only and hidden behind anchored lyrics',
      (t) async {
    await render(t, verse);
    expect(find.byType(AnchoredLyricLine), findsOneWidget);
    expect(find.byType(CompactChordGrid), findsNothing);
    await render(t, verse,
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.chordsOnly));
    expect(find.byType(AnchoredLyricLine), findsNothing);
    final grid = t.widget<CompactChordGrid>(find.byType(CompactChordGrid));
    expect(grid.rows.expand((r) => r.measures).map((m) => m.cells.first),
        ['E', 'B', 'D', 'A']);
    expect(find.text('1.1'), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'repeat text on an associated grid remains visible in Chords Only',
      (t) async {
    await render(t, '$verse\n(4x)',
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.chordsOnly));
    expect(find.text('(4x)'), findsOneWidget);
    expect(
        t
            .widgetList<CompactChordGrid>(find.byType(CompactChordGrid))
            .expand((grid) => grid.rows)
            .expand((r) => r.measures),
        hasLength(4));
  });
  testWidgets('standalone timing grid is also compact in Lyrics + Chords',
      (t) async {
    await render(t,
        '{key: E}\n{start_of_grid: Intro}\n| E - - - | B/E - - - |\n{end_of_grid}');
    expect(find.byType(CompactChordGrid), findsOneWidget);
    expect(
        t
            .widget<CompactChordGrid>(find.byType(CompactChordGrid))
            .rows
            .single
            .measures,
        hasLength(2));
  });
  testWidgets(
      'repeated written measures remain separate; Lyrics Only stays lyric-only',
      (t) async {
    const text =
        '{key: E}\n{section: Intro}\n| [1] - - - | [1] - - - |\n(2x)\n{section: Verse}\n[1]Well-being';
    await render(t, text);
    expect(
        t
            .widget<CompactChordGrid>(find.byType(CompactChordGrid))
            .rows
            .expand((r) => r.measures),
        hasLength(2));
    await render(t, text,
        settings:
            const ChartSettings(displayMode: ChartDisplayMode.lyricsOnly));
    expect(find.byType(ChordLabel), findsNothing);
    expect(find.text('Well-being'), findsOneWidget);
    expect(find.text('(2x)'), findsOneWidget);
  });
  testWidgets(
      'long styled slash chords wrap whole measures and keep anchors apart after typography changes',
      (t) async {
    const text =
        '{key: E}\n{section: Intro}\n| [C#m7/G#] - [B/E] - | [F#m9/C#] - - - |';
    for (final size in [18.0, 32.0]) {
      await render(t, text,
          width: 340, settings: ChartSettings(chordsFontSize: size));
      final first = t.getRect(find.byKey(const ValueKey('compact-measure-0')));
      final second = t.getRect(find.byKey(const ValueKey('compact-measure-1')));
      expect(second.top, greaterThan(first.top));
      for (var c = 0; c < 3; c++) {
        final cell = find.byKey(ValueKey('grid-cell-0-$c'));
        final label =
            find.descendant(of: cell, matching: find.byType(ChordLabel));
        expect(
            t.getRect(label).right,
            lessThanOrEqualTo(
                t.getRect(find.byKey(ValueKey('grid-cell-0-${c + 1}'))).left));
      }
      expect(find.text('7'), findsOneWidget);
      expect(t.takeException(), isNull);
    }
  });
  testWidgets(
      'dense actual subdivisions and large system scaling retain every slot on narrow screens',
      (t) async {
    await render(t,
        '{key: E}\n{time: 6/8}\n{grid_subdivision: 2}\n{start_of_grid: Intro}\n| C#m7/G# - D - E - F# - G# - A - |\n{end_of_grid}',
        width: 220,
        scale: 2,
        settings: const ChartSettings(
            displayMode: ChartDisplayMode.chordsOnly, chordsFontSize: 28));
    final cells = t
        .widget<CompactChordGrid>(find.byType(CompactChordGrid))
        .rows
        .single
        .measures
        .single
        .cells;
    expect(cells, hasLength(12));
    expect(cells.where((s) => s == '-'), hasLength(6));
    expect(
        find.byWidgetPredicate((w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final explicit in [false, true]) {
    for (final blanks in [0, 1, 3]) {
      for (final mode in [
        ChartDisplayMode.lyricsAndChords,
        ChartDisplayMode.chordsOnly
      ]) {
        testWidgets(
            '${explicit ? 'explicit' : 'ordinary'} grid: $blanks blank rows in $mode separate groups without adding timing',
            (t) async {
          const measures =
              '| [1] - - - | [5/1] - - - |\n| [b7/1] - - - | [4/1] - - - |';
          final body =
              '$measures\n${List.filled(blanks, "\n").join()}$measures';
          final source =
              '{key: E}\n${explicit ? "{start_of_grid: Chorus}" : "{section: Chorus}"}\n$body${explicit ? "\n{end_of_grid}" : ""}\n(2x)\n(4x)';
          final parsed = const ChordProParser().parse(source);
          await render(t, source,
              width: 500,
              settings: ChartSettings(displayMode: mode, useNashville: true));
          final grid = t
              .widgetList<CompactChordGrid>(find.byType(CompactChordGrid))
              .firstWhere((g) => g.rows.any((r) => r.measures.isNotEmpty));
          expect(grid.rows.expand((r) => r.measures), hasLength(8));
          expect(grid.rows.where((r) => r.measures.isEmpty && r.text == ''),
              hasLength(blanks));
          expect(grid.rows.expand((r) => r.measures).map((m) => m.cells.first),
              ['1', '5/1', 'b7/1', '4/1', '1', '5/1', 'b7/1', '4/1']);
          Rect measure(int index) =>
              t.getRect(find.byKey(ValueKey('compact-measure-$index')));
          final regularGap = measure(2).top - measure(0).bottom;
          final groupGap = measure(4).top - measure(2).bottom;
          expect(
              groupGap,
              closeTo(
                  regularGap +
                      const ChartSettings().chordsFontSize * .45 * blanks,
                  .01));
          expect(measure(0).left, closeTo(measure(4).left, .01));
          expect(measure(1).left, closeTo(measure(5).left, .01));
          expect(find.text('(2x)'), findsOneWidget);
          expect(find.text('(4x)'), findsOneWidget);
          if (explicit) {
            expect(parsed.grids.single.measures, hasLength(8));
            expect(
                parsed.grids.single.measures.every((m) => m.slots.length == 4),
                true);
          }
          expect(parsed.source, source);
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
