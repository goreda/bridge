// Extract G4 matrix metrics from a drive log: bytes in/out, underruns, CPU, peaks.
// v2 (gdb review 2026-11-22): reports PEAK RSS per process, not the final
// sample (v1 kept the last RSS line). Final RSS is still reported, labeled.
// Also surfaces throttle pause/resume-timer counts from drive.mjs v2 logs.
import fs from 'node:fs';
const log = fs.readFileSync(process.argv[2], 'utf8');
const lines = log.split('\n');
let stalls = 0, stallEvents = 0, holderPhases = 0, readBytes = 0, lastPlayerSec = 0, firstDone = null, lastDone = 0, lastDl = 0, maxPending = 0, maxConns = 0, maxConnected = 0, verified = 0, put = 0, playedBytes = 0, cpuU = 0, cpuS = 0, throttlePauses = 0, throttleResumes = 0;
const rssPeak = {}, rssFinal = {};
for (const l of lines) {
  if (l.includes('STALL:')) stalls++;
  if (/STALL: piece=\d+ play=\d+ retry/.test(l)) stallEvents++;
  if (l.includes('STALL:holder')) holderPhases++;
  if (l.startsWith('THROTTLE pause')) throttlePauses++;
  if (l.startsWith('THROTTLE resume-timer')) throttleResumes++;
  const w = l.match(/WINDOW_END readBytes=(\d+)/); if (w) readBytes = +w[1];
  const m = l.match(/REPLAY:pending=(\d+) connected=(\d+) conns=(\d+).*dl=([\d.]+) done=(\d+)(?: cpuUser=([\d.]+) cpuSys=([\d.]+))?/);
  if (m) {
    const pending = +m[1], connected = +m[2], conns = +m[3];
    lastDl = +m[4]; lastDone = +m[5];
    if (firstDone === null) firstDone = lastDone;
    if (pending > maxPending) maxPending = pending;
    if (conns > maxConns) maxConns = conns;
    if (connected > maxConnected) maxConnected = connected;
    if (m[6]) { cpuU = +m[6]; cpuS = +m[7] || 0; }
  }
  const s = l.match(/STORE:(\{.*\})/);
  if (s) { try { const j = JSON.parse(s[1]); verified = j.verifiedCount; put = j.put; lastPlayerSec = j.playerSec || lastPlayerSec; } catch (_) { } }
  const r = l.match(/RSS (\S+) pid=\d+ rssMB=(\d+) user=([\d.]+) sys=([\d.]+)/);
  if (r) {
    const name = r[1], mb = +r[2];
    rssFinal[name] = mb;
    if (!(name in rssPeak) || mb > rssPeak[name]) rssPeak[name] = mb;
    if (name === 'wt_replay.mjs') { cpuU = +r[3]; cpuS = +r[4]; }
  }
}
console.log(JSON.stringify({
  stalls, stallEvents, holderPhases,
  readMB: +(readBytes / 1048576).toFixed(1), playerSec: lastPlayerSec,
  fetchedMB: +(lastDone / 1048576).toFixed(1), verified, put,
  maxPending, maxConns, maxConnected,
  cpuUserS: cpuU, cpuSysS: cpuS,
  engRssPeakMB: rssPeak['wt_replay.mjs'] ?? null,
  engRssFinalMB: rssFinal['wt_replay.mjs'] ?? null,
  rssPeakByProc: rssPeak,
  throttlePauses, throttleResumes,
}));
