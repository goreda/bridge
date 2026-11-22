import Foundation
// Darwin-native test stub for the cooperative-pause test (arch-196b C3). On Darwin the extracted
// ThreeDPrepareSpawn section's live branches name NativePrepareRunner (the real one, a relocated span in
// ThreeD.swift, is guarded by canImport(AVFoundation/CoreML/VideoToolbox/Accelerate) and would drag the CoreML
// model stack into this Foundation-only test binary). Same public shape as the real runner; the model work is
// never exercised by this test. VTShotEncoder is NOT stubbed: its relocated section self-guards and the real
// one compiles here on Darwin.
#if canImport(Darwin)
final class NativePrepareRunner: ShotPrepareRunner {
    let kitDir: URL
    let cacheRoot: URL
    init(kitDir: URL, cacheRoot: URL = DepthCachePaths.root) { self.kitDir = kitDir; self.cacheRoot = cacheRoot }
    var modelsDir: URL?
    var pauseRequested: () -> Bool = { false }
    func prepare(_ request: ThreeDPrepareLauncher.Request, cancelled: @escaping () -> Bool) throws {}
}
#endif

// DepthFrameReader (nested in the extracted DepthContainerWriter section, canImport(Metal)) names
// Stereo3DRenderer.decodeDepth; the real renderer (relocated Stereo3DKernel.swift span in ThreeD.swift) is the full
// Metal pipeline, far outside this Foundation-level fixture. Same public shape, inert: the reader is compiled, never run.
#if canImport(Metal)
import Metal
final class Stereo3DRenderer {
    func decodeDepth(luma: MTLTexture, metric: MTLTexture, shift: UInt32 = 6) -> Bool { return false }
}
#endif
