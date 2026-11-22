#if canImport(Metal)
import GorAVPlaybackCore
import Foundation
import Metal

/// Every-frame GPU tiled measurement; caller owns graph position and P22 binding.
/// Returns a same-command-buffer GPU statistics ticket for P22. Completion also returns CPU telemetry asynchronously. No waitUntilCompleted
/// on the playback thread. Binding travels with the buffer and is checked by consumer.
public struct PhotonMeasurementGPUTicket {
    public let buffer: MTLBuffer
    public let commandBufferID: ObjectIdentifier
    public let binding: PhotonSourceBinding
    public let domain: PhotonMeasurementDomain
    public static let byteCount = 64
    public static let sigmaByteOffset = 0
    public static let countsByteOffset = 32
    public func admits(_ expected: PhotonSourceBinding, domain expectedDomain: PhotonMeasurementDomain, on commandBuffer: MTLCommandBuffer) -> Bool { binding==expected && domain==expectedDomain && commandBufferID==ObjectIdentifier(commandBuffer) && (commandBuffer.status == .notEnqueued || commandBuffer.status == .enqueued) }
}
public final class PhotonSourceMeasurementStage {
    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let reduction: MTLComputePipelineState
    public init(device: MTLDevice) throws {
        self.device=device
        let lib=try device.makeLibrary(source:PhotonMeasurementShader.source,options:nil)
        guard let fn=lib.makeFunction(name:"photonSourceMeasure") else { throw PhotonV4Error.invalid("measurement function") }
        pipeline=try device.makeComputePipelineState(function:fn)
        guard let reduce=lib.makeFunction(name:"photonSourceReduce") else { throw PhotonV4Error.invalid("reduction function") }
        reduction=try device.makeComputePipelineState(function:reduce)
    }
    public func encode(commandBuffer: MTLCommandBuffer, decodedLuma: MTLTexture,
                       rect: PhotonPictureRect, binding: PhotonSourceBinding, domain: PhotonMeasurementDomain,
                       completion: @escaping @Sendable (Result<PhotonSourceMeasurement,Error>)->Void) throws -> PhotonMeasurementGPUTicket {
        guard decodedLuma.device.registryID==device.registryID,
              commandBuffer.commandQueue.device.registryID==device.registryID,
              decodedLuma.textureType == .type2D, decodedLuma.sampleCount==1,
              [.r8Unorm,.r16Unorm,.r16Float,.r32Float].contains(decodedLuma.pixelFormat),
              rect.valid(width:decodedLuma.width,height:decodedLuma.height),
              decodedLuma.width<=Int(UInt32.max),decodedLuma.height<=Int(UInt32.max) else { throw PhotonV4Error.invalid("decoded texture") }
        let tx=(rect.width+15)/16, ty=(rect.height+15)/16, tileBytes=96
        guard tx<=Int.max/ty, tx*ty<=Int.max/tileBytes, tx*ty<=Int(UInt32.max),
              rect.width<=Int(UInt32.max)/rect.height,
              let result=device.makeBuffer(length:tx*ty*tileBytes,options:.storageModeShared),
              let enc=commandBuffer.makeComputeCommandEncoder() else { throw PhotonV4Error.invalid("measurement resources") }
        // Explicit packed 32-byte wire layout matches uint4,uint2,uint,float.
        var words:[UInt32]=[UInt32(rect.x),UInt32(rect.y),UInt32(rect.width),UInt32(rect.height),UInt32(decodedLuma.width),UInt32(decodedLuma.height),UInt32(tx),Float(0.02).bitPattern]
        enc.setComputePipelineState(pipeline);enc.setTexture(decodedLuma,index:0);enc.setBuffer(result,offset:0,index:0)
        words.withUnsafeMutableBytes { enc.setBytes($0.baseAddress!,length:$0.count,index:1) }
        enc.dispatchThreads(MTLSize(width:tx,height:ty,depth:1),threadsPerThreadgroup:MTLSize(width:min(32,pipeline.maxTotalThreadsPerThreadgroup),height:1,depth:1));enc.endEncoding()
        guard let final=device.makeBuffer(length:PhotonMeasurementGPUTicket.byteCount,options:.storageModeShared),
              let reduce=commandBuffer.makeComputeCommandEncoder() else { throw PhotonV4Error.invalid("reduction resources") }
        var tileCount=UInt32(tx*ty)
        reduce.setComputePipelineState(reduction);reduce.setBuffer(result,offset:0,index:0);reduce.setBuffer(final,offset:0,index:1)
        reduce.setBytes(&tileCount,length:4,index:2)
        reduce.dispatchThreads(MTLSize(width:8,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:8,height:1,depth:1));reduce.endEncoding()
        commandBuffer.addCompletedHandler { cb in
            guard cb.status == .completed else { completion(.failure(cb.error ?? PhotonV4Error.invalid("measurement GPU")));return }
            let pointer=final.contents()
            let sigma=(0..<8).map { Double(pointer.load(fromByteOffset:$0*4,as:Float.self)) }
            let n=(0..<8).map { Int(pointer.load(fromByteOffset:32+$0*4,as:UInt32.self)) }
            guard sigma.allSatisfy({$0.isFinite && $0>=0}) else { completion(.failure(PhotonV4Error.invalid("measurement finite")));return }
            completion(.success(PhotonSourceMeasurement(binding:binding,domain:domain,pictureRect:rect,sigma:sigma,counts:n,sourceCellPixels:nil,cellConfidence:0)))
        }
        return PhotonMeasurementGPUTicket(buffer:final,commandBufferID:ObjectIdentifier(commandBuffer),binding:binding,domain:domain)
    }
}
#endif
