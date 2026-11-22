import Foundation
// one command per stdin line: "<cmd> | section | section ..."; sections are space-separated numbers (bools as 0/1). Output: one line per command.
func nums(_ s: Substring) -> [Double] { s.split(separator: " ").map { Double($0)! } }
func fl(_ s: Substring) -> [Float] { nums(s).map { Float($0) } }
func out(_ a: [Float]) -> String { a.map { String($0) }.joined(separator: " ") }
func bl(_ s: Substring) -> [Bool] { nums(s).map { $0 != 0 } }
while let line = readLine() {
    let p = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }.map { Substring($0) }
    let w = Int(p[1])!, h = Int(p[2])!
    switch p[0] {
    case "std": print(out(DepthGuards.localStd(fl(p[3]), w: w, h: h)))
    case "tex": print(out(DepthGuards.textureWeights(luma: fl(p[3]), w: w, h: h)))
    case "sky":     // sky | w | h | inv | luma | finite or "-" | topFrac
        let fin: [Bool]? = p[5] == "-" ? nil : bl(p[5])
        print(out(DepthGuards.skyFarClamp(inv: fl(p[3]), luma: fl(p[4]), w: w, h: h, topFrac: Double(p[6])!, mogeFinite: fin)))
    case "fade":    // fade | w | h | inv frames flattened (T*w*h) | luma frames flattened | T
        let t = Int(p[5])!, n = w * h, inv = fl(p[3]), lu = fl(p[4])
        let invs = (0..<t).map { Array(inv[$0 * n..<($0 + 1) * n]) }, means = (0..<t).map { f in Double(lu[f * n..<(f + 1) * n].reduce(0.0) { $0 + Double($1) }) / Double(n) }
        print(out(DepthGuards.fadeFlatten(inv: invs, meanLuma: means).flatMap { $0 })); print(DepthGuards.fadeAmounts(meanLuma: means).map { String($0) }.joined(separator: " "))
    case "overlay":   // overlay | w | h | luma frames flattened | T | minFrames
        let t = Int(p[4])!, n = w * h, lu = fl(p[3]); var acc = DepthGuards.OverlayAccumulator(w: w, h: h)
        for f in 0..<t { acc.add(luma: Array(lu[f * n..<(f + 1) * n])) }
        if let m = acc.mask(minFrames: Int(p[5])!) { print(m.map { $0 ? "1" : "0" }.joined(separator: " ")) } else { print("none") }
    case "fit":     // fit | n | 0 | target | reference | mask or - | weights or -
        let m: [Bool]? = p[5] == "-" ? nil : bl(p[5]), wt: [Float]? = p[6] == "-" ? nil : fl(p[6])
        if let r = ShotAlignerSwift.fit(target: fl(p[3]), reference: fl(p[4]), mask: m, weights: wt) { print(r.scale, r.shift, r.pairs) } else { print("nil") }
    case "jitter":  // jitter | w | h | z frames flattened | T
        let t = Int(p[4])!, n = w * h, z = fl(p[3]); var acc = DepthGuards.JitterAccumulator()
        for f in 0..<t { acc.add(z: Array(z[f * n..<(f + 1) * n])) }
        print(acc.value.map { String($0) } ?? "nil")
    case "mask":    // mask | mw | mh | depth (mw*mh, inf allowed) | dw | dh
        let dw = Int(p[4])!, dh = Int(p[5])!; print(DepthGuards.finiteMask(fl(p[3]), mw: w, mh: h, dw: dw, dh: dh).map { $0 ? "1" : "0" }.joined(separator: " "))
    default: print("?")
    }
}
