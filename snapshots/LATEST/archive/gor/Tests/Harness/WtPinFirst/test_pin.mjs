// Usage: node wt_pin_first_piece_test.mjs <path/to/wt_server.mjs> [--expect-unpinned]
// Extracts RingBufferStore from the server source (the server has import-time side effects) and runs it with stubs.
import fs from 'node:fs';
import vm from 'node:vm';
const src = fs.readFileSync(process.argv[2], 'utf8');
const expectUnpinned = process.argv.includes('--expect-unpinned');
const a = src.indexOf('class RingBufferStore'), b = src.indexOf('// ─── Global store');
if (a < 0 || b < a) { console.log('FAIL cannot locate RingBufferStore'); process.exit(2); }
// Bind the real retention functions too; WT22.22 added reader-owned retention.
function extractFunction(name) {
  const start=src.indexOf('function '+name+'(');
  if(start<0) throw new Error('missing production retention function: '+name);
  const body=src.indexOf('{',start);let depth=1,i=body+1;
  for(;depth && i<src.length;i++) {if(src[i]==='{')depth++;else if(src[i]==='}')depth--;}
  if(depth)throw new Error('unbalanced retention function: '+name);
  return src.slice(start,i);
}
const retention=extractFunction('readerRetentionPiece')+'\n'+extractFunction('readerOwnedRetentionFloor');
const MB = 1048576, PIECE = 4 * MB;
const code = `
const EVICT_TARGET=0.65, EVICT_TRIGGER=0.68, RAM_CAP_DEFAULT=192*${MB}, RAM_CAP_MIN=192*${MB}, RAM_CAP_MAX=1536*${MB};
const PieceLedger={onPut(){},onEvict(){}}; const pieceFailureTracker={clear(){}}; const _retryPins=new Map();
let _refetchedBytes=0;
const RING_PIN_HEAD=2, RING_PIN_TAIL=3, RING_PIN_MAX=5;
let _torrentGone=true, torrent, totalFileLast=0;
const activePumps=new Map();const READER_FLOOR_STALL_MS=15000;
${retention}
const behindPieces=p=>Math.max(1,Math.ceil(8*${MB}/p));
${src.slice(a, b)}
({Ring: RingBufferStore, pumps:activePumps, readerFloor:readerOwnedRetentionFloor, getRefetched: () => _refetchedBytes});`;
const __vm = vm.runInNewContext(code, { process, Date, Map, Set, Math, Number, setTimeout, clearTimeout });
const Ring = __vm.Ring, getRefetched = __vm.getRefetched;
// An active reader owns its whole open range, not only its current cursor.
const now=Date.now();
__vm.pumps.set(1,{startPiece:4,cursorPiece:20,cursorAt:now,isProbe:false,isAnalysis:false,abortController:{signal:{aborted:false}},response:{destroyed:false}});
if(__vm.readerFloor(50)!==4)throw new Error('reader-owned start not retained');
__vm.pumps.get(1).isAnalysis=true;
if(__vm.readerFloor(50)!==50)throw new Error('analysis reader must not own playback retention');
__vm.pumps.get(1).isAnalysis=false;__vm.pumps.get(1).cursorAt=now-16000;
if(__vm.readerFloor(50)!==50)throw new Error('stale reader must not own playback retention');
__vm.pumps.clear();
console.log('PASS actual reader-owned retention: start/cursor, analysis exclusion and stale reader');
let fails = 0; const ok = (c, m) => { console.log((c ? 'PASS ' : 'FAIL ') + m); if (!c) fails++; };
function fill(pinned) {
  const r = new Ring(PIECE, { length: 1543 * PIECE });
  r.maxBytes = 192 * MB; r._notifyEvicted = () => {};
  if (pinned) r.pinnedFirst = 0;
  for (let i = 0; i < 40; i++) r.put(i, Buffer.alloc(PIECE, i & 255));
  r.put(1542, Buffer.alloc(PIECE, 7));              // tail piece, above any playhead cutoff
  r.setPlayhead(38);                                 // playback far past the header
  r.setPlayhead(45);
  r._evictForPump(46);
  return r;
}
const r = fill(true);
const evicted = [...Array(40).keys()].filter(i => !r.chunks.has(i));
if (expectUnpinned) {
  const u = fill(false);
  ok(!u.chunks.has(0), 'negative control (no pin): piece 0 IS evicted when playback is far past it');
  process.exit(fails ? 1 : 0);
}
ok(r.pinnedFirst === 0, 'ring exposes pinnedFirst=0');
ok(r.chunks.has(0), 'pin: piece 0 survives proactive + pump eviction at play=45');
ok(evicted.length > 0 && evicted.every(i => i > 0 && i < 45 - 2), `other behind-pieces are still evicted (${evicted.length} evicted, first=${evicted[0]})`);
ok(r.chunks.has(1542), 'tail piece 1542 is not evicted (above cutoff)');
let got = null; r.get(0, { offset: 502373, length: 1024 }, (e, buf) => { got = { e, buf }; });
ok(got && !got.e && got.buf && got.buf.length === 1024, 'get(0, offset 502373) served synchronously from RAM');
ok(r.bytes <= r.maxBytes * 0.70, `ram stays near target (${(r.bytes / MB).toFixed(0)}MB of ${r.maxBytes / MB}MB)`);
// v22.19: refetch accounting — evict a piece, put it again, bytes count once.
{
  const q = new Ring(PIECE, { length: 100 * PIECE });
  q.maxBytes = 8 * MB; q._notifyEvicted = () => {};
  q.put(0, Buffer.alloc(PIECE, 1));
  q.setPlayhead(3);                            // cutoff passes piece 0
  q.put(1, Buffer.alloc(PIECE, 2));            // over 68% trigger -> evicts piece 0 (unpinned)
  q.put(2, Buffer.alloc(PIECE, 3));
  const before = getRefetched();
  ok(!q.chunks.has(0) && q._evictedOnce.has(0), 'refetch setup: piece 0 evicted and marked');
  q.maxBytes = 40 * MB;                        // RAM pressure relieved: re-store must not re-evict
  q.put(0, Buffer.alloc(PIECE, 1));            // swarm refetch arrives
  ok(getRefetched() === before + PIECE, `refetchedBytes counts re-stored piece once (+${(getRefetched() - before) / MB}MB)`);
  ok(!q._evictedOnce.has(0), 'refetch mark cleared on re-store');
  const again = getRefetched();
  q.put(0, Buffer.alloc(PIECE, 1));            // duplicate put without eviction: not a refetch
  ok(getRefetched() === again, 'duplicate put without eviction does not count as refetch');
}
// v22.20: moov/header pin — head 2 + tail 3 of the served file survive eviction.
{
  const m = new Ring(PIECE, { length: 1543 * PIECE });
  m.maxBytes = 192 * MB; m._notifyEvicted = () => {};
  m.pinFileEdges(0, 1542);
  ok(m.pinned.size === 5 && m.pinned.has(0) && m.pinned.has(1) && m.pinned.has(1540) && m.pinned.has(1541) && m.pinned.has(1542), 'pin set = head 2 + tail 3 (5 pieces)');
  ok(m.pinned.size <= 5, 'pin ceiling respected (<= 5 pieces = 20MB at 4MiB)');
  for (let i = 0; i < 40; i++) m.put(i, Buffer.alloc(PIECE, i & 255));
  for (let i = 1540; i <= 1542; i++) m.put(i, Buffer.alloc(PIECE, 9));
  m.setPlayhead(38); m.setPlayhead(45);
  m._evictForPump(46);
  ok(m.chunks.has(0) && m.chunks.has(1), 'pinned head pieces 0-1 survive at play=45');
  ok(m.chunks.has(1540) && m.chunks.has(1541) && m.chunks.has(1542), 'pinned moov tail pieces survive');
  // pinned RAM is retained, everything else still evicts to target
  ok(!m.chunks.has(3), 'unpinned behind-piece 3 still evicted (pin does not freeze the ring)');
  // small file clamp + clear on re-pin
  m.pinFileEdges(0, 3);
  ok(m.pinned.size === 4 && !m.pinned.has(1542), 're-pin replaces set; tiny file clamps to span');
  m.pinFileEdges(0, 200);
  ok(m.pinned.size === 5, 'ceiling enforced on wide span (5 max)');
  m.pinFileEdges(NaN, 10);
  ok(m.pinned.size === 0, 'invalid span clears pins');
}
console.log(fails ? `RESULT FAIL ${fails}` : 'RESULT PASS');
process.exit(fails ? 1 : 0);
