import Foundation
// SYNTHETIC shots (no owner baseline). name zNear zFar zc -> baseline (ShotComfort.make) span vs span-derived span, both ceilings.
for (n, a, b, c) in [("flat distant", 7.5, 9.0, 8.0), ("mid", 2.0, 8.0, 4.0), ("close deep", 0.8, 12.0, 2.5), ("far wide", 3.0, 40.0, 12.0), ("tiny range", 3.0, 3.05, 3.02)] as [(String, Double, Double, Double)] {
    let s = ShotComfortSpan.make(zNear: a, zFar: b, zc: c)!
    print("\(n) gain=\(s.gain) near=\(s.nearDeg) far=\(s.farDeg) span=\(s.spanDeg) before=\(s.spanBeforeDeg) clamped=\(s.clamped)")
}
print("invalid \(ShotComfortSpan.make(zNear: 0, zFar: 1, zc: 1) == nil) \(ShotComfortSpan.make(zNear: 2, zFar: 1, zc: 1) == nil)")
print("q \(ShotComfortSpan.quantile([[1, 2, 3, 4, 5, .nan, 0]], 0.5)!) \(ShotComfortSpan.quantile([[1, 2, 3, 4, 5]], 0.05)!) \(ShotComfortSpan.quantile([[]], 0.5) == nil)")

for (a, b, c) in [(7.5, 9.0, 8.0), (2.0, 8.0, 4.0), (0.8, 12.0, 2.5)] {
    let s = ShotComfortSpan.make(zNear: a, zFar: b, zc: c)!
    print("near_clamp_m \(s.nearClampM) crossed=\(ShotComfort.dispDeg(z: s.nearClampM, zc: c, ipd: s.ipdEff))")
}
var h = ShotComfort.Histogram(); h.add(plane: [1, 2, 3, 4, 5, 0])
print("histogram q05=\(h.quantile(0.05)!) q95=\(h.quantile(0.95)!) median=\(h.median()!)")
