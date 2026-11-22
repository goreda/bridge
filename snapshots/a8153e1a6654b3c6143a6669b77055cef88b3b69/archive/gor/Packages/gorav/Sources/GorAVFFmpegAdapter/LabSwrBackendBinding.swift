// Lane (c) playback-path wiring (arch-196y r1 item 3c / 196t r2 item 4b).
// Product binding of the LANDED LabSwrConverter seam (G0740 / 195b-N9) to the
// real libswresample of the pinned FFmpeg provider: until this file the seam
// existed only as a kit parity port with the backend protocol bound inside
// the kit. This is the product backend; the DSP stays in libswresample, the
// seam owns the state machine (generation/stale/flush, bounded pts math,
// zero-input contract). No resampling is reimplemented here.
import Foundation
import CFFmpeg
import GorAVPlaybackCore

public enum LabSwrBackendError: Error {
    case initRefused   // swr_init refused the negotiated spec (UNSUPPORTED)
}

public final class GorAVSwrBackend: LabSwrBackend {
    private var ctx: OpaquePointer?
    private let inSpec: LabSwrSpec
    private let outSpec: LabSwrSpec

    private static func avLayout(_ l: LabSwrLayout) -> AVChannelLayout {
        var out = AVChannelLayout()
        out.order = AV_CHANNEL_ORDER_NATIVE
        out.nb_channels = Int32(l.channels)
        out.u.mask = l.mask
        return out
    }

    public static func make(in inSpec: LabSwrSpec, out outSpec: LabSwrSpec) throws -> LabSwrBackend? {
        var inL = avLayout(inSpec.layout)
        var outL = avLayout(outSpec.layout)
        var ctx: OpaquePointer? = nil
        let arc = swr_alloc_set_opts2(&ctx, &outL, AVSampleFormat(rawValue: Int32(outSpec.fmt.rawValue)),
                                      Int32(outSpec.rate), &inL,
                                      AVSampleFormat(rawValue: Int32(inSpec.fmt.rawValue)),
                                      Int32(inSpec.rate), 0, nil)
        guard arc >= 0, ctx != nil else { return nil } // NOMEM
        let irc = swr_init(ctx)
        guard irc >= 0 else {
            swr_free(&ctx)
            throw LabSwrBackendError.initRefused
        }
        return GorAVSwrBackend(ctx: ctx, inSpec: inSpec, outSpec: outSpec)
    }

    private init(ctx: OpaquePointer?, inSpec: LabSwrSpec, outSpec: LabSwrSpec) {
        self.ctx = ctx
        self.inSpec = inSpec
        self.outSpec = outSpec
    }

    deinit {
        var c = ctx
        swr_free(&c)
        ctx = nil
    }

    public static func runtimeVersionMismatch() -> Bool {
        // gorav_l3_swresample_version() is the shim's wrapper over
        // swresample_version(); the macro is the build-time major.
        (gorav_l3_swresample_version() >> 16) & 0xFF != UInt32(LIBSWRESAMPLE_VERSION_MAJOR)
    }

    public static func depVersions() -> String {
        let v = gorav_l3_swresample_version()
        return "swresample \(v >> 16 & 0xFF).\(v >> 8 & 0xFF).\(v & 0xFF) (build major \(LIBSWRESAMPLE_VERSION_MAJOR))"
    }

    /// swr_close keeps the context's negotiated spec and drops buffered
    /// state; swr_init re-opens it. <0 = backend failure.
    public func reset() -> Int32 {
        guard ctx != nil else { return -1 }
        swr_close(ctx)
        return swr_init(ctx)
    }

    public func outSamples(_ n: Int32) -> Int32 {
        guard ctx != nil else { return -1 }
        return swr_get_out_samples(ctx, n)
    }

    public func delay(outRate: Int64) -> Int64 {
        guard ctx != nil else { return -1 }
        return swr_get_delay(ctx, outRate)
    }

    public func convert(out: [UnsafeMutablePointer<UInt8>?], cap: Int32,
                        inPlanes: [UnsafePointer<UInt8>?]?, n: Int32) -> Int32 {
        guard ctx != nil else { return -1 }
        var outArr = out
        return outArr.withUnsafeMutableBufferPointer { ob in
            if let inPlanes {
                var inArr = inPlanes
                return inArr.withUnsafeBufferPointer { ib in
                    swr_convert(ctx, ob.baseAddress, cap,
                                UnsafePointer(ib.baseAddress), n)
                }
            }
            return swr_convert(ctx, ob.baseAddress, cap, nil, 0)
        }
    }
}
