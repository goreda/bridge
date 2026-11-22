// VT-PRODUCER: independently authored from the public FFmpeg hwcontext,
// codec get_format and VideoToolbox frame layout documentation. Sources
// are recorded in docs/diagnostics/VT-PUBLIC-PRODUCER.md. No decoder close
// implementation is used here. Call all instance methods on decoder owner.
import Foundation
import CFFmpeg
import GorAVPlaybackCore
#if canImport(CoreVideo)
import CoreVideo
#endif

/// Stateless C callback. No ctx.opaque capture and no lifetime dependency on
/// a Swift object: FFmpeg may call this from its own decode worker thread.
private func vtPublicSoftwareFormat(_ formats: UnsafePointer<AVPixelFormat>?) -> AVPixelFormat {
    guard let formats else { return AV_PIX_FMT_NONE }
    var index = 0
    while formats[index] != AV_PIX_FMT_NONE {
        let format = formats[index]
        if let descriptor = av_pix_fmt_desc_get(format),
           descriptor.pointee.flags & UInt64(AV_PIX_FMT_FLAG_HWACCEL) == 0 { return format }
        index += 1
    }
    return AV_PIX_FMT_NONE
}
private func vtPublicPreferredFormat(_ context: UnsafeMutablePointer<AVCodecContext>?,
                                     _ formats: UnsafePointer<AVPixelFormat>?) -> AVPixelFormat {
    guard let formats else { return AV_PIX_FMT_NONE }
    var index = 0
    while formats[index] != AV_PIX_FMT_NONE {
        if formats[index] == AV_PIX_FMT_VIDEOTOOLBOX { return AV_PIX_FMT_VIDEOTOOLBOX }
        index += 1
    }
    return vtPublicSoftwareFormat(formats)
}
private func vtPublicSoftwareCallback(_ context: UnsafeMutablePointer<AVCodecContext>?,
                                      _ formats: UnsafePointer<AVPixelFormat>?) -> AVPixelFormat {
    vtPublicSoftwareFormat(formats)
}

/// Owns only its AVBufferRef device reference. The codec context owns the
/// av_buffer_ref installed in hw_device_ctx. Producer teardown never closes,
/// flushes, frees or reorders an existing decoder/format/AVIO context.
public final class VTHardwareFrameProducer {
    public enum Preparation: Equatable { case hardwareAttached, software(String) }
    public enum ProducerError: Error, Equatable {
        case alreadyOpened, occupiedDevice, staleGeneration, invalidTiming
        case unsupportedNativeFrame, missingNativeBuffer, freshSoftwareContextRequired
    }
    public struct Receipt: Equatable {
        public var fallbackReason: String?
        public var nativeFrames = 0
        public var softwareFrames = 0
        public var deviceAttached = false
        public var freshSoftwareRetryRequested = false
        public init() {}
    }
    public private(set) var receipt = Receipt()
    private var device: UnsafeMutablePointer<AVBufferRef>?
    private var source: SourceSession
    private var hardwareAllowed = true
    private var prepared = false
    private let forceDeviceFailure: Bool
    public init(source: SourceSession) { self.source = source; forceDeviceFailure = false }
    #if DEBUG
    public init(source: SourceSession, testForceDeviceFailure: Bool) {
        self.source = source; forceDeviceFailure = testForceDeviceFailure
    }
    #endif
    deinit { av_buffer_unref(&device) }

    /// Install before avcodec_open2. A failed device attempt still installs
    /// software-only format selection and returns a recorded software reason.
    @discardableResult
    public func prepareBeforeOpen(_ context: UnsafeMutablePointer<AVCodecContext>) throws -> Preparation {
        guard avcodec_is_open(context) == 0, !prepared else { throw ProducerError.alreadyOpened }
        guard context.pointee.hw_device_ctx == nil else { throw ProducerError.occupiedDevice }
        prepared = true
        guard hardwareAllowed else {
            context.pointee.get_format = vtPublicSoftwareCallback
            return .software(receipt.fallbackReason ?? "vt-software-retry")
        }
        let rc: Int32
        if forceDeviceFailure { rc = -1 }
        else { rc = av_hwdevice_ctx_create(&device, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, nil, nil, 0) }
        guard rc >= 0, let device, let codecReference = av_buffer_ref(device) else {
            av_buffer_unref(&self.device)
            noteFallback(forceDeviceFailure ? "vt-forced-device-failure" : "vt-device-create-failed")
            hardwareAllowed = false
            context.pointee.get_format = vtPublicSoftwareCallback
            return .software(receipt.fallbackReason!)
        }
        context.pointee.hw_device_ctx = codecReference
        context.pointee.get_format = vtPublicPreferredFormat
        receipt.deviceAttached = true
        return .hardwareAttached
    }

    /// A codec-open or receive/session failure requests one fresh software
    /// context. The caller closes through its EXISTING public close path and
    /// supplies a freshly allocated, configured context. This unit does not
    /// touch the old context or choose packet/seek replay ordering.
    public func requestFreshSoftwareRetry(reason: String) -> Bool {
        guard !receipt.freshSoftwareRetryRequested else { return false }
        noteFallback(reason)
        receipt.freshSoftwareRetryRequested = true
        hardwareAllowed = false; prepared = false
        receipt.deviceAttached = false
        av_buffer_unref(&device) // codec's independently owned reference remains valid
        return true
    }
    /// Only after the actual owner queue has completed its seek barrier.
    public func advanceAfterBarrier(to binding: SourceSession) throws {
        guard binding.session == source.session, binding.revision >= source.revision else { throw ProducerError.staleGeneration }
        source = binding
    }
    public func validates(_ provenance: NativeFrameProvenance) -> Bool {
        provenance.admits(source: source, ptsSeconds: provenance.ptsSeconds, durationSeconds: provenance.durationSeconds)
    }
    /// Call for software frames after receive, including a provider's failed
    /// VT negotiation. There is no fabricated native-frame receipt.
    public func noteSoftwareFrame() {
        receipt.softwareFrames += 1
        if receipt.deviceAttached { noteFallback("vt-format-negotiated-software") }
    }
    private func noteFallback(_ reason: String) {
        if receipt.fallbackReason == nil { receipt.fallbackReason = reason }
    }

    #if canImport(CoreVideo)
    /// Call while the original AVFrame is still owned on the decode queue.
    /// provenance must be captured for that original frame, never stamped from
    /// current state after a seek. Exact PTS is checked in its stream timebase.
    /// nil = software frame; unsupported native SDR variant is a typed error.
    public func retainSourceFrame(_ frame: UnsafePointer<AVFrame>, provenance: NativeFrameProvenance,
                                  timebase: AVRational) throws -> SourceFrame? {
        guard validates(provenance) else { throw ProducerError.staleGeneration }
        let timestamp = frame.pointee.best_effort_timestamp
        guard timestamp != Int64.min, timebase.num > 0, timebase.den > 0,
              Double(timestamp) * Double(timebase.num) / Double(timebase.den) == provenance.ptsSeconds else {
            throw ProducerError.invalidTiming
        }
        guard frame.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue else {
            noteSoftwareFrame(); return nil
        }
        guard let data = frame.pointee.data.3 else { throw ProducerError.missingNativeBuffer }
        let pb = Unmanaged<CVPixelBuffer>.fromOpaque(UnsafeRawPointer(data)).retain().takeRetainedValue()
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetWidth(pb) == Int(frame.pointee.width),
              CVPixelBufferGetHeight(pb) == Int(frame.pointee.height),
              CVPixelBufferGetPlaneCount(pb) == 2,
              frame.pointee.color_range == AVCOL_RANGE_MPEG,
              frame.pointee.color_trc == AVCOL_TRC_BT709 || frame.pointee.color_trc == AVCOL_TRC_SMPTE170M else {
            throw ProducerError.unsupportedNativeFrame
        }
        let matrix: YUV420Converter.Matrix
        switch frame.pointee.colorspace {
        case AVCOL_SPC_BT709: matrix = .bt709
        case AVCOL_SPC_BT470BG, AVCOL_SPC_SMPTE170M: matrix = .bt601
        default: throw ProducerError.unsupportedNativeFrame
        }
        let payload = VTFramePayload(pixelBuffer: pb, width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb),
                                     matrix: matrix, ioSurfaceBacked: CVPixelBufferGetIOSurface(pb) != nil,
                                     cvPixelFormat: CVPixelBufferGetPixelFormatType(pb), provenance: provenance)
        receipt.nativeFrames += 1
        return SourceFrame(ptsSeconds: provenance.ptsSeconds, durationSeconds: provenance.durationSeconds,
                           digest: "vt-zerocopy", vtPayload: payload)
    }
    #endif
}
