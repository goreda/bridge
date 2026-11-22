import Foundation

/// DR-0017: P22 layout extension for the measured photon source statistics.
/// The first 64 bytes mirror the GPU measurement ticket wire exactly
/// (sigma: 8 x Float32 little-endian @0, counts: 8 x UInt32 little-endian @32);
/// a validity mask word and a zero reserved word follow. One declared layout is
/// the single source of truth for the Swift consumer, the MSL apply kernel and
/// the Linux witness - no guessed P22 offsets anywhere.
///
/// Semantics (lane b stock-field constraints, measured 36-combo proof):
/// - A bin is SUPPORTED iff counts[i] >= 32 and sigma[i] is finite and >= 0.
///   Zero-count/under-count bins are MISSING data, never zero grain: the mask
///   bit stays clear and interpolation skips the bin.
/// - sourceCellPixels is NEVER synthesized from residual sigma; it stays nil
///   until a validated spatial-fit estimator exists (NEXT-GATES gate 2).
/// - Interpolation uses supported bins only, with knots at the bin centers
///   (i+0.5)/8, clamping to the nearest supported value outside the range.
public enum PhotonMeasurementP22 {
    public static let binCount = 8
    /// Byte count of the GPU stats ticket wire this layout extends.
    public static let statsWireBytes = 64
    public static let sigmaByteOffset = 0
    public static let countsByteOffset = 32
    public static let maskByteOffset = 64
    public static let reservedByteOffset = 68
    public static let extensionBytes = 72
    /// Minimum samples for a bin to count as measured (matches the reduce
    /// kernel's sigma=0-below-32 rule; the mask makes that rule explicit).
    public static let minimumBinCount = 32

    public enum MeasurementError: Error, Equatable, Sendable {
        case invalidBins
        case noSupportedBins
        case nonFiniteLevel
    }

    /// Bin i covers the signal range [i/8, (i+1)/8); supported knots sit at
    /// the centers, (i+0.5)/8.
    public static func binCenter(_ i: Int) -> Double { (Double(i) + 0.5) / Double(binCount) }

    public static func isSupported(sigma: Double, count: Int) -> Bool {
        sigma.isFinite && sigma >= 0 && count >= minimumBinCount
    }

    /// Validity mask: bit i set iff bin i is supported.
    public static func mask(sigma: [Double], counts: [Int]) -> UInt32 {
        guard sigma.count == binCount, counts.count == binCount else { return 0 }
        var m: UInt32 = 0
        for i in 0..<binCount where isSupported(sigma: sigma[i], count: counts[i]) { m |= UInt32(1) << UInt32(i) }
        return m
    }

    /// The exact 72 extension bytes (little-endian) the apply kernel must
    /// produce: sigma words, count words, mask word, zero reserved word.
    /// Unsupported bins write sigma 0 with a clear mask bit - the count word
    /// always carries the measured count for telemetry.
    public static func packExtensionBytes(sigma: [Double], counts: [Int]) -> [UInt8] {
        guard sigma.count == binCount, counts.count == binCount else { return [] }
        func word(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        var bytes = [UInt8](); bytes.reserveCapacity(extensionBytes)
        for i in 0..<binCount {
            let s = isSupported(sigma: sigma[i], count: counts[i]) ? sigma[i] : 0
            bytes.append(contentsOf: word(Float(s).bitPattern))
        }
        for i in 0..<binCount { bytes.append(contentsOf: word(UInt32(clamping: counts[i]))) }
        bytes.append(contentsOf: word(mask(sigma: sigma, counts: counts)))
        bytes.append(contentsOf: word(0))
        return bytes
    }

    /// Piecewise-linear source sigma at a normalized signal level, over
    /// SUPPORTED bins only, knots at the bin centers. Levels outside the
    /// supported knot range clamp to the nearest supported bin's sigma.
    /// Refuses typed - never zero-fills - when no bin is supported.
    public static func interpolatedSigma(at level: Double, sigma: [Double], counts: [Int]) throws -> Double {
        guard sigma.count == binCount, counts.count == binCount else { throw MeasurementError.invalidBins }
        guard level.isFinite else { throw MeasurementError.nonFiniteLevel }
        var xs = [Double](), ys = [Double]()
        for i in 0..<binCount where isSupported(sigma: sigma[i], count: counts[i]) {
            xs.append(binCenter(i)); ys.append(sigma[i])
        }
        guard !xs.isEmpty else { throw MeasurementError.noSupportedBins }
        if xs.count == 1 { return ys[0] }
        if level <= xs[0] { return ys[0] }
        if level >= xs[xs.count - 1] { return ys[ys.count - 1] }
        for i in 1..<xs.count where level <= xs[i] {
            let t = (level - xs[i - 1]) / (xs[i] - xs[i - 1])
            return ys[i - 1] + t * (ys[i] - ys[i - 1])
        }
        return ys[ys.count - 1]
    }
}
