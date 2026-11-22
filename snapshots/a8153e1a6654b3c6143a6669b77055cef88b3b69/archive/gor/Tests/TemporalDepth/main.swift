import Foundation
// SYNTHETIC static scene: 4096 px, base depth 1.5..6 m, +-3% uniform noise per frame (LCG, deterministic). Prints p95 |z_t - z_{t-1}| / z, raw vs smoothed; then a 25% step at frame 20 and a slow ramp.
var seed: UInt64 = 12345
func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float((seed >> 40) & 0xFFFF) / 65535 }
let n = 4096; let base = (0..<n).map { 1.5 + 4.5 * Float($0) / Float(n) }
func p95(_ a: [Float]) -> Float { let s = a.sorted(); return s[Int(Float(s.count - 1) * 0.95)] }
func frames(_ k: Int, _ f: (Int, Int) -> Float) -> [[Float]] { (0..<k).map { t in (0..<n).map { i in f(t, i) } } }
func smooth(_ fr: [[Float]]) -> [[Float]] { var o = [fr[0]]; for t in 1..<fr.count { o.append(TemporalDepth.smooth(prev: o[t - 1], cur: fr[t])) }; return o }
func jit(_ fr: [[Float]]) -> Float { var d: [Float] = []; for t in 1..<fr.count { for i in 0..<n { d.append(abs(fr[t][i] - fr[t - 1][i]) / base[i]) } }; return p95(d) }
let st = frames(60) { _, i in base[i] * (1 + 0.06 * (rnd() - 0.5)) }
let sm = smooth(st)
print("static jitter raw \(jit(st)) smooth \(jit(sm))")
let step = frames(40) { t, i in base[i] * (t >= 20 ? 1.25 : 1) }
let ss = smooth(step)
print("step frame20 err \(abs(ss[20][100] - step[20][100]) / step[20][100]) frame21 \(abs(ss[21][100] - step[21][100]) / step[21][100])")
let ramp = frames(60) { t, i in base[i] * (1 + 0.004 * Float(t)) }
let rs = smooth(ramp)
var worst: Float = 0; for t in 5..<60 { worst = max(worst, abs(rs[t][50] - ramp[t][50]) / ramp[t][50]) }
print("ramp lag worst \(worst)")
print("invalid \(TemporalDepth.smooth(prev: [0, 2, .nan], cur: [3, 0, 2])) mismatch \(TemporalDepth.smooth(prev: [1], cur: [1, 2]))")
