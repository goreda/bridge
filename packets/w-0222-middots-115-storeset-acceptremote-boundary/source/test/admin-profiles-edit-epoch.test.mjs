import test from 'node:test';
import {helperSrc,custodyCtx} from './_helpers.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {mergeStates} from '../state-merge.js';
const app=readFileSync(new URL('../app.js',import.meta.url),'utf8');
const body=app.slice(app.indexOf('    const applyRemote = async (r'),app.indexOf('    // once, on load:',app.indexOf('    const applyRemote = async (r')));
function fixture(){
 const state={pieces:[],adminProfiles:{version:1,profiles:{desktop:{textPt:12}}}};
 const epoch={current:0},raw={current:state.adminProfiles},hits=[];let current=true,overlays=0,last=null;const gates=[];
 const context={...custodyCtx(),STATE_KEY:'fixture-state',adminEditEpoch:epoch,adminProfilesRemote:raw,adminProfilesBinding:{current:'owner'},adminProfilesHeld:{current:false},currentRead:()=>current,saveStateRef:{current:()=>state},cachedScope:()=> 'scope',token:()=> 'owner',isJoined:()=>true,getBase:()=>state,syncLoading:{current:false},mergeStates,
 overlayRecovery:()=>{overlays++;return new Promise(resolve=>gates.push(resolve));},localStorage:{getItem:()=>last,setItem:(k,v)=>{last=v;hits.push(['store',JSON.parse(v).state])}},applySaved:()=>hits.push(['apply']),scrollerRef:{current:null},acceptRemote:()=>hits.push(['accept']),pushMerged:async()=>{hits.push(['push']);return {};},localEditEpoch:{current:0},handleMergeReceipt:()=>{},retryMerged:()=>{},showNote:()=>hits.push(['note'])};
 vm.createContext(context);vm.runInContext(helperSrc+'\n'+body+'\nglobalThis.run=applyRemote;',context);
 return {context,state,epoch,raw,hits,gates,get overlays(){return overlays;},invalidate:()=>current=false};
}
test('one fresh merge preserves admin edit during awaited overlay and still accepts healthy revision',async()=>{
 const f=fixture();const pending=f.context.run({state:f.state,rev:2,restoring:false});
 f.epoch.current++;f.raw.current={version:1,profiles:{desktop:{textPt:27}}};f.gates.shift()(f.state);await Promise.resolve();await Promise.resolve();
 assert.equal(f.overlays,2);const merged=mergeStates(f.state,{...f.state,adminProfiles:f.raw.current},f.state).state;f.gates.shift()(merged);await pending;
 assert.equal(f.hits.find(h=>h[0]==='store')[1].adminProfiles.profiles.desktop.textPt,27);assert.equal(f.hits.filter(h=>h[0]==='accept').length,1);
});
test('second edit during bounded retry never spins or overwrites latest edit',async()=>{
 const f=fixture();const pending=f.context.run({state:f.state,rev:2,restoring:false});f.epoch.current++;f.gates.shift()(f.state);await Promise.resolve();await Promise.resolve();f.epoch.current++;f.gates.shift()(f.state);await pending;
 assert.equal(f.overlays,2);assert.deepEqual(f.hits.map(h=>h[0]),['note']);
});
test('old session after awaited overlay neither retries nor writes',async()=>{
 const f=fixture();const pending=f.context.run({state:f.state,rev:2,restoring:false});f.epoch.current++;f.invalidate();f.gates.shift()(f.state);await pending;assert.equal(f.overlays,1);assert.deepEqual(f.hits,[]);
});

test('non-restoring null-local retry preserves remote pieces and accepts revision without inventing admin-only local',async()=>{
 const f=fixture();const piece={id:'retained-piece',versions:[{vid:'v1',title:'keep',lines:['keep']}],current:0};
 const remote={...f.state,pieces:[piece]};const base={...f.state,pieces:[piece]};
 f.context.saveStateRef.current=()=>null;f.context.scopeForToken=async()=> 'scope';f.context.storeGet=()=>null;f.context.readScopedState=()=>({apply:false});f.context.getBase=()=>base;
 const actualMerge=f.context.mergeStates;const locals=[];let secondMerged;
 f.context.mergeStates=(b,l,r)=>{locals.push(l);const merged=actualMerge(b,l,r);secondMerged=merged.state;return merged;};
 const pending=f.context.run({state:remote,rev:3,restoring:false});await new Promise(resolve=>setImmediate(resolve));
 f.epoch.current++;f.raw.current={version:1,profiles:{desktop:{textPt:29}}};f.gates.shift()(remote);await new Promise(resolve=>setImmediate(resolve));
 assert.equal(f.overlays,2);assert.equal(locals.length,2);assert.equal(locals[1],null,'no admin-only local document fabricated');assert.equal(secondMerged.pieces[0].id,'retained-piece');
 f.gates.shift()(secondMerged);await pending;assert.equal(f.hits.filter(h=>h[0]==='accept').length,1);assert.equal(f.hits.find(h=>h[0]==='store')[1].pieces[0].id,'retained-piece');
});
