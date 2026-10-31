import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/widgets/chord_label.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'anchored_lyric_line_test.dart' as lyrics;

Future<void> label(WidgetTester tester, String text,
    {double scale = 1, double width = 400}) async {
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: width,
                      child: Align(
                          alignment: Alignment.topLeft,
                          child: ChordLabel(text,
                              style: const TextStyle(
                                  fontSize: 32, height: 1.3)))))))));
  await tester.pumpAndSettle();
}

Finder textPart(String text) =>
    find.descendant(of: find.byType(ChordLabel), matching: find.text(text));
double baseline(WidgetTester tester, Finder finder) {
  final text = tester.widget<Text>(finder);
  final context = tester.element(finder);
  final painter = TextPainter(
      text: TextSpan(
          text: text.data,
          style: DefaultTextStyle.of(context).style.merge(text.style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context))
    ..layout();
  final value = tester.getTopLeft(finder).dy +
      painter.computeLineMetrics().first.baseline;
  painter.dispose();
  return value;
}

void main() {
  for (final (symbol, normal, extension) in [
    ('Bm7', 'Bm', '7'),
    ('Emaj7', 'Emaj', '7'),
    ('F#m9', 'F#m', '9'),
    ('A7sus4', 'A', '7'),
    ('Bm7/F#', 'Bm', '7'),
    ('5m7', '5m', '7'),
  ]) {
    testWidgets(
        '$symbol keeps root/minor baseline and raises only its extension',
        (tester) async {
      await label(tester, symbol);
      final root = textPart(normal);
      final raised = textPart(extension);
      expect(tester.widget<Text>(root).style!.fontSize, 32);
      expect(tester.widget<Text>(raised).style!.fontSize, closeTo(20.8, .01));
      expect(baseline(tester, raised), lessThan(baseline(tester, root)));
      if (symbol == 'Bm7/F#') {
        expect(baseline(tester, textPart('/F#')),
            closeTo(baseline(tester, root), .01));
      }
      if (symbol == 'A7sus4') {
        expect(baseline(tester, textPart('sus4')),
            closeTo(baseline(tester, root), .01));
      }
      final bounds = tester.getRect(find.byType(ChordLabel));
      for (final part in find
          .descendant(of: find.byType(ChordLabel), matching: find.byType(Text))
          .evaluate()) {
        final rect = tester.getRect(find.byWidget(part.widget));
        expect(rect.top, greaterThanOrEqualTo(bounds.top - .01));
        expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + .01));
      }
    });
  }

  testWidgets(
      'altered/add/dim/aug suffixes preserve literal text and accidentals',
      (tester) async {
    for (final symbol in ['Cadd9', 'Bdim7', 'Caug13', 'F#7(b9#11)', 'b37/5']) {
      await label(tester, symbol);
      final parts = tester.widgetList<Text>(find.descendant(
          of: find.byType(ChordLabel), matching: find.byType(Text)));
      expect(parts.map((t) => t.data).join(), symbol);
      for (final part in parts) {
        if (const ['7', '9', '11', '13'].contains(part.data)) {
          expect(part.style!.fontSize, lessThan(32));
        } else {
          expect(part.style!.fontSize, 32);
        }
      }
    }
    for (final symbol in ['b7', '#3', '7', 'G/B', 'N.C.', 'H7']) {
      await label(tester, symbol);
      expect(tester.widget<Text>(textPart(symbol)).style!.fontSize, 32);
    }
  });

  testWidgets(
      'styled measurements match wrapped rendering under accessibility scaling',
      (tester) async {
    await label(tester, 'F#m13/C#', scale: 2, width: 170);
    final context = tester.element(find.byType(ChordLabel));
    final style = DefaultTextStyle.of(context)
        .style
        .merge(const TextStyle(fontSize: 32, height: 1.3));
    final measured = ChordLabel.measure(
        'F#m13/C#', style, const TextScaler.linear(2),
        maxWidth: 170);
    final size = tester.getSize(find.byType(ChordLabel));
    expect(size.width, closeTo(measured.width, .01));
    expect(size.height, closeTo(measured.height, .01));
    expect(size.width, lessThanOrEqualTo(170));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'styled widths drive horizontal expansion while preserving lyric anchors',
      (tester) async {
    final line = lyrics.parse('[Bm7]a[Emaj7]b[F#m9]c[A7sus4]d[Bm7/F#]e');
    await lyrics.showLine(tester, line, width: 780);
    lyrics.aligned(tester, line);
    for (var i = 1; i < line.chords.length; i++) {
      expect(
          lyrics
              .chord(tester, line, i)
              .overlaps(lyrics.chord(tester, line, i - 1)),
          isFalse);
    }
    expect(line.lyrics, 'abcde');
    expect(line.chords.map((c) => c.offset), [0, 1, 2, 3, 4]);
  });

  testWidgets(
      'transposition and Nashville use the shared typography without source edits',
      (tester) async {
    const source = '{key: C}\n[Gm7]a [Bm7/F#]b';
    final document = const ChordProParser().parse(source);
    final transposed =
        const ChartTransformer().transpose(document, targetKey: 'D');
    final chart = const ChartTransformer()
        .display(transposed, const ChartSettings(useNashville: true));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ChordChartView(
                chart: chart,
                settings: const ChartSettings(useNashville: true)))));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<ChordLabel>(find.byType(ChordLabel))
            .any((w) => w.text == '5m7'),
        isTrue);
    expect(chart.document.source, source);
  });

  testWidgets(
      'instrumental sequences and explicit grids share styled labels in both chord modes',
      (tester) async {
    const source = '{key: G}\n{section: Instrumental}\n| Bm7 Emaj7 |\n'
        '{start_of_grid: Intro}\n| F#m9 - A7sus4 - |\n{end_of_grid}';
    final document = const ChordProParser().parse(source);
    for (final mode in [
      ChartDisplayMode.lyricsAndChords,
      ChartDisplayMode.chordsOnly
    ]) {
      final settings = ChartSettings(
          displayMode: mode, chordsFontSize: 24, globalScale: 1.2);
      final chart = const ChartTransformer().display(document, settings);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  child: ChordChartView(chart: chart, settings: settings)))));
      await tester.pumpAndSettle();
      final labels = tester.widgetList<ChordLabel>(find.byType(ChordLabel));
      for (final symbol in ['Bm7', 'Emaj7', 'F#m9', 'A7sus4']) {
        final match =
            find.byWidgetPredicate((w) => w is ChordLabel && w.text == symbol);
        expect(match, findsOneWidget);
        final numbers = tester
            .widgetList<Text>(
                find.descendant(of: match, matching: find.byType(Text)))
            .where((t) => t.data == '7' || t.data == '9');
        expect(numbers, isNotEmpty);
        expect(
            numbers.every((t) =>
                t.style!.fontSize! <
                settings.chordsFontSize * settings.globalScale),
            isTrue);
      }
      expect(labels, isNotEmpty);
      expect(tester.takeException(), isNull);
    }
  });
}
