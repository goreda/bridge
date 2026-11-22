// ================================================================
//  mega_relay.mjs — local HTTP relay that streams a MEGA file to mpv
//  as PLAINTEXT, built on the vendored megajs library.
//
//  mpv <-http (plaintext)-> this relay <-https (ciphertext)-> MEGA CDN
//
//  This rewrite replaces the hand-rolled AES-CTR/key-derivation core
//  and the CDP "g"-API XHR in CDPSession.swift: megajs owns the link
//  parsing, folder listing, node-key decryption, CDN URL fetching,
//  chunked download and content decryption. Key state bugs of the old
//  relay (it re-decrypted an already-decrypted webclient key) are
//  impossible here because the key never crosses the Swift/JS boundary
//  at all — megajs derives it from the link's own #fragment.
//
//  Usage: node mega_relay.mjs <port> <link> <nodeKeyField> <folderKeyFragment>
//
//    <link>              one of:
//                          https://mega.nz/file/<handle>#<key>
//                          https://mega.nz/folder/<id>#<key>
//                          mega-folder::<shareURL>::<handle>   (gor internal form)
//    <nodeKeyField>      folder links only: "<fileHandle>:<b64>" straight from
//                        the M.d scrape — only the handle before the first colon
//                        is used, to find the file inside the folder. Pass ""
//                        for single-file links (handle comes from the URL).
//    <folderKeyFragment> unused by this rewrite (megajs reads the key from the
//                        link fragment); argv slot kept so MegaStreamManager's
//                        launch contract is unchanged.
//
//  Stdout contract (unchanged): exactly one "STREAM:<url>" line once the
//  file's attributes are resolved and the server is listening.
//  Stderr contract (unchanged): "ERROR:<message>" lines for the OSD/log.
//
//  TEST HOOK: if env MEGA_RELAY_FAKE_FILE is set, the relay serves that
//  local file instead of touching the network. Used by the offline
//  round-trip test; never set in the app.
// ================================================================

import http from 'node:http';
import fs from 'node:fs';
import { pipeline, Readable } from 'node:stream';
import https from 'node:https';
import dns from 'node:dns';
import { EventEmitter } from 'node:events';
import { performance } from 'node:perf_hooks';

function fail(msg) {
  console.error(`ERROR:${msg}`);
  process.exit(1);
}

const [, , portArg, link, nodeKeyField /* , folderKeyFragment (unused) */] = process.argv;
if (!portArg || !link) {
  fail('usage: mega_relay.mjs <port> <link> <nodeKeyField> <folderKeyFragment>');
}
const PORT = Number(portArg);
if (!Number.isInteger(PORT) || PORT < 0 || PORT > 65535) fail(`invalid port: ${portArg}`);

// ---------------------------------------------------------------
// Plain signed CDN URL (transfer.it): parallel ranged reader
// ---------------------------------------------------------------
function isPlainCdnUrl(raw) {
  try {
    const u = new URL(raw);
    if (process.env.MEGA_RELAY_ALLOW_HTTP_TEST === '1' && u.protocol === 'http:' && u.hostname === '127.0.0.1') return true;
    return u.protocol === 'https:' && !u.username && !u.password && !u.port && u.hostname.endsWith('.userstorage.mega.co.nz');
  } catch { return false; }
}

const PLAIN_CONNECTIONS = 6;
const PLAIN_FIRST_CHUNK = 512 * 1024;      // fast start
const PLAIN_CHUNK = 2 * 1024 * 1024;       // steady state

// One-shot diagnostic only. No preference/default changes. Owner's update
// command creates the marker; the next plain-CDN relay consumes it once.
const abMarker=(process.env.HOME || '')+'/Library/Application Support/gor/transfer-lookahead-ab.once';
let lookaheadAB=false,abBegan=0;
if(isPlainCdnUrl(link))try{
  const age=Date.now()-fs.statSync(abMarker).mtimeMs;
  if(age>=0 && age<3600000){fs.unlinkSync(abMarker);lookaheadAB=true;abBegan=performance.now();}
}catch{}
function lookaheadMode(now=performance.now()) {
  const phase=lookaheadAB ? Math.floor(Math.max(0,now-abBegan)/60000):-1;
  // ABBA twice reduces simple monotonic drift confounding; not a proof that
  // the service is stationary. Eight minutes, then ordinary12-slot behavior.
  const slots=lookaheadAB && phase<8 ? ([6,12,12,6][phase%4]):12;
  return {diagnostic:lookaheadAB && phase<8,phase,lookahead_slots:slots,
    mode:lookaheadAB && phase<8 ? (slots===6 ? 'A6':'B12'):'default12'};
}
function foregroundWindow(conns,background) {
  return background ? conns:Math.max(conns,Math.round(conns*lookaheadMode().lookahead_slots/6));
}

// This lookup belongs only to the transfer.it plaintext CDN Agent. Do not
// change process-wide DNS order or MEGA's own networking. Preserve both
// families so Node can try IPv6 when IPv4 fails or does not connect promptly.
function ipv4FirstLookup(hostname, options, callback) {
  dns.lookup(hostname, { ...options, all: true, verbatim: true }, (err, addresses) => {
    if (err) { callback(err); return; }
    const ordered = [...addresses.filter(a => a.family === 4), ...addresses.filter(a => a.family !== 4)];
    if (options.all) callback(null, ordered);
    else if (ordered.length) callback(null, ordered[0].address, ordered[0].family);
    else callback(Object.assign(new Error('CDN hostname has no addresses'), {code:'ENOTFOUND'}));
  });
}

function agentFor(u) {
  const options = { keepAlive: true, maxSockets: PLAIN_CONNECTIONS,
    lookup: ipv4FirstLookup, autoSelectFamily: true, autoSelectFamilyAttemptTimeout: 250 };
  return u.protocol === 'http:' ? new http.Agent(options) : new https.Agent(options);
}

// Source-local measured capacity search, not a saved preference. Start at6.
// Keep a higher cap only after aggregate delivered bytes/sec improve by12%.
// A no-gain/shared-bandwidth path returns to its last measured good cap.
function capacitySearch() {
  let began=null,bytes=0,count=0,bestLimit=6,bestRate=0,trial=false,holdUntil=0,settleUntil=0;
  return {
    reset(now){began=null;bytes=0;count=0;bestLimit=6;bestRate=0;trial=false;holdUntil=now+60000;},
    sample(now,n,limit,demand) {
      if(limit<6 || !demand){began=null;bytes=0;count=0;return null;}
      if(now<holdUntil || now<settleUntil)return null;
      if(began===null){began=now;bytes=0;count=0;return null;}
      bytes+=n;count++;
      if(now-began<10000 || count<6)return null;
      const rate=bytes*1000/(now-began),elapsed=now-began;
      began=null;bytes=0;count=0;settleUntil=now+2000;
      if(!trial){bestLimit=limit;bestRate=rate;
        if(limit>=12)return null;
        trial=true;return {from:limit,to:limit+2,rate_bps:Math.round(rate),elapsed_ms:Math.round(elapsed),decision:'trial'};
      }
      if(rate<bestRate*1.12){const to=bestLimit;trial=false;holdUntil=now+60000;began=null;
        return {from:limit,to,rate_bps:Math.round(rate),baseline_bps:Math.round(bestRate),elapsed_ms:Math.round(elapsed),decision:'no_gain'};
      }
      bestLimit=limit;bestRate=rate;
      if(limit>=12){trial=false;holdUntil=now+60000;began=null;
        return {from:limit,to:limit,rate_bps:Math.round(rate),elapsed_ms:Math.round(elapsed),decision:'retain'};
      }
      return {from:limit,to:limit+2,rate_bps:Math.round(rate),elapsed_ms:Math.round(elapsed),decision:'gain'};
    }
  };
}

// Per-source cumulative totals plus bounded rolling body-latency windows.
// No IP addresses, hostnames or signed URLs enter these summaries.
const familySummaries = new WeakMap();
function reportFamily(agent, timing) {
  if (timing.status !== 206 || !(timing.body_ms >= 0)) return;
  const family = timing.ip_family === 'IPv4' || timing.ip_family === 4 ? 'IPv4' :
    timing.ip_family === 'IPv6' || timing.ip_family === 6 ? 'IPv6' : 'unknown';
  let families = familySummaries.get(agent);
  if (!families) { families = new Map(); familySummaries.set(agent, families); }
  let s = families.get(family);
  if (!s) { s = {requests:0,bytes:0,body_ms:0,samples:[],last_report:0}; families.set(family,s); }
  s.requests++; s.bytes += timing.bytes; s.body_ms += timing.body_ms;
  s.samples.push(timing.body_ms); if (s.samples.length > 64) s.samples.shift();
  if (s.requests === 1 || s.requests % 16 === 0 || Date.now() - s.last_report >= 5000) {
    s.last_report = Date.now(); const sorted = [...s.samples].sort((a,b)=>a-b), mid = Math.floor(sorted.length/2);
    const median = sorted.length%2 ? sorted[mid] : (sorted[mid-1]+sorted[mid])/2;
    console.error('CDN-EVIDENCE:'+JSON.stringify({event:'family-body-summary',ip_family:family,
      requests:s.requests,bytes:s.bytes,total_body_ms:Math.round(s.body_ms),
      mean_body_ms:Math.round(s.body_ms/s.requests),rolling_samples:sorted.length,
      rolling_median_body_ms:Math.round(median),rolling_p95_body_ms:Math.round(sorted[Math.ceil(sorted.length*.95)-1]),
      body_bytes_per_second:Math.round(s.bytes*1000/Math.max(s.body_ms,.001)),
      note:'body-time sum across concurrent requests, not wall-clock aggregate throughput',
      family_preference:'IPv4-first',ipv6_fallback:true}));
  }
}

// Process-local endpoint groups preserve clustering, never raw addresses or URLs.
// Weak socket ownership does not keep closed connections alive.
const transportSockets=new WeakMap(),transportRoutes=new Map();let transportSequence=0;
function transportIdentity(socket) {
  if(!socket)return {};
  let id=transportSockets.get(socket);
  if(!id){id={connection_id:++transportSequence,requests:0};transportSockets.set(socket,id);}
  const address=socket.remoteAddress;
  if(address&&transportRoutes.size<256&&!transportRoutes.has(address))transportRoutes.set(address,transportRoutes.size+1);
  return {connection_id:id.connection_id,route_id:transportRoutes.get(address)||0,
    socket_request_index:id.requests,socket_read_watermark:socket.readableHighWaterMark,
    tcp_receive_buffer_status:'unsupported-node-tcp-api'};
}

// One bounded, validated ranged GET. Never buffer a whole-file response.
// `track` receives the ClientRequest so the caller can destroy it.
function fetchRange(u, agent, start, end, track, context={}, supply=()=>{}) {
  const began = performance.now();
  const timing={socket_ms:null,dns_ms:null,connect_ms:null,tls_ms:null,headers_ms:null,first_byte_ms:null,
    body_ms:null,ip_family:null,reused_socket:false,bytes:0};
  let reported=false, socketAt=null, dnsAt=null, connectAt=null, headersAt=null,requestSocket=null,lastBodyAt=null;
  const chunks={body_chunks:0,body_chunk_min:0,body_chunk_max:0,body_gap_max_ms:0};
  const elapsed=()=>Math.round((performance.now()-began)*1000)/1000;
  function report(req,outcome) {
    if(reported)return;reported=true;
    const total=elapsed();
    if(outcome==='complete')reportFamily(agent,timing);
    console.error('CDN-EVIDENCE:'+JSON.stringify({event:'upstream-request',start,end,outcome,...context,...timing,
      ...transportIdentity(requestSocket),...chunks,
      response_read_watermark:timing.response_read_watermark,
      body_rate_bps:headersAt===null?0:Math.round(timing.bytes*1000/Math.max(performance.now()-headersAt,0.001)),
      elapsed_ms:total,bytes_per_second:Math.round(timing.bytes*1000/Math.max(total,0.001)),
      reused_socket:req.reusedSocket===true,proxy_env_present:['HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy'].some(k=>Boolean(process.env[k])),
      proxy_mode:'direct-node-agent',agent:{keep_alive:agent.keepAlive,max_sockets:agent.maxSockets,
        max_free_sockets:agent.maxFreeSockets,keep_alive_msecs:agent.keepAliveMsecs,
        family_preference:'IPv4-first',auto_select_family:true,attempt_timeout_ms:250,ipv6_fallback:true},
      request_high_water_mark:req.writableHighWaterMark}));
  }
  return new Promise((resolve, reject) => {
    const lib = u.protocol === 'http:' ? http : https;
    const req = lib.request(u, {
      agent,
      method: 'GET',
      headers: { Range: `bytes=${start}-${end}`, 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)' },
    }, (res) => {
      headersAt=performance.now();timing.headers_ms=elapsed();timing.status=res.statusCode;
      timing.ip_family=res.socket?.remoteFamily || timing.ip_family;
      timing.response_read_watermark=res.readableHighWaterMark;
      const evidence = {
        status: res.statusCode, start, end, headers_ms: timing.headers_ms,
        content_range: res.headers['content-range'] || null,
        content_length: res.headers['content-length'] || null,
        retry_after: res.headers['retry-after'] || null,
      };
      // Fixed header allowlist: never emit signed paths, cookies or authorization.
      if (res.statusCode !== 206) {
        console.error('CDN-EVIDENCE:' + JSON.stringify(evidence));
        // 200 means the CDN ignored Range and would send the whole file: never buffer that.
        res.destroy();
        reject(Object.assign(new Error(`CDN returned ${res.statusCode}`), { status: res.statusCode >= 400 ? res.statusCode : 400, retryAfter: Number(res.headers['retry-after']) || 0 }));
        return;
      }
      const contentRange = /^bytes (\d+)-(\d+)\/(\d+)$/.exec(res.headers['content-range'] || '');
      if (!contentRange || Number(contentRange[1]) !== start || Number(contentRange[2]) !== end || Number(contentRange[3]) <= end) {
        res.destroy(); reject(new Error('invalid CDN Content-Range')); return;
      }
      const parts = []; let received = 0;
      res.once('data',()=>{timing.first_byte_ms=elapsed();});
      res.on('data', (d) => {
        const at=performance.now();chunks.body_chunks++;
        chunks.body_chunk_min=chunks.body_chunk_min?Math.min(chunks.body_chunk_min,d.length):d.length;
        chunks.body_chunk_max=Math.max(chunks.body_chunk_max,d.length);
        chunks.body_gap_max_ms=Math.round(Math.max(chunks.body_gap_max_ms,at-(lastBodyAt??headersAt))*1000)/1000;lastBodyAt=at;
        received += d.length;timing.bytes=received;
        if (received > end - start + 1) { res.destroy(new Error('CDN chunk exceeded range')); return; }
        parts.push(d);supply(d.length);
      });
      res.on('end', () => {
        if(received !== end-start+1) {reject(new Error('short CDN chunk'));return;}
        timing.body_ms=Math.round((performance.now()-headersAt)*1000)/1000;
        evidence.elapsed_ms=elapsed();report(req,'complete');
        resolve({buf:Buffer.concat(parts),headers:res.headers,evidence});
      });
      res.on('aborted', () => reject(new Error('CDN response aborted')));
      res.on('error', reject);
    });
    req.once('socket',socket=>{
      requestSocket=socket;transportIdentity(socket);transportSockets.get(socket).requests++;
      socketAt=performance.now();timing.socket_ms=elapsed();
      timing.ip_family=socket.remoteFamily || null;
      if(!socket.connecting)return;
      socket.once('lookup',(_err,_address,family)=>{dnsAt=performance.now();timing.dns_ms=Math.round((dnsAt-socketAt)*1000)/1000;timing.ip_family=family || null;});
      socket.once('connect',()=>{connectAt=performance.now();timing.connect_ms=Math.round((connectAt-(dnsAt || socketAt))*1000)/1000;timing.ip_family=socket.remoteFamily || timing.ip_family;});
      socket.once('secureConnect',()=>{timing.tls_ms=Math.round((performance.now()-(connectAt || socketAt))*1000)/1000;});
    });
    req.once('error',()=>report(req,'error'));
    req.once('close',()=>report(req,'closed'));
    req.setTimeout(15000, () => req.destroy(new Error('CDN request timed out')));
    req.on('close', () => reject(new Error('CDN request closed')));
    req.on('error', reject);
    track(req);
    req.end();
  });
}

// One source owns the global permits and ticket. Overlapping mpv probes cannot
// multiply the source cap per downstream response; rejected tickets renew once.
function plainSourceState(rawUrl, agent) {
  let current = new URL(rawUrl), generation = 0, refreshing = null;
  let active = 0, cooldown = 0, delivered = 0, lastReport = Date.now();
  let limit = PLAIN_CONNECTIONS, healthyBytes = 0, upstreamSequence = 0;
  const capacity=capacitySearch();
  const waiting=[];let foregroundStreams=0,activeBackground=0,foregroundAdmissions=0,maxAdmittedBackground=0;
  function drain() {
    while(active<limit && waiting.length) {
      const fg=waiting.findIndex(w=>!w.background());
      const bg=waiting.findIndex(w=>w.background());
      let index=fg;
      // With playback present, probes retain at most one lane. Reserve it
      // when saturated; serial recovery gives a probe one turn per eight.
      if(bg>=0 && (!foregroundStreams || (activeBackground===0 &&
          (fg<0 || (limit>1 && active===limit-1) || (limit===1 && foregroundAdmissions>=8))))) index=bg;
      if(index<0 || (waiting[index].background() && foregroundStreams>0 && activeBackground>=1))break;
      const entry=waiting.splice(index,1)[0],background=entry.background();
      active++;if(background){activeBackground++;foregroundAdmissions=0;
        if(foregroundStreams>0)maxAdmittedBackground=Math.max(maxAdmittedBackground,activeBackground);
      }else foregroundAdmissions++;
      entry.resolve(background);
    }
  }
  function acquire(background) {return new Promise(resolve=>{waiting.push({resolve,background});drain();});}
  function release(background) {active--;if(background)activeBackground--;drain();}
  async function refresh(seen) {
    if (generation !== seen) return;
    if (refreshing) return refreshing;
    refreshing = (async () => {
      const share = process.env.GOR_TRANSFER_SHARE || '', node = process.env.GOR_TRANSFER_NODE || '';
      if (!/^[A-Za-z0-9_-]{8,64}$/.test(share) || !/^[A-Za-z0-9_-]{8}$/.test(node))
        throw new Error('signed CDN ticket rejected; renewal context unavailable');
      const test = process.env.MEGA_RELAY_ALLOW_HTTP_TEST === '1' && process.env.MEGA_RELAY_TEST_REFRESH;
      const endpoint = test ? new URL(process.env.MEGA_RELAY_TEST_REFRESH) : new URL('https://bt7.api.mega.co.nz/cs');
      if (test && (endpoint.hostname !== '127.0.0.1' || endpoint.protocol !== 'http:')) throw new Error('invalid test endpoint');
      endpoint.searchParams.set('x', share);
      const payload = JSON.stringify([{a:'g',n:node,pt:1,g:1,ssl:1}]);
      const ticket = await new Promise((resolve,reject) => {
        const lib=endpoint.protocol === 'http:' ? http:https;
        const req=lib.request(endpoint,{method:'POST',headers:{'Content-Type':'text/plain','Content-Length':Buffer.byteLength(payload),'Origin':'https://transfer.it'}},res => {
          if(res.statusCode !== 200) {res.destroy();reject(new Error('ticket API status '+res.statusCode));return;}
          let body='';res.setEncoding('utf8');
          res.on('data',d => {body+=d;if(body.length>65536)res.destroy(new Error('ticket reply too large'));});
          res.on('error',reject);res.on('end',() => {try {resolve(JSON.parse(body)[0]);} catch(e){reject(new Error('invalid ticket reply'));}});
        });
        req.setTimeout(15000,()=>req.destroy(new Error('ticket renewal timed out')));req.on('error',reject);req.end(payload);
      });
      if (!ticket || typeof ticket.g !== 'string' || !isPlainCdnUrl(ticket.g)) throw new Error('ticket renewal refused');
      if (state.size && ticket.s !== state.size) throw new Error('renewed ticket file size changed');
      const next=new URL(ticket.g);next.pathname=next.pathname.replace(/\/$/,'')+'/x';
      current=next;generation++;
      console.error('CDN-EVIDENCE:'+JSON.stringify({event:'ticket-renewed',generation,connections:limit}));
    })().finally(()=>{refreshing=null;});
    return refreshing;
  }
  const state = {
    size: 0,
    capacity(){return limit;},
    foreground(delta){foregroundStreams=Math.max(0,foregroundStreams+delta);if(!foregroundStreams)capacity.sample(performance.now(),0,limit,false);console.error('CDN-EVIDENCE:'+JSON.stringify({event:'priority-state',...state.scheduling()}));drain();},
    reprioritize(){drain();},
    scheduling(){return {...lookaheadMode(),foreground_window_slots:foregroundWindow(Math.max(PLAIN_CONNECTIONS,limit),false),background_window_slots:PLAIN_CONNECTIONS,foreground_streams:foregroundStreams,active_upstream:active,active_background:activeBackground,queued_upstream:waiting.length,max_new_background_while_foreground:maxAdmittedBackground};},
    async fetch(start,end,track,cancelled=()=>false,background=()=>false) {
      const remaining=cooldown-Date.now();
      if(remaining>0) throw new Error('CDN cooling down; retry in '+Math.ceil(remaining/1000)+'s');
      for(let attempt=0;attempt<3;attempt++) {
        const queuedAt=performance.now();
        const backgroundPermit=await acquire(background);
        const queueMs=Math.round((performance.now()-queuedAt)*1000)/1000;
        if(cancelled() || Date.now()<cooldown){release(backgroundPermit);throw new Error(cancelled() ? 'downstream closed':'CDN cooling down');}
        const seen=generation,upstreamID=++upstreamSequence,modeAtStart=lookaheadMode();
        const laneEvidence=event=>console.error('CDN-EVIDENCE:'+JSON.stringify({event,upstream_id:upstreamID,
          mono_ms:Math.round(performance.now()*1000)/1000,background:backgroundPermit,connections:limit,...state.scheduling(),...modeAtStart}));
        laneEvidence('lane-start');
        try {
          const result=await fetchRange(current,agent,start,end,track,{queue_ms:queueMs,background:backgroundPermit,generation:seen,...modeAtStart,upstream_id:upstreamID},n=>{
            // Measure arriving body bytes, not completion batches. Settling
            // windows exclude boundary bursts; all source permits still apply.
            if(lookaheadAB || backgroundPermit)return;
            const change=capacity.sample(performance.now(),n,limit,
              foregroundStreams>0);
            if(change){limit=change.to;agent.maxSockets=limit;drain();console.error('CDN-EVIDENCE:'+JSON.stringify({event:'capacity-search',...change,connections:limit,...state.scheduling()}));}
          });
          result.evidence.queue_ms=queueMs;
          delivered+=result.buf.length;healthyBytes+=result.buf.length;
          // Conservative recovery: one extra lane per 8 MiB of valid data.
          // A ticket refresh must not permanently reduce playback to one lane.
          if(limit<PLAIN_CONNECTIONS && healthyBytes>=8*1024*1024) {
            limit++;agent.maxSockets=limit;healthyBytes=0;drain();
            console.error('CDN-EVIDENCE:'+JSON.stringify({event:'lane-ramp',connections:limit,generation}));
          }
          if(Date.now()-lastReport>=5000 || state.size===0) {
            console.error('CDN-EVIDENCE:'+JSON.stringify({...result.evidence,event:'range-ok',generation,active,connections:limit,bytes_since_report:delivered,report_ms:Date.now()-lastReport}));
            delivered=0;lastReport=Date.now();
          }
          return result;
        } catch(err) {
          if(cancelled() || Date.now()<cooldown)throw err;
          if([403,404,429,509].includes(err.status)) {
            limit=1;agent.maxSockets=limit;healthyBytes=0;capacity.reset(performance.now());
            console.error('CDN-EVIDENCE:'+JSON.stringify({event:'serial-fallback',status:err.status,generation,connections:limit}));
            if((err.status===403 || err.status===404) && attempt===0) {
              try {await refresh(seen);} catch(e) {cooldown=Date.now()+30000;throw e;}
            } else {cooldown=Date.now()+Math.min(60000,Math.max(1000,err.retryAfter*1000 || 5000));throw err;}
          } else if(err.status || attempt===2) throw err;
          else await new Promise(r=>setTimeout(r,300*(attempt+1)));
        } finally {release(backgroundPermit);laneEvidence('lane-end');}
      }
      throw new Error('CDN range recovery exhausted');
    },
  };
  return state;
}

// Source-scoped canonical blocks coalesce independent decoder/probe reads.
// A consumer owns a lease, not the shared upstream request: aborting a probe
// must not cancel bytes still awaited by playback. All-consumer abort cancels it.
function cachedPlainSource(network, size) {
  const cap=64*1024*1024, pinnedHead=8*1024*1024, pinnedTail=4*1024*1024;
  const cache=new Map(),pending=new Map();let used=0,hits=0,joined=0,misses=0;
  function blockAt(offset) {
    const start=offset<PLAIN_FIRST_CHUNK ? 0:PLAIN_FIRST_CHUNK+Math.floor((offset-PLAIN_FIRST_CHUNK)/PLAIN_CHUNK)*PLAIN_CHUNK;
    return [start,Math.min(size-1,start+(start===0 ? PLAIN_FIRST_CHUNK:PLAIN_CHUNK)-1)];
  }
  function retain(start,end,buf) {
    if(cache.has(start))return;
    cache.set(start,{end,buf,pinned:start<pinnedHead || end>=size-pinnedTail});used+=buf.length;
    for(const [key,value] of cache) {
      if(used<=cap)break;
      if(!value.pinned){cache.delete(key);used-=value.buf.length;}
    }
  }
  function readBlock(start,end,lease) {
    const found=cache.get(start);
    if(found){hits++;cache.delete(start);cache.set(start,found);return Promise.resolve(found.buf);}
    let slot=pending.get(start);
    if(slot){joined++;slot.users++;if(!lease.background)slot.foreground++;} else {
      misses++;slot={users:1,foreground:lease.background ? 0:1,requests:new Set(),promise:null};pending.set(start,slot);
      slot.promise=network.fetch(start,end,req=>{slot.requests.add(req);req.once('close',()=>slot.requests.delete(req));},()=>slot.users===0,()=>slot.foreground===0)
        .then(({buf})=>{if(slot.users>0)retain(start,end,buf);return buf;})
        .finally(()=>{if(pending.get(start)===slot)pending.delete(start);});
    }
    if(!lease.background)network.reprioritize();
    return new Promise((resolve,reject)=>{
      let done=false;
      function finish(err,buf) {
        if(done)return;done=true;lease.removeListener('cancel',cancel);slot.users--;if(!lease.background)slot.foreground--;
        if(slot.users===0) {
          if(pending.get(start)===slot)pending.delete(start);
          for(const req of slot.requests)req.destroy();
        }
        if(err)reject(err);else resolve(buf);
      }
      function cancel(){finish(new Error('downstream closed'));}
      lease.once('cancel',cancel);
      slot.promise.then(buf=>finish(null,buf),err=>finish(err));
      if(lease.cancelled)cancel();
    });
  }
  return {
    async fetch(start,end,track,cancelled=()=>false,background=false) {
      const lease=new EventEmitter();lease.cancelled=false;lease.background=background;
      lease.destroy=()=>{if(!lease.cancelled){lease.cancelled=true;lease.emit('cancel');lease.emit('close');}};
      track(lease);
      try {
        const parts=[];
        for(let offset=start;offset<=end;) {
          if(cancelled() || lease.cancelled)throw new Error('downstream closed');
          const [s,e]=blockAt(offset),buf=await readBlock(s,e,lease),last=Math.min(end,e);
          parts.push(buf.subarray(offset-s,last-s+1));offset=last+1;
        }
        return {buf:parts.length===1 ? parts[0]:Buffer.concat(parts)};
      } finally {lease.emit('close');}
    },
    capacity(){return network.capacity?.() || PLAIN_CONNECTIONS;},
    evidence(){return {cache_bytes:used,cache_limit:cap,cache_hits:hits,coalesced:joined,cache_misses:misses,pending_blocks:pending.size,...network.scheduling()};},
  };
}

async function resolvePlainSource(rawUrl) {
  const agent=agentFor(new URL(rawUrl)), state=plainSourceState(rawUrl,agent);
  const {headers}=await state.fetch(0,0,()=>{});
  const m=/\/(\d+)\s*$/.exec(headers['content-range'] || ''),size=m ? Number(m[1]):NaN;
  if (!Number.isSafeInteger(size) || size<=0) throw new Error('CDN gave no total size for the signed URL');
  state.size=size;
  const cached=cachedPlainSource(state,size);
  let requestID=0;
  return {name:'transfer',size,open(start,end,background=false){
    if(!background)state.foreground(1);
    const stream=parallelStream(cached,start,end,PLAIN_CONNECTIONS,background);
    if(!background)stream.once('close',()=>state.foreground(-1));
    return stream;
  },
    beginRequest(req,res,start,end) {
      const id=++requestID;let served=0,lastProgress=0;
      const ua=String(req.headers['user-agent'] || '').toLowerCase();
      const client=ua.includes('mpv') ? 'mpv':ua.includes('lavf') || ua.includes('ffmpeg') ? 'ffmpeg':ua.includes('curl') ? 'curl':'other';
      console.error('CDN-EVIDENCE:'+JSON.stringify({event:'downstream-open',request_id:id,client,start,end,...cached.evidence()}));
      res.once('close',()=>console.error('CDN-EVIDENCE:'+JSON.stringify({event:'downstream-close',request_id:id,complete:res.writableFinished,served_bytes:served,...cached.evidence()})));
      const evidence=count=>{served+=count;
        if(Date.now()-lastProgress>=5000){lastProgress=Date.now();
          console.error('CDN-EVIDENCE:'+JSON.stringify({event:'downstream-progress',request_id:id,client,
            served_bytes:served,mono_ms:Math.round(performance.now()*1000)/1000,...cached.evidence()}));
        }
      };evidence.background=client==='ffmpeg';return evidence;
    },
  };
}

function parallelStream(source, start, end, conns = PLAIN_CONNECTIONS, background=false) {
  const inflight = new Map();   // chunk index -> { req, buf|null }
  const reqs = new Set();
  let nextOffset = start;       // next byte to schedule
  let nextIndex = 0;            // next chunk index to schedule
  let deliverIndex = 0;         // next chunk index to push
  // A completed out-of-order block must not strand a free network lane.
  // Two windows per live source cap keep skewed completions from emptying
  // the upstream queue. Global permits remain source-owned, maximum12.
  // Probe readers and the opt-in ABBA diagnostic keep their old windows.
  const lookahead = () => foregroundWindow(background ? conns :
    Math.max(conns,Math.min(12,source.capacity?.() || conns)),background);
  let failed = null;
  let destroyed = false;
  let blocked = false, blockedAt=0,blockedMs=0,pushWaits=0;
  const pressure=()=>({local_push_waits:pushWaits,local_push_blocked_ms:Math.round(blockedMs+(blockedAt ? performance.now()-blockedAt:0)),local_readable_bytes:stream.readableLength,local_readable_high_water_mark:stream.readableHighWaterMark});

  const stream = new Readable({
    highWaterMark: 4 * 1024 * 1024,
    read() { if(blockedAt){blockedMs+=performance.now()-blockedAt;blockedAt=0;} blocked = false; pump(); },
    destroy(err, cb) {
      destroyed = true;
      for (const r of reqs) r.destroy();
      reqs.clear(); inflight.clear();
      cb(err);
    },
  });

  function schedule() {
    while (!destroyed && !failed && nextOffset <= end && inflight.size < lookahead()) {
      const idx = nextIndex++;
      const size = idx === 0 ? PLAIN_FIRST_CHUNK : PLAIN_CHUNK;
      const s = nextOffset;
      const e = Math.min(end, s + size - 1);
      nextOffset = e + 1;
      const slot = { buf: null };
      inflight.set(idx, slot);
      const go = () => {
        if (destroyed) return;
        source.fetch(s,e,(r) => {reqs.add(r);r.once('close',()=>reqs.delete(r));},()=>destroyed,background).then(({ buf }) => {
          if (destroyed) return;
          if (buf.length !== e - s + 1) throw new Error(`short chunk ${buf.length}/${e - s + 1}`);
          slot.buf = buf;
          pump();
        }).catch((err) => {
          if (destroyed) return;
          failed = err; stream.destroy(err);
        });
      };
      go();
    }
  }

  function pump() {
    if (destroyed || blocked) return;
    // push strictly in order
    for (;;) {
      const slot = inflight.get(deliverIndex);
      if (!slot || !slot.buf) break;
      inflight.delete(deliverIndex);
      deliverIndex++;
      const more = stream.push(slot.buf);
      slot.buf = null;
      if (!more) { blocked = true; blockedAt=performance.now();pushWaits++;schedule(); return; }
    }
    if (nextOffset > end && inflight.size === 0) { stream.push(null); return; }
    schedule();
  }

  stream.transferPressure=pressure;
  schedule();
  return stream;
}

// ---------------------------------------------------------------
// Resolve the link into { shareURL, wantedHandle }
// ---------------------------------------------------------------
function parseLink(raw, keyField) {
  if (isPlainCdnUrl(raw)) return { shareURL: raw, wantedHandle: '', plain: true };
  if (raw.startsWith('mega-folder::')) {
    const parts = raw.split('::');
    const shareURL = parts[1] || '';
    const handle = parts[2] || '';
    if (!shareURL || !handle) fail(`malformed mega-folder link: ${raw}`);
    return { shareURL, wantedHandle: handle };
  }
  if (raw.includes('mega.nz/file/')) {
    const afterFile = raw.split('mega.nz/file/')[1] || '';
    const handle = afterFile.split('#')[0].split('/')[0];
    if (!handle || !raw.includes('#')) fail(`malformed mega file link: ${raw}`);
    return { shareURL: raw, wantedHandle: handle };
  }
  if (raw.includes('mega.nz/folder/')) {
    // handle comes from the M.d scrape: "<handle>:<b64key>"
    const handle = (keyField || '').split(':')[0];
    if (!handle) fail(`folder link without a file handle (nodeKeyField="${keyField}")`);
    return { shareURL: raw, wantedHandle: handle };
  }
  fail(`unrecognized mega link: ${raw}`);
}

// ---------------------------------------------------------------
// Source abstraction: same shape for the real megajs source and the
// offline fake-file test hook.
//   { name, size, open(start, end) -> Readable }   // end inclusive
// ---------------------------------------------------------------
async function resolveRealSource(shareURL, wantedHandle) {
  const { File } = await import('megajs');
  const root = File.fromURL(shareURL);
  const loaded = await root.loadAttributes();
  // For folder links that point at a specific file (/folder/ID#KEY/file/H),
  // megajs resolves it via loadAttributes' return value; otherwise walk the
  // folder tree for wantedHandle.
  let file = null;
  if (loaded && loaded !== root && loaded.download) {
    file = loaded;
  } else if (wantedHandle && root.children) {
    // Shared-folder children do NOT carry nodeId (it stays undefined); their
    // downloadId is an ARRAY [<shareId>, <nodeHandle>] (verified live against
    // a real public folder share). Logged-in Storage children use nodeId
    // instead. Match both shapes.
    const handleOf = (n) => n.nodeId
      ?? (Array.isArray(n.downloadId) ? n.downloadId[1]
        : (typeof n.downloadId === 'string' ? n.downloadId.split(',')[1] : undefined));
    const stack = [...root.children];
    while (stack.length) {
      const n = stack.pop();
      if (n.children) { stack.push(...n.children); continue; }
      if (handleOf(n) === wantedHandle) { file = n; break; }
    }
  } else if (!root.children) {
    file = root; // single-file link
  }
  if (!file) {
    const known = [];
    const handleOf = (n) => n.nodeId
      ?? (Array.isArray(n.downloadId) ? n.downloadId[1]
        : (typeof n.downloadId === 'string' ? n.downloadId.split(',')[1] : '?'));
    const stack = [...(root.children || [])];
    while (stack.length && known.length < 50) {
      const n = stack.pop();
      if (n.children) { stack.push(...n.children); continue; }
      known.push(handleOf(n));
    }
    fail(`file ${wantedHandle} not found in this mega share (share contains: ${known.join(' ')})`);
  }
  if (typeof file.size !== 'number' || file.size <= 0) fail(`bad size for "${file.name}" (${file.size})`);
  return {
    name: file.name || wantedHandle,
    size: file.size,
    // maxConnections 1, deliberately: only this path wires an AbortController
    // to the stream's close event, so a downstream (mpv) abort stops the CDN
    // fetch immediately instead of letting in-flight chunks write into a
    // destroyed stream. One connection is plenty for playback bitrates.
    open: (start, end) => file.download({ start, end, maxConnections: 1 }),
  };
}

function resolveFakeSource(path) {
  const size = fs.statSync(path).size;
  return {
    name: path.split('/').pop(),
    size,
    open: (start, end) => fs.createReadStream(path, { start, end }),
  };
}

const { shareURL, wantedHandle, plain } = parseLink(link, nodeKeyField || '');
const fakePath = process.env.MEGA_RELAY_FAKE_FILE;
const source = fakePath
  ? resolveFakeSource(fakePath)
  : plain
    ? await resolvePlainSource(shareURL).catch((e) => fail(`transfer.it CDN: ${e.message}`))
    : await resolveRealSource(shareURL, wantedHandle);

// Diagnostic to stdout (ignored by MegaStreamManager, visible in logs);
// stderr is reserved for ERROR: lines, which the app shows on the OSD.
console.log(`note: streaming "${source.name}" (${source.size} bytes)`);

// ---------------------------------------------------------------
// HTTP server: HEAD/GET with Range, 206/200/416, mpv-grade seeking
// ---------------------------------------------------------------
const server = http.createServer((req, res) => {
  try {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405); res.end(); return;
    }
    const size = source.size;
    let start = 0;
    let end = size - 1;
    const range = req.headers.range;
    if (range) {
      const m = /^bytes=(\d+)-(\d*)$/.exec(range);
      if (!m) { res.writeHead(416, { 'Content-Range': `bytes */${size}` }); res.end(); return; }
      start = Number(m[1]);
      end = m[2] ? Number(m[2]) : size - 1;
    }
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) ||
        start >= size || end >= size || start > end) {
      res.writeHead(416, { 'Content-Range': `bytes */${size}` });
      res.end();
      return;
    }

    // Content-Type is a fixed guess; mpv sniffs the real container from
    // the byte stream regardless.
    res.writeHead(range ? 206 : 200, {
      'Content-Type': 'video/mp4',
      'Accept-Ranges': 'bytes',
      'Content-Length': end - start + 1,
      ...(range ? { 'Content-Range': `bytes ${start}-${end}/${size}` } : {}),
    });
    if (req.method === 'HEAD') { res.end(); return; }

    const evidence=source.beginRequest?.(req,res,start,end);
    const body = source.open(start,end,evidence?.background);
    // mpv opens and aborts downstream connections constantly (probing, cache
    // management). An abort is a normal shutdown path, not an error: flag it,
    // kill the upstream pull at once, and keep write-after-destroy noise off
    // the ERROR: channel (every stderr ERROR: line pops the app's OSD).
    let aborted = false;
    const isExpectedShutdown = (e) => aborted || res.destroyed ||
      e.code === 'ERR_STREAM_PREMATURE_CLOSE' || e.code === 'ERR_STREAM_DESTROYED' ||
      (e.message && e.message.includes('write after a stream was destroyed'));
    body.on('error', (e) => {
      if (isExpectedShutdown(e)) {
        console.log(`note: downstream closed mid-stream (${e.message})`);
      } else {
        console.error(`ERROR:source stream error: ${e.message}`);
      }
      res.destroy();
    });
    res.once('close', () => {
      if (res.writableFinished) return; // clean completion, nothing to stop
      aborted = true;
      if (body.pause) body.pause();
      if (body.destroy) body.destroy();
    });
    if(evidence){body.on('data',chunk=>evidence(chunk.length));res.once('close',()=>console.error('CDN-EVIDENCE:'+JSON.stringify({event:'downstream-pressure',...body.transferPressure?.()})));}
    pipeline(body, res, (e) => {
      if (!e) return;
      if (isExpectedShutdown(e)) console.log(`note: pipe closed early (${e.message || e.code})`);
      else console.error(`ERROR:pipe error: ${e.message}`);
    });
  } catch (e) {
    console.error(`ERROR:${e.message}`);
    if (!res.headersSent) res.writeHead(500);
    res.end();
  }
});

server.on('error', (e) => fail(`server error: ${e.message}`));

server.listen(PORT, '127.0.0.1', () => {
  const boundAddress = server.address();
  if (!boundAddress || typeof boundAddress === 'string') return fail('missing bound HTTP port');
  const boundPort = boundAddress.port;
  // Readiness signal — MegaStreamManager.swift watches stdout for this
  // exact prefix. Attributes are already resolved at this point, so a
  // STREAM: line means playback can actually start.
  console.log(`STREAM:http://127.0.0.1:${boundPort}/`);
});

// megajs' single-connection reader chain (body.getReader/read loop) drops the
// rejection when our abort lands mid-read, so an expected shutdown surfaces as
// an unhandled AbortError rejection. Swallow exactly that; anything else is a
// real bug and should still crash loudly.
process.on('unhandledRejection', (e) => {
  if (e && (e.name === 'AbortError' || String(e).includes('aborted'))) {
    console.log('note: upstream fetch aborted on shutdown');
    return;
  }
  throw e;
});

process.on('SIGTERM', () => process.exit(0));
process.on('SIGINT', () => process.exit(0));
