import '../../groups/data/firestore_group_repository.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../data/firestore_song_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/song.dart';
import '../../auth/providers/auth_providers.dart';
import '../../groups/providers/group_providers.dart';
import '../../setlists/providers/setlist_providers.dart';
import '../../setlists/data/setlist_repository.dart';
import '../data/song_repository.dart';
import '../data/mock_song_repository.dart';
import 'song_catalog_provider.dart';

final songRepositoryProvider = Provider<SongRepository>((ref) {
  if (!ref.watch(useMockBackendProvider) &&
      ref.watch(groupRepositoryProvider) is FirestoreGroupRepository) {
    return FirestoreSongRepository(
        ref.watch(firestoreProvider),
        ref.watch(firebaseAuthProvider),
        () => ref.read(selectedGroupIdProvider));
  }
  final setlists = ref.watch(setlistRepositoryProvider);
  return MockSongRepository(
      catalog: ref.watch(songCatalogProvider),
      session: () {
        final state = ref.read(sessionProvider);
        return SongSession(
            userId: state.user?.id,
            groupId: state.selectedGroupId,
            role: ref.read(currentRoleProvider));
      },
      groups: ref.watch(groupRepositoryProvider),
      isReferenced: (group, song, arrangement) {
        if (setlists is! SetlistSongReferences) {
          throw const SongRepositoryException(
              'Reference checks are unavailable; deletion is disabled.');
        }
        return (setlists as SetlistSongReferences)
            .referencesSong(group, song, arrangementId: arrangement);
      });
});
final canManageSongsProvider = Provider<bool>((ref) {
  final group = ref.watch(selectedGroupIdProvider);
  return group != null &&
      (ref.watch(currentRoleProvider)?.canManageSongs ?? false) &&
      (ref.watch(roleInGroupProvider(group))?.canManageSongs ?? false);
});
final groupSongsProvider = StreamProvider<List<Song>>((ref) {
  final session = ref.watch(sessionProvider);
  final group = session.selectedGroupId;
  if (session.user == null || group == null) return Stream.value(const []);
  // Restart permission-sensitive subscriptions when memberships change.
  ref.watch(allGroupsProvider);
  return ref.watch(songRepositoryProvider).watchSongs(group);
});
final songsListProvider = Provider<List<Song>>(
    (ref) => ref.watch(groupSongsProvider).asData?.value ?? const []);
final songByIdProvider = Provider.family<Song?, String>((ref, id) =>
    ref.watch(songsListProvider).where((s) => s.id == id).firstOrNull);
