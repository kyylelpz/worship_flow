import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/chord_symbol.dart';

/// Presentation-only chord typography. Measurements and rendering share exactly
/// the same run layout, including raised ascent, wrapping and system text scale.
class ChordLabel extends StatelessWidget {
  const ChordLabel(this.text,
      {super.key, required this.style, this.textAlign = TextAlign.left});
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  static ({double width, double height, double baseline}) measure(
      String text, TextStyle style, TextScaler scaler,
      {double maxWidth = double.infinity}) {
    final layout = _layout(text, style, scaler, maxWidth);
    return (
      width: layout.width,
      height: layout.height,
      baseline: layout.baseline
    );
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final font = DefaultTextStyle.of(context).style.merge(style);
        final layout = _layout(
            text, font, MediaQuery.textScalerOf(context), constraints.maxWidth,
            align: textAlign);
        return Semantics(
            label: text,
            child: ExcludeSemantics(
                child: SizedBox(
              width: layout.width,
              height: layout.height,
              child: Stack(clipBehavior: Clip.none, children: [
                for (final run in layout.runs)
                  Positioned(
                      left: run.x,
                      top: run.y,
                      child: Text(run.text,
                          style: run.style,
                          softWrap: false,
                          textDirection: TextDirection.ltr)),
              ]),
            )));
      });
}

List<({String text, bool raised})> _format(String text) {
  final root =
      RegExp(r'^(?:[A-G][#b♯♭]{0,2}|[#b♯♭]{0,2}[1-7])').firstMatch(text);
  if (root == null) return [(text: text, raised: false)];
  final bass =
      RegExp(r'/(?:[A-G][#b♯♭]{0,2}|[#b♯♭]{0,2}[1-7])$').firstMatch(text);
  final suffixEnd = bass?.start ?? text.length;
  final suffix = text.substring(root.end, suffixEnd);
  // Reuse the engine's suffix vocabulary without interpreting numeric roots or
  // changing semantics. Unknown/malformed labels remain plain text.
  if (ChordSymbol.tryParse('C$suffix') == null) {
    return [(text: text, raised: false)];
  }
  final result = <({String text, bool raised})>[];
  var start = 0;
  for (final number in RegExp(r'\d+').allMatches(suffix)) {
    if (!const ['7', '9', '11', '13'].contains(number[0])) continue;
    final offset = root.end + number.start;
    if (offset > start) {
      result.add((text: text.substring(start, offset), raised: false));
    }
    result.add((text: number[0]!, raised: true));
    start = root.end + number.end;
  }
  if (start < text.length) {
    result.add((text: text.substring(start), raised: false));
  }
  return result;
}

class _Run {
  _Run(
      this.text, this.style, this.width, this.height, this.baseline, this.rise);
  final String text;
  final TextStyle style;
  final double width, height, baseline, rise;
  double x = 0, y = 0;
}

class _Layout {
  final List<_Run> runs = [];
  final List<List<_Run>> rows = [];
  double width = 0, height = 0, baseline = 0;
}

_Layout _layout(
    String text, TextStyle style, TextScaler scaler, double maxWidth,
    {TextAlign align = TextAlign.left}) {
  final layout = _Layout();
  final width = math.max(1.0, maxWidth);
  final fontSize = style.fontSize ?? 16;
  final rise = scaler.scale(fontSize) * .35;
  _Run measure(String value, bool raised) {
    final font = raised ? style.copyWith(fontSize: fontSize * .65) : style;
    final painter = TextPainter(
        text: TextSpan(text: value, style: font),
        textDirection: TextDirection.ltr,
        textScaler: scaler)
      ..layout();
    final metrics = painter.computeLineMetrics();
    final run = _Run(
        value,
        font,
        painter.width,
        painter.height,
        metrics.isEmpty ? painter.height : metrics.first.baseline,
        raised ? rise : 0);
    painter.dispose();
    return run;
  }

  var row = <_Run>[];
  var x = 0.0;
  void flush() {
    if (row.isEmpty) return;
    final ascent =
        row.fold<double>(0, (n, run) => math.max(n, run.baseline + run.rise));
    final descent = row.fold<double>(
        0, (n, run) => math.max(n, run.height - run.baseline - run.rise));
    if (layout.runs.isEmpty) layout.baseline = ascent;
    for (final run in row) {
      run.y = layout.height + ascent - run.baseline - run.rise;
      layout.runs.add(run);
    }
    layout.rows.add(row);
    layout.width = math.max(layout.width, x);
    layout.height += ascent + descent;
    row = [];
    x = 0;
  }

  void add(_Run run) {
    if (x > 0 && x + run.width > width) flush();
    run.x = x;
    x += run.width;
    row.add(run);
  }

  for (final token in _format(text)) {
    final run = measure(token.text, token.raised);
    if (run.width <= width) {
      add(run);
    } else {
      // Oversized labels wrap at graphemes instead of clipping raised glyphs.
      var part = '';
      for (final grapheme in token.text.characters) {
        final next = part + grapheme;
        if (part.isNotEmpty && measure(next, token.raised).width > width) {
          add(measure(part, token.raised));
          part = grapheme;
        } else {
          part = next;
        }
      }
      if (part.isNotEmpty) add(measure(part, token.raised));
    }
  }
  flush();
  for (final line in layout.rows) {
    final rowWidth = line.last.x + line.last.width;
    final extra = layout.width - rowWidth;
    final dx = align == TextAlign.center
        ? extra / 2
        : (align == TextAlign.right || align == TextAlign.end)
            ? extra
            : 0.0;
    for (final run in line) {
      run.x += dx;
    }
  }
  return layout;
}
