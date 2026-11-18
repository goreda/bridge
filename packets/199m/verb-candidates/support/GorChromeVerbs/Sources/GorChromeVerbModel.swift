import Foundation

// Typed operation interface for three chrome verbs that the gorav host refuses
// at gor 55e11d70 (default branch of GorAVPlayerHost.handleChromeCommand):
//   transport-speed, audio-boost, capture-screenshot.
// Value types only. No AppKit, no engine import, no host wiring. A verb is
// applied only when the engine capability it needs is stated; an unknown
// capability is a typed refusal, never a silent default.

public enum GorVerbRefusal: Equatable, CustomStringConvertible {
    case nonFinite
    case nonPositive
    case outOfRange(lower: Double, upper: Double)
    case currentValueUnknown
    case engineUnsupported(String)
    case engineHeadroomUnknown
    case destinationUnspecified
    case modeUnsupported(String)
    case notOpen
    case noFrame

    public var description: String {
        switch self {
        case .nonFinite: return "value is not finite"
        case .nonPositive: return "value must be positive"
        case .outOfRange(let lower, let upper): return "value outside \(lower)...\(upper)"
        case .currentValueUnknown: return "current value unknown"
        case .engineUnsupported(let what): return "engine does not support \(what)"
        case .engineHeadroomUnknown: return "engine gain headroom unknown"
        case .destinationUnspecified: return "no destination"
        case .modeUnsupported(let mode): return "mode unsupported: \(mode)"
        case .notOpen: return "no open session"
        case .noFrame: return "no frame available"
        }
    }
}

public func gorCommandNumber(_ command: [Any], _ index: Int) -> Double? {
    guard command.indices.contains(index) else { return nil }
    if let n = command[index] as? NSNumber { return n.doubleValue }
    if let s = command[index] as? String { return Double(s) }
    return nil
}

public func gorCommandString(_ command: [Any], _ index: Int) -> String? {
    guard command.indices.contains(index) else { return nil }
    return command[index] as? String
}

/// Mirror of the host default branch detail rule (GorAVPlayerHost.swift, default case).
/// Used only to document the current refusal text; the guard test slices the host text.
public enum GorHostDefaultRefusal {
    public static func detail(_ command: [Any]) -> String {
        guard let name = gorCommandString(command, 0) else { return "" }
        let detail: String
        if name == "script-message-to" {
            detail = "script " + (gorCommandString(command, 1) ?? "unknown") + " " + (gorCommandString(command, 2) ?? "unknown")
        } else if ["set_property", "add", "cycle", "get_property"].contains(name) {
            detail = name + " " + (gorCommandString(command, 1) ?? "unknown")
        } else {
            detail = name
        }
        return String(detail.prefix(96))
    }
}

// MARK: - transport-speed

public struct GorSpeedLimits: Equatable {
    public let lower: Double
    public let upper: Double
    public init(lower: Double, upper: Double) { self.lower = lower; self.upper = upper }
    /// Owner decision pending: these are the bounds the interface enforces, not an engine measurement.
    public static let proposed = GorSpeedLimits(lower: 0.01, upper: 100)
}

public enum GorEngineRateCapability: Equatable { case none, supported }

public enum GorSpeedRequest: Equatable {
    case multiply(Double)
    case set(Double)

    /// Call sites (MenuActions.swift:246-250): ["multiply","speed",N] and ["set","speed",N].
    public static func parse(_ command: [Any]) -> GorSpeedRequest? {
        guard gorCommandString(command, 1) == "speed", let value = gorCommandNumber(command, 2) else { return nil }
        switch gorCommandString(command, 0) {
        case "multiply": return .multiply(value)
        case "set": return .set(value)
        default: return nil
        }
    }
}

public enum GorSpeedOutcome: Equatable {
    case applied(speed: Double)
    case refused(GorVerbRefusal)
}

public enum GorSpeedVerb {
    /// Order: finite, positive, current value (multiply only), range, capability.
    public static func resolve(_ request: GorSpeedRequest, currentSpeed: Double?, limits: GorSpeedLimits = .proposed, capability: GorEngineRateCapability) -> GorSpeedOutcome {
        let target: Double
        switch request {
        case .set(let value):
            guard value.isFinite else { return .refused(.nonFinite) }
            guard value > 0 else { return .refused(.nonPositive) }
            target = value
        case .multiply(let factor):
            guard factor.isFinite else { return .refused(.nonFinite) }
            guard factor > 0 else { return .refused(.nonPositive) }
            guard let current = currentSpeed, current.isFinite, current > 0 else { return .refused(.currentValueUnknown) }
            target = current * factor
        }
        guard target >= limits.lower, target <= limits.upper else { return .refused(.outOfRange(lower: limits.lower, upper: limits.upper)) }
        guard capability == .supported else { return .refused(.engineUnsupported("rate control")) }
        return .applied(speed: target)
    }
}

// MARK: - audio-boost

public enum GorEngineGainCapability: Equatable {
    case unknown
    case unityOnly
    case boosted(maxLinear: Double)
}

public struct GorVolumeBoostRequest: Equatable {
    public let volumeMaxPercent: Double
    public init(volumeMaxPercent: Double) { self.volumeMaxPercent = volumeMaxPercent }

    /// Call site (MenuActions.swift:1926): ["set_property","volume-max",200].
    public static func parse(_ command: [Any]) -> GorVolumeBoostRequest? {
        guard gorCommandString(command, 0) == "set_property", gorCommandString(command, 1) == "volume-max",
              let value = gorCommandNumber(command, 2) else { return nil }
        return GorVolumeBoostRequest(volumeMaxPercent: value)
    }
}

public enum GorBoostOutcome: Equatable {
    case applied(maxLinear: Double)
    case refused(GorVerbRefusal)
}

public enum GorBoostVerb {
    /// 100 percent is unity by definition. ceilingPercent is the interface cap (owner decision pending).
    public static let unityPercent = 100.0
    public static let proposedCeilingPercent = 200.0

    public static func resolve(_ request: GorVolumeBoostRequest, ceilingPercent: Double = proposedCeilingPercent, capability: GorEngineGainCapability) -> GorBoostOutcome {
        let percent = request.volumeMaxPercent
        guard percent.isFinite else { return .refused(.nonFinite) }
        guard percent >= unityPercent, percent <= ceilingPercent else {
            return .refused(.outOfRange(lower: unityPercent, upper: ceilingPercent))
        }
        switch capability {
        case .unknown: return .refused(.engineHeadroomUnknown)
        case .unityOnly: return .refused(.engineUnsupported("gain above unity"))
        case .boosted(let maxLinear):
            guard maxLinear.isFinite, maxLinear >= 1 else { return .refused(.engineHeadroomUnknown) }
            guard percent / 100 <= maxLinear else { return .refused(.outOfRange(lower: unityPercent, upper: maxLinear * 100)) }
            return .applied(maxLinear: percent / 100)
        }
    }
}

// MARK: - capture-screenshot

public enum GorScreenshotMode: String, Equatable { case subtitles, video, window }

public struct GorScreenshotRequest: Equatable {
    public let mode: GorScreenshotMode
    public init(mode: GorScreenshotMode) { self.mode = mode }

    /// Call sites (MenuActions.swift:437-439): ["screenshot","subtitles"|"video"|"window"].
    public static func parse(_ command: [Any]) -> GorScreenshotRequest? {
        guard gorCommandString(command, 0) == "screenshot", let raw = gorCommandString(command, 1),
              let mode = GorScreenshotMode(rawValue: raw) else { return nil }
        return GorScreenshotRequest(mode: mode)
    }
}

public struct GorScreenshotCapabilities: Equatable {
    public var isOpen: Bool
    public var frameTap: Bool
    public var subtitleComposite: Bool
    public var windowCapture: Bool
    public init(isOpen: Bool, frameTap: Bool, subtitleComposite: Bool, windowCapture: Bool) {
        self.isOpen = isOpen; self.frameTap = frameTap; self.subtitleComposite = subtitleComposite; self.windowCapture = windowCapture
    }
    /// Current state at gor 55e11d70: nothing is wired, so every mode refuses.
    public static let currentDefault = GorScreenshotCapabilities(isOpen: false, frameTap: false, subtitleComposite: false, windowCapture: false)
}

public enum GorScreenshotOutcome: Equatable {
    case capture(mode: GorScreenshotMode, destination: String)
    case refused(GorVerbRefusal)
}

public enum GorScreenshotVerb {
    /// Order: open, destination, mode capability, frame availability. The destination is required
    /// because the call sites carry none and no screenshot directory policy exists here.
    public static func resolve(_ request: GorScreenshotRequest, destination: String?, capabilities: GorScreenshotCapabilities, frameAvailable: Bool) -> GorScreenshotOutcome {
        guard capabilities.isOpen else { return .refused(.notOpen) }
        guard let destination, !destination.isEmpty else { return .refused(.destinationUnspecified) }
        switch request.mode {
        case .window:
            guard capabilities.windowCapture else { return .refused(.modeUnsupported("window")) }
        case .subtitles:
            guard capabilities.subtitleComposite else { return .refused(.modeUnsupported("subtitles")) }
            guard capabilities.frameTap else { return .refused(.engineUnsupported("frame tap")) }
        case .video:
            guard capabilities.frameTap else { return .refused(.engineUnsupported("frame tap")) }
        }
        guard frameAvailable else { return .refused(.noFrame) }
        return .capture(mode: request.mode, destination: destination)
    }
}
