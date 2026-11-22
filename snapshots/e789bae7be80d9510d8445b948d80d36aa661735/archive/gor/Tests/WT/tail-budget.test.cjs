const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const source=fs.readFileSync(process.argv[2],'utf8');
function fn(name){const a=source.indexOf('function '+name+'(');assert(a>=0,name);let n=0,b=source.indexOf('{',a);for(let i=b;i<source.length;i++){if(source[i]==='{')n++;if(source[i]==='}'&&!--n)return source.slice(a,i+1);}throw Error(name);}
const context={totalFileFirst:0,totalFileLast:406,MOOV_TAIL_PIECES:80,_retryPins:new Set(),_seekWatch:null,activePumps:new Map(),_boostOwned:()=>null,readerRetentionPiece:x=>x};
context.activePumps.set(99,{isProbe:false,startPiece:390,cursorPiece:390,abortController:{signal:{aborted:false}},response:{destroyed:false}});
vm.createContext(context);vm.runInContext(fn('_retireLimit')+'\n'+fn('_admissionBelowFloor'),context);
const ring={_isPinned:i=>[0,1,404,405,406].includes(i),waitedPieces:[]};
assert.equal(context._retireLimit(392,ring),392,'rolling retirement must pass old326ceiling');
assert.equal(context._admissionBelowFloor(340,380,ring),true,'consumed tail piece must not be re-admitted');
assert.equal(context._admissionBelowFloor(405,406,ring),false,'actual tail pin kept');
context.activePumps.set(1,{isProbe:true,startPiece:350,cursorPiece:350,abortController:{signal:{aborted:false}},response:{destroyed:false}});
assert.equal(context._retireLimit(392,ring),350,'real tail probe still protects cursor');
assert.equal(context._admissionBelowFloor(350,380,ring),false,'real probe still may request');
context.activePumps.delete(1);context.activePumps.get(99).cursorPiece=406;
// Sequential playback budget: each of407pieces fetched once. Model eviction after
// bounded28piece RAM wrap, and probe stale selection eligibility with ACTUAL predicate.
let payload=407*8388608,extra=0;
for(let play=340;play<=406;play++)for(let piece=326;piece<play-28;piece++) {
 if(!context._admissionBelowFloor(piece,play-8,ring)&&!ring._isPinned(piece))extra+=8388608;
}
assert.equal(extra,0,'tail RAM-wrap must add zero consumed-piece refetch');
assert.equal(payload+extra,payload,'byte budget one pass +0repeat bytes');
console.log('PASS actual retirement/admission predicates; live tail owner preserved; sequential RAM-wrap byte budget +0refetch');
