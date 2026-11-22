import Foundation

/// Typed errors for checked media time math. No silent wrap, no trap, no
/// dropped overflow flag: every failing intermediate is one of these.
public enum TimeMathError: Error, Equatable, Sendable {
    case overflow
    case nonPositiveScale
    case nonPositiveParts
}

/// Checked time math for media timestamps: rational rescaling, duration
/// splitting and timestamp accumulation with typed overflow.
public protocol CheckedTimeMath {
    /// v * dstScale / srcScale, round to nearest, halves away from zero.
    /// Any intermediate overflow is a typed .overflow, including the
    /// rounding addition itself - checking only the multiply is a named
    /// failure mode of this packet.
    static func rescale(_ v: Int64, from srcScale: Int64, to dstScale: Int64) throws -> Int64
    /// Split total into parts contiguous durations whose sum is EXACTLY
    /// total (conservation), each part floor or floor+1 of the equal share,
    /// in order. parts <= 0 throws; total may be negative.
    static func splitDuration(total: Int64, parts: Int64) throws -> [Int64]
    /// Checked timestamp add/subtract; typed .overflow, no trap, no wrap.
    static func add(_ a: Int64, _ b: Int64) throws -> Int64
    static func subtract(_ a: Int64, _ b: Int64) throws -> Int64
}

/// Int64 implementation. Namespace enum: all API is static.
public enum Int64TimeMath: CheckedTimeMath {

    public static func rescale(_ v: Int64, from srcScale: Int64, to dstScale: Int64) throws -> Int64 {
        guard srcScale > 0, dstScale > 0 else { throw TimeMathError.nonPositiveScale }
        // Checked multiply: the product itself may not fit.
        let (product, mulOverflow) = v.multipliedReportingOverflow(by: dstScale)
        guard !mulOverflow else { throw TimeMathError.overflow }
        // Checked rounding addition: halves away from zero. This addition is
        // part of the contract - it is checked exactly like the multiply.
        let half = srcScale / 2
        let rounded: Int64
        if v >= 0 {
            let (r, of) = product.addingReportingOverflow(half)
            guard !of else { throw TimeMathError.overflow }
            rounded = r
        } else {
            let (r, of) = product.subtractingReportingOverflow(half)
            guard !of else { throw TimeMathError.overflow }
            rounded = r
        }
        // srcScale >= 1, so this division cannot trap (no Int64.min / -1).
        return rounded / srcScale
    }

    public static func splitDuration(total: Int64, parts: Int64) throws -> [Int64] {
        guard parts > 0 else { throw TimeMathError.nonPositiveParts }
        // Floor division with remainder in [0, parts): exact for negative
        // totals too. Swift's / and % truncate toward zero, so adjust once.
        var q = total / parts
        var r = total % parts
        if r < 0 {
            q -= 1   // safe: trunc quotient is > Int64.min whenever r != 0
            r += parts
        }
        // total == q*parts + r with 0 <= r < parts. The first r shares get
        // q+1 (== floor+1), the rest q (== floor). Sum is exactly total by
        // construction; no per-side truncated subtraction is involved.
        // q+1 cannot overflow: q == Int64.max implies r == 0 (parts == 1).
        var shares: [Int64] = []
        shares.reserveCapacity(Int(parts))
        for i in 0 ..< parts {
            shares.append(i < r ? q + 1 : q)
        }
        return shares
    }

    public static func add(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (r, of) = a.addingReportingOverflow(b)
        guard !of else { throw TimeMathError.overflow }
        return r
    }

    public static func subtract(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (r, of) = a.subtractingReportingOverflow(b)
        guard !of else { throw TimeMathError.overflow }
        return r
    }
}
