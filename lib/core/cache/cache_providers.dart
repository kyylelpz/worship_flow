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
  if (ref.watch(useMockBackendProvider) || kIsWeb) return null;
  final auth = ref.watch(firebaseAuthProvider);
  final cache = LocalContentCache(
      ref.watch(contentCacheDatabaseProvider), () => auth.currentUser?.uid);
  final subscription =
      auth.authStateChanges().listen((user) => cache.switchAccount(user?.uid));
  ref.onDispose(() => unawaited(subscription.cancel()));
  return cache;
});
