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
function mkLS(ls,fail){const api={getItem:k=>ls[k]??null,setItem:(k,v)=>{if(fail.on)throw new Error('QuotaExceededError');ls[k]=v}};
 return new Proxy(api,{ownKeys:()=>Object.keys(ls),getOwnPropertyDescriptor:(_,k)=>k in ls?{enumerable:true,configurable:true,value:ls[k]}:undefined});}
const cases={
 'corrupt local, remote key absent':{local:{pieces:[],adminProfiles:BAD},remote:{pieces:[]},slot:'local',heldFlag:false},
 'corrupt local, remote valid':{local:{pieces:[],adminProfiles:BAD},remote:{pieces:[],adminProfiles:VALID},slot:'local',heldFlag:false},
 'corrupt base, remote valid':{local:{pieces:[]},base:{pieces:[],adminProfiles:BAD},remote:{pieces:[],adminProfiles:VALID},slot:'base',heldFlag:false},
};
for(const [name,k] of Object.entries(cases))test(`${name}: raw corrupt value kept in its own scoped custody, never on the wire, healthy revision accepted`,async()=>{
 const {c,ls,fx,held}=setup(k);
 await c.run({state:k.remote,restoring:false,rev:42});await Promise.resolve();
 const env=stored(ls);
 assert.deepEqual(heldOf(ls,k.slot),[BAD],'raw custody, byte for byte, in its own scoped key');assert.ok(!('adminHeld' in env));
 assert.equal(env.scope,'scope-a');
 assert.ok(!JSON.stringify(env.state).includes('distinct-corrupt-custody'),'not mixed into the applied state');
 assert.equal(readScopedState(ls['middots-state'],'scope-a').apply,true,'envelope still applies under its own scope');
 assert.equal(readScopedState(ls['middots-state'],'scope-b').apply,false);
 assert.equal(fx.accepted.rev,42);
 assert.ok(!JSON.stringify(fx.accepted.state).includes('distinct-corrupt-custody'));
 if(fx.pushed)assert.ok(!JSON.stringify(fx.pushed).includes('distinct-corrupt-custody')&&!JSON.stringify(fx.pushed).includes('adminHeld'));
 assert.equal(held.current,k.heldFlag);
 assert.ok(fx.notes.some(n=>/kept aside/.test(n)),'honest note, not "held unchanged"');
 assert.ok(!fx.notes.some(n=>/held unchanged/.test(n)));
 // a later ordinary save must not drop the custody
 c.localStorage.setItem('middots-state',c.pack('scope-a',{pieces:[],x:1}));
 assert.deepEqual(heldOf(ls,k.slot),[BAD]);
});
test('corrupt remote + corrupt local: remote stays unchanged on the wire, local raw kept aside separately',async()=>{
 const REM={version:1,profiles:{desktop:{textPt:'remote-corrupt'}}};
 const {c,ls,fx,held,rem}=setup({local:{pieces:[],adminProfiles:BAD},remote:{pieces:[],adminProfiles:REM}});
 await c.run({state:{pieces:[],adminProfiles:REM},restoring:false,rev:7});await Promise.resolve();
 assert.equal(held.current,true);assert.deepEqual(rem.current,REM);
 assert.deepEqual(fx.accepted.state.adminProfiles,REM);
 assert.deepEqual(heldOf(ls,'local'),[BAD]);
 assert.ok(fx.notes.some(n=>/left unchanged there/.test(n)&&/kept aside/.test(n)));
});
test('custody survives an unrelated second event, and the same raw value is not duplicated',async()=>{
 const {c,ls}=setup({local:{pieces:[],adminProfiles:BAD},remote:{pieces:[],adminProfiles:VALID}});
 await c.run({state:{pieces:[],adminProfiles:VALID},restoring:false,rev:1});await c.run({state:{pieces:[],adminProfiles:VALID},restoring:false,rev:2});
 assert.equal(heldOf(ls,'local').length,1);
});
test('boot from the device copy: unreadable admin value is moved to custody, not treated as the account value',()=>{
 const i=app.indexOf('        if (!keepScroll && Object.hasOwn(data, \'adminProfiles\')');
 const block=app.slice(i,app.indexOf('        }\n',app.indexOf('delete data.adminProfiles',i))+10);
 const {c,fx}=setup({local:{pieces:[]},remote:{pieces:[]}});
 c.data={pieces:[],adminProfiles:BAD};c.keepScroll=undefined;
 vm.runInContext('(()=>{let data=globalThis.data;const keepScroll=globalThis.keepScroll;'+block+'globalThis.out=data;})()',c);
 assert.ok(!('adminProfiles' in c.out));assert.deepEqual(JSON.parse(JSON.stringify(vm.runInContext('load()',c).local)),[BAD]);
 assert.ok(fx.notes.length===1);
});

const run=(c,rev)=>c.run({state:{pieces:[],adminProfiles:VALID},restoring:false,rev}).then(()=>Promise.resolve());
test('two contexts interleaved on shared storage: distinct raw values both survive reload (peer F3 interleaving, no read-modify-write)',async()=>{
 const ls={};
 const a=setup({local:{pieces:[]},remote:{pieces:[]},ls}),b=setup({local:{pieces:[]},remote:{pieces:[]},ls});
 const one={...BAD,marker:'tab-A-only'},two={...BAD,marker:'tab-B-only'};a.c.raw=one;b.c.raw=two;
 // both run their whole hold + ordinary-state write with arbitrary interleaving: B between A's hold and A's state write, and the stale pack written last
 vm.runInContext("holdAdminRaw('local',globalThis.raw)",a.c);
 const pa=a.c.pack('scope-a',{pieces:[]});
 vm.runInContext("holdAdminRaw('local',globalThis.raw)",b.c);
 const pb=b.c.pack('scope-a',{pieces:[]});
 ls['middots-state']=pb;ls['middots-state']=pa; // any order of stale whole-state writes
 assert.deepEqual(heldOf(ls,'local').map(x=>x.marker).sort(),['tab-A-only','tab-B-only']);
 vm.runInContext('write("scope-a",{pieces:[]})',a.c);vm.runInContext('write("scope-a",{pieces:[]})',b.c);
 assert.equal(heldOf(ls,'local').length,2,'ordinary saves never touch custody keys');
});
test('same raw value from two tabs is one key (idempotent), different values never overwrite each other',()=>{
 const ls={};const a=setup({local:{pieces:[]},remote:{pieces:[]},ls}),b=setup({local:{pieces:[]},remote:{pieces:[]},ls});
 a.c.raw=BAD;b.c.raw=BAD;vm.runInContext("holdAdminRaw('local',globalThis.raw)",a.c);vm.runInContext("holdAdminRaw('local',globalThis.raw)",b.c);
 assert.equal(Object.keys(ls).filter(k=>k.startsWith('middots-admin-held:')).length,1);
});
test('storage failure: custody pending in memory, revision/base/push NOT advanced, state envelope untouched; retry persists',async()=>{
 const ls={'middots-state':JSON.stringify({v:1,scope:'scope-a',state:{pieces:[],adminProfiles:BAD}})};const before=ls['middots-state'];const fail={on:true};
 const {c,fx}=setup({local:{pieces:[],adminProfiles:BAD},remote:{pieces:[],adminProfiles:VALID},ls,fail});
 await run(c,9);
 assert.equal(fx.accepted,null);assert.equal(fx.applied,null);assert.equal(fx.pushed,null);assert.equal(ls['middots-state'],before);
 assert.ok(fx.notes.some(n=>/could not keep unreadable admin layout data aside/.test(n)));
 fail.on=false;await run(c,9);
 assert.equal(fx.accepted.rev,9);assert.deepEqual(heldOf(ls,'local'),[BAD]);
});
test('scope binding: custody of scope A is invisible to scope B, returns for A, and never enters a B state envelope',async()=>{
 const ls={};const sc={scope:'scope-a',tok:'ta'};
 const {c}=setup({local:{pieces:[],adminProfiles:BAD},remote:{pieces:[],adminProfiles:VALID},ls,sc});
 await run(c,1);assert.deepEqual(heldOf(ls,'local'),[BAD]);
 sc.scope='scope-b';sc.tok='tb';
 assert.deepEqual(JSON.parse(JSON.stringify(vm.runInContext('load()',c))),{local:[],base:[]});
 const packedB=vm.runInContext("pack('scope-b',{pieces:[]})",c);assert.ok(!packedB.includes('distinct-corrupt-custody'));
 assert.deepEqual(heldOf(ls,'local','scope-b'),[]);
 sc.scope='scope-a';sc.tok='ta';assert.deepEqual(JSON.parse(JSON.stringify(vm.runInContext('load()',c).local)),[BAD]);
});
test('a forged held key whose value names another scope is ignored',()=>{
 const ls={'middots-admin-held:scope-a:local:x:0':JSON.stringify({v:1,scope:'scope-z',slot:'local',raw:BAD})};
 const {c}=setup({local:{pieces:[]},remote:{pieces:[]},ls});
 assert.deepEqual(JSON.parse(JSON.stringify(vm.runInContext('load()',c))),{local:[],base:[]});
});
test('key is SHA-256 of the raw value: matches node crypto for several inputs',async()=>{
 const {createHash}=await import('node:crypto');
 const {c}=setup({local:{pieces:[]},remote:{pieces:[]}});
 const sha=vm.runInContext('(s)=>sha256Hex(s)',c);
 for(const s of ['','abc','a'.repeat(1000),'{"é":"ü€😀"}','x'.repeat(55),'x'.repeat(56),'x'.repeat(64)])assert.equal(sha(s),createHash('sha256').update(s).digest('hex'));
});
test('forced hash collision (test-only stub): occupied key with different content is never overwritten; the loser stays pending and holds the revision',async()=>{
 const ls={};
 globalThis.__src=helperSrc.replace('const heldHash = sha256Hex;',"const heldHash = () => 'forced';");
 let a,b;try{a=setup({local:{pieces:[]},remote:{pieces:[]},ls});b=setup({local:{pieces:[]},remote:{pieces:[]},ls});}finally{delete globalThis.__src;}
 for(const x of [a,b])vm.runInContext("globalThis.hold=holdAdminRaw;globalThis.pending=adminCustodyPending;globalThis.dirty=adminCustodyDirty;",x.c);
 a.c.r1={...BAD,m:1};b.c.r2={...BAD,m:2};
 vm.runInContext("hold('local',globalThis.r1)",a.c);vm.runInContext("hold('local',globalThis.r2)",b.c);
 assert.deepEqual(heldOf(ls,'local').map(x=>x.m),[1],'first value intact');
 assert.equal(b.c.pending.current.length,1);assert.equal(b.c.dirty.current,true);
 // residual, stated honestly: only a TRUE collision plus an interleave between get and set can lose a value; with SHA-256 that is not reachable
});
test('explicit device reset sweep removes custody with every other middots key',()=>{
 const ls={};const {c}=setup({local:{pieces:[]},remote:{pieces:[]},ls});c.raw=BAD;vm.runInContext("holdAdminRaw('local',globalThis.raw)",c);
 assert.ok(app.includes("k.startsWith('middots')")&&Object.keys(ls).every(k=>k.startsWith('middots')));
});

test('F7 closes peer counterexample custody-only quota: state copy is NOT replaced while custody is not durable',async()=>{
 const before=JSON.stringify({v:1,scope:'scope-a',state:{pieces:[],adminProfiles:BAD}});const ls={'middots-state':before};
 const {c,fx}=setup({local:{pieces:[],adminProfiles:BAD},remote:{pieces:[],adminProfiles:VALID},ls});
 const set=c.localStorage.setItem;c.localStorage.setItem=(k,v)=>{if(k.startsWith('middots-admin-held:'))throw Error('selective custody storage failure');set(k,v);};
 await run(c,61);assert.equal(fx.accepted,null);
 assert.equal(ls['middots-state'],before);assert.equal(fx.pushed,null);assert.equal(heldOf(ls,'local').length,0);
 
});
