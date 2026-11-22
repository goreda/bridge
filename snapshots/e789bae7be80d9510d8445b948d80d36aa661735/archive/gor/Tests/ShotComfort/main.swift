import Foundation
// stdin: line1 "pins"; "case <n>" followed by n floats per line frame lines: prints results for the Python test to compare.
var frames: [[Float]] = []
var hist = ShotComfort.Histogram()
let pins = [ShotComfort.farOverflow(zc: 1.0), ShotComfort.minConvergence(), ShotComfort.nearClamp(zc: 3.6095)]
print("pins", pins.map { String(format: "%.9f", $0) }.joined(separator: " "))
while let line = readLine() {
    let p = line.split(separator: " ")
    if p.first == "strength" {   // strength zc s over -> final eye offset, crossed deg at z_near, uncrossed deg at infinity (all with the FINAL baseline)
        let zc = Double(p[1])!, st = Double(p[2])!, ob = p[3] == "1"
        let c = ShotComfort.make(medianZ: zc)!, f = ShotComfort.strengthFactor(st, overBudget: ob), b = ShotComfort.ipd * c.depthScale * f
        print("strength", String(format: "%.12g %.12g %.12g %.12g", f, b, f > 0 ? ShotComfort.dispDeg(z: c.zNear, zc: zc, ipd: b) : 0, f > 0 ? ShotComfort.dispDeg(z: 1e12, zc: zc, ipd: b) : 0)); continue }
    if p.first == "frame" { frames.append(p.dropFirst().map { Float($0)! }) }
    else if p.first == "w10" { hist.add(plane: p.dropFirst().map { UInt16($0)! }) }
    else if p.first == "end" {
        let m = ShotComfort.median(frames)
        let c = m.flatMap { ShotComfort.make(medianZ: $0) }
        print("exact", m.map { String(format: "%.12g", $0) } ?? "nil", c.map { String(format: "%.12g %.12g %.12g %.12g", $0.ipdEff, $0.depthScale, $0.zNear, $0.farOverflowDeg) } ?? "nil",
              "hist", hist.median().map { String(format: "%.12g", $0) } ?? "nil")
        frames = []; hist = ShotComfort.Histogram()
    }
}
