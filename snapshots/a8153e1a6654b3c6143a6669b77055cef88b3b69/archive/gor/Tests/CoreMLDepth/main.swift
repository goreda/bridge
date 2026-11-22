import Foundation

// 195h A driver: the REAL production files (CoreMLDepthRunner.swift, ModelDepthEMA.swift, ThreeDExperimentOptions.swift,
// PrepareSupport.swift) - no shadow copies, compiled and run for real.
func chk(_ name: String, _ ok: Bool) { print("\(name) \(ok)") }

// toggle -> request identity (B's prepareComponent, extended): tokens and the worker's REAL parse-back
chk("default identity empty", ThreeDExperimentOptions().prepareComponent == "")
chk("dav2 identity", ThreeDExperimentOptions(dav2Depth: true).prepareComponent == "dav2")
chk("dav2+tempema identity", ThreeDExperimentOptions(dav2Depth: true, dav2TemporalEMA: true).prepareComponent == "dav2.tempema")
chk("full identity sorted", ThreeDExperimentOptions(depthRangeEMA: true, dav2Depth: true, dav2TemporalEMA: true).prepareComponent == "dav2.ema.tempema")
chk("worker parse roundtrips the identity", ThreeDExperimentOptions(experiments: "dav2.ema.tempema") == ThreeDExperimentOptions(depthRangeEMA: true, dav2Depth: true, dav2TemporalEMA: true))
chk("worker parse of legacy empty string is all-off", ThreeDExperimentOptions(experiments: "") == ThreeDExperimentOptions())
chk("render key component nil when all off", ThreeDExperimentOptions().renderKeyComponent == nil)
chk("render key carries the model tokens", ThreeDExperimentOptions(dav2Depth: true, dav2TemporalEMA: true).renderKeyComponent == "exp-dav2.tempema")

// container guard (real PrepareSupport.optionsMatch over real marker files)
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gor-195hA-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.removeItem(at: dir); try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let dzc = dir.appendingPathComponent("depth_shot_00000.dzc")
try! "x".write(to: dzc, atomically: true, encoding: .utf8)
let marker = dzc.appendingPathExtension("options.json")
chk("absent marker matches only the all-off identity", PrepareSupport.optionsMatch(dzc: dzc, options: ThreeDExperimentOptions()) && !PrepareSupport.optionsMatch(dzc: dzc, options: ThreeDExperimentOptions(dav2Depth: true)))
_ = PrepareSupport.writeJSON(["depth_range_ema": false, "depth_model": "dav2_small_coreml", "dav2_temporal_ema": false], to: marker)
chk("dav2 marker matches dav2 request", PrepareSupport.optionsMatch(dzc: dzc, options: ThreeDExperimentOptions(dav2Depth: true)))
chk("dav2 marker rejects default request", !PrepareSupport.optionsMatch(dzc: dzc, options: ThreeDExperimentOptions()))
chk("dav2 marker rejects dav2+tempema request", !PrepareSupport.optionsMatch(dzc: dzc, options: ThreeDExperimentOptions(dav2Depth: true, dav2TemporalEMA: true)))
_ = PrepareSupport.writeJSON(["depth_range_ema": false, "depth_model": "luma_y_prior", "dav2_temporal_ema": false], to: marker)
chk("default marker matches default request and rejects dav2", PrepareSupport.optionsMatch(dzc: dzc, options: ThreeDExperimentOptions()) && !PrepareSupport.optionsMatch(dzc: dzc, options: ThreeDExperimentOptions(dav2Depth: true)))
chk("container action: fresh / resume / rebuild", PrepareSupport.containerAction(dzc: dir.appendingPathComponent("nope.dzc"), options: ThreeDExperimentOptions()) == .fresh && PrepareSupport.containerAction(dzc: dzc, options: ThreeDExperimentOptions()) == .resume && PrepareSupport.containerAction(dzc: dzc, options: ThreeDExperimentOptions(dav2Depth: true)) == .rebuild)
try? FileManager.default.removeItem(at: dir)

// item 3: EMA semantics - first frame passes through, blend applies after, reset (shot boundary) passes through again
let ema = ModelDepthEMA(alpha: 0.25)
let f1: [Float] = [4, 4, 4, 4], f2: [Float] = [0, 0, 8, 8]
chk("ema first frame passthrough", ema.apply(f1) == f1)
chk("ema blend", ema.apply(f2) == [3, 3, 5, 5])   // 0.25*[0,0,8,8] + 0.75*[4,4,4,4]
let saved = ema.stateBundles
ema.reset()
chk("ema reset passthrough", ema.apply(f2) == f2)
ema.restore(bundles: saved)
chk("ema checkpoint state resumes exactly", ema.apply(f2) == [2.25, 2.25, 5.75, 5.75])   // 0.25*[0,0,8,8] + 0.75*[3,3,5,5]
chk("ema default off", ModelDepthEMA.enabled == false)

// resize + disparity conversion + half decode
let up = DepthMapResize.bilinear([0, 10, 20, 30], w: 2, h: 2, outW: 4, outH: 4)
chk("bilinear corners replicate the edge", up[0] == 0 && up[3] == 10 && up[12] == 20 && up[15] == 30)
chk("bilinear interior blends", abs(up[5] - 7.5) < 1e-6 && abs(up[6] - 12.5) < 1e-6)
chk("bilinear count", up.count == 16)
chk("disparity to depth", DepthMapResize.disparityToDepth([2, 0]) == [0.5, 1e6])
chk("half 0x0000 -> 0", HalfFloat.toFloat(0x0000) == 0)
chk("half 0x3C00 -> 1", HalfFloat.toFloat(0x3C00) == 1)
chk("half 0xC000 -> -2", HalfFloat.toFloat(0xC000) == -2)
chk("half 0x7C00 -> +inf", HalfFloat.toFloat(0x7C00) == Float.infinity)

// model selection: default and the single switch
chk("default model luma_y_prior", DepthModelID.selected() == .luma_y_prior)
DepthModelID.select(.dav2_small_coreml)
chk("selection switches", DepthModelID.selected() == .dav2_small_coreml)
DepthModelID.select(.luma_y_prior)
chk("selection switches back", DepthModelID.selected() == .luma_y_prior)
