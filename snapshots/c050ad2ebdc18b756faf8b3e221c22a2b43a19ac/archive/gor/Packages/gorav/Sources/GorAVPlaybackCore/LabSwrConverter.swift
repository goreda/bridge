// Lab streaming audio converter (G0740 / 195b-N9, lab: 1nstinct), additive
// consumer seam: line-faithful Swift port of kits/n9-swr/v3/swc.c v3 - the
// converter STATE MACHINE on top of a libswresample backend: bounded
// timestamp math, int cap checks, zero-input contract, reset error
// propagation, generation/stale/flush semantics, format/layout negotiation.
// The DSP itself stays in real libswresample (v1 own-resampler was REJECTED
// by the lab; the port deliberately does not reimplement resampling): the
// backend is a protocol bound at integration. Parity harness in the kit
// binds this port and the C carrier to the same pinned FFmpeg 7.1 static
// libs (libswresample 5.3.100, libavutil 59.39.100) and diffs full
// behaviour incl. output sample hashes.
// Pinned-7.1 rerun of the lab suite: byte-identical to saved test_output.txt
// (checks 813 failed 0). Mac/Metal NOT_TESTED.

import Foundation

public enum LabSwrCode: Int {
    case ok = 0, arg = -1, nomem = -2, nospc = -3, unsupported = -4
    case stale = -5, version = -6, swr = -7, flushed = -8, range = -9
}

/// AVSampleFormat values mirrored exactly (U8=0..DBLP=9).
public enum LabSwrFmt: Int {
    case u8 = 0, s16 = 1, s32 = 2, flt = 3, dbl = 4
    case u8p = 5, s16p = 6, s32p = 7, fltp = 8, dblp = 9
    public var isPlanar: Bool { rawValue >= 5 }
    public var bytesPerSample: Int {
        switch self {
        case .u8, .u8p: return 1
        case .s16, .s16p: return 2
        case .s32, .s32p, .flt, .fltp: return 4
        case .dbl, .dblp: return 8
        }
    }
    /// av_get_alt_sample_fmt(f, planar): same bit-depth class, other packing.
    public var altPacking: LabSwrFmt {
        isPlanar ? LabSwrFmt(rawValue: rawValue - 5)! : LabSwrFmt(rawValue: rawValue + 5)!
    }
}

/// Native-order channel layout (mask + count), mirroring AVChannelLayout
/// ORDER_NATIVE for the masks libswresample accepts here.
public struct LabSwrLayout: Equatable {
    public let channels: Int
    public let mask: UInt64
    public init(_ channels: Int, _ mask: UInt64) { self.channels = channels; self.mask = mask }
    public static let mono = LabSwrLayout(1, 0x4)
    public static let stereo = LabSwrLayout(2, 0x3)
    public static let fiveOne = LabSwrLayout(6, 0x3F)
}

public struct LabSwrSpec {
    public var rate: Int
    public var fmt: LabSwrFmt
    public var layout: LabSwrLayout
    public init(rate: Int, fmt: LabSwrFmt, layout: LabSwrLayout) {
        self.rate = rate; self.fmt = fmt; self.layout = layout
    }
}

/// The libswresample boundary. Implementations wrap SwrContext; the product
/// seam never reimplements resampling.
public protocol LabSwrBackend: AnyObject {
    /// nil = allocation failure (NOMEM); throws unsupported = swr_init refused.
    static func make(in inSpec: LabSwrSpec, out outSpec: LabSwrSpec) throws -> LabSwrBackend?
    /// True when the runtime library major differs from the build major (VERSION).
    static func runtimeVersionMismatch() -> Bool
    static func depVersions() -> String
    func reset() -> Int32              // 0 ok, <0 backend failure (swr_init)
    func outSamples(_ n: Int32) -> Int32  // swr_get_out_samples; <0 backend failure
    func delay(outRate: Int64) -> Int64
    /// Returns frames written, or a negative number on backend failure.
    func convert(out: [UnsafeMutablePointer<UInt8>?], cap: Int32,
                 inPlanes: [UnsafePointer<UInt8>?]?, n: Int32) -> Int32
}

public final class LabSwrConverter {
    public static let rateMax = 1 << 20
    public static let ptsMax: Int64 = 1 << 40
    public static let framesMax: UInt64 = 1 << 40
    public static let nopts = Int64.min
    public static let fDiscont = 1

    public let inSpec: LabSwrSpec
    public let outSpec: LabSwrSpec
    private var backend: LabSwrBackend
    public private(set) var generation: UInt32 = 0
    private var ptsValid = false
    private var inPts0: Int64 = 0, outPts0: Int64 = 0
    private var T: UInt64 = 0, K: UInt64 = 0   // frames in / out since reset
    private var flushed = false, broken = false

    /// Mirrors swc_create: argument validation, version gate, backend open.
    public static func create<B: LabSwrBackend>(in inSpec: LabSwrSpec?, out outSpec: LabSwrSpec?,
                                                backend: B.Type) -> (LabSwrConverter?, LabSwrCode) {
        guard let i = inSpec, let o = outSpec,
              i.rate > 0, o.rate > 0, i.rate <= rateMax, o.rate <= rateMax,
              i.layout.channels > 0, o.layout.channels > 0 else { return (nil, .arg) }
        if B.runtimeVersionMismatch() { return (nil, .version) }
        let be: LabSwrBackend?
        do { be = try B.make(in: i, out: o) } catch { return (nil, .unsupported) }
        guard let be = be else { return (nil, .nomem) }
        return (LabSwrConverter(inSpec: i, outSpec: o, backend: be), .ok)
    }

    private init(inSpec: LabSwrSpec, outSpec: LabSwrSpec, backend: LabSwrBackend) {
        self.inSpec = inSpec; self.outSpec = outSpec; self.backend = backend
    }

    /// Drop buffered audio + timing. On backend init failure the object is
    /// broken and refuses use until a successful reset (SWC_ERR_SWR).
    @discardableResult
    public func reset() -> LabSwrCode {
        let r = backend.reset()
        ptsValid = false; inPts0 = 0; outPts0 = 0; T = 0; K = 0; flushed = false
        if r < 0 { broken = true; return .swr }
        broken = false; return .ok
    }

    /// New generation => reset, no flush.
    @discardableResult
    public func setGeneration(_ gen: UInt32) -> LabSwrCode {
        if gen != generation {
            let r = reset()
            if r != .ok { return r }
            generation = gen
        }
        return .ok
    }

    /// >= frames a convert may write; SWC_ERR_ARG for out-of-contract n.
    public func maxOut(_ n: Int64) -> Int64 {
        if n < 0 || n > Int64(Int32.max / 2) { return Int64(LabSwrCode.arg.rawValue) }
        let r = backend.outSamples(Int32(n))
        return r < 0 ? Int64(LabSwrCode.swr.rawValue) : Int64(r)
    }

    public func getDelay() -> Int64 { backend.delay(outRate: Int64(outSpec.rate)) }

    public func maxFlush() -> Int64 {
        let r = backend.outSamples(0)
        return r < 0 ? 0 : Int64(r)
    }

    /// av_rescale_rnd(a, b, c, AV_ROUND_NEAR_INF): (a*b + c/2)/c, half away
    /// from zero, exact 128-bit intermediate.
    static func rescaleNearInf(_ a: Int64, _ b: Int64, _ c: Int64) -> Int64 {
        let neg = (a < 0) != (b < 0)
        let ua = UInt64(bitPattern: a < 0 ? (a == Int64.min ? a : -a) : a)
        let ub = UInt64(bitPattern: b < 0 ? -b : b)
        let (hi, lo) = ua.multipliedFullWidth(by: ub)
        // 128-bit add of c/2 (c > 0 here by contract: rates in 1..2^20)
        let half = UInt64(c / 2)
        let rLo = lo &+ half
        var rHi = hi
        if rLo < lo { rHi &+= 1 }
        // divide 128-bit (rHi:rLo) by c
        let qHi = rHi / UInt64(c)
        let remHi = rHi % UInt64(c)
        let (qLo, _) = UInt64(c).dividingFullWidth((remHi, rLo))
        let q = qHi &* (UInt64.max &+ 1) &+ qLo // = qHi*2^64 + qLo (fits by contract bounds)
        return Int64(bitPattern: neg ? 0 &- q : q)
    }

    public struct ConvertOut {
        public var outN: Int64 = 0
        public var outPts: Int64 = LabSwrConverter.nopts
        public var flags: Int = 0
        /// Public zero init so product consumers outside this module (the
        /// lane-(c) live-path wiring) can declare a result slot. Semantics
        /// unchanged: convert/flush always reset the slot before writing.
        public init() {}
    }

    /// Mirrors swc_convert incl. argument/bounds order, generation adoption,
    /// zero-input no-op contract, discontinuity flagging and pts emission.
    @discardableResult
    public func convert(gen: UInt32, inPlanes: [UnsafePointer<UInt8>?]?, n: Int64, inPts: Int64,
                        out: [UnsafeMutablePointer<UInt8>?]?, cap: Int64, result: inout ConvertOut) -> LabSwrCode {
        result = ConvertOut()
        if n < 0 || n > Int64(Int32.max / 2) || cap < 0 || cap > Int64(Int32.max)
            || (n > 0 && inPlanes == nil) || (cap > 0 && out == nil) { return .arg }
        if broken { return .swr }
        if gen < generation { return .stale }
        let gr = setGeneration(gen)
        if gr != .ok { return gr }
        if flushed { return .flushed }
        // zero-input contract: n==0 is a no-op (in may be nil): no swr call,
        // no drain, no state/pts change. Draining only via flush.
        if n == 0 { return .ok }
        if T + UInt64(n) > LabSwrConverter.framesMax { return .range }
        if inPts != LabSwrConverter.nopts && (inPts > LabSwrConverter.ptsMax || inPts < -LabSwrConverter.ptsMax) { return .range }
        if cap < maxOut(n) { return .nospc }
        if inPts != LabSwrConverter.nopts {
            if !ptsValid && T == 0 {
                ptsValid = true; inPts0 = inPts
                outPts0 = LabSwrConverter.rescaleNearInf(inPts, Int64(outSpec.rate), Int64(inSpec.rate)) // |.|<=2^60
            } else if ptsValid {
                var d = inPts - (inPts0 + Int64(T)) // all terms <= 2^41
                if d < 0 { d = -d }
                if d > 1 { result.flags |= LabSwrConverter.fDiscont }
            }
        }
        let K0 = K
        let r = backend.convert(out: out ?? [], cap: Int32(cap), inPlanes: inPlanes, n: Int32(n))
        if r < 0 { return .swr }
        T += UInt64(n); K += UInt64(r)
        result.outN = Int64(r)
        if r > 0 && ptsValid { result.outPts = outPts0 + Int64(K0) } // <=2^60+2^60
        return .ok
    }

    /// Mirrors swc_flush: only draining path; sets flushed, single-shot.
    @discardableResult
    public func flush(out: [UnsafeMutablePointer<UInt8>?]?, cap: Int64, result: inout ConvertOut) -> LabSwrCode {
        result = ConvertOut()
        if cap < 0 || cap > Int64(Int32.max) || (cap > 0 && out == nil) { return .arg }
        if broken { return .swr }
        if flushed { return .flushed }
        if cap < maxFlush() { return .nospc }
        let K0 = K
        let r = backend.convert(out: out ?? [], cap: Int32(cap), inPlanes: nil, n: 0)
        if r < 0 { return .swr }
        K += UInt64(r)
        result.outN = Int64(r)
        flushed = true
        if r > 0 && ptsValid { result.outPts = outPts0 + Int64(K0) }
        return .ok
    }

    // MARK: negotiation

    /// swc_negotiate_fmt: exact; else same-bit-depth other packing; else
    /// FLT/FLTP; else first entry.
    public static func negotiateFmt(_ inFmt: LabSwrFmt, ok: [LabSwrFmt]) -> Int {
        if ok.isEmpty { return LabSwrCode.arg.rawValue }
        for (k, f) in ok.enumerated() where f == inFmt { return k }
        let p = inFmt.altPacking
        for (k, f) in ok.enumerated() where f == p { return k }
        for (k, f) in ok.enumerated() where f == .flt || f == .fltp { return k }
        return 0
    }

    /// swc_negotiate_layout: exact (mask+count); else first entry the backend
    /// accepts, probed by the caller (swr_alloc_set_opts2 + swr_init).
    public static func negotiateLayout(_ inLay: LabSwrLayout, ok: [LabSwrLayout],
                                       probe: (LabSwrLayout) -> Bool) -> Int {
        if ok.isEmpty { return LabSwrCode.arg.rawValue }
        for (k, l) in ok.enumerated() where l == inLay { return k }
        for (k, l) in ok.enumerated() where probe(l) { return k }
        return LabSwrCode.unsupported.rawValue
    }
}
