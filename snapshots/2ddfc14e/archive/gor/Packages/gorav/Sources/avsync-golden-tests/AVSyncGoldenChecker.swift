import Foundation
import GorAVPlaybackCore

func bitsDouble(_ v: Any?) -> Double { Double(bitPattern: UInt64(v as? String ?? "", radix: 16) ?? 0x7ff8000000000000) }

/// Named tolerance constant: the goldens sit at +/-AVSYNC_TOLERANCE_MS around each half-frame threshold.
let AVSYNC_TOLERANCE_MS: Double = 1

func avsyncDecisionString(_ d: FrameDecision) -> String {
    switch d { case .show: return "show"; case .drop: return "drop"; case .wait(let w): return "wait(\(w))" }
}
func avsyncExpectString(_ e: [String: Any]) -> String {
    switch e["decision"] as? String ?? "" {
    case "wait": return "wait(\(bitsDouble(e["waitBits"])))"
    case let s: return s
    }
}

/// flipMs: negative control. Shifts every `now` by flipMs; a shift of +/-AVSYNC_TOLERANCE_MS must flip boundary rows.
func runAVSyncGoldens(path: String, flipMs: Double) -> (pass: Int, fail: Int) {
    var pass = 0, fail = 0
    guard let data = FileManager.default.contents(atPath: path),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let maxWait = (root["maxWaitSeconds"] as? NSNumber)?.doubleValue,
          let tol = (root["toleranceMs"] as? NSNumber)?.doubleValue else { print("FAIL cannot load \(path)"); return (0, 1) }
    if tol != AVSYNC_TOLERANCE_MS { print("FAIL toleranceMs \(tol) != AVSYNC_TOLERANCE_MS"); fail += 1 }
    let decider = AVSyncDecider(maxWaitSeconds: maxWait)
    func check(_ label: String, _ t: [String: Any]) {
        let pts = bitsDouble(t["ptsBits"])
        let now = bitsDouble(t["nowBits"]) + flipMs / 1000.0
        let fd = bitsDouble(t["fdBits"])
        let got = avsyncDecisionString(decider.decide(ptsSeconds: pts, nowSeconds: now, frameDuration: fd))
        let want = avsyncExpectString(t["expect"] as! [String: Any])
        if got == want { pass += 1 } else { fail += 1; print("FAIL \(label): pts=\(pts) now=\(now) fd=\(fd) want=\(want) got=\(got)") }
    }
    for (i, t) in (root["thresholdRows"] as? [[String: Any]] ?? []).enumerated() { check("threshold[\(i)] \(t["group"] ?? "") \(t["offsetMs"] ?? "")ms", t) }
    for key in ["straddlingSequences", "dropBurstRecovery"] {
        for s in root[key] as? [[String: Any]] ?? [] {
            for (i, t) in (s["ticks"] as? [[String: Any]] ?? []).enumerated() { check("\(s["name"] ?? "?")[\(i)] \(t["note"] ?? "")", t) }
        }
    }
    return (pass, fail)
}

// Entry point (lane a: the target shipped without one - this file defined
// runAVSyncGoldens but nothing ever called it). Usage:
//   avsync-golden-tests <goldens.json>
// Contract: flip=0 must be all-pass; shifting every `now` by +/- the named
// tolerance (1ms) is the negative control and must flip at least one
// boundary row each way.
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: avsync-golden-tests <goldens.json>\n".data(using: .utf8)!)
    exit(2)
}
let avsyncGoldensPath = CommandLine.arguments[1]
let avsyncBase = runAVSyncGoldens(path: avsyncGoldensPath, flipMs: 0)
let avsyncPlus = runAVSyncGoldens(path: avsyncGoldensPath, flipMs: AVSYNC_TOLERANCE_MS)
let avsyncMinus = runAVSyncGoldens(path: avsyncGoldensPath, flipMs: -AVSYNC_TOLERANCE_MS)
print("avsync-golden-tests: base \(avsyncBase.pass) PASS \(avsyncBase.fail) FAIL; +1ms flips \(avsyncPlus.fail); -1ms flips \(avsyncMinus.fail)")
guard avsyncBase.fail == 0, avsyncBase.pass > 0, avsyncPlus.fail > 0, avsyncMinus.fail > 0 else { exit(1) }
