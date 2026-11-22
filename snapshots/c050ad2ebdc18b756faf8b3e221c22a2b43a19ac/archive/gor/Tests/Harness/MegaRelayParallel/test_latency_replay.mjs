// Offline replay of request-service times through shipping cache and stream.
import fs from 'node:fs';import vm from 'node:vm';import {Readable} from 'node:stream';import {performance} from 'node:perf_hooks';import {EventEmitter} from 'node:events';
const source=fs.readFileSync(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url),'utf8');
const cache=source.slice(source.indexOf('function cachedPlainSource('),source.indexOf('async function resolvePlainSource'));
const begin=source.indexOf('function parallelStream('),stream=source.slice(begin,source.indexOf('// Resolve the link',begin));
const delays=JSON.parse(fs.readFileSync(new URL('latency-1739.json',import.meta.url),'utf8')).elapsed_ms;const scale=0.02;
import assert from 'node:assert/strict';
async function run(window){let active=0,max=0,busy=0,waiting=[],requests=0;const FIRST=512,CHUNK=2048,SIZE=FIRST+delays.length*CHUNK;
 const context=vm.createContext({Map,Set,Readable,Buffer,performance,EventEmitter,PLAIN_CONNECTIONS:6,PLAIN_FIRST_CHUNK:FIRST,PLAIN_CHUNK:CHUNK,foregroundWindow:(conns,background)=>background?conns:conns*2});
 vm.runInContext(cache+stream.replace('inflight.size < lookahead()','inflight.size < conns*'+window)+';globalThis.api={cachedPlainSource,parallelStream}',context);
 const network={reprioritize(){},scheduling(){return{};},fetch(s,e,track,cancelled){return new Promise((resolve,reject)=>{const delay=delays[requests++%delays.length]*scale;
 const start=()=>{active++;max=Math.max(max,active);const began=performance.now(),req=new EventEmitter();req.destroy=()=>{};track(req);
 setTimeout(()=>{busy+=performance.now()-began;active--;req.emit('close');while(active<6&&waiting.length)waiting.shift()();if(cancelled())reject(Error('cancelled'));else resolve({buf:Buffer.alloc(e-s+1,(s/512)%251)});},delay);};if(active<6)start();else waiting.push(start);});}};
 const cached=context.api.cachedPlainSource(network,SIZE);const began=performance.now();let bytes=0;
 for await(const b of context.api.parallelStream(cached,7,SIZE-1,6))bytes+=b.length;
 assert.equal(bytes,SIZE-7);assert.equal(requests,delays.length+1);assert(max<=6);
 const ms=performance.now()-began;return {window,ms:Math.round(ms),requests,bytes,max,average_active:Number((busy/ms).toFixed(3))};}
assert(stream.includes('Math.max(conns,Math.min(12,source.capacity?.() || conns)),background);'));
const old=await run(1),current=await run(2);
console.log(JSON.stringify({fixture:'1739-recorded-latency-fixed-service',old,current}));
assert(current.ms<old.ms*.85,'recorded-skew benefit lost');
assert(current.average_active>old.average_active);
console.log('PASS same byte count/canonical block count/six-lane cap; recorded skew benefits from bounded two-window lookahead, not a CDN speed claim');
// A held leading block cannot grow an unbounded queue. Abort all leases.
for(const background of [false,true]){
 const context=vm.createContext({Map,Set,Readable,Buffer,performance,EventEmitter,PLAIN_CONNECTIONS:6,PLAIN_FIRST_CHUNK:524288,PLAIN_CHUNK:2097152,foregroundWindow:(conns,background)=>background?conns:conns*2});
 vm.runInContext(stream+';globalThis.open=parallelStream;',context);
 let started=0,destroyed=0;
 const stalled={fetch(s,e,track){started++;const req=new EventEmitter();req.destroy=()=>{destroyed++;req.emit('close');};track(req);return new Promise(()=>{});}};
 const output=context.open(stalled,0,1024*1024*1024-1,6,background);
 await new Promise(r=>setTimeout(r,10));assert.equal(started,background?6:12);
 output.destroy();assert.equal(destroyed,started);
}
console.log('PASS held-first-block queue bounded to12 foreground/6 background; cancellation destroys every pending lease');
// Live source cap grows only foreground producer; hard clamp and cancel all leases.
for(const capacity of [8,10,12,99])for(const background of [false,true]){
 const context=vm.createContext({Map,Set,Readable,Buffer,performance,EventEmitter,PLAIN_CONNECTIONS:6,PLAIN_FIRST_CHUNK:524288,PLAIN_CHUNK:2097152,foregroundWindow:(conns,background)=>background?conns:conns*2});
 vm.runInContext(stream+';globalThis.open=parallelStream;',context);
 let started=0,destroyed=0;
 const stalled={capacity:()=>capacity,fetch(s,e,track){started++;const req=new EventEmitter();req.destroy=()=>{destroyed++;req.emit('close');};track(req);return new Promise(()=>{});}};
 const output=context.open(stalled,0,1024*1024*1024-1,6,background);
 await new Promise(r=>setTimeout(r,10));assert.equal(started,background?6:Math.min(capacity,12)*2);
 output.destroy();assert.equal(destroyed,started);
}
console.log('PASS live8/10/12 cap grows foreground16/20/24 blocks; probes stay6, clamp24 and cancellation exact');
// Execute the shipping one-shot marker and ABBA clock policy, not a mirror.
const policy=source.slice(source.indexOf('const abMarker='),source.indexOf('// This lookup belongs'));
for(const markerAge of [null,3600001,0]){
 let removed=0;const ctx=vm.createContext({process:{env:{HOME:'/fixture'}},link:'fixture',isPlainCdnUrl:()=>true,
 fs:{statSync(){if(markerAge===null)throw Error('absent');return{mtimeMs:10000000-markerAge};},unlinkSync(){removed++;}},Date:{now:()=>10000000},performance:{now:()=>1000},Math});
 vm.runInContext(policy+';globalThis.mode=lookaheadMode;',ctx);
 const expected=markerAge===0?['A6','B12','B12','A6','A6','B12','B12','A6','default12']:Array(9).fill('default12');
 for(let i=0;i<9;i++){const m=ctx.mode(1000+i*60000);assert.equal(m.mode,expected[i]);assert.equal(m.lookahead_slots,m.mode==='A6'?6:12);}
 assert.equal(removed,markerAge===0?1:0);
}
console.log('PASS absent/expired marker leaves default12; fresh marker consumed once; timed ABBA twice then default12');
