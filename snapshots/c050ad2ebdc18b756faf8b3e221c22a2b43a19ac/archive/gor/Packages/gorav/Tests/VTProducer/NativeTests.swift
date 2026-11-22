#if canImport(AppKit) && canImport(Metal)
import Foundation
import CoreVideo
import GorAVPlaybackCore
import GorAVMetalPresenter

@MainActor func nativeProducerSlotTests() async throws {
    let renderer = try MetalRenderer()
    renderer.beginSession(sessionID: "VT-PRODUCER", generation: 7)
    let binding = SourceSession(session: 42, revision: 0)
    func identity(_ sequence: UInt64, source: SourceSession? = nil) -> FrameIdentity {
        FrameIdentity(sessionID: "VT-PRODUCER", sessionGeneration: 7, sequence: sequence,
                      surfaceRevision: 0, ptsSeconds: Double(sequence) / 30,
                      producerSource: source ?? binding)
    }
    func payload(_ sequence: UInt64, y: UInt8) throws -> VTFramePayload {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
                                     kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
        guard CVPixelBufferCreate(nil, 8, 4, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                  attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess, let pb = pixelBuffer else {
            fatalError("CVPixelBuffer fixture allocation failed")
        }
        // Fixture generation may write pixels. Production native upload may not.
        precondition(CVPixelBufferLockBaseAddress(pb, []) == kCVReturnSuccess)
        for plane in 0..<2 {
            memset(CVPixelBufferGetBaseAddressOfPlane(pb, plane)!, plane == 0 ? Int32(y) : 128,
                   CVPixelBufferGetBytesPerRowOfPlane(pb, plane) * CVPixelBufferGetHeightOfPlane(pb, plane))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        return VTFramePayload(pixelBuffer: pb, width: 8, height: 4, matrix: .bt709,
                              ioSurfaceBacked: CVPixelBufferGetIOSurface(pb) != nil,
                              cvPixelFormat: CVPixelBufferGetPixelFormatType(pb),
                              provenance: NativeFrameProvenance(source: binding, ptsSeconds: Double(sequence) / 30, durationSeconds: 1.0 / 30))
    }
    weak var lastOwner: NativeFrameOwnership?
    // The actual Metal slot must retain ownership after SourceFrame/payload
    // release and drop it on CPU replacement once the GPU callback drains.
    var frame: VTFramePayload? = try payload(1, y: 235)
    lastOwner = frame?.ownership
    precondition(renderer.upload(vtFrame: frame!, identity: identity(1)) == .okZeroCopy)
    frame = nil
    precondition(lastOwner != nil)
    guard let white = renderer.probePixel(identity: identity(1), px: 4, py: 2, drawableW: 8, drawableH: 4) else {
        fatalError("native offscreen white readback missing")
    }
    precondition(white.r >= 254 && white.g >= 254 && white.b >= 254)
    for sequence in 2...30 {
        try await Task.sleep(nanoseconds: 1_000_000)
        let result = renderer.upload(rgba: [UInt8](repeating: 0, count: 8*4*4), width: 8, height: 4, identity: identity(UInt64(sequence)))
        if case .ok = result {} else { fatalError("CPU recycle refused: \(result)") }
    }
    precondition(lastOwner == nil, "native ownership leaked after slot recycle")
    let stalePayload = try payload(31, y: 16)
    precondition(renderer.upload(vtFrame: stalePayload, identity: identity(31, source: SourceSession(session: 42, revision: 1))) == .rejectedStaleGeneration)
    let blackPayload = try payload(31, y: 16)
    precondition(renderer.upload(vtFrame: blackPayload, identity: identity(31)) == .okZeroCopy)
    guard let black = renderer.probePixel(identity: identity(31), px: 4, py: 2, drawableW: 8, drawableH: 4) else {
        fatalError("native offscreen black readback missing")
    }
    precondition(black.r <= 1 && black.g <= 1 && black.b <= 1)
    _ = await renderer.close()
    print("PASS VT-PRODUCER native slot ownership/recycle, generation refusal, NV12 GPU white/black offscreen")
}
#endif
