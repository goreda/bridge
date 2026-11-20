# W-gdb-199au-in2tinct-01 - CacheTuningPolicy torrent relay back window clamps to the forward window (mpv mirror)
state: OPEN / unclaimed
lab: in2tinct
row: GORAV-CACHE-PARITY (A2)

Patch + tests authored by gdb (Ops, leg A) under arch-199au item 6; in2tinct verifies and ingests per the leg/lab rules. Real production change plus semantic Linux tests, both executed against the pin before publication (run proof below). Support-only: no native/UI/playback/Darwin claims, no gorav main ref change, no paid CI; integration lands on the target lane branch only after lab verification and integrator review.

PROBLEM. PARAMS-driven torrent sessions whose demuxerMaxBytes is below the launch 32M backward window got a nil policy from gorParityTorrentRelay, because the validated init refuses back > forward and PARAMS never sets demuxer-max-back-bytes. mpv caps the backward window at the forward window; the policy layer now mirrors that clamp.

DECISION. Clamp backCapacityBytes to min(launch 32M, demuxerMaxBytes) in gorParityTorrentRelay only. Stated as a policy-level mirror of mpv runtime behavior, not a new gor pin. demuxerMaxBytes == 0 still refuses; every other PARAMS field and all other constructors are byte-identical in behavior. Companion expectation repair in the row's own consumer test: its old Q3 middle clause pinned the accidental nil (1024 bytes / 0 secs refused only through back > forward); the real refusals stay pinned and cacheSecs=0 is now pinned as legal (mpv --cache-secs=0).

Scope boundaries: this packet touches only the listed files. It does not touch the returned/conflicting paths ABLoopPolicy.swift, SubtitleSelectionPolicy.swift, ASSParser.swift or the CacheAccounting.swift chain, and does not re-open their rows. No generic tooling, no label-only work, no fabricated evidence: every check below ran on this exact patch against the exact pin.

Repo goreda/gorav main pin 087c15cc068daf1e74112d436e63f07b3d254be4. Test toolchain: official Swift 6.2.3 (ubuntu22.04) on PATH, -swift-version 6 strict concurrency. Return full files on target branch lane/199au/cache-tuning-torrent-back-clamp; the patch against the pin is derivable from the inline sources. Keep .build out of git.

```packet-json
{
  "packet_id": "W-gdb-199au-in2tinct-01",
  "lab": "in2tinct",
  "writer": "gdb",
  "code_owner": "gdb (Ops leg A) authored the patch and tests; goreda owns the gorav trunk integration decision; in2tinct verifies and ingests the listed files only",
  "product_repo": "goreda/gorav",
  "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/cache-parity-tests/Sources/cache-parity-tests/main.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: UInt64, cacheSecs: Double) -> CacheTuningPolicy? (signature unchanged; back-window semantics clamped)",
    "types": "CacheTuningPolicy, CacheTuningPolicyTable, CacheTuningPolicyError, CacheSourceKind (all unchanged)",
    "ownership_lifetime": "Owned production path Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift plus the row's own consumer expectation file; no other production file touched.",
    "caller": "Session creation registering per-torrent PARAMS tuning (TorrentManager PARAMS application, wt_server bridge).",
    "callee": "CacheTuningPolicy.init? validated construction (invariants unchanged)."
  },
  "scope": "product",
  "test": {
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au01 Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift kits/199au/in2tinct-01/main.swift && /tmp/wgdb199au01 && swift build --package-path Sources/cache-parity-tests 2>&1 | tail -1 && Sources/cache-parity-tests/.build/debug/cache-parity-tests | tail -1",
    "expected": "exit 0; kit log ends 'SEMANTIC_PASS W-gdb-199au-in2tinct-01 14 checks' and the row's own cache-parity-tests executable ends 'ALL PASS'",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/199au/cache-tuning-torrent-back-clamp",
    "paths": [
      "Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift",
      "Sources/cache-parity-tests/Sources/cache-parity-tests/main.swift",
      "kits/199au/in2tinct-01/main.swift"
    ],
    "return_form": "full-files"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift",
        "block": "source1"
      },
      {
        "path": "Sources/cache-parity-tests/Sources/cache-parity-tests/main.swift",
        "block": "source2"
      },
      {
        "path": "kits/199au/in2tinct-01/main.swift",
        "block": "fixtures1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "087c15cc068daf1e74112d436e63f07b3d254be4",
    "command": "swiftc -swift-version 6 -o /tmp/wgdb199au01 Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift kits/199au/in2tinct-01/main.swift && /tmp/wgdb199au01 && swift build --package-path Sources/cache-parity-tests 2>&1 | tail -1 && Sources/cache-parity-tests/.build/debug/cache-parity-tests | tail -1",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-20T20:39:41.115513+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "SEMANTIC_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift",
        "block": "source1",
        "sha256": "1ce5a2be4e9e79b2bbf1fdccae1b1f152de7217d3d39b9bcaa88f83f3ac6cc72"
      },
      {
        "path": "Sources/cache-parity-tests/Sources/cache-parity-tests/main.swift",
        "block": "source2",
        "sha256": "bf50bc7e41c71cb7e48e7a3c521ffda813882d241cec0fa3e167a1d7a5e67808"
      },
      {
        "path": "kits/199au/in2tinct-01/main.swift",
        "block": "fixtures1",
        "sha256": "3192258b9e37b1471064cb8bd4dc82614e422ca48532222599dd3ff03822a515"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "c662c8ee10ed78ed1ace19a67acfa3be260b45273b551fef75f1eaed6d68d678",
    "last_5_lines": [
      "PASS T3 unregistered kind refuses typed",
      "PASS B1 launch pins intact",
      "SEMANTIC_PASS W-gdb-199au-in2tinct-01 14 checks",
      "Build complete! (4.08s)",
      "ALL PASS"
    ],
    "receipt_sha256": "a739e0662fe44c3e20463aa7d58223de6509c5278275753d01188734bc6e9e66"
  }
}
```

```swift id=source1
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
        // 199au (W-gdb-199au-in2tinct-01): PARAMS never sets
        // demuxer-max-back-bytes, so the launch 32M backward window was passed
        // through unchanged - but the validated init refuses back > forward,
        // so any torrent session whose PARAMS demuxerMaxBytes is below 32M
        // (a legitimate small-cache PARAMS line) got a nil policy instead of
        // tuning. mpv itself caps the backward window at the forward window
        // when demuxer-max-back-bytes exceeds demuxer-max-bytes; mirror that
        // clamp here. This is a policy-level mirror of mpv runtime behavior,
        // not a new gor pin. demuxerMaxBytes == 0 still refuses (an enabled
        // cache requires a positive forward window).
        let backCapacityBytes = min(launch.backCapacityBytes, demuxerMaxBytes)
        return CacheTuningPolicy(cacheEnabled: true,          // PARAMS: cache=yes
                                 cacheSecs: cacheSecs,        // PARAMS: cache-secs
                                 cachePauseInitial: true,     // PARAMS: cache-pause-initial=yes
                                 cachePause: false,           // PARAMS: cache-pause=no
                                 cachePauseWaitSecs: launch.cachePauseWaitSecs, // untouched
                                 cacheOnDisk: launch.cacheOnDisk,               // untouched
                                 forwardCapacityBytes: demuxerMaxBytes,         // PARAMS: demuxer-max-bytes
                                 backCapacityBytes: backCapacityBytes,          // launch 32M, clamped to forward (mpv mirror)
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

```swift id=source2
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
// 199au (W-gdb-199au-in2tinct-01): the middle clause of the old Q3 pinned an
// accident: (1024 bytes, 0 secs) returned nil only because the launch 32M
// back window exceeded the 1024-byte forward window, not because of the
// zero seconds. The back window is now clamped to the forward window (mpv
// mirrors the same cap), so that combination yields a policy. The real
// refusals stay pinned; cacheSecs=0 is legal (mpv --cache-secs=0).
check("Q3 invalid PARAMS refused (zero bytes, NaN secs)",
      CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 0, cacheSecs: 900) == nil
      && CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 1024, cacheSecs: .nan) == nil)
check("Q4 cacheSecs=0 yields a policy when the forward window stands (mpv --cache-secs=0)",
      CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 64 * 1024 * 1024, cacheSecs: 0) != nil
      && CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 1024, cacheSecs: 0) != nil)

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
```

```swift id=fixtures1
import Foundation

// W-gdb-199au-in2tinct-01 semantic tests for the CacheTuningPolicy torrent
// relay back-window clamp. Compiles against the PATCHED production file
// Sources/GorAVPlaybackCore/CacheParity/CacheTuningPolicy.swift (same module,
// no source-copy stage). Exit 0 only when every check passes.

var failures = 0
@MainActor func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " " + info))
    if !ok { failures += 1 }
}

let M: UInt64 = 1024 * 1024

// C-series: the clamp (new behavior)
if let p = CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 8 * M, cacheSecs: 20) {
    check("C1 small PARAMS forward window is the PARAMS value", p.forwardCapacityBytes == 8 * M)
    check("C2 small PARAMS back window clamps to the forward window", p.backCapacityBytes == 8 * M, "\(p.backCapacityBytes)")
} else { check("C0 small PARAMS session now yields a policy", false, "nil") }
if let p = CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 64 * M, cacheSecs: 20) {
    check("C3 large PARAMS keeps the launch 32M back window", p.backCapacityBytes == 32 * M, "\(p.backCapacityBytes)")
} else { check("C3 large PARAMS yields a policy", false, "nil") }
if let p = CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 32 * M, cacheSecs: 20) {
    check("C4 exact-boundary PARAMS keeps back == forward", p.backCapacityBytes == 32 * M)
} else { check("C4 exact-boundary PARAMS yields a policy", false, "nil") }

// R-series: preserved refusals and fields
check("R1 zero forward window still refuses (enabled cache needs positive forward)",
      CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 0, cacheSecs: 20) == nil)
check("R2 non-finite cacheSecs still refuses",
      CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 8 * M, cacheSecs: .nan) == nil
      && CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 8 * M, cacheSecs: .infinity) == nil)
check("R3 negative cacheSecs still refuses",
      CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 8 * M, cacheSecs: -1) == nil)
if let p = CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 8 * M, cacheSecs: 20) {
    check("R4 PARAMS fields unchanged: cache=yes, pause-initial=yes, pause=no, readahead=cacheSecs",
          p.cacheEnabled && p.cachePauseInitial && !p.cachePause && p.readaheadSecs == 20 && p.cacheSecs == 20)
    check("R5 untouched knobs keep launch values",
          p.cachePauseWaitSecs == 0 && p.cacheOnDisk == false)
} else { check("R4/R5 small PARAMS policy", false, "nil") }

// T-series: table integration over the clamped policy
let table = CacheTuningPolicyTable()
if let p = CacheTuningPolicy.gorParityTorrentRelay(demuxerMaxBytes: 8 * M, cacheSecs: 20) {
    do {
        try table.register(policy: p, for: .torrentRelay)
        let got = try table.policy(for: .torrentRelay)
        check("T1 clamped policy registers and reads back", got.backCapacityBytes == 8 * M)
    } catch { check("T1 register/readback", false, "\(error)") }
    do {
        try table.register(policy: p, for: .torrentRelay)
        check("T2 duplicate registration refused", false, "no throw")
    } catch CacheTuningPolicyError.duplicateRegistration(let kind) {
        check("T2 duplicate registration refused typed", kind == .torrentRelay)
    } catch { check("T2 duplicate registration refused typed", false, "\(error)") }
} else { check("T1/T2 clamped policy", false, "nil") }
do {
    _ = try table.policy(for: .localFile)
    check("T3 unregistered kind refuses typed", false, "no throw")
} catch CacheTuningPolicyError.unknownSource(let kind) {
    check("T3 unregistered kind refuses typed", kind == .localFile)
} catch { check("T3 unregistered kind refuses typed", false, "\(error)") }

// B-series: launch baseline pins unchanged
let baseline = CacheTuningPolicy.gorParityBaseline()
check("B1 launch pins intact", baseline.cacheEnabled && baseline.cacheSecs == 8
      && !baseline.cachePauseInitial && baseline.forwardCapacityBytes == 128 * M
      && baseline.backCapacityBytes == 32 * M && baseline.readaheadSecs == 10)

if failures == 0 {
    print("SEMANTIC_PASS W-gdb-199au-in2tinct-01 14 checks")
} else {
    print("SEMANTIC_FAIL W-gdb-199au-in2tinct-01 \(failures) failures")
    exit(1)
}
```

```text id=actual_run_log
PASS C1 small PARAMS forward window is the PARAMS value
PASS C2 small PARAMS back window clamps to the forward window
PASS C3 large PARAMS keeps the launch 32M back window
PASS C4 exact-boundary PARAMS keeps back == forward
PASS R1 zero forward window still refuses (enabled cache needs positive forward)
PASS R2 non-finite cacheSecs still refuses
PASS R3 negative cacheSecs still refuses
PASS R4 PARAMS fields unchanged: cache=yes, pause-initial=yes, pause=no, readahead=cacheSecs
PASS R5 untouched knobs keep launch values
PASS T1 clamped policy registers and reads back
PASS T2 duplicate registration refused typed
PASS T3 unregistered kind refuses typed
PASS B1 launch pins intact
SEMANTIC_PASS W-gdb-199au-in2tinct-01 14 checks
Build complete! (4.08s)
ALL PASS
```
