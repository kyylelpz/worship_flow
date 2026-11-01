import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/mock_data/mock_songs.dart';
import '../../../core/models/arrangement.dart';
import '../../../core/models/setlist_item.dart';
import '../../../core/models/song.dart';
import '../../../core/models/vocalist_key.dart';
import '../../groups/data/group_repository.dart';
import '../../charts/data/chordpro_parser.dart';
import '../../charts/models/chord_symbol.dart';
import 'song_repository.dart';
import 'song_validation.dart';

/// Internal shared storage; independent catalogs retain fixture IDs per group.
/// Only repositories mutate it. Setlist saves use its synchronous reference check.
class InMemorySongCatalog {
  InMemorySongCatalog(
      {Iterable<String> groupIds = const ['group-1', 'group-2']}) {
    for (final id in groupIds) {
      _songs[id] = [for (final song in mockSongs) _freeze(song)];
    }
  }
  final Map<String, List<Song>> _songs = {};
  final _changes = StreamController<String>.broadcast(sync: true);
  List<Song> snapshot(String groupId) =>
      List.unmodifiable(_songs[groupId] ?? const []);
  Stream<String> get changes => _changes.stream;
  void _put(String groupId, Song song) {
    final songs = _songs.putIfAbsent(groupId, () => []);
    final index = songs.indexWhere((s) => s.id == song.id);
    if (index < 0) {
      songs.add(_freeze(song));
    } else {
      songs[index] = _freeze(song);
    }
    _changes.add(groupId);
  }

  void _remove(String groupId, String songId) {
    _songs[groupId]?.removeWhere((s) => s.id == songId);
    _changes.add(groupId);
  }

  static Song _freeze(Song song) => song.copyWith(
      arrangements: List.unmodifiable(song.arrangements),
      vocalistKeys: List.unmodifiable(song.vocalistKeys));
  void validateReferences(String groupId, List<SetlistItem> items) {
    final songs = snapshot(groupId);
    for (final item in items) {
      if (MusicalKey.tryParse(item.performanceKey) == null) {
        throw const SongRepositoryException(
            'Choose a vocalist key for each song before saving.');
      }
      final song = songs.where((s) => s.id == item.songId).firstOrNull;
      if (song == null ||
          !song.arrangements.any((a) => a.id == item.arrangementId)) {
        throw const SongRepositoryException(
            'A selected song or arrangement no longer exists. Re-select it before saving.');
      }
    }
  }

  void dispose() => unawaited(_changes.close());
}

class MockSongRepository implements SongRepository {
  MockSongRepository(
      {required this.catalog,
      required this.session,
      required this.groups,
      required this.isReferenced});
  final InMemorySongCatalog catalog;
  final SongSession Function() session;
  final GroupRepository groups;

  /// Synchronous in-memory check, performed immediately before destructive writes.
  final bool Function(String groupId, String songId, String? arrangementId)
      isReferenced;
  static const _uuid = Uuid();

  Future<void> _authorize(String groupId, {bool write = false}) async {
    final before = session();
    if (before.userId == null || before.groupId != groupId) {
      throw const SongRepositoryException(
          'Select an authorized worship group first.');
    }
    final group = await groups.getGroup(groupId);
    final current = session();
    final membership =
        group?.members.where((m) => m.user.id == current.userId).firstOrNull;
    if (current.userId != before.userId ||
        current.groupId != groupId ||
        membership == null ||
        (write &&
            (!(current.role?.canManageSongs ?? false) ||
                !membership.role.canManageSongs))) {
      throw const SongRepositoryException(
          'You do not have permission for this song operation.');
    }
  }

  Song _find(String groupId, String songId) =>
      catalog.snapshot(groupId).where((s) => s.id == songId).firstOrNull ??
      (throw const SongRepositoryException('Song not found in this group.'));
  Arrangement _arrangement(Song song, String id) =>
      song.arrangements.where((a) => a.id == id).firstOrNull ??
      (throw const SongRepositoryException('Arrangement not found.'));
  Arrangement _clean(Arrangement a, {String? id}) => Arrangement(
      id: id ?? a.id,
      name: a.name.trim(),
      bpm: a.bpm,
      timeSignature: a.timeSignature.trim(),
      chordProSource: a.chordProSource,
      referenceLink: a.referenceLink.trim());
  Song _metadata(Song song) => song.copyWith(
          title: song.title.trim(),
          artist: song.artist.trim(),
          category: song.category.trim(),
          vocalistKeys: [
            for (final v in song.vocalistKeys)
              VocalistKey(
                  vocalistName: v.vocalistName.trim(), key: v.key.trim())
          ]);

  @override
  Stream<List<Song>> watchSongs(String groupId) => Stream.multi((controller) {
        var cancelled = false;
        var pending = Future<void>.value();
        void request() {
          pending = pending.then((_) async {
            if (cancelled) return;
            try {
              await _authorize(groupId);
              if (!cancelled) controller.add(catalog.snapshot(groupId));
            } catch (error, stack) {
              if (!cancelled) controller.addError(error, stack);
            }
          });
        }

        final subscription = catalog.changes
            .where((id) => id == groupId)
            .listen((_) => request());
        controller.onCancel = () {
          cancelled = true;
          unawaited(subscription.cancel());
        };
        request();
      });
  @override
  Future<Song?> getSong(String groupId, String songId) async {
    await _authorize(groupId);
    return catalog.snapshot(groupId).where((s) => s.id == songId).firstOrNull;
  }

  @override
  Future<bool> canManage(String groupId) async {
    try {
      await _authorize(groupId, write: true);
      return true;
    } on SongRepositoryException {
      return false;
    }
  }

  @override
  Future<String> createSong(String groupId, Song song) async {
    await _authorize(groupId, write: true);
    SongValidation.song(song);
    if (song.arrangements.isEmpty) {
      throw const SongRepositoryException('Add at least one arrangement.');
    }
    for (final a in song.arrangements) {
      SongValidation.arrangement(a);
    }
    final id = _uuid.v4();
    final created = _metadata(Song(
        id: id,
        title: song.title,
        artist: song.artist,
        category: song.category,
        vocalistKeys: song.vocalistKeys,
        isFavorite: song.isFavorite,
        arrangements: [
          for (final a in song.arrangements) _clean(a, id: _uuid.v4())
        ]));
    catalog._put(groupId, created);
    return id;
  }

  @override
  Future<void> updateSong(String groupId, Song song) async {
    await _authorize(groupId, write: true);
    final existing = _find(groupId, song.id);
    SongValidation.song(song);
    catalog._put(
        groupId, _metadata(song.copyWith(arrangements: existing.arrangements)));
  }

  @override
  Future<void> deleteSong(String groupId, String songId) async {
    await _authorize(groupId, write: true);
    _find(groupId, songId);
    if (isReferenced(groupId, songId, null)) {
      throw const SongRepositoryException(
          'This song is used in a published or draft setlist. Remove those references before deleting.');
    }
    catalog._remove(groupId, songId);
  }

  @override
  Future<String> createArrangement(
      String groupId, String songId, Arrangement arrangement) async {
    await _authorize(groupId, write: true);
    final song = _find(groupId, songId);
    SongValidation.arrangement(arrangement);
    final id = _uuid.v4();
    catalog._put(
        groupId,
        song.copyWith(
            arrangements: [...song.arrangements, _clean(arrangement, id: id)]));
    return id;
  }

  @override
  Future<void> updateArrangement(
      String groupId, String songId, Arrangement arrangement) async {
    await _authorize(groupId, write: true);
    final song = _find(groupId, songId);
    final existing = _arrangement(song, arrangement.id);
    SongValidation.arrangement(arrangement);
    final oldKey = const ChordProParser().parse(existing.chordProSource).key;
    final updatedChart =
        const ChordProParser().parse(arrangement.chordProSource);
    final newKey = updatedChart.key;
    final hasLetters = updatedChart.sections
        .expand((s) => s.lines)
        .expand((l) => l.chords)
        .any((c) => c.symbol != null && c.symbol!.rootDegree == null);
    if (hasLetters &&
        oldKey != null &&
        newKey != null &&
        oldKey.isMinor != newKey.isMinor &&
        isReferenced(groupId, songId, arrangement.id)) {
      throw const SongRepositoryException(
          'A referenced letter-source arrangement cannot change major/minor mode. Duplicate it for the new mode.');
    }
    catalog._put(
        groupId,
        song.copyWith(arrangements: [
          for (final a in song.arrangements)
            a.id == arrangement.id ? _clean(arrangement) : a
        ]));
  }

  @override
  Future<String> duplicateArrangement(
      String groupId, String songId, String arrangementId) async {
    await _authorize(groupId, write: true);
    final song = _find(groupId, songId);
    final existing = _arrangement(song, arrangementId);
    final id = _uuid.v4();
    catalog._put(
        groupId,
        song.copyWith(arrangements: [
          ...song.arrangements,
          _clean(existing.copyWith(name: '${existing.name} (Copy)'), id: id)
        ]));
    return id;
  }

  @override
  Future<void> deleteArrangement(
      String groupId, String songId, String arrangementId) async {
    await _authorize(groupId, write: true);
    final song = _find(groupId, songId);
    _arrangement(song, arrangementId);
    if (isReferenced(groupId, songId, arrangementId)) {
      throw const SongRepositoryException(
          'This arrangement is used in a published or draft setlist. Remove those references before deleting.');
    }
    if (song.arrangements.length == 1) {
      throw const SongRepositoryException(
          'A song must keep at least one arrangement.');
    }
    catalog._put(
        groupId,
        song.copyWith(
            arrangements: song.arrangements
                .where((a) => a.id != arrangementId)
                .toList()));
  }
}
