// Lab crop engine (G0736 / 195b-N10, lab: 1nstinct): multi-pixfmt luma
// extraction + temporal stabilizer, additive consumer seam behind the pinned
// TapCropDetector surface. Ported line-faithful from kits/n10-cropdetect
// (cropdetect.c, C99); the C reference with its own test suite stays vendored
// in kits/n10-cropdetect and is the executable witness. The pinned
// TapCropDetector/BorderScanConfig semantics are NOT changed by this file.
// Threshold mapping into the pinned surface: barMaxLuma <-> blackThreshold,
// sampleStride <-> sampleStep; the pinned mean/peak scan stays the acceptance
// vocabulary (W-gdb-045).

/// Pixel layouts the engine can sample luma from.
public enum LabCropPixelFormat: String, Equatable, Sendable {
    case gray8, yuv420p, nv12, rgb24, rgba, bgra
}

/// Video range of the incoming samples.
public enum LabCropRange: String, Equatable, Sendable {
    case limited, full
}

/// Engine parameters. Mirrors cd_params; validated by `isValid` (the C pbad
/// rule). Defaults follow the lab kit, not the pinned BorderScanConfig.
public struct LabCropParams: Equatable, Sendable {
    public var blackThreshold = 16        // luma (full-range units) <= this is black
    public var noisePixelsPctX100 = 50    // a line is content when bright pixels exceed this share (1/100 %)
    public var noisePixelsMin = 2         // ... and at least this many pixels
    public var align = 2                  // round rect outward to this multiple
    public var minW = 16, minH = 16       // smallest accepted crop
    public var histLen = 8                // stabilizer window in frames (<=64)
    public var shrinkHold = 8             // frames a tighter crop must persist
    public var sampleStep = 1             // examine every Nth line
    public init() {}
    public var isValid: Bool {
        blackThreshold >= 0 && blackThreshold <= 255 && align >= 1 && align <= 64
            && histLen >= 1 && histLen <= 64 && sampleStep >= 1
            && minW >= 1 && minH >= 1 && shrinkHold >= 0 && noisePixelsMin >= 0
            && noisePixelsPctX100 >= 0 && noisePixelsPctX100 <= 10000
    }
}

/// One frame for detection: plane pointers as byte arrays + byte strides.
/// Plane 0 is luma or packed; NV12 uses plane 1 for chroma (never read).
public struct LabCropFrame: Sendable {
    public let planes: [[UInt8]]
    public let strides: [Int]
    public let width: Int
    public let height: Int
    public let format: LabCropPixelFormat
    public let range: LabCropRange
    public static let maxDim = 32768
    public init?(planes: [[UInt8]], strides: [Int], width: Int, height: Int,
                 format: LabCropPixelFormat, range: LabCropRange) {
        guard !planes.isEmpty, strides.count >= planes.count,
              width > 0, height > 0, width <= Self.maxDim, height <= Self.maxDim
        else { return nil }
        let bpp = format == .rgb24 ? 3 : (format == .rgba || format == .bgra ? 4 : 1)
        guard strides[0] >= width * bpp else { return nil }
        // Every row the sampler can touch must be inside plane 0.
        guard planes[0].count >= strides[0] * (height - 1) + width * bpp else { return nil }
        self.planes = planes; self.strides = strides
        self.width = width; self.height = height
        self.format = format; self.range = range
    }
}

/// Pixel-space rectangle, same convention as the C cd_rect.
public struct LabCropRect: Equatable, Sendable {
    public var x = 0, y = 0, w = 0, h = 0
    public init() {}
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    public func contains(_ o: LabCropRect) -> Bool {
        x <= o.x && y <= o.y && x + w >= o.x + o.w && y + h >= o.y + o.h
    }
    public func union(_ o: LabCropRect) -> LabCropRect {
        let x0 = min(x, o.x), y0 = min(y, o.y)
        let x1 = max(x + w, o.x + o.w), y1 = max(y + h, o.y + o.h)
        return LabCropRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }
}

/// Per-frame result: raw detection + stabilized rect.
public struct LabCropResult: Equatable, Sendable {
    public var detected = LabCropRect()
    public var stable = LabCropRect()
    public var detectedValid = false   // false on an all-black/blank frame: detected = full frame, history unchanged
    public var stableChanged = false
    public init() {}
}

public enum LabCropEngine {
    /// BT.709 integer luma in full-range units at (x, y). Bounds are the
    /// caller's guarantee (the failable frame init enforces them).
    public static func luma(_ f: LabCropFrame, x: Int, y: Int) -> Int {
        let p0 = f.planes[0]
        let base = y * f.strides[0]
        switch f.format {
        case .gray8, .yuv420p, .nv12:
            var v = Int(p0[base + x])
            if f.range == .limited {
                v = (v - 16) * 255 / 219
                if v < 0 { v = 0 }; if v > 255 { v = 255 }
            }
            return v
        case .rgb24:
            let q = base + 3 * x
            return (54 * Int(p0[q]) + 183 * Int(p0[q + 1]) + 19 * Int(p0[q + 2]) + 128) >> 8
        case .rgba:
            let q = base + 4 * x
            return (54 * Int(p0[q]) + 183 * Int(p0[q + 1]) + 19 * Int(p0[q + 2]) + 128) >> 8
        case .bgra:
            let q = base + 4 * x
            return (54 * Int(p0[q + 2]) + 183 * Int(p0[q + 1]) + 19 * Int(p0[q]) + 128) >> 8
        }
    }

    static func isContent(_ count: Int, total: Int, _ p: LabCropParams) -> Bool {
        if count < p.noisePixelsMin || count == 0 { return false }
        return count * 10000 > p.noisePixelsPctX100 * total || p.noisePixelsPctX100 == 0
    }

    /// Stateless per-frame detection. nil on invalid input; otherwise the
    /// content rect plus a validity flag (blank frame -> full frame, false).
    public static func detect(_ f: LabCropFrame, params pp: LabCropParams = LabCropParams())
        -> (rect: LabCropRect, valid: Bool)? {
        guard pp.isValid else { return nil }
        let W = f.width, H = f.height, s = pp.sampleStep, T = pp.blackThreshold
        var top = -1, bot = -1, left = W, right = -1
        var col = [Int](repeating: 0, count: W)
        var nrows = 0
        var y = 0
        while y < H {
            var cnt = 0
            nrows += 1
            var x = 0
            while x < W {
                if luma(f, x: x, y: y) > T { cnt += 1; col[x] += 1 }
                x += 1
            }
            if isContent(cnt, total: W, pp) { if top < 0 { top = y }; bot = y }
            y += s
        }
        var x = 0
        while x < W {
            if isContent(col[x], total: nrows, pp) { if x < left { left = x }; right = x }
            x += 1
        }
        if top < 0 || right < 0 {
            return (LabCropRect(x: 0, y: 0, w: W, h: H), false)
        }
        bot += s - 1
        if bot >= H { bot = H - 1 }
        let a = pp.align
        var x0 = left, y0 = top, x1 = right + 1, y1 = bot + 1
        x0 -= x0 % a; y0 -= y0 % a               // expand outward so content is never cut
        x1 = (x1 + a - 1) / a * a; y1 = (y1 + a - 1) / a * a
        if x1 > W { x1 = W }; if y1 > H { y1 = H }
        if x1 - x0 < pp.minW { x0 = 0; x1 = W }
        if y1 - y0 < pp.minH { y0 = 0; y1 = H }
        return (LabCropRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0), true)
    }
}

/// Detect + temporal stabilizer (window union; grow at once; shrink only
/// after a tighter rect persists shrinkHold frames; geometry change or
/// reset() clears state). Value type: one engine per stream.
public struct LabCropStabilizer: Sendable {
    public private(set) var params: LabCropParams
    private var hist = [LabCropRect](repeating: LabCropRect(), count: 64)
    private var n = 0, head = 0
    private var stable = LabCropRect()
    private var have = false
    private var shrinkCount = 0
    private var pend = LabCropRect()
    private var fw = 0, fh = 0

    public init?(params: LabCropParams = LabCropParams()) {
        guard params.isValid else { return nil }
        self.params = params
    }

    /// Call on seek / generation change / format change.
    public mutating func reset() {
        let p = params
        self = LabCropStabilizer(params: p)!
    }

    public mutating func process(_ f: LabCropFrame) -> LabCropResult? {
        if have && (f.width != fw || f.height != fh) { reset() }
        fw = f.width; fh = f.height
        guard let det = LabCropEngine.detect(f, params: params) else { return nil }
        let full = LabCropRect(x: 0, y: 0, w: f.width, h: f.height)
        let prev = have ? stable : full
        var res = LabCropResult()
        res.detected = det.rect
        res.detectedValid = det.valid
        if det.valid {
            hist[head] = det.rect
            head = (head + 1) % params.histLen
            if n < params.histLen { n += 1 }
            var u = hist[(head + params.histLen - 1) % params.histLen]
            var i = 0
            while i < n { u = u.union(hist[i]); i += 1 }   // window union: never cuts recent content
            if !have {
                stable = u; have = true; shrinkCount = 0
            } else if !stable.contains(u) {
                stable = stable.union(u); shrinkCount = 0  // grow at once
            } else if stable != u {                        // shrink only if persistent
                if shrinkCount > 0 && pend == u { shrinkCount += 1 } else { pend = u; shrinkCount = 1 }
                if shrinkCount >= params.shrinkHold || params.shrinkHold == 0 { stable = u; shrinkCount = 0 }
            } else {
                shrinkCount = 0
            }
        }
        res.stable = have ? stable : full
        res.stableChanged = res.stable != prev
        return res
    }
}
