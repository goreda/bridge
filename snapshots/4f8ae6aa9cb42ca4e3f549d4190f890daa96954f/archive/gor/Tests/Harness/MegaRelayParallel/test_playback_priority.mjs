// Throttled actual relay: playback competes with three cold probe readers.
import http from 'node:http';
import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const MiB=1048576,SIZE=256*MiB;let active=0,max=0,hits=0,logs='';
const cdn=http.createServer((req,res)=>{
 const m=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range || '');assert(m);const s=+m[1],e=+m[2];active++;hits++;max=Math.max(max,active);
 res.once('close',()=>active--);res.writeHead(206,{'Content-Length':e-s+1,'Content-Range':`bytes ${s}-${e}/${SIZE}`});
 setTimeout(()=>{const data=Buffer.alloc(e-s+1);for(let i=0;i<data.length;i++)data[i]=(s+i)%251;res.end(data);},Math.max(10,(e-s+1)/MiB*100));
});
await new Promise(r=>cdn.listen(0,'127.0.0.1',r));
const home=fs.mkdtempSync(path.join(os.tmpdir(),'relay-ab-'));const marker=path.join(home,'Library/Application Support/gor/transfer-lookahead-ab.once');fs.mkdirSync(path.dirname(marker),{recursive:true});fs.writeFileSync(marker,'');
const relay=spawn(process.execPath,[process.env.RELAY_PATH || fileURLToPath(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url)),'23312',`http://127.0.0.1:${cdn.address().port}/ticket`],{env:{...process.env,MEGA_RELAY_ALLOW_HTTP_TEST:'1',HOME:home}});
relay.stderr.on('data',d=>logs+=d);await new Promise((resolve,reject)=>{relay.stdout.on('data',d=>{if(String(d).includes('STREAM:'))resolve();});relay.once('exit',()=>reject(new Error(logs)));});
function get(s,e,ua){return new Promise((resolve,reject)=>{
 const began=Date.now();let count=0,valid=true;
 http.get('http://127.0.0.1:23312/',{headers:{Range:`bytes=${s}-${e}`,'User-Agent':ua}},res=>{
  res.on('data',d=>{for(let i=0;i<d.length;i++)if(d[i]!==((s+count+i)%251))valid=false;count+=d.length;});
  res.on('end',()=>{assert(valid && count===e-s+1);resolve({ms:Date.now()-began,bytes:count});});res.on('error',reject);
 }).on('error',reject);
});}
try {
 const probe=[get(64*MiB,88*MiB-1,'Lavf/probe1'),get(96*MiB,120*MiB-1,'Lavf/probe2'),get(128*MiB,152*MiB-1,'Lavf/probe3')];
 await new Promise(r=>setTimeout(r,30));
 const play=await get(0,12*MiB-1,'mpv/playback');
 const background=await Promise.all(probe);
 console.log(JSON.stringify({fixture:'12MiB-playback-vs-three-24MiB-probes',playback:play,probes:background,max_upstream:max,cdn_requests:hits}));
 assert(max<=6);assert(play.ms<1000,'foreground should bypass queued probe work');
 // All probes complete byte-exact, never disabled; inspect evidence after
 // initial already-in-flight background requests have drained.
 const events=logs.split('\n').filter(l=>l.startsWith('CDN-EVIDENCE:')).map(l=>JSON.parse(l.slice(13)));
 assert(!fs.existsSync(marker),'one-shot marker must be consumed');
 assert(events.some(e=>e.event==='lane-start' && e.mode==='A6' && e.lookahead_slots===6 && e.diagnostic===true));
 assert(events.some(e=>e.event==='downstream-progress' && e.mode==='A6'));
 assert(events.some(e=>e.foreground_streams>0));
 assert(events.some(e=>e.event==='downstream-progress' && e.client==='mpv' && e.served_bytes>0 && Number.isFinite(e.mono_ms)));
 assert(Math.max(...events.map(e=>e.max_new_background_while_foreground || 0))<=1);
 assert(events.some(e=>e.max_new_background_while_foreground===1));
 const requests=events.filter(e=>e.event==='upstream-request' && e.outcome==='complete');
 assert(requests.length>10,'per-request diagnostics present');
 assert(requests.some(e=>e.reused_socket===true),'keepAlive reuse observed');
 for(const e of requests){
  for(const k of ['socket_ms','dns_ms','connect_ms','tls_ms','headers_ms','first_byte_ms','body_ms','elapsed_ms','bytes_per_second','queue_ms'])
   assert(e[k]===null || (Number.isFinite(e[k]) && e[k]>=0),k);
  assert.equal(e.agent.keep_alive,true);assert.equal(e.agent.max_sockets,6);
  assert.equal(e.ip_family,'IPv4');assert.equal(e.status,206);
  assert.equal(e.bytes,e.end-e.start+1);
  assert.equal(e.proxy_mode,'direct-node-agent');
 }
 assert(events.some(e=>e.event==='downstream-pressure' && Number.isFinite(e.local_push_blocked_ms)));
 assert(!logs.includes('/ticket'),'signed path never logged');
 const starts=events.filter(e=>e.event==='lane-start'),ends=events.filter(e=>e.event==='lane-end');
 assert(starts.length>10 && ends.length>10);
 const ids=new Set();for(const e of starts){assert(!ids.has(e.upstream_id));ids.add(e.upstream_id);assert(Number.isFinite(e.mono_ms));assert(e.active_upstream<=6);}
 const startByID=new Map(starts.map(e=>[e.upstream_id,e]));
 for(const e of ends){assert(startByID.has(e.upstream_id));assert(e.mono_ms>=startByID.get(e.upstream_id).mono_ms);assert(e.active_upstream<=6);}
 console.log('PASS monotonic start/end lane IDs, unique starts, matching completed ends and six-lane cap');
 console.log('PASS per-request timings, socket reuse, byte counts, pressure, scrubbed paths');
 console.log('PASS foreground bypasses queued probes; all three probes still complete byte-exact; six-lane cap');
} finally {relay.kill();cdn.close();fs.rmSync(home,{recursive:true,force:true});}
