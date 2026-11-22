#if canImport(Metal)
import Foundation
import Metal
import GorAVPlaybackCore

/// DR-0017: the P22-update consumer for GPU source measurement. Encodes the
/// measurement apply into the SAME command buffer as the measurement, and
/// only when the ticket fence admits it: exact session+generation+frameIndex
/// binding equality, domain equality, and command-buffer identity. A ticket
/// from any other command buffer, frame, session or domain is REFUSED typed -
/// never deferred, never last-good. Buffer existence is not evidence of use:
/// the fence is the only admission path. The CPU never reads the ticket before
/// encoding; CPU completion reads are the stage's async telemetry only.
public final class PhotonP22UpdateConsumer {
    public enum Refusal: Error, Equatable, Sendable {
        /// Ticket fence rejected the binding, domain or command buffer.
        case fenceRejected
        /// The P22 destination buffer cannot hold the extension at the offset.
        case p22BufferTooSmall
        /// Apply pipeline could not be built.
        case applyPipelineUnavailable
    }

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState

    public init(device: MTLDevice) throws {
        self.device = device
        let lib = try device.makeLibrary(source: PhotonP22ApplyShader.source, options: nil)
        guard let fn = lib.makeFunction(name: "photonP22Apply") else { throw Refusal.applyPipelineUnavailable }
        pipeline = try device.makeComputePipelineState(function: fn)
    }

    /// Encodes the apply. Must be called on the ticket's own command buffer,
    /// before the P22 update is consumed by the photon pass.
    public func encode(commandBuffer: MTLCommandBuffer, ticket: PhotonMeasurementGPUTicket,
                       expectedBinding: PhotonSourceBinding, domain: PhotonMeasurementDomain,
                       p22Buffer: MTLBuffer, p22ExtensionByteOffset: Int) throws {
        guard ticket.admits(expectedBinding, domain: domain, on: commandBuffer) else { throw Refusal.fenceRejected }
        guard p22Buffer.device.registryID == device.registryID,
              p22ExtensionByteOffset >= 0,
              p22ExtensionByteOffset <= p22Buffer.length - PhotonMeasurementP22.extensionBytes,
              p22ExtensionByteOffset <= Int(UInt32.max),
              let enc = commandBuffer.makeComputeCommandEncoder() else { throw Refusal.p22BufferTooSmall }
        var offset = UInt32(p22ExtensionByteOffset)
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(ticket.buffer, offset: 0, index: 0)
        enc.setBuffer(p22Buffer, offset: 0, index: 1)
        enc.setBytes(&offset, length: 4, index: 2)
        enc.dispatchThreads(MTLSize(width: PhotonMeasurementP22.binCount, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: PhotonMeasurementP22.binCount, height: 1, depth: 1))
        enc.endEncoding()
    }
}

/// Active encoder dispatch (DR-0017): pairs the measurement stage and the P22
/// apply in ONE command buffer - measure then apply, no gap where a stale or
/// foreign ticket could be consumed. The caller owns the graph position: this
/// dispatch runs at the sourceMeasurement stage, after the decoded source luma
/// is shader-readable and before colorToneMap and the photon sharp/grain
/// passes (RenderGraphStage canonical order).
///
/// Decoded single-channel luma plane seam: the ONLY eligible plane formats are
/// .r8Unorm, .r16Unorm, .r16Float, .r32Float (enforced by the stage). Range
/// normalization belongs to the decode-plane producer at this seam: unorm
/// planes sample as signal-domain [0,1]; narrow-range YCbCr luma is
/// range-expanded by the producer before binding; PQ/HLG sources stay in the
/// encoded signal domain and bind as .r16Float/.r32Float with the matching
/// PhotonMeasurementDomain - the measurement bins encoded signal, never a
/// post-render screenshot and never CPU readback on the playback path.
public final class PhotonSourceMeasurementDispatcher {
    private let stage: PhotonSourceMeasurementStage
    private let consumer: PhotonP22UpdateConsumer

    public init(device: MTLDevice) throws {
        stage = try PhotonSourceMeasurementStage(device: device)
        consumer = try PhotonP22UpdateConsumer(device: device)
    }

    /// Dispatches measure+apply for one frame. Refuses typed on any fence or
    /// resource failure; the photon pass then runs with the previous P22
    /// measurement section intact (validity mask still authoritative).
    @discardableResult
    public func dispatch(commandBuffer: MTLCommandBuffer, decodedLuma: MTLTexture,
                         rect: PhotonPictureRect, binding: PhotonSourceBinding,
                         domain: PhotonMeasurementDomain,
                         p22Buffer: MTLBuffer, p22ExtensionByteOffset: Int,
                         telemetry: @escaping @Sendable (Result<PhotonSourceMeasurement, Error>) -> Void) throws
        -> PhotonMeasurementGPUTicket {
        let ticket = try stage.encode(commandBuffer: commandBuffer, decodedLuma: decodedLuma,
                                      rect: rect, binding: binding, domain: domain, completion: telemetry)
        try consumer.encode(commandBuffer: commandBuffer, ticket: ticket,
                            expectedBinding: binding, domain: domain,
                            p22Buffer: p22Buffer, p22ExtensionByteOffset: p22ExtensionByteOffset)
        return ticket
    }
}
#endif
