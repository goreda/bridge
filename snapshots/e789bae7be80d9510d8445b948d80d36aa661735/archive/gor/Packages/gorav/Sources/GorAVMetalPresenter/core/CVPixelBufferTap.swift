#if canImport(Metal) && canImport(CoreVideo)
import Foundation
import Metal
import CoreVideo
import GorAVPlaybackCore
import GorAVNativeProbeKit

// Bounded CV layout copies and a standalone BGRA8 readback utility.
// No screenshot pipeline, tone mapping, pool or decoder-native CV retention claim.

/// Metadata extraction + pixel copy for one decoded CVPixelBuffer. The
/// buffer is locked for the duration of each call and always unlocked,
/// including on the error paths.
public enum CVPixelBufferTap {

    public static func nativeFrame(session: UInt64, handle: UInt64, ptsUs: Int64,
                                   buffer: CVPixelBuffer) -> NativeFrame {
        NativeFrame(session: session, handle: handle, pts: ptsUs, duration: 0,
                    width: CVPixelBufferGetWidth(buffer),
                    height: CVPixelBufferGetHeight(buffer),
                    pixelFormatName: fourCCName(CVPixelBufferGetPixelFormatType(buffer)),
                    isKeyFrame: false)
    }

    /// The R5 readback hook: copy the full plane-0 bytes of a still-leased
    /// buffer. Planar formats get their planes concatenated in index order.
    public static func copyPixels(buffer: CVPixelBuffer, maxBytes: Int = 128 << 20) -> Data? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard maxBytes > 0 else { return nil }
        var out = Data()
        let planar = CVPixelBufferIsPlanar(buffer)
        let planes = planar ? CVPixelBufferGetPlaneCount(buffer) : 1
        guard planes > 0 else { return nil }
        for p in 0..<planes {
            guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, p) : CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, p) : CVPixelBufferGetBytesPerRow(buffer)
            let rows = planar ? CVPixelBufferGetHeightOfPlane(buffer, p) : CVPixelBufferGetHeight(buffer)
            guard stride > 0, rows > 0 else { return nil }
            let (bytes, overflow) = stride.multipliedReportingOverflow(by: rows)
            let (total, totalOverflow) = out.count.addingReportingOverflow(bytes)
            guard !overflow, !totalOverflow, bytes > 0, total <= maxBytes else { return nil }
            out.append(Data(bytes: base, count: bytes))
        }
        return out.isEmpty ? nil : out
    }

    private static func fourCCName(_ t: OSType) -> String {
        let chars: [UInt8] = [UInt8((t >> 24) & 0xFF), UInt8((t >> 16) & 0xFF),
                              UInt8((t >> 8) & 0xFF), UInt8(t & 0xFF)]
        return String(bytes: chars, encoding: .ascii) ?? "unknown"
    }
}

/// Unwired BGRA8 blit utility. Allocates one buffer per call (not a pool).
/// It is not attached to presentation or screenshot requests. Caller must
/// provide a completed source frame; the utility owns its non-render worker.
public final class CVPixelBufferReadback {
    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?
    // Only this worker creates the blit, waits for the GPU and touches the cache.
    // The caller can be a render worker; blocking work can never run there.
    private let worker = DispatchQueue(label: "gorav.bgra8-readback", qos: .utility)

    public init(device: MTLDevice) {
        self.device = device
        if CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache) != kCVReturnSuccess {
            textureCache = nil
        }
    }

    /// The caller supplies the command buffer that last wrote this source.
    /// It must already have completed successfully. This utility never waits
    /// for pending source writes and never turns a failed GPU result into pixels.
    public func capture(source: MTLTexture, completedSource: MTLCommandBuffer,
                        commandQueue: MTLCommandQueue) async -> CVPixelBuffer? {
        await withCheckedContinuation { continuation in
            worker.async {
                continuation.resume(returning: self.captureOnWorker(source: source,
                    completedSource: completedSource, commandQueue: commandQueue))
            }
        }
    }

    private func captureOnWorker(source: MTLTexture, completedSource: MTLCommandBuffer,
                                 commandQueue: MTLCommandQueue) -> CVPixelBuffer? {
        dispatchPrecondition(condition: .onQueue(worker))
        guard completedSource.status == .completed, completedSource.error == nil,
              completedSource.commandQueue.device.registryID == device.registryID,
              source.pixelFormat == .bgra8Unorm,
              source.sampleCount == 1, source.textureType == .type2D,
              source.device.registryID == device.registryID,
              commandQueue.device.registryID == device.registryID else { return nil }
        let w = source.width, h = source.height
        let (pixels, pixelOverflow) = w.multipliedReportingOverflow(by: h)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard w > 0, h > 0, !pixelOverflow, !byteOverflow,
              bytes <= SurfaceContract.maxFrameBytes else { return nil }
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
                                            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb, let cache = textureCache else { return nil }
        var cvTex: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil,
                .bgra8Unorm, w, h, 0, &cvTex) == kCVReturnSuccess,
              let texRef = cvTex, let dst = CVMetalTextureGetTexture(texRef),
              dst.pixelFormat == source.pixelFormat, dst.width == w, dst.height == h,
              dst.device.registryID == device.registryID, dst.sampleCount == 1,
              let cmd = commandQueue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: dst, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed, cmd.error == nil else { return nil }
        return pixelBuffer
    }
}
#endif
