import Foundation
import GorAVPlaybackCore

// live-control-tests (P29-LIVE-CONTROL, DR-0021, lane c): Linux witness
// replaying TWO references against LiveControlActuator:
//   1. live-control-lua-reference.json - AUTHORITATIVE: raw outputs of the
//      exact pinned photon-live-control.lua executed under real LuaJIT
//      (lua-reference/, executedLua flag honoured; NOT_RUN skips cleanly).
//   2. live-control-vectors.json - MODEL-ONLY Python replay, kept as a
//      secondary cross-check only (never presented as independent proof).
// The witness also asserts the two references agree step-for-step.

var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) {
    if cond { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}

func loadJson(_ path: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return root
}
guard let pyRoot = loadJson("Sources/live-control-tests/live-control-vectors.json"),
      let pyVectors = pyRoot["vectors"] as? [[String: Any]] else {
    print("FAIL python-vectors-unreadable"); exit(1)
}
let luaRoot = loadJson("Sources/live-control-tests/lua-reference/live-control-lua-reference.json")
let executedLua = (luaRoot?["executedLua"] as? NSNumber)?.boolValue ?? false
if !executedLua { print("lua-reference executedLua NOT_RUN - skipping authoritative replay") }

func makeConfig() -> LiveControlConfig {
    LiveControlConfig(
        initialGamma: 1.0, qualified: true, rate: 0.5, staleAge: 0.5,
        callbackGap: 0.5, referenceInterval: 1.0 / 24.0, retention: 0.5,
        maxSettlementSamples: 3,
        classifyCut: { old, new in
            let d = abs(new.pbs - old.pbs)
            return d > 30 ? .confirmed : (d > 15 ? .candidate : nil)
        },
        settled: { profiles in
            profiles.count >= 2
                && (profiles.map(\.pbs).max()! - profiles.map(\.pbs).min()!) < 5
        },
        target: { profile, _ in max(0.5, min(2.0, 1.0 + (profile.pbs - 100.0) / 100.0)) },
        velocity: { old, new, _ in (new.pbs - old.pbs) / (new.t - old.t) })
}

func profile(_ any: [String: Any]) -> LiveControlProfile? {
    guard let doc = any["doc"] as? String, let id = any["id"] as? Int else { return nil }
    return LiveControlProfile(doc: doc, id: id,
                              t: (any["t"] as? NSNumber)?.doubleValue ?? 0,
                              pts: (any["pts"] as? NSNumber)?.doubleValue ?? 0,
                              pbs: (any["pbs"] as? NSNumber)?.doubleValue ?? 0)
}

func close(_ a: Double?, _ b: Double?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x?, y?): return abs(x - y) <= 1e-9
    default: return false
    }
}
func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

var vectorCount = 0, comparedSteps = 0, luaComparedSteps = 0

@discardableResult
func replay(_ vectors: [[String: Any]], label: String) -> Int {
    var compared = 0
for vector in vectors {
    let name = vector["name"] as? String ?? "?"
    guard let steps = vector["steps"] as? [[String: Any]] else { check("\(name).steps", false); continue }
    var cfg = makeConfig()
    if let overrides = vector["config"] as? [String: Any] {
        if let rate = (overrides["rate"] as? NSNumber)?.doubleValue { cfg.rate = rate }
    }
    var actuator = LiveControlActuator(config: cfg)
    var ok = true
    for (i, step) in steps.enumerated() {
        let op = step["op"] as? String ?? ""
        let now = Double((step["nowUs"] as? NSNumber)?.int64Value ?? 0) / 1_000_000
        var decision: LiveControlDecision
        switch op {
        case "observe":
            decision = actuator.observe(profile(step["profile"] as? [String: Any] ?? [:]))
        case "observeRaw":
            // Raw payload with nil doc: unrepresentable in the typed profile;
            // the nil whole-profile path carries the same hold.
            decision = actuator.observe(nil)
        case "observeNaN":
            // One named field NaN in an otherwise valid profile.
            var p = profile(step["profile"] as? [String: Any] ?? [:])
            switch step["nanField"] as? String {
            case "t": p = p.map { LiveControlProfile(doc: $0.doc, id: $0.id, t: .nan, pts: $0.pts, pbs: $0.pbs) }
            case "pts": p = p.map { LiveControlProfile(doc: $0.doc, id: $0.id, t: $0.t, pts: .nan, pbs: $0.pbs) }
            case "pbs": p = p.map { LiveControlProfile(doc: $0.doc, id: $0.id, t: $0.t, pts: $0.pts, pbs: .nan) }
            default: ok = false; print("FAIL \(name).step\(i).nanField"); p = nil
            }
            decision = actuator.observe(p)
        case "tick":
            decision = actuator.tick(now)
        case "tickRaw":
            decision = actuator.tick(.nan)
        case "setTargetNaN":
            var c = makeConfig()
            c.target = { _, _ in .nan }
            actuator.updateConfig(c)
            continue
        case "freshUnqualified":
            // A SEPARATE unqualified instance (the generator's sim2); the
            // main actuator keeps its own state for later steps.
            var cfg2 = makeConfig()
            cfg2.qualified = false
            var fresh = LiveControlActuator(config: cfg2)
            decision = fresh.observe(profile(step["profile"] as? [String: Any] ?? [:]))
        case "freshUnqualifiedTick":
            var cfg2 = makeConfig()
            cfg2.qualified = false
            var fresh = LiveControlActuator(config: cfg2)
            _ = fresh.observe(profile(step["profile"] as? [String: Any] ?? [:]))
            decision = fresh.tick(now)
        case "freshStaleTick":
            var fresh = LiveControlActuator(config: makeConfig())
            _ = fresh.tick(now - 0.1) // prime last_tick; last_t still nil
            decision = fresh.tick(now)
        default:
            ok = false; print("FAIL \(name).step\(i).op \(op)"); continue
        }
        guard let expect = step["expect"] as? [String: Any] else { continue }
        compared += 1
        if decision.state.rawValue != expect["state"] as? String {
            ok = false; print("FAIL \(name).step\(i).state got \(decision.state.rawValue) want \(expect["state"] ?? "nil")")
        }
        let wantReason = expect["reason"] is NSNull ? nil : expect["reason"] as? String
        if decision.reason != wantReason {
            ok = false; print("FAIL \(name).step\(i).reason got \(decision.reason ?? "nil") want \(wantReason ?? "nil")")
        }
        if decision.cutPending != ((expect["cut_pending"] as? NSNumber)?.boolValue ?? false) {
            ok = false; print("FAIL \(name).step\(i).cutPending")
        }
        if decision.settlementSamples != ((expect["settlement_samples"] as? NSNumber)?.intValue ?? 0) {
            ok = false; print("FAIL \(name).step\(i).settlementSamples")
        }
        if !close(decision.heldGamma, num(expect["held_gamma"])) {
            ok = false; print("FAIL \(name).step\(i).heldGamma got \(decision.heldGamma) want \(expect["held_gamma"] ?? "nil")")
        }
        if !close(decision.returned, num(expect["returned"])) {
            ok = false; print("FAIL \(name).step\(i).returned got \(String(describing: decision.returned)) want \(expect["returned"] ?? "nil")")
        }
    }
    check("\(label).\(name).replay", ok)
    vectorCount += 1
}
    return compared
}

comparedSteps = replay(pyVectors, label: "py")
check("vectors.count", vectorCount == 6)

// Authoritative replay: the pinned script's real LuaJIT outputs.
if executedLua, let luaVectors = luaRoot?["vectors"] as? [[String: Any]] {
    vectorCount = 0
    luaComparedSteps = replay(luaVectors, label: "lua")
    check("lua.vectors.count", vectorCount == 6)
    // Cross-check: the model-only Python replay must agree with the real
    // Lua execution step-for-step (same structure, same expects).
    // Field-wise compare: the two references serialize numbers differently
    // (Python "5.0" vs Lua %.17g "5"), so compare values, not raw objects.
    func expectsAgree(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        guard Set(a.keys) == Set(b.keys) else { return false }
        for k in a.keys {
            let x = a[k]!, y = b[k]!
            if x is NSNull || y is NSNull {
                if !(x is NSNull && y is NSNull) { return false }
                continue
            }
            if let xs = x as? String, let ys = y as? String {
                if xs != ys { return false }
                continue
            }
            // numbers and booleans compare numerically (true -> 1, false -> 0)
            guard let xn = num(x), let yn = num(y), abs(xn - yn) <= 1e-9 else { return false }
        }
        return true
    }
    var agree = luaVectors.count == pyVectors.count
    outer: for (lv, pv) in zip(luaVectors, pyVectors) {
        let lSteps = lv["steps"] as? [[String: Any]] ?? []
        let pSteps = pv["steps"] as? [[String: Any]] ?? []
        if lSteps.count != pSteps.count { agree = false; break }
        for (ls, ps) in zip(lSteps, pSteps) {
            let le = ls["expect"] as? [String: Any], pe = ps["expect"] as? [String: Any]
            if (le == nil) != (pe == nil) { agree = false; break outer }
            if let le, let pe, !expectsAgree(le, pe) {
                print("references differ at \(lv["name"] ?? "?") op \(ls["op"] ?? "?")")
                agree = false; break outer
            }
        }
    }
    check("references.agree", agree)
}

// Spot-assertions.
// Feed fires for fresh observations even while gamma is held.
do {
    var fed = 0
    var cfg = makeConfig()
    cfg.feed = { _ in fed += 1 }
    var a = LiveControlActuator(config: cfg)
    a.observe(LiveControlProfile(doc: "x", id: 1, t: 0, pts: 0, pbs: 100))
    a.observe(nil) // invalid-profile: feed must NOT fire (rejected before feed)
    a.observe(LiveControlProfile(doc: "x", id: 2, t: 0.1, pts: 0.1, pbs: 140)) // cut: feed fires
    check("feed.freshOnly", fed == 2 && a.feedCount == 2)
}
// Bounded sliding window: settlement samples never exceed max.
do {
    var a = LiveControlActuator(config: makeConfig())
    a.observe(LiveControlProfile(doc: "x", id: 1, t: 0, pts: 0, pbs: 100))
    a.observe(LiveControlProfile(doc: "x", id: 2, t: 0.1, pts: 0.1, pbs: 140)) // cut
    var maxSeen = 0
    for i in 3...8 {
        let d = a.observe(LiveControlProfile(doc: "x", id: i, t: Double(i) / 10, pts: Double(i) / 10,
                                             pbs: i % 2 == 0 ? 140 : 150))
        maxSeen = max(maxSeen, d.settlementSamples)
    }
    check("window.bounded", maxSeen <= 3)
}
// Overshoot clamp: a tiny distance lands exactly on target.
do {
    var a = LiveControlActuator(config: makeConfig())
    a.observe(LiveControlProfile(doc: "x", id: 1, t: 0, pts: 0, pbs: 100)) // target 1.0 = gamma
    a.tick(0.0)
    let d = a.tick(1.0 / 24.0)
    check("step.exactWhenZero", d.returned == 1.0)
}

// -- PhotonAdmission -> typed P22 writer binding (the queue's wiring half) -----
// A control write reaches the typed block with the expected (Linux-visible)
// effect: lane value, block revision, and serialized packet bytes at the lane
// offset; refused and NOOP commands never touch the block.
do {
    let writer = PhotonAdmissionP22Writer(lane: "GR_AMOUNT")
    var now = 0.0
    let doc = PhotonAdmission.Document(gen: 1, name: "clip")
    let r = PhotonAdmission.Receiver(base: 10, cacheCapacity: 2,
                                     apply: { writer.apply($0) }, clock: { now })
    r.bind(doc, enabled: true)
    let laneOffset = 24 + 80 * 4  // GR_AMOUNT at P22 offset 80
    let before = LookParameterABI.serialize(writer.block)
    let c1 = PhotonAdmission.Command(doc: doc, id: 1, revision: 0, serialFloor: 0, mult: 2, expectedStrength: 20)
    let rc1 = r.auto(c1)
    check("bind.applied", rc1.status == .applied)
    check("bind.laneValue", writer.value() == 20)
    let after = LookParameterABI.serialize(writer.block)
    check("bind.revisionAdvanced", after != before)
    let laneBits = after[laneOffset..<(laneOffset + 4)].withUnsafeBytes { $0.load(as: UInt32.self) }
    check("bind.packetBytes", laneBits == Float32(20).bitPattern)
    // NOOP: same strength again -> apply not called, block bytes unchanged.
    let c2 = PhotonAdmission.Command(doc: doc, id: 2, revision: 1, serialFloor: 0, mult: 2, expectedStrength: 20)
    let rc2 = r.auto(c2)
    check("bind.noop", rc2.status == .noop && LookParameterABI.serialize(writer.block) == after)
    // Refused: revision fence -> block untouched.
    let c3 = PhotonAdmission.Command(doc: doc, id: 3, revision: 99, serialFloor: 0, mult: 3, expectedStrength: 30)
    let rc3 = r.auto(c3)
    check("bind.refusedUntouched", rc3.status == .rejected && rc3.reason == "revision"
          && LookParameterABI.serialize(writer.block) == after)
    // apply-failed: an unknown lane makes the typed writer refuse loudly.
    let badWriter = PhotonAdmissionP22Writer(lane: "NO_SUCH_LANE")
    let r2 = PhotonAdmission.Receiver(base: 10, cacheCapacity: 2,
                                      apply: { badWriter.apply($0) }, clock: { now })
    r2.bind(doc, enabled: true)
    let rc4 = r2.auto(c1)
    check("bind.applyFailed", rc4.status == .rejected && rc4.reason == "apply-failed")
    _ = now
}

print("FINAL pass=\(pass) fail=\(fail) (vectors \(vectorCount), py steps \(comparedSteps), lua steps \(luaComparedSteps), executedLua \(executedLua))")
exit(fail == 0 ? 0 : 1)
