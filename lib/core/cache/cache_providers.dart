import '../models/setlist.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../firebase/firebase_providers.dart';
import 'content_cache_database.dart';
import 'local_content_cache.dart';

final contentCacheDatabaseProvider = Provider<ContentCacheDatabase>((ref) {
  final database =
      ContentCacheDatabase(driftDatabase(name: 'worship_flow_read_cache'));
  ref.onDispose(() => unawaited(database.close()));
  return database;
});
final localContentCacheProvider = Provider<LocalContentCache?>((ref) {
  // Web needs separately deployed SQLite WASM/worker assets, deferred in 4A.
  if (ref.watch(useMockBackendProvider) || kIsWeb || Firebase.apps.isEmpty) {
    return null;
  }
  final auth = ref.watch(firebaseAuthProvider);
  String? authorizedUid() {
    final user = auth.currentUser;
    return user != null &&
            user.emailVerified &&
            user.providerData.any((p) => p.providerId == 'google.com')
        ? user.uid
        : null;
  }

  final cache =
      LocalContentCache(ref.watch(contentCacheDatabaseProvider), authorizedUid);
  final subscription = auth
      .authStateChanges()
      .listen((_) => cache.switchAccount(authorizedUid()));
  ref.onDispose(() => unawaited(subscription.cancel()));
  return cache;
});

final cacheChangesProvider = StreamProvider<int>((ref) async* {
  final cache = ref.watch(localContentCacheProvider);
  yield 0;
  if (cache != null) yield* cache.changes;
});
final cachedRehearsalProvider =
    FutureProvider.family<OfflineRehearsal, (String, String)>((ref, key) {
  ref.watch(cacheChangesProvider);
  final cache = ref.watch(localContentCacheProvider);
  if (cache == null) {
    throw StateError('Offline cache is unavailable on this device.');
  }
  return cache.rehearsal(key.$1, key.$2);
});

final offlineSetlistsProvider =
    FutureProvider.family<List<Setlist>, String>((ref, group) async {
  ref.watch(cacheChangesProvider);
  return ref.watch(localContentCacheProvider)?.offlineSetlists(group) ??
      <Setlist>[];
});
