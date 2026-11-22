import Foundation
// Models the owner flow with fake projection state: vr = old vr180-look flat-2d3d on/off, 3D mode, rendered shot showing.
var vr = false, mode = "off", osd = "-"
ThreeDAutoRoute.stopPreview = { vr = false }; ThreeDAutoRoute.resumePreview = { vr = true }
func menu(_ k: String, stereo: Bool) { ThreeDAutoRoute.run(kind: k, filmLooksStereo: stereo, setMode: { mode = $0 }, osd: { osd = $0 }); if k == "flat-2d3d" || k == "flat-sbs" || k == "vr180" { vr = true } }   // the caller ALWAYS runs the old select afterwards
func st(_ l: String) { print("\(l) vr=\(vr) mode=\(mode) preview=\(ThreeDAutoRoute.previewActive) osd=\(osd)") }
menu("flat-2d3d", stereo: false); st("after 2d3d on mono film")
MainActor.assumeIsolated {
    let defaults=UserDefaults(suiteName:"gor-route-regression-"+UUID().uuidString)!
    let store=ThreeDStore(defaults:defaults),id=FilmID(rawValue:"flat-film")
    store.dispatch(.open(id,ThreeDEvidence(metadata:ThreeDSource(.flat2D))))
    store.dispatch(.setOutput(.sbs))
    store.dispatch(.generated(id,ThreeDSource(.vr180SBS),.sbs))
    precondition(store.snapshot.presentationSource.format == .vr180SBS)
    print("rendered shot loaded: store presentation=vr180SBS output=full_sbs")
    store.dispatch(.original)
    precondition(store.snapshot.presentationSource.format == .flat2D && store.snapshot.current.output == .sbs)
    print("seek to unrendered shot: store presentation=flat2D output=full_sbs")
    store.dispatch(.setOutput(.off));store.dispatch(.original)
    precondition(store.snapshot.presentationSource.format == .flat2D && store.snapshot.current.output == .off)
    print("off then original: store presentation=flat2D output=off")
}
osd = "-"; mode = "off"; vr = false; menu("flat-sbs", stereo: false); st("sbs on mono film")
osd = "-"; menu("vr180", stereo: true); st("vr180 on stereo film")
vr = false; osd = "-"; mode = "sbs-picked"; ThreeDAutoRoute.filmStereo = { false }; ThreeDAutoRoute.osdOut = { osd = $0 }; ThreeDAutoRoute.beginPreview(); st("any mode picked on mono film, no models")
vr = false; osd = "-"; ThreeDAutoRoute.endPreview(); ThreeDAutoRoute.filmStereo = { true }; ThreeDAutoRoute.beginPreview(); st("mode picked on stereo film")
vr = false; mode = "off"; osd = "-"; ThreeDAutoRoute.endPreview(); let before = "vr=\(vr) mode=\(mode) preview=\(ThreeDAutoRoute.previewActive)"
ThreeDAutoRoute.filmStereo = { false }; ThreeDAutoRoute.osdOut = { _ in }; menu("flat-2d3d", stereo: false); ThreeDAutoRoute.turnOff(); mode = "off"
print("3d switch on then off: " + (before == "vr=\(vr) mode=\(mode) preview=\(ThreeDAutoRoute.previewActive)" ? "RESTORED" : "NOT RESTORED"))
menu("flat-2d3d", stereo: false); ThreeDAutoRoute.vrChoseOff(setMode: { mode = $0 }); vr = false
print("vr item on then vr mono: " + (before == "vr=\(vr) mode=\(mode) preview=\(ThreeDAutoRoute.previewActive)" ? "RESTORED" : "NOT RESTORED"))

var pf = 0
func pcheck(_ n: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + n); if !ok { pf += 1 } }
typealias R = ThreeDAutoRoute
let base = R.previewParams(mode: "full_sbs", strength: 1, screenDepthM: nil, screenDeg: nil, surround: "black")
pcheck("mode: sbs 3, half sbs 3, top/bottom 1, anaglyph 2, vr180 4 (pairwise layouts differ)", R.pack(mode: "full_sbs") == 3 && R.pack(mode: "half_sbs") == 3 && R.pack(mode: "over_under") == 1 && R.pack(mode: "anaglyph") == 2 && R.pack(mode: "vr180") == 4)
pcheck("strength changes gain, 0 is flat, clamped 0...2", R.previewParams(mode: "full_sbs", strength: 0, screenDepthM: nil, screenDeg: nil, surround: "black").gain == 0 && R.previewParams(mode: "full_sbs", strength: 2, screenDepthM: nil, screenDeg: nil, surround: "black").gain == 2 && R.previewGain(strength: 9) == 2)
pcheck("screen depth changes the convergence plane both ways", R.previewConv(screenDepthM: 0.75) > base.conv && R.previewConv(screenDepthM: 3) < base.conv)
pcheck("screen size changes zoom both ways", R.previewZoom(screenDeg: 55) < 1 && R.previewZoom(screenDeg: 100) > 1 && R.previewZoom(screenDeg: nil) == 1)
pcheck("surround soft vs black changes soft", R.previewParams(mode: "full_sbs", strength: 1, screenDepthM: nil, screenDeg: nil, surround: "soft").soft != base.soft)
pcheck("source: flat forces 2d, layout forces stereo, auto follows the probe", !R.effectiveStereo(probe: true, source: "flat") && R.effectiveStereo(probe: false, source: "sbs") && R.effectiveStereo(probe: true, source: "auto") && !R.effectiveStereo(probe: false, source: "auto"))
pcheck("quality: no tier claims a processing effect with or without kit", R.qualityState(quality: "tier1", kitReady: false).contains("not implemented") && R.qualityState(quality: "tier1", kitReady: true).contains("selection changes no processing") && R.qualityState(quality: "auto", kitReady: true).contains("fallback only"))

print("preview params: \(pf) failure(s)")

R.previewActive = false; var stops = 0; R.stopPreview = { stops += 1 }; R.turnOff(); pcheck("off always stops the projection even when preview flag was stale/false", stops == 1 && !R.previewActive)

pcheck("master state: saved mode without active playback is OFF; projection/preview ON is checked; OFF mode is unchecked", !R.masterActive(mode: "vr180", projectionOn: false, previewOn: false) && R.masterActive(mode: "vr180", projectionOn: true, previewOn: false) && R.masterActive(mode: "vr180", projectionOn: false, previewOn: true) && R.masterActive(mode: "off", projectionOn: true, previewOn: false))
