import Foundation
import GorAVPlaybackCore

// Witness for the R9 color stage policy: curve selection, peak defaults,
// overrides, software fallback, receipts, input guards.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

// T1: sdr to sdr = no tone map, no fallback
let p1 = ColorStage.plan(source: SourceSignal(trc: .bt709), target: .sdr100, hardwareToneMapper: false)
check("T1", p1.curve == .none && !p1.softwareFallback && p1.receipts.contains("sdr-to-sdr:no-tone-map"))

// T2: hdr10 to sdr, no hw = mobius + software fallback, default peak 1000
let p2 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ), target: .sdr100, hardwareToneMapper: false)
check("T2", p2.curve == .mobius && p2.softwareFallback && p2.sourcePeakNits == 1000
      && p2.receipts.contains("hdr-to-sdr:mobius-default")
      && p2.receipts.contains("no-hw-tone-mapper:software-fallback"))

// T3: same with hw tone mapper = no fallback
let p3 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ), target: .sdr100, hardwareToneMapper: true)
check("T3", p3.curve == .mobius && !p3.softwareFallback)

// T4: signalled mastering peak wins over default; invalid signalled peak ignored
let p4 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: 4000), target: .sdr100, hardwareToneMapper: true)
check("T4", p4.sourcePeakNits == 4000 && !p4.receipts.contains { $0.hasPrefix("src-peak-default") })
check("T4b", SourceSignal(trc: .bt2020PQ, sourcePeakNits: -5).sourcePeakNits == nil
      && SourceSignal(trc: .bt2020PQ, sourcePeakNits: .nan).sourcePeakNits == nil)

// T5: hlg to sdr
let p5 = ColorStage.plan(source: SourceSignal(trc: .hlg), target: .sdr100, hardwareToneMapper: false)
check("T5", p5.curve == .mobius && p5.sourcePeakNits == 1000)

// T6: dv without hw forces software even when curve is none (sdr-to-hdr path cannot occur for dv, use hdr target)
let dvTarget = DisplayTarget(targetTRC: .bt2020PQ, peakNits: 1000)!
let p6 = ColorStage.plan(source: SourceSignal(trc: .dolbyVision), target: dvTarget, hardwareToneMapper: false)
check("T6", p6.softwareFallback && p6.receipts.contains("dv-without-hw:software-fallback"))

// T7: sdr to hdr = passthrough, no inverse tone map
let p7 = ColorStage.plan(source: SourceSignal(trc: .bt709), target: dvTarget, hardwareToneMapper: false)
check("T7", p7.curve == .none && p7.receipts.contains("sdr-to-hdr:passthrough-no-inverse-tone-map"))

// T8: hdr to hdr, peak fits = none; exceeds = mobius
let p8a = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: 600), target: dvTarget, hardwareToneMapper: true)
let p8b = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ, sourcePeakNits: 4000), target: dvTarget, hardwareToneMapper: true)
check("T8", p8a.curve == .none && p8a.receipts.contains("hdr-to-hdr:peak-fits")
      && p8b.curve == .mobius && p8b.receipts.contains("hdr-to-hdr:mobius-down-map"))

// T9: curve override wins, receipt names it
let p9 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ),
                         target: DisplayTarget(targetTRC: .bt709, peakNits: 100, curveOverride: .hable)!,
                         hardwareToneMapper: true)
check("T9", p9.curve == .hable && p9.receipts.contains("curve-override:hable"))

// T10: target guards - bad peak/saturation refused
check("T10", DisplayTarget(targetTRC: .bt709, peakNits: 0) == nil
      && DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: 2.5) == nil
      && DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: -1) == nil
      && DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: 2.0) != nil)

// T11: saturation and gamut carried into the plan
let p11 = ColorStage.plan(source: SourceSignal(trc: .bt2020PQ),
                          target: DisplayTarget(targetTRC: .bt709, peakNits: 100, saturation: 0.8, gamut: .relativeColorimetric)!,
                          hardwareToneMapper: true)
check("T11", p11.saturation == 0.8 && p11.gamut == .relativeColorimetric)

print("color-stage-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
