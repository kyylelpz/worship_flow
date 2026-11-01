import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_flow/core/firebase/content_codec.dart';
import 'package:worship_flow/core/firebase/firebase_providers.dart';
import 'package:worship_flow/core/firebase/navigation_resume.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/mock_data/mock_setlists.dart';
import 'package:worship_flow/core/models/app_user.dart';
import 'package:worship_flow/core/models/setlist_item.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/groups/screens/group_selection_screen.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'package:worship_flow/features/setlists/data/mock_setlist_repository.dart';
import 'package:worship_flow/features/setlists/providers/setlist_providers.dart';
import 'package:worship_flow/features/setlists/screens/setlists_screen.dart';
import 'package:worship_flow/features/setlists/screens/setlist_editor_screen.dart';
import 'firebase_foundation_test.dart' as foundation;

class TrackingSetlists extends MockSetlistRepository {
  TrackingSetlists() : super(delay: Duration.zero);
  int commits = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<String> commitSetlist(
      {required String id,
      required String groupId,
      required String name,
      required DateTime serviceDateTime,
      required List<SetlistItem> items,
      bool publish = false,
      int? expectedRevision}) async {
    commits++;
    await gate?.future;
    if (fail) throw StateError('Connection unavailable.');
    return super.commitSetlist(
        id: id,
        groupId: groupId,
        name: name,
        serviceDateTime: serviceDateTime,
        items: items,
        publish: publish,
        expectedRevision: expectedRevision);
  }
}

class MemoryResume implements ResumeStore {
  final values = <String, ResumeLocation>{};
  Completer<void>? gate;
  @override
  Future<ResumeLocation?> read(String uid) async {
    await gate?.future;
    return values[uid];
  }

  @override
  Future<void> write(String uid, ResumeLocation location) async {
    values[uid] = location;
  }
}

Future<(ProviderContainer, TrackingSetlists, foundation.AccountFake)> launch(
    WidgetTester t,
    {ResumeStore? store,
    AppUser user = mockCurrentUser,
    String? route}) async {
  final repository = TrackingSetlists();
  final account = foundation.AccountFake(user);
  final c = ProviderContainer(overrides: [
    useMockBackendProvider.overrideWithValue(true),
    authRepositoryProvider.overrideWithValue(account),
    setlistRepositoryProvider.overrideWithValue(repository),
    resumeStoreProvider.overrideWithValue(store)
  ]);
  final auth = c.read(sessionProvider.notifier);
  auth.updateProfile(user);
  auth.setRoleForTesting(UserRole.administrator);
  if (store == null) auth.selectGroup('group-1');
  final router = c.read(routing.appRouterProvider);
  addTearDown(() =>
      {router.dispose(), c.dispose(), repository.dispose(), account.dispose()});
  await t.pumpWidget(UncontrolledProviderScope(
      container: c, child: MaterialApp.router(routerConfig: router)));
  if (store is MemoryResume && store.gate != null) {
    await t.pump();
    return (c, repository, account);
  }
  await t.pumpAndSettle();
  if (route != null) {
    router.go(route);
    await t.pumpAndSettle();
  }
  return (c, repository, account);
}

Future<void> back(WidgetTester t) async {
  await t.tap(find.byTooltip('Back').first);
  await t.pumpAndSettle();
}

void main() {
  test(
      'Firestore codecs retain source byte-for-byte, IDs, presets, metadata, item ordering and independent versions',
      () {
    final song = mockSongs.first;
    final decoded = songFromData(songData('group-1', song));
    expect(decoded.arrangements.first.chordProSource,
        song.arrangements.first.chordProSource);
    expect(decoded.arrangements.first.id, song.arrangements.first.id);
    expect(decoded.vocalistKeys.first.key, song.vocalistKeys.first.key);
    expect(sameContentValue({'name': 'A', 'bpm': 90}, {'bpm': 90, 'name': 'A'}),
        isTrue);
    expect(sameContentValue({'source': 'a  '}, {'source': 'a '}), isFalse);
    final value = mockSetlists[1];
    final restored = setlistFromData(setlistData(value));
    expect(restored.publishedItems.map((i) => i.songId),
        value.publishedItems.map((i) => i.songId));
    expect(restored.draftItems!.map((i) => i.arrangementId),
        value.draftItems!.map((i) => i.arrangementId));
    expect(restored.serviceDateTime, value.serviceDateTime);
  });
  test(
      'account-scoped local preferences serialize writes and never return another UID',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferencesResumeStore();
    await Future.wait([
      store.write(
          'alice',
          const ResumeLocation(
              groupId: 'g', setlistId: 'one', songId: 'first')),
      store.write('alice',
          const ResumeLocation(groupId: 'g', setlistId: 'one', songId: 'last'))
    ]);
    expect((await PreferencesResumeStore().read('alice'))!.songId, 'last');
    expect(await store.read('bob'), isNull);
  });
  testWidgets(
      'new form creates nothing; Back Cancel stays, Discard leaves without a document',
      (t) async {
    final (c, repo, _) = await launch(t, route: '/setlists/new/edit');
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    expect(repo.commits, 0);
    await t.enterText(find.byType(TextField).first, 'Unsaved team');
    await back(t);
    expect(find.text('Save Setlist as Draft?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Unsaved team'), findsOneWidget);
    await back(t);
    await t.tap(find.text('Discard Changes'));
    await t.pumpAndSettle();
    expect(find.byType(SetlistsScreen), findsOneWidget);
    expect(repo.commits, 0);
    expect(c.read(selectedGroupIdProvider), 'group-1');
  });
  testWidgets(
      'Back Save as Draft commits once then leaves; repeated saves keep one ID',
      (t) async {
    final (_, repo, _) = await launch(t, route: '/setlists/new/edit');
    await t.enterText(find.byType(TextField).first, 'Saved team');
    await back(t);
    await t.tap(find.text('Save as Draft'));
    await t.pumpAndSettle();
    expect(repo.commits, 1);
    expect(find.byType(SetlistsScreen), findsOneWidget);
    final lists = await t.runAsync(() => repo.watchSetlists('group-1').first);
    expect(lists!.where((s) => s.name == 'Saved team').length, 1);
  });
  testWidgets(
      'existing editor uses exact dirty comparison and Discard never writes published content',
      (t) async {
    final (_, repo, _) = await launch(t, route: '/setlists/setlist-1/edit');
    final name =
        t.widget<TextField>(find.byType(TextField).first).controller!.text;
    await t.enterText(find.byType(TextField).first, 'Edited');
    await t.enterText(find.byType(TextField).first, name);
    await back(t);
    expect(find.text('Save Setlist as Draft?'), findsNothing);
    expect(repo.commits, 0);
  });
  testWidgets(
      'failed save retains local text; saving blocks double taps and system Back',
      (t) async {
    final (_, repo, _) = await launch(t, route: '/setlists/new/edit');
    repo.fail = true;
    await t.enterText(find.byType(TextField).first, 'Kept after failure');
    await t.tap(find.text('Save Draft'));
    await t.pumpAndSettle();
    expect(find.text('Kept after failure'), findsOneWidget);
    expect(find.textContaining('Your edits are kept'), findsOneWidget);
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    repo.fail = false;
    repo.gate = Completer<void>();
    await t.tap(find.text('Save Draft'));
    await t.pump();
    expect(
        t.widget<TextButton>(find.byType(TextButton).last).onPressed, isNull);
    unawaited(t.binding.handlePopRoute());
    await t.pump();
    expect(repo.commits, 2);
    expect(find.text('Save Setlist as Draft?'), findsNothing);
    repo.gate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(SetlistEditorScreen), findsOneWidget);
    await back(t);
    expect(find.text('Save Setlist as Draft?'), findsNothing);
  });
  testWidgets('route exit and Android Back use the three-action guard',
      (t) async {
    final (c, repo, _) = await launch(t, route: '/setlists/new/edit');
    await t.enterText(find.byType(TextField).first, 'Local');
    c.read(routing.appRouterProvider).go('/songs');
    await t.pumpAndSettle();
    expect(find.text('Save Setlist as Draft?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    unawaited(t.binding.handlePopRoute());
    await t.pumpAndSettle();
    expect(find.text('Save Setlist as Draft?'), findsOneWidget);
    await t.tap(find.text('Discard Changes'));
    await t.pumpAndSettle();
    expect(repo.commits, 0);
  });
  testWidgets(
      'cold restoration stays on loading then opens last setlist and song',
      (t) async {
    final store = MemoryResume()
      ..values[mockCurrentUser.id] = const ResumeLocation(
          groupId: 'group-1', setlistId: 'setlist-1', songId: 'song-6')
      ..gate = Completer<void>();
    await launch(t, store: store);
    expect(find.byType(RehearsalScreen), findsNothing);
    expect(find.byType(SetlistsScreen), findsNothing);
    expect(find.byType(GroupSelectionScreen), findsNothing);
    store.gate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(RehearsalScreen), findsOneWidget);
    expect(find.text(mockSongs.firstWhere((s) => s.id == 'song-6').title),
        findsOneWidget);
  });
  for (final missing in ['group', 'setlist', 'song']) {
    testWidgets('resume missing $missing uses the authorized fallback',
        (t) async {
      final store = MemoryResume()
        ..values[mockCurrentUser.id] = ResumeLocation(
            groupId: missing == 'group' ? 'missing' : 'group-1',
            setlistId: missing == 'setlist' ? 'missing' : 'setlist-1',
            songId: 'missing-song');
      await launch(t, store: store);
      if (missing == 'group') {
        expect(find.byType(GroupSelectionScreen), findsOneWidget);
      }
      if (missing == 'setlist') {
        expect(find.byType(SetlistsScreen), findsOneWidget);
      }
      if (missing == 'song') {
        expect(find.byType(RehearsalScreen), findsOneWidget);
        expect(find.text(mockSongs.first.title), findsOneWidget);
      }
    });
  }
  testWidgets(
      'pending restoration cannot apply the previous account destination',
      (t) async {
    final store = MemoryResume()
      ..values[mockCurrentUser.id] = const ResumeLocation(
          groupId: 'group-1', setlistId: 'setlist-1', songId: 'song-6')
      ..gate = Completer<void>();
    final (c, _, account) = await launch(t, store: store);
    account.emit(mockUserTwo);
    await t.pump();
    store.gate!.complete();
    await t.pumpAndSettle();
    expect(c.read(currentUserProvider)!.id, mockUserTwo.id);
    expect(c.read(selectedGroupIdProvider), isNull);
    expect(find.byType(GroupSelectionScreen), findsOneWidget);
  });
  testWidgets(
      'manual group switching does not reapply launch resume and clears the saved setlist',
      (t) async {
    final store = MemoryResume()
      ..values[mockCurrentUser.id] = const ResumeLocation(
          groupId: 'group-1', setlistId: 'setlist-1', songId: 'song-6');
    final (c, _, _) = await launch(t, store: store);
    c.read(sessionProvider.notifier).clearGroup();
    await t.pumpAndSettle();
    expect(find.byType(GroupSelectionScreen), findsOneWidget);
    await t.tap(find.text('Riverside Youth Band'));
    await t.pumpAndSettle();
    expect(c.read(selectedGroupIdProvider), 'group-2');
    expect(store.values[mockCurrentUser.id]!.setlistId, isNull);
  });
  testWidgets('authorized draft preview is separate from published playback',
      (t) async {
    final (c, _, _) = await launch(t, route: '/setlists/setlist-2/rehearse');
    await t.tap(find.byTooltip('Open setlist'));
    await t.pumpAndSettle();
    expect(find.text('Preview Draft'), findsOneWidget);
    await t.tap(find.text('Preview Draft'));
    await t.pumpAndSettle();
    expect(find.text('Draft preview · unpublished changes'), findsOneWidget);
    expect(find.byType(RehearsalScreen), findsOneWidget);
    expect(c.read(currentRoleProvider), UserRole.administrator);
  });
  testWidgets('another account never restores the saved account setlist',
      (t) async {
    final store = MemoryResume()
      ..values[mockCurrentUser.id] = const ResumeLocation(
          groupId: 'group-1', setlistId: 'setlist-1', songId: 'song-6');
    await launch(t, store: store, user: mockUserTwo);
    expect(find.byType(GroupSelectionScreen), findsOneWidget);
    expect(find.byType(RehearsalScreen), findsNothing);
  });
}
