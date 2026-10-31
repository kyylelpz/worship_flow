import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/chart_document.dart';

/// Lyrics wrap through Flutter's text shaper. Labels use its caret coordinates;
/// collision lanes add vertical space, never spaces or changed lyric offsets.
class AnchoredLyricLine extends StatelessWidget {
  const AnchoredLyricLine(
      {super.key,
      required this.line,
      required this.lyricStyle,
      required this.chordStyle});
  final DisplayChartLine line;
  final TextStyle lyricStyle;
  final TextStyle chordStyle;

  TextPainter _text(String text, TextStyle style, TextScaler scaler) =>
      TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler);

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final effectiveLyrics =
            DefaultTextStyle.of(context).style.merge(lyricStyle);
        final effectiveChords =
            DefaultTextStyle.of(context).style.merge(chordStyle);
        final width = constraints.maxWidth;
        final scaler = MediaQuery.textScalerOf(context);
        final lyrics = line.lyrics ?? '';
        var widest = 0.0;
        for (final chord in line.chords) {
          final measure = _text(chord.text, effectiveChords, scaler)..layout();
          widest = math.max(widest, measure.width);
          measure.dispose();
        }
        // Reserve a right gutter so labels at soft-wrap boundaries remain visible.
        final lyricWidth = math.max(1.0, width - math.min(widest, width * .5));
        final text = _text(lyrics, effectiveLyrics, scaler)
          ..layout(maxWidth: lyricWidth);
        final metrics = text.computeLineMetrics();
        final rows =
            metrics.map((m) => _Row(m.baseline - m.ascent, m.height)).toList();
        if (rows.isEmpty) {
          rows.add(_Row(0, scaler.scale(effectiveLyrics.fontSize ?? 18)));
        }
        for (var i = 0; i < line.chords.length; i++) {
          final chord = line.chords[i];
          final caret = text.getOffsetForCaret(
              TextPosition(offset: chord.offset.clamp(0, lyrics.length)),
              Rect.zero);
          // Caret dy excludes some leading; comparing against line bottoms can
          // misclassify anchors exactly at a soft wrap. Match the nearest top.
          var rowIndex = 0;
          var nearest = double.infinity;
          for (var r = 0; r < rows.length; r++) {
            final distance = (caret.dy - rows[r].sourceTop).abs();
            if (distance < nearest) {
              nearest = distance;
              rowIndex = r;
            }
          }
          final x = caret.dx.clamp(0.0, math.max(0.0, width - 1)).toDouble();
          final measure = _text(chord.text, effectiveChords, scaler)
            ..layout(maxWidth: width - x);
          final label = _Label(chord.text, x, measure.width, measure.height, i);
          measure.dispose();
          final row = rows[rowIndex];
          var lane = 0;
          while (lane < row.lanes.length &&
              row.lanes[lane].any((other) =>
                  x < other.x + other.width + 6 &&
                  x + label.width + 6 > other.x)) {
            lane++;
          }
          if (lane == row.lanes.length) row.lanes.add([]);
          row.lanes[lane].add(label);
        }
        var height = 0.0;
        for (final row in rows) {
          row.top = height;
          for (final lane in row.lanes) {
            final laneHeight =
                lane.fold<double>(0, (h, l) => math.max(h, l.height));
            for (final label in lane) {
              label.y = height;
            }
            height += laneHeight + 3;
          }
          row.lyricY = height + (row.lanes.isEmpty ? 0 : 3);
          height = row.lyricY + row.height;
        }
        text.dispose();
        return Semantics(
          label: lyrics,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(children: [
              Positioned.fill(
                  child: CustomPaint(
                      painter: _LyricsPainter(
                          lyrics, effectiveLyrics, scaler, lyricWidth, rows))),
              for (final row in rows)
                for (final lane in row.lanes)
                  for (final label in lane)
                    Positioned(
                        left: label.x,
                        top: label.y,
                        width: width - label.x,
                        child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(label.text,
                                key: ValueKey(
                                    'chord-${line.original.sourceLine}-${label.index}'),
                                style: effectiveChords,
                                textDirection: TextDirection.ltr))),
            ]),
          ),
        );
      });
}

class _Label {
  _Label(this.text, this.x, this.width, this.height, this.index);
  final String text;
  final double x, width, height;
  final int index;
  double y = 0;
}

class _Row {
  _Row(this.sourceTop, this.height);
  final double sourceTop, height;
  final List<List<_Label>> lanes = [];
  double top = 0, lyricY = 0;
}

class _LyricsPainter extends CustomPainter {
  _LyricsPainter(this.text, this.style, this.scaler, this.width, this.rows);
  final String text;
  final TextStyle style;
  final TextScaler scaler;
  final double width;
  final List<_Row> rows;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler)
      ..layout(maxWidth: width);
    for (final row in rows) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, row.lyricY, size.width, row.height));
      painter.paint(canvas, Offset(0, row.lyricY - row.sourceTop));
      canvas.restore();
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(_LyricsPainter oldDelegate) => true;
}
