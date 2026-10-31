import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/models/chart_document.dart';
import 'package:worship_flow/features/charts/widgets/anchored_lyric_line.dart';

DisplayChartLine parse(String source, {String? targetKey}) {
  final parsed = const ChordProParser().parse(source);
  final chart = targetKey == null
      ? parsed
      : const ChartTransformer().transpose(parsed, targetKey: targetKey);
  return const ChartTransformer()
      .display(chart, const ChartSettings())
      .sections
      .expand((s) => s.lines)
      .singleWhere((l) => l.original.kind == ChartLineKind.lyrics);
}

Future<void> showLine(
  WidgetTester tester,
  DisplayChartLine line, {
  double width = 700,
  double lyricSize = 18,
  double chordSize = 20,
  double scale = 1,
}) async {
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
        body: SingleChildScrollView(
            child: SizedBox(
                width: width,
                child: AnchoredLyricLine(
                    line: line,
                    lyricStyle: TextStyle(fontSize: lyricSize, height: 1.4),
                    chordStyle: TextStyle(fontSize: chordSize, height: 1.3))))),
  )));
  await tester.pumpAndSettle();
}

Rect chord(WidgetTester tester, DisplayChartLine line, int index) => tester
    .getRect(find.byKey(ValueKey('chord-${line.original.sourceLine}-$index')));
Rect lyric(WidgetTester tester, DisplayChartLine line, int offset) => tester
    .getRect(find.byKey(ValueKey('lyric-${line.original.sourceLine}-$offset')));
void aligned(WidgetTester tester, DisplayChartLine line) {
  for (var i = 0; i < line.chords.length; i++) {
    expect(chord(tester, line, i).left,
        closeTo(lyric(tester, line, line.chords[i].offset).left, .01));
    expect(chord(tester, line, i).bottom,
        lessThanOrEqualTo(lyric(tester, line, line.chords[i].offset).top));
  }
}

void main() {
  testWidgets(
      'adjacent distinct anchors use minimum measured expansion on one row',
      (tester) async {
    final line = parse('[Cmaj7]a[D/F#]b[G]c');
    await showLine(tester, line);
    final first = chord(tester, line, 0);
    final second = chord(tester, line, 1);
    final third = chord(tester, line, 2);
    expect(second.left, closeTo(first.right + 10, .1));
    expect(third.left, closeTo(second.right + 10, .1));
    expect(second.top, first.top);
    expect(third.top, first.top);
    aligned(tester, line);
    expect(line.lyrics, 'abc');
    expect(line.original.source, '[Cmaj7]a[D/F#]b[G]c');
    expect(line.chords.map((c) => c.offset), [0, 1, 2]);
  });

  testWidgets(
      'mid-word spacing moves the syllable and all subsequent lyric segments',
      (tester) async {
    final line = parse('[Cmaj7]glo[G/B]ry [D]end');
    await showLine(tester, line);
    final start = lyric(tester, line, 0);
    final syllable = lyric(tester, line, 3);
    expect(syllable.left, greaterThan(start.right));
    expect(syllable.left, closeTo(chord(tester, line, 0).right + 10, .1));
    expect(lyric(tester, line, 6).left, greaterThan(syllable.right));
    expect(chord(tester, line, 2).top, chord(tester, line, 0).top);
    aligned(tester, line);
    expect(line.lyrics, 'glory end');
  });

  testWidgets(
      'long slash chords and unequal font sizes stay on one row when they fit',
      (tester) async {
    final line = parse('[Cmaj7/G#]Hel[D7sus4/F#]lo [G]friend');
    await showLine(tester, line, lyricSize: 14, chordSize: 26, width: 780);
    for (var i = 1; i < line.chords.length; i++) {
      expect(chord(tester, line, i).top, chord(tester, line, 0).top);
      expect(
          chord(tester, line, i).overlaps(chord(tester, line, i - 1)), isFalse);
    }
    aligned(tester, line);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflow wraps whole words before splitting syllables',
      (tester) async {
    final line = parse('[Cmaj7]Hello [D/F#]world');
    await showLine(tester, line, width: 180, chordSize: 24);
    expect(chord(tester, line, 1).top,
        greaterThanOrEqualTo(lyric(tester, line, 0).bottom));
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);
    aligned(tester, line);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'oversized words wrap at anchors and graphemes without changing lyric text',
      (tester) async {
    final line = parse('[Cmaj7]Super[G/B]califragilistic');
    await showLine(tester, line, width: 160);
    expect(chord(tester, line, 1).top, greaterThan(chord(tester, line, 0).top));
    aligned(tester, line);
    final parts = tester.widgetList<Text>(find.byWidgetPredicate((w) =>
        w is Text &&
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('lyric-')));
    expect(parts.map((t) => t.data).join(), line.lyrics);
    final bounds = tester.getRect(find.byType(AnchoredLyricLine));
    for (final text in parts) {
      expect(tester.getRect(find.byKey(text.key!)).right,
          lessThanOrEqualTo(bounds.right + .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'font size, system scaling and width changes remeasure expansion and alignment',
      (tester) async {
    final line = parse('[Cmaj7]a[D/F#]b[G]c');
    await showLine(tester, line, chordSize: 14);
    final before = chord(tester, line, 1).left;
    await showLine(tester, line, lyricSize: 24, chordSize: 32);
    expect(chord(tester, line, 1).left, greaterThan(before));
    aligned(tester, line);
    await showLine(tester, line,
        width: 190, lyricSize: 24, chordSize: 32, scale: 1.5);
    aligned(tester, line);
    final bounds = tester.getRect(find.byType(AnchoredLyricLine));
    for (var i = 0; i < line.chords.length; i++) {
      expect(
          chord(tester, line, i).right, lessThanOrEqualTo(bounds.right + .1));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'transposition remeasures longer symbols without moving canonical anchors',
      (tester) async {
    const source = '{key: C}\n[C]a[G/B]b';
    final initial = parse(source);
    final changed = parse(source, targetKey: 'F#');
    await showLine(tester, initial);
    final before = chord(tester, initial, 1).left;
    await showLine(tester, changed);
    expect(chord(tester, changed, 1).left, greaterThan(before));
    expect(find.text('C#/E#'), findsOneWidget);
    aligned(tester, changed);
    expect(changed.lyrics, initial.lyrics);
    expect(changed.chords.map((c) => c.offset),
        initial.chords.map((c) => c.offset));
    expect(changed.original.source, initial.original.source);
  });
}
