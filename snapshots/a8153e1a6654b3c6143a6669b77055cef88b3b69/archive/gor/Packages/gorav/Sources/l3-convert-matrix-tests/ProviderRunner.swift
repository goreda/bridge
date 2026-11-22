// Provider lane: replays the golden matrix against the REAL pinned
// L3SampleConverter (Sources/GorAVFFmpegAdapter/L3SampleConvert.swift,
// product pin 2112af0d, branch ohal/gorav) through the gorav_l3_swr_* shim.
// This whole file compiles to nothing unless the product package defines
// L3_PROVIDER for this target and links GorAVFFmpegAdapter (see README.md).
#if L3_PROVIDER
import Foundation
import CFFmpeg
import GorAVFFmpegAdapter

public enum ProviderLane {
    public static func layoutMask(_ name: String) -> UInt64 {
        // Layout masks per the FFmpeg channel-layout API used by the product's
        // CFFmpeg module. Newer FFmpeg exposes AVChannelLayout; populate
        // channel_layout/u.mask equivalently. These numeric masks are the
        // long-stable AV_CH_LAYOUT_* values (ASSUMED stable across the
        // FFmpeg major the product pins; verify against the product's
        // CFFmpeg if it differs).
        switch name {
        case "mono": return 0x4
        case "stereo": return 0x3
        case "2.1": return 0x103
        case "3.0": return 0x7
        case "4.0": return 0x33
        case "5.0": return 0x607
        case "5.1": return 0x60f
        case "6.1": return 0x70f
        case "7.1": return 0x63f
        default: return 0 // "unknown" and anything else: no layout mask
        }
    }

    public static func sampleFormat(_ name: String) -> AVSampleFormat? {
        switch name {
        case "u8": return AV_SAMPLE_FMT_U8
        case "s16le": return AV_SAMPLE_FMT_S16
        case "s32le": return AV_SAMPLE_FMT_S32
        case "f32le": return AV_SAMPLE_FMT_FLT
        case "f64le": return AV_SAMPLE_FMT_DBL
        case "u8p": return AV_SAMPLE_FMT_U8P
        case "s16p": return AV_SAMPLE_FMT_S16P
        case "s32p": return AV_SAMPLE_FMT_S32P
        case "fltp": return AV_SAMPLE_FMT_FLTP
        case "dblp": return AV_SAMPLE_FMT_DBLP
        default: return nil
        }
    }

    /// Builds one decoded-frame stand-in: `inSamples` of a sine at `tone`
    /// Hz (or deterministic noise when tone is nil) in the given
    /// layout/format/rate. Layout mask 0 or rate <= 0 leaves the frame
    /// unallocated on purpose: the matrix expects a typed nil-failure there.
    public static func makeFrame(_ d: RefFrame) -> UnsafeMutablePointer<AVFrame>? {
        var f0: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard let f = f0 else { return nil }
        f.pointee.nb_samples = Int32(d.inSamples)
        // Integrator adaptation (product pins FFmpeg 7.1 headers): the kit was
        // authored against the 4.4-era AVFrame.channel_layout field; the pinned
        // 7.1 API carries AVChannelLayout (ch_layout). Mask values are the same
        // long-stable AV_CH_LAYOUT_* constants.
        av_channel_layout_from_mask(&f.pointee.ch_layout, layoutMask(d.layout))
        f.pointee.sample_rate = Int32(d.inRate)
        guard let fmt = sampleFormat(d.inFormat) else { av_frame_free(&f0); return nil }
        f.pointee.format = fmt.rawValue
        guard f.pointee.ch_layout.nb_channels > 0, d.inRate > 0 else { return f } // unallocated on purpose
        guard av_frame_get_buffer(f, 0) == 0 else { av_frame_free(&f0); return nil }
        let ch = Int(f.pointee.ch_layout.nb_channels)
        let planar = av_sample_fmt_is_planar(fmt) != 0
        for i in 0..<d.inSamples {
            let v = d.tone != nil
                ? sin(2.0 * Double.pi * d.tone! * Double(i) / Double(d.inRate))
                : Double((i * 37) & 0xff) / 128.0 - 1.0
            let planes = planar ? ch : 1
            for p in 0..<planes {
                guard let data = f.pointee.extended_data[p] else { continue }
                let idx = planar ? i : i * ch + p
                switch fmt {
                case AV_SAMPLE_FMT_U8, AV_SAMPLE_FMT_U8P:
                    data[idx] = UInt8(clamping: Int(v * 100.0) + 128)
                case AV_SAMPLE_FMT_S16, AV_SAMPLE_FMT_S16P:
                    data.withMemoryRebound(to: Int16.self, capacity: idx + 1) { $0[idx] = Int16(clamping: Int(v * 12000.0)) }
                case AV_SAMPLE_FMT_S32, AV_SAMPLE_FMT_S32P:
                    data.withMemoryRebound(to: Int32.self, capacity: idx + 1) { $0[idx] = Int32(clamping: Int(v * 800_000_000.0)) }
                case AV_SAMPLE_FMT_FLT, AV_SAMPLE_FMT_FLTP:
                    data.withMemoryRebound(to: Float.self, capacity: idx + 1) { $0[idx] = Float(v * 0.5) }
                case AV_SAMPLE_FMT_DBL, AV_SAMPLE_FMT_DBLP:
                    data.withMemoryRebound(to: Double.self, capacity: idx + 1) { $0[idx] = v * 0.5 }
                default: break
                }
            }
        }
        return f
    }

    public static func freeFrame(_ f: UnsafeMutablePointer<AVFrame>?) {
        var v = f
        av_frame_free(&v)
    }
}

/// Adapter giving the shared sequence interpreter one uniform surface over
/// the real pinned converter.
public final class ProviderConv: Conv {
    public let inner = L3SampleConverter()
    public init() {}
    public var convertedFrames: Int { inner.convertedFrames }
    public var conversionFailures: Int { inner.conversionFailures }
    public var inputSamples: Int64 { inner.inputSamples }
    public var outputSamples: Int64 { inner.outputSamples }
    public var inputSamplesByRate: [Int: Int64] { inner.inputSamplesByRate }
    public var seekCount: Int { inner.seekCount }
    public var reinitCount: Int { inner.reinitCount }
    public func currentInputDelay(inputRate: Int64) -> Int64 { inner.currentInputDelay(inputRate: inputRate) }
    public func resetForSeek() -> Bool { inner.resetForSeek() }
    public func convert(frame d: RefFrame, maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        guard let f = ProviderLane.makeFrame(d) else { return nil }
        defer { ProviderLane.freeFrame(f) }
        return inner.convert(frame: f, maxFrameBytes: maxFrameBytes)
    }
    public func drain(maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        inner.drain(maxFrameBytes: maxFrameBytes)
    }
}
#endif
