import 'package:flutter/material.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/core/firebase/firebase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:worship_flow/core/mock_data/mock_setlists.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/core/router/route_paths.dart';
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/charts/data/source_chart_adapter.dart';
import 'package:worship_flow/features/charts/providers/chart_providers.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'package:worship_flow/features/setlists/data/mock_setlist_repository.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/setlists/screens/setlist_editor_screen.dart';
import 'package:worship_flow/features/setlists/widgets/setlist_card.dart';
import 'package:worship_flow/features/setlists/widgets/upcoming_service_card.dart';

Future<ProviderContainer> launch(WidgetTester tester,
    {String? route, UserRole role = UserRole.administrator}) async {
  final repository = MockSetlistRepository(delay: Duration.zero);
  final container = ProviderContainer(overrides: [
    useMockBackendProvider.overrideWithValue(true),
    setlistRepositoryProvider.overrideWithValue(repository),
  ]);
  addTearDown(() {
    container.dispose();
    repository.dispose();
  });
  final auth = container.read(sessionProvider.notifier);
  auth.updateProfile(mockCurrentUser);
  auth.setRoleForTesting(role);
  auth.selectGroup('group-1');
  final router = container.read(routing.appRouterProvider);
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  if (route != null) {
    router.go(route);
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open setlist'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('toolbar keeps action targets stable across transpose values',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(left: 8, right: 12);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await launch(tester,
        route: RoutePaths.setlistRehearsalFor('setlist-1'));
    final transpose =
        container.read(personalTransposeProvider('song-1-arr-full').notifier);
    final controls = [
      find.byType(DropdownButton<ChartDisplayMode>),
      find.byTooltip('Transpose down'),
      find.byKey(const ValueKey('transpose-value')),
      find.byTooltip('Transpose up'),
      find.byTooltip('Smaller chart text'),
      find.byTooltip('Larger chart text'),
      find.byTooltip('Hide Sections'),
    ];

    for (final scale in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final width in [320.0, 360.0, 393.0, 600.0]) {
        tester.view.physicalSize = Size(width, 800);
        List<Rect>? baseline;
        for (final value in [0, 9, 10, 12, -9, -10, -12]) {
          transpose.state = value;
          await tester.pumpAndSettle();
          final reason = 'width $width, scale $scale, transpose $value';
          expect(tester.takeException(), isNull, reason: reason);
          expect(
              find.descendant(of: controls[2], matching: find.text('$value')),
              findsOneWidget,
              reason: reason);
          final bounds = controls.map(tester.getRect).toList();
          baseline ??= bounds;
          expect(bounds, baseline, reason: reason);
          for (var i = 0; i < bounds.length; i++) {
            final rect = bounds[i];
            expect(rect.left, greaterThanOrEqualTo(8), reason: reason);
            expect(rect.right, lessThanOrEqualTo(width - 12), reason: reason);
            if (i != 0 && i != 2) {
              expect(rect.size, const Size(48, 48), reason: reason);
            }
            for (final previous in bounds.take(i)) {
              expect(rect.overlaps(previous), isFalse, reason: reason);
            }
          }
          if (width == 320) {
            expect(bounds[4].top, greaterThanOrEqualTo(bounds[3].bottom),
                reason: reason);
          }
          if (width == 600) {
            expect(bounds[4].top, bounds[3].top, reason: reason);
          }
        }
      }
    }
    tester.view.physicalSize = const Size(320, 800);
    await tester.pumpAndSettle();
    await tester.tap(controls.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(ChartDisplayMode.chordsOnly.label).last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(container.read(chartSettingsProvider).displayMode,
        ChartDisplayMode.chordsOnly);
  });

  test('source adapter groups sections without changing chord symbols', () {
    final sections = sourceChartSections(
        '{key: G}\n{section: Intro}\n[G/B]Hello\n{section: Chorus}\n[C]World');
    expect(sections.map((s) => s.label), ['Chart', 'Intro', 'Chorus']);
    expect(sections[1].source, '[G/B]Hello');
    expect(sourceChartSections(' \n'), isEmpty);
  });

  testWidgets('setlist card opens rehearsal directly with first published song',
      (tester) async {
    await launch(tester);
    await tester.tap(find
        .descendant(
          of: find.byType(SetlistCard).last,
          matching: find.byType(InkWell),
        )
        .first);
    await tester.pumpAndSettle();
    expect(
        GoRouterState.of(tester.element(find.byType(RehearsalScreen))).uri.path,
        RoutePaths.setlistRehearsalFor('setlist-1'));
    expect(find.byType(RehearsalScreen), findsOneWidget);
    expect(find.text('Anchor of the Morning'), findsOneWidget);
    expect(find.text('Key of G · 4/4'), findsOneWidget);
  });

  testWidgets('upcoming card opens rehearsal without details', (tester) async {
    await launch(tester);
    await tester.tap(find
        .descendant(
          of: find.byType(UpcomingServiceCard),
          matching: find.byType(InkWell),
        )
        .first);
    await tester.pumpAndSettle();
    expect(
        GoRouterState.of(tester.element(find.byType(RehearsalScreen))).uri.path,
        RoutePaths.setlistRehearsalFor('setlist-2'));
    expect(find.text('Mercy Like a River'), findsOneWidget);
  });

  testWidgets('drawer selection and swipes stay synchronized and reset scroll',
      (tester) async {
    final container = await launch(tester,
        route: RoutePaths.setlistRehearsalFor('setlist-1'));
    container
        .read(chartSettingsProvider.notifier)
        .update((s) => s.copyWith(lyricsFontSize: 40, globalScale: 2));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('chart-scroll')), const Offset(0, -300));
    await tester.pumpAndSettle();
    ScrollController chartScroll() => tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('chart-scroll')))
        .controller!;
    expect(chartScroll().offset, greaterThan(0));
    final offset = chartScroll().offset;
    await openDrawer(tester);
    // Dismissing the drawer preserves the current chart and scroll position.
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    expect(chartScroll().offset, offset);
    await openDrawer(tester);
    await tester.tap(find.byKey(const ValueKey('setlist-song-1')));
    await tester.pumpAndSettle();
    expect(find.text('Open Hands'), findsOneWidget);
    expect(chartScroll().offset, 0);
    await tester.drag(
        find.byKey(const ValueKey('song-swipe')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Silent Hallelujah'), findsOneWidget);
    await openDrawer(tester);
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('setlist-song-2')))
            .selected,
        isTrue);
    await tester.tapAt(const Offset(700, 300));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('song-swipe')), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Open Hands'), findsOneWidget);
    expect(chartScroll().offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('floating sections are separate from setlist drawer',
      (tester) async {
    await launch(tester, route: RoutePaths.setlistRehearsalFor('setlist-1'));
    expect(find.widgetWithText(TextButton, 'CH'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'CH'));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('chart-scroll')))
        .controller!;
    expect(scroll.offset, greaterThan(0));
    expect(find.byType(Drawer), findsNothing);
    await tester.tap(find.byTooltip('Hide Sections'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'CH'), findsNothing);
  });

  testWidgets('draft-only previews are marked and management reuses editor',
      (tester) async {
    await launch(tester, route: RoutePaths.setlistRehearsalFor('setlist-3'));
    expect(find.text('Draft preview · not published'), findsOneWidget);
    expect(find.text('King of Every Season'), findsOneWidget);
    await openDrawer(tester);
    await tester.tap(find.text('Edit Setlist'));
    await tester.pumpAndSettle();
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    expect(
        GoRouterState.of(tester.element(find.byType(SetlistEditorScreen)))
            .uri
            .path,
        RoutePaths.setlistEditorFor('setlist-3'));
  });

  testWidgets(
      'deleting through management refreshes rehearsal to missing state',
      (tester) async {
    await launch(tester, route: RoutePaths.setlistRehearsalFor('setlist-1'));
    await openDrawer(tester);
    await tester.tap(find.text('Edit Setlist'));
    await tester.pumpAndSettle();
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Setlist not found.'), findsOneWidget);
    expect(
        GoRouterState.of(tester.element(find.byType(RehearsalScreen))).uri.path,
        RoutePaths.setlistRehearsalFor('setlist-1'));
  });

  testWidgets('trainee cannot preview unpublished songs or manage a setlist',
      (tester) async {
    await launch(tester,
        route: RoutePaths.setlistRehearsalFor('setlist-3'),
        role: UserRole.worshipTrainee);
    expect(find.text('No published songs available.'), findsOneWidget);
    expect(find.byType(ChordChartView), findsNothing);
    await openDrawer(tester);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Edit Setlist'), findsNothing);
    expect(find.text('Edit Setlist'), findsNothing);
  });

  testWidgets('empty and missing setlists offer a safe return to list',
      (tester) async {
    final container = await launch(tester);
    final id = await tester.runAsync(() => container
        .read(setlistRepositoryProvider)
        .createDraft(
            groupId: 'group-1',
            name: 'Empty',
            serviceDateTime: DateTime(2030)));
    final router = container.read(routing.appRouterProvider);
    router.go(RoutePaths.setlistRehearsalFor(id!));
    await tester.pumpAndSettle();
    expect(find.textContaining('No songs in this setlist.'), findsOneWidget);
    expect(find.byType(ChordChartView), findsNothing);
    router.go(RoutePaths.setlistRehearsalFor('missing'));
    await tester.pumpAndSettle();
    expect(find.text('Setlist not found.'), findsOneWidget);
    await tester.tap(find.text('Back to Setlists'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, RoutePaths.setlists);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing song or arrangement does not crash rehearsal',
      (tester) async {
    // Override the detail lookup without changing the shared data model.
    final setlist = mockSetlists.first.copyWith(publishedItems: [
      mockSetlists.first.publishedItems.first
          .copyWith(arrangementId: 'missing'),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        useMockBackendProvider.overrideWithValue(true),
        setlistByIdProvider(setlist.id).overrideWith((ref) async => setlist)
      ],
      child: const MaterialApp(home: RehearsalScreen(setlistId: 'setlist-1')),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Song or arrangement unavailable.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
