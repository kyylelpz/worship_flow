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
      this.key})
      : sections = List.unmodifiable(sections),
        metadata = Map.unmodifiable(
            metadata.map((k, v) => MapEntry(k, List<String>.unmodifiable(v))));

  /// Canonical input, including its original whitespace and line endings.
  final String source;
  final List<ChartSection> sections;
  final Map<String, List<String>> metadata;

  /// Effective key of this chart value; metadata always describes the source.
  final MusicalKey? key;
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
  DisplayChart(this.document, Iterable<DisplayChartSection> sections)
      : sections = List.unmodifiable(sections);
  final ChartDocument document;
  final List<DisplayChartSection> sections;
}
