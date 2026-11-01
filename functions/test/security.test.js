import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, collection, Timestamp } from 'firebase/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run security tests with the Firestore emulator.');
let env;
const google = { email: 'owner@example.test', email_verified: true, firebase: { sign_in_provider: 'google.com' } };
const clock = Timestamp.now();
const profile = { firstName: 'Sam', lastName: 'River', email: google.email, profileComplete: true,
  createdAt: clock, updatedAt: clock, completedAt: clock };
const member = { uid: 'owner', groupId: 'group-one', firstName: 'Sam', lastName: 'River',
  role: 'administrator', position: 'drums', customPosition: '', createdAt: clock, updatedAt: clock };
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-worship-flow',
    firestore: { rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'profiles/owner'), profile);
    await setDoc(doc(db, 'profiles/outsider'), { ...profile, email: 'outsider@example.test' });
    await setDoc(doc(db, 'profiles/incomplete'), { ...profile, profileComplete: false });
    await setDoc(doc(db, 'groups/group-one'), { name: 'Worship', churchName: 'Church', createdBy: 'owner',
      memberCount: 1, accentColorValue: 1, createdAt: clock, updatedAt: clock });
    await setDoc(doc(db, 'groups/group-one/members/owner'), member);
    await setDoc(doc(db, 'profiles/owner/memberships/group-one'), { uid: 'owner', groupId: 'group-one', createdAt: clock, updatedAt: clock });
    await setDoc(doc(db, 'accountPrivate/owner'), { invitationCode: 'A5NJ3', createdAt: clock, updatedAt: clock });
    await setDoc(doc(db, 'invitationCodeReservations/A5NJ3'), { uid: 'owner', createdAt: clock });
  });
});
after(async () => env.cleanup());
const database = (uid = 'owner', claims = google) => env.authenticatedContext(uid, claims).firestore();

test('anonymous and non-Google/unverified accounts cannot read foundation data', async () => {
  for (const db of [env.unauthenticatedContext().firestore(), database('owner', { ...google, email_verified: false }),
    database('owner', { ...google, firebase: { sign_in_provider: 'password' } })]) {
    await assertFails(getDoc(doc(db, 'profiles/owner')));
    await assertFails(getDoc(doc(db, 'groups/group-one')));
  }
});
test('profiles are owner-only gets, never publicly listable', async () => {
  await assertSucceeds(getDoc(doc(database(), 'profiles/owner')));
  await assertFails(getDoc(doc(database('outsider'), 'profiles/owner')));
  await assertFails(getDocs(collection(database(), 'profiles')));
});
test('private code, reservation index and quotas are denied even to owners', async () => {
  for (const path of ['accountPrivate/owner', 'invitationCodeReservations/A5NJ3', 'foundationLimits/owner_reveal']) {
    await assertFails(getDoc(doc(database(), path)));
    await assertFails(setDoc(doc(database(), path), { invitationCode: 'AAAAA' }));
  }
});
test('the exact membership-index and group/member reads used by the app work', async () => {
  await assertSucceeds(getDocs(collection(database(), 'profiles/owner/memberships')));
  await assertSucceeds(getDoc(doc(database(), 'groups/group-one')));
  await assertSucceeds(getDocs(collection(database(), 'groups/group-one/members')));
  await assertFails(getDocs(collection(database('outsider'), 'profiles/owner/memberships')));
  await assertFails(getDoc(doc(database('outsider'), 'groups/group-one')));
  await assertFails(getDocs(collection(database(), 'groups')));
});
test('clients cannot create or corrupt profiles, impersonate owners or add fields', async () => {
  for (const data of [profile, { ...profile, isAdmin: true }, { ...profile, firstName: 'x'.repeat(10000) },
    { ...profile, firstName: 42 }, { firstName: 'Missing fields' }]) {
    await assertFails(setDoc(doc(database(), 'profiles/owner'), data));
    await assertFails(setDoc(doc(database(), 'profiles/stolen'), data));
  }
  await assertFails(updateDoc(doc(database(), 'profiles/owner'), { createdAt: Timestamp.fromMillis(1), email: 'spoof@example.test' }));
  await assertFails(deleteDoc(doc(database(), 'profiles/owner')));
});
test('client group creation, self-membership and role/position escalation are denied', async () => {
  await assertFails(setDoc(doc(database('outsider'), 'groups/stolen'), { createdBy: 'owner' }));
  await assertFails(setDoc(doc(database('outsider'), 'groups/group-one/members/outsider'), { ...member, uid: 'outsider' }));
  await assertFails(updateDoc(doc(database(), 'groups/group-one/members/owner'), { role: 'worshipLeader' }));
  await assertFails(updateDoc(doc(database(), 'groups/group-one/members/owner'), { position: 'keyboard', customPosition: 'x'.repeat(10000) }));
  await assertFails(setDoc(doc(database(), 'profiles/owner/memberships/stolen'), { uid: 'owner', groupId: 'stolen' }));
  await assertFails(updateDoc(doc(database(), 'groups/group-one'), { createdBy: 'outsider', memberCount: 99 }));
});
test('incomplete profiles and orphaned group subcollections do not grant access', async () => {
  await assertSucceeds(getDoc(doc(database('incomplete'), 'profiles/incomplete')));
  await assertFails(getDocs(collection(database('incomplete'), 'profiles/incomplete/memberships')));
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'groups/orphan/members/owner'), { ...member, groupId: 'orphan' });
  });
  await assertFails(getDoc(doc(database(), 'groups/orphan/members/owner')));
});
test('songs and setlists remain denied until their backend migration', async () => {
  await assertFails(setDoc(doc(database(), 'groups/group-one/songs/song'), { title: 'Song' }));
  await assertFails(getDoc(doc(database(), 'groups/group-one/setlists/setlist')));
});
