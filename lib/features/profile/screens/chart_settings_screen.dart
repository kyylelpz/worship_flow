import '../../../core/preferences/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chart_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_providers.dart';
import '../../charts/widgets/chord_label.dart';

/// Account-scoped chart preferences; canonical and shared chart data are untouched.
class ChartSettingsController extends StateNotifier<ChartSettings> {
  ChartSettingsController([super.state = const ChartSettings()]);

  void update(ChartSettings Function(ChartSettings) transform) {
    state = transform(state);
  }

  void reset() => state = const ChartSettings();

  void adjustLyrics(double delta) => update(
        (s) => s.copyWith(
          lyricsFontSize: (s.lyricsFontSize + delta).clamp(10, 40),
        ),
      );

  void adjustChords(double delta) => update(
        (s) => s.copyWith(
          chordsFontSize: (s.chordsFontSize + delta).clamp(10, 40),
        ),
      );

  void adjustHeaders(double delta) => update(
        (s) => s.copyWith(
          sectionHeaderFontSize:
              (s.sectionHeaderFontSize + delta).clamp(10, 40),
        ),
      );
}

final chartSettingsProvider =
    StateNotifierProvider<ChartSettingsController, ChartSettings>(
  (ref) {
    ref.watch(userPreferencesProvider.select((s) => (s.uid, s.loading)));
    final owner = ref.read(userPreferencesProvider.notifier);
    final controller =
        ChartSettingsController(ref.read(userPreferencesProvider).value.chart);
    controller.addListener(owner.setChart, fireImmediately: false);
    return controller;
  },
);

class ChartSettingsScreen extends ConsumerWidget {
  const ChartSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(chartSettingsProvider);
    final controller = ref.read(chartSettingsProvider.notifier);
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chart Settings'),
        actions: [
          IconButton(
            tooltip: 'Reset to defaults',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset to defaults?'),
                  content: const Text(
                    'Font sizes and display preferences return to their '
                    'recommended values.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (ok == true) controller.reset();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const _SectionLabel('Typography'),
          _NumberStepper(
            label: 'Lyrics font size',
            value: settings.lyricsFontSize,
            onDecrement: () => controller.adjustLyrics(-1),
            onIncrement: () => controller.adjustLyrics(1),
          ),
          _NumberStepper(
            label: 'Chords font size',
            value: settings.chordsFontSize,
            onDecrement: () => controller.adjustChords(-1),
            onIncrement: () => controller.adjustChords(1),
          ),
          _NumberStepper(
            label: 'Section headers',
            value: settings.sectionHeaderFontSize,
            onDecrement: () => controller.adjustHeaders(-1),
            onIncrement: () => controller.adjustHeaders(1),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            label: 'Global scale',
            value: settings.globalScale,
            min: 0.5,
            max: 2.0,
            divisions: 30,
            display: '${(settings.globalScale * 100).round()}%',
            onChanged: (v) => controller.update(
              (s) => s.copyWith(globalScale: v),
            ),
          ),
          _SliderRow(
            label: 'Line spacing',
            value: settings.lineSpacing,
            min: 1.0,
            max: 2.5,
            divisions: 30,
            display: settings.lineSpacing.toStringAsFixed(1),
            onChanged: (v) => controller.update(
              (s) => s.copyWith(lineSpacing: v),
            ),
          ),
          _SliderRow(
            label: 'Chord Spacing',
            value: settings.chordSpacing,
            min: 0,
            max: 24,
            divisions: 24,
            display: '${settings.chordSpacing.round()} px',
            onChanged: (v) => controller.update(
              (s) => s.copyWith(chordSpacing: v),
            ),
          ),
          _SliderRow(
            label: 'Chart width',
            value: settings.chartWidth,
            min: 320,
            max: 1200,
            divisions: 22,
            display: '${settings.chartWidth.round()} px',
            onChanged: (v) => controller.update(
              (s) => s.copyWith(chartWidth: v),
            ),
          ),
          const SizedBox(height: 20),
          _ChordColorCard(settings: settings, controller: controller),
          const SizedBox(height: 20),
          const _SectionLabel('Notation'),
          Card(
            child: SwitchListTile(
              title: const Text('Nashville Number System'),
              subtitle: const Text('Show chords as scale degrees'),
              value: settings.useNashville,
              onChanged: (v) => controller.update(
                (s) => s.copyWith(useNashville: v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _SectionLabel('Display Mode'),
          Card(
            child: RadioGroup<ChartDisplayMode>(
              groupValue: settings.displayMode,
              onChanged: (v) {
                if (v != null) {
                  controller.update((s) => s.copyWith(displayMode: v));
                }
              },
              child: Column(
                children: [
                  for (final mode in ChartDisplayMode.values)
                    RadioListTile<ChartDisplayMode>(
                      value: mode,
                      title: Text(mode.label),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionLabel('Theme'),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (v) {
                if (v != null) {
                  ref.read(themeModeProvider.notifier).setMode(v);
                }
              },
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    title: Text('Light'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    title: Text('Dark'),
                    subtitle: Text('Optimized for stage readability'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    title: Text('System'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Settings are stored per-device. Account sync arrives in Phase 2.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.lightSecondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChordColorCard extends StatelessWidget {
  const _ChordColorCard({required this.settings, required this.controller});

  final ChartSettings settings;
  final ChartSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selected = settings.chordColorFor(dark);
    final argb = selected.argb;
    final previewColor = argb == null ? theme.colorScheme.primary : Color(argb);
    final previewStyle = (theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(
            color: previewColor,
            fontSize: settings.chordsFontSize * settings.globalScale,
            fontWeight: FontWeight.w700);

    void select(ChordColorPreset preset) => controller.update((s) => dark
        ? s.copyWith(darkChordColor: preset)
        : s.copyWith(lightChordColor: preset));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child:
                      Text('Chord Color', style: theme.textTheme.titleMedium)),
              Tooltip(
                message: 'Reset chord color',
                child: TextButton(
                  onPressed: selected == ChordColorPreset.defaultFor(dark)
                      ? null
                      : () => select(ChordColorPreset.themeDefault),
                  child: const Text('Reset'),
                ),
              ),
            ]),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in ChordColorPreset.forTheme(dark))
                  _ChordSwatch(
                      preset: preset,
                      selected: selected == preset,
                      onTap: () => select(preset)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Preview', style: theme.textTheme.bodySmall),
            Wrap(
              spacing: settings.chordSpacing,
              runSpacing: 4,
              children: [
                for (final chord in settings.useNashville
                    ? const ['1', '4M7', '1/3']
                    : const ['D', 'GM7', 'D/F#'])
                  ChordLabel(chord, style: previewStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChordSwatch extends StatelessWidget {
  const _ChordSwatch(
      {required this.preset, required this.selected, required this.onTap});

  final ChordColorPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(preset.argb!);
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Semantics(
      label: preset.label,
      button: true,
      selected: selected,
      child: Tooltip(
        message: preset.label,
        excludeFromSemantics: true,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: selected ? Icon(Icons.check, color: checkColor) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, top: 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: AppColors.lightSecondaryText,
        ),
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.label,
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String label;
  final double value;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_rounded),
              onPressed: onDecrement,
            ),
            SizedBox(
              width: 40,
              child: Text(
                value.round().toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: onIncrement,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
                Text(display, style: theme.textTheme.bodySmall),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
