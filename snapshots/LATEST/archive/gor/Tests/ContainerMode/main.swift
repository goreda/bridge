import Foundation

/// 195h r3 driver (Delivery: "a test that drives mismatched-mode existing container through the real functions"): runs the REAL
/// ShotPrepare.run / PrepareSupport.containerAction / DZCWriter resume path against fixture containers. Pure Foundation, Linux swiftc.
class BreathFake: ShotPrepareBackend {
    var window = VDAWindowState(tokens: [2, 1], dims: [3, 2])
    func vdaStep(frame k: Int) -> [Float]? {
        let W = VDAStream.exportW, H = VDAStream.exportH
        let breathe = 1.0 + 0.15 * sin(Double(k) * 0.5)          // the depth range breathes frame to frame (the EMA must change the bytes)
        var out = [Float](); out.reserveCapacity(W * H)
        for y in 0..<H { for x in 0..<W {
            let u = Double(x) / Double(W), v = Double(y) / Double(H)
            out.append(Float((2.0 + 4.0 * (u * 0.7 + v * 0.3)) * breathe))
        } }
        let b: VDAWindowState.Bundle = (0..<2).map { i in [Float](repeating: Float(k), count: [6, 2][i]) }
        if window.isFirst { window.start(b) } else { window.advance(b) }
        return out
    }
    func mogeKeyframe(frame k: Int) -> MoGeKeyframe? {
        let mw = 37, mh = 21, breathe = 1.0 + 0.15 * sin(Double(k) * 0.5)
        var d = [Float]()
        for y in 0..<mh { for x in 0..<mw { d.append(Float((2.0 + 4.0 * (Double(x) / Double(mw) * 0.7 + Double(y) / Double(mh) * 0.3)) * breathe)) } }
        return MoGeKeyframe(hfovDeg: 60, depth: d, validFraction: 1, usedFP32: false, width: mw, height: mh)
    }
}

let passthrough: DZCWriter.Codec = ({ $0 }, { d, _ in d })      // Linux has no Compression; identity keeps the container layout exact
func hash(_ u: URL) -> String { var h = SHA256Pure.Hasher(); h.update([UInt8](try! Data(contentsOf: u))); return h.hex() }

let dir = URL(fileURLWithPath: CommandLine.arguments[1]), fm = FileManager.default
try? fm.removeItem(at: dir); try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
let n = 30
let emaOn = ThreeDExperimentOptions(depthRangeEMA: true), off = ThreeDExperimentOptions()

// 1: containerAction on fixtures, through the real function
let fx = dir.appendingPathComponent("fx"); try! fm.createDirectory(at: fx, withIntermediateDirectories: true)
let fxdzc = fx.appendingPathComponent("c.dzc")
print("action fresh \(PrepareSupport.containerAction(dzc: fxdzc, options: off).rawValue)")
try! Data("x".utf8).write(to: fxdzc)
print("action no-marker-ema-request \(PrepareSupport.containerAction(dzc: fxdzc, options: emaOn).rawValue)")   // absent marker = pre-195h depth (all off)
print("action no-marker-off-request \(PrepareSupport.containerAction(dzc: fxdzc, options: off).rawValue)")
_ = PrepareSupport.writeJSON(["depth_range_ema": true], to: fxdzc.appendingPathExtension("options.json"))
print("action match \(PrepareSupport.containerAction(dzc: fxdzc, options: emaOn).rawValue)")
print("action mismatch \(PrepareSupport.containerAction(dzc: fxdzc, options: off).rawValue)")

// 1b (Delivery block 2): prepare identity is B alone. E/G/hole are render-only: a legacy container (no marker) or an ema-off marker
// MATCHES when only render switches are on; only an EMA-mode difference mismatches.
let legacyDzc = fx.appendingPathComponent("legacy.dzc"); try! Data("x".utf8).write(to: legacyDzc)
print("legacy no-marker render-only-on match \(PrepareSupport.optionsMatch(dzc: legacyDzc, options: ThreeDExperimentOptions(floatingWindow: true, depthOfField: true, holeFillGradient: true)))")
print("legacy no-marker render-only-on action \(PrepareSupport.containerAction(dzc: legacyDzc, options: ThreeDExperimentOptions(floatingWindow: true)).rawValue)")
print("legacy no-marker ema-on mismatch \(!PrepareSupport.optionsMatch(dzc: legacyDzc, options: emaOn))")
_ = PrepareSupport.writeJSON(["depth_range_ema": false], to: legacyDzc.appendingPathExtension("options.json"))
print("marker-off render-only-on match \(PrepareSupport.optionsMatch(dzc: legacyDzc, options: ThreeDExperimentOptions(depthOfField: true)))")

// 2: full prepare runs through the real ShotPrepare.runResumable
func job(_ sub: String, _ ema: Bool) -> ShotPrepareJob {
    var j = ShotPrepareJob(shot: 0, startFrame: 0, frames: n, fps: 24, dzc: dir.appendingPathComponent(sub).appendingPathComponent("depth_shot_00000.dzc"),
                           spool: dir.appendingPathComponent(sub).appendingPathComponent("s.spool"), codec: passthrough,
                           checkpointURL: dir.appendingPathComponent(sub).appendingPathComponent("s.ck"))
    j.experiments = ThreeDExperimentOptions(depthRangeEMA: ema)
    return j
}
func run(_ j: ShotPrepareJob) -> Bool {
    try! fm.createDirectory(at: j.dzc.deletingLastPathComponent(), withIntermediateDirectories: true)
    if case .done = ShotPrepare.runResumable(job: j, backend: BreathFake()) { return true }
    return false
}

let jA = job("a", true); guard run(jA) else { print("run A failed"); exit(1) }
let hA = hash(jA.dzc)
let mA = PrepareSupport.readJSON(jA.dzc.appendingPathExtension("options.json"))
print("A marker ema \(mA?["depth_range_ema"] as? Bool == true)")
let sA = PrepareSupport.readJSON(jA.dzc.appendingPathExtension("ema.json"))
print("A ema state frames \(sA?["frames"] as? Int ?? -1) primed \(sA?["primed"] as? Bool ?? false)")

let jB = job("b", false); guard run(jB) else { print("run B failed"); exit(1) }
let hB = hash(jB.dzc)
print("ema changes output \(hA != hB)")
print("B has no ema state \(PrepareSupport.readJSON(jB.dzc.appendingPathExtension("ema.json")) == nil)")

let jA2 = job("a", true); guard run(jA2) else { print("run A2 failed"); exit(1) }
print("resume same mode bytes unchanged \(hash(jA2.dzc) == hA)")

let jA3 = job("a", false); guard run(jA3) else { print("run A3 failed"); exit(1) }
print("mismatch rebuild equals flag-off fresh \(hash(jA3.dzc) == hB)")
let mA3 = PrepareSupport.readJSON(jA3.dzc.appendingPathExtension("options.json"))
print("rebuild marker ema \(mA3?["depth_range_ema"] as? Bool ?? true)")
print("rebuild ema state removed \(PrepareSupport.readJSON(jA3.dzc.appendingPathExtension("ema.json")) == nil)")

// 2b (Delivery 7): an interrupted phase 2 whose persisted EMA state is lost resumes through the EXACT prefix replay and lands on
// the uninterrupted bytes. Boundary calls: 1 before the shot + (n-1) frame boundaries in phase 1, then one per phase-2 append.
let jC = job("c", true)
try! fm.createDirectory(at: jC.dzc.deletingLastPathComponent(), withIntermediateDirectories: true)
var hk = ShotPrepareHooks(); var boundaryCalls = 0
hk.boundary = { cp in boundaryCalls += 1; if boundaryCalls > n + 11 { return false }; cp(); return true }   // phase 1 makes n boundary calls; cancelling call n+12 lands right after the 12th phase-2 append
if case .cancelled = ShotPrepare.runResumable(job: jC, backend: BreathFake(), hooks: hk) {} else { print("interrupt setup failed"); exit(1) }
print("interrupted at 12 appended \(DZC.scanValid([UInt8](try! Data(contentsOf: jC.dzc)), decompress: passthrough.decompress)?.frames == 12)")
try! fm.removeItem(at: jC.dzc.appendingPathExtension("ema.json"))   // the lost-state case: no valid file -> replay path
let jC2 = job("c", true); guard run(jC2) else { print("run C2 failed"); exit(1) }
print("lost-state resume replays to the exact uninterrupted bytes \(hash(jC2.dzc) == hA)")

// 2c (Delivery A-3): an interrupted run whose mode then changes NEVER resumes through the old mode's spool/checkpoint. The fence in
// runResumable wipes container+marker+ema state+spool+checkpoint BEFORE the checkpoint file is decoded, so the mismatched resume starts
// at frame 0 and lands on the fresh-mode bytes (hA), not on old-mode-prefix bytes.
let jD = job("d", false); try! fm.createDirectory(at: jD.dzc.deletingLastPathComponent(), withIntermediateDirectories: true)
var hkD = ShotPrepareHooks(); var bc = 0
hkD.boundary = { cp in bc += 1; if bc > n + 11 { return false }; cp(); return true }
if case .cancelled = ShotPrepare.runResumable(job: jD, backend: BreathFake(), hooks: hkD) {} else { print("fence setup failed"); exit(1) }
print("fence setup left a checkpoint and spool \(fm.fileExists(atPath: jD.checkpointURL!.path) && fm.fileExists(atPath: jD.spool.path))")
let jD2 = job("d", true)   // same paths, OTHER mode
guard run(jD2) else { print("fence resume failed"); exit(1) }
print("mismatched resume lands on the fresh-mode bytes (old spool/checkpoint never read) \(hash(jD2.dzc) == hA)")
let mD2 = PrepareSupport.readJSON(jD2.dzc.appendingPathExtension("options.json"))
let fenceEMA = mD2?["depth_range_ema"] as? Bool ?? false
print("fence resume marker is the new mode \(fenceEMA)")

// 2d (Delivery A-4, the exact reproduced repro): interrupt an old-mode job BEFORE the DZC exists, switch the request to DAV2,
// rerun the REAL runResumable: the old mode's checkpoint/spool is never reused or relabelled (first backend frame = 0, not 11),
// because the identity marker written before phase 1 lets the no-container fence see the mismatch.
final class RecordingFake: BreathFake { var frames: [Int] = []; override func vdaStep(frame k: Int) -> [Float]? { frames.append(k); return super.vdaStep(frame: k) } }
let jE = job("e", false)   // old mode: all off (luma)
try! fm.createDirectory(at: jE.dzc.deletingLastPathComponent(), withIntermediateDirectories: true)
var hkE = ShotPrepareHooks(); var bcE = 0
hkE.boundary = { cp in bcE += 1; if bcE > 12 { return false }; cp(); return true }   // cancel at the 13th boundary: still phase 1, 11 frames spooled, checkpoint nextFrame=11
if case .cancelled = ShotPrepare.runResumable(job: jE, backend: BreathFake(), hooks: hkE) {} else { print("2d setup failed"); exit(1) }
print("2d setup: interrupted in phase 1 (no container, checkpoint and spool left) \(!fm.fileExists(atPath: jE.dzc.path) && fm.fileExists(atPath: jE.checkpointURL!.path) && fm.fileExists(atPath: jE.spool.path))")
print("2d setup: the pre-phase-1 identity marker says the old model \(PrepareSupport.readJSON(PrepareSupport.spoolIdentityURL(spool: jE.spool))?["depth_model"] as? String == "luma_y_prior")")
var jE2 = job("e", false); jE2.experiments = ThreeDExperimentOptions(dav2Depth: true)   // same paths, DAV2 request
let rec = RecordingFake()
if case .done = ShotPrepare.runResumable(job: jE2, backend: rec) {} else { print("2d resume failed"); exit(1) }
print("DAV2 resume of an interrupted luma job restarts at frame 0 (Delivery repro read 11) \(rec.frames.first == 0)")
print("2d resume relabels the identity marker \(PrepareSupport.readJSON(PrepareSupport.spoolIdentityURL(spool: jE2.spool))?["depth_model"] as? String == "dav2_small_coreml")")

// 2e: a PRE-195h spool/checkpoint with NO identity marker under the all-off default still resumes (legacy behavior preserved).
let jF = job("f", false)
try! fm.createDirectory(at: jF.dzc.deletingLastPathComponent(), withIntermediateDirectories: true)
var hkF = ShotPrepareHooks(); var bcF = 0
hkF.boundary = { cp in bcF += 1; if bcF > 12 { return false }; cp(); return true }
if case .cancelled = ShotPrepare.runResumable(job: jF, backend: BreathFake(), hooks: hkF) {} else { print("2e setup failed"); exit(1) }
try! fm.removeItem(at: PrepareSupport.spoolIdentityURL(spool: jF.spool))   // simulate pre-195h work: no marker
let recF = RecordingFake()
if case .done = ShotPrepare.runResumable(job: job("f", false), backend: recF) {} else { print("2e resume failed"); exit(1) }
print("legacy markerless spool resumes at frame 11 \(recF.frames.first == 11)")

// 3 (Delivery block 1 + 4): launcher lifecycle through the real ThreeDPrepareLauncher. The nudge carries mode identity and never stops
// a current-mode job (the coordinator ticks every 250 ms while the rebuild runs); a stopped job's late completion is generation-guarded
// and can neither clear nor fail the new job. The launcher hops completions to the main queue, so this part runs on a background
// thread while the main thread dispatches (Linux swiftc has no runloop integration for DispatchQueue.main).
// 4 (Delivery process boundary): the prepare-mode identity survives the worker boundary through the REAL PrepareWorker.Job Codable.
let job = PrepareWorkerJob(film: "/tmp/f.mp4", fps: 24, frames: 10, start: 0, quality: "auto", kit: "/k", cache: "/c", models: nil, experiments: "ema")
let jobData = try! JSONEncoder().encode(job)
let jobBack = try! JSONDecoder().decode(PrepareWorkerJob.self, from: jobData)
print("worker job roundtrip keeps the mode \(jobBack.experiments == "ema" && jobBack.request.experiments == "ema")")
let legacyJob = "{\"film\":\"/tmp/f.mp4\",\"fps\":24,\"frames\":10,\"start\":0,\"quality\":\"auto\",\"kit\":\"/k\",\"cache\":\"/c\",\"models\":null}"
let oldJob = try! JSONDecoder().decode(PrepareWorkerJob.self, from: legacyJob.data(using: .utf8)!)
print("legacy job file decodes to the default mode \(oldJob.experiments == "" && oldJob.request.experiments == "")")

final class FakeSpawn { var starts = 0, stops = 0; var lastExperiments = ""; var completions: [(Bool) -> Void] = [] }
let fake = FakeSpawn(), filmURL = URL(fileURLWithPath: "/tmp/cm-film.mp4")
let launcher = ThreeDPrepareLauncher(spawn: {
    return { req, done in
        fake.starts += 1; fake.lastExperiments = req.experiments; fake.completions.append(done)
        return ThreeDPrepareLauncher.Handle(stop: { fake.stops += 1 })
    }
}, report: { _ in })
launcher.settleDelay=0 // legacy lifecycle fixture; dedicated churn test measures production debounce
fflush(stdout)
DispatchQueue.global().async {
    func drainMain() { let s = DispatchSemaphore(value: 0); DispatchQueue.main.async { s.signal() }; _ = s.wait(timeout: .now() + 10) }
    let info = (fps: 24.0, frames: 100)
    launcher.update(mode: "sbs", film: filmURL, playhead: 0, info: info, quality: "auto", experiments: "ema", preflightReason: nil)
    print("old-mode job started \(fake.starts == 1 && fake.lastExperiments == "ema")")
    launcher.noteModeMismatch(current: "ema")             // same mode: must NOT stop
    print("same-mode nudge keeps the job \(fake.stops == 0)")
    launcher.noteModeMismatch(current: "")                // mode off: the ema job IS old-mode now
    print("old-mode nudge stops the job \(fake.stops == 1)")
    launcher.update(mode: "sbs", film: filmURL, playhead: 0, info: info, quality: "auto", experiments: "", preflightReason: nil)
    print("current-mode rebuild started \(fake.starts == 2 && fake.lastExperiments == "")")
    launcher.noteModeMismatch(current: ""); launcher.noteModeMismatch(current: "")   // the 250 ms ticks while the rebuild runs
    print("repeated nudges never stop the current-mode rebuild \(fake.stops == 1)")
    fake.completions[0](false)                            // the cancelled old job's late completion: generation-guarded, must be ignored
    drainMain()
    fake.completions[1](true)                             // the rebuild's own completion
    drainMain()
    launcher.update(mode: "sbs", film: filmURL, playhead: 0, info: info, quality: "auto", experiments: "", preflightReason: nil)
    print("stale completion neither cleared nor failed the new job \(fake.starts == 3)")
    fflush(stdout); exit(0)
}
dispatchMain()
