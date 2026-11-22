import Foundation
import GorAVNativeProbeKit
import CFFmpeg

/// A queue-time observation of the active AVIOContext, not a cache model.
/// nil means unavailable/not observed, never zero. No paths, URLs or headers.
public struct ActiveTransportSnapshot: Equatable, Sendable {
    public let source: SourceToken
    public let session: SeekSessionID
    public let revision: SeekRevision
    /// FFmpeg AVIO bytes_read counter, cumulative for this open. Includes probe
    /// reads and rereads; not network-only unique bytes or file position.
    public let bytesRead: Int64?
    /// Bytes remaining in AVIO's current user-space input buffer only.
    public let bufferAvailableBytes: Int?
    /// true when AVIO has observed EOF; nil before that or without an AVIOContext.
    /// A seek can clear this observation. No prediction that the remote is finished.
    public let eofObserved: Bool?
    /// Negative FFmpeg AVIO error when present; nil means no error observed,
    /// not an assertion that transport is healthy or unable to stall.
    public let errorCode: Int32?

    // Called only inside the format owner's native queue, never retains pb.
    static func capture(_ pb: UnsafePointer<AVIOContext>?, source: SourceToken,
                        session: SeekSessionID, revision: SeekRevision) -> Self {
        guard let pb else {
            return Self(source: source, session: session, revision: revision,
                        bytesRead: nil, bufferAvailableBytes: nil, eofObserved: nil, errorCode: nil)
        }
        let count = pb.pointee.bytes_read
        let available = gorav_avio_buffer_available(pb)
        return Self(source: source, session: session, revision: revision,
                    bytesRead: count >= 0 ? count : nil,
                    bufferAvailableBytes: available >= 0 ? Int(available) : nil,
                    eofObserved: pb.pointee.eof_reached != 0 ? true : nil,
                    errorCode: pb.pointee.error < 0 ? pb.pointee.error : nil)
    }
}

public enum ActiveTransportRefusal: Error, Equatable, Sendable {
    case notOpen, staleBinding
}
