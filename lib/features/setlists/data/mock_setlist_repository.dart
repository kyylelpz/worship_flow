import 'dart:async';

import '../../../core/mock_data/mock_setlists.dart';
import '../../../core/models/setlist.dart';
import '../../../core/models/setlist_item.dart';
import 'setlist_repository.dart';

class MockSetlistRepository implements SetlistRepository {
  MockSetlistRepository({this.delay = const Duration(milliseconds: 250)});

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

  void dispose() {
    _controller.close();
  }
}
