import Foundation
var lines: [String] = []
let lk = NSLock()
ThreeDStageLog.sink = { lk.lock(); lines.append($0); lk.unlock() }
ThreeDStageLog.beat = 0.2
ThreeDStageLog.time("off") { }           // disabled: silent
ThreeDStageLog.enabled = true; ThreeDStageLog.start()
ThreeDStageLog.progress("depth-windows", done: 0, total: 2)
ThreeDStageLog.time("outer") { ThreeDStageLog.time("inner slow") { Thread.sleep(forTimeInterval: 0.7) } }
ThreeDStageLog.done("prepare cuts", ms: 12)
ThreeDStageLog.stop()
lk.lock(); for l in lines { print(l) }; lk.unlock()

let fast: (value: Int?, timedOut: Bool) = BoundedLoad.attempt(seconds: 0.2) { 42 }
let started = Date()
let stuck: (value: Int?, timedOut: Bool) = BoundedLoad.attempt(seconds: 0.05) { Thread.sleep(forTimeInterval: 0.5); return 99 }
let fallback: (value: Int?, timedOut: Bool) = BoundedLoad.attempt(seconds: 0.1) { 7 }
print("bounded \(fast.value == 42 && !fast.timedOut) \(stuck.value == nil && stuck.timedOut) \(fallback.value == 7) \(Date().timeIntervalSince(started) < 0.3)")
let box = BoundedLoadResult<Int>(); _ = box.finish(); box.publish(99); print("late_discarded \(box.finish() == nil)")

precondition(ThreeDStageLog.progressLine("cuts", done: 2, total: 48, t: 1).contains("done=2 total=48"))

precondition(lines.contains { $0.contains("progress stage=depth-windows done=0 total=2") })
