import '../../../core/cache/content_cache_database.dart';
import '../../../core/cache/offline_reads.dart';
import '../../../core/cache/local_content_cache.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/models/app_user.dart';
import '../../../core/models/group_member.dart';
import '../../../core/models/membership_position.dart';
import '../../../core/models/user_role.dart';
import '../../../core/models/worship_group.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/firebase_auth_repository.dart';
import 'group_repository.dart';
import 'firestore_invitation_repository.dart';

GroupMember memberFromFirestore(Map<String, dynamic> data,
    {String? expectedUid, String? expectedGroupId}) {
  if ((expectedUid != null && data['uid'] != expectedUid) ||
      (expectedGroupId != null && data['groupId'] != expectedGroupId)) {
    throw const AccountException(
        'Membership identity does not match its group document.');
  }
  final role = UserRole.values.where((r) => r.name == data['role']).firstOrNull;
  final position = MembershipPosition.values
      .where((p) => p.name == data['position'])
      .firstOrNull;
  if (role == null ||
      position == null ||
      data['createdAt'] is! Timestamp ||
      data['updatedAt'] is! Timestamp) {
    throw const AccountException(
        'Invalid membership data. Please contact the group administrator.');
  }
  final first = data['firstName'] as String? ?? '';
  final last = data['lastName'] as String? ?? '';
  return GroupMember(
      user: AppUser(
          id: data['uid'] as String,
          firstName: first,
          lastName: last,
          email: '',
          instrument: '',
          avatarInitials:
              '${first.isEmpty ? '' : String.fromCharCode(first.runes.first)}${last.isEmpty ? '' : String.fromCharCode(last.runes.first)}'
                  .toUpperCase()),
      role: role,
      groupId: data['groupId'] as String?,
      position: position,
      customPosition: data['customPosition'] as String? ?? '',
      joinedAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate());
}

class _GroupSnapshot {
  bool groupConfirmed = false, membersConfirmed = false;
  Map<String, dynamic>? group;
  List<GroupMember>? members;
  final subscriptions = <StreamSubscription<dynamic>>[];
}

class FirestoreGroupRepository
    implements GroupRepository, GroupCreationRepository {
  FirestoreGroupRepository(this.firestore, this.auth, {this.cache});
  final LocalContentCache? cache;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  Future<bool> hasMembership(String groupId, String uid) async {
    if (auth.currentUser?.uid != uid) return false;
    try {
      final member = await firestore
          .doc('groups/$groupId/members/$uid')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final allowed = member.exists &&
          member.data()?['uid'] == uid &&
          member.data()?['groupId'] == groupId;
      if (!allowed) await cache?.revoke(uid, groupId);
      return allowed;
    } on FirebaseException catch (e) {
      if (['permission-denied', 'not-found'].contains(e.code)) {
        await cache?.revoke(uid, groupId);
        return false;
      }
      if (isConnectionFailure(e) && cache != null) {
        return cache!.hasOfflineAccess(groupId);
      }
      rethrow;
    } on TimeoutException {
      if (cache != null) return cache!.hasOfflineAccess(groupId);
      rethrow;
    }
  }

  WorshipGroup _group(
          String id, Map<String, dynamic> data, List<GroupMember> members) =>
      WorshipGroup(
          id: id,
          name: data['name'] as String,
          churchName: data['churchName'] as String,
          accentColorValue: data['accentColorValue'] as int,
          createdBy: data['createdBy'] as String?,
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
          members: List.unmodifiable(members));

  @override
  Stream<List<WorshipGroup>> watchGroups() {
    final uid = auth.currentUser?.uid;
    return uid == null ? Stream.value(const []) : watchGroupsForUser(uid);
  }

  @override
  Stream<List<WorshipGroup>> watchGroupsForUser(String userId) =>
      Stream.multi((output) {
        if (auth.currentUser?.uid != userId) {
          output.addError(const AccountException(
              'Only your own group memberships can be loaded.'));
          output.close();
          return;
        }
        final entries = <String, _GroupSnapshot>{};
        var cancelled = false;
        var published = false;
        cache?.metadata(CachedKind.access).then((rows) {
          if (cancelled || published || auth.currentUser?.uid != userId) return;
          final groups = <WorshipGroup>[];
          for (final row in rows) {
            try {
              final value = Map<String, dynamic>.from(row['value'] as Map);
              if (value['uid'] != userId ||
                  cache?.begin(row['groupId'] as String) == null) {
                continue;
              }
              final member = memberFromFirestore(
                      Map<String, dynamic>.from(value['member'] as Map),
                      expectedUid: userId,
                      expectedGroupId: row['groupId'] as String)
                  .copyWith(role: UserRole.worshipTrainee);
              groups.add(_group(row['groupId'] as String,
                  Map<String, dynamic>.from(value['group'] as Map), [member]));
            } catch (_) {/* Invalid metadata is not permission. */}
          }
          output.add(groups);
        }).catchError((Object _) {});

        void publish() {
          if (cancelled ||
              entries.values.any((e) => e.group == null || e.members == null)) {
            return;
          }
          try {
            final groups = entries.entries
                .where((e) => e.value.members!.any((m) => m.user.id == userId))
                .map((e) => _group(e.key, e.value.group!, e.value.members!))
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            published = true;
            for (final group in groups) {
              final entry = entries[group.id]!;
              final member = group.members.firstWhere((m) => m.uid == userId);
              if (entry.groupConfirmed && entry.membersConfirmed) {
                unawaited(
                    cache?.saveMetadata(group.id, CachedKind.access, group.id, {
                  'uid': userId,
                  'group': entry.group!,
                  'member': {
                    'uid': userId,
                    'groupId': group.id,
                    'role': member.role.name,
                    'position': member.position.name,
                    'customPosition': member.customPosition,
                    'firstName': member.user.firstName,
                    'lastName': member.user.lastName,
                    'createdAt': Timestamp.fromDate(member.createdAt),
                    'updatedAt':
                        Timestamp.fromDate(member.updatedAt ?? member.createdAt)
                  }
                }));
              }
            }
            output.add(List.unmodifiable(groups));
          } catch (error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              unawaited(cache?.invalidateAccount(userId));
            }
            output.addError(accountFailure(error));
          }
        }

        void failure(Object error) {
          if (!cancelled) {
            if (isConnectionFailure(error)) {
              cache?.markAccessOffline();
              return;
            }
            output.addError(accountFailure(error));
          }
        }

        void groupFailure(String id, Object error) {
          if (error is FirebaseException &&
              const ['permission-denied', 'not-found'].contains(error.code)) {
            unawaited(cache?.revoke(userId, id));
            final removed = entries.remove(id);
            for (final sub
                in removed?.subscriptions ?? <StreamSubscription<dynamic>>[]) {
              unawaited(sub.cancel());
            }
            publish();
            return;
          }
          failure(error);
        }

        final membershipSub = firestore
            .collection('profiles/$userId/memberships')
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
          if (cancelled) return;
          if (snapshot.metadata.isFromCache) {
            cache?.markAccessOffline();
            return;
          }
          final ids = snapshot.docs.map((d) => d.id).toSet();
          if (!snapshot.metadata.hasPendingWrites) {
            unawaited(cache?.retainAuthorizedGroups(userId, ids));
          }
          for (final removed
              in entries.keys.where((id) => !ids.contains(id)).toList()) {
            for (final sub in entries.remove(removed)!.subscriptions) {
              unawaited(sub.cancel());
            }
          }
          for (final id in ids.where((id) => !entries.containsKey(id))) {
            final entry = _GroupSnapshot();
            entries[id] = entry;
            entry.subscriptions.add(firestore
                .doc('groups/$id')
                .snapshots(includeMetadataChanges: true)
                .listen((doc) {
              if (cancelled) return;
              if (doc.metadata.isFromCache) {
                entry.groupConfirmed = false;
                cache?.markAccessOffline();
                return;
              }
              if (!doc.exists) {
                groupFailure(
                    id,
                    FirebaseException(
                        plugin: 'cloud_firestore', code: 'not-found'));
                return;
              }
              entry.groupConfirmed = !doc.metadata.hasPendingWrites;
              entry.group = doc.data();
              publish();
            }, onError: (Object error) => groupFailure(id, error)));
            entry.subscriptions.add(firestore
                .collection('groups/$id/members')
                .snapshots(includeMetadataChanges: true)
                .listen((members) {
              if (cancelled) return;
              if (members.metadata.isFromCache) {
                entry.membersConfirmed = false;
                cache?.markAccessOffline();
                return;
              }
              try {
                entry.membersConfirmed = !members.metadata.hasPendingWrites;
                entry.members = members.docs
                    .map((d) => memberFromFirestore(d.data(),
                        expectedUid: d.id, expectedGroupId: id))
                    .toList();
                if (!members.metadata.hasPendingWrites &&
                    !entry.members!.any((m) => m.uid == userId)) {
                  unawaited(cache?.revoke(userId, id));
                }
                publish();
              } catch (error) {
                failure(error);
              }
            }, onError: (Object error) => groupFailure(id, error)));
          }
          publish();
        }, onError: failure);
        output.onCancel = () async {
          cancelled = true;
          await membershipSub.cancel();
          await Future.wait(entries.values
              .expand((e) => e.subscriptions)
              .map((s) => s.cancel()));
        };
      });

  @override
  Future<WorshipGroup?> getGroup(String groupId) async {
    if (auth.currentUser == null) {
      throw const AccountException('Please sign in first.');
    }
    try {
      final doc = await firestore
          .doc('groups/$groupId')
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return null;
      final members = await firestore
          .collection('groups/$groupId/members')
          .get(const GetOptions(source: Source.server));
      return _group(
          groupId,
          doc.data()!,
          members.docs
              .map((d) => memberFromFirestore(d.data(),
                  expectedUid: d.id, expectedGroupId: groupId))
              .toList());
    } catch (error) {
      throw accountFailure(error);
    }
  }

  @override
  Future<String> createGroupWithPosition(
      {required String name,
      required String churchName,
      required MembershipPosition position,
      String customPosition = '',
      required String requestId}) async {
    try {
      final user = auth.currentUser;
      if (user == null) throw const AccountException('Please sign in first.');
      if (!RegExp(r'^[A-Za-z0-9-]{16,80}$').hasMatch(requestId)) {
        throw const AccountException('Invalid group request ID.');
      }
      final groupId = requestId;
      await firestore.runTransaction((tx) async {
        final index =
            firestore.doc('profiles/${user.uid}/memberships/$groupId');
        if ((await tx.get(index)).exists) return;
        final profile =
            (await tx.get(firestore.doc('profiles/${user.uid}'))).data()!;
        if (profile['profileComplete'] != true) {
          throw const AccountException('Complete your profile first.');
        }
        final now = FieldValue.serverTimestamp();
        tx.set(firestore.doc('groups/$groupId'), {
          'name': name.trim(),
          'churchName': churchName.trim(),
          'createdBy': user.uid,
          'administratorUid': user.uid,
          'memberCount': 1,
          'accentColorValue': 0xff2f7a6b,
          'createdAt': now,
          'updatedAt': now,
        });
        tx.set(firestore.doc('groups/$groupId/members/${user.uid}'), {
          'uid': user.uid,
          'groupId': groupId,
          'firstName': profile['firstName'],
          'lastName': profile['lastName'],
          'role': 'administrator',
          'position': position.name,
          'customPosition':
              position == MembershipPosition.other ? customPosition.trim() : '',
          'createdAt': now,
          'updatedAt': now,
        });
        tx.set(index, {
          'uid': user.uid,
          'groupId': groupId,
          'createdAt': now,
          'updatedAt': now
        });
      });
      return groupId;
    } catch (error) {
      throw accountFailure(error);
    }
  }

  @override
  Future<void> createGroup(String name, String churchName) =>
      throw const AccountException(
          'Use group creation with an explicit position and request ID.');
  @override
  Future<void> joinGroup(String inviteCode) => throw const AccountException(
      'Accept an email invitation from Invitation Requests.');
  @override
  Future<void> updateMemberRole(
      {required String groupId,
      required String userId,
      required UserRole role}) async {
    final target = (await getGroup(groupId))
        ?.members
        .where((m) => m.uid == userId)
        .firstOrNull;
    if (target == null) throw const AccountException('Member unavailable.');
    await FirestoreInvitationRepository(firestore, auth).updateMember(
        groupId: groupId,
        uid: userId,
        role: role,
        position: target.position,
        customPosition: target.customPosition);
  }
}
