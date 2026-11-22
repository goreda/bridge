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
                                pauseInitial: policy.cachePauseInitial)
    }
}
