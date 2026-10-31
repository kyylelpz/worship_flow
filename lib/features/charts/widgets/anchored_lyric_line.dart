import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/chart_document.dart';

/// Display-only spacing moves a lyric segment and its anchors together.
/// Words wrap before syllables/graphemes; only coincident anchors need lanes.
class AnchoredLyricLine extends StatelessWidget {
  const AnchoredLyricLine(
      {super.key,
      required this.line,
      required this.lyricStyle,
      required this.chordStyle});
  final DisplayChartLine line;
  final TextStyle lyricStyle;
  final TextStyle chordStyle;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final lyrics = line.lyrics ?? '';
        final lyricFont = DefaultTextStyle.of(context).style.merge(lyricStyle);
        final chordFont = DefaultTextStyle.of(context).style.merge(chordStyle);
        final scaler = MediaQuery.textScalerOf(context);
        final width = math.max(1.0, constraints.maxWidth);
        final effectiveChordSize = scaler.scale(chordFont.fontSize ?? 16.0);

        final chordGap = math.max(8.0, effectiveChordSize * 0.5);

        _Metrics measure(String value, TextStyle style,
            {double maxWidth = double.infinity}) {
          final painter = TextPainter(
              text: TextSpan(text: value, style: style),
              textDirection: TextDirection.ltr,
              textScaler: scaler)
            ..layout(maxWidth: maxWidth);
          final metrics = painter.computeLineMetrics();
          final result = _Metrics(painter.width, painter.height,
              metrics.isEmpty ? painter.height : metrics.first.baseline);
          painter.dispose();
          return result;
        }

        final labels = <int, List<_Chord>>{};
        for (var i = 0; i < line.chords.length; i++) {
          final chord = line.chords[i];
          final offset = chord.offset.clamp(0, lyrics.length);
          labels.putIfAbsent(offset, () => []).add(_Chord(
              chord.text, i, measure(chord.text, chordFont, maxWidth: width)));
        }
        final rows = <_Row>[];
        var row = _Row();
        void wrap() {
          if (row.parts.isNotEmpty || row.labels.isNotEmpty) rows.add(row);
          row = _Row();
        }

        _Row plan(_Row original, List<_Part> parts) {
          final result = original.copy();
          for (final part in parts) {
            var x = result.cursor;
            if (part.chords.isNotEmpty && result.chordRight != null) {
              // Maintain at least 12 logical pixels between adjacent chord labels.
              x = math.max(x, result.chordRight! + chordGap);
            }
            result.parts.add(_PlacedPart(part, x));
            result.cursor = x + part.metrics.width;
            result.baseline = math.max(result.baseline, part.metrics.baseline);
            result.descent = math.max(
                result.descent, part.metrics.height - part.metrics.baseline);
            for (var lane = 0; lane < part.chords.length; lane++) {
              final chord = part.chords[lane];
              result.labels.add(_PlacedChord(chord, x, lane));
              result.chordRight =
                  math.max(result.chordRight ?? 0, x + chord.metrics.width);
            }
          }
          return result;
        }

        _Part part(String text, int offset, List<_Chord> chords) =>
            _Part(text, offset, chords, measure(text, lyricFont));

        void placeWord(List<_Part> parts) {
          var candidate = plan(row, parts);
          if (candidate.width <= width) {
            row = candidate;
            return;
          }
          if (row.parts.isNotEmpty || row.labels.isNotEmpty) wrap();
          candidate = plan(row, parts);
          if (candidate.width <= width) {
            row = candidate;
            return;
          }
          // An expanded word wider than the viewport first splits at chord anchors.
          // A single oversized syllable then splits only at grapheme boundaries.
          for (final original in parts) {
            var remaining = original;
            while (true) {
              candidate = plan(row, [remaining]);
              if (candidate.width <= width) {
                row = candidate;
                break;
              }
              if (row.parts.isNotEmpty || row.labels.isNotEmpty) {
                wrap();
                continue;
              }
              final graphemes = remaining.text.characters.toList();
              if (graphemes.length <= 1) {
                row = candidate;
                break;
              }
              var prefix = '';
              var chosen = '';
              for (final grapheme in graphemes) {
                prefix += grapheme;
                if (plan(row, [
                      part(prefix, remaining.offset, remaining.chords)
                    ]).width >
                    width) {
                  break;
                }
                chosen = prefix;
              }
              // Progress even when an individual glyph is wider than the viewport.
              if (chosen.isEmpty) chosen = graphemes.first;
              row =
                  plan(row, [part(chosen, remaining.offset, remaining.chords)]);
              wrap();
              remaining = part(remaining.text.substring(chosen.length),
                  remaining.offset + chosen.length, const []);
            }
          }
        }

        // These are source substrings, never padded strings. Added spacing exists
        // only in the x coordinates of placed segments.
        for (final word in RegExp(r'\s+|\S+').allMatches(lyrics)) {
          final boundaries = {
            word.start,
            word.end,
            ...labels.keys
                .where((offset) => offset > word.start && offset < word.end)
          }.toList()
            ..sort();
          final parts = [
            for (var i = 0; i + 1 < boundaries.length; i++)
              part(lyrics.substring(boundaries[i], boundaries[i + 1]),
                  boundaries[i], labels[boundaries[i]] ?? const [])
          ];
          if (word[0]!.trim().isEmpty && parts.every((p) => p.chords.isEmpty)) {
            final candidate = plan(row, parts);
            if (candidate.width <= width) {
              row = candidate;
            } else {
              wrap();
            } // Ordinary soft wrapping consumes inter-word whitespace.
          } else {
            placeWord(parts);
          }
        }
        if (labels.containsKey(lyrics.length)) {
          placeWord([part('', lyrics.length, labels[lyrics.length]!)]);
        }
        wrap();
        if (rows.isEmpty) rows.add(plan(_Row(), [part('', 0, const [])]));
        var height = 0.0;
        for (final current in rows) {
          final lanes = <double>[];
          for (final label in current.labels) {
            while (lanes.length <= label.lane) {
              lanes.add(0);
            }
            lanes[label.lane] =
                math.max(lanes[label.lane], label.chord.metrics.height);
          }
          final tops = <double>[];
          for (final laneHeight in lanes) {
            tops.add(height);
            height += laneHeight + 3;
          }
          for (final label in current.labels) {
            label.y = tops[label.lane];
          }
          current.lyricY = height + (lanes.isEmpty ? 0 : 3);
          height = current.lyricY + current.baseline + current.descent;
        }
        return Semantics(
            label: lyrics,
            child: SizedBox(
                width: width,
                height: height,
                child: Stack(clipBehavior: Clip.none, children: [
                  for (final current in rows) ...[
                    for (final placed in current.parts)
                      Positioned(
                          left: placed.x,
                          top: current.lyricY +
                              current.baseline -
                              placed.part.metrics.baseline,
                          child: ExcludeSemantics(
                              child: Text(placed.part.text,
                                  key: ValueKey(
                                      'lyric-${line.original.sourceLine}-${placed.part.offset}'),
                                  style: lyricFont,
                                  softWrap: false,
                                  textDirection: TextDirection.ltr))),
                    for (final placed in current.labels)
                      Positioned(
                          left: placed.x,
                          top: placed.y,
                          width: width - placed.x,
                          child: Align(
                              alignment: Alignment.topLeft,
                              child: Text(placed.chord.text,
                                  key: ValueKey(
                                      'chord-${line.original.sourceLine}-${placed.chord.index}'),
                                  style: chordFont,
                                  textDirection: TextDirection.ltr))),
                  ],
                ])));
      });
}

class _Metrics {
  const _Metrics(this.width, this.height, this.baseline);
  final double width, height, baseline;
}

class _Chord {
  const _Chord(this.text, this.index, this.metrics);
  final String text;
  final int index;
  final _Metrics metrics;
}

class _Part {
  const _Part(this.text, this.offset, this.chords, this.metrics);
  final String text;
  final int offset;
  final List<_Chord> chords;
  final _Metrics metrics;
}

class _PlacedPart {
  const _PlacedPart(this.part, this.x);
  final _Part part;
  final double x;
}

class _PlacedChord {
  _PlacedChord(this.chord, this.x, this.lane);
  final _Chord chord;
  final double x;
  final int lane;
  double y = 0;
}

class _Row {
  final List<_PlacedPart> parts = [];
  final List<_PlacedChord> labels = [];
  double cursor = 0, baseline = 0, descent = 0, lyricY = 0;
  double? chordRight;
  double get width => math.max(cursor, chordRight ?? 0);
  _Row copy() => _Row()
    ..parts.addAll(parts)
    ..labels.addAll(labels)
    ..cursor = cursor
    ..baseline = baseline
    ..descent = descent
    ..chordRight = chordRight;
}
