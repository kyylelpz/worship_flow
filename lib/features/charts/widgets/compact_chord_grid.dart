import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/chart_document.dart';
import 'chord_label.dart';

/// Presentation cells only: an untimed token is not assigned a beat duration.
class CompactMeasure {
  const CompactMeasure(this.cells, {this.opening = '', this.closing = ''});
  final List<String> cells;
  final String opening, closing;
}

class CompactGridRow {
  const CompactGridRow(this.measures, {this.text});
  final List<CompactMeasure> measures;
  final String? text;
}

/// Uses parsed chord source offsets solely to separate labels from written marks.
/// Chord recognition, transposition and notation remain in the engine.
CompactGridRow instrumentalGridRow(DisplayChartLine line) {
  final tokens = <String>[];
  var cursor = 0;
  void marks(String value) {
    tokens.addAll(
        RegExp(r'\|:|:\||\||[^\s|]+').allMatches(value).map((m) => m[0]!));
  }

  for (var i = 0; i < line.chords.length; i++) {
    final start = line.original.chords[i].sourceOffset;
    marks(line.original.source.substring(cursor, start));
    tokens.add(line.chords[i].text);
    final token = RegExp(r'^\[[^\[\]]+\]|^[^\s|:]+')
        .firstMatch(line.original.source.substring(start));
    cursor = start + (token?.end ?? 0);
  }
  marks(line.original.source.substring(cursor));
  final measures = <CompactMeasure>[];
  var cells = <String>[];
  var opening = '';
  for (final token in tokens) {
    if (token.contains('|')) {
      if (cells.isNotEmpty) {
        measures.add(CompactMeasure(cells, opening: opening, closing: token));
        cells = [];
      }
      opening = token;
    } else {
      cells.add(token);
    }
  }
  if (cells.isNotEmpty) measures.add(CompactMeasure(cells, opening: opening));
  return CompactGridRow(measures);
}

List<CompactGridRow> timingGridRows(DisplayTimingGrid grid,
    {Iterable<ChartLine> sourceLines = const []}) {
  final blankLines = sourceLines
      .where((l) => l.kind == ChartLineKind.blank)
      .map((l) => l.sourceLine)
      .toList();
  final rows = <CompactGridRow>[];
  var measures = <CompactMeasure>[];
  int? sourceLine;
  for (var i = 0; i < grid.measures.length; i++) {
    final original = grid.original.measures[i];
    if (sourceLine != null && sourceLine != original.sourceLine) {
      rows.add(CompactGridRow(measures));
      // Use actual blank rows, not gaps caused by intervening directives.
      for (final line in blankLines) {
        if (line > sourceLine && line < original.sourceLine) {
          rows.add(const CompactGridRow([], text: ''));
        }
      }
      measures = [];
    }
    sourceLine = original.sourceLine;
    measures.add(CompactMeasure(grid.measures[i].map((s) => s.text).toList(),
        opening: original.openingBar, closing: original.closingBar));
  }
  if (measures.isNotEmpty) rows.add(CompactGridRow(measures));
  return rows;
}

/// Measures size their own beat cells while sharing a chord baseline.
class CompactChordGrid extends StatelessWidget {
  const CompactChordGrid({super.key, required this.rows, required this.style});
  final List<CompactGridRow> rows;
  final TextStyle style;
  @override
  Widget build(BuildContext context) {
    final font = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final measures = rows.expand((r) => r.measures).toList();
    if (measures.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final row in rows)
          if (row.text != null) Text(row.text!, style: font),
      ]);
    }
    final fontSize = scaler.scale(font.fontSize ?? 16);
    final gap = fontSize * .10;
    final minimumBeatWidth = fontSize * .55;
    final blankLineHeight = fontSize * .45;
    var ascent = 0.0, descent = 0.0;
    final barStyle = font.copyWith(
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurfaceVariant);
    double paddedWidth(String text, TextStyle style) {
      if (text.isEmpty) return 0;
      final size = ChordLabel.measure(text, style, scaler);
      ascent = math.max(ascent, size.baseline);
      descent = math.max(descent, size.height - size.baseline);
      return size.width + 2 * gap;
    }

    final barWidths = <String, double>{};
    final layouts = <CompactMeasure, ({List<double> cells, double width})>{};
    for (final measure in measures) {
      final opening = barWidths.putIfAbsent(
          measure.opening, () => paddedWidth(measure.opening, barStyle));
      barWidths.putIfAbsent(
          measure.closing, () => paddedWidth(measure.closing, barStyle));
      final cells = [
        for (final text in measure.cells)
          math.max(minimumBeatWidth, paddedWidth(text, font)),
      ];
      layouts[measure] = (
        cells: cells,
        width: cells.fold<double>(opening, (sum, width) => sum + width),
      );
    }
    final rowHeight = ascent + descent;
    Widget label(String text, double width, TextStyle style, Key key) {
      if (text.isEmpty) {
        return SizedBox(key: key, width: width, height: rowHeight);
      }
      final size = ChordLabel.measure(text, style, scaler);
      return SizedBox(
          key: key,
          width: width,
          height: rowHeight,
          child: Padding(
              padding: EdgeInsets.only(left: gap, top: ascent - size.baseline),
              child: Align(
                  alignment: Alignment.topLeft,
                  child: ChordLabel(text, style: style))));
    }

    return LayoutBuilder(builder: (context, box) {
      final children = <Widget>[];
      var index = 0;
      for (final sourceRow in rows) {
        if (sourceRow.measures.isEmpty && sourceRow.text?.trim() == '') {
          // A presentation boundary only: never a measure, slot or rest.
          children.add(SizedBox(height: blankLineHeight));
          continue;
        }
        if (sourceRow.text != null) {
          children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(sourceRow.text!, style: font)));
        }
        for (var start = 0; start < sourceRow.measures.length;) {
          var end = start;
          var width = 0.0;
          var closingWidth = 0.0;
          while (end < sourceRow.measures.length) {
            final measure = sourceRow.measures[end];
            final nextWidth = width + layouts[measure]!.width;
            final nextClosingWidth = barWidths[measure.closing]!;
            final fits = nextWidth + nextClosingWidth <= box.maxWidth;
            if (!fits && end > start) break;
            width = nextWidth;
            closingWidth = nextClosingWidth;
            end++;
            if (!fits) break;
          }
          final cells = <Widget>[];
          for (var i = start; i < end; i++) {
            final measure = sourceRow.measures[i];
            final m = index++;
            final layout = layouts[measure]!;
            cells.add(SizedBox(
                key: ValueKey('compact-measure-$m'),
                width: layout.width,
                child: Row(children: [
                  label(measure.opening, barWidths[measure.opening]!, barStyle,
                      ValueKey('grid-bar-$m-open')),
                  for (var c = 0; c < measure.cells.length; c++)
                    label(measure.cells[c], layout.cells[c], font,
                        ValueKey('grid-cell-$m-$c')),
                ])));
            if (i == end - 1) {
              cells.add(label(measure.closing, closingWidth, barStyle,
                  ValueKey('grid-bar-$m-close')));
            }
          }
          final row = Padding(
              padding: EdgeInsets.symmetric(vertical: fontSize * .05),
              child: Row(mainAxisSize: MainAxisSize.min, children: cells));
          // A single measure can exceed the viewport at large text scales or
          // with dense subdivisions. Only that unavoidable case scrolls sideways.
          children.add(width + closingWidth > box.maxWidth
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: row)
              : row);
          start = end;
        }
      }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children);
    });
  }
}
