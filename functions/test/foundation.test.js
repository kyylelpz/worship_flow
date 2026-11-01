import assert from 'node:assert/strict';
import { beforeEach, after, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { createFoundationService, generateInvitationCode } from '../foundation.js';

if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Refusing to test against production Firestore.');
const projectId = 'demo-worship-flow';
const app = initializeApp({ projectId }, 'foundation-test');
const db = getFirestore(app);
const service = createFoundationService(db);
const auth = uid => ({ uid, token: { name: 'Sam River', email: `${uid}@example.test`, email_verified: true,
  firebase: { sign_in_provider: 'google.com' } } });
const payload = { name: 'Morning Worship', churchName: 'Community Church', position: 'drums', customPosition: '', requestId: 'request-0123456789' };
beforeEach(async () => {
  const result = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(result.ok, true);
});
after(() => deleteApp(app));
async function complete(uid = 'owner') {
  await service.ensureAccount(auth(uid));
  await service.completeProfile(auth(uid), { firstName: 'Sam', lastName: 'River' });
}

test('secure generator format, collision retry and idempotent account setup', async () => {
  for (let i = 0; i < 100; i++) assert.match(generateInvitationCode(), /^[A-Z0-9]{5}$/);
  const candidates = ['AAAAA', 'AAAAA', 'BBBBB', 'CCCCC'];
  const collisionService = createFoundationService(db, { codeGenerator: () => candidates.shift() });
  await collisionService.ensureAccount(auth('one'));
  await collisionService.ensureAccount(auth('two'));
  await collisionService.ensureAccount(auth('two'));
  assert.equal((await db.doc('accountPrivate/two').get()).data().invitationCode, 'BBBBB');
  const profile = (await db.doc('profiles/two').get()).data();
  assert.equal(profile.profileComplete, false);
  assert.equal(profile.firstName, 'Sam');
  assert.equal(profile.lastName, 'River');
  assert.equal('invitationCode' in profile, false);
  assert.equal((await db.collection('invitationCodeReservations').get()).size, 2);
});
test('parallel first-account requests allocate exactly one private code', async () => {
  await Promise.all(Array.from({ length: 4 }, () => service.ensureAccount(auth('owner'))));
  assert.equal((await db.collection('invitationCodeReservations').get()).size, 1);
});
test('profile completion validates names, uses verified email and preserves private code', async () => {
  await service.ensureAccount(auth('owner'));
  const before = (await service.getPrivateInvitationCode(auth('owner'))).code;
  await service.completeProfile(auth('owner'), { firstName: ' Edited ', lastName: ' Name ' });
  const saved = (await db.doc('profiles/owner').get()).data();
  assert.equal(saved.firstName, 'Edited');
  assert.equal(saved.profileComplete, true);
  assert.equal(saved.email, 'owner@example.test');
  assert.equal((await service.getPrivateInvitationCode(auth('owner'))).code, before);
  for (const data of [{ firstName: '', lastName: 'Name' }, { firstName: 'x'.repeat(81), lastName: 'Name' },
    { firstName: 'Name', lastName: 'Name', email: 'spoof@test' }, { firstName: 'Name', lastName: 'Name', invitationCode: 'AAAAA' }]) {
    await assert.rejects(service.completeProfile(auth('owner'), data), { code: 'invalid-argument' });
  }
});
test('only verified Google identities can invoke trusted operations', async () => {
  await assert.rejects(service.ensureAccount(null), { code: 'unauthenticated' });
  await assert.rejects(service.ensureAccount({ ...auth('owner'), token: { ...auth('owner').token, email_verified: false } }), { code: 'permission-denied' });
  await assert.rejects(service.ensureAccount({ ...auth('owner'), token: { ...auth('owner').token, firebase: { sign_in_provider: 'anonymous' } } }), { code: 'permission-denied' });
});
test('group creation is atomic, idempotent, group-specific and always Administrator', async () => {
  await complete();
  const parallel = await Promise.all(Array.from({ length: 3 }, () => service.createGroup(auth('owner'), payload)));
  const result = parallel[0];
  assert.equal(parallel.every(r => r.groupId === result.groupId), true);
  assert.equal((await service.createGroup(auth('owner'), payload)).groupId, result.groupId);
  const member = (await db.doc(`groups/${result.groupId}/members/owner`).get()).data();
  assert.equal(member.role, 'administrator');
  assert.equal(member.position, 'drums');
  assert.equal(member.uid, 'owner');
  assert.equal(member.groupId, result.groupId);
  assert.ok(member.createdAt.toMillis());
  assert.ok(member.updatedAt.toMillis());
  assert.equal('email' in member, false);
  assert.equal((await db.doc(`profiles/owner/memberships/${result.groupId}`).get()).exists, true);
  assert.equal((await db.collection('groups').get()).size, 1);
  const second = await service.createGroup(auth('owner'), { ...payload, requestId: 'request-9876543210', position: 'other', customPosition: 'Sound Engineer' });
  assert.equal((await db.doc(`groups/${second.groupId}/members/owner`).get()).data().customPosition, 'Sound Engineer');
  assert.equal((await db.doc(`groups/${result.groupId}/members/owner`).get()).data().position, 'drums');
});
test('incomplete profiles, injected roles/UIDs and malformed group requests cannot write anything', async () => {
  await service.ensureAccount(auth('owner'));
  await assert.rejects(service.createGroup(auth('owner'), payload), { code: 'failed-precondition' });
  await complete();
  for (const bad of [{ ...payload, role: 'administrator' }, { ...payload, uid: 'victim' }, { ...payload, groupId: 'existing' },
    { ...payload, name: '' }, { ...payload, position: 'lead' }, { ...payload, position: 'other', customPosition: '' }, { ...payload, requestId: 'short' }]) {
    await assert.rejects(service.createGroup(auth('owner'), bad), { code: 'invalid-argument' });
  }
  assert.equal((await db.collection('groups').get()).size, 0);
});
test('private-code reads are owner-bound and rate limited; future verification is absent', async () => {
  await complete('one'); await complete('two');
  const one = (await service.getPrivateInvitationCode(auth('one'))).code;
  const two = (await service.getPrivateInvitationCode(auth('two'))).code;
  assert.notEqual(one, two);
  for (let i = 0; i < 29; i++) await service.getPrivateInvitationCode(auth('one'));
  await assert.rejects(service.getPrivateInvitationCode(auth('one')), { code: 'resource-exhausted' });
  assert.equal(service.verifyInvitationCode, undefined);
  assert.equal(service.regenerateInvitationCode, undefined);
});
