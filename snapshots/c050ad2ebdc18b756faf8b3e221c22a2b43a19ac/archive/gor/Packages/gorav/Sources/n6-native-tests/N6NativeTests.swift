#if canImport(Metal) && canImport(CoreVideo)
import Foundation
import Metal
import CoreVideo
import GorAVMetalPresenter
import GorAVPlaybackCore

#endif

@main struct N6NativeTests {
    static func main() async throws {
        #if canImport(Metal) && canImport(CoreVideo)
        var failed = 0
        func check(_ name: String, _ ok: Bool) {
            print(ok ? "PASS \(name)" : "FAIL \(name)"); if !ok { failed += 1 }
        }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("Metal unavailable: native checks NOT_RUN")
        }
        func texture(_ format: MTLPixelFormat, _ w: Int = 4, _ h: Int = 4) -> MTLTexture {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            td.storageMode = .shared; td.usage = [.renderTarget, .shaderRead]
            return device.makeTexture(descriptor: td)!
        }
        // Register before commit; never block an async executor waiting for GPU.
        func complete(_ command: MTLCommandBuffer) async {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                command.addCompletedHandler { _ in done.resume() }
                command.commit()
            }
        }
        let pass = try MetalStagePass(device: device)
        let source = texture(.rgba32Float), target = texture(.rgba32Float)
        let samples: [Float] = Array(repeating: [2, 3, 4, 1], count: 16).flatMap { $0 }
        samples.withUnsafeBytes { raw in
            source.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                           withBytes: raw.baseAddress!, bytesPerRow: 4 * 16)
        }
        var u = FrameUniforms(); u.frameWidth = 4; u.frameHeight = 4; u.fitModeID = FrameUniformABI.FitID.fit.rawValue
        u.srcPeakNits = 4000; u.dstPeakNits = 100 // off means off, even for this down-map-looking ratio
        let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = target; rp.colorAttachments[0].storeAction = .store
        let pipeline = try pass.makePipeline(colorPixelFormat: .rgba32Float)
        let cmd = queue.makeCommandBuffer()!
        try pass.encode(commandBuffer: cmd, pipeline: pipeline, source: source, destination: rp, uniforms: u)
        await complete(cmd)
        check("N6 GPU stage completed", cmd.status == .completed && cmd.error == nil)
        var result = [Float](repeating: 0, count: 64)
        result.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: 4 * 16, from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0)
        }
        check("N6 HDR off values above one preserved", zip(result, samples).allSatisfy { abs($0 - $1) < 0.0001 })
        var color = u; color.flags = 2
        do {
            try pass.encode(commandBuffer: queue.makeCommandBuffer()!, pipeline: pipeline, source: source, destination: rp, uniforms: color)
            check("N6 unsupported gamut refused", false)
        } catch StagePassError.color(.gamutConversionUnavailable) { check("N6 unsupported gamut refused", true) }
        let readback = CVPixelBufferReadback(device: device)
        let hdrResult = await readback.capture(source: target, completedSource: cmd, commandQueue: queue)
        check("N6 BGRA utility refuses HDR format", hdrResult == nil)
        let bgra = texture(.bgra8Unorm), bgraTarget = texture(.bgra8Unorm)
        let bytes = [UInt8](repeating: 128, count: 64)
        bytes.withUnsafeBytes { raw in
            bgra.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: 16)
        }
        let bgraPass = MTLRenderPassDescriptor(); bgraPass.colorAttachments[0].texture = bgraTarget; bgraPass.colorAttachments[0].storeAction = .store
        let bgraCmd = queue.makeCommandBuffer()!
        try pass.encode(commandBuffer: bgraCmd, pipeline: pass.makePipeline(colorPixelFormat: .bgra8Unorm), source: bgra, destination: bgraPass, uniforms: u)
        await complete(bgraCmd)
        let copied = await readback.capture(source: bgraTarget, completedSource: bgraCmd, commandQueue: queue)
        check("N6 BGRA completed source copied", copied != nil)
        if let copied {
            check("N6 nonplanar buffer APIs", !CVPixelBufferIsPlanar(copied) && CVPixelBufferTap.copyPixels(buffer: copied) != nil)
            check("N6 BGRA copied pixels", CVPixelBufferTap.copyPixels(buffer: copied)?.prefix(16).allSatisfy { $0 == 128 } == true)
            check("N6 CV aggregate byte cap", CVPixelBufferTap.copyPixels(buffer: copied, maxBytes: 1) == nil)
        }
        let pending = queue.makeCommandBuffer()!
        let refusedPending = await readback.capture(source: bgraTarget, completedSource: pending, commandQueue: queue)
        check("N6 pending source refused", refusedPending == nil)
        var planar: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &planar)
        check("N6 planar fixture allocated", status == kCVReturnSuccess)
        if let planar {
            check("N6 planar APIs and bounded copy", CVPixelBufferIsPlanar(planar) && CVPixelBufferTap.copyPixels(buffer: planar) != nil)
        }
        print("n6-native-tests: \(failed) FAIL (offscreen only, no scanout/color parity/screenshot proof)")
        if failed != 0 { exit(1) }
        #else
        print("n6-native-tests: NOT_RUN (requires macOS Metal/CoreVideo)")
        #endif
    }
}
