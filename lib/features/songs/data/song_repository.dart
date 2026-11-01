import '../../../core/models/edit_conflict.dart';
import '../../../core/models/song.dart';
import '../../../core/models/arrangement.dart';
import '../../../core/models/user_role.dart';

class SongRepositoryException implements Exception {
  const SongRepositoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SongSession {
  const SongSession({this.userId, this.groupId, this.role});
  final String? userId, groupId;
  final UserRole? role;
}

abstract class SongRepository {
  Stream<List<Song>> watchSongs(String groupId);
  Future<Song?> getSong(String groupId, String songId);
  Future<bool> canManage(String groupId);
  Future<String> createSong(String groupId, Song song);

  /// Metadata only. Arrangements are changed through the methods below.
  /// Editors pass their opening snapshot as [expected] for atomic stale checks.
  Future<void> updateSong(String groupId, Song song, {Song? expected});
  Future<void> deleteSong(String groupId, String songId);
  Future<String> createArrangement(
      String groupId, String songId, Arrangement arrangement);
  Future<void> updateArrangement(
      String groupId, String songId, Arrangement arrangement,
      {Arrangement? expected});
  Future<String> duplicateArrangement(
      String groupId, String songId, String arrangementId);
  Future<void> deleteArrangement(
      String groupId, String songId, String arrangementId);
}

/// Compare only the fields this operation replaces; unrelated arrangement edits
/// can safely coexist with song metadata changes. No source normalization.
void checkSongEdit(Song? current, Song expected) {
  if (current == null) throw const EditConflict('Song', deleted: true);
  if (current.id != expected.id ||
      current.title != expected.title ||
      current.artist != expected.artist ||
      current.category != expected.category ||
      current.isFavorite != expected.isFavorite ||
      current.vocalistKeys.length != expected.vocalistKeys.length ||
      List.generate(
              current.vocalistKeys.length,
              (i) =>
                  current.vocalistKeys[i].vocalistName !=
                      expected.vocalistKeys[i].vocalistName ||
                  current.vocalistKeys[i].key != expected.vocalistKeys[i].key)
          .any((v) => v)) {
    throw const EditConflict('Song');
  }
}

void checkArrangementEdit(Arrangement? current, Arrangement expected) {
  if (current == null) throw const EditConflict('Arrangement', deleted: true);
  if (current.id != expected.id ||
      current.name != expected.name ||
      current.bpm != expected.bpm ||
      current.timeSignature != expected.timeSignature ||
      current.referenceLink != expected.referenceLink ||
      current.chordProSource != expected.chordProSource) {
    throw const EditConflict('Arrangement');
  }
}
