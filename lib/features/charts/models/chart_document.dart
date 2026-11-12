import 'chord_symbol.dart';

enum ChartLineKind { blank, lyrics, chords, directive, tablature }

enum DirectiveKind {
  metadata,
  sectionStart,
  sectionEnd,
  comment,
  layout,
  unknown
}

class ChartDirective {
  const ChartDirective(this.name, this.value, this.kind);
  final String name;
  final String value;
  final DirectiveKind kind;
}

class AnchoredChord {
  const AnchoredChord(
      {required this.text,
      required this.offset,
      required this.sourceOffset,
      this.symbol});
  final String text;

  /// UTF-16 offset in lyric text (or original grid column), never chord width.
  final int offset;
  final int sourceOffset;
  final ChordSymbol? symbol;

  AnchoredChord withSymbol(ChordSymbol value) => AnchoredChord(
      text: value.name,
      offset: offset,
      sourceOffset: sourceOffset,
      symbol: value);
}

class ChartLine {
  ChartLine(
      {required this.source,
      required this.sourceLine,
      required this.kind,
      required this.text,
      Iterable<AnchoredChord> chords = const [],
      this.directive})
      : chords = List.unmodifiable(chords);
  final String source;
  final int sourceLine;
  final ChartLineKind kind;

  /// Lyrics with bracket markers removed, or spacing/separators for grids.
  final String text;
  final List<AnchoredChord> chords;
  final ChartDirective? directive;
}

class ChartSection {
  ChartSection(
      {required this.id,
      required this.label,
      required Iterable<ChartLine> lines})
      : lines = List.unmodifiable(lines);

  /// Deterministic source-line identity; repeated labels have distinct IDs.
  final String id;
  final String label;
  final List<ChartLine> lines;
}

class ChartDocument {
  ChartDocument(
      {required this.source,
      required Iterable<ChartSection> sections,
      required Map<String, List<String>> metadata,
      this.key,
      Iterable<TimingGrid> grids = const [],
      Iterable<String> warnings = const []})
      : grids = List.unmodifiable(grids),
        warnings = List.unmodifiable(warnings),
        sections = List.unmodifiable(sections),
        metadata = Map.unmodifiable(
            metadata.map((k, v) => MapEntry(k, List<String>.unmodifiable(v))));

  /// Canonical input, including its original whitespace and line endings.
  final String source;
  final List<ChartSection> sections;
  final Map<String, List<String>> metadata;

  /// Effective key of this chart value; metadata always describes the source.
  final MusicalKey? key;
  final List<TimingGrid> grids;
  final List<String> warnings;
}

class DisplayChord {
  const DisplayChord(this.text, this.offset);
  final String text;
  final int offset;
}

class DisplayChartLine {
  DisplayChartLine(
      {required this.original,
      this.lyrics,
      this.layout,
      Iterable<DisplayChord> chords = const []})
      : chords = List.unmodifiable(chords);
  final ChartLine original;
  final String? lyrics;

  /// Grid spacing/bar separators, shown only when chords are visible.
  final String? layout;
  final List<DisplayChord> chords;
}

class DisplayChartSection {
  DisplayChartSection(this.id, this.label, Iterable<DisplayChartLine> lines)
      : lines = List.unmodifiable(lines);
  final String id;
  final String label;
  final List<DisplayChartLine> lines;
}

class DisplayChart {
  DisplayChart(this.document, Iterable<DisplayChartSection> sections,
      {Iterable<DisplayTimingGrid> grids = const []})
      : grids = List.unmodifiable(grids),
        sections = List.unmodifiable(sections);
  final ChartDocument document;
  final List<DisplayChartSection> sections;
  final List<DisplayTimingGrid> grids;
}

/// Each slot is one denominator-note beat divided by [TimingGrid.subdivision].
/// A slot with no chord and no sustain is a rest.
/// A sustain has no new chord event. It continues the previous event, including
/// across a bar; no timing is derived from lyric anchors.
class TimingSlot {
  const TimingSlot(this.index, {this.chord, this.sustain = false});
  final int index;
  final AnchoredChord? chord;
  final bool sustain;
}

class TimingMeasure {
  TimingMeasure(
      {required this.source,
      required this.sourceLine,
      required this.openingBar,
      required this.closingBar,
      required Iterable<TimingSlot> slots})
      : slots = List.unmodifiable(slots);
  final String source;
  final int sourceLine;
  final String openingBar;
  final String closingBar;
  final List<TimingSlot> slots;
}

class TimingGrid {
  TimingGrid(
      {required this.sectionId,
      required this.label,
      this.targetSectionId,
      required this.meter,
      required this.subdivision,
      required this.isValid,
      required Iterable<TimingMeasure> measures})
      : measures = List.unmodifiable(measures);
  final String sectionId;
  final String label;
  final String? targetSectionId;
  final String meter;
  final int subdivision;
  final bool isValid;
  final List<TimingMeasure> measures;

  int get slotsPerMeasure => switch (meter) {
        '3/4' => 3 * subdivision,
        '4/4' => 4 * subdivision,
        '6/8' => 6 * subdivision,
        _ => 0,
      };
  double? get slotDurationInWholeNotes =>
      isValid ? 1 / (int.parse(meter.split('/').last) * subdivision) : null;

  TimingGrid mapChords(AnchoredChord Function(AnchoredChord) transform) =>
      TimingGrid(
        sectionId: sectionId,
        label: label,
        targetSectionId: targetSectionId,
        meter: meter,
        subdivision: subdivision,
        isValid: isValid,
        measures: measures.map((measure) => TimingMeasure(
              source: measure.source,
              sourceLine: measure.sourceLine,
              openingBar: measure.openingBar,
              closingBar: measure.closingBar,
              slots: measure.slots.map((slot) => TimingSlot(slot.index,
                  sustain: slot.sustain,
                  chord: slot.chord == null ? null : transform(slot.chord!))),
            )),
      );
}

class DisplayTimingSlot {
  const DisplayTimingSlot(this.original, this.text);
  final TimingSlot original;
  final String text;
}

class DisplayTimingGrid {
  DisplayTimingGrid(this.original, Iterable<List<DisplayTimingSlot>> measures)
      : measures = List.unmodifiable(
            measures.map((m) => List<DisplayTimingSlot>.unmodifiable(m)));
  final TimingGrid original;
  final List<List<DisplayTimingSlot>> measures;
}
