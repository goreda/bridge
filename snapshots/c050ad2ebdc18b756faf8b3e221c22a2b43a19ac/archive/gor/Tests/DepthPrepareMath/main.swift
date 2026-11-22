import Foundation
final class GuardFake: ShotPrepareBackend {       // s35: ShotFake plus a luma stream (flat flickering sky, panning ground, static overlay block) and a MoGe keyframe with +inf sky rows
    let inner = ShotFake(); var last = 0
    var window: VDAWindowState { get { inner.window } set { inner.window = newValue } }
    func vdaStep(frame k: Int) -> [Float]? { last = k; return inner.vdaStep(frame: k) }
    func mogeKeyframe(frame k: Int) -> MoGeKeyframe? {
        guard var kf = inner.mogeKeyframe(frame: k) else { return nil }
        for y in 0..<8 { for x in 0..<kf.width { kf.depth[y * kf.width + x] = .infinity } }
        return kf
    }
    func guardLuma() -> [Float]? {
        let W = VDAStream.exportW, H = VDAStream.exportH; var o = [Float](repeating: 0, count: W * H)
        for y in 0..<H { for x in 0..<W {
            if y < Int(Double(H) * 0.4) { o[y * W + x] = 100 + Float(last % 2) * 6 }
            else { o[y * W + x] = Float(128 + 100 * sin(Double(x + 3 * last) * 0.7) * cos(Double(y) * 0.9)) }
            if x >= W - 40 && x < W - 10 && y >= H - 30 && y < H - 10 { o[y * W + x] = 250 }
        } }
        return o
    }
}
final class ShotFake: ShotPrepareBackend {
    var window = VDAWindowState(tokens: [2, 1], dims: [3, 2]); var calls = 0
    func z(_ k: Int, _ u: Double, _ v: Double) -> Double { 3 + 0.4 * u + 0.3 * v + 0.01 * Double(k) }
    func vdaStep(frame k: Int) -> [Float]? {
        let W = VDAStream.exportW, H = VDAStream.exportH
        var off: Float = 0
        if !window.isFirst { let c = window.buildCurCache()[0]; off = 1e-5 * (c.reduce(0, +) / Float(c.count)) }   // output depends on the window, so a lost window would change the bytes
        var out = [Float](); out.reserveCapacity(W * H)
        for y in 0..<H { for x in 0..<W { out.append(Float((z(k, (Double(x) + 0.5) / Double(W), (Double(y) + 0.5) / Double(H)) - 0.5) / 2.0) + off) } }
        let b: VDAWindowState.Bundle = (0..<2).map { i in [Float](repeating: Float(k), count: [6, 2][i]) }
        if window.isFirst { window.start(b) } else { window.advance(b) }
        return out
    }
    func mogeKeyframe(frame k: Int) -> MoGeKeyframe? {
        let mw = 37, mh = 21; var d = [Float]()
        for y in 0..<mh { for x in 0..<mw { d.append((x > 30 && y < 4) ? .infinity : Float(z(k, (Double(x) + 0.5) / Double(mw), (Double(y) + 0.5) / Double(mh)))) } }
        return MoGeKeyframe(hfovDeg: 60 + 0.1 * Double(k), depth: d, validFraction: 0.9, usedFP32: false, width: mw, height: mh)
    }
}

// Driver for depth_prepare_math_test.py: compiled together with Sources/gor/ThreeD.swift DepthPrepareMath.swift section (pure Foundation, so it runs on Linux too).
func floats(_ p: String) -> [Float] { let d = try! Data(contentsOf: URL(fileURLWithPath: p)); return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
let a = CommandLine.arguments
switch a[1] {
case "focal":   // focal H W points.f32 [mask.f32]
    let h = Int(a[2])!, w = Int(a[3])!, pts = floats(a[4])
    let mask: [Bool]? = a.count > 5 ? floats(a[5]).map { $0 > 0.5 } : nil
    let r = MoGeGeometry.recoverFocalShift(points: pts, mask: mask, height: h, width: w)
    print(r.focal, r.shift, MoGeGeometry.hfovDegrees(focal: r.focal, width: w, height: h))
case "align":   // align T N vda.f32 moge.f32  -> per-frame running scale shift, then skipped
    let t = Int(a[2])!, n = Int(a[3])!, v = floats(a[4]), m = floats(a[5]); let al = ShotAlignerSwift(ema: 0.9)
    for i in 0..<t {
        al.update(vda: Array(v[i * n..<(i + 1) * n]), moge: Array(m[i * n..<(i + 1) * n]))
        print(al.scale ?? .nan, al.shift ?? .nan, al.skipped)
    }
case "track":   // track T defS defB k:s:b ...  (s/b "nil" = no fit yet) -> per frame: scale shift (s30 eased application)
    let t = Int(a[2])!, ds = Double(a[3])!, db = Double(a[4])!
    let kf: [(k: Int, scale: Double?, shift: Double?)] = a[5...].map { let p = $0.split(separator: ":").map(String.init); return (Int(p[0])!, Double(p[1]).flatMap { $0.isNaN ? nil : $0 }, Double(p[2]).flatMap { $0.isNaN ? nil : $0 }) }
    let tr = AlignTrack(keyframes: kf, defaultScale: ds, defaultShift: db)
    precondition(AlignTrack(json: tr.json) == tr)
    for f in 0..<t { let q = tr.params(at: f, defaultScale: ds, defaultShift: db); print(q.scale, q.shift) }
case "budget":   // budget frames vdaMs mogeMs mogeN -> the rt_ notes
    let tel = PrepareTelemetry(); let fr = Int(a[2])!, v = Double(a[3])!, m = Double(a[4])!, mn = Int(a[5])!
    for _ in 0..<fr { tel.add("vda_step_total", ms: v) }; for i in 0..<mn { tel.add("moge_step_total", ms: i == 0 ? m * 2 : m) }
    tel.addRealtimeBudget(frames: fr); for n in tel.notes { print(n.key, n.value) }
case "rtlines":   // rtlines cfg ms... (7 means in rtOrder, "-" = omit the stage) -> the log lines PrepareTelemetry emits
    let tel = PrepareTelemetry(); tel.note("rt_config", a[2])
    for (i, n) in PrepareTelemetry.rtOrder.enumerated() where a[3 + i] != "-" { tel.rtStage(n, meanMs: Double(a[3 + i])!, n: 36, maxMs: Double(a[3 + i])! * 1.5) }
    tel.thermalSample(level: 0)
    for l in tel.lines(header: "rt test") { print(l) }
    let back = PrepareTelemetry.parse(tel.lines(header: "rt test")); precondition(back.rtstages.count == tel.rtStages.count)
case "quant":   // quant z.f32 -> w10 per value
    for z in floats(a[2]) { print(DepthQuant.w10(zMetres: z)) }
case "fov":    // fov start end fps frame:fov ...
    let e = FovTrackBuilder.entry(startFrame: Int(a[2])!, endFrame: Int(a[3])!, fps: Double(a[4])!, keyframes: a[5...].map { let p = $0.split(separator: ":"); return (Int(p[0])!, Double(p[1])!) })
    print(e.startPTS, e.endPTS, e.hfovDeg.map { String($0) } ?? "nil", e.confidence, e.keyframes.count)
    print(FovTrackBuilder.keyframeIndices(frames: Int(a[3])! - Int(a[2])! + 1).map(String.init).joined(separator: ","))
case "chw":    // chw: prints a few normalised values for a deterministic RGBA pattern
    var px = [UInt8](repeating: 0, count: 518 * 518 * 4)
    for i in 0..<(518 * 518) { px[i * 4] = UInt8(i % 256); px[i * 4 + 1] = UInt8((i / 7) % 256); px[i * 4 + 2] = UInt8((i / 13) % 256); px[i * 4 + 3] = 255 }
    let c = MoGeInput.chw(rgba: px); let n = 518 * 518
    for i in [0, 1, 777, 268323] { print(c[i], c[n + i], c[2 * n + i]) }
case "pick":   // pick srcW srcH -> shape from a fixed enumerated set
    let set: [MoGeInput.Shape] = [.init(w: 518, h: 294), .init(w: 518, h: 518), .init(w: 392, h: 518), .init(w: 518, h: 364)]
    let r = MoGeInput.pick(set, srcW: Int(a[2])!, srcH: Int(a[3])!)!
    print(r.w, r.h)
case "vdawin":   // frames shape-tokens... : each frame k's bundle is filled with value k; prints, per step, the T-axis frame ids of cache0 and the list size
    let n = Int(a[2])!; let tk = [2, 1], dm = [3, 2]
    func bundle(_ k: Int) -> VDAWindowState.Bundle { (0..<2).map { i in [Float](repeating: Float(k), count: tk[i] * dm[i]) } }
    var st = VDAWindowState(tokens: tk, dims: dm)
    for k in 0..<n {
        if st.isFirst { st.start(bundle(k)); print(k, "first") } else {
            let c = st.buildCurCache()[0]; let t = 31
            var ids: [String] = []; var same = true
            for f in 0..<t { ids.append(String(Int(c[f * 3]))); if c[(1 * t + f) * 3 + 2] != c[f * 3] { same = false } }
            print(k, ids.joined(separator: ","), same ? "tok1same" : "tok1diff")
            st.advance(bundle(k))
        }
    }
case "vdachw":   // r g b a ... one px 2x1 -> CHW
    print(VDAStream.chw(rgba: [UInt8](a[2...9].map { UInt8($0)! }), w: 2, h: 1).map { String($0) }.joined(separator: " "))
case "shotprep":   // dir n suspendFrames(comma list or -) : fake backends, identity codec; prints result line
    let dir = URL(fileURLWithPath: a[2]); let n = Int(a[3])!; let sus = a[4] == "-" ? [] : a[4].split(separator: ",").map { Int($0)! }
    let codec: DZCWriter.Codec = ({ $0 }, { c, _ in c })
    let job = ShotPrepareJob(shot: 3, startFrame: 100, frames: n, fps: 24, dzc: dir.appendingPathComponent("s.dzc"), spool: dir.appendingPathComponent("s.spool"), codec: codec)
    var backend = ShotFake(); var ck: ShotCheckpoint? = nil; var pending = sus; var suspends = 0
    while true {
        let next = pending.first
        var hk = ShotPrepareHooks(); hk.shouldSuspend = { k in k == next }; let out = ShotPrepare.run(job: job, backend: backend, checkpoint: ck, hooks: hk)
        switch out {
        case .suspended(let c):
            suspends += 1; pending.removeFirst()
            let rt = ShotCheckpoint.decode(c.encode())!; precondition(rt.encode() == c.encode(), "checkpoint roundtrip")
            ck = rt; backend = ShotFake()          // a fresh process: only the checkpoint carries the window
        case .cancelled: print("cancelled"); exit(1)
        case .failed(let m): print("failed", m); exit(1)
        case .done(let r):
            print("done suspends", suspends, "scale", r.alignScale ?? -1, "shift", r.alignShift ?? -1, "kf", r.keyframesUsed, "skipped", r.alignSkipped)
            print("fov", r.fov.hfovDeg ?? -1, r.fov.confidence, r.fov.keyframes.count, r.fov.startPTS, r.fov.endPTS)
            exit(0)
        }
    }
case "shotkill":   // dir n killFrame: boundary hook cancels at killFrame after running the checkpoint closure; then a fresh process resumes from the persisted file
    let dir = URL(fileURLWithPath: a[2]); let n = Int(a[3])!; let kill = Int(a[4])!
    let codec: DZCWriter.Codec = ({ $0 }, { c, _ in c })
    var job = ShotPrepareJob(shot: 3, startFrame: 100, frames: n, fps: 24, dzc: dir.appendingPathComponent("s.dzc"), spool: dir.appendingPathComponent("s.spool"), codec: codec)
    job.checkpointURL = dir.appendingPathComponent("s.ckpt")
    var boundaries = 0, laneCalls = 0, cpRuns = 0
    var hk = ShotPrepareHooks(); hk.lane = { laneCalls += 1; $0() }
    hk.boundary = { cp in boundaries += 1; if boundaries == kill { cp(); cpRuns += 1; return false }; return true }
    let b1 = ShotFake()
    let o1 = ShotPrepare.runResumable(job: job, backend: b1, hooks: hk)
    var cancelled = false; if case .cancelled = o1 { cancelled = true }
    print("first", cancelled, "boundaries", boundaries, "lane", laneCalls, "cp", cpRuns, "ckfile", FileManager.default.fileExists(atPath: job.checkpointURL!.path))
    var b2 = 0; var hk2 = ShotPrepareHooks(); hk2.boundary = { _ in b2 += 1; return true }
    let o2 = ShotPrepare.runResumable(job: job, backend: ShotFake(), hooks: hk2)
    if case .done(let r) = o2 { print("resumed done scale", r.alignScale ?? -1, "boundaries", b2, "ckfile", FileManager.default.fileExists(atPath: job.checkpointURL!.path)) } else { print("resumed not done") }
case "cuts":   // fps n t1 t2 ...
    let fps = Double(a[2])!, n = Int(a[3])!; let cf = ShotCuts.frames(fromTimes: a[4...].map { Double($0)! }, fps: fps)
    print(cf.map(String.init).joined(separator: ","), ShotCuts.shots(nFrames: n, cuts: cf).map { "\($0[0])-\($0[1])" }.joined(separator: ","))
case "scd":   // raw.yuv w h : yuv420p frames, luma only
    let w = Int(a[3])!, h = Int(a[4])!; let d = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: a[2]))); let fs = w * h * 3 / 2
    var sc = SceneScorer(); var k = 0
    while (k + 1) * fs <= d.count { let r = sc.score(luma: Array(d[(k * fs)..<(k * fs + w * h)])); print(String(format: "%.6f %.6f", r.mafd, r.score)); k += 1 }
    var i = 0; let det = ShotCuts.detect(next: { guard (i + 1) * fs <= d.count else { return nil }; defer { i += 1 }; return Array(d[(i * fs)..<(i * fs + w * h)]) })
    print("cuts", det.cuts.map(String.init).joined(separator: ","), det.nFrames)
case "ckey":   // path
    print(PrepareSupport.cacheKey(path: a[2]) ?? "nil")
case "sha":   // path : pure SHA-256 of a file
    var h = SHA256Pure.Hasher(); h.update([UInt8](try! Data(contentsOf: URL(fileURLWithPath: a[2])))); print(h.hex())
case "order":   // playhead shots(s-e,...) done(i,...|-)
    let sh = a[3].split(separator: ",").map { $0.split(separator: "-").map { Int($0)! } }; let dn = a[4] == "-" ? Set<Int>() : Set(a[4].split(separator: ",").map { Int($0)! })
    print(PrepareSupport.pendingOrder(shots: sh, done: dn, playheadFrame: a[2] == "-" ? nil : Int(a[2])!).map(String.init).joined(separator: ","))
case "fovfile":   // dir
    let d = URL(fileURLWithPath: a[2]); let e1 = FovTrackBuilder.entry(startFrame: 0, endFrame: 23, fps: 24, keyframes: [(0, 50), (12, 52)]); let e2 = FovTrackBuilder.entry(startFrame: 24, endFrame: 47, fps: 24, keyframes: [])
    precondition(PrepareSupport.writeCuts(entry: d, cuts: [24], shots: [[0, 23], [24, 47]])); precondition(PrepareSupport.mergeFov(entry: d, fps: 24, shot: 1, e2)); precondition(PrepareSupport.mergeFov(entry: d, fps: 24, shot: 0, e1))
    print(PrepareSupport.readCuts(entry: d)!)
case "kcc":   // kitdir modelsdir
    let kd = URL(fileURLWithPath: a[2]), md = URL(fileURLWithPath: a[3]); let sha = KitCompiledCache.manifestSha(kitDir: kd) ?? "nil"
    print(sha, KitCompiledCache.cacheDir(modelsDir: md, sha: sha).path, KitCompiledCache.compiledName(URL(fileURLWithPath: "/k/moge2_vits_518x294_fp16.mlpackage")), KitCompiledCache.stale(children: ["a", sha, ".x", "b"], keep: sha).joined(separator: ","))
case "tele":   // prints the log lines (with noise lines around) then the parse result
    let t = PrepareTelemetry(); t.add("decode", ms: 1.5); t.add("decode", ms: 2.5); t.add("vda_model", ms: 10); t.thermalSample(level: 0); t.thermalSample(level: 0); t.thermalSample(level: 2); t.thermalSample(level: 1)
    t.depthFrame([1, 2.5, .nan, .infinity, 0.25]); t.depthFrame([9, .nan]); t.note("moge_precision", "fp16_used=3 fp16_rejected=1 fp32_used=1"); t.note("compute_plan x", "plan ops ane=10 gpu=2"); t.error("shot 0 depth: bad\nthing \\ with = and spaces"); t.error("second")
    var lines = ["unrelated log line", "2026-11-09 NSLog something"] + t.lines(header: "3D self-test finished") + ["tail noise"]
    for l in lines { print(l) }
    let p = PrepareTelemetry.parse(lines)
    print("PARSED", p.header, p.stages["decode"]!.ms, p.stages["decode"]!.n, p.stages["decode"]!.max, p.thermal.map { $0.level }, p.peak, p.transitions, p.depth.min, p.depth.max, p.depth.nan, p.depth.inf, p.depth.count, p.notes["moge_precision"]!, p.notes["compute_plan x"]!, p.errors.count, p.ended)
    print("ERR0", p.errors[0].replacingOccurrences(of: "\n", with: "<NL>"))
case "stpure":
    print(ThreeDSelfTest.markerName(manifestSha: "abcdef0123456789abcdef", build: "r27 build/1.2"), ThreeDSelfTest.shouldRun(enabled: true, kitPresent: true, markerExists: false, filmPreparing: false), ThreeDSelfTest.shouldRun(enabled: true, kitPresent: true, markerExists: true, filmPreparing: false), ThreeDSelfTest.shouldRun(enabled: true, kitPresent: false, markerExists: false, filmPreparing: false), ThreeDSelfTest.shouldRun(enabled: true, kitPresent: true, markerExists: false, filmPreparing: true))
    let a = ThreeDSelfTest.pattern(frame: 3), b = ThreeDSelfTest.pattern(frame: 3), c = ThreeDSelfTest.pattern(frame: 4)
    var h = SHA256Pure.Hasher(); h.update(a); print(a.count, a == b, a != c, h.hex())
case "lbox":   // srcW srcH [outfile]: box, and the canvas for a constant-255 picture
    let sw = Int(a[2])!, sh = Int(a[3])!, b = VDAStream.letterbox(srcW: sw, srcH: sh)
    print(b.nw, b.nh, b.x0, b.y0)
    if a.count > 4 { let c = VDAStream.chwLetterboxed(rgba: [UInt8](repeating: 255, count: b.nw * b.nh * 4), box: b); try! c.withUnsafeBytes { Data($0) }.write(to: URL(fileURLWithPath: a[4]))
        let d = (0..<(VDAStream.exportW * VDAStream.exportH)).map { Float($0) }; let cd = VDAStream.cropDepth(d, box: b)
        print(cd.count, cd[0], cd[cd.count - 1]) }
case "gate":   // level,time pairs after the script name
    var g = ThermalDutyGate(); var res: [String] = []
    for p in a[2...] { let x = p.split(separator: ","); res.append(g.mayRun(level: ThermalLevel(rawValue: Int(x[0])!)!, now: Double(x[1])!) ? "run" : "hold") }
    print(res.joined(separator: " "))
case "dzc-quant":   // z.f32 h w out.u16
    let z = floats(a[2]); let q = DZC.quantise(z: z, h: Int(a[3])!, w: Int(a[4])!)
    try! Data(DZC.planeBytesLE(q.plane)).write(to: URL(fileURLWithPath: a[5])); print(q.width, q.height)
case "dzc-assemble":   // out shot fpsnum fpsden start dh dw n z.f32 blobs.bin lens.txt   (blobs = reference LZFSE payloads, in order)
    let dh = Int(a[7])!, dw = Int(a[8])!, n = Int(a[9])!, z = floats(a[10]); let blobs = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: a[11])))
    let lens = try! String(contentsOfFile: a[12]).split(separator: " ").map { Int($0)! }
    let q = DZC.quantise(z: Array(z[0..<(dh * dw)]), h: dh, w: dw)
    let meta = DZC.Meta(shot: UInt32(a[3])!, fpsNum: UInt32(a[4])!, fpsDen: UInt32(a[5])!, startFrame: UInt64(a[6])!, width: UInt32(q.width), height: UInt32(q.height),
                        depthWidth: UInt32(dw), depthHeight: UInt32(dh), nFrames: UInt32(n))
    var idx = 0, off = 0
    let codec: DZCWriter.Codec = ({ _ in let b = Array(blobs[off..<(off + lens[idx])]); off += lens[idx]; idx += 1; return b }, { c, _ in c })
    let w = DZCWriter(url: URL(fileURLWithPath: a[2]), meta: meta, codec: codec)!
    for i in 0..<n { precondition(w.append(zMetres: Array(z[(i * dh * dw)..<((i + 1) * dh * dw)]))) }
    print(w.finish())
case "dzc-selftest":   // identity codec: write 3 of 5 frames, cut a partial record, resume, finish, verify
    let url = URL(fileURLWithPath: a[2]); let dh = 3, dw = 5
    let meta = DZC.Meta(shot: 7, fpsNum: 24, fpsDen: 1, startFrame: 48, width: 6, height: 4, depthWidth: 5, depthHeight: 3, nFrames: 5)
    let codec: DZCWriter.Codec = ({ $0 }, { c, _ in c })
    func frame(_ i: Int) -> [Float] { (0..<(dh * dw)).map { Float($0 + 1 + i) * 0.5 } }
    var w = DZCWriter(url: url, meta: meta, codec: codec)!
    for i in 0..<3 { precondition(w.append(zMetres: frame(i))) }
    precondition(!w.finish())                                                  // incomplete: finish refuses
    var d = [UInt8](try! Data(contentsOf: url)); d.removeLast(5); try! Data(d).write(to: url)    // partial third record
    w = DZCWriter(url: url, meta: meta, resume: true, codec: codec)!
    print("resumed", w.framesWritten)
    for i in 2..<5 { precondition(w.append(zMetres: frame(i))) }
    print("finished", w.finish())
    let f = [UInt8](try! Data(contentsOf: url)); let s = DZC.scanValid(f, decompress: { c, _ in c })!
    print("frames", s.frames, "tail", Array(f.suffix(8)) == DZC.trailer, "trailerAt", f.count - 8 - 5 * 8 == s.end)
case "guardprep":   // guardprep dir n flags(wsc: weighted, sky, conv/overlay as 0/1 digits) : prints per-frame probes of the metres the container would get
    let dir = URL(fileURLWithPath: a[2]); let n = Int(a[3])!, fl = Array(a[4])
    DepthGuards.weightedFit = fl[0] == "1"; DepthGuards.skyClamp = fl[1] == "1"; DepthGuards.overlayFlatten = fl[2] == "1"
    let codec: DZCWriter.Codec = ({ $0 }, { c, _ in c })
    let job = ShotPrepareJob(shot: 3, startFrame: 100, frames: n, fps: 24, dzc: dir.appendingPathComponent("g.dzc"), spool: dir.appendingPathComponent("g.spool"), codec: codec)
    var hk = ShotPrepareHooks(); var frames: [[Float]] = []; hk.depthMetres = { frames.append($0) }
    guard case .done(let r) = ShotPrepare.run(job: job, backend: GuardFake(), hooks: hk) else { print("notdone"); exit(1) }
    let W = VDAStream.exportW, H = VDAStream.exportH
    print("scale", r.alignScale ?? -1, "shift", r.alignShift ?? -1)
    for (i, f) in frames.enumerated() { print("f", i, f[10 * W + 20], f[(H - 20) * W + W - 20], f[(H - 60) * W + 60], f[(H - 5) * W + 5]) }   // sky px, overlay px, ground px, ground corner
    let all = frames.flatMap { $0 }; print("sum", all.reduce(0.0) { $0 + Double($1.isFinite ? $1 : 0) })
default: exit(2)
}
