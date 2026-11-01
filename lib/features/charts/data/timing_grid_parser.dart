import '../models/chart_document.dart';
import '../models/chord_symbol.dart';

/// Worship Flow extension, applied after normal parsing. Source remains intact.
ChartDocument attachTimingGrids(ChartDocument document,
    {String? defaultMeter, MusicalKey? numberKey}) {
  final grids = <TimingGrid>[];
  final warnings = <String>[...document.warnings];
  var meter = defaultMeter?.trim() ?? '4/4';
  var subdivision = 1;
  final gridSections = document.sections
      .where((s) => s.lines.any((l) => l.directive?.name == 'start_of_grid'))
      .map((s) => s.id)
      .toSet();
  for (final section in document.sections) {
    final isGrid = gridSections.contains(section.id);
    // Directives apply in source order, not the last value in metadata.
    final measures = <TimingMeasure>[];
    var valid = true;
    var hasPreviousChord = false;
    var gridMeter = meter;
    var gridSubdivision = subdivision;
    for (final line in section.lines) {
      final directive = line.directive;
      if (directive?.name == 'time') meter = directive!.value.trim();
      if (directive?.name == 'grid_subdivision') {
        subdivision = int.tryParse(directive!.value) ?? 0;
      }
      if (!isGrid ||
          line.kind == ChartLineKind.directive ||
          line.kind == ChartLineKind.blank) {
        continue;
      }
      if (measures.isNotEmpty &&
          (gridMeter != meter || gridSubdivision != subdivision)) {
        warnings.add(
            '${section.label}: meter/subdivision changes inside one grid are unsupported.');
        valid = false;
      }
      gridMeter = meter;
      gridSubdivision = subdivision;
      final beats =
          switch (meter) { '3/4' => 3, '4/4' => 4, '6/8' => 6, _ => 0 };
      if (beats == 0 || subdivision < 1 || subdivision > 8) {
        warnings.add(
            '${section.label}: unsupported meter/subdivision ($meter, $subdivision).');
        valid = false;
      }
      final raw = line.source;
      final bars = RegExp(r'[|:]+').allMatches(raw).toList();
      if (bars.length < 2 ||
          raw.substring(0, bars.first.start).trim().isNotEmpty ||
          raw.substring(bars.last.end).trim().isNotEmpty) {
        warnings.add(
            '${section.label}: grid row ${line.sourceLine} needs enclosing bars.');
        valid = false;
        continue;
      }
      for (var i = 0; i + 1 < bars.length; i++) {
        final start = bars[i].end;
        final end = bars[i + 1].start;
        final body = raw.substring(start, end);
        final slots = <TimingSlot>[];
        for (final token in RegExp(r'\S+').allMatches(body)) {
          final text = token[0]!;
          if (text == '-') {
            if (!hasPreviousChord) {
              warnings.add(
                  '${section.label}: sustain without a preceding chord at line ${line.sourceLine}.');
              valid = false;
            }
            slots.add(TimingSlot(slots.length, sustain: true));
          } else {
            final name = text.startsWith('[') && text.endsWith(']')
                ? text.substring(1, text.length - 1)
                : text;
            final symbol = ChordSymbol.tryParse(name) ??
                ((numberKey ?? document.key) == null
                    ? null
                    : ChordSymbol.tryParseNumbered(
                        name, (numberKey ?? document.key)!));
            if (symbol == null) {
              warnings.add('${section.label}: unsupported grid token "$text".');
              valid = false;
            }
            hasPreviousChord = symbol != null;
            slots.add(TimingSlot(slots.length,
                chord: AnchoredChord(
                    text: name,
                    symbol: symbol,
                    offset: start + token.start,
                    sourceOffset: start + token.start)));
          }
        }
        if (slots.length != beats * subdivision || slots.isEmpty) {
          warnings.add(
              '${section.label}: line ${line.sourceLine} measure ${i + 1} has ${slots.length} slots; expected ${beats * subdivision}.');
          valid = false;
        }
        measures.add(TimingMeasure(
            source: body,
            sourceLine: line.sourceLine,
            openingBar: bars[i][0]!,
            closingBar: bars[i + 1][0]!,
            slots: slots));
      }
    }
    if (!isGrid) continue;
    final candidates = document.sections
        .where((s) =>
            !gridSections.contains(s.id) &&
            s.label.trim().toLowerCase() ==
                section.label.trim().toLowerCase() &&
            s.lines.any((l) =>
                l.kind == ChartLineKind.lyrics ||
                l.kind == ChartLineKind.chords))
        .toList();
    final preceding = candidates.where(
        (s) => s.lines.first.sourceLine < section.lines.first.sourceLine);
    final target = preceding.lastOrNull ?? candidates.firstOrNull;
    if (measures.isEmpty) {
      valid = false;
      warnings.add('${section.label}: timing grid is empty.');
    }
    grids.add(TimingGrid(
        sectionId: section.id,
        label: section.label,
        targetSectionId: target?.id,
        meter: gridMeter,
        subdivision: gridSubdivision,
        isValid: valid,
        measures: measures));
  }
  return ChartDocument(
      source: document.source,
      sections: document.sections,
      metadata: document.metadata,
      key: document.key,
      grids: grids,
      warnings: [
        ...warnings,
        ...timingGridSequenceWarnings(document.sections, grids)
      ]);
}

/// Compare the effective chord events, after any selected-key resolution.
List<String> timingGridSequenceWarnings(
    Iterable<ChartSection> sections, Iterable<TimingGrid> grids) {
  List<String> sequence(Iterable<AnchoredChord> chords) {
    final result = <String>[];
    for (final chord in chords) {
      final symbol = chord.symbol;
      final identity = symbol == null
          ? chord.text
          : '${symbol.root.pitch}:${symbol.quality}/${symbol.bass?.pitch}';
      if (result.isEmpty || result.last != identity) result.add(identity);
    }
    return result;
  }

  final warnings = <String>[];
  for (final grid in grids) {
    final target =
        sections.where((s) => s.id == grid.targetSectionId).firstOrNull;
    if (target == null) continue;
    final lyrics = sequence(target.lines.expand((l) => l.chords));
    final rhythm = sequence(grid.measures
        .expand((m) => m.slots)
        .map((s) => s.chord)
        .whereType<AnchoredChord>());
    if (lyrics.join(';') != rhythm.join(';')) {
      warnings.add(
          '${grid.label}: lyric and grid chord sequences differ; both representations are preserved.');
    }
  }
  return warnings;
}
