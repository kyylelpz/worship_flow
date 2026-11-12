import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_flow/app/app.dart';
import 'package:worship_flow/features/groups/screens/group_selection_screen.dart';
import 'package:worship_flow/core/firebase/firebase_providers.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/models/app_user.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/core/preferences/user_preferences.dart';
import 'package:worship_flow/core/theme/theme_providers.dart';
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/charts/providers/chart_providers.dart';
import 'package:worship_flow/features/charts/widgets/chord_label.dart';
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';
import 'navigation_resume_restart_test.dart' as restart;

final account = StateProvider<AppUser?>((ref) => mockCurrentUser);
const customChart = ChartSettings(
    lyricsFontSize: 23,
    chordsFontSize: 28,
    sectionHeaderFontSize: 31,
    globalScale: 1.5,
    lineSpacing: 2,
    chordSpacing: 16,
    lightChordColor: ChordColorPreset.teal,
    darkChordColor: ChordColorPreset.peach,
    chartWidth: 960,
    useNashville: true,
    displayMode: ChartDisplayMode.chordsOnly);
ProviderContainer launch({UserPreferencesStore? store}) {
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWith((ref) => ref.watch(account)),
    if (store != null) userPreferencesStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> ready(ProviderContainer c) =>
    c.read(userPreferencesProvider.notifier).restored;
void expectChart(ChartSettings actual, ChartSettings expected) {
  expect(UserPreferences(chart: actual).toJson()['chart'],
      UserPreferences(chart: expected).toJson()['chart']);
}

class DelayedStore implements UserPreferencesStore {
  final reads = <String, Completer<UserPreferences>>{};
  final writes = <String, UserPreferences>{};
  @override
  Future<UserPreferences> read(String uid) =>
      (reads[uid] = Completer<UserPreferences>()).future;
  @override
  Future<void> write(String uid, UserPreferences value) async {
    writes[uid] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Chord Color follows active theme and resets only that theme',
      (tester) async {
    final c = launch();
    await ready(c);
    Future<void> show(ThemeData theme) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: theme, home: const ChartSettingsScreen()),
      ));
      await tester.scrollUntilVisible(find.text('Chord Color'), 120);
      await tester.ensureVisible(find.byType(ChordLabel).first);
      await tester.pumpAndSettle();
    }

    Color? previewColor() =>
        tester.widget<ChordLabel>(find.byType(ChordLabel).first).style.color;
    void expectPresets(bool dark) {
      for (final preset in ChordColorPreset.values.skip(1)) {
        expect(find.byTooltip(preset.label),
            preset.dark == dark ? findsOneWidget : findsNothing);
      }
    }

    final light = ThemeData.light();
    final dark = ThemeData.dark();
    await show(light);
    expectPresets(false);
    expect(previewColor(), light.colorScheme.primary);
    await tester.ensureVisible(find.byTooltip('Teal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Teal'));
    await tester.pumpAndSettle();
    expect(previewColor(), const Color(0xFF006F70));
    await show(dark);
    expectPresets(true);
    expect(previewColor(), const Color(0xFF8CB8FF));
    expect(tester.getTopLeft(find.byTooltip('Sky Blue')).dx,
        lessThan(tester.getTopLeft(find.byTooltip('Soft Yellow')).dx));
    await tester.ensureVisible(find.byTooltip('Peach'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Peach'));
    await tester.pumpAndSettle();
    expect(previewColor(), const Color(0xFFFFB48E));
    await show(light);
    expect(previewColor(), const Color(0xFF006F70));
    await show(dark);
    expect(previewColor(), const Color(0xFFFFB48E));
    await tester.ensureVisible(find.byTooltip('Reset chord color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reset chord color'));
    await tester.pumpAndSettle();
    expect(previewColor(), const Color(0xFF8CB8FF));
    expect(
        c.read(chartSettingsProvider).lightChordColor, ChordColorPreset.teal);
    expect(c.read(chartSettingsProvider).darkChordColor,
        ChordColorPreset.themeDefault);
  });
  testWidgets('Chart Settings slider updates chord spacing', (tester) async {
    final c = launch();
    await ready(c);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: ChartSettingsScreen()),
    ));
    await tester.scrollUntilVisible(find.text('Chord Spacing'), 100);
    final slider = find.descendant(
        of: find.widgetWithText(Card, 'Chord Spacing'),
        matching: find.byType(Slider));
    final initial = tester.widget<Slider>(slider);
    expect((initial.min, initial.max, initial.value), (0, 24, 8));
    initial.onChanged!(16);
    await tester.pump();
    expect(c.read(chartSettingsProvider).chordSpacing, 16);
    expect(tester.widget<Slider>(slider).value, 16);
  });
  test(
      'all chart fields, theme and arrangement offsets survive a fresh container/store',
      () async {
    final c = launch();
    await ready(c);
    c.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    c.read(chartSettingsProvider.notifier).update((_) => customChart);
    c.read(personalTransposeProvider('arrangement-a').notifier).state = 3;
    c.read(personalTransposeProvider('arrangement-b').notifier).state = -2;
    await c.read(userPreferencesStoreProvider).read(mockCurrentUser.id);
    final restarted = launch(store: SharedUserPreferencesStore());
    // Construct consumers while storage is pending, as on a real restart.
    restarted.read(themeModeProvider);
    restarted.read(chartSettingsProvider);
    restarted.read(personalTransposeProvider('arrangement-a'));
    await ready(restarted);
    expect(restarted.read(themeModeProvider), ThemeMode.dark);
    expectChart(restarted.read(chartSettingsProvider), customChart);
    expect(restarted.read(personalTransposeProvider('arrangement-a')), 3);
    expect(restarted.read(personalTransposeProvider('arrangement-b')), -2);
  });
  test('UID changes, sign-out and returning account never share preferences',
      () async {
    final c = launch();
    await ready(c);
    c.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    c.read(personalTransposeProvider('same-arrangement').notifier).state = 5;
    final store = c.read(userPreferencesStoreProvider);
    await store.read(mockCurrentUser.id);
    c.read(account.notifier).state = mockUserTwo;
    await ready(c);
    expect(c.read(themeModeProvider), ThemeMode.light);
    expect(c.read(personalTransposeProvider('same-arrangement')), 0);
    c.read(chartSettingsProvider.notifier).update((_) => customChart);
    c.read(personalTransposeProvider('same-arrangement').notifier).state = -4;
    await store.read(mockUserTwo.id);
    c.read(account.notifier).state = null;
    await ready(c);
    expect(c.read(personalTransposeProvider('same-arrangement')), 0);
    c.read(themeModeProvider.notifier).setMode(ThemeMode.system);
    c.read(account.notifier).state = mockCurrentUser;
    await ready(c);
    expect(c.read(themeModeProvider), ThemeMode.dark);
    expectChart(c.read(chartSettingsProvider), const ChartSettings());
    expect(c.read(personalTransposeProvider('same-arrangement')), 5);
    expect((await store.read(mockUserTwo.id)).offsets['same-arrangement'], -4);
  });
  test('chart reset and theme reset persist independently and retain offsets',
      () async {
    final c = launch();
    await ready(c);
    c.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    c.read(chartSettingsProvider.notifier).update((_) => customChart);
    c.read(personalTransposeProvider('a').notifier).state = 2;
    c.read(chartSettingsProvider.notifier).reset();
    final store = c.read(userPreferencesStoreProvider);
    var saved = await store.read(mockCurrentUser.id);
    expect(saved.theme, ThemeMode.dark);
    expectChart(saved.chart, const ChartSettings());
    expect(saved.offsets['a'], 2);
    c.read(chartSettingsProvider.notifier).update((_) => customChart);
    c.read(themeModeProvider.notifier).reset();
    saved = await store.read(mockCurrentUser.id);
    expect(saved.theme, ThemeMode.light);
    expectChart(saved.chart, customChart);
    final restart = launch();
    await ready(restart);
    expect(restart.read(themeModeProvider), ThemeMode.light);
    expectChart(restart.read(chartSettingsProvider), customChart);
    expect(restart.read(personalTransposeProvider('a')), 2);
  });
  test('malformed, outdated, unknown and unsafe fields fall back safely',
      () async {
    for (final text in [
      '{broken',
      'null',
      '[]',
      '{"version":99}',
      '{"theme":"dark"}'
    ]) {
      final value = UserPreferences.decode(text);
      expect(value.theme, ThemeMode.light);
      expectChart(value.chart, const ChartSettings());
    }
    final value = UserPreferences.decode(jsonEncode({
      'version': 1,
      'theme': 'unknown',
      'chart': {
        'lyricsFontSize': -1,
        'chordsFontSize': 'large',
        'globalScale': 500,
        'sectionHeaderFontSize': null,
        'lineSpacing': .1,
        'chordSpacing': 25,
        'lightChordColor': 'peach',
        'darkChordColor': 'unrecognized',
        'chartWidth': 0,
        'useNashville': 'yes',
        'displayMode': 'old-name',
      },
      'offsets': {
        'good': -12,
        'tooBig': 13,
        'fraction': 1.5,
        'text': '2',
        '': 3
      },
    }));
    expectChart(value.chart, const ChartSettings());
    expect(
        UserPreferences.decode('{"version":1,"chart":{}}').chart.chordSpacing,
        8);
    expect(value.offsets, {'good': -12});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wf.preferences.${mockCurrentUser.id}', 17);
    expect((await SharedUserPreferencesStore().read(mockCurrentUser.id)).theme,
        ThemeMode.light);
  });
  test('late previous-account read cannot overwrite active account', () async {
    final store = DelayedStore();
    final c = launch(store: store);
    c.read(themeModeProvider);
    c.read(account.notifier).state = mockUserTwo;
    final secondReady = ready(c);
    store.reads[mockUserTwo.id]!
        .complete(const UserPreferences(theme: ThemeMode.system));
    await secondReady;
    store.reads[mockCurrentUser.id]!
        .complete(const UserPreferences(theme: ThemeMode.dark));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(themeModeProvider), ThemeMode.system);
    expect(c.read(userPreferencesProvider).uid, mockUserTwo.id);
    expect(store.writes, isEmpty);
  });
  test('changes during restoration merge without losing other saved fields',
      () async {
    final store = DelayedStore();
    final c = launch(store: store);
    c.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    c.read(personalTransposeProvider('a').notifier).state = 4;
    store.reads[mockCurrentUser.id]!.complete(
        const UserPreferences(chart: customChart, offsets: {'a': 1, 'b': -2}));
    await ready(c);
    expect(c.read(themeModeProvider), ThemeMode.dark);
    expectChart(c.read(chartSettingsProvider), customChart);
    expect(c.read(personalTransposeProvider('a')), 4);
    expect(c.read(personalTransposeProvider('b')), -2);
    expect(store.writes[mockCurrentUser.id]!.offsets, {'a': 4, 'b': -2});
  });
  testWidgets(
      'account content waits for preferences; first visible account theme is restored',
      (t) async {
    final store = DelayedStore();
    final authReady = Completer<void>();
    final auth = restart.RestoredProfile(authReady, mockCurrentUser);
    final c = ProviderContainer(overrides: [
      useMockBackendProvider.overrideWithValue(true),
      authRepositoryProvider.overrideWithValue(auth),
      userPreferencesStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(() {
      c.dispose();
      auth.dispose();
    });
    await t.pumpWidget(
        UncontrolledProviderScope(container: c, child: const WorshipFlowApp()));
    await t.pump();
    authReady.complete();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(c.read(userPreferencesProvider).loading, isTrue);
    expect(find.text('Choose a Group'), findsNothing);
    store.reads[mockCurrentUser.id]!.complete(
        const UserPreferences(theme: ThemeMode.dark, chart: customChart));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(c.read(userPreferencesProvider).loading, isFalse);
    expect(c.read(themeModeProvider), ThemeMode.dark);
    expect(t.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark);
    expectChart(c.read(chartSettingsProvider), customChart);
    await t.pumpAndSettle();
    expect(find.byType(GroupSelectionScreen), findsOneWidget);
  });
}
