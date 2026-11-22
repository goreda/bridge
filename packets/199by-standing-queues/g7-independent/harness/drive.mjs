// G4 actual-archive replay driver v2 (trace demand from /tmp/wt/trace.json,
// media + swarm synthetic local, throttled). One variant per invocation.
// v2 repairs (gdb review 2026-11-22):
//  1. demand throttle budgets REAL chunk sizes (v1 decremented a constant
//     65536 per data event regardless of chunk.length).
//  2. paused responses resume from an INDEPENDENT per-response timer that
//     tops the budget up on a 100ms tick (v1 topped up only inside the data
//     handler, so a paused response never accumulated budget again and sat
//     stalled until the next scheduled range destroyed it).
//  3. THROTTLE pause/resume events are logged as evidence.
//  4. seeder count is a parameter (capacity legs run >16 real wires).
// usage: node drive.mjs <maxConns> <cap30 0|1> <outLogFile> [windowSecs] [nSeeds]
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';

const [maxConns, cap30, outLog, winArg, seedsArg] = process.argv.slice(2);
const WINDOW = parseInt(winArg || '120', 10);
const N_SEEDS = parseInt(seedsArg || '16', 10);
const BITRATE = 9.19e6;              // trace-real bytes/s (archive median)
const FILE_LEN = 97921926465;        // full archive geometry (sparse zeros; hashes valid)
const trace = JSON.parse(fs.readFileSync('/tmp/wt/trace.json', 'utf8'));
const t0 = trace.t0;

const log = fs.createWriteStream(outLog);
const children = [];
function run(name, cmd, args, env) {
  const p = spawn(cmd, args, { env: { ...process.env, ...env }, stdio: ['ignore', 'pipe', 'pipe'] });
  p.stdout.on('data', d => log.write(`[${name}] ` + d.toString().replace(/\n/g, `\n[${name}] `)));
  p.stderr.on('data', d => log.write(`[${name}!] ` + d.toString().replace(/\n/g, `\n[${name}!] `)));
  children.push(p);
  return p;
}
const shutdown = (code) => { for (const p of children) { try { p.kill('SIGINT'); } catch (_) {} } setTimeout(() => process.exit(code), 1500); };
setInterval(() => {
  for (const p of children) {
    try {
      const s = fs.readFileSync(`/proc/${p.pid}/status`, 'utf8');
      const m = s.match(/VmRSS:\s*(\d+) kB/);
      const name = p.spawnargs.find(a => a.includes('/tmp/wt/'))?.split('/').pop() || String(p.pid);
      let cpu = '';
      try {
        const st = fs.readFileSync(`/proc/${p.pid}/stat`, 'utf8');
        const f = st.slice(st.lastIndexOf(')') + 2).split(' ');
        cpu = ` user=${((+f[11]) / 100).toFixed(1)} sys=${((+f[12]) / 100).toFixed(1)}`;
      } catch (_) { }
      log.write(`RSS ${name} pid=${p.pid} rssMB=${m ? (m[1] / 1024).toFixed(0) : '?'}${cpu}\n`);
    } catch (_) { log.write(`RSS pid=${p.pid} DEAD\n`); }
  }
}, 2000);
process.on('SIGINT', () => shutdown(0));
setTimeout(() => shutdown(0), (WINDOW + 45) * 1000);

// 1. blackholes (pending-dial population) + throttled seeder swarm
run('bh', 'node', ['--max-old-space-size=128', '/tmp/wt/blackholes.mjs', '200', '32000', '/tmp/wt/peers_bh.txt']);
run('seed', 'node', ['--max-old-space-size=192', '/tmp/wt/minimal_seed.mjs', String(N_SEEDS), '300', '31000', '/tmp/wt/peers_seed.txt']);

// 2. engine under test
await new Promise(r => setTimeout(r, 12000)); // let swarm seeding come up
const peers = fs.readFileSync('/tmp/wt/peers_seed.txt', 'utf8') + fs.readFileSync('/tmp/wt/peers_bh.txt', 'utf8'); // seeders first so real wires establish; blackholes keep dial queue hot
fs.writeFileSync('/tmp/wt/peers_all.txt', peers);
const eng = run('eng', 'node', ['/tmp/wt/wt_replay.mjs', '2222', '/tmp/wt/media.torrent'], {
  WT_MAX_CONNS: maxConns, WT_CAP30: cap30, WT_CAP30_BPS: String(BITRATE),
  WT_REPLAY_PEERS: '/tmp/wt/peers_all.txt',
});

// 3. wait for the stream token
const token = await new Promise((resolve) => {
  let buf = '';
  eng.stdout.on('data', d => {
    buf += d.toString();
    const m = buf.match(/STREAM:http:\/\/localhost:2222\/\?gor_stream=(\S+)/);
    if (m) resolve(m[1]);
  });
  setTimeout(() => resolve(null), 30000);
});
if (!token) { log.write('NO TOKEN\n'); shutdown(1); await new Promise(() => {}); }
log.write(`TOKEN ${token}\n`);

function postPos(playhead) {
  return new Promise((resolve) => {
    const body = JSON.stringify({ token, playhead });
    const req = http.request({ host: '127.0.0.1', port: 2222, path: '/cmd', method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } },
      res => { res.resume(); res.on('end', resolve); });
    req.on('error', () => resolve());
    req.end(body);
  });
}

// demand: RANGE GETs, throttled consumption at 1.15x bitrate.
// v2 throttle: real chunk sizes against a budget that an independent 100ms
// timer tops up at 1.15x BITRATE; pause at budget<0, resume at budget>=0.
let activeReq = null;
function fireRange(start, end) {
  if (activeReq) { try { activeReq.destroy(); } catch (_) {} activeReq = null; }
  const e = Math.min(end, FILE_LEN - 1);
  if (start >= e) return;
  const req = http.request({ host: '127.0.0.1', port: 2222, path: `/?gor_stream=${token}`,
    headers: { range: `bytes=${start}-${e}` } }, (res) => {
    if (res.statusCode >= 400) { res.resume(); return; }
    let budget = 1048576; // 1MB initial burst allowance
    let paused = false;
    res.on('data', (chunk) => {
      globalThis._readBytes = (globalThis._readBytes || 0) + chunk.length;
      budget -= chunk.length;                     // REAL chunk size, not a constant
      if (budget < 0 && !paused) { paused = true; res.pause(); log.write(`THROTTLE pause budget=${budget.toFixed(0)}\n`); }
    });
    const iv = setInterval(() => {                // independent resume timer
      budget += 0.1 * BITRATE * 1.15;
      if (paused && budget >= 0) { paused = false; log.write(`THROTTLE resume-timer budget=${budget.toFixed(0)}\n`); res.resume(); }
    }, 100);
    res.on('close', () => clearInterval(iv));
    res.on('error', () => clearInterval(iv));
  });
  req.on('error', () => {});
  req.end();
  activeReq = req;
}

// schedule the trace window
for (const [t, ph] of trace.pos.map(x => [x[0], x[1]])) {
  const dt = t - t0;
  if (dt < 2 || dt > WINDOW) continue;
  setTimeout(() => postPos(ph), (dt - 2) * 1000);
}
for (const [t, s, e] of trace.ranges) {
  const dt = t - t0;
  if (dt < 2 || dt > WINDOW) continue;
  setTimeout(() => fireRange(s, e), (dt - 2) * 1000);
}
setTimeout(() => { log.write(`WINDOW_END readBytes=${globalThis._readBytes || 0}\n`); shutdown(0); }, WINDOW * 1000);
