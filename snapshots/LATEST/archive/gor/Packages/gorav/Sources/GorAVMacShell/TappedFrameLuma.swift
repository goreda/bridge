#if canImport(AppKit) && canImport(CoreVideo)
import CoreVideo
import Foundation
import GorAVPlaybackCore

// R8 (arch-195l, dispatch L6): Darwin adapter from the P27 tap's TappedFrame
// (retained CVPixelBuffer) to the pure-Swift TapCropDetector. This file is
// macOS-only and UNCOMPILED on Linux (no Mac here): it is reviewed source,
// not measured native behavior. Pixel formats: planar luma is read from
// plane 0 for yuv420-family and bi-planar NV12/P010; anything else (BGRA,
// RGB) returns nil rather than guessing a luma transform. The buffer is
// locked read-only for the duration of the copy and always unlocked.

public enum TappedFrameLuma {
    /// Copy the luma plane of a tapped frame into a LumaPlane for
    /// TapCropDetector. nil = unsupported pixel format or lock failure; the
    /// pump treats that as "no frame this tick", never as a bar detection.
    public static func lumaPlane(of frame: TappedFrame) -> LumaPlane? {
        let pb = frame.pixelBuffer
        let isPlanarYUV = CVPixelBufferIsPlanar(pb)
            && (CVPixelBufferGetPlaneCount(pb) >= 1)
        guard isPlanarYUV else { return nil }
        guard CVPixelBufferLockBaseAddress(pb, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pb, 0)
        let height = CVPixelBufferGetHeightOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        guard width > 0, height > 0, stride >= width else { return nil }
        let needed = stride * (height - 1) + width
        let bytes = Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self),
                                              count: needed))
        return LumaPlane(bytes: bytes, width: width, height: height, strideBytes: stride)
    }

    /// One-shot convenience: luma extraction + detection for a tapped frame.
    public static func detectCrop(in frame: TappedFrame,
                                  config: BorderScanConfig = BorderScanConfig())
        -> CropSuggestion? {
        guard let plane = lumaPlane(of: frame) else { return nil }
        return TapCropDetector.detect(plane, config: config)
    }
}
#endif
