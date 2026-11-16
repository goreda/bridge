# W-gdb-d53: 195b-53 follow-on: byte-owning backend behind the lease release hook
> rev 2026-11-16-r4: pin rolled a34e2cd -> dbd96d4 (Package.swift grew; ex_pkg_target re-located 14-14 -> 16-16, byte-identical, hash unchanged); all excerpts re-verified byte-identical at dbd96d4.

> rev 2026-11-16-r2: excerpt ranges/hashes rebound to pin 8786bfe3 (Team A log-verify fixes: 040 whole-file 1-137, d59 ex_store 119-155, d64 ex_test_tail 115-134, G0761 hash map added, stale header shas replaced). Supersedes the 2026-11-16 minting only after a fresh gate-flow run_proof binds to these bytes
> rev 2026-11-16-r3: pin rolled 8786bfe3 -> a34e2cd (arch-197e item 5 self-decision; the delta is docs/LEDGER.tsv only, every excerpt body re-verified byte-identical and excerpt_sha256_8 unchanged). Supersedes the r2 receipts once a fresh gate-flow run_proof binds at a34e2cd.


Row 195b-53 landed lease BOOKKEEPING: FrameLeaseStore calls one release hook on every release path, but nothing owns the bytes behind that hook. Write `RetainedPixelOwner`, a portable owner that holds the retained frame bytes by handle, frees them exactly once when the store's hook fires, and ledgers double and unknown releases. It must not read pixels on the render thread and must not touch the store lock. The decoder producer wiring and native/Metal pixels stay open.

Not in scope: native pixel retention, producer wiring in FFmpegSoftwareDecoder, GPU readback, any change to FrameLeaseStore or DecodedFrameTap source. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
  "packet": "W-gdb-d53",
  "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
  "scope": "implementation",
  "product_repo": "goreda/gorav",
  "product_branch": "engine",
  "product_sha": "dbd96d4cf3309d4c31d2f2d96bfbf49f918047b2",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/FrameLeaseStore.swift",
      "excerpt_block": "ex_refusal",
      "lines": "34-64"
    },
    {
      "path": "Sources/GorAVPlaybackCore/FrameLeaseStore.swift",
      "excerpt_block": "ex_store_init",
      "lines": "136-150"
    },
    {
      "path": "Sources/GorAVPlaybackCore/DecodedFrameTap.swift",
      "excerpt_block": "ex_tap_attach",
      "lines": "73-77"
    },
    {
      "path": "Sources/GorAVPlaybackCore/DecodedFrameTap.swift",
      "excerpt_block": "ex_tap_offerleased",
      "lines": "145-191"
    },
    {
      "path": "Package.swift",
      "excerpt_block": "ex_pkg_target",
      "lines": "16-16"
    }
  ],
  "excerpt_sha256_8": {
    "ex_refusal": "78a2afbf",
    "ex_store_init": "921730ea",
    "ex_tap_attach": "365b5850",
    "ex_tap_offerleased": "7370ffa0",
    "ex_pkg_target": "c4c987da"
  },
  "interface": {
    "signatures": "public final class RetainedPixelOwner: @unchecked Sendable { public init(session: UInt64); public func adopt(handle: UInt64, bytes: [UInt8]); public func abandon(handle: UInt64); public var releaseHook: (UInt64, UInt64) -> Void { get }; public func firstByte(handle: UInt64) -> UInt8?; public var liveHandles: [UInt64] { get }; public var releasedHandles: [UInt64] { get }; public var abandonedHandles: [UInt64] { get }; public var liveBytes: Int { get }; public var unknownReleases: Int { get }; public var doubleReleases: Int { get }; public var adoptedCount: Int { get } }. liveHandles, releasedHandles and abandonedHandles return handles sorted ascending by handle.",
    "types": "Handles and sessions are UInt64, the same values as NativeFrame.handle and NativeFrame.session. Bytes are stored as [UInt8]. The release hook type is (handle: UInt64, session: UInt64) -> Void, exactly the onRelease parameter of FrameLeaseStore.init.",
    "ownership_lifetime": "adopt moves the byte array into the owner under an NSLock. The caller adopts BEFORE offerLeased. If offerLeased returns refusedLease or any non-accepted verdict, the caller calls abandon(handle) to free the bytes. The store fires releaseHook exactly once per retained lease (immediately or after the last unpin), and the owner frees the bytes on that call and appends the handle to releasedHandles. A hook for a handle that was already freed increments doubleReleases; a hook for a handle never adopted increments unknownReleases; neither crashes. The hook is called without the store lock held, and the owner must never call back into the store.",
    "caller": "The decoder frame producer (future wiring, not in this packet) calls adopt then DecodedFrameTap.offerLeased(frame, clockNow:, seekGeneration:); frame-lease-tests style consumers read bytes through FrameLeaseStore.withPinnedAccess and owner.firstByte.",
    "callee": "RetainedPixelOwner implements only Foundation (NSLock, Array). It calls no GorAV API."
  },
  "test": {
    "command": "swift run retained-owner-tests",
    "expected": "Exit 0 and stdout ends with the line \"retained-owner-tests: 0 FAIL\" after 13 lines PASS O1 through PASS O13. Any FAIL line exits 1.",
    "fixture_block": "fx_retained_owner_tests",
    "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
  },
  "target": {
    "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
    "paths": [
      "Sources/GorAVPlaybackCore/RetainedFrameOwner.swift",
      "Sources/retained-owner-tests/main.swift",
      "Package.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Package.swift",
        "block": "merged_package"
      },
      {
        "path": "Sources/retained-owner-tests/main.swift",
        "block": "fx_retained_owner_tests"
      },
      {
        "path": "Sources/GorAVPlaybackCore/RetainedPixelOwner.swift",
        "block": "fx_owner_patch"
      }
    ]
  }
}
```

## Excerpt ex_refusal

```swift id=ex_refusal
// Sources/GorAVPlaybackCore/FrameLeaseStore.swift lines 34-64 @ dbd96d4cf3309d4c31d2f2d96bfbf49f918047b2
public enum FrameLeaseRefusal: Error, Equatable, Sendable {
    /// Frame session does not match the store's session.
    case foreignSession
    /// Store is closed; nothing can be retained, pinned, accessed or released.
    case storeClosed
    /// No live lease known for this handle (never retained, or already
    /// logically released by overflow/fence/close).
    case unknownLease
    /// Caller's or lease's seek generation is behind the store's fence.
    case staleGeneration(current: UInt64)
    /// Release or access of a lease that was already explicitly released.
    case alreadyReleased
    /// A lease for this handle is already outstanding (including one whose
    /// owner hook is still deferred behind pins).
    case duplicateLease
    /// Single frame exceeds the byte budget even when empty, or a negative
    /// byte count was claimed.
    case exceedsCapacity
    /// Overflow could not be resolved: every evictable candidate is pinned.
    case overflowBlockedByPins
    /// unpin without a matching outstanding pin.
    case notPinned
    /// The caller offered a frame without the generation the lease needs
    /// (produced by DecodedFrameTap's generation-less offer in lease mode).
    case generationRequired
}

public struct FrameLeaseCounters: Equatable, Sendable {
    public var retained = 0
    public var pinned = 0
    public var unpinned = 0
```

## Excerpt ex_store_init

```swift id=ex_store_init
// Sources/GorAVPlaybackCore/FrameLeaseStore.swift lines 136-150 @ dbd96d4cf3309d4c31d2f2d96bfbf49f918047b2
    public init(session: UInt64, maxLeases: Int, maxBytes: Int,
                initialGeneration: UInt64 = 0,
                onRelease: @escaping (UInt64, UInt64) -> Void) {
        self.session = session
        self.maxLeases = max(1, maxLeases)
        self.maxBytes = max(1, maxBytes)
        self.generation = initialGeneration
        self.onRelease = onRelease
    }

    /// The only frame session this store serves (set at init).
    public var storeSession: UInt64 { session }
    public var outstandingCount: Int { lock.lock(); defer { lock.unlock() }; return leases.count }
    public var outstandingByteCount: Int { lock.lock(); defer { lock.unlock() }; return outstandingBytes }
    public var currentGeneration: UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
```

## Excerpt ex_tap_attach

```swift id=ex_tap_attach
// Sources/GorAVPlaybackCore/DecodedFrameTap.swift lines 73-77 @ dbd96d4cf3309d4c31d2f2d96bfbf49f918047b2
    public mutating func attachLeaseStore(_ store: FrameLeaseStore, byteEstimate: @escaping @Sendable (NativeFrame) -> Int) {
        precondition(store.storeSession == session, "lease store session must match the tap session")
        self.leaseStore = store
        self.byteEstimate = byteEstimate
    }
```

## Excerpt ex_tap_offerleased

```swift id=ex_tap_offerleased
// Sources/GorAVPlaybackCore/DecodedFrameTap.swift lines 145-191 @ dbd96d4cf3309d4c31d2f2d96bfbf49f918047b2
    @discardableResult
    public mutating func offerLeased(_ frame: NativeFrame, clockNow: Double, seekGeneration: UInt64) -> Verdict {
        guard let store = leaseStore else { return offer(frame, clockNow: clockNow) }
        guard frame.session == session else {
            counters.refusedStaleSession += 1
            return .refusedStaleSession
        }
        if minInterval > 0, clockNow.isFinite, let last = lastAcceptClock, clockNow - last < minInterval {
            counters.droppedRateLimit += 1
            return .droppedRateLimit
        }
        switch store.retain(frame, bytes: byteEstimate?(frame) ?? 0, seekGeneration: seekGeneration) {
        case .failure(let refusal):
            counters.refusedLease += 1
            return .refusedLease(refusal)
        case .success:
            break
        }
        var verdict: Verdict = .accepted
        if queue.count >= capacity {
            let evicted = queue.removeFirst()
            counters.evictedOldest += 1
            verdict = .acceptedEvictingOldest
            // Bounded overflow logically releases the evicted frame's lease
            // (owner hook deferred while that lease is pinned).
            _ = store.release(evicted.handle)
        }
        queue.append(frame)
        newest = frame
        if clockNow.isFinite { lastAcceptClock = clockNow }
        counters.accepted += 1
        return verdict
    }

    /// Oldest queued frame (FIFO) for consumers like crop/live-depth/brightness.
    public mutating func next() -> NativeFrame? {
        queue.isEmpty ? nil : queue.removeFirst()
    }

    /// Newest accepted frame for the screenshot readback path. The caller
    /// copies pixels from the still-leased frame through its own hook; the
    /// tap returns stored identity and PTS only. It cannot vouch for lease validity,
    /// generation or freshness. The caller must check those before readback.
    public mutating func latestForReadback() -> NativeFrame? {
        if newest != nil { counters.readbacks += 1 }
        return newest
    }
```

## Excerpt ex_pkg_target

```swift id=ex_pkg_target
// Package.swift lines 16-16 @ dbd96d4cf3309d4c31d2f2d96bfbf49f918047b2
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVCore"], path: "Sources/frame-lease-tests"),
```

## Fixture fx_retained_owner_tests

```swift id=fx_retained_owner_tests
import Foundation
import GorAVPlaybackCore
import GorAVNativeProbeKit

var failures = 0
func check(_ id: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + id + (ok || detail.isEmpty ? "" : " " + detail))
    if !ok { failures += 1 }
}
func frame(_ s: UInt64, _ h: UInt64) -> NativeFrame {
    NativeFrame(session: s, handle: h, pts: Int64(h), duration: 1, width: 2, height: 2,
                pixelFormatName: "fake", isKeyFrame: false)
}

let owner = RetainedPixelOwner(session: 7)
let store = FrameLeaseStore(session: 7, maxLeases: 8, maxBytes: 1024, onRelease: owner.releaseHook)
var tap = DecodedFrameTap(session: 7, capacity: 2, maxPerSecond: 0)
tap.attachLeaseStore(store, byteEstimate: { _ in 16 })

for h in 1...3 {
    owner.adopt(handle: UInt64(h), bytes: [UInt8](repeating: UInt8(h), count: 16))
    _ = tap.offerLeased(frame(7, UInt64(h)), clockNow: .nan, seekGeneration: 0)
}
check("O1 overflow released the oldest frame's bytes", owner.liveHandles == [2, 3] && owner.releasedHandles == [1])
check("O2 live bytes match the two retained frames", owner.liveBytes == 32)
check("O3 pinned access reads owner bytes without copying out of the owner",
      store.withPinnedAccess(3, seekGeneration: 0, { _ in owner.firstByte(handle: 3) }) == .success(3))

tap.fenceLeases(newGeneration: 1)
check("O4 seek fence released every older-generation lease", owner.liveHandles.isEmpty && owner.releasedHandles == [1, 2, 3])
check("O5 live bytes are zero after the fence", owner.liveBytes == 0)

owner.adopt(handle: 4, bytes: [UInt8](repeating: 4, count: 16))
let stale = tap.offerLeased(frame(7, 4), clockNow: .nan, seekGeneration: 0)
var staleRefused = false
if case .refusedLease(.staleGeneration) = stale { staleRefused = true }
check("O6 stale in-flight frame refused typed", staleRefused, "\(stale)")
check("O7 refused frame stays owner-held until abandon", owner.liveHandles == [4])
owner.abandon(handle: 4)
check("O8 abandon frees refused frame bytes", owner.liveHandles.isEmpty && owner.abandonedHandles == [4])

owner.adopt(handle: 5, bytes: [UInt8](repeating: 5, count: 16))
_ = tap.offerLeased(frame(7, 5), clockNow: .nan, seekGeneration: 1)
check("O9 current-generation frame retained", owner.liveHandles == [5])
tap.closeLeases()
check("O10 close released everything", owner.liveHandles.isEmpty && owner.releasedHandles == [1, 2, 3, 5])

owner.releaseHook(99, 7)
check("O11 unknown handle release is counted, not a crash", owner.unknownReleases == 1)
owner.releaseHook(5, 7)
check("O12 second release of a freed handle is counted as a double free", owner.doubleReleases == 1)
check("O13 ledger balances: adopted == released + abandoned + live",
      owner.adoptedCount == owner.releasedHandles.count + owner.abandonedHandles.count + owner.liveHandles.count)
print("retained-owner-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)

```

## Fixture fx_package_additions

```swift id=fx_package_additions
// Package.swift additions (two lines, same style as frame-lease-tests):
// in products: .executable(name: "retained-owner-tests", targets: ["retained-owner-tests"])
// in targets:  .executableTarget(name: "retained-owner-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/retained-owner-tests"),
```

```swift id=merged_package
// swift-tools-version: 5.9
// SOURCE-ONLY PROPOSAL. Isolated decoder tree, NOT a production replacement.
// Locked include/library search paths must come from a verified provider lock.
import PackageDescription

let package = Package(
    name: "GorAVDecoderOnlyCandidate",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "retained-owner-tests", targets: ["retained-owner-tests"]), .executable(name: "frame-lease-tests", targets: ["frame-lease-tests"]), .executable(name: "audio-interrupt-tests", targets: ["audio-interrupt-tests"]), .executable(name: "cue-output-tests", targets: ["cue-output-tests"]), .executable(name: "render-graph-tests", targets: ["render-graph-tests"]), .executable(name: "decoder-inventory-tests", targets: ["decoder-inventory-tests"]), .executable(name: "color-stage-tests", targets: ["color-stage-tests"]), .executable(name: "crop-tests", targets: ["crop-tests"]), .executable(name: "frame-tap-tests", targets: ["frame-tap-tests"]), .executable(name: "media-inventory-tests", targets: ["media-inventory-tests"]), .executable(name: "remote-source-tests", targets: ["remote-source-tests"]), .executable(name: "prepared-shot-tests", targets: ["prepared-shot-tests"]), .executable(name: "hosttransform-tests", targets: ["hosttransform-tests"]), .executable(name: "timepos-tests", targets: ["timepos-tests"]), .executable(name: "timepos-vector-tests", targets: ["timepos-vector-tests"]), .executable(name: "controlbus-tests", targets: ["controlbus-tests"]), .executable(name: "gorav-probe", targets: ["gorav-probe"]), .library(name: "BridgeVTDecode", targets: ["BridgeVTDecode"]), .library(name: "AudioMasterScheduler", targets: ["AudioMasterScheduler"]), .executable(name: "gorav-sink-check", targets: ["gorav-sink-check"]), .executable(name: "gorav-first-frame", targets: ["gorav-first-frame"]), .executable(name: "refusal-tests", targets: ["refusal-tests"]), .executable(name: "playback-test", targets: ["playback-test"]), .executable(name: "audio-test", targets: ["audio-test"]), .executable(name: "seek-test", targets: ["seek-test"]), .executable(name: "audio-refusal-tests", targets: ["audio-refusal-tests"]), .executable(name: "video-refusal-tests", targets: ["video-refusal-tests"]), .executable(name: "coexist-test", targets: ["coexist-test"]), .executable(name: "isolation-test", targets: ["isolation-test"]), .executable(name: "trace-dump", targets: ["trace-dump"]), .executable(name: "core-seek-tests", targets: ["core-seek-tests"]), .executable(name: "real-seek-tests", targets: ["real-seek-tests"]), .executable(name: "seek-ring-reset-tests", targets: ["seek-ring-reset-tests"]), .executable(name: "seek-pacing-tests", targets: ["seek-pacing-tests"]), .executable(name: "seek-composition-tests", targets: ["seek-composition-tests"]), .executable(name: "audio-seek-tests", targets: ["audio-seek-tests"]), .executable(name: "audio-baseline-tests", targets: ["audio-baseline-tests"]), .executable(name: "demux-parity-tests", targets: ["demux-parity-tests"]), .executable(name: "seek-contract-tests", targets: ["seek-contract-tests"]), .executable(name: "adversarial-seek-tests", targets: ["adversarial-seek-tests"]), .executable(name: "shell-seek-bridge-tests", targets: ["shell-seek-bridge-tests"]), .executable(name: "k9-adversarial", targets: ["k9-adversarial"]), .executable(name: "shell-mac-test", targets: ["shell-mac-test"]), .executable(name: "frame-dump", targets: ["frame-dump"]), .executable(name: "gorav-play", targets: ["gorav-play"]), .executable(name: "l4-hwdecode-tests", targets: ["l4-hwdecode-tests"]), .executable(name: "timing-ledger-tests", targets: ["timing-ledger-tests"]), .executable(name: "race-witness-tests", targets: ["race-witness-tests"]), .executable(name: "gorav-metal-check", targets: ["gorav-metal-check"]), .library(name: "GorAVFFmpegAdapter", targets: ["GorAVFFmpegAdapter"]), .library(name: "GorAVAudioClockSwift", targets: ["GorAVAudioClockSwift"]), .library(name: "GorAVSubtitles", targets: ["GorAVSubtitles"]), .executable(name: "subtitle-srt-tests", targets: ["subtitle-srt-tests"]), .executable(name: "vtt-parser-tests", targets: ["vtt-parser-tests"]), .executable(name: "l3-convert-matrix-tests", targets: ["l3-convert-matrix-tests"]), .executable(name: "avsync-golden-tests", targets: ["avsync-golden-tests"]), .executable(name: "transport-vector-tests", targets: ["transport-vector-tests"]), .executable(name: "subtitle-ass-tests", targets: ["subtitle-ass-tests"]), .executable(name: "subtitle-track-tests", targets: ["subtitle-track-tests"]), .library(name: "GorAVEmbeddedShell", targets: ["GorAVEmbeddedShell"]), .executable(name: "admission-tests", targets: ["admission-tests"]), .executable(name: "session-venue-tests", targets: ["session-venue-tests"]), .executable(name: "b-gate-tests", targets: ["b-gate-tests"]), .executable(name: "seek-restart-probe", targets: ["seek-restart-probe"]), .executable(name: "e1-shapes-tests", targets: ["e1-shapes-tests"]), .executable(name: "parity-pixel-tests", targets: ["parity-pixel-tests"]), .executable(name: "untagged-color-tests", targets: ["untagged-color-tests"])],
    targets: [
        .executableTarget(name: "n6-native-tests", dependencies: ["GorAVMetalPresenter", "GorAVPlaybackCore", "GorAVSubtitles"], path: "Sources/n6-native-tests"),
        .executableTarget(name: "uniform-packing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/uniform-packing-tests"),
        .executableTarget(name: "active-transport-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter", "GorAVNativeProbeKit", "CFFmpeg"], path: "Sources/active-transport-tests"),
        .executableTarget(name: "frame-lease-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVCore"], path: "Sources/frame-lease-tests"),
        .executableTarget(name: "retained-owner-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/retained-owner-tests"),
        .executableTarget(name: "audio-interrupt-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/audio-interrupt-tests"),
        .executableTarget(name: "cue-output-tests", dependencies: ["GorAVSubtitles", "GorAVPlaybackCore"], path: "Sources/cue-output-tests"),
        .executableTarget(name: "render-graph-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/render-graph-tests"),
        .executableTarget(name: "decoder-lifetime-tests", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore"], path: "Sources/decoder-lifetime-tests"),
        .executableTarget(name: "decoder-inventory-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/decoder-inventory-tests"),
        .testTarget(name: "PreparedVideoSwapTests", dependencies: ["GorAVPlaybackCore"], path: "Tests/PreparedVideoSwapTests"),
        .testTarget(name: "EmbeddedPreparedShotTests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), "GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Tests/EmbeddedPreparedShotTests"),
        .executableTarget(name: "color-stage-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/color-stage-tests"),
        .executableTarget(name: "crop-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/crop-tests"),
        .executableTarget(name: "frame-tap-tests", dependencies: ["GorAVPlaybackCore", "GorAVNativeProbeKit"], path: "Sources/frame-tap-tests"),
        .executableTarget(name: "active-media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/active-media-inventory-tests"),
        .executableTarget(name: "media-inventory-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/media-inventory-tests"),
        .executableTarget(name: "video-remote-open-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/video-remote-open-tests"),
        .executableTarget(name: "remote-source-tests", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/remote-source-tests"),
        .executableTarget(name: "subtitle-controller-tests", dependencies: ["GorAVSubtitles"], path: "Sources/subtitle-tests", sources: ["SubtitleControllerTests.swift"]),
        .executableTarget(name: "prepared-shot-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/prepared-shot-tests"),
        .executableTarget(name: "hosttransform-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/hosttransform-tests"),
        .executableTarget(name: "timepos-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-tests"),
        .executableTarget(name: "timepos-vector-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/timepos-vector-tests"),
        .executableTarget(name: "controlbus-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/controlbus-tests"),
        .target(name: "BridgeDemux", path: "Tests/labs/p-a1-r2/Sources/BridgeDemux"),
        .target(name: "BridgeVTDecode", dependencies: ["BridgeDemux"], path: "Sources/BridgeVTDecode"),
        .target(name: "AudioMasterScheduler", path: "Sources/AudioMasterScheduler"),
        .testTarget(name: "EngineContractTests", dependencies: ["BridgeVTDecode", "BridgeDemux", "AudioMasterScheduler"], path: "Tests/EngineContractTests"),
        .executableTarget(name: "e1-headless-tests", dependencies: ["BridgeDemux", "AudioMasterScheduler", "CFFmpeg", "GorAVPlaybackCore", "GorAVMetalPresenter"], path: "Sources/e1-headless-tests"),
        .executableTarget(name: "gorav-probe", dependencies: ["GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/gorav-probe"),


        .target(name: "GorAVCore", dependencies: ["GorAVCAtomics"], path: "Sources/GorAVCore", sources: ["Boundary.swift", "AdmissionTable.swift", "OpenURLRouter.swift"]),
        // L5/L6 u7 wiring candidate (coordinator-owned landing): parser/model library +
        // three SEPARATE @main consumer suites (one file each, never one merged target).
        .target(name: "GorAVSubtitles", path: "Sources/GorAVSubtitles", sources: ["ASSParser.swift", "SRTParser.swift", "VTTParser.swift", "SubtitleCue.swift", "SubtitlePlan.swift", "SubtitleSchedule.swift", "SubtitleTrack.swift", "SubtitleAutoLoad.swift", "SubtitleController.swift", "SubtitleCueOutput.swift", "SubtitleCueDelivery.swift", "SubtitleSidecarSession.swift"]),
        .executableTarget(name: "vtt-parser-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/vtt-parser-tests"),
        .executableTarget(name: "avsync-golden-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/avsync-golden-tests"),
        .executableTarget(name: "transport-vector-tests", path: "Sources/transport-vector-tests"),
        .executableTarget(name: "parity-pixel-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                          path: "Sources/parity-pixel-tests"),
        .executableTarget(name: "untagged-color-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/untagged-color-tests"),
        .executableTarget(name: "l3-convert-matrix-tests", dependencies: ["GorAVFFmpegAdapter"],
                          path: "Sources/l3-convert-matrix-tests",
                          swiftSettings: [.define("L3_PROVIDER")]),
        .executableTarget(name: "subtitle-srt-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SRTTests.swift"]),
        .executableTarget(name: "subtitle-ass-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["ASSTests.swift"]),
        .executableTarget(name: "subtitle-track-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitleTrackTests.swift"]),
        .executableTarget(name: "subtitle-plan-tests", dependencies: ["GorAVSubtitles"],
                          path: "Sources/subtitle-tests", sources: ["SubtitlePlanTests.swift"]),
        .target(name: "GorAVNativeProbeKit", dependencies: ["GorAVCore"],
                path: "Sources/GorAVNativeProbeKit",
                sources: ["GorAVSeekContract.swift", "NativeProbe.swift", "LeaseTable.swift", "PacketFeedMachine.swift", "DemuxerPolicy.swift"]),
        .systemLibrary(name: "CFFmpeg", path: "Sources/CFFmpeg"),
        // L6 Dolby Vision lane (block 78d L6; new lane dirs only, milestone-gated M4)
        .target(name: "GorAVDVRPU",
                path: "Sources/GorAVDVRPU",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVDolbyVision",
                dependencies: ["GorAVDVRPU", "CFFmpeg", "GorAVCore",
                               "GorAVFFmpegAdapter"],
                path: "Sources/GorAVDolbyVision"),
        .executableTarget(name: "dovi-selftest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-selftest",
                exclude: ["swift"]),
        .executableTarget(name: "dovi-hdrtest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-hdrtest",
                exclude: ["gen_ref_fields.py"]),
        .executableTarget(name: "dovi-vectest",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-vectest"),
        .executableTarget(name: "dovi-fuzz",
                dependencies: ["GorAVDVRPU"],
                path: "Sources/dovi-fuzz"),
        .target(name: "GorAVFFmpegAdapter", dependencies: ["CFFmpeg", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/GorAVFFmpegAdapter", sources: ["FFmpegSoftwareDecoder.swift", "SnapshotInput.swift", "SnapshotAVIOOwner.swift", "FrameObservation.swift", "FFmpegSoftwareAudioDecoder.swift", "L3Admission.swift", "L3SampleConvert.swift", "L3PixelConvert.swift", "L3HardwareDecode.swift", "L3AVCoordinator.swift", "SourceOpenOptions.swift", "MediaInventory.swift", "ActiveTransportSnapshot.swift"]),        .executableTarget(name: "l4-hwdecode-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "CFFmpeg"],
                path: "Sources/l4-hwdecode-tests", sources: ["L4HWDecodeTests.swift"]),

        .executableTarget(name: "gorav-first-frame", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/gorav-first-frame", sources: ["FirstFrame.swift"]),
        .executableTarget(name: "refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/refusal-tests", sources: ["RefusalTests.swift"]),
        .executableTarget(name: "playback-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/playback-test", sources: ["PlaybackTest.swift"]),
        .executableTarget(name: "audio-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/audio-test", sources: ["AudioTest.swift"]),
        .executableTarget(name: "seek-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-test", sources: ["SeekTest.swift"]),
        .executableTarget(name: "e1-shapes-tests", dependencies: [.target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS])), .target(name: "GorAVMetalPresenter", condition: .when(platforms: [.macOS])), .target(name: "GorAVPlaybackCore", condition: .when(platforms: [.macOS]))], path: "Sources/e1-shapes-tests"),
        .executableTarget(name: "seek-restart-probe", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/seek-restart-probe", sources: ["main.swift"]),
        .executableTarget(name: "audio-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/audio-refusal-tests", sources: ["AudioRefusalTests.swift"]),
        .executableTarget(name: "video-refusal-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/video-refusal-tests", sources: ["VideoRefusalTests.swift"]),
        .executableTarget(name: "coexist-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/coexist-test", sources: ["CoexistTest.swift"]),
        .executableTarget(name: "isolation-test", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/isolation-test", sources: ["IsolationTest.swift"]),
        .executableTarget(name: "trace-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"],
                path: "Sources/trace-dump", sources: ["TraceDump.swift"]),
        .executableTarget(name: "core-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/core-seek-tests"),
        .executableTarget(name: "real-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/real-seek-tests"),
        .executableTarget(name: "seek-ring-reset-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-ring-reset-tests"),
        .target(name: "GorAVSeekComposition", dependencies: ["GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVSeekComposition"),
        .executableTarget(name: "seek-pacing-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/seek-pacing-tests"),
        .executableTarget(name: "seek-composition-tests", dependencies: ["GorAVSeekComposition", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/seek-composition-tests"),
        .executableTarget(name: "audio-seek-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-seek-tests"),
        .executableTarget(name: "demux-parity-tests", dependencies: ["BridgeDemux", "CFFmpeg"], path: "Sources/demux-parity-tests"),
        .executableTarget(name: "audio-baseline-tests", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/audio-baseline-tests"),
        .executableTarget(name: "seek-contract-tests", dependencies: ["GorAVNativeProbeKit", "GorAVCore", "GorAVFFmpegAdapter"], path: "Sources/seek-contract-tests"),
        .executableTarget(name: "adversarial-seek-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/adversarial-seek-tests"),
        .executableTarget(name: "shell-seek-bridge-tests", dependencies: ["GorAVPlaybackCore", "GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"], path: "Sources/shell-seek-bridge-tests"),
        .executableTarget(name: "k9-adversarial", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/k9-adversarial", sources: ["K9Adversarial.swift"]),
        .executableTarget(name: "shell-mac-test", dependencies: ["GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/shell-mac-test", sources: ["ShellMacTest.swift"]),
        .executableTarget(name: "frame-dump", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVNativeProbeKit", "GorAVPlaybackCore"],
                path: "Sources/frame-dump", sources: ["FrameDump.swift", "ConverterVariants.swift", "RawPlaneDump.swift"]),
        .target(name: "GorAVCAtomics", path: "Sources/GorAVCAtomics", publicHeadersPath: "."),
        .target(name: "GorAVAudioClock",
                path: "Sources/GorAVAudioClock",
                sources: ["src"],
                publicHeadersPath: "include"),
        .target(name: "GorAVAudioClockSwift",
                dependencies: ["GorAVAudioClock", "GorAVCAtomics", "GorAVPlaybackCore"],
                path: "Sources/GorAVAudioClockSwift"),
        // r3 (architect r2 BLOCKER): NO explicit sources list - an explicit
        // list silently omitted Lane0Contract.swift + LifetimeRegistry.swift
        // (AudioSink/AudioStopResult/PlaybackRegistry unresolved in a real
        // package build; manual swiftc had masked it). Default = every file.
        .target(name: "GorAVPlaybackCore", dependencies: ["GorAVCAtomics", "GorAVCore", "GorAVNativeProbeKit"], path: "Sources/GorAVPlaybackCore"),
        .executableTarget(name: "session-venue-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/session-venue-tests"),
        // native87 Stage B entrypoint (B1-B3): pause-hold counter witnesses,
        // parked seek, close-from-paused report on the REAL embedded session.
        // macOS legs only; UNRUN (exit 77) elsewhere.
        .executableTarget(name: "b-gate-tests",
                          dependencies: ["GorAVPlaybackCore", .target(name: "GorAVEmbeddedShell", condition: .when(platforms: [.macOS]))],
                          path: "Sources/b-gate-tests"),
        .testTarget(name: "GorAVAudioClockTests",
                    dependencies: ["GorAVAudioClockSwift"],
                    path: "Tests/GorAVAudioClockTests"),
        .testTarget(name: "ReadinessAnchorTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/ReadinessAnchorTests"),
        .testTarget(name: "AudioPacingTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/AudioPacingTests"),
        .testTarget(name: "J3AudioControlTests",
                    dependencies: ["GorAVAudioClockSwift", "GorAVPlaybackCore"],
                    path: "Tests/J3AudioControlTests"),
        .testTarget(name: "DecodeHeartbeatTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/DecodeHeartbeatTests"),
        .testTarget(name: "PlayerControlPlaneTests",
                    dependencies: ["GorAVPlaybackCore"],
                    path: "Tests/PlayerControlPlaneTests"),
        .executableTarget(name: "pause-resume-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/pause-resume-tests"),
        .executableTarget(name: "race-witness-tests", dependencies: ["GorAVPlaybackCore"],
                          path: "Sources/race-witness-tests"),
        .executableTarget(name: "admission-tests", dependencies: ["GorAVCore", "GorAVNativeProbeKit", "GorAVFFmpegAdapter"],
                          path: "Sources/admission-tests"),
        .executableTarget(name: "open-url-tests", dependencies: ["GorAVCore"], path: "Sources/open-url-tests"),
        .executableTarget(name: "audio-delay-tests", dependencies: ["GorAVPlaybackCore", "GorAVAudioClockSwift"], path: "Sources/audio-delay-tests"),
        .executableTarget(name: "window-mode-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/window-mode-tests"),
        .executableTarget(name: "observation-tests", dependencies: ["GorAVPlaybackCore"], path: "Sources/observation-tests"),
        .executableTarget(name: "timing-ledger-tests", dependencies: ["GorAVPlaybackCore"],
                path: "Sources/timing-ledger-tests", sources: ["TimingLedgerTests.swift", "SPSCTests.swift"]),
        .executableTarget(name: "gorav-sink-check", dependencies: ["GorAVMacShell"], path: "Sources/gorav-sink-check", sources: ["SinkCheck.swift"]),
        .executableTarget(name: "gorav-play", dependencies: ["GorAVMacShell", "GorAVMetalPresenter", "GorAVPlaybackCore"], path: "Sources/gorav-play", sources: ["GorAVPlay.swift"]),
        // L7 embedded shell (block 168 factory gap): the E1 host-NSView embed
        // session. Whole body is canImport(AppKit)-gated - compiles empty
        // off-Mac; a Linux build is NOT a Mac compile claim. Explicit
        // sources pin: exactly the reviewed session file; a stray file
        // dropped into the dir is uncompiled, never silently wired.
        .target(name: "GorAVEmbeddedShell",
                dependencies: ["GorAVSubtitles", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVMacShell", "GorAVMetalPresenter", "GorAVFFmpegAdapter", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVEmbeddedShell", sources: ["GorAVEmbeddedSession.swift"]),
        .target(name: "GorAVMacShell", dependencies: ["GorAVFFmpegAdapter", "GorAVCore", "GorAVPlaybackCore", "GorAVNativeProbeKit", "GorAVSeekComposition", "GorAVAudioClockSwift"],
                path: "Sources/GorAVMacShell", sources: ["ShellClock.swift", "DisplaySink.swift", "AudioUnitSink.swift", "ShellFrameSource.swift", "FrameTap.swift", "TappedFrameLuma.swift", "WindowModeController.swift"]),
        // L2 Metal presenter lane, r7 landing (block 168 L3): new target dir
        // only; every Metal/AppKit source is canImport-gated so off-Mac
        // builds compile the target empty. GorAVMetalShellApp mirrors the
        // trunk shell contract (owner-issued session, shared CancelCommit,
        // audio-master pacing).
        .target(name: "GorAVMetalPresenter",
                dependencies: ["GorAVMacShell", "GorAVPlaybackCore", "GorAVFFmpegAdapter", "GorAVCore", "GorAVSubtitles"],
                path: "Sources/GorAVMetalPresenter/core",
                sources: ["AspectFit.swift", "MetalPresenterTelemetry.swift", "SurfaceContract.swift", "MetalRenderer.swift", "MetalPresenter.swift", "GorAVMetalShellApp.swift", "StagePass.swift", "CVPixelBufferTap.swift"]),
        .executableTarget(name: "gorav-metal-check", dependencies: ["GorAVMetalPresenter", "GorAVMacShell", "GorAVPlaybackCore"],
                path: "Sources/GorAVMetalPresenter/cli", sources: ["MetalCheck.swift"])
    ]
)

```

```swift id=fx_owner_patch
import Foundation

/// Retained-byte owner for the frame-lease path: the decoder frame producer
/// adopts bytes before offering a lease; the lease store's onRelease hook
/// frees them exactly once. Foundation only; calls no GorAV API.
public final class RetainedPixelOwner: @unchecked Sendable {
    private let lock = NSLock()
    public let session: UInt64
    private var live: [UInt64: [UInt8]] = [:]
    private var released: [UInt64] = []
    private var abandoned: [UInt64] = []
    private var unknown = 0
    private var doubles = 0
    private var adopted = 0

    public init(session: UInt64) { self.session = session }

    public func adopt(handle: UInt64, bytes: [UInt8]) {
        lock.lock(); defer { lock.unlock() }
        live[handle] = bytes
        adopted += 1
    }

    public func abandon(handle: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if live.removeValue(forKey: handle) != nil { abandoned.append(handle) }
    }

    /// Exactly the onRelease parameter type of FrameLeaseStore.init. The store
    /// fires it once per retained lease, without its lock held; the owner must
    /// never call back into the store.
    public var releaseHook: (UInt64, UInt64) -> Void {
        return { [self] handle, _ in
            self.lock.lock(); defer { self.lock.unlock() }
            if self.live.removeValue(forKey: handle) != nil {
                self.released.append(handle)
            } else if self.released.contains(handle) || self.abandoned.contains(handle) {
                self.doubles += 1
            } else {
                self.unknown += 1
            }
        }
    }

    public func firstByte(handle: UInt64) -> UInt8? {
        lock.lock(); defer { lock.unlock() }
        return live[handle]?.first
    }

    public var liveHandles: [UInt64] { lock.lock(); defer { lock.unlock() }; return live.keys.sorted() }
    public var releasedHandles: [UInt64] { lock.lock(); defer { lock.unlock() }; return released.sorted() }
    public var abandonedHandles: [UInt64] { lock.lock(); defer { lock.unlock() }; return abandoned.sorted() }
    public var liveBytes: Int { lock.lock(); defer { lock.unlock() }; return live.values.reduce(0) { $0 + $1.count } }
    public var unknownReleases: Int { lock.lock(); defer { lock.unlock() }; return unknown }
    public var doubleReleases: Int { lock.lock(); defer { lock.unlock() }; return doubles }
    public var adoptedCount: Int { lock.lock(); defer { lock.unlock() }; return adopted }
}

```
