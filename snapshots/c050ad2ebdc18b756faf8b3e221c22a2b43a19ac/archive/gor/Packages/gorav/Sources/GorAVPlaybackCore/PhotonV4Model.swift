import Foundation

public enum PhotonV4Error: Error { case invalid(String) }
public enum PhotonV4Model {
    static func positive(_ x: Double, _ name: String) throws {
        guard x.isFinite && x > 0 else { throw PhotonV4Error.invalid(name) }
    }
    static func nonnegative(_ x: Double, _ name: String) throws {
        guard x.isFinite && x >= 0 else { throw PhotonV4Error.invalid(name) }
    }
    public static func cell(sourceHeight: Double, outputHeight: Double, sourceCell: Double?, confidence: Double, lookFraction: Double, trim: Double) throws -> Double {
        try positive(sourceHeight,"source height"); try positive(outputHeight,"output height")
        try positive(lookFraction,"look fraction"); try positive(trim,"trim")
        try nonnegative(confidence,"confidence"); guard confidence <= 1 else { throw PhotonV4Error.invalid("confidence") }
        var v = lookFraction * outputHeight
        if let sourceCell, confidence >= 0.6 { try positive(sourceCell,"source cell"); v = sourceCell * outputHeight / sourceHeight }
        let result = max(0.6,v*trim)
        guard result.isFinite else { throw PhotonV4Error.invalid("cell overflow") }; return result
    }
    public static func pwl(_ y: Double, xs: [Double], ys: [Double]) throws -> Double {
        guard y.isFinite, xs.count == ys.count, xs.count >= 2 else { throw PhotonV4Error.invalid("curve") }
        for i in xs.indices {
            guard xs[i].isFinite else { throw PhotonV4Error.invalid("knot") }; try nonnegative(ys[i],"sigma")
            if i>0 && xs[i]<=xs[i-1] { throw PhotonV4Error.invalid("ordered knots") }
        }
        if y <= xs[0] { return ys[0] }
        for i in 1..<xs.count where y<=xs[i] { let t=(y-xs[i-1])/(xs[i]-xs[i-1]); return ys[i-1]+t*(ys[i]-ys[i-1]) }
        return ys.last!
    }
    public static func sigma(target: Double, source: Double, floor: Double = 0.35, compression: Double = 1, amount: Double = 1, strength: Double = 1, enabled: Bool = true) throws -> Double {
        try nonnegative(target,"target"); try nonnegative(source,"source"); try positive(floor,"floor")
        guard floor<=1 else { throw PhotonV4Error.invalid("floor") }; try positive(compression,"compression")
        guard compression>=1 else { throw PhotonV4Error.invalid("compression") }; try nonnegative(amount,"amount"); try nonnegative(strength,"strength")
        if !enabled || amount==0 || strength==0 { return 0 }
        try positive(target,"target")
        let t=target*compression, ratio=source/t, result=t*sqrt(max(1-ratio*ratio,floor*floor))*amount*strength
        guard result.isFinite && result>0 else { throw PhotonV4Error.invalid("sigma overflow/underflow") }; return result
    }
}
