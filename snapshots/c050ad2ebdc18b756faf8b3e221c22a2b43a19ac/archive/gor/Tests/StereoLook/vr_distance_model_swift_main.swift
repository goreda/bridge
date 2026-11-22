import Foundation

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func expect(_ ok: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !ok() { throw CheckFailure(description: message) }
}
func near(_ value: Double?, _ expected: Double, _ message: String,
          tolerance: Double = 1e-9) throws {
    guard let value, value.isFinite, abs(value - expected) <= tolerance else {
        throw CheckFailure(description: "\(message): expected \(expected), got \(String(describing: value))")
    }
}
// This calls the actual Swift source. Expected values below are numeric
// fixtures, not a second implementation of the model.
func evaluate(_ model: VRLookDistanceModel, width: Double = 1_000,
              offset: Double? = 0, nudge: Double = 0.2,
              now: Double = 10) -> VRLookDistanceModel.Outcome {
    let outcome = model.evaluate(osdWidth: width, vrFov: 90, manualFov: 0,
                   fovMinDeg: 45, fovMaxDeg: 120, ipdNudge: nudge,
                   ipdOffsetMM: offset, parallaxEnabled: false,
                   parallaxDisparity: -0.4, parallaxStrength: 0.4, now: now)
    print("MODEL now=\(now) width=\(width) outcomeReason=\(outcome.reason) trace=\(outcome.trace)")
    return outcome
}
func sample(_ distance: Double? = nil, scale: Double? = 0.2,
            reason: String? = nil, at: Double = 10) -> VRLookDistanceModel {
    var model = VRLookDistanceModel()
    model.acceptDistance(dMM: distance, reason: reason, mmPerPx: scale, now: at)
    return model
}
func json(_ outcome: VRLookDistanceModel.Outcome) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(outcome.trace.utf8)) as? [String: Any] else {
        throw CheckFailure(description: "trace must be a JSON object")
    }
    return object
}
func closeCap() throws {
    let out = evaluate(sample(300))
    try near(out.eyeWidthMM, 100, "eye width")
    try near(out.sTodayMM, 10, "current separation")
    try near(out.sCapMM, -19.2, "close cap")
    try near(out.sRequestedMM, -19.2, "requested close separation")
    try near(out.sTotalMM, -19.2, "feasible close separation")
    try near(out.appliedBase, -0.584, "base removes nudge exactly once")
    try expect(out.reason == "ok" && out.capped && out.capMet && !out.infeasible, "close cap flags")
    let trace = try json(out)
    try expect(trace["reason"] as? String == "ok", "trace close reason")
    try near((trace["s_cap_mm"] as? NSNumber)?.doubleValue, -19.2, "trace close cap")
}
func farCap() throws {
    let out = evaluate(sample(600))
    try near(out.sCapMM, 24.6, "far cap")
    try near(out.sRequestedMM, 10, "far must not increase current separation")
    try near(out.sTotalMM, 10, "far total")
    try near(out.appliedBase, 0, "far base")
    try expect(!out.capped && out.capMet && !out.infeasible, "far cap flags")
}
func exactReference() throws {
    let out = evaluate(sample(500))
    try near(out.sCapMM, 10, "500 mm reference")
    try near(out.sTotalMM, 10, "reference total")
    try expect(!out.capped && out.capMet, "reference not shrink-capped")
}
func holdBoundaries() throws {
    let model = sample(600)
    let vectors: [(Double, String, Double?)] = [
        (10.5.nextDown, "ok", 600), (10.5, "ok", 600),
        (10.5.nextUp, "hold-last-d", 600),
        (12.0.nextDown, "hold-last-d", 600), (12, "hold-last-d", 600),
        (12.0.nextUp, "no-face-hold-expired", nil)
    ]
    for (time, reason, distance) in vectors {
        let out = evaluate(model, now: time)
        try expect(out.reason == reason && out.dMM == distance,
                   "exact hold boundary at \(time): \(out.reason), \(String(describing: out.dMM))")
        if distance == nil {
            try near(out.sTotalMM, 10, "expired distance reverts to constant-mm separation")
            try expect(!out.capped, "expired distance must not retain clamp")
        }
    }
}
func unavailableFOV() throws {
    var model = sample(300)
    model.acceptDistance(dMM: nil, reason: "fov-unavailable", mmPerPx: nil, now: 10.1)
    let out = evaluate(model, now: 10.2)
    try expect(out.dMM == nil && out.reason == "fov-unavailable", "missing FOV must clear distance")
    try expect(!out.capped && out.sCapMM == nil, "missing FOV must not use prior cap")
    try near(out.sTotalMM, 10, "missing FOV constant-mm total")
    try expect(try json(out)["d_mm"] is NSNull, "missing distance trace must use null")
}
func displayScaleFallback() throws {
    for scale: Double? in [nil, 0] {
        let out = evaluate(sample(nil, scale: scale))
        try near(out.mmPerPx, 0.1118942731277533, "MacBook scale fallback", tolerance: 1e-15)
        try near(out.eyeWidthMM, 55.94713656387665, "fallback eye width")
        try near(out.sTotalMM, 5.594713656387665, "fallback separation")
        try expect(out.mmPerPxSource == "macbook-227ppi", "fallback source label")
    }
    let actual = evaluate(sample(nil, scale: 0.2))
    try near(actual.eyeWidthMM, 100, "positive supplied scale")
    // This checks the standalone model's own label, not host display custody.
    try expect(actual.mmPerPxSource == "CGDisplayScreenSize", "standalone positive scale label")
}
func noOSDWidth() throws {
    for width in [0.0, -1.0] {
        let out = evaluate(sample(300), width: width)
        try expect(out.appliedBase == nil && out.dMM == nil, "no OSD size must not apply distance")
        let trace = try json(out)
        try expect(trace["reason"] as? String == "no-osd-size" && trace["applied"] as? Bool == false,
                   "no OSD size early trace")
        try expect(out.reason == "no-osd-size", "no OSD size outcome/trace mismatch: outcome.reason=\(out.reason)")
    }
}
func nilDial() throws {
    let out = evaluate(sample(300), offset: nil)
    try expect(out.appliedBase == nil, "nil dial must not apply base")
    try near(out.offsetMM, 0, "nil dial offset")
    try near(out.sCapMM, -19.2, "nil dial cap still evaluated")
}
func infeasibleCap() throws {
    let out = evaluate(sample(200), offset: 500)
    try near(out.sTodayMM, 510, "infeasible current separation")
    try near(out.ipdEffMM, 563, "effective IPD")
    try near(out.sCapMM, -133.8, "infeasible requested cap")
    try near(out.sRequestedMM, -133.8, "infeasible request retained")
    try near(out.sTotalMM, -40, "shader feasibility clamp")
    try near(out.appliedBase, -1, "infeasible base")
    try expect(out.capped && out.infeasible && !out.capMet, "infeasible cap must not claim cap_met")
    let trace = try json(out)
    try expect(trace["cap_met"] as? Bool == false && trace["infeasible"] as? Bool == true,
               "infeasible trace flags")
}
func originalParallaxGolden() throws {
    let model = VRLookDistanceModel()
    let out = model.evaluate(osdWidth: 2560, vrFov: 100, manualFov: 0,
                             fovMinDeg: 45, fovMaxDeg: 120, ipdNudge: 0,
                             ipdOffsetMM: 0, parallaxEnabled: true,
                             parallaxDisparity: -0.4, parallaxStrength: 0.4, now: 1_000)
    try near(out.sTodayMM, 1.8435921730975418, "original numeric parallax golden")
    try near(out.sTotalMM, 1.8435921730975418, "original numeric total")
    try near(out.appliedBase, 0, "original numeric applied base")
    try expect(out.reason == "no-input" && out.dMM == nil, "fresh model source absence")
}
let checks: [(String, () throws -> Void)] = [
    ("close-cap-numeric", closeCap), ("far-cap-numeric", farCap),
    ("reference-distance", exactReference), ("exact-hold-boundaries", holdBoundaries),
    ("missing-FOV", unavailableFOV), ("display-scale-fallback", displayScaleFallback),
    ("no-OSD-width", noOSDWidth), ("nil-dial", nilDial),
    ("infeasible-cap-met", infeasibleCap), ("parallax-golden", originalParallaxGolden)
]
var failed = false
for (name, check) in checks {
    do { try check(); print("PASS \(name)") }
    catch { failed = true; print("FAIL \(name): \(error)") }
}
if failed { exit(1) }
