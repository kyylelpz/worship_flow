import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, signInWithCredential, GoogleAuthProvider, signOut } from 'firebase/auth';
import { getFirestore, connectFirestoreEmulator, doc, getDoc, collection, getDocs } from 'firebase/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('This test requires Auth, Firestore and Functions emulators.');
}
const app = initializeApp({ projectId: 'demo-worship-flow', apiKey: 'emulator-only', authDomain: 'demo-worship-flow.firebaseapp.com' }, 'callable-flow-test');
const auth = getAuth(app);
connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
const db = getFirestore(app);
const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
connectFirestoreEmulator(db, host, Number(port));
after(() => deleteApp(app));
async function call(name, data = {}, token) {
  const response = await fetch(`http://127.0.0.1:5001/demo-worship-flow/asia-east2/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }),
  });
  return { status: response.status, body: await response.json() };
}
test('emulator Google identity → incomplete profile → completion → group → own membership → sign-out', async () => {
  // Unsigned Google token accepted ONLY by Auth emulator. Never used by app code.
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const googleToken = `${encode({ alg: 'none', typ: 'JWT' })}.${encode({
    sub: 'phase3a-flow-google', email: 'phase3a-flow@example.test', email_verified: true,
    name: 'Taylor Rivers', iss: 'https://accounts.google.com', aud: 'emulator-only',
    iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 3600,
  })}.`;
  const result = await signInWithCredential(auth, GoogleAuthProvider.credential(googleToken));
  const token = await result.user.getIdToken();
  assert.equal((await call('ensureAccount', {}, token)).status, 200);
  const profile = await getDoc(doc(db, `profiles/${result.user.uid}`));
  assert.equal(profile.data().profileComplete, false);
  assert.equal(profile.data().firstName, 'Taylor');
  assert.equal(profile.data().lastName, 'Rivers');
  assert.equal((await call('createGroup', { name: 'Denied', churchName: 'Church', position: 'drums', requestId: 'denied-0123456789' }, token)).status, 400);
  assert.equal((await call('completeProfile', { firstName: 'Taylor', lastName: 'Rivers' }, token)).status, 200);
  assert.equal((await getDoc(doc(db, `profiles/${result.user.uid}`))).data().profileComplete, true);
  const code = await call('getPrivateInvitationCode', {}, token);
  assert.match(code.body.result.code, /^[A-Z0-9]{5}$/);
  const created = await call('createGroup', { name: 'Emulator Worship', churchName: 'Emulator Church',
    position: 'vocalist', customPosition: '', requestId: 'flow-create-0123456789' }, token);
  assert.equal(created.status, 200);
  const groupId = created.body.result.groupId;
  const own = await getDocs(collection(db, `profiles/${result.user.uid}/memberships`));
  assert.equal(own.docs.some(d => d.id === groupId), true);
  assert.equal((await getDoc(doc(db, `groups/${groupId}/members/${result.user.uid}`))).data().role, 'administrator');
  assert.equal((await getDoc(doc(db, `groups/${groupId}`))).data().name, 'Emulator Worship');
  assert.equal((await call('getPrivateInvitationCode')).status, 401);
  await signOut(auth);
  assert.equal(auth.currentUser, null);
  await assert.rejects(getDoc(doc(db, `groups/${groupId}`)));
});
