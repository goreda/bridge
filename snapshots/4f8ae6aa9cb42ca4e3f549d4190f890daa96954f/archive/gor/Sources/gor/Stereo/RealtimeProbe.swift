import Foundation
#if canImport(Metal) && canImport(AVFoundation) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
import Metal

/// 190v s32: fills the self-test log's `rtstage` lines (see PrepareTelemetry.rtStage) that the prepare stage totals do not already give. Everything here is a MEASUREMENT of the
/// real kernels on this Mac, at the canvas the s31 model uses (720x720 per eye, 1280x720 source, 266x150 depth box); nothing is estimated. Stage meaning:
///  - upsample: DepthUpsampler.resample (266x150 -> 1280x720), one waited command buffer.
///  - render: Stereo3DRenderer.render with surround off (both eyes, GPU wall time of the command buffer, waited).
///  - surround: render with surround on minus render with surround off (what the surround r4 kernels add).
///  - vt_decode: AVAssetReader copyNextSampleBuffer (BGRA) over the self-test's HEVC source proxy (640x360 clip: a lower bound for 720p).
///  - vt_encode: the prepare's `source_encode` stage total / frames (includes the second decode + 10-bit widen of that loop: an UPPER bound for the encode alone).
/// Compile risk: not compiled on a Mac; Metal texture creation with shared storage and `replace(region:)` are standard API.
/// REVIEW (s37 gate clean-up, read against the call sites; still not compiled on a Mac):
///  - Every Metal object is created once and reused across warm-up and timed iterations; timings therefore exclude pipeline compilation (Stereo3DRenderer.make() runs before `timed`).
///  - `render` waits on `lastCommandBuffer` and requires `.completed`, so the render/surround numbers are GPU wall time, not encode time. `surround` = on - off is clamped at 0.
///  - The decode loop measures `copyNextSampleBuffer` only (BGRA output, no GPU upload); the buffers are dropped each iteration, so no CVPixelBuffer pool growth.
///  - Textures use shared storage + `replace(region:)` (valid for .shared on both Apple silicon and Intel). Probe pixels are synthetic: timings are content independent except the
///    z-buffer contention of the render, which the ramp depth (1.5..4.5 m) exercises the same way a real scene does.
///  - Not covered: the flat s36 output modes (s3d_pack, perspective branch); they are not probed yet, so an rtstage line for them would be an estimate and none is emitted.
///  - Failure paths log via tel.error and return; nothing here can fail the prepare.
///  - Call order: the self-test runs this after the prepare finishes, so the GPU is idle and the thermal state is whatever the prepare left; the numbers are warm, not cold-start.
///  - Frame count: `frames` only scales the vt_encode mean (source_encode total / frames); a zero count skips the line rather than dividing.
///  - Owner of the numbers: PrepareTelemetry.rtStage writes them to the self-test log; the s31 model reads them from there. This file never writes anywhere else.
enum RealtimeProbe {
    static let eye = 720, srcW = 1280, srcH = 720, depthW = 266, depthH = 150, warmup = 3, iterations = 16

    static func run(tel: PrepareTelemetry, sourceProxy: URL?, frames: Int) {
        tel.note("rt_config", "fps=24.0 vr180=false depth_rate=24.0 surround_opt=true")           // surround_opt: footprint-box pre-blur (s31 d) is in; no margin, no single integral image
        tel.note("rt_probe", "canvas \(eye)x\(eye) per eye, source \(srcW)x\(srcH), depth box \(depthW)x\(depthH); \(iterations) timed iterations after \(warmup) warm-up")
        tel.rtStageFromTotal("vda", stage: "vda_step_total"); tel.rtStageFromTotal("moge", stage: "moge_step_total")
        if let e = tel.stages.first(where: { $0.name == "source_encode" })?.s, frames > 0 { tel.rtStage("vt_encode", meanMs: e.ms / Double(frames), n: frames, maxMs: e.max) }
        if let url = sourceProxy { decode(url, tel) } else { tel.error("rtstage vt_decode: no source proxy to read") }
        guard let r = Stereo3DRenderer.make(), let dev = MTLCreateSystemDefaultDevice(), let up = DepthUpsampler(device: dev, queue: r.queue) else { tel.error("rtstage: no Metal renderer"); return }
        func shared(_ f: MTLPixelFormat, _ w: Int, _ h: Int, _ bytesPerPixel: Int, _ fill: (Int, Int) -> [UInt8]) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false); d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .shared
            guard let t = dev.makeTexture(descriptor: d) else { return nil }
            var buf = [UInt8](); buf.reserveCapacity(w * h * bytesPerPixel)
            for y in 0..<h { for x in 0..<w { buf.append(contentsOf: fill(x, y)) } }
            t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: buf, bytesPerRow: w * bytesPerPixel); return t
        }
        func f32(_ v: Float) -> [UInt8] { withUnsafeBytes(of: v.bitPattern.littleEndian) { Array($0) } }
        guard let frame = shared(.bgra8Unorm, srcW, srcH, 4, { x, y in [UInt8(x & 255), UInt8(y & 255), UInt8((x + y) & 255), 255] }),
              let box = shared(.r32Float, depthW, depthH, 4, { x, _ in f32(1.5 + 3.0 * Float(x) / Float(depthW)) }),
              let metric = Stereo3DRenderer.texture(dev, .r32Float, srcW, srcH), let sbs = Stereo3DRenderer.texture(dev, .rgba8Unorm, eye * 2, eye) else { tel.error("rtstage: probe textures"); return }
        func timed(_ body: () -> Bool) -> (mean: Double, max: Double, ok: Bool) {
            for _ in 0..<warmup { if !body() { return (.nan, .nan, false) } }
            var sum = 0.0, mx = 0.0
            for _ in 0..<iterations { let t = DispatchTime.now(); if !body() { return (.nan, .nan, false) }; let ms = Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6; sum += ms; mx = Swift.max(mx, ms) }
            return (sum / Double(iterations), mx, true)
        }
        let u = timed { up.resample(box, into: metric) }
        if u.ok { tel.rtStage("upsample", meanMs: u.mean, n: iterations, maxMs: u.max) } else { tel.error("rtstage upsample: resample failed") }
        func render(_ surround: Bool) -> Bool {
            guard r.render(frame: frame, depth: metric, thetaH: 75 * .pi / 180, ipd: 0.063, convergence: 2.0, zNear: 0.5, swapEyes: false, surround: surround, outW: eye, outH: eye, sbsOut: sbs) else { return false }
            r.lastCommandBuffer?.waitUntilCompleted(); return r.lastCommandBuffer?.status == .completed
        }
        let off = timed { render(false) }, on = timed { render(true) }
        if off.ok && on.ok {
            tel.rtStage("render", meanMs: off.mean, n: iterations, maxMs: off.max)
            tel.rtStage("surround", meanMs: Swift.max(0, on.mean - off.mean), n: iterations, maxMs: Swift.max(0, on.max - off.mean))
        } else { tel.error("rtstage render/surround: render failed") }
    }

    private static func decode(_ url: URL, _ tel: PrepareTelemetry) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first, let rd = try? AVAssetReader(asset: asset) else { tel.error("rtstage vt_decode: cannot open the source proxy"); return }
        let o = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard rd.canAdd(o) else { tel.error("rtstage vt_decode: reader refused the output"); return }
        rd.add(o); guard rd.startReading() else { tel.error("rtstage vt_decode: startReading failed"); return }
        var sum = 0.0, mx = 0.0, n = 0
        while true {
            let t = DispatchTime.now(); guard let sb = o.copyNextSampleBuffer() else { break }; _ = sb
            let ms = Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6; sum += ms; mx = Swift.max(mx, ms); n += 1
        }
        if n > 0 { tel.rtStage("vt_decode", meanMs: sum / Double(n), n: n, maxMs: mx) } else { tel.error("rtstage vt_decode: no frames read") }
    }
}
#endif
