// AUTHORED NEW, SOURCE ONLY / NOT_RUN. Owns custom IO, not AVFormatContext.
import Foundation
import CFFmpeg

final class SnapshotAVIOOwner {
    private(set) var io: UnsafeMutablePointer<AVIOContext>?
    private var opaque: UnsafeMutableRawPointer?

    init(snapshot: ImmutableInputSnapshot) throws {
        let retained = Unmanaged.passRetained(SnapshotAVIOBox(snapshot: snapshot))
        let pointer = retained.toOpaque()
        guard let allocation = av_malloc(4096) else {
            retained.release()
            throw FFmpegSoftwareDecoder.OpenError.rejected("custom IO buffer allocation failed")
        }
        let buffer = allocation.assumingMemoryBound(to: UInt8.self)
        guard let context = avio_alloc_context(buffer, 4096, 0, pointer,
                                               SnapshotAVIOBridge.read, nil, SnapshotAVIOBridge.seek) else {
            av_free(allocation) // no context took ownership
            retained.release()
            throw FFmpegSoftwareDecoder.OpenError.rejected("custom IO context allocation failed")
        }
        io = context
        opaque = pointer
    }

    // Must run only after the owning format stopped using pb/callbacks.
    // Same serialized native queue as open/nextEvent/close; no host-thread proof.
    func close() {
        gorav_free_custom_avio(&io)
        if let pointer = opaque {
            opaque = nil
            Unmanaged<SnapshotAVIOBox>.fromOpaque(pointer).release()
        }
    }
    deinit { close() }
}
