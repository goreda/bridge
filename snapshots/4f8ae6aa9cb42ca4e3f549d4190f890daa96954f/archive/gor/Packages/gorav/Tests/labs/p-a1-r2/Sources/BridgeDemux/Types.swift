import Foundation

/// Rational timestamp: seconds = value / scale. `scale` is always positive.
public struct RationalTime: Equatable, Sendable {
    public let value: Int64
    public let scale: Int64 // positive; seconds = value / scale
    public init(value: Int64, scale: Int64) {
        self.value = value
        self.scale = scale
    }
}

public struct DemuxTrack: Sendable {
    public let id: Int
    public let kind: String
    public let codec: String
    public let codecPrivate: [UInt8]
    public init(id: Int, kind: String, codec: String, codecPrivate: [UInt8] = []) {
        self.id = id
        self.kind = kind
        self.codec = codec
        self.codecPrivate = codecPrivate
    }
}

public struct DemuxPacket: Sendable {
    public let trackID: Int
    public let pts: RationalTime?
    public let dts: RationalTime?
    public let duration: RationalTime?
    public let bytes: [UInt8]
    public init(trackID: Int, pts: RationalTime?, dts: RationalTime?, duration: RationalTime?, bytes: [UInt8]) {
        self.trackID = trackID
        self.pts = pts
        self.dts = dts
        self.duration = duration
        self.bytes = bytes
    }
}

/// A demuxer reads one container held fully in memory and returns its
/// elementary-stream packets in the container's natural (decode) order.
public protocol PacketDemuxer {
    /// Parses container headers and returns the track table.
    mutating func open(_ bytes: [UInt8]) throws -> [DemuxTrack]
    /// Returns the next packet, or nil only at end of stream.
    mutating func next() throws -> DemuxPacket?
}

/// Errors thrown by the demuxers. Empty or truncated input always throws;
/// it never crashes and never returns invented timestamps.
public enum DemuxError: Error, Equatable, CustomStringConvertible {
    case emptyInput
    case truncated(String)
    case malformed(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case .emptyInput: return "empty input"
        case .truncated(let s): return "truncated: \(s)"
        case .malformed(let s): return "malformed: \(s)"
        case .unsupported(let s): return "unsupported: \(s)"
        }
    }
}
