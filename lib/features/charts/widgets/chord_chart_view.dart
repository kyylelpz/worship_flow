import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/chart_settings.dart';
import '../models/chart_document.dart';
import 'anchored_lyric_line.dart';
import 'chord_label.dart';
import 'compact_chord_grid.dart';

/// Navigation-independent shared chart surface for Rehearsal.
class ChordChartView extends StatefulWidget {
  const ChordChartView(
      {super.key,
      required this.chart,
      required this.settings,
      this.sectionNavigationEnabled = true,
      this.showSections = true,
      this.reserveSectionSpace = true});
  final DisplayChart chart;
  final ChartSettings settings;

  /// False removes tracking and navigation layout; showSections only hides UI.
  final bool sectionNavigationEnabled;
  final bool showSections;
  final bool reserveSectionSpace;

  @override
  State<ChordChartView> createState() => _ChordChartViewState();
}

class _ChordChartViewState extends State<ChordChartView> {
  final _scroll = ScrollController(keepScrollOffset: false);
  final Map<String, GlobalKey> _anchors = {};
  final _viewportKey = GlobalKey();
  final _sectionScroll = ScrollController();
  List<DisplayChartSection> _sections = const [];
  final _activeId = ValueNotifier<String?>(null);
  final _sectionOffsets = <String, double>{};
  bool _layoutRefreshScheduled = false, _jumping = false;
  int _jumpGeneration = 0;
  bool _needsActiveUpdate = true;
  Size? _lastViewportSize;
  double? _lastTextScale;

  void _scheduleLayoutRefresh() {
    if (!widget.sectionNavigationEnabled || _layoutRefreshScheduled) return;
    _layoutRefreshScheduled = true;
    final jumpGeneration = _jumpGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutRefreshScheduled = false;
      if (!mounted || !widget.sectionNavigationEnabled || !_scroll.hasClients) {
        return;
      }
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      _sectionOffsets.clear();
      for (final section in _sections) {
        final anchor = _anchors[section.id]?.currentContext?.findRenderObject();
        if (anchor is RenderBox && anchor.hasSize) {
          _sectionOffsets[section.id] =
              anchor.localToGlobal(Offset.zero, ancestor: viewport).dy +
                  _scroll.offset;
        }
      }
      // A jump since this callback was scheduled owns the highlight.
      if (jumpGeneration == _jumpGeneration) _updateActive();
    });
  }

  bool _scrollEnded(ScrollEndNotification notification) {
    if (widget.sectionNavigationEnabled &&
        notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical &&
        !_jumping) {
      // ScrollEnd is dispatched just before ScrollPosition marks itself idle.
      final jumpGeneration = _jumpGeneration;
      scheduleMicrotask(() {
        if (mounted &&
            widget.sectionNavigationEnabled &&
            jumpGeneration == _jumpGeneration) {
          _updateActive();
        }
      });
    }
    return false;
  }

  void _updateActive() {
    if (!mounted ||
        !widget.sectionNavigationEnabled ||
        _needsActiveUpdate ||
        _sections.isEmpty ||
        !_scroll.hasClients ||
        _scroll.position.isScrollingNotifier.value ||
        _jumping) {
      return;
    }
    var active = _sections.first.id;
    for (final section in _sections) {
      final offset = _sectionOffsets[section.id];
      if (offset != null && offset <= _scroll.offset + 16) active = section.id;
    }
    if (_scroll.position.maxScrollExtent > 0 &&
        _scroll.offset >= _scroll.position.maxScrollExtent - 1) {
      active = _sections.last.id;
    }
    // Only the floating navigation listens to this value, not the chart body.
    if (_activeId.value != active) _activeId.value = active;
  }

  void _jumpTo(DisplayChartSection section) {
    if (!widget.sectionNavigationEnabled) return;
    final target = _anchors[section.id]?.currentContext;
    if (target == null) return;
    _jumpGeneration++;
    _jumping = true;
    try {
      unawaited(Scrollable.ensureVisible(target, duration: Duration.zero));
      if (_activeId.value != section.id) _activeId.value = section.id;
    } finally {
      _jumping = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.sectionNavigationEnabled) _needsActiveUpdate = true;
  }

  @override
  void didUpdateWidget(ChordChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectionNavigationEnabled != widget.sectionNavigationEnabled) {
      _jumpGeneration++;
      _anchors.clear();
      _sectionOffsets.clear();
      _sections = const [];
      _needsActiveUpdate = true;
      _lastViewportSize = null;
      _lastTextScale = null;
    }
    if (widget.sectionNavigationEnabled &&
        (oldWidget.settings != widget.settings ||
            oldWidget.chart.document.key?.name !=
                widget.chart.document.key?.name)) {
      _needsActiveUpdate = true;
    }
    if (oldWidget.chart.document.source != widget.chart.document.source) {
      if (widget.sectionNavigationEnabled) {
        _anchors.clear();
        _activeId.value = null;
        _sectionOffsets.clear();
        _needsActiveUpdate = true;
      }
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _activeId.dispose();
    _scroll.dispose();
    _sectionScroll.dispose();
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
                _repeatText(l) ||
                (l.original.kind == ChartLineKind.tablature &&
                    l.original.text.trim().isNotEmpty) ||
                l.original.directive?.kind == DirectiveKind.comment ||
                l.original.directive?.kind == DirectiveKind.unknown))
        .toList();
    if (widget.sectionNavigationEnabled) {
      _sections = sections;
      if (_needsActiveUpdate) {
        _needsActiveUpdate = false;
        _scheduleLayoutRefresh();
      }
      for (final section in sections) {
        _anchors.putIfAbsent(section.id, () => GlobalKey());
      }
    }
    Widget sequence(Iterable<DisplayChartLine> lines) =>
        CompactChordGrid(style: chordStyle, rows: [
          for (final line in lines)
            if (line.layout != null)
              instrumentalGridRow(line)
            else if (line.chords.isNotEmpty)
              CompactGridRow(
                  [CompactMeasure(line.chords.map((c) => c.text).toList())])
            else if (_repeatText(line))
              CompactGridRow(const [], text: line.original.text)
            else if (line.original.kind == ChartLineKind.blank)
              const CompactGridRow([], text: ''),
        ]);
    Widget gridView(DisplayTimingGrid grid) => CompactChordGrid(
        rows: timingGridRows(grid,
            sourceLines: chart.document.sections
                .where((s) => s.id == grid.original.sectionId)
                .expand((s) => s.lines)),
        style: chordStyle);
    List<Widget> lyricLines(List<DisplayChartLine> lines) {
      final result = <Widget>[];
      var passage = <DisplayChartLine>[];
      void flush() {
        if (passage.isEmpty) return;
        result.add(sequence(passage));
        passage = [];
      }

      for (final line in lines) {
        if (line.layout != null ||
            (passage.isNotEmpty &&
                (_repeatText(line) ||
                    line.original.kind == ChartLineKind.blank))) {
          passage.add(line);
          continue;
        }
        flush();
        if (line.original.kind == ChartLineKind.blank) {
          result.add(SizedBox(
              height:
                  MediaQuery.textScalerOf(context).scale(lyricStyle.fontSize!) *
                      settings.lineSpacing));
        } else if (line.lyrics != null && line.lyrics!.isNotEmpty) {
          result.add(Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: line.chords.isEmpty
                  ? Text(line.lyrics!, style: lyricStyle)
                  : AnchoredLyricLine(
                      line: line,
                      lyricStyle: lyricStyle,
                      chordStyle: chordStyle)));
        } else if (line.chords.isNotEmpty) {
          result.add(sequence([line]));
        } else if (line.original.kind == ChartLineKind.tablature) {
          result.add(Text(line.original.text,
              style: lyricStyle.copyWith(fontFamily: 'monospace')));
        } else if (line.original.directive?.kind == DirectiveKind.comment) {
          result.add(Text(line.original.directive!.value,
              style: theme.textTheme.bodyMedium));
        } else if (line.original.directive?.kind == DirectiveKind.unknown) {
          result.add(
              Text(line.original.source, style: theme.textTheme.bodySmall));
        }
      }
      flush();
      return result;
    }

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
        key: widget.sectionNavigationEnabled ? _anchors[section.id] : null,
        padding: const EdgeInsets.only(bottom: 18),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(section.label,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontSize:
                      settings.sectionHeaderFontSize * settings.globalScale)),
          const SizedBox(height: 6),
          if (usableGrids.isNotEmpty &&
              settings.displayMode != ChartDisplayMode.lyricsOnly &&
              (settings.displayMode == ChartDisplayMode.chordsOnly ||
                  !section.lines.any((l) =>
                      l.original.kind == ChartLineKind.lyrics &&
                      l.original.text.trim().isNotEmpty &&
                      !_repeatText(l)))) ...[
            for (final grid in usableGrids) ...[
              gridView(grid),
              if (grid.original.sectionId != section.id)
                for (final line in chart.sections
                    .where((s) => s.id == grid.original.sectionId)
                    .expand((s) => s.lines)
                    .where(_repeatText))
                  Text(line.original.text, style: lyricStyle),
            ],
            for (final line in section.lines.where(_repeatText))
              Text(line.original.text, style: lyricStyle),
          ] else if (settings.displayMode == ChartDisplayMode.chordsOnly) ...[
            if (section.lines
                .any((l) => l.chords.isNotEmpty && l.layout == null))
              Text('Chord sequence · no timing',
                  style: theme.textTheme.bodySmall),
            sequence(section.lines),
            for (final grid in grids.where((g) => !g.original.isValid)) ...[
              Text('Invalid grid sequence · no timing',
                  style: theme.textTheme.bodySmall),
              Wrap(spacing: 18, runSpacing: 12, children: [
                for (final measure in grid.measures)
                  for (final slot in measure)
                    if (slot.original.chord != null)
                      ChordLabel(slot.text, style: chordStyle),
              ]),
            ],
          ] else if (!timingSection ||
              settings.displayMode != ChartDisplayMode.lyricsOnly)
            ...lyricLines(section.lines),
        ]),
      );
    }

    final labels = widget.sectionNavigationEnabled
        ? _sectionLabels(sections)
        : const <String>[];
    return SafeArea(
      top: false,
      child: LayoutBuilder(builder: (context, constraints) {
        if (widget.sectionNavigationEnabled) {
          final viewportSize =
              Size(constraints.maxWidth, constraints.maxHeight);
          final textScale = MediaQuery.textScalerOf(context).scale(16);
          if (_lastViewportSize != viewportSize ||
              _lastTextScale != textScale) {
            _lastViewportSize = viewportSize;
            _lastTextScale = textScale;
            _scheduleLayoutRefresh();
          }
        }

        final bubbleWidth = !widget.sectionNavigationEnabled
            ? 0.0
            : MediaQuery.textScalerOf(context)
                .scale(24)
                .clamp(48.0,
                    math.max(48.0, math.min(96.0, constraints.maxWidth * .35)))
                .toDouble();
        final chartScroll = Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
              key: const ValueKey('chart-scroll'),
              controller: _scroll,
              // Keep this gutter even when hidden: toggling never reflows lyrics.
              padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  widget.sectionNavigationEnabled && widget.reserveSectionSpace
                      ? bubbleWidth + 20
                      : 12,
                  12),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: settings.chartWidth),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final warning in chart.document.warnings)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('Chart warning: $warning',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.error))),
                          if (sections.isEmpty)
                            const Text('No chart content available.'),
                          for (final section in sections) sectionView(section),
                        ])),
              )),
        );
        return Stack(
            key: widget.sectionNavigationEnabled ? _viewportKey : null,
            fit: StackFit.expand,
            children: [
              if (widget.sectionNavigationEnabled)
                NotificationListener<ScrollEndNotification>(
                    onNotification: _scrollEnded, child: chartScroll)
              else
                chartScroll,
              if (widget.sectionNavigationEnabled &&
                  widget.showSections &&
                  sections.isNotEmpty)
                Positioned(
                  top: 8,
                  right: 8,
                  width: bubbleWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: math.max(
                            0, math.min(360, constraints.maxHeight - 16))),
                    child: Scrollbar(
                      controller: _sectionScroll,
                      child: ValueListenableBuilder<String?>(
                          valueListenable: _activeId,
                          builder: (context, activeId, _) => ListView.separated(
                                key: const ValueKey('section-bubbles'),
                                controller: _sectionScroll,
                                primary: false,
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: sections.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (context, index) {
                                  final section = sections[index];
                                  final selected =
                                      (activeId ?? sections.first.id) ==
                                          section.id;
                                  return Semantics(
                                      key: ValueKey(
                                          'section-state-${section.id}'),
                                      selected: selected,
                                      label:
                                          '${section.label}, section ${index + 1} of ${sections.length}',
                                      child: Tooltip(
                                          message:
                                              '${section.label} · ${index + 1}/${sections.length}',
                                          child: Material(
                                              elevation: 2,
                                              shape: const StadiumBorder(),
                                              color: selected
                                                  ? theme.colorScheme
                                                      .primaryContainer
                                                  : theme.colorScheme
                                                      .surfaceContainerHigh,
                                              child: TextButton(
                                                key: ValueKey(
                                                    'section-bubble-${section.id}'),
                                                style: TextButton.styleFrom(
                                                    minimumSize:
                                                        const Size(48, 48),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 4,
                                                        vertical: 6),
                                                    foregroundColor: selected
                                                        ? theme.colorScheme
                                                            .onPrimaryContainer
                                                        : theme.colorScheme
                                                            .onSurfaceVariant,
                                                    shape:
                                                        const StadiumBorder()),
                                                onPressed: () =>
                                                    _jumpTo(section),
                                                child: Text(labels[index],
                                                    textAlign: TextAlign.center,
                                                    style: theme
                                                        .textTheme.labelMedium
                                                        ?.copyWith(
                                                            color: selected
                                                                ? theme
                                                                    .colorScheme
                                                                    .onPrimaryContainer
                                                                : theme
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                            fontWeight: selected
                                                                ? FontWeight
                                                                    .w800
                                                                : FontWeight
                                                                    .w600)),
                                              ))));
                                },
                              )),
                    ),
                  ),
                ),
            ]);
      }),
    );
  }
}

List<String> _sectionLabels(List<DisplayChartSection> sections) {
  String shortLabel(String label) {
    final value = label.trim().toLowerCase();
    final number = RegExp(r'\d+').firstMatch(value)?.group(0) ?? '';
    if (value.startsWith('intro')) return 'IN$number';
    if (value.startsWith('outro') || value.startsWith('ending')) {
      return 'OUT$number';
    }
    if (value.startsWith('pre-chorus') ||
        value.startsWith('prechorus') ||
        value.startsWith('pre chorus')) {
      return 'PC$number';
    }
    if (value.startsWith('verse')) return 'V${number.isEmpty ? '1' : number}';
    if (value.startsWith('chorus')) return 'CH$number';
    if (value.startsWith('refrain')) return 'RF$number';
    if (value.startsWith('bridge')) return 'BR$number';
    final letters = value.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
    return letters.isEmpty
        ? 'S'
        : letters.substring(0, math.min(3, letters.length));
  }

  final bases = sections.map((s) => shortLabel(s.label)).toList();
  final seen = <String, int>{};
  final used = <String>{};
  return bases.map((base) {
    if (bases.where((b) => b == base).length == 1 && !used.contains(base)) {
      used.add(base);
      return base;
    }
    final occurrence = seen.update(base, (n) => n + 1, ifAbsent: () => 1);
    var label = '$base${RegExp(r'\d$').hasMatch(base) ? '·' : ''}$occurrence';
    // Numbered names and repeated unnumbered names must not collide.
    var suffix = occurrence;
    while (used.contains(label) || bases.contains(label)) {
      label = '$base·${suffix++}';
    }
    used.add(label);
    return label;
  }).toList();
}

bool _repeatText(DisplayChartLine line) =>
    RegExp(r'^\s*\(\s*\d+\s*x\s*\)\s*$', caseSensitive: false)
        .hasMatch(line.original.text);
