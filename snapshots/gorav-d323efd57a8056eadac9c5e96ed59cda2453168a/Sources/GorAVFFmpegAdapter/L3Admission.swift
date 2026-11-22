// AUTHORED NEW (2026-10-25, L3 formats/hardware-decode lane).
// L3 codec/container admission policy and hardware-attempt policy.
// d4 close-out (queue 36): the L3AdmissionProfile forwarding layer is retired;
// admission sets and policy live only in GorAVCore AdmissionTable.
import Foundation
import CFFmpeg
import GorAVCore

/// Software pixel-format classification at retain time. Direct formats flow
/// through the trunk's bounded plane allowlist unchanged; convertible formats
/// (the 10-bit family the L3 codecs actually emit) are converted to yuv420p
/// 8-bit first; anything else is an honest refusal, no fallback.
/// Blocker 1 rework: 10-bit frames are PRESERVED ORIGINALS with their own
/// bounded lease and HDR side-data descriptor; the 8-bit SDR conversion is a
/// derived, explicitly requested product (framePlaneCopyDerived), never the
/// retained truth.
public enum L3PixelClass: Equatable, Sendable {
    case direct             // 8-bit allowlist, trunk behavior unchanged
    case preservedOriginal  // 10-bit family: retained with side data, no reduction
    case refuse
}

public enum L3PixelPolicy {
    public static func classification(_ format: Int32) -> L3PixelClass {
        switch format {
        case AV_PIX_FMT_YUV420P.rawValue, AV_PIX_FMT_YUVJ420P.rawValue,
             AV_PIX_FMT_YUV422P.rawValue, AV_PIX_FMT_YUV444P.rawValue,
             AV_PIX_FMT_NV12.rawValue, AV_PIX_FMT_RGB24.rawValue:
            return .direct
        case AV_PIX_FMT_YUV420P10LE.rawValue, AV_PIX_FMT_P010LE.rawValue:
            return .preservedOriginal
        default:
            return .refuse
        }
    }
}
