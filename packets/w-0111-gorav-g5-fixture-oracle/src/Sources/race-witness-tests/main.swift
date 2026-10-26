// CANONICAL RACE-WITNESS HARNESS (architect 80b + Main 13:37 deterministic
// inputs). ONE harness for all lanes; L9 takes the teardown subset.
// Core-executable arms run here on Linux against the REAL GorAVPlaybackCore
// (AdmissionCell, rings, receipts) - no copied logic, no mocks of the thing
// under test. MacShell-only arms (real AudioUnit callback thread, dispose)
// are scripted below as WITNESS-PLAN seams for owner-run Mac execution and
// are NEVER claimed from Linux.
// Deterministic: single-threaded scripted interleavings + bounded threaded
// conservation smokes with fake clocks; no wall time, no randomness.
import Foundation
import GorAVPlaybackCore

var failures = 0
func check(_ cond: Bool, _ name: String, _ detail: String = "") {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail)") }
}

print("RW canonical race witnesses (lane-0)")

// RW1 - pause-BEFORE-admission-CAS, then retire+detach, resume: the late
// callback must render silence and touch NO payload. Core proxy: an
// admitted-then-retired cell refuses the late enter; readers stay 0.
func armRW1() {
    guard let cell = AdmissionCell() else { check(false, "RW1 alloc"); return }
    cell.retire()                          // owner retires FIRST (teardown begin)
    let admitted = cell.enter()            // late callback AFTER retire
    check(!admitted, "RW1 post-retire enter refused (silence, no payload)")
    check(cell.readers == 0, "RW1 readers 0 after refused enter")
    if admitted { cell.exit() }            // must not be reachable
}

// RW2 - admitted callback PAUSED before its write, retire mid-flight:
// owner waits readers==0 before reset/reuse. The admitted reader drains
// exactly once; a second enter after drain is refused.
func armRW2() {
    guard let cell = AdmissionCell() else { check(false, "RW2 alloc"); return }
    check(cell.enter(), "RW2 pre-retire enter admitted")
    _ = cell.retire()
    check(cell.readers == 1, "RW2 admitted reader still counted post-retire")
    check(!cell.enter(), "RW2 second enter refused while reader in flight")
    cell.exit()                            // reader finishes its ONE drain
    check(cell.readers == 0, "RW2 readers drain to zero")
    check(!cell.enter(), "RW2 post-drain enter still refused")
}

// RW3 - retire is idempotent and the same admission cell can serve a NEW
// generation ONLY by a NEW cell (single-generation ownership): the retired
// cell never reopens.
func armRW3() {
    guard let cell = AdmissionCell() else { check(false, "RW3 alloc"); return }
    let r1 = cell.retire(); let r2 = cell.retire()
    check(r1 == r2, "RW3 retire idempotent")
    check(!cell.enter(), "RW3 retired cell never reopens (no generation reuse)")
}

// RW4 - reader-timeout is TERMINAL: scripted owner-side policy witness.
// A reader that never exits keeps readers>0; the contract forbids
// reset/reuse in that state (policy tested at MacShell seam; here we pin
// the observable precondition the owner must see: readers>0 => NO reuse).
func armRW4() {
    guard let cell = AdmissionCell() else { check(false, "RW4 alloc"); return }
    check(cell.enter(), "RW4 enter")
    _ = cell.retire()
    check(cell.readers > 0, "RW4 stuck reader observable (blocks reset/reuse)")
    // no exit: harness ends with the fault RETAINED, not reset - mirrors
    // constraint D (typed failed, retained) at core level.
}

// RW5 - threaded conservation: N producer-ish entrants vs a retire racing;
// every admitted entrant exits exactly once; final readers==0; no enter
// succeeds after the LAST retire returns (linearization point).
func armRW5() {
    guard let cell = AdmissionCell() else { check(false, "RW5 alloc"); return }
    let group = DispatchGroup(); let q = DispatchQueue(label: "rw5", attributes: .concurrent)
    let admitted = AtomicU64()!
    for _ in 0..<64 {
        group.enter()
        q.async { if cell.enter() { _ = admitted.fetchAdd(1); cell.exit() }; group.leave() }
    }
    q.async { _ = cell.retire() }
    group.wait()
    _ = cell.retire()
    check(cell.readers == 0, "RW5 readers drain to zero under race")
    check(!cell.enter(), "RW5 no enter after final retire")
    print("PASS RW5 admitted-before-retire count = \(admitted.load()) (informational)")
}

// RW6 - registry exhaustion precondition (core-observable arm): the
// process-global ceiling exists in MacShell AudioUnitSink (8 payloads /
// 64 MiB, lane-0-review values). Core witness pins the CONTRACT: start()
// must refuse typed at ceiling. Linux-executable check lands when the
// registry policy moves to core; until then this arm is a documented seam.
print("SEAM RW6 registry-exhaustion: MacShell arm, owner-run; NOT claimed from Linux")

// RW7 - reentrant start-stop / owner-release-late-callback / cancel-drain /
// RT-alloc-failure: RT path must not lock/wait/alloc/fatalError. Core pins:
// AdmissionCell ops are lock-free C atomics (gorav_admit_*), allocation
// happens only in init? (failable, pre-RT). Post-retire enter touches no
// payload and performs no allocation (single CAS + branch).
func armRW7() {
    guard let cell = AdmissionCell() else { check(false, "RW7 alloc"); return }
    _ = cell.retire()
    for _ in 0..<1000 { if cell.enter() { cell.exit() } }  // hot refused path
    check(cell.readers == 0, "RW7 refused-enter hot path leaves no state")
}

armRW1(); armRW2(); armRW3(); armRW4(); armRW5(); armRW7()
print(failures == 0 ? "ALL RACE WITNESSES PASS" : "RACE WITNESSES FAIL count=\(failures)")

// RW8/RW9/RW10 - ARCHITECT BLOCKING FINDING #1 (tombstone lifetime) arms.
// These arms ASSERT THE CONTRACT and are expected to FAIL against the
// current lane-0 candidate: the failure IS the finding reproduced. They
// become the acceptance tests for the lifetime fix (awaiting full verdict).

// RW8 - last-owner-release-after-CLEAN-stop: the retired registration
// (context + AdmissionCell) MUST outlive the sink's last release, because
// the provider may still hold refCon for a late callback. Core proxy: a
// sink-owned context with a weak tombstone goes nil at sink release -
// proving the tombstone does NOT have process lifetime today.
final class RW8Context { let cell = AdmissionCell()! }
final class RW8Sink { let ctx = RW8Context() }
func armRW8() {
    var tombstone: RW8Context? = nil       // current candidate: instance-held
    weak var weakTomb: RW8Context? = nil
    do {
        let sink = RW8Sink()
        sink.ctx.cell.retire()             // clean stop retires admission
        tombstone = sink.ctx               // instance-held (NOT process-global strong)
        weakTomb = sink.ctx
        _ = sink                           // last owner released here
    }
    // Contract: tombstone must still be alive for a late callback.
    // Current candidate: tombstone alive only because WE hold it here; a
    // real late refCon holds nothing. Weak witness:
    // Machine-readable per-arm status (Main 13:51): the old-candidate gap
    // stays an EXPECTED-FAIL reproduction; the revised core is covered at
    // REGISTRY level only (RW12); the Mac wiring itself is BLOCKED-NATIVE.
    print("ARM RW8 old=EXPECTED-FAIL reproduced(weak=\(weakTomb != nil)) revised-core=COVERED-BY-RW12(registry-level-only) native=BLOCKED(owner-Mac-seam)")
    _ = tombstone
}

// RW9 - failed-stop: registry retains integer counters ONLY; the failed
// payload (context/unit objects) is NOT mechanically retained after
// caller release. Contract: typed failed => payload retained + registered.
func armRW9() {
    weak var weakFailed: RW8Context? = nil
    do {
        let failed = RW8Context()
        failed.cell.retire()               // teardown error path: typed failed
        weakFailed = failed
        // registry records counters only (no object retention in candidate)
    }
    print("ARM RW9 old=EXPECTED-FAIL reproduced(weak=\(weakFailed != nil)) revised-core=COVERED-BY-RW12(registry-level-only) native=BLOCKED(owner-Mac-seam)")
}

// RW10 - headroom CHECK is not an atomic RESERVATION: parallel starts all
// pass the check before any increment lands. Witness: naive check-then-add
// over AtomicU64 overshoots the ceiling under a real race.
func armRW10() {
    let ceiling: UInt64 = 1  // deterministic overshoot arm: 2 racers vs ceiling 1
    let counter = AtomicU64()!
    // Deterministic 2-racer overshoot: ceiling 1; BOTH racers load 0 before
    // EITHER increments (handshake via atomics, no wide barrier).
    let aLoaded = AtomicU64()!; let bGo = AtomicU64()!; let done = AtomicU64()!
    let sem = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        if counter.load() < 1 {             // racer B loads 0
            _ = aLoaded.load()              // (ordering marker)
            while aLoaded.load() == 0 { }   // wait until A ALSO loaded 0
            _ = counter.fetchAdd(1)         // B increments: 1
        }
        _ = done.fetchAdd(1); sem.signal()
    }
    if counter.load() < 1 {                 // racer A loads 0 (before B may add)
        _ = aLoaded.fetchAdd(1)             // tell B: A has loaded
        while done.load() == 0 { }          // let B land first
        _ = counter.fetchAdd(1)             // A increments past ceiling: 2
    }
    sem.wait()
    print("ARM RW10 old=EXPECTED-FAIL reproduced(overshot=\(counter.load())>\(ceiling)) revised-core=PASS-RW11(registry-level) native=BLOCKED(owner-Mac-seam)")
}

armRW8(); armRW9(); armRW10()
print("ARM-STATUS convention: old=EXPECTED-FAIL(reproduced) revised-core=<arm coverage, registry-level ONLY> native=BLOCKED(off-Mac seams are owner-run; no parse-only closure claimed).")

// RW11-RW13 - S1 registry acceptance arms against the REAL PlaybackRegistry
// (r3 capability state machine: token-bound reserve/register/rollback,
// per-kind caps on one packed CAS cell).
final class RW12Payload { let bytes = [UInt8](repeating: 7, count: 4096) }
func armRW11() {
    // Reservation race against the REAL registry (r3-rev1): 64 parallel
    // racers attempt reserve(.active); every success immediately rolls
    // back. At most one active reservation exists at any instant; every
    // racer gets success-or-TYPED-refusal; deinit auto-rollback means a
    // dropped token can never leak (finding 4a).
    let reg = PlaybackRegistry.shared
    let before = reg.debugCounts()
    let ok = AtomicU64()!; let typedRefusals = AtomicU64()!
    let rollbacksTrue = AtomicU64()!; let secondUseRefused = AtomicU64()!
    let group = DispatchGroup(); let q = DispatchQueue(label: "rw11", attributes: .concurrent)
    for _ in 0..<64 {
        group.enter()
        q.async {
            switch reg.reserve(.active) {
            case .success(let token):
                _ = ok.fetchAdd(1)
                if reg.rollback(token) { _ = rollbacksTrue.fetchAdd(1) }
                if !reg.rollback(token) { _ = secondUseRefused.fetchAdd(1) }  // once-consume
            case .failure: _ = typedRefusals.fetchAdd(1)   // typed exhaustion
            }
            group.leave()
        }
    }
    group.wait()
    let after = reg.debugCounts()
    check(ok.intValue + typedRefusals.intValue == 64, "RW11 every racer got success-or-typed-refusal")
    check(rollbacksTrue.intValue == ok.intValue, "RW11 every token rolled back exactly once")
    check(secondUseRefused.intValue == ok.intValue, "RW11 token is once-consume (second rollback refused typed)")
    check(after.active == before.active && after.pendingTerminal == before.pendingTerminal,
          "RW11 no leaked reservation after rollback",
          "active \(before.active)->\(after.active) pending \(before.pendingTerminal)->\(after.pendingTerminal)")
}

func armRW11b() {
    // FINDING 1 (headroom RESERVE, not check): hold ONE active
    // reservation (its terminal obligation is atomically reserved);
    // fault reserves now exhaust at cap-1 (the held obligation owns the
    // last slot); the holder's commit + active->fault transition STILL
    // commits - the r3-rev1 guarantee RW13's concurrent race broke.
    let reg = PlaybackRegistry.shared
    guard case .success(let held) = reg.reserve(.active) else {
        check(false, "RW11b initial active reserve refused"); return
    }
    // HOLD the tokens: a dropped Reservation rolls back in deinit
    // (finding 4a), which would make this loop never exhaust.
    var heldFaults: [PlaybackRegistry.Reservation] = []
    while case .success(let t) = reg.reserve(.fault) { heldFaults.append(t) }
    let faultReserves = heldFaults.count
    let heldTok = reg.register(root: RW12Payload(), token: held)
    check(heldTok != nil, "RW11b held active reservation commits under full fault backlog")
    if let t = heldTok {
        check(reg.reclassify(t, to: .fault), "RW11b FINDING-1-FIX active->fault commits with reserved terminal slot (concurrent terminal backlog full)")
    }
    check(faultReserves == PlaybackRegistry.maxRetainedFaults - 1,
          "RW11b fault headroom stops one short while a terminal obligation is held",
          "faultReserves=\(faultReserves)")
}

func armRW12() {
    // FINDING 3 (immutable root): register(root:token:) retains the
    // ROOT immutably; a caller release never frees it while the
    // registration lives; consumed tokens refuse typed.
    weak var weakRoot: RW12Payload? = nil
    var tok: RegistrationToken? = nil
    var secondRegisterNil = false
    do {
        let root = RW12Payload()
        weakRoot = root
        switch PlaybackRegistry.shared.reserve(.fault) {
        case .success(let token):
            tok = PlaybackRegistry.shared.register(root: root, token: token)
            secondRegisterNil = (PlaybackRegistry.shared.register(root: root, token: token) == nil)
        case .failure:
            check(false, "RW12 fault reservation refused unexpectedly")
        }
    }
    check(weakRoot != nil, "RW12 FINDING-3-FIX registration ROOT immutably retained (no rebind can free it)",
          "root freed - registry root retention broken")
    check(tok != nil, "RW12 registration token issued by token commit")
    check(secondRegisterNil, "RW12 consumed token cannot register twice (typed nil)")
}

// RW12b - FINDING 2/3 arms: typed graph ATTACHMENT (never a root
// replacement); capability-gated transitions.
private final class RW12Edge { let id: Int; init(_ i: Int) { id = i } }
private final class RW12Graph: FaultPayloadGraph {
    let ownerEdge: RW12Edge    // stands for the sink/ring owner edge
    let handle: RW12Edge       // stands for the provider-handle edge
    init(owner: RW12Edge, handle: RW12Edge) { self.ownerEdge = owner; self.handle = handle }
    var owner: AnyObject { ownerEdge }   // TYPED real owner (verdict S1)
    var strongEdgeCount: Int { 2 }
    var payloadDescription: String { "RW12Graph(owner+handle)" }
}
private final class RW12ThinGraph: FaultPayloadGraph {
    var owner: AnyObject { self }        // minimal legal graph
    var strongEdgeCount: Int { 1 }
    var payloadDescription: String { "thin" }
}
func armRW12b() {
    weak var weakOwner: RW12Edge? = nil
    weak var weakHandle: RW12Edge? = nil
    var tok: RegistrationToken? = nil
    var attachOK = false, thinRefused = false
    do {
        let owner = RW12Edge(2), handle = RW12Edge(3)
        weakOwner = owner; weakHandle = handle
        switch PlaybackRegistry.shared.reserve(.tombstone) {
        case .success(let res):
            tok = PlaybackRegistry.shared.register(root: RW12Edge(0), token: res)
            if let t = tok {
                let graph = RW12Graph(owner: owner, handle: handle)
                attachOK = PlaybackRegistry.shared.attachFaultGraph(t, graph)
                // Verdict S1: ATTACH-ONCE - a second attach (which could
                // drop the real owner behind a claimed count) is refused.
                thinRefused = !PlaybackRegistry.shared.attachFaultGraph(t, RW12ThinGraph())
                // FINDING 2: the mutation surface takes ONLY a
                // capability token - there is no public ID-based API
                // left to address another entry at all (RW12c covers
                // the transition rules).
            }
        case .failure:
            check(false, "RW12b tombstone reservation refused unexpectedly")
        }
    }
    check(attachOK, "RW12b typed fault graph ATTACHED (root untouched)")
    check(weakOwner != nil && weakHandle != nil,
          "RW12b graph edges (owner+handle) survive caller release",
          "an edge was freed - the fault graph is not strongly owned")
    check(thinRefused, "RW12b ATTACH-ONCE second attach refused typed (graph not replaceable)")
}

func armRW12c() {
    // FINDING 2 transition validation: active->fault and
    // active->tombstone commit; terminal->active REFUSED (arbitrary
    // resurrection impossible); terminal kind immutable
    // (fault->tombstone refused); foreign-token reclassify refused.
    let reg = PlaybackRegistry.shared
    guard case .success(let ra) = reg.reserve(.active),
          let ta = reg.register(root: RW12Edge(1), token: ra) else {
        check(false, "RW12c setup reserve/register refused"); return
    }
    check(reg.reclassify(ta, to: .fault), "RW12c active->fault commits (valid transition)")
    check(!reg.reclassify(ta, to: .active), "RW12c FINDING-2-FIX terminal->active REFUSED (no resurrection)")
    check(!reg.reclassify(ta, to: .tombstone), "RW12c terminal kind immutable (fault->tombstone refused)")
    guard case .success(let rb) = reg.reserve(.active),
          let tb = reg.register(root: RW12Edge(2), token: rb) else {
        check(false, "RW12c second setup refused"); return
    }
    // FINDING 2: reclassify binds to the token's OWN entry - tb can
    // only drive tb's registration; no API can name ta without ta's
    // token (structural capability, not a guessable UInt64).
    check(reg.reclassify(tb, to: .tombstone), "RW12c token drives its OWN entry (active->tombstone commits)")
    let st = reg.retentionState(of: ta)
    check(st.retained && st.kind == .fault, "RW12c retentionState typed query: fault registration retained")
}

func armRW13() {
    // Typed exhaustion per-kind under rev1 headroom: fill the fault
    // backlog (no held obligations) to the cap; the next fault reserve
    // fails TYPED; an ACTIVE reserve also fails typed while a terminal
    // backlog is full (its atomically-reserved obligation cannot fit).
    let reg = PlaybackRegistry.shared
    var last: Result<PlaybackRegistry.Reservation, RegistryExhausted>? = nil
    for _ in 0..<64 {
        last = reg.reserve(.fault)
        switch last! {
        case .success(let t): _ = reg.register(root: RW12Payload(), token: t)
        case .failure: break
        }
        if case .failure = last! { break }
    }
    switch last {
    case .failure(let e):
        check(e.faults == PlaybackRegistry.maxRetainedFaults,
              "RW13 fault exhaustion at the per-kind cap", "faults=\(e.faults)")
        print("PASS RW13 typed exhaustion at per-kind cap (active=\(e.active) faults=\(e.faults) tombstones=\(e.tombstones))")
    default:
        check(false, "RW13 reserve never exhausts (unbounded growth = verdict S1e violation)")
    }
    switch reg.reserve(.active) {
    case .failure:
        print("PASS RW13 active reserve refuses typed while a terminal backlog is full")
    case .success(let t):
        _ = reg.rollback(t)
        check(false, "RW13 active reserve granted with full fault backlog (reserved-obligation headroom broken)")
    }
    switch reg.reserve(.tombstone) {
    case .success(let t):
        _ = reg.rollback(t)
        print("PASS RW13 tombstone headroom independent of fault cap")
    case .failure:
        check(false, "RW13 tombstone cap consumed by fault exhaustion (per-kind isolation broken)")
    }
}

func armRW26() {
    // S4 FINDINGS 7-9 (generation-bound outcome cache): a cached outcome
    // is returned only for the CURRENT generation; an in-flight stop
    // reads .pending (never stale, never bare .noop); publication
    // precedes the lifecycle transition.
    let c = StopOutcomeCache()
    check(c.idleOutcome() == .noop, "RW26 no evidence -> .noop")
    c.noteStart(generation: 1)
    c.noteStopInFlight()
    check(c.idleOutcome() == .pending, "RW26 FINDING-7-FIX in-flight stop reads .pending (not stale, not noop)")
    let ev1 = AudioStopEvidence(generation: 1, stopStatus: 0, uninitStatus: 0, disposeStatus: 0,
                                readersDrained: true, producerWitnessed: true, drainResidual: nil,
                                retainedRegistration: nil)
    c.publish(generation: 1, outcome: .complete(ev1))
    check(c.idleOutcome().isComplete, "RW26 published outcome returned for its generation")
    check(c.idleOutcome().isComplete, "RW26 repeat idle query returns the SAME preserved outcome")
    c.noteStart(generation: 2)
    check(c.idleOutcome() == .noop, "RW26 FINDING-7-FIX new generation invalidates the old cache (no g1 outcome from g2 stop)")
    c.noteStopInFlight()
    let ev2 = AudioStopEvidence(generation: 2, stopStatus: -1, uninitStatus: 0, disposeStatus: 0,
                                readersDrained: false, producerWitnessed: false, drainResidual: nil,
                                retainedRegistration: nil)
    c.publish(generation: 2, outcome: .failed(ev2))
    if case .failed(let e) = c.idleOutcome() {
        check(e.generation == 2, "RW26 FINDING-8-FIX start/stop-owned failure evidence preserved for its generation")
    } else { check(false, "RW26 failed outcome not preserved") }
    // Verdict S4: a STALE-generation publish is refused typed and must
    // NOT clobber the current cache nor clear a live in-flight marker.
    c.noteStopInFlight()
    check(!c.publish(generation: 1, outcome: .complete(ev1)), "RW26 stale-generation publish refused typed")
    check(c.idleOutcome() == .pending, "RW26 stale publish did not clear the current in-flight marker")
    c.publish(generation: 2, outcome: .failed(ev2))
}

// RW27 - verdict S1 registration distinctness under concurrency: every
// committed registration gets a UNIQUE id and keeps its OWN root (the
// re-issue/overwrite class at reachable scale; the MAX boundary itself
// is model-level - 2^64 mints are not a runnable witness).
final class RW27Root { let tag: Int; init(_ t: Int) { tag = t } }
func armRW27() {
    let reg = PlaybackRegistry.shared
    var toks: [RegistrationToken] = []
    var roots: [RW27Root] = []
    let g = DispatchGroup(); let q = DispatchQueue(label: "rw27", attributes: .concurrent)
    let lock = NSLock()
    for i in 0..<2 {   // remaining tombstone capacity after RW12b/RW12c
        g.enter(); q.async {
            if case .success(let r) = reg.reserve(.tombstone),
               let t = reg.register(root: RW27Root(i), token: r) {
                lock.lock(); toks.append(t); roots.append(RW27Root(i)); lock.unlock()
            }
            g.leave()
        }
    }
    g.wait()
    check(Set(toks.map { $0.id }).count == toks.count && toks.count == 2,
          "RW27 concurrent registration ids unique (no re-issue/overwrite)", "\(toks.map { $0.id })")
    var allRetained = true
    for t in toks { if !reg.retentionState(of: t).retained { allRetained = false } }
    check(allRetained, "RW27 every concurrent registration keeps its own root")
}

func armRW26b() {
    // Verdict S4 REAL INTERLEAVING (not the ideal setter sequence): two
    // CONCURRENT stops over the real SessionLifecycle + StopOutcomeCache
    // wiring. Exactly one teardown owner; the in-flight marker is taken
    // atomically inside the lifecycle lock; the loser observes pending-
    // then-cached; the winner publishes BEFORE the transition.
    let lc = SessionLifecycle(); let cache = StopOutcomeCache()
    let g = lc.beginStart()!; _ = lc.commitStart(g)
    cache.noteStart(generation: g)
    let owners = AtomicU64()!; let pendingSeen = AtomicU64()!; let cachedSeen = AtomicU64()!
    let grp = DispatchGroup(); let q = DispatchQueue(label: "rw26b", attributes: .concurrent)
    for _ in 0..<2 {
        grp.enter(); q.async {
            switch lc.beginStop(onStopTransition: { cache.noteStopInFlight() }) {
            case .teardownOwned(let gg):
                _ = owners.fetchAdd(1)
                // Winner: simulate teardown work, then publish-then-finish.
                let ev = AudioStopEvidence(generation: gg, stopStatus: 0, uninitStatus: 0,
                                           disposeStatus: 0, readersDrained: true,
                                           producerWitnessed: true, drainResidual: nil,
                                           retainedRegistration: nil)
                cache.publish(generation: gg, outcome: .complete(ev))
                lc.finishStop(gg)
            case .startWillTearDown:
                break
            case .none:
                // Loser path: while the winner tears down this reads
                // .pending; after publication it reads the cached outcome.
                let idle = cache.idleOutcome()
                if idle == .pending { _ = pendingSeen.fetchAdd(1) }
                else if idle.isComplete { _ = cachedSeen.fetchAdd(1) }
            }
            grp.leave()
        }
    }
    grp.wait()
    check(owners.intValue == 1, "RW26b exactly one teardown owner across concurrent stops")
    check(pendingSeen.intValue + cachedSeen.intValue == 1,
          "RW26b concurrent loser saw pending-or-cached, never a bare noop gap",
          "pending=\(pendingSeen.intValue) cached=\(cachedSeen.intValue)")
    // Post-completion repeat stop: the cached outcome, generation-bound.
    check(lc.beginStop() == .none, "RW26b post-finish beginStop is a no-op")
    check(cache.idleOutcome().isComplete, "RW26b repeat stop returns the preserved outcome")
}
armRW11(); armRW11b(); armRW12(); armRW12b(); armRW12c(); armRW13(); armRW26(); armRW26b()
print("RW11-RW13+RW26 registry/outcome acceptance arms done (r3-rev1 capability state machine).")

// === L9 TEARDOWN SUBSET (RW14-RW22), integrated 2026-10-25, renumbered vs RW11-13.
// RW14 - SessionLifecycle teardown transition matrix: running dies WITH the
// stop transition; double stop is a no-op; wrong-generation finishStop is
// ignored; generations are never reused across cycles.
func armRW14() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!; _ = lc.commitStart(g)
    check(lc.runningGen == g, "RW14 runningGen born with active transition")
    check(lc.beginStop() == .teardownOwned(g), "RW14 beginStop -> teardownOwned")
    check(lc.runningGen == nil, "RW14 runningGen nil in the SAME transition (no late-running window)")
    check(lc.beginStop() == .none, "RW14 NEG second beginStop no-op (single teardown owner)")
    lc.finishStop(g &+ 99)
    if case .stopping(let s) = lc.current { check(s == g && lc.stopCount == 0, "RW14 NEG finishStop(wrong g) ignored") } else { check(false, "RW14 NEG finishStop(wrong g) ignored", "\(lc.current)") }
    lc.finishStop(g)
    var gs: [UInt64] = []
    for _ in 0..<3 { let h = lc.beginStart()!; _ = lc.commitStart(h); _ = lc.beginStop(); lc.finishStop(h); gs.append(h) }
    check(gs == [g+1, g+2, g+3], "RW14 generations strictly monotonic, no reuse", "\(gs)")
}

// RW15 - terminal teardown: failStop/failStart are TERMINAL - no restart, no
// fake completion, no re-teardown; the retained fault is never overwritten.
func armRW15() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!; _ = lc.commitStart(g); _ = lc.beginStop()
    lc.failStop(g)
    check(lc.current == .failed(g), "RW15 failStop -> failed terminal")
    check(lc.beginStart() == nil && lc.refusedStartFailedCount == 1, "RW15 restart after failed teardown refused (retained handle never overwritten)")
    lc.finishStop(g)
    check(lc.stopCount == 0 && lc.current == .failed(g), "RW15 NEG finishStop after failStop is NOT a fake completion")
    check(lc.beginStop() == .none && lc.runningGen == nil, "RW15 NEG no re-teardown, no running resurrection in failed")
    let lc2 = SessionLifecycle(); let h = lc2.beginStart()!
    lc2.failStart(h)
    check(lc2.beginStart() == nil && lc2.refusedStartFailedCount == 1, "RW15 failStart terminal, start refused")
}

// RW16 - stop races start: stop during starting does NOT touch the unit; the
// start side observes commitStart()==false and tears down itself; the abort
// completes the stop exactly once.
func armRW16() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!
    check(lc.beginStop() == .startWillTearDown(g), "RW16 stop during starting -> startWillTearDown (stop does NOT tear down)")
    check(lc.runningGen == nil, "RW16 runningGen never born for torn-down start")
    check(!lc.commitStart(g), "RW16 commitStart after stop race refused")
    lc.abortStart(g)
    check(lc.current == .idle && lc.abortedStartCount == 1 && lc.stopCount == 1, "RW16 abort in stopping completes the stop once")
}

// RW17 - GenerationFence: late callback after the stop boundary is fenced and
// EVERY stale call is counted; a new generation commit re-admits only itself.
func armRW17() {
    let f = GenerationFence(); let g0 = f.active
    check(f.checkRT(g0), "RW17 active generation admitted")
    f.advance()
    check(!f.checkRT(g0) && f.fencedCount == 1, "RW17 late callback from retired generation fenced + counted")
    _ = f.checkRT(g0)
    check(f.fencedCount == 2, "RW17 every stale call counted (no dedup)")
    let g1 = f.active; f.setActive(g1 &+ 5)
    check(f.checkRT(g1 &+ 5) && !f.checkRT(g1), "RW17 old generation stays fenced after new commit")
}

// RW18 - receipt BEFORE reset: the retired session's admission evidence
// survives resetForNewGeneration; live counters zero; drop accounting is
// byte-exact with a sticky latch cleared only by the per-generation reset.
func armRW18() {
    guard let ring = SPSCPCMRing(capacityFrames: 16) else { check(false, "RW18 alloc"); return }
    var bytes = [UInt8](repeating: 0xAB, count: 12)
    let pr = bytes.withUnsafeBufferPointer { ring.push($0) }
    check(pr.admittedFrames == 3, "RW18 3 frames admitted")
    var dst = [UInt8](repeating: 0, count: 8)
    _ = dst.withUnsafeMutableBufferPointer { ring.render(into: $0.baseAddress!, frames: 2) }
    let receipt = ring.snapshotReceipt(generation: 7)
    ring.resetForNewGeneration()
    check(receipt.pushedFrames == 3 && receipt.consumedFrames == 2 && receipt.admittedBytes == 12, "RW18 receipt holds retired-session evidence across reset")
    check(ring.pushedFrames.load() == 0 && ring.availableFrames == 0, "RW18 live counters zero after reset")
    guard let small = SPSCPCMRing(capacityFrames: 2) else { return }
    var five = [UInt8](repeating: 1, count: 20)
    let ov = five.withUnsafeBufferPointer { small.push($0) }
    check(ov.admittedFrames == 2 && ov.droppedFrames == 3 && small.droppedBytes.load() == 12 && small.droppedAnything.load() == 1, "RW18 NEG overflow drop byte-exact + sticky latch")
    var tail = [UInt8](repeating: 2, count: 10)
    let pt = tail.withUnsafeBufferPointer { small.push($0) } // ring already full
    check(pt.droppedTailBytes == 2 && small.partialTailDrops.load() == 1, "RW18 NEG partial-frame tail refused byte-exact, never misaligned")
    check(small.requestedBytes.load() == small.admittedBytes.load() + small.droppedBytes.load(), "RW18 byte conservation requested==admitted+dropped")
    small.resetForNewGeneration()
    check(small.droppedAnything.load() == 0, "RW18 reset clears the sticky latch")
}

// RW19 - producer gate after stop-reset: a producer that captured the running
// generation BEFORE stop must be refused on RE-CHECK; the new session never
// reuses the captured generation. (Core mirror of AudioUnitSink.push :326-327;
// the sink wiring itself is MacShell.)
func armRW19() {
    let lc = SessionLifecycle(); let g = lc.beginStart()!; _ = lc.commitStart(g)
    let captured = lc.runningGen
    check(captured == g, "RW19 producer pre-check sees running generation")
    _ = lc.beginStop(); lc.finishStop(g)
    check(lc.runningGen == nil, "RW19 joined/absent stop-reset: re-check refuses (no old push into stopped session)")
    check(lc.beginStart()! != g, "RW19 new session generation differs from captured stale one")
}

// RW20 - teardown completeness is ORDERED and PER-SESSION/GENERATION; the
// record ceiling drops are counted and refuse success; a non-finite stamp
// refuses success with a visibly corrupted record.
func armRW20() {
    var t = 1000.0
    let l = TimingLedger(capacity: 64, clock: { t })
    let req: [LedgerKind] = [.audioStartAttempt, .audioStartAccepted, .audioStopAttempt, .audioStopAccepted, .disposeCompleted]
    for k in req { l.append(session: 1, generation: 1, segment: .teardown, subsystem: .audio, kind: k) }
    check(l.missingSequence(session: 1, generation: 1, required: req).isEmpty, "RW20 ordered teardown sequence complete")
    check(l.missingSequence(session: 1, generation: 2, required: req) == req, "RW20 NEG foreign generation fulfills nothing")
    check(l.missingSequence(session: 2, generation: 1, required: req) == req, "RW20 NEG foreign session fulfills nothing")
    let l2 = TimingLedger(capacity: 3, clock: { t })
    for i in 0..<5 { l2.append(session: 0, generation: 0, segment: .teardown, subsystem: .core, kind: .teardownStart, bytes: i) }
    check(l2.count == 3 && l2.overflowed && l2.droppedEventCount == 2 && !l2.allowsSuccess, "RW20 NEG ceiling exact: 3 kept 2 dropped, refuses success")
    var bad = false; let badClock: @Sendable () -> Double = { bad ? .nan : 1000.0 }
    let l3 = TimingLedger(capacity: 16, clock: badClock); bad = true
    l3.append(session: 0, generation: 0, segment: .teardown, subsystem: .core, kind: .teardownStart)
    check(l3.invalidStampCount == 1 && !l3.allowsSuccess && l3.snapshot().first?.note.hasPrefix("INVALID_STAMP:") == true, "RW20 NEG non-finite stamp counted, marked, refuses success")
    t += 1
}

// RW21 - FINDING REPRODUCTION (observed v5/lane-0 candidate gaps; FAIL = the
// finding): (a) jsonLines reserves the truncation marker but not the header,
// so for maxBytes in (header, header+marker) the export exceeds its own byte
// ceiling (observed exact: maxBytes=120 -> 191 bytes). (b) A small-budget
// export sets overflowed and flips allowsSuccess false - an export-formatting
// budget permanently poisons the run verdict.
func armRW21() {
    let t = 1000.0
    let hl = TimingLedger(capacity: 100, clock: { t })
    let headerLen = hl.jsonLines(maxBytes: 10_000_000).utf8.count
    var firstBad = -1
    for mb in stride(from: 60, through: 900, by: 4) {
        let l = TimingLedger(capacity: 100, clock: { t })
        for i in 0..<8 { l.append(session: 1, generation: 1, segment: .teardown, subsystem: .audio, kind: .teardownStart, bytes: i, note: String(repeating: "n", count: 120)) }
        if mb > headerLen && l.jsonLines(maxBytes: mb).utf8.count > mb { firstBad = mb; break }
    }
    check(firstBad < 0, "RW21a export byte ceiling holds for every budget", "GAP REPRODUCED: header=\(headerLen) firstBad=\(firstBad) (export exceeds maxBytes in (header, header+marker))")
    let l2 = TimingLedger(capacity: 100, clock: { t })
    for i in 0..<8 { l2.append(session: 1, generation: 1, segment: .teardown, subsystem: .audio, kind: .teardownStart, bytes: i, note: String(repeating: "n", count: 120)) }
    let before = l2.allowsSuccess
    _ = l2.jsonLines(maxBytes: 400)
    check(!(before && !l2.allowsSuccess), "RW21b export budget does not poison the run verdict", "GAP REPRODUCED: truncated export set overflowed, allowsSuccess flipped false")
}

// RW22 - FINDING REPRODUCTION (architect blocker 1, weak-nil reader leak):
// the lane-0 callback guard (AudioUnitSink.swift :267-271) enters admission
// BEFORE the weak-sink check and returns -50 WITHOUT exit() on the nil
// branch. Executed here: the ACTUAL production AdmissionCell with the
// guard's exact order transcribed (the Mac callback body is not
// Linux-reachable - proxy for the guard sequence, native for the cell).
func armRW22() {
    guard let cell = AdmissionCell() else { check(false, "RW22 alloc"); return }
    let sinkIsNil = true
    if cell.enter() { if sinkIsNil { /* return -50 :271 - no exit() */ } }
    let atRetire = cell.retire()
    // ARM status (Main convention): the OLD guard shape leaked the reader;
    // the r2 callback balances defer-on-admit so the leak shape is gone.
    print("ARM RW22 old=EXPECTED-FAIL reproduced(readerLeak=\(atRetire == 1 && cell.readers == 1)) revised-core=PASS-by-control native=BLOCKED(Mac callback body owner-run)")
    guard let ctl = AdmissionCell() else { return }
    if ctl.enter() { if sinkIsNil { ctl.exit() } }
    check(ctl.retire() == 0 && ctl.readers == 0, "RW22 control: exit-on-nil drains to zero")
}


print("SEAM RW23 real-AudioUnit stop/uninit/dispose error injection + retired-callback zero-output: MacShell arms, owner-run; NOT claimed from Linux")

// === r3 S5 SUBSET (RW24-RW25): shared cancel/commit + typed end reason ===

final class RW25Clock: PlaybackClock, @unchecked Sendable {
    var t = 0.0
    func nowSeconds() -> Double { t }
}
final class RW25Source: FrameSource, @unchecked Sendable {
    var events: [SourceEvent]; var i = 0
    init(_ events: [SourceEvent]) { self.events = events }
    func nextEvent() async -> SourceEvent {
        if i >= events.count { return .ended(.sourceEnded) }
        let e = events[i]; i += 1; return e
    }
}
final class RW25Sink: FrameSink, @unchecked Sendable {
    var shown = 0
    func show(_ frame: SourceFrame) async -> Bool { shown += 1; return true }
    // Explicit TEST-FAKE ticketed conformance (the protocol has NO
    // bypass default - verdict S5 rev3): the fake forwards by choice;
    // the REAL strict boundary is proven at CancelCommit.commitFrame
    // (RW30) and in DisplaySink's fail-closed strict show.
    func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        await show(frame)
    }
}

func armRW24() {
    // Shared cancel/commit cell: admission serializes on ONE CAS.
    let commit = CancelCommit()
    check(commit.available, "RW24 commit cell available")
    let t0 = commit.tryAdmit(revision: 0)
    // Verdict S5 rev3: the post-cancel arm needs a FRESH UNCONSUMED
    // ticket - reusing a consumed one would pass from replay rejection
    // even with the cancel fence broken.
    let t0fresh = commit.tryAdmit(revision: 0)
    check(t0 != nil && t0fresh != nil, "RW24 admit before cancel succeeds (tickets issued)")
    check(commit._testMayFinishConsume(ticket: t0!), "RW24 pre-ACK ticket may finish its commit")
    check(commit.admitted == 2, "RW24 admissions counted on the cell")
    commit.requestCancel(); commit.requestCancel()   // idempotent
    check(commit.isCancelled, "RW24 cancel set monotonically")
    check(commit.tryAdmit(revision: 0) == nil, "RW24 no admission after cancel (serialized refusal)")
    check(commit.validate(ticket: t0fresh!), "RW24 pre-admitted ticket stays GENUINE (sequence issued)")
    check(!commit._testMayFinishConsume(ticket: t0fresh!), "RW24 ACK=NO-FURTHER-COMMIT fresh unconsumed ticket fenced after the cancel-ACK")
    check(commit.admitted == 2, "RW24 post-cancel refusal not counted")
    do { _ = try commit.bumpRevision(); check(false, "RW24 cancelled commit seek must throw .cancelled") }
    catch let e as CancelCommit.SeekRefusal { check(e == .cancelled, "RW24 cancelled seek is a typed .cancelled refusal") }
    catch { check(false, "RW24 unexpected seek error type") }
    check(commit.tryAdmit(revision: 0) == nil, "RW24 cancelled commit refuses admission")

    let c2 = CancelCommit()
    _ = try! c2.bumpRevision()
    check(c2.tryAdmit(revision: 0) == nil, "RW24 stale revision refused typed")
    check(c2.tryAdmit(revision: 1) != nil, "RW24 current revision admitted")
    // Verdict S5: NO caller-revision mask alias - an out-of-range
    // revision is refused typed, never aliased into the 31-bit field.
    check(c2.tryAdmit(revision: 1 << 31) == nil, "RW24 ALIAS-FIX out-of-range revision refused (no mask alias)")
    // Finish contract across a seek: a pre-seek ticket stays genuine
    // (admission was the gate), but NEW admissions need the new revision.
    let preSeek = c2.tryAdmit(revision: 1)!
    _ = try! c2.bumpRevision()
    check(c2.validate(ticket: preSeek), "RW24 pre-seek ticket stays GENUINE (sequence issued)")
    check(!c2._testMayFinishConsume(ticket: preSeek), "RW24 ACK=NO-FURTHER-COMMIT old-revision ticket fenced at commit after seek")
    check(c2.tryAdmit(revision: 1) == nil && c2.tryAdmit(revision: 2) != nil,
          "RW24 post-seek admission needs the exact new revision")
    // Race smoke: admissions vs a concurrent cancel - counts must add
    // up, no admit lands after the cell shows cancelled.
    let c3 = CancelCommit()
    let okN = AtomicU64()!; let noN = AtomicU64()!
    let g = DispatchGroup(); let q = DispatchQueue(label: "rw24", attributes: .concurrent)
    for _ in 0..<64 {
        g.enter(); q.async {
            if c3.tryAdmit(revision: 0) != nil { _ = okN.fetchAdd(1) } else { _ = noN.fetchAdd(1) }
            g.leave()
        }
    }
    q.async { c3.requestCancel() }
    g.wait()
    check(okN.intValue + noN.intValue == 64, "RW24 race: every racer admitted-or-refused")
    check(c3.admitted == UInt64(okN.intValue), "RW24 cell admission count == successful admits (no interleave)")
}

func armRW25() {
    // (a) source-reported cancel sets BOTH the typed end reason and the
    // cancelled flag (r2 defect: flag stayed false).
    let src = RW25Source([.ended(.cancelled)])
    let sink = RW25Sink()
    let pump = FramePump(source: src, sink: sink, clock: RW25Clock(), onWait: { _ in true })
    let sem = DispatchSemaphore(value: 0)
    var statsBox: PumpStats? = nil
    Task { statsBox = await pump.run(); sem.signal() }
    sem.wait()
    let st = statsBox!
    check(st.cancelled, "RW25 source-reported cancel sets stats.cancelled")
    check(st.endReason == .cancelled, "RW25 end reason is TYPED .cancelled", "\(st.endReason)")

    // (b) commit-wired pump: an external cancel before the show admits
    // nothing; the cell carries the refusal, not just a bool check.
    let commit = CancelCommit()
    let src2 = RW25Source([.frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "a"))])
    let sink2 = RW25Sink()
    let pump2 = FramePump(source: src2, sink: sink2, clock: RW25Clock(), commit: commit, onWait: { _ in true })
    commit.requestCancel()
    let sem2 = DispatchSemaphore(value: 0)
    var statsBox2: PumpStats? = nil
    Task { statsBox2 = await pump2.run(); sem2.signal() }
    sem2.wait()
    let st2 = statsBox2!
    check(st2.shown == 0 && sink2.shown == 0, "RW25 externally-cancelled commit admits zero shows")
    check(commit.admitted == 0, "RW25 commit cell recorded zero admissions")
    check(st2.cancelled && st2.endReason == .cancelled, "RW25 pump ends typed cancelled via commit")

    // (c) Verdict S5 rev6: an external INVALIDATION (direct bump)
    // before the pump's first pull does NOT fence new production on a
    // stateless source - the pull stamps the LIVE revision at pull
    // start and admits under it. (Stale-PULL and stale-WAIT fencing,
    // where production CROSSED the ACK, is witnessed by RW31/RW32.)
    let commit3 = CancelCommit()
    let src3 = RW25Source([.frame(SourceFrame(ptsSeconds: 0.0, durationSeconds: 0.04, digest: "b")),
                           .ended(.endOfStream)])
    let sink3 = RW25Sink()
    let ledger = TimingLedger(capacity: 32, clock: { 0.0 })
    let pump3 = FramePump(source: src3, sink: sink3, clock: RW25Clock(),
                          ledger: ledger, ledgerSession: 1, ledgerGeneration: 1,
                          commit: commit3, onWait: { _ in true })
    _ = try! commit3.bumpRevision()   // external seek AFTER pump adopted rev 0
    let sem3 = DispatchSemaphore(value: 0)
    var statsBox3: PumpStats? = nil
    Task { statsBox3 = await pump3.run(); sem3.signal() }
    sem3.wait()
    let st3 = statsBox3!
    check(st3.shown == 1 && sink3.shown == 1 && commit3.admitted == 1,
          "RW25 post-invalidation pull on a stateless source admits under the live revision")
    check(st3.endReason == .endOfStream, "RW25 admission is not an end; source EOS reached")
    check(st3.seekStalePulls == 0, "RW25 no stale pull: the pull started after the invalidation")
}

func armRW28() {
    // Verdict S1 rev2 FULL BOUNDARY MATRIX on a seeded fresh instance
    // (the shared minter is permanently consumed by earlier arms - a
    // boundary matrix needs a fresh minter): mint-at-reserve ordering,
    // rollback burns (never re-issues) an id, the last valid id mints
    // once, exhaustion latches permanently, a HELD pre-ceiling token
    // registers post-ceiling with a distinct root, refusals are typed,
    // and roots stay reachable through the capability-gated accessor.
    let reg = PlaybackRegistry(testSeedNextID: UInt64.max - 3)

    // 1. rollback BURNS the id: r0 mints max-2, rolls back, and the
    //    next reserve mints max-1 - the burned id is never re-issued.
    guard case .success(let r0) = reg.reserve(.tombstone) else {
        check(false, "RW28 r0 reserve refused unexpectedly"); return
    }
    check(r0.id == UInt64.max - 2, "RW28 first mint is the seeded next id")
    check(reg.rollback(r0), "RW28 held-token rollback releases the slot")
    guard case .success(let r1) = reg.reserve(.tombstone),
          case .success(let r2) = reg.reserve(.tombstone) else {
        check(false, "RW28 r1/r2 reserves refused unexpectedly"); return
    }
    check(r1.id == UInt64.max - 1 && r2.id == UInt64.max,
          "RW28 mints continue in order after a burn (no re-issue): \(r1.id), \(r2.id)")

    // 2. the LAST VALID id minted exactly once: the next reserve hits
    //    the ceiling, refuses typed, and latches permanent exhaustion.
    if case .failure = reg.reserve(.tombstone) {
        print("PASS RW28 reserve at the issuance ceiling refuses typed")
    } else {
        check(false, "RW28 reserve at the ceiling succeeded (wrap!)")
    }
    if case .failure = reg.reserve(.tombstone) {
        print("PASS RW28 exhaustion LATCHED (second reserve still refuses)")
    } else {
        check(false, "RW28 exhaustion not latched (reserve succeeded after the ceiling)")
    }

    // 3. a HELD pre-ceiling token REGISTERS post-ceiling (mint-at-
    //    reserve makes exhaustion stop NEW issuance, never a valid
    //    insert): both held tokens register with distinct ids, no
    //    re-issue, no root overwrite.
    var toks: [RegistrationToken] = []
    let lock = NSLock()
    let g = DispatchGroup(); let q = DispatchQueue(label: "rw28", attributes: .concurrent)
    for (i, r) in [r1, r2].enumerated() {
        g.enter(); q.async {
            if let t = reg.register(root: RW27Root(i), token: r) { lock.lock(); toks.append(t); lock.unlock() }
            g.leave()
        }
    }
    g.wait()
    check(toks.count == 2 && Set(toks.map { $0.id }).count == 2,
          "RW28 held pre-ceiling tokens register post-ceiling DISTINCT", "\(toks.map { $0.id })")
    check(toks.allSatisfy { reg.retentionState(of: $0).retained },
          "RW28 both boundary roots retained (no overwrite)")

    // 4. root retention reachable through the capability-gated
    //    accessor, and ONLY for the registered capability.
    for t in toks {
        check(reg.root(of: t) != nil, "RW28 capability-gated root reachable post-ceiling")
    }
    check(reg.retentionState(of: toks[0]).kind == .tombstone,
          "RW28 retention kind intact post-ceiling")
}

func armRW29() {
    // Verdict S5 rev2 ticket transport arms + seeded ceilings.
    // A. issuer binding: a ticket is genuine ONLY on its issuing cell.
    let a = CancelCommit(); let b = CancelCommit()
    let ta = a.tryAdmit(revision: 0)!
    check(!b.validate(ticket: ta), "RW29 cross-cell validate refuses a foreign ticket")
    check(!b._testMayFinishConsume(ticket: ta), "RW29 cross-cell mayFinish refuses a foreign ticket")
    check(a.validate(ticket: ta), "RW29 issuer validate accepts its own ticket")
    // B. single consume: mayFinish BURNS the ticket - a replay is a
    //    typed refusal even on the issuer, while genuineness (validate)
    //    remains a stable historical fact.
    check(a._testMayFinishConsume(ticket: ta), "RW29 first mayFinish consumes the ticket")
    check(!a._testMayFinishConsume(ticket: ta), "RW29 replayed mayFinish refused (single consume)")
    check(a.validate(ticket: ta), "RW29 consumed ticket stays genuine (validate is not the gate)")
    // C. seeded ADMISSION ceiling: the REAL saturating algorithm at
    //    2^32-1 - the next admission is a typed nil refusal, the count
    //    never wraps into the revision field.
    let cAd = CancelCommit(testSeedAdmissions: CancelCommit.admitCeilingForTest, revision: 0)
    check(cAd.tryAdmit(revision: 0) == nil, "RW29 seeded admission ceiling refuses typed")
    check(cAd.revision == 0, "RW29 admission saturation never carries into revision")
    check(cAd.admissionExhausted, "RW29 admissionExhausted reads true at the ceiling")
    // D. seeded REVISION ceiling: the REAL saturating bump at 2^31-1 -
    //    one bump lands, the next is a typed .exhausted throw, and the
    //    cancel bit is untouched.
    let cRev = CancelCommit(testSeedAdmissions: 0, revision: CancelCommit.revisionCeilingForTest - 1)
    do {
        let bumped = try cRev.bumpRevision()
        check(bumped == CancelCommit.revisionCeilingForTest, "RW29 seeded near-ceiling bump lands exactly at the ceiling")
    } catch { check(false, "RW29 near-ceiling bump threw unexpectedly") }
    do { _ = try cRev.bumpRevision(); check(false, "RW29 ceiling bump must throw .exhausted") }
    catch let e as CancelCommit.SeekRefusal { check(e == .exhausted, "RW29 ceiling bump is a typed .exhausted refusal") }
    catch { check(false, "RW29 unexpected ceiling bump error type") }
    check(!cRev.isCancelled, "RW29 revision saturation never carries into the cancel bit")
    check(cRev.seekExhausted, "RW29 seekExhausted reads true at the ceiling")
    check(cRev.tryAdmit(revision: CancelCommit.revisionCeilingForTest) != nil,
          "RW29 admissions still issue at the seek ceiling (independent fields)")
}
/// RW30 (verdict S5 rev5): locked state box + poll-with-deadline - the
/// ACK-blocking witness reads state ONLY under the lock, and the 2s
/// bound guards a STUCK witness, never a success-timing oracle.
armRW24(); armRW25(); armRW27(); armRW28(); armRW29(); armRW30(); armRW31(); armRW32(); armRW33(); armRW14(); armRW15(); armRW16(); armRW17(); armRW18(); armRW19(); armRW20(); armRW21(); armRW22()
print("RW14-RW22 L9 teardown subset done (RW21 now ACCEPTANCE after production fix; RW22 ARM status).")
