import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import '../firebase/content_codec.dart';
import '../models/song.dart';
import '../models/setlist.dart';

enum CachedKind { songs, setlists }

class CachedDocument {
  const CachedDocument(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

class CachedCollection<T> {
  const CachedCollection(this.items,
      {required this.complete, this.refreshedAt});
  final List<T> items;
  final bool complete;
  final DateTime? refreshedAt;
}

/// Explicit SQL through Drift avoids a generated API for two cache-only tables.
/// Payloads retain server fields, including revisions and exact source strings.
class ContentCacheDatabase extends GeneratedDatabase {
  ContentCacheDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (_) async {
        await customStatement(
            'CREATE TABLE cached_documents (uid TEXT NOT NULL, group_id TEXT NOT NULL, kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(uid, group_id, kind, id))');
        await customStatement(
            'CREATE TABLE cached_collections (uid TEXT NOT NULL, group_id TEXT NOT NULL, kind TEXT NOT NULL, refreshed_at INTEGER NOT NULL, PRIMARY KEY(uid, group_id, kind))');
      });

  static dynamic _encode(dynamic value) {
    if (value is Timestamp) {
      return {
        '__timestamp': [value.seconds, value.nanoseconds]
      };
    }
    if (value is Map) return value.map((k, v) => MapEntry(k, _encode(v)));
    if (value is List) return value.map(_encode).toList();
    return value;
  }

  static dynamic _decode(dynamic value) {
    if (value is Map) {
      if (value.length == 1 && value['__timestamp'] is List) {
        final parts = value['__timestamp'] as List;
        return Timestamp(parts[0] as int, parts[1] as int);
      }
      return value.map((k, v) => MapEntry(k as String, _decode(v)));
    }
    if (value is List) return value.map(_decode).toList();
    return value;
  }

  static Map<String, dynamic> decode(String payload) =>
      Map<String, dynamic>.from(_decode(jsonDecode(payload)) as Map);
  static void validate(String group, CachedKind kind, CachedDocument doc) {
    if (doc.id.isEmpty ||
        doc.data['id'] != doc.id ||
        doc.data['groupId'] != group) {
      throw const FormatException('Cache document identity mismatch.');
    }
    if (kind == CachedKind.songs) {
      final song = songFromData(doc.data);
      if (song.arrangements.isEmpty ||
          song.arrangements.map((a) => a.id).toSet().length !=
              song.arrangements.length) {
        throw const FormatException('Duplicate arrangement IDs.');
      }
    } else {
      if (doc.data['revision'] is! int || (doc.data['revision'] as int) < 0) {
        throw const FormatException('Missing or invalid setlist revision.');
      }
      setlistFromData(doc.data);
    }
  }

  List<Variable> _scope(String uid, String group, CachedKind kind) =>
      [Variable(uid), Variable(group), Variable(kind.name)];

  // Independent document reads and collection listeners can finish out of order.
  Future<bool> _wouldRegress(String uid, String group, CachedKind kind,
      Iterable<CachedDocument> incoming) async {
    final rows = await customSelect(
            'SELECT id,payload FROM cached_documents WHERE uid=? AND group_id=? AND kind=?',
            variables: _scope(uid, group, kind))
        .get();
    final byId = {for (final doc in incoming) doc.id: doc.data};
    for (final row in rows) {
      final next = byId[row.read<String>('id')];
      if (next == null) continue;
      try {
        final old = decode(row.read<String>('payload'));
        if (kind == CachedKind.setlists &&
            old['revision'] is int &&
            next['revision'] is int &&
            old['revision'] > next['revision']) {
          return true;
        }
        if (old['updatedAt'] is Timestamp &&
            next['updatedAt'] is Timestamp &&
            (old['updatedAt'] as Timestamp)
                    .compareTo(next['updatedAt'] as Timestamp) >
                0) {
          return true;
        }
      } catch (_) {
        // A valid remote read can repair a corrupt row.
      }
    }
    return false;
  }

  /// Only called for a complete, authorized, server-confirmed collection.
  Future<void> replace(String uid, String group, CachedKind kind,
      List<CachedDocument> docs) async {
    final encoded = <String, String>{};
    for (final doc in docs) {
      validate(group, kind, doc);
      if (encoded.containsKey(doc.id)) {
        throw const FormatException('Duplicate document ID.');
      }
      encoded[doc.id] = jsonEncode(_encode(doc.data));
    }
    await transaction(() async {
      if (await _wouldRegress(uid, group, kind, docs)) return;
      await customStatement(
          'DELETE FROM cached_documents WHERE uid=? AND group_id=? AND kind=?',
          [uid, group, kind.name]);
      for (final entry in encoded.entries) {
        await customStatement('INSERT INTO cached_documents VALUES (?,?,?,?,?)',
            [uid, group, kind.name, entry.key, entry.value]);
      }
      await customStatement(
          'INSERT OR REPLACE INTO cached_collections VALUES (?,?,?,?)',
          [uid, group, kind.name, DateTime.now().millisecondsSinceEpoch]);
    });
  }

  Future<void> put(String uid, String group, CachedKind kind, String id,
      Map<String, dynamic>? data) async {
    if (data == null) {
      await customStatement(
          'DELETE FROM cached_documents WHERE uid=? AND group_id=? AND kind=? AND id=?',
          [uid, group, kind.name, id]);
    } else {
      validate(group, kind, CachedDocument(id, data));
      final encoded = jsonEncode(_encode(data));
      await transaction(() async {
        if (await _wouldRegress(uid, group, kind, [CachedDocument(id, data)])) {
          return;
        }
        await customStatement(
            'INSERT OR REPLACE INTO cached_documents VALUES (?,?,?,?,?)',
            [uid, group, kind.name, id, encoded]);
      });
    }
  }

  Future<CachedCollection<T>> read<T>(String uid, String group, CachedKind kind,
      T Function(Map<String, dynamic>) parse) async {
    return transaction(() async {
      final rows = await customSelect(
              'SELECT id,payload FROM cached_documents WHERE uid=? AND group_id=? AND kind=? ORDER BY id',
              variables: _scope(uid, group, kind))
          .get();
      final meta = await customSelect(
              'SELECT refreshed_at FROM cached_collections WHERE uid=? AND group_id=? AND kind=?',
              variables: _scope(uid, group, kind))
          .getSingleOrNull();
      var valid = true;
      final items = <T>[];
      for (final row in rows) {
        try {
          final data = decode(row.read<String>('payload'));
          validate(group, kind, CachedDocument(row.read<String>('id'), data));
          items.add(parse(data));
        } catch (_) {
          valid = false;
        }
      }
      return CachedCollection(List.unmodifiable(items),
          complete: valid && meta != null,
          refreshedAt: meta == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  meta.read<int>('refreshed_at')));
    });
  }

  Future<CachedCollection<Song>> songs(String uid, String group) =>
      read(uid, group, CachedKind.songs, songFromData);
  Future<CachedCollection<Setlist>> setlists(String uid, String group) =>
      read(uid, group, CachedKind.setlists, setlistFromData);

  Future<void> purge(String uid, {String? group}) => transaction(() async {
        for (final table in ['cached_documents', 'cached_collections']) {
          await customStatement(
              'DELETE FROM $table WHERE uid=?${group == null ? '' : ' AND group_id=?'}',
              [uid, if (group != null) group]);
        }
      });
  Future<void> retainGroups(String uid, Set<String> groups) =>
      transaction(() async {
        for (final table in ['cached_documents', 'cached_collections']) {
          await customStatement(
              'DELETE FROM $table WHERE uid=?${groups.isEmpty ? '' : ' AND group_id NOT IN (${List.filled(groups.length, '?').join(',')})'}',
              [uid, ...groups]);
        }
      });
}
