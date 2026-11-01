import '../../../core/cache/content_cache_database.dart';
import '../../../core/cache/local_content_cache.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../../core/firebase/content_codec.dart';
import '../../../core/models/arrangement.dart';
import '../../../core/models/song.dart';
import '../../charts/data/chordpro_parser.dart';
import 'song_repository.dart';
import 'song_validation.dart';

class FirestoreSongRepository implements SongRepository {
  FirestoreSongRepository(this.db, this.auth, this.selectedGroup, {this.cache});
  final LocalContentCache? cache;
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final String? Function() selectedGroup;
  void _scope(String g) {
    if (auth.currentUser == null || selectedGroup() != g) {
      throw const SongRepositoryException(
          'Select an authorized worship group first.');
    }
  }

  DocumentReference<Map<String, dynamic>> _song(String g, String id) =>
      db.doc('groups/$g/songs/$id');
  @override
  Stream<List<Song>> watchSongs(String groupId) {
    _scope(groupId);
    final uid = auth.currentUser!.uid;
    final lease = cache?.begin(groupId);
    return db
        .collection('groups/$groupId/songs')
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snapshot) async {
      _scope(groupId);
      if (auth.currentUser?.uid != uid) throw StateError('Account changed.');
      final songs = snapshot.docs.map((d) => songFromData(d.data())).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
      await cache?.collection(lease, CachedKind.songs,
          [for (final d in snapshot.docs) CachedDocument(d.id, d.data())],
          fromServer: !snapshot.metadata.isFromCache,
          pendingWrites: snapshot.metadata.hasPendingWrites);
      return songs;
    });
  }

  @override
  Future<Song?> getSong(String groupId, String songId) async {
    _scope(groupId);
    final uid = auth.currentUser!.uid;
    final lease = cache?.begin(groupId);
    final doc = await _song(groupId, songId)
        .get(const GetOptions(source: Source.server));
    _scope(groupId);
    if (auth.currentUser?.uid != uid) throw StateError('Account changed.');
    final song = doc.exists ? songFromData(doc.data()!) : null;
    await cache?.document(lease, CachedKind.songs, songId, doc.data(),
        fromServer: !doc.metadata.isFromCache,
        pendingWrites: doc.metadata.hasPendingWrites);
    return song;
  }

  @override
  Future<bool> canManage(String groupId) async {
    try {
      _scope(groupId);
      final d = await db
          .doc('groups/$groupId/members/${auth.currentUser!.uid}')
          .get(const GetOptions(source: Source.server));
      return ['administrator', 'worshipLeader'].contains(d.data()?['role']);
    } catch (_) {
      return false;
    }
  }

  void _validate(Song s) {
    SongValidation.song(s);
    if (s.title.trim().length > 200 ||
        s.artist.trim().length > 200 ||
        s.category.trim().length > 80) {
      throw const SongRepositoryException(
          'Use at most 200 characters for title/artist and 80 for category.');
    }
    if (s.arrangements.isEmpty ||
        s.arrangements.length > 8 ||
        s.vocalistKeys.length > 8) {
      throw const SongRepositoryException(
          'A song needs 1–8 arrangements and at most 8 vocal presets.');
    }
    for (final a in s.arrangements) {
      SongValidation.arrangement(a);
      if (a.chordProSource.length > 200000 ||
          a.name.trim().length > 120 ||
          a.referenceLink.trim().length > 2048) {
        throw const SongRepositoryException(
            'Arrangement fields exceed the supported chart/name/link size.');
      }
    }
  }

  Future<void> _mutate(
      String g, String id, Song? Function(Song?, Map<String, dynamic>) change,
      {Set<String>? readUses = const {}}) async {
    _scope(g);
    final uid = auth.currentUser!.uid;
    await db.runTransaction((tx) async {
      final ref = _song(g, id);
      final old = await tx.get(ref);
      final before = old.exists ? songFromData(old.data()!) : null;
      final entries = <String, dynamic>{};
      for (final a in (before?.arrangements ?? <Arrangement>[])
          .where((a) => readUses == null || readUses.contains(a.id))) {
        final registration = await tx.get(db.doc('groups/$g/catalog/${a.id}'));
        entries[a.id] = registration.data();
      }
      final next = change(before, entries);
      _scope(g);
      if (auth.currentUser!.uid != uid) {
        throw const SongRepositoryException('Account changed. Retry.');
      }
      if (next != null) {
        _validate(next);
      }
      final prior = {
        for (final a in before?.arrangements ?? <Arrangement>[]) a.id
      };
      final after = {
        for (final a in next?.arrangements ?? <Arrangement>[]) a.id
      };
      for (final removed in prior.difference(after)) {
        if ((entries[removed]['uses'] as List).isNotEmpty) {
          throw const SongRepositoryException(
              'This song or arrangement is used in a published or draft setlist. Remove those references first.');
        }
        tx.delete(db.doc('groups/$g/catalog/$removed'));
      }
      for (final added in after.difference(prior)) {
        tx.set(db.doc('groups/$g/catalog/$added'), {
          'songId': id,
          'uses': <String>[],
          'target': id,
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
      if (next == null) {
        tx.delete(ref);
      } else {
        tx.set(ref, {
          ...songData(g, next),
          'arrangementChanges': {
            ...?before?.arrangements.map((a) => a.id),
            ...next.arrangements.map((a) => a.id)
          }
              .where((key) => !sameContentValue(
                  (old.data()?['arrangements'] as Map?)?[key],
                  (songData(g, next)['arrangements'] as Map)[key]))
              .toList(),
          'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
    });
  }

  @override
  Future<String> createSong(String g, Song song) async {
    if (song.arrangements.length > 2) {
      throw const SongRepositoryException(
          'Create the song with up to two arrangements, then add more from Edit Song.');
    }
    if (song.vocalistKeys.length > 4) {
      throw const SongRepositoryException(
          'Create the song with up to four vocal presets, then add more from Edit Song.');
    }
    final id = const Uuid().v4();
    final created = Song(
        id: id,
        title: song.title,
        artist: song.artist,
        category: song.category,
        isFavorite: song.isFavorite,
        vocalistKeys: song.vocalistKeys,
        arrangements: [
          for (final a in song.arrangements)
            Arrangement(
                id: const Uuid().v4(),
                name: a.name,
                bpm: a.bpm,
                timeSignature: a.timeSignature,
                chordProSource: a.chordProSource,
                referenceLink: a.referenceLink)
        ]);
    await _mutate(g, id, (_, __) => created);
    return id;
  }

  Song _required(Song? s) =>
      s ?? (throw const SongRepositoryException('Song not found.'));
  @override
  Future<void> updateSong(String g, Song s, {Song? expected}) =>
      _mutate(g, s.id, (old, _) {
        if (expected != null) checkSongEdit(old, expected);
        return s.copyWith(arrangements: _required(old).arrangements);
      });
  @override
  Future<void> deleteSong(String g, String id) async {
    final lease = cache?.begin(g);
    await _mutate(g, id, (old, _) {
      _required(old);
      return null;
    }, readUses: null);
    await cache?.document(lease, CachedKind.songs, id, null,
        fromServer: true, pendingWrites: false);
  }

  @override
  Future<String> createArrangement(String g, String id, Arrangement a) async {
    final key = const Uuid().v4();
    final created = Arrangement(
        id: key,
        name: a.name,
        bpm: a.bpm,
        timeSignature: a.timeSignature,
        chordProSource: a.chordProSource,
        referenceLink: a.referenceLink);
    await _mutate(
        g,
        id,
        (old, _) => _required(old)
            .copyWith(arrangements: [...old!.arrangements, created]));
    return key;
  }

  @override
  Future<void> updateArrangement(String g, String id, Arrangement a,
          {Arrangement? expected}) =>
      _mutate(g, id, (old, entries) {
        if (expected != null) {
          checkArrangementEdit(
              old?.arrangements.where((v) => v.id == a.id).firstOrNull,
              expected);
        }
        final song = _required(old);
        final previous =
            song.arrangements.where((v) => v.id == a.id).firstOrNull;
        if (previous == null) {
          throw const SongRepositoryException('Arrangement not found.');
        }
        final before =
            const ChordProParser().parse(previous.chordProSource).key;
        final chart = const ChordProParser().parse(a.chordProSource);
        if (before != null &&
            chart.key != null &&
            before.isMinor != chart.key!.isMinor &&
            (entries[a.id]['uses'] as List).isNotEmpty &&
            chart.sections
                .expand((s) => s.lines)
                .expand((l) => l.chords)
                .any((c) => c.symbol != null && c.symbol!.rootDegree == null)) {
          throw const SongRepositoryException(
              'Duplicate a referenced letter-source arrangement to change major/minor mode.');
        }
        return song.copyWith(arrangements: [
          for (final v in song.arrangements) v.id == a.id ? a : v
        ]);
      }, readUses: {a.id});
  @override
  Future<String> duplicateArrangement(
      String g, String id, String arrangementId) async {
    final song = await getSong(g, id);
    final a =
        _required(song).arrangements.firstWhere((a) => a.id == arrangementId);
    return createArrangement(g, id, a.copyWith(name: '${a.name} (Copy)'));
  }

  @override
  Future<void> deleteArrangement(String g, String id, String aid) =>
      _mutate(g, id, (old, _) {
        final song = _required(old);
        if (!song.arrangements.any((a) => a.id == aid)) {
          throw const SongRepositoryException('Arrangement not found.');
        }
        return song.copyWith(
            arrangements: song.arrangements.where((a) => a.id != aid).toList());
      }, readUses: {aid});
}
