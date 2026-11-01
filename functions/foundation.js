import { randomInt, createHash } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
export const positions = ['vocalist', 'acousticGuitar', 'electricGuitar', 'bassGuitar', 'keyboard', 'drums', 'other'];
export function generateInvitationCode() {
  return Array.from({ length: 5 }, () => alphabet[randomInt(alphabet.length)]).join('');
}

function identity(auth) {
  if (!auth?.uid) throw new HttpsError('unauthenticated', 'Sign in with Google first.');
  if (auth.token?.email_verified !== true || auth.token?.firebase?.sign_in_provider !== 'google.com' ||
      typeof auth.token.email !== 'string' || auth.token.email.length > 320) {
    throw new HttpsError('permission-denied', 'A verified Google account is required.');
  }
  return { uid: auth.uid, email: auth.token.email, name: auth.token.name ?? '' };
}
function fields(data, allowed) {
  if (!data || typeof data !== 'object' || Array.isArray(data) || Object.keys(data).some(k => !allowed.includes(k))) {
    throw new HttpsError('invalid-argument', 'Unexpected request fields.');
  }
}
function text(value, label, max, optional = false) {
  if (typeof value !== 'string' || (!optional && !value.trim()) || value.trim().length > max || /[\x00-\x1f\x7f]/u.test(value)) {
    throw new HttpsError('invalid-argument', `${label} must be ${optional ? 'at most' : '1–'}${max} characters.`);
  }
  return value.trim();
}

/** All methods run on the trusted server. No client may choose a UID or role.
 * Code verification/regeneration are deliberately not exposed in this phase.
 */
export function createFoundationService(db, { codeGenerator = generateInvitationCode, now = () => Date.now() } = {}) {
  const profileRef = uid => db.doc(`profiles/${uid}`);
  const privateRef = uid => db.doc(`accountPrivate/${uid}`);
  function quotaRef(uid, action) { return db.doc(`foundationLimits/${uid}_${action}`); }
  function quota(tx, ref, snapshot, limit, period, clock) {
    const previous = snapshot.data();
    const fresh = !previous || previous.windowStart.toMillis() + period <= clock;
    const count = fresh ? 0 : previous.count;
    if (count >= limit) throw new HttpsError('resource-exhausted', 'Too many requests. Please try again later.');
    tx.set(ref, { windowStart: fresh ? Timestamp.fromMillis(clock) : previous.windowStart, count: count + 1 });
  }

  return {
    async ensureAccount(auth) {
      const user = identity(auth);
      for (let attempt = 0; attempt < 20; attempt++) {
        const candidate = codeGenerator();
        if (!/^[A-Z0-9]{5}$/.test(candidate)) throw new Error('Invalid server code generator.');
        const reservation = db.doc(`invitationCodeReservations/${candidate}`);
        const result = await db.runTransaction(async tx => {
          const [profile, secret, reserved] = await tx.getAll(profileRef(user.uid), privateRef(user.uid), reservation);
          if (!secret.exists && reserved.exists) return false;
          const clock = Timestamp.fromMillis(now());
          if (!secret.exists) {
            tx.create(privateRef(user.uid), { invitationCode: candidate, createdAt: clock, updatedAt: clock });
            tx.create(reservation, { uid: user.uid, createdAt: clock });
          }
          if (!profile.exists) {
            const names = String(user.name).trim().split(/\s+/u);
            tx.create(profileRef(user.uid), {
              firstName: (names.shift() ?? '').slice(0, 80), lastName: names.join(' ').slice(0, 80),
              email: user.email, profileComplete: false, createdAt: clock, updatedAt: clock, completedAt: null,
            });
          } else if (profile.data().email !== user.email) {
            tx.update(profileRef(user.uid), { email: user.email, updatedAt: clock });
          }
          return true;
        });
        if (result) return { ready: true };
      }
      throw new HttpsError('resource-exhausted', 'Could not allocate a private code. Please retry.');
    },

    async completeProfile(auth, data) {
      const user = identity(auth);
      fields(data, ['firstName', 'lastName']);
      const firstName = text(data.firstName, 'First name', 80);
      const lastName = text(data.lastName, 'Last name', 80);
      const limitRef = quotaRef(user.uid, 'profile');
      await db.runTransaction(async tx => {
        const [profile, secret, limit] = await tx.getAll(profileRef(user.uid), privateRef(user.uid), limitRef);
        if (!profile.exists || !secret.exists) throw new HttpsError('failed-precondition', 'Load your account before saving.');
        const clock = now();
        quota(tx, limitRef, limit, 20, 60000, clock);
        tx.update(profileRef(user.uid), { firstName, lastName, email: user.email, profileComplete: true,
          completedAt: profile.data().completedAt ?? Timestamp.fromMillis(clock), updatedAt: Timestamp.fromMillis(clock) });
      });
      return { saved: true };
    },

    async getPrivateInvitationCode(auth) {
      const user = identity(auth);
      const limitRef = quotaRef(user.uid, 'reveal');
      return db.runTransaction(async tx => {
        const [secret, profile, limit] = await tx.getAll(privateRef(user.uid), profileRef(user.uid), limitRef);
        if (!secret.exists || !profile.exists) throw new HttpsError('failed-precondition', 'Load your account first.');
        quota(tx, limitRef, limit, 30, 60000, now());
        return { code: secret.data().invitationCode };
      });
    },

    async createGroup(auth, data) {
      const user = identity(auth);
      fields(data, ['name', 'churchName', 'position', 'customPosition', 'requestId']);
      const name = text(data.name, 'Group name', 120);
      const churchName = text(data.churchName, 'Church name', 160);
      const position = data.position;
      if (!positions.includes(position)) throw new HttpsError('invalid-argument', 'Choose a supported position.');
      const customPosition = text(data.customPosition ?? '', 'Custom position', 80, position !== 'other');
      if (position !== 'other' && customPosition) throw new HttpsError('invalid-argument', 'Custom position is only available for Other.');
      if (typeof data.requestId !== 'string' || !/^[A-Za-z0-9_-]{16,80}$/.test(data.requestId)) {
        throw new HttpsError('invalid-argument', 'A valid creation request ID is required.');
      }
      const payloadHash = createHash('sha256').update(JSON.stringify({ name, churchName, position, customPosition })).digest('hex');
      const requestRef = privateRef(user.uid).collection('groupCreationRequests').doc(data.requestId);
      const limitRef = quotaRef(user.uid, 'createGroup');
      const groupRef = db.collection('groups').doc();
      return db.runTransaction(async tx => {
        const [profile, prior, limit] = await tx.getAll(profileRef(user.uid), requestRef, limitRef);
        if (!profile.exists || profile.data().profileComplete !== true) {
          throw new HttpsError('failed-precondition', 'Complete your profile before creating a group.');
        }
        if (prior.exists) {
          if (prior.data().payloadHash !== payloadHash) throw new HttpsError('already-exists', 'This creation request was already used.');
          return { groupId: prior.data().groupId };
        }
        const clock = now();
        quota(tx, limitRef, limit, 20, 86400000, clock);
        const timestamp = Timestamp.fromMillis(clock);
        tx.create(groupRef, { name, churchName, createdBy: user.uid, createdAt: timestamp,
          updatedAt: timestamp, memberCount: 1, accentColorValue: 0xff2f7a6b });
        tx.create(groupRef.collection('members').doc(user.uid), {
          uid: user.uid, groupId: groupRef.id, role: 'administrator', position, customPosition,
          firstName: profile.data().firstName, lastName: profile.data().lastName,
          createdAt: timestamp, updatedAt: timestamp,
        });
        tx.create(profileRef(user.uid).collection('memberships').doc(groupRef.id), {
          uid: user.uid, groupId: groupRef.id, createdAt: timestamp, updatedAt: timestamp,
        });
        tx.create(requestRef, { groupId: groupRef.id, payloadHash, createdAt: timestamp });
        return { groupId: groupRef.id };
      });
    },
  };
}
