import '../../../core/models/setlist.dart';
import '../../../core/models/setlist_item.dart';

/// Contract for setlist data. Mock impl is in-memory. Firestore impl in
/// Phase 2 will read/write `groups/{groupId}/setlists/{setlistId}`.
abstract class SetlistRepository {
  /// All setlists in a group. Emits again after mutations.
  Stream<List<Setlist>> watchSetlists(String groupId);

  Future<Setlist?> getSetlist(String setlistId);

  /// Create a new draft setlist. Returns its id.
  Future<String> createDraft({
    required String groupId,
    required String name,
    required DateTime serviceDateTime,
  });

  /// Replace the draft items for a setlist (editor save).
  Future<void> saveDraft(String setlistId, List<SetlistItem> items);

  /// Update name and/or service date on a setlist.
  Future<void> updateMetadata(
    String setlistId, {
    String? name,
    DateTime? serviceDateTime,
  });

  /// Publish: copy draftItems (or current publishedItems) into publishedItems.
  Future<void> publish(String setlistId);

  /// Duplicate a setlist into a new draft under the same group.
  Future<String> duplicate(String setlistId);

  /// Delete a setlist.
  Future<void> delete(String setlistId);
}
