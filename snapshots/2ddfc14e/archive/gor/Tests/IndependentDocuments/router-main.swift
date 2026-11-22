import Foundation
var count = 0
func check(_ ok: Bool) { count += 1; precondition(ok, "router check \(count)") }
let a="/tmp/gor-document-A.mp4", b="/tmp/gor-document-B.mp4", c="/tmp/gor-document-C.mp4"
// Actual old guard: nonempty argv forces a launch on every delivery, at
// every generation. Bound the witness rather than executing any processes.
var oldSpawnCount = 0
for _ in 0..<500 { let videoPath = a; if !videoPath.isEmpty { oldSpawnCount += 1 } }
check(oldSpawnCount == 500)
for startupFirst in [false, true] {
    var child = IndependentDocumentRouter(commandLinePath: nil, receiver: true)
    if startupFirst { check(child.startup() == nil) }
    check(child.receive(a) == .initial(a))
    if !startupFirst { check(child.startup()! == a) }
    // A new explicit request after initial delivery remains a new player,
    // including reopening the same file. No process-global path ignore.
    check(child.receive(a) == .launch(a))
    check(child.receive(b) == .launch(b))
}
for batch in [[a,b], [b,a]] {
    var root = IndependentDocumentRouter(commandLinePath: a, receiver: false)
    _ = root.startup()
    var launches=[String]()
    for p in batch { if case .launch(let f) = root.receive(p) { launches.append(f) } }
    check(launches == [b])
    check(root.receive(a) == .launch(a))
}
var root = IndependentDocumentRouter(commandLinePath: nil, receiver: false)
check(root.receive(a) == .initial(a));check(root.receive(b) == .launch(b));check(root.receive(c) == .launch(c))
check(root.startup()! == a)
var child = IndependentDocumentRouter(commandLinePath: nil, receiver: true)
check(child.startup() == nil);check(child.receive(b) == .initial(b))
// One forwarding request creates one receiver, whose initial event spawns none.
var launches=0
var parent = IndependentDocumentRouter(commandLinePath: a, receiver: false);_ = parent.startup()
if case .launch = parent.receive(b) { launches += 1 }
var receiver = IndependentDocumentRouter(commandLinePath: nil, receiver: true);_ = receiver.startup()
if case .launch = receiver.receive(b) { launches += 1 }
check(launches == 1)
print("PASS \(count) actual router assertions; old 500-hop chain; single-transport receiver terminates launch chain")
