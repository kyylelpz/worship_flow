import 'package:flutter/material.dart';
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
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'package:worship_flow/features/setlists/data/mock_setlist_repository.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/setlists/screens/setlist_details_screen.dart';
import 'package:worship_flow/features/setlists/screens/setlist_editor_screen.dart';
import 'package:worship_flow/features/setlists/widgets/setlist_card.dart';
import 'package:worship_flow/features/setlists/widgets/upcoming_service_card.dart';

Future<ProviderContainer> launch(WidgetTester tester,
    {String? route, UserRole role = UserRole.administrator}) async {
  final repository = MockSetlistRepository(delay: Duration.zero);
  final container = ProviderContainer(overrides: [
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
    expect(find.byType(SetlistDetailsScreen), findsNothing);
    expect(find.text('Anchor of the Morning'), findsOneWidget);
    expect(find.text('Key G · 1/3'), findsOneWidget);
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
    expect(find.byType(SetlistDetailsScreen), findsNothing);
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

  testWidgets('section rail is separate from setlist drawer', (tester) async {
    await launch(tester, route: RoutePaths.setlistRehearsalFor('setlist-1'));
    await tester.tap(find.byTooltip('Expand sections'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Chorus'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Chorus'));
    await tester.pumpAndSettle();
    final scroll = tester
        .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('chart-scroll')))
        .controller!;
    expect(scroll.offset, greaterThan(0));
    expect(find.byType(Drawer), findsNothing);
    await tester.tap(find.byTooltip('Collapse sections'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Chorus'), findsNothing);
  });

  testWidgets('draft-only previews are marked and management reuses editor',
      (tester) async {
    await launch(tester, route: RoutePaths.setlistRehearsalFor('setlist-3'));
    expect(find.text('Draft preview · not published'), findsOneWidget);
    expect(find.text('King of Every Season'), findsOneWidget);
    await openDrawer(tester);
    await tester.tap(find.text('Reorder'));
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
    await tester.tap(find.text('Details & management'));
    await tester.pumpAndSettle();
    expect(find.byType(SetlistDetailsScreen), findsOneWidget);
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
    expect(find.text('Reorder'), findsNothing);
    expect(find.text('Details & management'), findsNothing);
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
