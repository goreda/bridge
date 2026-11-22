// Actual loopback cache, coalescing, cancellation and memory-bound fixtures.
import http from 'node:http';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const MiB=1024*1024,SIZE=128*MiB,bytes=Buffer.alloc(SIZE);
for(let i=0;i<SIZE;i++)bytes[i]=i%251;
let hits=0,active=0,max=0,transferred=0,logs='';
const cdn=http.createServer((req,res)=>{
 const m=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range || '');assert(m);
 const s=+m[1],e=+m[2];hits++;transferred+=e-s+1;active++;max=Math.max(max,active);
 res.once('close',()=>active--);
 res.writeHead(206,{'Content-Length':e-s+1,'Content-Range':`bytes ${s}-${e}/${SIZE}`});
 setTimeout(()=>res.end(bytes.subarray(s,e+1)),35);
});
await new Promise(r=>cdn.listen(0,'127.0.0.1',r));
const relay=spawn(process.execPath,[process.env.RELAY_PATH || fileURLToPath(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url)),'23311',`http://127.0.0.1:${cdn.address().port}/private-ticket`],{env:{...process.env,MEGA_RELAY_ALLOW_HTTP_TEST:'1'}});
relay.stderr.on('data',d=>logs+=d);
await new Promise((resolve,reject)=>{relay.stdout.on('data',d=>{if(String(d).includes('STREAM:'))resolve();});relay.once('exit',()=>reject(new Error(logs)));});
function get(s,e,ua='mpv/test'){return new Promise((resolve,reject)=>{
 const req=http.get('http://127.0.0.1:23311/',{headers:{Range:`bytes=${s}-${e}`,'User-Agent':ua}},res=>{
  const chunks=[];res.on('data',d=>chunks.push(d));res.on('end',()=>resolve(Buffer.concat(chunks)));res.on('error',reject);
 });req.on('error',reject);
});}
function stats(){const events=logs.split('\n').filter(l=>l.startsWith('CDN-EVIDENCE:')).map(l=>JSON.parse(l.slice(13)));return events.filter(e=>e.event==='downstream-close').at(-1);}
try {
 let before=hits;const beforeBytes=transferred,began=Date.now();
 const both=await Promise.all([get(0,12*MiB-1),get(7129,12*MiB-2,'Lavf/ffmpeg probe')]);
 assert(both[0].equals(bytes.subarray(0,12*MiB)));assert(both[1].equals(bytes.subarray(7129,12*MiB-1)));
 console.log(JSON.stringify({fixture:'two-overlap-12MiB',upstream_requests:hits-before,upstream_bytes:transferred-beforeBytes,elapsed_ms:Date.now()-began,max_active:max}));
 assert.equal(hits-before,7);assert(max<=6);
 console.log('PASS two overlapping differently aligned 12 MiB reads use seven canonical blocks, byte exact, <=6 lanes');
 before=hits;assert((await get(0,512*1024-1)).equals(bytes.subarray(0,512*1024)));assert.equal(hits,before);
 console.log('PASS repeated head read is served without any CDN request');
 // Abort a probe while another consumer still needs the same cold blocks.
 const survivor=get(32*MiB,40*MiB-1);
 const abort=http.get('http://127.0.0.1:23311/',{headers:{Range:`bytes=${32*MiB}-${40*MiB-1}`,'User-Agent':'Lavf/probe'}},res=>res.resume());abort.on('error',()=>{});
 setTimeout(()=>abort.destroy(),10);
 assert((await survivor).equals(bytes.subarray(32*MiB,40*MiB)));
 console.log('PASS aborting one coalesced consumer does not cancel surviving playback');
 // Touch the end/index, then exceed the 64 MiB bound with middle blocks.
 await get(SIZE-2*MiB,SIZE-1);
 for(let s=16*MiB;s<112*MiB;s+=8*MiB)assert((await get(s,s+8*MiB-1)).equals(bytes.subarray(s,s+8*MiB)));
 await new Promise(r=>setTimeout(r,30));assert(stats().cache_bytes<=64*MiB);
 before=hits;await get(0,512*1024-1);await get(SIZE-2*MiB,SIZE-1);assert.equal(hits,before);
 assert(logs.includes('"client":"mpv"') && logs.includes('"client":"ffmpeg"'));assert(!logs.includes('private-ticket') && !logs.includes('Lavf/probe'));
 console.log('PASS >96 MiB traversal stays within 64 MiB cache; head/tail retained; only client enums logged');
 console.log(JSON.stringify({cdn_requests:hits,max_active:max,...stats()}));
} finally {relay.kill();cdn.close();}
