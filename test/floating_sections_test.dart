import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/core/router/route_paths.dart';
import 'package:worship_flow/features/charts/data/chordpro_parser.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/features/charts/models/chart_document.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/charts/widgets/anchored_lyric_line.dart';
import 'package:worship_flow/features/charts/providers/chart_providers.dart';
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';
import 'rehearsal_test.dart' as rehearsal;

String song({int count = 3}) =>
    '{key: C}\n${List.generate(count, (i) => '{section: ${i == 0 ? 'Intro' : i == count - 1 ? 'Outro' : 'Chorus'}}\n'
        '${List.filled(8, '[C]A line of lyrics [G]for this section').join('\n')}').join('\n')}';

Future<DisplayChart> pumpChart(WidgetTester tester,
    {int count = 3,
    double width = 360,
    double height = 400,
    double scale = 1,
    EdgeInsets padding = EdgeInsets.zero,
    bool show = true}) async {
  final chart = const ChartTransformer().display(
      const ChordProParser().parse(song(count: count)), const ChartSettings());
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
    data:
        MediaQueryData(textScaler: TextScaler.linear(scale), padding: padding),
    child: Scaffold(
        body: Center(
            child: SizedBox(
                width: width,
                height: height,
                child: ChordChartView(
                    chart: chart,
                    settings: const ChartSettings(),
                    showSections: show)))),
  )));
  await tester.pumpAndSettle();
  return chart;
}

ScrollController chartScroll(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.byKey(const ValueKey('chart-scroll')))
    .controller!;
bool selected(WidgetTester tester, String id) => tester
    .widget<Semantics>(find.byKey(ValueKey('section-state-$id')))
    .properties
    .selected!;

void main() {
  testWidgets('bubbles jump immediately and stay fixed while chart scrolls',
      (tester) async {
    final chart = await pumpChart(tester);
    final first = chart.sections.firstWhere((s) => s.label == 'Intro');
    final chorus = chart.sections.firstWhere((s) => s.label == 'Chorus');
    final bubble = find.byKey(ValueKey('section-bubble-${chorus.id}'));
    final position = tester.getRect(bubble);
    expect(selected(tester, first.id), isTrue);
    await tester.tap(bubble);
    expect(chartScroll(tester).offset, greaterThan(0));
    await tester.pump();
    expect(selected(tester, chorus.id), isTrue);
    expect(tester.getRect(bubble), position);
    expect(find.byTooltip('Expand sections'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual scrolling updates the active visible section',
      (tester) async {
    final chart = await pumpChart(tester);
    await tester.drag(
        find.byKey(const ValueKey('chart-scroll')), const Offset(0, -5000));
    await tester.pumpAndSettle();
    final outro = chart.sections.lastWhere((s) => s.label == 'Outro');
    expect(selected(tester, outro.id), isTrue);
    await tester.drag(
        find.byKey(const ValueKey('chart-scroll')), const Offset(0, 5000));
    await tester.pumpAndSettle();
    expect(
        selected(
            tester, chart.sections.firstWhere((s) => s.label == 'Intro').id),
        isTrue);
  });

  testWidgets('repeated occurrences have distinct labels, IDs and selection',
      (tester) async {
    final chart = await pumpChart(tester, count: 4);
    final repeats = chart.sections.where((s) => s.label == 'Chorus').toList();
    expect(find.widgetWithText(TextButton, 'CH1'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'CH2'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('section-bubble-${repeats[1].id}')));
    await tester.pump();
    expect(selected(tester, repeats[1].id), isTrue);
    expect(selected(tester, repeats[0].id), isFalse);
  });

  testWidgets('toggle hides only bubbles and is pinned immediately after A+',
      (tester) async {
    final container = await rehearsal.launch(tester,
        route: RoutePaths.setlistRehearsalFor('setlist-1'));
    const arrangementId = 'song-1-arr-full';
    container.read(personalTransposeProvider(arrangementId).notifier).state = 2;
    container
        .read(chartSettingsProvider.notifier)
        .update((s) => s.copyWith(lyricsFontSize: 24));
    await tester.pumpAndSettle();

    final controller = chartScroll(tester);
    await tester.drag(
        find.byKey(const ValueKey('chart-scroll')), const Offset(0, -120));
    await tester.pumpAndSettle();
    final offset = controller.offset;
    final lyricBounds = tester.getRect(find.byType(AnchoredLyricLine).first);
    final settings = container.read(chartSettingsProvider);
    final personal = container.read(personalTransposeProvider(arrangementId));
    final plus = tester.getRect(find.byTooltip('Larger chart text'));
    final toggle = tester.getRect(find.byTooltip('Hide Sections'));
    expect(toggle.left, greaterThanOrEqualTo(plus.right));
    expect(toggle.top, plus.top);
    final overlay =
        tester.getRect(find.byKey(const ValueKey('section-bubbles')));
    expect(overlay.top, greaterThanOrEqualTo(toggle.bottom));
    await tester.tap(find.byTooltip('Hide Sections'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('section-bubbles')), findsNothing);
    expect(chartScroll(tester), same(controller));
    expect(controller.offset, offset);
    expect(tester.getRect(find.byType(AnchoredLyricLine).first), lyricBounds);
    expect(container.read(chartSettingsProvider), same(settings));
    expect(container.read(personalTransposeProvider(arrangementId)), personal);
    await tester.tap(find.byTooltip('Show Sections'));
    await tester.pumpAndSettle();
    expect(controller.offset, offset);
    expect(find.byKey(const ValueKey('section-bubbles')), findsOneWidget);
  });

  testWidgets(
      'long bubble lists scroll independently on narrow scaled safe-area layouts',
      (tester) async {
    await pumpChart(tester,
        count: 20,
        width: 240,
        height: 260,
        scale: 2.5,
        padding: const EdgeInsets.fromLTRB(8, 0, 20, 18));
    final list = find.byKey(const ValueKey('section-bubbles'));
    final bounds = tester.getRect(list);
    final view = tester.getRect(find.byType(ChordChartView));
    expect(bounds.right, lessThanOrEqualTo(view.right - 20));
    expect(bounds.bottom, lessThanOrEqualTo(view.bottom - 18));
    final firstButton = tester.getSize(find.widgetWithText(TextButton, 'IN'));
    expect(firstButton.width, greaterThanOrEqualTo(48));
    expect(firstButton.height, greaterThanOrEqualTo(48));
    final scroll = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(chartScroll(tester).offset, 0);
    expect(tester.takeException(), isNull);
    await pumpChart(tester, count: 20, width: 700, height: 180, scale: 1.5);
    expect(tester.getRect(list).height, lessThanOrEqualTo(180));
    expect(tester.takeException(), isNull);
  });
}
