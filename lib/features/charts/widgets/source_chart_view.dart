import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/models/chart_settings.dart';
import '../data/source_chart_adapter.dart';

/// Shared temporary source viewer for Rehearsal.
/// Keep the key tied to song selection to reset scrolling on each switch.
class SourceChartView extends StatefulWidget {
  const SourceChartView({
    super.key,
    required this.source,
    required this.settings,
  });

  final String source;
  final ChartSettings settings;

  @override
  State<SourceChartView> createState() => _SourceChartViewState();
}

class _SourceChartViewState extends State<SourceChartView> {
  final _scroll = ScrollController(keepScrollOffset: false);
  late List<SourceChartSection> _sections;
  late List<GlobalKey> _anchors;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _readSource();
  }

  void _readSource() {
    _sections = sourceChartSections(widget.source);
    _anchors = List.generate(_sections.length, (_) => GlobalKey());
  }

  @override
  void didUpdateWidget(SourceChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _readSource();
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
    final settings = widget.settings;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: SizedBox(
            width: _expanded ? 132 : 48,
            child: Column(
              children: [
                IconButton(
                  tooltip: _expanded ? 'Collapse sections' : 'Expand sections',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.chevron_left : Icons.segment),
                ),
                if (_expanded)
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < _sections.length; i++)
                          TextButton(
                            onPressed: () {
                              final target = _anchors[i].currentContext;
                              if (target != null) {
                                unawaited(Scrollable.ensureVisible(
                                  target,
                                  duration: const Duration(milliseconds: 200),
                                ));
                              }
                            },
                            child: Text(_sections[i].label),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                key: const ValueKey('chart-scroll'),
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: settings.chartWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Source preview · chord symbols are unchanged',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 20),
                        if (_sections.isEmpty)
                          const Text('No chart source available.'),
                        for (var i = 0; i < _sections.length; i++)
                          Padding(
                            key: _anchors[i],
                            padding: const EdgeInsets.only(bottom: 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  _sections[i].label,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontSize: settings.sectionHeaderFontSize *
                                        settings.globalScale,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _sections[i].source,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: settings.lyricsFontSize *
                                        settings.globalScale,
                                    height: settings.lineSpacing,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
