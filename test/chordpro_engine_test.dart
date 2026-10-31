import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/mock_data/mock_setlists.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/models/chart_document.dart';
import 'package:worship_flow/features/charts/models/chord_symbol.dart';

const parser = ChordProParser();
const transformer = ChartTransformer();
Iterable<ChartLine> lines(ChartDocument chart) =>
    chart.sections.expand((s) => s.lines);
List<String> chords(ChartDocument chart) =>
    lines(chart).expand((l) => l.chords).map((c) => c.text).toList();
List<String> displayedChords(DisplayChart chart) => chart.sections
    .expand((s) => s.lines)
    .expand((l) => l.chords)
    .map((c) => c.text)
    .toList();

void main() {
  group('parser', () {
    test('metadata aliases, repeated values, common and unknown directives',
        () {
      const source =
          '{t: A song}\r\n{artist: One}\r\n{artist: Two}\r\n{k: Eb}\r\n'
          '{tempo: 72}\r\n{time: 6/8}\r\n{capo: 2}\r\n{c: Softly}\r\n'
          '{custom: untouched [C]}\r\n{np}\r\n';
      final chart = parser.parse(source);
      expect(chart.source, source);
      expect(chart.metadata['title'], ['A song']);
      expect(chart.metadata['artist'], ['One', 'Two']);
      expect(chart.key!.name, 'Eb');
      expect(chart.metadata['time'], ['6/8']);
      expect(
          lines(chart)
              .where((l) => l.directive?.kind == DirectiveKind.comment)
              .single
              .directive!
              .value,
          'Softly');
      final unknown =
          lines(chart).firstWhere((l) => l.directive?.name == 'custom');
      expect(unknown.directive!.kind, DirectiveKind.unknown);
      expect(unknown.source, '{custom: untouched [C]}');
      expect(unknown.chords, isEmpty);
      expect(lines(chart).last.kind, ChartLineKind.blank);
      expect(
          () => chart.metadata['artist']!.add('bad'), throwsUnsupportedError);
      expect(() => chart.sections.clear(), throwsUnsupportedError);
    });

    test('exact inline anchors, adjacent/trailing chords and Unicode offsets',
        () {
      final line =
          lines(parser.parse('  [G]Hel[D/F#]lo [Am][C]🌟[G/B]')).single;
      expect(line.text, '  Hello 🌟');
      expect(line.chords.map((c) => c.offset), [2, 5, 8, 8, 10]);
      expect(line.chords.map((c) => c.sourceOffset), [2, 8, 17, 21, 26]);
      expect(line.chords.last.symbol!.bass!.name, 'B');
    });

    test('repeated sections have stable distinct identities and blank lines',
        () {
      const source = '{soc: Refrain}\n[C]One\n\n{eoc}\n'
          '{section: Refrain}\n[G]Two\n{chorus}';
      final chart = parser.parse(source);
      final repeated =
          chart.sections.where((s) => s.label == 'Refrain').toList();
      expect(repeated.length, 2);
      expect(repeated[0].id, isNot(repeated[1].id));
      expect(chart.sections.map((s) => s.id),
          parser.parse(source).sections.map((s) => s.id));
      expect(
          lines(chart).where((l) => l.kind == ChartLineKind.blank).length, 1);
      expect(lines(chart).last.directive!.name, 'chorus');
    });

    test('bare and bracketed instrumental grids retain columns and separators',
        () {
      const source =
          '{sog}\n| C    G/B | Am7  F |\n| [C] G/B | [Am7] F |\n|: % / N.C. :|\n{eog}';
      final chart = parser.parse(source);
      final grids =
          lines(chart).where((l) => l.kind == ChartLineKind.chords).toList();
      expect(grids.length, 3);
      expect(grids[0].chords.map((c) => c.offset), [2, 7, 13, 18]);
      expect(grids[0].text, '|          |        |');
      expect(grids[1].chords.map((c) => c.text), ['C', 'G/B', 'Am7', 'F']);
      expect(grids[1].chords.map((c) => c.offset), [2, 6, 12, 18]);
      expect(grids[2].text, '|: % / N.C. :|');
      final shifted = transformer.transpose(chart, semitones: 2);
      expect(chords(shifted).take(4), ['D', 'A/C#', 'Bm7', 'G']);
      expect(
          lines(shifted)
              .where((l) => l.kind == ChartLineKind.chords)
              .first
              .text,
          grids[0].text);
    });

    test('tablature is opaque, not interpreted as chord symbols', () {
      final chart = parser.parse('{sot}\nE|---0---[C]---|\n{eot}\n[C]Words');
      final tab =
          lines(chart).firstWhere((l) => l.kind == ChartLineKind.tablature);
      expect(tab.chords, isEmpty);
      expect(tab.text, 'E|---0---[C]---|');
      expect(chords(chart), ['C']);
    });

    test('malformed and unknown tokens are safe and retained', () {
      for (final source in [
        '',
        '[',
        ']',
        '{section:',
        '{broken}',
        '[H7]Words [C',
        '[[G]word',
        '{}',
        'text {custom: x}',
        '[N.C.]Stop'
      ]) {
        final chart = parser.parse(source);
        expect(chart.source, source);
        expect(
            () => transformer.transpose(chart, semitones: -3), returnsNormally);
      }
      final chart = parser.parse('[H7]Words [N.C.]stop [C]now');
      expect(lines(chart).single.text, 'Words stop now');
      expect(chords(transformer.transpose(chart, semitones: 2)),
          ['H7', 'N.C.', 'D']);
      expect(lines(parser.parse('A beautiful morning')).single.kind,
          ChartLineKind.lyrics);
    });
  });

  group('transposition', () {
    test('root, slash bass, quality and extensions survive transposition', () {
      const cases = {
        'Cmaj7/E': 'Dmaj7/F#',
        'CmMaj7': 'DmMaj7',
        'C7alt': 'D7alt',
        'Am7': 'Bm7',
        'F#sus4': 'G#sus4',
        'Bbdim7': 'Cdim7',
        'Gaug': 'Aaug',
        'C7(b9,#11)': 'D7(b9,#11)',
        'Cm(maj7)': 'Dm(maj7)',
        'C6/9': 'D6/9',
        'Cø7': 'Dø7',
        'C+': 'D+',
      };
      for (final entry in cases.entries) {
        final chart = parser.parse('[${entry.key}]word');
        expect(
            chords(transformer.transpose(chart, semitones: 2)), [entry.value],
            reason: entry.key);
      }
    });

    test('target major/minor keys and enharmonic scale spelling', () {
      final major = parser.parse('{key: C}\n[C]a [F]b [G/B]c [B]d');
      expect(chords(transformer.transpose(major, targetKey: 'Db')),
          ['Db', 'Gb', 'Ab/C', 'C']);
      expect(chords(transformer.transpose(major, targetKey: 'F#')),
          ['F#', 'B', 'C#/E#', 'E#']);
      final minor = parser.parse('{key: Am}\n[Am]a [Dm]b [E7/G#]c [F]d');
      final result = transformer.transpose(minor, targetKey: 'Cm');
      expect(result.key!.name, 'Cm');
      expect(chords(result), ['Cm', 'Fm', 'G7/B', 'Ab']);
      expect(chords(transformer.transpose(major, targetKey: 'Cb')).first, 'Cb');
    });

    test('negative, octave and large offsets never mutate canonical chart', () {
      const source = '{key: C}\n{section: Verse}\n[Cmaj7]Stay [G/B]here';
      final chart = parser.parse(source);
      final down = transformer.transpose(chart, semitones: -2);
      expect(chords(down), ['Bbmaj7', 'F/A']);
      expect(down.source, source);
      expect(down.metadata['key'], ['C']);
      expect(down.sections.map((s) => s.id), chart.sections.map((s) => s.id));
      expect(lines(down).last.text, 'Stay here');
      expect(lines(down).last.chords.map((c) => c.offset), [0, 5]);
      expect(chords(chart), ['Cmaj7', 'G/B']);
      expect(
          chords(transformer.transpose(chart, semitones: 24)), chords(chart));
      expect(chords(transformer.transpose(chart, semitones: 26)),
          ['Dmaj7', 'A/C#']);
    });

    test('identity transposition preserves borrowed chord spellings', () {
      final chart = parser.parse('{key: C}\n[Eb]a [Db]b [G/B]c');
      final same = transformer.transpose(chart, targetKey: 'C');
      expect(chords(same), ['Eb', 'Db', 'G/B']);
      expect(
          displayedChords(transformer.display(
              same, const ChartSettings(useNashville: true))),
          ['b3', 'b2', '5/7']);
      final enharmonic = transformer.transpose(
          parser.parse('{key: C#}\n[C#]a [G#/B#]b'),
          targetKey: 'Db');
      expect(chords(enharmonic), ['Db', 'Ab/C']);
    });

    test('invalid key requests fail explicitly instead of guessing', () {
      final chart = parser.parse('[C]word');
      expect(() => transformer.transpose(chart, targetKey: 'D'),
          throwsArgumentError);
      expect(() => transformer.transpose(chart, targetKey: 'H'),
          throwsArgumentError);
      expect(
          () => transformer.transpose(chart, sourceKey: 'C', targetKey: 'Dm'),
          throwsArgumentError);
      expect(
          () => transformer.transpose(chart,
              sourceKey: 'C', targetKey: 'D', semitones: 2),
          throwsArgumentError);
      expect(
          chords(transformer.transpose(chart, sourceKey: 'C', targetKey: 'D')),
          ['D']);
    });
  });

  group('display / Nashville', () {
    test('major degrees, accidentals, extensions and slash bass', () {
      final chart = parser
          .parse('{key: C}\n[C]a [Dm7]b [Ebmaj7]c [F#dim]d [G7/B]e [Bb]f');
      final result =
          transformer.display(chart, const ChartSettings(useNashville: true));
      expect(displayedChords(result),
          ['1', '2m7', 'b3maj7', '#4dim', '57/7', 'b7']);
      expect(result.sections.last.lines.last.lyrics, 'a b c d e f');
      expect(result.sections.last.lines.last.chords.map((c) => c.offset),
          [0, 2, 4, 6, 8, 10]);
    });

    test('natural minor tonic convention and chromatic alterations', () {
      final chart =
          parser.parse('{key: Am}\n[Am]a [C]b [Dm]c [E7/G#]d [F]e [Bb]f');
      expect(
          displayedChords(transformer.display(
              chart, const ChartSettings(useNashville: true))),
          ['1m', '3', '4m', '57/#7', '6', 'b2']);
      expect(
          displayedChords(transformer.display(
              transformer.transpose(chart, targetKey: 'Cm'),
              const ChartSettings(useNashville: true))),
          ['1m', '3', '4m', '57/#7', '6', 'b2']);
    });

    test('all modes preserve structure/anchors and keep layout separate', () {
      final chart = parser
          .parse('{key: C}\n{section: Intro}\n| C G |\n\n[C]Hello [G]world');
      for (final mode in ChartDisplayMode.values) {
        for (final numbers in [false, true]) {
          final display = transformer.display(
              chart, ChartSettings(displayMode: mode, useNashville: numbers));
          expect(display.sections.map((s) => s.id),
              chart.sections.map((s) => s.id));
          final output = display.sections.expand((s) => s.lines).toList();
          expect(output.length, lines(chart).length);
          if (mode == ChartDisplayMode.lyricsOnly) {
            expect(displayedChords(display), isEmpty);
            expect(output.every((l) => l.layout == null), isTrue);
          } else {
            expect(displayedChords(display),
                numbers ? ['1', '5', '1', '5'] : ['C', 'G', 'C', 'G']);
            expect(output.last.chords.map((c) => c.offset), [0, 6]);
          }
          expect(output.last.lyrics,
              mode == ChartDisplayMode.chordsOnly ? null : 'Hello world');
          expect(output[1].original.directive, isNotNull);
        }
      }
      expect(
          () => transformer.display(
              parser.parse('[C]a'), const ChartSettings(useNashville: true)),
          throwsArgumentError);
    });
  });

  test(
      'every existing mock arrangement parses and prepares without source edits',
      () {
    for (final song in mockSongs) {
      for (final arrangement in song.arrangements) {
        final chart = parser.parse(arrangement.chordProSource);
        expect(chart.metadata['title']!.single, song.title);
        expect(chart.sections.where((s) => s.label.startsWith('Verse')),
            isNotEmpty);
        expect(
            lines(chart).expand((l) => l.chords).every((c) => c.symbol != null),
            isTrue);
        for (final numbers in [false, true]) {
          final output = transformer.prepare(
              song: song,
              arrangement: arrangement,
              settings: ChartSettings(useNashville: numbers));
          expect(displayedChords(output), isNotEmpty);
          expect(output.document.source, arrangement.chordProSource);
        }
      }
    }
    for (final setlist in mockSetlists) {
      for (final item in [...setlist.publishedItems, ...?setlist.draftItems]) {
        final song = mockSongs.firstWhere((s) => s.id == item.songId);
        final arrangement =
            song.arrangements.firstWhere((a) => a.id == item.arrangementId);
        final output = transformer.prepare(
            song: song,
            arrangement: arrangement,
            item: item,
            settings: const ChartSettings());
        expect(output.document.key!.name, item.performanceKey);
      }
    }
    expect(
        () => transformer.prepare(
            song: mockSongs[0],
            arrangement: mockSongs[1].primaryArrangement,
            settings: const ChartSettings()),
        throwsArgumentError);
  });

  test('malformed suffixes and source comments remain opaque', () {
    expect(ChordSymbol.tryParse('C(maj7'), isNull);
    expect(ChordSymbol.tryParse('C7)'), isNull);
    expect(ChordSymbol.tryParse('C/'), isNull);
    final chart = parser.parse('# comment [C]\n[C(maj7]word');
    final changed = transformer.transpose(chart, semitones: 2);
    expect(lines(changed).first.directive!.kind, DirectiveKind.comment);
    expect(lines(changed).first.chords, isEmpty);
    expect(chords(changed), ['C(maj7']);
  });

  test('supported note spellings and invalid chord labels', () {
    expect(NoteName.tryParse('F♯')!.pitch, 6);
    expect(NoteName.tryParse('B♭')!.pitch, 10);
    expect(ChordSymbol.tryParse('not-a-chord'), isNull);
    expect(ChordSymbol.tryParse('H7'), isNull);
    expect(MusicalKey.tryParse('F# minor')!.name, 'F#m');
  });
}
