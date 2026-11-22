import Foundation

// P29-LIVE-CONTROL (DR-0021, lane c): photon-live-control.lua (M.VERSION=1)
// re-expressed as a pure Swift value-type model, under the 198o/OHAL-QUEUE
// reconciliation: goreda owns the gor shell twin; this is the separate
// gorav-side model. No gor shell file and no photon-hud surface is touched.
// The source is a live-only gamma actuator with zero mpv API usage; the
// caller remains owner of config construction, the observation feed, and
// output rounding + setter dedupe. Foundation only, time as parameter.
// INERT until the gor lane's LuaJIT witness passes; Lua stays authoritative.

/// One observation from the live path (source: profile table fields).
public struct LiveControlProfile: Equatable {
    public var doc: String
    public var id: Int
    public var t: Double
    public var pts: Double
    public var pbs: Double
    public init(doc: String, id: Int, t: Double, pts: Double, pbs: Double) {
        self.doc = doc; self.id = id; self.t = t; self.pts = pts; self.pbs = pbs
    }
}

/// Cut classification from the caller's scene logic (source: classify_cut
/// returns 'candidate' | 'confirmed' | nil).
public enum LiveControlCut: String, Equatable {
    case candidate, confirmed
}

/// Caller-supplied configuration (source: config table). All closures are
/// the caller's; the qualification fence only checks presence and the
/// numeric constants' finiteness/domain, exactly like the source.
public struct LiveControlConfig {
    public var initialGamma: Double
    public var qualified: Bool
    public var rate: Double
    public var staleAge: Double
    public var callbackGap: Double
    public var referenceInterval: Double
    public var retention: Double
    public var maxSettlementSamples: Int
    public var classifyCut: (LiveControlProfile, LiveControlProfile) -> LiveControlCut?
    public var settled: ([LiveControlProfile]) -> Bool
    public var target: (LiveControlProfile, Double) -> Double
    public var velocity: (LiveControlProfile, LiveControlProfile, Double) -> Double
    public var feed: ((LiveControlProfile) -> Void)?

    public init(initialGamma: Double, qualified: Bool = true, rate: Double, staleAge: Double,
                callbackGap: Double, referenceInterval: Double, retention: Double,
                maxSettlementSamples: Int,
                classifyCut: @escaping (LiveControlProfile, LiveControlProfile) -> LiveControlCut?,
                settled: @escaping ([LiveControlProfile]) -> Bool,
                target: @escaping (LiveControlProfile, Double) -> Double,
                velocity: @escaping (LiveControlProfile, LiveControlProfile, Double) -> Double,
                feed: ((LiveControlProfile) -> Void)? = nil) {
        self.initialGamma = initialGamma
        self.qualified = qualified
        self.rate = rate
        self.staleAge = staleAge
        self.callbackGap = callbackGap
        self.referenceInterval = referenceInterval
        self.retention = retention
        self.maxSettlementSamples = maxSettlementSamples
        self.classifyCut = classifyCut
        self.settled = settled
        self.target = target
        self.velocity = velocity
        self.feed = feed
    }
}

/// The actuator state after an observe/tick (source: diagnostics() table,
/// plus the returned value).
public struct LiveControlDecision: Equatable {
    public enum State: String, Equatable {
        case unknown = "UNKNOWN"
        case cutHold = "CUT_HOLD"
        case cutHoldUnknown = "CUT_HOLD_UNKNOWN"
        case ready = "READY"
    }
    public var state: State
    public var reason: String?
    public var cutPending: Bool
    public var settlementSamples: Int
    public var heldGamma: Double
    /// observe: whether state == .READY at return. tick: the gamma proposal.
    public var returned: Double?
}

public struct LiveControlActuator {
    static func finite(_ v: Double) -> Bool { v == v && v.magnitude < Double.infinity }

    public private(set) var config: LiveControlConfig
    public private(set) var gamma: Double
    public private(set) var state: LiveControlDecision.State = .unknown
    public private(set) var velocity: Double = 0
    public private(set) var target: Double? = nil
    public private(set) var previous: LiveControlProfile? = nil
    public private(set) var reason: String? = nil
    public private(set) var cutPending = false
    public private(set) var feedCount = 0

    private var doc: String? = nil
    private var lastId: Int? = nil
    private var lastPts: Double? = nil
    private var lastT: Double? = nil
    private var lastTick: Double? = nil
    private var cutProfiles: [LiveControlProfile]? = nil

    public init(config: LiveControlConfig) {
        precondition(LiveControlActuator.finite(config.initialGamma))
        self.config = config
        self.gamma = config.initialGamma
    }

    /// Config replacement is the caller's prerogative (source: config fields
    /// are read live each call); qualification is re-evaluated per call.
    public mutating func updateConfig(_ c: LiveControlConfig) { config = c }

    private func qualified() -> Bool {
        let c = config
        return c.qualified == true && LiveControlActuator.finite(c.rate) && c.rate > 0
            && LiveControlActuator.finite(c.staleAge) && c.staleAge > 0
            && LiveControlActuator.finite(c.callbackGap) && c.callbackGap > 0
            && LiveControlActuator.finite(c.referenceInterval) && c.referenceInterval > 0
            && LiveControlActuator.finite(c.retention) && c.retention > 0 && c.retention < 1
            && c.maxSettlementSamples >= 1
    }

    private mutating func hold(_ why: String) {
        state = cutPending ? .cutHoldUnknown : .unknown
        target = nil
        velocity = 0
        previous = nil
        reason = why
        if cutPending { cutProfiles = [] }
    }

    public func diagnostics() -> LiveControlDecision {
        LiveControlDecision(state: state, reason: reason, cutPending: cutPending,
                            settlementSamples: cutProfiles?.count ?? 0, heldGamma: gamma,
                            returned: nil)
    }

    @discardableResult
    public mutating func observe(_ profile: LiveControlProfile?) -> LiveControlDecision {
        guard let profile, LiveControlActuator.finite(profile.t),
              LiveControlActuator.finite(profile.pts), LiveControlActuator.finite(profile.pbs) else {
            hold("invalid-profile")
            return finish(returned: 0) // false
        }
        if doc != profile.doc {
            hold("document")
            doc = profile.doc
            lastId = nil; lastPts = nil; lastT = nil
            cutProfiles = nil
            cutPending = false
            state = .unknown
        }
        if let lastId, profile.id <= lastId || profile.pts <= lastPts! || profile.t <= lastT! {
            hold("repeated-profile")
            return finish(returned: 0)
        }
        var old = previous
        lastId = profile.id; lastPts = profile.pts; lastT = profile.t
        // Feed fresh observations even while gamma is held.
        feedCount += 1
        config.feed?(profile)
        guard qualified() else {
            hold("unqualified")
            return finish(returned: 0)
        }
        if let o = old, profile.t - o.t > config.staleAge {
            hold("observation-gap")
            old = nil
        }
        let cut = old.map { config.classifyCut($0, profile) } ?? nil
        if cut != nil {
            state = .cutHold
            cutPending = true
            velocity = 0
            target = nil
            cutProfiles = [profile]
        } else if cutPending {
            var window = cutProfiles ?? []
            if window.count >= config.maxSettlementSamples {
                window.removeFirst()
            }
            window.append(profile)
            cutProfiles = window
            if config.settled(window) == true {
                state = .ready
                reason = nil
                cutProfiles = nil
                cutPending = false
            } else {
                state = .cutHold
                reason = "settlement-unresolved"
            }
        } else {
            state = .ready
            reason = nil
        }
        if state == .ready {
            if let o = old {
                velocity = config.velocity(o, profile, velocity)
            } else {
                velocity = 0
            }
            let t = config.target(profile, velocity)
            guard LiveControlActuator.finite(t) else {
                hold("invalid-target")
                return finish(returned: 0)
            }
            target = t
        }
        previous = profile
        return finish(returned: state == .ready ? 1 : 0)
    }

    @discardableResult
    public mutating func tick(_ now: Double) -> LiveControlDecision {
        guard LiveControlActuator.finite(now) else {
            hold("invalid-clock")
            return finish(returned: nil)
        }
        let last = lastTick
        lastTick = now
        guard qualified() else {
            hold("unqualified")
            return finish(returned: nil)
        }
        guard let last else { return finish(returned: nil) }
        let dt = now - last
        guard dt > 0, dt <= config.callbackGap else {
            hold("callback-gap")
            return finish(returned: nil)
        }
        guard let lastT, now >= lastT, now - lastT <= config.staleAge else {
            hold("stale")
            return finish(returned: nil)
        }
        guard state == .ready, let target, LiveControlActuator.finite(target) else {
            return finish(returned: nil)
        }
        let distance = target - gamma
        let proposal = distance * (1 - pow(config.retention, dt / config.referenceInterval))
        var step = max(-config.rate * dt, min(config.rate * dt, proposal))
        if abs(step) > abs(distance) { step = distance }
        let candidate = gamma + step
        guard LiveControlActuator.finite(candidate) else {
            hold("invalid-actuator")
            return finish(returned: nil)
        }
        gamma = candidate
        return finish(returned: candidate)
    }

    private func finish(returned: Double?) -> LiveControlDecision {
        var d = diagnostics()
        d.returned = returned
        return d
    }
}
