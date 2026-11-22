// L2 presenter (block 78d), revision 3 (architect L2 r2 findings 1/3/4/7 +
// L8 r3 seam flag): ONE surface negotiation contract, shared with L5
// (HDR10/HLG/EDR) and L8 (subtitles) BEFORE any render fork.
// r3: FrameIdentity is the full immutable frame lease identity
// (sessionID + generation + unique sequence + trackRevision +
// surfaceRevision) - a bare generation UInt64 is NOT collision-free across
// allocators (L8 r3). Transfer covers sRGB/linear/PQ/HLG with a typed
// colorspace mapping table; HDR provenance is range/finite-validated;
// EDR/16F/signal consistency is validated typed (no HDR implied by enum
// cases). Public memberwise init (r2 finding 7: the synthesized one is
// internal, external lanes could not construct). AUTHORED NEW 2026-10-25.
#if canImport(AppKit) && canImport(Metal)
import AppKit
import Metal
import QuartzCore
import GorAVPlaybackCore

/// Score-binding envelope (L5 requirement): binds a frame to its corpus
/// position and the exact scoring arm. NIL in the SDR lane - never a faked
/// HDR identity.
public struct ScoreBinding: Equatable, Hashable, Sendable {
    public let corpusFrameIndex: Int
    public let armID: String
    public let kernelVersion: String
    public let corpusRevision: String
    public init(corpusFrameIndex: Int, armID: String, kernelVersion: String, corpusRevision: String) {
        self.corpusFrameIndex = corpusFrameIndex; self.armID = armID
        self.kernelVersion = kernelVersion; self.corpusRevision = corpusRevision
    }
}

/// Rational timebase for producer PTS values (L5 r5 (b)). Nil means the
/// ptsSeconds Double is already display seconds (the current SDR lane).
public struct GorAVTimebase: Equatable, Hashable, Sendable {
    public let num: Int
    public let den: Int
    public init(num: Int, den: Int) { self.num = num; self.den = den }
}

/// Full immutable frame identity (r2 finding 3 + L8 r3 + L5 r5 (b)):
/// session-unique, collision-free, carried through upload/slot/overlay/
/// command buffer/readback/records AND across renegotiation. Duplicate
/// PTS values can never misattribute a record.
public struct FrameIdentity: Equatable, Hashable, Sendable {
    /// Unique per session instance (UUID issued by the presenter).
    public let sessionID: String
    /// Monotonic process-wide generation (GorAVSessionGenerations).
    public let sessionGeneration: UInt64
    /// Strictly increasing per session; the unique frame key.
    public let sequence: UInt64
    /// Surface contract revision the frame was uploaded against; an upload
    /// after renegotiation carries the NEW revision, so same-generation
    /// frames can never relabel a slot holding an older-revision texture.
    public let surfaceRevision: UInt64
    public let producerSource: SourceSession?
    public let ptsSeconds: Double
    /// Decoder track-change revision when the source provides one.
    public let trackRevision: UInt64?
    public let score: ScoreBinding?
    /// Producer stream identity, kept as SEPARATE TYPED fields (L5 r5
    /// mapping review: L3/L5's streamIndex Int and handle UInt64 are
    /// distinct identities in the producer's space; an opaque combined
    /// String could claim a 1:1 mapping that does not exist).
    /// Explicit mapping: streamIndex <- L3/L5 stream table index;
    /// streamHandle <- L3/L5 opaque stream handle. Both passthrough, both
    /// nil in the current SDR lane.
    public let streamIndex: Int?
    public let streamHandle: UInt64?
    /// Producer PTS timebase (L5 r5 (b)); nil = display seconds.
    public let ptsTimebase: GorAVTimebase?
    /// Producer presentation epoch (L5 r5 (b)): binds L5FrameProvenance
    /// 1:1 across renegotiation. Passthrough; nil when the producer has none.
    public let presentationEpoch: UInt64?
    public init(sessionID: String, sessionGeneration: UInt64, sequence: UInt64,
                surfaceRevision: UInt64, ptsSeconds: Double,
                trackRevision: UInt64? = nil, score: ScoreBinding? = nil,
                streamIndex: Int? = nil, streamHandle: UInt64? = nil,
                ptsTimebase: GorAVTimebase? = nil,
                presentationEpoch: UInt64? = nil, producerSource: SourceSession? = nil) {
        self.producerSource = producerSource
        self.sessionID = sessionID; self.sessionGeneration = sessionGeneration
        self.sequence = sequence; self.surfaceRevision = surfaceRevision
        self.ptsSeconds = ptsSeconds; self.trackRevision = trackRevision
        self.score = score
        self.streamIndex = streamIndex; self.streamHandle = streamHandle
        self.ptsTimebase = ptsTimebase
        self.presentationEpoch = presentationEpoch
    }
    /// Display/debug key. ATTRIBUTION NEVER USES THIS STRING ALONE:
    /// slots, leases and records match on FULL FrameIdentity equality
    /// (every field above), so a same-key-different-generation or
    /// different-track frame can never relabel another frame (r3 finding 2).
    public var leaseKey: String {
        "\(sessionID)#g\(sessionGeneration)#s\(sequence)@r\(surfaceRevision)#pts\(ptsSeconds)#tr\(trackRevision ?? 0)#sc\(score == nil ? 0 : 1)"
    }

    /// Canonical re-issue at a new surface revision (r4 finding 2): ALL
    /// other fields carried - stream index/handle, PTS timebase and
    /// presentation epoch included. Hand-copying fields drops them (the
    /// ghost identity the r6 presenter minted).
    public func withSurfaceRevision(_ rev: UInt64) -> FrameIdentity {
        FrameIdentity(sessionID: sessionID, sessionGeneration: sessionGeneration,
                      sequence: sequence, surfaceRevision: rev, ptsSeconds: ptsSeconds,
                      trackRevision: trackRevision, score: score,
                      streamIndex: streamIndex, streamHandle: streamHandle,
                      ptsTimebase: ptsTimebase, presentationEpoch: presentationEpoch, producerSource: producerSource)
    }
}

/// Mastering display primaries as CIE xy chromaticities (HDR provenance).
public struct MasteringPrimaries: Equatable, Sendable {
    public let rx: Double, ry: Double, gx: Double, gy: Double
    public let bx: Double, by: Double, wx: Double, wy: Double
    public init(rx: Double, ry: Double, gx: Double, gy: Double,
                bx: Double, by: Double, wx: Double, wy: Double) {
        self.rx = rx; self.ry = ry; self.gx = gx; self.gy = gy
        self.bx = bx; self.by = by; self.wx = wx; self.wy = wy
    }
    public var allFiniteInUnitRange: Bool {
        [rx, ry, gx, gy, bx, by, wx, wy].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
    }
}

/// Source HDR signal provenance (L5 requirement): what the decoder said the
/// source is. Optional; NIL for SDR. All fields range/finite-validated in
/// SurfaceContract.validated() (r2 finding 4).
public struct SourceSignal: Equatable, Sendable {
    public enum HDRTransfer: String, Sendable { case pq, hlg }
    public let transfer: HDRTransfer
    public let primaries: SurfaceContract.Primaries
    public let masteringMinNits: Double?
    public let masteringMaxNits: Double?
    public let maxCLL: Double?
    public let maxFALL: Double?
    public let masteringPrimaries: MasteringPrimaries?
    public init(transfer: HDRTransfer, primaries: SurfaceContract.Primaries,
                masteringMinNits: Double? = nil, masteringMaxNits: Double? = nil,
                maxCLL: Double? = nil, maxFALL: Double? = nil,
                masteringPrimaries: MasteringPrimaries? = nil) {
        self.transfer = transfer; self.primaries = primaries
        self.masteringMinNits = masteringMinNits; self.masteringMaxNits = masteringMaxNits
        self.maxCLL = maxCLL; self.maxFALL = maxFALL
        self.masteringPrimaries = masteringPrimaries
    }
}

public struct SurfaceContract: Equatable, Sendable {
    /// Working pixel formats with EXPLICIT byte order (L8 requirement).
    /// sdrRGBA8: bytes R,G,B,A per pixel, 8 bits, row stride width*4.
    /// edrRGBA16F: half-float RGBA holding LINEAR values for the EDR arm,
    /// row stride width*8; PQ/HLG source transforms run BEFORE the layer.
    public enum PixelFormat: String, Sendable { case sdrRGBA8, edrRGBA16F }
    /// Transfer function, named separately from primaries (L8: no implicit
    /// DeviceRGB; r2 finding 4: the linear/EDR arm needs real transfers,
    /// not gamma-only spaces).
    public enum Transfer: String, Sendable { case sRGB, linear, pq, hlg }
    public enum Primaries: String, Sendable { case bt709, displayP3, bt2020 }
    public enum AlphaSpace: String, Sendable { case premultiplied }
    public enum Origin: String, Sendable { case topLeftRowFirst }
    /// What the OUTPUT claims to be (L5 r5 (c)): an HDR source tone-mapped
    /// down to an SDR surface must NEVER wear a native-HDR label, and a
    /// native-SDR output must never carry unexplained HDR provenance.
    /// - nativeSDR: no source signal; sdrRGBA8; no EDR.
    /// - nativeHDR: source signal required; edrRGBA16F; EDR on.
    /// - tonemappedHDRtoSDR: source signal required (it is PROVENANCE of
    ///   the HDR original, not an output claim); EDR off; sdrRGBA8 or a
    ///   16F linear working surface.
    public enum OutputIntent: String, Sendable { case nativeSDR, nativeHDR, tonemappedHDRtoSDR }

    public let pixelFormat: PixelFormat
    public let transfer: Transfer
    public let primaries: Primaries
    public let alphaSpace: AlphaSpace
    public let origin: Origin
    /// SDR reference white in NITS (explicit unit, never unitless EDR 1.0).
    public let referenceWhiteNits: Double
    public let sourceSignal: SourceSignal?
    public let outputIntent: OutputIntent
    public let wantsEDR: Bool
    public let framebufferOnly: Bool
    public let drawableWidth: Int
    public let drawableHeight: Int
    /// Slot ring capacity (renderer-side bound, 1...3). The CAMetalLayer
    /// drawable pool is clamped to its own allowed 2...3 by the negotiator
    /// (r2 finding 7); a 1-slot ring still bounds GPU ownership to 1.
    public let maxInFlight: Int

    /// Public memberwise init (r2 finding 7: the synthesized init is
    /// internal; L5/L8 construct contracts from outside the module).
    public init(pixelFormat: PixelFormat, transfer: Transfer, primaries: Primaries,
                alphaSpace: AlphaSpace, origin: Origin, referenceWhiteNits: Double,
                sourceSignal: SourceSignal?, outputIntent: OutputIntent = .nativeSDR,
                wantsEDR: Bool, framebufferOnly: Bool,
                drawableWidth: Int, drawableHeight: Int, maxInFlight: Int) {
        self.pixelFormat = pixelFormat; self.transfer = transfer
        self.primaries = primaries; self.alphaSpace = alphaSpace; self.origin = origin
        self.referenceWhiteNits = referenceWhiteNits; self.sourceSignal = sourceSignal
        self.outputIntent = outputIntent
        self.wantsEDR = wantsEDR; self.framebufferOnly = framebufferOnly
        self.drawableWidth = drawableWidth; self.drawableHeight = drawableHeight
        self.maxInFlight = maxInFlight
    }

    public static let sdrDefault = SurfaceContract(pixelFormat: .sdrRGBA8,
                                                   transfer: .sRGB, primaries: .bt709,
                                                   alphaSpace: .premultiplied,
                                                   origin: .topLeftRowFirst,
                                                   referenceWhiteNits: 100.0,
                                                   sourceSignal: nil,
                                                   outputIntent: .nativeSDR,
                                                   wantsEDR: false,
                                                   framebufferOnly: true,
                                                   drawableWidth: 0, drawableHeight: 0,
                                                   maxInFlight: 3)

    public func withDrawableSize(width: Int, height: Int) -> SurfaceContract {
        SurfaceContract(pixelFormat: pixelFormat, transfer: transfer, primaries: primaries,
                        alphaSpace: alphaSpace, origin: origin,
                        referenceWhiteNits: referenceWhiteNits, sourceSignal: sourceSignal,
                        outputIntent: outputIntent,
                        wantsEDR: wantsEDR, framebufferOnly: framebufferOnly,
                        drawableWidth: width, drawableHeight: height, maxInFlight: maxInFlight)
    }

    /// L5 r5 (a) UNITS INVARIANT: for edrRGBA16F the working values are
    /// LINEAR and 1.0 == referenceWhiteNits nits, display-referred. The
    /// renderer stamps this value into every frame's params from the
    /// lease's immutable contract snapshot - the producer never overrides
    /// it per-frame, so the transfer/units invariant cannot drift.
    public var nitsPerUnit: Double { referenceWhiteNits }

    public enum NegotiationError: Error, Equatable {
        case edrRequiresFloatFormat
        case hdrWithoutSourceSignal
        case edrSurfaceWithoutEDR
        case invalidOutputIntent
        case invalidDrawableSize
        case invalidReferenceWhite
        case inFlightOutOfRange
        case invalidSourceSignal
        case unsupportedColorSpaceMapping
        /// E1 embed init strictness (XA9 compose2 question): the presenter
        /// view's CAMetalLayer must exist BEFORE parenting (wantsLayer=true
        /// creates it in init per AppKit contract, but a nil here is a typed
        /// refusal, never a silent skip of negotiation).
        case metalLayerUnavailable
    }

    /// Typed validation of the negotiation itself. Reject unsupported
    /// variants; never imply HDR via enum cases (r2 finding 4).
    public func validated() throws -> SurfaceContract {
        if wantsEDR && pixelFormat != .edrRGBA16F { throw NegotiationError.edrRequiresFloatFormat }
        // Output-intent consistency (L5 r5 (c)): the label must match the
        // surface, the EDR flags and the provenance exactly.
        switch outputIntent {
        case .nativeSDR:
            if sourceSignal != nil { throw NegotiationError.invalidOutputIntent }
            if pixelFormat != .sdrRGBA8 || wantsEDR { throw NegotiationError.invalidOutputIntent }
        case .nativeHDR:
            if sourceSignal == nil { throw NegotiationError.hdrWithoutSourceSignal }
            if pixelFormat != .edrRGBA16F { throw NegotiationError.edrRequiresFloatFormat }
            if !wantsEDR { throw NegotiationError.edrSurfaceWithoutEDR }
        case .tonemappedHDRtoSDR:
            if sourceSignal == nil { throw NegotiationError.hdrWithoutSourceSignal }
            if wantsEDR { throw NegotiationError.invalidOutputIntent }
        }
        if drawableWidth < 0 || drawableHeight < 0 { throw NegotiationError.invalidDrawableSize }
        // Reference white: finite nits, sane display range 1...10000.
        if !referenceWhiteNits.isFinite || referenceWhiteNits < 1 || referenceWhiteNits > 10000 {
            throw NegotiationError.invalidReferenceWhite
        }
        if maxInFlight < 1 || maxInFlight > 3 { throw NegotiationError.inFlightOutOfRange }
        if let s = sourceSignal {
            // HDR provenance: every declared value finite and in range.
            if let lo = s.masteringMinNits, !lo.isFinite || lo < 0 || lo > 10000 {
                throw NegotiationError.invalidSourceSignal
            }
            if let hi = s.masteringMaxNits, !hi.isFinite || hi <= 0 || hi > 10000 {
                throw NegotiationError.invalidSourceSignal
            }
            if let lo = s.masteringMinNits, let hi = s.masteringMaxNits, lo >= hi {
                throw NegotiationError.invalidSourceSignal
            }
            if let cll = s.maxCLL, !cll.isFinite || cll < 0 || cll > 100000 {
                throw NegotiationError.invalidSourceSignal
            }
            if let fall = s.maxFALL, !fall.isFinite || fall < 0 || fall > 100000 {
                throw NegotiationError.invalidSourceSignal
            }
            if let mp = s.masteringPrimaries, !mp.allFiniteInUnitRange {
                throw NegotiationError.invalidSourceSignal
            }
            // For a NATIVE HDR output the layer transfer must carry the
            // declared source transfer (or the explicit linear EDR arm).
            // A tone-mapped output deliberately converts, so no such
            // constraint applies (L5 r5 (c)).
            if outputIntent == .nativeHDR {
                switch (s.transfer, transfer) {
                case (.pq, .pq), (.hlg, .hlg), (_, .linear): break
                default: throw NegotiationError.invalidSourceSignal
                }
            }
        }
        // The colorspace mapping table must cover the combination.
        if SurfaceNegotiator.colorSpaceName(primaries: primaries, transfer: transfer) == nil {
            throw NegotiationError.unsupportedColorSpaceMapping
        }
        return self
    }

    /// Bounds checked before ANY allocation or upload (r2 findings 2/5).
    public static let maxTextureSide = 16384
    /// Real BYTE budget (r2 finding 5): the 16384 side cap alone permits
    /// ~1 GiB per RGBA8 texture x3 slots + readbacks. One frame may use at
    /// most 128 MiB (covers 4K rgba16Float = 67.5 MiB); the whole slot ring
    /// may hold at most 384 MiB.
    public static let maxFrameBytes = 128 * 1024 * 1024
    public static let maxAggregateSlotBytes = 384 * 1024 * 1024
    public static func frameBytesOK(width: Int, height: Int, bytesPerPixel: Int) -> Bool {
        let (px, o1) = width.multipliedReportingOverflow(by: height)
        let (bytes, o2) = px.multipliedReportingOverflow(by: bytesPerPixel)
        return !o1 && !o2 && bytes <= maxFrameBytes
    }
}

/// The single negotiation point: binds a contract to a CAMetalLayer,
/// INCLUDING the device assignment.
public enum SurfaceNegotiator {
    public static func metalPixelFormat(_ f: SurfaceContract.PixelFormat) -> MTLPixelFormat {
        switch f {
        case .sdrRGBA8: return .rgba8Unorm
        case .edrRGBA16F: return .rgba16Float
        }
    }
    /// The typed transfer x primaries -> CGColorSpace table (r2 finding 4).
    /// A combination NOT in the table is rejected by validated(), never
    /// silently mapped to DeviceRGB.
    public static func colorSpaceName(primaries: SurfaceContract.Primaries,
                                      transfer: SurfaceContract.Transfer) -> CFString? {
        switch (primaries, transfer) {
        case (.bt709, .sRGB): return CGColorSpace.sRGB
        case (.displayP3, .sRGB): return CGColorSpace.displayP3
        case (.bt2020, .sRGB): return CGColorSpace.itur_2020
        case (.bt709, .linear): return CGColorSpace.extendedLinearSRGB
        case (.displayP3, .linear): return CGColorSpace.extendedLinearDisplayP3
        case (.bt2020, .linear): return CGColorSpace.extendedLinearITUR_2020
        case (.bt2020, .pq): return CGColorSpace.itur_2100_PQ
        case (.bt2020, .hlg): return CGColorSpace.itur_2100_HLG
        default: return nil
        }
    }
    public static func apply(_ contract: SurfaceContract, to layer: CAMetalLayer, device: MTLDevice) throws {
        let c = try contract.validated()
        applyValidated(c, to: layer, device: device)
    }
    /// Apply an ALREADY validated contract (atomic transition handoff;
    /// validated() is the only throwing step).
    public static func applyValidated(_ c: SurfaceContract, to layer: CAMetalLayer, device: MTLDevice) {
        layer.device = device
        layer.pixelFormat = metalPixelFormat(c.pixelFormat)
        if let name = colorSpaceName(primaries: c.primaries, transfer: c.transfer) {
            layer.colorspace = CGColorSpace(name: name)
        }
        // wantsExtendedDynamicRangeContent is macOS 14+ (Package.swift
        // targets .v13): guard it. Behavior on 14+ is identical; on 13
        // the surface stays at its default SDR behavior (EDR not
        // available there), and the contract's own validated() already
        // binds wantsEDR to the 16F format. No deployment-target raise.
        if #available(macOS 14.0, *) {
            layer.wantsExtendedDynamicRangeContent = c.wantsEDR
        }
        layer.framebufferOnly = c.framebufferOnly
        // CAMetalLayer allows only 2...3 drawables (r2 finding 7); the
        // renderer's own ring enforces the contract's 1...3 bound.
        layer.maximumDrawableCount = max(2, min(3, c.maxInFlight))
        if c.drawableWidth > 0, c.drawableHeight > 0 {
            layer.drawableSize = CGSize(width: c.drawableWidth, height: c.drawableHeight)
        }
    }
}

/// L8 overlay seam, TYPED. The only supported representation today is the
/// SDR premultiplied working space; it is valid ONLY against an sdrRGBA8
/// contract (r2 finding 5: an SDR-gamma overlay composited into an HDR
/// linear surface is wrong, so the renderer rejects that typed).
public enum OverlayRepresentation: Sendable {
    case sdrRGBA8Premultiplied(rgba: [UInt8], width: Int, height: Int)
}

/// Overlay bound to the exact frame by full FrameIdentity.
/// L8 r4 question (b): FrameIdentity.trackRevision is the DECODER/source
/// track revision (passthrough; presenter-local seek fence until L3 exposes
/// one). The subtitle plan has a DIFFERENT semantic and gets its OWN field
/// here - subtitlePlanRevision is owned by the subtitle producer (L8),
/// carried opaquely, and echoed in receipts so L8 can verify WHICH plan was
/// composited. One field is never shared between the two semantics.
public struct PresenterOverlay: Sendable {
    public let identity: FrameIdentity
    public let representation: OverlayRepresentation
    public let frameX: Int
    public let frameY: Int
    public let frameW: Int
    public let frameH: Int
    /// L8-owned subtitle plan revision (opaque passthrough).
    public let subtitlePlanRevision: UInt64?
    public init(identity: FrameIdentity, representation: OverlayRepresentation,
                frameX: Int, frameY: Int, frameW: Int, frameH: Int,
                subtitlePlanRevision: UInt64? = nil) {
        self.identity = identity; self.representation = representation
        self.frameX = frameX; self.frameY = frameY; self.frameW = frameW; self.frameH = frameH
        self.subtitlePlanRevision = subtitlePlanRevision
    }
}

/// The named output-transform stage (L5 production seam). r2 finding 4: the
/// transform is BOUND to its kernel/arm provenance, carried into the
/// per-frame params so a scored readback can name what produced it.
public enum OutputTransform: Sendable {
    case identity
    /// MSL source defining `float4 goravOT(float4 c)`, plus the provenance
    /// of the scoring arm it belongs to.
    case customMSL(source: String, kernelVersion: String, armID: String)
}
#endif
