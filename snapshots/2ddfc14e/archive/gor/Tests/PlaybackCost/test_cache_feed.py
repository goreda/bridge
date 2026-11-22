"""Actual vendor scheduler, simulated swarm, fixed-clock HTTP consumer.

No public torrent or native Mac proof. Baseline is the exact old shuffle loop.
"""
from pathlib import Path
import json,subprocess,tempfile
root=Path(__file__).resolve().parents[2]
s=(root/'Resources/vendor/webtorrent-cli/node_modules/webtorrent/lib/torrent.js').read_text()
a=s.index('  _updateWire (wire) {');b=s.index('\n  /**',a);method=s[a:b]
new='for (let j = i; j < self._selections.length && self._selections.get(j).priority === priority; j++)'
old='for (let j = i; j < self._selections.length && self._selections.get(j).priority; j++)'
assert method.count(new)==1
baseline=method.replace(new,old)
code=r'''
const assert=require('node:assert/strict');
const SPEED_THRESHOLD=1,PIPELINE_MIN_DURATION=0.5,PIPELINE_MAX_DURATION=1;
// 8 peers x 11 blocks x 16 KiB every 250 ms = 5.77 MB/s payload.
const getBlockPipelineLength=()=>11;
function run(method, strategy='sequential',equal=false) {
 const T=eval('(class T {'+method+'})'),t=new T();
 const pieces=2048,blocks=256,remaining=Array(pieces).fill(blocks),reserved=Array(pieces).fill(0);
 const completed=new Set();let received=0;
 const items=equal?[{from:100,to:100,offset:0,priority:2},{from:200,to:200,offset:0,priority:2},{from:300,to:300,offset:0,priority:1}]:
  [{from:100,to:100,offset:0,priority:2},...Array.from({length:8},(_,i)=>({from:101+i*40,to:140+i*40,offset:0,priority:1}))];
 t._selections={get:i=>items[i],swap:(i,j)=>{[items[i],items[j]]=[items[j],items[i]]},get length(){return items.length}};
 t.strategy=strategy;t._critical={};t.destroyed=false;
 t.bitfield={get:i=>completed.has(i)};t.pieces=remaining.map(missing=>({missing}));
 t.wires=Array.from({length:8},()=>({requests:[],downloaded:1,peerChoking:false,destroyed:false,peerPieces:{get:()=>true},downloadSpeed:()=>10000000}));
 t._request=(wire,piece)=>{
  if(completed.has(piece)||remaining[piece]-reserved[piece]<=0)return false;
  reserved[piece]++;wire.requests.push({piece});return true;
 };
 // Rarest branch still obeys priority; fixture's rarity order is ascending.
 t._rarityMap={getRarestPiece:filter=>{for(let i=0;i<pieces;i++)if(!completed.has(i)&&remaining[i]-reserved[i]>0&&filter(i))return i;return -1}};
 const first={};let underruns=0;
 for(let tick=1;tick<=40;tick++) {
  for(const wire of t.wires)t._updateWire(wire);
  for(const wire of t.wires) {
   for(const r of wire.requests){remaining[r.piece]--;reserved[r.piece]--;received+=16384;
    if(remaining[r.piece]===0){completed.add(r.piece);first[r.piece]=tick*250;}}
   wire.requests=[];
  }
  // 1 s startup allowance then playback needs this already-requested 4 MiB.
  if(tick>=4 && !completed.has(100))underruns++;
 }
 return {firstWriteMs:first[100]??Infinity,second:first[200]??Infinity,underruns,received,order:items.map(i=>i.priority)};
}
const old=run(__OLD__),fixed=run(__NEW__);
assert(old.firstWriteMs>=1500,JSON.stringify(old));
assert(fixed.firstWriteMs<=1000,JSON.stringify(fixed));
assert(fixed.underruns===0 && old.underruns>0);
assert(fixed.firstWriteMs<=old.firstWriteMs/2);
const equal=run(__NEW__,'sequential',true);
assert(equal.firstWriteMs<2000 && equal.second<2000,'same-priority fairness retained');
const rare=run(__NEW__,'rarest');assert(rare.firstWriteMs<=1000,'rarest must not bypass priority');
console.log(JSON.stringify({kind:'actual-vendor-scheduler-simulated-swarm',payloadMBps:8*11*16384/.25/1e6,baseline:old,fixed,equal,rare},null,2));
'''.replace('__OLD__',json.dumps(baseline)).replace('__NEW__',json.dumps(method))
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'test.cjs';p.write_text(code);subprocess.run(['node',str(p)],check=True)
# Actual vendor selection merge + production bounded-priority helper.
wt=(root/'Resources/vendor/wt_server/wt_server.mjs').read_text()
start=wt.index('function _selectBaseRange(');end=wt.index('function _boostWaiterPiece(',start)
helper=wt[start:end]
selection=(root/'Resources/vendor/webtorrent-cli/node_modules/webtorrent/lib/selections.js').read_text().replace('export ','')
js="const assert=require('node:assert/strict');\n"+selection+"\n"+r'''const q=new Selections();
q.insert({from:100,to:140,offset:0,priority:0});
q.insert({from:110,to:111,offset:0,priority:2});
assert.equal(q.get(0).from,100);assert.equal(q.get(0).to,140);assert.equal(q.get(0).priority,2);
// Above proves the old nested select promotes the full window, not two pieces.
const torrent={_selections:new Selections(),_updateSelections(){},select(from,to,priority){this._selections.insert({from,to,offset:0,priority});}};
torrent._selections.insert({from:100,to:140,offset:3,priority:0});
const base=torrent._selections.get(0);
__HELPER__
_setStreamingPriority('lookahead',110,115,1);
_setStreamingPriority('waiter',112,113,2);
assert.equal(torrent._selections.length,3);
assert.deepEqual(torrent._selections._items.map(i=>[i.from,i.to,i.priority]),[[112,113,2],[110,115,1],[100,140,0]]);
_setStreamingPriority('lookahead',111,116,1);
assert(torrent._selections._items.includes(base));assert.equal(base.offset,3);
assert(torrent._selections._items.some(i=>i.gorPriorityOwner==='waiter'&&i.from===112));
_selectBaseRange(120,150,0);
assert(torrent._selections._items.some(i=>i.gorPriorityOwner==='waiter'&&i.from===112&&i.to===113));
assert(torrent._selections._items.filter(i=>!i.gorPriorityOwner).every(i=>i.priority===0));
_setStreamingPriority('waiter',1,0,2);
assert.equal(torrent._selections.length,2);
console.log('PASS actual vendor concatenate reproduces full-window boost; production managed selections keep exact two-piece waiter, lookahead, base offset and priority independent');
'''.replace('__HELPER__',helper)
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'selection.cjs';p.write_text(js);subprocess.run(['node',str(p)],check=True)
print('NOT_RUN native Mac long-playback outcome; simulated scheduler improvement is not owner smoothness proof')
