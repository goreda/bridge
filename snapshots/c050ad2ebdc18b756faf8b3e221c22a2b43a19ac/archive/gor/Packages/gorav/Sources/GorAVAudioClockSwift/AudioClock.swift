// GorAVAudioClockSwift - thin Swift binding over the GorAVAudioClock C core
// (GP-47 r2 candidate, pinned zip sha256 1cc4c76cf1868ff98e260275a14392dc1cc41481d6d36da14e1d8c1098ecf47d).
//
// The binding is a 1:1 semantic mirror of gorav_audio_clock.h: every status
// and decision value maps by its C raw value, every refusal is reported,
// nothing is substituted. The C core never reads a system clock; the owner
// supplies the shared origin host clock here, once, at init.
//
// Threading: the C core has no internal locking; serialize external access
// like any single-owner session object. This class intentionally does NOT
// conform to Sendable.

import GorAVAudioClock

public enum AudioClockStatus: Int32, Equatable, Sendable {
    case ok = 0
    case noMaster = 1
    case staleGeneration = 2
    case inconsistent = 3
    case rateChange = 4
    case latencyUnknown = 5
    case invalidArgument = 6
    case insufficientAnchors = 7

    init(_ c: gvac_status) {
        let raw: Int32 = numericCast(c.rawValue)
        self = AudioClockStatus(rawValue: raw) ?? .invalidArgument
    }
}

public enum AudioClockSyncDecision: Equatable, Sendable {
    case show
    case wait
    case dropLate

    init(_ c: gvac_sync_decision) {
        switch c.rawValue {
        case 0: self = .show
        case 1: self = .wait
        default: self = .dropLate
        }
    }
}

private final class HostClockBox {
    let clock: () -> Double
    init(_ clock: @escaping () -> Double) { self.clock = clock }
}

public final class AudioClock {
    /// Mirrors GVAC_LATENCY_UNKNOWN in gorav_audio_clock.h: pass as the
    /// latency when the sink has no proven value; the call then fails with
    /// .latencyUnknown and the out value stays untouched.
    public static let latencyUnknown: Double = -1.0

    private let handle: OpaquePointer
    private let box: Unmanaged<HostClockBox>

    /// hostClock: monotonic seconds on the owner's SHARED origin clock (the
    /// same authority TimingLedger uses). Called by the C core, never a
    /// system clock.
    public init?(hostClock: @escaping () -> Double) {
        let box = Unmanaged.passRetained(HostClockBox(hostClock))
        self.box = box
        guard let h = gvac_create({ ctx in
            Unmanaged<HostClockBox>.fromOpaque(ctx!).takeUnretainedValue().clock()
        }, box.toOpaque()) else {
            box.release()
            return nil
        }
        self.handle = h
    }

    deinit {
        gvac_destroy(handle)
        box.release()
    }

    /// Anchor (or re-anchor) the audio/host correlation for a generation.
    /// consumedSamples is the sink's OWN device-consumed counter at hostTime;
    /// submitted-but-unheard buffers are never counted (8.2).
    @discardableResult
    public func anchor(generation: UInt64, consumedSamples: Int64,
                       sampleRate: UInt32, hostTime: Double,
                       consistencyTolerance: Double) -> AudioClockStatus {
        AudioClockStatus(gvac_anchor(handle, generation, consumedSamples,
                                     sampleRate, hostTime, consistencyTolerance))
    }

    /// Fence all anchors up to and including `generation` (teardown / K3 reset).
    public func fence(generation: UInt64) {
        gvac_fence(handle, generation)
    }

    public func mediaTime(atHost hostTime: Double) -> (status: AudioClockStatus, mediaTime: Double?) {
        var out = 0.0
        let st = AudioClockStatus(gvac_media_time(handle, hostTime, &out))
        return (st, st == .ok ? out : nil)
    }

    public func expectedSamples(atHost hostTime: Double) -> (status: AudioClockStatus, samples: Int64?) {
        var out: Int64 = 0
        let st = AudioClockStatus(gvac_expected_samples(handle, hostTime, &out))
        return (st, st == .ok ? out : nil)
    }

    public func hostDeadline(pts: Double, latency: Double) -> (status: AudioClockStatus, hostDeadline: Double?) {
        var out = 0.0
        let st = AudioClockStatus(gvac_host_deadline(handle, pts, latency, &out))
        return (st, st == .ok ? out : nil)
    }

    /// earlyWindow / lateThreshold are caller-fixed policy (G-A11); both must
    /// be finite and >= 0 or the call refuses with .invalidArgument.
    public func classifyFrame(pts: Double, nowHost: Double, latency: Double,
                              earlyWindow: Double, lateThreshold: Double)
        -> (status: AudioClockStatus, decision: AudioClockSyncDecision?, waitUntilHost: Double?) {
        var dec = gvac_sync_decision(rawValue: 0)
        var waitUntil = 0.0
        let st = AudioClockStatus(gvac_classify_frame(handle, pts, nowHost, latency,
                                                      earlyWindow, lateThreshold, &dec, &waitUntil))
        guard st == .ok else { return (st, nil, nil) }
        return (st, AudioClockSyncDecision(dec), waitUntil)
    }

    public func driftPPM() -> (status: AudioClockStatus, ppm: Double?) {
        var out = 0.0
        let st = AudioClockStatus(gvac_drift_ppm(handle, &out))
        return (st, st == .ok ? out : nil)
    }

    public var currentGeneration: UInt64 { gvac_current_generation(handle) }
    public var hasMaster: Bool { gvac_has_master(handle) }
}
