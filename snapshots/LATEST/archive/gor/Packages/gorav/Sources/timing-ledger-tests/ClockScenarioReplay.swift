import Foundation
import GorAVPlaybackCore

// Replays kits/clock-scenarios/scenarios.json against the production AVSyncDecider.
// Virtual clock only: every tick carries its own pts/now; no sleeps, no wall reads.
// Negative control: --perturb-drift-ms N shifts every tick's `now` by N ms and MUST produce FAIL rows.
func bitsDouble(_ v: Any?) -> Double { Double(bitPattern: UInt64(v as? String ?? "", radix: 16) ?? 0x7ff8000000000000) }
struct ClockScenarioResult { var pass = 0; var fail = 0 }

func clockScenarioDecisionString(_ d: FrameDecision) -> String {
    switch d { case .show: return "show"; case .drop: return "drop"; case .wait(let w): return "wait(\(w))" }
}
func clockScenarioExpectString(_ e: [String: Any]) -> String {
    switch e["decision"] as? String ?? "" {
    case "wait": return "wait(\(bitsDouble(e["waitBits"])))"
    case let s: return s
    }
}

func replayClockScenarios(path: String, classes: Set<String>, perturbDriftMs: Double) -> ClockScenarioResult {
    var r = ClockScenarioResult()
    guard let data = FileManager.default.contents(atPath: path),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let maxWait = (root["maxWaitSeconds"] as? NSNumber)?.doubleValue,
          let scenarios = root["scenarios"] as? [[String: Any]] else {
        print("FAIL cannot load \(path)"); r.fail += 1; return r
    }
    let decider = AVSyncDecider(maxWaitSeconds: maxWait) // master defaults to .clock, fixed at init
    for sc in scenarios {
        let name = sc["name"] as? String ?? "?"
        guard classes.contains(sc["class"] as? String ?? "") else { continue }
        if sc["class"] as? String == "master" {
            if decider.master == .clock { r.pass += 1 } else { r.fail += 1; print("FAIL \(name): master is not .clock") }
        }
        for (i, t) in (sc["ticks"] as? [[String: Any]] ?? []).enumerated() {
            let pts = bitsDouble(t["ptsBits"])
            let now = bitsDouble(t["nowBits"]) + perturbDriftMs / 1000.0
            let fd = bitsDouble(t["fdBits"])
            let got = clockScenarioDecisionString(decider.decide(ptsSeconds: pts, nowSeconds: now, frameDuration: fd))
            let want = clockScenarioExpectString(t["expect"] as! [String: Any])
            if got == want { r.pass += 1 } else {
                r.fail += 1
                print("FAIL \(name) tick \(i): pts=\(pts) now=\(now) fd=\(fd) want=\(want) got=\(got)")
            }
        }
    }
    return r
}

/// Master-seam honesty (static): decide() body must not read `master`.
func clockScenarioDecideIgnoresMaster(sourcePath: String) -> Bool {
    guard let s = try? String(contentsOfFile: sourcePath, encoding: .utf8),
          let a = s.range(of: "public func decide("),
          let b = s.range(of: "return .show", range: a.upperBound..<s.endIndex) else { return false }
    return !s[a.lowerBound..<b.upperBound].contains("master")
}
