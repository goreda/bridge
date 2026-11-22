// Execute shipping Agent/lookup/fetch/summary functions with actual dual-stack
// loopback TCP. DNS answer only is stubbed. No Mac or public CDN speed claim.
import http from 'node:http';import https from 'node:https';import assert from 'node:assert/strict';
import vm from 'node:vm';import fs from 'node:fs';import {performance} from 'node:perf_hooks';
const source=fs.readFileSync(new URL('../../../Resources/vendor/mega_relay/mega_relay.mjs',import.meta.url),'utf8');
const begin=source.indexOf('function ipv4FirstLookup('),end=source.indexOf('// One source owns the global permits');
let mode='dual',logs=[],lookups=0;
const context=vm.createContext({http,https,performance,Buffer,Date,Map,WeakMap,process:{env:{}},
 console:{error:s=>logs.push(s)},PLAIN_CONNECTIONS:6,
 dns:{lookup(host,opts,cb){lookups++;assert.equal(host,'fixture.invalid');assert.equal(opts.all,true);
  cb(null,mode==='v6-only' ? [{address:'::1',family:6}] : [{address:'::1',family:6},{address:mode==='fallback'?'127.0.0.2':'127.0.0.1',family:4}]);}}});
vm.runInContext(source.slice(begin,end)+'\nglobalThis.api={ipv4FirstLookup,agentFor,fetchRange};',context);
const {ipv4FirstLookup,agentFor,fetchRange}=context.api;
const ordered=await new Promise((resolve,reject)=>ipv4FirstLookup('fixture.invalid',{all:true},(e,a)=>e?reject(e):resolve(a)));
assert.deepEqual(Array.from(ordered,a=>a.family),[4,6]);
let count4=0,count6=0;
function handler(family){return(req,res)=>{if(family===4)count4++;else count6++;
 const m=/^bytes=(\d+)-(\d+)$/.exec(req.headers.range);assert(m);const s=+m[1],e=+m[2];
 res.writeHead(206,{'Content-Range':`bytes ${s}-${e}/1048576`,'Content-Length':e-s+1});
 res.end(Buffer.alloc(e-s+1,77));};}
const v6=http.createServer(handler(6)),v4=http.createServer(handler(4));
await new Promise((r,j)=>{v6.once('error',j);v6.listen({host:'::1',port:0,ipv6Only:true},r)});
const port=v6.address().port;await new Promise((r,j)=>{v4.once('error',j);v4.listen(port,'127.0.0.1',r)});
const url=new URL(`http://fixture.invalid:${port}/DO-NOT-LOG-SIGNED-PATH`),agents=[];
try{
 for(const m of ['dual','fallback','v6-only']){
  mode=m;const agent=agentFor(url);agents.push(agent);const before4=count4,before6=count6;
  const n=m==='dual'?20:2;
  for(let i=0;i<n;i++){
   const result=await fetchRange(url,agent,0,65535,()=>{});
   assert.equal(result.buf.length,65536);assert(result.buf.every(v=>v===77));
  }
  if(m==='dual'){assert.equal(count4-before4,20);assert.equal(count6-before6,0);}
  else{assert.equal(count4-before4,0);assert.equal(count6-before6,2);}
  console.log(`PASS ${m}: IPv4=${count4-before4} IPv6=${count6-before6}, byte-exact`);
 }
 const events=logs.filter(l=>l.startsWith('CDN-EVIDENCE:')).map(l=>JSON.parse(l.slice(13)));
 const summaries=events.filter(e=>e.event==='family-body-summary');
 assert(summaries.some(e=>e.ip_family==='IPv4'&&e.requests===16&&e.bytes===16*65536));
 assert(summaries.some(e=>e.ip_family==='IPv6'&&e.requests===1));
 assert(events.some(e=>e.event==='upstream-request'&&e.reused_socket===true));
 for(const e of summaries){assert(e.rolling_samples<=64);assert(e.mean_body_ms>=0);assert(e.rolling_p95_body_ms>=e.rolling_median_body_ms);}
 assert(!logs.join('').includes('DO-NOT-LOG')&&!logs.join('').includes('fixture.invalid'));
 const requests=events.filter(e=>e.event==='upstream-request'&&e.outcome==='complete');
 const four=requests.filter(e=>e.ip_family==='IPv4'),six=requests.filter(e=>e.ip_family==='IPv6');
 assert.equal(new Set(four.map(e=>e.connection_id)).size,1);
 assert.equal(four.at(-1).socket_request_index,20);
 assert.equal(new Set(four.map(e=>e.route_id)).size,1);
 assert(six.every(e=>e.route_id!==four[0].route_id));
 for(const e of requests){
  assert(e.connection_id>0&&e.route_id>0);assert(e.response_read_watermark>0&&e.socket_read_watermark>0);
  assert.equal(e.tcp_receive_buffer_status,'unsupported-node-tcp-api');
  assert(e.body_rate_bps>0&&e.body_chunks>0&&e.body_chunk_min>0&&e.body_chunk_max>=e.body_chunk_min&&e.body_gap_max_ms>=0);
 }
 assert(!logs.join('').includes('127.0.0.')&&!logs.join('').includes('::1'));
 console.log('PASS actual socket reuse/sequence, distinct address groups, read watermarks and body chunk/gap/rate telemetry; no raw endpoints');
 console.log('PASS family summaries, bounded windows, keepAlive and scrubbed logs');
}finally{for(const a of agents)a.destroy();await Promise.all([new Promise(r=>v4.close(r)),new Promise(r=>v6.close(r))]);}
