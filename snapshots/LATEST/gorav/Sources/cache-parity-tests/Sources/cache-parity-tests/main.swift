// Sources/cache-parity-tests/Sources/cache-parity-tests/main.swift  (exit 0 = all pass)
// Row GORAV-CACHE-PARITY: validation, gor-parity baseline pins, by-source
// immutability and NSLock race witnesses for CacheTuningPolicy(Table).
// The policy source is compiled into this target through a relative symlink
// (see the local Package.swift); there is no GorAVPlaybackCore import.
import Foundation
import Dispatch
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

var failures = 0
func check(_ n: String, _ ok: Bool) { print(ok ? "PASS \(n)" : "FAIL \(n)"); if !ok { failures += 1 } }

func policy(enabled: Bool = true, secs: Double = 8, pauseInitial: Bool = false,
            pause: Bool = true, pauseWait: Double = 0, onDisk: Bool = false,
            forward: UInt64 = 128 * 1024 * 1024, back: UInt64 = 0, readahead: Double = 0) -> CacheTuningPolicy? {
    CacheTuningPolicy(cacheEnabled: enabled, cacheSecs: secs, cachePauseInitial: pauseInitial,
                      cachePause: pause, cachePauseWaitSecs: pauseWait, cacheOnDisk: onDisk,
                      forwardCapacityBytes: forward, backCapacityBytes: back, readaheadSecs: readahead)
}

// V: validated construction
check("V1 rejects NaN and negative seconds",
      policy(secs: .nan) == nil && policy(secs: -1) == nil
      && policy(pauseWait: .infinity) == nil && policy(readahead: -0.5) == nil)
check("V2 rejects backward window above forward window",
      policy(forward: 100, back: 101) == nil && policy(forward: 100, back: 100) != nil)
check("V3 enabled cache requires positive forward capacity; disabled may carry zero",
      policy(enabled: true, forward: 0) == nil && policy(enabled: false, forward: 0, back: 0) != nil)
check("V4 accepts the gor-parity baseline shape", policy() != nil)

// B: gor-parity baseline pins (docs/LEDGER.tsv @ gor 56181f76, AppDelegate 1266-1268)
let baseline = CacheTuningPolicy.gorParityBaseline()
check("B1 baseline pins gor launch: cache=yes, cache-secs=8, cache-pause-initial=no",
      baseline.cacheEnabled && baseline.cacheSecs == 8 && !baseline.cachePauseInitial)
check("B2 source kinds cover gor's five cache-tuned classes",
      CacheSourceKind.allCases.count == 5)
// Pin test: values from in-repo bytes, gorav historical commit f7ebdf56 tree
// archive/gor/Sources/gor/AppDelegate.swift:959-964 (mpv launch array).
check("B3 launch cluster pins: max-bytes=128M, back-bytes=32M, readahead=10s",
      baseline.forwardCapacityBytes == 128 * 1024 * 1024
      && baseline.backCapacityBytes == 32 * 1024 * 1024
      && baseline.readaheadSecs == 10)

// P: per-source pins (gorav historical f7ebdf56 tree MenuActions.swift:1010-1071)
let archiveBase = CacheTuningPolicy.gorParityBaseline(for: .archiveItem)
check("P1 archiveItem pins gor's per-file archive.org profile",
      archiveBase.cacheEnabled && archiveBase.cacheSecs == 120 && !archiveBase.cachePauseInitial
      && archiveBase.cachePauseWaitSecs == 1 && !archiveBase.cacheOnDisk
      && archiveBase.forwardCapacityBytes == 256 * 1024 * 1024
      && archiveBase.backCapacityBytes == 128 * 1024 * 1024 && archiveBase.readaheadSecs == 120)
let netBase = CacheTuningPolicy.gorParityBaseline(for: .networkStream)
check("P2 networkStream is launch + else-branch overrides (secs 30, 500M, readahead 120; back 32M stands)",
      netBase.cacheSecs == 30 && netBase.forwardCapacityBytes == 500 * 1024 * 1024
      && netBase.readaheadSecs == 120 && netBase.backCapacityBytes == 32 * 1024 * 1024
      && netBase.cacheEnabled && !netBase.cachePauseInitial)
check("P3 gap kinds (localFile, hlsVOD, torrentRelay) hold the launch baseline",
      CacheTuningPolicy.gorParityBaseline(for: .localFile) == baseline
      && CacheTuningPolicy.gorParityBaseline(for: .hlsVOD) == baseline
      && CacheTuningPolicy.gorParityBaseline(for: .torrentRelay) == baseline)
let pixel = CacheTuningPolicy.gorParityPixeldrainOverride()
check("P4 pixeldrain host override pins (secs 3600, 4096M/1024M, readahead 3600, on-disk, pause-initial, wait 600)",
      pixel.cacheSecs == 3600 && pixel.forwardCapacityBytes == 4096 * 1024 * 1024
      && pixel.backCapacityBytes == 1024 * 1024 * 1024 && pixel.readaheadSecs == 3600
      && pixel.cacheOnDisk && pixel.cachePauseInitial && pixel.cachePauseWaitSecs == 600)
check("P5 per-source seeding now differs by kind where gor differs",
      CacheTuningPolicy.gorParityBaseline(for: .archiveItem) != CacheTuningPolicy.gorParityBaseline(for: .networkStream)
      && CacheTuningPolicy.gorParityBaseline(for: .archiveItem) != baseline)

// Q: torrentRelay PARAMS-driven pins (composition TorrentManager.swift blob
// 5db095ce :469-508): cache=yes, pause-initial=yes, pause=no, readahead=secs,
// max-bytes=PARAMS, back 32M launch stands
if let t = CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 2_147_000_000, cacheSecs: 900) {
    check("Q1 PARAMS policy pins: pause=no, pause-initial=yes, on-disk/wait untouched",
          !t.cachePause && t.cachePauseInitial && t.cacheEnabled && !t.cacheOnDisk && t.cachePauseWaitSecs == 0)
    check("Q2 PARAMS linkage: readahead == cacheSecs, forward == PARAMS bytes, back = launch 32M",
          t.readaheadSecs == 900 && t.cacheSecs == 900
          && t.forwardCapacityBytes == 2_147_000_000 && t.backCapacityBytes == 32 * 1024 * 1024)
} else { check("Q1 PARAMS policy pins: pause=no, pause-initial=yes, on-disk/wait untouched", false); check("Q2 PARAMS linkage: readahead == cacheSecs, forward == PARAMS bytes, back = launch 32M", false) }
check("Q3 invalid PARAMS refused (zero bytes, zero/NaN secs)",
      CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 0, cacheSecs: 900) == nil
      && CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 1024, cacheSecs: 0) == nil
      && CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 1024, cacheSecs: .nan) == nil)

// H: HLS prepare-time budget pins (HLSVODSource.swift c1431906 :37/:45/:55/
// :76/:80/:108/:109) and the localFile typed fact (no per-source cache
// option on cited local open paths: gor MenuActions.openFile :721-776;
// gorav FFmpegSoftwareDecoder.swift:767-770 remoteOptions=nil)
let hls = HLSCacheBudget.goravPinned
check("H1 HLS budget pins: 1MiB playlist, 4MiB init, 16MiB segment, 64MiB total",
      hls.playlistCapBytes == 1 * 1024 * 1024 && hls.initSegmentCapBytes == 4 * 1024 * 1024
      && hls.segmentCapBytes == 16 * 1024 * 1024 && hls.totalBudgetBytes == 64 * 1024 * 1024)
check("H2 HLS fetch pins: request 10s, resource 20s, shared URL cache disabled",
      hls.requestTimeoutSecs == 10 && hls.resourceTimeoutSecs == 20 && hls.sharedURLCacheDisabled)
check("H3 localFile typed fact: launch-shaped consumption, capacity 128MiB/secs 8/readahead 10",
      (try? CachePolicyConsumption.resolve(route: .localFile, table: CacheTuningPolicyTable.seedingWithGorParity()))
      == CacheConsumption(kind: .localFile, capacityBytes: 128 * 1024 * 1024,
                          cacheSecs: 8, readaheadSecs: 10, pauseInitial: false))

// T: table semantics
let table = CacheTuningPolicyTable.seedingWithGorParity()
check("T1 seeded table answers every kind with its per-source parity baseline",
      CacheSourceKind.allCases.allSatisfy { (try? table.policy(for: $0)) == CacheTuningPolicy.gorParityBaseline(for: $0) })
check("T2 duplicate registration is refused and the first policy stands",
      (try? table.register(policy: baseline, for: .localFile)) == nil
      && (try? table.policy(for: .localFile)) == baseline)
if let tuned = policy(secs: 30, forward: 256 * 1024 * 1024, back: 64 * 1024 * 1024) {
    let t2 = CacheTuningPolicyTable()
    try? t2.register(policy: baseline, for: .networkStream)
    try? t2.register(policy: tuned, for: .torrentRelay)
    check("T3 by-source: distinct registered policies stay distinct per kind",
          (try? t2.policy(for: .networkStream)) == baseline
          && (try? t2.policy(for: .torrentRelay)) == tuned
          && (try? t2.policy(for: .networkStream)) != (try? t2.policy(for: .torrentRelay)))
} else {
    check("T3 by-source: distinct registered policies stay distinct per kind", false)
}
check("T4 unregistered kind is a typed refusal, not an invented default",
      (try? CacheTuningPolicyTable().policy(for: .hlsVOD)) == nil)
check("T5 registeredKinds tracks registration in declaration order",
      CacheTuningPolicyTable.seedingWithGorParity().registeredKinds == CacheSourceKind.allCases)
do {
    _ = try CacheTuningPolicyTable().policy(for: .archiveItem)
    check("T6 refusal carries the queried kind", false)
} catch let e as CacheTuningPolicyError {
    check("T6 refusal carries the queried kind", e == .unknownSource(.archiveItem))
} catch {
    check("T6 refusal carries the queried kind", false)
}
do {
    let seeded = CacheTuningPolicyTable.seedingWithGorParity()
    _ = try seeded.register(policy: baseline, for: .hlsVOD)
    check("T7 duplicate refusal carries the kind", false)
} catch let e as CacheTuningPolicyError {
    check("T7 duplicate refusal carries the kind", e == .duplicateRegistration(.hlsVOD))
} catch {
    check("T7 duplicate refusal carries the kind", false)
}

// C: NSLock race witnesses
let shared = CacheTuningPolicyTable.seedingWithGorParity()
let mismatch = NSLock()
var raceMismatch = false
DispatchQueue.concurrentPerform(iterations: 8) { _ in
    for _ in 0..<1000 {
        if (try? shared.policy(for: .networkStream)) != CacheTuningPolicy.gorParityBaseline(for: .networkStream) {
            mismatch.lock(); raceMismatch = true; mismatch.unlock()
        }
    }
}
check("C1 8000 concurrent locked reads all return the registered baseline", !raceMismatch)
let contested = CacheTuningPolicyTable()
let counter = NSLock()
var duplicateRefusals = 0
DispatchQueue.concurrentPerform(iterations: 16) { i in
    if let p = policy(secs: Double(i + 1)) {
        do { try contested.register(policy: p, for: .localFile) }
        catch CacheTuningPolicyError.duplicateRegistration(.localFile) {
            counter.lock(); duplicateRefusals += 1; counter.unlock()
        } catch {}
    }
}
check("C2 concurrent registrations: exactly one wins, 15 refused, winner readable",
      duplicateRefusals == 15 && (try? contested.policy(for: .localFile)) != nil)

// S: pure consumption seam (call-site model: FFmpegSoftwareDecoder.swift:768)
check("S1 not-yet-openable route refuses policy resolution, typed",
      (try? CachePolicyConsumption.resolve(route: .needsExternalResolve, table: table)) == nil)
check("S2 decoder-open shape: admittedHTTP resolves the per-kind networkStream policy fields",
      (try? CachePolicyConsumption.resolve(route: .admittedHTTP, table: table))
      == CacheConsumption(kind: .networkStream, capacityBytes: 500 * 1024 * 1024,
                          cacheSecs: 30, readaheadSecs: 120, pauseInitial: false))
check("S3 empty table fails closed at the seam with the missing kind",
      (try? CachePolicyConsumption.resolve(route: .localFile, table: CacheTuningPolicyTable())) == nil)
do {
    _ = try CachePolicyConsumption.resolve(route: .archiveItem, table: CacheTuningPolicyTable())
    check("S4 seam refusal carries the missing kind", false)
} catch let e as CacheSeamError {
    check("S4 seam refusal carries the missing kind", e == .noPolicy(.archiveItem))
} catch {
    check("S4 seam refusal carries the missing kind", false)
}
if let tuned = policy(secs: 30, forward: 256 * 1024 * 1024, back: 64 * 1024 * 1024) {
    let t2 = CacheTuningPolicyTable()
    try? t2.register(policy: baseline, for: .networkStream)
    try? t2.register(policy: tuned, for: .torrentRelay)
    let plain = try? CachePolicyConsumption.resolve(route: .admittedHTTP, table: t2)
    let torrent = try? CachePolicyConsumption.resolve(route: .torrentBridged, table: t2)
    check("S5 per-source consumption differs by routed kind through the seam",
          plain?.capacityBytes == 128 * 1024 * 1024 && torrent?.capacityBytes == 256 * 1024 * 1024
          && plain?.cacheSecs == 8 && torrent?.cacheSecs == 30)
} else {
    check("S5 per-source consumption differs by routed kind through the seam", false)
}

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
exit(failures == 0 ? 0 : 1)
