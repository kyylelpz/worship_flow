import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/chart_settings.dart';
import '../models/chart_document.dart';
import 'anchored_lyric_line.dart';

/// Navigation-independent shared chart surface for Rehearsal and future Live.
class ChordChartView extends StatefulWidget {
  const ChordChartView(
      {super.key, required this.chart, required this.settings});
  final DisplayChart chart;
  final ChartSettings settings;

  @override
  State<ChordChartView> createState() => _ChordChartViewState();
}

class _ChordChartViewState extends State<ChordChartView> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final Map<String, GlobalKey> _anchors = {};
  bool _expanded = false;

  @override
  void didUpdateWidget(ChordChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart.document.source != widget.chart.document.source) {
      _anchors.clear();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final settings = widget.settings;
    final theme = Theme.of(context);
    final lyricStyle = (theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(
            fontSize: settings.lyricsFontSize * settings.globalScale,
            height: settings.lineSpacing);
    final chordStyle = (theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(
            fontSize: settings.chordsFontSize * settings.globalScale,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary);
    final hiddenGridSections = chart.document.grids
        .where((g) => g.targetSectionId != null)
        .map((g) => g.sectionId)
        .toSet();
    final sections = chart.sections
        .where((s) =>
            !hiddenGridSections.contains(s.id) &&
            s.lines.any((l) =>
                l.chords.isNotEmpty ||
                (l.lyrics?.trim().isNotEmpty ?? false) ||
                (l.original.kind == ChartLineKind.tablature &&
                    l.original.text.trim().isNotEmpty) ||
                l.original.directive?.kind == DirectiveKind.comment ||
                l.original.directive?.kind == DirectiveKind.unknown))
        .toList();
    for (final section in sections) {
      _anchors.putIfAbsent(section.id, () => GlobalKey());
    }
    Widget sequence(Iterable<DisplayChartLine> lines) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final line in lines)
              if (line.original.kind == ChartLineKind.blank)
                SizedBox(
                    height: MediaQuery.textScalerOf(context)
                            .scale(lyricStyle.fontSize!) *
                        settings.lineSpacing)
              else if (line.chords.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(spacing: 18, runSpacing: 12, children: [
                      for (final chord in line.chords)
                        Text(chord.text, style: chordStyle),
                    ])),
          ],
        );
    Widget gridView(DisplayTimingGrid grid) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                '${grid.original.meter} · ${grid.original.subdivision} slot(s) per denominator beat',
                style: theme.textTheme.bodySmall),
            LayoutBuilder(
                builder: (context, constraints) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var m = 0; m < grid.measures.length; m++)
                          ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: constraints.maxWidth),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerColor),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${grid.original.measures[m].openingBar} ${m + 1} ${grid.original.measures[m].closingBar}',
                                            style: theme.textTheme.labelSmall),
                                        LayoutBuilder(
                                            builder: (context, slotsBox) {
                                          final desired =
                                              MediaQuery.textScalerOf(context)
                                                  .scale(
                                                      settings.chordsFontSize *
                                                          settings.globalScale *
                                                          3.5);
                                          final columns = (slotsBox.maxWidth /
                                                  desired)
                                              .floor()
                                              .clamp(
                                                  1, grid.measures[m].length);
                                          final cellWidth =
                                              slotsBox.maxWidth / columns;
                                          return Wrap(runSpacing: 8, children: [
                                            for (final slot in grid.measures[m])
                                              SizedBox(
                                                  width: cellWidth,
                                                  child: Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 3),
                                                      child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                                '${slot.original.index ~/ grid.original.subdivision + 1}'
                                                                '${grid.original.subdivision == 1 ? '' : '.${slot.original.index % grid.original.subdivision + 1}'}',
                                                                style: theme
                                                                    .textTheme
                                                                    .labelSmall),
                                                            Text(slot.text,
                                                                style:
                                                                    chordStyle,
                                                                textAlign:
                                                                    TextAlign
                                                                        .center),
                                                          ]))),
                                          ]);
                                        }),
                                      ])),
                            ),
                          ),
                      ],
                    )),
          ],
        );
    Widget sectionView(DisplayChartSection section) {
      final grids = chart.grids
          .where((g) =>
              g.original.targetSectionId == section.id ||
              (g.original.targetSectionId == null &&
                  g.original.sectionId == section.id))
          .toList();
      final usableGrids = grids.where((g) => g.original.isValid).toList();
      final timingSection =
          chart.document.grids.any((g) => g.sectionId == section.id);
      return Padding(
        key: _anchors[section.id],
        padding: const EdgeInsets.only(bottom: 28),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(section.label,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontSize:
                      settings.sectionHeaderFontSize * settings.globalScale)),
          const SizedBox(height: 12),
          if (settings.displayMode == ChartDisplayMode.chordsOnly &&
              usableGrids.isNotEmpty)
            for (final grid in usableGrids) gridView(grid)
          else if (settings.displayMode == ChartDisplayMode.chordsOnly) ...[
            if (section.lines.any((l) => l.chords.isNotEmpty))
              Text('Chord sequence · no timing',
                  style: theme.textTheme.bodySmall),
            sequence(section.lines),
            for (final grid in grids.where((g) => !g.original.isValid)) ...[
              Text('Invalid grid sequence · no timing',
                  style: theme.textTheme.bodySmall),
              Wrap(spacing: 18, runSpacing: 12, children: [
                for (final measure in grid.measures)
                  for (final slot in measure)
                    if (!slot.original.sustain)
                      Text(slot.text, style: chordStyle),
              ]),
            ],
          ] else if (!timingSection ||
              settings.displayMode != ChartDisplayMode.lyricsOnly)
            for (final line in section.lines) ...[
              if (line.original.kind == ChartLineKind.blank)
                SizedBox(
                    height: MediaQuery.textScalerOf(context)
                            .scale(lyricStyle.fontSize!) *
                        settings.lineSpacing)
              else if (line.lyrics != null && line.lyrics!.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: line.chords.isEmpty
                        ? Text(line.lyrics!, style: lyricStyle)
                        : AnchoredLyricLine(
                            line: line,
                            lyricStyle: lyricStyle,
                            chordStyle: chordStyle))
              else if (line.chords.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: sequence([line]))
              else if (line.original.kind == ChartLineKind.tablature)
                Text(line.original.text,
                    style: lyricStyle.copyWith(fontFamily: 'monospace'))
              else if (line.original.directive?.kind == DirectiveKind.comment)
                Text(line.original.directive!.value,
                    style: theme.textTheme.bodyMedium)
              else if (line.original.directive?.kind == DirectiveKind.unknown)
                Text(line.original.source, style: theme.textTheme.bodySmall),
            ],
        ]),
      );
    }

    return LayoutBuilder(
        builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  child: SizedBox(
                      width: _expanded
                          ? math.min(132, constraints.maxWidth * .32)
                          : 40,
                      child: Column(children: [
                        IconButton(
                            tooltip: _expanded
                                ? 'Collapse sections'
                                : 'Expand sections',
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            icon: Icon(_expanded
                                ? Icons.chevron_left
                                : Icons.segment)),
                        if (_expanded)
                          Expanded(
                              child: ListView(children: [
                            for (final section in sections)
                              TextButton(
                                  onPressed: () {
                                    final target =
                                        _anchors[section.id]?.currentContext;
                                    if (target != null) {
                                      unawaited(Scrollable.ensureVisible(target,
                                          duration: const Duration(
                                              milliseconds: 200)));
                                    }
                                  },
                                  child: Text(section.label)),
                          ])),
                      ])),
                ),
                Expanded(
                    child: Scrollbar(
                  controller: _scroll,
                  child: SingleChildScrollView(
                      key: const ValueKey('chart-scroll'),
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: settings.chartWidth),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final warning in chart.document.warnings)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Text('Chart warning: $warning',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    color: theme
                                                        .colorScheme.error))),
                                  if (sections.isEmpty)
                                    const Text('No chart content available.'),
                                  for (final section in sections)
                                    sectionView(section),
                                ])),
                      )),
                )),
              ],
            ));
  }
}
