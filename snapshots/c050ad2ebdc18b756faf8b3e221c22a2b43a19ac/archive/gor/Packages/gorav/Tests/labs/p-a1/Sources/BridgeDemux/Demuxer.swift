import Foundation

/// Container-sniffing demuxer: dispatches to the MP4 or Matroska
/// implementation based on magic bytes. This is the main entry point.
public struct Demuxer: PacketDemuxer {
    private var impl: (any PacketDemuxer)?

    public init() {}

    public mutating func open(_ bytes: [UInt8]) throws -> [DemuxTrack] {
        if bytes.isEmpty { throw DemuxError.emptyInput }
        if MP4Demuxer.looksLikeMP4(bytes) {
            var d = MP4Demuxer()
            let tracks = try d.open(bytes)
            impl = d
            return tracks
        }
        if MKVDemuxer.looksLikeMKV(bytes) {
            var d = MKVDemuxer()
            let tracks = try d.open(bytes)
            impl = d
            return tracks
        }
        throw DemuxError.unsupported("container is neither MP4 (ftyp) nor Matroska (EBML)")
    }

    public mutating func next() throws -> DemuxPacket? {
        guard var d = impl else { throw DemuxError.malformed("next() before open()") }
        let p = try d.next()
        impl = d
        return p
    }
}
