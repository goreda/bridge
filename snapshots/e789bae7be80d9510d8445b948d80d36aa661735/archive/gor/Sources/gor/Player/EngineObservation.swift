//
//  EngineObservation.swift
//  gor - G4 observation surface (arch-195b, gor side)
//
//  Engine-neutral view of the player properties PPController observes today.
//  The mpv PollEngine keeps its exact tiers and cadence; this file owns:
//    - EngineProperty: the neutral keys and the single-source mpv<->neutral
//      name mapping (no mpv property name literal anywhere upstream),
//    - EngineObservedState: the typed snapshot consumers (G5 control bus,
//      G6 presentation receipt) read instead of raw [String: Any] stores,
//    - EngineObservationTranslator: pure store-snapshot -> state translation,
//    - EngineObservationCenter: the live sink PPController publishes every
//      poll flush into; consumers add observers or poll latest().
//  A future gorav backend publishes the same EngineObservedState and no
//  consumer changes.
//
//  Foundation-only on purpose: the file compiles and is checked on Linux
//  (no AppKit) via g4-observation-tests/main.swift.
//

import Foundation

// MARK: - EngineProperty (neutral keys, single-source mpv mapping)

/// The properties of the G4 observation surface. The Swift case name is the
/// engine-neutral key; the raw value is the mpv property name (the ONLY
/// place mpv names for this surface are written down).
public enum EngineProperty: String, CaseIterable {
    case timePos = "time-pos"
    case duration = "duration"
    case paused = "pause"
    case eofReached = "eof-reached"
    case idleActive = "idle-active"
    case metadata = "metadata"
    case mediaTitle = "media-title"
    case videoDisplayWidth = "video-params/dw"
    case videoDisplayHeight = "video-params/dh"
    case videoStereoMode = "video-params/stereo-in"
    case videoRotation = "video-params/rotate"
    case displayWidth = "dwidth"
    case displayHeight = "dheight"
    case containerFPS = "container-fps"
    case estimatedVideoFPS = "estimated-vf-fps"
    case displayFPS = "display-fps"
    case frameDropCount = "frame-drop-count"
    case decoderFrameDropCount = "decoder-frame-drop-count"
    case hwdecCurrent = "hwdec-current"

    /// mpv-side property name for IPC tables (PollEngine tiers).
    public var mpvName: String { rawValue }
    /// Engine-neutral key (the Swift case name).
    public var neutralName: String { String(describing: self) }
}

// MARK: - EngineObservedState (typed snapshot)

public struct EngineVideoParams: Equatable {
    public var displayWidth: Double?
    public var displayHeight: Double?
    public var stereoMode: String?
    public var rotationDegrees: Double?
    public init(displayWidth: Double? = nil, displayHeight: Double? = nil,
                stereoMode: String? = nil, rotationDegrees: Double? = nil) {
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.stereoMode = stereoMode
        self.rotationDegrees = rotationDegrees
    }
}

public struct EngineObservedState: Equatable {
    public var timePos: Double?
    public var duration: Double?
    public var paused: Bool?
    public var eofReached: Bool?
    public var idleActive: Bool?
    public var metadata: [String: String]?
    public var mediaTitle: String?
    public var videoParams: EngineVideoParams
    public var displayWidth: Double?
    public var displayHeight: Double?
    public var containerFPS: Double?
    public var estimatedVideoFPS: Double?
    public var displayFPS: Double?
    public var frameDropCount: Int?
    public var decoderFrameDropCount: Int?
    public var hwdecCurrent: String?
    public init() {
        videoParams = EngineVideoParams()
    }
}

// MARK: - EngineObservationTranslator (pure)

public enum EngineObservationTranslator {
    /// Raw poll-store snapshot (mpv property names, JSON-decoded values) ->
    /// typed neutral state. A missing, NSNull, or mistyped entry maps to nil,
    /// never to a fabricated default. Values pass through as delivered,
    /// including NaN/inf (mirrors today's store semantics; consumers decide).
    public static func translate(_ results: [String: Any]) -> EngineObservedState {
        func double(_ p: EngineProperty) -> Double? {
            guard let v = results[p.mpvName] else { return nil }
            if let d = v as? Double { return d }
            if let n = v as? NSNumber { return n.doubleValue }
            if let i = v as? Int { return Double(i) }
            return nil
        }
        func bool(_ p: EngineProperty) -> Bool? {
            guard let v = results[p.mpvName] else { return nil }
            if let b = v as? Bool { return b }
            if let n = v as? NSNumber { return n.boolValue }
            return nil
        }
        func int(_ p: EngineProperty) -> Int? {
            guard let v = results[p.mpvName] else { return nil }
            // Exact bridging first: integer NSNumbers land here; a fractional
            // NSNumber fails this cast instead of truncating.
            if let i = v as? Int { return i }
            // Fractional Doubles are rejected, never truncated.
            if let d = v as? Double { return d == d.rounded() ? Int(d) : nil }
            if let n = v as? NSNumber { return n.intValue }
            return nil
        }
        func string(_ p: EngineProperty) -> String? {
            guard let v = results[p.mpvName] else { return nil }
            return v as? String
        }
        var state = EngineObservedState()
        state.timePos = double(.timePos)
        state.duration = double(.duration)
        state.paused = bool(.paused)
        state.eofReached = bool(.eofReached)
        state.idleActive = bool(.idleActive)
        state.mediaTitle = string(.mediaTitle)
        if let m = results[EngineProperty.metadata.mpvName] as? [String: String] {
            state.metadata = m
        } else if let m = results[EngineProperty.metadata.mpvName] as? [String: Any] {
            // Mixed-value dictionaries keep only their string entries.
            var out = [String: String]()
            for (k, v) in m { if let s = v as? String { out[k] = s } }
            state.metadata = out
        }
        state.videoParams = EngineVideoParams(
            displayWidth: double(.videoDisplayWidth),
            displayHeight: double(.videoDisplayHeight),
            stereoMode: string(.videoStereoMode),
            rotationDegrees: double(.videoRotation))
        state.displayWidth = double(.displayWidth)
        state.displayHeight = double(.displayHeight)
        state.containerFPS = double(.containerFPS)
        state.estimatedVideoFPS = double(.estimatedVideoFPS)
        state.displayFPS = double(.displayFPS)
        state.frameDropCount = int(.frameDropCount)
        state.decoderFrameDropCount = int(.decoderFrameDropCount)
        state.hwdecCurrent = string(.hwdecCurrent)
        return state
    }
}

// MARK: - EngineObservationCenter (live sink)

/// The single publication point for the neutral surface. PPController's
/// PollEngine ingests one translated snapshot per flush; G5/G6 consumers
/// either poll latest() or register an observer. Thread-safe; observers are
/// called synchronously on the ingesting queue (the main queue in the
/// shipped wiring) in registration order, after `current` is updated.
public final class EngineObservationCenter {
    public static let shared = EngineObservationCenter()
    public typealias Observer = (EngineObservedState) -> Void

    private let lock = NSLock()
    private var current: EngineObservedState?
    private var observers: [Int: Observer] = [:]
    private var nextToken = 0
    /// Total ingests since process start; checks and future liveness use it.
    public private(set) var ingestedCount: UInt64 = 0

    public init() {}

    public func ingest(_ state: EngineObservedState) {
        lock.lock()
        current = state
        ingestedCount &+= 1
        let snapshot = observers.sorted { $0.key < $1.key }.map { $0.value }
        lock.unlock()
        for observer in snapshot { observer(state) }
    }

    public func latest() -> EngineObservedState? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// Returns a token for removeObserver(_:).
    @discardableResult
    public func addObserver(_ observer: @escaping Observer) -> Int {
        lock.lock()
        let token = nextToken
        nextToken += 1
        observers[token] = observer
        lock.unlock()
        return token
    }

    public func removeObserver(_ token: Int) {
        lock.lock()
        observers[token] = nil
        lock.unlock()
    }
}
