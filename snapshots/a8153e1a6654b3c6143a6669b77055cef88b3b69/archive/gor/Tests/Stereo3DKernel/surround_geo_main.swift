import Foundation
// Linux driver for SurroundGeometry: surround-geo w h f conv ow oh outdir -> inside.u8 / src.i32 / wb2.f32
let a = CommandLine.arguments
guard a.count >= 8, let w = Int(a[1]), let h = Int(a[2]), let f = Double(a[3]), let conv = Double(a[4]), let ow = Int(a[5]), let oh = Int(a[6]) else { exit(2) }
let g = SurroundGeometry.cached(w: w, h: h, f: f, conv: conv, ow: ow, oh: oh)
let dir = URL(fileURLWithPath: a[7])
try! Data(g.inside).write(to: dir.appendingPathComponent("inside.u8"))
try! g.sourceIndex.withUnsafeBytes { Data($0) }.write(to: dir.appendingPathComponent("src.i32"))
try! g.blendWeights.withUnsafeBytes { Data($0) }.write(to: dir.appendingPathComponent("wb4.f32"))
try! g.nearIndex.withUnsafeBytes { Data($0) }.write(to: dir.appendingPathComponent("near.i32"))
let bx = g.footprintBox
try! "\(bx[0]) \(bx[1]) \(bx[2]) \(bx[3])".write(to: dir.appendingPathComponent("box.txt"), atomically: true, encoding: .utf8)
print(g.allInside ? "allInside" : "partial")
