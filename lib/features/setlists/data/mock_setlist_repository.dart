import '../../../core/models/edit_conflict.dart';
import 'dart:async';

import '../../../core/mock_data/mock_setlists.dart';
import '../../../core/models/setlist.dart';
import '../../../core/models/setlist_item.dart';
import 'setlist_repository.dart';

class MockSetlistRepository
    implements
        SetlistRepository,
        SetlistSongReferences,
        AtomicSetlistRepository {
  MockSetlistRepository(
      {this.delay = const Duration(milliseconds: 250), this.validateItems});

  final void Function(String groupId, List<SetlistItem> items)? validateItems;

  final Duration delay;

  final List<Setlist> _setlists = List<Setlist>.from(mockSetlists);
  final StreamController<List<Setlist>> _controller =
      StreamController<List<Setlist>>.broadcast();
  int _idSeed = 1000;

  List<Setlist> _forGroup(String groupId) =>
      _setlists.where((s) => s.groupId == groupId).toList();

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List<Setlist>.unmodifiable(_setlists));
    }
  }

  Setlist? _find(String id) {
    for (final s in _setlists) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Stream<List<Setlist>> watchSetlists(String groupId) async* {
    await Future<void>.delayed(delay);
    yield _forGroup(groupId);
    yield* _controller.stream.map((_) => _forGroup(groupId));
  }

  @override
  Future<Setlist?> getSetlist(String setlistId) async {
    await Future<void>.delayed(delay);
    return _find(setlistId);
  }

  @override
  Future<String> createDraft({
    required String groupId,
    required String name,
    required DateTime serviceDateTime,
  }) async {
    await Future<void>.delayed(delay);
    final id = 'setlist-new-${_idSeed++}';
    _setlists.add(Setlist(
      id: id,
      groupId: groupId,
      name: name,
      serviceDateTime: serviceDateTime,
      status: SetlistStatus.draft,
      publishedItems: const [],
      draftItems: const [],
    ));
    _emit();
    return id;
  }

  @override
  Future<void> saveDraft(String setlistId, List<SetlistItem> items) async {
    await Future<void>.delayed(delay);
    final idx = _setlists.indexWhere((s) => s.id == setlistId);
    if (idx == -1) return;
    validateItems?.call(_setlists[idx].groupId, items);
    _setlists[idx] = _setlists[idx].copyWith(
      draftItems: List<SetlistItem>.unmodifiable(items),
    );
    _emit();
  }

  @override
  Future<void> updateMetadata(
    String setlistId, {
    String? name,
    DateTime? serviceDateTime,
  }) async {
    await Future<void>.delayed(delay);
    final idx = _setlists.indexWhere((s) => s.id == setlistId);
    if (idx == -1) return;
    _setlists[idx] = _setlists[idx].copyWith(
      name: name,
      serviceDateTime: serviceDateTime,
    );
    _emit();
  }

  @override
  Future<void> publish(String setlistId) async {
    await Future<void>.delayed(delay);
    final idx = _setlists.indexWhere((s) => s.id == setlistId);
    if (idx == -1) return;
    final s = _setlists[idx];
    final items = s.draftItems ?? s.publishedItems;
    _setlists[idx] = s.copyWith(
      status: SetlistStatus.published,
      publishedItems: List<SetlistItem>.unmodifiable(items),
      clearDraft: true,
    );
    _emit();
  }

  @override
  Future<String> duplicate(String setlistId) async {
    await Future<void>.delayed(delay);
    final original = _find(setlistId);
    if (original == null) throw StateError('Setlist not found: $setlistId');
    final newId = 'setlist-new-${_idSeed++}';
    final copy = Setlist(
      id: newId,
      groupId: original.groupId,
      name: '${original.name} (Copy)',
      serviceDateTime: original.serviceDateTime,
      status: SetlistStatus.draft,
      publishedItems: const [],
      draftItems: List<SetlistItem>.unmodifiable(
        original.draftItems ?? original.publishedItems,
      ),
    );
    _setlists.add(copy);
    _emit();
    return newId;
  }

  @override
  Future<void> delete(String setlistId) async {
    await Future<void>.delayed(delay);
    _setlists.removeWhere((s) => s.id == setlistId);
    _emit();
  }

  @override
  bool referencesSong(String groupId, String songId, {String? arrangementId}) =>
      _setlists.where((s) => s.groupId == groupId).any((s) => [
            ...s.publishedItems,
            ...?s.draftItems
          ].any((item) =>
              item.songId == songId &&
              (arrangementId == null || item.arrangementId == arrangementId)));

  void dispose() {
    _controller.close();
  }

  @override
  Future<String> commitSetlist(
      {required String id,
      required String groupId,
      required String name,
      required DateTime serviceDateTime,
      required List<SetlistItem> items,
      bool publish = false,
      int? expectedRevision}) async {
    await Future<void>.delayed(delay);
    if (name.trim().isEmpty) {
      throw StateError('Enter a setlist name.');
    }
    validateItems?.call(groupId, items);
    final old = _find(id);
    if (expectedRevision != null && old?.revision != expectedRevision) {
      throw EditConflict('Setlist', deleted: old == null);
    }
    final value = Setlist(
        id: id,
        groupId: groupId,
        name: name.trim(),
        serviceDateTime: serviceDateTime,
        status: publish
            ? SetlistStatus.published
            : old?.status ?? SetlistStatus.draft,
        publishedItems: publish
            ? List.unmodifiable(items)
            : old?.publishedItems ?? const [],
        draftItems: publish ? null : List.unmodifiable(items),
        revision: (old?.revision ?? 0) + 1);
    _setlists.removeWhere((s) => s.id == id);
    _setlists.add(value);
    _emit();
    return id;
  }
}
