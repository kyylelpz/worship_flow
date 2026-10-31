import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/setlist.dart';
import '../../songs/providers/song_catalog_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/mock_setlist_repository.dart';
import '../data/setlist_repository.dart';

/// Swap for FirestoreSetlistRepository in Phase 2.
final setlistRepositoryProvider = Provider<SetlistRepository>((ref) {
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
  return ref.watch(setlistRepositoryProvider).getSetlist(setlistId);
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
  final now = DateTime.now();

  return asyncSetlists.whenData((setlists) {
    List<Setlist> filtered;
    switch (filter) {
      case SetlistFilter.upcoming:
        filtered = setlists
            .where((s) =>
                s.status == SetlistStatus.published &&
                s.serviceDateTime.isAfter(now))
            .toList();
        filtered.sort((a, b) => a.serviceDateTime.compareTo(b.serviceDateTime));
        break;
      case SetlistFilter.previous:
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
