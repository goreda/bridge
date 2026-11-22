import Foundation
import GorAVNativeProbeKit

// R1 (arch-195b, Mac-free part): render graph stage-interface contracts and
// the per-frame uniform block. Each stage is a typed encoder that writes ONLY
// its own fields of one FrameUniforms value; the presenter upload is NOT implemented here. setHostTransform stays in gdb's lane: it is consumed here through
// the HostTransform contract, never reimplemented.

// Uses the existing HostTransform.swift type and its validation.

/// Implemented by the presenter side (gdb's lane) to publish the current
/// host transform. The graph reads it per frame; it never calls back in.
public protocol HostTransformSource: Sendable {
    var currentHostTransform: HostTransform { get }
}

/// Logical per-frame values, not a Swift-memory shader ABI. FrameUniformABI
/// defines the stable 16-lane wire format; never upload this struct memory.
/// Field ownership is by stage; a stage writing another stage's field is a
/// contract violation caught by the stage-isolation witnesses.
@frozen public struct FrameUniforms: Equatable, Sendable {
    // control stage: frame geometry + fit
    public var frameWidth: Float = 0
    public var frameHeight: Float = 0
    /// Opaque fit token packed by the control stage (0 = unset). The renderer
    /// maps ids back through the same table the control stage used.
    public var fitModeID: UInt32 = 0
    public var reserved0: UInt32 = 0
    // crop stage: normalized resolved source rect
    public var cropX: Float = 0
    public var cropY: Float = 0
    public var cropW: Float = 1
    public var cropH: Float = 1
    // host transform stage (gdb's parameters, consumed not implemented)
    public var panX: Float = 0
    public var panY: Float = 0
    public var log2Zoom: Float = 0
    /// bit0: software tone-map fallback required
    public var flags: UInt32 = 0
    // color stage: resolved tone-map plan
    public var toneCurveID: UInt32 = 0
    public var srcPeakNits: Float = 100
    public var dstPeakNits: Float = 100
    public var saturation: Float = 1

    public init() {}

    public static let laneCount = 16
    /// Stable wire IDs, independent of CaseIterable or declaration order.
    public static func curveID(_ c: ToneMapCurve) -> UInt32 {
        switch c {
        case .none: return 0
        case .clip: return 1
        case .mobius: return 2
        case .hable: return 3
        case .reinhard: return 4
        }
    }
    public static func gamutID(_ g: GamutMode) -> UInt32 { g == .perceptual ? 0 : 1 }
}

public enum RenderStageID: String, CaseIterable, Equatable, Sendable {
    case control, crop, hostTransform, color
}

/// P21 canonical ordered per-frame pass list (PLAN.md P21). Stages with no
/// encoder yet are declared and inert: they hold their position, write
/// nothing and make no Metal/pixel claim.
public enum RenderGraphStage: String, CaseIterable, Sendable {
    case decode, sourceMeasurement, colorToneMap, crop, stereoProjection, photon, surround, output, bitmapSubtitles, present
    /// Encoders exist for these stages today; the rest are scaffolding.
    /// sourceMeasurement (DR-0017): additive GPU pass, dispatched in the
    /// presenter after the decoded source luma is shader-readable and BEFORE
    /// colorToneMap and the photon sharp/grain passes. It writes no
    /// FrameUniforms lanes - its output is the 64-byte measurement ticket
    /// consumed by the same-command-buffer P22 update, so hasEncoder stays
    /// false on the CPU uniform path by design.
    /// P31/R3: stereoProjection KEEPS hasEncoder == false. This property
    /// tracks CPU-uniform/FrameUniform encoders; the carrier's
    /// render-graph tests assert exactly colorToneMap/crop/output. The
    /// stereo projection is a renderer-owned GPU pass
    /// (StereoProjectionPass, GorAVMetalPresenter) consuming the stage
    /// block directly - not a FrameUniform encoder; the existing Photon
    /// GPU effects likewise report false.
    public var hasEncoder: Bool {
        switch self {
        case .colorToneMap, .crop, .output: return true
        case .decode, .sourceMeasurement, .stereoProjection, .photon, .surround, .bitmapSubtitles, .present: return false
        }
    }
}

extension RenderStageID {
    /// Position of this encoder's writes in the canonical pass list. The
    /// control (frame geometry + fit) and hostTransform (pan/zoom) encoders
    /// both feed the output stage.
    public var graphStage: RenderGraphStage {
        switch self {
        case .color: return .colorToneMap
        case .crop: return .crop
        case .control, .hostTransform: return .output
        }
    }
}

/// The typed stage contract. A stage encodes its own fields from its own
/// typed input; the frame carries session/dimensions for fencing.
public protocol FrameUniformStage: Sendable {
    static var stageID: RenderStageID { get }
}

public enum ControlStageEncoder: FrameUniformStage {
    public static let stageID = RenderStageID.control
    /// Packs frame geometry + the control state's fit token. Fit ids are
    /// assigned by the caller's table; unset fit encodes 0.
    public static func encode(into u: inout FrameUniforms, frame: NativeFrame,
                              state: ControlState, fitID: (ModeToken?) -> UInt32) {
        u.frameWidth = Float(frame.width)
        u.frameHeight = Float(frame.height)
        u.fitModeID = fitID(state.fit)
        u.reserved0 = 0
    }
}

public enum CropStageEncoder: FrameUniformStage {
    public static let stageID = RenderStageID.crop
    /// Resolves the controller's current crop against the frame and writes
    /// the normalized source rect. A refused resolution leaves the block's
    /// crop fields untouched (the caller keeps last-good or identity).
    public static func encode(into u: inout FrameUniforms, frame: NativeFrame,
                              controller: CropController) -> Bool {
        guard let r = controller.geometry(frame: frame),
              case .success(let g) = r, frame.width > 0, frame.height > 0 else { return false }
        u.cropX = Float(g.x) / Float(frame.width)
        u.cropY = Float(g.y) / Float(frame.height)
        u.cropW = Float(g.width) / Float(frame.width)
        u.cropH = Float(g.height) / Float(frame.height)
        return true
    }
}

public enum HostTransformStageEncoder: FrameUniformStage {
    public static let stageID = RenderStageID.hostTransform
    public static func encode(into u: inout FrameUniforms, source: any HostTransformSource) {
        let t = source.currentHostTransform
        u.panX = Float(t.panX)
        u.panY = Float(t.panY)
        u.log2Zoom = Float(t.log2Zoom)
    }
}

public enum ColorStageEncoder: FrameUniformStage {
    public static let stageID = RenderStageID.color
    public static func encode(into u: inout FrameUniforms, plan: ToneMapPlan) {
        u.toneCurveID = FrameUniforms.curveID(plan.curve)
        u.srcPeakNits = Float(plan.sourcePeakNits)
        u.dstPeakNits = Float(plan.targetPeakNits)
        u.saturation = Float(plan.saturation)
        if plan.softwareFallback { u.flags |= 1 } else { u.flags &= ~1 }
        // gamut rides in the high half of flags' sibling: keep block at 16
        // lanes by packing gamut into flags bit1.
        if FrameUniforms.gamutID(plan.gamut) == 1 { u.flags |= 2 } else { u.flags &= ~2 }
    }
}

/// The graph: stage encoders applied in contract order to one block per
/// frame. Session-fenced: a frame from another session yields no encode.
public enum RenderGraph {
    public struct EncodeResult: Equatable, Sendable {
        public let uniforms: FrameUniforms
        /// false when the crop resolution was refused and crop fields kept
        /// their previous values.
        public let cropEncoded: Bool
    }

    /// Canonical pass position: stage order first, then the intra-stage order
    /// control-before-hostTransform inside the output stage.
    private static func passPosition(_ id: RenderStageID) -> (stage: Int, intra: Int) {
        let stagePos = RenderGraphStage.allCases.firstIndex(of: id.graphStage)!
        let intra: Int
        switch id {
        case .control: intra = 0
        case .hostTransform: intra = 1
        default: intra = 0
        }
        return (stagePos, intra)
    }

    /// Encoders applied in canonical P21 pass order; declared stages without
    /// encoders are skipped. The writes are field-disjoint, so this ordering
    /// does not change the encoded block - it makes the graph's application
    /// order derived from the canonical stage list instead of hand-written.
    public static let encoderApplicationOrder: [RenderStageID] =
        RenderStageID.allCases.sorted {
            let a = passPosition($0), b = passPosition($1)
            return a.stage != b.stage ? a.stage < b.stage : a.intra < b.intra
        }

    public static func encode(session: UInt64, frame: NativeFrame,
                              control: ControlState,
                              crop: CropController,
                              host: any HostTransformSource,
                              color: ToneMapPlan,
                              fitID: (ModeToken?) -> UInt32 = { _ in 0 })
        -> EncodeResult? {
        guard frame.session == session else { return nil }
        var u = FrameUniforms()
        var cropOK = true
        for id in encoderApplicationOrder {
            switch id {
            case .control: ControlStageEncoder.encode(into: &u, frame: frame, state: control, fitID: fitID)
            case .crop: cropOK = CropStageEncoder.encode(into: &u, frame: frame, controller: crop)
            case .hostTransform: HostTransformStageEncoder.encode(into: &u, source: host)
            case .color: ColorStageEncoder.encode(into: &u, plan: color)
            }
        }
        guard [u.frameWidth, u.frameHeight, u.cropX, u.cropY, u.cropW, u.cropH,
               u.panX, u.panY, u.log2Zoom, u.srcPeakNits, u.dstPeakNits, u.saturation].allSatisfy({ $0.isFinite }) else { return nil }
        return EncodeResult(uniforms: u, cropEncoded: cropOK)
    }
}
