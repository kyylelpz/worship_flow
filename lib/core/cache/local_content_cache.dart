import '../models/arrangement.dart';
import 'dart:async';
import '../models/song.dart';
import '../models/setlist.dart';
import 'content_cache_database.dart';

class CacheLease {
  const CacheLease._(this.uid, this.group, this.session, this.generation);
  final String uid, group;
  final int session, generation;
}

/// Session-scoped read boundary. Raw database access belongs to infrastructure.
/// Invalidation and writes share a queue, so an in-flight read cannot repopulate
/// a purged account/group after revocation or sign-out.
class LocalContentCache {
  LocalContentCache(this.database, this.currentUid) {
    _uid = currentUid();
  }
  final _changes = StreamController<int>.broadcast(sync: true);
  int _change = 0;
  Stream<int> get changes => _changes.stream;
  final _fresh = <(String, CachedKind), bool>{};
  final _freshAccess = <String>{};
  bool _offlineIdentity = false;
  bool get offlineIdentity => _offlineIdentity;
  void markIdentityOffline() {
    if (!_offlineIdentity) {
      _offlineIdentity = true;
      _notify();
    }
  }

  void markIdentityFresh() {
    if (_offlineIdentity) {
      _offlineIdentity = false;
      _notify();
    }
  }

  bool isOffline(String group) =>
      _offlineIdentity ||
      !_freshAccess.contains(group) ||
      _fresh[(group, CachedKind.songs)] != true ||
      _fresh[(group, CachedKind.setlists)] != true;
  bool isReadOnly(String group) =>
      _offlineIdentity ||
      !_freshAccess.contains(group) ||
      _fresh.entries.any((e) => e.key.$1 == group && !e.value);
  void _notify() {
    if (!_changes.isClosed) _changes.add(++_change);
  }

  void markFresh(String group, CachedKind kind) {
    if (_fresh[(group, kind)] != true) {
      _fresh[(group, kind)] = true;
      _notify();
    }
  }

  void markAccessOffline() {
    _freshAccess.clear();
    _notify();
  }

  void markOffline(String group, CachedKind kind) {
    _fresh[(group, kind)] = false;
    _notify();
  }

  final ContentCacheDatabase database;
  final String? Function() currentUid;
  String? _uid;
  int _session = 0;
  Set<String>? _authorizedGroups;
  final _revoked = <(String, String)>{};
  final _generations = <(String, String), int>{};
  Future<void> _queue = Future.value();
  Object? lastError;
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object error) {
      lastError = error;
    });
    return _queue;
  }

  Future<void> get settled => _queue;
  CacheLease? begin(String group) {
    final uid = currentUid();
    if (uid == null ||
        uid != _uid ||
        _revoked.contains((uid, group)) ||
        (group.isNotEmpty &&
            _authorizedGroups != null &&
            !_authorizedGroups!.contains(group))) {
      return null;
    }
    final key = (uid, group);
    return CacheLease._(
        uid, group, _session, _generations.putIfAbsent(key, () => 0));
  }

  bool _valid(CacheLease lease) =>
      lease.uid == _uid &&
      lease.uid == currentUid() &&
      !_revoked.contains((lease.uid, lease.group)) &&
      lease.session == _session &&
      lease.generation == _generations[(lease.uid, lease.group)] &&
      (lease.group.isEmpty ||
          _authorizedGroups == null ||
          _authorizedGroups!.contains(lease.group));

  void switchAccount(String? uid) {
    if (uid == _uid) return;
    final previous = _uid;
    _uid = uid;
    _session++;
    _authorizedGroups = null;
    _fresh.clear();
    _offlineIdentity = false;
    _freshAccess.clear();
    _notify();
    if (previous != null) unawaited(_enqueue(() => database.purge(previous)));
  }

  Future<void> revoke(String uid, String group) {
    final key = (uid, group);
    _revoked.add(key);
    _freshAccess.remove(group);
    _notify();
    _generations[key] = (_generations[key] ?? 0) + 1;
    if (uid == _uid && _authorizedGroups != null) {
      _authorizedGroups!.remove(group);
    }
    return _enqueue(() => database.purge(uid, group: group));
  }

  /// Only invoke from a complete server membership-index snapshot, never errors.
  Future<void> retainAuthorizedGroups(String uid, Set<String> groups) {
    if (uid != currentUid() || uid != _uid) return Future.value();
    _authorizedGroups = Set.of(groups);
    _freshAccess.removeWhere((g) => !groups.contains(g));
    _notify();
    _revoked.removeWhere((key) => key.$1 == uid && groups.contains(key.$2));
    for (final key in _generations.keys
        .where((k) => k.$1 == uid && !groups.contains(k.$2))
        .toList()) {
      _generations[key] = _generations[key]! + 1;
    }
    return _enqueue(() => database.retainGroups(uid, groups));
  }

  Future<void> collection(
      CacheLease? lease, CachedKind kind, List<CachedDocument> docs,
      {required bool fromServer,
      required bool pendingWrites,
      bool complete = true}) {
    if (lease == null || !fromServer || pendingWrites || !complete) {
      return Future.value();
    }
    return _enqueue(() async {
      if (_valid(lease)) {
        await database.replace(lease.uid, lease.group, kind, docs);
        _fresh[(lease.group, kind)] = true;
        _notify();
      }
    });
  }

  Future<void> document(
      CacheLease? lease, CachedKind kind, String id, Map<String, dynamic>? data,
      {required bool fromServer, required bool pendingWrites}) {
    if (lease == null || !fromServer || pendingWrites) return Future.value();
    return _enqueue(() async {
      if (_valid(lease)) {
        await database.put(lease.uid, lease.group, kind, id, data);
        _notify();
      }
    });
  }

  CacheLease _readScope(String group) =>
      begin(group) ??
      (throw StateError('No active account access to this cache scope.'));
  Future<CachedCollection<Song>> readSongs(String group) async {
    final lease = _readScope(group);
    await settled;
    final value = await database.songs(lease.uid, group);
    if (!_valid(lease)) {
      throw StateError('Cache account or membership changed.');
    }
    return value;
  }

  Future<CachedCollection<Setlist>> readSetlists(String group) async {
    final lease = _readScope(group);
    await settled;
    final value = await database.setlists(lease.uid, group);
    if (!_valid(lease)) {
      throw StateError('Cache account or membership changed.');
    }
    return value;
  }

  Future<Song?> readSong(String group, String id) async =>
      (await readSongs(group)).items.where((s) => s.id == id).firstOrNull;
  Future<Setlist?> readSetlist(String group, String id) async =>
      (await readSetlists(group)).items.where((s) => s.id == id).firstOrNull;
  Future<Arrangement?> readArrangement(
          String group, String songId, String arrangementId) async =>
      (await readSong(group, songId))
          ?.arrangements
          .where((a) => a.id == arrangementId)
          .firstOrNull;
  Future<void> saveMetadata(String group, CachedKind kind, String id,
      Map<String, dynamic> value) async {
    final lease = begin(group);
    await document(
        lease,
        kind,
        id,
        {
          'id': id,
          'groupId': group,
          'value': value,
          if (value['updatedAt'] != null) 'updatedAt': value['updatedAt']
        },
        fromServer: true,
        pendingWrites: false);
    if (kind == CachedKind.access && lease != null && _valid(lease)) {
      _freshAccess.add(group);
      _notify();
    }
  }

  Future<List<Map<String, dynamic>>> metadata(CachedKind kind) async {
    final lease = _readScope('');
    await settled;
    final values = await database.metadata(lease.uid, kind);
    if (!_valid(lease)) throw StateError('Account changed.');
    return values;
  }

  Future<bool> hasOfflineAccess(String group) async {
    if (begin(group) == null) return false;
    final profiles = await metadata(CachedKind.profile);
    if (!profiles.any((d) =>
        d['id'] == currentUid() &&
        d['value'] is Map &&
        (d['value'] as Map)['profileComplete'] == true)) {
      return false;
    }
    return (await metadata(CachedKind.access)).any((d) {
      final value = d['value'];
      if (value is! Map || value['member'] is! Map) return false;
      final member = value['member'] as Map;
      return d['groupId'] == group &&
          value['uid'] == currentUid() &&
          member['uid'] == currentUid() &&
          member['groupId'] == group &&
          const ['administrator', 'worshipLeader', 'worshipTrainee']
              .contains(member['role']);
    });
  }

  Future<void> invalidateAccount(String uid) {
    if (uid == _uid) {
      _session++;
      _freshAccess.clear();
      _fresh.clear();
      _notify();
    }
    return _enqueue(() => database.purge(uid));
  }

  Future<OfflineRehearsal> rehearsal(String group, String id) async {
    if (!await hasOfflineAccess(group)) {
      throw StateError(
          'No previously verified group access is cached. Connect to verify membership.');
    }
    final setlist = await readSetlist(group, id);
    if (setlist == null || !setlist.isPublished) {
      throw StateError(
          'This published setlist is unavailable offline. Open it online first.');
    }
    final songs = (await readSongs(group)).items;
    for (final item in setlist.publishedItems) {
      final song = songs.where((s) => s.id == item.songId).firstOrNull;
      final arrangement = song?.arrangements
          .where((a) => a.id == item.arrangementId)
          .firstOrNull;
      if (arrangement == null || arrangement.chordProSource.trim().isEmpty) {
        throw StateError(
            'This setlist is not fully cached. Open every required chart online before rehearsing offline.');
      }
    }
    return OfflineRehearsal(setlist, songs);
  }

  Future<List<Setlist>> offlineSetlists(String group) async {
    final result = <Setlist>[];
    if (!await hasOfflineAccess(group)) return result;
    for (final setlist in (await readSetlists(group)).items) {
      try {
        result.add((await rehearsal(group, setlist.id)).setlist);
      } catch (_) {/* Incomplete setlists are not offered offline. */}
    }
    return result;
  }
}

class OfflineRehearsal {
  const OfflineRehearsal(this.setlist, this.songs);
  final Setlist setlist;
  final List<Song> songs;
}
