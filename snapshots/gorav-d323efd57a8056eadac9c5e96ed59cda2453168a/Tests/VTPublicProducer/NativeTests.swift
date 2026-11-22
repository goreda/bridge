#if canImport(CoreVideo)
import CoreVideo
import CFFmpeg
import GorAVPlaybackCore
import GorAVFFmpegAdapter

func nativePublicProducerRetainTest() throws {
    let binding = SourceSession(session: 91, revision: 0)
    let producer = VTHardwareFrameProducer(source: binding)
    let provenance = NativeFrameProvenance(source: binding, ptsSeconds: 1, durationSeconds: 0.04)
    var slot = NativeFrameSlot()
    var recycled = 0
    for _ in 0..<1000 {
        weak var weakOwner: NativeFrameOwnership?
        var gpuReader: NativeFrameOwnership?
        do {
            var pb: CVPixelBuffer?
            let attrs: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
                                         kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
            precondition(CVPixelBufferCreate(nil, 8, 4, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                            attrs as CFDictionary, &pb) == kCVReturnSuccess)
            var frame = av_frame_alloc()
            precondition(frame != nil)
            frame!.pointee.format = AV_PIX_FMT_VIDEOTOOLBOX.rawValue
            frame!.pointee.width = 8; frame!.pointee.height = 4
            frame!.pointee.best_effort_timestamp = 25
            frame!.pointee.color_range = AVCOL_RANGE_MPEG
            frame!.pointee.color_trc = AVCOL_TRC_BT709
            frame!.pointee.colorspace = AVCOL_SPC_BT709
            // Synthetic AVFrame fixture, native image is live here. Product
            // receive uses the actual VT frame and retains data[3] identically.
            frame!.pointee.data.3 = Unmanaged.passUnretained(pb!).toOpaque().assumingMemoryBound(to: UInt8.self)
            var sourceFrame = try producer.retainSourceFrame(UnsafePointer(frame!), provenance: provenance,
                                                             timebase: AVRational(num: 1, den: 25))
            precondition(sourceFrame?.pixelPayload == nil)
            weakOwner = sourceFrame?.vtPayload?.ownership
            slot.replace(with: sourceFrame?.vtPayload?.ownership)
            gpuReader = slot.ownership
            sourceFrame = nil
            av_frame_free(&frame)
            pb = nil // slot/GPU owners now keep the image alive
        }
        precondition(weakOwner != nil)
        slot.recycle(); precondition(weakOwner != nil)
        precondition(gpuReader != nil); gpuReader = nil
        precondition(weakOwner == nil)
        recycled += 1
    }
    try producer.advanceAfterBarrier(to: SourceSession(session: 91, revision: 1))
    precondition(!producer.validates(provenance))
    print("PASS VT-PUBLIC-PRODUCER native CVPixelBuffer SourceFrame retain/recycle=\(recycled); original generation refused after barrier. Synthetic AVFrame, not hardware decode/Metal PASS.")
}
#endif
