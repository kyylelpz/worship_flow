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
        (_authorizedGroups != null && !_authorizedGroups!.contains(group))) {
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
      (_authorizedGroups == null || _authorizedGroups!.contains(lease.group));

  void switchAccount(String? uid) {
    if (uid == _uid) return;
    final previous = _uid;
    _uid = uid;
    _session++;
    _authorizedGroups = null;
    if (previous != null) unawaited(_enqueue(() => database.purge(previous)));
  }

  Future<void> revoke(String uid, String group) {
    final key = (uid, group);
    _revoked.add(key);
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
}
