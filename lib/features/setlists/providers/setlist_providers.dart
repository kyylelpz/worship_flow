import '../../../core/cache/cache_providers.dart';
import '../../groups/providers/group_providers.dart';
import '../../groups/data/firestore_group_repository.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../data/firestore_setlist_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/setlist.dart';
import '../../songs/providers/song_catalog_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/mock_setlist_repository.dart';
import '../data/setlist_repository.dart';

/// Production persists group data; development/test overrides retain fixtures.
final setlistRepositoryProvider = Provider<SetlistRepository>((ref) {
  if (!ref.watch(useMockBackendProvider) &&
      ref.watch(groupRepositoryProvider) is FirestoreGroupRepository) {
    return FirestoreSetlistRepository(
        ref.watch(firestoreProvider),
        ref.watch(firebaseAuthProvider),
        () => ref.read(selectedGroupIdProvider),
        cache: ref.watch(localContentCacheProvider));
  }
  final repo = MockSetlistRepository(
      validateItems: ref.watch(songCatalogProvider).validateReferences);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Setlists in the current group.
final groupSetlistsProvider = StreamProvider<List<Setlist>>((ref) {
  final groupId = ref.watch(selectedGroupIdProvider);
  if (groupId == null) return const Stream.empty();
  return ref.watch(setlistRepositoryProvider).watchSetlists(groupId);
});

/// A single setlist by id.
final setlistByIdProvider =
    FutureProvider.family<Setlist?, String>((ref, setlistId) async {
  final lists = ref.watch(groupSetlistsProvider);
  if (ref.watch(selectedGroupIdProvider) == null) return null;
  if (lists.asData != null) {
    return lists.asData!.value.where((s) => s.id == setlistId).firstOrNull;
  }
  final initial = await ref.watch(groupSetlistsProvider.future);
  return initial.where((s) => s.id == setlistId).firstOrNull;
});

/// Filter state for the Setlists screen.
enum SetlistFilter { upcoming, previous, drafts }

class SetlistFilterController extends StateNotifier<SetlistFilter> {
  SetlistFilterController() : super(SetlistFilter.upcoming);
  void select(SetlistFilter f) => state = f;
}

final setlistFilterProvider =
    StateNotifierProvider<SetlistFilterController, SetlistFilter>(
  (ref) => SetlistFilterController(),
);

/// Derived: the group's setlists filtered by the current filter, sorted.
final filteredSetlistsProvider = Provider<AsyncValue<List<Setlist>>>((ref) {
  final filter = ref.watch(setlistFilterProvider);
  final asyncSetlists = ref.watch(groupSetlistsProvider);
  final nextUpcoming = ref.watch(nextUpcomingSetlistProvider);
  final now = DateTime.now();

  return asyncSetlists.whenData((setlists) {
    List<Setlist> filtered;
    switch (filter) {
      case SetlistFilter.upcoming:
        filtered = setlists
            .where((s) =>
                s.status == SetlistStatus.published &&
                s.serviceDateTime.isAfter(now) &&
                s.id != nextUpcoming?.id) // 👈 exclude "UP NEXT"
            .toList();
        filtered.sort((a, b) => a.serviceDateTime.compareTo(b.serviceDateTime));
        break;

      case SetlistFilter.previous: // 👈 this was missing
        filtered = setlists
            .where((s) =>
                s.status == SetlistStatus.published &&
                !s.serviceDateTime.isAfter(now))
            .toList();
        filtered.sort((a, b) => b.serviceDateTime.compareTo(a.serviceDateTime));
        break;

      case SetlistFilter.drafts:
        filtered = setlists
            .where((s) => s.status == SetlistStatus.draft || s.hasDraftChanges)
            .toList();
        filtered.sort((a, b) => a.serviceDateTime.compareTo(b.serviceDateTime));
        break;
    }
    return List<Setlist>.unmodifiable(filtered);
  });
});

/// The next upcoming published setlist — used by UpcomingServiceCard.
final nextUpcomingSetlistProvider = Provider<Setlist?>((ref) {
  final asyncSetlists = ref.watch(groupSetlistsProvider).valueOrNull;
  if (asyncSetlists == null) return null;
  final now = DateTime.now();
  final upcoming = asyncSetlists
      .where((s) =>
          s.status == SetlistStatus.published && s.serviceDateTime.isAfter(now))
      .toList()
    ..sort((a, b) => a.serviceDateTime.compareTo(b.serviceDateTime));
  return upcoming.isEmpty ? null : upcoming.first;
});
