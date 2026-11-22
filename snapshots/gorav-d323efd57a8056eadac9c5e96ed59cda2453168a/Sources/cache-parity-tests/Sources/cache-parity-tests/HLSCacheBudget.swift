// HLSCacheBudget: gorav's pinned HLS VOD preparation budget (SUPPORT only).
// Row: GORAV-CACHE-PARITY. HLS in gorav is a download-then-open-local model:
// HLSVODSource.prepare fetches whole segments into a caller-owned private
// directory and the decoder opens the prepared files as LOCAL sources, so
// the mpv-shaped CacheTuningPolicy for .hlsVOD stays at the launch baseline
// (the decode open is a local open) and HLS's per-source cache substance
// lives HERE, at prepare time, in these budget constants.
// Every value is GOR-PINNED from gorav main c1431906
// Sources/GorAVPlaybackCore/HLSVODSource.swift: playlist fetch cap 1 MiB
// (:45 master, :55 variant), init-segment cap min(total, 4 MiB) (:76),
// segment cap min(total, 16 MiB) (:80), total budget default 64 MiB (:37),
// request timeout 10 s / resource timeout 20 s (:108), URLSession cache and
// cookie storage explicitly disabled (:109). Immutable value; no I/O here.
import Foundation

public struct HLSCacheBudget: Equatable, Sendable {
    /// Cap on each playlist fetch (master and chosen variant), bytes.
    public let playlistCapBytes: Int
    /// Cap on the init segment (#EXT-X-MAP), bytes, before the total budget.
    public let initSegmentCapBytes: Int
    /// Cap on each media segment fetch, bytes, before the total budget.
    public let segmentCapBytes: Int
    /// Default total byte budget across all fetched parts.
    public let totalBudgetBytes: Int
    /// URLSession per-request timeout, seconds.
    public let requestTimeoutSecs: Double
    /// URLSession whole-resource timeout, seconds.
    public let resourceTimeoutSecs: Double
    /// gorav pins URLSessionConfiguration.urlCache = nil for these fetches:
    /// no shared HTTP cache participates in HLS preparation.
    public let sharedURLCacheDisabled: Bool

    public init(playlistCapBytes: Int, initSegmentCapBytes: Int, segmentCapBytes: Int,
                totalBudgetBytes: Int, requestTimeoutSecs: Double, resourceTimeoutSecs: Double,
                sharedURLCacheDisabled: Bool) {
        self.playlistCapBytes = playlistCapBytes
        self.initSegmentCapBytes = initSegmentCapBytes
        self.segmentCapBytes = segmentCapBytes
        self.totalBudgetBytes = totalBudgetBytes
        self.requestTimeoutSecs = requestTimeoutSecs
        self.resourceTimeoutSecs = resourceTimeoutSecs
        self.sharedURLCacheDisabled = sharedURLCacheDisabled
    }

    /// The exact constants HLSVODSource.prepare ships with today (citations
    /// in the file header). Pinned so a drift in the source constants fails
    /// a test instead of silently changing the cache behaviour.
    public static let goravPinned = HLSCacheBudget(
        playlistCapBytes: 1 * 1024 * 1024,
        initSegmentCapBytes: 4 * 1024 * 1024,
        segmentCapBytes: 16 * 1024 * 1024,
        totalBudgetBytes: 64 * 1024 * 1024,
        requestTimeoutSecs: 10,
        resourceTimeoutSecs: 20,
        sharedURLCacheDisabled: true)
}
