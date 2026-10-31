import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';

const parser = ChordProParser();
const engine = ChartTransformer();
void main() {
  test(
      'optional grids attach to sections, preserve source, events and sustains',
      () {
    const source =
        '{key: D}\n{time: 4/4}\n{section: Verse 1}\n[D]One [G]two [Bm]three [A]four\n'
        '{start_of_grid: Verse 1}\n| D - G - | Bm - A - |\n{end_of_grid}';
    final chart = parser.parse(source);
    final grid = chart.grids.single;
    expect(chart.source, source);
    expect(chart.warnings, isEmpty);
    expect(grid.isValid, isTrue);
    expect(grid.measures.length, 2);
    expect(grid.slotsPerMeasure, 4);
    expect(grid.slotDurationInWholeNotes, .25);
    expect(grid.targetSectionId,
        chart.sections.firstWhere((s) => s.label == 'Verse 1').id);
    expect(grid.measures.first.slots.map((s) => s.chord?.text),
        ['D', null, 'G', null]);
    expect(grid.measures.first.slots[1].sustain, isTrue);
    expect(grid.measures.first.openingBar, '|');
    expect(grid.measures.first.closingBar, '|');
  });

  test('3/4, 4/4 and 6/8 support explicit subdivisions', () {
    for (final meter in ['3/4', '4/4', '6/8']) {
      for (final subdivision in [1, 2, 3]) {
        final count = int.parse(meter[0]) * subdivision;
        final source = '{time: $meter}\n{grid_subdivision: $subdivision}\n'
            '{start_of_grid: Intro}\n| C ${List.filled(count - 1, '-').join(' ')} |\n{end_of_grid}';
        final chart = parser.parse(source);
        expect(chart.grids.single.isValid, isTrue,
            reason: '$meter / $subdivision');
        expect(chart.grids.single.measures.single.slots.length, count);
        expect(chart.grids.single.subdivision, subdivision);
        expect(chart.grids.single.slotDurationInWholeNotes,
            1 / (int.parse(meter.split('/').last) * subdivision));
      }
    }
  });

  test('repeat bar marks and repeated measures are retained without expansion',
      () {
    final chart = parser.parse(
        '{start_of_grid: Intro}\n|: C - - - || C - - - :|\n{end_of_grid}');
    final grid = chart.grids.single;
    expect(grid.isValid, isTrue);
    expect(grid.measures.length, 2);
    expect(grid.measures.first.openingBar, '|:');
    expect(grid.measures.first.closingBar, '||');
    expect(grid.measures.last.closingBar, ':|');
  });

  test(
      'no grid never invents durations and mismatches warn without overwriting',
      () {
    final plain = parser.parse('{section: Verse}\n[C]Hi [G]there');
    expect(plain.grids, isEmpty);
    final source =
        '${plain.source}\n{start_of_grid: Verse}\n| F - - - |\n{end_of_grid}';
    final chart = parser.parse(source);
    expect(chart.warnings.single, contains('sequences differ'));
    expect(chart.grids.single.isValid, isTrue);
    expect(
        chart.sections.first.lines.last.chords.map((c) => c.text), ['C', 'G']);
    expect(chart.grids.single.measures.first.slots.first.chord!.text, 'F');
    expect(chart.source, source);
  });

  test('timing chords use the same transpose and Nashville operations', () {
    final chart = parser.parse(
        '{key: D}\n{start_of_grid: Intro}\n| D - G/B A7 |\n{end_of_grid}');
    final changed = engine.transpose(chart, targetKey: 'E');
    expect(changed.grids.single.measures.first.slots.map((s) => s.chord?.text),
        ['E', null, 'A/C#', 'B7']);
    final display =
        engine.display(changed, const ChartSettings(useNashville: true));
    expect(display.grids.single.measures.first.map((s) => s.text),
        ['1', '-', '4/6', '57']);
    expect(changed.source, chart.source);
    expect(
        engine
            .display(changed,
                const ChartSettings(displayMode: ChartDisplayMode.lyricsOnly))
            .grids,
        isEmpty);
  });

  test(
      'invalid slot counts, unknown tokens and orphan sustains produce warnings',
      () {
    for (final row in [
      '| C - |',
      '| - - - - |',
      '| H - - - |',
      'C - - -',
      '| % |'
    ]) {
      final chart = parser.parse('{start_of_grid: Verse}\n$row\n{end_of_grid}');
      expect(chart.grids.single.isValid, isFalse, reason: row);
      expect(chart.warnings, isNotEmpty);
      expect(chart.grids.single.slotDurationInWholeNotes, isNull);
    }
    final chart = parser.parse(
        '{time: 5/4}\n{grid_subdivision: 0}\n{start_of_grid: Intro}\n| C - |\n{end_of_grid}');
    expect(chart.grids.single.isValid, isFalse);
  });

  test('repeated section names associate with nearest preceding occurrence',
      () {
    final chart = parser.parse(
        '{section: Verse}\n[C]One\n{start_of_grid: Verse}\n| C - - - |\n{end_of_grid}\n'
        '{section: Verse}\n[G]Two\n{start_of_grid: Verse}\n| G - - - |\n{end_of_grid}');
    expect(
        chart.grids[0].targetSectionId, isNot(chart.grids[1].targetSectionId));
    expect(chart.warnings, isEmpty);
  });
}
