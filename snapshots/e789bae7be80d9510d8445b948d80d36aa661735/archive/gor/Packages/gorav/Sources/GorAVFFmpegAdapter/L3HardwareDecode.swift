// AUTHORED NEW (2026-10-25, L3 formats/hardware-decode lane).
// VideoToolbox hardware-decode session with MEASURED software fallback.
// Every state transition is recorded in the receipt; nothing is inferred from
// the configure line. Off-Darwin builds attach nothing (shim returns -2) and
// the receipt says so.
import Foundation
import CFFmpeg
import GorAVCore

public final class L3HardwareSession {
    public var nativeProducer: VTHardwareFrameProducer?
    public func noteIndependentAttach(_ attached: Bool) {
        receipt.attempted = true
        receipt.attachResult = attached ? 0 : -1
    }

    /// Session-scoped hardware receipt, readable after close for the run report.
    /// Review (sticky-flag critique): activeEver/activeCurrent are separate.
    /// "Ever" is a lifetime fact; "current" is the mode NOW; softwareFallbacks
    /// counts REAL provider reopens, each confirmed by a successful software
    /// open2 - a returned intent is never counted as a clean fallback.
    public struct Receipt: Equatable, Sendable {
        public var attempted = false        // VT attach was requested
        public var attachResult = 0         // 0 attached, -1 device create failed, -2 off-Darwin
        public var activeEver = false       // VT format negotiated at least once
        public var activeCurrent = false    // VT is the decode mode right now
        public var hardwareFrames = 0       // frames transferred out of VT
        public var transferErrors = 0       // av_hwframe_transfer_data failures
        public var softwareFallbacks = 0    // confirmed software provider reopens
        public var fallbackArmed = false    // session now decodes software after a hw failure
        // P30 (arch-196z E1) zero-copy additions; additive, defaults keep old
        // producers valid. Field semantics are MEASURED: each is incremented
        // at the operation it names, never inferred from the configure line.
        public var vtFramesZeroCopy = 0     // VT frames passed through with NO av_hwframe_transfer_data
        public var cpuFrameCopies = 0       // av_hwframe_transfer_data executions / derived-copy plane copies
        public var cpuYUVtoRGB = 0          // CPU YUV->RGB conversions on the present path
        public var ioSurfaceBackedFrames = 0 // presented frames with CVPixelBufferGetIOSurface != nil
        public var fallbackReason: String? = nil // typed HUD token (GorAVEmbeddedSession.fallbackReason vocabulary); nil on the hardware path

        /// One-line run-report row ops enforces (field order is the
        /// contract). P30 gate on an admitted hwdec file:
        /// hwdec=videotoolbox, cpuCopies=0, cpuYUVtoRGB=0, iosurface>0. A
        /// software file carries its typed reason.
        public func receiptLine() -> String {
            "VTRECEIPT hwdec=\(activeCurrent ? "videotoolbox" : "no") vtZeroCopy=\(vtFramesZeroCopy) cpuCopies=\(cpuFrameCopies) cpuYUVtoRGB=\(cpuYUVtoRGB) iosurface=\(ioSurfaceBackedFrames) fallback=\(fallbackReason ?? "-") hwFrames=\(hardwareFrames) transferErrors=\(transferErrors) swFallbacks=\(softwareFallbacks)"
        }
    }

    /// One-line run-report row ops enforces (field order is the contract).
    public func receiptLine() -> String { receipt.receiptLine() }

    /// v4 adversarial-test hook (module-internal; set only from the decoder's
    /// DEBUG injection entry point): the next processReceivedFrame takes the
    /// REAL hardware-failure branch - the actual reopen path runs, not a stub.
    var forceNextReceiveFailure = false

    /// P30/W2 (arch-197b): when armed, pipelineStep runs
    /// processReceivedFrameZeroCopy instead of processReceivedFrame - VT
    /// frames stay GPU-resident for the CVMetalTextureCache present path.
    /// Software frames pass through BOTH variants untouched, so arming is
    /// inert off-Darwin and on software-decoded files. Policy:
    /// Product zero-copy preference defaults on. GORAV_VT_ZEROCOPY=0 is
    /// the explicit diagnostic opt-out; require-mode gate policy is unchanged.
    public private(set) var zeroCopyArmed = false
    public func armZeroCopy(environment: [String: String] = ProcessInfo.processInfo.environment) {
        zeroCopyArmed = environment["GORAV_VT_ZEROCOPY"] != "0"
    }

    /// P30/W2 transfer-on-demand: the zero-copy lane's typed fallback. When a
    /// retained VT frame cannot present GPU-resident (unresolved colour, HDR
    /// transfer, full range, untexturable CV format), the derived-copy path
    /// runs the REAL av_hwframe_transfer_data here - counted as a CPU frame
    /// copy - and the returned software frame feeds the existing derived
    /// machinery (consent gate, matrix naming, bounded planes). nil on
    /// allocation or transfer failure (the shim counts the transfer error).
    public func transferToSoftwareCopy(_ frame: UnsafeMutablePointer<AVFrame>) -> UnsafeMutablePointer<AVFrame>? {
        var sw: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard sw != nil else { return nil }
        let rc = gorav_l3_hw_transfer(sw, frame, state)
        if rc < 0 { av_frame_free(&sw); syncReceipt(); return nil }
        receipt.cpuFrameCopies += 1
        syncReceipt()
        return sw
    }
    /// P30/W2: a CPU frame copy performed by a caller outside this class
    /// (none today - transfer sites live here; the entry point keeps the
    /// receipt the single writer of its own fields).
    public func noteCPUFrameCopies(_ n: Int = 1) { receipt.cpuFrameCopies += n }

    private let state: UnsafeMutablePointer<GorAVL3HWState>
    public private(set) var receipt = Receipt()
    /// One re-arm per session: after the detach there is no hardware left to
    /// fail, so a larger bound was an untrue claim.
    public static let maxSoftwareFallbacks = 1

    public init() {
        state = UnsafeMutablePointer<GorAVL3HWState>.allocate(capacity: 1)
        state.initialize(to: GorAVL3HWState(hw_attempted: 0, hw_active: 0, hw_frames: 0,
                                            hw_transfer_errors: 0, hw_disabled: 0))
    }
    deinit {
        state.deinitialize(count: 1)
        state.deallocate()
    }

    public enum FrameOutcome: Equatable {
        case ok
        case refused(String)
        case hardwareFailed(Int)
    }

    /// Attaches VideoToolbox if policy admits this codec. Returns true when an
    /// attempt was made AND the device context attached; the receipt records
    /// every outcome either way. Call before avcodec_open2.
    @discardableResult
    public func attachIfAdmitted(codecContext: UnsafeMutablePointer<AVCodecContext>,
                                 videoCodecName: String,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard AdmissionTable.shouldAttemptHardware(videoCodec: videoCodecName, environment: environment) else {
            receipt.attempted = false
            return false
        }
        let rc = gorav_l3_attach_videotoolbox(codecContext, state)
        receipt.attempted = true
        receipt.attachResult = Int(rc)
        if rc != 0 { noteFallbackReason(rc == -2 ? "vt-unavailable-platform" : "vt-device-attach-failed") }
        syncReceipt()
        return rc == 0
    }

    /// Processes one frame right after avcodec_receive_frame/av_frame_clone:
    /// a hardware frame is transferred to a new software frame (which replaces
    /// `frame`); software frames pass through untouched. On a transfer error
    /// the frame is freed, the error is recorded, and .hardwareFailed is
    /// returned so the caller can arm the software fallback.
    public func processReceivedFrame(_ frame: inout UnsafeMutablePointer<AVFrame>?) -> FrameOutcome {
        if forceNextReceiveFailure {
            forceNextReceiveFailure = false
            if frame != nil { av_frame_free(&frame) }
            receipt.transferErrors += 1
            noteFallbackReason("vt-forced-receive-failure")
            return .hardwareFailed(-1001)
        }
        guard let f = frame else { return .refused("L3: nil frame after clone") }
        syncReceipt()
        guard f.pointee.format == gorav_l3_pixfmt_videotoolbox() else { return .ok }
        var sw: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard sw != nil else {
            av_frame_free(&frame)
            return .refused("L3: software transfer frame allocation failed")
        }
        let rc = gorav_l3_hw_transfer(sw, f, state)
        if rc < 0 {
            noteFallbackReason("vt-frame-transfer-failed")
            av_frame_free(&sw)
            av_frame_free(&frame)
            syncReceipt()
            return .hardwareFailed(Int(rc))
        }
        receipt.cpuFrameCopies += 1 // P30: the transfer IS a CPU copy; counted
        av_frame_free(&frame)
        frame = sw
        syncReceipt()
        return .ok
    }

    /// P30 zero-copy variant (arch-196z E1): a VT-format frame passes
    /// through WITHOUT av_hwframe_transfer_data; the Darwin consumer
    /// (ShellFrameSource / E1 VT leg) extracts the CVPixelBuffer (data[3])
    /// and textures it via CVMetalTextureCache. Software frames pass
    /// through untouched. Same failure-injection contract as the transfer
    /// variant. Counted in vtFramesZeroCopy; nothing is transferred, freed
    /// or re-created.
    public func processReceivedFrameZeroCopy(_ frame: inout UnsafeMutablePointer<AVFrame>?) -> FrameOutcome {
        if forceNextReceiveFailure {
            forceNextReceiveFailure = false
            if frame != nil { av_frame_free(&frame) }
            receipt.transferErrors += 1
            noteFallbackReason("vt-forced-receive-failure")
            return .hardwareFailed(-1001)
        }
        guard let f = frame else { return .refused("L3: nil frame after clone") }
        syncReceipt()
        guard f.pointee.format == gorav_l3_pixfmt_videotoolbox() else { return .ok }
        receipt.vtFramesZeroCopy += 1
        return .ok
    }

    /// P30 counters owned by callers outside this class (the present path):
    /// CPU YUV->RGB conversions and IOSurface-provenance reads. Each call
    /// records an ACTUAL operation the caller performed.
    public func noteCPUYUVtoRGB(_ n: Int = 1) { receipt.cpuYUVtoRGB += n }
    public func noteIOSurfaceBackedFrames(_ n: Int = 1) { receipt.ioSurfaceBackedFrames += n }
    /// Binds the per-file fallback HUD reason (fallbackReason vocabulary)
    /// the first time the session arms the software fallback.
    public func noteFallbackReason(_ reason: String) {
        if receipt.fallbackReason == nil { receipt.fallbackReason = reason }
    }

    /// Detaches VT from a codec context that is about to be freed or retried
    /// software-only. Does NOT count a fallback: the count moves only when
    /// the software provider reopen actually succeeds (noteSoftwareReopen-
    /// Succeeded). The decoder owns the reopen; this owns the receipt.
    public func detachForSoftwareReopen(codecContext: UnsafeMutablePointer<AVCodecContext>? = nil) {
        gorav_l3_detach_hardware(codecContext, state)
        receipt.fallbackArmed = true
        receipt.activeCurrent = false
    }

    /// Called by the decoder after a software avcodec_open2 succeeded.
    public func noteSoftwareReopenSucceeded() {
        receipt.softwareFallbacks += 1
        receipt.fallbackArmed = true
        receipt.activeCurrent = false
    }

    private func syncReceipt() {
        let s = state.pointee
        receipt.activeEver = receipt.activeEver || s.hw_active != 0
        receipt.activeCurrent = s.hw_active != 0 && !receipt.fallbackArmed
        receipt.hardwareFrames = Int(s.hw_frames)
        receipt.transferErrors = Int(s.hw_transfer_errors)
    }
}
