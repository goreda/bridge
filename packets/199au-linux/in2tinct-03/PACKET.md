# W-gdb-199au-in2tinct-03 - CachePolicyConsumption carries cachePause and cacheOnDisk through the consumption seam
state: OPEN / unclaimed
lab: in2tinct
row: GORAV-CACHE-PARITY (A2)

Patch + tests authored by gdb (Ops, leg A) under arch-199au item 6; in2tinct verifies and ingests per the leg/lab rules. Real production change plus semantic Linux tests, both executed against the pin before publication (run proof below). Support-only: no native/UI/playback/Darwin claims, no gorav main ref change, no paid CI; integration lands on the target lane branch only after lab verification and integrator review.

PROBLEM. CacheConsumption dropped cachePause and cacheOnDisk at the seam: once wired, the open site could never honor cache-pause=no (gor's torrent PARAMS application) or cache-on-disk=yes (gor's pixeldrain override) - the values existed on the registered policy and were silently lost in projection.

DECISION. Add both fields to CacheConsumption and project them in resolve(). An explicit init with launch-baseline defaults keeps pre-existing five-argument call sites compiling (documented as compatibility only; resolve() always projects the real policy). Packet pinned against the UNMODIFIED CacheTuningPolicy at the pin (W-gdb-199au-in2tinct-01's clamp is an independent, additive change).

Scope boundaries: this packet touches only the listed files. It does not touch the returned/conflicting paths ABLoopPolicy.swift, SubtitleSelectionPolicy.swift, ASSParser.swift or the CacheAccounting.swift chain, and does not re-open their rows. No generic tooling, no label-only work, no fabricated evidence: every check below ran on this exact patch against the exact pin.

Repo goreda/gorav main pin 087c15cc068daf1e74112d436e63f07b3d254be4. Test toolchain: official Swift 6.2.3 (ubuntu22.04) on PATH, -swift-version 6 strict concurrency. Return full files on target branch lane/199au/cache-policy-consumption-knobs; the patch against the pin is derivable from the inline sources. Keep .build out of git.

```packet-json
{
  "packet_id": "W-gdb-199au-in2tinct-03",
  "lab": "in2tinct",
  "writer": "gdb",
  "code_owner": "gdb (Ops leg A) authored the patch and tests; goreda owns the gorav trunk integration decision; in2tinct verifies and ingests the listed files only",
  "product_repo": "goreda/gorav",
  "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "CacheConsumption(kind:capacityBytes:cacheSecs:readaheadSecs:pauseInitial:cachePause:cacheOnDisk:) (two new fields, defaulted); CachePolicyConsumption.resolve(route:table:) projection extended",
    "types": "CacheConsumption, CacheSeamRoute, CacheSeamError, CachePolicyConsumption (additive)",
    "ownership_lifetime": "Owned production path Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift only; CacheTuningPolicy.swift is a pinned dependency, not modified.",
    "caller": "Decoder-open seam model (FFmpegSoftwareDecoder.swift:768 / FFmpegSoftwareAudioDecoder.swift:334); no wiring in this packet.",
    "callee": "CacheTuningPolicyTable.policy(for:) typed lookup (unchanged)."
  },
  "scope": "product",
  "test": {
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au03 Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift kits/199au/in2tinct-03/main.swift && /tmp/wgdb199au03",
    "expected": "exit 0; log ends 'SEMANTIC_PASS W-gdb-199au-in2tinct-03 11 checks'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/199au/cache-policy-consumption-knobs",
    "paths": [
      "Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift",
      "Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift",
      "kits/199au/in2tinct-03/main.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift",
        "block": "source0"
      },
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift",
        "block": "source1"
      },
      {
        "path": "kits/199au/in2tinct-03/main.swift",
        "block": "fixtures1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au03 Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift kits/199au/in2tinct-03/main.swift && /tmp/wgdb199au03",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-20T20:39:43.715830+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "SEMANTIC_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift",
        "block": "source0",
        "sha256": "57e275faf5826483c65c6653bb188654c11c573c5d70c3b04e9bb0598125618f"
      },
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift",
        "block": "source1",
        "sha256": "8ca53ae15b804f7635816ac6988bd62b6428a3f40bba2c3a1bb2f60c65465a6c"
      },
      {
        "path": "kits/199au/in2tinct-03/main.swift",
        "block": "fixtures1",
        "sha256": "e9bd6f27e34b1227617b4c968e52303ed4705e2b8364bdfa264abc5728fa014b"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "171a7927219f81b955ec7206710d5542ecb1a852854a04806529c4f75c2520c3",
    "last_5_lines": [
      "PASS R1 not-yet-openable route refuses typed",
      "PASS R2 missing policy refuses typed with the kind",
      "PASS S1 five-argument init still compiles with launch defaults",
      "PASS S2 seeded localFile resolve equals the compat expectation shape",
      "SEMANTIC_PASS W-gdb-199au-in2tinct-03 11 checks"
    ],
    "receipt_sha256": "0d560c757fbdbda98db3d0f4d7c407dac8c38b3f302fa2594ec48d994db7a19c"
  }
}
```

```swift id=source0
// CacheParity: immutable per-source cache tuning policy (SUPPORT only).
// Row: GORAV-CACHE-PARITY (lane/cache-parity-20261119, base main c1431906).
// Parity baseline is gor's pinned mpv cache surface (docs/LEDGER.tsv @ gor
// 56181f76): launch --cache=yes --cache-secs=8 --cache-pause-initial=no
// (AppDelegate.swift:1266-1268); the runtime knobs cache, cache-on-disk,
// cache-pause and cache-pause-wait are set per source by gor's TorrentManager
// and MenuActions. This module decides nothing at runtime: it holds one
// immutable CacheTuningPolicy per CacheSourceKind, registered once and read
// many times. No I/O, no eviction, no player/ffmpeg/live cache wiring, no
// edit of the lab-merged CacheAccounting; the policy's forwardCapacityBytes
// is the intended feed for CacheAccounting.capacity. Darwin/Linux portable.
//
// Provenance classes, kept explicit:
//  - GOR-PINNED: values read from the pinned LEDGER rows above.
//  - MPV-DEFAULT: values gor does not set at launch, so mpv's default applies
//    (pending gor-source readback of the per-source runtime sites).
//  - PROVISIONAL: module placeholders pending evidence; never a parity claim.
//
// 2026-11-19 flip: the mangled "ln"/128M LEDGER launch row is resolved from
// in-repo bytes. Historical gorav commit f7ebdf56 (170e byte-identical
// transfer of the l8 lane from goreda/instinct 440dbbfa) carries
// archive/gor/Sources/gor/AppDelegate.swift:959-964 as the literal mpv
// launch array: --cache=yes --cache-secs=8 --cache-pause-initial=no
// --demuxer-max-bytes=128M --demuxer-max-back-bytes=32M
// --demuxer-readahead-secs=10. The first three match the LEDGER's gor@56181f76
// pins exactly (line numbers differ across the snapshots: 1266-1268 there,
// 959-961 here; same relative cluster order), so the 128M row at 56181f76:1269
// is --demuxer-max-bytes, and the back-bytes/readahead pins come from the same
// cluster. forwardCapacityBytes, backCapacityBytes and readaheadSecs are now
// GOR-PINNED, not PROVISIONAL.
//
// Concurrency scope: policies are immutable values; the table is the only
// shared state and serializes every access through NSLock, so a policy read
// on any thread (decode, UI, stats) is race-free. Strict Swift 6
// complete-concurrency clean with ONE explicit @unchecked Sendable waiver on
// the table, stated at the type. NSLock predates macOS 13; no macOS-15-only
// symbols (no Synchronization.Mutex) - deployment floor preserved.
import Foundation

/// Typed refusals for table operations. Value validation uses a failable
/// initializer, matching the module's existing validated-value style.
public enum CacheTuningPolicyError: Error, Equatable {
    /// A source kind that already has a policy: policies are immutable once
    /// registered, so a second registration is refused and the first stands.
    case duplicateRegistration(CacheSourceKind)
    /// Lookup for a kind with no registered policy: seed the gor-parity
    /// baseline or register an explicit policy first. Fail-closed: no silent
    /// default is ever invented at read time.
    case unknownSource(CacheSourceKind)
}

/// The source classes gor tunes cache for today, mapped to gorav's existing
/// source types. No identifier rules are re-implemented here.
public enum CacheSourceKind: String, CaseIterable, Sendable {
    /// Local file playback (SnapshotInput family).
    case localFile
    /// Direct http(s) and yt-dlp-resolved streams (YtdlpProcessSource).
    case networkStream
    /// HLS video-on-demand (HLSVODSource).
    case hlsVOD
    /// archive.org item sources (ArchiveItemSource).
    case archiveItem
    /// Torrent-backed sources; gor's TorrentManager carries the distinct
    /// runtime cache tuning for this class.
    case torrentRelay
}

/// One source kind's cache tuning. Immutable after construction: every field
/// is a let, the struct is a value type, and the table hands out copies.
public struct CacheTuningPolicy: Equatable, Sendable {
    /// mpv cache (GOR-PINNED launch: yes).
    public let cacheEnabled: Bool
    /// mpv cache-secs (GOR-PINNED launch: 8).
    public let cacheSecs: Double
    /// mpv cache-pause-initial (GOR-PINNED launch: no).
    public let cachePauseInitial: Bool
    /// mpv cache-pause (MPV-DEFAULT: true; gor overrides per source at
    /// runtime, values pending gor-source readback).
    public let cachePause: Bool
    /// mpv cache-pause-wait (MPV-DEFAULT pending readback).
    public let cachePauseWaitSecs: Double
    /// mpv cache-on-disk (MPV-DEFAULT: no; gor sets it at runtime sites,
    /// values pending gor-source readback).
    public let cacheOnDisk: Bool
    /// Forward cache window in bytes; the intended feed for
    /// CacheAccounting.capacity (GOR-PINNED --demuxer-max-bytes=128M;
    /// resolved from the mangled "ln" LEDGER row, see header).
    public let forwardCapacityBytes: UInt64
    /// Backward cache window in bytes, never larger than the forward window
    /// (GOR-PINNED --demuxer-max-back-bytes=32M, same cluster).
    public let backCapacityBytes: UInt64
    /// Readahead target in seconds (GOR-PINNED --demuxer-readahead-secs=10,
    /// same cluster).
    public let readaheadSecs: Double

    /// Validated construction; nil on any violated invariant. Checked rules:
    /// every second field finite and non-negative; backward window never
    /// exceeds the forward window; an enabled cache requires a positive
    /// forward capacity (a disabled cache may carry zero capacities).
    public init?(cacheEnabled: Bool,
                 cacheSecs: Double,
                 cachePauseInitial: Bool,
                 cachePause: Bool,
                 cachePauseWaitSecs: Double,
                 cacheOnDisk: Bool,
                 forwardCapacityBytes: UInt64,
                 backCapacityBytes: UInt64,
                 readaheadSecs: Double) {
        guard cacheSecs.isFinite, cacheSecs >= 0,
              cachePauseWaitSecs.isFinite, cachePauseWaitSecs >= 0,
              readaheadSecs.isFinite, readaheadSecs >= 0 else { return nil }
        guard backCapacityBytes <= forwardCapacityBytes else { return nil }
        guard !cacheEnabled || forwardCapacityBytes > 0 else { return nil }
        self.cacheEnabled = cacheEnabled
        self.cacheSecs = cacheSecs
        self.cachePauseInitial = cachePauseInitial
        self.cachePause = cachePause
        self.cachePauseWaitSecs = cachePauseWaitSecs
        self.cacheOnDisk = cacheOnDisk
        self.forwardCapacityBytes = forwardCapacityBytes
        self.backCapacityBytes = backCapacityBytes
        self.readaheadSecs = readaheadSecs
    }

    /// gor's pinned launch cache surface as one baseline value. This is the
    /// LAUNCH layer only (restoreDefaultProfile in gor resets to this);
    /// per-source pins layer on top in gorParityBaseline(for:).
    public static func gorParityBaseline() -> CacheTuningPolicy {
        CacheTuningPolicy(cacheEnabled: true,          // GOR-PINNED --cache=yes
                          cacheSecs: 8,                // GOR-PINNED --cache-secs=8
                          cachePauseInitial: false,    // GOR-PINNED --cache-pause-initial=no
                          cachePause: true,            // MPV-DEFAULT
                          cachePauseWaitSecs: 0,       // MPV-DEFAULT pending readback
                          cacheOnDisk: false,          // MPV-DEFAULT
                          forwardCapacityBytes: 128 * 1024 * 1024, // GOR-PINNED --demuxer-max-bytes=128M
                          backCapacityBytes: 32 * 1024 * 1024,     // GOR-PINNED --demuxer-max-back-bytes=32M
                          readaheadSecs: 10)!                      // GOR-PINNED --demuxer-readahead-secs=10
    }

    /// gor's per-source cache tuning by kind. Evidence: gorav historical
    /// commit f7ebdf56 tree archive/gor/Sources/gor/MenuActions.swift
    /// :1010-1071 (playMedia): every load first restores the launch profile
    /// ("Per-file baseline first (pass-5 #7), then branch overrides"), then
    /// branches apply set_property / per-file loadfile overrides.
    ///  - archiveItem: isArchive branch (https archive.org / *.us.archive.org)
    ///    per-file loadfile options pinned at :1056-1069.
    ///  - networkStream: the non-torrent non-pixeldrain else branch
    ///    (:1036-1040): launch + cache-secs=30, demuxer-max-bytes=500M,
    ///    demuxer-readahead-secs=120.
    ///  - localFile: TYPED FACT (was a gap), proven from code 2026-11-19:
    ///    no per-source cache option exists on any cited local open path.
    ///    gor side (f7ebdf56 tree): the local selection path in
    ///    MenuActions.openFile (:721-776) applies no cache set_property -
    ///    its only cache writes live in playMedia's network branches - and
    ///    openMediaFile's body sits in PPController, NOT in the transferred
    ///    trees (residual gap, stated honestly). gorav side (c1431906):
    ///    FFmpegSoftwareDecoder.swift:767-770 / FFmpegSoftwareAudioDecoder
    ///    .swift:305,326 give local opens remoteOptions=nil, and no cache
    ///    AVOption exists anywhere in Sources/GorAVFFmpegAdapter. So the
    ///    launch baseline stands, as a fact with citations, not a guess.
    ///  - hlsVOD: launch baseline at the DECODE open (prepared segments are
    ///    local files); HLS's per-source cache substance is pinned at
    ///    prepare time in HLSCacheBudget.goravPinned (see that file).
    ///  - torrentRelay: cache/demuxer owned by TorrentManager's PARAMS
    ///    application (:1017-1020 comment). RESOLVED 2026-11-19 from the
    ///    current composition TorrentManager.swift (git blob 5db095ce,
    ///    source 94ee671d, :469-508): the values are DATA-DRIVEN per torrent
    ///    via PARAMS JSON (demuxerMaxBytes Int bytes, cacheSecs Int), so no
    ///    fixed numeric baseline exists; the launch baseline stands here and
    ///    per-session policies are built by gorParityTorrentRelay(...).
    ///    Fixed pins from the PARAMS application: cache=yes,
    ///    cache-pause-initial=yes, demuxer-readahead-secs = cacheSecs,
    ///    demuxer-max-bytes = demuxerMaxBytes, cache-pause=no.
    /// pixeldrain.com's host-scoped override (:1024-1035) is not a kind; see
    /// gorParityPixeldrainOverride().
    public static func gorParityBaseline(for kind: CacheSourceKind) -> CacheTuningPolicy {
        let launch = gorParityBaseline()
        switch kind {
        case .archiveItem:
            return CacheTuningPolicy(cacheEnabled: true,          // per-file cache=yes
                                     cacheSecs: 120,              // per-file cache-secs=120
                                     cachePauseInitial: false,    // per-file cache-pause-initial=no
                                     cachePause: true,            // MPV-DEFAULT (untouched by branch)
                                     cachePauseWaitSecs: 1,       // per-file cache-pause-wait=1
                                     cacheOnDisk: false,          // per-file cache-on-disk=no
                                     forwardCapacityBytes: 256 * 1024 * 1024, // demuxer-max-bytes=256MiB
                                     backCapacityBytes: 128 * 1024 * 1024,    // demuxer-max-back-bytes=128MiB
                                     readaheadSecs: 120)!         // demuxer-readahead-secs=120
        case .networkStream:
            return CacheTuningPolicy(cacheEnabled: launch.cacheEnabled,
                                     cacheSecs: 30,               // else branch cache-secs=30
                                     cachePauseInitial: launch.cachePauseInitial,
                                     cachePause: launch.cachePause,
                                     cachePauseWaitSecs: launch.cachePauseWaitSecs,
                                     cacheOnDisk: launch.cacheOnDisk,
                                     forwardCapacityBytes: 500 * 1024 * 1024, // demuxer-max-bytes=500M
                                     backCapacityBytes: launch.backCapacityBytes, // launch 32M stands
                                     readaheadSecs: 120)!         // demuxer-readahead-secs=120
        case .localFile, .hlsVOD, .torrentRelay:
            return launch // typed gaps, see doc above
        }
    }

    /// gor's torrent-relay tuning, applied per torrent session from the
    /// wt_server PARAMS line. Evidence: current composition TorrentManager.swift
    /// (git blob 5db095ce, source 94ee671d) :469-508 - PARAMS JSON carries
    /// demuxerMaxBytes (Int, bytes) and cacheSecs (Int); the application sets
    /// cache=yes, cache-secs=cacheSecs, cache-pause-initial=yes,
    /// demuxer-readahead-secs=cacheSecs, demuxer-max-bytes=demuxerMaxBytes
    /// (emitted as M), cache-pause=no. cache-on-disk and cache-pause-wait are
    /// untouched there (launch/mpv defaults stand); demuxer-max-back-bytes is
    /// untouched, so the launch 32M stands. One-shot registration means the
    /// first torrent session's policy stands for the table's lifetime; a
    /// per-session table is future wiring, noted as a typed limitation.
    public static func gorParityTorrentRelay(demuxerMaxBytes: UInt64, cacheSecs: Double) -> CacheTuningPolicy? {
        let launch = gorParityBaseline()
        return CacheTuningPolicy(cacheEnabled: true,          // PARAMS: cache=yes
                                 cacheSecs: cacheSecs,        // PARAMS: cache-secs
                                 cachePauseInitial: true,     // PARAMS: cache-pause-initial=yes
                                 cachePause: false,           // PARAMS: cache-pause=no
                                 cachePauseWaitSecs: launch.cachePauseWaitSecs, // untouched
                                 cacheOnDisk: launch.cacheOnDisk,               // untouched
                                 forwardCapacityBytes: demuxerMaxBytes,         // PARAMS: demuxer-max-bytes
                                 backCapacityBytes: launch.backCapacityBytes,   // launch 32M stands
                                 readaheadSecs: cacheSecs)   // PARAMS: readahead = cacheSecs
    }

    /// gor's host-scoped pixeldrain.com override (MenuActions.swift:1024-1035,
    /// same tree): launch profile plus these pins. Host granularity is finer
    /// than CacheSourceKind; a caller that knows the host registers this
    /// explicitly. Provenance: GOR-PINNED from the cited bytes.
    public static func gorParityPixeldrainOverride() -> CacheTuningPolicy {
        CacheTuningPolicy(cacheEnabled: true, cacheSecs: 3600, cachePauseInitial: true,
                          cachePause: true, cachePauseWaitSecs: 600, cacheOnDisk: true,
                          forwardCapacityBytes: 4096 * 1024 * 1024,
                          backCapacityBytes: 1024 * 1024 * 1024,
                          readaheadSecs: 3600)!
    }
}

/// NSLock-guarded table of immutable policies keyed by source kind. The
/// single @unchecked Sendable waiver, stated explicitly: mutual exclusion is
/// implemented manually with NSLock, so every access to the protected
/// dictionary is serialized by construction; every value handed out is an
/// immutable copy. Registration is one-shot per kind: the first registration
/// stands and later attempts are refused with .duplicateRegistration, which
/// keeps a registered policy immutable for the table's lifetime.
public final class CacheTuningPolicyTable: @unchecked Sendable {
    private let lock = NSLock()
    private var policies: [CacheSourceKind: CacheTuningPolicy] = [:]

    public init() {}

    /// A table pre-seeded with gor's per-source parity baseline for every
    /// kind (gorParityBaseline(for:)); kinds without per-source pins hold the
    /// launch baseline.
    public static func seedingWithGorParity() -> CacheTuningPolicyTable {
        let table = CacheTuningPolicyTable()
        for kind in CacheSourceKind.allCases {
            // Fresh table: registration cannot fail.
            try? table.register(policy: CacheTuningPolicy.gorParityBaseline(for: kind), for: kind)
        }
        return table
    }

    /// One-shot registration. Refuses a kind that already has a policy; a
    /// refused registration changes nothing.
    public func register(policy: CacheTuningPolicy, for kind: CacheSourceKind) throws {
        lock.lock()
        defer { lock.unlock() }
        guard policies[kind] == nil else {
            throw CacheTuningPolicyError.duplicateRegistration(kind)
        }
        policies[kind] = policy
    }

    /// Locked read of the immutable policy for a source kind. Fail-closed:
    /// an unregistered kind is a typed refusal, never an invented default.
    public func policy(for kind: CacheSourceKind) throws -> CacheTuningPolicy {
        lock.lock()
        defer { lock.unlock() }
        guard let policy = policies[kind] else {
            throw CacheTuningPolicyError.unknownSource(kind)
        }
        return policy
    }

    /// The kinds currently holding a policy, in stable declaration order.
    public var registeredKinds: [CacheSourceKind] {
        lock.lock()
        defer { lock.unlock() }
        return CacheSourceKind.allCases.filter { policies[$0] != nil }
    }
}
```

```swift id=source1
// CachePolicyConsumption: pure consumption seam for the per-source cache
// tuning policy (GORAV-CACHE-PARITY row). No I/O, no module coupling: the
// router decision shape is mirrored, not imported, so the seam stays
// testable in isolation and the real call sites keep their own types.
//
// Consumption points identified from code (base c1431906):
//  - Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift:768
//    video open: remoteOpenOptions.validatedForOpen() - the per-open point
//    where this seam's resolved consumption would be applied for video.
//  - Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift:334
//    audio open: same shape for the audio path.
//  - Sources/GorAVCore/OpenURLRouter.swift:64 (route(_:), cases at :14-:22)
//    classification point where the source class - and therefore the
//    CacheSourceKind - is first known.
//  - Sources/GorAVPlaybackCore/HLSVODSource.swift:35 (prepare(...)) -
//    HLS VOD segment preparation, per-segment cache consumption.
//  - Sources/GorAVPlaybackCore/PlaybackCore.swift:207 (SourceSession) -
//    session scope where a CacheAccounting(capacity:) would be created per
//    opened source; CacheAccounting has NO consumer in Sources/ today
//    (typed gap: policy and accounting are both lab/new and unwired).
// This seam models the first site (:768): resolve the immutable policy for
// the routed source BEFORE open, in the same pre-open position as
// validatedForOpen, and hand the call site one immutable value.
import Foundation

/// Mirror of the router's decision shape (OpenURLRouter.swift:64) reduced to
/// the cache-relevant classes. Not an import: the seam stays pure and the
/// mapping here is the single documented translation point.
public enum CacheSeamRoute: Sendable, Equatable {
    /// Router: local file open.
    case localFile
    /// Router: admitted http(s) (AdmissionTable classes).
    case admittedHTTP
    /// HLS VOD playlist/segment (HLSVODSource.admitted/prepare, :20/:35).
    case hlsPlaylist
    /// Archive item (ArchiveItemSource.identifier boundary).
    case archiveItem
    /// Router: magnet/.torrent re-entering as admitted http(s) via the
    /// wt_server bridge; keeps gor's distinct TorrentManager tuning class.
    case torrentBridged
    /// Router: needsMegaResolver (:18) - not openable yet, no cache policy
    /// applies until the external resolve re-enters as admitted http(s).
    case needsExternalResolve
}

public enum CacheSeamError: Error, Equatable {
    /// Route is not openable yet (external resolve pending). Resolving a
    /// cache policy now would pin tuning to a source that does not exist.
    case notYetOpenable
    /// The policy table has no policy for the routed kind. Fail-closed:
    /// the open site gets a typed refusal, never an invented default.
    case noPolicy(CacheSourceKind)
}

/// The immutable values a call site applies at open time, resolved once and
/// held for the session. capacityBytes is the intended feed for
/// CacheAccounting(capacity:) at SourceSession creation.
public struct CacheConsumption: Equatable, Sendable {
    public let kind: CacheSourceKind
    public let capacityBytes: UInt64
    public let cacheSecs: Double
    public let readaheadSecs: Double
    public let pauseInitial: Bool
    /// 199au (W-gdb-199au-in2tinct-03): the two remaining applied knobs now
    /// cross the seam. Without them a wired consumer could never honor
    /// cache-pause=no (gor's torrent PARAMS application) or cache-on-disk=yes
    /// (gor's pixeldrain override): the values existed on the policy and were
    /// silently dropped here.
    public let cachePause: Bool
    public let cacheOnDisk: Bool

    /// The defaults exist ONLY for source compatibility with pre-199au call
    /// sites (they pin the launch-baseline values, which is what those
    /// expectations construct); resolve() always projects the registered
    /// policy's real fields and never uses the defaults.
    public init(kind: CacheSourceKind, capacityBytes: UInt64, cacheSecs: Double,
                readaheadSecs: Double, pauseInitial: Bool,
                cachePause: Bool = true, cacheOnDisk: Bool = false) {
        self.kind = kind
        self.capacityBytes = capacityBytes
        self.cacheSecs = cacheSecs
        self.readaheadSecs = readaheadSecs
        self.pauseInitial = pauseInitial
        self.cachePause = cachePause
        self.cacheOnDisk = cacheOnDisk
    }
}

public enum CachePolicyConsumption {
    /// Route classification to source kind; the only translation point.
    public static func kind(for route: CacheSeamRoute) throws -> CacheSourceKind {
        switch route {
        case .localFile: return .localFile
        case .admittedHTTP: return .networkStream
        case .hlsPlaylist: return .hlsVOD
        case .archiveItem: return .archiveItem
        case .torrentBridged: return .torrentRelay
        case .needsExternalResolve: throw CacheSeamError.notYetOpenable
        }
    }

    /// The seam the open site calls before open: route to kind to the
    /// registered immutable policy, projected to the consumption value.
    public static func resolve(route: CacheSeamRoute, table: CacheTuningPolicyTable) throws -> CacheConsumption {
        let kind = try kind(for: route)
        let policy: CacheTuningPolicy
        do {
            policy = try table.policy(for: kind)
        } catch CacheTuningPolicyError.unknownSource(let missing) {
            throw CacheSeamError.noPolicy(missing)
        }
        return CacheConsumption(kind: kind,
                                capacityBytes: policy.forwardCapacityBytes,
                                cacheSecs: policy.cacheSecs,
                                readaheadSecs: policy.readaheadSecs,
                                pauseInitial: policy.cachePauseInitial,
                                cachePause: policy.cachePause,
                                cacheOnDisk: policy.cacheOnDisk)
    }
}
```

```swift id=fixtures1
import Foundation

// W-gdb-199au-in2tinct-03 semantic tests for CachePolicyConsumption carrying
// cachePause / cacheOnDisk through the consumption seam. Compiles against the
// PATCHED production files (same module, no source-copy stage):
//   Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift
//   Sources/GorAVPlaybackCore/CacheParity/CachePolicyConsumption.swift
// Exit 0 only when every check passes.

var failures = 0
@MainActor func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " " + info))
    if !ok { failures += 1 }
}

let M: UInt64 = 1024 * 1024
let seeded = CacheTuningPolicyTable.seedingWithGorParity()

// P-series: the new fields cross the seam from the registered policy
do {
    let c = try CachePolicyConsumption.resolve(route: .admittedHTTP, table: seeded)
    check("P1 networkStream projects launch cachePause/cacheOnDisk",
          c.cachePause == true && c.cacheOnDisk == false)
    check("P2 existing fields unchanged",
          c.kind == .networkStream && c.capacityBytes == 500 * M
          && c.cacheSecs == 30 && c.readaheadSecs == 120 && !c.pauseInitial)
} catch { check("P1/P2 networkStream resolve", false, "\(error)") }

// T-series: a torrent session policy (PARAMS: cache-pause=no) survives the seam
do {
    let t = CacheTuningPolicyTable()
    let session = CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 256 * M, cacheSecs: 60)!
    try t.register(policy: session, for: .torrentRelay)
    let c = try CachePolicyConsumption.resolve(route: .torrentBridged, table: t)
    check("T1 torrent PARAMS cache-pause=no crosses the seam", c.cachePause == false)
    check("T2 torrent session capacity and readahead cross unchanged",
          c.capacityBytes == 256 * M && c.cacheSecs == 60 && c.readaheadSecs == 60 && c.pauseInitial)
} catch { check("T1/T2 torrent seam", false, "\(error)") }

// X-series: the pixeldrain override (cache-on-disk=yes) crosses the seam
do {
    let t = CacheTuningPolicyTable()
    try t.register(policy: CacheTuningPolicy.gorParityPixeldrainOverride(), for: .networkStream)
    let c = try CachePolicyConsumption.resolve(route: .admittedHTTP, table: t)
    check("X1 pixeldrain cache-on-disk=yes crosses the seam", c.cacheOnDisk == true)
    check("X2 pixeldrain pins intact through the seam",
          c.capacityBytes == 4096 * M && c.cacheSecs == 3600 && c.pauseInitial && c.cachePause)
} catch { check("X1/X2 pixeldrain seam", false, "\(error)") }

// K-series: every seeded kind resolves with its policy's own knobs
check("K1 all five kinds resolve through the seeded table", CacheSourceKind.allCases.allSatisfy { kind in
    guard let route: CacheSeamRoute = {
        switch kind {
        case .localFile: return .localFile
        case .networkStream: return .admittedHTTP
        case .hlsVOD: return .hlsPlaylist
        case .archiveItem: return .archiveItem
        case .torrentRelay: return .torrentBridged
        } }() as CacheSeamRoute?,
        let c = try? CachePolicyConsumption.resolve(route: route, table: seeded) else { return false }
    let p = CacheTuningPolicy.gorParityBaseline(for: kind)
    return c.cachePause == p.cachePause && c.cacheOnDisk == p.cacheOnDisk
        && c.capacityBytes == p.forwardCapacityBytes && c.pauseInitial == p.cachePauseInitial
})

// R-series: preserved refusals
check("R1 not-yet-openable route refuses typed",
      (try? CachePolicyConsumption.resolve(route: .needsExternalResolve, table: seeded)) == nil)
do {
    _ = try CachePolicyConsumption.resolve(route: .archiveItem, table: CacheTuningPolicyTable())
    check("R2 missing policy refuses typed", false, "no throw")
} catch CacheSeamError.noPolicy(let kind) {
    check("R2 missing policy refuses typed with the kind", kind == .archiveItem)
} catch { check("R2 missing policy refuses typed", false, "\(error)") }

// S-series: source-compat init defaults pin the launch-baseline values only
do {
    let compat = CacheConsumption(kind: .localFile, capacityBytes: 128 * M,
                                  cacheSecs: 8, readaheadSecs: 10, pauseInitial: false)
    check("S1 five-argument init still compiles with launch defaults",
          compat.cachePause == true && compat.cacheOnDisk == false)
    let resolved = try CachePolicyConsumption.resolve(route: .localFile, table: seeded)
    check("S2 seeded localFile resolve equals the compat expectation shape", resolved == compat)
} catch { check("S1/S2 compat", false, "\(error)") }

if failures == 0 {
    print("SEMANTIC_PASS W-gdb-199au-in2tinct-03 11 checks")
} else {
    print("SEMANTIC_FAIL W-gdb-199au-in2tinct-03 \(failures) failures")
    exit(1)
}
```

```text id=actual_run_log
PASS P1 networkStream projects launch cachePause/cacheOnDisk
PASS P2 existing fields unchanged
PASS T1 torrent PARAMS cache-pause=no crosses the seam
PASS T2 torrent session capacity and readahead cross unchanged
PASS X1 pixeldrain cache-on-disk=yes crosses the seam
PASS X2 pixeldrain pins intact through the seam
PASS K1 all five kinds resolve through the seeded table
PASS R1 not-yet-openable route refuses typed
PASS R2 missing policy refuses typed with the kind
PASS S1 five-argument init still compiles with launch defaults
PASS S2 seeded localFile resolve equals the compat expectation shape
SEMANTIC_PASS W-gdb-199au-in2tinct-03 11 checks
```
