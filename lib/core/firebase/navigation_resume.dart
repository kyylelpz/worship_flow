import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/groups/data/firestore_group_repository.dart';
import '../../features/groups/providers/group_providers.dart';
import '../../features/setlists/data/firestore_setlist_repository.dart';
import '../../features/setlists/providers/setlist_providers.dart';

class ResumeLocation {
  const ResumeLocation({required this.groupId, this.setlistId, this.songId});
  final String groupId;
  final String? setlistId, songId;
}

abstract interface class ResumeStore {
  Future<ResumeLocation?> read(String uid);
  Future<void> write(String uid, ResumeLocation location);
}

class PreferencesResumeStore implements ResumeStore {
  Future<void> _queue = Future.value();
  @override
  Future<ResumeLocation?> read(String uid) async {
    await _queue;
    final value =
        (await SharedPreferences.getInstance()).getString('wf.resume.$uid');
    try {
      final d = jsonDecode(value ?? 'null');
      final id = RegExp(r'^[A-Za-z0-9-]{1,80}$');
      return d is Map &&
              d['groupId'] is String &&
              id.hasMatch(d['groupId'] as String) &&
              (d['setlistId'] == null ||
                  d['setlistId'] is String &&
                      id.hasMatch(d['setlistId'] as String))
          ? ResumeLocation(
              groupId: d['groupId'] as String,
              setlistId: d['setlistId'] as String?,
              songId: d['songId'] as String?)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String uid, ResumeLocation location) {
    final next = _queue.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(
          'wf.resume.$uid',
          jsonEncode({
            'groupId': location.groupId,
            'setlistId': location.setlistId,
            'songId': location.songId
          }))) {
        throw StateError('Could not store navigation preferences.');
      }
    });
    _queue = next.catchError((Object _) {});
    return next;
  }
}

final resumeStoreProvider = Provider<ResumeStore?>((ref) =>
    ref.watch(groupRepositoryProvider) is FirestoreGroupRepository
        ? PreferencesResumeStore()
        : null);

/// Tags even an empty result with its account. A previously resolved anonymous
/// result must never be consumed as an authenticated account's restoration.
class ResumeResolution {
  const ResumeResolution({required this.uid, this.location});
  final String? uid;
  final ResumeLocation? location;
}

/// Only reads while resolving. The router applies the verified destination once
/// per authenticated account; manual navigation never re-triggers restoration.
final sessionResumeProvider = FutureProvider<ResumeResolution>((ref) async {
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  final account =
      ref.watch(currentUserProvider.select((u) => (u?.id, u?.profileComplete)));
  if (account.$1 == null || account.$2 != true) {
    return ResumeResolution(uid: account.$1);
  }
  final store = ref.watch(resumeStoreProvider);
  if (store == null) return ResumeResolution(uid: account.$1);
  final saved = await store.read(account.$1!);
  if (saved == null || cancelled) return ResumeResolution(uid: account.$1);
  final groups = ref.read(groupRepositoryProvider);
  try {
    if (groups is FirestoreGroupRepository) {
      if (!await groups.hasMembership(saved.groupId, account.$1!)) {
        return ResumeResolution(uid: account.$1);
      }
    } else {
      final group = await groups.getGroup(saved.groupId);
      if (group == null || !group.members.any((m) => m.uid == account.$1)) {
        return ResumeResolution(uid: account.$1);
      }
    }
  } on FirebaseException catch (e) {
    if (['permission-denied', 'not-found'].contains(e.code)) {
      return ResumeResolution(uid: account.$1);
    }
    rethrow;
  }
  if (cancelled) return ResumeResolution(uid: account.$1);
  if (saved.setlistId == null) {
    return ResumeResolution(
        uid: account.$1, location: ResumeLocation(groupId: saved.groupId));
  }
  final repository = ref.read(setlistRepositoryProvider);
  try {
    final setlist = repository is FirestoreSetlistRepository
        ? await repository.getInGroup(saved.groupId, saved.setlistId!)
        : await repository.getSetlist(saved.setlistId!);
    return ResumeResolution(
        uid: account.$1,
        location: setlist == null || setlist.groupId != saved.groupId
            ? ResumeLocation(groupId: saved.groupId)
            : saved);
  } on FirebaseException catch (e) {
    if (['permission-denied', 'not-found'].contains(e.code)) {
      return ResumeResolution(
          uid: account.$1, location: ResumeLocation(groupId: saved.groupId));
    }
    rethrow;
  }
});

void rememberLocation(WidgetRef ref, ResumeLocation location) {
  final uid = ref.read(currentUserProvider)?.id,
      store = ref.read(resumeStoreProvider);
  if (uid != null && store != null) {
    // Navigation remains usable if platform preference storage is unavailable.
    unawaited(store.write(uid, location).catchError((Object _) {}));
  }
}
