import Foundation
func check(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
// Replay the old forwarding mistake even when each child has a fresh rate state.
// Initial-document fence must stop the recursive edge independently of routing.
var processes = 1, spawned = 0
for event in 0..<500 {
    let receiverInitial = event > 0
    if IndependentSpawnFence.refusal(receiverInitial: receiverInitial,
        runningCount: processes, recentSpawnTimes: [], now: Double(event)) == nil {
        spawned += 1; processes += 1
    }
}
check(spawned == 1 && spawned <= 5, "receiver initial 500 replay")
// Global observed-count fence, independent of receiver and rate policy.
processes = 1; spawned = 0
for event in 0..<500 {
    if IndependentSpawnFence.refusal(receiverInitial: false, runningCount: processes,
        recentSpawnTimes: [], now: Double(event)*11) == nil { processes += 1; spawned += 1 }
}
check(spawned == 5, "observed process count 500 replay")
// One already-running caller, no process-count pressure, a rapid 500-event burst.
var times: [Double] = []; spawned = 0
for event in 0..<500 {
    let now=Double(event)/1000
    if IndependentSpawnFence.refusal(receiverInitial: false, runningCount: 1,
        recentSpawnTimes: times, now: now) == nil { times.append(now); spawned += 1 }
}
check(spawned == 2, "per-process burst 500 replay")
check(IndependentSpawnFence.refusal(receiverInitial:false,runningCount:1,recentSpawnTimes:[0,1],now:10)==nil,"10s boundary")
check(IndependentSpawnFence.refusal(receiverInitial:false,runningCount:6,recentSpawnTimes:[],now:10)=="running-count","count boundary")
print("PASS 500-event receiver/count/rate replays and boundary checks")
var early = IndependentDocumentRouter(commandLinePath: nil, receiver: true)
_ = early.receive("/tmp/A")
early.replacePendingInitial("/tmp/B")
check(early.startup()!! == "/tmp/B", "refusal before startup adopts current document once")
check(early.startup() == nil, "no second startup")
