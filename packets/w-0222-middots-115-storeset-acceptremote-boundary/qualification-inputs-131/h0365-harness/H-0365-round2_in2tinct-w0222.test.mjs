// Separate raw custody for unreadable local / base / remote admin data. Production applyRemote + helper bodies, real merge, real state-scope.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {mergeStates} from '../state-merge.js';
import {cleanAdminProfileState} from '../admin-profile-state.js';
import {packState, readScopedState} from '../state-scope.js';
const app=readFileSync(new URL('../app.js',import.meta.url),'utf8');
const hs=app.indexOf('    const HELD_PREFIX'), he=app.indexOf('    const adminDefaults');
const helperSrc=app.slice(hs,app.indexOf('    reactExports.useEffect(() => {\n        const onStorage'));
const s0=app.indexOf('    const applyRemote = async (r');
const body=app.slice(s0,app.indexOf('    // once, on load:',s0));
const BAD={version:1,profiles:{desktop:{textPt:'distinct-corrupt-custody'}},unknown:{mustRetain:'marker'}};
const VALID={version:1,profiles:{desktop:{textFace:'fragment-mono',indexFace:'fragment-mono',textPt:12,indexPt:10,textAxes:{},indexAxes:{},lh:1.5,hz:0,textWidthEm:29}}};
function setup({local,remote,base,storedText,ls=({}),fail={on:false},sc={scope:'scope-a',tok:'t'}}){
 if(storedText)ls['middots-state']=storedText;
 const fx={accepted:null,pushed:null,applied:null,notes:[]};
 const held={current:false},rem={current:undefined};
 const c={TextEncoder,DataView,Uint8Array,reactExports:{useRef:v=>({current:v})},STATE_KEY:'middots-state',localStorage:mkLS(ls,fail),isJoined:()=>true,token:()=>sc.tok,cachedScope:()=>sc.scope,packState,readScopedState,
  adminEditEpoch:{current:0},adminProfilesBinding:{current:'t'},adminProfilesRemote:rem,cleanAdminProfileState,currentRead:()=>true,scopeForToken:async()=>sc.scope,
  saveStateRef:{current:()=>local},storeGet:k=>ls[k]??null,storeSet:(k,v)=>{ls[k]=v},getBase:()=>base??null,syncLoading:{current:false},mergeStates,adminProfilesHeld:held,
  showNote:t=>fx.notes.push(t),applySaved:t=>{fx.applied=JSON.parse(t)},acceptRemote:(rev,state)=>{fx.accepted={rev,state}},pushMerged:async(state)=>{fx.pushed=state;return {}},overlayRecovery:async s=>s,scrollerRef:{current:null},localEditEpoch:{current:0},saveRecovery:()=>true,piecesOf:()=>[],handleMergeReceipt:()=>{},currentWrite:()=>true,retryMerged:()=>{},requestAnimationFrame:()=>{}};
 vm.createContext(c);vm.runInContext((globalThis.__src||helperSrc)+'\n'+body+'\nglobalThis.run=applyRemote;globalThis.pack=packWithCustody;globalThis.write=writeScopedWithCustody;globalThis.repair=repairAdminCustody;globalThis.load=loadAdminCustody;',c);
 return {c,ls,fx,held,rem};
}
const stored=ls=>JSON.parse(ls['middots-state']);
const heldOf=(ls,slot,scope='scope-a')=>Object.keys(ls).filter(k=>k.startsWith('middots-admin-held:'+scope+':'+slot+':')).map(k=>JSON.parse(ls[k]).raw);
function mkLS(ls,fail){const api={getItem:k=>ls[k]??null,setItem:(k,v)=>{if(fail.on&&(!fail.prefix||k.startsWith(fail.prefix)))throw new Error('QuotaExceededError');ls[k]=v}};
 return new Proxy(api,{ownKeys:()=>Object.keys(ls),getOwnPropertyDescriptor:(_,k)=>k in ls?{enumerable:true,configurable:true,value:ls[k]}:undefined});}

const LOCAL={pieces:[{id:'p1',title:'local'}]}, REMOTE={pieces:[{id:'p2',title:'remote'}]};
const run=async(opts,k={})=>{const s=setup({local:LOCAL,remote:REMOTE,...k});Object.assign(s.c.localStorage,{});await s.c.run({state:REMOTE,restoring:false,rev:42});await Promise.resolve();return s;};
test('CONTROL: storage healthy -> scoped copy durable, acceptRemote called once, no note',async()=>{
 const s=await run();
 assert.deepEqual(s.fx.accepted?.rev,42); assert.equal(s.fx.notes.length,0);
 assert.equal(JSON.parse(s.ls['middots-state']).scope,'scope-a');
});
test('OBS-Q1: STATE_KEY write denied (quota), no custody pending -> acceptRemote STILL called, merged state applied, no note',async()=>{
 const fail={on:true,prefix:'middots-state'};
 const s=await run({},{fail});
 assert.equal('middots-state' in s.ls,false,'nothing persisted');
 assert.equal(s.fx.accepted?.rev,42,'acceptRemote reached');
 assert.ok(s.fx.applied,'merged state applied in memory');
 assert.deepEqual(s.fx.notes,[],'no user note from applyRemote');
});
test('OBS-Q2: writeScopedWithCustody directly: STATE_KEY denied throws (caller catch => persisted=false)',async()=>{
 const fail={on:false}; const s=setup({local:LOCAL,remote:REMOTE,fail}); fail.on=true;
 assert.throws(()=>s.c.write('scope-a',LOCAL),/Quota/);
});
test('OBS-Q3: readback mismatch (stored value differs) -> durable:false returned',async()=>{
 const ls={}; const s=setup({local:LOCAL,remote:REMOTE,ls});
 const orig=s.c.localStorage.getItem; s.c.localStorage.getItem=k=>k==='middots-state'?'{"v":1,"scope":"scope-a","state":{"stale":true}}':orig(k);
 const w=s.c.write('scope-a',LOCAL); assert.equal(w.durable,false); assert.equal(w.held,undefined);
});
test('OBS-Q4: readback mismatch inside applyRemote -> acceptRemote still called (same gate as Q1)',async()=>{
 const ls={}; const s=setup({local:LOCAL,remote:REMOTE,ls});
 const orig=s.c.localStorage.getItem; s.c.localStorage.getItem=k=>k==='middots-state'?'x':orig(k);
 await s.c.run({state:REMOTE,restoring:false,rev:42});await Promise.resolve();
 assert.equal(s.fx.accepted?.rev,42); assert.deepEqual(s.fx.notes,[]);
});
test('NEG-CONTROL: custody pending and unwritable (dirty) -> early return, acceptRemote NOT called, note shown',async()=>{
 const BADV={version:1,profiles:{desktop:{textPt:'corrupt'}},unknown:{m:1}};
 const fail={on:true,prefix:'middots-admin-held'};
 const s=setup({local:{pieces:[],adminProfiles:BADV},remote:{pieces:[]},fail});
 await s.c.run({state:{pieces:[]},restoring:false,rev:42});await Promise.resolve();
 assert.equal(s.fx.accepted,null); assert.ok(s.fx.notes.length>=1);
});
test('SCOPE: residue under another profile scope is not applied (readScopedState, real module)',()=>{
 const raw=packState('scope-b',{pieces:[{id:'x'}]});
 assert.deepEqual(readScopedState(raw,'scope-a'),{apply:false,reason:'scope-mismatch'});
 assert.equal(readScopedState(raw,'scope-b').apply,true);
 assert.equal(readScopedState(JSON.stringify({pieces:[]}),'scope-a').reason,'legacy-under-account');
});
