import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/cache/content_cache_database.dart';
import 'package:worship_flow/core/cache/local_content_cache.dart';
import 'package:worship_flow/core/firebase/content_codec.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/mock_data/mock_setlists.dart';

const source =
    '  {section: Verse 1}\r\n[1]Hello  [5/1]world \n\n{start_of_grid: Verse 1}\n| 1 - - - |\n{end_of_grid}\n';
CachedDocument songDoc({String group = 'group-1', String title = 'Remote'}) {
  final song = mockSongs.first.copyWith(title: title, arrangements: [
    mockSongs.first.primaryArrangement.copyWith(chordProSource: source),
    ...mockSongs.first.arrangements.skip(1),
  ]);
  return CachedDocument(song.id,
      {...songData(group, song), 'updatedAt': Timestamp(100, 123456789)});
}

CachedDocument setlistDoc({int revision = 7}) {
  final s = mockSetlists.first;
  return CachedDocument(s.id, {
    ...setlistData(s.copyWith(draftItems: s.publishedItems.reversed.toList())),
    'revision': revision
  });
}

Future<void> populate(LocalContentCache cache,
    {String group = 'group-1'}) async {
  final lease = cache.begin(group);
  await cache.collection(lease, CachedKind.songs, [songDoc(group: group)],
      fromServer: true, pendingWrites: false);
  if (group == 'group-1') {
    await cache.collection(lease, CachedKind.setlists, [setlistDoc()],
        fromServer: true, pendingWrites: false);
  }
}

void main() {
  late ContentCacheDatabase db;
  late LocalContentCache cache;
  String? uid;
  setUp(() {
    uid = 'account-a';
    db = ContentCacheDatabase(NativeDatabase.memory());
    cache = LocalContentCache(db, () => uid);
  });
  tearDown(() async {
    await cache.settled;
    await db.close();
  });

  test(
      'typed read APIs preserve exact canonical source, arrangement IDs, presets, revisions and independent ordered versions',
      () async {
    await populate(cache);
    final songs = await cache.readSongs('group-1');
    expect(songs.complete, true);
    expect(songs.refreshedAt, isNotNull);
    final song = songs.items.single;
    expect(song.id, mockSongs.first.id);
    expect(song.vocalistKeys.map((v) => v.key),
        mockSongs.first.vocalistKeys.map((v) => v.key));
    expect(
        (await cache.readArrangement(
                'group-1', song.id, song.primaryArrangement.id))!
            .chordProSource,
        source);
    final setlist =
        (await cache.readSetlist('group-1', mockSetlists.first.id))!;
    expect(setlist.revision, 7);
    expect(setlist.publishedItems.map((i) => i.arrangementId),
        mockSetlists.first.publishedItems.map((i) => i.arrangementId));
    expect(setlist.draftItems!.map((i) => i.songId),
        mockSetlists.first.publishedItems.reversed.map((i) => i.songId));
    expect(setlist.serviceDateTime, mockSetlists.first.serviceDateTime);
    final raw = await db
        .customSelect("SELECT payload FROM cached_documents WHERE kind='songs'")
        .getSingle();
    expect(
        ContentCacheDatabase.decode(raw.read<String>('payload'))['updatedAt'],
        Timestamp(100, 123456789));
  });
  test('SQLite file survives database close and fresh connection', () async {
    await db.close();
    final dir = await Directory.systemTemp.createTemp('wf-read-cache-');
    final file = File('${dir.path}/cache.sqlite');
    final first = ContentCacheDatabase(NativeDatabase(file));
    try {
      await first
          .replace('account-a', 'group-1', CachedKind.songs, [songDoc()]);
      await first.close();
      final reopened = ContentCacheDatabase(NativeDatabase(file));
      try {
        expect(
            (await reopened.songs('account-a', 'group-1'))
                .items
                .single
                .primaryArrangement
                .chordProSource,
            source);
        expect((await reopened.songs('account-b', 'group-1')).items, isEmpty);
      } finally {
        await reopened.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
      'account and group scopes are isolated; account switch purges old account and rejects late reads',
      () async {
    await populate(cache);
    await populate(cache, group: 'group-2');
    final stale = cache.begin('group-1');
    uid = 'account-b';
    // Even before the auth stream callback, the old identity cannot be read.
    await expectLater(cache.readSongs('group-1'), throwsStateError);
    cache.switchAccount(uid);
    await cache.collection(stale, CachedKind.songs, [songDoc()],
        fromServer: true, pendingWrites: false);
    expect((await cache.readSongs('group-1')).items, isEmpty);
    expect((await db.songs('account-a', 'group-2')).items, isEmpty);
    await populate(cache);
    expect((await cache.readSongs('group-2')).items, isEmpty);
    expect((await cache.readSongs('group-1')).items, hasLength(1));
  });
  test(
      'complete refresh replaces confirmed deletions; individual reads do not imply complete collection',
      () async {
    final lease = cache.begin('group-1');
    final doc = songDoc();
    await cache.document(lease, CachedKind.songs, doc.id, doc.data,
        fromServer: true, pendingWrites: false);
    expect((await cache.readSongs('group-1')).complete, false);
    await populate(cache);
    await cache.collection(
        lease, CachedKind.songs, [songDoc(title: 'New title')],
        fromServer: true, pendingWrites: false);
    expect((await cache.readSong('group-1', doc.id))!.title, 'New title');
    await cache.document(lease, CachedKind.songs, doc.id, null,
        fromServer: true, pendingWrites: false);
    expect(await cache.readSong('group-1', doc.id), isNull);
    await cache.collection(lease, CachedKind.setlists, [],
        fromServer: true, pendingWrites: false);
    expect((await cache.readSetlists('group-1')).items, isEmpty);
    expect((await cache.readSetlists('group-1')).complete, true);
  });
  test(
      'cache, pending, partial and malformed remote results cannot erase valid snapshot',
      () async {
    await populate(cache);
    final lease = cache.begin('group-1');
    await cache.collection(lease, CachedKind.songs, [],
        fromServer: false, pendingWrites: false);
    await cache.collection(lease, CachedKind.songs, [],
        fromServer: true, pendingWrites: true);
    await cache.collection(lease, CachedKind.songs, [],
        fromServer: true, pendingWrites: false, complete: false);
    await cache.collection(
        lease, CachedKind.songs, [songDoc(), const CachedDocument('bad', {})],
        fromServer: true, pendingWrites: false);
    expect(cache.lastError, isA<FormatException>());
    expect(
        (await cache.readSongs('group-1'))
            .items
            .single
            .primaryArrangement
            .chordProSource,
        source);
    expect((await cache.readSongs('group-1')).complete, true);
    await cache.collection(
        lease, CachedKind.songs, [songDoc(title: 'Recovered')],
        fromServer: true, pendingWrites: false);
    expect((await cache.readSongs('group-1')).items.single.title, 'Recovered');
  });
  test(
      'confirmed membership revocation purges only that group and blocks in-flight repopulation',
      () async {
    await populate(cache);
    await populate(cache, group: 'group-2');
    final stale = cache.begin('group-1');
    await cache.revoke('account-a', 'group-1');
    await cache.collection(stale, CachedKind.songs, [songDoc()],
        fromServer: true, pendingWrites: false);
    await expectLater(cache.readSongs('group-1'), throwsStateError);
    expect((await db.songs('account-a', 'group-1')).items, isEmpty);
    expect((await cache.readSongs('group-2')).items, hasLength(1));
    await cache.retainAuthorizedGroups('account-a', {'group-1', 'group-2'});
    await cache.collection(stale, CachedKind.songs, [songDoc()],
        fromServer: true, pendingWrites: false);
    expect((await cache.readSongs('group-1')).items, isEmpty);
    await populate(cache);
    expect((await cache.readSongs('group-1')).items, hasLength(1));
  });
  test(
      'complete membership index removes stale groups after restart; sign-out purges account',
      () async {
    await populate(cache);
    await populate(cache, group: 'group-2');
    await cache.retainAuthorizedGroups('account-a', {'group-2'});
    expect((await db.setlists('account-a', 'group-1')).items, isEmpty);
    await expectLater(cache.readSongs('group-1'), throwsStateError);
    final stale = cache.begin('group-2');
    uid = null;
    cache.switchAccount(null);
    await cache.collection(stale, CachedKind.songs, [songDoc(group: 'group-2')],
        fromServer: true, pendingWrites: false);
    await cache.settled;
    expect((await db.songs('account-a', 'group-2')).items, isEmpty);
    await expectLater(cache.readSongs('group-2'), throwsStateError);
  });
  test(
      'malformed cached row is excluded and marked incomplete; authorized refresh repairs it',
      () async {
    await populate(cache);
    await db.customStatement(
        'UPDATE cached_documents SET payload=? WHERE kind=?',
        ['{broken', 'songs']);
    final result = await cache.readSongs('group-1');
    expect(result.items, isEmpty);
    expect(result.complete, false);
    expect((await cache.readSetlists('group-1')).complete, true);
    await populate(cache);
    expect((await cache.readSongs('group-1')).complete, true);
  });
  test(
      'SQLite transaction failure rolls back refresh instead of leaving a partial collection',
      () async {
    await populate(cache);
    await db.customStatement(
        "CREATE TRIGGER reject_cache_insert BEFORE INSERT ON cached_documents WHEN NEW.id='reject' BEGIN SELECT RAISE(ABORT,'test write failure'); END");
    final bad = songDoc();
    await cache.collection(
        cache.begin('group-1'),
        CachedKind.songs,
        [
          songDoc(title: 'Partial update'),
          CachedDocument('reject', {...bad.data, 'id': 'reject'})
        ],
        fromServer: true,
        pendingWrites: false);
    expect(cache.lastError, isNotNull);
    final saved = await cache.readSongs('group-1');
    expect(saved.complete, true);
    expect(saved.items.single.title, 'Remote');
    await db.customStatement('DROP TRIGGER reject_cache_insert');
    await populate(cache);
    expect((await cache.readSongs('group-1')).complete, true);
  });
  test(
      'corrupt SQLite file reports cache unavailability, not an empty authorized collection',
      () async {
    await db.close();
    final dir = await Directory.systemTemp.createTemp('wf-corrupt-cache-');
    try {
      final file = await File('${dir.path}/cache.sqlite')
          .writeAsString('not a SQLite database');
      db = ContentCacheDatabase(NativeDatabase(file));
      cache = LocalContentCache(db, () => uid);
      await populate(cache);
      expect(cache.lastError, isNotNull);
      await expectLater(cache.readSongs('group-1'), throwsA(isA<Exception>()));
      await db.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
      'late document reads and snapshots cannot regress cached Setlist revisions',
      () async {
    await populate(cache);
    final lease = cache.begin('group-1');
    final newer = setlistDoc(revision: 9);
    await cache.document(lease, CachedKind.setlists, newer.id, newer.data,
        fromServer: true, pendingWrites: false);
    await cache.collection(
        lease, CachedKind.setlists, [setlistDoc(revision: 8)],
        fromServer: true, pendingWrites: false);
    await cache.document(
        lease, CachedKind.setlists, newer.id, setlistDoc(revision: 7).data,
        fromServer: true, pendingWrites: false);
    expect((await cache.readSetlist('group-1', newer.id))!.revision, 9);
  });
}
