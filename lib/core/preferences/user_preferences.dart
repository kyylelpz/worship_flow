import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../models/chart_settings.dart';

class UserPreferences {
  const UserPreferences(
      {this.theme = ThemeMode.light,
      this.chart = const ChartSettings(),
      this.offsets = const {}});
  final ThemeMode theme;
  final ChartSettings chart;
  final Map<String, int> offsets;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'theme': theme.name,
        'chart': {
          'lyricsFontSize': chart.lyricsFontSize,
          'chordsFontSize': chart.chordsFontSize,
          'sectionHeaderFontSize': chart.sectionHeaderFontSize,
          'globalScale': chart.globalScale,
          'lineSpacing': chart.lineSpacing,
          'chartWidth': chart.chartWidth,
          'useNashville': chart.useNashville,
          'displayMode': chart.displayMode.name,
        },
        'offsets': offsets,
      };

  static UserPreferences decode(String? source) {
    try {
      final d = jsonDecode(source ?? 'null');
      if (d is! Map || d['version'] != 1) return const UserPreferences();
      final c = d['chart'] is Map ? d['chart'] as Map : const {};
      const defaults = ChartSettings();
      double number(String key, double fallback, double min, double max) {
        final v = c[key];
        return v is num && v.isFinite && v >= min && v <= max
            ? v.toDouble()
            : fallback;
      }

      return UserPreferences(
        theme:
            ThemeMode.values.where((v) => v.name == d['theme']).firstOrNull ??
                ThemeMode.light,
        chart: ChartSettings(
          lyricsFontSize:
              number('lyricsFontSize', defaults.lyricsFontSize, 10, 40),
          chordsFontSize:
              number('chordsFontSize', defaults.chordsFontSize, 10, 40),
          sectionHeaderFontSize: number(
              'sectionHeaderFontSize', defaults.sectionHeaderFontSize, 10, 40),
          globalScale: number('globalScale', defaults.globalScale, .5, 2),
          lineSpacing: number('lineSpacing', defaults.lineSpacing, 1, 2.5),
          chartWidth: number('chartWidth', defaults.chartWidth, 320, 1200),
          useNashville:
              c['useNashville'] is bool ? c['useNashville'] as bool : false,
          displayMode: ChartDisplayMode.values
                  .where((v) => v.name == c['displayMode'])
                  .firstOrNull ??
              defaults.displayMode,
        ),
        offsets: Map.unmodifiable({
          if (d['offsets'] is Map)
            for (final e in (d['offsets'] as Map).entries)
              if (e.key is String &&
                  (e.key as String).isNotEmpty &&
                  e.value is int &&
                  e.value >= -12 &&
                  e.value <= 12)
                e.key as String: e.value as int,
        }),
      );
    } catch (_) {
      return const UserPreferences();
    }
  }
}

abstract interface class UserPreferencesStore {
  Future<UserPreferences> read(String uid);
  Future<void> write(String uid, UserPreferences value);
}

/// Like navigation storage, writes are serialized and always capture their UID.
class SharedUserPreferencesStore implements UserPreferencesStore {
  Future<void> _queue = Future.value();
  @override
  Future<UserPreferences> read(String uid) async {
    await _queue;
    final prefs = await SharedPreferences.getInstance();
    try {
      return UserPreferences.decode(prefs.getString('wf.preferences.$uid'));
    } catch (_) {
      return const UserPreferences();
    }
  }

  @override
  Future<void> write(String uid, UserPreferences value) {
    final encoded = jsonEncode(value.toJson());
    final next = _queue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString('wf.preferences.$uid', encoded)) {
        throw StateError('Could not store user preferences.');
      }
    });
    _queue = next.catchError((Object _) {});
    return next;
  }
}

final userPreferencesStoreProvider =
    Provider<UserPreferencesStore>((ref) => SharedUserPreferencesStore());

class UserPreferencesState {
  const UserPreferencesState(this.uid, this.value, {this.loading = false});
  final String? uid;
  final UserPreferences value;
  final bool loading;
}

class UserPreferencesController extends StateNotifier<UserPreferencesState> {
  UserPreferencesController(String? uid, this.store)
      : super(UserPreferencesState(uid, const UserPreferences(),
            loading: uid != null)) {
    restored = uid == null ? Future.value() : _restore(uid);
    unawaited(restored);
  }
  final UserPreferencesStore store;
  late final Future<void> restored;
  bool _themeEdited = false, _chartEdited = false;
  final Set<String> _offsetsEdited = {};
  Future<void> _restore(String uid) async {
    UserPreferences saved;
    try {
      saved = await store.read(uid);
    } catch (_) {
      saved = const UserPreferences();
    }
    if (!mounted) return;
    final current = state.value;
    state = UserPreferencesState(
        uid,
        UserPreferences(
          theme: _themeEdited ? current.theme : saved.theme,
          chart: _chartEdited ? current.chart : saved.chart,
          offsets: Map.unmodifiable({
            ...saved.offsets,
            for (final id in _offsetsEdited) id: current.offsets[id]!
          }),
        ));
    if (_themeEdited || _chartEdited || _offsetsEdited.isNotEmpty) _persist();
  }

  void _persist() {
    if (state.uid != null && !state.loading) {
      unawaited(store.write(state.uid!, state.value).catchError((Object _) {}));
    }
  }

  void setTheme(ThemeMode mode) {
    _themeEdited = true;
    _set(UserPreferences(
        theme: mode, chart: state.value.chart, offsets: state.value.offsets));
  }

  void setChart(ChartSettings chart) {
    _chartEdited = true;
    _set(UserPreferences(
        theme: state.value.theme, chart: chart, offsets: state.value.offsets));
  }

  void setOffset(String id, int offset) {
    if (id.isEmpty) return;
    _offsetsEdited.add(id);
    _set(UserPreferences(
        theme: state.value.theme,
        chart: state.value.chart,
        offsets: Map.unmodifiable(
            {...state.value.offsets, id: offset.clamp(-12, 12)})));
  }

  void _set(UserPreferences value) {
    if (!mounted) return;
    state = UserPreferencesState(state.uid, value, loading: state.loading);
    _persist();
  }
}

final userPreferencesProvider =
    StateNotifierProvider<UserPreferencesController, UserPreferencesState>(
        (ref) {
  final uid = ref.watch(currentUserProvider.select((user) => user?.id));
  return UserPreferencesController(
      uid, ref.watch(userPreferencesStoreProvider));
});
