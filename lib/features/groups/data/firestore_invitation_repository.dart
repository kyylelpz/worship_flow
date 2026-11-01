import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/models/membership_position.dart';
import '../../../core/models/user_role.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/firebase_auth_repository.dart';
import 'invitation_repository.dart';

class FirestoreInvitationRepository implements InvitationRepository {
  FirestoreInvitationRepository(this.db, this.auth);
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  String get _uid =>
      auth.currentUser?.uid ??
      (throw const AccountException('Please sign in again.'));
  DocumentReference<Map<String, dynamic>> _member(String g, String u) =>
      db.doc('groups/$g/members/$u');
  DocumentReference<Map<String, dynamic>> _index(String g, String u) =>
      db.doc('profiles/$u/memberships/$g');
  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw accountFailure(e);
    }
  }

  @override
  Stream<List<GroupInvitation>> watchPending() => db
      .collection('profiles/$_uid/invitations')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.map((doc) {
            final d = doc.data();
            return GroupInvitation(
                groupId: doc.id,
                groupName: d['groupName'] as String,
                recipientUid: d['recipientUid'] as String,
                inviterUid: d['inviterUid'] as String,
                role: UserRole.values.byName(d['role'] as String),
                position:
                    MembershipPosition.values.byName(d['position'] as String),
                customPosition: d['customPosition'] as String);
          }).toList());
  @override
  Stream<List<MembershipNotification>> watchNotifications() => db
      .collection('profiles/$_uid/notifications')
      .where('readAt', isNull: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) =>
              MembershipNotification(d.id, d.data()['groupName'] as String))
          .toList());
  @override
  Future<void> setAllowInvitations(bool allow) => _run(() async {
        final user = auth.currentUser!;
        final directory = db.doc('emailDirectory/${user.email!.toLowerCase()}');
        await db.runTransaction((tx) async {
          final ref = db.doc('profiles/${user.uid}');
          final profile = (await tx.get(ref)).data()!;
          final directoryExists = (await tx.get(directory)).exists;
          if (profile['profileComplete'] != true) {
            throw const AccountException('Complete your profile first.');
          }
          // Legacy completed profiles acquire the default explicitly on first toggle.
          tx.update(ref, {
            'allowInvitations': allow,
            'updatedAt': FieldValue.serverTimestamp()
          });
          if (allow) {
            tx.set(directory, {'uid': user.uid});
          } else if (directoryExists) {
            tx.delete(directory);
          }
        });
      });
  @override
  Future<void> invite(
          {required String groupId,
          required String email,
          required UserRole role,
          required MembershipPosition position,
          String customPosition = ''}) =>
      _run(() async {
        final normalized = email.trim().toLowerCase();
        if (validateInvitationEmail(normalized) != null) {
          throw const AccountException('Enter a valid Google email address.');
        }
        if (normalized == auth.currentUser!.email!.toLowerCase()) {
          throw const AccountException('You cannot invite yourself.');
        }
        await db.doc('directoryAccess/$_uid').set({'groupId': groupId});
        final lookup = await db
            .doc('emailDirectory/$normalized')
            .get(const GetOptions(source: Source.server));
        if (!lookup.exists) {
          throw const AccountException(
              'No registered account allowing invitations was found.');
        }
        final recipient = lookup.data()!['uid'] as String;
        final id = db.collection('unused').doc().id;
        await db.runTransaction((tx) async {
          final group = await tx.get(db.doc('groups/$groupId'));
          final ref = db.doc('profiles/$recipient/invitations/$groupId');
          final old = await tx.get(ref);
          if (old.data()?['status'] == 'pending') {
            throw const AccountException(
                'A pending invitation already exists.');
          }
          // Membership is already readable to the inviter as a group member.
          if ((await tx.get(_member(groupId, recipient))).exists) {
            throw const AccountException('This user is already a member.');
          }
          if (group.data()!['administratorUid'] == null) {
            tx.update(group.reference, {
              'administratorUid': _uid,
              'updatedAt': FieldValue.serverTimestamp()
            });
          }
          tx.set(ref, {
            'groupId': groupId,
            'recipientUid': recipient,
            'groupName': group.data()!['name'],
            'inviterUid': _uid,
            'role': role.name,
            'position': position.name,
            'customPosition': position == MembershipPosition.other
                ? customPosition.trim()
                : '',
            'notificationId': id,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp()
          });
        });
      });
  @override
  Future<void> respond(GroupInvitation invitation, {required bool accept}) =>
      _run(() async {
        final uid = _uid, g = invitation.groupId;
        await db.runTransaction((tx) async {
          final ref = db.doc('profiles/$uid/invitations/$g');
          final i = (await tx.get(ref)).data();
          if (i == null || i['status'] != 'pending') {
            throw const AccountException(
                'This invitation is no longer pending.');
          }
          final profile =
              accept ? (await tx.get(db.doc('profiles/$uid'))).data()! : null;
          final now = FieldValue.serverTimestamp();
          tx.update(ref,
              {'status': accept ? 'accepted' : 'declined', 'updatedAt': now});
          if (!accept) return;
          tx.set(_member(g, uid), {
            'uid': uid,
            'groupId': g,
            'firstName': profile!['firstName'],
            'lastName': profile['lastName'],
            'role': i['role'],
            'position': i['position'],
            'customPosition': i['customPosition'],
            'createdAt': now,
            'updatedAt': now
          });
          tx.set(_index(g, uid),
              {'uid': uid, 'groupId': g, 'createdAt': now, 'updatedAt': now});
          tx.set(
              db.doc(
                  'profiles/${i['inviterUid']}/notifications/${i['notificationId']}'),
              {
                'recipientUid': uid,
                'groupId': g,
                'groupName': i['groupName'],
                'createdAt': now,
                'readAt': null
              });
        });
      });
  @override
  Future<void> markRead(String notificationId) => _run(() => db
      .doc('profiles/$_uid/notifications/$notificationId')
      .update({'readAt': FieldValue.serverTimestamp()}));

  Future<void> _manage(String g, String uid, Map<String, dynamic>? changes) =>
      _run(() async {
        // Read the candidates before the transaction, then transactionally recheck the witness.
        final members = await db
            .collection('groups/$g/members')
            .get(const GetOptions(source: Source.server));
        await db.runTransaction((tx) async {
          final groupRef = db.doc('groups/$g');
          final group = (await tx.get(groupRef)).data()!;
          final actor = (await tx.get(_member(g, _uid))).data();
          final target = (await tx.get(_member(g, uid))).data();
          if (actor?['role'] != 'administrator' || target == null) {
            throw const AccountException('Administrator access is required.');
          }
          final witness = group['administratorUid'] as String? ?? _uid;
          final losesAdmin =
              changes == null || changes['role'] != 'administrator';
          String survivor = witness;
          if (witness == uid && losesAdmin) {
            final candidates = members.docs.where(
                (m) => m.id != uid && m.data()['role'] == 'administrator');
            if (candidates.isEmpty) {
              throw const AccountException(
                  'The group must retain at least one Administrator.');
            }
            survivor = candidates.first.id;
          }
          final survivorData = await tx.get(_member(g, survivor));
          if (survivorData.data()?['role'] != 'administrator') {
            throw const AccountException('Membership changed. Please retry.');
          }
          if (group['administratorUid'] != survivor) {
            tx.update(groupRef, {
              'administratorUid': survivor,
              'updatedAt': FieldValue.serverTimestamp()
            });
          }
          if (changes == null) {
            tx.delete(_member(g, uid));
            tx.delete(_index(g, uid));
          } else {
            tx.update(_member(g, uid),
                {...changes, 'updatedAt': FieldValue.serverTimestamp()});
          }
        });
      });
  @override
  Future<void> updateMember(
          {required String groupId,
          required String uid,
          required UserRole role,
          required MembershipPosition position,
          String customPosition = ''}) =>
      _manage(groupId, uid, {
        'role': role.name,
        'position': position.name,
        'customPosition':
            position == MembershipPosition.other ? customPosition.trim() : ''
      });
  @override
  Future<void> removeMember({required String groupId, required String uid}) =>
      _manage(groupId, uid, null);
}
