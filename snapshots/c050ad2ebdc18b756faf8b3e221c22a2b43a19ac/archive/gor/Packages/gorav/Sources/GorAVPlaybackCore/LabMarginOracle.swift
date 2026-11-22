// Lab margin oracle (G0733 / 195a-N02, lab: 1nstinct), additive consumer
// seam: line-faithful Swift port of kits/n2-margin/oracle.py v1.1.0 - CPU
// BT.2124-0 PQ dE-ITP + BT.2020 code-luma PSNR margin oracle over .rgbf
// frames. Corrected v1.1.0 semantics only: Ct half-weight (T = 0.5*CT) and
// LMS S row (99R + 309G + 3688B)/4096; the preserved v1.0.0 wrong-spec copy
// stays vendored in the kit as evidence, not ported. BT.709 rejected,
// fixed BT.2020 transform. Python<->Swift parity harness in kit: 9
// conformance compare cases + 20 analytic selftest vectors byte-identical.
// Thresholds (mean <= 1.0, p99 <= 3.0, PSNR >= 40 dB) are packet criteria,
// not product acceptance. Mac/Metal NOT_TESTED.

import Foundation

public enum LabMargin {
    public static let oracleVersion = "d11-margin-oracle 1.1.0"

    public static let meanDeitpMax = 1.0
    public static let p99DeitpMax = 3.0
    public static let lumaPsnrMinDb = 40.0

    // ST 2084:2014 constants
    static let m1 = 2610.0 / 16384.0
    static let m2 = (2523.0 / 4096.0) * 128.0
    static let c1 = 3424.0 / 4096.0
    static let c2 = (2413.0 / 4096.0) * 32.0
    static let c3 = (2392.0 / 4096.0) * 32.0

    public static let kr = 0.2627, kg = 0.6780, kb = 0.0593

    // BT.2020 -> LMS, ITU-R BT.2124-0 Annex 1 step 1 (integer numerators, /4096)
    static let rgbToLmsNum: [[Double]] = [
        [1688, 2146, 262],
        [683, 2951, 462],
        [99, 309, 3688],
    ]

    // ICtCp XYZ -> LMS matrix (Dolby derivation); used only by the selftest's
    // first-principles re-derivation of rgbToLmsNum.
    static let xyzToLms: [[Double]] = [
        [0.3592832590121217, 0.6976051147779502, -0.0358915932320290],
        [-0.1920808463704996, 1.1004767970374321, 0.0753748658519118],
        [0.0070797844607479, 0.0748396662186362, 0.8433265453898765],
    ]

    static let allowedBitdepths: Set<Int> = [8, 10, 12, 16]
    static let allowedPrimaries: Set<String> = ["BT2020"]  // fixed BT.2020; BT.709 rejected
    static let allowedTransfers: Set<String> = ["PQ"]
    static let allowedRanges: Set<String> = ["full", "narrow"]

    public struct FrameError: Error, CustomStringConvertible {
        public let message: String
        public var description: String { message }
        public init(_ m: String) { message = m }
    }

    /// ST 2084 EOTF: normalized code value [0,1] -> normalized linear luminance (1.0 = 10000 cd/m^2).
    public static func pqEotf(_ vIn: Double) -> Double {
        let v = min(max(vIn, 0.0), 1.0)
        let p = pow(v, 1.0 / m2)
        let num = max(p - c1, 0.0)
        let den = c2 - c3 * p
        return pow(num / den, 1.0 / m1)
    }

    /// ST 2084 inverse EOTF (OETF): normalized linear luminance -> normalized code value.
    public static func pqOetf(_ yIn: Double) -> Double {
        let y = min(max(yIn, 0.0), 1.0)
        let p = pow(y, m1)
        return pow((c1 + c2 * p) / (1.0 + c3 * p), m2)
    }

    /// Display-referred linear BT.2020 RGB -> LMS, BT.2124-0 Annex 1 step 1.
    public static func lmsFromLinear(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let n = rgbToLmsNum
        return ((n[0][0] * r + n[0][1] * g + n[0][2] * b) / 4096.0,
                (n[1][0] * r + n[1][1] * g + n[1][2] * b) / 4096.0,
                (n[2][0] * r + n[2][1] * g + n[2][2] * b) / 4096.0)
    }

    /// ICtCp from normalized PQ-encoded BT.2020 R'G'B' code values.
    public static func ictcpFromPqCodes(_ rp: Double, _ gp: Double, _ bp: Double) -> (Double, Double, Double) {
        let (l, m, s) = lmsFromLinear(pqEotf(rp), pqEotf(gp), pqEotf(bp))
        let lp = pqOetf(l), mp = pqOetf(m), sp = pqOetf(s)
        let i = 0.5 * lp + 0.5 * mp
        let ct = (6610.0 * lp - 13613.0 * mp + 7003.0 * sp) / 4096.0
        let cp = (17933.0 * lp - 17390.0 * mp - 543.0 * sp) / 4096.0
        return (i, ct, cp)
    }

    /// ITU-R BT.2124-0 delta-E ITP. T axis (Ct) half-scaled (Annex 1 step 4):
    /// dE_ITP = 720*sqrt(dI^2 + 0.25*dCt^2 + dCp^2).
    public static func deItp(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let di = a.0 - b.0, dct = a.1 - b.1, dcp = a.2 - b.2
        return 720.0 * (di * di + 0.25 * dct * dct + dcp * dcp).squareRoot()
    }

    public struct Frame {
        public var meta: [String: String] = [:]
        public var vals: [UInt16] = []
        public var w = 0, h = 0, bd = 0
    }

    /// .rgbf reader: ASCII key=value header terminated by "end", then
    /// width*height*3 uint16 little-endian code values.
    public static func readFrame(_ path: String) throws -> Frame {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var lines: [String] = []
        var idx = data.startIndex
        while true {
            guard let nl = data[idx...].firstIndex(of: 0x0a) else {
                throw FrameError("truncated header: no 'end' terminator")
            }
            let lineData = data[idx..<nl]
            guard let line = String(data: lineData, encoding: .ascii) else {
                throw FrameError("malformed header line")
            }
            idx = nl + 1
            if line == "end" { break }
            lines.append(line)
            if lines.count > 32 { throw FrameError("header too long") }
        }
        guard !lines.isEmpty, lines[0] == "RGBF1" else {
            throw FrameError("bad magic: not an RGBF1 frame")
        }
        var meta: [String: String] = [:]
        for ln in lines.dropFirst() {
            guard let eq = ln.firstIndex(of: "=") else {
                throw FrameError("malformed header line: \(ln)")
            }
            let k = String(ln[..<eq]), v = String(ln[ln.index(after: eq)...])
            if k.isEmpty || v.isEmpty { throw FrameError("malformed header line: \(ln)") }
            meta[k] = v
        }
        for k in ["width", "height", "bitdepth", "primaries", "transfer", "range"] {
            if meta[k] == nil { throw FrameError("missing header field: \(k)") }
        }
        guard let w = Int(meta["width"]!), let h = Int(meta["height"]!), let bd = Int(meta["bitdepth"]!) else {
            throw FrameError("non-integer width/height/bitdepth")
        }
        if w <= 0 || h <= 0 { throw FrameError("non-positive dimensions") }
        if !allowedBitdepths.contains(bd) { throw FrameError("unsupported bitdepth: \(bd)") }
        if !allowedPrimaries.contains(meta["primaries"]!) {
            throw FrameError("unsupported primaries for fixed BT.2020 transform: \(meta["primaries"]!)")
        }
        if !allowedTransfers.contains(meta["transfer"]!) {
            throw FrameError("unsupported transfer for this oracle: \(meta["transfer"]!)")
        }
        if !allowedRanges.contains(meta["range"]!) { throw FrameError("unsupported range: \(meta["range"]!)") }
        let n = w * h * 3
        let body = data[idx...]
        if body.count < 2 * n {
            throw FrameError("missing pixel values: payload truncated (\(body.count) of \(2 * n) bytes)")
        }
        if body.count > 2 * n {
            throw FrameError("trailing bytes after payload (\(body.count - 2 * n) extra)")
        }
        var vals: [UInt16] = []
        vals.reserveCapacity(n)
        body.withUnsafeBytes { p in
            for i in 0..<n { vals.append(UInt16(littleEndian: p.load(fromByteOffset: 2 * i, as: UInt16.self))) }
        }
        let maxcv = UInt16((1 << bd) - 1)
        for v in vals where v > maxcv {
            throw FrameError("code value \(v) exceeds \(bd)-bit range")
        }
        return Frame(meta: meta, vals: vals, w: w, h: h, bd: bd)
    }

    /// Code value -> normalized signal [0,1] for declared range.
    public static func normalize(_ cv: UInt16, _ bd: Int, _ rng: String) -> Double {
        if rng == "full" { return Double(cv) / Double((1 << bd) - 1) }
        let scale = 1 << (bd - 8)
        let black = 16 * scale
        let white = 235 * scale
        let v = (Double(cv) - Double(black)) / Double(white - black)
        return min(max(v, 0.0), 1.0)
    }

    public struct CompareResult {
        public var exit = 0
        public var verdict = ""
        public var reason: String? = nil
        public var pixels = 0
        public var size = ""
        public var bitdepth = 0
        public var primaries = ""
        public var transfer = ""
        public var range = ""
        public var meanDeitp = 0.0
        public var p99Deitp = 0.0
        public var maxDeitp = 0.0
        public var lumaPsnrDb: Double? = nil  // nil renders as "inf"
        public var checks: (mean: Bool, p99: Bool, psnr: Bool) = (false, false, false)
    }

    /// Python round(x, nd): round-half-even on the decimal-scaled value.
    static func pyRound(_ x: Double, _ nd: Int) -> Double {
        let f = pow(10.0, Double(nd))
        return (x * f).rounded(.toNearestOrEven) / f
    }

    public static func compare(refPath: String, candPath: String) -> CompareResult {
        var out = CompareResult()
        let f1: Frame, f2: Frame
        do {
            f1 = try readFrame(refPath)
            f2 = try readFrame(candPath)
        } catch let e as FrameError {
            out.exit = 2; out.verdict = "REJECT"; out.reason = e.message
            return out
        } catch {
            out.exit = 2; out.verdict = "REJECT"; out.reason = "\(error)"
            return out
        }
        for (k, a, b) in [("_w", "\(f1.w)", "\(f2.w)"), ("_h", "\(f1.h)", "\(f2.h)"), ("_bd", "\(f1.bd)", "\(f2.bd)")] where a != b {
            out.exit = 2; out.verdict = "REJECT"
            out.reason = "mismatched sizes/bitdepth: \(k) \(a) vs \(b)"
            return out
        }
        for k in ["primaries", "transfer", "range"] where f1.meta[k] != f2.meta[k] {
            out.exit = 2; out.verdict = "REJECT"
            out.reason = "mismatched color metadata: \(k) \(f1.meta[k] ?? "") vs \(f2.meta[k] ?? "")"
            return out
        }
        let bd = f1.bd, rng = f1.meta["range"]!
        let npix = f1.w * f1.h
        var des: [Double] = []
        des.reserveCapacity(npix)
        var mseY = 0.0
        for p in 0..<npix {
            let r1 = normalize(f1.vals[3 * p], bd, rng)
            let g1 = normalize(f1.vals[3 * p + 1], bd, rng)
            let b1 = normalize(f1.vals[3 * p + 2], bd, rng)
            let r2 = normalize(f2.vals[3 * p], bd, rng)
            let g2 = normalize(f2.vals[3 * p + 1], bd, rng)
            let b2 = normalize(f2.vals[3 * p + 2], bd, rng)
            des.append(deItp(ictcpFromPqCodes(r1, g1, b1), ictcpFromPqCodes(r2, g2, b2)))
            let y1 = kr * r1 + kg * g1 + kb * b1
            let y2 = kr * r2 + kg * g2 + kb * b2
            let d = y1 - y2
            mseY += d * d
        }
        mseY /= Double(npix)
        des.sort()
        let p99 = des[min(Int((0.99 * Double(npix)).rounded(.up)) - 1, npix - 1)]
        let meanDe = des.reduce(0, +) / Double(npix)
        let psnr = mseY == 0.0 ? Double.infinity : 10.0 * log10(1.0 / mseY)
        let checks = (mean: meanDe <= meanDeitpMax, p99: p99 <= p99DeitpMax, psnr: psnr >= lumaPsnrMinDb)
        out.checks = checks
        out.verdict = (checks.mean && checks.p99 && checks.psnr) ? "PASS" : "FAIL"
        out.exit = out.verdict == "PASS" ? 0 : 1
        out.pixels = npix
        out.size = "\(f1.w)x\(f1.h)"
        out.bitdepth = bd
        out.primaries = f1.meta["primaries"]!
        out.transfer = f1.meta["transfer"]!
        out.range = rng
        out.meanDeitp = pyRound(meanDe, 6)
        out.p99Deitp = pyRound(p99, 6)
        out.maxDeitp = pyRound(des.last!, 6)
        out.lumaPsnrDb = psnr.isInfinite ? nil : pyRound(psnr, 3)
        return out
    }

    // MARK: selftest (analytic + independent vectors)

    static func bt2020RgbToXyz() -> [[Double]] {
        let prim = [(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)]
        let xw = 0.3127, yw = 0.3290
        let cols = prim.map { (x: $0.0 / $0.1, y: 1.0, z: (1.0 - $0.0 - $0.1) / $0.1) }
        let w = (xw / yw, 1.0, (1.0 - xw - yw) / yw)
        func det3(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let m = [[cols[0].x, cols[1].x, cols[2].x],
                 [cols[0].y, cols[1].y, cols[2].y],
                 [cols[0].z, cols[1].z, cols[2].z]]
        let d = det3(m)
        var s: [Double] = []
        for i in 0..<3 {
            var mi = m
            mi[0][i] = w.0; mi[1][i] = w.1; mi[2][i] = w.2
            s.append(det3(mi) / d)
        }
        return (0..<3).map { r in (0..<3).map { c in m[r][c] * s[c] } }
    }

    /// Returns the exact python selftest output lines and exit code.
    public static func selftest() -> (lines: [String], exit: Int) {
        var checks: [(String, Bool, Double, Double)] = []
        func add(_ name: String, _ got: Double, _ want: Double, _ tol: Double) {
            checks.append((name, abs(got - want) <= tol, got, want))
        }
        add("de_itp dI=0.01 -> 7.2 (I full weight)",
            deItp((0.5, 0.0, 0.0), (0.51, 0.0, 0.0)), 7.2, 1e-9)
        add("de_itp dCt=0.01 -> 3.6 (Ct half-scaled)",
            deItp((0.5, 0.0, 0.0), (0.5, 0.01, 0.0)), 3.6, 1e-9)
        add("de_itp dCp=0.01 -> 7.2 (Cp full weight)",
            deItp((0.5, 0.0, 0.0), (0.5, 0.0, 0.01)), 7.2, 1e-9)
        add("de_itp dI=dCt=dCp=0.01 -> 10.8",
            deItp((0.5, 0.0, 0.0), (0.51, 0.01, 0.01)), 10.8, 1e-9)
        add("de_itp identical -> 0",
            deItp((0.4, -0.1, 0.2), (0.4, -0.1, 0.2)), 0.0, 0.0)
        add("colour-science doctest vector -> 1.4265722",
            deItp((0.4885468072, -0.04739350675, 0.07475401302),
                  (0.4899203231, -0.04567508203, 0.07361341775)),
            1.4265722, 1e-6)
        let (l, m, s) = lmsFromLinear(0.1, 0.2, 0.3)
        add("LMS L for (0.1,0.2,0.3)", l, 676.6 / 4096.0, 1e-12)
        add("LMS M for (0.1,0.2,0.3)", m, 797.1 / 4096.0, 1e-12)
        add("LMS S for (0.1,0.2,0.3)", s, 1178.1 / 4096.0, 1e-12)
        let rgb2xyz = bt2020RgbToXyz()
        for i in 0..<3 {
            for j in 0..<3 {
                let v = (0..<3).reduce(0.0) { $0 + xyzToLms[i][$1] * rgb2xyz[$1][j] } * 4096.0
                add("derived RGB->LMS numerator [\(i)][\(j)]", v, rgbToLmsNum[i][j], 0.5)
            }
        }
        add("PQ EOTF(0.5) ~ 92.2457 nits", pqEotf(0.5) * 10000.0, 92.2457, 1e-3)
        add("PQ round-trip at 0.37", pqOetf(pqEotf(0.37)), 0.37, 1e-12)
        let failed = checks.filter { !$0.1 }
        var lines: [String] = []
        for (name, ok, got, want) in checks {
            lines.append(String(format: "%@ %@ (got %.12g, want %.12g)", ok ? "PASS" : "FAIL", name, got, want))
        }
        lines.append("selftest: \(checks.count - failed.count)/\(checks.count) vectors pass")
        return (lines, failed.isEmpty ? 0 : 1)
    }
}
