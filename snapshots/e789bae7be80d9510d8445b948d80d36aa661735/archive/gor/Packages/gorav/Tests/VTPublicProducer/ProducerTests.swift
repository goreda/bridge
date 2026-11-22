import Foundation
import CFFmpeg
import GorAVPlaybackCore
#if SWIFT_PACKAGE
import GorAVFFmpegAdapter
#endif

@main struct VTPublicProducerTests {
    static func main() async throws {
        let origin = SourceSession(session: 77, revision: 0)
        let producer = VTHardwareFrameProducer(source: origin, testForceDeviceFailure: true)
        guard let codec = avcodec_find_decoder(AV_CODEC_ID_H264), let context = avcodec_alloc_context3(codec) else { fatalError("h264 decoder unavailable") }
        var ownedContext: UnsafeMutablePointer<AVCodecContext>? = context
        defer { avcodec_free_context(&ownedContext) } // test owns this context, not the product decoder
        let initialPreparation = try producer.prepareBeforeOpen(context)
        precondition(initialPreparation == .software("vt-forced-device-failure"))
        precondition(context.pointee.hw_device_ctx == nil)
        let offered = [AV_PIX_FMT_VIDEOTOOLBOX, AV_PIX_FMT_YUV420P, AV_PIX_FMT_NONE]
        let selected = offered.withUnsafeBufferPointer { context.pointee.get_format!(context, $0.baseAddress) }
        precondition(selected == AV_PIX_FMT_YUV420P) // actual installed callback, no fake provider
        precondition(producer.receipt.fallbackReason == "vt-forced-device-failure")
        precondition(producer.requestFreshSoftwareRetry(reason: "forced-open-failure"))
        precondition(!producer.requestFreshSoftwareRetry(reason: "second-failure"))
        let p0 = NativeFrameProvenance(source: origin, ptsSeconds: 0, durationSeconds: 0.04)
        precondition(producer.validates(p0))
        try producer.advanceAfterBarrier(to: SourceSession(session: 77, revision: 1))
        precondition(!producer.validates(p0))
        precondition(!producer.validates(NativeFrameProvenance(source: SourceSession(session: 78, revision: 1), ptsSeconds: 0, durationSeconds: 0.04)))
        var dropCount = 0
        final class Probe { let onDrop: () -> Void; init(_ onDrop: @escaping () -> Void) { self.onDrop = onDrop }; deinit { onDrop() } }
        var slot = NativeFrameSlot()
        for _ in 0..<1000 {
            weak var weakOwner: NativeFrameOwnership?
            var gpuOwner: NativeFrameOwnership?
            do {
                let owner = NativeFrameOwnership(retaining: Probe { dropCount += 1 }, provenance: p0)
                weakOwner = owner; slot.replace(with: owner); gpuOwner = owner
            }
            slot.recycle(); precondition(weakOwner != nil)
            precondition(gpuOwner != nil); gpuOwner = nil
            precondition(weakOwner == nil)
        }
        precondition(dropCount == 1000)
        guard CommandLine.arguments.count == 2 else { fatalError("expected actual h264 fixture path") }
        // An actual independently owned local demux/decode test: forced VT
        // device failure must still open/decode, not merely return a reason.
        var format: UnsafeMutablePointer<AVFormatContext>?
        precondition(avformat_open_input(&format, CommandLine.arguments[1], nil, nil) >= 0)
        defer { avformat_close_input(&format) }
        precondition(avformat_find_stream_info(format, nil) >= 0)
        let streamIndex = av_find_best_stream(format, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        precondition(streamIndex >= 0)
        let stream = format!.pointee.streams[Int(streamIndex)]!
        guard let decoder = avcodec_find_decoder(stream.pointee.codecpar.pointee.codec_id),
              let software = avcodec_alloc_context3(decoder) else { fatalError("fixture decoder unavailable") }
        var ownedSoftware: UnsafeMutablePointer<AVCodecContext>? = software
        defer { avcodec_free_context(&ownedSoftware) }
        precondition(avcodec_parameters_to_context(software, stream.pointee.codecpar) >= 0)
        let retryPreparation = try producer.prepareBeforeOpen(software)
        precondition(retryPreparation == .software("vt-forced-device-failure"))
        precondition(avcodec_open2(software, decoder, nil) >= 0)
        var packet = av_packet_alloc(), frame = av_frame_alloc()
        defer { av_packet_free(&packet); av_frame_free(&frame) }
        var frames = 0
        func drain() {
            while true {
                let rc = avcodec_receive_frame(software, frame)
                if rc < 0 { break }
                precondition(frame!.pointee.format != AV_PIX_FMT_VIDEOTOOLBOX.rawValue)
                producer.noteSoftwareFrame(); frames += 1; av_frame_unref(frame)
            }
        }
        while av_read_frame(format, packet) >= 0 {
            if packet!.pointee.stream_index == streamIndex { precondition(avcodec_send_packet(software, packet) >= 0); drain() }
            av_packet_unref(packet)
        }
        precondition(avcodec_send_packet(software, nil) >= 0); drain()
        precondition(frames > 0 && producer.receipt.softwareFrames == frames)
        print("PASS VT-PUBLIC-PRODUCER forced-device callback selects software; fresh retry bounded; real software decoded frames=\(frames); generation refusals; recycle=\(dropCount)")
        #if canImport(CoreVideo) && SWIFT_PACKAGE
        try nativePublicProducerRetainTest()
        #else
        print("UNRUN native VT CVPixelBuffer retain + Metal integration on Linux")
        #endif
    }
}
