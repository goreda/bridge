import Foundation
import GorAVPlaybackCore

// hud-state-tests (P29-HUD, DR-0020, lane c): Linux witness replaying the
// golden vectors (hud-vectors.json, formula-derived from photon-hud.lua
// v2.2.17; gor lane re-derives from the authoritative LuaJIT) against
// HUDStateModel. The compared output is the exact gor-osd payload string,
// which also asserts the section-id prefix contract (a Swift click handler
// reads those prefixes, so the builders must stay byte-exact).

var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) {
    if cond { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}

let url = URL(fileURLWithPath: "Sources/hud-state-tests/hud-vectors.json")
guard let data = try? Data(contentsOf: url),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let vectors = root["vectors"] as? [[String: Any]] else {
    print("FAIL vectors-unreadable"); exit(1)
}

func sample(_ step: [String: Any]) -> HUDSubsystemSample {
    var fields: [String: String] = [:]
    for (k, v) in (step["fields"] as? [String: Any]) ?? [:] {
        if let sv = v as? String { fields[k] = sv }
    }
    return HUDSubsystemSample(fields: fields)
}

func bright(_ step: [String: Any]) -> HUDBrightSnapshot {
    let f = step["fields"] as? [String: Any] ?? [:]
    var b = HUDBrightSnapshot()
    b.active = f["active"] as? Bool ?? false
    b.backlight = (f["backlight"] as? NSNumber)?.doubleValue
    b.inertiaMode = f["inertia_mode"] as? String ?? "n/a"
    b.isCut = f["is_cut"] as? Bool ?? false
    b.ambientLevel = (f["ambient_level"] as? NSNumber)?.doubleValue
    b.ambientWindowOpen = f["ambient_window_open"] as? Bool ?? false
    b.ambientSource = f["ambient_source"] as? String ?? "n/a"
    b.ambientLux = (f["ambient_lux"] as? NSNumber)?.doubleValue
    b.ambientFace = (f["ambient_face"] as? NSNumber)?.doubleValue
    b.ambientRoom = (f["ambient_room"] as? NSNumber)?.doubleValue
    return b
}

var vectorCount = 0, comparedDraws = 0
for vector in vectors {
    let name = vector["name"] as? String ?? "?"
    guard let steps = vector["steps"] as? [[String: Any]] else { check("\(name).steps", false); continue }
    var model = HUDStateModel()
    var ok = true
    for (i, step) in steps.enumerated() {
        let op = step["op"] as? String ?? ""
        let now = Double((step["nowUs"] as? NSNumber)?.int64Value ?? 0) / 1_000_000
        switch op {
        case "hudToggle": model.hudToggle()
        case "setNow": model.setNow(now)
        case "fileLoaded": model.fileLoaded()
        case "grainMeasureStatus": model.grainMeasure(step["value"] as? String ?? "", at: now)
        case "toggleFold": model.toggleFold(step["section"] as? String ?? "")
        case "foldTick":
            model.setNow(now)
            model.foldTick(step["section"] as? String ?? "")
        case "photonHudState": model.applyPhoton(sample(step))
        case "grainHudState": model.applyGrain(sample(step))
        case "chromeHudState": model.applyChrome(sample(step))
        case "negativHudState": model.applyNegativ(sample(step))
        case "sharpHudState": model.applySharp(sample(step))
        case "brightState": model.applyBright(bright(step))
        case "expectWarnings":
            let want = (step["fields"] as? [String]) ?? []
            check("\(name).step\(i).warnings", model.guardState.lastRejected == want)
            if model.guardState.lastRejected != want {
                print("  got \(model.guardState.lastRejected) want \(want)")
            }
            continue
        case "draw":
            let got = model.drawHUD()
            comparedDraws += 1
            let expect = (step["expect"] as? [String: Any]) ?? [:]
            let want = expect["osd"] as? String
            if got != want {
                ok = false
                print("FAIL \(name).step\(i).osd")
                let g = (got ?? "<nil>").split(separator: "‖", omittingEmptySubsequences: false).map(String.init)
                let w = (want ?? "<nil>").split(separator: "‖", omittingEmptySubsequences: false).map(String.init)
                for j in 0..<max(g.count, w.count) {
                    let gl = j < g.count ? g[j] : "<absent>"
                    let wl = j < w.count ? w[j] : "<absent>"
                    if gl != wl { print("  line \(j):\n    got  \(gl)\n    want \(wl)") }
                }
            }
            continue
        default: ok = false; print("FAIL \(name).step\(i).op \(op)")
        }
    }
    check("\(name).replay", ok)
    vectorCount += 1
}
check("vectors.count", vectorCount == 8)

// Pinned spot-assertions.
// Corrupt rejection: NaN, inf, out-of-domain, and the x10^18 fixed-point junk
// case hold the last good value; warn-once is a data flag, emitted once.
do {
    var m = HUDStateModel()
    m.applyPhoton(HUDSubsystemSample(fields: ["enabled_str": "true", "hdr_peak_str": "800", "is_hdr_str": "true"]))
    check("guard.firstAccepted", (m.photonState?["hdr_peak"]).map { "\($0)" } != nil)
    m.applyPhoton(HUDSubsystemSample(fields: ["enabled_str": "true", "hdr_peak_str": "1.8e19", "is_hdr_str": "true"]))
    check("guard.fixedPointJunkRejected", m.guardState.lastRejected == ["photon.hdr_peak"])
    m.applyPhoton(HUDSubsystemSample(fields: ["enabled_str": "true", "hdr_peak_str": "1.8e19", "is_hdr_str": "true"]))
    check("guard.warnOnce", m.guardState.lastRejected.isEmpty)
    m.hudToggle()
    let osd = m.drawHUD() ?? ""
    check("guard.holdsLastGood", osd.contains("peak: 800 nit"))
}
// sdr_gamma domain: -1.875 is valid (the v14 correction), -7.6 is not.
do {
    var m = HUDStateModel()
    m.applyPhoton(HUDSubsystemSample(fields: ["enabled_str": "true", "sdr_gamma_str": "-1.875"]))
    check("guard.gammaNegativeOk", m.guardState.lastRejected.isEmpty)
    m.applyPhoton(HUDSubsystemSample(fields: ["enabled_str": "true", "sdr_gamma_str": "-7.6"]))
    check("guard.gammaOutOfDomain", m.guardState.lastRejected == ["photon.sdr_gamma"])
}
// Empty string is "no value yet": silent fallback, no corrupt warn.
do {
    var m = HUDStateModel()
    m.applyPhoton(HUDSubsystemSample(fields: ["enabled_str": "true", "scene_smooth_peak_str": ""]))
    check("guard.emptySilent", m.guardState.lastRejected.isEmpty)
}
// Fold defaults: chrome/negativ closed, the rest open.
do {
    let m = HUDStateModel()
    check("fold.defaults", m.fold["chrome"]?.revealed == 0 && m.fold["negativ"]?.revealed == 0
          && m.fold["photon"]?.revealed == .infinity && m.fold["bright"]?.revealed == .infinity
          && m.fold["sharp"]?.revealed == .infinity && m.fold["grain"]?.revealed == .infinity)
}
// Nil bright backlight means "engine has not published yet" -> waiting, not off.
do {
    var m = HUDStateModel()
    var b = HUDBrightSnapshot()
    b.active = true
    m.applyBright(b)
    m.hudToggle()
    check("bright.nilIsWaiting", (m.drawHUD() ?? "").contains("feed: waiting"))
}

print("FINAL pass=\(pass) fail=\(fail) (vectors \(vectorCount), compared draws \(comparedDraws))")
exit(fail == 0 ? 0 : 1)
