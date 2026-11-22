import Foundation
import GorAVPlaybackCore
import GorAVNativeProbeKit

// Witness for the R8 crop stage: geometry resolution, bounds, minimum-size
// refusal, detector seam (stub + scripted), confidence threshold, session
// fencing.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

func frame(_ session: UInt64, _ w: Int, _ h: Int) -> NativeFrame {
    NativeFrame(session: session, handle: 1, pts: 0, duration: 33_333,
                width: w, height: h, pixelFormatName: "yuv420p", isKeyFrame: true)
}

// T1: full frame on 1920x1080
switch CropStage.resolve(.full, frameWidth: 1920, frameHeight: 1080) {
case .success(let g):
    check("T1-full-geom", g == CropGeometry(x: 0, y: 0, width: 1920, height: 1080, aspect: Double(1920)/1080))
case .failure(let e):
    check("T1-full-geom \(e)", false)
}

// T2: centered half crop
let half = NormalizedRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5)!
switch CropStage.resolve(half, frameWidth: 1920, frameHeight: 1080) {
case .success(let g):
    check("T2-half-geom", g.x == 480 && g.y == 270 && g.width == 960 && g.height == 540)
    check("T2-half-aspect", abs(g.aspect - 16.0/9.0) < 0.01)
case .failure: check("T2-half-geom", false)
}

// T3: small valid crops are retained
let tiny = NormalizedRect(x: 0, y: 0, w: 0.005, h: 0.01)!
check("T3-small-valid", CropStage.resolve(tiny, frameWidth: 1920, frameHeight: 1080) != .failure(.belowMinimum))

// T4: tiny frame refused
check("T4-small-frame", CropStage.resolve(.full, frameWidth: 0, frameHeight: 8) == .failure(.frameTooSmall))

// T5: detector stub never suggests; autoApply leaves crop at full
var c5 = CropController(session: 7, autoThreshold: 0.9)!
check("T5-stub-no-suggestion", c5.autoApply(frame: frame(7, 1920, 1080)) == .noSuggestion)
check("T5-still-full", c5.current == .full)

// T6: scripted detector above threshold applies
struct Scripted: CropDetecting {
    let s: CropSuggestion?
    func suggest(frame: NativeFrame) -> CropSuggestion? { s }
}
let sg = CropSuggestion(rect: half, confidence: 0.95)!
var c6 = CropController(session: 7, detector: Scripted(s: sg), autoThreshold: 0.9)!
if case .applied(let g) = c6.autoApply(frame: frame(7, 1920, 1080)) {
    check("T6-applied", g.width == 960 && c6.current == half)
} else { check("T6-applied", false) }

// T7: below threshold leaves crop untouched
let weak = CropSuggestion(rect: half, confidence: 0.5)!
var c7 = CropController(session: 7, detector: Scripted(s: weak), autoThreshold: 0.9)!
check("T7-below-threshold", c7.autoApply(frame: frame(7, 1920, 1080)) == .noSuggestion && c7.current == .full)

// T8: small suggestion stays valid
let badSug = CropSuggestion(rect: tiny, confidence: 0.99)!
var c8 = CropController(session: 7, detector: Scripted(s: badSug), autoThreshold: 0.9)!
check("T8-small-applied", c8.autoApply(frame: frame(7, 1920, 1080)) == .applied(CropGeometry(x: 0, y: 0, width: 10, height: 11, aspect: Double(10)/11)) && c8.current == tiny)

// T9: session fencing on both paths
var c9 = CropController(session: 7, autoThreshold: 0.9)!
check("T9-geometry-fenced", c9.geometry(frame: frame(8, 1920, 1080)) == nil)
check("T9-auto-fenced", c9.autoApply(frame: frame(8, 1920, 1080)) == .refusedStaleSession)

// T10: manual set/clear + geometry path
c9.set(half)
if let r = c9.geometry(frame: frame(7, 1920, 1080)), case .success(let g) = r {
    check("T10-manual", g.width == 960)
} else { check("T10-manual", false) }
c9.clear()
check("T10-clear", c9.current == .full)

// T11: invalid suggestion confidence cannot be constructed
check("T11-confidence-guard", CropSuggestion(rect: half, confidence: 0) == nil
      && CropSuggestion(rect: half, confidence: 1.5) == nil
      && CropSuggestion(rect: half, confidence: .nan) == nil)

check("T12-invalid-threshold-refused", CropController(session: 7, autoThreshold: .nan) == nil && CropController(session: 7, autoThreshold: -0.1) == nil)
if case .success(let g) = CropStage.resolve(.full, frameWidth: Int.max, frameHeight: Int.max) {
    check("T13-huge-frame-no-overflow", g.width == Int.max && g.height == Int.max)
} else { check("T13-huge-frame-no-overflow", false) }
let fractional = NormalizedRect(x: 0, y: 0, w: 0.101, h: 0.101)!
if case .success(let g) = CropStage.resolve(fractional, frameWidth: 100, frameHeight: 100) {
    check("T14-ceil-edge", g.width == 11 && g.height == 11)
} else { check("T14-ceil-edge", false) }
// R8 (arch-195l): tap-consuming crop detection (TapCropDetector + pump).
// Luma builder: stride padded with 0xFF sentinels; padding must never be read.
func luma(_ w: Int, _ h: Int, strideExtra: Int = 0, fill: UInt8 = 120,
          bars: (top: Int, bottom: Int, left: Int, right: Int) = (0, 0, 0, 0),
          barValue: UInt8 = 4) -> LumaPlane {
    let strideB = w + strideExtra
    var b = [UInt8](repeating: 0xFF, count: strideB * h)
    for y in 0..<h { for x in 0..<w {
        let inBar = y < bars.top || y >= h - bars.bottom || x < bars.left || x >= w - bars.right
        b[y * strideB + x] = inBar ? barValue : fill
    } }
    return LumaPlane(bytes: b, width: w, height: h, strideBytes: strideB)!
}

// T15: letterbox detection, exact rect
if let s = TapCropDetector.detect(luma(320, 180, bars: (20, 20, 0, 0))) {
    check("T15-letterbox", abs(s.rect.y - 20.0/180.0) < 1e-9 && s.rect.x == 0
          && abs(s.rect.h - 140.0/180.0) < 1e-9 && s.rect.w == 1
          && s.confidence > 0.5 && s.confidence <= 1)
} else { check("T15-letterbox", false) }
// T16: pillarbox
if let s = TapCropDetector.detect(luma(320, 180, bars: (0, 0, 30, 30))) {
    check("T16-pillarbox", abs(s.rect.x - 30.0/320.0) < 1e-9 && abs(s.rect.w - 260.0/320.0) < 1e-9 && s.rect.y == 0 && s.rect.h == 1)
} else { check("T16-pillarbox", false) }
// T17: both bar kinds at once
if let s = TapCropDetector.detect(luma(320, 180, bars: (10, 10, 16, 16))) {
    check("T17-both", abs(s.rect.x - 16.0/320.0) < 1e-9 && abs(s.rect.y - 10.0/180.0) < 1e-9)
} else { check("T17-both", false) }
// T18: no bars -> nil
check("T18-nobars", TapCropDetector.detect(luma(320, 180)) == nil)
// T19: fully dark frame is dark content, not a crop
check("T19-darkframe", TapCropDetector.detect(luma(320, 180, fill: 4)) == nil)
// T20: bars beyond maxBarFraction refused
check("T20-overcrop", TapCropDetector.detect(luma(320, 180, bars: (85, 85, 0, 0))) == nil)
// T21: 1px edge noise below minBarPx is not a bar
check("T21-thinbar", TapCropDetector.detect(luma(320, 180, bars: (1, 1, 1, 1))) == nil)
// T22: padded stride gives the same result as packed
let packed = TapCropDetector.detect(luma(320, 180, bars: (20, 20, 0, 0)))
let padded = TapCropDetector.detect(luma(320, 180, strideExtra: 13, bars: (20, 20, 0, 0)))
check("T22-stride", packed?.rect == padded?.rect && padded != nil)
// T23: invalid plane init refused
check("T23-plane-init", LumaPlane(bytes: [1, 2], width: 10, height: 10, strideBytes: 10) == nil
      && LumaPlane(bytes: [UInt8](repeating: 0, count: 100), width: 10, height: 10, strideBytes: 9) == nil)
// T24: pump - rate limit, agreement window, emit once, rect change resets
var pump = CropDetectionPump(minInterval: 1.0, requiredAgreement: 3)!
check("T24-rate", pump.poll(clock: 0.0, plane: luma(320, 180, bars: (20, 20, 0, 0))) == nil
      && pump.poll(clock: 0.5, plane: luma(320, 180, bars: (20, 20, 0, 0))) == nil
      && pump.counters.suppressedRate == 1)
// clock 0.0 already counted as detection #1, so the third agreeing tick is clock 2.0
let e1 = pump.poll(clock: 1.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
let e2 = pump.poll(clock: 2.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
let e3 = pump.poll(clock: 3.0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
check("T24-agreement", e1 == nil && e2 != nil && pump.counters.emitted == 1)
check("T24-stable-no-reemit", e3 == nil && pump.counters.emitted == 1)
// T25: changing bars need a fresh agreement run
let c1 = pump.poll(clock: 5.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))
let c2 = pump.poll(clock: 6.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))
let c3 = pump.poll(clock: 7.0, plane: luma(320, 180, bars: (40, 40, 0, 0)))
check("T25-change", c1 == nil && c2 == nil && c3 != nil
      && c3 != nil && abs(c3!.rect.y - 40.0/180.0) < 1e-9)
// T26: bars gone -> clear to .full only after the agreement run
let n1 = pump.poll(clock: 8.0, plane: luma(320, 180))
let n2 = pump.poll(clock: 9.0, plane: luma(320, 180))
let n3 = pump.poll(clock: 10.0, plane: luma(320, 180))
check("T26-clear", n1 == nil && n2 == nil && n3?.rect == .full && pump.counters.emittedClears == 1)
// T27: nil plane (tap empty this tick) neither emits nor disturbs pending
var pump2 = CropDetectionPump(minInterval: 0, requiredAgreement: 2)!
_ = pump2.poll(clock: 0, plane: luma(320, 180, bars: (20, 20, 0, 0)))
_ = pump2.poll(clock: 1, plane: nil)
let afterNil = pump2.poll(clock: 2, plane: luma(320, 180, bars: (20, 20, 0, 0)))
check("T27-nil-plane", afterNil != nil && pump2.counters.framesSeen == 2)
// T28: invalid pump config refused
check("T28-pump-init", CropDetectionPump(minInterval: .nan) == nil
      && CropDetectionPump(minInterval: 0, requiredAgreement: 0) == nil
      && CropDetectionPump(minInterval: 0, requiredAgreement: 1, tolerance: 0) == nil)
// T29: noisy bar above barMaxPeak is content, not a bar
var noisyBytes = [UInt8](repeating: 120, count: 320 * 180)
for y in 0..<20 { for x in 0..<320 { noisyBytes[y * 320 + x] = 4 } }
for y in 160..<180 { for x in 0..<320 { noisyBytes[y * 320 + x] = 4 } }
for y in 0..<20 { noisyBytes[y * 320] = 200 }                       // one bright pixel per bar row
for y in 160..<180 { noisyBytes[y * 320] = 200 }                     // same for the bottom bar
let noisyPlane = LumaPlane(bytes: noisyBytes, width: 320, height: 180, strideBytes: 320)!
check("T29-noisy-bar", TapCropDetector.detect(noisyPlane) == nil)

print("crop-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
