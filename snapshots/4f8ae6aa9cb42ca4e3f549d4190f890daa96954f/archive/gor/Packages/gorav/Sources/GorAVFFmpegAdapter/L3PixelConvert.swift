// AUTHORED NEW (2026-10-25, L3 formats/hardware-decode lane).
// swscale-backed conversion of admitted 10-bit software frames to yuv420p
// 8-bit, the format the trunk's bounded plane allowlist and the display sink
// already model. Conversion is measured (context cached per geometry/format),
// bounded (refusal, never a guess, on any conversion failure), and honest:
// 10-bit to 8-bit is a bit-depth reduction for the 8-bit pipeline, NOT tone
// mapping; that is stated in PATCH_NOTES, not hidden.
import Foundation
import CFFmpeg

public final class L3PixelConverter {
    private var conv: UnsafeMutablePointer<GorAVL3PixConv>?
    private(set) public var convertedFrames = 0
    private(set) public var conversionFailures = 0
    /// Typed result accounting per source format (L5 seam).
    private(set) public var conversionSources: [String: Int] = [:]

    public init() {
        conv = gorav_l3_pixconv_open()
    }
    deinit {
        gorav_l3_pixconv_close(&conv)
    }

    /// Converts `src` (an admitted convertible software frame) into a newly
    /// allocated yuv420p 8-bit frame with metadata copied. The caller owns the
    /// returned frame (retain path treats it exactly like a decoded clone).
    /// Returns nil on any failure; the failure is counted, never guessed past.
    public func convertToYUV420P(_ src: UnsafeMutablePointer<AVFrame>) -> UnsafeMutablePointer<AVFrame>? {
        var dst: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard dst != nil else { conversionFailures += 1; return nil }
        let srcName = av_get_pix_fmt_name(AVPixelFormat(rawValue: src.pointee.format))
            .map { String(cString: $0) } ?? "unknown"
        let rc = gorav_l3_to_yuv420p(conv, dst, src)
        guard rc == 0 else {
            av_frame_free(&dst)
            conversionFailures += 1
            return nil
        }
        convertedFrames += 1
        conversionSources[srcName, default: 0] += 1
        return dst
    }
}
