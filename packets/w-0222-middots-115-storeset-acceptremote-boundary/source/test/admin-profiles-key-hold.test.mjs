// Key-level hold: a corrupt admin value never freezes pieces, save or revision. Runs the production applyRemote and saveState bodies.
import {helperSrc,custodyCtx} from './_helpers.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {mergeStates} from '../state-merge.js';
import {cleanAdminProfileState} from '../admin-profile-state.js';
const app=readFileSync(new URL('../app.js',import.meta.url),'utf8');
const s0=app.indexOf('    const applyRemote = async (r');
const body=app.slice(s0,app.indexOf('    // once, on load:',s0));
const good={version:1,profiles:{desktop:{textFace:'fragment-mono',indexFace:'fragment-mono',textPt:12,indexPt:10,textAxes:{},indexAxes:{},lh:1.5,hz:0,textWidthEm:29}}};
const bad={version:1,profiles:{desktop:{textPt:'corrupt'}}};
const piece=(id,t)=>({id,versions:[{id:'v1',text:t}]});
async function run(reason){
 const local={pieces:[piece('p1','local text')],...(reason==='local'?{adminProfiles:bad}:{adminProfiles:good})};
 const remote={pieces:[piece('p1','local text'),piece('p2','from other device')],...(reason==='remote'?{adminProfiles:bad}:{adminProfiles:good})};
 const out={store:0,apply:0,accept:0,push:0,note:0,saved:null};
 const held={current:false},rem={current:undefined};
 const context={...custodyCtx(),adminEditEpoch:{current:0},adminProfilesBinding:{current:'t'},adminProfilesRemote:rem,cleanAdminProfileState,currentRead:()=>true,token:()=>'t',cachedScope:()=>'s',scopeForToken:async()=>'s',isJoined:()=>true,
  saveStateRef:{current:()=>local},storeGet:()=>JSON.stringify(local),STATE_KEY:'k',readScopedState:raw=>({apply:true,stateText:raw}),getBase:()=>reason==='base'?{pieces:[],adminProfiles:bad}:{pieces:local.pieces,adminProfiles:good},syncLoading:{current:false},mergeStates,adminProfilesHeld:held,
  showNote:()=>out.note++,storeSet:()=>out.store++,applySaved:t=>{out.apply++;out.saved=JSON.parse(t)},acceptRemote:()=>out.accept++,pushMerged:async()=>{out.push++;return {}},overlayRecovery:async s=>s,scrollerRef:{current:null},localEditEpoch:{current:0},saveRecovery:()=>true,piecesOf:()=>[],handleMergeReceipt:()=>{},currentWrite:()=>true,retryMerged:()=>{},requestAnimationFrame:()=>{}};
 vm.createContext(context);vm.runInContext(helperSrc+'\n'+body+'\nglobalThis.run=applyRemote;',context);
 await context.run({state:remote,restoring:false,rev:2});
 return {out,held,rem};
}
for(const reason of ['local','remote','base'])test(`corrupt ${reason} admin value: pieces from other device still merged, revision accepted`,async()=>{
 const {out,held}=await run(reason);
 assert.equal(out.accept,1);assert.equal(out.apply,1);assert.equal(out.push,1);
 assert.deepEqual(out.saved.pieces.map(p=>p.id).sort(),['p1','p2']);
 assert.equal(held.current,reason==='remote');
 if(reason==='remote')assert.deepEqual(out.saved.adminProfiles,bad); // service raw value kept byte-for-byte, not trimmed
 else assert.deepEqual(out.saved.adminProfiles,good); // valid value wins, corrupt side not written to the wire
});
test('save body does not return early when held',()=>{
 const start=app.indexOf('    saveStateRef.current = () => {');
 assert.ok(!/adminProfilesHeld\.current\) return null/.test(app.slice(start,start+400)));
});
