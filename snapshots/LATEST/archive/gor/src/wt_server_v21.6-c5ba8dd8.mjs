// wt_server.mjs — WebTorrent HTTP streaming server (magnet → mpv/ffmpeg via HTTP 206 range)
// CURRENT VERSION: 21.6

// INVARIANT
//        - pump must never block forever —
//        - self-resolve via zero-fill/skip.
// DO NOT
//        - touch wire-level timeout/hotswap (WT native handles it)
//        - remove deselect:true (entire selection architecture depends on it)
//        - convert RingBufferStore to disk-backed (RAM-only is intentional)
//        - couple AdaptiveWindow and StallDetector (must stay independent)
//        - reach into WT internals (pieces[], _selections) — public API only

// RULES
//        — on commenting. Hard limits, no exceptions:
//        1.Bump CURRENT VERSION and INIT on every change. Integer = architectural/
//          behavioral; decimal = fix, tweak, or tuning within the same mechanism.
//        2.CHANGELOG entry: exactly ONE line, ~25 words max, "vX.Y — what changed
//          (terse why)". Multiple sub-fixes in one bump = one comma-separated list
//          on that same line, never a numbered sub-list, never multiple lines.
//          No root-cause essay, no repro steps, no "verified by..." paragraph.
//          If it doesn't fit on one line, you're explaining too much — cut it,
//          don't wrap it. Deeper reasoning that truly must survive belongs in the
//          commit message, not here.
//        3.Inline comment: ≤3 lines, current behavior + reason only. Never retell
//          a CHANGELOG entry — point to it: "(see vX.Y)". If an inline comment
//          and its CHANGELOG entry would say the same thing, delete the inline one.
//        4.ONE version-tag format, always: "vX.Y" (e.g. "v18.3"), matching a real
//          CURRENT VERSION bump. No sub-letter/sub-number schemes (no "S12", no
//          "FIX vX #N", no bare "vX" without a decimal). A batch of fixes landing
//          together shares that batch's single vX.Y — don't invent per-fix IDs.
//        5.Unverified claims: say so in ≤5 words ("unverified", "needs real test").
//        6.English only, including inline comments. No exceptions.

// CHANGELOG
//          (newest first):
// v21.5 — sweep probe no longer self-matches (false 2s sweep every boot), SIGTERM-in-bootstrap TDZ crash closed (hoisted declarations).
// v21.6 — stall final-retry reissues the stalled piece: soft-cancel its stranded reservations on all wires (WT hotswap pattern), re-request immediately instead of waiting out WT’s request-timeout cycle.
// v21.4 — wt_full.log mirror on by default (logs drive wt tuning), GOR_WT_FULL_LOG=0 disables.
// v21.3 — caps report moved to REQ: prefix (gor's stdout handler surfaces REQ:; non-JSON STORE: lines are silently dropped).
// v21.2 — storeCacheSlots:0 drops WT's duplicate 20-piece LRU wrapper (ring is the cache); caps log warns if vendored webtorrent lacks _markUnverified.
// v21.1 — verdict recalibrated to the player's clock: ban-informed VERDICT (bans>=2 + fails continue = swarm-corrupt, fires ~fail 6-8 instead of 10+), AdaptiveWindow targets clamped to RAM cap in bytes (was piece-count blind to pieceLen: 8MB pieces drove 544MB through a 396MB cap).
// v21.0 — bad-swarm kit: waiter-piece priority boost, dl-gate patience scales with swarm size, hash-fail wire-ban, VERDICT: line on corrupt-suspect pieces.
// v20.2 — zombie-sweep at startup, DHT decoupled from the 6771 LSD probe, 2222 EADDRINUSE bind-retry, STATS carry session pid, tracker list pruned (4 dead dropped, demonii added).
// v20.1 — trackers re-tiered from a 183-tracker scan: confirmed UDP + 2 WSS in TIER1, HTTP(S) fallbacks in TIER2/3, dead hosts dropped.
// v20.0 — no-SELECT auto-pick gains modes via AUTO_PICK_DEFAULT/WT_AUTO_PICK (0 wait, 1 first playable, 2 random; default 2), replacing WT_AUTO_RANDOM.
// v19.14 — random pick is now opt-in: off unless WT_AUTO_RANDOM=1 (it fired on every multi-file torrent).
// v19.13 — FILES: list capped (huge torrents), random pick when no SELECT: arrives (WT_AUTO_RANDOM=0 disables).
// v19.12 — .torrent path in argv[3] read as Buffer (no &tr= appended), extension-less files servable, audio MIME added.
// v19.11 — torrentPort now probed before use (was hardcoded 51413, which is
//          ALSO Transmission's own default listen port — silent collision
//          when Transmission open, same failure class as 6771/1A). Falls
//          back to a free OS-assigned TCP port if 51413 is occupied.
// v19.10 — lsd gated on _dhtOccupied probe (was static true). Root cause of
//          1A: bittorrent-lsd hardcodes port 6771, same port DHT was being
//          disabled for — LSD kept colliding with Transmission's LSD/DHT
//          even after dht:false, stalling Discovery before tracker announce.
// v19.9  — torrentPort hardcoded to 51413 (was 0 until DHT bound, which
//          never happened with DHT off — Discovery got port:0, no inbound
//          peers); also enables router port-forwarding.
// v19.8  — TIER1 +4 trackers, confirmed live in ngosang/trackerslist AND
//          newtrackon.com independently (the other 26 of 30 existing
//          trackers matched at most one source); +1 WSS tracker per
//          openwebtorrent.com's own recommendation. dl-gate maxWaitMs now
//          floored at the DL_GATE_LOW-derived wait — v19.7's higher global
//          throughput was shrinking expectedMs and therefore the tolerance
//          for a single contested-but-present piece (have>0), the opposite
//          of intent; a faster swarm average doesn't make the specific
//          holder of a stuck piece more likely to send it.
// v19.7  — TIER2/TIER3 tracker gate now peer-count-only (was peer+progress),
//          check 15s→5s; periodic DHT lookup added (was reconnect-only);
//          WAKE 2s→1s; uploads 10→20 — all four under-used available capacity.
// v19.6  — shutdown() now sets _shuttingDown synchronously, checked alongside
//          _torrentGone in updateSlidingWindow's entry guard — covers a tick
//          already in flight when clearInterval can't stop it.
// v19.5  — shutdown() now clears the stall-detection interval (handle was
//          previously uncaptured) before forceDestroyClient, so no tick
//          can hit a torrent mid-destroy.
// v19.4  — updateSlidingWindow now detects a destroyed torrent in its select()
//          catch, sets _torrentGone, and short-circuits further calls instead
//          of retrying the same dead select() forever.
// v19.3  — RESUME now also opens the forward-jump bypass window
//          (_pendingSeekAt), previously only opened by the Range handler's
//          isSeek branch.
// v19.2  — Stall-loop recovery branch now skips while _isUserPaused; only
//          the suppressed-pump branch checked it before, so this one fired
//          every tick during a real pause.
// v19.1  — _notifyEvicted drops the index<=playhead guard; it skipped
//          markUnverified on every normal eviction since _evict()'s cutoff
//          is always behind playhead.
// v19.0  — Pump abort-recovery flag now exempts probes and clears on clean
//          finish (was latching stale), wire-pipeline staleness check
//          hoisted to file scope (was dead code), stdout lines gained
//          HH:MM:SS.mmm timestamps.
// v18.6  — Comment rules tightened (one-line entries, single vX.Y tag, no
//          header/inline duplication); full file reformatted to match. No
//          functional change.
// v18.5  — wt_full.log capture patch moved above INIT; it previously installed
//          ~2400 lines later, so INIT and everything before it reached the
//          terminal but never the log file.
// v18.4  — DHT/Transmission UDP 6771 conflict: catch EADDRINUSE instead of
//          crashing, probe the port via dgram (was wrongly using TCP), moved
//          INIT to the first executable line.
// v18.3  — Explicit PAUSE/RESUME /cmd commands; grace window keeps
//          _lastDlBytes/_lastStalledPiece current; DL-gate/wire-destroy
//          coherence; dead-code and Turkish-comment cleanup.
// v18.2  — Audit cleanup: double-escape fix, dead dht.bootstrap removal,
//          maxBytes race fix, duplicate const removal, multi-video startup fix.
// v18.1  — Pause/resume freeze fixes: grace period skips _reset(), selective
//          destroy also kills idle-unchoked wires, DL-gate on have>0,
//          suppressed-reconnect counter, dead-zone-skip triggers reconnect.
// v18.0  — Swarm reconnect overhaul: removed small-swarm full-reset and
//          maxConns/throttle pulse, added 20s grace window, lsd:true, uploads 10.
// v17.39 — Diagnostic only: RARE_PIECE logs wire choke/unchoke detail;
//          confirmed peersWithPiece ignores wire.peerChoking.
// v17.38 — Merged two parallel v17.34 branches (_notifyEvicted/_markUnverified
//          re-arm; S1-S68 batch); dropped duplicate _selectHighPriority
//          removal, superseded by the S30 item within v17.34.
// v17.37 — _currentVideoIndex=0 fix for first-episode auto-advance, SKIP:0
//          guard, startServer deselect-before-overwrite, incrementSkipStreak().
// v17.36 — CANCEL_ADVANCE stays on current episode; near-end debounce
//          requires 3 consecutive ticks.
// v17.35 — Auto-advance for multi-video torrents: 5s countdown near end,
//          SELECT cancels it, no advance past last episode.
// v17.34 — Batch of ~20 fixes (pump/probe guards, DL-gate hysteresis,
//          dedup-by-bytes, SELECT buffering, orphan-flush protections,
//          throttled announce, WAKE/EPIPE fixes) — see inline "(see v17.34)".
// v17.33 — currentPlayPiece clamps to totalFileLast; a failed select() leaves
//          currentWindow unchanged instead of committing a broken state.
// v17.32 — DL-gate: stall detector defers zero-fill while downloadSpeed≥
//          512KB/s and peers have the piece, capped at 4x expected transfer time.
// v17.31 — fileFirst piece (holds the EBML header) protected from skip/
//          zero-fill at all six call sites.
// v17.30 — Dead-zone-skip anchor uses Math.min when piece<currentPlayPiece
//          (was always Math.max, never triggered in the common case).
// v17.29 — AdaptiveWindow no longer sampled during orphan-flush iterations
//          (was shrinking the window 50→30 over a flush chain).
// v17.28 — Dead-zone-skip: streak resets only on stalled-piece arrival; gate
//          no longer requires piece≥currentPlayPiece.
// v17.27 — Orphan-flush now drives the skip streak and resets stall state;
//          pump-abort recovery via PUMP_ABORT_RECOVERY_MS; ring.setMaxBytes
//          moved earlier; tracker.update()→announce().
// v17.26 — Dead-zone block-skip: streak≥5 jumps WINDOW_AHEAD_MIN pieces at
//          once, flushes waiters, resets streak.
// v17.25 — dlMoved requires waitedPieces[0] to change, not just the global
//          torrent.downloaded counter.
// v17.24 — abortCtrl gets a synchronous 'abort' listener; the signal alone
//          wasn't observed by all-RAM-cache pumps.
// v17.23 — Seek bypass uses a timestamp window instead of a single-use flag;
//          abort signal early-exits the zero-fill path.
// v17.22 — Seek rewrite: _pendingSeekPiece bypass flag, immediate abort on
//          old-region pumps, debounce reset, widened waiter-flush/isSeekBack.
// v17.21 — Forward-jump streak anchor slides per-sample; window-thrash
//          debounce 1.5s; in-window hash-fail tracked; selective wire destroy
//          at ≥50 wires.
// v17.20 — GUARD interval aborts the pump before deleting an expired entry;
//          added a pre-waitForPiece heartbeat.
// v17.19 — POS_FORWARD_JUMP_SECS 30→60.
// v17.18 — _evict() ahead-cap removed; forward-jump streak-of-3 accepted as
//          real position (superseded by v17.21's sliding anchor).
// v17.16 — Fixed double-escaped \n in 9 stdout.write calls inside
//          triggerSwarmReconnect (log readability only).
// v17.15 — dht.bootstrap?.() (nonexistent method) replaced with dht.lookup();
//          forceDestroyClient() adds a 5s watchdog around client.destroy().
// v17.14 — Removed DHT destroy+restart from reconnect (closed-socket
//          .address() access crashed the process); kept bootstrap()-only retry.
// v17.13 — computeAdaptiveParams() derives RAM_CAP/WINDOW_AHEAD_MAX/demuxer-
//          bytes/cache-secs from metadata instead of fixed 3GB-tuned constants.
// v17.12 — Forward-jump filter no longer poisons lastMpvPosSec; SWARM:reconnect
//          triggers on dl<50KB/s instead of dl=0.
// v17.11 — applyMpvPosition forward-jump filter (POS_FORWARD_JUMP_SECS=30)
//          for Swift IPC's interleaved Tip-A/Tip-B position streams.
// v17.10 — SWARM:reconnect mechanism: dl=0 for 60s+ destroys wires, cycles
//          maxConns, restarts DHT, adds trackers, bursts WAKE.
// v17.09 — 30-min-freeze fixes: MPV_POS_STALE_MS 12s→5s, stale-recovery
//          reselects window, PLAYER:stalled flushes+reselects, REFRESH always
//          updates window, suppressed during active pump.
// v17.08 — SKIP/REWINDOW/REFRESH call applyMpvPosition before touching window
//          state; gate widened to lastMpvPosAt>0 (was excluding the stalled case).
// v17.07 — Extended STORE/monitor logging (playerSec, aheadSec, dlGap,
//          pumpActive, evictRate, POS:received).
// v17.05 — uncaughtException EPIPE handler calls process.exit(0), preventing a
//          zombie retry loop.
// v17.04 — Backward-pull branch now only fires on genuine seek-back (seconds
//          decreasing), not on monotonic /pos lag.
// v17.03 — WAKE interval 30s→2s, merged with synthetic-unchoke (public
//          wire.emit, replacing a private API call); removed final-deselect.
// v17.02 — GUARD:leaked fixed via pump heartbeat every 10 pieces; pre-check
//          skips already-failed pieces before waitForPiece.
// v17.01 — isFullFileRequest no longer calls res.destroy(); sends a capped
//          real 206 response instead (mpv requires a real probe response).
// v17.00 — Removed dead isHeadProbe branch; AdaptiveStallDetector tracks
//          auto-skip streaks; DESELECT_ORPHAN_HASHFAIL enabled; PieceFailure-
//          Tracker split into clear()/clearTimeoutOnly().
// v16.03 — Reverted v16.2 (Content-Length lied about body size, hung mpv at
//          play=0).
// v16.02 — [reverted] fullfile gate made state-independent, idle→header-only.
// v16.01 — Fixed StreamSession generation-leak (begin() was outside try{}).
// v16.00 — Replaced activeStreams counter with StreamSession (generation-set);
//          PIECE_TIMEOUT_MIN floor raised to WT's wire timeout + margin.
// v15.00 — Baseline: RingBufferStore, PieceFailureTracker, AdaptiveWindow,
//          AdaptiveStallDetector, zero-fill-on-failure, restartWaiter.

// KNOWN OPEN ITEMS:
//        - None. All previously listed items resolved across v17.8–v18.6.
//          See individual version entries for details.

import http from 'http';
import net from 'net';
import fs from 'fs';
import path from 'path';
import dgram from 'dgram';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

// wt_full.log mirror must install before INIT writes, or earlier output
// reaches the terminal but never the log file (see v18.5).
const FULL_LOG_PATH = '/tmp/wt_full.log';
// Production stdout is the Swift protocol. Disk mirroring is diagnostics only.
// v21.4: mirror on by default; GOR_WT_FULL_LOG=0 disables.
const mirrorLog = process.env.GOR_WT_FULL_LOG !== '0';
if (mirrorLog) { try { fs.writeFileSync(FULL_LOG_PATH, ''); } catch (_) { } }
const origStdoutWrite = process.stdout.write.bind(process.stdout);
const hasTimestamp = /^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\] /;

process.stdout.write = function (chunk, encoding, cb) {
  const timestamp = new Date().toISOString();
  let str = typeof chunk === 'string' ? chunk : chunk.toString();

  const prefixed = str.split('\n').map(line => {
    if (!line) return line; // Skip empty lines (preserves newlines without adding timestamps)
    if (hasTimestamp.test(line)) return line; // Skip if already timestamped
    return `[${timestamp}] ${line}`;
  }).join('\n');

  if (mirrorLog) fs.appendFile(FULL_LOG_PATH, prefixed, () => {});
  return origStdoutWrite(chunk, encoding, cb);
};

// INIT must be the first line of output — any later anchor risks silently
// dropping earlier lines from log capture (see v18.4). DO NOT FORGET TO UPDATE HERE IN EACH VERSION!!!
process.stdout.write("INIT:v21.6 — stall final-retry reissue of stranded piece requests\n");

// ─── Arguments ────────────────────────────────────────────────────
const port = parseInt(process.argv[2]) || 2222;
const magnet = process.argv[3];
if (!magnet) { process.stderr.write('ERROR: magnet required\n'); process.exit(1); }

const __dir = path.dirname(fileURLToPath(import.meta.url));
const wtPath = path.join(__dir, '..', 'webtorrent-cli', 'node_modules', 'webtorrent', 'index.js');
const { default: WebTorrent } = await import(wtPath);

// ─── Tmp dir ──────────────────────────────────────────────────────
const tmpDir = `/tmp/wt_${process.pid}`;
fs.mkdirSync(tmpDir, { recursive: true });

// v20.2: reap wt_server processes orphaned by a crashed gor — they still own
// 2222/51413/6771 and poison every probe below. gor's swap pkill only covers
// the graceful path; this covers the crash path. Own pid excluded.
{
  const myPid = process.pid;
  const zombiePids = () => {
    try {
      // v21.5: strict pattern — the loose 'wt_server.mjs' matched this probe's
      // own sh -c wrapper: false 2s sweep every boot, real zombies masked.
      return execSync("pgrep -f 'node .*wt_server\\.mjs' || true", { encoding: 'utf8' })
        .split('\n').map(x => parseInt(x.trim(), 10))
        .filter(x => Number.isInteger(x) && x > 0 && x !== myPid);
    } catch (_) { return []; }
  };
  if (zombiePids().length) {
    process.stdout.write(`STARTUP:zombie-sweep pids=${zombiePids().join(',')}\n`);
    for (const z of zombiePids()) { try { process.kill(z, 'SIGTERM'); } catch (_) { } }
    const grace = Date.now() + 2000;
    const spin = new Int32Array(new SharedArrayBuffer(4));
    while (Date.now() < grace && zombiePids().length) Atomics.wait(spin, 0, 0, 100);
    for (const z of zombiePids()) { try { process.kill(z, 'SIGKILL'); } catch (_) { } }
  }
}

// ─── Clean exit ───────────────────────────────────────────────────
// Watchdog around client.destroy(cb): if any sub-task in WT's parallel
// destroy chain never calls back, force-exit instead of zombieing (see v17.15).
const FORCE_EXIT_MS = 5_000;
function forceDestroyClient(onDone) {
  let done = false;
  const finish = () => { if (done) return; done = true; onDone(); };
  const watchdog = setTimeout(() => {
    process.stdout.write('SHUTDOWN:client.destroy callback never fired — force exit\n');
    finish();
  }, FORCE_EXIT_MS);
  if (watchdog.unref) watchdog.unref();
  try {
    client.destroy(() => { clearTimeout(watchdog); finish(); });
  } catch (_) { clearTimeout(watchdog); finish(); }
}

// v21.5: hoisted above the SIGTERM registration — a swap SIGTERM landing
// mid-bootstrap previously hit the TDZ on these and crashed the handler
// (ReferenceError) instead of shutting down.
let _shuttingDown = false;
let _stallIntervalHandle = null;

const shutdown = () => {
  // v19.6: set before anything else — synchronous, so any tick already
  // in flight when this runs sees it on its next updateSlidingWindow call,
  // even though client.destroy() below is async and torrent.destroyed
  // (v19.4's flag) won't flip until it actually completes.
  _shuttingDown = true;
  process.stdout.write('SHUTDOWN\n');
  // v19.5: stop the stall-detection loop before destroying the client —
  // otherwise the next tick can call torrent.select()/applyMpvPosition
  // against a torrent that's mid-destroy or already gone.
  if (_stallIntervalHandle) clearInterval(_stallIntervalHandle);
  forceDestroyClient(() => {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) { }
    process.exit(0);
  });
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
process.on('exit', () => {
  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) { }
});

// v17.5: EPIPE on stdout when downstream (gor) closes. logging it to stdout
// re-triggers EPIPE, creating a zombie loop. EPIPE now exits cleanly; other
// errors log normally (safe as long as stdout is open).
function isEpipe(err) {
  return err && (err.code === 'EPIPE' || /EPIPE/.test(err?.message || ''));
}

// One-shot flag prevents re-entrant EPIPE: client.destroy() inside
// forceDestroyClient calls monkeypatched stdout.write, which can re-trigger
// a second uncaughtException (see v17.34).
let _epipeHandled = false;
process.on('uncaughtException', err => {
  if (isEpipe(err)) {
    if (_epipeHandled) return;
    _epipeHandled = true;
    try { process.stderr.write('FATAL:EPIPE downstream-closed — exiting\n'); } catch (_) { }
    try { forceDestroyClient(() => process.exit(0)); } catch (_) { process.exit(0); }
    return;
  }
  try { process.stdout.write(`FATAL:uncaughtException ${err?.stack || err?.message || err}\n`); } catch (_) { }
});
process.on('unhandledRejection', reason => {
  if (isEpipe(reason)) {
    if (_epipeHandled) return;
    _epipeHandled = true;
    try { process.stderr.write('FATAL:EPIPE downstream-closed — exiting\n'); } catch (_) { }
    try { forceDestroyClient(() => process.exit(0)); } catch (_) { process.exit(0); }
    return;
  }
  try { process.stdout.write(`FATAL:unhandledRejection ${reason?.stack || reason?.message || reason}\n`); } catch (_) { }
});

// ─── Trackers ─────────────────────────────────────────────────────
// TIER1 rides in every magnet: ngosang best (daily-tested) AND a 3-round scan, one host per IP.
// WSS is WebTorrent-only infra, verified via the operator's own page (upstream lists skip it).
const TIER1 = [
  'udp://tracker.ducks.party:1984/announce',
  'udp://tracker.nyaa.vc:6969/announce',
  'udp://tracker.opentrackr.org:1337/announce',
  'udp://tracker.qu.ax:6969/announce',
  'udp://tracker-udp.gbitt.info:80/announce',
  'udp://tracker.torrent.eu.org:451/announce',
  'udp://open.stealth.si:80/announce',
  'udp://retracker01-msk-virt.corbina.net:80/announce',
  'udp://tracker.bittor.pw:1337/announce',
  'udp://exodus.desync.com:6969/announce',
  'udp://explodie.org:6969/announce',
  'udp://t.overflow.biz:6969/announce',
  'udp://tracker.dler.org:6969/announce',
  'udp://open.demonii.com:1337/announce',
  'wss://tracker.openwebtorrent.com',
  'wss://tracker.webtorrent.dev',
];
// Injected on stall; HTTP(S) entries keep a UDP-blocked network supplied with trackers.
const TIER2 = [
  'udp://tracker.nyaa.net:6969/announce',
  'udp://martin-gebhardt.eu:25/announce',
  'udp://tracker.teambelgium.net:6969/announce',
  'udp://torrent.tracker.durukanbal.com:6969/announce',
  'udp://ipv4announce.sktorrent.eu:6969/announce',
  'udp://tracker.peerfect.org:6969/announce',
  'udp://mail.segso.net:6969/announce',
  'udp://tracker.ilibr.org:6969/announce',
  'udp://tracker.opentrackr.com:6969/announce',
  'http://tracker.renfei.net:8080/announce',
  'http://tracker.mywaifu.best:6969/announce',
  'http://bittorrent-tracker.e-n-c-r-y-p-t.net:1337/announce',
];
// Last resort: fast in one scan run only, not confirmed by ngosang/XIU2 best.
const TIER3 = [
  'udp://tracker.tryhackx.org:6969/announce',
  'udp://tracker.torrents.observer:80/announce',
  'udp://opentracker.lain.moscow:6969/announce',
  'udp://tr3.ysagin.top:2715/announce',
  'udp://rekcart.duckdns.org:15480/announce',
  'udp://tracker.orsvarn.com:6969/announce',
  'udp://yuptracker-eu.gaijinent.com:27022/announce',
  'udp://tracker.ddunlimited.net:6969/announce',
  'http://nyaa.tracker.wf:7777/announce',
  'https://1.tracker.eu.org:443/announce',
];

// A .torrent path is read as a Buffer; appending &tr= to a path corrupts it and
// parse-torrent's fs.readFile fallback then fails without surfacing an error.
let src;
if (/^magnet:/i.test(magnet)) {
  src = magnet;
  if (!src.includes('&tr=')) {
    src += TIER1.map(t => '&tr=' + encodeURIComponent(t)).join('');
  }
} else if (fs.existsSync(magnet)) {
  try { src = fs.readFileSync(magnet); }
  catch (e) { process.stderr.write(`ERROR: cannot read torrent file: ${e.message}\n`); process.exit(1); }
} else {
  process.stderr.write(`ERROR: argv[3] is neither a magnet URI nor an existing file: ${magnet}\n`);
  process.exit(1);
}

// ─── Constants ────────────────────────────────────────────────────
// RAM_CAP_DEFAULT/WINDOW_AHEAD_MAX are `let`: computeAdaptiveParams()
// recomputes them from metadata at runtime (see v17.13).
let RAM_CAP_DEFAULT = 320 * 1024 * 1024;
const RAM_CAP_MAX = 1536 * 1024 * 1024;
const RAM_CAP_MIN = 192 * 1024 * 1024;
const EVICT_TARGET = 0.65;
const EVICT_TRIGGER = 0.68;

// Adaptive window bounds
const WINDOW_AHEAD_MIN = 20;
let WINDOW_AHEAD_MAX = 120;
const WINDOW_AHEAD_DEFAULT = 60;
const WINDOW_BEHIND = 8;
// v17.13: cap on WINDOW_AHEAD_MAX from computeAdaptiveParams() — prevents
// piece-count explosion on very small pieceLen (e.g. 256K).
const WINDOW_AHEAD_MAX_CAP = 300;
// LOOKAHEAD now feeds priority selection, not critical() (see v15.0).
const LOOKAHEAD = 5;
const RESELECT_STRIDE = 3;
// Streak threshold before dead-zone-skip jumps WINDOW_AHEAD_MIN pieces at
// once instead of one piece at a time (see v17.26).
const DEAD_ZONE_SKIP_STREAK = 5;

// WT's own wire-level piece timeout is a hardcoded 30s; PIECE_TIMEOUT_MIN
// must stay above it or we zero-fill before WT's own retry finishes
// (v15.0 set this to 8s, wrong; floor raised in v16.0).
const WT_WIRE_TIMEOUT_MS = 30_000;
const PIECE_TIMEOUT_BASE = 60_000;
const PIECE_TIMEOUT_STALL = 15_000;
const PIECE_TIMEOUT_MIN = WT_WIRE_TIMEOUT_MS + 5_000; // 35_000


const STALL_CHECK_MS = 3_000;
const STALL_THRESHOLD_MS = 6_000;
const STALL_MAX_RETRIES = 2;
// Hysteresis pair replaces a single DL_GATE_BYTES_PER_SEC threshold — a
// hard edge caused zero-fill/defer flips on small speed noise (see v17.34).
const DL_GATE_HIGH = 600 * 1024; // enter gate: clearly healthy swarm
const DL_GATE_LOW = 400 * 1024; // exit gate: clearly dead/slow swarm
// Maximum time to extend the wait when DL_GATE is active, expressed as a
// multiplier of the expected piece transfer time. Beyond this the piece is
// assumed lost despite healthy global speed (peer has it but won't send it).
const DL_GATE_TIMEOUT_MULTIPLIER = 4;

const MAX_CONCURRENT_PUMPS = 10;
// DEDUP_RADIUS was a fixed 4-piece constant — 64MB on 16MB pieces,
// swallowing legitimate seeks. Bytes-based + dedupRadius() keeps this
// constant regardless of piece size (see v17.34).
const DEDUP_BYTES = 4 * 1024 * 1024;
// Active pump lifetime, not request age, now owns deduplication.
const MOOV_TAIL_PIECES = 80;
// Fullfile probe response caps at this many pieces past startPiece —
// enough for mpv's format probe without pumping the whole file (see v17.1).
const FULLFILE_PROBE_CAP_PIECES = 5;

// Failure count threshold that triggers zero-fill (not skip).
const PIECE_FAIL_THRESHOLD = 2;
// Raised to 300s so the failure count survives mpv's disconnect/reconnect
// cycles without a restart (see v15.0).
const PIECE_FAIL_RESET_MS = 300_000;

// Frozen-pipeline detection: WT's pipeline minimum is 2 requests at dl=0;
// if those 2 stay stuck, no new piece gets picked. This long with no
// change in total wire requests triggers a synthetic unchoke (see v15.0).
const PIPELINE_FROZEN_MS = 15_000;

// Pre-buffer full but dl=0 → window-advance threshold (see v15.0).
const PREBUFFER_FILL_RATIO = 0.85;
const PREBUFFER_STALL_MS = 8_000;

// Threshold for the IPC forward-jump filter: Swift sends interleaved
// normal-poll and buffer-echo position streams, and naively trusting both
// thrashes the window every ~2s (see v17.11).
const POS_FORWARD_JUMP_SECS = 30;

// Window now sized by bytes, not piece count — old fixed constants choked
// on a 98GB remux's large pieceLen (see v17.13). Duration unused here:
// lastKnownDuration=0 at metadata time.
const TARGET_AHEAD_BYTES = 128 * 1024 * 1024; // at pieceLen=1MB → 128 pieces ahead (close to old value of 120)
const RAM_CAP_MARGIN = 1.15;              // eviction headroom
const DEMUX_BYTES_MIN = 500 * 1024 * 1024; // old fixed value kept as a baseline floor
const DEMUX_BYTES_MAX = 2048 * 1024 * 1024;
const DEMUX_RAM_MULTIPLIER = 1.5;               // mpv's own buffer should be slightly larger than RAM_CAP

function computeAdaptiveParams(pieceLen, totalPieces, fileLength) {
  if (!pieceLen || pieceLen <= 0) {
    // Bad metadata falls back to fixed defaults — never produces NaN.
    return {
      ramCap: RAM_CAP_DEFAULT, windowAheadMax: WINDOW_AHEAD_DEFAULT,
      demuxerMaxBytes: DEMUX_BYTES_MIN, cacheSecs: 30,
    };
  }

  let windowAheadMax = Math.round(TARGET_AHEAD_BYTES / pieceLen);
  windowAheadMax = Math.max(WINDOW_AHEAD_MIN, Math.min(windowAheadMax, WINDOW_AHEAD_MAX_CAP));

  const windowBytes = (WINDOW_BEHIND + windowAheadMax) * pieceLen;
  let ramCap = (windowBytes / EVICT_TARGET) * RAM_CAP_MARGIN;
  ramCap = Math.max(RAM_CAP_MIN, Math.min(ramCap, RAM_CAP_MAX));

  const demuxerMaxBytes = Math.max(DEMUX_BYTES_MIN, Math.min(ramCap * DEMUX_RAM_MULTIPLIER, DEMUX_BYTES_MAX));

  const GB = 1024 ** 3;
  const cacheSecs = fileLength < 5 * GB ? 30 : fileLength < 30 * GB ? 45 : 60;

  return { ramCap, windowAheadMax, demuxerMaxBytes, cacheSecs };
}

// StreamSession: generation-set state machine, replaces the old
// activeStreams counter to close a pump-teardown/next-request race
// (see v16.0, v16.1).
class StreamSession {
  constructor() {
    this._phase = 'idle'; // 'idle' | 'streaming'
    this._generation = 0;
    this._activeGens = new Set();
  }

  get phase() { return this._phase; }
  get count() { return this._activeGens.size; }

  begin() { // call when a pump starts; returns this pump's generation id
    const gen = ++this._generation;
    this._activeGens.add(gen);
    this._phase = 'streaming';
    return gen;
  }

  end(gen) { // call in pump's finally; only retires caller's own generation
    this._activeGens.delete(gen);
    if (this._activeGens.size === 0) this._phase = 'idle';
  }

  isStreaming() { return this._phase === 'streaming'; }

  forceReset() { // leaked-generation cleanup, paired with GUARD interval below
    this._activeGens.clear();
    this._phase = 'idle';
  }
}

const streamSession = new StreamSession();

// RingBufferStore — RAM-only chunk store.
// restartWaiter(index): on hash-fail WT skips store.put() (emits 'warning'
// only), so a waiter would hang forever. This renews the wait timeout
// without resolving/flushing — WT retries, we keep waiting (see v15.0).
class RingBufferStore {
  constructor(chunkLength, opts) {
    this.chunkLength = chunkLength;
    this.length = (opts && typeof opts === 'object') ? opts.length : opts;
    this.chunks = new Map();
    this.bytes = 0;
    this.maxBytes = RAM_CAP_DEFAULT;
    this.closed = false;
    this.totalPut = 0;
    this.totalEvicted = 0;
    this._playhead = 0;
    this._waiters = new Map();
  }

  setMaxBytes(n) {
    this.maxBytes = Math.max(RAM_CAP_MIN, Math.min(n, RAM_CAP_MAX));
    this._evict();
  }

  setPlayhead(pieceIndex) {
    this._playhead = pieceIndex;
    this._evict();
  }

  put(index, buf, cb) {
    if (this.closed) return cb && cb(null);
    if (this.chunks.has(index)) this.bytes -= this.chunks.get(index).length;
    else this.totalPut++;
    this.chunks.set(index, buf);
    this.bytes += buf.length;
    this._evict();
    cb && cb(null);

    try { pieceFailureTracker.clear(index); } catch (_) { }

    const waiters = this._waiters.get(index);
    if (waiters?.length) {
      const list = waiters.splice(0);
      this._waiters.delete(index);
      const stored = this.chunks.get(index) ?? buf;
      for (const { resolve, timer, onAbort, signal } of list) {
        clearTimeout(timer);
        if (signal && onAbort) signal.removeEventListener('abort', onAbort);
        resolve(stored);
      }
    }
  }

  get(index, opts, cb) {
    if (typeof opts === 'function') { cb = opts; opts = {}; }
    if (this.closed) return cb(new Error('store closed'));
    const buf = this.chunks.get(index);
    if (buf) {
      const o = opts?.offset || 0;
      const l = opts?.length != null ? opts.length : buf.length;
      return cb(null, buf.slice(o, o + l));
    }
    cb(new Error(`piece ${index} not in store`));
  }

  forceSkip(index) {
    const waiters = this._waiters.get(index);
    if (!waiters?.length) return false;
    const list = waiters.splice(0);
    this._waiters.delete(index);
    for (const { resolve, timer, onAbort, signal } of list) {
      clearTimeout(timer);
      if (signal && onAbort) signal.removeEventListener('abort', onAbort);
      resolve(null);
    }
    return true;
  }

  // On hash-fail, don't flush the waiter — renew its timeout instead. WT
  // retries the request; store.put() resolves the waiter normally when it
  // lands (see v15.0). `ms` is typically the current PIECE_TIMEOUT value.
  restartWaiter(index, ms) {
    const waiters = this._waiters.get(index);
    if (!waiters?.length) return false;
    const now = Date.now();
    for (const entry of waiters) {
      clearTimeout(entry.timer);
      entry.timer = setTimeout(() => {
        const list = this._waiters.get(index);
        if (list) {
          const i = list.indexOf(entry);
          if (i >= 0) list.splice(i, 1);
          if (!list.length) this._waiters.delete(index);
        }
        entry.resolve(null);
      }, ms);
      entry.startTime = now; // reset for stuck-waiter detection
    }
    return true;
  }

  waitForPiece(index, ms, signal = null) {
    if (this.chunks.has(index)) return Promise.resolve(this.chunks.get(index));
    if (this.closed) return Promise.resolve(null);

    this._evictForPump(index);

    return new Promise(resolve => {
      let timer, onAbort;

      const cleanup = () => {
        clearTimeout(timer);
        if (signal && onAbort) signal.removeEventListener('abort', onAbort);
        const list = this._waiters.get(index);
        if (list) {
          const i = list.findIndex(w => w.resolve === resolve);
          if (i >= 0) list.splice(i, 1);
          if (!list.length) this._waiters.delete(index);
        }
      };

      timer = setTimeout(() => { cleanup(); resolve(null); }, ms);

      if (signal) {
        if (signal.aborted) { clearTimeout(timer); return resolve(null); }
        onAbort = () => { cleanup(); resolve(null); };
        signal.addEventListener('abort', onAbort);
      }

      if (!this._waiters.has(index)) this._waiters.set(index, []);
      const entry = { resolve, timer, onAbort, signal, startTime: Date.now() };
      this._waiters.get(index).push(entry);
      try { _boostWaiterPiece(index); } catch (_) { }
    });
  }

  // RAM eviction doesn't update WT's bitfield, so WT believes it still
  // "has" the piece and never re-requests it. Unconditional now — any
  // evicted piece needs this, not just ones ahead of playhead (see v19.1).
  _notifyEvicted(index) {
    try {
      if (typeof torrent !== 'undefined' && torrent && !torrent.destroyed &&
        typeof torrent._markUnverified === 'function' &&
        torrent.bitfield && torrent.bitfield.get(index)) {
        torrent._markUnverified(index);
      }
    } catch (e) {
      process.stdout.write(`EVICT:markUnverified-failed piece=${index} err=${e?.message || e}\n`);
    }
  }

  _evictForPump(neededIndex) {
    if (this.bytes < this.maxBytes * 0.85) return;
    const target = this.maxBytes * EVICT_TARGET;
    for (const [idx, buf] of this.chunks) {
      if (this.bytes <= target) break;
      if (idx >= neededIndex - WINDOW_BEHIND) continue;
      this.chunks.delete(idx);
      this.bytes -= buf.length;
      this.totalEvicted++;
      this._notifyEvicted(idx);
    }
    if (this.bytes > target) {
      for (const [idx, buf] of this.chunks) {
        if (this.bytes <= target) break;
        if (idx >= neededIndex) continue;
        this.chunks.delete(idx);
        this.bytes -= buf.length;
        this.totalEvicted++;
        this._notifyEvicted(idx);
      }
    }
  }

  _evict() {
    if (this.bytes <= this.maxBytes * EVICT_TRIGGER) return;
    const before = this.bytes;
    const target = this.maxBytes * EVICT_TARGET;
    const cutoff = this._playhead - WINDOW_BEHIND;
    let removed = 0;
    for (const [idx, buf] of this.chunks) {
      if (this.bytes <= target) break;
      if (idx >= cutoff) continue;
      this.chunks.delete(idx);
      this.bytes -= buf.length;
      this.totalEvicted++;
      removed++;
      this._notifyEvicted(idx);
    }
    if (removed > 0) {
      process.stdout.write(
        `EVICT:proactive removed=${removed} freedMB=${((before - this.bytes) / 1_048_576).toFixed(1)} ` +
        `ram=${(this.bytes / this.maxBytes * 100).toFixed(0)}% play=${this._playhead}\n`
      );
    }
  }

  get waiterCount() {
    let n = 0;
    for (const list of this._waiters.values()) n += list.length;
    return n;
  }

  get waitedPieces() {
    return [...this._waiters.keys()];
  }

  close(cb) {
    this.closed = true;
    for (const waiters of this._waiters.values()) {
      for (const { resolve, timer, onAbort, signal } of waiters) {
        clearTimeout(timer);
        if (signal && onAbort) signal.removeEventListener('abort', onAbort);
        resolve(null);
      }
    }
    this._waiters.clear();
    this.chunks.clear();
    this.bytes = 0;
    cb && cb(null);
  }

  destroy(cb) { this.close(cb); }
}

// ─── Global store ─────────────────────────────────────────────────
let globalRing = null;
const getRing = () => globalRing;

class RingStoreFactory {
  constructor(chunkLength, opts) {
    if (!globalRing) {
      globalRing = new RingBufferStore(chunkLength, opts);
      process.stdout.write(`STORE:created chunkLen=${chunkLength} totalLen=${globalRing.length}\n`);
    }
    this.chunkLength = globalRing.chunkLength;
    this.length = globalRing.length;
  }
  put(i, b, cb) { return globalRing.put(i, b, cb); }
  get(i, o, cb) { return globalRing.get(i, o, cb); }
  close(cb) { return globalRing.close(cb); }
  destroy(cb) { return globalRing.destroy(cb); }
}

// ═══════════════════════════════════════════════════════════════════
//  PieceFailureTracker — persistent-failure detector. Despite the name,
//  decides zero-fill (not skip); counter survives mpv reconnects via
//  PIECE_FAIL_RESET_MS (see v15.0).
// ═══════════════════════════════════════════════════════════════════
class PieceFailureTracker {
  constructor() {
    this._fails = new Map();
    this._skipped = new Set();
    this._manual = new Set();
  }

  recordTimeout(index) {
    const now = Date.now();
    const entry = this._fails.get(index);
    if (!entry || (now - entry.lastTs) > PIECE_FAIL_RESET_MS) {
      this._fails.set(index, { count: 1, lastTs: now });
      return 1;
    }
    entry.count++;
    entry.lastTs = now;
    return entry.count;
  }

  // Called when a piece genuinely arrives (store.put / verified event) —
  // the piece exists now, so any earlier manual-skip decision is moot.
  clear(index) {
    this._fails.delete(index);
    this._skipped.delete(index);
    this._manual.delete(index);
  }

  // On hash-fail the piece didn't arrive, only failed verification — calling
  // clear() here used to also wipe a user's SKIP: (_manual) flag. clear-
  // TimeoutOnly() resets just the retry counter instead (see v17.0).
  clearTimeoutOnly(index) {
    this._fails.delete(index);
  }

  shouldZeroFill(index) {
    const entry = this._fails.get(index);
    return !!entry && entry.count >= PIECE_FAIL_THRESHOLD;
  }

  // Backward-compat alias
  shouldSkip(index) { return this.shouldZeroFill(index); }

  markManualSkip(index) {
    this._fails.set(index, { count: PIECE_FAIL_THRESHOLD, lastTs: Date.now() });
    this._manual.add(index);
  }

  isManualSkip(index) {
    return this._manual.has(index);
  }

  markSkippedOnce(index) {
    if (this._skipped.has(index)) return false;
    this._skipped.add(index);
    return true;
  }
}

const pieceFailureTracker = new PieceFailureTracker();


// ═══════════════════════════════════════════════════════════════════
//  AdaptiveWindow
// ═══════════════════════════════════════════════════════════════════
class AdaptiveWindow {
  constructor() {
    this._ahead = WINDOW_AHEAD_DEFAULT;
    this._dlSamples = [];
  }

  update(downloadSpeed, storeBytes, storeMax, pieceLen) {
    if (pieceLen > 0) this._pieceLen = pieceLen;
    this._dlSamples.push(downloadSpeed);
    if (this._dlSamples.length > 5) this._dlSamples.shift();
    const avgDl = this._dlSamples.reduce((a, b) => a + b, 0) / this._dlSamples.length;
    const storeFill = storeBytes / storeMax;

    let target;
    if (avgDl === 0) target = WINDOW_AHEAD_MAX;
    else if (avgDl < 0.5 * 1024 * 1024) target = WINDOW_AHEAD_MAX;
    else if (avgDl < 2 * 1024 * 1024) target = 80;
    else if (avgDl < 5 * 1024 * 1024) target = 60;
    else if (avgDl < 10 * 1024 * 1024) target = 50;
    else target = WINDOW_AHEAD_DEFAULT;

    if (storeFill > 0.90) target = Math.min(target, WINDOW_AHEAD_MIN);
    else if (storeFill > 0.80) target = Math.min(target, 30);
    else if (storeFill > 0.70) target = Math.min(target, 50);

    // v21.1: tier targets are piece-count constants calibrated for ~1MB
    // pieces. At 8MB pieces 60-80 pieces is 480-640MB — straight through
    // the RAM cap, and in-window pieces never evict, so the cap could not
    // defend itself. Clamp every target to what the store can actually
    // hold (85% of maxBytes, floored at WINDOW_AHEAD_MIN).
    const ramPieces = (this._pieceLen > 0 && storeMax > 0)
      ? Math.max(WINDOW_AHEAD_MIN, Math.floor(storeMax * 0.85 / this._pieceLen))
      : WINDOW_AHEAD_MAX;
    this._ramPieces = ramPieces; // cached for the ahead getter's clamp
    target = Math.min(target, ramPieces);

    if (target > this._ahead) this._ahead = Math.min(this._ahead + 8, target);
    else if (target < this._ahead) this._ahead = Math.max(this._ahead - 2, target);

    // Clamp the return too: _ahead eases down at -2/call, so without this
    // the first selects after a big pieceLen arrives still overshoot.
    return Math.min(Math.round(this._ahead), ramPieces);
  }

  setPieceLen(pieceLen) {
    this._pieceLen = pieceLen;
  }

  get ahead() {
    const cap = this._ramPieces || WINDOW_AHEAD_MAX;
    return Math.min(Math.round(this._ahead), cap);
  }
}

// v18.0: deadline written by triggerSwarmReconnect (defined far below),
// read by AdaptiveStallDetector.check just below — declared here so it
// exists before either use regardless of file order.
let _reconnectGraceUntil = 0;

// ═══════════════════════════════════════════════════════════════════
//  AdaptiveStallDetector — when activeStreams===0 but waitedPieces.length>0,
//  _reset() is skipped (avoids a double-deadlock); onDeadlock fires a
//  synthetic unchoke instead (see v15.0).
// ═══════════════════════════════════════════════════════════════════
class AdaptiveStallDetector {
  constructor() {
    this._stallStart = null;
    this._lastDlBytes = 0;
    this._retryCount = 0;
    this._pieceTimeout = PIECE_TIMEOUT_BASE;
    this._isStalling = false;
    // Lets repeated consecutive auto-skips shorten the per-piece stall
    // threshold for the rest of the streak, so a chronically-bad region is
    // recognized faster instead of re-learned piece by piece (see v17.0).
    this._consecutiveAutoSkips = 0;
    // v17.25: tracks waitedPieces[0] across check() calls so dlMoved can
    // tell "this specific piece arrived" from "the swarm is busy elsewhere".
    this._lastStalledPiece = null;
    // Separate timestamp for the DL-gate window — _stallStart resets on
    // every retry cycle, making a cap on it unreachable (see v17.34).
    this._dlGateStart = null;
    // Hysteresis state: true once speed crossed DL_GATE_HIGH, stays true
    // until speed drops below DL_GATE_LOW (see v17.34).
    this._dlGateActive = false;
  }

  get pieceTimeout() { return this._pieceTimeout; }
  get isStalling() { return this._isStalling; }
  // v17.26: exposes the streak so onForceSkip can switch from a 1-piece
  // skip to a block skip once a region has proven chronically dead —
  // see DEAD_ZONE_SKIP_STREAK at the call site.
  get consecutiveAutoSkips() { return this._consecutiveAutoSkips; }
  // v18.3: read-only DL-gate state for triggerSwarmReconnect. Lets the wire
  // destroy loop spare peers that reported having the stuck piece — those are
  // exactly the peers the DL-gate is waiting on; destroying them defeats the
  // gate's own strategy and forces an unnecessary re-request cycle.
  get isDlGateActive() { return this._dlGateActive && this._dlGateStart !== null; }
  get dlGateStalledPiece() { return this._lastStalledPiece; }

  // Call when a piece genuinely arrives (verified event) to break the
  // consecutive-auto-skip streak — only a real arrival should reset this,
  // not generic dlMoved, or the streak would never accumulate (see v17.0).
  resetSkipStreak() { this._consecutiveAutoSkips = 0; }

  // v17.37: public increment for orphan-flush sites that count skips toward
  // dead-zone detection. Previously _consecutiveAutoSkips was mutated directly
  // from updateSlidingWindow, breaking class encapsulation.
  incrementSkipStreak() { this._consecutiveAutoSkips++; }

  check({ downloadedBytes, downloadSpeed, pieceLen, waitedPieces, torrent, currentWindow,
    fileFirst, fileLast, currentPlayPiece,
    onWindowMissing, onForceSkip, onDeadlock }) {

    if (!streamSession.isStreaming()) {
      // streams=0 + a pending waiter is a double-deadlock: WT is also
      // waiting, nothing would ever trigger. Skip _reset() and fire
      // onDeadlock (synthetic unchoke) instead of clearing stall state (see v15.0).
      if (waitedPieces.length > 0) {
        if (!currentWindow) {
          if (typeof onWindowMissing === 'function') {
            try {
              onWindowMissing(currentPlayPiece, fileFirst, fileLast);
              process.stdout.write(
                `STALL:streams0-waiter-recover play=${currentPlayPiece} waited=${waitedPieces[0]}\n`
              );
            } catch (e) {
              process.stdout.write(`STALL:streams0-waiter-recover ERR ${e?.message || e}\n`);
            }
          }
        }
        if (typeof onDeadlock === 'function') {
          try { onDeadlock(); } catch (_) { }
        }
        // No _reset() here — preserves the stall counter.
      } else {
        // No waiter, genuinely idle — safe to reset.
        this._reset();
      }
      return;
    }

    if (!currentWindow) {
      if (typeof onWindowMissing === 'function') {
        try {
          onWindowMissing(currentPlayPiece, fileFirst, fileLast);
          process.stdout.write(
            `STALL:window-missing-recover play=${currentPlayPiece}\n`
          );
        } catch (e) {
          process.stdout.write(`STALL:window-missing-recover ERR ${e?.message || e}\n`);
        }
      }
    }

    // dlMoved requires the actually-stalled piece (waitedPieces[0]) to have
    // changed, not just torrent.downloaded — that counter is global, so a
    // single stuck piece was masked by unrelated swarm traffic (see v17.25).
    if (Date.now() < _reconnectGraceUntil) {
      // Preserve stall state during reconnect grace instead of resetting it,
      // or the timer restarts from zero after grace expires (see v18.1).
      this._stallStart = this._stallStart || Date.now();
      // Keep these current too, or a piece-identity change during grace
      // wipes _stallStart again on exit via pieceChanged→dlMoved (see v18.3).
      this._lastDlBytes = downloadedBytes;
      this._lastStalledPiece = waitedPieces[0] ?? null;
      return;
    }

    const globalDlMoved = downloadedBytes > this._lastDlBytes;
    this._lastDlBytes = downloadedBytes;
    const stalledCandidate = waitedPieces[0] ?? null;
    const pieceChanged = stalledCandidate !== this._lastStalledPiece;
    this._lastStalledPiece = stalledCandidate;
    const dlMoved = stalledCandidate == null ? globalDlMoved : pieceChanged;

    if (dlMoved) {
      this._reset();
      return;
    }

    if (!this._stallStart) {
      this._stallStart = Date.now();
      this._isStalling = false;
      return;
    }

    const stallMs = Date.now() - this._stallStart;
    // After repeated consecutive auto-skips, shrink this streak's threshold —
    // a region already proven bad doesn't need the full wait re-learned every
    // piece. Floored at 2s so WT/peers still get a real chance (see v17.0).
    const effectiveThreshold = this._consecutiveAutoSkips >= 3
      ? Math.max(2_000, STALL_THRESHOLD_MS - this._consecutiveAutoSkips * 1_000)
      : STALL_THRESHOLD_MS;
    if (stallMs < effectiveThreshold) return;

    this._isStalling = true;
    this._retryCount++;
    const stalledPiece = waitedPieces[0] ?? currentPlayPiece;

    process.stdout.write(
      `STALL: piece=${stalledPiece} play=${currentPlayPiece} ` +
      `retry=${this._retryCount}/${STALL_MAX_RETRIES} stallMs=${stallMs}\n`
    );

    if (this._retryCount >= STALL_MAX_RETRIES) {
      const have = this._countPeersWithPiece(stalledPiece, torrent);
      const total = torrent.wires.length;

      // If peers report having the stuck piece, extend the wait instead of
      // zero-filling — fires on have>0 alone, since choked peers show dl≈0
      // yet still have it; capped at DL_GATE_TIMEOUT_MULTIPLIER × expected transfer time (see v18.1).
      if (downloadSpeed >= DL_GATE_HIGH) this._dlGateActive = true;
      else if (downloadSpeed < DL_GATE_LOW) this._dlGateActive = false;

      if (have > 0 && pieceLen > 0) {
        if (!this._dlGateStart) this._dlGateStart = Date.now();
        const gateMs = Date.now() - this._dlGateStart;
        // Use at least DL_GATE_LOW as floor so cap is never zero/Infinity.
        const effectiveSpeed = Math.max(downloadSpeed, DL_GATE_LOW);
        const expectedMs = (pieceLen / effectiveSpeed) * 1_000;
        // v19.8: floored at the DL_GATE_LOW-derived wait, not just speed
        // itself — expectedMs alone shrinks as *global* throughput rises,
        // so a healthier swarm was silently giving a stuck-but-present piece
        // LESS time, the opposite of intent. have>0 already means the swarm
        // isn't the problem (some peer holds the piece); a faster global
        // average doesn't make that specific peer more likely to send it,
        // so global speed shouldn't be allowed to shrink the wait below what
        // a borderline-healthy swarm (DL_GATE_LOW) would have gotten.
        const floorMs = (pieceLen / DL_GATE_LOW) * 1_000 * DL_GATE_TIMEOUT_MULTIPLIER;
        // v21.0: thin swarms get proportionally more patience — with one
        // seed there is nobody else to fetch from, so the wait scales up
        // instead of zero-filling a piece that just needs time.
        const swarmFactor = total <= 1 ? 4 : total <= 3 ? 2.5 : 1;
        const maxWaitMs = Math.max(expectedMs * DL_GATE_TIMEOUT_MULTIPLIER, floorMs) * swarmFactor;
        if (gateMs < maxWaitMs) {
          process.stdout.write(
            `STALL:dl-gate piece=${stalledPiece} peers=${have}/${total} ` +
            `dlSpeed=${(downloadSpeed / 1024).toFixed(0)}KB/s active=${this._dlGateActive} ` +
            `swarmFactor=${swarmFactor} gateMs=${gateMs} maxWaitMs=${maxWaitMs.toFixed(0)} — extending wait\n`
          );
          // v21.6: final-retry reissue — release the stalled piece's stranded
          // block reservations on every wire and re-request now, not after
          // WT's request-timeout cycle (WT hotswap pattern, see v21.6).
          try {
            const piece = torrent.pieces?.[stalledPiece];
            if (piece) {
              let canceled = 0;
              for (const w of torrent.wires) {
                if (!w.requests?.length) continue;
                let touched = false;
                for (const req of w.requests) {
                  if (req.piece !== stalledPiece) continue;
                  piece.cancel((req.offset / 16384) | 0); // 16KB blocks
                  canceled++; touched = true;
                }
                if (touched && Array.isArray(torrent._reservations?.[stalledPiece])) {
                  const r = torrent._reservations[stalledPiece];
                  for (let i = 0; i < r.length; i++) if (r[i] === w) r[i] = null;
                }
              }
              if (canceled > 0) torrent._update();
              process.stdout.write(`STALL:reissue piece=${stalledPiece} canceled=${canceled}\n`);
            }
          } catch (e) {
            process.stdout.write(`STALL:reissue ERR ${e?.message || e}\n`);
          }
          this._retryCount = 0;
          return;
        }
        process.stdout.write(
          `STALL:dl-gate-expired piece=${stalledPiece} peers=${have}/${total} ` +
          `gateMs=${gateMs} maxWaitMs=${maxWaitMs.toFixed(0)} — zero-fill\n`
        );
      }

      this._consecutiveAutoSkips++;
      process.stdout.write(
        `RARE_PIECE: piece=${stalledPiece} peersWithPiece=${have}/${total} ` +
        `streak=${this._consecutiveAutoSkips} ` +
        `— ${have === 0 ? 'NOT IN SWARM (source problem)' : 'peers have it but not delivering (selective/slow)'}\n`
      );
      // Diagnostic only, no behavior change. peersWithPiece counts wires
      // that HAVE the piece but says nothing about choke state — this
      // breaks that down into choking/unchoked/withPendingReqs (see v17.39).
      try {
        if (have > 0 && typeof torrent !== 'undefined' && torrent?.wires) {
          let choking = 0, unchoked = 0, withReqs = 0, notInterested = 0;
          for (const w of torrent.wires) {
            if (!w.peerPieces?.get(stalledPiece)) continue;
            if (w.peerChoking) choking++; else unchoked++;
            if (w.requests?.length > 0) withReqs++;
            if (!w.amInterested) notInterested++;
          }
          process.stdout.write(
            `RARE_PIECE:wire-detail piece=${stalledPiece} choking=${choking} ` +
            `unchoked=${unchoked} withPendingReqs=${withReqs} notInterested=${notInterested}\n`
          );
        }
      } catch (e) {
        process.stdout.write(`RARE_PIECE:wire-detail-failed err=${e?.message || e}\n`);
      }
      this._retryCount = 0;
      this._stallStart = null;

      if (typeof onForceSkip === 'function') {
        try { onForceSkip(stalledPiece); } catch (_) { }
      }
      return;
    }

    // Action 1: re-select the window.
    if (currentWindow) {
      try {
        torrent.deselect(currentWindow.from, currentWindow.to, false);
        torrent.select(currentWindow.from, currentWindow.to, false);
        // High-priority selection instead of critical() (see v15.0).
        _selectHighPriority(stalledPiece, Math.min(stalledPiece + LOOKAHEAD, fileLast));
        process.stdout.write(`STALL:reselect [${currentWindow.from},${currentWindow.to}]\n`);
      } catch (_) { }
    }

    // Action 2: tracker refresh, via debounce guard (see v17.34).
    throttleTrackerAnnounce('STALL');

    // Action 3: shorten PIECE_TIMEOUT.
    this._pieceTimeout = Math.max(PIECE_TIMEOUT_MIN, this._pieceTimeout - 10_000);
    process.stdout.write(`STALL:timeout-reduced=${this._pieceTimeout}ms\n`);

    this._stallStart = null;
  }

  _reset() {
    this._stallStart = null;
    this._dlGateStart = null;
    this._dlGateActive = false;
    this._retryCount = 0;
    this._isStalling = false;
    this._pieceTimeout = PIECE_TIMEOUT_BASE;
    // _consecutiveAutoSkips intentionally NOT cleared here — _reset() fires
    // on dlMoved (including after a skip), which would prevent accumulation.
    // Only _resetStreak()/resetSkipStreak() should zero the streak (see v17.34).
  }

  // Private alias for explicit streak reset, e.g. a dead-zone jump (see v17.34).
  _resetStreak() {
    this._consecutiveAutoSkips = 0;
  }

  _countPeersWithPiece(index, torrent) {
    let n = 0;
    for (const wire of torrent.wires) {
      try { if (wire.peerPieces?.get(index)) n++; } catch (_) { }
    }
    return n;
  }
}

// ─── Wire counters ──────────────────────────────────────────────────
let wireErrorCount = 0;
let hotswapCount = 0;

// ─── WebTorrent client ────────────────────────────────────────────
// DHT binds UDP (k-rpc-socket → dgram), not TCP — the prior net.createServer()
// probe tested a different namespace and never detected Transmission's UDP
// 6771 conflict; this probes with dgram to match what bittorrent-dht binds (see v18.4).
const _findFreeUdpPort = () => new Promise((resolve, reject) => {
  const s = dgram.createSocket('udp4');
  s.once('error', reject);
  s.bind(0, '0.0.0.0', () => { const { port } = s.address(); s.close(() => resolve(port)); });
});
const _isDhtPortOccupied = () => new Promise(resolve => {
  const s = dgram.createSocket('udp4');
  s.once('error', () => resolve(true));
  s.bind(6771, '0.0.0.0', () => s.close(() => resolve(false)));
});
const _dhtPort = await _findFreeUdpPort();
const _dhtOccupied = await _isDhtPortOccupied();
process.stdout.write(`CLIENT:dht-probe port=${_dhtPort} occupied6771=${_dhtOccupied} dht=on lsd=${!_dhtOccupied}\n`);

// Preferred fixed peer-listen port (TCP+UDP, uTP shares the UDP side) for
// router port-forwarding — but Transmission's own default listen port is
// ALSO 51413, so if it's already bound (Transmission open), fall back to a
// free OS-assigned TCP port instead of colliding silently like DHT/LSD did
// on 6771. Trade-off: on fallback, the port isn't the one forwarded in the
// router, so inbound connectability degrades to outbound-only for that
// session — still functional (tracker/DHT/LSD/PEX all work outbound), just
// fewer reachable peers than with the forwarded port. Logged either way so
// it's visible which case fired.
const PREFERRED_TORRENT_PORT = 51413;
const _isTcpPortOccupied = (p) => new Promise(resolve => {
  const s = net.createServer();
  s.once('error', () => resolve(true));
  s.listen(p, '0.0.0.0', () => s.close(() => resolve(false)));
});
const _findFreeTcpPort = () => new Promise((resolve, reject) => {
  const s = net.createServer();
  s.once('error', reject);
  s.listen(0, '0.0.0.0', () => { const { port } = s.address(); s.close(() => resolve(port)); });
});
const _torrentPortOccupied = await _isTcpPortOccupied(PREFERRED_TORRENT_PORT);
const TORRENT_LISTEN_PORT = _torrentPortOccupied
  ? await _findFreeTcpPort()
  : PREFERRED_TORRENT_PORT;
process.stdout.write(`CLIENT:torrent-port-probe preferred=${PREFERRED_TORRENT_PORT} occupied=${_torrentPortOccupied} using=${TORRENT_LISTEN_PORT}\n`);

const client = new WebTorrent({
  // Port passed three ways so it reaches bittorrent-dht's bind() regardless
  // of bundled WT/bittorrent-dht version: dhtPort, dht.port (see v18.4).
  // v20.2: dht no longer dies with the 6771 probe — it binds _dhtPort (a
  // probed-free port), which never collides with LSD's hardcoded 6771.
  dht: { port: _dhtPort },
  dhtPort: _dhtPort,
  torrentPort: TORRENT_LISTEN_PORT,
  // lsd gated on the 6771 probe: bittorrent-lsd hardcodes LSD_PORT=6771
  // (no override option exists — see bittorrent-lsd/index.js). lsd:true with
  // 6771 taken bind-collides and stalls Discovery's constructor before
  // tracker announce can fire (see v19.10). v20.2: the probe now gates LSD
  // only; dht runs on its own free port regardless.
  tracker: true, lsd: !_dhtOccupied, utPex: true,
  webSeeds: true, maxConns: 1000,
  alwaysChokeSeeders: false,
});
client.setMaxListeners(0);

const torrent = client.add(src, {
  path: tmpDir,
  store: RingStoreFactory,
  // v21.2: skip WT's CacheChunkStore LRU (default 20 pieces) — unaccounted
  // duplicate RAM on top of the ring, which is already the cache.
  storeCacheSlots: 0,
  maxWebConns: 64,
  // uploads 10→20: more reciprocal-unchoke slots, more peers likely to
  // unchoke back; alwaysChokeSeeders:false already exempts seeders, so
  // this mainly affects leecher reciprocity. Unverified (see v19.7).
  uploads: 20,
  destroyStoreOnDestroy: false,
  announce: TIER1,
  deselect: true,
});
torrent.setMaxListeners(0);

// v21.2: one-time capability check — _markUnverified arrived in webtorrent
// #2757 (2.4+); without it _notifyEvicted silently no-ops and evicted
// pieces are never re-fetched. REQ: prefix so gor surfaces it (see v21.3).
if (typeof torrent._markUnverified === 'function') {
  process.stdout.write('REQ:caps markUnverified=ok\n');
} else {
  process.stdout.write('REQ:caps markUnverified=MISSING — upgrade vendored webtorrent (>=2.4); RAM eviction cannot re-request pieces\n');
}

// ─── Wire setup ─────────────────────────────────────────────────────
torrent.on('wire', wire => {
  wire.setKeepAlive(true);
  wire.on('error', () => { wireErrorCount++; });
});

torrent.on('hotswap', (minWire, wire, index) => {
  hotswapCount++;
  if (index === currentPlayPiece) {
    process.stdout.write(`HOTSWAP: piece=${index} play=${currentPlayPiece} (PLAYHEAD) total=${hotswapCount}\n`);
  }
});

// On bad hash WT skips store.put() (only emits 'warning'), leaving a waiter
// orphaned forever; restartWaiter() renews its timeout instead of flushing
// it. Out-of-window pieces default to NOT deselecting (see v17.0, v17.2).
const DESELECT_ORPHAN_HASHFAIL = false;

// v21.0: per-piece hash-fail accounting. WT's warning names the piece, never
// the wire, so attribution is heuristic: after HASHFAIL_BAN_STREAK consecutive
// fails, drop the likeliest offender (a wire that HAS the piece, most pending
// requests, never a web seed, never the last wire) so honest peers get tried.
// VERDICT: fires at monotone totals so the HUD can name a corrupt swarm
// instead of spinning silently.
const _hashFailStreak = new Map();
const _hashFailTotal = new Map();
const _hashFailBans = new Map();
const _verdictFired = new Set();
const HASHFAIL_BAN_STREAK = 4;
const VERDICT_THRESHOLDS = new Set([10, 25, 50, 100]);
// v21.1: the raw-fail thresholds outlive the player — mpv's own network
// timeout kills the session before fail #10 lands (production log: counter
// died at 8). Two bans with fails still coming is the same proof on a
// shorter clock: the prime suspect was already destroyed and the piece
// still fails, so the corruption is swarm-wide, not one bad peer.
const VERDICT_BAN_MIN_FAILS = 6;
const VERDICT_BAN_MIN_BANS = 2;
function _verdict(index, total, reason) {
  const key = `${index}:${reason}${reason === 'fails' ? ':' + total : ''}`;
  if (_verdictFired.has(key)) return;
  _verdictFired.add(key);
  process.stdout.write(`VERDICT:corrupt-suspect piece=${index} fails=${total} bans=${_hashFailBans.get(index) || 0} peers=${torrent.wires.length} reason=${reason}\n`);
}
function _recordHashFail(index) {
  const streak = (_hashFailStreak.get(index) || 0) + 1;
  _hashFailStreak.set(index, streak);
  const total = (_hashFailTotal.get(index) || 0) + 1;
  _hashFailTotal.set(index, total);
  if (VERDICT_THRESHOLDS.has(total)) {
    _verdict(index, total, 'fails');
  }
  if (total >= VERDICT_BAN_MIN_FAILS && (_hashFailBans.get(index) || 0) >= VERDICT_BAN_MIN_BANS) {
    _verdict(index, total, 'bans');
  }
  if (streak >= HASHFAIL_BAN_STREAK && torrent.wires.length > 1) {
    let suspect = null;
    for (const w of torrent.wires) {
      if (w.type === 'webSeed') continue;
      if (!w.peerPieces?.get(index)) continue;
      if (!suspect || (w.requests?.length || 0) > (suspect.requests?.length || 0)) suspect = w;
    }
    if (suspect) {
      process.stdout.write(`HASH:fail-ban piece=${index} wire=${suspect.remoteAddress || 'unknown'} streak=${streak}\n`);
      try { suspect.destroy(); } catch (_) { }
      _hashFailBans.set(index, (_hashFailBans.get(index) || 0) + 1);
      _hashFailStreak.set(index, 0);
    }
  }
}

torrent.on('warning', (err) => {
  if (!err?.message) return;
  const match = err.message.match(/Piece (\d+) failed verification/);
  if (match) {
    const index = parseInt(match[1]);
    const ring = getRing();
    _recordHashFail(index);
    if (ring?._waiters.has(index)) {
      const restarted = ring.restartWaiter(index, stallDetector.pieceTimeout);
      try { _boostWaiterPiece(index); } catch (_) { }
      process.stdout.write(
        `HASH:fail piece=${index} waiter-restarted=${restarted} — WT will retry\n`
      );
      // clearTimeoutOnly belongs in this branch only — WT retries the piece,
      // so resetting the counter lets a later recordTimeout() accumulate
      // from 1 again; _manual/_skipped flags stay untouched (see v17.34).
      pieceFailureTracker.clearTimeoutOnly(index);
    } else {
      const outOfWindow = currentWindow && (index < currentWindow.from || index > currentWindow.to);
      if (outOfWindow) {
        if (DESELECT_ORPHAN_HASHFAIL) {
          try {
            torrent.deselect(index, index, false);
            process.stdout.write(
              `HASH:fail piece=${index} no-waiter out-of-window — deselected\n`
            );
          } catch (_) {
            process.stdout.write(`HASH:fail piece=${index} no-waiter out-of-window — deselect-failed\n`);
          }
        } else {
          process.stdout.write(
            `HASH:fail piece=${index} no-waiter out-of-window win=[${currentWindow.from},${currentWindow.to}] — bandwidth-waste (observe-only)\n`
          );
        }
      } else {
        // v17.21: no-waiter in-window hash-fail increments failure counter.
        // Do NOT call clearTimeoutOnly() here — the count written by
        // recordTimeout() must survive to reach PIECE_FAIL_THRESHOLD (2).
        // Previously clearTimeoutOnly() was called unconditionally after both
        // branches, deleting _fails on every hash-fail; threshold unreachable.
        const failCount = pieceFailureTracker.recordTimeout(index);
        process.stdout.write(
          `HASH:fail piece=${index} no-waiter in-window fail=${failCount}/${PIECE_FAIL_THRESHOLD}` +
          `${failCount >= PIECE_FAIL_THRESHOLD ? ' — THRESHOLD reached, next pump will zero-fill' : ' — WT retry pending'}\n`
        );
        // Counter cleared only on genuine arrival (verified → pieceFailureTracker.clear()).
      }
    }
  }
});

// 'verified' fires once WT confirms store.put()+SHA1 — the only event that
// proves a piece truly landed. Clears the failure tracker and can advance
// currentPlayPiece during pre-buffer, before mpv has connected (see v15.0).
let verifiedCount = 0;
let lastVerifiedAt = 0;

torrent.on('verified', (index) => {
  verifiedCount++;
  lastVerifiedAt = Date.now();

  // Already cleared inside store.put(), but verified is guaranteed to
  // fire so clear it here too as a redundant safety net.
  pieceFailureTracker.clear(index);
  _hashFailStreak.delete(index);
  const ring = getRing();
  // Reset the skip streak only when the arrived piece is the one the
  // stall detector is actually waiting on — pieces landing elsewhere in
  // the window don't prove the stuck piece resolved (see v17.28).
  const stalledPiece = ring?.waitedPieces[0] ?? null;
  if (stalledPiece === null || index === stalledPiece) {
    stallDetector.resetSkipStreak();
  }

  // Pre-buffer: mpv hasn't connected yet but pieces keep arriving — pull
  // currentPlayPiece toward the verified piece so the window keeps pace
  // once metadata is loaded (no-op if play is already ahead).
  if (!streamSession.isStreaming() && index >= currentPlayPiece && index <= totalFileLast) {
    const newPlay = Math.min(index, currentPlayPiece + WINDOW_AHEAD_DEFAULT);
    if (newPlay > currentPlayPiece && totalFileFirst > 0) {
      currentPlayPiece = newPlay;
      const ring = getRing();
      if (ring) ring.setPlayhead(currentPlayPiece);
    }
  }
});

// ─── Tracker enjeksiyonu ──────────────────────────────────────────
function injectTrackers(list) {
  try {
    const tracker = torrent.discovery?.tracker;
    if (!tracker) return;
    const existing = new Set(tracker._trackers?.map(t => t.announceUrl) || []);
    for (const url of list) {
      if (!existing.has(url)) try { tracker.addTracker(url); } catch (_) { }
    }
    try { tracker.start(); } catch (_) { }
  } catch (_) { }
}

let tier2Done = false, tier3Done = false;
// Peer-count gate only — progress no longer blocks escalation once a
// swarm thins after passing it (see v19.7).
setInterval(() => {
  const p = torrent.numPeers;
  if (!tier2Done && p < 10) {
    tier2Done = true; injectTrackers(TIER2);
    process.stdout.write('TRACKERS:TIER2\n');
  }
  if (!tier3Done && p < 3) {
    tier3Done = true; injectTrackers(TIER3);
    process.stdout.write('TRACKERS:TIER3\n');
  }
}, 5_000);

// v17.34: Announce burst guard. STALL, CMD:refresh, SWARM:reconnect, and
// periodic can all fire within 500ms. 5s debounce is well below any tracker
// min-interval. Returns true if the announce was sent.
const TRACKER_ANNOUNCE_DEBOUNCE_MS = 5_000;
let _lastTrackerAnnounceAt = 0;

function throttleTrackerAnnounce(tag) {
  const now = Date.now();
  if (now - _lastTrackerAnnounceAt < TRACKER_ANNOUNCE_DEBOUNCE_MS) {
    process.stdout.write(
      `${tag}:tracker-announce skipped (debounce ${now - _lastTrackerAnnounceAt}ms < ${TRACKER_ANNOUNCE_DEBOUNCE_MS}ms)\n`
    );
    return false;
  }
  _lastTrackerAnnounceAt = now;
  try {
    torrent.discovery?.tracker?.announce?.();
    process.stdout.write(`${tag}:tracker-announce\n`);
    return true;
  } catch (e) {
    process.stdout.write(`${tag}:tracker-announce ERR ${e?.message || e}\n`);
    return false;
  }
}

// Periodic tracker re-announce (10 min). announce() confirmed correct:
// bittorrent-tracker Client.update() sends an update announce (no event
// field) identical to the scheduled ping — for forced peer discovery,
// announce() is the right call. See v17.27 CHANGELOG for full analysis.
const TRACKER_REANNOUNCE_MS = 10 * 60 * 1000; // 10 min
// Fires every 10min so virtually never hits the
// 5s gate; goes through helper for consistency (see v17.34).
setInterval(() => { throttleTrackerAnnounce('TRACKERS:periodic'); }, TRACKER_REANNOUNCE_MS);

// v19.7: periodic DHT lookup — previously fired only inside
// triggerSwarmReconnect (stall-only). No debounce: a local routing-
// table walk, not a rate-limited tracker call.
const DHT_LOOKUP_REFRESH_MS = 5 * 60 * 1000; // 5 min
setInterval(() => {
  try {
    const dht = torrent.discovery?.dht ?? client.dht;
    if (dht && typeof dht.lookup === 'function') {
      dht.lookup(torrent.infoHash, () => { });
      process.stdout.write('DHT:periodic-lookup\n');
    }
  } catch (_) { }
}, DHT_LOOKUP_REFRESH_MS);

torrent.on('noPeers', t => process.stdout.write(`NOPEERS:${t}\n`));

// ─── Global state ─────────────────────────────────────────────────
// activeStreams counter removed in v16, replaced by streamSession.
let currentPlayPiece = 0;
let currentWindow = null;
let totalFileLast = 0;
let totalFileFirst = 0;
let currentFileLength = 0;
let currentFileOffset = 0;
// v17.13: computeAdaptiveParams() result — stored here to be relayed to the
// Swift side in the PARAMS: message before STREAM:.
let adaptiveParams = null;

// v15.0: wire pipeline metrics
let _pipelineFrozenSince = null;
// v19.0: hoisted out of the interval callback below — it was being
// re-declared with `let` (and reset to 0) on every tick, which collapsed
// the "totalWireReqs === _lastTotalWireRequests" check into an effective
// "totalWireReqs === 0" check and made the PIPELINE:frozen branch dead code.
let _lastTotalWireRequests = 0;

// v15.0: pre-buffer monitor state
let _prebufferStallSince = null;
let _lastDlAtPrebuffer = 0;

// v17.27: pump abort recovery — timestamp of last pump that exited with
// aborted=true. The stall-check interval watches this: if no new RANGE (i.e.
// streamSession returns to idle and stays idle) arrives within
// PUMP_ABORT_RECOVERY_MS, trigger handleRefreshCommand + synthetic unchoke so
// wt_server is ready when mpv reconnects (or prompts it to reconnect).
let _lastPumpAbortAt = 0;
const PUMP_ABORT_RECOVERY_MS = 8_000;

let _chokeLastLog = 0;
let _reqLastLog = 0;

// ─── v15.0: high-priority selection helper ───────────────────────
// critical() only sets _critical[i]=true and allows hotswap.
// INEFFECTIVE outside selection.
// This function adds priority=1 selection around the playhead.
// WT's _selections.sort() mechanism puts this first.
let _priorityWindow = null; // { from, to } — stored so we can clear it later

// v21.0: a piece with a live HTTP waiter outranks the whole window. WT
// fetches in-window pieces roughly in order, so the playhead piece starves
// behind 60+ queued pieces on thin swarms — this cuts the line.
let _waiterBoost = null;
function _boostWaiterPiece(index) {
  if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
  const to = Math.min(index + 1, totalFileLast);
  if (_waiterBoost && _waiterBoost.from === index && _waiterBoost.to === to) return;
  try {
    if (_waiterBoost) torrent.deselect(_waiterBoost.from, _waiterBoost.to, 2);
    torrent.select(index, to, 2);
    _waiterBoost = { from: index, to };
    process.stdout.write(`SEL:boost piece=${index} priority=2\n`);
  } catch (_) { }
}

function _selectHighPriority(from, to) {
  if (from > to) return;
  try {
    // Clear old priority selection if any
    if (_priorityWindow) {
      torrent.deselect(_priorityWindow.from, _priorityWindow.to, false);
    }
    // priority=1 → comes ahead of normal selection (priority=0)
    torrent.select(from, to, 1);
    _priorityWindow = { from, to };
  } catch (_) { }
}

function _clearHighPriority() {
  if (!_priorityWindow) return;
  try {
    torrent.deselect(_priorityWindow.from, _priorityWindow.to, false);
    _priorityWindow = null;
  } catch (_) { }
}

// ─── mpv FEEDBACK LOOP ────────────────────────────────────────────
let lastMpvPosSec = null;
// v17.17: counts consecutive forward-jumps. If N similar "forward" values
// come in a row (real mpv progress, not Type-B echo), force the
// reference forward so it doesn't stay locked forever.
let _fwdJumpStreak = 0;
let _fwdJumpStreakSec = null;
let lastMpvPosAt = 0;
let mpvPosRecovering = false;
const MPV_POS_STALE_MS = 5_000; // v17.9: 12_000→5_000; healthy poll ~200ms, 5s is already a late alarm
// v17.6: PLAYER:stalled log — printed once when mpvPosAge ≥ 30s, reset
// when pos arrives. Lets future debug sessions immediately distinguish a
// frozen player from an unhealthy WT side.
const PLAYER_STALL_LOG_MS = 30_000;
let _playerStalledAt = 0; // 0 = not yet stalled / reset when pos arrives
// v17.34: tracks when mpv pos first went stale, independent of lastMpvPosAt.
// mpv-pos-stale recovery bumps lastMpvPosAt every 5s, permanently preventing
// PLAYER:stalled (30s gate) from firing.
let _lastMpvPosStaleAt = 0; // 0 = not stale / cleared on real /pos commit
// v18.1: count consecutive mpv-pos-stale-suppressed fires without a real
// /pos advance — pump streaming but playerSec frozen means choke-freeze.
// After 3 suppressed cycles (~15s), trigger swarm reconnect once.
let _mpvSuppressedCount = 0;
const MPV_SUPPRESSED_RECONNECT = 3;
// v18.3: explicit pause signal from the client (/cmd PAUSE|RESUME). Root
// cause of the recurring pause/resume freeze family (v17.34, v17.38, v18.1):
// the server had no way to distinguish "user paused" from "swarm choked" —
// both look identical from here (pump stays open mid-drain, /pos stops
// advancing, downloadSpeed drops near zero). Every prior fix improved the
// inference; none removed the ambiguity. _isUserPaused gates both
// reconnect triggers below so a deliberate pause is never treated as a
// freeze. Defaults to false (assume playing) if the client never sends it,
// preserving pre-v18.3 behavior for clients that don't yet send PAUSE.
let _isUserPaused = false;
// v17.21: window-thrash suppression — minimum delay between two forward
// updateSlidingWindow calls. Swift IPC Type-A/Type-B pairs arrive within a
// ~2s window; if the window were pulled forward/back within that same ~2s,
// the SEL:extend/deselect cycle would start and wireReqs would collapse.
let _lastWindowForwardAt = 0;
const WINDOW_FORWARD_DEBOUNCE_MS = 1_500;
// v17.23: seek bypass timestamp — Range handler sets _pendingSeekAt on seek;
// forward-jumps within SEEK_BYPASS_WINDOW_MS after are bypassed. Replaces
// v17.22's one-shot _pendingSeekPiece, which missed cases where /pos arrived before the Range.
let _pendingSeekAt = 0;
// v17.34: 4_000→8_000 — 4s insufficient under CPU-throttled IPC; Swift latency
// can exceed 4s before /pos arrives. 8s still << typical seek cooldown.
const SEEK_BYPASS_WINDOW_MS = 8_000;
// v19.4: torrent object itself is dead (e.g. client tore it down outside
// intentional shutdown) — an object-level state, distinct from any
// process-level "are we shutting down" question. Set once
// updateSlidingWindow's select() catches a destroyed-torrent error;
// short-circuits further retries against the same dead object.
let _torrentGone = false;
// v19.6: the process-level counterpart to _torrentGone above — set
// synchronously at the top of shutdown(), before client.destroy() (which
// is async) actually flips torrent.destroyed. Closes the narrow window
// where a tick already in flight when shutdown() runs hasn't hit a
// destroyed-torrent error yet; clearInterval() alone only stops *future*
// ticks. Checked at the same updateSlidingWindow entry guard as
// _torrentGone — complementary, not a replacement for it.
// (declaration hoisted above the SIGTERM registration — see v21.5)

const adaptiveWindow = new AdaptiveWindow();
const stallDetector = new AdaptiveStallDetector();

// ─── Sliding window ───────────────────────────────────────────────
// v16: skip deselect+select when new window overlaps/is-adjacent-to the
// old one (WT's selections.js concatenate() merges these automatically,
// and _gcSelections() skips already-downloaded pieces via its own
// offset) — avoids needless interest-churn on small window shifts.
// Only does a real deselect+select when ranges don't overlap at all
// (true discontinuity — big seek/seekback).
function updateSlidingWindow(playheadPiece, fileFirst, fileLast, doCritical = true) {
  // Torrent destroyed (v19.4) or shutdown in progress (v19.6) — every call
  // here would otherwise repeat the same dead select() forever. No
  // recovery path exists (out of scope); just stop.
  if (_torrentGone || _shuttingDown) return;

  // Defense-in-depth: playheadPiece must never exceed fileLast (callers
  // near EOF have occasionally overshot it — see dead-zone-skip / skip-cmd
  // fixes). An unclamped playhead here produces from>to and a failed
  // torrent.select() whose currentWindow still gets committed (stale/broken
  // state persists until the next successful select). Clamping here is a
  // pure safety net; it does not change normal mid-file behavior.
  playheadPiece = Math.max(fileFirst, Math.min(fileLast, playheadPiece));
  const ring = getRing();
  // v17.29: skip adaptiveWindow.update() during orphan-flush calls. Each orphan
  // flush is a control-flow event (evicting old waiters), not a real playhead
  // advance. Sampling storeFill here during an N-piece orphan chain caused
  // _ahead to drop by 2 per flush (storeFill>0.80 caps target at 30); in the
  // v17.27 log, _ahead fell 50→30 over 10 flushes, narrowing the window after
  // recovery. Detect orphan-flush scenario by checking if any current waiters
  // are below the incoming playhead window before computing the new [from,to].
  // If so, skip the adaptive sample and reuse the current _ahead value.
  const from_prelim = Math.max(fileFirst, playheadPiece - WINDOW_BEHIND);
  const hasOrphans = ring
    ? ring.waitedPieces.some(idx => idx < from_prelim)
    : false;
  const ahead = ring
    ? (hasOrphans ? adaptiveWindow.ahead : adaptiveWindow.update(torrent.downloadSpeed, ring.bytes, ring.maxBytes, torrent.pieceLength))
    : WINDOW_AHEAD_DEFAULT;

  const from = from_prelim;
  const to = Math.min(fileLast, playheadPiece + ahead);

  if (currentWindow &&
    Math.abs(from - currentWindow.from) < RESELECT_STRIDE &&
    Math.abs(to - currentWindow.to) < RESELECT_STRIDE) {
    if (doCritical) {
      // v15: priority selection instead of critical() — see _selectHighPriority
      _selectHighPriority(playheadPiece, Math.min(playheadPiece + LOOKAHEAD, to));
    }
    return;
  }

  // overlap/adjacency test matching WT's own concatenate() condition
  // (selections.js isLowerIntersecting/isUpperIntersecting); +1 tolerance
  // matches WT's "adjacent" definition.
  const overlapsExisting = currentWindow &&
    from <= currentWindow.to + 1 && to >= currentWindow.from - 1;

  if (currentWindow && !overlapsExisting) {
    try {
      torrent.deselect(currentWindow.from, currentWindow.to, false);
      process.stdout.write(`SEL:deselect [${currentWindow.from},${currentWindow.to}]\n`);
    } catch (e) {
      process.stdout.write(`SEL:deselect ERR ${e?.message || e}\n`);
    }
  } else if (currentWindow) {
    process.stdout.write(
      `SEL:extend [${currentWindow.from},${currentWindow.to}]→[${from},${to}] (no-deselect, WT-merge)\n`
    );
  }

  _clearHighPriority(); // priority window will be rebuilt by the new select below

  // Flush orphan waiters
  {
    const ring = getRing();
    if (ring) {
      let orphanCount = 0;
      for (const idx of ring.waitedPieces) {
        if (idx < from || idx > to) {
          if (idx <= totalFileFirst) {
            // Header piece: evict without counting as auto-skip (see v17.34)
            process.stdout.write(`SEL:flush-orphan-blocked piece=${idx} — header piece protected, evicting stale waiter\n`);
            ring.forceSkip(idx);
            continue;
          }
          pieceFailureTracker.markManualSkip(idx);
          ring.forceSkip(idx);
          stallDetector.incrementSkipStreak(); // counts toward dead-zone streak (see v17.27, v17.37)
          orphanCount++;
          process.stdout.write(`SEL:flush-orphan-waiter piece=${idx} new-win=[${from},${to}]\n`);
        }
      }
      if (orphanCount > 0) {
        stallDetector._reset(); // resets stall timer so next check() starts fresh (see v17.27)
      }
    }
  }

  let _selectOk = true;
  try {
    torrent.select(from, to, false);
    process.stdout.write(`SEL:select [${from},${to}] play=${playheadPiece} ahead=${ahead}\n`);
  } catch (e) {
    _selectOk = false;
    // v19.4: distinguish "torrent object is gone" from transient select
    // errors — same torrent.destroyed convention _notifyEvicted already
    // uses. Terminal: no retry path, just stop calling select().
    if (typeof torrent !== 'undefined' && torrent && torrent.destroyed) {
      _torrentGone = true;
      process.stdout.write('SEL:select ERR torrent-destroyed — suspending window updates\n');
    } else {
      process.stdout.write(`SEL:select ERR ${e?.message || e} — currentWindow kept at prior value\n`);
    }
  }

  if (_selectOk) currentWindow = { from, to };

  if (doCritical) {
    // v15.0: critical() removed, priority selection used instead
    _selectHighPriority(playheadPiece, Math.min(playheadPiece + LOOKAHEAD, to));
  }
}

// ─── activeStreams sanity guard ───────────────────────────────────
// v16.0: no longer a counter but a generation set. If activePumps is
// empty but streamSession still says 'streaming' (leaked generation —
// e.g. the pump's finally block never ran but the process somehow
// dirtied the state), forceReset clears it.
setInterval(() => {
  const now = Date.now();
  for (const [id, v] of activePumps) {
    if (now - v.ts > 120_000) {
      // Expired pump: abort so it exits waitForPiece and runs finally→end()
      try { v.abortController?.abort(); } catch (_) { }
      activePumps.delete(id);
      process.stdout.write(`GUARD:pump-expired piece=${v.startPiece} — aborted\n`);
    }
  }
  if (activePumps.size === 0 && streamSession.isStreaming()) {
    process.stdout.write(`GUARD:streamSession leaked=${streamSession.count} → reset\n`);
    streamSession.forceReset();
  }
}, 10_000);

// ─── v15.0: synthetic unchoke + periodic wake ──────────────────
// Sends wire.emit('unchoke') to all wires that haven't choked and have
// no active request. WT's event-driven _updateWire loop never fires
// again after handshake; this function fills that gap.
// v17.3: the old WAKE block (torrent._updateWire — private API) was
// merged into this function; setInterval 30s→2s (to refill the
// request pipeline once a request's duration ends).
function _triggerSyntheticUnchoke(tag) {
  let triggered = 0;
  for (const wire of torrent.wires) {
    try {
      if (wire && !wire.destroyed && !wire.peerChoking && (wire.requests?.length || 0) === 0) {
        wire.emit('unchoke');
        triggered++;
      }
    } catch (_) { }
  }
  if (triggered > 0) {
    process.stdout.write(`${tag || 'WAKE'}:kicked=${triggered}\n`);
  }
}

// Periodic wake: wakes idle unchoked wires every WAKE_BASELINE_MS to refill the request pipeline.
// v19.7: baseline 2s→1s; promoted to a named constant so the
// restore-after-reconnect site (below) can't silently keep stale "2_000"
// on a future bump — it previously duplicated the literal.
const WAKE_BASELINE_MS = 1_000;
let _wakeIntervalMs = WAKE_BASELINE_MS;   // v17.10: temporarily lowered to 0.5s during swarm reconnect
let _wakeTimer = null;

function _scheduleWake() {
  if (_wakeTimer) clearInterval(_wakeTimer);
  // v17.34: gate (> 50) removed — small swarms need WAKE more than large ones;
  // the 50-wire value was copied from SWARM_RECONNECT_WIRE_KEEP_THRESHOLD
  // (selective-destroy) and has no WAKE correctness basis. Guard > 0 only.
  _wakeTimer = setInterval(() => {
    if (torrent.wires.length > 0) {
      _triggerSyntheticUnchoke('WAKE');
    }
  }, _wakeIntervalMs);
}
_scheduleWake();

// ─── v18.0: Swarm Reconnect ───────────────────────────────────────
// dl=0 streak triggers reconnect after 60s; debounce 120s.
// selective (choked+idle) destroy now runs at every swarm size — see
// v18.0 changelog entry for the log evidence. Grace period added below.
const SWARM_RECONNECT_DL0_TRIGGER_MS = 60_000;  // 60s streak tetikler
const SWARM_RECONNECT_DEBOUNCE_MS = 120_000; // en fazla 1×/2dk
const SWARM_RECONNECT_WAKE_FAST_MS = 500;     // temporary fast wake interval
const SWARM_RECONNECT_WAKE_RESTORE_MS = 30_000; // restore to normal after 30s
// v18.0: grace window read by AdaptiveStallDetector.check(), see v18.0
// changelog. Deadline, not a duration — compared directly to Date.now().
const SWARM_RECONNECT_GRACE_MS = 20_000;

let _lastSwarmReconnectAt = 0;
let _dl0StreamingSince = null; // start of dl=0 + active stream streak
// _reconnectGraceUntil declared near AdaptiveStallDetector (top of file) —
// written here, read there.

function triggerSwarmReconnect() {
  const now = Date.now();
  if (now - _lastSwarmReconnectAt < SWARM_RECONNECT_DEBOUNCE_MS) return;
  _lastSwarmReconnectAt = now;
  _reconnectGraceUntil = now + SWARM_RECONNECT_GRACE_MS;

  // v18.0: count unchoked wires BEFORE touching anything — diagnostic
  // only (see mode= below), destroy logic doesn't branch on it.
  let unchokedBefore = 0;
  for (const w of torrent.wires) {
    try { if (w && !w.destroyed && !w.peerChoking) unchokedBefore++; } catch (_) { }
  }

  process.stdout.write(
    `SWARM:reconnect start wires=${torrent.wires.length} ` +
    `peers=${torrent.numPeers} unchoked=${unchokedBefore} ` +
    `dl0since=${_dl0StreamingSince ? now - _dl0StreamingSince : 0}ms\n`
  );

  // 1. Selective destroy unconditional at every swarm size (was: full
  // wipe below 50 wires). Destroy choked+idle AND unchoked+idle wires —
  // v18.0 kept unchoked wires alive but an 82/114 choke ratio means the
  // few unchoked wires are also idle; keeping them blocks slot reuse (v18.0).
  // Active wires (requests.length > 0) are never touched.
  // v18.3: if the DL-gate is active, spare wires from peers that report
  // having the stalled piece. Those are exactly the peers the gate is
  // waiting on (likely about to unchoke); destroying them defeats the
  // gate's purpose and causes an unnecessary fresh-handshake round-trip.
  const gateActive = stallDetector.isDlGateActive;
  const gatePiece = stallDetector.dlGateStalledPiece;
  let destroyed = 0;
  let spared = 0;
  const totalWires = torrent.wires.length;
  for (const wire of [...torrent.wires]) {
    try {
      if (wire && !wire.destroyed && (wire.requests?.length || 0) === 0) {
        if (gateActive && gatePiece !== null &&
          wire.peerPieces && wire.peerPieces.get(gatePiece)) {
          spared++;
          continue; // DL-gate: peer has the piece, give it more time
        }
        wire.destroy();
        destroyed++;
      }
    } catch (_) { }
  }
  process.stdout.write(
    `SWARM:reconnect wires-destroyed=${destroyed}/${totalWires} spared=${spared} ` +
    `(idle-only — kept active requests>0, mode=${unchokedBefore > 0 ? 'slow' : 'dead'}` +
    `${gateActive ? ` dl-gate-active piece=${gatePiece}` : ''})\n`
  );

  // 2. maxConns 1000→50→1000 rotation and throttleDownload(0) pulse
  // removed — both narrowed the connection window during the exact
  // moment more peers were wanted. See v18.0 changelog.

  // 3. bootstrap?.() was wrong — bittorrent-dht's DHT class has no public
  // bootstrap() method, so optional chaining silently no-op'd it. Real API:
  // dht.lookup() emits 'peer' events torrent-discovery forwards to addPeer() (see v17.15).
  try {
    const dht = torrent.discovery?.dht ?? client.dht;
    if (dht && typeof dht.lookup === 'function') {
      dht.lookup(torrent.infoHash, () => { });
      process.stdout.write('SWARM:reconnect dht-lookup\n');
    }
  } catch (_) { }

  // 4. Inject TIER2 + TIER3 trackers and announce
  try {
    injectTrackers([...TIER2, ...TIER3]);
    process.stdout.write('SWARM:reconnect trackers-injected\n');
  } catch (_) { }
  // Delayed 500ms so injectTrackers registers new
  // trackers before the announce fires (see v17.34).
  setTimeout(() => { throttleTrackerAnnounce('SWARM:reconnect'); }, 500);

  // 5. torrent.discovery.refresh() — call if available
  try {
    if (typeof torrent.discovery?.refresh === 'function') {
      torrent.discovery.refresh();
      process.stdout.write('SWARM:reconnect discovery-refresh\n');
    } else if (typeof torrent.discovery?.start === 'function') {
      torrent.discovery.start(torrent.infoHash);
      process.stdout.write('SWARM:reconnect discovery-start\n');
    }
  } catch (_) { }

  // 6. Drop WAKE to 0.5s, restore to normal after 30s
  _wakeIntervalMs = SWARM_RECONNECT_WAKE_FAST_MS;
  _scheduleWake();
  process.stdout.write('SWARM:reconnect wake-fast (0.5s) for 30s\n');
  setTimeout(() => {
    _wakeIntervalMs = WAKE_BASELINE_MS;
    _scheduleWake();
    process.stdout.write('SWARM:reconnect wake-restored (1s)\n');
  }, SWARM_RECONNECT_WAKE_RESTORE_MS);

  process.stdout.write('SWARM:reconnect done\n');
}

// ─── Stall detection loop ─────────────────────────────────────────
// v19.5: handle captured (was anonymous/uncleared) so shutdown() can
// clearInterval() it before destroying the client — see shutdown().
_stallIntervalHandle = setInterval(() => {
  const ring = getRing();

  // choke diagnostic
  if (ring && Date.now() - (_chokeLastLog || 0) > 30_000) {
    _chokeLastLog = Date.now();
    let choked = 0, unchoked = 0;
    for (const w of torrent.wires) {
      try { w.peerChoking ? choked++ : unchoked++; } catch (_) { choked++; }
    }
    process.stdout.write(`CHOKE:choked=${choked} unchoked=${unchoked} total=${choked + unchoked}\n`);
  }
  // wire request diagnostic
  if (ring && Date.now() - (_reqLastLog || 0) > 30_000) {
    _reqLastLog = Date.now();
    let reqTotal = 0, wiresWithReq = 0, seedCount = 0;
    for (const w of torrent.wires) {
      try {
        const r = w.requests?.length || 0;
        if (r > 0) { reqTotal += r; wiresWithReq++; }
        if (w.isSeeder) seedCount++;
      } catch (_) { }
    }
    process.stdout.write(`WIRE:requests=${reqTotal} activeWires=${wiresWithReq}/${torrent.wires.length} seeders=${seedCount}\n`);
  }

  // mpv-stale check (runs even when activeStreams=0)
  if (lastMpvPosAt > 0 && !mpvPosRecovering) {
    const posAge = Date.now() - lastMpvPosAt;
    if (posAge > MPV_POS_STALE_MS) {
      // v17.9: suppress alarm if pump is actively streaming — HTTP consumption
      // is proof mpv is alive even if IPC is slow.
      if (streamSession.isStreaming()) {
        lastMpvPosAt = Date.now(); // pump active — not stale
        _lastMpvPosStaleAt = 0;          // streaming resumed — clear stale clock (see v17.34)
        _mpvSuppressedCount++;
        process.stdout.write(
          `STALL:mpv-pos-stale-suppressed ageMs=${posAge} streams=${streamSession.count} suppressCount=${_mpvSuppressedCount} pump-active → lastMpvPosAt refreshed\n`
        );
        // v18.1: pump streaming but playerSec frozen — likely choke-freeze.
        // After MPV_SUPPRESSED_RECONNECT cycles (~15s), trigger swarm reconnect.
        // v18.3: skip while explicitly paused — a frozen playerSec is
        // expected and correct during a deliberate pause, not a symptom.
        if (_mpvSuppressedCount >= MPV_SUPPRESSED_RECONNECT) {
          _mpvSuppressedCount = 0;
          if (_isUserPaused) {
            process.stdout.write('STALL:mpv-pos-stale-suppressed-reconnect-skipped — user paused\n');
          } else {
            process.stdout.write('STALL:mpv-pos-stale-suppressed-reconnect — playerSec frozen with active pump, reconnecting swarm\n');
            try { triggerSwarmReconnect(); } catch (_) { }
          }
        }
      } else if (_isUserPaused) {
        // Real recovery branch had no _isUserPaused check — only the
        // isStreaming() branch above did, but isStreaming() is false during
        // a real pause, so this branch is the one that actually ran (see v19.2).
        process.stdout.write('STALL:mpv-pos-stale-suppressed-reconnect-skipped — user paused\n');
      } else {
        // Record the moment staleness began; do not overwrite on repeated
        // recovery cycles — PLAYER:stalled measures from this origin (see v17.34).
        if (_lastMpvPosStaleAt === 0) _lastMpvPosStaleAt = Date.now() - posAge;
        mpvPosRecovering = true;
        process.stdout.write(
          `STALL:mpv-pos-stale ageMs=${posAge} lastPos=${lastMpvPosSec} streams=${streamSession.count} — recovery\n`
        );
        // v17.9: applyMpvPosition first
        if (lastMpvPosSec != null) {
          try { applyMpvPosition(lastMpvPosSec, lastKnownDuration || undefined); } catch (_) { }
        }
        try {
          updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
          process.stdout.write(`STALL:mpv-stale-rewindow play=${currentPlayPiece}\n`);
        } catch (_) { }
        try { handleRefreshCommand(); } catch (_) { }
        if (ring && ring.waitedPieces.length > 0) {
          for (const idx of [...ring.waitedPieces]) {
            if (idx <= totalFileFirst) continue; // never flush the container header piece
            pieceFailureTracker.markManualSkip(idx);
            ring.forceSkip(idx);
            process.stdout.write(`STALL:mpv-stale-flush piece=${idx}\n`);
          }
        }
        setTimeout(() => { mpvPosRecovering = false; }, MPV_POS_STALE_MS);
      }
    }
  }

  // v17.9: PLAYER:stalled — WT healthy but player frozen for ≥30s.
  // Measure age from _lastMpvPosStaleAt (first stale detection) not
  // lastMpvPosAt, so mpv-pos-stale recovery bumps cannot permanently mask gate (see v17.34).
  if (_lastMpvPosStaleAt > 0) {
    const posAgeNow = Date.now() - _lastMpvPosStaleAt;
    if (posAgeNow >= PLAYER_STALL_LOG_MS && _playerStalledAt === 0 && !streamSession.isStreaming()) {
      _playerStalledAt = Date.now();
      const _wtWireReqs = torrent.wires.reduce(
        (s, w) => { try { return s + (w?.requests?.length ?? 0); } catch (_) { return s; } }, 0
      );
      const wtHealthy = ring
        ? `chunks=${ring.chunks.size} evicted=${ring.totalEvicted} wireReqs=${_wtWireReqs} verified=${verifiedCount}`
        : 'ring=null';
      process.stdout.write(
        `PLAYER:stalled posAgeMs=${posAgeNow} lastPos=${lastMpvPosSec} — WT-side-healthy: ${wtHealthy}\n`
      );
      if (ring && ring.waitedPieces.length > 0) {
        process.stdout.write(`PLAYER:stalled-flush flushing ${ring.waitedPieces.length} waiters\n`);
        for (const idx of [...ring.waitedPieces]) {
          if (idx <= totalFileFirst) continue; // never flush the container header piece
          pieceFailureTracker.markManualSkip(idx);
          ring.forceSkip(idx);
        }
      }
      try {
        updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
        process.stdout.write(`PLAYER:stalled-rewindow play=${currentPlayPiece}\n`);
      } catch (_) { }
      _triggerSyntheticUnchoke('PLAYER:stalled-wake');
    }
  } else if (lastMpvPosAt > 0 && !mpvPosRecovering) {
    // mpv-stale path never fired but posAge reached 30s (edge case).
    // Back-date _lastMpvPosStaleAt so the next interval catches it (see v17.34).
    const posAgeNow = Date.now() - lastMpvPosAt;
    if (posAgeNow >= PLAYER_STALL_LOG_MS && _playerStalledAt === 0 && !streamSession.isStreaming()) {
      _lastMpvPosStaleAt = Date.now() - posAgeNow;
    }
  }

  // v15.0: wire pipeline metrics
  const totalWireReqs = torrent.wires.reduce((sum, w) => {
    try { return sum + (w?.requests?.length ?? 0); } catch (_) { return sum; }
  }, 0);

  if (totalWireReqs === _lastTotalWireRequests && totalWireReqs > 0) {
    if (!_pipelineFrozenSince) {
      _pipelineFrozenSince = Date.now();
    } else if (Date.now() - _pipelineFrozenSince > PIPELINE_FROZEN_MS) {
      process.stdout.write(
        `PIPELINE:frozen reqs=${totalWireReqs} frozenMs=${Date.now() - _pipelineFrozenSince}\n`
      );
      _triggerSyntheticUnchoke('DEADLOCK');
      _pipelineFrozenSince = null;
    }
  } else {
    _pipelineFrozenSince = null;
  }
  _lastTotalWireRequests = totalWireReqs;

  // v15.0: pre-buffer monitor
  if (!streamSession.isStreaming() && ring && totalFileFirst > 0) {
    const storeFill = ring.bytes / ring.maxBytes;
    const dlNow = torrent.downloadSpeed;
    if (storeFill > PREBUFFER_FILL_RATIO && dlNow === 0) {
      if (!_prebufferStallSince) {
        _prebufferStallSince = Date.now();
        _lastDlAtPrebuffer = ring.bytes;
      } else if (Date.now() - _prebufferStallSince > PREBUFFER_STALL_MS) {
        // v17.34: WINDOW_AHEAD_MAX is stale (=120 default) before startServer
        // sets it. Use adaptiveParams when available.
        const _safeAhead = adaptiveParams != null ? adaptiveParams.windowAheadMax : WINDOW_AHEAD_DEFAULT;
        const nextPlay = currentPlayPiece + Math.floor(_safeAhead / 2);
        if (nextPlay <= totalFileLast) {
          process.stdout.write(
            `PREBUFFER:advance play=${currentPlayPiece}→${nextPlay} fill=${(storeFill * 100).toFixed(0)}%\n`
          );
          currentPlayPiece = nextPlay;
          ring.setPlayhead(currentPlayPiece);
          updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, false);
        }
        _prebufferStallSince = null;
      }
    } else {
      _prebufferStallSince = null;
    }
  }

  if (!streamSession.isStreaming()) {
    // v17.27: pump abort recovery. If a pump exited with aborted=true
    // (e.g. piece timeout → connection reset) and mpv hasn't reconnected
    // within PUMP_ABORT_RECOVERY_MS, proactively refresh so wt_server is
    // ready when mpv does reconnect — or prompts it to do so via the window
    // reselect. Only fires when not streaming (mpv disconnected) to avoid
    // interfering with a healthy running pump.
    if (_lastPumpAbortAt > 0 && !streamSession.isStreaming() &&
      (Date.now() - _lastPumpAbortAt) > PUMP_ABORT_RECOVERY_MS) {
      process.stdout.write(
        `PUMP:abort-recovery ageMs=${Date.now() - _lastPumpAbortAt} play=${currentPlayPiece} — refresh+wake\n`
      );
      _lastPumpAbortAt = 0; // one recovery attempt per abort event
      try { handleRefreshCommand(); } catch (_) { }
      _triggerSyntheticUnchoke('PUMP:abort-wake');
    }
    return;
  }
  if (!ring) return;

  stallDetector.check({
    downloadedBytes: torrent.downloaded,
    downloadSpeed: torrent.downloadSpeed,
    pieceLen: torrent.pieceLength,
    waitedPieces: ring.waitedPieces,
    torrent,
    currentWindow,
    fileFirst: totalFileFirst,
    fileLast: totalFileLast,
    currentPlayPiece,
    onWindowMissing: (playhead, fFirst, fLast) => {
      updateSlidingWindow(playhead, fFirst, fLast, true);
    },
    onDeadlock: () => {
      _triggerSyntheticUnchoke('DEADLOCK');
    },
    onForceSkip: (piece) => {
      const ring = getRing();
      if (!ring) {
        process.stdout.write(`STALL:auto-skip-noRing piece=${piece}\n`);
        return;
      }
      const waited = [...ring.waitedPieces];
      for (const idx of waited) {
        // Never skip fileFirst: it contains the container header (EBML for MKV).
        // Zero-filling it causes mpv to fail avformat_open_input with no recovery.
        if (idx <= totalFileFirst) {
          process.stdout.write(`STALL:auto-skip-blocked piece=${idx} — header piece protected\n`);
          continue;
        }
        pieceFailureTracker.markManualSkip(idx);
        ring.forceSkip(idx);
        process.stdout.write(`STALL:auto-skip piece=${idx}\n`);
      }
      // v17.30: anchor to whichever pointer is behind. Math.max always
      // resolved to currentPlayPiece (skip range started 9+ pieces past
      // the stall); Math.min fixes the common case, Math.max kept for v17.27/28 ahead-of-stall.
      const deadZone = stallDetector.consecutiveAutoSkips >= DEAD_ZONE_SKIP_STREAK;
      if (deadZone) {
        const jumpFrom = piece < currentPlayPiece
          ? Math.min(piece, currentPlayPiece)
          : Math.max(piece, currentPlayPiece);
        const nextPlay = Math.min(totalFileLast, jumpFrom + WINDOW_AHEAD_MIN);
        for (let idx = jumpFrom + 1; idx < nextPlay; idx++) {
          if (idx <= totalFileFirst) continue; // never pre-mark the container header piece
          pieceFailureTracker.markManualSkip(idx);
          ring.forceSkip(idx);
        }
        process.stdout.write(
          `STALL:dead-zone-skip piece=${piece} play=${currentPlayPiece}→${nextPlay} streak=${stallDetector.consecutiveAutoSkips}\n`
        );
        stallDetector.resetSkipStreak();
        currentPlayPiece = nextPlay;
        ring.setPlayhead(currentPlayPiece);
        updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
        // v18.1: dead-zone-skip moves the playhead but the swarm state
        // is unchanged — new position inherits the same choke freeze.
        // Trigger reconnect so fresh peers pick up the new window.
        try { triggerSwarmReconnect(); } catch (_) { }
      } else if (piece >= currentPlayPiece) {
        currentPlayPiece = Math.min(totalFileLast, piece + 1);
        ring.setPlayhead(currentPlayPiece);
        updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
      }
    },
  });

  // Stuck waiter flush
  const STUCK_WAITER_MS = PIECE_TIMEOUT_BASE + 10_000;
  {
    const now = Date.now();
    for (const [idx, list] of ring._waiters) {
      if (!list.length) continue;
      const oldest = Math.min(...list.map(w => w.startTime ?? now));
      const waitMs = now - oldest;
      if (waitMs > STUCK_WAITER_MS) {
        process.stdout.write(`STALL:stuck-waiter piece=${idx} waitMs=${waitMs} — force-flush\n`);
        pieceFailureTracker.markManualSkip(idx);
        ring.forceSkip(idx);
      }
    }
  }
}, STALL_CHECK_MS);

// ─── Dedup ────────────────────────────────────────────────────────
const activePumps = new Map(); // Unique ID -> { startPiece, abortController, ts }
let nextPumpId = 0;

function registerPump(startPiece, abortController) {
  const id = ++nextPumpId;
  activePumps.set(id, { startPiece, ts: Date.now(), abortController });
  return id;
}

function unregisterPump(id) {
  activePumps.delete(id);
}

// v17.34: piece-count radius derived from DEDUP_BYTES so the dedup window stays
// ~4MB regardless of pieceLen. Falls back to 4 if torrent not yet ready.
function dedupRadius() {
  const pl = torrent?.pieceLength;
  return (pl > 0) ? Math.max(1, Math.ceil(DEDUP_BYTES / pl)) : 4;
}

function checkDuplicate(startPiece) {
  if (activePumps.size >= MAX_CONCURRENT_PUMPS) return 'reject';
  const radius = dedupRadius();
  const hasSameRegion = [...activePumps.values()].some(
    pump => Math.abs(pump.startPiece - startPiece) <= radius
  );
  return hasSameRegion ? 'duplicate' : 'new';
}

// v17.22: abort old pumps immediately on seek instead of waiting for
// req.close (frees the resource now, not after pieceTimeout's 60s).
// exceptPiece: the new seek's startPiece — never abort that one.
function abortPumpsOutsideWindow(exceptPiece) {
  const radius = dedupRadius();
  let aborted = 0;
  for (const [id, v] of activePumps) {
    if (Math.abs(v.startPiece - exceptPiece) <= radius) continue; // new seek region — keep these pumps
    try { v.abortController?.abort(); } catch (_) { }
    activePumps.delete(id);
    aborted++;
  }
  if (aborted > 0) {
    process.stdout.write(`SEEK:abort-old-pumps count=${aborted} new-piece=${exceptPiece}\n`);
  }
  return aborted;
}

// ═══════════════════════════════════════════════════════════════════
//  STDIN command channel
// ═══════════════════════════════════════════════════════════════════
let pendingVideoFiles = null;
let pendingStartServer = null;
let _pendingSelectIdx = null; // v17.34: buffer SELECT: that arrives before metadata

// ─── Large-torrent list cap / auto-pick ──────────────────────────
// Only the first FILES_LIST_CAP are listed (position == index): FILES: is one pipe
// line, megabytes when huge (panel cost unverified). SELECT:/auto-pick see all files.
const FILES_LIST_CAP = 2000;
// 0 = wait for a selection, 1 = first playable item, 2 = random playable
// item. Keep the existing default until the UI supplies an explicit policy;
// WT_AUTO_PICK overrides it for manual runs.
const AUTO_PICK_DEFAULT = 2; // Existing random-play fallback; needs UI decision before changing.
const _envPick = parseInt(process.env.WT_AUTO_PICK, 10);
const AUTO_PICK_MODE = (_envPick === 0 || _envPick === 1 || _envPick === 2) ? _envPick : AUTO_PICK_DEFAULT;
const AUTO_PICK_DELAY_MS = 15000;
let _autoPickTimer = null;

function cancelAutoPick() {
  if (_autoPickTimer) { clearTimeout(_autoPickTimer); _autoPickTimer = null; }
}

function scheduleAutoPick() {
  if (AUTO_PICK_MODE === 0 || _autoPickTimer) return;
  _autoPickTimer = setTimeout(() => {
    _autoPickTimer = null;
    if (!pendingVideoFiles || !pendingStartServer) return;
    // Archives ship .xml/.jpg/.txt next to the audio; picking one would hand
    // mpv a non-media file. Extension-less names stay eligible (see getExt).
    let pool = [];
    for (let i = 0; i < pendingVideoFiles.length; i++) {
      const ext = getExt(pendingVideoFiles[i].name);
      if (ext === '' || Object.prototype.hasOwnProperty.call(MIME, ext)) pool.push(i);
    }
    if (pool.length === 0) pool = pendingVideoFiles.map((_, i) => i);
    const idx = AUTO_PICK_MODE === 1 ? pool[0] : pool[Math.floor(Math.random() * pool.length)];
    process.stdout.write(`AUTO_PICK:mode=${AUTO_PICK_MODE} idx=${idx} of=${pendingVideoFiles.length} name=${pendingVideoFiles[idx].name}\n`);
    // Mirrors the SELECT: path below so downstream sees the same sequence.
    cancelAutoAdvance('auto-pick');
    lastKnownDuration = 0;
    process.stdout.write(`SELECT:reset-duration idx=${idx}\n`);
    const fn = pendingStartServer;
    pendingStartServer = null;
    _currentVideoIndex = idx;
    fn(pendingVideoFiles[idx]);
  }, AUTO_PICK_DELAY_MS);
}

// ─── Auto-advance state (v17.35) ─────────────────────────────────
// Tracks which file in pendingVideoFiles is currently playing so we
// can advance to index+1 when the episode nears its end.
let _currentVideoIndex = -1;
let _autoAdvanceTimeout = null;   // NodeJS.Timeout for the 1-second tick
let _autoAdvanceActive = false;  // true while countdown is running
let _autoAdvanceCountdown = 0;      // seconds remaining (5→0)

// Near-end detection thresholds: trigger when remaining time is less than
// the larger of 5% of duration or 60 seconds.
const AUTO_ADVANCE_COUNTDOWN_SECS = 5;
const AUTO_ADVANCE_THRESHOLD_FRAC = 0.05; // last 5% of file
const AUTO_ADVANCE_THRESHOLD_SECS = 60;   // last 60 seconds (floor)
// v17.36: require this many consecutive 2s stat ticks near end before
// starting countdown — prevents false triggers from seek position jumps.
const AUTO_ADVANCE_DEBOUNCE_TICKS = 3;
let _autoAdvanceNearEndTicks = 0; // consecutive ticks at/below threshold

function cancelAutoAdvance(reason) {
  if (_autoAdvanceTimeout) { clearTimeout(_autoAdvanceTimeout); _autoAdvanceTimeout = null; }
  _autoAdvanceNearEndTicks = 0; // v17.36: reset debounce on any cancellation
  if (_autoAdvanceActive) {
    _autoAdvanceActive = false;
    _autoAdvanceCountdown = 0;
    process.stdout.write(`AUTO_ADVANCE:cancelled reason=${reason}\n`);
  }
}

function _doAutoAdvanceTick() {
  if (!_autoAdvanceActive) return;
  _autoAdvanceCountdown--;
  if (_autoAdvanceCountdown > 0) {
    process.stdout.write(`AUTO_ADVANCE:countdown ${_autoAdvanceCountdown}\n`);
    _autoAdvanceTimeout = setTimeout(_doAutoAdvanceTick, 1_000);
    return;
  }
  // Countdown expired — advance to next episode.
  _autoAdvanceActive = false;
  _autoAdvanceTimeout = null;
  if (!pendingVideoFiles || !pendingStartServer) {
    process.stdout.write('AUTO_ADVANCE:no-server-fn — cannot advance\n');
    return;
  }
  const nextIdx = _currentVideoIndex + 1;
  if (nextIdx < 0 || nextIdx >= pendingVideoFiles.length) {
    process.stdout.write('AUTO_ADVANCE:last-episode — no advance\n');
    return;
  }
  process.stdout.write(`AUTO_ADVANCE:advancing to index=${nextIdx} name=${pendingVideoFiles[nextIdx].name}\n`);
  lastKnownDuration = 0;
  const fn = pendingStartServer;
  pendingStartServer = null; // prevent re-entry
  _currentVideoIndex = nextIdx;
  fn(pendingVideoFiles[nextIdx]);
}

function startAutoAdvanceCountdown() {
  if (_autoAdvanceActive) return; // already running
  if (!pendingVideoFiles) return;
  const nextIdx = _currentVideoIndex + 1;
  if (nextIdx >= pendingVideoFiles.length) return; // last episode, no advance
  _autoAdvanceActive = true;
  _autoAdvanceCountdown = AUTO_ADVANCE_COUNTDOWN_SECS;
  process.stdout.write(
    `AUTO_ADVANCE:countdown ${_autoAdvanceCountdown} next=${pendingVideoFiles[nextIdx]?.name}\n`
  );
  _autoAdvanceTimeout = setTimeout(_doAutoAdvanceTick, 1_000);
}

function resolveTargetPiece(explicitPiece) {
  if (explicitPiece != null && !Number.isNaN(explicitPiece)) return explicitPiece;
  const ring = getRing();
  if (ring && ring.waitedPieces.length) return ring.waitedPieces[0];
  return currentPlayPiece;
}

function handleSkipCommand(explicitPiece) {
  // v17.8: staleness gate removed — see CHANGELOG. resolveTargetPiece()
  // below falls back to currentPlayPiece when no explicit piece is given,
  // so it must reflect the real player position even when posAge is high.
  if (lastMpvPosAt > 0) {
    applyMpvPosition(lastMpvPosSec, lastKnownDuration || undefined);
  }

  const target = resolveTargetPiece(explicitPiece);

  // v17.37: never skip fileFirst — it holds the container header (EBML/moov).
  // Zero-filling it causes mpv avformat_open_input to fail unrecoverably.
  // This matches the pump's own pre-check guard at the piece > fileFirst site.
  if (target <= totalFileFirst) {
    process.stdout.write(`CMD:skip piece=${target} blocked — header piece protected\n`);
    return;
  }

  pieceFailureTracker.markManualSkip(target);
  const ring = getRing();
  const hadWaiter = ring ? ring.forceSkip(target) : false;

  if (target >= currentPlayPiece) {
    currentPlayPiece = Math.min(totalFileLast, target + 1);
  }

  updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);

  if (ring) ring.setPlayhead(currentPlayPiece);

  process.stdout.write(
    `CMD:skip piece=${target} hadWaiter=${hadWaiter} play=${currentPlayPiece} ` +
    `(${hadWaiter ? 'pump released' : 'queued'})\n`
  );
}

function handleRewindowCommand() {
  // v17.8: staleness gate removed — see CHANGELOG.
  if (lastMpvPosAt > 0) {
    applyMpvPosition(lastMpvPosSec, lastKnownDuration || undefined);
  }
  process.stdout.write(`CMD:rewindow play=${currentPlayPiece}\n`);
  updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
}

function handleRefreshCommand() {
  // v17.8: was missing entirely — REFRESH (button + the automatic
  // mpv-pos-stale recovery call above) reselected currentWindow around an
  // uncorrected currentPlayPiece, re-affirming the wrong window. See CHANGELOG.
  if (lastMpvPosAt > 0) {
    applyMpvPosition(lastMpvPosSec, lastKnownDuration || undefined);
  }
  process.stdout.write('CMD:refresh\n');

  // via debounce guard (see v17.34).
  throttleTrackerAnnounce('CMD:refresh');

  for (const wire of torrent.wires) {
    try { wire.keepAlive?.(); } catch (_) { }
  }

  // v17.9: always call updateSlidingWindow regardless of currentWindow —
  // a plain reselect skips adaptiveWindow.update(), leaving `ahead` stale.
  try {
    updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
    process.stdout.write(`CMD:refresh reselected play=${currentPlayPiece} win=[${currentWindow?.from},${currentWindow?.to}]\n`);
  } catch (e) {
    process.stdout.write(`CMD:refresh reselect ERR ${e?.message || e}\n`);
  }
}

// ─── applyMpvPosition ─────────────────────────────────────────────
let lastKnownDuration = 0;

function applyMpvPosition(seconds, duration) {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds) || seconds < 0) return null;
  if (typeof duration === 'number' && Number.isFinite(duration) && duration > 0) {
    lastKnownDuration = duration;
  }

  // v17.4: capture BEFORE overwriting — direction of `seconds` is the only
  // reliable seek-back signal. 30-min-freeze log: lastPos rose monotonically
  // despite a persistent 31-57 piece gap; a gap-size threshold misclassifies this.
  const prevSeconds = lastMpvPosSec;

  // v17.12: forward-jump filter must run BEFORE updating lastMpvPosSec —
  // v17.11 updated it to the Tip-B value first, poisoning prevSeconds for
  // the next Tip-A message. Fix: compute isForwardJump against prevSeconds first.
  const pieceLen = torrent.pieceLength;
  if (!pieceLen || currentFileLength <= 0) {
    lastMpvPosAt = Date.now(); // staleness only
    return null;
  }

  let absByte;
  if (lastKnownDuration > 0) {
    const frac = Math.max(0, Math.min(1, seconds / lastKnownDuration));
    absByte = currentFileOffset + Math.floor(frac * currentFileLength);
  } else {
    // v17.34: 1_000_000 bytes/sec is ~4× wrong for typical video; pinning to
    // fileStart is safe — window corrects on next /pos with duration.
    if (seconds > 0) {
      process.stdout.write(`POS:duration-zero-fallback seconds=${seconds} — pinned to fileFirst\n`);
    }
    absByte = currentFileOffset;
  }

  const piece = Math.floor(absByte / pieceLen);
  const clamped = Math.max(totalFileFirst, Math.min(totalFileLast, piece));

  // forward-jump filter: Tip B echo — update staleness clock only,
  // do NOT touch lastMpvPosSec so the next Tip-A is compared correctly.
  const isForwardJump = prevSeconds != null &&
    seconds > prevSeconds + POS_FORWARD_JUMP_SECS;
  if (isForwardJump) {
    // v17.23: timestamp window, not v17.22's single-use _pendingSeekPiece
    // flag — that missed cases where Swift's /pos arrives before the Range
    // request. A window catches forward-jump reports on either side of the seek.
    const _seekBypassActive = _pendingSeekAt > 0 &&
      (Date.now() - _pendingSeekAt) < SEEK_BYPASS_WINDOW_MS;
    if (_seekBypassActive) {
      const _seekAge = Date.now() - _pendingSeekAt;
      process.stdout.write(
        `POS:forward-jump-seek-bypass seconds=${seconds} prev=${prevSeconds} ` +
        `jump=${(seconds - prevSeconds).toFixed(1)}s seekAge=${_seekAge}ms — bypass filter\n`
      );
      _pendingSeekAt = 0; // close window — first valid /pos captured
      _fwdJumpStreak = 0;
      _fwdJumpStreakSec = null;
      // bypass active — fall through to normal path below, do not return
    } else {
      // v17.21: anchor advances each accepted step instead of locking to
      // the first sample (v17.17's bug) — mpv advances ~1.1-1.2s/poll, so a
      // fixed anchor almost never stayed within ±2s by the 3rd report.
      if (_fwdJumpStreakSec != null && Math.abs(seconds - _fwdJumpStreakSec) <= 2) {
        _fwdJumpStreak++;
        _fwdJumpStreakSec = seconds; // anchor advancing — update to previous sample
      } else {
        _fwdJumpStreak = 1;
        _fwdJumpStreakSec = seconds;
      }
      if (_fwdJumpStreak >= 3) {
        process.stdout.write(
          `POS:forward-jump-streak-accepted seconds=${seconds} prev=${prevSeconds} streak=${_fwdJumpStreak} — accepting as real position\n`
        );
        _fwdJumpStreak = 0;
        _fwdJumpStreakSec = null;
        // streak broke — fall through to normal path below, do not return
      } else {
        lastMpvPosAt = Date.now(); // keep staleness tracking alive
        mpvPosRecovering = false;
        _playerStalledAt = 0;
        process.stdout.write(
          `POS:forward-jump-filtered seconds=${seconds} prev=${prevSeconds} ` +
          `jump=${(seconds - prevSeconds).toFixed(1)}s > ${POS_FORWARD_JUMP_SECS}s threshold — window+lastMpvPosSec unchanged\n`
        );
        return clamped;
      }
    }
  } else {
    _fwdJumpStreak = 0;
    _fwdJumpStreakSec = null;
    _pendingSeekAt = 0; // small step arrived — close seek bypass window
  }

  // Normal path: commit the position.
  lastMpvPosSec = seconds;
  lastMpvPosAt = Date.now();
  mpvPosRecovering = false;
  _playerStalledAt = 0; // v17.6: new /pos — stall cleared, can re-fire
  _lastMpvPosStaleAt = 0; // real pos received — stale clock reset (see v17.34)
  _mpvSuppressedCount = 0; // v18.1: real pos advance — clear suppression counter

  const ring = getRing();
  const wasForward = clamped >= currentPlayPiece;

  if (wasForward) {
    currentPlayPiece = clamped;
    if (ring) ring.setPlayhead(currentPlayPiece);
    // v17.21: suppress window thrash — a second forward update within
    // WINDOW_FORWARD_DEBOUNCE_MS leaves the window untouched (currentPlayPiece
    // still advances; window catches up next debounce window). Stops Tip-A/Tip-B jump pairs from yanking the window back and forth within ~2s.
    const nowFwd = Date.now();
    // v17.22/23: Range handler sets _lastWindowForwardAt=0 on seek, so the
    // debounce gate is open and the first post-seek /pos always passes (nowFwd - 0 ≥ 1500), no extra delay.
    if (nowFwd - _lastWindowForwardAt >= WINDOW_FORWARD_DEBOUNCE_MS) {
      _lastWindowForwardAt = nowFwd;
      updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
    }
  } else {
    // v17.4: clamped < currentPlayPiece. Only a real drop in `seconds`,
    // not gap size, is a genuine seek-back — shrinking _evict()'s window
    // on a lagging-but-rising seconds strands ahead-pieces (bitfield never un-sets on evict; the 30-min-freeze cause).
    const isGenuineSeekBack = prevSeconds != null && seconds < prevSeconds - 1;
    if (isGenuineSeekBack) {
      currentPlayPiece = clamped;
      if (ring) ring.setPlayhead(currentPlayPiece);
      updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
      process.stdout.write(`POS:seekback play=${currentPlayPiece} from=${prevSeconds} to=${seconds}\n`);
    }
    // else: lagging/buffering echo — lastMpvPosSec/lastMpvPosAt already
    // updated above for staleness tracking; currentPlayPiece and ring
    // playhead are left untouched.
  }

  return clamped;
}

process.stdin.setEncoding('utf8');
let stdinPending = '';
process.stdin.on('data', data => {
  stdinPending += data;
  if (stdinPending.length > 65536) { stdinPending = ''; process.stdout.write('CMD:input-too-long\n'); return; }
  let newline;
  while ((newline = stdinPending.indexOf('\n')) !== -1) {
    const line = stdinPending.slice(0, newline).trim();
    stdinPending = stdinPending.slice(newline + 1);
    if (!line) continue;

    if (line.startsWith('SELECT:')) {
      const idx = parseInt(line.split(':')[1]);
      if (!Number.isNaN(idx) && idx >= 0) {
        if (pendingVideoFiles && pendingStartServer &&
          idx < pendingVideoFiles.length) {
          // v17.35: cancel any in-progress auto-advance countdown.
          cancelAutoAdvance('SELECT:manual');
          cancelAutoPick();
          // v17.34: null before calling — prevents re-entry if a second
          // SELECT: arrives while startServer is running.
          lastKnownDuration = 0; // v17.34: stale duration from prior file must not poison new file
          process.stdout.write(`SELECT:reset-duration idx=${idx}\n`);
          const fn = pendingStartServer;
          pendingStartServer = null;
          _currentVideoIndex = idx; // v17.35: track which file is now playing
          fn(pendingVideoFiles[idx]);
        } else {
          // v17.34: metadata not yet arrived — buffer for replay.
          _pendingSelectIdx = idx;
        }
      }
    } else if (line === 'CANCEL_ADVANCE') {
      // v17.36: cancel countdown without switching files — stay on current episode.
      cancelAutoAdvance('CANCEL_ADVANCE:user');
    } else if (line === 'SKIP' || line.startsWith('SKIP:')) {
      const parts = line.split(':');
      const explicitPiece = parts.length > 1 ? parseInt(parts[1]) : null;
      try { handleSkipCommand(explicitPiece); } catch (e) {
        process.stdout.write(`CMD:skip ERR ${e?.message || e}\n`);
      }
    } else if (line === 'REWINDOW') {
      try { handleRewindowCommand(); } catch (e) {
        process.stdout.write(`CMD:rewindow ERR ${e?.message || e}\n`);
      }
    } else if (line === 'REFRESH') {
      try { handleRefreshCommand(); } catch (e) {
        process.stdout.write(`CMD:refresh ERR ${e?.message || e}\n`);
      }
    }
  }
});

// ─── STATS ────────────────────────────────────────────────────────
const LOG_PATH = '/tmp/wt_monitor.log';
if (process.env.GOR_WT_MONITOR_LOG === '1') {
  try { fs.writeFileSync(LOG_PATH, ''); } catch (_) { }
}

setInterval(() => {
  const ring = getRing();

  const statsJson = {
    session: process.pid,
    downloadSpeed: torrent.downloadSpeed,
    uploadSpeed: torrent.uploadSpeed,
    downloaded: torrent.downloaded,
    progress: torrent.progress,
    numPeers: torrent.numPeers,
    fileLength: currentFileLength,
    ratio: torrent.ratio,
  };
  process.stdout.write(`STATS:${JSON.stringify(statsJson)}\n`);

  const stalledPieceNow = ring && ring.waitedPieces.length
    ? ring.waitedPieces[0]
    : null;

  // v15.0: pipeline metrics added to STORE JSON
  const totalWireReqs = torrent.wires.reduce((sum, w) => {
    try { return sum + (w?.requests?.length ?? 0); } catch (_) { return sum; }
  }, 0);
  const frozenPipeline = _pipelineFrozenSince
    ? Date.now() - _pipelineFrozenSince
    : 0;

  const storeJson = {
    chunks: ring ? ring.chunks.size : 0,
    bytesMB: ring ? Math.round(ring.bytes / 1_048_576) : 0,
    put: ring ? ring.totalPut : 0,
    evicted: ring ? ring.totalEvicted : 0,
    live: ring ? ring.totalPut - ring.totalEvicted : 0,
    piece: currentPlayPiece,
    stalling: stallDetector.isStalling,
    stalledPiece: stalledPieceNow,
    windowActive: !!currentWindow,
    mpvPosAgeMs: lastMpvPosAt > 0 ? (Date.now() - lastMpvPosAt) : null,
    // v15: new pipeline metrics
    wireRequests: totalWireReqs,
    pipelineFrozenMs: frozenPipeline,
    verifiedCount: verifiedCount,
    // v17.7: player position and buffer health metrics
    playerSec: lastMpvPosSec,
    playerMin: lastMpvPosSec != null ? parseFloat((lastMpvPosSec / 60).toFixed(1)) : null,
    aheadSec: (currentWindow && lastKnownDuration > 0 && currentFileLength > 0)
      ? Math.floor((currentWindow.to - currentPlayPiece) * torrent.pieceLength / (currentFileLength / lastKnownDuration))
      : 0,
    dlGap: (lastMpvPosSec != null && lastKnownDuration > 0)
      ? currentPlayPiece - Math.floor(lastMpvPosSec / lastKnownDuration * (totalFileLast - totalFileFirst + 1))
      : 0,
    pumpActive: streamSession.isStreaming(),
    evictRate: ring ? parseFloat((ring.totalEvicted / Math.max(1, ring.totalPut) * 100).toFixed(1)) : 0,
  };
  process.stdout.write(`STORE:${JSON.stringify(storeJson)}\n`);

  const dl = (torrent.downloadSpeed / 1_048_576).toFixed(1);
  const ul = (torrent.uploadSpeed / 1_048_576).toFixed(1);
  const dn = (torrent.downloaded / 1_048_576).toFixed(0);
  const pct = (torrent.progress * 100).toFixed(1);
  const ram = ring ? Math.round(ring.bytes / 1_048_576) : 0;
  const cap = ring ? Math.round(ring.maxBytes / 1_048_576) : 0;
  const win = currentWindow
    ? `[${currentWindow.from},${currentWindow.to}](ahead=${adaptiveWindow.ahead})`
    : 'none';
  const line =
    `${new Date().toISOString().slice(11, 19)} ` +
    `dl=${dl}MB/s ul=${ul}MB/s dn=${dn}MB(${pct}%) ` +
    `peers=${torrent.numPeers} streams=${streamSession.count} ` +
    `ram=${ram}MB/${cap}MB chunks=${storeJson.chunks} ` +
    `evicted=${storeJson.evicted} waiting=${ring ? ring.waiterCount : 0} ` +
    `play=${currentPlayPiece} win=${win} stall=${stallDetector.isStalling} ` +
    `timeout=${stallDetector.pieceTimeout / 1000}s ` +
    `mpvPosAge=${storeJson.mpvPosAgeMs ?? 'never'}ms ` +
    `player=${lastMpvPosSec != null ? Math.floor(lastMpvPosSec) : 'never'}s` +
    `(${lastMpvPosSec != null ? (lastMpvPosSec / 60).toFixed(1) : ''}dk) ` +
    `gap=${storeJson.dlGap}piece pump=${streamSession.isStreaming() ? 1 : 0} ` +
    `wireReqs=${totalWireReqs} pipeFreeze=${frozenPipeline}ms ` +
    `verified=${verifiedCount} hotswap=${hotswapCount} wireErr=${wireErrorCount}\n`;
  if (process.env.GOR_WT_MONITOR_LOG === '1') fs.appendFile(LOG_PATH, line, () => {});

  // v17.10: dl=0 streak → swarm reconnect.
  // Active stream + dl=0 for 60s triggers triggerSwarmReconnect.
  // Debounce (120s) is applied inside triggerSwarmReconnect.
  // v18.3: skip while explicitly paused — dl=0 is expected (nothing ahead
  // of an unmoving window needs fetching), not evidence of a dead swarm.
  const MIN_DL_FOR_RECONNECT = 50_000;
  if (streamSession.isStreaming() && torrent.downloadSpeed < MIN_DL_FOR_RECONNECT && !_isUserPaused) {
    if (!_dl0StreamingSince) _dl0StreamingSince = Date.now();
    const streakMs = Date.now() - _dl0StreamingSince;
    if (streakMs >= SWARM_RECONNECT_DL0_TRIGGER_MS) {
      triggerSwarmReconnect();
      _dl0StreamingSince = null; // reset for the next streak
    }
  } else {
    _dl0StreamingSince = null; // dl>0, no stream, or paused → reset streak
  }

  // v17.35: auto-advance near-end detection.
  // Only relevant for multi-video torrents where there is a next episode.
  // Trigger when playerSec is within the last 5% of duration or last 60s,
  // whichever window is larger. Once triggered, start the countdown unless
  // it is already running. Countdown is cancelled by any SELECT: command.
  if (pendingVideoFiles && pendingVideoFiles.length > 1 &&
    _currentVideoIndex >= 0 &&
    _currentVideoIndex < pendingVideoFiles.length - 1 &&
    lastMpvPosSec != null && lastKnownDuration > 0 &&
    streamSession.isStreaming() && !_autoAdvanceActive) {
    const remaining = lastKnownDuration - lastMpvPosSec;
    const threshold = Math.max(
      AUTO_ADVANCE_THRESHOLD_FRAC * lastKnownDuration,
      AUTO_ADVANCE_THRESHOLD_SECS
    );
    if (remaining > 0 && remaining <= threshold) {
      // v17.36: debounce — require DEBOUNCE_TICKS consecutive intervals
      // so a seek that momentarily lands near the end doesn't fire.
      _autoAdvanceNearEndTicks++;
      if (_autoAdvanceNearEndTicks >= AUTO_ADVANCE_DEBOUNCE_TICKS) {
        process.stdout.write(
          `AUTO_ADVANCE:near-end remaining=${remaining.toFixed(1)}s ` +
          `threshold=${threshold.toFixed(1)}s idx=${_currentVideoIndex} — starting countdown\n`
        );
        startAutoAdvanceCountdown();
      } else {
        process.stdout.write(
          `AUTO_ADVANCE:near-end-debounce remaining=${remaining.toFixed(1)}s ` +
          `tick=${_autoAdvanceNearEndTicks}/${AUTO_ADVANCE_DEBOUNCE_TICKS}\n`
        );
      }
    } else {
      // v17.36: player seeked away from end — reset debounce counter.
      if (_autoAdvanceNearEndTicks > 0) {
        process.stdout.write(`AUTO_ADVANCE:debounce-reset remaining=${remaining.toFixed(1)}s\n`);
        _autoAdvanceNearEndTicks = 0;
      }
    }
  }
}, 2_000);

// ─── Mime ─────────────────────────────────────────────────────────
const MIME = {
  mkv: 'video/x-matroska', mp4: 'video/mp4', avi: 'video/x-msvideo',
  mov: 'video/quicktime', webm: 'video/webm', ts: 'video/mp2t',
  m2ts: 'video/mp2t', m4v: 'video/mp4',
  opus: 'audio/ogg', ogg: 'audio/ogg', oga: 'audio/ogg', mp3: 'audio/mpeg',
  flac: 'audio/flac', m4a: 'audio/mp4', aac: 'audio/aac', wav: 'audio/wav',
};
// Without the dot check, split('.').pop() returns the whole name for
// extension-less files, which then matches nothing downstream.
const getExt = n => n.includes('.') ? n.split('.').pop().toLowerCase() : '';

// ═══════════════════════════════════════════════════════════════════
//  torrent metadata → startServer
// ═══════════════════════════════════════════════════════════════════
torrent.on('metadata', () => {
  process.stdout.write(
    `METADATA: ${torrent.name} ` +
    `(${(torrent.length / 1_073_741_824).toFixed(2)}GB, ` +
    `${torrent.pieces.length} pieces, ` +
    `pieceLen=${torrent.pieceLength})\n`
  );

  // Strict extension match first; extension-less torrents (e.g. Ogg/Opus
  // audio) would otherwise be rejected outright.
  let videoFiles = torrent.files.filter(f =>
    ['mkv', 'mp4', 'avi', 'webm', 'mov', 'ts', 'm2ts', 'm4v'].includes(getExt(f.name))
  );
  if (videoFiles.length === 0) videoFiles = torrent.files.slice();

  if (videoFiles.length === 0) {
    process.stderr.write('ERROR: No video file found\n');
    process.exit(1);
  }

  if (videoFiles.length === 1) {
    const f = videoFiles[0];
    const pLen = torrent.pieceLength;
    const fFirst = Math.floor((f.offset || 0) / pLen);
    const fLast = Math.floor(((f.offset || 0) + f.length - 1) / pLen);
    totalFileFirst = fFirst;
    totalFileLast = fLast;

    // v17.27: compute adaptive params early, push ramCap to the ring before
    // updateSlidingWindow/startServer — the ring starts at RAM_CAP_DEFAULT
    // (320MB) until startServer sets it later. Single-video path only; multi-video already gets it via startServer.
    if (pLen && pLen > 0) {
      const earlyParams = computeAdaptiveParams(pLen, torrent.pieces.length, f.length);
      const earlyRing = getRing();
      if (earlyRing) earlyRing.setMaxBytes(earlyParams.ramCap);
      // startServer will overwrite adaptiveParams and WINDOW_AHEAD_MAX;
      // this only closes the pre-startServer gap — no inconsistency risk
      // since the window isn't selected yet (see v17.27)
    }

    // v15.0: set currentPlayPiece to fFirst.
    // It used to stay at 0 in the previous version; the stall detector
    // went blind with activeStreams=0 and the window never shifted.
    currentPlayPiece = fFirst;
    const ring = getRing();
    if (ring) ring.setPlayhead(currentPlayPiece);

    updateSlidingWindow(fFirst, fFirst, fLast, false);
    process.stdout.write(`EARLY_WINDOW:done play=${currentPlayPiece}\n`);
  }

  // v17.34: track bound server so startServer can close it before rebinding.
  let activeServer = null;

  function startServer(file) {
    const ext = getExt(file.name);
    const mime = MIME[ext] || (ext === '' ? 'audio/ogg' : 'application/octet-stream');
    const pieceLen = torrent.pieceLength;
    const totalPieces = torrent.pieces.length;
    const fileOffset = file.offset || 0;
    const fileFirst = Math.floor(fileOffset / pieceLen);
    const fileLast = Math.floor((fileOffset + file.length - 1) / pieceLen);

    // v17.37: deselect old window and null currentWindow BEFORE updating
    // totalFileFirst/totalFileLast — a stall-check tick between these two
    // mutations would see mismatched globals and spuriously deselect the prior file's selection. Nulling makes stall-check see windowMissing=true instead.
    if (currentWindow) {
      try { torrent.deselect(currentWindow.from, currentWindow.to, false); } catch (_) { }
      currentWindow = null;
    }
    currentPlayPiece = fileFirst;

    totalFileFirst = fileFirst;
    totalFileLast = fileLast;
    currentFileOffset = fileOffset;

    // v17.13: recompute RAM_CAP/WINDOW_AHEAD_MAX from torrent metadata.
    // _evict(), AdaptiveWindow, and seekback filter read these module-level
    // vars — they auto-adapt when values change, no other code touched.
    adaptiveParams = computeAdaptiveParams(pieceLen, totalPieces, file.length);
    RAM_CAP_DEFAULT = adaptiveParams.ramCap;
    WINDOW_AHEAD_MAX = adaptiveParams.windowAheadMax;
    const ring = getRing();
    if (ring) ring.setMaxBytes(adaptiveParams.ramCap);
    process.stdout.write(
      `ADAPTIVE:params pieceLen=${pieceLen} totalPieces=${totalPieces} ` +
      `ramCap=${(adaptiveParams.ramCap / 1_048_576).toFixed(0)}MB ` +
      `windowAheadMax=${adaptiveParams.windowAheadMax} ` +
      `demux=${(adaptiveParams.demuxerMaxBytes / 1_048_576).toFixed(0)}M ` +
      `cacheSecs=${adaptiveParams.cacheSecs}\n`
    );

    const getPieceSize = idx => {
      if (idx < totalPieces - 1) return pieceLen;
      const rem = torrent.length % pieceLen;
      return rem === 0 ? pieceLen : rem;
    };

    process.stdout.write(
      `SERVING: ${file.name} ` +
      `(${(file.length / 1_073_741_824).toFixed(2)}GB) ` +
      `pieces=${fileFirst}-${fileLast} ${mime}\n`
    );
    currentFileLength = file.length;

    // ─── HTTP server ──────────────────────────────────────────
    const server = http.createServer(async (req, res) => {

      // CMD endpoint
      if (req.method === 'POST' && req.url === '/cmd') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
          const raw = body.trim();
          let line = raw;

          if (raw.startsWith('{')) {
            try {
              const payload = JSON.parse(raw);
              if (typeof payload.playhead === 'number') {
                applyMpvPosition(
                  payload.playhead,
                  typeof payload.duration === 'number' ? payload.duration : null
                );
                process.stdout.write(
                  `CMD:pos-sync playhead=${payload.playhead} play=${currentPlayPiece}\n`
                );
              }
              line = typeof payload.cmd === 'string' ? payload.cmd.trim() : '';
            } catch (e) {
              process.stdout.write(`CMD:bad-json ${e?.message || e}\n`);
              res.writeHead(400); res.end('bad json');
              return;
            }
          }

          if (line === 'SKIP' || line.startsWith('SKIP:')) {
            const parts = line.split(':');
            const explicitPiece = parts.length > 1 ? parseInt(parts[1]) : null;
            try { handleSkipCommand(explicitPiece); res.writeHead(200); res.end('OK'); }
            catch (e) { res.writeHead(500); res.end(e.message); }
          } else if (line === 'PAUSE') {
            // v18.3: explicit pause — see _isUserPaused declaration for why
            // this exists. Does not touch the pump/window/swarm; purely
            // tells the reconnect triggers "this is not a freeze."
            _isUserPaused = true;
            process.stdout.write('CMD:pause — reconnect triggers suppressed\n');
            res.writeHead(200); res.end('OK');
          } else if (line === 'RESUME') {
            _isUserPaused = false;
            // v18.3: resume is exactly when a stale mpv-pos clock or dl0
            // streak (both accrued harmlessly while paused) could misfire
            // as a freeze — clear both so resume starts with a clean window.
            _mpvSuppressedCount = 0;
            _dl0StreamingSince = null;
            // v19.3: also opens the forward-jump bypass window — previously
            // only the Range handler's isSeek branch did. _seekBypassActive
            // only checks recency, not who set it.
            _pendingSeekAt = Date.now();
            process.stdout.write('CMD:resume — reconnect triggers re-armed\n');
            res.writeHead(200); res.end('OK');
          } else if (line === 'REWINDOW') {
            try { handleRewindowCommand(); res.writeHead(200); res.end('OK'); }
            catch (e) { res.writeHead(500); res.end(e.message); }
          } else if (line === 'REFRESH') {
            try { handleRefreshCommand(); res.writeHead(200); res.end('OK'); }
            catch (e) { res.writeHead(500); res.end(e.message); }
          } else {
            process.stdout.write(`CMD:unknown command: ${line}\n`);
            res.writeHead(400); res.end('unknown command');
          }
        });
        return;
      }

      // POS endpoint
      if (req.method === 'POST' && req.url === '/pos') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
          try {
            const payload = JSON.parse(body || '{}');
            const playhead = typeof payload.playhead === 'number' ? payload.playhead : null;
            const duration = typeof payload.duration === 'number' ? payload.duration : null;
            if (playhead == null) {
              res.writeHead(400); res.end('missing playhead');
              return;
            }
            const piece = applyMpvPosition(playhead, duration);
            process.stdout.write(`POS:received playhead=${payload.playhead}s (piece=${piece})\n`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: true, piece }));
          } catch (e) {
            process.stdout.write(`POS:err ${e?.message || e}\n`);
            res.writeHead(400); res.end('bad json');
          }
        });
        return;
      }

      const rangeHeader = req.headers.range;

      if (req.method === 'HEAD') {
        res.writeHead(200, { 'Content-Length': file.length, 'Content-Type': mime, 'Accept-Ranges': 'bytes' });
        res.end();
        process.stdout.write('PROBE:HEAD\n');
        return;
      }
      // mpv may issue a rangeless GET solely to probe metadata. Preserve its
      // legacy response until the client's probe contract is tested on macOS.
      if (!rangeHeader) {
        res.writeHead(200, { 'Content-Length': file.length, 'Content-Type': mime, 'Accept-Ranges': 'bytes' });
        res.end();
        process.stdout.write('PROBE:GET\n');
        return;
      }

      const m = /bytes=(\d+)-(\d*)/.exec(rangeHeader);
      if (!m) {
        res.writeHead(416, { 'Content-Range': `bytes */${file.length}` });
        res.end();
        return;
      }

      const start = parseInt(m[1], 10);
      const end = m[2] ? parseInt(m[2], 10) : file.length - 1;
      let clampedEnd = Math.min(end, file.length - 1);

      if (isNaN(start) || start >= file.length || start > clampedEnd) {
        res.writeHead(416, { 'Content-Range': `bytes */${file.length}` });
        res.end();
        return;
      }

      const absStart = fileOffset + start;
      let absEnd = fileOffset + clampedEnd;
      const startPiece = Math.floor(absStart / pieceLen);
      let endPiece = Math.min(Math.floor(absEnd / pieceLen), fileLast);

     // v17.1: fullfile probe capped to FULLFILE_PROBE_CAP_PIECES pieces
     // so mpv gets a real 206 response for format/duration detection
     // without pumping the whole file. Treated like isMoovProbe.
      const isFullFileProbe = (start === 0 && clampedEnd >= file.length - 1024);
      if (isFullFileProbe) {
        endPiece = Math.min(startPiece + FULLFILE_PROBE_CAP_PIECES, endPiece);
        absEnd = Math.min((endPiece + 1) * pieceLen - 1, absEnd);
        clampedEnd = absEnd - fileOffset;
      }
      const chunkLen = clampedEnd - start + 1;

      process.stdout.write(
        `RANGE: bytes=${start}-${clampedEnd}/${file.length} ` +
        `(${(chunkLen / 1_048_576).toFixed(1)}MB) ` +
        `pieces=${startPiece}-${endPiece}\n`
      );

      const dedupResult = checkDuplicate(startPiece);
      if (dedupResult === 'reject') {
        process.stdout.write(`RANGE:reject pieces=${startPiece}-${endPiece}\n`);
        try {
          res.writeHead(429, { 'Content-Length': '0', 'Retry-After': '2' });
          res.end();
        } catch (_) { }
        return;
      }
      const isDup = dedupResult === 'duplicate';
      if (isDup) process.stdout.write(`RANGE:dup pieces=${startPiece}-${endPiece}\n`);

      // writeHead wrapped in try/catch: a closed socket here (mpv reconnect
      // churn) used to throw uncaught and leak a StreamSession generation
      // before begin() was even called (v16.1 fix).
      try {
        res.writeHead(206, {
          'Content-Range': `bytes ${start}-${clampedEnd}/${file.length}`,
          'Accept-Ranges': 'bytes',
          'Content-Length': chunkLen,
          'Content-Type': mime,
        });
      } catch (e) {
        process.stdout.write(`RANGE:writeHead-failed pieces=${startPiece}-${endPiece} ${e?.message || e}\n`);
        return;
      }
      try { res.socket.setNoDelay(true); } catch (_) { }

      // v17.34: floor prevents underflow on files smaller than MOOV_TAIL_PIECES;
      // without it every startPiece qualifies, freezing currentPlayPiece.
      const isMoovProbe = (fileLast - fileFirst >= MOOV_TAIL_PIECES) &&
        (startPiece >= fileLast - MOOV_TAIL_PIECES);
      // v17.1: fullfile probe gets the exact same treatment as moov probe
      // — neither should move currentPlayPiece or touch window state, both
      // are format/duration checks, not real seeks.
      const isProbeRequest = isMoovProbe || isFullFileProbe;
      let isForwardRequest = !isProbeRequest && startPiece >= currentPlayPiece;

      const windowMissing = !currentWindow;

        // v17.22: seek detection — out-of-window Range request. Triggers:
        //   A) _pendingSeekAt set → forward-jump bypass in applyMpvPosition
        //   B) abortPumpsOutsideWindow → old pumps killed immediately
        //   C) _lastWindowForwardAt=0 → post-seek window update not delayed
        //   D) out-of-window waiters flushed → resources freed for new region
        // Probe requests excluded. Both forward and backward directions.
      const isSeek = !isProbeRequest && !isDup && currentWindow &&
        (startPiece < currentWindow.from || startPiece > currentWindow.to);
      if (isSeek) {
        _pendingSeekAt = Date.now();    // A+E: open forward-jump bypass window
        _lastWindowForwardAt = 0;             // C: reset debounce
        abortPumpsOutsideWindow(startPiece);  // B: abort stale pumps
        // D: flush all waiters outside the current window
        const _seekRing = getRing();
        if (_seekRing) {
          let _flushed = 0;
          for (const idx of [..._seekRing.waitedPieces]) {
            if (idx < startPiece || idx > startPiece + WINDOW_AHEAD_MAX) {
              if (idx <= fileFirst) continue; // never flush the container header piece
              pieceFailureTracker.markManualSkip(idx);
              _seekRing.forceSkip(idx);
              _flushed++;
            }
          }
          if (_flushed > 0) {
            process.stdout.write(`SEEK:flush-waiters count=${_flushed} new-start=${startPiece}\n`);
          }
        }
        process.stdout.write(
          `SEEK:detected piece=${startPiece} prevWindow=[${currentWindow.from},${currentWindow.to}] ` +
          `dir=${startPiece >= currentPlayPiece ? 'forward' : 'backward'}\n`
        );
      }

      if (isProbeRequest) {
        // v17.34: suppress _selectHighPriority for probe pumps when a non-probe
        // pump is already active. Concurrent tail-file priority selections
        // compete with the playback window, starving pieces at file start.
        // registerPump hasn't run for us yet, so activePumps.size > 0 means
        // a pre-existing pump is active. torrent.select() still fires.
        try {
          const critEnd = Math.min(endPiece, fileLast);
          torrent.select(startPiece, critEnd, false);
          if (activePumps.size === 0) {
            _selectHighPriority(startPiece, critEnd);
          }
        } catch (_) { }
        const label = isMoovProbe ? 'RANGE:moov' : 'RANGE:fullfile-probe';
        process.stdout.write(`${label} pieces=${startPiece}-${endPiece} — capped-pump\n`);
        if (windowMissing) {
          process.stdout.write(`RANGE:probe-rewindow piece=${startPiece}\n`);
          updateSlidingWindow(currentPlayPiece, fileFirst, fileLast, true);
        }
      } else if (!isDup && isForwardRequest) {
        updateSlidingWindow(startPiece, fileFirst, fileLast, true);
      } else if (!isDup) {
        // v17.34: abort old pumps unconditionally on any backward non-dup request.
        // Previously only called on isSeek=true; in-window backward seeks left
        // the old pump running and advancing currentPlayPiece past the target.
        abortPumpsOutsideWindow(startPiece);

        // v15.0: priority selection instead of critical()
        _selectHighPriority(startPiece, Math.min(startPiece + LOOKAHEAD, fileLast));
        process.stdout.write(`RANGE:backward piece=${startPiece} play=${currentPlayPiece}\n`);

        // v17.22: isSeekBack threshold widened — out-of-window (isSeek)
        // is now sufficient. Small in-window backward seeks still use the
        // old currentPlayPiece - startPiece > WINDOW_AHEAD_MAX fallback.
        const isSeekBack = isSeek || currentPlayPiece - startPiece > WINDOW_AHEAD_MAX;
        if (windowMissing || isSeekBack) {
          const label = isSeekBack ? 'RANGE:seekback-rewindow' : 'RANGE:backward-rewindow';
          process.stdout.write(`${label} piece=${startPiece} play=${currentPlayPiece}\n`);
          currentPlayPiece = startPiece;
          updateSlidingWindow(startPiece, fileFirst, fileLast, true);
          isForwardRequest = true;
          if (isSeekBack) {
            const ring = getRing();
            if (ring) {
              for (const idx of ring.waitedPieces) {
                if (idx < startPiece || idx > startPiece + WINDOW_AHEAD_MAX) {
                  pieceFailureTracker.markManualSkip(idx);
                  ring.forceSkip(idx);
                }
              }
              process.stdout.write(`RANGE:seekback-flush-waiters start=${startPiece}\n`);
            }
          }
        }
      } else if (isDup && windowMissing) {
        process.stdout.write(`RANGE:dup-rewindow piece=${startPiece}\n`);
        currentPlayPiece = Math.max(currentPlayPiece, startPiece);
        updateSlidingWindow(currentPlayPiece, fileFirst, fileLast, true);
      }

      // ─── Pump ─────────────────────────────────────────────
      // streamGen stays null until streamSession.begin() succeeds inside
      // try{} below — if any setup call before that throws, finally's
      // null-check skips end(), so no generation leak (v16.1 fix; v16.0
      // called begin() outside try and could leak on a closed-socket throw).
      let streamGen = null;
      let pumpId = null;
      const abortCtrl = new AbortController();
      let aborted = false;
      const onClose = () => {
        if (!aborted) {
          aborted = true;
          try { abortCtrl.abort(); } catch (_) { }
        }
      };
        // v17.24: synchronous 'abort' listener on abortCtrl.signal. Without
        // it, RAM-cache-hit pumps never observe abort (they skip waitForPiece)
        // and keep force-advancing currentPlayPiece past the seek target.
      abortCtrl.signal.addEventListener('abort', () => { aborted = true; }, { once: true });
      let piece = startPiece;

      try {
        streamGen = streamSession.begin();
        if (!isDup && isForwardRequest) {
          currentPlayPiece = startPiece;
        }
        getRing()?.setPlayhead(currentPlayPiece);

        pumpId = registerPump(startPiece, abortCtrl);
        req.on('close', onClose);
        res.on('close', onClose);

        while (piece <= endPiece && !aborted) {
          const ring = getRing();
          if (!ring) break;

          // v17.2: heartbeat — refresh activePumps entry timestamp so the
          // GUARD interval's 120s expiry doesn't evict a long-running pump
          // as a leaked session. Observed 3 GUARD:leaked events when piece
          // 148 stalled 103s and its own activePumps entry expired mid-run.
          if ((piece - startPiece) % 10 === 0) {
            const _hb = activePumps.get(pumpId);
            if (_hb) _hb.ts = Date.now();
          }

          if (!isDup && isForwardRequest && piece > currentPlayPiece) {
            currentPlayPiece = piece;
            ring.setPlayhead(currentPlayPiece);
            updateSlidingWindow(piece, fileFirst, fileLast, true);
          } else {
            ring.setPlayhead(currentPlayPiece);
          }

          // Check store cache first — avoid waitForPiece if already in RAM
          let buf = ring.chunks.get(piece);
          let immediateZeroFill = false;
          if (!buf) {
            // v17.2: pre-check skips waitForPiece for already-marked pieces
            // (manual-skip or shouldZeroFill). Never applies to fileFirst
            // (container header — avformat_open_input fatal). Eliminates
            // 100s+ mpvPosAge accumulation across multi-piece zero-fill chains.
            if (piece > fileFirst &&
              (pieceFailureTracker.isManualSkip(piece) || pieceFailureTracker.shouldZeroFill(piece))) {
              immediateZeroFill = true;
            } else {
              // Quick peer availability check
              const peerCount = torrent.wires.length;
              const peersWithPiece = peerCount > 0
                ? stallDetector._countPeersWithPiece(piece, torrent)
                : -1;
              // Peer bitfields are only a snapshot. A peer may arrive shortly;
              // never omit bytes from the already advertised HTTP range.
              if (piece > fileFirst && peerCount > 0 && peersWithPiece === 0) {
                process.stdout.write(`PUMP:nopeers piece=${piece} peers=${peerCount} — waiting\n`);
              }
              // Heartbeat: refresh activePumps timestamp before blocking wait
              // so GUARD's 120s expiry never fires while we're in waitForPiece.
              const _hbWait = activePumps.get(pumpId);
              if (_hbWait) _hbWait.ts = Date.now();
              buf = await ring.waitForPiece(piece, stallDetector.pieceTimeout, abortCtrl.signal);
            }
          }

          if (aborted) break;

          if (!buf) {
            // v17.23: abort signal resolved waitForPiece to null — exit
            // without zero-fill. Old code entered the buf=null branch and
            // wrote phantom zeroBuf to the aborted connection before break.
            if (aborted) break;
            const wasManual = pieceFailureTracker.isManualSkip(piece);
            // v17.2: immediateZeroFill bypasses recordTimeout — outcome is
            // already determined and a false timeout entry would advance lastTs,
            // delaying PIECE_FAIL_RESET_MS expiry for the piece.
            const failCount = (wasManual || immediateZeroFill)
              ? PIECE_FAIL_THRESHOLD
              : pieceFailureTracker.recordTimeout(piece);

            if (!(wasManual || immediateZeroFill) && failCount < PIECE_FAIL_THRESHOLD) {
              process.stdout.write(
                `PUMP:timeout piece=${piece} fail=${failCount}/${PIECE_FAIL_THRESHOLD} — connection reset\n`
              );
              aborted = true;
              try { res.destroy(); } catch (_) { }
              break;
            }

            // v17.34: fileFirst must never reach zero-fill via the pump's own
            // timeout path; zero-filling it sends nulls as the EBML header.
            if (piece === fileFirst) {
              process.stdout.write(
                `PUMP:timeout-fileFirst piece=${piece} — connection reset (never zero-fill)\n`
              );
              aborted = true;
              try { res.destroy(); } catch (_) { }
              break;
            }

            // v15.0: zero-fill instead of skip-corrupt. Skipping left a hole
            // in the HTTP bytestream that lost mpv's NAL unit boundaries and
            // crashed the decoder; a zero-filled buffer degrades gracefully
            // (visual artifact, no crash) until the next keyframe recovers it.
            if (pieceFailureTracker.markSkippedOnce(piece)) {
              process.stdout.write(
                wasManual
                  ? `PUMP:zero-fill-manual piece=${piece} — zero fill (manual)\n`
                  : `PUMP:zero-fill-corrupt piece=${piece} fail=${failCount} — zero fill\n`
              );
            }

            // Compute piece size and send zero-filled buffer
            const pieceSize = getPieceSize(piece);
            const pieceAbsStart = piece * pieceLen;
            const sliceFrom = Math.max(absStart, pieceAbsStart) - pieceAbsStart;
            const sliceTo = Math.min(absEnd, pieceAbsStart + pieceSize - 1) - pieceAbsStart + 1;
            const zeroLen = Math.max(0, sliceTo - sliceFrom);

            if (zeroLen > 0) {
              const zeroBuf = Buffer.alloc(zeroLen, 0);
              const okZero = res.write(zeroBuf);
              if (!okZero && !aborted) {
                await new Promise(r => {
                  const onDrain = () => {
                    abortCtrl.signal.removeEventListener('abort', onAbortDrain);
                    r();
                  };
                  const onAbortDrain = () => {
                    res.removeListener('drain', onDrain);
                    r();
                  };
                  res.once('drain', onDrain);
                  abortCtrl.signal.addEventListener('abort', onAbortDrain, { once: true });
                });
              }
            }

            // Advance playhead past the skipped piece
            if (!isDup && isForwardRequest && piece >= currentPlayPiece) {
              currentPlayPiece = piece + 1;
              ring.setPlayhead(currentPlayPiece);
              updateSlidingWindow(currentPlayPiece, fileFirst, fileLast, true);
            }

            piece++;
            continue;
          }

          const pieceAbsStart = piece * pieceLen;
          const sliceFrom = Math.max(absStart, pieceAbsStart) - pieceAbsStart;
          const sliceTo = Math.min(absEnd, pieceAbsStart + buf.length - 1) - pieceAbsStart + 1;
          const chunk = buf.slice(sliceFrom, sliceTo);

          const ok = res.write(chunk);
          if (!ok && !aborted) {
            await new Promise(r => {
              const onDrain = () => {
                abortCtrl.signal.removeEventListener('abort', onAbortDrain);
                r();
              };
              const onAbortDrain = () => {
                res.removeListener('drain', onDrain);
                r();
              };
              res.once('drain', onDrain);
              abortCtrl.signal.addEventListener('abort', onAbortDrain, { once: true });
            });
          }

          piece++;
        }
      } catch (err) {
        process.stdout.write(`PUMP:err piece=${piece} ${err.message}\n`);
        aborted = true;
      } finally {
        if (!aborted) {
          try { res.end(); } catch (_) { }
        }
        req.removeListener('close', onClose);
        res.removeListener('close', onClose);
        if (pumpId !== null) unregisterPump(pumpId);
        // streamGen may be null if setup threw before begin() ran — guard
        // is mostly for clarity (end(null) is already a safe no-op).
        if (streamGen !== null) streamSession.end(streamGen);

        // v17.27: record abort time so the stall-check interval can
        // trigger recovery if mpv doesn't reconnect within PUMP_ABORT_RECOVERY_MS.
        // v19.0: two-part fix for staleness —
        //   (1) probe pumps (moov/fullfile) are short and capped; mpv closing
        //       that connection once it has enough data is expected behavior,
        //       not a real stream break, so probes must not set this flag.
        //   (2) the flag was previously only ever written on abort and never
        //       cleared on a clean finish, so a stale abort from pumps ago
        //       could sit latched indefinitely and fire a bogus recovery
        //       long after the stream had already recovered on its own.
        //       Every pump finish now reflects its own outcome.
        if (aborted) {
          if (!isProbeRequest) _lastPumpAbortAt = Date.now();
        } else {
          _lastPumpAbortAt = 0;
        }

        // v17.3: final-deselect removed. Deselecting on pump end empties
        // _selections — next WAKE has nothing to request. Window stays
        // active; updateSlidingWindow repositions it on next mpv connect.

        process.stdout.write(
          `PUMP:done piece=${piece}/${endPiece} aborted=${aborted} dup=${isDup}\n`
        );
      }
    });

    // v17.34: close the previous server before binding. http.Server.close()
    // stops new connections; active pump responses hold their own res ref
    // and complete or abort independently.
    if (activeServer) {
      try { activeServer.close(); } catch (_) { }
      activeServer = null;
    }
    activeServer = server;
    // v20.2: a dying predecessor can still hold the port for up to ~5s
    // (client.destroy watchdog). Retry the bind with backoff instead of
    // living serverless — the old path only logged and left mpv/HUD polling
    // a corpse, which read as permanent zero peers/speed on back-to-back magnets.
    let bindRetries = 0;
    server.on('error', e => {
      if (e && e.code === 'EADDRINUSE' && bindRetries < 12 && !_shuttingDown && activeServer === server) {
        const delay = 250 * ++bindRetries;
        process.stdout.write(`SERVER_ERR:${e.message} — bind retry ${bindRetries}/12 in ${delay}ms\n`);
        setTimeout(() => { if (activeServer === server) { try { server.listen(port, '127.0.0.1'); } catch (_) { } } }, delay);
      } else {
        process.stdout.write(`SERVER_ERR:${e.message}\n`);
      }
    });
    server.listen(port, '127.0.0.1', () => {
        // v17.13: PARAMS line emitted before STREAM: so Swift sets mpv
        // cache-secs/demuxer-max-bytes before opening the URL. Sent as a
        // separate line (not embedded in STREAM:) to avoid depending on how
        // mpv's HTTP demuxer handles query strings in media URLs.

      // v17.35: a new file just started — cancel any lingering countdown
      // (safety net; auto-advance path already clears _autoAdvanceActive).
      cancelAutoAdvance('startServer:new-file');

      // v17.35: restore pendingStartServer so the next episode (whether
      // triggered by auto-advance or a manual SELECT:) can call startServer.
      // pendingStartServer was nulled before the call to prevent re-entry;
      // restoring it here after bind ensures it is available for the next use.
      if (pendingVideoFiles && pendingVideoFiles.length > 1) {
        pendingStartServer = startServer;
      }

      process.stdout.write(`PARAMS:${JSON.stringify({
        demuxerMaxBytes: Math.round(adaptiveParams.demuxerMaxBytes),
        cacheSecs: adaptiveParams.cacheSecs,
      })}\n`);
      process.stdout.write(`STREAM:http://localhost:${port}\n`);
      process.stdout.write(`TITLE:${file.name}\n`);
    });
  }

  if (videoFiles.length > 1) {
    const listed = videoFiles.length > FILES_LIST_CAP ? videoFiles.slice(0, FILES_LIST_CAP) : videoFiles;
    process.stdout.write(`FILES:${JSON.stringify(
      listed.map((f, i) => ({ index: i, name: f.name, size: f.length }))
    )}\n`);
    if (listed.length < videoFiles.length) {
      process.stdout.write(`FILES_TRUNCATED:listed=${listed.length} total=${videoFiles.length}\n`);
    }
    // v17.34: multi-video path had no earlyParams — ring kept RAM_CAP_DEFAULT
    // (320MB) until startServer. Push ramCap for the first file now, matching
    // the single-video v17.27 fix. startServer overwrites with its file's params.
    const _ep0 = torrent.pieceLength > 0
      ? computeAdaptiveParams(torrent.pieceLength, torrent.pieces.length, videoFiles[0].length)
      : null;
    if (_ep0) { const _er0 = getRing(); if (_er0) _er0.setMaxBytes(_ep0.ramCap); }
    pendingVideoFiles = videoFiles;
    // v17.34: replay a SELECT: that arrived before metadata set pendingStartServer.
    if (_pendingSelectIdx !== null && _pendingSelectIdx < videoFiles.length) {
      const _ri = _pendingSelectIdx;
      _pendingSelectIdx = null;
      pendingStartServer = null; // consumed — prevent re-entry via stdin
      _currentVideoIndex = _ri;  // v17.35: track which file is now playing
      startServer(videoFiles[_ri]);
    } else {
      // v17.37: first episode — auto-advance needs a valid index from the start.
      // Without this, _currentVideoIndex stays -1 and the near-end gate never
      // fires for the first file (nextIdx = 0 always fails the >= length guard).
      _currentVideoIndex = 0;
      scheduleAutoPick();
    }
  } else {
    startServer(videoFiles[0] || torrent.files[0]);
  }
  // v18.2: pendingStartServer set unconditionally so both single-video and
  // multi-video paths have it available for auto-advance and SELECT: handling.
  // Previously only set inside the multi-video branch, leaving it null for
  // single-video torrents and preventing any subsequent startServer call.
  pendingStartServer = startServer;
});

client.on('error', e => {
  // v18.4: EADDRINUSE should no longer occur — we probe UDP 6771 before
  // creating the client and disable DHT preemptively if occupied. If it
  // fires anyway (race or a different port), log and continue — do NOT
  // destroy client.dht as that corrupts the client state. All other errors
  // are fatal (was: process.exit(1) unconditionally, which crashed the
  // server on any DHT bind conflict before this version's probe existed).
  if (e.code === 'EADDRINUSE') {
    process.stdout.write(`CLIENT_WARN:unexpected port conflict (${e.message}) — ignoring\n`);
    return;
  }
  process.stderr.write(`CLIENT_ERROR:${e.message}\n`);
  process.exit(1);
});
