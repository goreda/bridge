// Offline recovery and global-concurrency contracts. No live account or CDN.
import http from 'node:http';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const RELAY=fileURLToPath(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url));
const bytes=Buffer.alloc(80*1024*1024);for(let i=0;i<bytes.length;i++)bytes[i]=i%251;
let active=0,max=0,renewals=0,hits=0,expired=false,mode='ok',apiMode='ok';
const cdn=http.createServer((req,res)=>{
 if(req.url.startsWith('/api')){
  renewals++;let body='';req.on('data',d=>body+=d);req.on('end',()=>setTimeout(()=>{
   if(apiMode==='refuse'){res.writeHead(200);res.end('[-9]');return;}
   assert.deepEqual(JSON.parse(body),[{a:'g',n:'abcdefgh',pt:1,g:1,ssl:1}]);
   assert.equal(new URL(req.url,'http://localhost').searchParams.get('x'),'abcdefgh1234');
   res.end(JSON.stringify([{g:`http://127.0.0.1:${cdn.address().port}/fresh`,s:apiMode==='size-change' ? bytes.length+1:bytes.length}]));
  },60));return;
 }
 hits++;
 if((expired && req.url.startsWith('/old')) || mode==='403' || mode==='429' || mode==='509'){
  res.writeHead(mode==='429' ? 429:mode==='509' ? 509:403,{'Retry-After':'2','Set-Cookie':'do-not-log-secret','Location':'https://secret.invalid/token'});res.end();return;
 }
 const match=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range || '');
 if(!match){res.writeHead(400);res.end();return;}
 const s=+match[1],e=+match[2];active++;max=Math.max(max,active);
 let closed=false;res.on('close',()=>{if(!closed){closed=true;active--;}});
 res.writeHead(206,{'Content-Range':`bytes ${s}-${e}/${bytes.length}`,'Content-Length':e-s+1});
 setTimeout(()=>res.end(bytes.subarray(s,e+1)),30);
});
await new Promise(r=>cdn.listen(0,'127.0.0.1',r));
let child,logs='';
async function start(){
 expired=false;mode='ok';apiMode='ok';active=0;max=0;renewals=0;logs='';
 const p=spawn(process.execPath,[RELAY,'23309',`http://127.0.0.1:${cdn.address().port}/old/secret-ticket`],{env:{...process.env,MEGA_RELAY_ALLOW_HTTP_TEST:'1',MEGA_RELAY_TEST_REFRESH:`http://127.0.0.1:${cdn.address().port}/api`,GOR_TRANSFER_SHARE:'abcdefgh1234',GOR_TRANSFER_NODE:'abcdefgh'}});
 child=p;await new Promise((resolve,reject)=>{p.stdout.on('data',d=>{if(String(d).includes('STREAM:'))resolve();});p.stderr.on('data',d=>logs+=d);p.once('exit',()=>reject(new Error(logs)));});
}
async function stop(){const p=child;await new Promise(r=>{p.once('exit',r);p.kill();});await new Promise(r=>setTimeout(r,50));}
function get(start,end,ua='mpv/test'){return new Promise(resolve=>{
 const parts=[];const req=http.get('http://127.0.0.1:23309/',{headers:{Range:`bytes=${start}-${end}`,'User-Agent':ua}},res=>{res.on('data',d=>parts.push(d));res.on('end',()=>resolve({status:res.statusCode,buf:Buffer.concat(parts)}));res.on('error',()=>resolve({status:0}));});req.on('error',()=>resolve({status:0}));
});}
try {
 await start();max=0;
 const results=await Promise.all([get(0,8*1024*1024-1),get(8*1024*1024,16*1024*1024-1)]);
 assert(results.every((r,i)=>r.status===206 && r.buf.equals(bytes.subarray(i*8*1024*1024,(i+1)*8*1024*1024))));
 assert(max<=6 && max>1);console.log('PASS two downstream requests share six global permits, byte exact');
 await stop();await start();expired=true;max=0;
 const recovered=await Promise.all([get(0,6*1024*1024-1),get(8*1024*1024,14*1024*1024-1)]);
 assert(recovered.every((r,i)=>r.status===206 && r.buf.equals(bytes.subarray(i*8*1024*1024,i*8*1024*1024+6*1024*1024))));
 assert.equal(renewals,1);assert(logs.includes('ticket-renewed'));assert(logs.includes('serial-fallback'));
 assert(!logs.includes('secret-ticket') && !logs.includes('do-not-log-secret') && !logs.includes('secret.invalid'));
 console.log('PASS concurrent 403s coalesce one ticket renewal, serial fallback resumes bytes, logs scrub secrets');
 for(let i=1;i<=3;i++){const s=i*16*1024*1024,e=s+16*1024*1024;const warmed=await get(s,e-1);assert(warmed.status===206 && warmed.buf.equals(bytes.subarray(s,e)));}
 assert(/\"event\":\"lane-ramp\",\"connections\":6/.test(logs));assert(max<=6);
 console.log('PASS healthy recovered data ramps back to six lanes, never above global cap');
 await stop();
 for(const failure of ['size-change','refuse','persistent-403','429','509']){
  await start();expired=true;apiMode=failure;mode=failure==='persistent-403' ? '403':failure==='429' ? '429':failure==='509' ? '509':'ok';
  const r=await get(0,6*1024*1024-1);assert.notEqual(r.status,206);
  const count=hits;await get(0,1023);assert.equal(hits,count);
  assert(renewals<=1);console.log(`PASS ${failure}: bounded failure, no reconnect storm during cooldown`);await stop();
 }
 await start();expired=true;
 const mixed=await Promise.all([get(0,24*1024*1024-1),get(32*1024*1024,56*1024*1024-1,'Lavf/probe')]);
 assert(mixed.every((r,i)=>r.status===206 && r.buf.equals(bytes.subarray(i*32*1024*1024,i*32*1024*1024+24*1024*1024))));
 assert.equal(renewals,1);console.log('PASS serial 403 recovery preserves foreground and background completion with priority');await stop();
 await start();expired=true;
 const req=http.get('http://127.0.0.1:23309/',{headers:{Range:'bytes=0-'}},res=>res.resume());req.on('error',()=>{});
 setTimeout(()=>req.destroy(),10);await new Promise(r=>setTimeout(r,300));assert.equal(active,0);
 const afterAbort=await get(0,1023);assert(afterAbort.status===206 && afterAbort.buf.equals(bytes.subarray(0,1024)));
 console.log('PASS downstream abort cancels ranges during renewal and releases permits for next seek');await stop();
} finally {if(child && child.exitCode===null)child.kill();cdn.close();}
