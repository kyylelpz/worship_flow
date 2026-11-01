import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_flow/core/firebase/firebase_providers.dart';
import 'package:worship_flow/core/firebase/navigation_resume.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/models/app_user.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/groups/providers/group_providers.dart';
import 'package:worship_flow/features/groups/screens/group_selection_screen.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/setlists/screens/setlists_screen.dart';
import 'package:worship_flow/features/songs/providers/song_catalog_provider.dart';
import 'firebase_foundation_test.dart' as accounts;
import 'song_repository_test.dart' as data;

class RestoredProfile extends accounts.AccountFake {
  RestoredProfile(this.ready, AppUser user) : super(user);
  final Completer<void> ready;
  @override
  Stream<AppUser?> watchUser() async* {
    await ready.future;
    yield current;
    yield* changes.stream;
  }
}

Future<(ProviderContainer, RestoredProfile)> coldLaunch(
    WidgetTester t, ResumeStore store, Completer<void> ready,
    {AppUser? user}) async {
  final fixture = data.CatalogFixture();
  final auth = RestoredProfile(ready, user ?? mockCurrentUser);
  final c = ProviderContainer(overrides: [
    useMockBackendProvider.overrideWithValue(false),
    authRepositoryProvider.overrideWithValue(auth),
    groupRepositoryProvider.overrideWithValue(fixture.groups),
    songCatalogProvider.overrideWithValue(fixture.catalog),
    setlistRepositoryProvider.overrideWithValue(fixture.setlists),
    resumeStoreProvider.overrideWithValue(store)
  ]);
  final router = c.read(routing.appRouterProvider);
  addTearDown(
      () => {router.dispose(), c.dispose(), fixture.dispose(), auth.dispose()});
  await t.pumpWidget(UncontrolledProviderScope(
      container: c, child: MaterialApp.router(routerConfig: router)));
  await t.pump(const Duration(milliseconds: 100));
  return (c, auth);
}

void main() {
  testWidgets(
      'real cold auth/profile restoration must not consume an anonymous resume result',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesResumeStore();
    await store.write(
        mockCurrentUser.id,
        const ResumeLocation(
            groupId: 'group-1', setlistId: 'setlist-1', songId: 'song-6'));
    final ready = Completer<void>();
    final (c, _) = await coldLaunch(t, store, ready);
    expect(c.read(sessionProvider).isRestoring, isTrue);
    expect(find.byType(GroupSelectionScreen), findsNothing);
    ready.complete();
    await t.pumpAndSettle();
    expect(c.read(sessionResumeProvider).valueOrNull?.location?.setlistId,
        'setlist-1');
    expect(find.byType(RehearsalScreen), findsOneWidget);
    expect(find.byType(SetlistsScreen), findsNothing);
    expect(c.read(selectedGroupIdProvider), 'group-1');
    expect(find.text(mockSongs.firstWhere((s) => s.id == 'song-6').title),
        findsOneWidget);
    await t.tap(find.byTooltip('Open setlist'));
    await t.pumpAndSettle();
    await t.tap(find.text('Back to Setlists'));
    await t.pumpAndSettle();
    expect(find.byType(SetlistsScreen), findsOneWidget);
    c.invalidate(sessionResumeProvider);
    await t.pumpAndSettle();
    expect(find.byType(SetlistsScreen), findsOneWidget);
    expect((await store.read(mockCurrentUser.id))?.setlistId, 'setlist-1');
    await c.read(sessionProvider.notifier).signOut();
    await t.pumpAndSettle();
    expect((await PreferencesResumeStore().read(mockCurrentUser.id))?.songId,
        'song-6');
  });
  for (final missing in ['group', 'setlist', 'song']) {
    testWidgets('cold auth restoration handles missing $missing', (t) async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferencesResumeStore();
      await store.write(
          mockCurrentUser.id,
          ResumeLocation(
            groupId: missing == 'group' ? 'missing' : 'group-1',
            setlistId: missing == 'setlist' ? 'missing' : 'setlist-1',
            songId: 'missing-song',
          ));
      final ready = Completer<void>();
      await coldLaunch(t, store, ready);
      ready.complete();
      await t.pumpAndSettle();
      if (missing == 'group') {
        expect(find.byType(GroupSelectionScreen), findsOneWidget);
      } else if (missing == 'setlist') {
        expect(find.byType(SetlistsScreen), findsOneWidget);
      } else {
        expect(find.byType(RehearsalScreen), findsOneWidget);
        expect(find.text(mockSongs.first.title), findsOneWidget);
      }
    });
  }
  testWidgets(
      'saved group without current membership returns to group selection',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesResumeStore();
    await store.write(
        mockUserThree.id,
        const ResumeLocation(
            groupId: 'group-2', setlistId: 'setlist-1', songId: 'song-6'));
    final ready = Completer<void>();
    final (c, _) = await coldLaunch(t, store, ready, user: mockUserThree);
    ready.complete();
    await t.pumpAndSettle();
    expect(find.byType(GroupSelectionScreen), findsOneWidget);
    expect(c.read(selectedGroupIdProvider), isNull);
    expect((await store.read(mockUserThree.id))?.setlistId, 'setlist-1');
  });
}
