import Foundation

// 195h B driver: synthetic breathing range, invalid passthrough, flag-off identity, persisted-state restore. Prints metrics for depth_temporal_ema_test.py.
func scene(_ lo: Float, _ hi: Float, _ n: Int) -> [Float] { (0..<n).map { i in lo + (hi - lo) * Float(i % 97) / 96.0 } }
print("default off \(DepthTemporalEMA.isEnabled() == false)")
DepthTemporalEMA.toggleEnabled()          // review r1: the driver enables the flag through the real locked mutator, never the raw static
print("enabled after toggle \(DepthTemporalEMA.isEnabled())")

var st = DepthTemporalEMA.State()
var rawRanges: [Float] = [], outRanges: [Float] = []
for f in 0..<60 {
    let lo = Float(1.0 + 0.10 * sin(Double(f) * 0.5)), hi = Float(8.0 + 0.8 * sin(Double(f) * 0.5 + 1.0))
    let cur = scene(lo, hi, 2048)
    rawRanges.append(hi - lo)
    let out = st.apply(cur)
    let v = out.filter { $0 > 0 }.sorted()
    outRanges.append(v[Int(Float(v.count - 1) * 0.99)] - v[Int(Float(v.count - 1) * 0.01)])
}
let rawTail = rawRanges.suffix(20), outTail = outRanges.suffix(20)
print(String(format: "breathing range jitter raw %.4f ema %.4f", rawTail.max()! - rawTail.min()!, outTail.max()! - outTail.min()!))

var s2 = DepthTemporalEMA.State()
_ = s2.apply(Array(repeating: Float(2.5), count: 2000))          // prime
let bad: [Float] = [3.0, 0.0, 2.0, .nan] + scene(2, 5, 100)
let kept = s2.apply(bad)
print("invalid zero \(kept[1]) nankept \(kept[3].isNaN) mapped \(abs(kept[0] - (s2.lo + (3.0 - 2.0) * (s2.hi - s2.lo) / (5.0 - 2.0))) < 0.2)")

DepthTemporalEMA.toggleEnabled()          // back off through the same mutator
var s3 = DepthTemporalEMA.State()
let off = s3.apply(bad)
print("flagoff identical \(zip(off, bad).allSatisfy { $0 == $1 || ($0.isNaN && $1.isNaN) }) primed \(s3.primed == false)")
let restored = DepthTemporalEMA.State(active: true, lo: 2, hi: 6, primed: false)   // 195h r3-3: the persisted primed flag is restored exactly
print("restore exact primed \(restored.primed == false) lo \(restored.lo == 2) hi \(restored.hi == 6)")
