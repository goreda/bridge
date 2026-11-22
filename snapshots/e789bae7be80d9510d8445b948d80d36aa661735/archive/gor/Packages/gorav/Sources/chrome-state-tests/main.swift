import Foundation
import GorAVPlaybackCore

// chrome-state-tests (P29-CHROME, DR-0019, lane c): Linux witness replaying the
// golden vectors (chrome-vectors.json, formula-derived from photon-chrome.lua
// v1.1; gor lane re-derives from the authoritative Lua) against ChromeStateModel.
// Covers the pinned scenarios: hue-EMA jitter, cut reset, dwell-confirm, hue
// outside the arc, manual cycle + pause clear, file-loaded reset, carryover
// rendezvous, tier-1 ease, HDR sentinel + nil-hue hold.

var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) {
    if cond { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}

let url = URL(fileURLWithPath: "Sources/chrome-state-tests/chrome-vectors.json")
guard let data = try? Data(contentsOf: url),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let vectors = root["vectors"] as? [[String: Any]] else {
    print("FAIL vectors-unreadable"); exit(1)
}

let tol = 1e-9
func close(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x?, y?): return abs(x - y) <= tol
    default: return false
    }
}
func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
func boolVal(_ v: Any?) -> Bool? { (v as? NSNumber)?.boolValue }

var vectorCount = 0, stepCount = 0
for vector in vectors {
    let name = vector["name"] as? String ?? "?"
    guard let steps = vector["steps"] as? [[String: Any]] else { check("\(name).steps", false); continue }
    var model = ChromeStateModel()
    var ok = true
    for (i, step) in steps.enumerated() {
        let op = step["op"] as? String ?? ""
        // Times travel as integer microseconds (nowUs) and are divided here -
        // the identical correctly-rounded division the generator used.
        let now = Double((step["nowUs"] as? NSNumber)?.int64Value ?? 0) / 1_000_000
        switch op {
        case "toggle": model.apply(.toggle, now: now)
        case "filterToggle": model.apply(.filterToggle, now: now)
        case "pause": model.apply(.pauseTransition, now: now)
        case "fileLoaded": model.apply(.fileLoaded, now: now)
        case "setTargetEnabled": model.apply(.setTargetEnabled(boolVal(step["value"]) ?? false), now: now)
        case "ingest":
            let hue = step["hue"] is NSNull ? nil : num(step["hue"])
            model.ingest(ChromeSceneSample(hue: hue, saturation: num(step["sat"]) ?? -1,
                                           contrast: num(step["contrast"]) ?? 0.25,
                                           isCut: boolVal(step["isCut"]) ?? false), now: now)
        default: ok = false; print("FAIL \(name).step\(i).op \(op)")
        }
        guard let expect = step["expect"] as? [String: Any] else { continue }
        stepCount += 1
        let rs = model.resolvedState
        if !close(model.sceneHueSmoothed, num(expect["hueSmoothed"])) { ok = false; print("FAIL \(name).step\(i).hueSmoothed got \(model.sceneHueSmoothed?.description ?? "nil") want \(expect["hueSmoothed"] ?? "nil")") }
        if !close(rs.filterStrengthRendered, num(expect["strengthRendered"])) { ok = false; print("FAIL \(name).step\(i).strengthRendered") }
        if !close(rs.contrastAmount, num(expect["contrastRendered"])) { ok = false; print("FAIL \(name).step\(i).contrastRendered") }
        if !close(model.filterPosResolved, num(expect["posResolved"])) { ok = false; print("FAIL \(name).step\(i).posResolved") }
        if !close(rs.filterPositionRendered, num(expect["posRendered"])) { ok = false; print("FAIL \(name).step\(i).posRendered got \(rs.filterPositionRendered) want \(expect["posRendered"] ?? "nil")") }
        if boolVal(expect["arcClamped"]) != rs.hueArcClamped { ok = false; print("FAIL \(name).step\(i).arcClamped") }
        if boolVal(expect["enabled"]) != model.toggleState.enabled { ok = false; print("FAIL \(name).step\(i).enabled") }
        if boolVal(expect["hasFeed"]) != rs.hasFeed { ok = false; print("FAIL \(name).step\(i).hasFeed") }
        if boolVal(expect["manualActive"]) != model.toggleState.manualFilterActive { ok = false; print("FAIL \(name).step\(i).manualActive") }
        if !close(Double(model.toggleState.manualFilterPosition), num(expect["manualPos"])) { ok = false; print("FAIL \(name).step\(i).manualPos") }
        if !close(model.charCommitted, num(expect["committed"])) { ok = false; print("FAIL \(name).step\(i).committed") }
    }
    check("\(name).replay", ok)
    vectorCount += 1
}
check("vectors.count", vectorCount == 9)

// Pinned scenario spot-assertions (the four required covers, independently named):
// dwell-confirm: committed holds at its established value long after the jump.
do {
    var m = ChromeStateModel()
    m.apply(.toggle, now: 0)
    for i in 1...150 { m.ingest(ChromeSceneSample(hue: 0.05, saturation: 0.3, contrast: 0.25, isCut: false), now: Double(i) * 0.1) }
    let established = m.charCommitted
    for i in 1...10 { m.ingest(ChromeSceneSample(hue: 0.30, saturation: 0.3, contrast: 0.25, isCut: false), now: 15.0 + Double(i) * 0.1) }
    check("dwell.noCommitInsideDeadZone", m.charCommitted == established)
    for i in 11...120 { m.ingest(ChromeSceneSample(hue: 0.30, saturation: 0.3, contrast: 0.25, isCut: false), now: 15.0 + Double(i) * 0.1) }
    check("dwell.committedAfterDwell", m.charCommitted > established + 0.36)
}
// arc: outside-hue pins to the nearer endpoint with the clamp flag, not a wrapped value.
do {
    var m = ChromeStateModel()
    m.apply(.toggle, now: 0)
    m.ingest(ChromeSceneSample(hue: 0.5, saturation: 0.3, contrast: 0.25, isCut: false), now: 0.1)
    check("arc.bluePinsGreen", m.filterPosResolved == 3.0 && m.resolvedState.hueArcClamped)
    m.ingest(ChromeSceneSample(hue: 0.95, saturation: 0.3, contrast: 0.25, isCut: true), now: 0.2)
    check("arc.warmPinsRed", m.filterPosResolved == 0.0 && m.resolvedState.hueArcClamped)
    m.ingest(ChromeSceneSample(hue: 0.1, saturation: 0.3, contrast: 0.25, isCut: true), now: 0.3)
    check("arc.inArcNotClamped", !m.resolvedState.hueArcClamped && abs(m.filterPosResolved - 0.9) < 1e-9)
}
// cut reset: hue EMA snaps on a cut instead of easing across it.
do {
    var m = ChromeStateModel()
    m.apply(.toggle, now: 0)
    for i in 1...5 { m.ingest(ChromeSceneSample(hue: 0.1, saturation: 0.3, contrast: 0.25, isCut: false), now: Double(i) * 0.1) }
    m.ingest(ChromeSceneSample(hue: 0.3, saturation: 0.3, contrast: 0.25, isCut: true), now: 0.6)
    check("cut.snapsSmoothed", m.sceneHueSmoothed == 0.3)
}
// seam names and shader parameter lanes.
do {
    var m = ChromeStateModel()
    m.apply(.toggle, now: 0)
    m.ingest(ChromeSceneSample(hue: 0.1, saturation: 0.3, contrast: 0.25, isCut: false), now: 0.1)
    let p = m.resolvedState.shaderParameters
    check("seam.lanes", p["CH_FILTER_POS"] != nil && p["CH_FILTER_STRENGTH"] != nil && p["CH_CONTRAST_AMOUNT"] != nil && p.count == 3)
    check("seam.types", ChromeToggleEvent.toggle == .toggle && m.toggleState.enabled)
}

print("FINAL pass=\(pass) fail=\(fail) (vectors \(vectorCount), compared steps \(stepCount))")
exit(fail == 0 ? 0 : 1)
