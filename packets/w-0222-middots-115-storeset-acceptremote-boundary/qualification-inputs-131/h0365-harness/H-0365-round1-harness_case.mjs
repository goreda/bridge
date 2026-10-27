// One case per process (fresh sync.js module state, fresh storage). Usage: node case.mjs <case>
import assert from 'node:assert/strict';
const name = process.argv[2];
const ls = { m: new Map(), mode: {},
  getItem(k){ if (ls.mode.getThrow) throw new Error('get'); return ls.m.has(k)?ls.m.get(k):null; },
  setItem(k,v){ const d=ls.mode.deny; if (d && d.includes(k)) throw Object.assign(new Error('quota'),{name:'QuotaExceededError'}); if (ls.mode.drop && ls.mode.drop.includes(k)) return; ls.m.set(k,String(v)); },
  removeItem(k){ ls.m.delete(k); } };
const events = [];
globalThis.localStorage = ls;
globalThis.window = { localStorage: ls, setTimeout, clearTimeout, dispatchEvent: e => { events.push(e.type); return true; }, addEventListener(){}, removeEventListener(){} };
globalThis.CustomEvent = class { constructor(t){ this.type=t; } };
let remote;
globalThis.fetch = async (url, init={}) => {
  const p = String(url).replace('http://stub',''); const J=(o,s=200)=>({ok:s<300,status:s,json:async()=>o});
  if (p==='/auth/config') return J({}); if (p==='/join') return J({token:'tok1',created:false});
  if (p==='/state' && (!init.method||init.method==='GET')) return J(remote); return J({},500); };
const S = await import('./sync.js');
const REV='middots-sync-rev', BASE='middots-sync-base';
const A = {pieces:[{id:'a'}]}, B = {pieces:[{id:'a'},{id:'b'}]};
remote = {rev:5, state:A};
await S.join('code'); let r = await S.pull(); assert.ok(r, 'restoring read');
assert.equal(S.acceptRemote(r.rev, r.state, r), true); S.acceptArchive('tok1');
const baseA = ls.m.get(BASE); assert.equal(ls.m.get(REV), '5');
remote = {rev:7, state:B}; const x = await S.pull(); assert.ok(x && x.rev===7, 'rev-7 read');
const baseB = JSON.stringify({scope: ls.m.get('middots-sync-base-scope'), state: B});
events.length = 0; let ret; const out = {case:name};
const C = {
  control_ok(){ ret = S.acceptRemote(7, x.state, x); assert.equal(ret,true); assert.equal(ls.m.get(REV),'7'); assert.equal(ls.m.get(BASE), baseB); assert.deepEqual(events,[]); },
  T2_rev_denied(){ ls.mode={deny:[REV]}; ret = S.acceptRemote(7, x.state, x); assert.equal(ret,true); assert.equal(ls.m.get(REV),'5'); assert.equal(ls.m.get(BASE), baseB); assert.deepEqual(events,['middots-recovery']); },
  T3_base_denied(){ ls.mode={deny:[BASE]}; ret = S.acceptRemote(7, x.state, x); assert.equal(ret,true); assert.equal(ls.m.get(REV),'7'); assert.equal(ls.m.has(BASE), false); assert.deepEqual(events,[]); },
  T4_silent_drop_synthetic(){ ls.mode={drop:[REV,BASE]}; ret = S.acceptRemote(7, x.state, x); assert.equal(ret,true); assert.equal(ls.m.get(REV),'5'); assert.equal(ls.m.get(BASE), baseA); assert.deepEqual(events,[]); },
  T5_get_throws_negative_control(){ ls.mode={getThrow:true}; ret = S.acceptRemote(7, x.state, x); ls.mode={}; assert.equal(ret,false); assert.equal(ls.m.get(REV),'5'); assert.equal(ls.m.get(BASE), baseA); },
  T6_replay(){ assert.equal(S.acceptRemote(7,x.state,x),true); assert.equal(S.acceptRemote(7,x.state,x),true); assert.equal(ls.m.get(REV),'7'); assert.equal(ls.m.get(BASE), baseB); },
};
assert.ok(C[name], 'unknown case'); C[name]();
console.log(`PASS ${name} ret=${ret} rev=${ls.m.get(REV)} base=${ls.m.has(BASE)?(ls.m.get(BASE)===baseB?'rev7-state':ls.m.get(BASE)===baseA?'rev5-state':'other'):'absent'} events=${JSON.stringify(events)}`);
