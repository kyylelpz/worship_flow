import {readFile} from 'node:fs/promises';
import {before,after,beforeEach,test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,collection,getDoc,getDocs,setDoc,updateDoc,deleteDoc,writeBatch,runTransaction,serverTimestamp,Timestamp} from 'firebase/firestore';
if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
let env;const db=(uid='admin')=>env.authenticatedContext(uid,{email:`${uid}@example.test`,email_verified:true,firebase:{sign_in_provider:'google.com'}}).firestore();
const ref=(d,path)=>doc(d,`groups/g/${path}`);const now=serverTimestamp;
const source='  {start_of_grid: Verse 1}\n| [1] - - - |\n{end_of_grid}\n\n[1]Hello  world  \n';
const arrangement=(id='a')=>({id,name:'Full Band',bpm:128,timeSignature:'4/4',chordProSource:source,referenceLink:'https://example.com/chart'});
const song=(id='song',arrangements=[arrangement()])=>({id,groupId:'g',title:'Title',artist:'Artist',category:'Praise',isFavorite:false,vocalistKeys:[{vocalistName:'Sam',key:'E'}],arrangements:Object.fromEntries(arrangements.map(a=>[a.id,a])),arrangementIds:arrangements.map(a=>a.id)});
const item=(songId='song',arrangementId='a')=>({songId,arrangementId,performanceKey:'E',vocalistName:'Sam'});
async function writeSong(value,id=value?.id??'song',actor='admin') {
 const d=db(actor);await runTransaction(d,async tx=>{
  const r=ref(d,`songs/${id}`);const old=await tx.get(r);const previous=new Set(old.data()?.arrangementIds??[]),next=new Set(value?.arrangementIds??[]);
  for(const key of previous)await tx.get(ref(d,`catalog/${key}`));
  for(const key of previous)if(!next.has(key))tx.delete(ref(d,`catalog/${key}`));
  for(const key of next)if(!previous.has(key))tx.set(ref(d,`catalog/${key}`),{songId:id,uses:[],target:id,updatedAt:now()});
  if(value)tx.set(r,{...value,arrangementChanges:[...new Set([...Object.keys(old.data()?.arrangements??{}),...Object.keys(value.arrangements)])].filter(k=>JSON.stringify(old.data()?.arrangements?.[k])!==JSON.stringify(value.arrangements[k])),createdAt:old.data()?.createdAt??now(),updatedAt:now()});else tx.delete(r);
 });
}
async function writeSetlist(id,items=[],publish=false,actor='admin',remove=false){
 const d=db(actor);await runTransaction(d,async tx=>{
  const r=ref(d,`setlists/${id}`);const old=await tx.get(r);const previous=old.data();
  const publishedItems=publish?items:previous?.publishedItems??[],draftItems=publish?null:items;
  const keys=remove?[]:[...new Set([...publishedItems,...draftItems??[]].map(i=>i.arrangementId))];
  const registrations=new Map();
  for(const key of new Set([...(previous?.referenceKeys??[]),...keys]))registrations.set(key,await tx.get(ref(d,`catalog/${key}`)));
  for(const [key,snapshot] of registrations){const uses=snapshot.data().uses.filter(v=>v!==id);if(keys.includes(key))uses.push(id);if(JSON.stringify([...uses].sort())!==JSON.stringify([...snapshot.data().uses].sort()))tx.update(snapshot.ref,{uses:uses.sort(),target:id,updatedAt:now()});}
  if(remove)tx.delete(r);else tx.set(r,{id,groupId:'g',name:'Sunday',serviceDateTime:Timestamp.fromDate(new Date('2027-01-01T09:30:00Z')),status:publish?'published':previous?.status??'draft',publishedItems,draftItems,publishedKeys:[...new Set(publishedItems.map(i=>i.arrangementId))].sort(),draftKeys:[...new Set((draftItems??[]).map(i=>i.arrangementId))].sort(),referenceKeys:keys,revision:(previous?.revision??0)+1,createdAt:previous?.createdAt??now(),updatedAt:now()});
 });
}
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-worship-flow',firestore:{rules:await readFile(new URL('../firestore.rules',import.meta.url),'utf8')}});});
beforeEach(async()=>{await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{
 const d=c.firestore(),t=Timestamp.now();await setDoc(doc(d,'groups/g'),{name:'Group'});
 for(const [uid,role] of [['admin','administrator'],['leader','worshipLeader'],['trainee','worshipTrainee']])await setDoc(doc(d,`groups/g/members/${uid}`),{role});
});});
after(async()=>env?.cleanup());
test('Song CRUD preserves canonical source, metadata and stable IDs; only own group reads',async()=>{
 await assertSucceeds(writeSong(song()));assert.equal((await getDoc(ref(db(), 'songs/song'))).data().arrangements.a.chordProSource,source);
 await assertSucceeds(writeSong({...song(),title:'Edited',arrangements:{a:{...arrangement(),bpm:100}}},'song','leader'));
 assert.equal((await getDoc(ref(db('trainee'),'songs/song'))).data().arrangementIds[0],'a');
 await assertSucceeds(getDocs(collection(db('trainee'),'groups/g/songs')));
 await assertFails(getDoc(ref(db('outsider'),'songs/song')));
 await assertFails(getDoc(doc(db(),'groups/other/songs/song')));
 await assertFails(writeSong(song('forbidden',[arrangement('b')]),'forbidden','trainee'));
 await assertSucceeds(writeSong(null));
});
test('setlist ordering, draft/published independence and reference release',async()=>{
 await writeSong(song('song',[arrangement('a'),arrangement('b')]));
 await writeSetlist('service',[item('song','a'),item('song','b')],true);
 await writeSetlist('service',[item('song','b')]);
 const d=(await getDoc(ref(db('trainee'),'setlists/service'))).data();
 assert.deepEqual(d.publishedItems.map(v=>v.arrangementId),['a','b']);assert.deepEqual(d.draftItems.map(v=>v.arrangementId),['b']);assert.equal(d.status,'published');
 await assertFails(writeSong(song('song',[arrangement('b')])));
 await writeSetlist('service',[item('song','b')],true);await assertSucceeds(writeSong(song('song',[arrangement('b')])));
 await assertFails(writeSong(null));await writeSetlist('service',[],false,'admin',true);await assertSucceeds(writeSong(null));
});
test('rules reject forged registries, dangling refs, cross-group/role writes and direct destructive bypasses',async()=>{
 await writeSong(song());await writeSetlist('service',[item()]);
 await assertFails(deleteDoc(ref(db(),'songs/song')));
 await assertFails(updateDoc(ref(db(),'songs/song'),{arrangements:[],arrangementIds:[],updatedAt:now()}));
 await assertFails(deleteDoc(ref(db(),'catalog/a')));
 await assertFails(updateDoc(ref(db(),'catalog/a'),{uses:[],target:'service',updatedAt:now()}));
 await assertFails(updateDoc(ref(db(),'catalog/a'),{songId:'other',target:'service',updatedAt:now()}));
 await assertFails(updateDoc(ref(db(),'setlists/service'),{draftItems:[item('other','a')],revision:2,updatedAt:now()}));
 await assertFails(writeSetlist('service',[item()],true,'trainee'));
 await assertFails(deleteDoc(ref(db('outsider'),'setlists/service')));

});
test('shape, immutable ownership/IDs, musical metadata and missing-reference validation',async()=>{
 await writeSong(song());
 for(const patch of [{groupId:'other'},{id:'different'},{isFavorite:'yes'},{title:''},{vocalistKeys:[{vocalistName:'Sam',key:'not a key'}]},{arrangements:{a:{...arrangement(),bpm:0}}},{arrangements:{a:{...arrangement(),timeSignature:'8/9'}}},{extra:true}])await assertFails(writeSong({...song(),...patch}));
 await writeSetlist('service',[]);
 for(const patch of [{groupId:'other'},{id:'other'},{revision:1},{name:''},{serviceDateTime:'tomorrow'},{status:'invalid'},{draftItems:[item()]},{extra:true}])await assertFails(updateDoc(ref(db(),'setlists/service'),{...patch,updatedAt:now(),...('revision' in patch?{}:{revision:2})}));
});
test('maximum supported arrangement/preset and setlist sizes validate under rules limits',async()=>{
 const arrangements=[];
 for(let i=0;i<8;i++) {
  arrangements.push(arrangement(`a${i}`));
  await assertSucceeds(writeSong(song('song',[...arrangements])));;
 }
 await assertSucceeds(writeSong({...song('song',arrangements),vocalistKeys:Array.from({length:8},(_,i)=>({vocalistName:`Singer ${i}`,key:'F#m'}))}));

 const items=Array.from({length:6},(_,i)=>item('song',`a${i%8}`));
 await assertSucceeds(writeSetlist('service',items,true));await assertSucceeds(writeSetlist('service',[...items].reverse()));
 await assertFails(writeSetlist('large',Array.from({length:7},()=>item('song','a0'))));
});
test('concurrent deletion versus new reference cannot create dangling setlist',async()=>{
 await writeSong(song());
 const results=await Promise.allSettled([writeSetlist('race',[item()]),writeSong(null)]);
 assert.ok(results.some(v=>v.status==='rejected'));
 const exists=(await getDoc(ref(db(),'songs/song'))).exists();const service=await getDoc(ref(db(),'setlists/race'));assert.ok(!service.exists()||exists);
});

test('published and draft may reference disjoint songs; cleanup prevents stale locks',async()=>{
 const first=Array.from({length:6},(_,i)=>arrangement(`first-${i}`)),second=Array.from({length:6},(_,i)=>arrangement(`second-${i}`));
 for(let n=1;n<=6;n++){await writeSong(song('first',first.slice(0,n)));await writeSong(song('second',second.slice(0,n)));}
 await writeSetlist('independent',first.map(a=>item('first',a.id)),true);
 await writeSetlist('independent',second.map(a=>item('second',a.id)));
 const value=(await getDoc(ref(db(),'setlists/independent'))).data();assert.equal(value.referenceKeys.length,12);
 await assertFails(writeSong(null,'first'));await assertFails(writeSong(null,'second'));
 await writeSetlist('independent',[],false,'admin',true);await assertSucceeds(writeSong(null,'first'));await assertSucceeds(writeSong(null,'second'));
});
test('a skipped unchanged version cannot hide its references or forge its key manifest',async()=>{
 await writeSong(song());await writeSetlist('service',[item()],true);
 const d=db();const b=writeBatch(d);b.update(ref(d,'setlists/service'),{referenceKeys:[],publishedKeys:[],draftKeys:[],revision:2,updatedAt:now()});b.update(ref(d,'catalog/a'),{uses:[],target:'service',updatedAt:now()});await assertFails(b.commit());
});

test('initial song creation supports two arrangements and four presets; larger initial batches fail safely',async()=>{
 const vocalKeys=Array.from({length:4},(_,i)=>({vocalistName:`Vocalist ${i}`,key:'Bb minor'}));
 await assertSucceeds(writeSong({...song('song',[arrangement('a'),arrangement('b')]),vocalistKeys:vocalKeys}));
 await assertFails(writeSong(song('other',[arrangement('c'),arrangement('d'),arrangement('e')])));
});
