// Runs the real server wire handler and STATS object in a dependency-free VM.
// This is a source-extracted Linux regression, not a real swarm or native test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {EventEmitter} = require('node:events');
const root = path.resolve(__dirname, '../..');
const serverPath = process.env.WT_METRIC_SOURCE || path.join(root, 'Resources/vendor/wt_server/wt_server.mjs');
const server = fs.readFileSync(serverPath, 'utf8');
const swiftPath = process.env.WT_METRIC_SWIFT || path.join(root, 'Sources/gor/TorrentManager.swift');
const swift = fs.readFileSync(swiftPath, 'utf8');
const begin = server.indexOf('let _receivedPayloadBytes = 0;');
const end = server.indexOf("torrent.on('hotswap'", begin);
assert(begin >= 0 && end > begin, 'payload lifetime counter and real wire handler must exist');
const torrent = new EventEmitter();
Object.assign(torrent, {received: 0, downloaded: 0, progress: 0, downloadSpeed: 0, uploadSpeed: 0, numPeers: 2, ratio: 0});
const ctx = vm.createContext({torrent, process: {pid: 7}, Date, WeakMap, Set, Number, cpuPercent: 0, loopLagMs: 0, currentFileLength: 999});
vm.runInContext(server.slice(begin, end), ctx);
const statsStart = server.indexOf('const statsJson = {');
const statsEnd = server.indexOf('\n  };', statsStart);
assert(statsStart >= 0 && statsEnd > statsStart, 'real STATS object must exist');
const sample = () => JSON.parse(vm.runInContext('JSON.stringify((() => {' + server.slice(statsStart, statsEnd + 5) + ';return statsJson})())', ctx));
const wire = () => {const w = new EventEmitter();w.setKeepAlive = () => {};torrent.emit('wire', w);return w;};
const a = wire(); const b = wire();
assert.equal(sample().receivedPayloadBytes, 0);
assert.equal(sample().refetchedBytes, 0);
// Protocol-only socket input is real network traffic, but no film piece arrived.
torrent.received = 300;
assert.equal(sample().receivedPayloadBytes, 0);
assert.equal(sample().receivedTotalBytes, 300);
// Two wires aggregate once; socket total remains independently available.
torrent.received += 16384; a.emit('download', 16384);
torrent.received += 8192; b.emit('download', 8192);
assert.equal(sample().receivedPayloadBytes, 24576);
assert.equal(sample().receivedTotalBytes, 24876);
// Eviction does not lower the session total. Retry/duplicate bytes count as traffic.
torrent.downloaded = 0;
torrent.received += 16384; b.emit('download', 16384);
assert.equal(sample().receivedPayloadBytes, 40960);
assert.equal(sample().downloaded, 0);
for (const bad of [0, -1, NaN, Infinity, 1.5]) a.emit('download', bad);
assert.equal(sample().receivedPayloadBytes, 40960);
a.emit('close');
assert.equal(sample().receivedPayloadBytes, 40960);
// Missing mixed-version payload remains unknown, never raw-socket/resident fallback.
assert(swift.includes('if let received = stats["receivedPayloadBytes"] as? Double,'));
assert(!swift.includes('if let received = stats["receivedTotalBytes"] as? Double,'));
const hud = swift.slice(swift.indexOf('let dlTotalStr: String'), swift.indexOf('let fileLen = stats["fileLength"]'));
assert(hud.includes('dlTotalStr = "unknown"'));
assert(!hud.includes('stats["downloaded"]'));
assert(server.includes('if (_admissionBelowFloor(index, floor - WINDOW_BEHIND, ring))'));
console.log('PASS real extracted wire handler + real STATS: socket-only excluded, two-wire sum, retries retained, eviction monotonic, invalid events refused, close retained; HUD payload/unknown and consumed-prefix guard source contracts');

// Optional actual protocol parser probe. Install is deliberately outside the repo.
if (process.env.WT_PROTOCOL_MODULE) {
  (async () => {
    const {default: Protocol} = await import(process.env.WT_PROTOCOL_MODULE);
    const real = new Protocol();
    real.setKeepAlive = () => {};
    torrent.emit('wire', real);
    const before = sample().receivedPayloadBytes;
    real._onKeepAlive();
    real._onHave(3);
    assert.equal(sample().receivedPayloadBytes, before);
    // Unsolicited/retried piece frames must not be hidden by the metric.
    real._onPiece(3, 0, Buffer.alloc(16384));
    real._onPiece(3, 0, Buffer.alloc(16384));
    assert.equal(sample().receivedPayloadBytes, before + 32768);
    real.destroy();
    console.log('PASS actual upstream bittorrent-protocol: keep-alive/have excluded; unsolicited repeated piece frames included');
  })().catch(err => {console.error(err); process.exitCode = 1;});
}
