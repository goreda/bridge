// Offline test for the transfer.it parallel reader in mega_relay.mjs.
// Fake CDN: Range-capable, throttled PER CONNECTION (like MEGA's CDN).
// Run: node Tests/Harness/MegaRelayParallel/test_plain_relay.mjs (exit 0 = pass)
import http from 'node:http';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const RELAY = process.env.RELAY_PATH || path.join(here, '../../../Resources/vendor/mega_relay/mega_relay.mjs'); // in repo: Tests/Harness/MegaRelayParallel -> ../../../Resources/vendor/mega_relay/mega_relay.mjs
const SIZE = 24 * 1024 * 1024 + 12345;
const PER_CONN_BPS = 1 * 1024 * 1024;           // 1 MiB/s per connection
const data = crypto.randomBytes(SIZE);
let cdnActive = 0, cdnMax = 0, cdnHits = 0, cdnAborted = 0;
let rangeMode = 'ok';                              // 'ok' | 'ignore-range'

const cdn = http.createServer((req, res) => {
  cdnHits++;
  const m = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
  if (!m || rangeMode === 'ignore-range') { res.writeHead(200, { 'Content-Length': SIZE }); res.end(data); return; }
  const s = Number(m[1]); const e = Math.min(SIZE - 1, m[2] ? Number(m[2]) : SIZE - 1);
  res.writeHead(206, { 'Content-Range': `bytes ${rangeMode === 'bad-range' ? s + 1 : s}-${e}/${SIZE}`, 'Content-Length': e - s + 1 });
  cdnActive++; cdnMax = Math.max(cdnMax, cdnActive);
  let off = s; let done = false;
  const finish = () => { if (!done) { done = true; cdnActive--; } };
  res.on('close', () => { if (off <= e) cdnAborted++; finish(); });
  const tick = setInterval(() => {
    if (res.destroyed) { clearInterval(tick); return; }
    const n = Math.min(e + 1 - off, Math.floor(PER_CONN_BPS / 20));
    res.write(data.subarray(off, off + n)); off += n;
    if (off > e) { clearInterval(tick); res.end(); }
  }, 50);
});
await new Promise((r) => cdn.listen(0, '127.0.0.1', r));
const cdnPort = cdn.address().port;

function startRelay(port) {
  return new Promise((resolve, reject) => {
    const p = spawn(process.execPath, [RELAY, String(port), `http://127.0.0.1:${cdnPort}/dl/token`, '', ''],
      { env: { ...process.env, MEGA_RELAY_ALLOW_HTTP_TEST: '1' } });
    let out = '', err = '';
    p.stdout.on('data', (d) => { out += d; if (out.includes('STREAM:')) resolve(p); });
    p.stderr.on('data', (d) => { err += d; process.stderr.write('[relay] ' + d); }); p.stdout.on('data', (d) => process.stderr.write('[relay-out] ' + d));
    p.on('exit', (c) => reject(new Error(`relay exit ${c}: ${err}`)));
  });
}
const get = (port, range) => new Promise((resolve, reject) => {
  const t0 = Date.now(); const parts = [];
  http.get({ host: '127.0.0.1', port, headers: range ? { Range: range } : {} }, (res) => {
    res.on('data', (d) => parts.push(d));
    res.on('end', () => resolve({ status: res.statusCode, buf: Buffer.concat(parts), ms: Date.now() - t0 }));
  }).on('error', reject);
});
let fails = 0;
const check = (name, ok, extra = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${extra}`); if (!ok) fails++; };

// 1. byte-exact sequential read, and faster than one connection would allow
let relay = await startRelay(23301);
const a = await get(23301, 'bytes=0-' + (8 * 1024 * 1024 - 1));
const single = 8; // seconds a single 1 MiB/s connection would need for 8 MiB
check('range 0-8MiB byte-exact', a.status === 206 && a.buf.equals(data.subarray(0, 8 * 1024 * 1024)));
check('8MiB at 1MiB/s/conn is >=3x faster than single connection', a.ms < single * 1000 / 3, `(${a.ms} ms, concurrent=${cdnMax})`);
check('uses several CDN connections but no more than 6', cdnMax >= 3 && cdnMax <= 6, `(max ${cdnMax})`);
// 2. seek into the middle, odd offsets
const b = await get(23301, 'bytes=10000001-12000002');
check('mid-file seek byte-exact', b.status === 206 && b.buf.equals(data.subarray(10000001, 12000003)));
// 3. tail
const c = await get(23301, `bytes=${SIZE - 5000}-`);
check('tail range byte-exact', c.status === 206 && c.buf.equals(data.subarray(SIZE - 5000)));
// 4. out of range -> 416
const d = await get(23301, `bytes=${SIZE}-`);
check('past EOF gives 416', d.status === 416);
// 5. abort mid-stream cancels upstream quickly
const before = cdnAborted;
await new Promise((resolve) => {
  const req = http.get({ host: '127.0.0.1', port: 23301, headers: { Range: 'bytes=0-' } }, (res) => {
    res.once('data', () => { req.destroy(); setTimeout(resolve, 800); });
  });
  req.on('error', () => {});
});
check('abort destroys in-flight CDN requests', cdnAborted > before && cdnActive === 0, `(active ${cdnActive})`);
const afterAbort=await get(23301,'bytes=100-1123');
check('seek after abort has no leaked permits',afterAbort.status===206 && afterAbort.buf.equals(data.subarray(100,1124)));
relay.kill();

// 6. CDN that ignores Range: relay must refuse, never buffer the whole file
rangeMode = 'ignore-range';
let refused = false;
try { await startRelay(23302); } catch (e) { refused = /CDN/.test(e.message); }
check('CDN without Range support is refused, not buffered', refused);
rangeMode = 'bad-range';
refused = false;
try { await startRelay(23303); } catch (e) { refused = /Content-Range/.test(e.message); }
check('CDN with wrong Content-Range is refused', refused);
cdn.close();
process.exit(fails ? 1 : 0);
