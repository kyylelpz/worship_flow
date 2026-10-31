import '../../../core/models/arrangement.dart';
import '../../../core/models/chart_settings.dart';
import '../../../core/models/setlist_item.dart';
import '../../../core/models/song.dart';
import '../models/chart_document.dart';
import '../models/chord_symbol.dart';
import 'chordpro_parser.dart';

class ChartTransformer {
  const ChartTransformer();

  /// Unknown chords remain literal. Invalid/ambiguous requested keys are API
  /// errors; malformed source itself is accepted by the parser.
  ChartDocument transpose(
    ChartDocument chart, {
    int semitones = 0,
    String? targetKey,
    String? sourceKey,
  }) {
    final source = sourceKey == null ? chart.key : _key(sourceKey);
    if (targetKey != null && semitones != 0) {
      throw ArgumentError('Choose a semitone offset or target key, not both.');
    }
    final MusicalKey spelling;
    final int offset;
    if (targetKey != null) {
      if (source == null) {
        throw ArgumentError('Target-key transposition requires a source key.');
      }
      spelling = _key(targetKey);
      if (source.isMinor != spelling.isMinor) {
        throw ArgumentError('Transposition cannot change major/minor mode.');
      }
      offset = (spelling.tonic.pitch - source.tonic.pitch) % 12;
    } else {
      offset = semitones % 12;
      if (source == null) {
        spelling = const MusicalKey(NoteName('C', 0));
      } else if (offset == 0) {
        spelling = source;
      } else {
        spelling = source.transposed(offset);
      }
    }
    final unchanged =
        offset == 0 && (targetKey == null || source?.name == spelling.name);
    return ChartDocument(
      source: chart.source,
      metadata: chart.metadata,
      key: source == null && targetKey == null ? null : spelling,
      sections: chart.sections.map((section) => ChartSection(
            id: section.id,
            label: section.label,
            lines: section.lines.map((line) => ChartLine(
                  source: line.source,
                  sourceLine: line.sourceLine,
                  kind: line.kind,
                  text: line.text,
                  directive: line.directive,
                  chords: line.chords.map((chord) =>
                      chord.symbol == null || unchanged
                          ? chord
                          : chord.withSymbol(
                              chord.symbol!.transpose(offset, spelling))),
                )),
          )),
    );
  }

  DisplayChart display(ChartDocument chart, ChartSettings settings,
      {String? key}) {
    final context = key == null ? chart.key : _key(key);
    if (settings.useNashville && context == null) {
      throw ArgumentError('Nashville notation requires a selected key.');
    }
    final showLyrics = settings.displayMode != ChartDisplayMode.chordsOnly;
    final showChords = settings.displayMode != ChartDisplayMode.lyricsOnly;
    return DisplayChart(
        chart,
        chart.sections.map((section) => DisplayChartSection(
              section.id,
              section.label,
              section.lines.map((line) => DisplayChartLine(
                    original: line,
                    lyrics: showLyrics &&
                            (line.kind == ChartLineKind.lyrics ||
                                line.kind == ChartLineKind.blank)
                        ? line.text
                        : null,
                    layout: showChords && line.kind == ChartLineKind.chords
                        ? line.text
                        : null,
                    chords: showChords
                        ? line.chords.map((chord) => DisplayChord(
                              settings.useNashville && chord.symbol != null
                                  ? chord.symbol!.nashville(context!)
                                  : chord.text,
                              chord.offset,
                            ))
                        : const [],
                  )),
            )));
  }

  /// Preparation API: prefer explicit source {key}, then arrangement key,
  /// then song default. A mismatched item is rejected instead of substituted.
  DisplayChart prepare(
      {required Song song,
      required Arrangement arrangement,
      SetlistItem? item,
      required ChartSettings settings}) {
    if (!song.arrangements.any((a) => a.id == arrangement.id) ||
        (item != null &&
            (item.songId != song.id || item.arrangementId != arrangement.id))) {
      throw ArgumentError('Song, arrangement and setlist item must match.');
    }
    final parsed = const ChordProParser().parse(arrangement.chordProSource);
    final source = parsed.key?.name ??
        (arrangement.performanceKey.isNotEmpty
            ? arrangement.performanceKey
            : song.defaultKey);
    final chart = transpose(parsed,
        sourceKey: source, targetKey: item?.performanceKey ?? source);
    return display(chart, settings);
  }

  MusicalKey _key(String value) =>
      MusicalKey.tryParse(value) ??
      (throw ArgumentError.value(value, 'key', 'Unsupported major/minor key'));
}
