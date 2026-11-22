import Foundation

/// Source-space crop, independent of playback seek or decoder state. Strictly
/// validated once; the renderer snapshots it into each admitted frame lease.
public struct SourceCrop: Equatable, Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard [x,y,width,height].allSatisfy(\.isFinite), x >= 0, y >= 0,
              width > 0, height > 0, x+width <= 1, y+height <= 1 else {return nil}
        self.x=x;self.y=y;self.width=width;self.height=height
    }
    public static let full = SourceCrop(x:0,y:0,width:1,height:1)!
    public func apply(to u: inout FrameUniforms) {
        u.cropX=Float(x);u.cropY=Float(y);u.cropW=Float(width);u.cropH=Float(height)
    }
}
public enum SourceCropOutcome: Equatable, Sendable {
    case applied, refusedInvalid, refusedNotOpen, refusedSealed, refusedStaleSession
}

/// Screen-space output geometry shared by native stage and presenter.
/// UV crop does not change pan units. Unset means aspect-fit, never stretch.
public enum StageGeometry {
    public static func quad(uniforms u: FrameUniforms, drawableWidth: Int, drawableHeight: Int) -> [Float]? {
        guard FrameUniformABI.valid(u), drawableWidth > 0, drawableHeight > 0,
              let transform = HostTransform(panX: Double(u.panX), panY: Double(u.panY),
                                            log2Zoom: Double(u.log2Zoom)),
              let fit = FrameUniformABI.FitID(rawValue: u.fitModeID) else { return nil }
        let w = Double(u.frameWidth) * Double(u.cropW)
        let h = Double(u.frameHeight) * Double(u.cropH)
        let dw = Double(drawableWidth), dh = Double(drawableHeight)
        let scale: Double
        switch fit {
        case .unset, .fit: scale = min(dw / w, dh / h)
        case .fill: scale = max(dw / w, dh / h)
        case .stretch: scale = 1
        }
        let sx = fit == .stretch ? 1 : w * scale / dw
        let sy = fit == .stretch ? 1 : h * scale / dh
        var q = hostTransformQuad(scaleX: sx, scaleY: sy, transform)
        let x = u.cropX, y = u.cropY, r = x + u.cropW, b = y + u.cropH
        q[2] = x; q[3] = y; q[6] = x; q[7] = b
        q[10] = r; q[11] = y; q[14] = r; q[15] = b
        return q.allSatisfy(\.isFinite) ? q : nil
    }
}

/// These flags describe intent, not an implemented color transform.
public enum StageColorRefusal: Error, Equatable, Sendable {
    case invalidPayload
    case p12PixelMappingUnavailable
    case gamutConversionUnavailable
    case softwareToneMapperUnavailable
}
public enum StageColorAdmission {
    /// An off/identity plan must preserve extended values, including HDR.
    /// Bit 1 requests relative-colorimetric gamut conversion, not a no-op.
    /// Bit 0 requests an actual software mapper, not a Metal fallback.
    public static func identity(_ u: FrameUniforms) -> Result<Void, StageColorRefusal> {
        guard FrameUniformABI.valid(u) else { return .failure(.invalidPayload) }
        if u.flags & 1 != 0 { return .failure(.softwareToneMapperUnavailable) }
        if u.flags & 2 != 0 { return .failure(.gamutConversionUnavailable) }
        guard u.toneCurveID == 0, u.saturation == 1 else { return .failure(.p12PixelMappingUnavailable) }
        return .success(())
    }
}

/// P12 source policy, not a pixel implementation. Source: shipped mpv.conf
/// 975da1d4, SHA256 b7f7e571f43c67cbda1439ee2c5bd713825a9011b1c67b3901ac6cd587d397cd.
/// No transition/knee or target peak is invented from a profile name.
public enum P12Profile: Equatable, Sendable {
    case sdr, hdr, dolbyVision
    public var toneMapping: String { switch self { case .sdr: return "inherited"; case .hdr: return "mobius"; case .dolbyVision: return "auto" } }
    public var targetTransfer: String? { switch self { case .sdr: return nil; case .hdr: return "bt.1886"; case .dolbyVision: return "pq" } }
    public var computeDynamicPeak: Bool { false }
    public var saturationAdjustment: Int? { self == .hdr ? -10 : nil }
    public var gamutMapping: String? { self == .hdr ? "perceptual" : nil }
    /// DV ICC is expressly excluded by P12 until verified.
    public var requiresICC: Bool { self == .hdr }
}
