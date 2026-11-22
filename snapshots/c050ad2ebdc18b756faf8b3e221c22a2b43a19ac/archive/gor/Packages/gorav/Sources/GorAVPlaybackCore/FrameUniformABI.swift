import Foundation
import GorAVNativeProbeKit

/// Version 1 wire format. Never copy the memory of FrameUniforms into a GPU buffer.
/// Header: magic at 0, version at 4, session at 8, parameter revision at 16.
/// All integers and Float32 bit patterns are little endian. Payload starts at 24.
public enum FrameUniformABI {
    public static let magic: UInt32 = 0x31554647 // bytes GFU1
    public static let version: UInt32 = 1
    public static let headerBytes = 24
    public static let payloadBytes = 64
    public static let packetBytes = headerBytes + payloadBytes
    /// Wire IDs are versioned, not caller-assigned table indices.
    public enum FitID: UInt32, Sendable { case unset = 0, fit = 1, fill = 2, stretch = 3 }
    public static func fitID(_ token: ModeToken?) -> FitID? {
        guard let token else { return .unset }
        switch token.name {
        case "fit": return .fit
        case "fill": return .fill
        case "stretch": return .stretch
        default: return nil
        }
    }
    public enum Lane: Int, CaseIterable, Sendable {
        case frameWidth = 0, frameHeight = 1, fitModeID = 2, reserved = 3
        case cropX = 4, cropY = 5, cropW = 6, cropH = 7
        case panX = 8, panY = 9, log2Zoom = 10, flags = 11
        case toneCurveID = 12, srcPeakNits = 13, dstPeakNits = 14, saturation = 15
        public var payloadByteOffset: Int { rawValue * 4 }
        public var packetByteOffset: Int { FrameUniformABI.headerBytes + payloadByteOffset }
    }
    static func append(_ value: UInt32, to bytes: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    static func append(_ value: UInt64, to bytes: inout Data) {
        append(UInt32(truncatingIfNeeded: value), to: &bytes)
        append(UInt32(truncatingIfNeeded: value >> 32), to: &bytes)
    }
    static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
    static func wide(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
        UInt64(word(bytes, offset)) | UInt64(word(bytes, offset + 4)) << 32
    }
    static func payload(_ u: FrameUniforms) -> Data {
        let words: [UInt32] = [u.frameWidth.bitPattern, u.frameHeight.bitPattern, u.fitModeID, u.reserved0,
            u.cropX.bitPattern, u.cropY.bitPattern, u.cropW.bitPattern, u.cropH.bitPattern,
            u.panX.bitPattern, u.panY.bitPattern, u.log2Zoom.bitPattern, u.flags,
            u.toneCurveID, u.srcPeakNits.bitPattern, u.dstPeakNits.bitPattern, u.saturation.bitPattern]
        var bytes = Data(); bytes.reserveCapacity(payloadBytes)
        for w in words { append(w, to: &bytes) }
        return bytes
    }
    public static func valid(_ u: FrameUniforms) -> Bool {
        guard [u.frameWidth, u.frameHeight, u.cropX, u.cropY, u.cropW, u.cropH,
               u.panX, u.panY, u.log2Zoom, u.srcPeakNits, u.dstPeakNits, u.saturation].allSatisfy(\.isFinite),
              u.frameWidth > 0, u.frameHeight > 0, FitID(rawValue: u.fitModeID) != nil, u.reserved0 == 0, u.flags & ~3 == 0,
              u.toneCurveID <= 4, u.srcPeakNits > 0, u.dstPeakNits > 0,
              (0...2).contains(u.saturation), u.cropX >= 0, u.cropY >= 0, u.cropW > 0, u.cropH > 0,
              Double(u.cropX) + Double(u.cropW) <= 1.000001,
              Double(u.cropY) + Double(u.cropH) <= 1.000001 else { return false }
        return HostTransform(panX: Double(u.panX), panY: Double(u.panY), log2Zoom: Double(u.log2Zoom)) != nil
    }
}

public enum FrameUniformConsumerError: Error, Equatable, Sendable {
    case malformed, unsupportedVersion, sessionMismatch, revisionMismatch, invalidPayload
}

/// Concrete presenter-facing boundary: consumes serialized bytes, validates identity
/// and lanes, and exposes the exact 64 bytes for a future Metal binding. No pixel claim.
public enum PresenterUniformConsumer {
    public struct Block: Equatable, Sendable {
        public let session: UInt64
        public let revision: ParameterBlockRevision
        public let uniforms: FrameUniforms
        public let shaderBytes: Data
    }
    public static func consume(_ packet: Data, session: UInt64, revision: ParameterBlockRevision)
        -> Result<Block, FrameUniformConsumerError> {
        let b = [UInt8](packet)
        guard b.count == FrameUniformABI.packetBytes, FrameUniformABI.word(b, 0) == FrameUniformABI.magic else { return .failure(.malformed) }
        guard FrameUniformABI.word(b, 4) == FrameUniformABI.version else { return .failure(.unsupportedVersion) }
        guard FrameUniformABI.wide(b, 8) == session else { return .failure(.sessionMismatch) }
        guard FrameUniformABI.wide(b, 16) == revision.value else { return .failure(.revisionMismatch) }
        func w(_ lane: FrameUniformABI.Lane) -> UInt32 { FrameUniformABI.word(b, lane.packetByteOffset) }
        func f(_ lane: FrameUniformABI.Lane) -> Float { Float(bitPattern: w(lane)) }
        var u = FrameUniforms()
        u.frameWidth = f(.frameWidth); u.frameHeight = f(.frameHeight); u.fitModeID = w(.fitModeID); u.reserved0 = w(.reserved)
        u.cropX = f(.cropX); u.cropY = f(.cropY); u.cropW = f(.cropW); u.cropH = f(.cropH)
        u.panX = f(.panX); u.panY = f(.panY); u.log2Zoom = f(.log2Zoom); u.flags = w(.flags)
        u.toneCurveID = w(.toneCurveID); u.srcPeakNits = f(.srcPeakNits); u.dstPeakNits = f(.dstPeakNits); u.saturation = f(.saturation)
        guard FrameUniformABI.valid(u) else { return .failure(.invalidPayload) }
        return .success(Block(session: session, revision: revision, uniforms: u,
                              shaderBytes: Data(b[FrameUniformABI.headerBytes...])))
    }
}

extension RenderGraph {
    /// One captured control revision, one block. Refuse stale crop/session or
    /// missing/mismatched revision before exposing any packet to the presenter.
    public static func serialized(session: UInt64, revision: ParameterBlockRevision, frame: NativeFrame,
                                  control: ControlState, crop: CropController, host: any HostTransformSource,
                                  color: ToneMapPlan) -> Data? {
        guard control.look == revision, let fit = FrameUniformABI.fitID(control.fit),
              let result = encode(session: session, frame: frame, control: control, crop: crop,
                                  host: host, color: color, fitID: { _ in fit.rawValue }),
              result.cropEncoded, FrameUniformABI.valid(result.uniforms) else { return nil }
        var packet = Data()
        FrameUniformABI.append(FrameUniformABI.magic, to: &packet)
        FrameUniformABI.append(FrameUniformABI.version, to: &packet)
        FrameUniformABI.append(session, to: &packet)
        FrameUniformABI.append(revision.value, to: &packet)
        packet.append(FrameUniformABI.payload(result.uniforms))
        return packet
    }
}
