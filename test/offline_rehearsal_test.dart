import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/profile/screens/chart_settings_screen.dart';
// Test-only SDK doubles; Firestore exposes no public snapshot constructors.
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worship_flow/core/cache/cache_providers.dart';
import 'package:worship_flow/core/cache/content_cache_database.dart';
import 'package:worship_flow/core/cache/local_content_cache.dart';
import 'package:worship_flow/core/cache/offline_reads.dart';
import 'package:worship_flow/core/firebase/content_codec.dart';
import 'package:worship_flow/core/firebase/firebase_providers.dart';
import 'package:worship_flow/core/firebase/navigation_resume.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/mock_data/mock_setlists.dart';
import 'package:worship_flow/core/mock_data/mock_users.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/router/app_router.dart' as routing;
import 'package:worship_flow/features/auth/providers/auth_providers.dart';
import 'package:worship_flow/features/auth/data/firebase_auth_repository.dart';
import 'package:worship_flow/features/rehearsal/screens/rehearsal_screen.dart';
import 'package:worship_flow/features/charts/widgets/chord_chart_view.dart';
import 'package:worship_flow/features/charts/providers/chart_providers.dart';

class GoogleInfo extends Fake implements UserInfo {
  @override
  String get providerId => 'google.com';
}

class NativeUser extends Fake implements User {
  NativeUser(this.uid, {this.verified = true});
  @override
  final String uid;
  final bool verified;
  @override
  bool get emailVerified => verified;
  @override
  List<UserInfo> get providerData => [GoogleInfo()];
}

class NativeAuth extends Fake implements FirebaseAuth {
  Completer<void>? restoration;
  User? user = NativeUser(mockCurrentUser.id);
  final events = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() async* {
    await restoration?.future;
    yield user;
    yield* events.stream;
  }
}

class Metadata extends Fake implements SnapshotMetadata {
  Metadata(this.isFromCache);
  @override
  final bool isFromCache;
  @override
  bool get hasPendingWrites => false;
}

class Doc extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  Doc(this.id, this.value, {bool cached = false}) : metadata = Metadata(cached);
  @override
  final String id;
  final Map<String, dynamic>? value;
  @override
  final SnapshotMetadata metadata;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

class QueryDoc extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  QueryDoc(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  Map<String, dynamic> data() => value;
}

class QueryData extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  QueryData(this.docs, {bool cached = false}) : metadata = Metadata(cached);
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  final SnapshotMetadata metadata;
}

class Document extends Fake implements DocumentReference<Map<String, dynamic>> {
  Document(this.remote, this.path);
  final Remote remote;
  @override
  final String path;
  final events =
      StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
  final _latest = ValueNotifier<Doc?>(null);
  Doc? get latest => _latest.value;
  set latest(Doc? value) => _latest.value = value;
  void emit(Map<String, dynamic>? value) {
    latest = Doc(path.split('/').last, value);
    events.add(latest!);
  }

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get(
      [GetOptions? options]) async {
    remote.requests++;
    if (latest != null) return latest!;
    throw remote.error;
  }

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots(
      {bool includeMetadataChanges = false,
      ListenSource source = ListenSource.defaultSource}) async* {
    remote.requests++;
    yield latest ?? Doc(path.split('/').last, null, cached: true);
    yield* events.stream;
  }
}

class Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  Collection(this.remote);
  final Remote remote;
  final events =
      StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  final _latest = ValueNotifier<QueryData?>(null);
  QueryData? get latest => _latest.value;
  set latest(QueryData? value) => _latest.value = value;
  void disconnect() {
    latest = QueryData(latest?.docs ?? [], cached: true);
    events.add(latest!);
  }

  void emit(List<CachedDocument> docs) {
    latest = QueryData([for (final d in docs) QueryDoc(d.id, d.data)]);
    events.add(latest!);
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots(
      {bool includeMetadataChanges = false,
      ListenSource source = ListenSource.defaultSource}) async* {
    remote.requests++;
    yield latest ?? QueryData([], cached: true);
    yield* events.stream;
  }
}

class Remote extends Fake implements FirebaseFirestore {
  String code = 'unavailable';
  int requests = 0;
  FirebaseException get error =>
      FirebaseException(plugin: 'cloud_firestore', code: code);
  final documents = <String, Document>{};
  final collections = <String, Collection>{};
  @override
  Document doc(String path) =>
      documents.putIfAbsent(path, () => Document(this, path));
  @override
  Collection collection(String path) =>
      collections.putIfAbsent(path, () => Collection(this));
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> action,
      {Duration timeout = const Duration(seconds: 30),
      int maxAttempts = 5}) async {
    requests++;
    throw error;
  }

  Future<void> close() async {
    for (final d in documents.values) {
      unawaited(d.events.close());
    }
    for (final c in collections.values) {
      unawaited(c.events.close());
    }
  }
}

final stamp = Timestamp.fromMillisecondsSinceEpoch(1000);
Map<String, dynamic> get profile => {
      'firstName': 'Jordan',
      'lastName': 'Rivera',
      'email': mockCurrentUser.email,
      'profileComplete': true,
      'allowInvitations': true
    };
Map<String, dynamic> get member => {
      'uid': mockCurrentUser.id,
      'groupId': 'group-1',
      'role': 'administrator',
      'position': 'vocalist',
      'firstName': 'Jordan',
      'lastName': 'Rivera',
      'createdAt': stamp,
      'updatedAt': stamp
    };
Map<String, dynamic> get group => {
      'name': 'Cached Team',
      'churchName': 'Church',
      'accentColorValue': 0xff2563eb,
      'createdAt': stamp,
      'updatedAt': stamp
    };
List<CachedDocument> get songs =>
    [for (final s in mockSongs) CachedDocument(s.id, songData('group-1', s))];
CachedDocument setlist({int revision = 1}) => CachedDocument(
    mockSetlists.first.id,
    {...setlistData(mockSetlists.first), 'revision': revision});
Future<void> seed(LocalContentCache cache, {bool complete = true}) async {
  final uid = mockCurrentUser.id;
  await cache.saveMetadata('', CachedKind.profile, uid, profile);
  await cache.saveMetadata('group-1', CachedKind.access, 'group-1',
      {'uid': uid, 'member': member, 'group': group});
  await cache.collection(cache.begin('group-1'), CachedKind.songs,
      complete ? songs : songs.take(1).toList(),
      fromServer: true, pendingWrites: false);
  await cache.collection(
      cache.begin('group-1'), CachedKind.setlists, [setlist()],
      fromServer: true, pendingWrites: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ContentCacheDatabase db;
  late NativeAuth auth;
  late Remote remote;
  late LocalContentCache cache;
  WidgetTester? currentTester;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = ContentCacheDatabase(NativeDatabase.memory());
    auth = NativeAuth();
    remote = Remote();
    cache = LocalContentCache(db, () => auth.currentUser?.uid);
    currentTester = null;
  });
  tearDown(() async {
    Future<void> close() async {
      await remote.close();
      unawaited(auth.events.close());

      await db.close();
    }

    if (currentTester != null) {
      await currentTester!.runAsync(close);
    } else {
      await close();
    }
  });
  Future<ProviderContainer> launch(WidgetTester t) async {
    currentTester = t;
    auth.restoration = Completer<void>();
    await PreferencesResumeStore().write(
        mockCurrentUser.id,
        ResumeLocation(
            groupId: 'group-1',
            setlistId: mockSetlists.first.id,
            songId: 'song-6'));
    // Recreate the session facade, retaining only SQLite and Firebase identity.
    cache = LocalContentCache(db, () => auth.currentUser?.uid);
    final c = ProviderContainer(overrides: [
      useMockBackendProvider.overrideWithValue(false),
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(remote),
      localContentCacheProvider.overrideWithValue(cache)
    ]);
    final router = c.read(routing.appRouterProvider);
    addTearDown(() {
      router.dispose();
      c.dispose();
    });
    await t.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp.router(routerConfig: router)));
    auth.restoration!.complete();
    await t.pumpAndSettle();
    return c;
  }

  test(
      'offline bundle requires all referenced arrangements and prior membership; retains exact source',
      () async {
    await seed(cache, complete: false);
    await expectLater(
        cache.rehearsal('group-1', mockSetlists.first.id), throwsStateError);
    expect(await cache.offlineSetlists('group-1'), isEmpty);
    await seed(cache);
    final bundle = await cache.rehearsal('group-1', mockSetlists.first.id);
    expect(bundle.songs.first.primaryArrangement.chordProSource,
        mockSongs.first.primaryArrangement.chordProSource);
    await cache.revoke(mockCurrentUser.id, 'group-1');
    await expectLater(
        cache.rehearsal('group-1', bundle.setlist.id), throwsStateError);
  });
  test(
      'Google profile restores offline only for verified same UID; permission denial purges cached access',
      () async {
    await seed(cache);
    final repo = FirebaseAuthRepository(auth, remote, cache: cache);
    expect((await repo.getCurrentUser())!.profileComplete, true);
    auth.user = NativeUser(mockCurrentUser.id, verified: false);
    await expectLater(repo.getCurrentUser(), throwsA(isA<Exception>()));
    auth.user = NativeUser('different-account');
    cache.switchAccount(auth.user!.uid);
    await expectLater(repo.getCurrentUser(), throwsA(isA<Exception>()));
    auth.user = NativeUser(mockCurrentUser.id);
    cache.switchAccount(auth.user!.uid);
    await seed(cache);
    remote.code = 'permission-denied';
    await expectLater(repo.getCurrentUser(), throwsA(isA<Exception>()));
    expect(await cache.metadata(CachedKind.profile), isEmpty);
  });
  test(
      'network fallback is distinct from authorization failures and failed results do not erase cache',
      () async {
    await seed(cache);
    final denied =
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    expect(isConnectionFailure(denied), false);
    await expectLater(
        cachedThenRemote(
                () => Future.value([1]), Stream<List<int>>.error(denied))
            .toList(),
        throwsA(denied));
    expect(
        await cachedThenRemote(
                () => Future.value([1]), Stream<List<int>>.error(remote.error))
            .toList(),
        [
          [1],
          [1]
        ]);
    expect(
        (await cache.rehearsal('group-1', mockSetlists.first.id))
            .setlist
            .revision,
        1);
  });
  testWidgets(
      'cold restart without network resumes cached last song; chart operations issue no reads',
      (t) async {
    await t.runAsync(() => seed(cache));
    final c = await launch(t);
    expect(find.byType(RehearsalScreen), findsOneWidget);
    expect(find.text('Offline · Cached charts · Read only'), findsOneWidget);
    expect(find.text(mockSongs.firstWhere((s) => s.id == 'song-6').title),
        findsOneWidget);
    expect(c.read(currentRoleProvider), UserRole.worshipTrainee);
    final before = remote.requests;
    c.read(personalTransposeProvider('song-6-arr-full').notifier).state = 2;
    await t.pumpAndSettle();
    expect(find.byType(ChordChartView), findsOneWidget);
    c.read(chartSettingsProvider.notifier).update((value) => value.copyWith(
        useNashville: true,
        displayMode: ChartDisplayMode.chordsOnly,
        globalScale: 1.2,
        lyricsFontSize: 20));
    await t.pumpAndSettle();
    expect(
        t
            .widget<ChordChartView>(find.byType(ChordChartView))
            .settings
            .useNashville,
        true);
    await t.drag(find.byType(ChordChartView), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(find.text(mockSongs.first.title), findsOneWidget);
    expect(remote.requests, before);
    expect(t.takeException(), isNull);
  });
  testWidgets('incomplete cached setlist gives actionable offline message',
      (t) async {
    await t.runAsync(() => seed(cache, complete: false));
    await launch(t);
    expect(find.textContaining('not fully cached'), findsOneWidget);
    expect(find.byType(ChordChartView), findsNothing);
    expect(find.text('Back to Setlists'), findsOneWidget);
  });
  testWidgets(
      'reconnection refreshes data and indicator; revoked membership removes chart',
      (t) async {
    await t.runAsync(() => seed(cache));
    final c = await launch(t);
    remote.doc('profiles/${mockCurrentUser.id}').emit(profile);
    remote
        .collection('profiles/${mockCurrentUser.id}/memberships')
        .emit([const CachedDocument('group-1', {})]);
    await t.pumpAndSettle();
    remote.doc('groups/group-1').emit(group);
    remote
        .collection('groups/group-1/members')
        .emit([CachedDocument(mockCurrentUser.id, member)]);
    final changed = [
      for (final d in songs)
        CachedDocument(d.id, {...d.data, 'title': 'Updated ${d.id}'})
    ];
    remote.collection('groups/group-1/songs').emit(changed);
    remote.collection('groups/group-1/setlists').emit([setlist(revision: 2)]);
    await t.pumpAndSettle();
    expect(find.text('Offline · Cached charts · Read only'), findsNothing);
    expect(find.text('Updated song-6'), findsOneWidget);
    expect(c.read(currentRoleProvider), UserRole.administrator);
    remote.collection('groups/group-1/songs').disconnect();
    remote.collection('groups/group-1/setlists').disconnect();
    await t.pumpAndSettle();
    expect(find.text('Offline · Cached charts · Read only'), findsOneWidget);
    expect(c.read(currentRoleProvider), UserRole.worshipTrainee);
    expect(find.text('Updated song-6'), findsOneWidget);
    remote.collection('groups/group-1/songs').emit(changed);
    remote.collection('groups/group-1/setlists').emit([setlist(revision: 2)]);
    await t.pumpAndSettle();
    expect(find.text('Offline · Cached charts · Read only'), findsNothing);

    expect(
        (await cache.rehearsal('group-1', mockSetlists.first.id))
            .setlist
            .revision,
        2);
    await cache.collection(
        cache.begin('group-1'), CachedKind.setlists, [setlist(revision: 1)],
        fromServer: true, pendingWrites: false);
    expect(
        (await cache.readSetlist('group-1', mockSetlists.first.id))!.revision,
        2);
    remote.collection('profiles/${mockCurrentUser.id}/memberships').emit([]);
    await t.pumpAndSettle();
    expect(find.byType(ChordChartView), findsNothing);
    expect(await cache.hasOfflineAccess('group-1'), false);
  });
  test('slow cached reads never replace a newer remote result or its freshness',
      () async {
    final pending = Completer<List<int>>();
    final remoteEvents = StreamController<List<int>>();
    final values = <List<int>>[];
    var cachedEmissions = 0;
    final subscription = cachedThenRemote(
        () => pending.future, remoteEvents.stream,
        onCached: () => cachedEmissions++).listen(values.add);
    remoteEvents.add([2]);
    await Future<void>.delayed(Duration.zero);
    pending.complete([1]);
    await Future<void>.delayed(Duration.zero);
    expect(values, [
      [2]
    ]);
    expect(cachedEmissions, 0);
    await subscription.cancel();
    await remoteEvents.close();
  });
  testWidgets('deletion and account switching never retain a protected chart',
      (t) async {
    await t.runAsync(() => seed(cache));
    await launch(t);
    // A confirmed server collection deletion removes the cached setlist.
    remote.collection('groups/group-1/setlists').emit([]);
    await t.pumpAndSettle();
    expect(find.byType(ChordChartView), findsNothing);
    expect(find.textContaining('unavailable offline'), findsOneWidget);
    auth.user = NativeUser('another-account');
    cache.switchAccount(auth.user!.uid);
    auth.events.add(auth.user);
    await t.pumpAndSettle();
    expect(find.byType(ChordChartView), findsNothing);
    expect(await t.runAsync(() => cache.hasOfflineAccess('group-1')), false);
  });
  test(
      'published offline availability is independent of missing draft references',
      () async {
    await seed(cache);
    final published = setlist();
    final value = {
      ...published.data,
      'draftItems': [
        {
          'songId': 'missing',
          'arrangementId': 'missing',
          'performanceKey': 'E',
          'vocalistName': null
        }
      ]
    };
    await cache.document(
        cache.begin('group-1'), CachedKind.setlists, published.id, value,
        fromServer: true, pendingWrites: false);
    expect(
        (await cache.rehearsal('group-1', published.id)).setlist.publishedItems,
        hasLength(mockSetlists.first.publishedItems.length));
    await cache.document(cache.begin('group-1'), CachedKind.setlists,
        published.id, {...value, 'status': 'draft', 'revision': 2},
        fromServer: true, pendingWrites: false);
    await expectLater(
        cache.rehearsal('group-1', published.id), throwsStateError);
  });
  test('incomplete cached profile never grants offline group access', () async {
    await seed(cache);
    await cache.saveMetadata('', CachedKind.profile, mockCurrentUser.id,
        {...profile, 'profileComplete': false});
    expect(await cache.hasOfflineAccess('group-1'), false);
    await expectLater(
        cache.rehearsal('group-1', mockSetlists.first.id), throwsStateError);
  });
}
