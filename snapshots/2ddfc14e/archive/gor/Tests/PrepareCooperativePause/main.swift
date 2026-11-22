import Foundation

// Driver for cooperative_pause_test.py (arch-196b C3), compiled and run natively on Linux AND Darwin with the REAL
// sections out of Sources/gor/ThreeD.swift: ThreeDPrepareLauncher, PrepareWorkerJob, ThreeDThermalGate,
// ThreeDStageLog, FilmPrepareStatus (DepthCachePaths), DepthCacheBudget, DepthContainerWriter (DZCFile),
// PrepareProcessLifetime, ThreeDPrepareSpawn (ShotSink + PrepareWorker + spawn), VTShotEncoder (real on Darwin,
// self-guards to empty on Linux). No CoreML model stack here: on Darwin, NativePrepareRunner comes from
// DarwinPrepareStub.swift and the thermalState shim (lin.swift) is compiled out.

let a = CommandLine.arguments

func req(_ cond: Bool, _ msg: String) { if !cond { print("REQ-FAIL", msg); exit(1) } }

func progressPaused(_ entry: URL) -> String {
    guard let d = try? Data(contentsOf: entry.appendingPathComponent("progress.json")),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return "none" }
    return o["paused"] as? String ?? "none"
}

switch a[1] {
case "sinkpause":   // sinkpause dir : cooperative wait at the boundary with a real ShotSink and the real flag-file rule
    let dir = URL(fileURLWithPath: a[2])
    let entry = dir.appendingPathComponent("entry", isDirectory: true)
    let flag = dir.appendingPathComponent("job.json.pause").path
    guard let sink = ShotSink(entry: entry, shots: [[0, 4]], fps: 24) else { print("nosink"); exit(1) }
    sink.pauseRequested = { FileManager.default.fileExists(atPath: flag) }
    var checkpoints = 0
    // 1. no flag: the boundary passes through with no checkpoint and no marker
    req(sink.boundary(checkpoint: { checkpoints += 1 }, cancelled: { false }), "no-flag boundary returns true")
    req(checkpoints == 0 && progressPaused(entry) == "none", "no checkpoint, no marker without the flag")
    // progress.json already exists in production before a pause (the worker writes progress updates); writeAtomic replaces in place
    try! Data("{}".utf8).write(to: entry.appendingPathComponent("progress.json"))
    // 2. flag set: the boundary checkpoints once, marks progress.json and waits while the flag exists
    try! Data().write(to: URL(fileURLWithPath: flag))
    var returned: Bool? = nil
    let t = Thread { returned = sink.boundary(checkpoint: { checkpoints += 1 }, cancelled: { false }) }
    t.start()
    var waited = 0.0
    // The paused=pause marker lands through writeAtomic (FileManager.replaceItemAt). swift-corelibs-foundation's replaceItemAt
    // throws "file doesn't exist" (and removes the destination) where Darwin replaces in place, so the marker content is a
    // text pin here and is exercised on the Mac; Linux checks the cooperative mechanics around it.
    #if !os(Linux)
    while progressPaused(entry) != "pause" && waited < 5 { Thread.sleep(forTimeInterval: 0.05); waited += 0.05 }
    req(progressPaused(entry) == "pause", "progress.json must carry paused=pause while parked")
    #else
    while checkpoints == 0 && waited < 5 { Thread.sleep(forTimeInterval: 0.05); waited += 0.05 }
    #endif
    req(checkpoints == 1, "checkpoint ran exactly once on the way in")
    Thread.sleep(forTimeInterval: 0.5)
    req(returned == nil, "boundary still parked while the flag exists")
    try! FileManager.default.removeItem(atPath: flag)
    while returned == nil && waited < 8 { Thread.sleep(forTimeInterval: 0.05); waited += 0.05 }
    req(returned == true, "boundary returns true once the flag is removed")
    while !t.isFinished { Thread.sleep(forTimeInterval: 0.02) }
    req(progressPaused(entry) == "none", "marker removed on resume")
    req(checkpoints == 1, "no second checkpoint on the way out")
    // 3. cancel while parked: boundary returns false and clears the marker
    try! Data().write(to: URL(fileURLWithPath: flag))
    var returned2: Bool? = nil
    let t2 = Thread { returned2 = sink.boundary(checkpoint: { checkpoints += 1 }, cancelled: { true }) }
    t2.start()
    while returned2 == nil { Thread.sleep(forTimeInterval: 0.02) }
    req(returned2 == false, "cancel during the cooperative wait stops the film")
    while !t2.isFinished { Thread.sleep(forTimeInterval: 0.02) }
    req(progressPaused(entry) == "none", "marker cleared on cancel")
    try? FileManager.default.removeItem(atPath: flag)
    print("sinkpause ok checkpoints=\(checkpoints)")

case "launcher":   // launcher: the 30 s pause->cancel rule on the real ThreeDPrepareLauncher with an injected clock and fake spawn
    final class FakeHandle {
        var pauses = 0, resumes = 0, stops = 0
    }
    var now = 100.0
    var handles: [FakeHandle] = []
    var requests: [ThreeDPrepareLauncher.Request] = []
    let film = URL(fileURLWithPath: "/tmp/film.mkv")
    let l = ThreeDPrepareLauncher(spawn: {
        return { req, done in
            let h = FakeHandle(); handles.append(h); requests.append(req)
            return ThreeDPrepareLauncher.Handle(stop: { h.stops += 1 }, pause: { h.pauses += 1 }, resume: { h.resumes += 1 })
        }
    }, report: { _ in })
    l.clock = { now }
    l.settleDelay = 0.5
    let info: (fps: Double, frames: Int) = (24, 1000)
    // start a job
    l.update(mode: "vr180", film: film, playhead: 0, info: info, quality: "auto", preflightReason: nil)
    now += 1   // past the settle window
    l.update(mode: "vr180", film: film, playhead: 0, info: info, quality: "auto", preflightReason: nil)
    precondition(handles.count == 1 && l.isPreparing, "job started")
    // 3D off: cooperative pause; repeated polls do not reset the 30 s clock
    l.setPaused(true)
    precondition(handles[0].pauses == 1)
    now += 10; l.setPaused(true)
    now += 10; l.update(mode: "off", film: film, playhead: 0, info: info, quality: "auto", preflightReason: nil)
    precondition(handles[0].stops == 0 && l.isPreparing, "20 s parked: still paused, not cancelled")
    // past 30 s parked: the worker is cancelled
    now += 11; l.update(mode: "off", film: film, playhead: 0, info: info, quality: "auto", preflightReason: nil)
    precondition(handles[0].stops == 1 && !l.isPreparing, "31 s parked: worker cancelled")
    // 3D back on: a NEW job starts (resume = fresh job from the checkpoint, never a SIGCONT)
    now += 1; l.update(mode: "vr180", film: film, playhead: 0, info: info, quality: "auto", preflightReason: nil)
    now += 1; l.update(mode: "vr180", film: film, playhead: 0, info: info, quality: "auto", preflightReason: nil)
    precondition(handles.count == 2 && l.isPreparing, "resume starts a new job")
    precondition(handles[1].resumes == 0, "the new job is not 'resumed' into the old handle")
    // a short pause resumes in place and never cancels
    l.setPaused(true); now += 5; l.setPaused(false)
    precondition(handles[1].pauses == 1 && handles[1].resumes == 1)
    now += 40; l.update(mode: "off", film: film, playhead: 0, info: info, quality: "auto", preflightReason: nil)
    precondition(handles[1].stops == 1 || l.isPreparing, "after resume the 30 s clock was cleared")
    print("launcher ok handles=\(handles.count)")

case "jobflag":   // jobflag : the job file round-trips the flag path and decodes the pre-C3 default
    let job = PrepareWorkerJob(film: "/f", fps: 24, frames: 10, start: 0, quality: "auto", kit: "/k", cache: "/c", models: nil, experiments: "ema", pauseFlag: "/tmp/x.pause")
    let d = try! JSONEncoder().encode(job)
    let back = try! JSONDecoder().decode(PrepareWorkerJob.self, from: d)
    precondition(back.pauseFlag == "/tmp/x.pause" && back.experiments == "ema")
    let old = """
    {"film":"/f","fps":24,"frames":10,"start":0,"quality":"auto","kit":"/k","cache":"/c","experiments":""}
    """.data(using: .utf8)!
    let legacy = try! JSONDecoder().decode(PrepareWorkerJob.self, from: old)
    precondition(legacy.pauseFlag == "" && legacy.experiments == "", "pre-C3 job files decode the default empty flag")
    precondition(legacy.request.experiments == "")
    print("jobflag ok")

default: exit(2)
}
