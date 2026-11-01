import 'package:flutter_test/flutter_test.dart';
import 'package:worship_flow/core/mock_data/mock_songs.dart';
import 'package:worship_flow/core/models/arrangement.dart';
import 'package:worship_flow/core/models/setlist_item.dart';
import 'package:worship_flow/core/models/song.dart';
import 'package:worship_flow/core/models/user_role.dart';
import 'package:worship_flow/core/models/vocalist_key.dart';
import 'package:worship_flow/features/charts/data/chart_transformer.dart';
import 'package:worship_flow/core/models/chart_settings.dart';
import 'package:worship_flow/features/groups/data/mock_group_repository.dart';
import 'package:worship_flow/features/setlists/data/mock_setlist_repository.dart';
import 'package:worship_flow/features/songs/data/mock_song_repository.dart';
import 'package:worship_flow/features/songs/data/song_repository.dart';

const originalSource =
    '{key: G}\r\n\r\n{section: Verse}\r\n[G]Original [D/F#]source\r\n';
Arrangement draftArrangement() => const Arrangement(
    id: 'client-id',
    name: 'Band',
    bpm: 80,
    timeSignature: '4/4',
    chordProSource: originalSource);
Song draftSong() => Song(
    id: 'client-id',
    title: 'New Song',
    artist: 'Artist',
    category: 'Worship',
    vocalistKeys: const [VocalistKey(vocalistName: 'Jordan', key: 'A')],
    arrangements: [draftArrangement()],
    isFavorite: false);

class CatalogFixture {
  final catalog = InMemorySongCatalog();
  final groups = MockGroupRepository(delay: Duration.zero);
  late final setlists = MockSetlistRepository(
      delay: Duration.zero, validateItems: catalog.validateReferences);
  SongSession session = const SongSession(
      userId: 'user-1', groupId: 'group-1', role: UserRole.administrator);
  late final repo = MockSongRepository(
      catalog: catalog,
      session: () => session,
      groups: groups,
      isReferenced: (group, song, arrangement) =>
          setlists.referencesSong(group, song, arrangementId: arrangement));
  void dispose() {
    catalog.dispose();
    groups.dispose();
    setlists.dispose();
  }
}

void main() {
  late CatalogFixture f;
  setUp(() => f = CatalogFixture());
  tearDown(() => f.dispose());
  test(
      'create, reactive read, metadata edit and delete preserve canonical source',
      () async {
    final events = <List<Song>>[];
    final subscription = f.repo.watchSongs('group-1').listen(events.add);
    await f.repo.getSong('group-1', 'song-1');
    final id = await f.repo.createSong('group-1', draftSong());
    var saved = (await f.repo.getSong('group-1', id))!;
    expect(saved.id, isNot('client-id'));
    expect(saved.primaryArrangement.id, isNot('client-id'));
    final arrangementId = saved.primaryArrangement.id;
    await f.repo.updateSong(
        'group-1',
        saved.copyWith(
            title: 'Updated',
            artist: 'New artist',
            category: 'Praise',
            isFavorite: true,
            arrangements: const []));
    saved = (await f.repo.getSong('group-1', id))!;
    expect(saved.title, 'Updated');
    expect(saved.isFavorite, isTrue);
    expect(saved.primaryArrangement.id, arrangementId);
    expect(saved.primaryArrangement.chordProSource, originalSource);
    expect(() => saved.arrangements.clear(), throwsUnsupportedError);
    expect(() => saved.vocalistKeys.clear(), throwsUnsupportedError);
    await f.repo.deleteSong('group-1', id);
    expect(await f.repo.getSong('group-1', id), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(events.any((songs) => songs.any((s) => s.id == id)), isTrue);
    await subscription.cancel();
  });

  test('arrangement create/edit/duplicate/delete preserve IDs and exact source',
      () async {
    final id = await f.repo.createSong('group-1', draftSong());
    final original = (await f.repo.getSong('group-1', id))!.primaryArrangement;
    final added = await f.repo.createArrangement(
        'group-1', id, draftArrangement().copyWith(name: 'Acoustic'));
    final duplicate = await f.repo.duplicateArrangement('group-1', id, added);
    expect(duplicate, isNot(added));
    final changed = original.copyWith(
        name: 'Updated arrangement',
        bpm: 92,
        timeSignature: '6/8',
        referenceLink: 'https://example.com/chart');
    await f.repo.updateArrangement('group-1', id, changed);
    final song = (await f.repo.getSong('group-1', id))!;
    expect(song.primaryArrangement.id, original.id);
    expect(song.primaryArrangement.bpm, 92);
    expect(song.primaryArrangement.chordProSource, originalSource);
    final prepared = const ChartTransformer().prepare(
        song: song,
        arrangement: song.primaryArrangement,
        item: SetlistItem(
            songId: song.id,
            arrangementId: song.primaryArrangement.id,
            performanceKey: 'A'),
        settings: const ChartSettings());
    expect(prepared.document.source, originalSource);
    expect(prepared.document.key!.name, 'A');
    await f.repo.deleteArrangement('group-1', id, duplicate);
    await f.repo.deleteArrangement('group-1', id, added);
    await expectLater(f.repo.deleteArrangement('group-1', id, original.id),
        throwsA(isA<SongRepositoryException>()));
  });

  test(
      'metadata and arrangement validation reject incomplete or invalid values',
      () async {
    for (final invalid in [
      draftSong().copyWith(title: ''),
      draftSong().copyWith(artist: ' '),
      draftSong().copyWith(category: ''),
      draftSong().copyWith(
          vocalistKeys: const [VocalistKey(vocalistName: 'A', key: 'H')]),
      draftSong().copyWith(
          vocalistKeys: const [VocalistKey(vocalistName: '', key: 'G')]),
      draftSong().copyWith(vocalistKeys: const [
        VocalistKey(vocalistName: 'A', key: 'G'),
        VocalistKey(vocalistName: 'a', key: 'A')
      ]),
      draftSong().copyWith(arrangements: const [])
    ]) {
      await expectLater(f.repo.createSong('group-1', invalid),
          throwsA(isA<SongRepositoryException>()));
    }
    final id = await f.repo.createSong('group-1', draftSong());
    for (final invalid in [
      draftArrangement().copyWith(name: ''),
      draftArrangement().copyWith(bpm: 0),
      draftArrangement().copyWith(bpm: 401),
      draftArrangement().copyWith(referenceLink: 'javascript:alert(1)'),
      draftArrangement().copyWith(timeSignature: '5/4'),
      draftArrangement().copyWith(chordProSource: '  '),
    ]) {
      await expectLater(f.repo.createArrangement('group-1', id, invalid),
          throwsA(isA<SongRepositoryException>()));
    }
  });

  test('all writes enforce trainee permissions while reads remain available',
      () async {
    final song = mockSongs.first;
    f.session = const SongSession(
        userId: 'user-1', groupId: 'group-1', role: UserRole.worshipTrainee);
    expect(await f.repo.canManage('group-1'), isFalse);
    expect(await f.repo.getSong('group-1', song.id), isNotNull);
    for (final action in <Future<Object?> Function()>[
      () => f.repo.createSong('group-1', draftSong()),
      () => f.repo.updateSong('group-1', song),
      () => f.repo.deleteSong('group-1', song.id),
      () => f.repo.createArrangement('group-1', song.id, draftArrangement()),
      () =>
          f.repo.updateArrangement('group-1', song.id, song.primaryArrangement),
      () => f.repo
          .duplicateArrangement('group-1', song.id, song.primaryArrangement.id),
      () => f.repo
          .deleteArrangement('group-1', song.id, song.primaryArrangement.id),
    ]) {
      await expectLater(action(), throwsA(isA<SongRepositoryException>()));
    }
  });

  test('actual membership cannot be elevated by the development session role',
      () async {
    await f.groups.updateMemberRole(
        groupId: 'group-1', userId: 'user-1', role: UserRole.worshipTrainee);
    expect(await f.repo.canManage('group-1'), isFalse);
    await expectLater(f.repo.createSong('group-1', draftSong()),
        throwsA(isA<SongRepositoryException>()));
    f.session = const SongSession(
        userId: 'outsider', groupId: 'group-1', role: UserRole.administrator);
    await expectLater(f.repo.getSong('group-1', 'song-1'),
        throwsA(isA<SongRepositoryException>()));
  });

  test('access is rechecked after asynchronous work and session changes',
      () async {
    final result = f.repo.createSong('group-1', draftSong());
    f.session = const SongSession();
    await expectLater(result, throwsA(isA<SongRepositoryException>()));
    expect(f.catalog.snapshot('group-1').length, mockSongs.length);
  });

  test('group catalogs and generated IDs are isolated; leaders can manage',
      () async {
    final id = await f.repo.createSong('group-1', draftSong());
    await f.repo.updateSong(
        'group-1', mockSongs.first.copyWith(title: 'Group one title'));
    f.session = const SongSession(
        userId: 'user-1', groupId: 'group-2', role: UserRole.worshipLeader);
    expect(await f.repo.canManage('group-2'), isTrue);
    expect(await f.repo.getSong('group-2', id), isNull);
    expect((await f.repo.getSong('group-2', 'song-1'))!.title,
        mockSongs.first.title);
    await expectLater(
        f.repo.getSong('group-1', id), throwsA(isA<SongRepositoryException>()));
    await expectLater(
        f.repo.updateSong('group-2', draftSong().copyWith(title: 'Foreign')),
        throwsA(isA<SongRepositoryException>()));
    final second = await f.repo.createSong('group-2', draftSong());
    expect(second, isNot(id));
    await f.repo.deleteSong('group-2', second);
  });

  test('published and draft references prevent song and arrangement deletion',
      () async {
    for (final songId in ['song-1', 'song-8']) {
      final song = (await f.repo.getSong('group-1', songId))!;
      await expectLater(f.repo.deleteSong('group-1', song.id),
          throwsA(isA<SongRepositoryException>()));
      await expectLater(
          f.repo.deleteArrangement(
              'group-1', song.id, song.primaryArrangement.id),
          throwsA(isA<SongRepositoryException>()));
    }
    await f.repo.deleteArrangement('group-1', 'song-1', 'song-1-arr-acoustic');
    expect((await f.repo.getSong('group-1', 'song-1'))!.arrangements.length, 1);
  });

  test(
      'referenced arrangements cannot switch mode and invalidate performance keys',
      () async {
    final original =
        (await f.repo.getSong('group-1', 'song-1'))!.primaryArrangement;
    await expectLater(
        f.repo.updateArrangement('group-1', 'song-1',
            original.copyWith(chordProSource: '{key: Gm}\n[Gm]New mode')),
        throwsA(isA<SongRepositoryException>()));
    expect(
        (await f.repo.getSong('group-1', 'song-1'))!
            .primaryArrangement
            .chordProSource,
        original.chordProSource);
  });

  test('live draft reference checks block deletion and stale editor writes',
      () async {
    final songId = await f.repo.createSong('group-1', draftSong());
    final arr =
        await f.repo.createArrangement('group-1', songId, draftArrangement());
    final draft = await f.setlists.createDraft(
        groupId: 'group-1',
        name: 'New service',
        serviceDateTime: DateTime(2030));
    final item =
        SetlistItem(songId: songId, arrangementId: arr, performanceKey: 'A');
    await f.setlists.saveDraft(draft, [item]);
    await expectLater(f.repo.deleteArrangement('group-1', songId, arr),
        throwsA(isA<SongRepositoryException>()));
    await f.setlists.saveDraft(draft, []);
    await f.repo.deleteArrangement('group-1', songId, arr);
    await expectLater(f.setlists.saveDraft(draft, [item]),
        throwsA(isA<SongRepositoryException>()));
    expect((await f.setlists.getSetlist(draft))!.draftItems, isEmpty);
  });
}
