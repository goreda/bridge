// Actual shipping relay against a per-connection throttled TCP CDN.
// No public-CDN or Mac prediction. Each variant finishes within90s.
import http from 'node:http';import assert from 'node:assert/strict';import {spawn} from 'node:child_process';import {fileURLToPath} from 'node:url';
const shared=process.env.TEST_SHARED_BANDWIDTH==='1',rejectGrowth=process.env.TEST_REJECT_AFTER_GROWTH==='1';let rejected=false;
const MiB=1048576,SIZE=1024*MiB,total=(shared?96:768)*MiB;let active=0,max=0,logs='';const sharedClients=new Set();
const sharedTick=setInterval(()=>{const clients=[...sharedClients];for(const c of clients)c.send(Math.floor(65536/Math.max(1,clients.length)));},32);
const cdn=http.createServer((req,res)=>{
 if(rejectGrowth&&max>6&&!rejected){rejected=true;res.writeHead(429,{'Retry-After':'1'});res.end();return;}
 const m=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range||'');assert(m);const s=+m[1],e=+m[2];
 active++;max=Math.max(max,active);res.once('close',()=>active--);
 res.writeHead(206,{'Content-Length':e-s+1,'Content-Range':`bytes ${s}-${e}/${SIZE}`});let remain=e-s+1;
 let timer;const client={send(budget){if(res.destroyed){clearInterval(timer);sharedClients.delete(client);return;}const n=Math.min(remain,budget);res.write(Buffer.alloc(n,77));remain-=n;if(!remain){clearInterval(timer);sharedClients.delete(client);res.end();}}};
 if(shared)sharedClients.add(client);else timer=setInterval(()=>client.send(65536),32);
 res.once('close',()=>{clearInterval(timer);sharedClients.delete(client);});
});await new Promise(r=>cdn.listen(0,'127.0.0.1',r));
const relay=spawn(process.execPath,[fileURLToPath(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url)),'23314',`http://127.0.0.1:${cdn.address().port}/ticket`],{env:{...process.env,MEGA_RELAY_ALLOW_HTTP_TEST:'1'}});
relay.stderr.on('data',d=>logs+=d);await new Promise((resolve,reject)=>{relay.stdout.on('data',d=>{if(String(d).includes('STREAM:'))resolve();});relay.once('exit',()=>reject(Error('relay exited')));});
try{
 let count=0,transferError=null;try{await new Promise((resolve,reject)=>{http.get('http://127.0.0.1:23314/',{headers:{Range:`bytes=0-${total-1}`,'User-Agent':'mpv/fixture'}},res=>{res.on('data',d=>{assert(d.equals(Buffer.alloc(d.length,77)));count+=d.length;});res.on('error',reject);res.on('end',resolve);}).on('error',reject);});}catch(e){transferError=e;}
 if(rejectGrowth){assert(rejected);assert(transferError);assert(logs.includes('"event":"serial-fallback","status":429'));assert(logs.includes('"connections":1'));console.log('PASS actual TCP post-growth429 triggers existing serial fallback and aborts cleanly');}else{
 assert.equal(transferError,null);assert.equal(count,total);assert(max>6&&max<=12);
 const events=logs.split('\n').filter(l=>l.startsWith('CDN-EVIDENCE:')).map(l=>JSON.parse(l.slice(13)));
 const changes=events.filter(e=>e.event==='capacity-search');console.log(JSON.stringify({shared,changes,max}));assert(changes.some(e=>e.decision==='trial'&&e.from===6&&e.to===8));if(shared)assert(changes.some(e=>e.decision==='no_gain'&&e.to===6));else {assert(changes.some(e=>e.decision==='gain'));assert(changes.some(e=>e.to===12));}
 assert(events.some(e=>e.event==='upstream-request'&&e.agent.max_sockets>6));
 console.log(JSON.stringify({fixture:shared?'actual-relay-shared-ceiling':'actual-relay-per-connection-throttle',bytes:count,max_upstream:max,changes}));
 console.log(shared?'PASS actual shared-bandwidth negative: no gain returns to6, byte exact, twelve hard cap':'PASS actual TCP byte-exact768MiB; measured aggregate gain retains extra lanes; twelve hard cap');
}}finally{relay.kill();clearInterval(sharedTick);cdn.closeAllConnections();cdn.close();}
