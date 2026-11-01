import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/models/vocalist_key.dart';
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/charts/widgets/chord_label.dart';
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';
import 'package:worship_flow/features/songs/providers/song_providers.dart';
import 'package:worship_flow/features/songs/screens/basic_chordpro_editor_screen.dart';
import 'package:worship_flow/features/songs/screens/song_library_screen.dart';
import 'package:worship_flow/features/songs/widgets/chordpro_editing_controller.dart';
import 'song_management_test.dart' as ui;

Finder get source => find.byKey(const ValueKey('chordpro-source'));
ChordProEditingController controller(WidgetTester tester) =>
    tester.widget<TextFormField>(source).controller!
        as ChordProEditingController;

Future<Future<String?> Function()> open(WidgetTester tester, String text,
    {List<VocalistKey> presets = const [],
    UserRole role = UserRole.administrator}) async {
  await ui.launch(tester, role: role);
  final future = openChordProEditor(
      tester.element(find.byType(SongLibraryScreen)), text,
      vocalistKeys: presets);
  await tester.pumpAndSettle();
  return () => future;
}

void main() {
  testWidgets(
      'highlighting preserves whitespace and distinguishes metadata, sections, chords and lyrics',
      (tester) async {
    const text =
        '{title:  My Song}\r\n{section: Verse 1}\n\t[Bm7/F#]Hi  [5m7]there [b7/1]\n'
        '| D - G - |\n| [1] - D/F# - |\n[H7]literal {broken\n\n';
    final editor = ChordProEditingController(text: text);
    addTearDown(editor.dispose);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) {
      context = ctx;
      return const SizedBox();
    })));
    var span = editor.buildTextSpan(
        context: context,
        style: const TextStyle(color: Colors.black),
        withComposing: false);
    expect(span.toPlainText(), text);
    List<TextSpan> runs() => span.children!.cast<TextSpan>();
    expect(runs().singleWhere((r) => r.text == '{title:').style!.color,
        Colors.green.shade800);
    expect(runs().singleWhere((r) => r.text == '  My Song').style!.color,
        const Color(0xffa00080));
    expect(
        runs().singleWhere((r) => r.text == '{section: Verse 1}').style!.color,
        Colors.green.shade800);
    for (final chord in [
      '[Bm7/F#]',
      '[5m7]',
      '[b7/1]',
      'D',
      'G',
      '[1]',
      'D/F#'
    ]) {
      expect(runs().singleWhere((r) => r.text == chord).style!.color,
          Colors.teal.shade800);
    }
    expect(runs().singleWhere((r) => r.text == '[H7]').style!.color, isNull);
    editor.value = editor.value.copyWith(
        selection: const TextSelection.collapsed(offset: 4),
        composing: const TextRange(start: 1, end: 8));
    span = editor.buildTextSpan(context: context, withComposing: true);
    expect(span.toPlainText(), text);
    expect(runs().where((r) => r.style?.decoration == TextDecoration.underline),
        isNotEmpty);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(builder: (ctx) {
          context = ctx;
          return const SizedBox();
        })));
    await tester.pumpAndSettle();
    span = editor.buildTextSpan(context: context, withComposing: false);
    expect(span.toPlainText(), text);
    expect(runs().singleWhere((r) => r.text == '[5m7]').style!.color,
        Colors.tealAccent.shade100);
  });

  test(
      'history restores selections through typing, deletion, paste, wrapping and branching',
      () {
    final editor = ChordProEditingController(text: 'hello world');
    addTearDown(editor.dispose);
    editor.selection = const TextSelection(baseOffset: 11, extentOffset: 6);
    editor.insert('[', ']');
    expect(editor.text, 'hello [world]');
    expect(editor.selection.extentOffset, 12);
    editor.undo();
    expect(editor.text, 'hello world');
    expect(
        editor.selection, const TextSelection(baseOffset: 11, extentOffset: 6));
    editor.redo();
    editor.value = const TextEditingValue(
        text: 'hello [world]!', selection: TextSelection.collapsed(offset: 14));
    editor.value = const TextEditingValue(
        text: 'hello ', selection: TextSelection.collapsed(offset: 6));
    editor.value = const TextEditingValue(
        text: 'hello [5m7]\n  pasted',
        selection: TextSelection.collapsed(offset: 19));
    editor.undo();
    expect(editor.text, 'hello ');
    editor.undo();
    expect(editor.text, 'hello [world]!');
    editor.redo();
    expect(editor.text, 'hello ');
    editor.insert('{end_of_grid}');
    expect(editor.canRedo, isFalse);
    editor.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    editor.insert(' | ');
    expect(editor.text, ' |  {end_of_grid}');
  });

  test('IME composition is one reversible edit and history is bounded', () {
    final editor = ChordProEditingController(text: '');
    addTearDown(editor.dispose);
    editor.value = const TextEditingValue(
        text: 'a',
        composing: TextRange(start: 0, end: 1),
        selection: TextSelection.collapsed(offset: 1));
    editor.value = const TextEditingValue(
        text: 'ab',
        composing: TextRange(start: 0, end: 2),
        selection: TextSelection.collapsed(offset: 2));
    editor.value = editor.value.copyWith(composing: TextRange.empty);
    editor.undo();
    expect(editor.text, '');
    editor.redo();
    expect(editor.text, 'ab');
    editor.value = const TextEditingValue(
        text: 'abc',
        composing: TextRange(start: 2, end: 3),
        selection: TextSelection.collapsed(offset: 3));
    editor.insert('[', ']');
    editor.undo();
    expect(editor.text, 'abc');
    editor.undo();
    expect(editor.text, 'ab');
    for (var i = 0; i < 120; i++) {
      editor.text = '$i';
    }
    var count = 0;
    while (editor.canUndo) {
      editor.undo();
      count++;
    }
    expect(count, 100);
  });

  testWidgets(
      'toolbar shortcuts use current selection; toolbar and keyboard undo agree',
      (tester) async {
    await open(tester, 'hello world');
    final editor = controller(tester);
    await tester.tap(source);
    editor.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    await tester.pump();
    await tester.tap(find.text('[Chord]'));
    await tester.pumpAndSettle();
    expect(editor.text, 'hello [world]');
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(editor.text, 'hello world');
    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(editor.text, 'hello [world]');
    await tester.tap(source);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(editor.text, 'hello world');
    editor.selection = const TextSelection.collapsed(offset: 5);
    await tester.tap(find.text('[Chord]'));
    await tester.pumpAndSettle();
    expect(editor.text, 'hello[] world');
    expect(editor.selection.extentOffset, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'keyless preview uses song preset, chart preferences and both notations without saving',
      (tester) async {
    final future = await open(
        tester, '{section: Verse}\n[1]word [5m7/1]more\n[8]unknown',
        presets: const [VocalistKey(vocalistName: 'Jordan', key: 'E')]);
    final editor = controller(tester);
    editor.selection = const TextSelection.collapsed(offset: 22);
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordChartView), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('preview-key')))
            .controller!
            .text,
        'E');
    expect(
        tester
            .widgetList<ChordLabel>(find.byType(ChordLabel))
            .map((w) => w.text),
        containsAll(['E', 'Bm7/E']));
    expect(find.textContaining('Unsupported or ambiguous numbered chord'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Nashville'));
    await tester.tap(find.text('Nashville'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<ChordLabel>(find.byType(ChordLabel))
            .map((w) => w.text),
        contains('5m7/1'));
    await tester.tap(find.byTooltip('Edit source'));
    await tester.pumpAndSettle();
    expect(editor.selection.extentOffset, 22);
    expect(editor.text, '{section: Verse}\n[1]word [5m7/1]more\n[8]unknown');
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(await future(), editor.text);
  });

  testWidgets(
      'preview requests an explicit key when no song preset is available',
      (tester) async {
    await open(tester, '[1]word');
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a preview performance key'),
        findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('preview-key')), 'Bb');
    await tester.tap(find.byTooltip('Apply preview key'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<ChordLabel>(find.byType(ChordLabel))
            .map((w) => w.text),
        contains('Bb'));
    expect(tester.takeException(), isNull);
  });

  for (final system in [false, true]) {
    testWidgets(
        '${system ? 'Android' : 'toolbar'} Back confirms dirty source and returns null on discard',
        (tester) async {
      final future = await open(tester, 'original');
      await tester.enterText(source, 'unsaved');
      if (system) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tap(find.byTooltip('Back').first);
      }
      await tester.pumpAndSettle();
      expect(find.text('Discard source changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(controller(tester).text, 'unsaved');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(await future(), isNull);
      expect(find.byType(SongLibraryScreen), findsOneWidget);
    });
  }

  testWidgets(
      'unchanged source leaves without confirmation and Save returns exact CRLF source',
      (tester) async {
    final future = await open(tester, '[1]  word\r\n\r\n');
    controller(tester).insert('[', ']');
    controller(tester).undo();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await future(), isNull);
    final returned = openChordProEditor(
        tester.element(find.byType(SongLibraryScreen)), '[1]  word\r\n\r\n');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(await returned, '[1]  word\r\n\r\n');
  });

  testWidgets(
      'parent receives a source draft only; arrangement save owns persistence',
      (tester) async {
    final container = await ui.launch(tester, route: '/songs/song-1/edit');
    final original =
        container.read(songByIdProvider('song-1'))!.primaryArrangement;
    await tester.ensureVisible(find.text('Full Band'));
    await tester.tap(find.text('Full Band'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(source, '[1]new draft');
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(ChordChartView), findsOneWidget);
    expect(
        container
            .read(songByIdProvider('song-1'))!
            .primaryArrangement
            .chordProSource,
        original.chordProSource);
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(
        container
            .read(songByIdProvider('song-1'))!
            .primaryArrangement
            .chordProSource,
        original.chordProSource);
    await tester.tap(find.text('Save Arrangement'));
    await tester.pumpAndSettle();
    expect(
        container
            .read(songByIdProvider('song-1'))!
            .primaryArrangement
            .chordProSource,
        '[1]new draft');
  });

  testWidgets(
      'permissions disable editing, shortcuts, history and Save after revocation',
      (tester) async {
    final container = await ui.launch(tester);
    unawaited(openChordProEditor(
        tester.element(find.byType(SongLibraryScreen)), 'source'));
    await tester.pumpAndSettle();
    await tester.enterText(source, 'draft');
    container
        .read(sessionProvider.notifier)
        .setRoleForTesting(UserRole.worshipTrainee);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Save'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '[Chord]'))
            .onPressed,
        isNull);
    expect(find.textContaining('Read only:'), findsOneWidget);
    final field = tester.widget<TextField>(
        find.descendant(of: source, matching: find.byType(TextField)));
    expect(field.readOnly, isTrue);
  });

  testWidgets(
      'preview respects chart preferences and restores editor and chart scroll',
      (tester) async {
    final container = await ui.launch(tester);
    container.read(chartSettingsProvider.notifier).update((s) => s.copyWith(
        displayMode: ChartDisplayMode.chordsOnly,
        useNashville: true,
        chordsFontSize: 28));
    unawaited(openChordProEditor(tester.element(find.byType(SongLibraryScreen)),
        List.generate(80, (i) => '[1]Line $i [5m7]end').join('\n'),
        previewKey: 'E'));
    await tester.pumpAndSettle();
    final editor = controller(tester);
    final field = tester.widget<TextField>(
        find.descendant(of: source, matching: find.byType(TextField)));
    await tester.tap(source);
    await tester.pumpAndSettle();
    editor.selection = const TextSelection.collapsed(offset: 4);
    field.scrollController!.jumpTo(400);
    await tester.pumpAndSettle();
    final offset = field.scrollController!.offset;
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    final chart = tester.widget<ChordChartView>(find.byType(ChordChartView));
    expect(chart.settings.displayMode, ChartDisplayMode.chordsOnly);
    expect(chart.settings.useNashville, isTrue);
    expect(chart.settings.chordsFontSize, 28);
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('chart-scroll')))
        .controller!;
    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit source'));
    await tester.pumpAndSettle();
    expect(editor.selection.extentOffset, 4);
    expect(field.scrollController!.offset, closeTo(offset, 1));
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(scroll.offset, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow scaled keyboard layout keeps shortcuts usable in both themes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.reset);
    await ui.launch(tester);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(SongLibraryScreen)));
    for (final dark in [false, true]) {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: (dark ? ThemeData.dark() : ThemeData.light()).copyWith(
                  outlinedButtonTheme: OutlinedButtonThemeData(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)))),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.8)),
                  child: child!),
              home: const ChordProEditorScreen(source: '[1]line'))));
      await tester.pumpAndSettle();
      await tester.tap(source);
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('source-shortcuts')),
          const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
