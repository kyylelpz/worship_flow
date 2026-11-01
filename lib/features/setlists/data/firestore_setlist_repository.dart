import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../../core/firebase/content_codec.dart';
import '../../../core/models/setlist.dart';
import '../../../core/models/setlist_item.dart';
import '../../charts/models/chord_symbol.dart';
import 'setlist_repository.dart';

class FirestoreSetlistRepository
    implements SetlistRepository, AtomicSetlistRepository {
  FirestoreSetlistRepository(this.db, this.auth, this.selectedGroup);
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final String? Function() selectedGroup;
  String get _group =>
      selectedGroup() ?? (throw StateError('Select a group first.'));
  DocumentReference<Map<String, dynamic>> _ref(String g, String id) =>
      db.doc('groups/$g/setlists/$id');
  @override
  Stream<List<Setlist>> watchSetlists(String groupId) => db
      .collection('groups/$groupId/setlists')
      .snapshots()
      .map((s) => s.docs.map((d) => setlistFromData(d.data())).toList());
  @override
  Future<Setlist?> getSetlist(String setlistId) async {
    return getInGroup(_group, setlistId);
  }

  Future<Setlist?> getInGroup(String groupId, String setlistId) async {
    final d = await _ref(groupId, setlistId)
        .get(const GetOptions(source: Source.server));
    return d.exists ? setlistFromData(d.data()!) : null;
  }

  Future<void> _write(String id, String g, Setlist? Function(Setlist?) change,
      {int? expectedRevision}) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || g != _group) {
      throw StateError('Select an authorized group first.');
    }
    await db.runTransaction((tx) async {
      final ref = _ref(g, id);
      final old = await tx.get(ref);
      final before = old.exists ? setlistFromData(old.data()!) : null;
      if (expectedRevision != null && before?.revision != expectedRevision) {
        throw StateError(
            'This setlist was changed or deleted by another editor. Reopen it before saving; your local edits have been kept.');
      }
      final next = change(before);
      if (auth.currentUser?.uid != uid || selectedGroup() != g) {
        throw StateError('Session changed. Retry in the intended group.');
      }
      final entries = <String, dynamic>{};
      final allKeys = {
        for (final i in [
          ...?before?.publishedItems,
          ...?before?.draftItems,
          ...?next?.publishedItems,
          ...?next?.draftItems
        ])
          i.arrangementId
      };
      for (final key in allKeys) {
        final registration = await tx.get(db.doc('groups/$g/catalog/$key'));
        entries[key] = registration.data();
      }
      if (auth.currentUser?.uid != uid || selectedGroup() != g) {
        throw StateError('Session changed. Retry in the intended group.');
      }
      final keys = <String>{};
      if (next != null) {
        if (next.name.trim().isEmpty || next.name.length > 120) {
          throw StateError('Enter a setlist name (maximum 120 characters).');
        }
        if (next.publishedItems.length > 6 ||
            (next.draftItems?.length ?? 0) > 6) {
          throw StateError(
              'Each published/draft setlist supports up to 6 songs.');
        }
        for (final i in [...next.publishedItems, ...?next.draftItems]) {
          if (MusicalKey.tryParse(i.performanceKey) == null ||
              entries[i.arrangementId]?['songId'] != i.songId) {
            throw StateError(
                'A selected song, arrangement or performance key is unavailable. Re-select it before saving.');
          }
          keys.add(i.arrangementId);
        }
      }
      final previous = {
        for (final i in [...?before?.publishedItems, ...?before?.draftItems])
          i.arrangementId
      };
      for (final key in {...previous, ...keys}) {
        final uses = Set<String>.from(entries[key]['uses'] as List)..remove(id);
        if (keys.contains(key)) uses.add(id);
        final after = uses.toList()..sort();
        final prior = List<String>.from(entries[key]['uses'] as List)..sort();
        if (jsonEncode(prior) != jsonEncode(after)) {
          tx.update(db.doc('groups/$g/catalog/$key'), {
            'uses': after,
            'target': id,
            'updatedAt': FieldValue.serverTimestamp()
          });
        }
      }
      if (next == null) {
        tx.delete(ref);
      } else {
        tx.set(ref, {
          ...setlistData(next),
          'revision': (before?.revision ?? 0) + 1,
          'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
    });
  }

  Setlist _required(Setlist? s) =>
      s ?? (throw StateError('Setlist not found.'));
  @override
  Future<String> commitSetlist(
      {required String id,
      required String groupId,
      required String name,
      required DateTime serviceDateTime,
      required List<SetlistItem> items,
      bool publish = false,
      int? expectedRevision}) async {
    await _write(
        id,
        groupId,
        (old) => Setlist(
            id: id,
            groupId: groupId,
            name: name,
            serviceDateTime: serviceDateTime,
            status: publish
                ? SetlistStatus.published
                : old?.status ?? SetlistStatus.draft,
            publishedItems: publish ? items : old?.publishedItems ?? const [],
            draftItems: publish ? null : items),
        expectedRevision: expectedRevision);
    return id;
  }

  @override
  Future<String> createDraft(
          {required String groupId,
          required String name,
          required DateTime serviceDateTime}) =>
      commitSetlist(
          id: const Uuid().v4(),
          groupId: groupId,
          name: name,
          serviceDateTime: serviceDateTime,
          items: const []);
  @override
  Future<void> saveDraft(String id, List<SetlistItem> items) =>
      _write(id, _group, (s) => _required(s).copyWith(draftItems: items));
  @override
  Future<void> updateMetadata(String id,
          {String? name, DateTime? serviceDateTime}) =>
      _write(
          id,
          _group,
          (s) => _required(s)
              .copyWith(name: name, serviceDateTime: serviceDateTime));
  @override
  Future<void> publish(String id) => _write(
      id,
      _group,
      (s) => _required(s).copyWith(
          status: SetlistStatus.published,
          publishedItems: s!.draftItems ?? s.publishedItems,
          clearDraft: true));
  @override
  Future<String> duplicate(String id) async {
    final original = _required(await getSetlist(id));
    return commitSetlist(
        id: const Uuid().v4(),
        groupId: original.groupId,
        name: '${original.name} (Copy)',
        serviceDateTime: original.serviceDateTime,
        items: original.draftItems ?? original.publishedItems);
  }

  @override
  Future<void> delete(String id) => _write(id, _group, (s) {
        _required(s);
        return null;
      });
}
