import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, runTransaction, serverTimestamp, query, where } from 'firebase/firestore';
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Firestore emulator required; never run against production.');
let env;
const email = uid => `${uid}@example.test`;
const db = (uid='owner', claims={}) => env.authenticatedContext(uid,{email:email(uid),email_verified:true,firebase:{sign_in_provider:'google.com'},...claims}).firestore();
const ref = (d,p) => doc(d,p);
const own = (uid) => `profiles/${uid}`;
const mem = (u,g='group-one') => `groups/${g}/members/${u}`;
const idx = (u,g='group-one') => `${own(u)}/memberships/${g}`;
const inv = (u='recipient',g='group-one') => `${own(u)}/invitations/${g}`;
const now = serverTimestamp;
const member = (u,role,g='group-one') => ({uid:u,groupId:g,firstName:u,lastName:'Person',role,position:'vocalist',customPosition:'',createdAt:now(),updatedAt:now()});
const index = (u,g='group-one') => ({uid:u,groupId:g,createdAt:now(),updatedAt:now()});
async function profile(u,complete=true) {
 const d=db(u), b=writeBatch(d);
 b.set(ref(d,own(u)),{firstName:u,lastName:'Person',email:email(u),profileComplete:complete,allowInvitations:complete,
  createdAt:now(),updatedAt:now(),completedAt:complete?now():null});
 if(complete) b.set(ref(d,`emailDirectory/${email(u)}`),{uid:u});
 await b.commit();
}
async function createGroup(u='owner',g='group-one') {
 const d=db(u), b=writeBatch(d);
 b.set(ref(d,`groups/${g}`),{name:'Worship Team',churchName:'Church',createdBy:u,administratorUid:u,memberCount:1,accentColorValue:1,createdAt:now(),updatedAt:now()});
 b.set(ref(d,mem(u,g)),member(u,'administrator',g)); b.set(ref(d,idx(u,g)),index(u,g));
 await b.commit();
}
async function invite(u='recipient',role='worshipTrainee',g='group-one',actor='owner',extra={}) {
 const d=db(actor);
 await setDoc(ref(d,`directoryAccess/${actor}`),{groupId:g});
 const directory = await getDoc(ref(d,`emailDirectory/${email(u)}`)); assert.equal(directory.data()?.uid,u);
 const group=await getDoc(ref(d,`groups/${g}`));
 await setDoc(ref(d,inv(u,g)),{groupId:g,recipientUid:u,groupName:group.data().name,inviterUid:actor,role,
  position:'vocalist',customPosition:'',notificationId:doc(collection(d,'unused')).id,status:'pending',createdAt:now(),updatedAt:now(),...extra});
}
async function respond(u='recipient',accept=true,g='group-one',extraMember={}) {
 const d=db(u);
 await runTransaction(d,async tx => {
  const i=(await tx.get(ref(d,inv(u,g)))).data();
  const p=accept?(await tx.get(ref(d,own(u)))).data():null;
  tx.update(ref(d,inv(u,g)),{status:accept?'accepted':'declined',updatedAt:now()});
  if(!accept)return;
  tx.set(ref(d,mem(u,g)),{...member(u,i.role,g),firstName:p.firstName,lastName:p.lastName,position:i.position,customPosition:i.customPosition,...extraMember});
  tx.set(ref(d,idx(u,g)),index(u,g));
  tx.set(ref(d,`${own(i.inviterUid)}/notifications/${i.notificationId}`),{recipientUid:u,groupId:g,groupName:i.groupName,createdAt:now(),readAt:null});
 });
}
async function manage(actor,u,{role,position='vocalist',customPosition='',remove=false,witness}={}) {
 const d=db(actor),b=writeBatch(d);
 if(witness)b.update(ref(d,'groups/group-one'),{administratorUid:witness,updatedAt:now()});
 if(remove){b.delete(ref(d,mem(u)));b.delete(ref(d,idx(u)));}
 else b.update(ref(d,mem(u)),{role,position,customPosition,updatedAt:now()});
 await b.commit();
}
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-worship-flow',firestore:{rules:await readFile(new URL('../firestore.rules',import.meta.url),'utf8')}});});
beforeEach(async()=>{await env.clearFirestore();for(const u of ['owner','recipient','outsider','leader','trainee']) await profile(u);await createGroup();});
after(async()=>env?.cleanup());

test('verified Google profile completion is owner-only with exact schema and opt-in directory',async()=>{
 await profile('draft',false);
 const d=db('draft');
 await assertFails(updateDoc(ref(d,own('draft')),{profileComplete:true,allowInvitations:true,completedAt:now(),updatedAt:now()}));
 const b=writeBatch(d);b.update(ref(d,own('draft')),{profileComplete:true,allowInvitations:true,completedAt:now(),updatedAt:now()});b.set(ref(d,`emailDirectory/${email('draft')}`),{uid:'draft'});await assertSucceeds(b.commit());
 for(const data of [{role:'administrator'},{firstName:''},{lastName:42},{createdAt:now()},{allowInvitations:'yes'},{profileComplete:false}]) await assertFails(updateDoc(ref(d,own('draft')),{...data,updatedAt:now()}));
 await assertFails(getDoc(ref(db('recipient'),own('owner'))));await assertFails(getDocs(collection(db(),'profiles')));
 for(const bad of [env.unauthenticatedContext().firestore(),db('owner',{email_verified:false}),db('owner',{firebase:{sign_in_provider:'password'}})]) await assertFails(getDoc(ref(bad,own('owner'))));
});
test('atomic group bootstrap grants only its creator admin and index; incomplete/forged writes denied',async()=>{
 await assertSucceeds(createGroup('recipient','second-group'));
 await assertFails(setDoc(ref(db('outsider'),mem('outsider')) ,member('outsider','administrator')));
 await assertFails(setDoc(ref(db('outsider'),idx('outsider')),index('outsider')));
 await profile('draft',false);await assertFails(createGroup('draft','bad-group'));
 const d=db('outsider'),b=writeBatch(d);b.set(ref(d,'groups/forged'),{name:'Forged',churchName:'X',createdBy:'owner',administratorUid:'outsider',memberCount:1,accentColorValue:1,createdAt:now(),updatedAt:now()});b.set(ref(d,mem('outsider','forged')),member('outsider','administrator','forged'));b.set(ref(d,idx('outsider','forged')),index('outsider','forged'));await assertFails(b.commit());
});
test('directory requires live admin proof, exact email only, no listing/private profiles',async()=>{
 await assertFails(getDoc(ref(db('outsider'),`emailDirectory/${email('recipient')}`)));
 await assertFails(setDoc(ref(db('outsider'),'directoryAccess/outsider'),{groupId:'group-one'}));
 await setDoc(ref(db(),'directoryAccess/owner'),{groupId:'group-one'});
 await assertSucceeds(getDoc(ref(db(),`emailDirectory/${email('recipient')}`)));
 await assertFails(getDocs(collection(db(),'emailDirectory')));
 await assertFails(getDocs(query(collection(db(),'emailDirectory'),where('uid','==','recipient'))));
 await assertFails(getDoc(ref(db(),own('recipient'))));
 await assertFails(setDoc(ref(db(),`emailDirectory/${email('recipient')}`),{uid:'owner'}));
});
test('privacy disables new invitations but retains pending accept/decline across sessions',async()=>{
 await invite();const d=db('recipient'),b=writeBatch(d);b.update(ref(d,own('recipient')),{allowInvitations:false,updatedAt:now()});b.delete(ref(d,`emailDirectory/${email('recipient')}`));await assertSucceeds(b.commit());
 await assertFails(updateDoc(ref(d,own('recipient')),{allowInvitations:true,updatedAt:now()}));
 await createGroup('owner','group-two');
 const raw=(await getDoc(ref(db(),inv()))).data();
 await assertFails(setDoc(ref(db(),inv('recipient','group-two')),{...raw,groupId:'group-two',createdAt:now(),updatedAt:now()}));
 const pending=await getDocs(query(collection(db('recipient'),'profiles/recipient/invitations'),where('status','==','pending')));assert.equal(pending.size,1);
 await assertSucceeds(respond());await assertSucceeds(getDoc(ref(db('recipient'),'groups/group-one')));
});
test('invitation validates self, existing/duplicate, role, custom position, identity and names',async()=>{
 await assertFails(invite('owner'));await invite();await assertFails(invite());
 await assertFails(respond('recipient',true,'group-one',{role:'administrator'}));
 await assertSucceeds(respond());await assertFails(invite());
 for(const patch of [{role:'superAdmin'},{position:'unknown'},{position:'other',customPosition:''},{groupId:'other-group'},{inviterUid:'outsider'},{recipientUid:'owner'},{groupName:'Forged'},{extra:'field'}]) await assertFails(invite('outsider','worshipLeader','group-one','owner',patch));
});
test('atomic acceptance preserves assignment, index, notification; no partial acceptance or replay',async()=>{
 await invite('recipient','worshipLeader','group-one','owner',{position:'other',customPosition:'Sound Engineer'});
 const d=db('recipient');await assertFails(updateDoc(ref(d,inv()),{status:'accepted',updatedAt:now()}));
 await assertSucceeds(respond());
 const m=(await getDoc(ref(d,mem('recipient')))).data();assert.equal(m.role,'worshipLeader');assert.equal(m.customPosition,'Sound Engineer');
 assert.equal((await getDocs(collection(d,'profiles/recipient/memberships'))).size,1);
 const notices=await getDocs(query(collection(db(),'profiles/owner/notifications'),where('readAt','==',null)));assert.equal(notices.size,1);
 await assertFails(respond());await assertFails(getDocs(collection(db('outsider'),'profiles/owner/notifications')));
 await updateDoc(notices.docs[0].ref,{readAt:now()});assert.equal((await getDocs(query(collection(db(),'profiles/owner/notifications'),where('readAt','==',null)))).size,0);
});
test('decline is terminal, creates no membership or notification, allows independent reinvite',async()=>{
 await invite();await assertSucceeds(respond('recipient',false));
 await assertFails(getDoc(ref(db('recipient'),'groups/group-one')));
 assert.equal((await getDocs(collection(db(),'profiles/owner/notifications'))).size,0);
 await assertFails(respond());await assertSucceeds(invite('recipient','worshipLeader'));await assertSucceeds(respond());
});
test('only admins invite or manage; trainees/leaders cannot promote themselves or cross groups',async()=>{
 for(const [u,r] of [['trainee','worshipTrainee'],['leader','worshipLeader']]){await invite(u,r);await respond(u);await assertFails(invite('outsider','administrator','group-one',u));await assertFails(manage(u,u,{role:'administrator'}));await assertFails(manage(u,'owner',{remove:true}));}
 await createGroup('outsider','other');await assertFails(manage('outsider','owner',{role:'worshipTrainee'}));
 await assertFails(getDocs(collection(db('recipient'),'groups/group-one/members')));
});
test('admins change role/position and remove atomically; last admin survives and concurrent removals cannot eliminate all',async()=>{
 await invite('recipient','administrator');await respond();
 await assertSucceeds(manage('owner','recipient',{role:'worshipLeader',position:'drums'}));
 assert.equal((await getDoc(ref(db(),mem('recipient')))).data().position,'drums');
 await assertFails(manage('owner','owner',{remove:true}));
 await manage('owner','recipient',{role:'administrator'});
 const result=await Promise.allSettled([manage('owner','owner',{role:'worshipTrainee',witness:'recipient'}),manage('recipient','recipient',{role:'worshipTrainee',witness:'owner'})]);
 assert.ok(result.some(r=>r.status==='rejected'));
 const members=await getDocs(collection(db(),'groups/group-one/members'));assert.ok(members.docs.some(d=>d.data().role==='administrator'));
});
test('removal requires deleting index; revoked administrator proof and pending invitations cannot grant roles',async()=>{
 await invite('recipient','administrator');await respond();await invite('outsider','administrator','group-one','recipient');
 await assertFails(deleteDoc(ref(db(),mem('recipient'))));
 await assertSucceeds(manage('owner','recipient',{remove:true}));
 assert.equal((await getDocs(collection(db('recipient'),'profiles/recipient/memberships'))).size,0);
 await assertFails(getDoc(ref(db('recipient'),`emailDirectory/${email('outsider')}`)));
 await assertFails(respond('outsider'));await assertSucceeds(respond('outsider',false));
});
test('cannot forge/modify invitations or acceptance notifications, or access legacy secrets/future catalogs',async()=>{
 await invite();const d=db('recipient');
 await assertFails(updateDoc(ref(d,inv()),{role:'administrator',updatedAt:now()}));
 await assertFails(updateDoc(ref(d,inv()),{inviterUid:'recipient',updatedAt:now()}));
 await assertFails(setDoc(ref(db(),'profiles/owner/notifications/Forged'),{recipientUid:'recipient',groupId:'group-one',groupName:'Worship Team',createdAt:now(),readAt:null}));
 for(const path of ['accountPrivate/owner','invitationCodeReservations/ABCDE','foundationLimits/owner','songs/a','setlists/a']){await assertFails(getDoc(ref(db(),path)));await assertFails(setDoc(ref(db(),path),{value:true}));}
});
test('multiple memberships stay independent and owner indexes cannot be enumerated cross-user',async()=>{
 await createGroup('outsider','second');await invite('recipient','worshipTrainee');await respond();await invite('recipient','worshipLeader','second','outsider');await respond('recipient',true,'second');
 assert.equal((await getDocs(collection(db('recipient'),'profiles/recipient/memberships'))).size,2);
 assert.equal((await getDoc(ref(db('recipient'),mem('recipient','second')))).data().role,'worshipLeader');
 await assertFails(getDocs(collection(db(),'profiles/recipient/memberships')));
});

test('guardian cannot be forged or pointed to a trainee; group metadata and cross-user indexes stay immutable',async()=>{
 await invite();await respond();
 for(const patch of [{administratorUid:'recipient'},{administratorUid:'missing'},{createdBy:'recipient'},{name:'Hacked'},{memberCount:99},{administratorUid:['owner']}]) {
  await assertFails(updateDoc(ref(db(),'groups/group-one'),{...patch,updatedAt:now()}));
 }
 await assertFails(updateDoc(ref(db(),'profiles/recipient/memberships/group-one'),{role:'administrator',updatedAt:now()}));
 await assertFails(manage('owner','recipient',{role:'worshipLeader',position:'other',customPosition:''}));
 await assertFails(deleteDoc(ref(db(),'profiles/owner/memberships/group-one')));
});
test('legacy Phase 3A profiles and groups are adopted without granting new authority',async()=>{
 await env.withSecurityRulesDisabled(async context=>{
  const d=context.firestore();
  const p=(await getDoc(ref(d,own('owner')))).data();delete p.allowInvitations;await setDoc(ref(d,own('owner')),p);
  await deleteDoc(ref(d,`emailDirectory/${email('owner')}`));
  const g=(await getDoc(ref(d,'groups/group-one'))).data();delete g.administratorUid;await setDoc(ref(d,'groups/group-one'),g);
 });
 const d=db(),b=writeBatch(d);b.update(ref(d,own('owner')),{allowInvitations:true,updatedAt:now()});b.set(ref(d,`emailDirectory/${email('owner')}`),{uid:'owner'});await assertSucceeds(b.commit());
 await assertSucceeds(updateDoc(ref(d,'groups/group-one'),{administratorUid:'owner',updatedAt:now()}));
 await assertFails(updateDoc(ref(db('outsider'),'groups/group-one'),{administratorUid:'outsider',updatedAt:now()}));
 await assertSucceeds(invite());await assertSucceeds(respond());
});
