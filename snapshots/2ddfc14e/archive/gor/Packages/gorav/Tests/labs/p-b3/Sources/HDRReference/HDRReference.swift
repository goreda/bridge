import Foundation

// P-B3: HDR10 PQ/BT.2020 -> SDR BT.709 tone-map, scalar Double CPU reference.
// Clean-room implementation of the public contract in spec/SPEC.md.
// All transfer-function constants are published (SMPTE ST 2084-2014 / ITU-R
// BT.2100-2; ITU-R BT.709-6). The BT.2020 -> BT.709 matrix constants are
// derived at full double precision from the published BT.2020-2 and BT.709-6
// primaries with D65 white (see spec/SPEC.md section 4 and
// tools/generate_fixtures.py); they agree with the 4-decimal published
// conversion matrix in ITU-R BT.2407-0 section 2.2.

public struct RGB: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double
    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public protocol HDRReference {
    func map(pq2020: RGB, sourcePeakNits: Double, targetPeakNits: Double) throws -> RGB
}

public enum HDRReferenceError: Error, Equatable, Sendable {
    case nonFiniteInput
    case inputOutOfRange
    case invalidPeak
}

public struct ScalarHDRReference: HDRReference, Sendable {

    // SMPTE ST 2084-2014 / ITU-R BT.2100-2 Table 4.
    static let pqM1: Double = 2610.0 / 16384.0
    static let pqM2: Double = 2523.0 / 4096.0 * 128.0
    static let pqC1: Double = 3424.0 / 4096.0
    static let pqC2: Double = 2413.0 / 4096.0 * 32.0
    static let pqC3: Double = 2392.0 / 4096.0 * 32.0
    static let pqPeakNits: Double = 10000.0

    // BT.2020 luma coefficients, ITU-R BT.2100-2 (sum exactly 1.0).
    static let luma2020: (Double, Double, Double) = (0.2627, 0.6780, 0.0593)

    // BT.2020 -> BT.709 linear-light matrix, derived from published primaries
    // (ITU-R BT.2020-2, ITU-R BT.709-6, D65) via the standard RGB->XYZ /
    // XYZ->RGB construction. Row sums are 1 within 1e-15, which is what makes
    // neutral inputs map to neutral outputs within 1e-6. Matches the published
    // 4-decimal matrix in ITU-R BT.2407-0 section 2.2.
    static let m2020to709: [[Double]] = [
        [1.6604910021084338, -0.58764113878854973, -0.072849863319884856],
        [-0.12455047452159063, 1.1328998971259601, -0.0083494226043694872],
        [-0.018150763354905213, -0.10057889800800743, 1.1187296613629127],
    ]

    public init() {}

    /// ST 2084 inverse OETF ("PQ EOTF"): encoded signal [0,1] -> nits.
    public static func pqEOTF(_ n: Double) -> Double {
        let nc = min(1.0, max(0.0, n))
        let p = pow(nc, 1.0 / pqM2)
        let num = max(p - pqC1, 0.0)
        let den = pqC2 - pqC3 * p
        return pqPeakNits * pow(num / den, 1.0 / pqM1)
    }

    /// ST 2084 OETF ("inverse PQ"): nits -> encoded signal [0,1].
    public static func pqOETFInverse(_ nits: Double) -> Double {
        let y = min(1.0, max(0.0, nits / pqPeakNits))
        let ym1 = pow(y, pqM1)
        return pow((pqC1 + pqC2 * ym1) / (1.0 + pqC3 * ym1), pqM2)
    }

    /// ITU-R BT.709-6 OETF: linear [0,1] -> encoded [0,1].
    public static func bt709OETF(_ l: Double) -> Double {
        if l < 0.018 {
            return 4.5 * l
        }
        return 1.099 * pow(l, 0.45) - 0.099
    }

    /// Map one PQ-encoded BT.2020 pixel to encoded BT.709 SDR.
    ///
    /// Pipeline (spec/SPEC.md section 3):
    /// 1. ST 2084 decode to absolute nits (BT.2020 linear RGB).
    /// 2. Luminance with BT.2020 coefficients, normalize by source peak.
    /// 3. Reinhard (2002) tone curve L/(1+L), rescale to target peak.
    /// 4. Proportional RGB scale (hue/saturation preserving).
    /// 5. Linear matrix BT.2020 -> BT.709, normalize by target peak,
    ///    hard clip [0,1] per the BT.2407-0 simple conversion.
    /// 6. BT.709-6 OETF encode.
    public func map(pq2020: RGB, sourcePeakNits: Double, targetPeakNits: Double) throws -> RGB {
        let inputs = [pq2020.r, pq2020.g, pq2020.b]
        guard inputs.allSatisfy({ $0.isFinite }),
              sourcePeakNits.isFinite, targetPeakNits.isFinite else {
            throw HDRReferenceError.nonFiniteInput
        }
        guard sourcePeakNits > 0.0, targetPeakNits > 0.0 else {
            throw HDRReferenceError.invalidPeak
        }
        guard inputs.allSatisfy({ $0 >= 0.0 && $0 <= 1.0 }) else {
            throw HDRReferenceError.inputOutOfRange
        }

        let lr = Self.pqEOTF(pq2020.r)
        let lg = Self.pqEOTF(pq2020.g)
        let lb = Self.pqEOTF(pq2020.b)

        let y = Self.luma2020.0 * lr + Self.luma2020.1 * lg + Self.luma2020.2 * lb
        let yn = y / sourcePeakNits
        let yt = yn / (1.0 + yn) // Reinhard 2002 global operator
        let lt = yt * targetPeakNits
        let s = y > 0.0 ? lt / y : 0.0

        let mr = lr * s
        let mg = lg * s
        let mb = lb * s

        var out = [Double](repeating: 0.0, count: 3)
        for row in 0..<3 {
            let c = Self.m2020to709[row][0] * mr
                + Self.m2020to709[row][1] * mg
                + Self.m2020to709[row][2] * mb
            var v = c / targetPeakNits
            v = min(1.0, max(0.0, v)) // hard clip, BT.2407-0 simple conversion
            out[row] = Self.bt709OETF(v)
        }
        return RGB(r: out[0], g: out[1], b: out[2])
    }
}
