import '../models/chart_document.dart';
import '../models/chord_symbol.dart';
import 'timing_grid_parser.dart';

class ChordProParser {
  const ChordProParser();

  ChartDocument parse(String source, {String? defaultTimeSignature}) {
    final sections = <ChartSection>[];
    final metadata = <String, List<String>>{};
    var lines = <ChartLine>[];
    var id = 'section-0';
    var label = 'Chart';
    var inTab = false;
    void flush() {
      if (lines.isNotEmpty) {
        sections.add(ChartSection(id: id, label: label, lines: lines));
        lines = [];
      }
    }

    final input = source.split(RegExp(r'\r\n|\n|\r'));
    final keyDirective =
        RegExp(r'^\s*\{(?:key|k):\s*(.*?)\}\s*$', caseSensitive: false);
    final sourceKey = input
        .map(keyDirective.firstMatch)
        .whereType<RegExpMatch>()
        .map((m) => MusicalKey.tryParse(m[1]!))
        .firstOrNull;
    final warnings = <String>[];
    ChordSymbol? parseChord(String token, {bool warn = true}) {
      final letter = ChordSymbol.tryParse(token);
      if (letter != null) return letter;
      if (!RegExp(r'^[#b♯♭]*[0-9]').hasMatch(token)) return null;
      final numbered = ChordSymbol.tryParseNumbered(
          token, sourceKey ?? const MusicalKey(NoteName('C', 0)));
      if (numbered == null) {
        if (warn) {
          warnings.add(
              'Unsupported or ambiguous numbered chord "$token"; preserved literally.');
        }
        return null;
      }
      if (sourceKey == null) {
        if (warn) {
          warnings.add(
              'Numbered chord "$token" requires a valid source {key}; preserved literally.');
        }
        return null;
      }
      return numbered;
    }

    for (var i = 0; i < input.length; i++) {
      final raw = input[i];
      final match =
          RegExp(r'^\s*\{([\w-]+)(?::\s*(.*?))?\}\s*$').firstMatch(raw);
      if (match != null) {
        final name =
            _aliases[match[1]!.toLowerCase()] ?? match[1]!.toLowerCase();
        final value = match[2] ?? '';
        final kind = _kind(name);
        final directive = ChartDirective(name, value, kind);
        if (kind == DirectiveKind.sectionStart) {
          flush();
          id = 'section-${i + 1}';
          label = value.isNotEmpty ? value : _sectionLabel(name);
        }
        lines.add(ChartLine(
            source: raw,
            sourceLine: i + 1,
            kind: ChartLineKind.directive,
            text: raw,
            directive: directive));
        if (kind == DirectiveKind.metadata) {
          metadata.putIfAbsent(name, () => []).add(value);
        }
        if (name == 'start_of_tab') inTab = true;
        if (name == 'end_of_tab') inTab = false;
        if (kind == DirectiveKind.sectionEnd) {
          flush();
          id = 'section-after-${i + 1}';
          label = 'Chart';
        }
      } else if (inTab) {
        lines.add(ChartLine(
            source: raw,
            sourceLine: i + 1,
            kind: ChartLineKind.tablature,
            text: raw));
      } else {
        lines.add(_parseLine(raw, i + 1, parseChord));
      }
    }
    flush();
    return attachTimingGrids(
        ChartDocument(
            source: source,
            sections: sections,
            metadata: metadata,
            warnings: warnings.toSet(),
            key: MusicalKey.tryParse(metadata['key']?.firstOrNull ?? '')),
        defaultMeter: defaultTimeSignature);
  }

  ChartLine _parseLine(String raw, int number,
      ChordSymbol? Function(String, {bool warn}) parseChord) {
    if (raw.trim().isEmpty) {
      return ChartLine(
          source: raw,
          sourceLine: number,
          kind: ChartLineKind.blank,
          text: raw);
    }
    if (raw.trimLeft().startsWith('#') &&
        !RegExp(r'^#[#♯]?[1-7]').hasMatch(raw.trimLeft())) {
      return ChartLine(
          source: raw,
          sourceLine: number,
          kind: ChartLineKind.directive,
          text: raw,
          directive: ChartDirective(
              'comment', raw.trimLeft().substring(1), DirectiveKind.comment));
    }
    final chords = <AnchoredChord>[];
    // Instrumental rows may mix bracketed and bare chords. Grid anchors use
    // original columns, retaining bars, repeat signs and inter-token spacing.
    final tokens = RegExp(r'\[[^\[\]]+\]|[^\s|:]+').allMatches(raw).toList();
    String tokenText(RegExpMatch token) {
      final text = token[0]!;
      return text.startsWith('[') && text.endsWith(']')
          ? text.substring(1, text.length - 1)
          : text;
    }

    final symbols =
        tokens.map((m) => parseChord(tokenText(m), warn: false)).toList();
    const layoutTokens = ['%', '.', '-', '/', 'N.C.', 'NC'];
    final isGrid = tokens.isNotEmpty &&
        tokens.asMap().entries.every((entry) =>
            symbols[entry.key] != null ||
            layoutTokens.contains(tokenText(entry.value)));
    if (isGrid) {
      final layout = raw.split('');
      for (var i = 0; i < tokens.length; i++) {
        if (symbols[i] == null) continue;
        final token = tokens[i];
        chords.add(AnchoredChord(
            text: tokenText(token),
            offset: token.start,
            sourceOffset: token.start,
            symbol: symbols[i]));
        for (var column = token.start; column < token.end; column++) {
          layout[column] = ' ';
        }
      }
      return ChartLine(
          source: raw,
          sourceLine: number,
          kind: ChartLineKind.chords,
          text: layout.join(),
          chords: chords);
    }
    final lyric = StringBuffer();
    var cursor = 0;
    for (final match in RegExp(r'\[([^\[\]\r\n]+)\]').allMatches(raw)) {
      lyric.write(raw.substring(cursor, match.start));
      final token = match[1]!;
      chords.add(AnchoredChord(
          text: token,
          offset: lyric.length,
          sourceOffset: match.start,
          symbol: parseChord(token)));
      cursor = match.end;
    }
    if (chords.isNotEmpty) {
      lyric.write(raw.substring(cursor));
      final text = lyric.toString();
      final onlyChords = RegExp(r'^[\s|:%./\-]*$').hasMatch(text);
      if (onlyChords) {
        final layout = raw.split('');
        final anchored = <AnchoredChord>[];
        for (final match in RegExp(r'\[([^\[\]\r\n]+)\]').allMatches(raw)) {
          anchored.add(AnchoredChord(
              text: match[1]!,
              offset: match.start,
              sourceOffset: match.start,
              symbol: parseChord(match[1]!)));
          for (var column = match.start; column < match.end; column++) {
            layout[column] = ' ';
          }
        }
        return ChartLine(
            source: raw,
            sourceLine: number,
            kind: ChartLineKind.chords,
            text: layout.join(),
            chords: anchored);
      }
      return ChartLine(
          source: raw,
          sourceLine: number,
          kind: onlyChords ? ChartLineKind.chords : ChartLineKind.lyrics,
          text: text,
          chords: chords);
    }
    // Separator-only measures are still grid lines.
    final separator =
        RegExp(r'^[\s|:%./\-]+$').hasMatch(raw) && raw.contains('|');
    return ChartLine(
        source: raw,
        sourceLine: number,
        kind: separator ? ChartLineKind.chords : ChartLineKind.lyrics,
        text: raw);
  }

  static DirectiveKind _kind(String name) {
    if (const [
      'title',
      'subtitle',
      'artist',
      'composer',
      'lyricist',
      'album',
      'copyright',
      'year',
      'key',
      'capo',
      'tempo',
      'time',
      'duration',
      'grid_subdivision'
    ].contains(name)) {
      return DirectiveKind.metadata;
    }
    if (name == 'section' ||
        const [
          'start_of_chorus',
          'start_of_verse',
          'start_of_bridge',
          'start_of_grid',
          'start_of_tab'
        ].contains(name)) {
      return DirectiveKind.sectionStart;
    }
    if (const [
      'end_of_chorus',
      'end_of_verse',
      'end_of_bridge',
      'end_of_grid',
      'end_of_tab'
    ].contains(name)) {
      return DirectiveKind.sectionEnd;
    }
    if (const ['comment', 'comment_italic', 'comment_box'].contains(name)) {
      return DirectiveKind.comment;
    }
    if (const [
      'chorus',
      'new_page',
      'new_physical_page',
      'column_break',
      'start_of_part',
      'end_of_part'
    ].contains(name)) {
      return DirectiveKind.layout;
    }
    return DirectiveKind.unknown;
  }

  static String _sectionLabel(String name) => switch (name) {
        'start_of_chorus' => 'Chorus',
        'start_of_verse' => 'Verse',
        'start_of_bridge' => 'Bridge',
        'start_of_grid' => 'Instrumental',
        'start_of_tab' => 'Tab',
        _ => 'Section',
      };

  static const _aliases = {
    't': 'title',
    'st': 'subtitle',
    'k': 'key',
    'c': 'comment',
    'ci': 'comment_italic',
    'cb': 'comment_box',
    'soc': 'start_of_chorus',
    'eoc': 'end_of_chorus',
    'sov': 'start_of_verse',
    'eov': 'end_of_verse',
    'sob': 'start_of_bridge',
    'eob': 'end_of_bridge',
    'sog': 'start_of_grid',
    'eog': 'end_of_grid',
    'sot': 'start_of_tab',
    'eot': 'end_of_tab',
    'np': 'new_page',
    'npp': 'new_physical_page',
    'colb': 'column_break',
  };
}
