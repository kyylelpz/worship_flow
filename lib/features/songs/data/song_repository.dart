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
  Future<void> updateSong(String groupId, Song song);
  Future<void> deleteSong(String groupId, String songId);
  Future<String> createArrangement(
      String groupId, String songId, Arrangement arrangement);
  Future<void> updateArrangement(
      String groupId, String songId, Arrangement arrangement);
  Future<String> duplicateArrangement(
      String groupId, String songId, String arrangementId);
  Future<void> deleteArrangement(
      String groupId, String songId, String arrangementId);
}
