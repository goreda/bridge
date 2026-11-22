// Deterministic virtual-clock replay of20:45 service times through shipping
// scheduler/cache/stream/controller. Durations are inputs, not a CDN model.
import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import {Readable} from 'node:stream';import {EventEmitter} from 'node:events';
const source=fs.readFileSync(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url),'utf8');
const durations=JSON.parse(fs.readFileSync(new URL('latency-2045.json',import.meta.url),'utf8')).elapsed_ms;
const controller=source.slice(source.indexOf('function capacitySearch()'),source.indexOf('// Per-source cumulative totals'));
const scheduler=source.slice(source.indexOf('function plainSourceState('),source.indexOf('async function resolvePlainSource'));
const start=source.indexOf('function parallelStream('),producer=source.slice(start,source.indexOf('// Resolve the link',start));
async function run(mode){
 const oldDemand=mode==='old'||mode==='window-only',oldWindow=mode==='old'||mode==='demand-only';
 let now=0,sequence=0,scheduled=[],log=[],active=0,max=0,busy=0,requested=0,destroyed=0;
 const FIRST=512,CHUNK=2048,SIZE=FIRST+durations.length*CHUNK;
 function fetchRange(u,agent,s,e,track,context,supply=()=>{}){
  requested++;active++;max=Math.max(max,active);const started=now,duration=durations[(sequence++)%durations.length];
  return new Promise((resolve,reject)=>{let dead=false;const req=new EventEmitter();req.destroy=()=>{if(!dead){dead=true;destroyed++;active--;busy+=now-started;req.emit('close');reject(Error('closed'));}};track(req);
   for(let part=1;part<=16;part++)scheduled.push({at:now+duration*part/16,go(){if(dead)return;supply(Math.floor((e-s+1)*part/16)-Math.floor((e-s+1)*(part-1)/16));if(part===16){dead=true;active--;busy+=now-started;req.emit('close');resolve({buf:Buffer.alloc(e-s+1,77),evidence:{},headers:{}});}}});
  });
 }
 const ctx=vm.createContext({URL,Map,Set,Buffer,Readable,EventEmitter,Math,fetchRange,performance:{now:()=>now},Date:{now:()=>now},lookaheadAB:false,lookaheadMode:()=>({}),foregroundWindow:(n,b)=>b?n:n*2,PLAIN_CONNECTIONS:6,PLAIN_FIRST_CHUNK:FIRST,PLAIN_CHUNK:CHUNK,console:{error:s=>{if(s.startsWith('CDN-EVIDENCE:'))log.push({...JSON.parse(s.slice(13)),time_ms:now});}}});
 let code=scheduler,stream=producer;
 if(oldDemand){code=code.replace('foregroundStreams>0);','foregroundStreams>0 && (active>=limit || waiting.some(w=>!w.background())));');assert.notEqual(code,scheduler);}
 if(oldWindow){stream=stream.replace(/const lookahead = \(\) => foregroundWindow\(background \? conns :\s*Math.max\(conns,Math.min\(12,source.capacity\?\.\(\) \|\| conns\)\),background\);/,'const lookahead = () => foregroundWindow(conns,background);');assert.notEqual(stream,producer);}
 vm.runInContext(controller+code+stream+';globalThis.api={plainSourceState,cachedPlainSource,parallelStream};',ctx);
 const agent={maxSockets:6},network=ctx.api.plainSourceState('http://fixture.invalid',agent);network.size=SIZE;network.foreground(1);
 const cached=ctx.api.cachedPlainSource(network,SIZE),output=ctx.api.parallelStream(cached,0,SIZE-1,6,false);let bytes=0,ended=false,error=null;
 output.on('data',b=>{assert(b.equals(Buffer.alloc(b.length,77)));bytes+=b.length;});output.on('end',()=>ended=true);output.on('error',e=>{error=e;ended=true;});
 let maxPending=0;
 for(let ticks=0;!ended&&ticks<30000;ticks++){
  await new Promise(r=>setImmediate(r));if(!scheduled.length){if(!ended)throw Error('deadlock');break;}
  scheduled.sort((a,b)=>a.at-b.at);const task=scheduled.shift();now=task.at;task.go();maxPending=Math.max(maxPending,cached.evidence().pending_blocks);
 }
 assert.equal(error,null);assert(ended);assert.equal(bytes,SIZE);assert(max<=12);assert.equal(requested,durations.length+1);
 const changes=log.filter(e=>e.event==='capacity-search');return{mode,wall_ms:now,bytes,requested,max,maxPending,average_active:busy/now,changes};
}
const old=await run('old'),demandOnly=await run('demand-only'),windowOnly=await run('window-only'),fixed=await run('fixed');console.log(JSON.stringify({fixture:'2045-recorded-service-durations',block_scale:1024,old,demandOnly,windowOnly,fixed}));
const oldTen=old.changes.find(e=>e.to===10),oldDecision=old.changes.find(e=>e.from===10);assert(oldTen&&oldDecision);assert(oldDecision.time_ms-oldTen.time_ms>60000,'old saturation-reset starvation not reproduced');
const fixedTen=fixed.changes.find(e=>e.to===10),fixedDecision=fixed.changes.find(e=>e.from===10);assert(fixedTen&&fixedDecision);assert(fixedDecision.time_ms-fixedTen.time_ms<15000,'ten-cap trial must complete a measured decision without saturation resets');
assert(fixed.maxPending<=24,'foreground outstanding block window exceeds24');
assert(fixed.wall_ms<old.wall_ms,'dynamic bounded lookahead must improve this trace');
console.log('PASS actual shipping scheduler/cache/stream/controller on20:45 durations: byte exact, measured ten-cap decision, bounded24-block producer, no extra rereads');
