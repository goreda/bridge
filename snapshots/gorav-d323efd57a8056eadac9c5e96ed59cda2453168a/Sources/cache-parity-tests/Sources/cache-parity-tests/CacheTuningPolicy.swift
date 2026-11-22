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
