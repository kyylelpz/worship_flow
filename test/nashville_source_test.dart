import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/models/setlist_item.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/models/chart_document.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/charts/widgets/chord_label.dart';

const parser = ChordProParser();
const engine = ChartTransformer();
List<String> labels(DisplayChart chart) => chart.sections
    .expand((s) => s.lines)
    .expand((l) => l.chords)
    .map((c) => c.text)
    .toList();

void main() {
  test('E major numbered roots, borrowed degrees, qualities and slash bass',
      () {
    const source = '{key: E}\n[1]a[5/1]b[b7/1]c[1/3]d[5m7]e[b6]f[#2]g[#3]h';
    final parsed = parser.parse(source);
    expect(labels(engine.display(parsed, const ChartSettings())),
        ['E', 'B/E', 'D/E', 'E/G#', 'Bm7', 'C', 'G', 'A']);
    expect(
        labels(engine.display(parsed, const ChartSettings(useNashville: true))),
        ['1', '5/1', 'b7/1', '1/3', '5m7', 'b6', '#2', '#3']);
    final line = parsed.sections.last.lines.last;
    expect(line.text, 'abcdefgh');
    expect(line.chords.map((c) => c.offset), List.generate(8, (i) => i));
    expect(parsed.source, source);
  });

  test('mixed sources transpose to performance key then personal offset', () {
    final song = mockSongs.first;
    final arrangement = song.arrangements.first
        .copyWith(chordProSource: '{key: E}\n[1]a[Bm7]b[1/3]c[b7/1]d');
    final prepared = engine.prepare(
        song: song,
        arrangement: arrangement,
        item: SetlistItem(
            songId: song.id,
            arrangementId: arrangement.id,
            performanceKey: 'G'),
        personalSemitones: 2,
        settings: const ChartSettings());
    expect(labels(prepared), ['A', 'Em7', 'A/C#', 'G/A']);
    expect(
        labels(engine.display(
            prepared.document, const ChartSettings(useNashville: true))),
        ['1', '5m7', '1/3', 'b7/1']);
    expect(prepared.document.source, arrangement.chordProSource);
  });

  test('natural minor, qualities, flats and double accidentals', () {
    final chart =
        parser.parse('{key: Am}\n[1m7]a[3maj7]b[6]c[#7dim7/2]d[bb3aug]e');
    expect(labels(engine.display(chart, const ChartSettings())),
        ['Am7', 'Cmaj7', 'F', 'G#dim7/B', 'Bbaug']);
    expect(
        labels(engine.display(engine.transpose(chart, targetKey: 'Cm'),
            const ChartSettings(useNashville: true))),
        ['1m7', '3maj7', '6', '#7dim7/2', 'bb3aug']);
  });

  test(
      'supported suffixes remain literal and explicit display key is respected',
      () {
    final chart =
        parser.parse('{key: E}\n[1sus2]a[1add9]b[1dim7]c[1aug]d[15]e[16]f');
    expect(labels(engine.display(chart, const ChartSettings())),
        ['Esus2', 'Eadd9', 'Edim7', 'Eaug', 'E5', 'E6']);
    expect(
        labels(engine.display(parser.parse('{key: E}\n[1]word'),
            const ChartSettings(useNashville: true),
            key: 'A')),
        ['5']);
  });

  test('malformed numbers stay literal and missing/invalid key warns', () {
    for (final key in ['', '{key: H}\n']) {
      final chart = parser.parse('$key[1]text[5m7]here');
      expect(chart.warnings.join(), contains('valid source {key}'));
      expect(
          labels(engine.display(chart, const ChartSettings())), ['1', '5m7']);
      expect(
          chart.sections.last.lines.last.chords.every((c) => c.symbol == null),
          isTrue);
    }
    final chart = parser.parse('{key: E}\n[0]a[8]b[123]c[1/9]d[1/2/3]e[1wat]f');
    expect(chart.sections.last.lines.last.chords.every((c) => c.symbol == null),
        isTrue);
    expect(chart.warnings, isNotEmpty);
  });

  test('ordinary instrumentals preserve source columns and lyric hyphens', () {
    const row = '  [1] - - - |: [5/1]  - - - :| %';
    final chart = parser.parse('{key: E}\n$row\n[1]well-being\n#2 - | 5 -');
    final lines = chart.sections.expand((s) => s.lines).toList();
    final instrumental = lines[1];
    expect(instrumental.kind, ChartLineKind.chords);
    expect(instrumental.source, row);
    expect(instrumental.chords.map((c) => c.offset), [2, row.indexOf('[5/1]')]);
    expect(instrumental.text, contains('- - - |:'));
    expect(lines[2].text, 'well-being');
    expect(lines[3].kind, ChartLineKind.chords);
    expect(chart.grids, isEmpty);
  });

  test('numbered explicit grids share conversion and mismatch detection', () {
    final chart = parser.parse('{key: E}\n{section: Verse}\n[1]a[5/1]b\n'
        '{start_of_grid: Verse}\n| 1 - - - | 5/1 - - - |\n{end_of_grid}');
    expect(chart.grids.single.isValid, isTrue);
    expect(chart.warnings, isEmpty);
    final display = engine.display(engine.transpose(chart, targetKey: 'G'),
        const ChartSettings(displayMode: ChartDisplayMode.chordsOnly));
    expect(display.grids.single.measures.expand((m) => m).map((s) => s.text),
        ['G', '-', '-', '-', 'D/G', '-', '-', '-']);
  });

  testWidgets(
      'instrumental markers, typography and all display modes survive conversion',
      (tester) async {
    const source =
        '{key: E}\n{section: Intro}\n[1] - - - |: [5m7/1]  - - - :| %\n\n[1]well-being';
    for (final mode in ChartDisplayMode.values) {
      for (final nashville in [false, true]) {
        final settings =
            ChartSettings(displayMode: mode, useNashville: nashville);
        final chart = engine.display(
            engine.transpose(parser.parse(source), semitones: 3), settings);
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 320,
                    child: MediaQuery(
                        data: const MediaQueryData(
                            textScaler: TextScaler.linear(1.5)),
                        child: ChordChartView(
                            chart: chart, settings: settings))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (mode == ChartDisplayMode.lyricsOnly) {
          expect(find.byType(ChordLabel), findsNothing);
          expect(find.text('well-being'), findsOneWidget);
        } else {
          expect(find.text(' - - - |: '), findsOneWidget);
          expect(find.text('  - - - :| %'), findsOneWidget);
          expect(find.text('7'), findsOneWidget);
          expect(
              find.byWidgetPredicate((w) =>
                  w is ChordLabel && w.text == (nashville ? '5m7/1' : 'Dm7/G')),
              findsOneWidget);
        }
      }
    }
  });
}
