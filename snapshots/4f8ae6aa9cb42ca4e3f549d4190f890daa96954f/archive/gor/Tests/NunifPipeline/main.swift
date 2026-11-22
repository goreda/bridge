import Foundation
// usage: np <dir>; reads <name>.f32 raw little-endian float32 files written by the test, prints "name maxabs" for every fixture tensor.
let dir = CommandLine.arguments[1]
func load(_ n: String) -> [Float] { let d = try! Data(contentsOf: URL(fileURLWithPath: dir + "/" + n + ".f32")); return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
func md(_ a: [Float], _ b: [Float]) -> Float { precondition(a.count == b.count, "size \(a.count) vs \(b.count)"); var m: Float = 0; for i in 0..<a.count { m = max(m, abs(a[i] - b[i])) }; return m }
let h = 24, w = 48
typealias T = NunifPipeline.T
let depth = load("in_depth"), frame = T(c: 3, h: h, w: w, data: load("in_frame")), logits = T(c: 1, h: h, w: w, data: load("in_logits")), mask = T(c: 1, h: h, w: w, data: load("in_mask"))
let dx = T(c: 2, h: h, w: w, data: load("in_delta_x")), lw = T(c: 2, h: h, w: w, data: load("in_lw"))
let x3 = NunifPipeline.inputTensor(depth: depth, h: h, w: w, divergence: 2.0, convergence: 1.0)
print("feature_x3 \(md(x3.d, load("feature_x3")))")
let fv = NunifPipeline.featureValues(divergence: 2.0, convergence: 1.0, imageWidth: 48)
print("feature_values \(md([fv.0, fv.1], load("feature_values")))")
print("warp_delta_padded \(md(NunifPipeline.padDeltaY(dx).d, load("warp_delta_padded")))")
print("warp_delta_scale \(md([NunifPipeline.deltaScale(width: w)], load("warp_delta_scale")))")
print("warp_grid \(md(NunifPipeline.makeGrid(h: h, w: w).d, load("warp_grid")))")
print("warp_out \(md(NunifPipeline.applyMlbwDeltaWeight(c: frame, deltaX: dx, layerWeight: lw, layers: 2).d, load("warp_out")))")
let mp = NunifPipeline.postprocessHoleMask(logits: logits, th: h, tw: w, threshold: 0.15, innerDilation: 1, outerDilation: 1)
print("mask_post \(md(mp.map { $0 ? 1 : 0 }, load("mask_post")))")
print("gauss_k15 \(md(NunifPipeline.gaussianKernel1D(15), load("gauss_k15")))")
print("mask_blur \(md(NunifPipeline.gaussianBlur(mask).d, load("mask_blur")))")
let (xm, mb) = NunifPipeline.inpaintPreprocess(x: frame, mask: mask)
print("inpaint_x_masked \(md(xm.d, load("inpaint_x_masked")))")
print("inpaint_mask_blurred \(md(mb.d, load("inpaint_mask_blurred")))")
let plan = NunifPipeline.videoWindows(frames: 26)
print("windows_26f \(md(plan.flatMap { $0.idx.map { Float($0) } }, load("windows_26f")))")
print("windows_26f_emit \(md(plan.flatMap { [Float($0.emit.lowerBound), Float($0.emit.upperBound)] }, load("windows_26f_emit")))")
let p48 = NunifPipeline.videoWindows(frames: 48)
print("plan48 \(p48.map { "\($0.idx.first!):\($0.emit.lowerBound)-\($0.emit.upperBound)" }.joined(separator: " "))")
let nm = NunifPipeline.minmaxNormalize([0.045, 16.6, 8.0, .nan]); print("minmax \(nm[0]) \(nm[1]) \(nm[2]) \(nm[3]) flat \(NunifPipeline.minmaxNormalize([3, 3, 3])) fix \(md(NunifPipeline.minmaxNormalize(load("tos_frame0")), load("tos_frame0")))")
