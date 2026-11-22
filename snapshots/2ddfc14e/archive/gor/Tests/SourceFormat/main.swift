import Foundation
// stdin lines: w h rot sar bitdepth transfer primaries matrix avg max dv ; prints refuse-count normW normH matrix vfr ; "T a b c d tx ty sar w h" prints rot + display transform
while let l = readLine() {
    let t = l.split(separator: " ").map(String.init)
    if t[0] == "T" {
        let v = t[1...6].map { Double($0)! }, sar = Double(t[7])!, w = Int(t[8])!, h = Int(t[9])!
        let r = SourceFormat.rotation(a: v[0], b: v[1], c: v[2], d: v[3]); let m = SourceFormat.displayTransform(preferred: (v[0], v[1], v[2], v[3], v[4], v[5]), sar: sar, width: w, height: h)
        print("T \(r) \(m.a) \(m.b) \(m.c) \(m.d) \(m.tx) \(m.ty)")
    } else if t[0] == "W" {
        print("W \(SourceFormat.widen8To10(UInt8(t[1])!, fullRange: t[2] == "1"))")
    } else if t[0] == "B" {
        func bytes(_ s: String) -> [UInt8]? { s == "-" ? nil : stride(from: 0, to: s.count, by: 2).map { UInt8(s[s.index(s.startIndex, offsetBy: $0)..<s.index(s.startIndex, offsetBy: $0 + 2)], radix: 16)! } }
        print("B \(SourceFormat.bitDepth(hvcC: bytes(t[1]), avcC: bytes(t[2])))")
    } else {
        var f = SourceFacts(); f.width = Int(t[0])!; f.height = Int(t[1])!; f.rotation = Int(t[2])!; f.sar = Double(t[3])!; f.bitDepth = Int(t[4])!
        f.transfer = t[5]; f.primaries = t[6]; f.matrix = t[7]; f.avgFps = Double(t[8])!; f.maxFps = Double(t[9])!; f.dolbyVision = t[10] == "1"
        if t.count > 12 { f.ptsTickMs = Double(t[11])!; f.sampleDeltasMs = t[12].split(separator: ",").map { Double($0)! } }
        let n = SourceFormat.normalizedSize(f)
        print("\(SourceFormat.refuseReasons(f).count) \(n.w) \(n.h) \(SourceFormat.matrixKey(f)) \(SourceFormat.isVFR(f) ? 1 : 0) \(SourceFormat.verdicts(f).map { $0.status }.joined(separator: ","))")
    }
}
