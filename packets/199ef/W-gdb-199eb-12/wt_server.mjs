// wt_server.mjs — WebTorrent HTTP streaming server (magnet → mpv/ffmpeg via HTTP 206 range)
// CURRENT VERSION: 22.24-dev

// INVARIANT
//        - pump must never block forever —
//        - bound automatic waits by resetting HTTP; only explicit SKIP fills.
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
// v22.24 — Read-ahead byte target 256MB for >=30GB files and piece-count cap 16->32 (byte-neutral below 8MB pieces); 8-piece margin at 16MB pieces was ~17s, caused underruns (GOR-HEAT-BW-REMUX; native unverified).
// v22.23 — Cap peer connection attempts (maxConns 1000->200); ~900 half-open dials churned CPU on large swarms without adding connected peers (GOR-HEAT-BW-REMUX; native unverified).
// v22.22 — Frontier duplicate at most once per (piece,offset) per piece lifetime with holder-starvation gate, 10% payload dup budget, reader-owned eviction floor (arch-199w m3; harness, native unverified).
// v22.17 - Separate peer piece payload from socket traffic; HUD uses payload total, raw socket total remains diagnostic (Linux tested, native unverified).
// v22.12 - Post-seek reissue verification frees bounded holder pipeline room for the boosted play piece, reader-budget floor ignores never-advanced readers after 4s grace (log 260918: 153s seek stall).
// v22.10 - Stall escalation survives frozen-consumer reload gaps; retry-1 reissues the stalled piece instead of no-op window reselect; frozen-consumer reload gated off while the needed piece itself is missing (harness tested, native unverified).
// v22.9 - Add flag-gated (GOR_WT_PIECE_LEDGER=1, default OFF) read-only piece PUT/EVICT/pump diagnostics with log cap, no behavior change (native unverified).
// v22.8 - Gate stall detector, stuck-waiter flush, PLAYER:stalled and pump-abort recovery while user-paused, rebase stall clocks on resume (downloads and pins untouched, harness tested, native unverified).
// v22.7 - Retain live reader pieces, bound speculative range lead, require explicit seeks for range cancellation, recover frozen consumers on the same file.
// v22.6 - Advance only after near-final native EOF; fence playback telemetry and countdown by served-file token, reject retired ranges and positions.
// v22.5 - Repackage only: wt server logic identical to v22.4, shipped together with the survey-fixes Swift files and build.sh.
// v22.21 — Restrict tail retention and admission exemptions to real pins and active owners, avoiding consumed-tail refetch loops.
// v22.4 - Bound read-ahead and RAM admission, duplicate frontier blocks, reset seek state, ban corrupt peers, cancel proven snubs (harness tested, native unverified).
// v22.2 — Swap race window closed: signal handlers and tmp cleanup precede bootstrap, zombie sweep no longer blocks the loop, HTTP port released first on SIGTERM (scratch tested).
// v22.1 — Sole duplicate pump follows the sliding window; hash retries avoid stale cancellations and scale large-piece waits (scratch tested, native unverified).
// v22.0 — Automatic corruption/stall resets HTTP without injecting bytes or jumping playhead; explicit SKIP retains zero-fill (needs real test).
// v21.9 — STATS samples Node CPU and event-loop lag to separate swarm load from player capture contention (needs real test).
// v21.8 — experimental zero-request critical wake; bounded stall snapshots track wire requests, reservations, scheduler outcome (needs real test).
// v21.7 — hash-fail waiters: 10s bound + instant reissue + selection pin, spray VERDICT (4/5min), seek-orphan destroy, seek-no-follow watchdog.
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
// v17.32 — DL-gate: stall detector defers failure while downloadSpeed≥
//          512KB/s and peers have the piece, capped at 4x expected transfer time.
// v17.31 — fileFirst piece (holds the EBML header) protected from skip/
//          avoid premature timeout at all six call sites.
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
//          abort signal early-exits the missing-buffer path.
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
//          AdaptiveStallDetector, bounded failure, restartWaiter.

// KNOWN OPEN ITEMS:
//        - None. All previously listed items resolved across v17.8–v18.6.
//          See individual version entries for details.

import {createHash} from 'node:crypto';
import http from 'http';
import net from 'net';
import fs from 'fs';
import path from 'path';
import dgram from 'dgram';
import { fileURLToPath } from 'url';
import { execSync, execFile } from 'child_process';
import { makeLagSampler, makeHTTPTracer } from './diagnostics.mjs';
import { appendBounded } from './bounded_log.mjs';

// wt_full.log mirror must install before INIT writes, or earlier output
// reaches the terminal but never the log file (see v18.5).
const FULL_LOG_PATH = (process.env.GOR_LOG_SESSION_DIR || '/tmp') + '/wt_full.log';
// Production stdout is the Swift protocol. Disk mirroring is diagnostics only.
// v21.4: mirror on by default; GOR_WT_FULL_LOG=0 disables.
// In app capture mode Swift owns the sole admitted raw file. Never truncate
// it here or create unadmitted rotating mirrors / ancillary sample files.
const playerCapture = Boolean(process.env.GOR_PLAYER_LOG_ROOT && process.env.GOR_PLAYER_LOG_TOKEN);
const mirrorLog = !playerCapture && process.env.GOR_WT_FULL_LOG !== '0';
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

  if (mirrorLog) { try { appendBounded(FULL_LOG_PATH, prefixed); } catch (_) {} }
  return origStdoutWrite(chunk, encoding, cb);
};

// INIT must be the first line of output — any later anchor risks silently
// dropping earlier lines from log capture (see v18.4). DO NOT FORGET TO UPDATE HERE IN EACH VERSION!!!
process.stdout.write("INIT:v22.24-dev - remux read-ahead 256MB + ahead cap 32; v22.23-dev - peer connection cap 200 (pending-dial churn bound); v22.22-dev - frontier-dup once-per-piece-lifetime + holder-starvation gate + 10% payload dup budget + reader-owned eviction floor; v22.21-dev - bounded tail retirement and admission ownership; v22.20-dev - moov/header eviction pin (first 2 + last 3 pieces of the served file, ceiling 5 pieces, survives proactive+pump eviction); v22.19-dev - refetchedBytes session metric (piece payload re-stored after RAM eviction; makes the payload>downloaded gap attributable); v22.18-dev - capture-visible SELF row (pid + own-source sha256 + version) at startup and every 30 STATS ticks; v22.17-dev - separate piece payload and raw socket totals; v22.16-dev - stall-path room-free for pieceReq=0 play piece; v22.15-dev - FUNNEL discovery diagnostic + dead-wire eviction (never-delivered holders); v22.14-dev - STALL:holder per-peer detail for the stalled piece (read-only); v22.13-dev - frozen-consumer reload resumes in place (gate checks play frontier, not range start); v22.12 - post-seek reissue verification (bounded holder-room free) + reader-budget floor ignores never-advanced readers; v22.11 reader-floor stall release + reader-budget blocked logging; v22.10 stall escalation survives reload gaps, stalled-piece reissue on retry, frozen-consumer reload gated on missing piece\n");

// ─── Arguments ────────────────────────────────────────────────────
const diagnosticEmit = row => { try { process.stdout.write('WT_DIAG:' + JSON.stringify(row) + '\n'); } catch (_) { } };
const sampleNodeAfterLag = (playerCapture || process.env.GOR_WT_SAMPLE_FILES === '0') ? (() => {}) : makeLagSampler({pid:process.pid, directory:process.env.GOR_LOG_SESSION_DIR, platform:process.platform, execFile, emit:diagnosticEmit});

// v22.18-dev: self-identifying row. The periodic capture keeps only whitelisted
// WT_DIAG kinds; kind=self carries validated sha256/version so any bounded
// capture window names the exact file serving this process. No path: gor's own
// BACKEND_ACCEPT diagnostic already records the resolved script path.
const SELF_VERSION = 'v22.18-dev';
let _selfSha256 = 'unreadable';
try { _selfSha256 = createHash('sha256').update(fs.readFileSync(fileURLToPath(import.meta.url))).digest('hex'); } catch (_) { }
function emitSelfRow() {
  process.stdout.write(`WT_DIAG:${JSON.stringify({kind:'self',pid:process.pid,sha256:_selfSha256,version:SELF_VERSION})}\n`);
}
emitSelfRow();
const traceHTTPRequest = makeHTTPTracer({emit:diagnosticEmit});
const port = process.argv[2] === undefined ? 2222 : Number(process.argv[2]);
if (!Number.isInteger(port) || port < 0 || port > 65535) throw new Error('invalid HTTP port');
const magnet = process.argv[3];
if (!magnet) { process.stderr.write('ERROR: magnet required\n'); process.exit(1); }

// ─── Tmp dir ──────────────────────────────────────────────────────
const playerRoot = process.env.GOR_PLAYER_LOG_ROOT;
const playerToken = process.env.GOR_PLAYER_LOG_TOKEN;
if ((playerRoot || playerToken) && (!playerRoot || !path.isAbsolute(playerRoot) || !/^[0-9a-f]{32}$/.test(playerToken || ''))) {
  throw new Error('invalid player resource admission');
}
const runtimeRoot = process.env.GOR_PLAYER_RUNTIME_ROOT;
if (runtimeRoot && !path.isAbsolute(runtimeRoot)) throw new Error('invalid player runtime root');
// Log capture and resource storage have independent ownership. A valid app
// runtime root is supplied even when log capture is unavailable.
if (playerRoot && !runtimeRoot) throw new Error('player runtime root missing');
const tmpDir = runtimeRoot ? path.join(runtimeRoot, `wt_${process.pid}`) : `/tmp/wt_${process.pid}`;
fs.mkdirSync(tmpDir, { recursive: true });
// v22.2: boot stamp lets the zombie sweep reap only OLDER instances, never a newer swap target.
const BOOT_DIR = runtimeRoot ? path.join(runtimeRoot, 'wt_boot') : '/tmp/wt_boot';
const BOOT_MS = Date.now();
try { fs.mkdirSync(BOOT_DIR, { recursive: true }); fs.writeFileSync(`${BOOT_DIR}/${process.pid}`, String(BOOT_MS)); } catch (_) { }
// No stamp yet = either a crashed zombie or a newer instance still starting node; age tells them apart.
const isJustSpawned = (pid) => {
  try {
    const t = execSync(`ps -o etime= -p ${pid}`, { encoding: 'utf8' }).trim();
    const parts = t.split(/[-:]/).map(Number).reverse();
    const secs = (parts[0] || 0) + (parts[1] || 0) * 60 + (parts[2] || 0) * 3600 + (parts[3] || 0) * 86400;
    return secs < 3;
  } catch (_) { return false; }
};
const bootStampOf = (pid) => { try { return parseInt(fs.readFileSync(`${BOOT_DIR}/${pid}`, 'utf8'), 10); } catch (_) { return 0; } };

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
  // otherwise the next tick can call _selectBaseRange()/applyMpvPosition
  // against a torrent that's mid-destroy or already gone.
  if (_stallIntervalHandle) clearInterval(_stallIntervalHandle);
  try { PieceLedger.stop(); } catch (_) { } // TDZ-safe: SIGTERM may land before the ledger is defined
  // v22.2: release the HTTP port before the slow client.destroy.
  try { globalThis.__wtHttpServer?.close(); globalThis.__wtHttpServer?.closeAllConnections?.(); } catch (_) { }
  forceDestroyClient(() => {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) { }
    process.exit(0);
  });
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
process.on('exit', () => {
  try { PieceLedger.stop(); } catch (_) { }
  try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_) { }
  try { fs.rmSync(`${BOOT_DIR}/${process.pid}`, { force: true }); } catch (_) { }
});

const __dir = path.dirname(fileURLToPath(import.meta.url));
const wtPath = path.join(__dir, '..', 'webtorrent-cli', 'node_modules', 'webtorrent', 'index.js');
const { default: WebTorrent } = await import(wtPath);

// Orphan recovery is owned by the app's canonical-path/start-identity
// OrphanSweep. Never signal other players by command-line name here.

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
const WINDOW_AHEAD_MIN = 4;
let WINDOW_AHEAD_MAX = 16;
const WINDOW_AHEAD_DEFAULT = 8;
const WINDOW_BEHIND = 8;
const SEEK_BACK_RESERVE_BYTES = 8 * 1024 * 1024;
const behindPieces = pieceLen => Math.max(1, Math.ceil(SEEK_BACK_RESERVE_BYTES / pieceLen));
// v17.13: cap on WINDOW_AHEAD_MAX from computeAdaptiveParams() — prevents
// piece-count explosion on very small pieceLen (e.g. 256K).
const WINDOW_AHEAD_MAX_CAP = 32; // v22.24
// LOOKAHEAD now feeds priority selection, not critical() (see v15.0).
const LOOKAHEAD = 5;
const RESELECT_STRIDE = 3;
// Streak threshold before dead-zone-skip jumps WINDOW_AHEAD_MIN pieces at
// once instead of one piece at a time (see v17.26).
const DEAD_ZONE_SKIP_STREAK = 5;

// WT's own wire-level piece timeout is a hardcoded 30s; PIECE_TIMEOUT_MIN
// must stay above it or we reset before WT's own retry finishes
// (v15.0 set this to 8s, wrong; floor raised in v16.0).
const WT_WIRE_TIMEOUT_MS = 30_000;
const PIECE_TIMEOUT_BASE = 60_000;
const PIECE_TIMEOUT_STALL = 15_000;
const PIECE_TIMEOUT_MIN = WT_WIRE_TIMEOUT_MS + 5_000; // 35_000


// Large-piece retries need a full refill window (see v22.1).
const HASHFAIL_WAITER_MS = 10_000;
function hashFailWaiterMs(pieceLen) {
  if (pieceLen < 4 * 1024 * 1024) return HASHFAIL_WAITER_MS;
  // Bound the refill by measured throughput, with a safe floor and cap.
  const speed = Math.max(torrent?.downloadSpeed || 0, DL_GATE_LOW);
  return Math.min(90_000, Math.max(PIECE_TIMEOUT_MIN, Math.ceil(pieceLen / speed * 1_000 * 2)));
}
const RETRY_PIN_MAX = 8;
const SEEK_ORPHAN_GAP = 20;     // pieces; orphan farther than this = reader seeked away
const SEEK_JUMP_PIECES = 20;    // POS jump that arms the no-follow watchdog
const SEEK_NOFOLLOW_MS = 10_000;

const STALL_CHECK_MS = 3_000;
const STALL_THRESHOLD_MS = 6_000;
// Grace for a waiter's transient absence during a same-position stream reload
// (frozen-consumer recovery aborts the pump; the new waiter appears after the
// probes). Shorter than the reload cadence (30s), longer than any probe gap.
const STALL_WAITER_GAP_GRACE_MS = 15_000;
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

// Failure count threshold for integrity-stall diagnostics; automatic failures reset HTTP.
const PIECE_FAIL_THRESHOLD = 2;
const HOLD_MAX_WAITS = 3; // v22.3 B
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
// v22.24: remux-class files (>=30GB) get 256MB of read-ahead — 128MB is only
// ~17s at remux bitrates and 16MB pieces, too thin for swarm jitter (56 audio
// underruns in the heat session). Piece-cap 32 keeps this byte-neutral below
// 8MB pieces; RAM follows the existing ramCap formula (clamped by RAM_CAP_MAX).
const TARGET_AHEAD_BYTES_LARGE = 256 * 1024 * 1024;
const LARGE_FILE_BYTES = 30 * 1024 ** 3;
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

  const targetAheadBytes = fileLength >= LARGE_FILE_BYTES ? TARGET_AHEAD_BYTES_LARGE : TARGET_AHEAD_BYTES;
  let windowAheadMax = Math.round(targetAheadBytes / pieceLen);
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
// Exact raw info bytes bind v1 piece hashes to infohash, not index events.
function parseTorrentDigests(bytes, expectedInfoHash, limits) {
  if (!Buffer.isBuffer(bytes) || !Number.isSafeInteger(limits?.maxMetadataBytes) || limits.maxMetadataBytes<=0 || bytes.length>limits.maxMetadataBytes || !Number.isSafeInteger(limits?.maxPieces) || limits.maxPieces<=0 || typeof expectedInfoHash!=='string' || !/^[0-9a-f]{40}$/.test(expectedInfoHash)) throw new Error('metadata-binding');
  let p=0, infoSpan=null, nodes=0;
  const fail=()=>{throw new Error('invalid-bencode')};
  function ascii(slice) { if (slice.some(c=>c>=128)) fail(); return slice.toString('ascii'); }
  function parse(depth=0) {
    if(depth>32 || ++nodes>bytes.length || p>=bytes.length)fail();
    const start=p,c=bytes[p];
    if(c===105){p++;const z=bytes.indexOf(101,p);if(z<0)fail();const raw=ascii(bytes.subarray(p,z));if(!/^(0|-?[1-9][0-9]*)$/.test(raw))fail();const n=Number(raw);if(!Number.isSafeInteger(n))fail();p=z+1;return n;}
    if(c>=48 && c<=57){const z=bytes.indexOf(58,p);if(z<0)fail();const raw=ascii(bytes.subarray(p,z));if(!/^(0|[1-9][0-9]*)$/.test(raw))fail();const n=Number(raw);if(!Number.isSafeInteger(n)||n>bytes.length-z-1)fail();p=z+1+n;return bytes.subarray(z+1,p);}
    if(c===108){p++;const out=[];while(bytes[p]!==101)out.push(parse(depth+1));p++;return out;}
    if(c===100){p++;const out=new Map();let previous=null;while(bytes[p]!==101){const key=parse(depth+1);if(!Buffer.isBuffer(key)||previous&&Buffer.compare(previous,key)>=0)fail();previous=key;if (key.some(c=>c<32||c>=127)) fail(); const keyName=key.toString('ascii');const begin=p;const value=parse(depth+1);if(depth===0&&keyName==='info')infoSpan=[begin,p];out.set(keyName,value);}p++;return out;}
    fail();
  }
  const root=parse();if(p!==bytes.length||!(root instanceof Map)||!infoSpan)fail();const info=root.get('info');if(!(info instanceof Map))fail();
  const actual=createHash('sha1').update(bytes.subarray(...infoSpan)).digest('hex');if(actual!==expectedInfoHash)throw new Error('metadata-infohash-mismatch');
  const pieces=info.get('pieces'),pieceLength=info.get('piece length');if(!Buffer.isBuffer(pieces)||pieces.length===0||pieces.length%20||pieces.length/20>limits.maxPieces||!Number.isSafeInteger(pieceLength)||pieceLength<=0)throw new Error('metadata-piece-contract');
  let length=info.get('length');const files=info.get('files');
  if(files!==undefined){if(length!==undefined||!Array.isArray(files)||files.length===0)fail();length=0;for(const f of files){const n=f instanceof Map?f.get('length'):null;if(!Number.isSafeInteger(n)||n<0||!Number.isSafeInteger(length+n))fail();length+=n;}}
  if(!Number.isSafeInteger(length)||length<=0||Math.ceil(length/pieceLength)!==pieces.length/20)throw new Error('metadata-length-contract');
  const digests=new Map();for(let i=0;i<pieces.length/20;i++)digests.set(i,pieces.subarray(i*20,(i+1)*20).toString('hex'));
  return {infoHash:actual,pieceLength,length,digests};
}

// Read-only analysis seam: no torrent, HTTP, waiter or window methods.
class VerifiedCacheSnapshot {
  constructor({maxBytes, maxPieces, expectedDigests}) {
    if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0 || !Number.isSafeInteger(maxPieces) || maxPieces <= 0) throw new Error('snapshot limits required');
    this.expectedDigests = expectedDigests instanceof Map ? new Map(expectedDigests) : new Map();
    this.maxBytes = maxBytes; this.maxPieces = maxPieces;
    this.epoch = 0; this.confirmed = new Map();
  }
  invalidate() { this.epoch++; this.confirmed.clear(); }
  forget(index) { this.confirmed.delete(index); }
  verified(index, bytes) {
    if (Number.isSafeInteger(index) && index >= 0 && Buffer.isBuffer(bytes)) this.confirmed.set(index, bytes);
  }
  capture(chunks, first, last, expectedEpoch) {
    const hold = reason => Object.freeze({status:'HOLD', reason, epoch:this.epoch});
    if (expectedEpoch !== this.epoch) return hold('generation');
    if (!(chunks instanceof Map) || !Number.isSafeInteger(first) || !Number.isSafeInteger(last) || first < 0 || last < first || last-first+1 > this.maxPieces) return hold('range');
    const copies=[]; let bytes=0;
    for (let i=first; i<=last; i++) {
      const source=chunks.get(i);
      // The private copy's bound digest is proof; index-event order is not.
      if (!Buffer.isBuffer(source)) return hold('missing');
      if (source.length > this.maxBytes-bytes) return hold('byte-cap');
      const expected=this.expectedDigests.get(i);
      if (typeof expected!=='string' || !/^[a-f0-9]{40}$/.test(expected)) return hold('digest-unbound');
      const copy=Buffer.from(source);
      if (createHash('sha1').update(copy).digest('hex')!==expected) return hold('digest-mismatch');
      bytes+=copy.length; copies.push(Object.freeze({index:i, bytes:copy}));
    }
    // Returned buffers never alias playback. Consumer may mutate its private copy.
    return Object.freeze({status:'READY', epoch:this.epoch, first, last, bytes, pieces:Object.freeze(copies)});
  }
}

// v22.9: read-only piece ledger. OFF unless GOR_WT_PIECE_LEDGER=1; OFF = no arrays allocated, no timer, no output, no event state (the small counter object exists but stays zero).
// Never changes selection/eviction/pause behavior; every hook is try/caught. PUT-time owner state shows that
// moment only; the REQUEST that fetched the piece may have seen different owners.
const LEDGER_ON = process.env.GOR_WT_PIECE_LEDGER === '1';
const LEDGER_MAX_LINES = Math.max(50, parseInt(process.env.GOR_WT_PIECE_LEDGER_MAX_LINES, 10) || 3000);
const LEDGER_SNAP_ITEMS = 8;
const LEDGER_SNAP_PUMPS = 16; // bounded PUMPS row count (extra pumps counted, not listed)
const LEDGER_SNAP_OWNED = 32; // bounded owned-range count
const LEDGER_COUNT_MAX = 0xFFFFFFFF; // saturation: a repeat is never recounted as 'first'
const PieceLedger = {
  on: LEDGER_ON, n: 0, insertCount: null, lastEvictMs: null, lines: 0, dropped: 0, truncated: false, timer: null,
  agg: { firstPut: 0, repeatPut: 0, overwrite: 0, evict: 0, evictInSel: 0, repeatEvictInSel: 0, saturated: 0, snapPumpsOmitted: 0, snapOwnedOmitted: 0 },
  init(pieceCount) {
    if (!this.on || this.insertCount || !(pieceCount > 0)) return;
    this.n = pieceCount;
    this.insertCount = new Uint32Array(pieceCount);
    this.lastEvictMs = new Float64Array(pieceCount);
  },
  _now() { return Math.round(performance.now()); },
  _emit(line) {
    if (this.lines >= LEDGER_MAX_LINES) {
      this.dropped++;
      if (!this.truncated) {
        this.truncated = true;
        process.stdout.write(`LEDGER:truncated cap=${LEDGER_MAX_LINES} — further detail lines dropped, aggregates continue\n`);
      }
      return;
    }
    this.lines++;
    process.stdout.write(line + '\n');
  },
  // Same predicate as readerRetentionPiece(): which pumps pin the retention floor.
  _countedByRetention(o) {
    return !o.isProbe && !o.abortController.signal.aborted && !o.response.destroyed && Number.isSafeInteger(o.cursorPiece);
  },
  _effItems() {
    const items = (typeof torrent !== 'undefined' && torrent?._selections?._items) || [];
    return items;
  },
  // Effective range per vendor scheduler: [from+offset, to] (not nominal [from,to]).
  _inSel(idx) {
    const hits = [];
    for (const it of this._effItems()) if (idx >= it.from + (it.offset || 0) && idx <= it.to) hits.push(it);
    return hits;
  },
  // Lists the MATCHING items (those covering idx in effective range), bounded, with omitted count.
  _snap(items) {
    items = items || this._effItems();
    const out = items.slice(0, LEDGER_SNAP_ITEMS).map(it => `${it.isStreamSelection ? 's' : 'n'}${it.priority ?? 0}[${it.from},${it.to}]o${it.offset || 0}`);
    return out.join(',') + (items.length > LEDGER_SNAP_ITEMS ? `,+${items.length - LEDGER_SNAP_ITEMS}matchesOmitted` : '');
  },
  _ctx(ring) {
    const floor = readerRetentionPiece(ring ? ring._playhead : 0);
    const w = currentWindow ? `[${currentWindow.from},${currentWindow.to}]` : 'none';
    return `floor=${floor} retireCursor=${_retireCursor} win=${w} play=${currentPlayPiece}`;
  },
  onPut(ring, idx, isNew) {
    if (!this.on || !this.insertCount || !(idx >= 0 && idx < this.n)) return;
    try {
      if (!isNew) { this.agg.overwrite++; return; }
      if (this.insertCount[idx] >= LEDGER_COUNT_MAX) { this.agg.saturated++; this.agg.repeatPut++; return; }
      const c = ++this.insertCount[idx];
      const t = this._now();
      const le = this.lastEvictMs[idx];
      if (c === 1) {
        this.agg.firstPut++;
        this._emit(`LEDGER:PUT first idx=${idx} t=${t} n=1 ${this._ctx(ring)}`);
      } else {
        this.agg.repeatPut++;
        const sel = this._inSel(idx);
        this._emit(`LEDGER:PUT repeat idx=${idx} t=${t} n=${c} lastEvictAgoMs=${le ? t - le : -1} ${this._ctx(ring)} inEffSel=${sel.length} sel=${this._snap(sel)}`);
      }
    } catch (_) { }
  },
  onEvict(ring, idx, reason, cutoff) {
    if (!this.on || !this.insertCount || !(idx >= 0 && idx < this.n)) return;
    try {
      this.agg.evict++;
      const t = this._now();
      this.lastEvictMs[idx] = t;
      const sel = this._inSel(idx);
      const repeatable = this.insertCount[idx] >= 1;
      if (sel.length) { this.agg.evictInSel++; if (this.insertCount[idx] > 1) this.agg.repeatEvictInSel++; }
      this._emit(`LEDGER:EVICT idx=${idx} t=${t} reason=${reason} cutoff=${cutoff} ${this._ctx(ring)} n=${this.insertCount[idx]} inEffSel=${sel.length}${sel.length ? ' sel=' + this._snap(sel) : ''}${repeatable ? '' : ' unseen'}`);
    } catch (_) { }
  },
  aggLine(tag) {
    const a = this.agg;
    return `LEDGER:AGG ${tag} firstPut=${a.firstPut} repeatPut=${a.repeatPut} overwrite=${a.overwrite} evict=${a.evict} evictInSel=${a.evictInSel} repeatedPieceEvictInSel=${a.repeatEvictInSel} detailLines=${this.lines} droppedLines=${this.dropped} countSaturated=${a.saturated} snapPumpsOmitted=${a.snapPumpsOmitted} snapOwnedOmitted=${a.snapOwnedOmitted}`;
  },
  snapshotPumps(ring) {
    if (!this.on) return;
    try {
      const rows = [];
      let listed = 0, omitted = 0;
      for (const [id, o] of activePumps) {
        if (listed >= LEDGER_SNAP_PUMPS) { omitted++; continue; }
        listed++;
        const closed = !!(o.abortController?.signal?.aborted || o.response?.destroyed);
        let counted = false; try { counted = this._countedByRetention(o); } catch (_) { }
        const tok = typeof _activePlaybackToken === 'string' ? createHash('sha1').update(_activePlaybackToken).digest('hex').slice(0, 6) : 'none';
        rows.push(`#${id}{cur=${o.cursorPiece} start=${o.startPiece} probe=${!!o.isProbe} ${closed ? 'closed' : 'active'} countedByRetention=${counted} phase=${o.phase} globalTok=${tok}}`);
      }
      const all = _ownedRanges(ring);
      const ownedOmitted = Math.max(0, all.length - LEDGER_SNAP_OWNED);
      const owned = all.slice(0, LEDGER_SNAP_OWNED).map(r => `[${r[0]},${r[1]}]`).join('');
      this.agg.snapPumpsOmitted += omitted; this.agg.snapOwnedOmitted += ownedOmitted;
      this._emit(`LEDGER:PUMPS n=${activePumps.size} ${rows.join(' ')}${omitted ? ` +${omitted}pumpsOmitted` : ''} owned=${owned}${ownedOmitted ? ` +${ownedOmitted}rangesOmitted` : ''} ${this._ctx(ring)}`);
      process.stdout.write(this.aggLine('snapshot') + '\n');
    } catch (_) { }
  },
  start() {
    if (!this.on || this.timer) return;
    this.timer = setInterval(() => { try { this.snapshotPumps(getRing()); } catch (_) { } }, 10_000);
    this.timer.unref?.();
  },
  finalDone: false,
  stop() {
    if (this.timer) { clearInterval(this.timer); this.timer = null; }
    if (this.on && !this.finalDone) { this.finalDone = true; try { process.stdout.write(this.aggLine('final') + '\n'); } catch (_) { } }
  },
};

const RING_PIN_HEAD = 2, RING_PIN_TAIL = 3, RING_PIN_MAX = 5;

class RingBufferStore {
  constructor(chunkLength, opts) {
    this.chunkLength = chunkLength;
    this.length = (opts && typeof opts === 'object') ? opts.length : opts;
    this.chunks = new Map();
    this.analysisVerified = new Map();
    this.analysisPieceDigests = new Map();
    this.analysisEpoch = 0;
    this.bytes = 0;
    this.maxBytes = RAM_CAP_DEFAULT;
    this.closed = false;
    this.totalPut = 0;
    this.totalEvicted = 0;
    this._playhead = 0;
    this._waiters = new Map();
    // v22.17: container header piece (fileFirst: EBML/moov index). Never evicted by _evict()/_evictForPump():
    // reopens at byte 0 / header-range reads need it, and a refetch from peers takes >5 s (ffmpeg -rw_timeout).
    this.pinnedFirst = null;
    // v22.19: refetch accounting — indices evicted from RAM; a later put() of
    // the same index is a swarm refetch (first verify stays in torrent.downloaded).
    this._evictedOnce = new Set();
    // v22.20: moov/header pin — mpv re-probes the container head and the moov
    // tail with open-ended ranges; evicting those pieces forces a swarm
    // refetch on every revisit. Bounded by RING_PIN_MAX.
    this.pinned = new Set();
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
    const _isNewChunk = !this.chunks.has(index);
    if (!_isNewChunk) this.bytes -= this.chunks.get(index).length;
    else this.totalPut++;
    this.analysisVerified.delete(index);
    this.chunks.set(index, buf);
    this.bytes += buf.length;
    if (this._evictedOnce.delete(index)) _refetchedBytes += buf.length;
    PieceLedger.onPut(this, index, _isNewChunk);
    try { _onPieceStoredVerified(index); } catch (_) { } // v22.22
    this._evict();
    cb && cb(null);

    try { pieceFailureTracker.clear(index); } catch (_) { }
    try { // v21.7: verified — drop any retry pin and its priority selection
      if (_retryPins.delete(index) && !_torrentGone && typeof torrent !== 'undefined' && torrent && !torrent.destroyed) {
        torrent.deselect(index, Math.min(index + 1, totalFileLast), 2);
      }
    } catch (_) { }

    const waiters = this._waiters.get(index);
    if (waiters?.length) {
      const list = waiters.splice(0);
      this._waiters.delete(index);
      _refreshWaiterPriority(this);
      const stored = this.chunks.get(index) ?? buf;
      for (const { resolve, timer, onAbort, signal } of list) {
        clearTimeout(timer);
        if (signal && onAbort) signal.removeEventListener('abort', onAbort);
        resolve(stored);
      }
    }
  }

  bindAnalysisMetadata(rawTorrent, expectedInfoHash, limits) {
    const bound = parseTorrentDigests(rawTorrent, expectedInfoHash, limits);
    if (bound.pieceLength !== this.chunkLength || bound.length !== this.length) throw new Error('ring-metadata-mismatch');
    this.analysisEpoch++;
    this.analysisVerified.clear();
    this.analysisInfoHash = bound.infoHash;
    this.analysisPieceDigests = bound.digests;
    return this.analysisEpoch;
  }

  snapshotVerifiedRange(first, last, expectedEpoch, limits) {
    const snapshot = new VerifiedCacheSnapshot({...limits, expectedDigests: this.analysisPieceDigests});
    snapshot.epoch = this.analysisEpoch;
    snapshot.confirmed = this.analysisVerified;
    return snapshot.capture(this.chunks, first, last, expectedEpoch);
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
    _refreshWaiterPriority(this);
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
        _refreshWaiterPriority(this);
        entry.resolve(null);
      }, ms);
      entry.startTime = now; // reset for stuck-waiter detection
    }
    return true;
  }

  waitForPiece(index, ms, signal = null, pumpId = null) {
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
        _refreshWaiterPriority(this);
      };

      timer = setTimeout(() => { cleanup(); resolve(null); }, ms);

      if (signal) {
        if (signal.aborted) { clearTimeout(timer); return resolve(null); }
        onAbort = () => { cleanup(); resolve(null); };
        signal.addEventListener('abort', onAbort);
      }

      if (!this._waiters.has(index)) this._waiters.set(index, []);
      const entry = { resolve, timer, onAbort, signal, pumpId, playbackToken: activePumps.get(pumpId)?.playbackToken, startTime: Date.now() };
      this._waiters.get(index).push(entry);
      try { _refreshWaiterPriority(this); } catch (_) { }
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

  _isPinned(idx) {
    return idx === this.pinnedFirst || this.pinned.has(idx);
  }

  // v22.20: pin the container head (PIN_HEAD) and moov tail (PIN_TAIL) of the
  // served file. Ceiling RING_PIN_MAX pieces total; clamped to the file span.
  pinFileEdges(fileFirst, fileLast) {
    this.pinned.clear();
    if (!Number.isSafeInteger(fileFirst) || !Number.isSafeInteger(fileLast) || fileLast < fileFirst) return;
    for (let i = fileFirst; i <= Math.min(fileFirst + RING_PIN_HEAD - 1, fileLast); i++) this.pinned.add(i);
    for (let i = Math.max(fileLast - RING_PIN_TAIL + 1, fileFirst); i <= fileLast; i++) this.pinned.add(i);
    while (this.pinned.size > RING_PIN_MAX) this.pinned.delete(this.pinned.values().next().value);
    process.stdout.write(`RING-PIN: head=${RING_PIN_HEAD} tail=${RING_PIN_TAIL} pinned=${this.pinned.size} first=${fileFirst} last=${fileLast}\n`);
  }

  _evictForPump(neededIndex) {
    if (this.bytes < this.maxBytes * 0.85) return;
    const target = this.maxBytes * EVICT_TARGET;
    const cutoff = Math.min(neededIndex, readerRetentionPiece(this._playhead), readerOwnedRetentionFloor(this._playhead)) - behindPieces(this.chunkLength); // v22.22 reader-owned
    for (const idx of [...this.chunks.keys()].sort((a, b) => a - b)) {
      if (this.bytes <= target) break;
      if (idx >= cutoff) continue;
      if (this._isPinned(idx)) continue;
      const buf = this.chunks.get(idx);
      this.analysisVerified.delete(idx);
      this.chunks.delete(idx);
      this.bytes -= buf.length;
      this.totalEvicted++;
      if (this._evictedOnce.size >= 65536) this._evictedOnce.delete(this._evictedOnce.values().next().value);
      this._evictedOnce.add(idx);
      PieceLedger.onEvict(this, idx, 'pump', cutoff);
      this._notifyEvicted(idx);
    }
  }

  _evict() {
    if (this.bytes <= this.maxBytes * EVICT_TRIGGER) return;
    const before = this.bytes;
    const target = this.maxBytes * EVICT_TARGET;
    const cutoff = Math.min(readerRetentionPiece(this._playhead), readerOwnedRetentionFloor(this._playhead)) - behindPieces(this.chunkLength); // v22.22 reader-owned
    let removed = 0;
    for (const idx of [...this.chunks.keys()].sort((a, b) => a - b)) {
      if (this.bytes <= target) break;
      if (idx >= cutoff) continue;
      if (this._isPinned(idx)) continue;
      const buf = this.chunks.get(idx);
      this.analysisVerified.delete(idx);
      this.chunks.delete(idx);
      this.bytes -= buf.length;
      this.totalEvicted++;
      if (this._evictedOnce.size >= 65536) this._evictedOnce.delete(this._evictedOnce.values().next().value);
      this._evictedOnce.add(idx);
      removed++;
      PieceLedger.onEvict(this, idx, 'proactive', cutoff);
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
    _refreshWaiterPriority(this);
    this.analysisVerified.clear();
    this.analysisEpoch++;
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
      try { PieceLedger.init(Math.ceil(globalRing.length / chunkLength)); PieceLedger.start(); } catch (_) { }
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
//  tracks repeated failure; counter survives mpv reconnects via
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
    target = Math.min(target, WINDOW_AHEAD_MAX, ramPieces);

    if (target > this._ahead) this._ahead = Math.min(this._ahead + 8, target);
    else if (target < this._ahead) this._ahead = Math.max(this._ahead - 2, target);

    // Clamp the return too: _ahead eases down at -2/call, so without this
    // the first selects after a big pieceLen arrives still overshoot.
    return Math.min(Math.round(this._ahead), WINDOW_AHEAD_MAX, ramPieces);
  }

  setPieceLen(pieceLen) {
    this._pieceLen = pieceLen;
  }

  get ahead() {
    const cap = Math.min(WINDOW_AHEAD_MAX, this._ramPieces || WINDOW_AHEAD_MAX);
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
    // v22.10: last time the stalled piece was actually seen waiting. Tells a
    // reload probe gap (piece still missing, waiter briefly gone) apart from a
    // real advance, so escalation state survives the recovery loop.
    this._lastStalledSeenAt = 0;
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

  // v22.8: user-paused consumer is not a stall; keep the clock cleared, never run diagnostics/recovery.
  holdForPause() { this._reset(); }

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
    // v22.10: a same-position reload (frozen-consumer recovery) aborts the
    // playhead pump; its waiter vanishes for the probe gap and used to reset
    // all escalation state here (pieceChanged -> _reset()), pinning retry at
    // 1/2 forever (log 2026-10-17: 6 retries on piece 44, never escalated).
    // While the last stalled piece is still unverified and was seen waiting
    // within STALL_WAITER_GAP_GRACE_MS, a missing waiter means "reload gap",
    // not "piece moved" — keep the escalation clock and counter.
    let stalledCandidate = waitedPieces[0] ?? null;
    if (stalledCandidate == null && this._lastStalledPiece != null) {
      const stillMissing = !(torrent?.bitfield?.get(this._lastStalledPiece));
      const recent = Date.now() - (this._lastStalledSeenAt || 0) < STALL_WAITER_GAP_GRACE_MS;
      if (stillMissing && recent) stalledCandidate = this._lastStalledPiece;
    }
    const pieceChanged = stalledCandidate !== this._lastStalledPiece;
    if (stalledCandidate != null) this._lastStalledSeenAt = Date.now();
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

      // If peers report having the stuck piece, extend the wait before
      // resetting the HTTP range — fires on have>0 alone, since choked peers show dl≈0
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
          // v21.6: final-retry reissue (factored in v21.7, see _reissuePiece).
          try {
            const canceled = _reissuePiece(stalledPiece);
            process.stdout.write(`STALL:reissue piece=${stalledPiece} canceled=${canceled}\n`);
          } catch (e) {
            process.stdout.write(`STALL:reissue ERR ${e?.message || e}\n`);
          }
          this._retryCount = 0;
          return;
        }
        process.stdout.write(
          `STALL:dl-gate-expired piece=${stalledPiece} peers=${have}/${total} ` +
          `gateMs=${gateMs} maxWaitMs=${maxWaitMs.toFixed(0)} — reset waiter\n`
        );
      }

      try { if (have > 0) _rescueStuckBlock(stalledPiece); } catch (e) { process.stdout.write(`STALL:rescue ERR ${e?.message || e}\n`); }
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

    // Action 1: reissue the stalled piece itself. WT merges identical
    // overlapping selections, so the old deselect+select of the same window
    // was a no-op on wire traffic (log 2026-10-17: 6 reselects, no request
    // change). Cancel the piece's outstanding (snubbed) block requests so WT
    // re-reserves them on other wires; keep the window selection untouched.
    try {
      const canceled = _reissuePiece(stalledPiece);
      process.stdout.write(`STALL:reissue piece=${stalledPiece} canceled=${canceled}\n`);
    } catch (e) {
      process.stdout.write(`STALL:reissue ERR ${e?.message || e}\n`);
    }
    if (currentWindow) {
      try {
        // High-priority selection instead of critical() (see v15.0).
        _selectHighPriority(stalledPiece, Math.min(stalledPiece + LOOKAHEAD, fileLast));
        process.stdout.write(`STALL:priority [${stalledPiece},${Math.min(stalledPiece + LOOKAHEAD, fileLast)}] window [${currentWindow.from},${currentWindow.to}] kept\n`);
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
    this._lastStalledSeenAt = 0;
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
const _isDhtPortOccupied = () => new Promise(resolve => {
  const s = dgram.createSocket('udp4');
  s.once('error', () => resolve(true));
  s.bind(6771, '0.0.0.0', () => s.close(() => resolve(false)));
});
const _dhtPort = 0; // DHT owns its kernel-selected bind; no probe/release race.
const _dhtOccupied = await _isDhtPortOccupied();
process.stdout.write(`CLIENT:dht-probe requested=${_dhtPort} occupied6771=${_dhtOccupied} dht=on lsd=${!_dhtOccupied}\n`);

// Each player asks the kernel for its own peer listener too. A probe that
// closes before WebTorrent binds can race another player; do not reserve by age.
const TORRENT_LISTEN_PORT = 0;
process.stdout.write('CLIENT:torrent-port requested=0 kernel-assigned\n');

// v22.23: connection cap, shared by client opts and the FUNNEL hot marker.
const MAX_CONNS = 200;
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
  // v22.23: bound the pending-dial list; 900 half-open sockets sat against
  // ~40-60 live wires in the heat session. 200 leaves ~3x connected headroom.
  webSeeds: true, maxConns: MAX_CONNS, utp: process.platform !== 'darwin',
  alwaysChokeSeeders: false,
});
client.setMaxListeners(0);

const torrent = client.add(src, {
  path: tmpDir,
  store: RingStoreFactory,
  pieceAdmission: _admitStreamingPiece,
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

// v22.15-dev: FUNNEL diagnostic (read-only). Answers "search site claimed N
// sources, only a few connected": logs what trackers CLAIM (complete/incomplete
// per announce URL), how many peer addresses were DISCOVERED (torrent 'peer'
// events, by source when WT reports it), the pending candidate list, and how
// many are CONNECTED. No behavior change; every call is try/caught.
const _funnel = { discovered: 0, bySource: {}, tracker: {}, announces: 0, firstPeerMs: null, t0: Date.now() };
try {
  torrent.on('peer', (addr, source) => {
    _funnel.discovered++;
    const k = String(source || 'unknown');
    _funnel.bySource[k] = (_funnel.bySource[k] || 0) + 1;
    if (_funnel.firstPeerMs === null) _funnel.firstPeerMs = Date.now() - _funnel.t0;
  });
} catch (_) { }
let _funnelTrackerHooked = false;
const _funnelHookTimer = setInterval(() => {
  try {
    if (_funnelTrackerHooked || _torrentGone || _shuttingDown || !torrent || torrent.destroyed) { if (_funnelTrackerHooked) clearInterval(_funnelHookTimer); return; }
    const tr = torrent.discovery?.tracker;
    if (tr && typeof tr.on === 'function') {
      _funnelTrackerHooked = true;
      tr.on('update', (d) => {
        try {
          _funnel.announces++;
          const u = String(d?.announce || 'unknown').replace(/^[a-z]+:\/\//, '').split('/')[0];
          _funnel.tracker[u] = `${d?.complete ?? '?'}/${d?.incomplete ?? '?'}`;
        } catch (_) { }
      });
    }
  } catch (_) { }
}, 100);
_funnelHookTimer.unref?.();
const _funnelTimer = setInterval(() => {
  try {
    if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
    let claimSeeds = 0, claimLeech = 0;
    for (const v of Object.values(_funnel.tracker)) {
      const [c, i] = String(v).split('/').map(Number);
      if (Number.isFinite(c)) claimSeeds = Math.max(claimSeeds, c);
      if (Number.isFinite(i)) claimLeech = Math.max(claimLeech, i);
    }
    process.stdout.write(
      `FUNNEL: trackerClaimMax seeds=${claimSeeds} leechers=${claimLeech} ` +
      `trackersAnswered=${Object.keys(_funnel.tracker).length} announces=${_funnel.announces} ` +
      `discovered=${_funnel.discovered} bySource=${JSON.stringify(_funnel.bySource)} ` +
      `pending=${torrent._peersLength ?? '?'} connected=${torrent.numPeers} ` +
      `cap=${MAX_CONNS}${(torrent._peersLength ?? 0) > MAX_CONNS ? ' PENDING-OVER-CAP' : ''} ` +
      `firstPeerMs=${_funnel.firstPeerMs ?? 'none'} perTracker=${JSON.stringify(_funnel.tracker)}\n`
    );
  } catch (_) { }
}, 15_000);
_funnelTimer.unref?.();

// v21.2: one-time capability check — _markUnverified arrived in webtorrent
// #2757 (2.4+); without it _notifyEvicted silently no-ops and evicted
// pieces are never re-fetched. REQ: prefix so gor surfaces it (see v21.3).
if (typeof torrent._markUnverified === 'function') {
  process.stdout.write('REQ:caps markUnverified=ok\n');
} else {
  process.stdout.write('REQ:caps markUnverified=MISSING — upgrade vendored webtorrent (>=2.4); RAM eviction cannot re-request pieces\n');
}

// ─── Wire setup ─────────────────────────────────────────────────────
// Session lifetime: wire download counts piece payload, peer download also counts protocol traffic.
let _receivedPayloadBytes = 0;
// v22.19: piece payload re-stored after RAM eviction (mpv revisit of an evicted
// range forces a swarm refetch; downloaded counts first verify only).
let _refetchedBytes = 0;
const _bannedPeers = new Set();
const _wireProgress = new WeakMap();
function _hashFailPeerKey(wire) {
  return wire.peerId || `${wire.remoteAddress}:${wire.remotePort || ''}`;
}
torrent.on('wire', wire => {
  if (_bannedPeers.has(_hashFailPeerKey(wire))) {
    try { wire.destroy(); } catch (_) { }
    return;
  }
  _wireProgress.set(wire, { lastData: Date.now(), t0: Date.now(), received: 0, frontier: null, since: 0 });
  wire.on('download', bytes => {
    if (Number.isSafeInteger(bytes) && bytes > 0) _receivedPayloadBytes += bytes;
    const state = _wireProgress.get(wire);
    if (state && bytes > 0) { state.lastData = Date.now(); state.received += bytes; }
  });
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
// requests, never a web seed); sole holders use a longer streak.
// VERDICT: fires at monotone totals so the HUD can name a corrupt swarm
// instead of spinning silently.
const _hashFailStreak = new Map();
const _hashFailTotal = new Map();
const _hashFailBans = new Map();
const _verdictFired = new Set();
const HASHFAIL_BAN_STREAK = 4;
const HASHFAIL_SOLE_WIRE_MULTIPLIER = 2;
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
const _hashFailTimes = []; // v21.7: rolling global window for spray detection
function _recordHashFail(index) {
  {
    const now = Date.now();
    _hashFailTimes.push(now);
    while (_hashFailTimes.length && now - _hashFailTimes[0] > 300_000) _hashFailTimes.shift();
    const rolling = _hashFailTimes.length;
    // A corrupt peer spraying one bad block per piece never trips the
    // per-piece ban streak — surface it at 4/8/12... fails in 5min (see v21.7).
    if (rolling >= 4 && rolling % 4 === 0) {
      const key = `spray:${rolling}`;
      if (!_verdictFired.has(key)) {
        _verdictFired.add(key);
        process.stdout.write(`VERDICT:corrupt-suspect piece=${index} fails=${rolling} bans=0 peers=${torrent.wires.length} reason=spray-5min\n`);
      }
    }
  }
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
  const eligible = torrent.wires.filter(w => w.type !== 'webSeed' && w.peerPieces?.get(index));
  const soleWireBan = eligible.length === 1 && streak >= HASHFAIL_BAN_STREAK * HASHFAIL_SOLE_WIRE_MULTIPLIER;
  if ((streak >= HASHFAIL_BAN_STREAK && torrent.wires.length > 1) || soleWireBan) {
    let suspect = null;
    for (const w of torrent.wires) {
      if (w.type === 'webSeed') continue;
      if (!w.peerPieces?.get(index)) continue;
      if (!suspect || (w.requests?.length || 0) > (suspect.requests?.length || 0)) suspect = w;
    }
    if (suspect) {
      process.stdout.write(`HASH:fail-ban piece=${index} wire=${suspect.remoteAddress || 'unknown'} streak=${streak} sole=${soleWireBan}\n`);
      _bannedPeers.add(_hashFailPeerKey(suspect));
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
      const retryWaitMs = hashFailWaiterMs(torrent.pieceLength);
      const restarted = ring.restartWaiter(index, retryWaitMs);
      try { _refreshWaiterPriority(ring); } catch (_) { }
      try {
        _pinRetry(index);
        // Old requests belong to the discarded Piece (see v22.1).
        if (!torrent.destroyed) torrent._update();
      } catch (_) { }
      process.stdout.write(
        `HASH:fail piece=${index} waiter-restarted=${restarted} — pinned, retry bound ${retryWaitMs}ms (fresh-piece-safe)\n`
      );
      // v22.0: record the failed verification for diagnosis; the bounded
      // waiter resets HTTP if WT cannot replace it with verified bytes.
      pieceFailureTracker.recordTimeout(index);
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
          `${failCount >= PIECE_FAIL_THRESHOLD ? ' — THRESHOLD reached, next pump waits for verified bytes' : ' — WT retry pending'}\n`
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
  const cachedVerified = ring?.chunks.get(index);
  if (Buffer.isBuffer(cachedVerified)) ring.analysisVerified.set(index, cachedVerified);
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

// ─── Tracker injection ──────────────────────────────────────────
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
let _deadObservedOwner = null;
let _lastRangeStartPiece = -1, _lastStreamActivityAt = 0, _lastSkipAt = 0, _deadReqAt = 0, _deadPos = null, _deadPosSince = 0; // v22.3
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
// v21.8: sampled only at reissue, never per block or per WT scheduler tick.
// The vendored WT exposes no pending _update queue count; snapshot before
// and after the wake instead of reporting an invented queue depth.
// v22.14: per-peer detail for the stalled piece (read-only). Piece 2 of session
// 77383 stalled 4 min with holders=0-2 and no way to tell which peer had it,
// what was reserved on it, or whether the peer ever answered. idleMs = time
// since this wire's downloaded-byte counter last advanced, as seen by earlier
// snapshots (first sight = "new"); it is observation cadence, not a wire timestamp.
const _wireDlSeen = new WeakMap();
function _holderDetail(w, index, now) {
  const requests = w.requests || [];
  let reqN = 0, reqBytes = 0;
  for (const r of requests) if (r.piece === index) { reqN++; reqBytes += (r.length || 0); }
  const dl = w.downloaded || 0;
  const prev = _wireDlSeen.get(w);
  let idle = 'new';
  if (!prev) _wireDlSeen.set(w, { dl, advancedAt: now });
  else { if (dl > prev.dl) { prev.dl = dl; prev.advancedAt = now; } idle = String(now - prev.advancedAt); }
  const has = !!w.peerPieces?.get(index);
  const addr = String(w.remoteAddress || w.remoteAddr || w.peerId || '?').replace(/\s/g, '');
  return `${addr} has=${has ? 1 : 0} choke=${w.peerChoking ? 1 : 0} pieceReq=${reqN} reservedBytes=${reqBytes} allReq=${requests.length} dl=${dl} idleMs=${idle}`;
}

function _stallPieceSnapshot(index, phase) {
  if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
  const wireSamples = [];
  let holders = 0, unchokedHolders = 0, pieceRequests = 0, allRequests = 0, fullPipelines = 0;
  for (const w of torrent.wires) {
    if (!w || w.destroyed) continue;
    const requests = w.requests || [];
    const has = !!w.peerPieces?.get(index);
    const count = requests.reduce((n, r) => n + (r.piece === index ? 1 : 0), 0);
    if (has) { holders++; if (!w.peerChoking) unchokedHolders++; }
    pieceRequests += count;
    allRequests += requests.length;
    // WT's precise pipeline limit depends on live speed/reqq. Two requests
    // is its floor, not a claim that every fuller wire is saturated.
    if (requests.length >= 2) fullPipelines++;
    if (wireSamples.length < 24 && (has || count)) {
      wireSamples.push(`${has ? 1 : 0}${w.peerChoking ? 'c' : 'u'}:${count}/${requests.length}`);
    }
  }
  const reservations = torrent._reservations?.[index];
  let occupiedReservations = 0;
  if (Array.isArray(reservations)) {
    for (const r of reservations) if (r != null) occupiedReservations++;
  }
  const piece = torrent.pieces?.[index];
  const selected = [...(torrent._selections || [])].some(s => s.from + s.offset <= index && index <= s.to);
  process.stdout.write(
    `STALL:piece-diag phase=${phase} piece=${index} holders=${holders}/${torrent.wires.length} ` +
    `unchoked=${unchokedHolders} pieceReq=${pieceRequests} allReq=${allRequests} ` +
    `wiresReq2plus=${fullPipelines} reservations=${occupiedReservations}/${reservations?.length ?? 0} ` +
    `missing=${piece?.missing ?? 'none'} selected=${selected} critical=${!!torrent._critical?.[index]} ` +
    `verified=${!!torrent.bitfield?.get(index)} updateQueue=unobservable ` +
    `wires(has,choke:pieceReq/allReq)=[${wireSamples.join(',')}]\n`
  );
  // v22.14: one line per wire that holds the piece or has requests on it (cap 8).
  try {
    const now = Date.now();
    let shown = 0;
    for (const w of torrent.wires) {
      if (!w || w.destroyed) continue;
      const touches = !!w.peerPieces?.get(index) || (w.requests || []).some(r => r.piece === index);
      const d = _holderDetail(w, index, now);
      if (!touches || shown >= 8) continue;
      shown++;
      process.stdout.write(`STALL:holder phase=${phase} piece=${index} ${d}\n`);
    }
    if (shown === 0) process.stdout.write(`STALL:holder phase=${phase} piece=${index} none (no wire has or is requested it; wires=${torrent.wires.length})\n`);
  } catch (_) { }
}
// v21.6 dl-gate reissue, factored so the v21.7 hash-fail path reuses it:
// release the piece's stranded block reservations on every wire, re-request
// now (WT hotswap pattern — late dupes ignored by piece.set).
function _reissuePiece(index) {
  _stallPieceSnapshot(index, 'before');
  const piece = torrent?.pieces?.[index];
  if (!piece || typeof piece.cancel !== 'function') return 0;
  const canceled = typeof torrent.cancelRequests === 'function'
    ? torrent.cancelRequests(req => req.piece === index)
    : 0;
  // v22.12: also drop the piece-level reservation state. A cancel sweep can
  // leave reservations with no matching wire requests (canceled === 0 while
  // the piece stays unreservable); Piece.cancel() is the hotswap primitive
  // this path always probed for but never called.
  try { piece.cancel(); } catch (_) { }
  if (canceled === 0 && _waiterBoost?.from === index && !_torrentGone && !_shuttingDown && !torrent.destroyed) {
    // v21.8: public critical wakes the selected waiter. WT merges
    // overlapping selections, so reselecting cannot isolate it.
    torrent.critical(index, index);
    process.stdout.write(`STALL:reissue-wake piece=${index} critical=1\n`);
  }
  if (!torrent.destroyed) torrent._update();
  _stallPieceSnapshot(index, 'wake-issued');
  // WT may schedule its _update callback later. A delayed observation tells
  // whether piece requests appeared without patching its scheduler hot path.
  setTimeout(() => _stallPieceSnapshot(index, 'after-250ms'), 250).unref();
  setTimeout(() => _stallPieceSnapshot(index, 'after-1500ms'), 1500).unref();
  // v22.16: non-seek stalls get the same bounded room-free as post-seek.
  _armStallRoomReissue(index);
  return canceled;
}

// v22.12: post-seek reissue verification. Log 260918: after SEEK:cancel-requests
// (count=104, keep=[428,452]) the boosted play piece 436 sat 21s with
// pieceReq=0 reservations=0/0 while 7-8 unchoked holders ran 104-142 requests
// for everything else; STALL:reissue's cancel (0 matched) + critical + _update
// stayed inert until the scheduler reached the piece on its own. The sweep
// leaves saturated pipelines; boost/critical alone cannot cut through. Verify
// at +3s/+8s that the play piece actually has outstanding requests; if not,
// free bounded room on the piece's own unchoked holders so the next _update
// reserves the critical piece there.
const POST_SEEK_REISSUE_CHECK_MS = [3_000, 8_000];
const POST_SEEK_REISSUE_FREE_PER_WIRE = 3;
let _postSeekReissueGen = 0;

function _outstandingRequestsForPiece(index) {
  let n = 0;
  for (const w of torrent?.wires || []) {
    if (!w || w.destroyed) continue;
    for (const r of (w.requests || [])) if (r.piece === index) n++;
  }
  return n;
}

function _reissueRoomForPiece(index) {
  if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return 0;
  let freed = 0;
  for (const w of torrent.wires) {
    if (!w || w.destroyed || w.type === 'webSeed') continue;
    let has = false;
    try { has = !!w.peerPieces?.get(index); } catch (_) { }
    if (!has || w.peerChoking) continue;
    if (typeof torrent.cancelRequests !== 'function') break;
    // Free this holder's requests FARTHEST from the play piece; the piece's
    // own requests are never touched. WT re-reserves freed slots honoring
    // critical(), which marks the play piece for these very wires.
    // Radius guard: the play piece's immediate neighbors are next in line for
    // playback; never churn them to make room.
    const targets = (w.requests || [])
      .filter(r => r.piece !== index && Math.abs(r.piece - index) > 2)
      .sort((a, b) => Math.abs(b.piece - index) - Math.abs(a.piece - index))
      .slice(0, POST_SEEK_REISSUE_FREE_PER_WIRE);
    for (const t of targets) {
      freed += torrent.cancelRequests((req, wire) => wire === w && req === t);
    }
  }
  return freed;
}

function _armPostSeekReissue(piece) {
  const gen = ++_postSeekReissueGen;
  for (const delay of POST_SEEK_REISSUE_CHECK_MS) {
    setTimeout(() => {
      if (gen !== _postSeekReissueGen) return;
      if (_isUserPaused || _torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
      if (torrent.bitfield?.get(piece)) return; // already have it
      if (_outstandingRequestsForPiece(piece) > 0) return; // scheduler got there
      let freed = 0;
      try { freed = _reissueRoomForPiece(piece); } catch (_) { }
      try { torrent.pieces?.[piece]?.cancel?.(); } catch (_) { }
      try { torrent.critical(piece, piece); } catch (_) { }
      try { torrent._update(); } catch (_) { }
      process.stdout.write(`SEEK:reissue piece=${piece} freed=${freed} at=${delay}ms
`);
    }, delay).unref();
  }
}

// v22.16: stall-path room-free. Log 261026 (Crystal.Lake S01E06, no seek):
// the play piece sat with pieceReq=0 reservations=0/0 on 6-9 unchoked holders
// whose queues were full of later pieces; 10 of 28 stall reissues still had
// pieceReq=0 at +1500ms, playhead froze 3-12s at a time. Same remedy as the
// post-seek check, armed from every stall reissue. Bounded: 3 requests/wire,
// farthest from the play piece, radius guard kept, one check per reissue.
const STALL_REISSUE_CHECK_MS = [1_500, 5_000];
let _stallRoomGen = 0;
function _armStallRoomReissue(piece) {
  const gen = ++_stallRoomGen;
  for (const delay of STALL_REISSUE_CHECK_MS) {
    setTimeout(() => {
      if (gen !== _stallRoomGen) return;
      if (_isUserPaused || _torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
      if (torrent.bitfield?.get(piece)) return;
      if (_outstandingRequestsForPiece(piece) > 0) return;
      let freed = 0;
      try { freed = _reissueRoomForPiece(piece); } catch (_) { }
      try { torrent.pieces?.[piece]?.cancel?.(); } catch (_) { }
      try { torrent.critical(piece, piece); } catch (_) { }
      try { torrent._update(); } catch (_) { }
      process.stdout.write(`STALL:room-free piece=${piece} freed=${freed} at=${delay}ms\n`);
    }, delay).unref();
  }
}

// v22.3 A: last-block rescue. Log 2026-10-01 07:49: piece 1029 had 4/4 holders,
// ONE 16KB block missing and one wire holding the only outstanding request for it
// (the other wires had full queues). cancel+reissue gave the block back to the same
// wire. Drop the wire(s) holding the request so WT re-reserves it elsewhere.
function _rescueStuckBlock(index) {
  if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return 0;
  const piece = torrent.pieces?.[index];
  if (!piece || typeof piece.cancel !== 'function') return 0;
  const holders = torrent.wires.filter(w => { try { return w.peerPieces?.get(index); } catch (_) { return false; } });
  const stuck = holders.filter(w => (w.requests || []).some(r => r.piece === index));
  const others = holders.length - stuck.length;
  let dropped = 0;
  for (const w of stuck) {
    if (typeof torrent.cancelRequests === 'function') {
      torrent.cancelRequests((req, wire) => wire === w && req.piece === index);
    }
    if (others > 0) { try { w.destroy(); dropped++; } catch (_) { } }
  }
  try { torrent.critical(index, index); } catch (_) { }
  try { torrent._update(); } catch (_) { }
  process.stdout.write(`STALL:rescue-block piece=${index} holders=${holders.length} stuckWires=${stuck.length} dropped=${dropped} missing=${piece.missing ?? '?'}\n`);
  return dropped;
}

const _admitStats = { admitted: 0, rejectedBelowFloor: 0, retired: 0 };
// Pure policy: true when `index` lies below the floor and has no owner.
// Owners: live reader cursor, probe range, current waiter, hash-fail retry pin,
// seek target, waiter boost, header and moov-tail pieces. Only applies while a pump is active.
function _admissionBelowFloor(index, lowFloor, ring) {
  if (!activePumps.size || index >= lowFloor) return false;
  if (ring?._isPinned(index)) return false;
  for (const o of activePumps.values()) {
    if (o.abortController?.signal?.aborted) continue;
    if (o.isProbe) { if (index >= o.startPiece && index <= (o.cursorPiece ?? o.startPiece)) return false; }
    else if (o.cursorPiece === index) return false;
  }
  if (ring && ring.waitedPieces.includes(index)) return false;
  if (_retryPins.has(index) || _retryPins.has(index - 1)) return false;
  if (_seekWatch && _seekWatch.piece === index) return false;
  { const b = _boostOwned(ring); if (b && index >= b.from && index <= b.to) return false; }
  return true;
}
// Pure: what to deselect given the lowest still-selected piece (cursor), the owner limit
// (exclusive) and the header piece (kept selected). null = nothing to retire yet.
function _retirePlan(cursor, limit, firstPiece) {
  if (cursor == null) return null;
  const from = Math.max(cursor, firstPiece + 1);
  const to = limit - 1;
  return to >= from ? { from, to } : null;
}
let _discKeepFrom = null; // lowest owned piece kept selected across a discontinuity
let _retireCursor = null; // lowest piece that may still be selected below the window (retire watermark)
const _admitSeen = new Map(); // piece -> times ADMITTED (acceptances, not verified downloads)
let _admitTotal = 0, _admitLastEmit = '';
function _emitAdmitStats(tag) {
  const ring = getRing();
  const line = `ADMIT:stats admittedUnique=${_admitSeen.size} admittedRepeat=${_admitTotal - _admitSeen.size} admitted=${_admitTotal} (admission acceptances, NOT verified/complete downloads; cancel/retry re-admits count) ` +
    `rejectedBelowFloor=${_admitStats.rejectedBelowFloor} retired=${_admitStats.retired} ` +
    `ramMB=${ring ? (ring.bytes / 1048576).toFixed(1) : 0}/${ring ? (ring.maxBytes / 1048576).toFixed(1) : 0} retireCursor=${_retireCursor}`;
  if (tag !== 'force' && line === _admitLastEmit) return;
  _admitLastEmit = line;
  process.stdout.write(line + '\n');
}
setInterval(() => { try { _emitAdmitStats(); } catch (_) { } }, 10_000).unref?.();
// A waiter boost owns priority only while a registered, pending playback
// waiter is bound to its exact live pump, signal and current source token.
// A reader without a pending wait, or elapsed grace, grants no ownership.
function _boostOwned(ring) {
  const b = _waiterBoost;
  if (!b) return null;
  const have = p => { try { return !!torrent.bitfield?.get(p) || !!ring?.chunks?.has(p); } catch (_) { return false; } };
  let done = true;
  for (let p = b.from; p <= b.to; p++) if (!have(p)) { done = false; break; }
  if (done) return null;
  // Grace never grants ownership. Only a still-registered waiter tied to
  // this exact pump, signal and source token may keep shared priority.
  for (let p = b.from; p <= b.to; p++) if (_liveWaiterOwner(ring, p, true)) return b;
  return null;
}
function _expireStaleBoost(ring) {
  if (_waiterBoost && !_boostOwned(ring)) {
    process.stdout.write(`SEL:boost-expire piece=${_waiterBoost.from}-${_waiterBoost.to} (need satisfied or no waiter/reader)\n`);
    try { _setStreamingPriority('waiter', 1, 0, 2); } catch (_) { }
    _waiterBoost = null;
    return true;
  }
  return false;
}
// Ownership ranges (inclusive) that a discontinuity must not deselect. Same owner set as
// _retireLimit/_admissionBelowFloor: live reader cursor, probe range, waiters, seek target,
// waiter boost, retry pins.
function _ownedRanges(ring) {
  const r = [];
  for (const o of activePumps.values()) {
    if (o.abortController?.signal?.aborted) continue;
    if (o.isProbe) r.push([o.startPiece, Math.max(o.startPiece, o.cursorPiece ?? o.startPiece)]);
    else if (Number.isSafeInteger(o.cursorPiece) && !o.response?.destroyed) r.push([o.cursorPiece, o.cursorPiece]);
  }
  if (ring) for (const p of ring.waitedPieces) r.push([p, p]);
  if (_seekWatch && Number.isSafeInteger(_seekWatch.piece)) r.push([_seekWatch.piece, _seekWatch.piece]);
  { const b = _boostOwned(ring); if (b) r.push([b.from, b.to]); }
  for (const p of _retryPins) r.push([p, p + 1]);
  return r.filter(x => Number.isSafeInteger(x[0]) && Number.isSafeInteger(x[1])).sort((a, b) => a[0] - b[0]);
}
// Pure: parts of [from,to] not covered by owned ranges.
function _subtractOwned(from, to, owned) {
  const gaps = [];
  let c = from;
  for (const [a, b] of owned) {
    if (b < c || a > to) continue;
    if (a > c) gaps.push([c, a - 1]);
    c = Math.max(c, b + 1);
    if (c > to) break;
  }
  if (c <= to) gaps.push([c, to]);
  return gaps;
}
// Technical exception: touches torrent._selections._items and torrent._updateSelections (vendor internals), see vendor-dependency
// note; coupled to vendored torrent.js 4feb79e5 / selections.js, re-review on vendor bump. This comment asserts no authority.
// Postcondition for EVERY selection mutation (priority clear/select, discontinuity, orphan flush,
// retire): pieces owned by a live reader/probe/waiter/seek/boost/pin stay selected. Idempotent.
function _ensureOwnedSelected(ring) {
  if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return 0;
  const items = torrent._selections?._items;
  if (!items) return 0;
  // EFFECTIVE coverage = [from+offset, to]: the scheduler never requests below from+offset,
  // so an evicted owned piece behind the offset is NOT covered even though it is inside [from,to].
  const covered = items.filter(i => !i.isStreamSelection).map(i => [i.from + (i.offset || 0), i.to]).sort((a, b) => a[0] - b[0]);
  const have = idx => { try { return !!torrent.bitfield?.get(idx); } catch (_) { return false; } };
  let reselected = 0;
  for (const [oa, ob] of _ownedRanges(ring || getRing())) {
    const a = Math.max(oa, totalFileFirst), b = Math.min(ob, totalFileLast);
    if (a > b) continue;
    for (const [ga, gb] of _subtractOwned(a, b, covered)) {
      let start = null;
      for (let idx = ga; idx <= gb + 1; idx++) {
        const need = idx <= gb && !have(idx);
        if (need && start == null) start = idx;
        if (!need && start != null) {
          // Offset-safe repair: a separate un-merged selection (offset 0). _selectBaseRange() would
          // concatenate with the enclosing selection and drag its consumed prefix back in.
          items.push({ from: start, to: idx - 1, offset: 0, priority: 0, ownerRepair: true });
          reselected += idx - start;
          _retireCursor = _retireCursor == null ? start : Math.min(_retireCursor, start); // repair below watermark must be retired later
          start = null;
        }
      }
    }
  }
  if (reselected) {
    try { items.sort((x, y) => (y.priority ?? 0) - (x.priority ?? 0)); torrent._updateSelections?.(); } catch (_) { }
    _assertRetryPins();
    process.stdout.write(`SEL:owner-reselect pieces=${reselected}\n`);
  }
  return reselected;
}
// Highest piece (exclusive) the consumed-prefix retire may reach: nothing owned may be dropped.
function _retireLimit(newFrom, ring) {
  let limit = newFrom;
  const lim = p => { if (Number.isSafeInteger(p) && p < limit) limit = p; };
  for (const p of _retryPins) { lim(p); }
  { const b = _boostOwned(ring); if (b) lim(b.from); }
  if (ring) for (const p of ring.waitedPieces) lim(p);
  lim(readerRetentionPiece(newFrom));
  if (_seekWatch) lim(_seekWatch.piece);
  // HTTP tail classification is not a retention grant; live probe cursors above remain owned.
  for (const o of activePumps.values()) if (o.isProbe && !o.abortController?.signal?.aborted) lim(o.startPiece);
  return limit;
}

// Reserve a whole piece before its first block; leave room for the reader frontier.
function _admitStreamingPiece({ index, length, reservedBytes, reservedIndices }) {
  const ring = getRing();
  if (!ring || !torrent.pieceLength) return true;
  const floor = readerRetentionPiece(currentPlayPiece);
  const lead = Math.max(1, Math.min(WINDOW_AHEAD_MAX, Math.floor(ring.maxBytes / torrent.pieceLength / 2)));
  if (activePumps.size && !liveReaderOwnsPiece(index) && index > floor + lead &&
      !ring._isPinned(index)) return false;
  // Lower bound: never (re)admit a piece behind the reader retention floor unless
  // something owns it. Evicted-then-redownloaded consumed pieces were the 2.5x repeat.
  if (_admissionBelowFloor(index, floor - WINDOW_BEHIND, ring)) {
    _admitStats.rejectedBelowFloor++;
    return false;
  }
  _admitStats.admitted++;
  ring._evict();
  const waiter = ring.waitedPieces.filter(p => p >= totalFileFirst && p <= totalFileLast).sort((a, b) => a - b)[0];
  const frontier = _playbackWaiterPiece(ring) ?? (waiter == null ? currentPlayPiece : waiter);
  const frontierStored = ring.chunks.has(frontier);
  const frontierReserved = reservedIndices.includes(frontier);
  const spare = index === frontier || frontierStored || frontierReserved ? 0 : torrent.pieceLength;
  const ok = ring.bytes + reservedBytes + length + spare <= ring.maxBytes;
  if (ok) { _admitSeen.set(index, (_admitSeen.get(index) || 0) + 1); _admitTotal++; }
  return ok;
}

const SNUB_IDLE_MS = 6_000;
const SNUB_RETRY_MS = 6_000;
function _cancelOutsideStream(from, to) {
  _frontierDupState = null;
  _waiterBoost = null;
  _priorityWindow = null;
  if (typeof torrent.resetStreamWindow !== 'function') return;
  const count = torrent.resetStreamWindow(from, to);
  if (count) process.stdout.write(`SEEK:cancel-requests count=${count} keep=[${from},${to}]\n`);
}
// v22.15-dev: dead-wire eviction. Log 2026-10-22 23:19 (session 37276): wires with
// dl=0 for their whole life (idle 34s/49s/144s/183s) still held reserved blocks of the
// blocking piece in 4 of 11 STALL:holder snapshots (e.g. 91.193.6.171 held piece 13 and
// then piece 15 with idleMs=144015/183018). snub-cancel only retries after 6s and the
// library hands the block back to the same wire. A wire that has delivered 0 bytes for
// DEAD_WIRE_MS while holding requests, with enough live wires, is destroyed so it cannot
// re-reserve. Pure decision helper first so it is testable.
const DEAD_WIRE_MS = 20_000;
const DEAD_WIRE_MIN_LIVE = 3;
function _deadWireVictims(wires, progressOf, now) {
  const live = wires.filter(w => !w.destroyed && w.type !== 'webSeed' && (progressOf(w)?.received || 0) > 0 &&
    now - (progressOf(w)?.lastData || 0) < DEAD_WIRE_MS).length;
  if (live < DEAD_WIRE_MIN_LIVE) return [];
  return wires.filter(w => {
    if (w.destroyed || w.type === 'webSeed') return false;
    const st = progressOf(w);
    if (!st || st.received > 0) return false;
    if (!(w.requests && w.requests.length > 0)) return false;
    return now - st.lastData >= DEAD_WIRE_MS;
  });
}
function _evictDeadWires() {
  try {
    const victims = _deadWireVictims(torrent.wires, w => _wireProgress.get(w), Date.now());
    for (const w of victims) {
      const addr = w.remoteAddress || '?';
      const held = w.requests?.length || 0;
      try { w.destroy(); } catch (_) { }
      process.stdout.write(`STALL:dead-wire-evict ${addr} held=${held} neverDelivered=1 afterMs=${DEAD_WIRE_MS}\n`);
    }
  } catch (_) { }
}
function _cancelSnubbedFrontier(ring) {
  if (_isUserPaused || _torrentGone || _shuttingDown || torrent.destroyed || !ring || typeof torrent.cancelRequests !== 'function') return;
  const index = _playbackWaiterPiece(ring) ?? ring.waitedPieces.filter(p => p >= totalFileFirst && p <= totalFileLast).sort((a, b) => a - b)[0];
  if (index == null) return;
  const now = Date.now();
  for (const wire of torrent.wires) {
    if (wire.type === 'webSeed' || wire.destroyed) continue;
    const state = _wireProgress.get(wire);
    if (!state) continue;
    if (!(wire.requests || []).some(req => req.piece === index)) {
      state.frontier = null; state.since = 0;
      continue;
    }
    if (state.frontier !== index) { state.frontier = index; state.since = now; }
    if (now - Math.max(state.since, state.lastData) < SNUB_IDLE_MS) continue;
    const alternate = torrent.wires.some(w => {
      const progress = _wireProgress.get(w);
      return w !== wire && !w.destroyed && !w.peerChoking && w.type !== 'webSeed' && w.peerPieces?.get(index) &&
        progress?.received > 0 && now - progress.lastData < SNUB_IDLE_MS;
    });
    if (!alternate) continue;
    const count = torrent.cancelRequests((req, w) => w === wire && req.piece === index, { retryAfterMs: SNUB_RETRY_MS });
    state.frontier = null; state.since = 0;
    if (count) process.stdout.write(`STALL:snub-cancel piece=${index} requests=${count} holdMs=${SNUB_RETRY_MS}\n`);
  }
}

// Frontier duplicate policy stays here; the library owns request accounting.
const FRONTIER_DUP_AFTER_MS = 2_000;
// v22.22: a (piece,offset) is duplicated at most once per piece lifetime, and
// only when its sole holder has delivered nothing for >= max(2s, 2x its
// observed per-block time); total duplicated bytes stay under 10% of received
// piece payload (see arch-199w m3). Leftover duplicated copies are cancelled
// when the piece is stored.
const FRONTIER_DUP_BUDGET_RATIO = 0.10;
const FRONTIER_DUP_LOG_MAX = 64;
const _frontierDupLog = new Map(); // piece -> Set<offset> already duplicated
const _frontierDupWires = new Map(); // piece -> Set<wire> holding duplicated copies
let _frontierDupState = null;
let _dupBytes = 0;
let _dupBudgetLogged = false;
function _frontierDupForget(index) {
  _frontierDupLog.delete(index);
  _frontierDupWires.delete(index);
}
function _onPieceStoredVerified(index) {
  const wires = _frontierDupWires.get(index);
  _frontierDupForget(index);
  if (!wires || !wires.size) return;
  try {
    if (typeof torrent.cancelRequests !== 'function') return;
    const n = torrent.cancelRequests((req, w) => req.piece === index && wires.has(w));
    if (n) process.stdout.write(`STALL:frontier-dup-cancel piece=${index} requests=${n}\n`);
  } catch (_) { }
}
function _holderIdleOk(wire, now) {
  const state = _wireProgress.get(wire);
  if (!state) return true; // no observation yet: fixed floor only
  const idle = now - (state.lastData || 0);
  let observedBlockMs = null;
  if (state.received >= 16384 && state.t0 && state.lastData > state.t0) {
    // average block delivery time over the wire's active window (t0..lastData)
    observedBlockMs = (state.lastData - state.t0) / (state.received / 16384);
  }
  const threshold = Math.max(FRONTIER_DUP_AFTER_MS, observedBlockMs ? 2 * observedBlockMs : 0);
  return idle >= threshold;
}
function _duplicateFrontier(ring) {
  if (_isUserPaused || _torrentGone || _shuttingDown || torrent.destroyed || !ring || typeof torrent.duplicateBlock !== 'function') {
    _frontierDupState = null;
    return;
  }
  // Match priority/admission: analysis back-reads cannot divert recovery
  // from a live waiting playback cursor. All duplicate limits below stay.
  const index = _playbackWaiterPiece(ring) ?? ring.waitedPieces.filter(p => p >= totalFileFirst && p <= totalFileLast).sort((a, b) => a - b)[0];
  if (index == null || torrent.bitfield?.get(index)) { _frontierDupForget(index); _frontierDupState = null; return; }
  const now = Date.now();
  if (!_frontierDupState || _frontierDupState.index !== index) {
    _frontierDupState = { index, since: now };
    return;
  }
  if (now - _frontierDupState.since < FRONTIER_DUP_AFTER_MS) return;
  // v22.22: duplicate bytes stay under 10% of received piece payload.
  if (_dupBytes > FRONTIER_DUP_BUDGET_RATIO * Math.max(_receivedPayloadBytes, 1)) {
    if (!_dupBudgetLogged) {
      _dupBudgetLogged = true;
      process.stdout.write(`STALL:frontier-dup-budget piece=${index} dupBytes=${_dupBytes} payload=${_receivedPayloadBytes} — frontier duplication paused\n`);
    }
    return;
  }
  if (_frontierDupLog.size >= FRONTIER_DUP_LOG_MAX && !_frontierDupLog.has(index)) {
    _frontierDupForget(_frontierDupLog.keys().next().value);
  }
  if (!_frontierDupLog.has(index)) _frontierDupLog.set(index, new Set());
  const doneOffsets = _frontierDupLog.get(index);
  const offsets = new Set();
  for (const w of torrent.wires) {
    if (w.type === 'webSeed') continue;
    for (const req of w.requests || []) if (req.piece === index) offsets.add(req.offset);
  }
  const candidates = torrent.wires.filter(w => !w.destroyed && !w.peerChoking && w.type !== 'webSeed' && w.peerPieces?.get(index))
    .sort((a, b) => b.downloadSpeed() - a.downloadSpeed());
  let sent = 0;
  for (const offset of offsets) {
    if (doneOffsets.has(offset)) continue; // already duplicated once this piece lifetime (v22.22)
    const copies = torrent.wires.filter(w => (w.requests || []).some(r => r.piece === index && r.offset === offset));
    if (copies.length !== 1) continue;
    if (!_holderIdleOk(copies[0], now)) continue; // holder still delivering (v22.22)
    for (const w of candidates) {
      if (copies.includes(w)) continue;
      if (torrent.duplicateBlock(w, index, offset)) {
        sent++;
        doneOffsets.add(offset);
        _dupBytes += 16384;
        if (!_frontierDupWires.has(index)) _frontierDupWires.set(index, new Set());
        _frontierDupWires.get(index).add(w);
        break;
      }
    }
  }
  _frontierDupState.since = now;
  if (sent) process.stdout.write(`STALL:frontier-dup piece=${index} requests=${sent} dupBytes=${_dupBytes}\n`);
}

// v21.7: hash-failed waiter pieces stay selected until verified or seeked
// past — the single-slot waiter boost drops them when the frontier moves,
// and WT then silently stops the retry (see v21.7 CHANGELOG).
const _retryPins = new Set();
function _pinRetry(index) {
  if (_retryPins.size >= RETRY_PIN_MAX) _retryPins.delete(_retryPins.values().next().value);
  _retryPins.add(index);
  _assertRetryPins();
}
function _assertRetryPins() {
  if (!_retryPins.size || _torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
  // Merge-safe: _selectBaseRange() would concatenate with the enclosing selection and drag its
  // consumed prefix back in (offset reset). Push a separate priority-2 item only when the pin is
  // not already effectively covered at priority >= 2.
  const items = torrent._selections?._items;
  for (const idx of _retryPins) {
    try {
      const to = Math.min(idx + 1, totalFileLast);
      if (!items) { _selectBaseRange(idx, to, 2); continue; }
      const cov = items.some(i => !i.isStreamSelection && (i.priority ?? 0) >= 2 && i.from + (i.offset || 0) <= idx && i.to >= to);
      if (cov) continue;
      items.push({ from: idx, to, offset: 0, priority: 2, ownerRepair: true });
      items.sort((x, y) => (y.priority ?? 0) - (x.priority ?? 0));
      torrent._updateSelections?.();
    } catch (_) { }
  }
}
function _clearRetryPins() {
  if (!_retryPins.size) return;
  for (const idx of _retryPins) {
    try {
      if (!_torrentGone && torrent && !torrent.destroyed) torrent.deselect(idx, Math.min(idx + 1, totalFileLast), 2);
    } catch (_) { }
  }
  _retryPins.clear();
  _ensureOwnedSelected();
}

// v21.7: seek-orphan marks — piece -> window start at flush time; the pump
// destroys the connection instead of zero-filling a departing reader.
const _seekOrphans = new Map();
const SEEK_ORPHAN_MAX = 32;

// v21.7: seek-no-follow watchdog — armed by large POS jumps, disarmed when a
// matching RANGE arrives; one REQ: line per stuck seek.
let _seekWatch = null; // {piece, at}
let _lastPosPiece = null;

// Bounded managed selections must NOT go through select()/deselect():
// vendor concatenate() expands an inner boost to the entire enclosing window,
// while deselect() ignores its third argument and cuts every overlapping priority.
function _selectBaseRange(from, to, priority) {
  const items = torrent._selections?._items;
  if (!items) return torrent.select(from, to, priority);
  const managed = items.filter(i => i.gorPriorityOwner);
  for (let i = items.length - 1; i >= 0; i--) if (items[i].gorPriorityOwner) items.splice(i, 1);
  try { return torrent.select(from, to, priority); }
  finally {
    items.push(...managed);
    items.sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
    torrent._updateSelections?.();
  }
}
function _setStreamingPriority(owner, from, to, priority) {
  const items = torrent._selections?._items;
  if (!items) return false;
  // Exact owned entries only. No unrelated window, retry pin or stream is removed.
  for (let i = items.length - 1; i >= 0; i--) if (items[i].gorPriorityOwner === owner) items.splice(i, 1);
  if (from <= to) items.push({from, to, offset: 0, priority, gorPriorityOwner: owner});
  items.sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
  torrent._updateSelections?.();
  return true;
}
// One shared waiter priority must not become last-analysis-reader-wins.
// Only an actually waiting, live playback cursor is eligible. Probe and
// analysis ownership remains intact, but neither may displace that cursor.
function _validWaiterEntry(ring, piece, entry, playbackOnly = false) {
  if (!entry || !(ring?._waiters?.get(piece) || []).includes(entry)) return false;
  const owner = activePumps.get(entry.pumpId);
  return !!owner && entry.signal === owner.abortController?.signal &&
    entry.playbackToken === owner.playbackToken && owner.playbackToken === _activePlaybackToken &&
    !entry.signal?.aborted && !owner.response?.destroyed && !owner.response?.writableEnded &&
    owner.cursorPiece === piece && (!playbackOnly || (!owner.isAnalysis && !owner.isProbe));
}
function _liveWaiterOwner(ring, piece, playbackOnly = false) {
  for (const entry of ring?._waiters?.get(piece) || []) {
    if (_validWaiterEntry(ring, piece, entry, playbackOnly)) return activePumps.get(entry.pumpId);
  }
  return null;
}
function _playbackWaiterPiece(ring) {
  if (!ring) return null;
  return ring.waitedPieces.filter(p => _liveWaiterOwner(ring, p, true)).sort((a, b) => a - b)[0] ?? null;
}
function _refreshWaiterPriority(ring) {
  // An old source ring may finish its callbacks after the global source swaps.
  if (!ring || ring !== getRing()) return;
  if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
  // Analysis gets a separate bounded selection, never playback authority.
  // A live playback waiter always wins; source analysis may make progress
  // only when it cannot displace that waiting cursor.
  const index = _playbackWaiterPiece(ring);
  const analysis = index == null ? ring.waitedPieces.filter(piece =>
    (ring._waiters.get(piece) || []).some(entry => {
      if (!_validWaiterEntry(ring, piece, entry)) return false;
      const owner = activePumps.get(entry.pumpId);
      return owner.isAnalysis && !owner.isProbe;
    })).sort((a, b) => a - b)[0] : null;
  const selected = torrent._selections?._items?.filter(i => i.gorPriorityOwner === 'analysis-waiter') || [];
  if (analysis == null ? selected.length > 0 : selected.length !== 1 ||
      selected[0].from !== analysis || selected[0].to !== analysis || selected[0].offset !== 0) {
    _setStreamingPriority('analysis-waiter', analysis == null ? 1 : analysis,
      analysis == null ? 0 : analysis, 1);
  }
  if (index == null) {
    if (_waiterBoost || torrent._selections?._items?.some(i => i.gorPriorityOwner === 'waiter')) {
      _setStreamingPriority('waiter', 1, 0, 2);
    }
    _waiterBoost = null;
    return;
  }
  const entry = (ring._waiters.get(index) || []).find(e => _validWaiterEntry(ring, index, e, true));
  _boostWaiterPiece(index, entry);
}
function _boostWaiterPiece(index, entry = null) {
  if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
  const ring = getRing();
  if (!_validWaiterEntry(ring, index, entry, true)) return;
  index = _playbackWaiterPiece(ring);
  if (index == null) {
    _waiterBoost = null;
    _setStreamingPriority('waiter', 1, 0, 2);
    return;
  }
  const to = Math.min(index + 1, totalFileLast);
  if (_waiterBoost && _waiterBoost.from === index && _waiterBoost.to === to &&
      torrent._selections?._items?.some(i => i.gorPriorityOwner === 'waiter' && i.from === index && i.to === to)) {
    // A different reader may just have installed a waiter outside the
    // playback window. Keep its base ownership without stealing priority.
    _ensureOwnedSelected();
    return;
  }
  try {
    if (!_setStreamingPriority('waiter', index, to, 2)) return;
    _waiterBoost = { from: index, to, ts: Date.now() };
    process.stdout.write(`SEL:boost piece=${index} priority=2\n`);
  } catch (_) { }
  _assertRetryPins();
  _ensureOwnedSelected();
}
function _selectHighPriority(from, to) {
  if (from > to) return;
  try {
    if (_setStreamingPriority('lookahead', from, to, 1)) _priorityWindow = {from, to};
  } catch (_) { }
  _ensureOwnedSelected();
}
function _clearHighPriority() {
  if (!_priorityWindow) return;
  try {
    _setStreamingPriority('lookahead', 1, 0, 1);
    _priorityWindow = null;
  } catch (_) { }
  _ensureOwnedSelected();
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
  // _selectBaseRange() whose currentWindow still gets committed (stale/broken
  // state persists until the next successful select). Clamping here is a
  // pure safety net; it does not change normal mid-file behavior.
  playheadPiece = Math.max(fileFirst, Math.min(fileLast, playheadPiece));
  const ring = getRing();
  _expireStaleBoost(ring);
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
      // Discontinuity: also retire any still-held prefix below currentWindow.from (retire watermark),
      // header piece excepted, so a seek cannot orphan it. Pins are re-asserted after.
      const wm = Math.min(_retireCursor ?? currentWindow.from, currentWindow.from);
      const dsFrom = wm < currentWindow.from ? Math.max(wm, totalFileFirst + 1) : wm;
      const owned = _ownedRanges(ring);
      for (const [ga, gb] of _subtractOwned(dsFrom, currentWindow.to, owned)) torrent.deselect(ga, gb, false);
      // retained owned pieces stay selected; watermark must keep pointing at the lowest of them
      const keep = owned.filter(([a, b]) => b >= dsFrom && a <= currentWindow.to).map(x => Math.max(x[0], dsFrom));
      _discKeepFrom = keep.length ? Math.min(...keep) : null;
      _assertRetryPins();
      process.stdout.write(`SEL:deselect [${dsFrom},${currentWindow.to}] (window ${currentWindow.from},${currentWindow.to} watermark ${wm})\n`);
    } catch (e) {
      process.stdout.write(`SEL:deselect ERR ${e?.message || e}\n`);
    }
  } else if (currentWindow) {
    // Rolling consumed-prefix retire: drop the old consumed prefix before the new window
    // is selected so WT's merge cannot pull [oldFrom..] back in and re-request evicted pieces.
    // Selection.remove is offset-safe (selections.js). Owned pieces are never retired.
    const plan = _retirePlan(_retireCursor ?? currentWindow.from, _retireLimit(from, ring), totalFileFirst);
    if (plan) {
      try {
        torrent.deselect(plan.from, plan.to, false);
        _admitStats.retired += plan.to - plan.from + 1;
        _retireCursor = plan.to + 1;
        process.stdout.write(`SEL:retire-prefix [${plan.from},${plan.to}] new=[${from},${to}]\n`);
        _assertRetryPins();
        _emitAdmitStats();
      } catch (e) {
        process.stdout.write(`SEL:retire-prefix ERR ${e?.message || e}\n`);
      }
    }
    process.stdout.write(
      `SEL:extend [${currentWindow.from},${currentWindow.to}]→[${from},${to}] (retire+WT-merge)\n`
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
          if (liveReaderOwnsPiece(idx)) continue;
          if (idx <= totalFileFirst) {
            // Header piece: evict without counting as auto-skip (see v17.34)
            process.stdout.write(`SEL:flush-orphan-blocked piece=${idx} — header piece protected, evicting stale waiter\n`);
            ring.forceSkip(idx);
            continue;
          }
          // v21.7: far-orphan = reader left by a seek; pump destroys
          // that connection rather than sending bytes to a stale reader.
          if (Math.min(Math.abs(idx - from), Math.abs(idx - to)) > SEEK_ORPHAN_GAP) {
            if (_seekOrphans.size >= SEEK_ORPHAN_MAX) _seekOrphans.delete(_seekOrphans.keys().next().value);
            _seekOrphans.set(idx, from);
          }
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
    _selectBaseRange(from, to, false);
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

  if (_selectOk) {
    // retire watermark: continuous window keeps the lowest unretired piece; a discontinuity restarts it
    _retireCursor = (_retireCursor == null || !overlapsExisting) ? from : Math.min(_retireCursor, from);
    if (_discKeepFrom != null) { _retireCursor = Math.min(_retireCursor, _discKeepFrom); _discKeepFrom = null; }
    currentWindow = { from, to };
  }

  if (doCritical) {
    // v15.0: critical() removed, priority selection used instead
    _selectHighPriority(playheadPiece, Math.min(playheadPiece + LOOKAHEAD, to));
  }
  _ensureOwnedSelected(ring);
}

// ─── activeStreams sanity guard ───────────────────────────────────
// v16.0: no longer a counter but a generation set. If activePumps is
// empty but streamSession still says 'streaming' (leaked generation —
// e.g. the pump's finally block never ran but the process somehow
// dirtied the state), forceReset clears it.
setInterval(() => {
  const now = Date.now();
  for (const [id, v] of activePumps) {
    // Consumer lease uses actual validated /pos receipts, never the recovery
    // clock that other watchdogs refresh synthetically.
    // Live response backpressure is a suspended consumer, not a leaked pump.
    // Keep exact HTTP cursor/session/cache ownership while paused or buffered.
    if (v.phase === 'backpressure' && v.response &&
        !v.response.destroyed && !v.response.writableEnded &&
        !v.abortController.signal.aborted &&
        _lastConsumerEvidenceAt > 0 && now - _lastConsumerEvidenceAt <= 120_000) {
      pumpReceipt('guard-suppress', id, v, { preRefreshAtMs: v.ts });
      v.ts = now;
      continue;
    }
    if (now - v.ts > 120_000) {
      pumpReceipt('guard-expire', id, v, { preRefreshAtMs: v.ts });
      // Expired pump: abort so it exits waitForPiece and runs finally→end()
      try { v.abortController?.abort(); } catch (_) { }
      activePumps.delete(id);
      _refreshWaiterPriority(getRing());
      process.stdout.write(`GUARD:pump-expired piece=${v.cursorPiece ?? v.startPiece} — aborted\n`);
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
            if (idx <= totalFileFirst || liveReaderOwnsPiece(idx)) continue;
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
    if (posAgeNow >= PLAYER_STALL_LOG_MS && _playerStalledAt === 0 && !streamSession.isStreaming() && !_isUserPaused) {
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
          if (idx <= totalFileFirst || liveReaderOwnsPiece(idx)) continue;
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
    if (posAgeNow >= PLAYER_STALL_LOG_MS && _playerStalledAt === 0 && !streamSession.isStreaming() && !_isUserPaused) {
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

  // An unconsumed prebuffer must never advance the reader's eviction/window cursor.
  _prebufferStallSince = null;

  if (!streamSession.isStreaming()) {
    // v17.27: pump abort recovery. If a pump exited with aborted=true
    // (e.g. piece timeout → connection reset) and mpv hasn't reconnected
    // within PUMP_ABORT_RECOVERY_MS, proactively refresh so wt_server is
    // ready when mpv does reconnect — or prompts it to do so via the window
    // reselect. Only fires when not streaming (mpv disconnected) to avoid
    // interfering with a healthy running pump.
    if (_lastPumpAbortAt > 0 && !streamSession.isStreaming() && !_isUserPaused &&
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

  _evictDeadWires();
  _cancelSnubbedFrontier(ring);
  _duplicateFrontier(ring);
  // v22.8: while user-paused the detector neither diagnoses nor recovers; downloads/pins keep running.
  if (_isUserPaused) stallDetector.holdForPause();
  else stallDetector.check({
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
        // Losing it causes mpv to fail avformat_open_input with no recovery.
        if (idx <= totalFileFirst) {
          process.stdout.write(`STALL:auto-skip-blocked piece=${idx} — header piece protected\n`);
          continue;
        }
        ring.forceSkip(idx);
        process.stdout.write(`STALL:auto-skip piece=${idx}\n`);
      }
      // v22.0: do not advance the playhead across unverified data.
      // Refresh the same window and reconnect the swarm after a bounded reset.
      if (stallDetector.consecutiveAutoSkips >= DEAD_ZONE_SKIP_STREAK) {
        process.stdout.write(`STALL:integrity-stalled piece=${piece} play=${currentPlayPiece} — holding verified frontier\n`);
        stallDetector.resetSkipStreak();
        try { triggerSwarmReconnect(); } catch (_) { }
      }
      updateSlidingWindow(currentPlayPiece, totalFileFirst, totalFileLast, true);
    },
  });

  // v21.7: seek-no-follow — POS jumped but no matching RANGE ever arrived;
  // surfaced via REQ: so the app layer can nudge the player (see v21.7).
  if (_seekWatch && Date.now() - _seekWatch.at > SEEK_NOFOLLOW_MS) {
    const w = _seekWatch; _seekWatch = null;
    process.stdout.write(`REQ:seek-no-follow piece=${w.piece} waitMs=${Date.now() - w.at} — mpv never requested the seek region\n`);
  }

  // Stuck waiter flush
  const STUCK_WAITER_MS = PIECE_TIMEOUT_BASE + 10_000;
  if (!_isUserPaused) {
    const now = Date.now();
    for (const [idx, list] of ring._waiters) {
      if (!list.length) continue;
      const oldest = Math.min(...list.map(w => w.startTime ?? now));
      const waitMs = now - oldest;
      if (waitMs > STUCK_WAITER_MS) {
        process.stdout.write(`STALL:stuck-waiter piece=${idx} waitMs=${waitMs} — force-flush\n`);
        ring.forceSkip(idx);
      }
    }
  }
}, STALL_CHECK_MS);

// ─── Dedup ────────────────────────────────────────────────────────
// Test-only receipt channel. Off by default; never logs URLs, tokens or media.
const WT_PUMP_RECEIPTS = process.env.GOR_WT_PUMP_RECEIPTS === '1';
function pumpReceipt(event, id, pump, extra = {}) {
  if (!WT_PUMP_RECEIPTS) return;
  try {
    const now = Date.now();
    process.stdout.write('PUMP_RECEIPT:' + JSON.stringify({
      schema: 'wt-pump-test-v1', event, pid: process.pid, atMs: now,
      pumpId: id, startPiece: pump?.startPiece ?? null,
      cursorPiece: pump?.cursorPiece ?? null, phase: pump?.phase ?? null,
      probe: pump?.isProbe ?? null, analysis: pump?.isAnalysis ?? false, waitSeq: pump?.receiptWaitSeq ?? null,
      bornAtMs: pump?.receiptBornAtMs ?? null,
      waitAtMs: pump?.receiptWaitAtMs ?? null,
      consumerAtMs: _lastConsumerEvidenceAt,
      responseDestroyed: pump?.response?.destroyed ?? null,
      responseEnded: pump?.response?.writableEnded ?? null,
      aborted: pump?.abortController?.signal?.aborted ?? null,
      activeCount: activePumps.size, ...extra
    }) + '\n');
  } catch (_) { /* Receipt failure must not change transport decisions. */ }
}
const activePumps = new Map(); // Unique ID -> { startPiece, abortController, ts }
let nextPumpId = 0;
// v22.11: a reader whose cursor has not advanced for READER_FLOOR_STALL_MS is
// not reading and must not pin the retention floor. Session 91483-1
// (2026-10-17): mpv's post-reload full-file connection (bytes=11777-EOF)
// parked in HTTP backpressure at piece 1 forever; its cursor pinned the floor
// at 1, and the play pump at piece 44 (lead=16) sat in waitForReaderBudget
// until the next frozen-consumer reload — never reaching waitForPiece, never
// registering a waiter, never boosting piece 44 (stalledPiece=null for 210s;
// playhead frozen 16:28:27Z → SHUTDOWN; 6 reload cycles).
const READER_FLOOR_STALL_MS = 15_000;
function readerRetentionPiece(fallback) {
  let floor = fallback;
  const now = Date.now();
  for (const [id, owner] of activePumps) {
    if (!owner.isProbe && !owner.isAnalysis && !owner.abortController.signal.aborted && !owner.response.destroyed &&
        Number.isSafeInteger(owner.cursorPiece)) {
      const lastAdvance = owner.cursorAt ?? owner.ts ?? 0;
      if (now - lastAdvance > READER_FLOOR_STALL_MS) {
        if (!owner.floorStaleLogged) {
          owner.floorStaleLogged = true;
          process.stdout.write(`PUMP:reader-floor-stale pump=${id} cursor=${owner.cursorPiece} idleMs=${now - lastAdvance} — excluded from retention floor\n`);
        }
        continue;
      }
      floor = Math.min(floor, owner.cursorPiece);
    }
  }
  return floor;
}

// An HTTP range grants retention to its live cursor, not every byte since
// its start. The eviction callers subtract behindPieces(), preserving the
// existing byte-sized seek-back reserve. Pinning start..cursor indefinitely
// exhausts RAM on a long range and blocks new piece admission until the
// reader becomes stale. Older back-reads use the verified refetch path.
function readerOwnedRetentionFloor(fallback) {
  let floor = fallback;
  const now = Date.now();
  for (const [id, owner] of activePumps) {
    if (!owner.isProbe && !owner.isAnalysis && !owner.abortController.signal.aborted && !owner.response.destroyed &&
        Number.isSafeInteger(owner.cursorPiece)) {
      const lastAdvance = owner.cursorAt ?? owner.ts ?? 0;
      if (now - lastAdvance > READER_FLOOR_STALL_MS) continue;
      floor = Math.min(floor, owner.cursorPiece);
    }
  }
  return floor;
}

function liveReaderOwnsPiece(piece) {
  return [...activePumps.values()].some(owner => !owner.isProbe &&
    !owner.abortController.signal.aborted && !owner.response.destroyed && owner.cursorPiece === piece);
}

// v22.12: budget-gate floor. readerRetentionPiece's 15s stale-cursor exclusion
// stays correct for RETENTION, but the blockade readers are FRESH: every
// frozen-consumer reload spawns a new full-file connection parked at piece 0,
// and its first 15s legitimately re-pins the floor each cycle (log 260918:
// owners=[7:0:5ms] -> floor=0, play pump at 436 blocked; pumps 12/16/20 repeat
// the pattern across 4 reload cycles, ~15s lost per cycle). A reader that has
// never advanced past its start piece READER_BUDGET_NEVER_ADVANCED_MS after
// registration is not consuming; it must not pace the play pump. With every
// such reader skipped the floor resolves to the fallback (the waiting piece
// itself), so a lone fresh reader can never block itself.
const READER_BUDGET_NEVER_ADVANCED_MS = 4_000;
function readerBudgetFloor(fallback) {
  let floor = fallback;
  const now = Date.now();
  for (const owner of activePumps.values()) {
    if (owner.openingScanPacingRetired || owner.isProbe || owner.isAnalysis || owner.abortController.signal.aborted || owner.response.destroyed ||
        !Number.isSafeInteger(owner.cursorPiece)) continue;
    const lastAdvance = owner.cursorAt ?? owner.ts ?? 0;
    if (now - lastAdvance > READER_FLOOR_STALL_MS) continue;
    if (owner.cursorPiece === owner.startPiece && now - lastAdvance > READER_BUDGET_NEVER_ADVANCED_MS) continue;
    floor = Math.min(floor, owner.cursorPiece);
  }
  return floor;
}

const READER_BUDGET_LOG_MS = 10_000;
async function waitForReaderBudget(piece, pumpId, signal) {
  let blockedSince = 0, lastBudgetLog = 0;
  while (!signal.aborted) {
    const floor = readerBudgetFloor(piece);
    const ramPieces = Math.max(2, Math.floor((getRing()?.maxBytes || RAM_CAP_MIN) / torrent.pieceLength));
    const lead = Math.max(1, Math.min(WINDOW_AHEAD_MAX, Math.floor(ramPieces / 2)));
    if (piece <= floor + lead) return;
    // v22.11: the 91483-1 blockade was invisible in logs (stalledPiece=null,
    // pumpActive=true, no complaint). Name the pinning readers every 10s.
    const now = Date.now();
    if (!blockedSince) blockedSince = now;
    if (now - lastBudgetLog >= READER_BUDGET_LOG_MS) {
      lastBudgetLog = now;
      const owners = [...activePumps.entries()]
        .filter(([, o]) => !o.isProbe && !o.abortController.signal.aborted && !o.response.destroyed)
        .map(([id, o]) => `${id}:${o.cursorPiece}:${now - (o.cursorAt ?? o.ts ?? now)}ms`).join(',');
      process.stdout.write(`PUMP:reader-budget-blocked piece=${piece} floor=${floor} lead=${lead} blockedMs=${now - blockedSince} owners=[${owners}]\n`);
    }
    const owner = activePumps.get(pumpId);
    if (owner) { owner.phase = 'reader-budget'; owner.ts = Date.now(); }
    await new Promise(resolve => {
      const finish = () => { clearTimeout(timer); signal.removeEventListener('abort', finish); resolve(); };
      const timer = setTimeout(finish, 50);
      signal.addEventListener('abort', finish, { once: true });
      if (signal.aborted) finish();
    });
  }
}

let _lastConsumerEvidenceAt = 0; // actual validated /pos, not synthetic recovery

// Before any decoder clock exists, a new far-forward main range is the
// next opening scan demand. Superseded opening cursors keep their exact
// retention/waiter ownership, but no longer pace the newest scan read.
function _succeedOpeningScan(pumpId) {
  if (lastMpvPosSec != null) return false;
  const next = activePumps.get(pumpId);
  if (!next || next.isProbe || next.isAnalysis ||
      next.playbackToken !== _activePlaybackToken ||
      next.abortController.signal.aborted || next.response.destroyed || next.response.writableEnded) return false;
  const lead = Math.max(1, Math.min(WINDOW_AHEAD_MAX,
    Math.floor((getRing()?.maxBytes || RAM_CAP_MIN) / torrent.pieceLength / 2)));
  let retired = 0;
  for (const owner of activePumps.values()) {
    if (owner === next || owner.isProbe || owner.isAnalysis ||
        owner.playbackToken !== next.playbackToken || owner.pumpOrder >= next.pumpOrder ||
        owner.abortController.signal.aborted || owner.response.destroyed || owner.response.writableEnded ||
        !Number.isSafeInteger(owner.cursorPiece) || next.cursorPiece <= owner.cursorPiece + lead) continue;
    owner.openingScanPacingRetired = true;
    retired++;
  }
  if (retired) process.stdout.write(`PUMP:opening-succession pump=${pumpId} piece=${next.cursorPiece} retired=${retired}\n`);
  return retired > 0;
}

function openingSchedulingFloor(fallback) {
  let floor = fallback;
  const now = Date.now();
  for (const owner of activePumps.values()) {
    if (owner.openingScanPacingRetired || owner.isProbe || owner.isAnalysis ||
        owner.playbackToken !== _activePlaybackToken || owner.abortController.signal.aborted ||
        owner.response.destroyed || owner.response.writableEnded || !Number.isSafeInteger(owner.cursorPiece)) continue;
    if (now - (owner.cursorAt ?? owner.ts ?? 0) > READER_FLOOR_STALL_MS) continue;
    floor = Math.min(floor, owner.cursorPiece);
  }
  return floor;
}

function registerPump(startPiece, abortController, response, isProbe = false, isAnalysis = false) {
  const id = ++nextPumpId;
  activePumps.set(id, { startPiece, cursorPiece: startPiece, cursorAt: Date.now(), floorStaleLogged: false, phase: 'running', ts: Date.now(), abortController, response, isProbe, isAnalysis,
    pumpOrder: id, playbackToken: _activePlaybackToken, acceptedAt: Date.now(), hasWritten: false, lastWriteAt: 0 });
  if (WT_PUMP_RECEIPTS) {
    const pump = activePumps.get(id);
    pump.receiptBornAtMs = Date.now();
    pump.receiptWaitSeq = 0;
  }
  pumpReceipt('register', id, activePumps.get(id));
  return id;
}

// The write has already accepted its bytes when it returns false. Wait for
// drain without resending that chunk, and keep cleanup generation-local.
function waitForPumpDrain(response, signal, pumpId, cursorPiece) {
  const pump = activePumps.get(pumpId);
  if (pump) {
    pump.phase = 'backpressure';
    pump.cursorPiece = cursorPiece;
    pump.ts = Date.now();
    if (WT_PUMP_RECEIPTS) {
      pump.receiptWaitSeq++;
      pump.receiptWaitAtMs = Date.now();
    }
    pumpReceipt('wait-enter', pumpId, pump);
  }
  return new Promise(resolve => {
    let done = false;
    const finish = reason => {
      if (done) return;
      done = true;
      response.removeListener('drain', onDrain);
      response.removeListener('close', onClose);
      signal.removeEventListener('abort', onAbort);
      pumpReceipt('wait-exit', pumpId, pump, { reason });
      const current = activePumps.get(pumpId);
      if (current === pump && current) {
        current.phase = 'running';
        current.ts = Date.now();
      }
      resolve();
    };
    const onDrain = () => finish('drain');
    const onClose = () => finish('close');
    const onAbort = () => finish('abort');
    response.once('drain', onDrain);
    response.once('close', onClose);
    signal.addEventListener('abort', onAbort, { once: true });
    // Check after listener installation to close the abort/close setup race.
    if (response.destroyed || response.writableEnded) {
      const owner = activePumps.get(pumpId);
      if (owner === pump && owner) owner.abortController.abort();
    }
    if (signal.aborted || response.destroyed || response.writableEnded) finish('setup-terminal');
  });
}

function unregisterPump(id) {
  pumpReceipt('unregister', id, activePumps.get(id));
  activePumps.delete(id);
  _refreshWaiterPriority(getRing());
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
  _refreshWaiterPriority(getRing());
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

// Auto-advance requires a native EOF, never elapsed-time prediction.
let _currentVideoIndex = -1;
let _autoAdvanceTimeout = null;
let _autoAdvanceActive = false;
let _autoAdvanceCountdown = 0;
let _autoAdvanceProof = null;
let _serveGeneration = 0;
let _activePlaybackToken = null;
let _playbackEventSequence = -1;
let _explicitRangeSeekUntil = 0;
const AUTO_ADVANCE_COUNTDOWN_SECS = 5;
const AUTO_ADVANCE_END_TOLERANCE_SECS = 2;

function cancelAutoAdvance(reason) {
  if (_autoAdvanceTimeout) clearTimeout(_autoAdvanceTimeout);
  _autoAdvanceTimeout = null;
  _autoAdvanceProof = null;
  if (_autoAdvanceActive) process.stdout.write(`AUTO_ADVANCE:cancelled reason=${reason}\n`);
  _autoAdvanceActive = false;
  _autoAdvanceCountdown = 0;
}

function autoAdvanceProofValid() {
  const proof = _autoAdvanceProof;
  return !!proof && proof.token === _activePlaybackToken && proof.generation === _serveGeneration &&
    proof.index === _currentVideoIndex && !_isUserPaused &&
    !!pendingStartServer && !!pendingVideoFiles && _currentVideoIndex >= 0 &&
    _currentVideoIndex < pendingVideoFiles.length - 1;
}

function _doAutoAdvanceTick() {
  if (!_autoAdvanceActive) return;
  if (!autoAdvanceProofValid()) { cancelAutoAdvance('proof-invalid'); return; }
  _autoAdvanceCountdown--;
  if (_autoAdvanceCountdown > 0) {
    process.stdout.write(`AUTO_ADVANCE:countdown ${_autoAdvanceCountdown}\n`);
    _autoAdvanceTimeout = setTimeout(_doAutoAdvanceTick, 1_000);
    return;
  }
  const nextIdx = _currentVideoIndex + 1;
  const fn = pendingStartServer;
  cancelAutoAdvance('completed-eof');
  process.stdout.write(`AUTO_ADVANCE:advancing to index=${nextIdx} name=${pendingVideoFiles[nextIdx].name}\n`);
  pendingStartServer = null;
  _currentVideoIndex = nextIdx;
  fn(pendingVideoFiles[nextIdx]);
}

function handlePlaybackEvent(payload, token) {
  if (!payload || payload.token !== token || token !== _activePlaybackToken) return false;
  const seq = payload.sequence;
  if (!Number.isSafeInteger(seq) || seq < 0 || seq <= _playbackEventSequence) return false;
  _playbackEventSequence = seq;
  cancelAutoAdvance(`playback-${String(payload.event)}`);
  if (payload.event === 'seek' || payload.event === 'seek-intent') {
    _explicitRangeSeekUntil = Date.now() + 8_000;
  }
  if (payload.event !== 'eof') return true;
  const position = payload.playhead;
  const duration = payload.duration;
  const remaining = duration - position;
  if (payload.userPaused !== false || !Number.isFinite(payload.positionAge) || payload.positionAge < 0 ||
      payload.positionAge > 2 || !Number.isFinite(position) || !Number.isFinite(duration) ||
      position < 0 || duration <= 0 || remaining < -AUTO_ADVANCE_END_TOLERANCE_SECS ||
      remaining > AUTO_ADVANCE_END_TOLERANCE_SECS || !pendingVideoFiles ||
      _currentVideoIndex < 0 || _currentVideoIndex >= pendingVideoFiles.length - 1 || !pendingStartServer) {
    process.stdout.write(`AUTO_ADVANCE:eof-rejected remaining=${remaining} token=${token}\n`);
    return true;
  }
  _isUserPaused = false; // Native EOF can auto-pause keep-open without user intent.
  _autoAdvanceProof = { token, generation: _serveGeneration, index: _currentVideoIndex };
  _autoAdvanceActive = true;
  _autoAdvanceCountdown = AUTO_ADVANCE_COUNTDOWN_SECS;
  process.stdout.write(`AUTO_ADVANCE:eof-confirmed remaining=${remaining.toFixed(3)} token=${token}\n`);
  process.stdout.write(`AUTO_ADVANCE:countdown ${_autoAdvanceCountdown} next=${pendingVideoFiles[_currentVideoIndex + 1].name}\n`);
  _autoAdvanceTimeout = setTimeout(_doAutoAdvanceTick, 1_000);
  return true;
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

  // v22.3 D: SKIP without pieces with no waiter has nothing to release. Old behaviour
  // took currentPlayPiece (window END, 1088 in the 07:52 log), zero-marked it and
  // moved the window away from mpv's read position. Debounce double posts and turn
  // it into a "reconnect the reader" request instead.
  if (explicitPiece == null) {
    const _r = getRing();
    if (!(_r && _r.waitedPieces.length)) {
      if (Date.now() - _lastSkipAt < 500) return;
      _lastSkipAt = Date.now();
      const need = _lastRangeStartPiece >= 0 ? _lastRangeStartPiece : currentPlayPiece;
      process.stdout.write(`CMD:skip no-waiter pumpActive=${activePumps.size > 0} — no piece skipped; reader needs piece=${need}\n`);
      try { handleRefreshCommand(); } catch (_) { }
      if (activePumps.size === 0) process.stdout.write(`REQ:stream-dead piece=${need} reason=skip-no-waiter — reload stream at current position\n`);
      return;
    }
    if (Date.now() - _lastSkipAt < 500) return;
    _lastSkipAt = Date.now();
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

// v22.13: pure gate for the frozen-consumer reload. true = a needed piece is
// still missing, so a reload would only cancel its partial data and rewind.
function _deadGateMissingFrontier(bitfield, startPiece, playPiece, waitedPiece) {
  if (waitedPiece !== null && waitedPiece !== undefined) return true;
  const hi = Math.max(startPiece, playPiece);
  for (let i = Math.max(0, startPiece); i <= hi; i++) if (!bitfield?.get(i)) return true;
  return false;
}

// A main playback response owns its freeze clock ahead of auxiliary probes.
// Only actually admitted, current-session, live pumps can become owners.
function _deadConsumerOwner() {
  let main = null, probe = null;
  for (const owner of activePumps.values()) {
    if (owner.isAnalysis || owner.playbackToken !== _activePlaybackToken ||
        owner.abortController?.signal?.aborted || owner.response?.destroyed ||
        owner.response?.writableEnded) continue;
    if (!Number.isFinite(owner.acceptedAt) || !Number.isSafeInteger(owner.cursorPiece)) continue;
    if (owner.isProbe) { if (!probe || owner.acceptedAt >= probe.acceptedAt) probe = owner; }
    else if (!main || (owner.hasWritten && !main.hasWritten) ||
        (owner.hasWritten === main.hasWritten && owner.pumpOrder > main.pumpOrder)) main = owner;
  }
  return main || probe;
}

// v22.3 C: dead-reader detector. Nobody reads, the piece mpv last asked for is
// verified, mpv position is frozen: tell the app (REQ:stream-dead). Not while
// user-paused for less than 30s. One request per 30s.
setInterval(() => {
  try {
    if (_isUserPaused || _torrentGone || _shuttingDown || !torrent || torrent.destroyed || _lastRangeStartPiece < 0) return;
    const now = Date.now();
    const consumer = _deadConsumerOwner();
    if (!consumer) return;
    if (_deadObservedOwner !== consumer) {
      _deadObservedOwner = consumer;
      _deadPos = Number.isFinite(lastMpvPosSec) ? lastMpvPosSec : null;
      _deadPosSince = now;
    }
    if (_autoAdvanceActive) return;
    const hasPosition = Number.isFinite(lastMpvPosSec);
    // Opening has no decoder clock. Observe its actual admitted byte owner,
    // not a null===null epoch-duration or an unrelated RANGE arrival.
    if (!hasPosition) {
      _deadPos = null; _deadPosSince = now;
      if (now - Math.max(consumer.acceptedAt, consumer.lastWriteAt) < 15_000) return;
    } else {
      if (_deadPosSince === 0 || _deadPos !== lastMpvPosSec) {
        _deadPos = lastMpvPosSec; _deadPosSince = now; return;
      }
      if (now - _deadPosSince < 15_000) return;
    }
    // v22.10: the needed piece itself is missing — a stream reload cannot
    // fetch it faster. It aborts the live pump whose waiter/boost drive that
    // very download, then the new pump re-waits the same piece (log
    // 2026-10-17: 6 reloads in 3.5 min, piece 44 never landed, playhead
    // frozen until the owner quit). Fetch escalation belongs to the stall
    // detector; the reload stays for a verified piece with a frozen consumer.
    // v22.13: the range START piece is not where the reader froze. mpv opened at
    // piece 1 (verified) but stalled at piece 2 (missing) - the old check passed
    // and reloaded every 30s, rewinding the playhead and discarding the partial
    // piece (owner session 77383, 8 reloads, piece 2 never landed). Resume in
    // place: any missing piece between range start and the play frontier, or a
    // live waiter, means no reload; the stall detector keeps fetching it.
    if (_deadGateMissingFrontier(torrent.bitfield, consumer.startPiece, consumer.cursorPiece, getRing()?.waitedPieces?.[0] ?? null)) return;
    const frozen = hasPosition ? now - _deadPosSince : now - consumer.acceptedAt;
    const idle = now - Math.max(consumer.acceptedAt, consumer.lastWriteAt);
    if (frozen < 10000 || idle < 10000 || now - _deadReqAt < 30000) return;
    _deadReqAt = now;
    process.stdout.write(`REQ:stream-dead piece=${consumer.startPiece} reason=${hasPosition ? 'frozen-consumer' : 'opening-idle'} token=${_activePlaybackToken} pos=${lastMpvPosSec} posFrozenMs=${frozen} idleMs=${idle} paused=${_isUserPaused} — reload same stream\n`);
  } catch (_) { }
}, 2000).unref();

// v22.3 F: sustained-speed detector. Log 2026-10-01 09:26 (8MiB pieces): swarm gave
// 90-190 KB/s against ~2.1 MB/s content rate for 5 minutes; nothing told the user.
// Content rate = file length / duration (needs a /pos with duration). Samples every 2s;
// REQ:swarm-too-slow when the 30s average is under 25% of the content rate. Once per 120s.
// F7: swarm advice requires an actual missing HTTP-reader waiter. Idle/EOF
// drain and already-verified storage waits are not slow-swarm evidence.
function _swarmMissingDemand(ring, owner, readers, first, last) {
  if (!ring || ring.closed || readers <= 0 || !owner || owner.destroyed) return null;
  const waiters = ring.waitedPieces;
  if (!Array.isArray(waiters)) return null;
  let missing = null;
  for (const index of waiters) {
    if (!Number.isSafeInteger(index) || index < first || index > last) continue;
    if (ring.chunks.has(index) || owner.bitfield?.get(index)) continue;
    if (missing == null || index < missing) missing = index;
  }
  return missing;
}

const _spdSamples = []; let _spdReqAt = 0;
setInterval(() => {
  try {
    if (_torrentGone || _shuttingDown || !torrent || torrent.destroyed) return;
    if (!(lastKnownDuration > 0) || !(currentFileLength > 0)) return;
    const demandPiece = _swarmMissingDemand(getRing(), torrent, activePumps.size, totalFileFirst, totalFileLast);
    if (_isUserPaused || activePumps.size === 0) {
      _spdSamples.length = 0; // retired reader lifetime has no current demand
      return;
    }
    const now = Date.now();
    _spdSamples.push({ t: now, v: torrent.downloadSpeed || 0, demanded: demandPiece != null });
    while (_spdSamples.length && now - _spdSamples[0].t > 31000) _spdSamples.shift();
    const demandedSamples = _spdSamples.filter(x => x.demanded);
    if (demandPiece == null || demandedSamples.length < 14 || now - demandedSamples[0].t < 29000) return;
    if (now - _spdReqAt < 120000) return;
    const avg = demandedSamples.reduce((a, x) => a + x.v, 0) / demandedSamples.length;
    const content = currentFileLength / lastKnownDuration;
    // Low verified run alone is not demand. The missing waiter gate above
    // excludes idle/EOF drain; this run is an additional conservative threshold.
    let run = 0;
    for (let i = Math.max(currentPlayPiece, totalFileFirst); i <= totalFileLast && run < 100000; i++) {
      if (!torrent.bitfield?.get(i)) break;
      run++;
    }
    const aheadSecV = (run * torrent.pieceLength) / content;
    if (avg < content * 0.25 && aheadSecV < 20) {
      _spdReqAt = now;
      process.stdout.write(`REQ:swarm-too-slow avgKBs=${(avg / 1024).toFixed(0)} contentKBs=${(content / 1024).toFixed(0)} ratio=${(avg / content).toFixed(2)} aheadS=${aheadSecV.toFixed(0)} missingWaiter=${demandPiece} windowS=30 peers=${torrent.wires.length} — try another release\n`);
    }
  } catch (_) { }
}, 2000).unref();

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

// The first decoder clock ends opening-scan scheduling authority. Keep
// every reader and its retention grant; only far opening readers lose the
// right to move the shared window. New demux reads keep normal read-ahead.
function _adoptOpeningPlayback(playPiece) {
  const ring = getRing();
  const lead = Math.max(1, Math.min(WINDOW_AHEAD_MAX,
    Math.floor((ring?.maxBytes || RAM_CAP_MIN) / torrent.pieceLength / 2)));
  if (currentPlayPiece <= playPiece + lead) return false;
  let playback = null;
  for (const owner of activePumps.values()) {
    if (owner.isProbe || owner.isAnalysis || !owner.hasWritten ||
        owner.playbackToken !== _activePlaybackToken ||
        owner.abortController.signal.aborted || owner.response.destroyed ||
        owner.response.writableEnded || !Number.isSafeInteger(owner.cursorPiece) ||
        owner.cursorPiece < playPiece || owner.cursorPiece > playPiece + lead) continue;
    if (!playback || owner.pumpOrder > playback.pumpOrder) playback = owner;
  }
  const frontier = playback ? playback.cursorPiece : playPiece;
  for (const owner of activePumps.values()) {
    if (owner.playbackToken === _activePlaybackToken &&
        Number.isSafeInteger(owner.cursorPiece) && owner.cursorPiece > frontier + lead) {
      owner.openingScheduleRetired = true;
    }
  }
  currentPlayPiece = frontier;
  if (ring) ring.setPlayhead(frontier);
  _lastWindowForwardAt = 0;
  updateSlidingWindow(frontier, totalFileFirst, totalFileLast, true);
  process.stdout.write(`POS:opening-adopt play=${playPiece} frontier=${frontier} owner=${playback?.pumpOrder ?? 'none'}\n`);
  return true;
}

function _advancePumpFrontier(piece, pumpId, ring, fileFirst, fileLast) {
  const owner = activePumps.get(pumpId);
  if (!owner || owner.openingScheduleRetired || owner.openingScanPacingRetired || owner.isProbe || owner.isAnalysis ||
      owner.playbackToken !== _activePlaybackToken || owner.abortController.signal.aborted ||
      owner.response.destroyed || owner.response.writableEnded) return;
  const frontier = openingSchedulingFloor(piece);
  if (frontier > currentPlayPiece) {
    currentPlayPiece = frontier;
    ring.setPlayhead(frontier);
    updateSlidingWindow(frontier, fileFirst, fileLast, true);
  }
}

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
  if (prevSeconds == null) _adoptOpeningPlayback(clamped);
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

// Additive diagnostics only. No reader walk, disk write, policy or timer change.
function wtMemorySnapshot() {
  try {
    const m = process.memoryUsage();
    const finite = value => Number.isFinite(value) && value >= 0 ? value : null;
    return { rssBytes: finite(m.rss), heapUsedBytes: finite(m.heapUsed),
      externalBytes: finite(m.external), arrayBufferBytes: finite(m.arrayBuffers) };
  } catch (_) {
    return { rssBytes: null, heapUsedBytes: null, externalBytes: null, arrayBufferBytes: null };
  }
}
let _cpuSample = process.cpuUsage();
let _cpuSampleAt = process.hrtime.bigint();
let _statsExpectedAt = Date.now() + 2_000;
let _statsTicks = 0;
setInterval(() => {
  _statsTicks++;
  if (_statsTicks % 30 === 0) emitSelfRow();
  const ring = getRing();
  const now = process.hrtime.bigint();
  const cpu = process.cpuUsage();
  const sampleMs = Number(now - _cpuSampleAt) / 1_000_000;
  const cpuPercent = sampleMs > 0
    ? Math.round((cpu.user - _cpuSample.user + cpu.system - _cpuSample.system) / (sampleMs * 10))
    : 0;
  const loopLagMs = Math.max(0, Date.now() - _statsExpectedAt);
  sampleNodeAfterLag(loopLagMs);
  _cpuSample = cpu;
  _cpuSampleAt = now;
  _statsExpectedAt = Date.now() + 2_000;

  const statsJson = {
    session: process.pid,
    diagnosticsVersion: 1,
    ...wtMemorySnapshot(),
    ringStoredBytes: ring ? ring.bytes : 0,
    ringLimitBytes: ring ? ring.maxBytes : null,
    pieceLengthBytes: torrent.pieceLength || null,
    activePumpCount: activePumps.size,
    maxConnections: MAX_CONNS,
    downloadSpeed: torrent.downloadSpeed,
    uploadSpeed: torrent.uploadSpeed,
    downloaded: torrent.downloaded,
    // Session piece payload includes duplicate/retry blocks, never eviction subtraction.
    receivedPayloadBytes: _receivedPayloadBytes,
    // v22.19: evicted-then-refetched piece payload; gap attribution, never negative.
    refetchedBytes: _refetchedBytes,
    // v22.22: frontier-duplicate payload this session (10% budget, see STALL:frontier-dup-budget).
    dupBytes: _dupBytes,
    // Raw peer socket traffic includes protocol messages; retained for diagnostics.
    receivedTotalBytes: Number.isFinite(torrent.received) && torrent.received >= 0
      ? torrent.received : null,
    progress: torrent.progress,
    numPeers: torrent.numPeers,
    fileLength: currentFileLength,
    ratio: torrent.ratio,
    cpuPercent,
    loopLagMs,
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
  if (process.env.GOR_WT_MONITOR_LOG === '1') { try { appendBounded(LOG_PATH, line); } catch (_) {} }

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
    if (globalRing) { globalRing.pinnedFirst = fFirst; globalRing.pinFileEdges(fFirst, fLast); }

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
    cancelAutoAdvance('startServer:new-file');
    const playbackToken = `${process.pid}-${++_serveGeneration}`;
    _activePlaybackToken = playbackToken;
    _deadPos = null;
    _deadPosSince = 0;
    _deadReqAt = 0;
    _deadObservedOwner = null;
    _playbackEventSequence = -1;
    _explicitRangeSeekUntil = 0;
    lastKnownDuration = 0;
    lastMpvPosSec = null;
    lastMpvPosAt = 0;
    _isUserPaused = false;
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
      currentWindow = null; _retireCursor = null;
    }
    _clearRetryPins();
    _cancelOutsideStream(fileFirst, Math.min(fileLast, fileFirst + WINDOW_AHEAD_MAX));
    currentPlayPiece = fileFirst;

    totalFileFirst = fileFirst;
    totalFileLast = fileLast;
    if (globalRing) { globalRing.pinnedFirst = fileFirst; globalRing.pinFileEdges(fileFirst, fileLast); }
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
      const requestURL = new URL(req.url, `http://127.0.0.1:${port}`);
      if (playbackToken !== _activePlaybackToken) {
        res.writeHead(409); res.end('retired stream'); return;
      }
      if (req.method === 'POST' && requestURL.pathname === '/playback') {
        let body = '';
        req.on('data', chunk => { body += chunk; if (body.length > 8192) req.destroy(); });
        req.on('end', () => {
          try {
            const accepted = handlePlaybackEvent(JSON.parse(body), playbackToken);
            res.writeHead(accepted ? 200 : 409); res.end(accepted ? 'OK' : 'stale playback');
          } catch (_) { res.writeHead(400); res.end('bad json'); }
        });
        return;
      }
      if ((req.method === 'GET' || req.method === 'HEAD') &&
          requestURL.searchParams.get('gor_stream') !== playbackToken) {
        res.writeHead(409); res.end('stale stream URL'); return;
      }

      if (req.method === 'GET' || req.method === 'HEAD') traceHTTPRequest(req, res);

      // CMD endpoint
      if (req.method === 'POST' && requestURL.pathname === '/cmd') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
          const raw = body.trim();
          let line = raw;

          if (raw.startsWith('{')) {
            try {
              const payload = JSON.parse(raw);
              if (payload.token !== playbackToken || playbackToken !== _activePlaybackToken) {
                res.writeHead(409); res.end('stale command'); return;
              }
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
            cancelAutoAdvance('pause');
            process.stdout.write('CMD:pause — reconnect triggers suppressed\n');
            res.writeHead(200); res.end('OK');
          } else if (line === 'RESUME') {
            _isUserPaused = false;
            // Intentional pause is not dead-consumer evidence. Begin a fresh
            // observation window without replacing the live HTTP response.
            const resumedAt = Date.now();
            _deadPos = lastMpvPosSec;
            _deadPosSince = resumedAt;
            _lastStreamActivityAt = resumedAt;
            // Resume preserves the live HTTP response and byte cursor. Rebase
            // its guard clock, never reset its range/cache or skip a piece.
            for (const pump of activePumps.values()) {
              if (!pump.abortController.signal.aborted && pump.response &&
                  !pump.response.destroyed && !pump.response.writableEnded) pump.ts = Date.now();
            }
            // v18.3: resume is exactly when a stale mpv-pos clock or dl0
            // streak (both accrued harmlessly while paused) could misfire
            // as a freeze — clear both so resume starts with a clean window.
            _mpvSuppressedCount = 0;
            _dl0StreamingSince = null;
            // v22.8: waiters aged through the pause must not look stuck on resume; restart stall clocks.
            stallDetector._reset();
            // Rebase inherited clocks (not clear): real stalls still fire, but only after a fresh window.
            if (lastMpvPosAt > 0) lastMpvPosAt = resumedAt;
            if (_lastMpvPosStaleAt > 0) _lastMpvPosStaleAt = resumedAt;
            if (_lastPumpAbortAt > 0) _lastPumpAbortAt = resumedAt;
            { const r = getRing(); if (r) for (const list of r._waiters.values()) for (const w of list) w.startTime = resumedAt; }
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
      if (req.method === 'POST' && requestURL.pathname === '/pos') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
          try {
            const payload = JSON.parse(body || '{}');
            if (payload.token !== playbackToken || playbackToken !== _activePlaybackToken) {
              res.writeHead(409); res.end('stale position'); return;
            }
            if (!Number.isSafeInteger(payload.sequence) || payload.sequence <= _playbackEventSequence) {
              res.writeHead(409); res.end('stale position sequence'); return;
            }
            _playbackEventSequence = payload.sequence;
            if (_autoAdvanceActive) cancelAutoAdvance('position-after-eof');
            const playhead = typeof payload.playhead === 'number' ? payload.playhead : null;
            const duration = typeof payload.duration === 'number' ? payload.duration : null;
            if (playhead == null) {
              res.writeHead(400); res.end('missing playhead');
              return;
            }
            const piece = applyMpvPosition(playhead, duration);
            if (Number.isFinite(playhead) && playhead >= 0 && Number.isFinite(piece)) _lastConsumerEvidenceAt = Date.now();
            // v21.7: arm seek-no-follow watchdog on large jumps; a POS
            // landing near the armed target disarms it (see v21.7).
            if (typeof piece === 'number') {
              if (_seekWatch && Math.abs(piece - _seekWatch.piece) <= 2) _seekWatch = null;
              else if (_lastPosPiece != null && Math.abs(piece - _lastPosPiece) > SEEK_JUMP_PIECES) {
                _seekWatch = { piece, at: Date.now() };
                _clearRetryPins(); // v21.7: a real seek abandons pinned hash-fail retries
              }
              _lastPosPiece = piece;
            }
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

      const isAnalysisRequest = req.headers['x-gor-reader'] === 'analysis';
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

      if (!isAnalysisRequest) { _lastRangeStartPiece = startPiece; _lastStreamActivityAt = Date.now(); }
      // v21.7: a request near the armed seek target disarms the watchdog
      if (!isAnalysisRequest && _seekWatch && Math.abs(startPiece - _seekWatch.piece) <= 2) _seekWatch = null;

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
      try { res.socket.setNoDelay(true); res.socket.setKeepAlive(true, 30_000); } catch (_) { }

      // v17.34: floor prevents underflow on files smaller than MOOV_TAIL_PIECES;
      // without it every startPiece qualifies, freezing currentPlayPiece.
      const isMoovProbe = (fileLast - fileFirst >= MOOV_TAIL_PIECES) &&
        (startPiece >= fileLast - MOOV_TAIL_PIECES);
      // v17.1: fullfile probe gets the exact same treatment as moov probe
      // — neither should move currentPlayPiece or touch window state, both
      // are format/duration checks, not real seeks.
      const isProbeRequest = isMoovProbe || isFullFileProbe;
      let isForwardRequest = !isProbeRequest && !isAnalysisRequest && startPiece >= currentPlayPiece;

      const windowMissing = !currentWindow;

        // v17.22: seek detection — out-of-window Range request. Triggers:
        //   A) _pendingSeekAt set → forward-jump bypass in applyMpvPosition
        //   B) abortPumpsOutsideWindow → old pumps killed immediately
        //   C) _lastWindowForwardAt=0 → post-seek window update not delayed
        //   D) out-of-window waiters flushed → resources freed for new region
        // Probe requests excluded. Both forward and backward directions.
      const explicitSeek = !isAnalysisRequest && Date.now() < _explicitRangeSeekUntil;
      const isSeek = explicitSeek && !isProbeRequest && !isDup && currentWindow &&
        (startPiece < currentWindow.from || startPiece > currentWindow.to);
      if (isSeek) {
        _explicitRangeSeekUntil = 0;
        _pendingSeekAt = Date.now();    // A+E: open forward-jump bypass window
        _lastWindowForwardAt = 0;             // C: reset debounce
        abortPumpsOutsideWindow(startPiece);  // B: abort stale pumps
        _clearRetryPins();
        _cancelOutsideStream(Math.max(fileFirst, startPiece - WINDOW_BEHIND), Math.min(fileLast, startPiece + WINDOW_AHEAD_MAX));
        _armPostSeekReissue(startPiece);
        // D: flush all waiters outside the current window
        const _seekRing = getRing();
        if (_seekRing) {
          let _flushed = 0;
          for (const idx of [..._seekRing.waitedPieces]) {
            if (idx < startPiece || idx > startPiece + WINDOW_AHEAD_MAX) {
              if (idx <= fileFirst) continue; // never flush the container header piece
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

      if (isAnalysisRequest) {
        // Exact source-pixel reads retain their verified-piece waiter/owner,
        // but never rewindow, seek, pace or recover the playback consumer.
        process.stdout.write(`RANGE:analysis pieces=${startPiece}-${endPiece} playbackAuthority=false\n`);
      } else if (isProbeRequest) {
        // v17.34: suppress _selectHighPriority for probe pumps when a non-probe
        // pump is already active. Concurrent tail-file priority selections
        // compete with the playback window, starving pieces at file start.
        // registerPump hasn't run for us yet, so activePumps.size > 0 means
        // a pre-existing pump is active. _selectBaseRange() still fires.
        try {
          const critEnd = Math.min(endPiece, fileLast);
          _selectBaseRange(startPiece, critEnd, false);
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
      } else if (!isDup && isForwardRequest && activePumps.size === 0) {
        updateSlidingWindow(startPiece, fileFirst, fileLast, true);
      } else if (!isDup && explicitSeek) {
        // v17.34: abort old pumps unconditionally on any backward non-dup request.
        // Previously only called on isSeek=true; in-window backward seeks left
        // the old pump running and advancing currentPlayPiece past the target.
        abortPumpsOutsideWindow(startPiece);
        _clearRetryPins();
        _cancelOutsideStream(Math.max(fileFirst, startPiece - WINDOW_BEHIND), Math.min(fileLast, startPiece + WINDOW_AHEAD_MAX));
        _armPostSeekReissue(startPiece);

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
                  ring.forceSkip(idx);
                }
              }
              process.stdout.write(`RANGE:seekback-flush-waiters start=${startPiece}\n`);
            }
          }
        }
      } else if (!isAnalysisRequest && isDup && windowMissing) {
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
        if (!isDup && isForwardRequest && activePumps.size === 0) {
          currentPlayPiece = startPiece;
        }
        getRing()?.setPlayhead(currentPlayPiece);

        pumpId = registerPump(startPiece, abortCtrl, res, isProbeRequest, isAnalysisRequest);
        _succeedOpeningScan(pumpId);
        req.on('close', onClose);
        res.on('close', onClose);

        while (piece <= endPiece && !aborted) {
          const state = activePumps.get(pumpId);
          if (state) {
            if (state.cursorPiece !== piece) { state.cursorAt = Date.now(); state.floorStaleLogged = false; }
            state.cursorPiece = piece; state.ts = Date.now();
          }
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

          if (!isProbeRequest && !isAnalysisRequest) {
            await waitForReaderBudget(piece, pumpId, abortCtrl.signal);
            if (aborted) break;
            const owner = activePumps.get(pumpId);
            if (owner) owner.phase = 'running';
            _advancePumpFrontier(piece, pumpId, ring, fileFirst, fileLast);
          }

          // Check store cache first — avoid waitForPiece if already in RAM
          let buf = ring.chunks.get(piece);
          if (!buf) {
            // v22.0: only a user-issued SKIP may bypass the verified-piece wait.
            // Failed hashes and automatic recovery never authorize bytes.
            if (!(piece > fileFirst && pieceFailureTracker.isManualSkip(piece))) {
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
              buf = await ring.waitForPiece(piece, stallDetector.pieceTimeout, abortCtrl.signal, pumpId);
              // v22.3 B: peers hold the piece and the swarm is alive: do not reset mpv's
              // connection (each reset grew mpv's reconnect backoff 0,1,3,7s then it gave
              // up in the 07:50 log). Rescue the block and wait again, bounded.
              let _holds = 0;
              while (!buf && !aborted && _holds < HOLD_MAX_WAITS && !pieceFailureTracker.isManualSkip(piece) &&
                     peerCount > 0 && stallDetector._countPeersWithPiece(piece, torrent) > 0 && torrent.downloadSpeed > 0) {
                _holds++;
                process.stdout.write(`PUMP:hold piece=${piece} hold=${_holds}/${HOLD_MAX_WAITS} — peers hold it, connection kept\n`);
                try { _rescueStuckBlock(piece); } catch (_) { }
                buf = await ring.waitForPiece(piece, stallDetector.pieceTimeout, abortCtrl.signal, pumpId);
              }
            }
          }

          if (aborted) break;

          if (!buf) {
            // v17.23: abort signal resolved waitForPiece to null — exit
            // without zero-fill. Old code entered the buf=null branch and
            // wrote phantom zeroBuf to the aborted connection before break.
            if (aborted) break;
            // v21.7: seek-orphaned stream — destroy, never zero-fill into a
            // departing demuxer; zeros mid-re-cue poison the next read.
            if (_seekOrphans.has(piece)) {
              const orphanWin = _seekOrphans.get(piece);
              _seekOrphans.delete(piece);
              if (currentWindow && (piece < currentWindow.from || piece > currentWindow.to)) {
                process.stdout.write(`PUMP:seek-orphan piece=${piece} flushed-win=${orphanWin} — connection destroyed (reader seeked away)\n`);
                aborted = true;
                try { res.destroy(); } catch (_) { }
                break;
              }
            }
            const wasManual = pieceFailureTracker.isManualSkip(piece);
            if (!wasManual) {
              const failCount = pieceFailureTracker.recordTimeout(piece);
              // v22.0: an advertised HTTP range cannot contain invented
              // bytes. Abort at the first bounded failure and let WT retry.
              process.stdout.write(
                `PUMP:integrity-reset piece=${piece} fail=${failCount}/${PIECE_FAIL_THRESHOLD} ` +
                `reason=missing-verified-piece — connection reset\n`
              );
              if (failCount >= PIECE_FAIL_THRESHOLD && pieceFailureTracker.markSkippedOnce(piece)) {
                process.stdout.write(`REQ:integrity-stalled piece=${piece} — no verified data; try another release if this persists\n`);
              }
              aborted = true;
              try { res.destroy(); } catch (_) { }
              break;
            }

            // Explicit CMD:SKIP alone retains its deliberate zero-fill.
            if (piece === fileFirst) {
              process.stdout.write(`PUMP:skip-fileFirst-blocked piece=${piece} — connection reset\n`);
              aborted = true;
              try { res.destroy(); } catch (_) { }
              break;
            }
            if (pieceFailureTracker.markSkippedOnce(piece)) {
              process.stdout.write(`PUMP:zero-fill-manual piece=${piece} — zero fill (manual)\n`);
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
                await waitForPumpDrain(res, abortCtrl.signal, pumpId, piece);
              }
            }

            // Advance playhead past the skipped piece
            if (!isDup && isForwardRequest && piece >= currentPlayPiece &&
                !activePumps.get(pumpId)?.openingScheduleRetired &&
                !activePumps.get(pumpId)?.openingScanPacingRetired) {
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
          // Both true and false accept this nonempty chunk. Backpressure is
          // not a failed write; analysis/old/aborted pumps are not evidence.
          const owner = activePumps.get(pumpId);
          if (chunk.length > 0 && owner && !owner.isAnalysis && !aborted &&
              owner.playbackToken === _activePlaybackToken &&
              playbackToken === _activePlaybackToken && owner.response === res &&
              !abortCtrl.signal.aborted && !res.destroyed && !res.writableEnded) {
            owner.hasWritten = true;
            owner.lastWriteAt = Date.now();
          }
          if (!ok && !aborted) {
            await waitForPumpDrain(res, abortCtrl.signal, pumpId, piece);
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
        // A terminal abort must also close the HTTP response. Leaving a live
        // socket with no pump prevents the player issuing a replacement Range.
        if (aborted && !res.destroyed) {
          try { res.destroy(); } catch (_) { }
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
        if (!isAnalysisRequest) {
          if (aborted) {
            if (!isProbeRequest) _lastPumpAbortAt = Date.now();
          } else {
            _lastPumpAbortAt = 0;
          }
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
    globalThis.__wtHttpServer = server;
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
      const boundAddress = server.address();
      if (!boundAddress || typeof boundAddress === 'string') {
        process.stdout.write('SERVER_ERR:missing bound HTTP port\n');
        server.close(); return;
      }
      const boundPort = boundAddress.port;
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
      process.stdout.write(`FILM_ID:${JSON.stringify({url:`http://localhost:${boundPort}/?gor_stream=${playbackToken}`,infohash:torrent.infoHash,index:torrent.files.indexOf(file),basename:file.name,size:file.length})}\n`);
      process.stdout.write(`STREAM:http://localhost:${boundPort}/?gor_stream=${playbackToken}\n`);
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
