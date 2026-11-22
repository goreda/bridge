// ThreeD/Render.swift - 3D station "Render": render, shot writing, playback, stereo kernels and comfort.
// Move-only split of the former ThreeD.swift (arch-199s). The sections below are byte-identical to their former BEGIN/END spans,
// in their original relative order. The import list is the union of the former file (a deliberate superset; narrow it only with a Darwin compile).
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Accelerate)
import Accelerate
#endif
import AppKit
#if canImport(Compression)
import Compression
#endif
import CoreGraphics
#if canImport(CoreML)
import CoreML
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Darwin
import Foundation
#if canImport(Glibc)
import Glibc
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Metal)
import Metal
#endif
import QuartzCore
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(VideoToolbox)
import VideoToolbox
#endif
#if canImport(Vision)
import Vision
#endif

// BEGIN relocated ShotComfort.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// CONTRACT-190v s25 default comfort policy, port of tools/depth_analysis/comfort.py (shot_comfort), float64, pure Foundation.
/// Per shot, constant inside the shot (steps only at cuts): z_c = median of ALL valid depth (z > 0, finite) of the shot, B_eff = min(ipd, 2 z_c tan(FAR/2)),
/// depth_scale = B_eff / ipd, z_near = near_clamp(z_c, B_eff); the renderer clamps z to >= z_near before projecting (positive z only, invalid stays invalid).
struct ShotComfort: Equatable {
    static let ipd = 0.063, nearBudgetDeg = 2.0, farBudgetDeg = 1.0
    var convergenceM: Double, ipdEff: Double, depthScale: Double, zNear: Double, farOverflowDeg: Double
    var nearBudgetDeg = ShotComfort.nearBudgetDeg
    var measurement: Measurement? = nil
    var todayFallback = false
    struct Measurement: Equatable {
        var p5: Double, p50: Double, p95: Double, zc: Double, gain: Double, spanTodayDeg: Double, spanDeepDeg: Double
        var sat1023Frac = 0.0, zeroFrac = 0.0, seenSpanDeepDeg = 0.0
        var mode = "deep"
        func line(shot: Int, model: String, dofOverridden: Bool) -> String {
            "3D-DEEP shot=\(shot) model=\(model) p5=\(p5) p50=\(p50) p95=\(p95) zc=\(zc) gain=\(gain) spanTodayDeg=\(spanTodayDeg) spanDeepDeg=\(spanDeepDeg) sat1023Frac=\(sat1023Frac) zeroFrac=\(zeroFrac) seenSpanDeepDeg=\(seenSpanDeepDeg) dofOverridden=\(dofOverridden) mode=\(mode) seenTodayDeg=\(spanTodayDeg)"
        }
    }

    static func nearClamp(zc: Double, ipd: Double = ShotComfort.ipd, budgetDeg: Double = ShotComfort.nearBudgetDeg) -> Double {
        guard ipd > 0 else { return 0 }
        let t = tan(budgetDeg * Double.pi / 360.0 + atan(ipd / (2.0 * zc)))
        return ipd / (2.0 * t)
    }
    static func farOverflow(zc: Double, ipd: Double = ShotComfort.ipd, budgetDeg: Double = ShotComfort.farBudgetDeg) -> Double {
        2.0 * atan(ipd / (2.0 * zc)) * 180.0 / Double.pi - budgetDeg
    }
    static func minConvergence(ipd: Double = ShotComfort.ipd, budgetDeg: Double = ShotComfort.farBudgetDeg) -> Double {
        ipd / (2.0 * tan(budgetDeg * Double.pi / 360.0))
    }
    /// comfort.py disp_deg: + crossed, - uncrossed.
    static func dispDeg(z: Double, zc: Double, ipd: Double = ShotComfort.ipd) -> Double {
        (2.0 * atan(ipd / (2.0 * max(z, 1e-9))) - 2.0 * atan(ipd / (2.0 * zc))) * 180.0 / Double.pi
    }
    /// Menu "strength" on top of the comfort baseline: final eye offset = ipd * depthScale(B_eff / ipd) * factor. Strength <= 1 only shrinks the baseline, so z_near, z_c and both
    /// budgets (2 deg crossed, 1 deg divergence) keep holding. Above 1 it is capped to 1 unless the user explicitly picked an over-budget level (`overBudget`, labelled in the menu).
    static func strengthFactor(_ strength: Double, overBudget: Bool) -> Double {
        guard strength.isFinite, strength > 0 else { return 0 }
        return overBudget ? strength : min(strength, 1.0)
    }
    /// comfort.py shot_comfort for a given shot median; nil for a non-positive or non-finite median.
    static func make(medianZ zc: Double, ipd: Double = ShotComfort.ipd) -> ShotComfort? {
        guard zc.isFinite, zc > 0 else { return nil }
        let b = min(ipd, 2.0 * zc * tan(farBudgetDeg * Double.pi / 360.0))
        return ShotComfort(convergenceM: zc, ipdEff: b, depthScale: b / ipd, zNear: nearClamp(zc: zc, ipd: b), farOverflowDeg: b < ipd ? 0.0 : farOverflow(zc: zc, ipd: ipd))
    }
    /// Exact median (numpy semantics: mean of the two middle values) over the valid values of any number of frames.
    static func median(_ frames: [[Float]]) -> Double? {
        var v: [Double] = []
        for f in frames { for z in f where z.isFinite && z > 0 { v.append(Double(z)) } }
        return medianSorted(v.sorted())
    }
    private static func medianSorted(_ s: [Double]) -> Double? {
        if s.isEmpty { return nil }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2.0
    }

    /// Streaming median over the 10-bit .dzc planes (w10 -> z = 256 / (w10 / 1023 * 1024); w10 == 0 is invalid). 1024 counters, so a whole shot costs no memory.
    /// Exactly the median of the dequantised values (z falls as w10 rises); the quantisation is the container's, not added here.
    struct Histogram {
        private(set) var counts = [Int](repeating: 0, count: 1024)
        private(set) var total = 0, zeros = 0
        var samples: Int { total + zeros }
        var saturated: Int { counts[1023] }
        mutating func add(plane: [UInt16]) { for w in plane { let i = Int(w & 1023); if i > 0 { counts[i] += 1; total += 1 } else { zeros += 1 } } }
        static func z(w10: Int) -> Double { 256.0 / (Double(w10) / 1023.0 * 1024.0) }
        func quantile(_ q: Double) -> Double? {
            guard total > 0, q.isFinite, q >= 0, q <= 1 else { return nil }
            func at(_ rank: Int) -> Double {
                var seen = 0
                for w in stride(from: 1023, through: 1, by: -1) { seen += counts[w]; if rank < seen { return Histogram.z(w10: w) } }
                return Histogram.z(w10: 1)
            }
            let pos = q * Double(total - 1), i = Int(pos.rounded(.down)), j = min(i + 1, total - 1)
            return at(i) + (at(j) - at(i)) * (pos - Double(i))
        }
        func median() -> Double? { quantile(0.5) }
    }
}

// BEGIN relocated ShotComfortSpan.swift (195y G2, behavior unchanged)
/// F3 (A-D 14:41): the default comfort budget (ShotComfort.make) is derived from ONE number, the shot median, and keeps the divergence limit true for z -> infinity. A shot whose real depth range is small (a flat distant scene: p5..p95 span a fraction of a degree)
/// gets the same baseline as one that fills the budget, so its depth feel is weak. Scale-invariant variant: derive the eye-offset gain from the shot's OWN disparity quantiles, p5 (near side) and p95 (far side), in degrees relative to the convergence z_c:
/// the largest gain s in [minGain, maxGain] with dispDeg(p5, s*ipd) <= nearBudget (2 deg crossed) and dispDeg(p95, s*ipd) >= -farBudget (1 deg uncrossed). Both ceilings hold at the quantiles by construction (bisection on the exact formula, not a small-angle estimate).
/// Pure Foundation. ShotComfortShot derives these quantiles from the finished container; the renderer uses this gain, not the old median-only baseline.
struct ShotComfortSpan: Equatable {
    static let minGain = 0.25, maxGain = 3.0
    var nearClampM: Double, gain: Double, ipdEff: Double, nearDeg: Double, farDeg: Double, spanDeg: Double, spanBeforeDeg: Double, clamped: Bool
    /// zNear/zFar = shot quantiles p5 / p95 of valid depth (metres), zc = convergence (shot median). nil for invalid input.
    static func make(zNear: Double, zFar: Double, zc: Double, ipd: Double = ShotComfort.ipd, nearBudgetDeg: Double = ShotComfort.nearBudgetDeg, farBudgetDeg: Double = ShotComfort.farBudgetDeg, maxGain: Double = ShotComfortSpan.maxGain) -> ShotComfortSpan? {
        guard zNear.isFinite, zFar.isFinite, zc.isFinite, zNear > 0, zFar >= zNear, zc > 0 else { return nil }
        func ok(_ s: Double) -> Bool {
            ShotComfort.dispDeg(z: zNear, zc: zc, ipd: ipd * s) <= nearBudgetDeg && ShotComfort.dispDeg(z: zFar, zc: zc, ipd: ipd * s) >= -farBudgetDeg
        }
        func span(_ s: Double) -> Double { ShotComfort.dispDeg(z: zNear, zc: zc, ipd: ipd * s) - ShotComfort.dispDeg(z: zFar, zc: zc, ipd: ipd * s) }
        var g: Double
        if ok(maxGain) { g = maxGain }
        else if !ok(minGain) { g = minGain }
        else {
            var lo = minGain, hi = maxGain                       // ok(lo), !ok(hi)
            for _ in 0..<60 { let m = (lo + hi) / 2; if ok(m) { lo = m } else { hi = m } }
            g = lo
        }
        let base = ShotComfort.make(medianZ: zc, ipd: ipd)?.depthScale ?? 1.0
        return ShotComfortSpan(nearClampM: ShotComfort.nearClamp(zc: zc, ipd: ipd * g, budgetDeg: nearBudgetDeg), gain: g, ipdEff: ipd * g, nearDeg: ShotComfort.dispDeg(z: zNear, zc: zc, ipd: ipd * g), farDeg: ShotComfort.dispDeg(z: zFar, zc: zc, ipd: ipd * g),
                               spanDeg: span(g), spanBeforeDeg: span(base), clamped: g == minGain || g == maxGain)
    }
    /// Quantile of the valid depth values (z > 0, finite) of any number of frames, linear interpolation (numpy default); nil if none.
    static func quantile(_ frames: [[Float]], _ q: Double) -> Double? {
        var v: [Double] = []
        for f in frames { for z in f where z.isFinite && z > 0 { v.append(Double(z)) } }
        guard !v.isEmpty else { return nil }
        v.sort(); let pos = q * Double(v.count - 1), i = Int(pos.rounded(.down)), j = min(i + 1, v.count - 1)
        return v[i] + (v[j] - v[i]) * (pos - Double(i))
    }
}
/// arch-199i: shared pure geometry for rendered shots and subtitle parameters.
/// Compare displayed spans after the actual near clamp. Never raise the budget
/// gain to meet today's span: select the exact fixed path when deep is shallower.
enum ShotDeepGeometry {
    static func make(p5: Double, p50: Double, p95: Double, ipd: Double, screenDepth: Double?, strength: Double, overBudget: Bool, options: ThreeDExperimentOptions) -> (comfort: ShotComfort, spanTodayDeg: Double, spanDeepDeg: Double)? {
        guard p50.isFinite, p50 > 0, ipd.isFinite, ipd > 0 else { return nil }
        let deep = options.deepVolume
        let zc = deep ? p50 * ((screenDepth ?? 1.5) / 1.5) : p50
        let nearBudget = deep ? 3.0 : ShotComfort.nearBudgetDeg
        let farBudget = deep ? 2.0 : ShotComfort.farBudgetDeg
        let maxGain = deep ? 6.0 : ShotComfortSpan.maxGain
        guard let span = ShotComfortSpan.make(zNear: p5, zFar: p95, zc: zc, ipd: ipd, nearBudgetDeg: nearBudget, farBudgetDeg: farBudget, maxGain: maxGain) else { return nil }
        let factor = ShotComfort.strengthFactor(strength, overBudget: overBudget)
        func angularSpan(_ baseline: Double) -> Double {
            ShotComfort.dispDeg(z: p5, zc: zc, ipd: baseline) - ShotComfort.dispDeg(z: p95, zc: zc, ipd: baseline)
        }
        let zcToday = screenDepth ?? 1.5
        let today = ShotComfort.dispDeg(z: p5, zc: zcToday, ipd: ipd * strength) - ShotComfort.dispDeg(z: p95, zc: zcToday, ipd: ipd * strength)
        let gain = span.gain
        let after = angularSpan(ipd * gain * factor)
        var c = ShotComfort(convergenceM: zc, ipdEff: ipd * gain, depthScale: gain,
                            zNear: ShotComfort.nearClamp(zc: zc, ipd: ipd * gain, budgetDeg: nearBudget),
                            farOverflowDeg: ShotComfort.farOverflow(zc: zc, ipd: ipd * gain, budgetDeg: farBudget))
        c.nearBudgetDeg = nearBudget
        if deep {
            let finalIPD = ipd * gain * factor
            let nearClamp = ShotComfort.nearClamp(zc: zc, ipd: finalIPD, budgetDeg: nearBudget)
            let seenSpan = ShotComfort.dispDeg(z: max(p5, nearClamp), zc: zc, ipd: finalIPD) - ShotComfort.dispDeg(z: max(p95, nearClamp), zc: zc, ipd: finalIPD)
            c.todayFallback = seenSpan < today
            c.measurement = ShotComfort.Measurement(p5: p5, p50: p50, p95: p95, zc: zc, gain: gain, spanTodayDeg: today, spanDeepDeg: after, seenSpanDeepDeg: seenSpan, mode: c.todayFallback ? "today" : "deep")
        }
        return (c, today, after)
    }
}
// END relocated ShotComfortSpan.swift

// BEGIN relocated ShotCuts.swift (195y G2, behavior unchanged)
/// 190t native prepare: shot-cut detection (CONTRACT-190v s18, tools/depth_analysis/cuts.py). The detector is a port of ffmpeg's scdet score on the LUMA plane only
/// (measured against `ffmpeg -vf scdet,metadata=print` on a synthetic clip: luma-only mafd matches to 3 decimals, all-planes does not): mafd = SAD(Y, prevY) * 100 / (w*h) / 256,
/// diff = |mafd - prevMafd|, score = clip(min(mafd, diff), 0, 100), cut when score >= 12.0 (frame 0 scores 0). The ranges / rounding rules are the s18 hard semantics.
/// Pure Foundation: tested on Linux against the A-D parity fixture and ffmpeg. The frame feed (AVAssetReader luma) is the runner's job.
enum ShotCuts {
    static let threshold = 12.0
    /// cuts.py detect_cuts: frame = int(t * fps + 0.5), dedup, sort.
    static func frames(fromTimes times: [Double], fps: Double) -> [Int] { Array(Set(times.map { Int($0 * fps + 0.5) })).sorted() }
    /// cuts.py shots_from_cuts: bounds = [0] + cuts(0 < c < n) + [n]; shot i = (bounds[i], bounds[i+1] - 1) inclusive.
    static func shots(nFrames: Int, cuts: [Int]) -> [[Int]] {
        let b = [0] + cuts.filter { $0 > 0 && $0 < nFrames } + [nFrames]
        return (0..<(b.count - 1)).map { [b[$0], b[$0 + 1] - 1] }
    }
}

/// Streaming scorer: feed tightly packed luma planes (w*h bytes, equal size) in display order.
struct SceneScorer {
    private var prev: [UInt8]? = nil, prevMafd = 0.0
    private(set) var frameIndex = -1
    /// (mafd, score) for this frame (frame 0: 0, 0, as ffmpeg).
    mutating func score(luma: [UInt8]) -> (mafd: Double, score: Double) {
        frameIndex += 1
        defer { prev = luma }
        guard let p = prev, p.count == luma.count, !luma.isEmpty else { prevMafd = 0; return (0, 0) }
        var sad: UInt64 = 0
        for i in 0..<luma.count { let a = Int(luma[i]), b = Int(p[i]); sad += UInt64(a > b ? a - b : b - a) }
        let mafd = Double(sad) * 100.0 / Double(luma.count) / 256.0
        let diff = abs(mafd - prevMafd); prevMafd = mafd
        return (mafd, min(max(min(mafd, diff), 0), 100))
    }
}

extension ShotCuts {
    /// Cut frame indices from a luma feed (`next` returns nil at the end). Frame indices are display-order positions, equal to int(t*fps+0.5) for constant-rate video.
    static func detect(next: () -> [UInt8]?, threshold: Double = ShotCuts.threshold) -> (cuts: [Int], nFrames: Int) {
        var s = SceneScorer(), cuts: [Int] = [], n = 0
        while let f = next() { let r = s.score(luma: f); if n > 0, r.score >= threshold { cuts.append(n) }; n += 1 }
        return (cuts, n)
    }
}
// END relocated ShotCuts.swift

// BEGIN relocated ShotComfortShot.swift (195y G2, behavior unchanged)
/// Per-shot span comfort constants straight from the finished depth_shot_NNNNN.dzc: one streaming pass over every frame's w10 plane (ShotComfort.Histogram), no sidecar,
/// so it cannot disagree with the depth that gets rendered. nil (= fixed-parameter render) when the file is unreadable or has no valid depth.
/// p5, median and p95 use numpy-linear quantiles of the same streamed histogram. The plane includes the container's edge padding (at most a few rows/columns of repeated edge values): a sub-percent effect on the median. Not compiled on a Mac.
enum ShotComfortShot {
    static func compute(depth url: URL, ipd: Double = ShotComfort.ipd, options: ThreeDExperimentOptions = ThreeDExperimentOptions(), screenDepth: Double? = nil, strength: Double = 1.0, overBudget: Bool = false) -> ShotComfort? {
        guard let f = DZCFile(url: url) else { return nil }
        var h = ShotComfort.Histogram()
        for i in 0..<f.count { guard let p = f.plane(i) else { return nil }; h.add(plane: p) }
        guard let c = h.median(), let lo = h.quantile(0.05), let hi = h.quantile(0.95),
              let geometry = ShotDeepGeometry.make(p5: lo, p50: c, p95: hi, ipd: ipd, screenDepth: screenDepth, strength: strength, overBudget: overBudget, options: options) else { return nil }
        var result = geometry.comfort
        if result.measurement != nil, h.samples > 0 {
            result.measurement!.sat1023Frac = Double(h.saturated) / Double(h.samples)
            result.measurement!.zeroFrac = Double(h.zeros) / Double(h.samples)
        }
        return result
    }
}
// END relocated ShotComfortShot.swift
// END relocated ShotComfort.swift
// BEGIN relocated ThreeDRenderCoordinator.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AVFoundation) && canImport(Metal) && canImport(CoreVideo)

/// 190t I: decides WHICH shot to render and WHEN, and switches the player between the 2D film and render_shot files. Everything that touches
/// the player is injected (`send` takes one JSON line, `query` sends one JSON line and returns the reply, `playhead` / `film` read player
/// state), so this file has no player-socket code. Idle (mode off, no 3D film open, no Metal) = no timer work beyond a cheap tick.
/// Switching is a hard `loadfile` at the playhead: the 0.5 s crossfade in ThreeDPresentation has no compositing surface yet, so the alpha is
/// computed but not drawn. Not run on a Mac.
final class ThreeDRenderCoordinator {
    private let send: (String) -> Void, mpvExecutable: () -> URL?
    private let playhead: () -> Double?, film: () -> URL?
    // G1 injects the ACTUAL active engine and R4-backed prepared session. Defaults
    // preserve every existing mpv caller. Gorav never invokes mpv decoder probes.
    private let activeEngine: () -> PlayerEngine
    private let preparedSession: @MainActor () -> PreparedShotPlayback?
    private let goravDecoders: () -> [String]
    private var preparedLoadTask: Task<Void, Never>?
    private var preparedLoadID = UUID()
    private var preparedLoadPending = false
    private let prefsReader = RenderPrefsReader()
    private let work = DispatchQueue(label: "gor.3d.render", qos: .utility)
    private var timer: Timer?, presentation = ThreeDPresentation()
    private var decoders: [String]?, writer: RenderShotWriter?, synthTold = false
    private var busy: [Int: UInt64] = [:]
    private let revision = RenderRevision()
    private var renderPrefs: RenderPrefsValue?
    private var showingURL: URL?
    private var lastGood: [Int: (url: URL, prefs: RenderPrefsValue)] = [:]
    private var retired = Set<URL>()
    private var boundFilmID: FilmID?
    private var observedDepthKeys: [Int:String] = [:]
    private var lastPTS: Double?, lastTick = 0.0, showing: Int?       // shot whose render file the player currently plays (nil = 2D)
    private var film2D: URL?                                         // the 2D film's URL (the player's path is the render file while 3D plays)
    private var announced = Set<String>()
    /// s38 degradation FSM: logs every transition (3dfsm lines) and executes only OSD actions; the depth-input swaps it names are already what tick/backTo2D do.
    private(set) lazy var degrade = ThreeDDegrade(exec: { [weak self] a in
        if a.hasPrefix("act_osd("), a.hasSuffix(")") { self?.announce(String(a.dropFirst(8).dropLast())) }
    })
    private var lastFilm: URL?, diskBlocked = false, relaunchChecked = false
    private var duty = ThermalDutyPolicy()      // same suspend/resume rule as the prepare gate, stepped per tick, feeds thermal_trip / thermal_clear
    private var indexCache: (entry: URL, index: DepthShotIndex)?
    /// Frame range of the playhead's shot, kept fresh every tick even while mode is off (the menu reads it to enable sbs/vr180).
    private(set) var shotFrames: (Int, Int)?

    init(send: @escaping (String) -> Void, mpvExecutable: @escaping () -> URL?, playhead: @escaping () -> Double?, film: @escaping () -> URL?,
         activeEngine: @escaping () -> PlayerEngine = { .mpv },
         preparedSession: @escaping @MainActor () -> PreparedShotPlayback? = { nil },
         goravDecoders: @escaping () -> [String] = { [] }) {
        self.send = send; self.mpvExecutable = mpvExecutable; self.playhead = playhead; self.film = film
        self.activeEngine = activeEngine
        self.preparedSession = preparedSession
        self.goravDecoders = goravDecoders
    }

    private var cachePin: DepthCacheBudget.Pin?
    private var cachePinKey: String?
    private var mediaTransitionPending=false
    func setMediaTransitionPending(_ pending:Bool) {
        mediaTransitionPending=pending
        if pending {
            cachePin=nil;cachePinKey=nil
            revision.invalidate();preparedLoadTask?.cancel();preparedLoadTask=nil
            preparedLoadID=UUID();preparedLoadPending=false
            showing=nil;showingURL=nil;film2D=nil;lastFilm=nil;indexCache=nil
            lastGood=[:];lastPTS=nil;ThreeDSubtitleDepth.shared.end()
        }
    }
    private var storeOutput=ThreeDOutput.off
    func applyStoreOutput(_ output:ThreeDOutput,reapply:Bool=false,filmID:FilmID?=nil) {
        if filmID != boundFilmID {
            preparedLoadTask?.cancel(); preparedLoadTask=nil
            preparedLoadID=UUID(); preparedLoadPending=false
            revision.invalidate();boundFilmID=filmID;lastGood=[:]
            showing=nil;showingURL=nil;film2D=nil;lastFilm=nil;indexCache=nil
            renderPrefs=nil;observedDepthKeys=[:];lastPTS=nil;ThreeDSubtitleDepth.shared.end()
        }
        guard output != storeOutput else {return}
        lastGood=[:]
        storeOutput=output
        revision.invalidate()
        if output != .off && showing != nil { backTo2D(playhead() ?? 0,filmURL:film2D) }
        if output == .off {backTo2D(playhead() ?? 0,filmURL:film2D)}
    }
    func start() {
        guard timer == nil else { return }
        let startupSource=film()
        DispatchQueue.global(qos:.utility).async {
            let root=DepthCachePaths.root
            guard DepthCacheBudget.plainDirectory(root) else {return}
            do {try DepthCacheBudget.reapLegacyInputs(root:root,source:startupSource);try ShotGenerationStore.reapAbandoned(root:root)}
            catch {DepthCacheBudget.recordFailure(.unsafe,root:root);print("3d-cache startup_reaper_failed=\(error)");fflush(stdout)}
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.05
    }

    /// Called by the store subscriber immediately after writing render preferences.
    /// This cancels work now; the timer starts replacements only after debounce.
    func preferencesDidChange(force: Bool = false) {
        let prefs=prefsReader.refresh()
        if force {revision.invalidate()}
        if force || prefs != renderPrefs {
            renderPrefs=prefs
            revision.update(String(describing:prefs),now:ProcessInfo.processInfo.systemUptime)
            print("3D-RENDER v1 event=preferences generation=\(revision.token) debounce_ms=500")
        }
    }

    /// s33 F3: depth content version = the shot's .dzc size + mtime (nanoseconds). A re-prepare (e.g. another quality) rewrites the container, so a stale render_shot file no longer matches.
    static func depthStamp(_ dzc: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: dzc.path)
        let size = (a?[.size] as? NSNumber)?.int64Value ?? -1, t = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "|d\(size)-\(Int64((t*1_000_000_000).rounded()))"
    }
    /// Stable key of everything that changes a render's pixels; stored next to each file so a prefs change re-renders it.
    static func key(_ p: RenderPrefsValue, eyeN: Int, codec: RenderedShotPlan.Codec, swap: Bool, method: SynthMethod = SynthMethod.current.method, options: ThreeDExperimentOptions = .live) -> String {
        // v5: span-p5p95 invalidates median-only comfort renders; the depth stamp fixes shot quantiles.
        // v4 (190w W3): the synthesis method is part of the key, so a tier change re-prepares every stand-in render (v3-keyed files are stale; existing marker-only eviction). Mirror: rehearsal.render_key_v4.
        // v3 (CONTRACT-190v s33): under comfort the render uses ipdM * shotScale * strengthFactor, so key on ipdM and the strength FACTOR (not effectiveIPD = ipdM * strength):
        // fixes F1 (ipdM .063 x2 vs .126 x1 collided) and F2 (strength 2 -> 3 above the cap changed the key, not the pixels). The fixed path renders with effectiveIPD.
        let ipdPart = p.comfortActive(options) ? "comfort|ipd\(p.ipdM)|sf\(ShotComfort.strengthFactor(p.depthScale, overBudget: p.overBudget))" : "fixed|ipd\(p.effectiveIPD)"
        // 195h r2: experiment switches invalidate cached renders through this key; all-off keys stay byte-identical with the pre-195h strings.
        return "v5|span-p5p95|\(method.rawValue)|\(options.renderKeyComponent.map { $0 + "|" } ?? "")\(ipdPart)|\(OutputMode.parse(p.mode)?.rawValue ?? p.mode)|\(p.convergenceM.map { "\($0)" } ?? "nil")|\(eyeN)|\(codec.rawValue)|\(swap)|\(p.screenDeg)|\(p.surroundSoft)"
    }
    /// Eye size: the source picture height (even), at least 256, at most 4096 (an 8192-wide HEVC frame). Never below the source: no thumbnail.
    static func eyeN(sourceHeight: Int) -> Int { max(256, min(4096, sourceHeight - sourceHeight % 2)) }

    private func shotIndex(_ entry: URL) -> DepthShotIndex? {
        if let c = indexCache, c.entry == entry { return c.index }
        guard let i = DepthShotIndex(entry: entry) else { return nil }
        indexCache = (entry, i); return i
    }

    private func announce(_ text: String) {
        ThreeDShotPlayLog.logOSD(text)                           // X1: the log carries the OSD text even when the menu toggle hides it
        guard MainActor.assumeIsolated({ThreeDStore.shared.snapshot.effects[.osdLine] != .bool(false)}) else { return }      // the "osd line" menu toggle
        guard announced.insert(text).inserted, let d = try? JSONSerialization.data(withJSONObject: ["command": ["show-text", text, 4000]]),
              let s = String(data: d, encoding: .utf8) else { return }
        send(s)
    }

    private func tick() {
        guard !mediaTransitionPending else { return }
        preferencesDidChange()
        let prefs = renderPrefs ?? prefsReader.refresh(), now = Date.timeIntervalSinceReferenceDate
        if showing == nil { film2D = film() }                      // while a render file plays, the player's path is the render file, not the film
        // Protect the source film even while 3D output is off. A different
        // worker must not evict it during playback. Key hashing stays async.
        let playingKey = film2D.flatMap { CacheKeyMemo.key(path: $0.path) }
        if playingKey != cachePinKey || cachePin == nil {
            cachePin=nil;cachePinKey=playingKey
            if let key=playingKey {cachePin=try? DepthCacheBudget.pin(root:DepthCachePaths.root,key:key)}
        }
        let mapped = playhead()
        // 191o F6 interim: 2D-to-VR180 stays on the flat virtual-screen path until PIN V V6.
        if prefs.mode == "vr180" {revision.invalidate();backTo2D(mapped ?? 0,filmURL:film2D);lastPTS=nil;return}
        // A2: global render prefs and ready-cache callbacks never overrule this film's OUTPUT.
        // Native SOURCE is re-presented directly, never replaced by a depth-converted shot.
        guard let sourceFilm=film2D,
              SourceFormatChoice.output(sourceFilm.path) != "off",
              SourceFormatChoice.output(sourceFilm.path)==prefs.mode,
              StereoSourceGate.shared.route(for:sourceFilm)?.route == .depth else {
            revision.invalidate();backTo2D(mapped ?? 0,filmURL:film2D);lastPTS=nil;return
        }
        shotFrames = mapped.flatMap { p in currentEntry().flatMap { shotIndex($0) }?.shotFrames(pts: p) }
        // rendered files keep film time (rebase-start-time=no), so the player's time-pos IS film time in both modes
        let unavailable = ThreeDPreflight.shared.reason          // no libx265 ffmpeg / no HEVC decode: a saved sbs/vr180 still stays 2D
        if let why = unavailable, prefs.mode != "off" { announce(why) }
        if film2D != lastFilm {
            revision.invalidate();renderPrefs=nil;preferencesDidChange();lastGood=[:]
            if lastFilm != nil { degrade.sourceChanged() }; lastFilm = film2D
        }
        degrade.userMode(on: prefs.mode != "off")
        switch duty.step(rank: ProcessInfo.processInfo.thermalState.rawValue, now: ProcessInfo.processInfo.systemUptime) { case .suspend: degrade.thermal(trip: true); case .resume: degrade.thermal(trip: false); default: break }
        if prefs.mode != "off", degrade.state == "INIT" || degrade.state == "UNAVAILABLE_FLAT", let f = film2D, StereoSourceGate.shared.route(for: f)?.route == .depth {   // an already-3D film never goes through depth: no probe, no "preparing" badge       // source refusals first (HDR/VFR), then the kit outcome
            let k = ThreeDKit.probeState()
            if let s = ThreeDDegradeProbe.sourceEvent(film: f) {
                if !s.isEmpty { degrade.probe(s) }
                else if let e = ThreeDDegradeProbe.kitEvent(missing: k.missing, verified: k.verified, verifyFailed: k.failed, verifying: k.verifying) { degrade.probe(e) }
            }
        }
        if !relaunchChecked, let f = film2D, CacheKeyMemo.key(path: f.path).map({ FileManager.default.fileExists(atPath: DepthCachePaths.root.appendingPathComponent($0).appendingPathComponent("cuts.json").path) }) == true {
            relaunchChecked = true; if degrade.state == "INIT" { degrade.feed("relaunch") }          // cold start with a prepared cache present
        }
        if ThreeDDegradeProbe.takeDiskFull() { diskBlocked = true; degrade.disk(full: true) }
        else if diskBlocked, ThreeDDegradeProbe.headroomOK(at: DepthCachePaths.root) { diskBlocked = false; degrade.disk(full: false) }
        guard prefs.mode != "off", unavailable == nil, let pts = mapped, let filmURL = film2D else { revision.invalidate(); backTo2D(mapped ?? 0, filmURL: film2D); lastPTS = nil; return }
        let seeked = lastPTS.map { abs(pts - $0) > max(2.0, (now - lastTick) * 2.5) } ?? false
        lastPTS = pts; lastTick = now
        if showing != nil { ThreeDSubtitleDepth.shared.refreshPrepared(pts:pts) }
        let playbackDecoders: [String]
        if activeEngine() == .gorav {
            playbackDecoders = goravDecoders() // Actual native admission, not mpv --vd=help.
        } else {
            if decoders == nil { decoders = mpvExecutable().map { RenderedShotMPV.probeDecoders(executable: $0) } ?? [] }
            playbackDecoders = decoders ?? []
        }
        guard let entry = currentEntry(), let index = shotIndex(entry), let hit = index.find(pts: pts), let th = index.thetaH(pts: pts) else {
            if !holdsEncoded(pts) {presentation.update(now:now,covered:false,shot:nil,seeked:seeked,enabled:true);backTo2D(pts,filmURL:filmURL)}
            return
        }
        let expOpts = ThreeDExperimentOptions.live   // 195h r2-2: ONE snapshot per render request, threaded through the mode check, the key, the writer and render()
        if !PrepareSupport.optionsMatch(dzc: hit.depth, options: expOpts) {   // 195h r3-4: this container was prepared in another experiment mode
            ThreeDPrepareRuntime.launcher?.noteModeMismatch(current: expOpts.prepareComponent)   // stop only an old-mode job; the current-mode rebuild is never cancelled by these 250 ms ticks
            if !holdsEncoded(pts) {presentation.update(now:now,covered:false,shot:hit.shot,seeked:seeked,enabled:true);backTo2D(pts,filmURL:filmURL)}
            return
        }
        guard Self.shotReady(entry: entry, shot: hit.shot) else {   // A-D marks it failed (retried by its next chunk): stay 2D, render nothing
            if !holdsEncoded(pts) {presentation.update(now:now,covered:false,shot:hit.shot,seeked:seeked,enabled:true);backTo2D(pts,filmURL:filmURL)}
            return
        }
        let side = readJSON(entry.appendingPathComponent(String(format: "depth_shot_%05d.json", hit.shot))) ?? [:]
        let sh = (side["source_height"] as? Int) ?? (side["depth_height"] as? Int) ?? 0
        let sw0 = (side["source_width"] as? Int) ?? (side["depth_width"] as? Int) ?? 0
        guard sh > 0, let plan = RenderedShotPlan.make(eyeN: Self.eyeN(sourceHeight: sh), decoders: playbackDecoders, swapEyes: true, output: OutputMode.parse(prefs.mode) ?? .fullSBS, srcW: sw0, srcH: sh) else {
            announce("3D: the player has no HEVC/H.264 decoder for this size, staying 2D"); backTo2D(pts, filmURL: filmURL); return
        }
        if !synthTold { synthTold = true; print("3d-synth: \(SynthMethod.current.method.rawValue)"); fflush(stdout); announce(SynthMethod.current.note) }   // 190w W3: the method that actually runs, "fallback" labelled
        let baseKey = Self.key(prefs, eyeN: plan.eyeN, codec: plan.codec, swap: plan.swapEyes, options: expOpts), key = baseKey + Self.depthStamp(entry.appendingPathComponent(String(format: "depth_shot_%05d.dzc", hit.shot)))
        let depthIdentity=entry.path+Self.depthStamp(hit.depth)
        if let previous=observedDepthKeys[hit.shot], depthIdentity != previous {
            // A rewritten depth container invalidates a job even with identical preferences.
            revision.update("depth:"+depthIdentity+String(describing:prefs),now:ProcessInfo.processInfo.systemUptime)
        }
        observedDepthKeys[hit.shot]=depthIdentity
        let out = entry.appendingPathComponent(RenderRevision.fileName(shot:hit.shot,key:key))
        let side2 = out.deletingPathExtension().appendingPathExtension("json")
        let fresh = FileManager.default.fileExists(atPath: out.path) && (readJSON(side2)?["key"] as? String) == key
        let legacy=entry.appendingPathComponent(RenderedShotPlan.fileName(shot:hit.shot))
        let legacySide=legacy.deletingPathExtension().appendingPathExtension("json")
        if lastGood[hit.shot]==nil, FileManager.default.fileExists(atPath:legacy.path),
           let legacyKey=readJSON(legacySide)?["key"] as? String,
           legacyKey==key {
            // Legacy cache is considered only when it has exactly the current key.
            lastGood[hit.shot]=(legacy,prefs)
        }
        let held=RenderContinuity.holds(showing:showing,next:hit.shot,fileExists:showingURL.map {FileManager.default.fileExists(atPath:$0.path)} ?? false)
        let selected=fresh ? (url:out,prefs:prefs):lastGood[hit.shot]
        let available=held || selected.map {FileManager.default.fileExists(atPath:$0.url.path)} == true
        presentation.update(now:now,covered:available,shot:hit.shot,seeked:seeked,enabled:true)
        degrade.observe(covered:available,now:ProcessInfo.processInfo.systemUptime)
        if let selected, FileManager.default.fileExists(atPath:selected.url.path) {
            let candidate=selected.url
            let selectedKey=(readJSON(candidate.deletingPathExtension().appendingPathExtension("json"))?["key"] as? String) ?? "unknown"
            let prefs=selected.prefs // subtitles follow the actually encoded last-good picture
            if RenderContinuity.shouldLoad(showing:showing,next:hit.shot,seeked:seeked,showingURL:showingURL,candidateURL:candidate) {
                if activeEngine() == .gorav {
                    // Publish look/subtitle state only after native commit, never
                    // from intended state or after a stale film/prefs callback.
                    loadPreparedNative(render: candidate, source: filmURL, start: pts) { [weak self] in
                        guard let self else { return }
                        let look = RenderedShotMPV.plannedLook(plan: plan)
                        print("3D-EXPERIMENT applied route=gorav shot=\(hit.shot) fresh=\(fresh) key=\(selectedKey)"); fflush(stdout)
                        self.showing=hit.shot; self.showingURL=candidate; self.collectRetired()
                        if let id=ThreeDStore.shared.snapshot.currentFilm {
                            ThreeDStore.shared.dispatch(.generated(id,look.source,look.output,aspect:look.aspect))
                        }
                        ThreeDShotPlayLog.logShot(shot:hit.shot,pts:pts,menuMode:prefs.mode,key:Self.key(prefs,eyeN:plan.eyeN,codec:plan.codec,swap:plan.swapEyes))
                        let sw=(side["source_width"] as? Int) ?? (side["depth_width"] as? Int) ?? 0
                        let dz=hit.depth
                        ThreeDSubtitleDepth.shared.begin(depth:dz,pts:pts,thetaH:prefs.thetaH(shotThetaH:th,aspect:Double(max(1,sw))/Double(max(1,sh)))) {
                            let raw=prefs.comfortActive(expOpts) ? ShotComfortShot.compute(depth:dz,ipd:prefs.ipdM,options:expOpts,screenDepth:prefs.convergenceM,strength:prefs.depthScale,overBudget:prefs.overBudget) : nil
                            let cf=prefs.deepComfort(raw).map { c -> ShotComfort in var r=c; r.zNear=prefs.comfortZNear(c); return r }
                            return ThreeDSubtitleDepth.params(ipdM:prefs.ipdM,effectiveIPD:prefs.effectiveIPD,convergenceM:prefs.convergenceM,comfort:cf,comfortIPD:cf.map {prefs.comfortIPD($0)})
                        }
                    }
                } else if let cmd = RenderedShotMPV.load(render: candidate, source: filmURL, start: pts) {
                // Load before publishing the generated source, so the old parent
                // frame never receives the new source layout. Only the applier writes routes.
                let look=RenderedShotMPV.plannedLook(plan:plan)
                print("3D-RENDER v1 event=load generation=\(revision.token) shot=\(hit.shot) fresh=\(fresh) key=\(selectedKey)")
                send(cmd); showing = hit.shot; showingURL=candidate;collectRetired()
                MainActor.assumeIsolated {if let id=ThreeDStore.shared.snapshot.currentFilm {ThreeDStore.shared.dispatch(.generated(id,look.source,look.output,aspect:look.aspect))}}
                ThreeDShotPlayLog.logShot(shot: hit.shot, pts: pts, menuMode: prefs.mode, key: Self.key(prefs,eyeN:plan.eyeN,codec:plan.codec,swap:plan.swapEyes))    // X1: one gor3d-shot line per played shot
                // Recognition skips generated files; revision-owned applier routes reject other senders.
                let sw = (side["source_width"] as? Int) ?? (side["depth_width"] as? Int) ?? 0
                let dz = hit.depth
                ThreeDSubtitleDepth.shared.begin(depth: dz, pts: pts, thetaH: prefs.thetaH(shotThetaH: th, aspect: Double(max(1, sw)) / Double(max(1, sh)))) {
                    let raw = prefs.comfortActive(expOpts) ? ShotComfortShot.compute(depth: dz, ipd: prefs.ipdM, options: expOpts, screenDepth: prefs.convergenceM, strength: prefs.depthScale, overBudget: prefs.overBudget) : nil
                    let cf = prefs.deepComfort(raw).map { c -> ShotComfort in var r = c; r.zNear = prefs.comfortZNear(c); return r }      // same values the render of this shot used
                    return ThreeDSubtitleDepth.params(ipdM: prefs.ipdM, effectiveIPD: prefs.effectiveIPD, convergenceM: prefs.convergenceM, comfort: cf, comfortIPD: cf.map { prefs.comfortIPD($0) })
                }
                }
            }
        } else if !held {
            backTo2D(pts, filmURL: filmURL)
        }
        if fresh {remember(shot:hit.shot,url:out,prefs:prefs)}
        // Render current shot first and then forward. Keep displaying the old
        // encoded shot while its replacement is pending; never flash the parent.
        if revision.ready(now:ProcessInfo.processInfo.systemUptime) {
            schedule(index:index,from:hit.shot,prefs:prefs,plan:plan,key:baseKey,th:th,entry:entry,options:expOpts)
        }
    }

    /// CONTRACT-190v s8 as amended by 199h D2 (DISK-LAW): render-ready.json says the shot's depth is ready and its last attempt did not fail
    /// (no source proxy exists any more). Absent or unreadable sidecar
    /// (older cache) = no objection: the file checks in DepthShotIndex.find still apply.
    /// Explicit local-v2 readiness cannot inherit the delivered legacy
    /// missing-sidecar allowance. Durable generation admission is not wired yet.
    enum ReadinessTimeline {case legacyFilmPTS, localV2}
    static func shotReady(entry: URL, shot: Int, timeline: ReadinessTimeline = .legacyFilmPTS) -> Bool {
        if case .localV2 = timeline {return false}
        guard let d = try? Data(contentsOf: entry.appendingPathComponent("render-ready.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let arr = o["shots"] as? [[String: Any]],
              let e = arr.first(where: { ($0["shot"] as? Int) == shot }) else { return true }
        return (e["ready"] as? Bool) == true && (e["failed"] as? Bool) != true
    }

    private func remember(shot: Int, url: URL, prefs: RenderPrefsValue) {
        if let prior=lastGood[shot]?.url,prior != url {retired.insert(prior)}
        lastGood[shot]=(url,prefs);collectRetired()
    }
    private func collectRetired() {
        let retained=Set(lastGood.values.map { $0.url })
        for url in retired where url != showingURL && !retained.contains(url) {
            try? FileManager.default.removeItem(at:url)
            try? FileManager.default.removeItem(at:url.deletingPathExtension().appendingPathExtension("json"))
            retired.remove(url)
        }
    }

    /// A depth re-prepare may temporarily remove coverage metadata. The old
    /// encoded file still covers its original shot; never carry it across a cut.
    private func holdsEncoded(_ pts: Double) -> Bool {
        guard let shot=showing,let url=showingURL,FileManager.default.fileExists(atPath:url.path),
              let index=indexCache?.index,index.shots.indices.contains(shot),index.shots[shot].count==2 else {return false}
        let range=index.shots[shot]
        return pts>=Double(range[0])/index.fps && pts<Double(range[1]+1)/index.fps
    }

    private func backTo2D(_ pts: Double, filmURL: URL?) {
        guard !mediaTransitionPending else { return }
        if activeEngine() == .gorav {
            guard showing != nil, let f=filmURL else { return }
            loadPreparedNative(render:nil,source:f,start:pts) { [weak self] in
                guard let self else { return }
                self.showing=nil; self.showingURL=nil
                ThreeDShotPlayLog.shotEnded(); ThreeDStore.shared.dispatch(.original)
                ThreeDSubtitleDepth.shared.end()
            }
            return
        }
        guard showing != nil, let f = filmURL, let cmd = RenderedShotMPV.load2D(file: f, start: pts) else { return }
        showing = nil; showingURL=nil; ThreeDShotPlayLog.shotEnded(); MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.original)};send(cmd); ThreeDSubtitleDepth.shared.end()
    }

    /// Native multi-source route. No IPC fallback and no duplicate task per tick.
    /// G1 must supply the current session; nil is a visible capability refusal.
    private func loadPreparedNative(render:URL?,source:URL,start:Double,
                                    committed:@escaping @MainActor () -> Void) {
        guard !preparedLoadPending else { return }
        let id=UUID(), token=revision.token, filmID=boundFilmID
        preparedLoadID=id; preparedLoadPending=true
        preparedLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.preparedLoadID==id {
                    self.preparedLoadPending=false; self.preparedLoadTask=nil
                }
            }
            guard self.activeEngine() == .gorav,
                  let player=self.preparedSession() else {
                print("3D-RENDER native refused=multi-source-unavailable")
                return
            }
            do {
                if let render {
                    _ = try await player.loadPreparedShot(render:render,source:source,start:start)
                } else {
                    _ = try await player.loadSource2D(file:source,start:start)
                }
                guard !Task.isCancelled, self.preparedLoadID==id,
                      self.boundFilmID==filmID, self.activeEngine() == .gorav else { return }
                if !self.revision.isCurrent(token) {
                    // A mode/prefs change can land while the video swap awaits.
                    // Restore source before publishing nothing, otherwise the
                    // engine could show a render that gor thinks is still 2D.
                    if render != nil {
                        _ = try await player.loadSource2D(file:source,start:self.playhead() ?? start)
                        guard !Task.isCancelled, self.preparedLoadID==id,
                              self.boundFilmID==filmID else { return }
                        self.showing=nil; self.showingURL=nil
                        ThreeDShotPlayLog.shotEnded(); ThreeDStore.shared.dispatch(.original)
                        ThreeDSubtitleDepth.shared.end()
                    }
                    return
                }
                committed()
            } catch {
                print("3D-RENDER native refused=prepared-load error=\(error)")
            }
        }
    }

    /// Renders the playhead shot first, then the following ones, one at a time (utility queue); a prefs change or mode off cancels the running one.
    private func schedule(index: DepthShotIndex, from first: Int, prefs: RenderPrefsValue, plan: RenderedShotPlan, key baseKey: String, th: Double, entry: URL, options expOpts: ThreeDExperimentOptions) {   // 195h r3-1: the request snapshot arrives with the call
        let token=revision.token
        guard let filmURL = film2D ?? film() else { return }   // 199h D2 (DISK-LAW): the render source is the original film, never a proxy
        for shot in first..<min(first + 3, index.shots.count) where busy[shot] != token {
            let mp4 = entry.appendingPathComponent(String(format: "depth_shot_%05d.dzc", shot))
            guard DZCFile.isComplete(mp4), Self.shotReady(entry: entry, shot: shot) else { continue }   // 199h D2: depth-only readiness
            let key = baseKey + Self.depthStamp(mp4)
            let out = entry.appendingPathComponent(RenderRevision.fileName(shot:shot,key:key)), side2 = out.deletingPathExtension().appendingPathExtension("json")
            if FileManager.default.fileExists(atPath:out.path) {
                if (readJSON(side2)?["key"] as? String)==key {continue}
                // A crash can leave a complete file without its key sidecar.
                // Rebuild that orphan, but never unlink a retained/playing file.
                guard out != showingURL,!lastGood.values.contains(where: {$0.url==out}) else {continue}
                try? FileManager.default.removeItem(at:out)
                try? FileManager.default.removeItem(at:side2)
            }
            let side = readJSON(entry.appendingPathComponent(String(format: "depth_shot_%05d.json", shot))) ?? [:]
            let dsz = ((side["depth_width"] as? Int), (side["depth_height"] as? Int)), ssz = ((side["source_width"] as? Int), (side["source_height"] as? Int))
            let shotTheta=index.thetaH(pts:Double(index.shots[shot][0])/index.fps) ?? th
            busy[shot]=token
            work.async { [weak self] in
                guard let self else { return }
                guard self.revision.isCurrent(token) else {
                    DispatchQueue.main.async {if self.busy[shot]==token {self.busy.removeValue(forKey:shot)}}
                    return
                }
                guard let pin=try? DepthCacheBudget.pin(root:entry.deletingLastPathComponent(),key:entry.lastPathComponent) else {
                    DispatchQueue.main.async { if self.busy[shot]==token {self.busy.removeValue(forKey:shot)};self.announce("3D: cache safety check failed; staying 2D") };return
                }
                defer {withExtendedLifetime(pin) {}}
                let diskWatch=DepthCacheBudget.Watch(root:entry.deletingLastPathComponent())
                guard diskWatch.allowed(force:true) else {
                    DispatchQueue.main.async {if self.busy[shot]==token {self.busy.removeValue(forKey:shot)};self.announce(diskWatch.failure!.description)};return
                }
                print("3D-RENDER v1 event=started generation=\(token) shot=\(shot)")
                if self.writer == nil { self.writer = RenderShotWriter() }
                var ok = false
                var deepMeasurement: ShotComfort.Measurement? = nil
                if let w = self.writer, let dw = dsz.0, let dh = dsz.1 {
                    let sz = (ssz.0 != nil && ssz.1 != nil) ? (w: ssz.0!, h: ssz.1!) : nil
                    let raw = prefs.comfortActive(expOpts) ? ShotComfortShot.compute(depth: mp4, ipd: prefs.ipdM, options: expOpts, screenDepth: prefs.convergenceM, strength: prefs.depthScale, overBudget: prefs.overBudget) : nil
                    deepMeasurement = raw?.measurement
                    let cf = prefs.deepComfort(raw)
                    ok = (try? w.write(film: filmURL, startFrame: index.shots[shot][0], endFrame: index.shots[shot][1], fps: index.fps, firstPTS: index.firstPTS, depth: mp4, depthSize: (dw, dh), sourceSize: sz, thetaH: prefs.thetaH(shotThetaH: shotTheta, aspect: Double(sz?.w ?? dw) / Double(max(1, sz?.h ?? dh))), plan: plan, ipd: cf.map { prefs.comfortIPD($0) } ?? prefs.effectiveIPD,
                                       convergence: cf?.convergenceM ?? prefs.convergenceM, zNear: cf.map { prefs.comfortZNear($0) }, surround: prefs.surroundSoft, options: expOpts.renderOptions, out: out, cancelled: { !self.revision.isCurrent(token) || !diskWatch.allowed() })) != nil
                }
                if ok, let measurement = deepMeasurement {
                    print(measurement.line(shot: shot, model: expOpts.dav2Depth ? "dav2" : "vda", dofOverridden: expOpts.deepVolume && expOpts.depthOfField)); fflush(stdout)
                }
                let published:Bool
                if ok {
                    published=(try? self.revision.commit(token) {
                        try DepthCacheIO.write(JSONSerialization.data(withJSONObject:["key":key]),to:side2)
                    }) ?? false
                } else {published=false}
                print("3D-RENDER v1 event=finished generation=\(token) shot=\(shot) published=\(published) current=\(self.revision.isCurrent(token))")
                if !published && ok {try? FileManager.default.removeItem(at:out);try? FileManager.default.removeItem(at:side2)}
                DispatchQueue.main.async {
                    guard self.revision.isCurrent(token) else {if self.busy[shot]==token {self.busy.removeValue(forKey:shot)};return}
                    if let failure=diskWatch.failure {self.announce(failure.description)}
                    if published {self.remember(shot:shot,url:out,prefs:prefs);self.degrade.shotSucceeded(shot)}
                    else {self.degrade.shotFailed(shot);self.announce("3D: shot \(shot) could not be rendered; keeping available stereo")}
                    if self.busy[shot]==token {self.busy.removeValue(forKey:shot)}
                }
            }
        }
    }

    private func currentEntry() -> URL? {
        guard let p = readJSON(DepthCachePaths.root.appendingPathComponent("current-film.json")), let k = p["cache_key"] as? String else { return nil }
        return DepthCachePaths.root.appendingPathComponent(k, isDirectory: true)
    }
    private func readJSON(_ u: URL) -> [String: Any]? { (try? Data(contentsOf: u)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
}
#endif
// END relocated ThreeDRenderCoordinator.swift
// BEGIN relocated RenderedShotPlan.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190t I (render path): the fixed rules for render_shot_NNNNN.mp4, the Stereo3DRenderer output that mpv plays through the vr180 path.
/// E-G review conditions (1)-(5) are encoded here so the writer and the player setup cannot drift. Pure; nothing here runs mpv or Metal.
struct RenderedShotPlan: Equatable {
    enum Codec: String, Equatable { case hevc, h264 }
    let eyeN: Int                   // (1) each eye is N x N, so render(outW: N, outH: N) into an sbsOut of 2N x N
    let codec: Codec
    let swapEyes: Bool              // (2) vr_swap_eyes == 1.0 (the default): passed to Stereo3DRenderer.render(swapEyes:), positive ipd
    var output: OutputMode = .vr180 // s36: vr180 (N x N eyes) or a flat mode (eyes at the source size srcW x srcH)
    var srcW = 0, srcH = 0
    var canvas: (w: Int, h: Int) { output.isFlat ? output.canvasSize(srcW: srcW, srcH: srcH) : (eyeN * 2, eyeN) }
    var sbsWidth: Int { canvas.w }
    /// Player projection for the rendered file: vr180 stays vr180; flat modes use the existing flat packings (sbs, tb) with the per-eye aspect (half_sbs: the squeezed halves stretch back to srcW/srcH);
    /// anaglyph is one ordinary 2D picture (nil = no stereo look setup).
    var lookProjection: (kind: String, eyeAspect: Double)? {
        let a = srcH > 0 ? Double(srcW) / Double(srcH) : 0
        switch output { case .vr180: return (RenderedShotPlan.projectionKind, 0); case .fullSBS, .halfSBS: return ("flat-sbs", a); case .overUnder: return ("flat-tb", a); case .anaglyph: return nil }
    }
    static let h264MaxWidth = 4096

    /// (4) `decoders` = names from mpv's `decoder-list` property of the PLAYER mpv. HEVC when present. H.264 only when HEVC is
    /// missing AND the width fits 4096; otherwise nil (render nothing and say so on the OSD, never a silent downgrade).
    /// `swapEyes` mirrors the live vr_swap_eyes parameter (default true).
    static func make(eyeN: Int, decoders: [String], swapEyes: Bool = true, output: OutputMode = .vr180, srcW: Int = 0, srcH: Int = 0) -> RenderedShotPlan? {
        guard eyeN >= 256, eyeN % 2 == 0, !output.isFlat || (srcW >= 2 && srcH >= 2 && srcW % 2 == 0) else { return nil }
        let have = Set(decoders.map { $0.lowercased() })
        let hevc = RenderedShotPlan(eyeN: eyeN, codec: .hevc, swapEyes: swapEyes, output: output, srcW: srcW, srcH: srcH)
        if have.contains("hevc") { return hevc }
        if have.contains("h264"), hevc.canvas.w <= h264MaxWidth { return RenderedShotPlan(eyeN: eyeN, codec: .h264, swapEyes: swapEyes, output: output, srcW: srcW, srcH: srcH) }
        return nil
    }

    /// Eye offset to pass as Stereo3DRenderer.render(ipd:): always positive (RenderPrefsValue.effectiveIPD); eye order is `swapEyes`.
    func ipd(effective: Double) -> Double { abs(effective) }

    /// (3) Rendered files are already stereo and full frame: projection "vr180" (never flat-2d3d, no synthetic disparity twice),
    /// no menu crop (crop 1,1) and the full source-eye rectangle, so CropAcceptPolicy has nothing to cut.
    static let projectionKind = "vr180"
    static let menuCrop = (x: 1.0, y: 1.0)
    static let sourceEyeCrop = (x: 0.0, y: 0.0, w: 1.0, h: 1.0)

    /// (5) Timing: the video packets carry FILM time (PTS = source PTS of the frame), audio is never in the render file: mpv keeps the
    /// source audio track (audio-file / the original), so a seek inside the rendered range moves both from the same film time.
    static let ptsIsFilmTime = true, carriesAudio = false
    static func fileName(shot: Int) -> String { String(format: "render_shot_%05d.mp4", shot) }
}
// END relocated RenderedShotPlan.swift
// BEGIN relocated RenderedShotMPV.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190t I: the player-side messages for render_shot files, as plain JSON lines. This file only BUILDS and PARSES text; the caller sends
/// them over the existing player socket (the one call-site that owns that socket is the wiring step, not done here).
enum RenderedShotMPV {
    /// Preserve delivered film-PTS command routing. This legacy route does not
    /// support new local-v2 generated media, even with a parsed map elsewhere.
    enum Timeline {case legacyFilmPTS, localV2}
    /// E-G condition 4: which decoders the PLAYER mpv has. Runs `<mpv> --vd=help` (no socket) and keeps the names hevc / h264 when they appear as
    /// whole words (hevc_videotoolbox alone does not count: only a software or hwdec-independent hevc decoder entry does). Empty when it cannot run.
    static func probeDecoders(executable: URL) -> [String] {
        let p = Process(); p.executableURL = executable; p.arguments = ["--no-config", "--vd=help"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        guard (try? p.run()) != nil else { print("gor3d-decoder-probe v1 launch_failed executable=\(executable.path)"); return [] }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) { if p.isRunning { p.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let found = decoders(helpText: String(decoding: data, as: UTF8.self))
        print("gor3d-decoder-probe v1 rc=\(p.terminationStatus) bytes=\(data.count) decoders=\(found.joined(separator: ",")) executable=\(executable.path)")
        return found
    }

    static func decoders(helpText: String) -> [String] {
        ["hevc", "h264"].filter { name in
            helpText.range(of: "(^|[^A-Za-z0-9_])\(name)([^A-Za-z0-9_]|$)", options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func line(_ cmd: [Any]) -> String? {
        (try? JSONSerialization.data(withJSONObject: ["command": cmd])).flatMap { String(data: $0, encoding: .utf8) }
    }

    struct Look: Equatable {let source:ThreeDSource;let output:ThreeDOutput;let aspect:Double}
    /// No player messages: the store applier is the only route writer.
    static func plannedLook(plan: RenderedShotPlan) -> Look {
        let source=ThreeDSource(plan.output == .vr180 ? .vr180SBS : (plan.output == .overUnder ? .tbFull : (plan.output == .anaglyph ? .flat2D:.sbsFull)))
        return Look(source:source,output:ThreeDOutput(rawValue:plan.output.rawValue) ?? .off,aspect:plan.lookProjection?.eyeAspect ?? 0)
    }

    /// (5) Play the render file from film time `start`. rebase-start-time=no keeps the file's own timestamps (= film time), so time-pos stays film time
    /// and the source audio (which starts at film 0) lines up; the render file carries no audio. The loadfile index argument is -1 (mpv 0.38+); not run here.
    static func load(render: URL, source: URL, start: Double, timeline: Timeline = .legacyFilmPTS) -> String? {
        if case .localV2 = timeline {return nil}
        let opts = "start=\(String(format: "%.3f", start)),rebase-start-time=no,audio-file=\(source.path)"
        return line(["loadfile", render.path, "replace", -1, opts])
    }

    /// Back to the 2D film at film time `start` (its own audio, no audio-file option).
    static func load2D(file: URL, start: Double) -> String? {
        line(["loadfile", file.path, "replace", -1, "start=\(String(format: "%.3f", start))"])
    }
}
// END relocated RenderedShotMPV.swift
// BEGIN relocated RenderShotWriter.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AVFoundation) && canImport(Metal) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
import Metal

/// 190t I, amended 199h D2 (DISK-LAW): writes render_shot_NNNNN.mp4 for one prepared shot. Source frames come from the ORIGINAL film by frame
/// index (AVAssetReader over the shot's PTS window); a container AVAssetReader cannot open (MKV) is read through exactly one transient stream-copy
/// shot (vendored ffmpeg -c copy -copyts, deleted on every exit of write(), never persistent; no persistent source_shot exists). depth_shot_NNNNN.dzc (DepthFrameReader, s16 lossless),
/// thetaH from DepthShotIndex. A depth box smaller than the source (s22 letterbox) is bilinearly resampled to the source size (DepthUpsampler); the source is never resampled. Each frame: depth luma -> metric Z (decodeDepth, shift 0) -> crop to the sidecar size -> Stereo3DRenderer.render
/// -> 2N x N SBS -> HEVC/H.264 packets stamped with the SOURCE film PTS. No audio is written. Frames pair by order inside the shot
/// and the pair's PTS must agree within half a frame; any mismatch or resource failure aborts and removes the partial file (never a silent skip).
/// Not run on a Mac: the BGRA/RGBA channel order, VT behaviour and speed are unmeasured.
final class RenderShotWriter {
    enum Failure: Error { case open, size, depth, render, write, pairing }
    private let device: MTLDevice, renderer: Stereo3DRenderer

    init?(renderer: Stereo3DRenderer? = Stereo3DRenderer.make()) {
        guard let r = renderer, let d = MTLCreateSystemDefaultDevice() else { return nil }
        self.renderer = r; device = d
    }

    /// 199h D2 (DISK-LAW): for a container AVAssetReader cannot open (MKV), exactly one transient stream-copy shot of the shot's PTS range
    /// (vendored ffmpeg, stream copy, original timestamps kept). The caller deletes the file on every exit; it never enters the managed cache.
    /// A codec AV cannot decode after the remux fails closed (the shot stays 2D). UNRUN on a Mac: -ss keyframe alignment and annexb conversion unmeasured.
    private static func transientShotCopy(film: URL, to out: URL, startPTS: Double, endPTS: Double, timeout: Double = 120, cancelled: () -> Bool = { false }) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: GORResources.vendorPath("ffmpeg/bin/ffmpeg"))
        p.arguments = ["-hide_banner", "-loglevel", "error", "-ss", String(startPTS), "-i", film.path,
                       "-t", String((endPTS - startPTS) + 1.0 / 24.0), "-c", "copy", "-copyts", "-y", out.path]
        let err = Pipe(); p.standardError = err
        // stderr drains on its own handler: availableData blocks until data or EOF, so it cannot sit in the poll loop; a chatty child never blocks on a full pipe.
        err.fileHandleForReading.readabilityHandler = { h in _ = h.availableData }
        do { try p.run() } catch { err.fileHandleForReading.readabilityHandler = nil; return false }
        setpgid(p.processIdentifier, p.processIdentifier)   // own process group: cancel/timeout kills the whole tree, descendants included
        let deadline = Date().addingTimeInterval(timeout)   // a hung ffmpeg never outlives the render it serves
        while p.isRunning {
            // On cancel/timeout: SIGTERM the direct child AND its process group (a group-kill alone can lose the setpgid/exec race), a short grace, then SIGKILL both.
            if cancelled() || Date() > deadline {
                p.terminate()
                killpg(p.processIdentifier, SIGTERM)
                let grace = Date().addingTimeInterval(2)
                while p.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.05) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL); killpg(p.processIdentifier, SIGKILL) }
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // Bounded return without relying on pipe EOF: a descendant holding the stderr write end open must not delay the helper.
        err.fileHandleForReading.readabilityHandler = nil
        try? err.fileHandleForReading.close()
        p.waitUntilExit()
        guard p.terminationReason == .exit, p.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) else {
            try? FileManager.default.removeItem(at: out); return false
        }
        return true
    }

    /// `depthSize`: sidecar depth_width/depth_height and `sourceSize`: source_width/source_height (both unpadded; nil = the buffer size).
    /// Both pictures are cropped (top-left blit, no resampling) to that size and must then agree. Returns the output URL; throws and deletes on failure.
    /// 199h D2: `film` is the original film; the shot is addressed by frame range + fps + the film's first PTS (fov_track.json fps/first_pts).
    func write(film: URL, startFrame: Int, endFrame: Int, fps: Double, firstPTS: Double, depth: URL, depthSize: (w: Int, h: Int)?, sourceSize: (w: Int, h: Int)? = nil, thetaH: Double, plan: RenderedShotPlan, ipd: Double,
               convergence: Double?, zNear: Double? = nil, surround: Bool = true, options: ThreeDExperimentOptions = .live, out: URL, cancelled: () -> Bool = { false }) throws -> URL {
        // Encode privately. Never unlink a currently playing last-good file.
        let destination=out
        let out=out.deletingLastPathComponent().appendingPathComponent(".render-"+UUID().uuidString+".mp4")
        defer {try? FileManager.default.removeItem(at:out)}
        guard let fpsR = ShotEncoding.fpsRational(fps), endFrame >= startFrame else { throw Failure.open }
        let t0 = ShotEncoding.pts(frame: startFrame, fps: fpsR)
        let shotFrames = endFrame - startFrame + 1
        let filmStart = firstPTS + Double(startFrame) / fps, filmEnd = firstPTS + Double(endFrame + 1) / fps
        var asset = AVURLAsset(url: film), transient: URL? = nil
        defer { if let t = transient { try? FileManager.default.removeItem(at: t) } }   // armed before any copy runs; a missing file is a no-op
        if asset.tracks(withMediaType: .video).isEmpty {
            // 199h D2: exactly one transient stream-copy shot for this container, deleted on every exit (success AND failure).
            let t = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("gor3d-shot-" + UUID().uuidString + ".mp4")
            transient = t   // armed before the copy runs
            guard Self.transientShotCopy(film: film, to: t, startPTS: filmStart, endPTS: filmEnd, cancelled: cancelled) else { throw Failure.open }
            asset = AVURLAsset(url: t)
        }
        guard let track = asset.tracks(withMediaType: .video).first, let sr = try? AVAssetReader(asset: asset),
              let dr = DepthFrameReader(url: depth, device: device) else { throw Failure.open }
        if transient == nil {
            sr.timeRange = CMTimeRange(start: CMTime(seconds: filmStart, preferredTimescale: 600),
                                       duration: CMTime(seconds: (filmEnd - filmStart) + 0.5 / fps, preferredTimescale: 600))
        }
        let so = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                                       kCVPixelBufferMetalCompatibilityKey as String: true])
        guard sr.canAdd(so) else { throw Failure.open }
        sr.add(so)
        guard sr.startReading() else { throw Failure.open }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else { throw Failure.open }

        let n = plan.eyeN, w2 = plan.canvas.w, h2 = plan.canvas.h, flat = plan.output.isFlat
        guard let sbs = Stereo3DRenderer.texture(device, .rgba8Unorm, w2, h2),
              let movie=DepthBoundedMovie(url:out,start:CMTime(value: t0.value, timescale: t0.scale)) else {throw Failure.open}   // 199h D2: the shot's deterministic PTS space, as the proxy carried it
        let writer=movie.writer
        defer {movie.cancel()}
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: plan.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264, AVVideoWidthKey: w2, AVVideoHeightKey: h2,
            // review: with no compression properties AVAssetWriter picks its own (low) default bitrate for a 2x-wide canvas; same quality key the prepare encoder (VTShotEncoder) uses. UNCOMPILED on a Mac; real bitrate unmeasured.
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.9]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w2, kCVPixelBufferHeightKey as String: h2])
        guard writer.canAdd(input) else { throw Failure.open }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.write }
        guard let up = DepthUpsampler(device: device, queue: renderer.queue) else { throw Failure.open }
        var started = false, completedFrames = 0
        var firstOutputPTS=Double.nan,lastOutputPTS=Double.nan
        let totalFrames = shotFrames   // 199h D2: the shot's frame count, not a container-duration estimate
        ThreeDStageLog.progress("stereo-synthesis-" + plan.output.rawValue, done: 0, total: totalFrames)
        func fail(_ f: Failure) -> Failure { sr.cancelReading(); dr.cancel(); movie.cancel(); try? FileManager.default.removeItem(at: out); return f }

        while completedFrames < shotFrames, let sb = so.copyNextSampleBuffer() {   // 199h D2: the frame count terminates the loop, not reader exhaustion
            if cancelled() { throw fail(.write) }
            let sampleKind=DepthBoundedMovie.sampleKind(sb)
            guard sampleKind>=0 else {throw fail(.open)}
            if sampleKind==0 {continue} // No picture: do not consume a depth frame.
            // 199h D2: a transient copy can lead in from an earlier keyframe; pre-shot samples are skipped and consume no depth frame.
            if CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)) < filmStart - 0.5 / fps { continue }
            guard let sp = CMSampleBufferGetImageBuffer(sb), let df = dr.next(), df.rangeOK else { throw fail(.depth) }
            let t = ShotEncoding.pts(frame: startFrame + completedFrames, fps: fpsR)   // 199h D2: deterministic shot PTS, the space the proxy encoded and playback maps
            let pts = CMTime(value: t.value, timescale: t.scale)
            // 199h D2 (review 1c03e912): the REAL source PTS must agree with the expected film PTS of this frame: a lost, duplicated or
            // late source frame fails here, and a wrong first_pts (pre-D2 cache) fails closed. Output stamping stays the deterministic t above.
            let srcPTS = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb)), expPTS = filmStart + Double(completedFrames) / fps
            guard srcPTS.isFinite, expPTS.isFinite, abs(srcPTS - expPTS) <= 0.5 / 24.0 else { throw fail(.pairing) }   // non-finite fails closed: abs(NaN) > tol is false
            let depthDelta = df.pts - CMTimeGetSeconds(pts)
            guard depthDelta.isFinite, abs(depthDelta) <= 0.5 / 24.0 else { throw fail(.pairing) }   // half a frame at 24 fps; tighter than any cut
            let dw = depthSize?.w ?? df.width, dh = depthSize?.h ?? df.height
            let fw = sourceSize?.w ?? CVPixelBufferGetWidth(sp), fh = sourceSize?.h ?? CVPixelBufferGetHeight(sp)
            // the depth box (sidecar depth_width x depth_height, the letterbox box the native prepare stores) may be smaller than the source picture: same aspect, resampled up below
            guard DepthUpsampleKernel.compatible(depth: (dw, dh), source: (fw, fh)), dw <= df.width, dh <= df.height, fw <= CVPixelBufferGetWidth(sp), fh <= CVPixelBufferGetHeight(sp) else { throw fail(.size) }
            var ft: CVMetalTexture?
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, sp, nil, .bgra8Unorm, CVPixelBufferGetWidth(sp), CVPixelBufferGetHeight(sp), 0, &ft) == kCVReturnSuccess,
                  let padded = ft.flatMap({ CVMetalTextureGetTexture($0) }),
                  let ftex = Stereo3DRenderer.texture(device, .bgra8Unorm, fw, fh),
                  let full = Stereo3DRenderer.texture(device, .r32Float, df.width, df.height),
                  let box = Stereo3DRenderer.texture(device, .r32Float, dw, dh),
                  let metric = (dw == fw && dh == fh) ? box : Stereo3DRenderer.texture(device, .r32Float, fw, fh),
                  dr.decode(df, into: full, renderer: renderer) else { throw fail(.depth) }
            guard crop(full, to: box), (dw == fw && dh == fh) || up.resample(box, into: metric), withExtendedLifetime(ft, { crop(padded, to: ftex) }), renderer.render(frame: ftex, depth: metric, thetaH: thetaH, ipd: plan.ipd(effective: ipd), convergence: convergence, zNear: zNear, swapEyes: plan.swapEyes, surround: surround, outW: flat ? fw : n, outH: flat ? fh : n, sbsOut: sbs, output: plan.output, options: options) else { throw fail(.render) }   // options: one snapshot for the whole shot (review r4)
            while !input.isReadyForMoreMediaData {                                  // review: a failed/cancelled writer never becomes ready again: bail out instead of spinning forever
                if cancelled() || movie.failed || writer.status != .writing { throw fail(.write) }
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard !movie.failed, let pool = adaptor.pixelBufferPool else { throw fail(.write) }
            var pb: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let out_pb = pb, copy(sbs, into: out_pb) else { throw fail(.write) }
            if !started { writer.startSession(atSourceTime: .zero); started = true } // Keep global source PTS in the asset timeline.
            guard adaptor.append(out_pb, withPresentationTime: pts) else { throw fail(.write) }
            if completedFrames==0 {firstOutputPTS=pts.seconds};lastOutputPTS=pts.seconds
            completedFrames += 1; ThreeDStageLog.progress("stereo-synthesis-" + plan.output.rawValue, done: completedFrames, total: totalFrames)
        }
        // 199h D2: a short source fails the shot; trailing samples past the shot are ignored by the frame-count loop above.
        sr.cancelReading()
        guard completedFrames == shotFrames else { throw fail(.open) }
        input.markAsFinished()
        let g = DispatchGroup(); g.enter(); writer.finishWriting { g.leave() }
        while g.wait(timeout:.now()+0.1) == .timedOut {if cancelled() {throw fail(.write)}}
        guard movie.finish(), writer.status == .completed else { throw fail(.write) }
        SphericalTag.apply(to: out, plan: plan)          // s36: vr180 container tag, flag gor.3d.sphericalTag (default OFF); any failure leaves the untagged file
        guard !cancelled(),DepthBoundedMovie.verify(url:out,size:(w2,h2),frames:completedFrames,first:firstOutputPTS,last:lastOutputPTS) else {throw fail(.write)}
        // Same-directory rename exposes only a complete encoded file. An existing
        // key-bearing destination stays intact rather than being overwritten.
        try FileManager.default.moveItem(at:out,to:destination)
        return destination
    }

    /// Top-left crop of a padded picture to the sidecar size (blit, no resampling).
    private func crop(_ src: MTLTexture, to dst: MTLTexture) -> Bool {
        guard src.width >= dst.width, src.height >= dst.height, let cb = renderer.queue.makeCommandBuffer(), let b = cb.makeBlitCommandEncoder() else { return false }
        b.copy(from: src, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: dst.width, height: dst.height, depth: 1),
               to: dst, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        b.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        return cb.status == .completed
    }

    /// rgba8 SBS texture -> BGRA pixel buffer (CPU swizzle: slow, correct; a GPU view is a later optimisation).
    private func copy(_ tex: MTLTexture, into pb: CVPixelBuffer) -> Bool {
        let w = tex.width, h = tex.height
        guard let staging = device.makeBuffer(length: w * h * 4, options: .storageModeShared), let cb = renderer.queue.makeCommandBuffer(), let b = cb.makeBlitCommandEncoder() else { return false }
        b.copy(from: tex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: w, height: h, depth: 1),
               to: staging, destinationOffset: 0, destinationBytesPerRow: w * 4, destinationBytesPerImage: w * h * 4)
        b.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        guard cb.status == .completed else { return false }
        CVPixelBufferLockBaseAddress(pb, []); defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let bpr = CVPixelBufferGetBytesPerRow(pb), src = staging.contents().assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            let s = src + y * w * 4, d = base.assumingMemoryBound(to: UInt8.self) + y * bpr
            for x in 0..<w { d[x * 4] = s[x * 4 + 2]; d[x * 4 + 1] = s[x * 4 + 1]; d[x * 4 + 2] = s[x * 4]; d[x * 4 + 3] = s[x * 4 + 3] }
        }
        return true
    }
}
#endif
// END relocated RenderShotWriter.swift
// BEGIN relocated VTShotEncoder.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AVFoundation) && canImport(CoreVideo) && canImport(VideoToolbox)
import AVFoundation
import CoreVideo
import VideoToolbox
#endif

/// 190t A: in-app HEVC Main 10 writer for source_shot_NNNNN.mp4 (CONTRACT-190v s9 source proxy), replacing the libx265 ffmpeg of the Linux/reference
/// 199h D2 (DISK-LAW): no caller remains - the persistent proxy is gone. Retained dead (accepted default D-b); removal is a separate change.
/// path. SOURCE PROXY ONLY: the depth cache moves to a lossless per-shot container (parent decision 07:35), so there is deliberately no depth encoder here. Pure rules first (fps as an exact rational, even padding, the 10-bit word packing, the hvcC profile
/// read) so they have Python models; the AVAssetWriter part is below and has NOT been compiled or run on a Mac.
/// The proxy is lossy by design (x265 crf 10 in the reference); VT runs at maximum quality. Not measured against the reference on a Mac.
enum ShotEncoding {
    static func evenSize(_ w: Int, _ h: Int) -> (w: Int, h: Int) { (w + (w & 1), h + (h & 1)) }

    /// fps as an exact rational so frame * den / num == frame / fps with no drift (23.976 = 24000/1001, ...); other rates to 0.001.
    static func fpsRational(_ fps: Double) -> (num: Int32, den: Int32)? {
        guard fps.isFinite, fps > 0, fps <= 1000 else { return nil }
        for (n, d) in [(24000, 1001), (30000, 1001), (48000, 1001), (60000, 1001), (120000, 1001)] where abs(fps - Double(n) / Double(d)) < 0.002 { return (Int32(n), Int32(d)) }
        let r = fps.rounded()
        if abs(fps - r) < 0.002 { return (Int32(r), 1) }
        return (Int32((fps * 1000).rounded()), 1000)
    }
    /// Container PTS of film frame `frame` as CMTime(value, timescale): frame * den / num seconds.
    static func pts(frame: Int, fps: (num: Int32, den: Int32)) -> (value: Int64, scale: Int32) { (Int64(frame) * Int64(fps.den), fps.num) }

    /// 10-bit sample in a 16-bit word, MSB-aligned (shift 6): what the 10-bit biplanar formats store. Neutral chroma 512 -> 0x8000.
    static func word(_ v10: UInt16) -> UInt16 { min(v10, 1023) << 6 }
    static let neutralChromaWord: UInt16 = 512 << 6
    /// Black bottom-right padding of the source proxy: video range luma 64, full range 0 (10-bit).
    static func blackLumaWord(fullRange: Bool) -> UInt16 { fullRange ? 0 : 64 << 6 }
    /// Edge replication index for depth padding (same as prepare_film._pad_even).
    static func clampIndex(_ i: Int, _ n: Int) -> Int { min(i, n - 1) }

    /// hvcC general_profile_idc (byte 1, low 5 bits): 2 = Main 10.
    static func hvccIsMain10(_ hvcc: [UInt8]) -> Bool { hvcc.count > 1 && (hvcc[1] & 0x1F) == 2 }
}

#if canImport(AVFoundation) && canImport(CoreVideo) && canImport(VideoToolbox)
final class VTShotEncoder {
    private let writer: AVAssetWriter, input: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let boundedMovie:DepthBoundedMovie
    private let tmp: URL, dest: URL, fullRange: Bool
    private let fps: (num: Int32, den: Int32), startFrame: Int
    let width: Int, height: Int, padded: (w: Int, h: Int)
    private var written = 0, failed = false
    private let captureFixtureSegments:Bool
    private(set) var diagnosticAppendedPTS:[Double]=[]
    var diagnosticSegments:[Data]? {boundedMovie.diagnosticSegments}


    /// `width`/`height` = the unpadded picture size (also what the sidecar json records). `colorProperties` = the source's own AVVideoColorProperties
    /// dictionary (nil = untagged proxy: no forcing, a forced bt709 tag shifts colours on SD/untagged sources).
    init?(url: URL, width: Int, height: Int, fps: Double, startFrame: Int, sourceFullRange: Bool = false, colorProperties: [String: String]? = nil, captureFixtureSegments:Bool=false) {
        guard width > 0, height > 0, let r = ShotEncoding.fpsRational(fps) else { return nil }
        let e = ShotEncoding.evenSize(width, height)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-" + url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        let t0 = ShotEncoding.pts(frame: startFrame, fps: r)
        guard let movie=DepthBoundedMovie(url:tmp,start:CMTime(value:t0.value,timescale:t0.scale),captureFixtureSegments:captureFixtureSegments) else {return nil}
        let w=movie.writer
        let comp: [String: Any] = [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String, AVVideoQualityKey: 1.0,
                                   AVVideoAllowFrameReorderingKey: false, AVVideoExpectedSourceFrameRateKey: fps]
        var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: e.w, AVVideoHeightKey: e.h, AVVideoCompressionPropertiesKey: comp]
        if let c = colorProperties { settings[AVVideoColorPropertiesKey] = c }
        let fr = sourceFullRange
        let fmt = fr ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        inp.expectsMediaDataInRealTime = false
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: fmt, kCVPixelBufferWidthKey as String: e.w, kCVPixelBufferHeightKey as String: e.h])
        guard w.canAdd(inp) else { return nil }
        w.add(inp)
        guard w.startWriting() else { return nil }
        // Session mapping is movieTime = sourceTime - sessionStart.
        // Appended source times stay global; initialSegmentStartTime stays t0.
        w.startSession(atSourceTime: .zero)
        self.captureFixtureSegments=captureFixtureSegments
        writer = w; boundedMovie=movie; input = inp; adaptor = ad; self.tmp = tmp; dest = url; fullRange = fr; self.fps = r; self.startFrame = startFrame
        self.width = width; self.height = height; padded = e
    }

    private func pixelBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess else { return nil }
        return pb
    }
    private func submit(_ pb: CVPixelBuffer, cancelled: () -> Bool) -> Bool {
        var waited = 0.0
        while !input.isReadyForMoreMediaData {
            if cancelled() || failed || boundedMovie.failed || writer.status == .failed || waited > 60 { failed = true; return false }
            Thread.sleep(forTimeInterval: 0.002); waited += 0.002
        }
        guard !boundedMovie.failed else {failed=true;return false}
        let t = ShotEncoding.pts(frame: startFrame + written, fps: fps)
        guard adaptor.append(pb, withPresentationTime: CMTime(value: t.value, timescale: t.scale)) else { failed = true; return false }
        if captureFixtureSegments,diagnosticAppendedPTS.count<64 {
            diagnosticAppendedPTS.append(CMTime(value:t.value,timescale:t.scale).seconds)
        }
        written += 1; return true
    }

    /// Source proxy: `buffer` = a 10-bit 4:2:0 biplanar picture of the unpadded size (same range as `sourceFullRange`). Padded black bottom-right.
    func appendSource(_ buffer: CVPixelBuffer, cancelled: () -> Bool = { false }) -> Bool {
        guard !failed, CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
              CVPixelBufferGetPixelFormatType(buffer) == (fullRange ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
              let pb = pixelBuffer() else { failed = true; return false }
        CVPixelBufferLockBaseAddress(buffer, .readOnly); CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []); CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        for plane in 0..<2 {
            guard let s = CVPixelBufferGetBaseAddressOfPlane(buffer, plane), let d = CVPixelBufferGetBaseAddressOfPlane(pb, plane) else { failed = true; return false }
            let ss = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane), ds = CVPixelBufferGetBytesPerRowOfPlane(pb, plane)
            let rows = plane == 0 ? padded.h : padded.h / 2, srcRows = plane == 0 ? height : height / 2 + (height & 1)
            let words = plane == 0 ? padded.w : padded.w, srcWords = plane == 0 ? width : (width + (width & 1))
            let fill = plane == 0 ? ShotEncoding.blackLumaWord(fullRange: fullRange) : ShotEncoding.neutralChromaWord
            for j in 0..<rows {
                let dr = d.advanced(by: j * ds).assumingMemoryBound(to: UInt16.self)
                if j < srcRows {
                    let sr = s.advanced(by: j * ss).assumingMemoryBound(to: UInt16.self)
                    for i in 0..<words { dr[i] = i < srcWords ? sr[i] : fill }
                } else { for i in 0..<words { dr[i] = fill } }
            }
        }
        return submit(pb, cancelled: cancelled)
    }

    /// Finishes, moves the file into place and checks the CONTRACT s9 properties. Returns nil when the file is good, else the reason (file removed).
    func finish() -> String? {
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        let deadline=Date().addingTimeInterval(60)
        while sem.wait(timeout:.now()+0.1) == .timedOut {
            if boundedMovie.failed || Date()>deadline {boundedMovie.cancel();failed=true;return "bounded encoder finalization failed"}
        }
        guard boundedMovie.finish(), !failed, writer.status == .completed, written > 0 else { try? FileManager.default.removeItem(at: tmp); return "encoder failed (\(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)"))" }
        let rate=Double(fps.num)/Double(fps.den),start=Double(startFrame)/(Double(fps.num)/Double(fps.den))
        guard DepthBoundedMovie.verify(url:tmp,size:padded,frames:written,first:start,last:start+Double(written-1)/rate,segment:boundedMovie.verificationSegmentSummary) else {try? FileManager.default.removeItem(at:tmp);return "fragmented source proxy timeline verification failed"}
        if let why=Self.verify(url:tmp,expectedSize:padded,expectedStart:start,frames:written) {try? FileManager.default.removeItem(at:tmp);return why}
        guard rename(tmp.path,dest.path)==0 else {return "could not atomically publish the source proxy"}
        return nil
    }
    func cancel() { boundedMovie.cancel(); try? FileManager.default.removeItem(at: tmp); failed = true }

    /// Reads the file back: HEVC, Main 10 (hvcC), padded size, first PTS = start/fps. nil = good. Unverified on a Mac.
    static func verify(url: URL, expectedSize: (w: Int, h: Int), expectedStart: Double, frames: Int) -> String? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first, let fd = track.formatDescriptions.first else { return "no video track" }
        let f = fd as! CMFormatDescription
        guard CMFormatDescriptionGetMediaSubType(f) == kCMVideoCodecType_HEVC else { return "not HEVC" }
        let dim = CMVideoFormatDescriptionGetDimensions(f)
        guard Int(dim.width) == expectedSize.w, Int(dim.height) == expectedSize.h else { return "size \(dim.width)x\(dim.height) != \(expectedSize.w)x\(expectedSize.h)" }
        let ext = CMFormatDescriptionGetExtensions(f) as? [String: Any] ?? [:]
        if let atoms = ext[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any], let hv = atoms["hvcC"] as? Data {
            guard ShotEncoding.hvccIsMain10([UInt8](hv)) else { return "not HEVC Main 10" }
        } else { return "no hvcC" }
        guard let r = try? AVAssetReader(asset: asset) else { return "cannot read back" }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard r.canAdd(out) else { return "cannot read back" }
        r.add(out)
        guard r.startReading() else {return "cannot start read back"}
        defer {r.cancelReading()}
        while let sb=out.copyNextSampleBuffer() {
            let kind=DepthBoundedMovie.sampleKind(sb)
            guard kind>=0 else {return "invalid first media sample"}
            if kind==0 {continue}
            let t=CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            return abs(t-expectedStart)<0.0005 ? nil : "first PTS \(t) != \(expectedStart)"
        }
        return "no first media sample"
    }
}
#endif
// END relocated VTShotEncoder.swift
// BEGIN relocated PreparedShotPlayback.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// P26: gor's prepared-shot path, separate from RenderedShotMPV. The backend
/// implements these operations on its ONE multi-source session. No IPC/MPV
/// command string, timestamp rebase, or implicit restart of source audio.
@MainActor
protocol PreparedShotSessionBackend: AnyObject {
    /// Return only after the operation is committed. On failure the backend must
    /// stop the incomplete operation or mark its session unusable, never silently
    /// fall back to another engine. Gor will invalidate its local receipt state.
    func applyPreparedShot(_ request: PreparedShotPlayback.Request) async throws
        -> PreparedShotPlayback.Receipt
}

@MainActor
final class PreparedShotPlayback {
    enum Failure: Error, Equatable {
        case invalidFilmTime
        case notLocalFile
        case noSourceSession
        case sourceAudioChanged
        case operationInFlight
        case sessionInvalidated
        case receiptMismatch
        case timelineMigrationRequired
    }

    /// Legacy is unchanged. New local-v2 callers must identify their format;
    /// absence of a parsed map never turns a local request into legacy.
    enum Timeline {
        case legacyFilmPTS
        case localV2(ShotTimelineMap?)
    }

    enum Operation: Equatable {
        /// Adopt an already-running source video/audio pair, then swap video.
        /// Never starts or restarts audio. Idle/separate initial audio refuses.
        case adoptRunningSource
        /// Keep the running audio decoder/device/clock. Replace video only.
        case replaceVideo
        /// Return to source film video, preserving that same source audio.
        case returnToSource
    }

    struct Request: Equatable {
        let sessionID: UUID
        let operationID: UUID
        let operation: Operation
        let videoURL: URL
        let sourceAudioURL: URL
        /// Absolute source-film time. NEVER clip-relative time.
        let filmTime: Double
        /// Always false: rendered files already carry source-film timestamps.
        let rebaseStartTime: Bool
        /// true for every replacement, including return to source video.
        let preserveRunningAudio: Bool
    }

    /// This is a backend commit receipt, not an intended-state echo produced by
    /// the coordinator. R4's implementation must populate it from committed state.
    struct Receipt: Equatable {
        let sessionID: UUID
        let operationID: UUID
        let videoURL: URL
        let sourceAudioURL: URL
        let requestedFilmTime: Double
        let committedFilmTime: Double
        let rebased: Bool
        let preservedRunningAudio: Bool
    }

    private let backend: any PreparedShotSessionBackend
    private(set) var current: Receipt?
    private(set) var invalidated = false
    private var inFlight = false

    init(backend: any PreparedShotSessionBackend) {
        self.backend = backend
    }

    /// loadfile render, replace, start=<film time>, no rebase, audio-file=source
    /// semantics, without serializing that MPV command or changing its old path.
    @discardableResult
    func loadPreparedShot(render: URL, source: URL, start: Double, timeline: Timeline = .legacyFilmPTS) async throws -> Receipt {
        try validate(render, source, start)
        if case .localV2(let map) = timeline {
            guard let map else {throw Failure.timelineMigrationRequired}
            do {try ShotLocalTimelineAdmission.requireAdmission(map,at:.preparedPlayback)}
            catch {throw Failure.timelineMigrationRequired}
        }
        let operation: Operation
        let sessionID: UUID
        if let previous = current {
            guard previous.sourceAudioURL == source else { throw Failure.sourceAudioChanged }
            operation = .replaceVideo
            sessionID = previous.sessionID
        } else {
            operation = .adoptRunningSource
            sessionID = UUID()
        }
        return try await commit(Request(sessionID: sessionID, operationID: UUID(),
            operation: operation, videoURL: render, sourceAudioURL: source,
            filmTime: start, rebaseStartTime: false,
            preserveRunningAudio: true))
    }

    /// Switch back to 2D source video at film time without restarting audio.
    /// A different source must start a separate normal media-load lifecycle.
    @discardableResult
    func loadSource2D(file: URL, start: Double) async throws -> Receipt {
        try validate(file, file, start)
        guard let previous = current else { throw Failure.noSourceSession }
        guard previous.sourceAudioURL == file else { throw Failure.sourceAudioChanged }
        return try await commit(Request(sessionID: previous.sessionID, operationID: UUID(),
            operation: .returnToSource, videoURL: file, sourceAudioURL: file,
            filmTime: start, rebaseStartTime: false, preserveRunningAudio: true))
    }

    private func validate(_ video: URL, _ audio: URL, _ time: Double) throws {
        guard !invalidated else { throw Failure.sessionInvalidated }
        guard !inFlight else { throw Failure.operationInFlight }
        guard time.isFinite, time >= 0 else { throw Failure.invalidFilmTime }
        guard video.isFileURL, audio.isFileURL,
              video.path.hasPrefix("/"), audio.path.hasPrefix("/") else {
            throw Failure.notLocalFile
        }
    }

    private func commit(_ request: Request) async throws -> Receipt {
        inFlight = true
        defer { inFlight = false }
        do {
            try Task.checkCancellation()
            let receipt = try await backend.applyPreparedShot(request)
            try Task.checkCancellation()
            guard receipt.sessionID == request.sessionID,
                  receipt.operationID == request.operationID,
                  receipt.videoURL == request.videoURL,
                  receipt.sourceAudioURL == request.sourceAudioURL,
                  receipt.committedFilmTime.isFinite,
                  receipt.committedFilmTime >= 0,
                  receipt.requestedFilmTime == request.filmTime,
                  !receipt.rebased,
                  receipt.preservedRunningAudio == request.preserveRunningAudio else {
                throw Failure.receiptMismatch
            }
            current = receipt
            return receipt
        } catch {
            // The backend might have partially changed state. Do not issue a new
            // open over a still-running audio session or reuse the old receipt.
            current = nil
            invalidated = true
            throw error
        }
    }
}
// END relocated PreparedShotPlayback.swift
// BEGIN relocated RenderPrefsReader.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190t E-G side of CONTRACT-190v section 4: reads <cache_root>/render-prefs.json (written only by RenderPrefs.write in FilmPrepareStatus.swift).
/// Absent, unreadable or invalid file = contract defaults (mode off). Re-read only when the file's mtime changes. Never writes.
struct RenderPrefsValue: Equatable {
    var mode = "off"
    var depthScale = 1.0
    var ipdM = 0.063
    var convergenceM: Double? = nil
    /// Virtual screen: horizontal angular width (deg) the film occupies on the VR180 canvas. Optional key "screen_deg"; absent/invalid = default.
    /// 0 = legacy "shot FoV" (the picture is only as wide as the camera FoV, a few percent of 180 deg: faithful but a postage stamp).
    var screenDeg = RenderPrefsValue.defaultScreenDeg
    /// Optional key "surround": "soft" (default, edge-extended blurred fill of the canvas outside the film) or "off" (black). Part of the render key.
    var surroundSoft = true
    /// CONTRACT-190v s25 comfort policy (ShotComfort): per-shot convergence = shot median depth, baseline shrunk so infinity stays inside the 1 deg divergence budget, near clamp at 2 deg crossed.
    /// Default on. Explicit convergence normally selects the fixed path; deep volume instead treats it as the screen-depth dial. Optional key "comfort": "off" always restores the fixed-parameter renderer. Part of the render key.
    var comfort = true
    /// Optional key "over_budget": true = the user explicitly picked a strength above 100% (labelled over comfort budget in the menu); otherwise strength is capped to 1 on top of comfort.
    var overBudget = false
    static let defaultScreenDeg = 75.0, minScreenDeg = 20.0, maxScreenDeg = 150.0, maxVerticalDeg = 150.0
    /// thetaH to pass to Stereo3DRenderer.render: screen width from prefs, aspect-preserving (same f for x and y), vertical capped so the screen stays inside the canvas.
    /// Depth is NOT rescaled: disparity at depth Z stays atan(eye/Z) from the real metric depth; only the angular size of the picture changes.
    func thetaH(shotThetaH: Double, aspect: Double) -> Double {
        if screenDeg <= 0 || !(aspect > 0) { return shotThetaH }
        let h = min(max(screenDeg, RenderPrefsValue.minScreenDeg), RenderPrefsValue.maxScreenDeg) * Double.pi / 180.0
        let vMax = RenderPrefsValue.maxVerticalDeg * Double.pi / 180.0
        let hCap = 2.0 * atan(tan(vMax / 2.0) * aspect)
        return min(h, hCap)
    }
    /// Eye offset the renderer takes as `ipd`: depth_scale multiplies disparity, and disparity is linear in the eye offset.
    /// True when the comfort policy sets convergence, baseline and near clamp per shot. Deep volume enables it with an explicit screen-depth dial too; depth_scale (menu strength) scales on top.
    func comfortActive(_ o: ThreeDExperimentOptions) -> Bool { comfort && (convergenceM == nil || o.deepVolume) }
    /// Eye offset under the comfort policy: ipd_m * (B_eff / IPD of the shot) * strength factor (capped to 1 unless over_budget).
    func deepComfort(_ raw: ShotComfort?) -> ShotComfort? {
        guard let c = raw, !c.todayFallback else { return nil }; return c
    }
    func comfortIPD(_ c: ShotComfort) -> Double { ipdM * c.depthScale * ShotComfort.strengthFactor(depthScale, overBudget: overBudget) }
    /// Strength multiplies the shot span GAIN. The hard near clamp follows the final baseline, including explicit over-budget strength.
    func comfortZNear(_ c: ShotComfort) -> Double { ShotComfort.nearClamp(zc: c.convergenceM, ipd: comfortIPD(c), budgetDeg: c.nearBudgetDeg) }
    var effectiveIPD: Double { ipdM * depthScale }
    static func parse(_ data: Data?) -> RenderPrefsValue {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return RenderPrefsValue() }
        var v = RenderPrefsValue()
        if let m = o["mode"] as? String, RenderPrefs.modes.contains(m) { v.mode = m } else { return RenderPrefsValue() }
        if let s = (o["depth_scale"] as? NSNumber)?.doubleValue, s.isFinite, s >= 0 { v.depthScale = s }
        if let i = (o["ipd_m"] as? NSNumber)?.doubleValue, i.isFinite, i > 0 { v.ipdM = i }
        if let c = (o["convergence_m"] as? NSNumber)?.doubleValue, c.isFinite, c > 0 { v.convergenceM = c }
        if let ob = o["over_budget"] as? Bool { v.overBudget = ob }
        if let cv = o["comfort"] as? String, cv == "off" || cv == "on" { v.comfort = cv == "on" }
        if let sv = o["surround"] as? String, sv == "off" || sv == "soft" { v.surroundSoft = sv == "soft" }
        if let d = (o["screen_deg"] as? NSNumber)?.doubleValue, d.isFinite, d == 0 || (d >= minScreenDeg && d <= maxScreenDeg) { v.screenDeg = d }
        return v
    }
}

final class RenderPrefsReader {
    private let url: URL
    private var mtime: Date?
    private(set) var value = RenderPrefsValue()
    init(root: URL = DepthCachePaths.root) { url = root.appendingPathComponent("render-prefs.json") }
    /// Call per open/play. Returns the current value; cheap when unchanged.
    @discardableResult
    func refresh() -> RenderPrefsValue {
        let m = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if m != mtime || m == nil { mtime = m; value = m == nil ? RenderPrefsValue() : RenderPrefsValue.parse(try? Data(contentsOf: url)) }
        return value
    }
}
// END relocated RenderPrefsReader.swift
// BEGIN relocated RenderRevision.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// A render job owns an immutable generation. Returning to an earlier parameter
/// value never makes a cancelled job current again. All cross-queue reads lock.
final class RenderRevision {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var identity: String?
    private var settleAt = 0.0
    static let debounceSeconds = 0.5 // arch-194b starting value, not an owner preference

    @discardableResult
    func update(_ value: String, now: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value != identity else { return false }
        identity=value; generation &+= 1; settleAt=now+Self.debounceSeconds
        return true
    }
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; identity=nil
    }
    var token: UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func isCurrent(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return generation==token
    }
    func ready(now: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }; return identity != nil && now>=settleAt
    }
    /// A stale encode cannot publish its sidecar after a preference/source change.
    func commit(_ token: UInt64, _ body: () throws -> Void) rethrows -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation==token else { return false }
        try body(); return true
    }
    static func fileName(shot: Int, key: String) -> String {
        var hash=SHA256Pure.Hasher();hash.update(key)
        return String(format:"render_shot_%05d_",shot)+hash.hex()+".mp4"
    }
}

/// Keep the last-good encoded shot while a replacement is pending. A ready new
/// URL must replace the same shot too, so experiment changes become visible.
enum RenderContinuity {
    static func shouldLoad(showing: Int?, next: Int, seeked: Bool, showingURL: URL? = nil, candidateURL: URL? = nil) -> Bool {
        showing != next || seeked || (candidateURL != nil && showingURL != candidateURL)
    }
    static func holds(showing: Int?, next: Int, fileExists: Bool) -> Bool {
        showing==next && fileExists
    }
}
// END relocated RenderRevision.swift
// BEGIN relocated Stereo3DKernel.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(Metal)
import Metal

/// 190t E/F/G: VR180 / SBS eye render on the GPU. Mirrors tools/vr180_render_ref.py op for op (Tests/Stereo3DKernel keeps a Python model of
/// every kernel below). 3D-mode only: nothing in flat playback creates or calls this. The Metal source is compiled at runtime with fast-math
/// off, so a compile or device failure returns nil from `make()` and the caller stays on the 2D path; it cannot break the app build.
enum Stereo3DKernelSource {
    static let text = """
    #include <metal_stdlib>
    using namespace metal;
    struct S3DParams { float f; float eye; uint w; uint h; uint ow; uint oh; float conv; float znear; uint mode; float fout; };   // s36: mode 0 = equirect180 (vr180), 1 = perspective (flat modes, fout = pixels per tan across the eye canvas)
    constant uint S3D_INF = 0x7F800000u;
    static bool s3d_map(uint2 g, constant S3DParams& p, float z, thread int2& o) {
        float rx = ((float)g.x + 0.5f - (float)p.w * 0.5f) / p.f;
        float ry = ((float)p.h * 0.5f - ((float)g.y + 0.5f)) / p.f;
        float px = rx * z - p.eye, py = ry * z, pz = z;
        if (p.mode == 1u) {          // parallel-shift convergence: no toe-in keystone or vertical parallax
            if (!(z > 0.0f)) return false;
            float uu = px / pz + tan(p.conv), vv = py / pz;
            o = int2((int)floor(uu * p.fout + (float)p.ow * 0.5f), (int)floor((float)p.oh * 0.5f - vv * p.fout));
            return o.x >= 0 && o.x < (int)p.ow && o.y >= 0 && o.y < (int)p.oh;
        }
        float n = sqrt(px * px + py * py + pz * pz);
        float lon = atan2(px, pz) + p.conv, lat = asin(py / n);
        float u = lon / M_PI_F + 0.5f, v = 0.5f - lat / M_PI_F;
        o = int2((int)floor(u * (float)p.ow), (int)floor(v * (float)p.oh));
        return z > 0.0f && o.x >= 0 && o.x < (int)p.ow && o.y >= 0 && o.y < (int)p.oh;
    }
    kernel void s3d_clear(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                          texture2d<float, access::write> rendered [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        atomic_store_explicit(&zb[gid.y * p.ow + gid.x], S3D_INF, memory_order_relaxed);
        rendered.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
    }
    kernel void s3d_zmin(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                         texture2d<float, access::read> depth [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear); int2 o;
        if (!s3d_map(gid, p, z, o)) return;
        atomic_fetch_min_explicit(&zb[(uint)o.y * p.ow + (uint)o.x], as_type<uint>(z), memory_order_relaxed);
    }
    kernel void s3d_resolve(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                            texture2d<float, access::read> frame [[texture(0)]], texture2d<float, access::read> depth [[texture(1)]],
                            texture2d<float, access::write> rendered [[texture(2)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear); int2 o;
        if (!s3d_map(gid, p, z, o)) return;
        if (atomic_load_explicit(&zb[(uint)o.y * p.ow + (uint)o.x], memory_order_relaxed) != as_type<uint>(z)) return;
        rendered.write(float4(frame.read(gid).rgb, 1.0f), uint2(o));
    }
    // F1 integer-exact blend and far-column average; r2 edge-run fill stays inside the frustum.
    constant uint SHORT_RUN_K = 16u, VERT_HALF = 16u;
    static uint4 s3d_codes(float4 c) { return uint4(floor(clamp(c, 0.0f, 1.0f) * 255.0f + 0.5f)); }
    static uint4 s3d_round(uint4 num, uint den) { return (2u * num + den) / (2u * den); }
    static float4 s3d_vavg(device const uint* zb, constant S3DParams& p, texture2d<float, access::read> rendered, uint row, uint col) {
        uint lo = row > VERT_HALF ? row - VERT_HALF : 0u, hi = min(p.oh - 1u, row + VERT_HALF);
        uint4 sum = uint4(0u); uint n = 0u;
        for (uint r = lo; r <= hi; r++) if (zb[r * p.ow + col] != S3D_INF) { sum += s3d_codes(rendered.read(uint2(col, r))); n++; }
        return n > 0u ? float4(s3d_round(sum, n)) / 255.0f : rendered.read(uint2(col, row));
    }
    kernel void s3d_fill(device const uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]],
                         texture2d<float, access::read> rendered [[texture(0)]], texture2d<float, access::write> result [[texture(1)]],
                         uint row [[thread_position_in_grid]]) {
        if (row >= p.oh) return;
        for (uint c0 = 0; c0 < p.ow; c0++) result.write(float4(0.0f), uint2(c0, row));
        int a = -1, first = -1;
        for (uint c = 0; c < p.ow; c++) {
            uint zc = zb[row * p.ow + c];
            if (zc == S3D_INF) continue;
            if (a >= 0 && (int)c - a > 1) {
                uint g = c - (uint)a - 1u;
                if (g <= SHORT_RUN_K) {
                    uint4 A = s3d_codes(rendered.read(uint2((uint)a, row))), B = s3d_codes(rendered.read(uint2(c, row)));
                    for (uint k = 1u; k <= g; k++) result.write(float4(s3d_round(A * (g + 1u - k) + B * k, g + 1u)) / 255.0f, uint2((uint)a + k, row));
                } else {
                    uint za = zb[row * p.ow + (uint)a];
                    uint src = (as_type<float>(za) >= as_type<float>(zc)) ? (uint)a : c;
                    float4 col = s3d_vavg(zb, p, rendered, row, src);
                    for (uint k = (uint)a + 1u; k < c; k++) result.write(col, uint2(k, row));
                }
            }
            result.write(rendered.read(uint2(c, row)), uint2(c, row));
            if (first < 0) first = (int)c;
            a = (int)c;
        }
        if (a < 0) return;
        int lo = -1, hi = -1;
        for (uint c = 0; c < p.ow; c++) if (fp[row * p.ow + c] != 0) { if (lo < 0) lo = (int)c; hi = (int)c; }
        if (lo < 0) return;
        if (first > lo) {
            float4 col = (uint)(first - lo) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)first) : rendered.read(uint2((uint)first, row));
            for (int k = lo; k < first; k++) result.write(col, uint2((uint)k, row));
        }
        if (a < hi) {
            float4 col = (uint)(hi - a) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)a) : rendered.read(uint2((uint)a, row));
            for (int k = a + 1; k <= hi; k++) result.write(col, uint2((uint)k, row));
        }
    }
    // 195h E: dynamic floating window (doi 10.1117/1.jei.21.1.011009). Content nearer than the convergence (screen) distance that the OUTER canvas
    // edge cuts is a window violation; mask the violated outer strip per row with a one-column feather. Deterministic, per row like s3d_fill; conv 0
    // (no screen distance) = plain copy. Outer edge = the side the eye is shifted toward (left eye: x=0, right eye: x=ow-1).
    kernel void s3d_floatwin(device const uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                             texture2d<float, access::read> result [[texture(0)]], texture2d<float, access::write> outTex [[texture(1)]],
                             uint row [[thread_position_in_grid]]) {
        if (row >= p.oh) return;
        for (uint c = 0; c < p.ow; c++) outTex.write(result.read(uint2(c, row)), uint2(c, row));
        float tc = tan(fabs(p.conv));
        if (!(tc > 1e-6f)) return;
        float zs = fabs(p.eye) / tc;                                 // screen (convergence) distance, metres
        uint maxrun = p.ow / 8u, ext = 0u;                           // furthest violated column from the outer edge (capped)
        for (uint c = 0; c < maxrun; c++) {
            uint x = p.eye < 0.0f ? c : p.ow - 1u - c;
            uint z = zb[row * p.ow + x];
            if (z != S3D_INF && as_type<float>(z) < zs) ext = c + 1u;
        }
        for (uint c = 0; c < ext; c++) {
            uint x = p.eye < 0.0f ? c : p.ow - 1u - c;
            float w = (c + 1u == ext) ? 0.5f : 0.0f;                 // feather column at the crop boundary
            outTex.write(float4(result.read(uint2(x, row)).rgb * w, 1.0f), uint2(x, row));
        }
    }
    // 195h G: depth-guided defocus (Held & Banks 2012: blur + disparity as the realism cue). Per-source-pixel disc blur with radius following the
    // circle of confusion |1/z - 1/zf| about the convergence (focus) plane; conv 0 (no screen distance) = plain copy. Deterministic 12-tap disc.
    kernel void s3d_dof(texture2d<float, access::read> frame [[texture(0)]], texture2d<float, access::read> depth [[texture(1)]],
                        texture2d<float, access::write> blurred [[texture(2)]], constant S3DParams& p [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float tc = tan(fabs(p.conv));
        if (!(tc > 1e-6f)) { blurred.write(frame.read(gid), gid); return; }
        float zf = fabs(p.eye) / tc;                                 // focus plane = the convergence distance, metres
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear);
        float r = (z > 0.0f) ? clamp(28.0f * fabs(1.0f / z - 1.0f / zf), 0.0f, 12.0f) : 0.0f;
        if (r < 0.5f) { blurred.write(frame.read(gid), gid); return; }
        const float2 taps[12] = { float2(1.0f, 0.0f), float2(-1.0f, 0.0f), float2(0.0f, 1.0f), float2(0.0f, -1.0f),
                                  float2(0.7071f, 0.7071f), float2(-0.7071f, 0.7071f), float2(0.7071f, -0.7071f), float2(-0.7071f, -0.7071f),
                                  float2(0.5f, 0.866f), float2(-0.5f, 0.866f), float2(0.5f, -0.866f), float2(-0.5f, -0.866f) };
        float3 sum = frame.read(gid).rgb; float n = 1.0f;
        for (uint k = 0; k < 12; k++) {
            int2 t = clamp(int2(gid) + int2((int)round(taps[k].x * r), (int)round(taps[k].y * r)), int2(0, 0), int2((int)p.w - 1, (int)p.h - 1));
            sum += frame.read(uint2(t)).rgb; n += 1.0f;
        }
        blurred.write(float4(sum / n, 1.0f), gid);
    }
    // 195h: deterministic depth-guided gradient hole fill, a drop-in variant of s3d_fill behind Stereo3DExperiments.holeFillGradient.
    // Short gaps, edge runs and valid pixels are byte-identical to s3d_fill; long disocclusions ramp the near endpoint's colour into the far
    // (background) vertical average over 32 px from the near side and then hold the background, instead of s3d_fill's flat vavg wall.
    kernel void s3d_fillgrad(device const uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]],
                         texture2d<float, access::read> rendered [[texture(0)]], texture2d<float, access::write> result [[texture(1)]],
                         uint row [[thread_position_in_grid]]) {
        if (row >= p.oh) return;
        for (uint c0 = 0; c0 < p.ow; c0++) result.write(float4(0.0f), uint2(c0, row));
        int a = -1, first = -1;
        for (uint c = 0; c < p.ow; c++) {
            uint zc = zb[row * p.ow + c];
            if (zc == S3D_INF) continue;
            if (a >= 0 && (int)c - a > 1) {
                uint g = c - (uint)a - 1u;
                if (g <= SHORT_RUN_K) {
                    uint4 A = s3d_codes(rendered.read(uint2((uint)a, row))), B = s3d_codes(rendered.read(uint2(c, row)));
                    for (uint k = 1u; k <= g; k++) result.write(float4(s3d_round(A * (g + 1u - k) + B * k, g + 1u)) / 255.0f, uint2((uint)a + k, row));
                } else {
                    uint za = zb[row * p.ow + (uint)a];
                    bool nearLeft = as_type<float>(za) < as_type<float>(zc);
                    uint farC = nearLeft ? c : (uint)a, nearC = nearLeft ? (uint)a : c;
                    float4 farCol = s3d_vavg(zb, p, rendered, row, farC), nearCol = s3d_vavg(zb, p, rendered, row, nearC);
                    const uint GRAD_RUN = 32u;
                    for (uint k = 1u; k <= g; k++) {
                        uint d = nearLeft ? k : g + 1u - k;          // px from the near endpoint into the gap
                        if (d >= GRAD_RUN) { result.write(farCol, uint2((uint)a + k, row)); continue; }   // at/past the run: the far colour exactly, as s3d_fill
                        uint4 A = s3d_codes(nearCol), B = s3d_codes(farCol);
                        result.write(float4(s3d_round(A * (GRAD_RUN + 1u - d) + B * d, GRAD_RUN + 1u)) / 255.0f, uint2((uint)a + k, row));
                    }
                }
            }
            result.write(rendered.read(uint2(c, row)), uint2(c, row));
            if (first < 0) first = (int)c;
            a = (int)c;
        }
        if (a < 0) return;
        int lo = -1, hi = -1;
        for (uint c = 0; c < p.ow; c++) if (fp[row * p.ow + c] != 0) { if (lo < 0) lo = (int)c; hi = (int)c; }
        if (lo < 0) return;
        if (first > lo) {
            float4 col = (uint)(first - lo) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)first) : rendered.read(uint2((uint)first, row));
            for (int k = lo; k < first; k++) result.write(col, uint2((uint)k, row));
        }
        if (a < hi) {
            float4 col = (uint)(hi - a) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)a) : rendered.read(uint2((uint)a, row));
            for (int k = a + 1; k <= hi; k++) result.write(col, uint2((uint)k, row));
        }
    }
    kernel void s3d_depth10(texture2d<float, access::read> luma [[texture(0)]], texture2d<float, access::write> metric [[texture(1)]],
                            constant uint& shift [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= metric.get_width() || gid.y >= metric.get_height()) return;
        uint w10 = (uint)round(luma.read(gid).r * 65535.0f) >> shift;
        float v = (float)w10 / 1023.0f * 1024.0f;
        metric.write(float4(w10 == 0u ? 0.0f : 256.0f / v, 0.0f, 0.0f, 0.0f), gid);
    }
    // s3d_surround r4 (CONTRACT-190v s20 + s28/s28b), four kernels. The footprint mask `fp`, the nearest-footprint extension map `src`, the nearest-footprint (L1 BFS)
    // index `near` and the per-pixel weights `wb` = (t1, t2, wcorr, vert) are content independent and come from SurroundGeometry (CPU, exact port of the reference passes).
    // Colour work is here, float32 textures: 32x normalised 3x3 pre-blur over the footprint (np.roll wrap), gather (outside pixels copy their footprint source, then add the
    // r4 boundary correction (true - preblur32) of their nearest footprint pixel x wcorr; footprint pixels keep the TRUE film colour for the blur windows), clamped boxes
    // (16x16, 96x96 and the side-local far trend 256x64 / 64x256, rx x ry) from separable running sums blended by distance (R1 -> R2 over 1..40 px, R2 -> far over 40..120 px,
    // lerp form), one truncation to uint8. Only canvas OUTSIDE the footprint is written.
    // s31 (d): the pre-blur only matters at footprint pixels (non-footprint neighbours are skipped and gather reads `pre` at footprint pixels only), so the 32 passes are
    // dispatched over the footprint bounding box `box` = (x0, y0, w, h) alone. Exact, not an approximation: nothing outside the box is ever read.
    kernel void s3d_sur_pre(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]],
                            constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]], constant uint4& box [[buffer(6)]], constant uint& pass0 [[buffer(7)]], uint2 lid [[thread_position_in_grid]]) {
        if (lid.x >= box.z || lid.y >= box.w) return;
        uint2 gid = uint2(box.x + lid.x, box.y + lid.y);
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        if (fp[gid.y * p.ow + gid.x] == 0) { dst.write(float4(0.0f), gid); return; }
        float4 acc = float4(src.read(gid).rgb, 0.0f); float cnt = 1.0f;
        for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
            if (i == 0 && j == 0) continue;
            uint x = (uint)(((int)gid.x + i + (int)p.ow) % (int)p.ow), y = (uint)(((int)gid.y + j + (int)p.oh) % (int)p.oh);
            if (fp[y * p.ow + x] == 0) { if (pass0 != 0) acc += float4(src.read(uint2(x, y)).rgb, 0.0f); continue; }   // pass 0: the reference adds the rendered value of a non-footprint neighbour to the sum (not the count); later passes read 0 there
            acc += float4(src.read(uint2(x, y)).rgb, 0.0f); cnt += 1.0f;
        }
        dst.write(float4(acc.rgb / max(cnt, 1.0f), 1.0f), gid);
    }
    kernel void s3d_sur_gather(texture2d<float, access::read> pre [[texture(0)]], texture2d<float, access::write> work [[texture(1)]], texture2d<float, access::read> truth [[texture(2)]],
                               constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]], device const int* src [[buffer(3)]], device const float4* wb [[buffer(4)]],
                               device const int* near [[buffer(5)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        uint i = gid.y * p.ow + gid.x;
        if (fp[i] != 0) { work.write(float4(truth.read(gid).rgb, 1.0f), gid); return; }          // r4: blur windows read TRUE film content inside the footprint
        int s = src[i];
        if (s < 0) { work.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid); return; }
        float3 v = pre.read(uint2((uint)s % p.ow, (uint)s / p.ow)).rgb;
        int q = near[i];
        if (q >= 0) { uint2 qg = uint2((uint)q % p.ow, (uint)q / p.ow); v += (truth.read(qg).rgb - pre.read(qg).rgb) * wb[i].z; }   // (true - preblur32) x wcorr, additive
        work.write(float4(v, 1.0f), gid);
    }
    // r4 blur: one pass per axis computes the four clamped boxes with running sums (O(1) per pixel; float32 running-sum drift is far below 1 LSB after the divides). Horizontal radii
    // {16, 96, 256, 64}: one thread per row -> four row-blurred textures. Vertical radii {16, 96, 64, 256} for those rows give the rectangles 16x16, 96x96, 256x64 (wide-short, pixels
    // above/below the footprint) and 64x256 (tall-narrow, left/right). One thread per column, then the lerp-form blend and one truncation.
    kernel void s3d_sur_boxh(texture2d<float, access::read> work [[texture(0)]], texture2d<float, access::write> t1 [[texture(1)]], texture2d<float, access::write> t2 [[texture(2)]],
                             texture2d<float, access::write> t3 [[texture(3)]], texture2d<float, access::write> t4 [[texture(4)]], constant S3DParams& p [[buffer(1)]], uint gid [[thread_position_in_grid]]) {
        if (gid >= p.oh) return;
        const int R[4] = {16, 96, 256, 64}; const float D[4] = {33.0f, 193.0f, 513.0f, 129.0f}; const int n = (int)p.ow; float3 s[4];
        for (int k = 0; k < 4; k++) { s[k] = float3(0.0f); for (int i = -R[k]; i <= R[k]; i++) s[k] += work.read(uint2((uint)clamp(i, 0, n - 1), gid)).rgb; }
        for (int x = 0; x < n; x++) {
            t1.write(float4(s[0] / D[0], 1.0f), uint2((uint)x, gid)); t2.write(float4(s[1] / D[1], 1.0f), uint2((uint)x, gid));
            t3.write(float4(s[2] / D[2], 1.0f), uint2((uint)x, gid)); t4.write(float4(s[3] / D[3], 1.0f), uint2((uint)x, gid));
            for (int k = 0; k < 4; k++) s[k] += work.read(uint2((uint)clamp(x + 1 + R[k], 0, n - 1), gid)).rgb - work.read(uint2((uint)clamp(x - R[k], 0, n - 1), gid)).rgb;
        }
    }
    float3 colRead(texture2d<float, access::read> t1, texture2d<float, access::read> t2, texture2d<float, access::read> t3, texture2d<float, access::read> t4, int k, uint x, int y, int n) {
        uint yy = (uint)clamp(y, 0, n - 1);
        return k == 0 ? t1.read(uint2(x, yy)).rgb : (k == 1 ? t2.read(uint2(x, yy)).rgb : (k == 2 ? t3.read(uint2(x, yy)).rgb : t4.read(uint2(x, yy)).rgb));
    }
    kernel void s3d_sur_boxv(texture2d<float, access::read> t1 [[texture(0)]], texture2d<float, access::read> t2 [[texture(1)]], texture2d<float, access::read> t3 [[texture(2)]],
                             texture2d<float, access::read> t4 [[texture(3)]], texture2d<float, access::write> result [[texture(4)]], constant S3DParams& p [[buffer(1)]],
                             device const uchar* fp [[buffer(2)]], device const float4* wb [[buffer(4)]], uint gid [[thread_position_in_grid]]) {
        if (gid >= p.ow) return;
        const int R[4] = {16, 96, 64, 256}; const float D[4] = {33.0f, 193.0f, 129.0f, 513.0f}; const int n = (int)p.oh; float3 s[4];
        for (int k = 0; k < 4; k++) { s[k] = float3(0.0f); for (int j = -R[k]; j <= R[k]; j++) s[k] += colRead(t1, t2, t3, t4, k, gid, j, n); }
        for (int y = 0; y < n; y++) {
            if (fp[(uint)y * p.ow + gid] == 0) {
                float4 w = wb[(uint)y * p.ow + gid]; float3 b1 = s[0] / D[0], b2 = s[1] / D[1], b3 = w.w != 0.0f ? s[2] / D[2] : s[3] / D[3];   // w.w = 1: far trend 256x64 (above/below)
                float3 v = b1 + (b2 - b1) * w.x; v = v + (b3 - v) * w.y;          // lerp form: exact for constant fields
                result.write(float4(floor(v * 255.0f) / 255.0f, 1.0f), uint2(gid, (uint)y));
            }
            for (int k = 0; k < 4; k++) s[k] += colRead(t1, t2, t3, t4, k, gid, y + 1 + R[k], n) - colRead(t1, t2, t3, t4, k, gid, y - R[k], n);
        }
    }
    // s36 packers (output_modes.pack_*): mode 0 side by side, 1 half sbs (2:1 box average per eye, INTER_AREA), 2 over under, 3 Dubois anaglyph (one 3x3 pass on the 0-255 codes, +0.5, clamp, truncate).
    constant float3 DUBOIS_L[3] = {float3(0.437f, 0.449f, 0.164f), float3(-0.062f, -0.062f, -0.024f), float3(-0.048f, -0.050f, -0.017f)};
    constant float3 DUBOIS_R[3] = {float3(-0.011f, -0.032f, -0.007f), float3(0.377f, 0.761f, 0.009f), float3(-0.026f, -0.093f, 1.234f)};
    kernel void s3d_pack(texture2d<float, access::read> left [[texture(0)]], texture2d<float, access::read> right [[texture(1)]],
                         texture2d<float, access::write> outTex [[texture(2)]], constant uint& mode [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        uint ow = left.get_width(), oh = left.get_height();
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        if (mode == 1u) {
            uint hw = ow / 2; bool isL = gid.x < hw; uint x = isL ? gid.x : gid.x - hw;
            float3 a = isL ? left.read(uint2(2u * x, gid.y)).rgb : right.read(uint2(2u * x, gid.y)).rgb;
            float3 b = isL ? left.read(uint2(2u * x + 1u, gid.y)).rgb : right.read(uint2(2u * x + 1u, gid.y)).rgb;
            outTex.write(float4((a + b) * 0.5f, 1.0f), gid);
        } else if (mode == 2u) {
            outTex.write(gid.y < oh ? left.read(gid) : right.read(uint2(gid.x, gid.y - oh)), gid);
        } else if (mode == 3u) {
            float3 l = left.read(gid).rgb * 255.0f, r = right.read(gid).rgb * 255.0f;
            float3 a = float3(dot(DUBOIS_L[0], l) + dot(DUBOIS_R[0], r), dot(DUBOIS_L[1], l) + dot(DUBOIS_R[1], r), dot(DUBOIS_L[2], l) + dot(DUBOIS_R[2], r)) + 0.5f;
            outTex.write(float4(floor(clamp(a, 0.0f, 255.0f)) / 255.0f, 1.0f), gid);
        } else {
            outTex.write(gid.x < ow ? left.read(gid) : right.read(uint2(gid.x - ow, gid.y)), gid);
        }
    }
    // s37 passthrough resampling (stereo_probe.place_on_vr180 / vr180_to_perspective). One eye per dispatch. Bilinear in cv2.remap's coordinate convention (map value = pixel INDEX,
    // texel centres at integers), out-of-range taps are black (BORDER_CONSTANT 0) with the remaining weights kept like cv2.
    struct S3DRemap { uint mode; uint srcW; uint srcH; uint outW; uint outH; float f; float thetaOrHFov; };   // mode 0: baked-stereo screen -> vr180 canvas (f = (srcW/2)/tan(theta/2)); mode 1: vr180 equirect eye (srcW = srcH = n) -> perspective (f = (outW/2)/tan(hfov/2))
    static float4 s3d_tap(texture2d<float, access::read> t, int x, int y) {
        if (x < 0 || y < 0 || x >= (int)t.get_width() || y >= (int)t.get_height()) return float4(0.0f);
        return t.read(uint2((uint)x, (uint)y));
    }
    kernel void s3d_remap(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> outTex [[texture(1)]],
                          constant S3DRemap& p [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.outW || gid.y >= p.outH) return;
        float mx, my; bool inside = true;
        if (p.mode == 0u) {
            float n = (float)p.outW;
            float lon = ((float)gid.x + 0.5f) / n * M_PI_F - M_PI_F * 0.5f, lat = M_PI_F * 0.5f - ((float)gid.y + 0.5f) / n * M_PI_F;
            mx = tan(lon) * p.f + (float)p.srcW * 0.5f; my = (float)p.srcH * 0.5f - tan(lat) * p.f;
            inside = mx >= 0.0f && mx < (float)p.srcW && my >= 0.0f && my < (float)p.srcH;
        } else {
            float n = (float)p.srcW;
            float lon = atan(((float)gid.x + 0.5f - (float)p.outW * 0.5f) / p.f), lat = atan(((float)p.outH * 0.5f - (float)gid.y - 0.5f) / p.f);
            mx = (lon + M_PI_F * 0.5f) / M_PI_F * n - 0.5f; my = (M_PI_F * 0.5f - lat) / M_PI_F * n - 0.5f;
        }
        if (!inside) { outTex.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid); return; }
        int x0 = (int)floor(mx), y0 = (int)floor(my); float fx = mx - (float)x0, fy = my - (float)y0;
        float4 c = (s3d_tap(src, x0, y0) * (1.0f - fx) + s3d_tap(src, x0 + 1, y0) * fx) * (1.0f - fy) + (s3d_tap(src, x0, y0 + 1) * (1.0f - fx) + s3d_tap(src, x0 + 1, y0 + 1) * fx) * fy;
        outTex.write(float4(c.rgb, 1.0f), gid);
    }
    kernel void s3d_sbs(texture2d<float, access::read> left [[texture(0)]], texture2d<float, access::read> right [[texture(1)]],
                        texture2d<float, access::write> sbs [[texture(2)]], uint2 gid [[thread_position_in_grid]]) {
        uint ow = left.get_width(), oh = left.get_height();
        if (gid.x >= ow * 2 || gid.y >= oh) return;
        sbs.write(gid.x < ow ? left.read(gid) : right.read(uint2(gid.x - ow, gid.y)), gid);
    }
    """
}

/// 195h experiment switches (owner 195h 3D realism list; rows under video > 3d > Experiments). Each defaults OFF and is read inside render();
/// with every switch off, render() dispatches exactly the kernels it did before this lane (flag-off output identical).
enum Stereo3DExperiments {
    private static let lock = NSLock()
    static var floatingWindow = false, depthOfField = false, holeFillGradient = false, deepVolume = false   // mutated only through the toggles under lock; read only via snapshot()
    static func setAll(_ on: Bool) { lock.lock(); floatingWindow=on; depthOfField=on; holeFillGradient=on; deepVolume=on; lock.unlock() }
    static func toggleFloatingWindow() { lock.lock(); floatingWindow.toggle(); lock.unlock() }
    static func toggleDepthOfField() { lock.lock(); depthOfField.toggle(); lock.unlock() }
    static func toggleHoleFillGradient() { lock.lock(); holeFillGradient.toggle(); lock.unlock() }
    static func toggleDeepVolume() { lock.lock(); deepVolume.toggle(); lock.unlock() }
    static func snapshot() -> (fw: Bool, dof: Bool, hg: Bool, deep: Bool) { lock.lock(); defer { lock.unlock() }; return (floatingWindow, depthOfField, holeFillGradient, deepVolume) }
}

final class Stereo3DRenderer {
    struct Params { var f: Float; var eye: Float; var w: UInt32; var h: UInt32; var ow: UInt32; var oh: UInt32; var conv: Float; var znear: Float; var mode: UInt32 = 0; var fout: Float = 0 }
    private let device: MTLDevice; let queue: MTLCommandQueue   // queue is internal: RenderShotWriter blits on it so its blits order after render/decodeDepth
    private let clear: MTLComputePipelineState, zmin: MTLComputePipelineState, resolve: MTLComputePipelineState
    private let fill: MTLComputePipelineState, sbs: MTLComputePipelineState
    private var depth10: MTLComputePipelineState?, remapPipe: MTLComputePipelineState?, packPipe: MTLComputePipelineState?
    private var floatWinPipe: MTLComputePipelineState?          // s3d_floatwin, lazy like the surround pipes (195h E)
    private var dofPipe: MTLComputePipelineState?, dofBlurred: MTLTexture?   // s3d_dof pre-pass + its source-sized buffer (195h G)
    private var fillGradPipe: MTLComputePipelineState?                     // s3d_fillgrad, lazy (195h hole fill)
    private(set) var lastCommandBuffer: MTLCommandBuffer?          // s32: the probe waits on it to time one render (render() itself returns after commit)
    private var surroundPipes: [MTLComputePipelineState]?        // s3d_sur_pre, _gather, _boxh, _boxv (CONTRACT-190v s20, s28 r4)
    private var scratch: [MTLTexture] = []                         // rgba32Float ping, pong, work, tmp1-4 (rx = 16/96/256/64 row blurs) for the surround, sized to the canvas
    private var geoBuffers: [ObjectIdentifier: (fp: MTLBuffer, src: MTLBuffer?, wb: MTLBuffer?, near: MTLBuffer?, geo: SurroundGeometry)] = [:]
    private func buffers(_ geo: SurroundGeometry, surround: Bool) -> (fp: MTLBuffer, src: MTLBuffer?, wb: MTLBuffer?, near: MTLBuffer?)? {
        let k = ObjectIdentifier(geo)
        if geoBuffers.count > 8 { geoBuffers.removeAll() }
        var e = geoBuffers[k]
        if e == nil { guard let fp = geo.inside.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }; e = (fp, nil, nil, nil, geo) }
        if surround, e!.src == nil {
            let idx = geo.sourceIndex, wb = geo.blendWeights, nr = geo.nearIndex
            e!.src = idx.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            e!.wb = wb.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            e!.near = nr.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        }
        geoBuffers[k] = e; return (e!.fp, e!.src, e!.wb, e!.near)
    }

    /// nil when there is no Metal device or the source does not compile: stay on the 2D path.
    static func make() -> Stereo3DRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let options = MTLCompileOptions(); options.fastMathEnabled = false
        guard let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: options) else { return nil }
        func pipe(_ name: String) -> MTLComputePipelineState? {
            guard let fn = lib.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }
        guard let c = pipe("s3d_clear"), let z = pipe("s3d_zmin"), let r = pipe("s3d_resolve"), let f = pipe("s3d_fill"), let s = pipe("s3d_sbs") else { return nil }
        let renderer = Stereo3DRenderer(device: device, queue: queue, clear: c, zmin: z, resolve: r, fill: f, sbs: s)
        renderer.remapPipe = pipe("s3d_remap")                // s37 passthrough; nil = passthrough returns false
        renderer.packPipe = pipe("s3d_pack")                  // nil = the flat output modes are unavailable (render returns false), vr180 is unaffected
        return renderer
    }
    private init(device: MTLDevice, queue: MTLCommandQueue, clear: MTLComputePipelineState, zmin: MTLComputePipelineState,
                 resolve: MTLComputePipelineState, fill: MTLComputePipelineState, sbs: MTLComputePipelineState) {
        self.device = device; self.queue = queue; self.clear = clear; self.zmin = zmin; self.resolve = resolve; self.fill = fill; self.sbs = sbs
    }

    static func texture(_ device: MTLDevice, _ format: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    /// frame: rgba8/bgra8 source picture, depth: r32Float aligned METRIC depth (metres along the optical axis), thetaH: radians (shot median fov_x).
    /// `swapEyes` puts the +ipd/2 eye in the left half (the vr180-look vr_swap_eyes=1 order); a negative `ipd` does the same and is not needed. Writes side-by-side (left | right) equirect-180 eyes into `sbsOut` (2*outW x outH). Returns false on any resource failure.
    func render(frame: MTLTexture, depth: MTLTexture, thetaH: Double, ipd: Double = 0.063, convergence: Double? = nil, zNear: Double? = nil, swapEyes: Bool = false, surround: Bool = false, outW: Int, outH: Int, sbsOut: MTLTexture, output: OutputMode = .vr180, options: ThreeDExperimentOptions = .live) -> Bool {
        // s36: `output` = vr180 (default, unchanged: equirect180 eyes, outW = outH = eye N, sbsOut 2N x N) or a flat mode (perspective eyes at the source size: outW x outH = frame size,
        // sbsOut = output.canvasSize; no surround, the film fills the frame). Flat modes need the s3d_pack pipeline.
        let options = options.renderOptions
        let flat = output.isFlat, canvas = output.canvasSize(srcW: outW, srcH: outH)
        guard flat ? (sbsOut.width == canvas.w && sbsOut.height == canvas.h && outW == frame.width && outH == frame.height && packPipe != nil && (output != .halfSBS || outW % 2 == 0))
                   : (sbsOut.width == outW * 2 && sbsOut.height == outH),
              depth.width == frame.width, depth.height == frame.height,
              let cb = queue.makeCommandBuffer(),
              let zb = device.makeBuffer(length: outW * outH * 4, options: .storageModePrivate) else { return false }
        let surround = surround && !flat
        if surround, surroundPipes == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil) {
            let ps = ["s3d_sur_pre", "s3d_sur_gather", "s3d_sur_boxh", "s3d_sur_boxv"].compactMap { n in lib.makeFunction(name: n).flatMap { try? device.makeComputePipelineState(function: $0) } }
            surroundPipes = ps.count == 4 ? ps : nil        // nil on failure: the surround stays black, the render still succeeds
        }
        if surround, surroundPipes != nil, scratch.count != 7 || scratch[0].width != outW || scratch[0].height != outH {
            let t = (0..<7).compactMap { _ in Stereo3DRenderer.texture(device, .rgba32Float, outW, outH) }
            scratch = t.count == 7 ? t : []
        }
        var eyes: [MTLTexture] = []
        for sign in (swapEyes ? [1.0, -1.0] : [-1.0, 1.0]) {
            guard let rendered = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH),
                  let result = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH),
                  let enc = cb.makeComputeCommandEncoder() else { return false }
            let fD = (Double(frame.width) / 2.0) / tan(thetaH / 2.0)
            let convD = convergence.map { $0 > 0 ? atan2(sign * ipd / 2.0, $0) : 0 } ?? 0
            let geo = SurroundGeometry.cached(w: frame.width, h: frame.height, f: fD, conv: Double(Float(convD)), ow: outW, oh: outH)   // Float round trip: the kernel's own conv
            guard let gb = buffers(geo, surround: surround && surroundPipes != nil && scratch.count == 7) else { return false }
            let foutD = (Double(outW) / 2.0) / tan(OutputMode.screenDeg * Double.pi / 360.0)
            // Parallel-shift source frustum, per eye. Do not fill canvas margins with stretched film edges.
            var flatFP: MTLBuffer? = nil
            if flat {
                var mask = [UInt8](repeating: 0, count: outW * outH)
                let shift = tan(Double(Float(convD)))
                for y in 0..<outH { for x in 0..<outW {
                    let u = (Double(x) + 0.5 - Double(outW) / 2) / foutD - shift
                    let v = (Double(outH) / 2 - (Double(y) + 0.5)) / foutD
                    let sx = fD * u + Double(frame.width) / 2, sy = Double(frame.height) / 2 - fD * v
                    if sx >= 0 && sx < Double(frame.width) && sy >= 0 && sy < Double(frame.height) { mask[y * outW + x] = 1 }
                } }
                flatFP = device.makeBuffer(bytes: mask, length: mask.count, options: .storageModeShared)
                guard flatFP != nil else { return false }
            }
            var p = Params(f: Float((Double(frame.width) / 2.0) / tan(thetaH / 2.0)), eye: Float(sign * ipd / 2.0),
                           w: UInt32(frame.width), h: UInt32(frame.height), ow: UInt32(outW), oh: UInt32(outH),
                           conv: convergence.map { $0 > 0 ? Float(atan2(sign * ipd / 2.0, $0)) : 0 } ?? 0,
                           znear: zNear.map { $0 > 0 ? Float($0) : 0 } ?? 0, mode: flat ? 1 : 0, fout: flat ? Float(foutD) : 0)
            let out = MTLSize(width: outW, height: outH, depth: 1), src = MTLSize(width: frame.width, height: frame.height, depth: 1)
            func dispatch(_ s: MTLComputePipelineState, _ grid: MTLSize) {
                enc.setComputePipelineState(s)
                enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: 16, height: min(16, max(1, grid.height)), depth: 1))
            }
            enc.setBuffer(zb, offset: 0, index: 0); enc.setBytes(&p, length: MemoryLayout<Params>.size, index: 1)
            enc.setTexture(rendered, index: 0); dispatch(clear, out)
            enc.setTexture(depth, index: 0); dispatch(zmin, src)
            var srcFrame = frame
            if options.depthOfField {
                if dofPipe == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_dof") {
                    dofPipe = try? device.makeComputePipelineState(function: fn)
                }
                if let dp = dofPipe {
                    if dofBlurred == nil || dofBlurred!.width != frame.width || dofBlurred!.height != frame.height {
                        dofBlurred = Stereo3DRenderer.texture(device, .rgba8Unorm, frame.width, frame.height)
                    }
                    if let bt = dofBlurred {
                        enc.setComputePipelineState(dp)
                        enc.setTexture(frame, index: 0); enc.setTexture(depth, index: 1); enc.setTexture(bt, index: 2)
                        enc.setBytes(&p, length: MemoryLayout<Params>.size, index: 1)   // review r1: buffer 0 is the z-buffer binding; Params stay at 1 for every kernel
                        enc.dispatchThreads(src, threadsPerThreadgroup: MTLSize(width: 16, height: min(16, max(1, src.height)), depth: 1))
                        srcFrame = bt
                    }
                }
            }
            enc.setTexture(srcFrame, index: 0); enc.setTexture(depth, index: 1); enc.setTexture(rendered, index: 2); dispatch(resolve, src)
            enc.setTexture(rendered, index: 0); enc.setTexture(result, index: 1); enc.setBuffer(flat ? flatFP : gb.fp, offset: 0, index: 2)
            if options.holeFillGradient, fillGradPipe == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_fillgrad") {
                fillGradPipe = try? device.makeComputePipelineState(function: fn)
            }
            enc.setComputePipelineState(options.holeFillGradient ? (fillGradPipe ?? fill) : fill)
            enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))
            if surround, let ps = surroundPipes, scratch.count == 7, let sb = gb.src, let wb = gb.wb, let nb = gb.near, !geo.allInside {
                // r3 soft surround: normalised pre-blur x32 (canvas -> ping -> pong ...), gather the nearest-footprint source, boundary correction, four running-sum boxes (side-local far trend), distance lerp; outside the footprint only
                enc.setBuffer(gb.fp, offset: 0, index: 2); enc.setBuffer(sb, offset: 0, index: 3); enc.setBuffer(wb, offset: 0, index: 4); enc.setBuffer(nb, offset: 0, index: 5)
                var cur: MTLTexture = result
                var bx = geo.footprintBox; enc.setBytes(&bx, length: MemoryLayout<SIMD4<UInt32>>.size, index: 6)          // s31: pre-blur over the footprint box only
                let preGrid = MTLSize(width: Int(bx[2]), height: Int(bx[3]), depth: 1)
                for k in 0..<32 { var first: UInt32 = k == 0 ? 1 : 0; enc.setBytes(&first, length: 4, index: 7); let dst = scratch[k % 2]; enc.setTexture(cur, index: 0); enc.setTexture(dst, index: 1); dispatch(ps[0], preGrid); cur = dst }
                enc.setTexture(cur, index: 0); enc.setTexture(scratch[2], index: 1); enc.setTexture(result, index: 2); dispatch(ps[1], out)          // work (r4: truth = the filled film in `result`)
                enc.setTexture(scratch[2], index: 0); enc.setTexture(scratch[3], index: 1); enc.setTexture(scratch[4], index: 2); enc.setTexture(scratch[5], index: 3); enc.setTexture(scratch[6], index: 4)
                enc.setComputePipelineState(ps[2]); enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))   // row boxes
                enc.setTexture(scratch[3], index: 0); enc.setTexture(scratch[4], index: 1); enc.setTexture(scratch[5], index: 2); enc.setTexture(scratch[6], index: 3); enc.setTexture(result, index: 4)
                enc.setComputePipelineState(ps[3]); enc.dispatchThreads(MTLSize(width: outW, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outW), height: 1, depth: 1))   // column boxes + blend
            }
            var eyeOut = result
            if options.floatingWindow {
                if floatWinPipe == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_floatwin") {
                    floatWinPipe = try? device.makeComputePipelineState(function: fn)
                }
                if let fwp = floatWinPipe, let winTex = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH) {
                    enc.setBuffer(zb, offset: 0, index: 0); enc.setBytes(&p, length: MemoryLayout<Params>.size, index: 1)
                    enc.setTexture(result, index: 0); enc.setTexture(winTex, index: 1)
                    enc.setComputePipelineState(fwp)
                    enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))
                    eyeOut = winTex                                  // pipeline/texture failure keeps the un-windowed eye (experiment only)
                }
            }
            enc.endEncoding(); eyes.append(eyeOut)
        }
        guard let enc = cb.makeComputeCommandEncoder() else { return false }
        var packMode = output.packCode
        enc.setComputePipelineState(flat ? packPipe! : sbs); enc.setTexture(eyes[0], index: 0); enc.setTexture(eyes[1], index: 1); enc.setTexture(sbsOut, index: 2)
        if flat { enc.setBytes(&packMode, length: 4, index: 0) }
        enc.dispatchThreads(MTLSize(width: flat ? canvas.w : outW * 2, height: flat ? canvas.h : outH, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: min(16, outH), depth: 1))
        enc.endEncoding(); cb.commit(); lastCommandBuffer = cb
        return true
    }

    /// CONTRACT-190v v2 depth: `luma` is the Y plane of a 10-bit biplanar decode (MTLPixelFormat.r16Unorm view of plane 0, VideoToolbox), `metric`
    /// r32Float same size. Z = 256 / (w10/1023*1024) metres, w10 == 0 -> 0 (masked, skipped by s3d_map). `shift` = bits the decoder left of the 10-bit
    /// value (6 for Apple MSB-aligned 420YpCbCr10BiPlanar, 0 if right-aligned): unverified on device, so it is a parameter, not a guess baked in.
    func decodeDepth(luma: MTLTexture, metric: MTLTexture, shift: UInt32 = 6) -> Bool {
        if depth10 == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_depth10") {
            depth10 = try? device.makeComputePipelineState(function: fn)
        }
        guard let pipe = depth10, luma.width == metric.width, luma.height == metric.height, shift <= 6,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return false }
        var sh = shift
        enc.setComputePipelineState(pipe); enc.setTexture(luma, index: 0); enc.setTexture(metric, index: 1); enc.setBytes(&sh, length: 4, index: 0)
        enc.dispatchThreads(MTLSize(width: metric.width, height: metric.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: min(16, metric.height), depth: 1))
        enc.endEncoding(); cb.commit()
        return true
    }

    /// s37 passthrough of an ALREADY-3D source (no depth stage): `left`/`right` = the eye crops of the source frame (readable rgba8/bgra8; half layouts must be upscaled by the caller first).
    /// Baked-stereo (flat) source: flat output modes are lossless repacks (s3d_pack); vr180 output places each eye as a flat screen on the equirect canvas (s3d_remap mode 0, 75 deg screen).
    /// vr180 source: flat output reprojects the forward 75 deg (s3d_remap mode 1), then packs; vr180 -> vr180 is the source itself (returns false: play the file). `sbsOut` = output.canvasSize.
    /// Mirrors stereo_probe.passthrough (Linux parity of the resampling: Tests/Stereo3DKernel/stereo_remap_kernel_test.py). Not run on a Mac.
    func passthrough(left: MTLTexture, right: MTLTexture, sourceIsVR180: Bool, output: OutputMode, swap: Bool, sbsOut: MTLTexture) -> Bool {
        let needsRemap = output == .vr180 || sourceIsVR180, needsPack = output != .vr180     // review F2: each path needs only its own pipelines (a pack failure must not disable vr180 placement)
        guard left.width == right.width, left.height == right.height, !needsRemap || remapPipe != nil, !needsPack || packPipe != nil,
              !(sourceIsVR180 && output == .vr180), let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return false }
        let eyes = swap ? [right, left] : [left, right]
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        func remap(_ src: MTLTexture, _ dst: MTLTexture, mode: UInt32, f: Double) {
            var rm = S3DRemapParams(mode: mode, srcW: UInt32(src.width), srcH: UInt32(src.height), outW: UInt32(dst.width), outH: UInt32(dst.height), f: Float(f), thetaOrHFov: 0)
            enc.setComputePipelineState(remapPipe!); enc.setTexture(src, index: 0); enc.setTexture(dst, index: 1); enc.setBytes(&rm, length: MemoryLayout<S3DRemapParams>.size, index: 0)
            enc.dispatchThreads(MTLSize(width: dst.width, height: dst.height, depth: 1), threadsPerThreadgroup: tg)
        }
        let half = tan(OutputMode.screenDeg * Double.pi / 360.0)
        var out: [MTLTexture] = []
        if output == .vr180 {
            let n = sbsOut.height, f = (Double(left.width) / 2.0) / half
            guard sbsOut.width == 2 * n else { enc.endEncoding(); return false }
            for e in eyes { guard let t = Stereo3DRenderer.texture(device, .rgba8Unorm, n, n) else { enc.endEncoding(); return false }; remap(e, t, mode: 0, f: f); out.append(t) }
            enc.setComputePipelineState(sbs); enc.setTexture(out[0], index: 0); enc.setTexture(out[1], index: 1); enc.setTexture(sbsOut, index: 2)
            enc.dispatchThreads(MTLSize(width: 2 * n, height: n, depth: 1), threadsPerThreadgroup: tg)
        } else {
            let ew: Int, eh: Int
            if sourceIsVR180 { (ew, eh) = (output.eyeW(canvasW: sbsOut.width), output.eyeH(canvasH: sbsOut.height)) } else { (ew, eh) = (left.width, left.height) }
            let c = output.canvasSize(srcW: ew, srcH: eh)
            guard c.w == sbsOut.width, c.h == sbsOut.height, output != .halfSBS || ew % 2 == 0 else { enc.endEncoding(); return false }
            for e in eyes {
                if sourceIsVR180 {
                    guard let t = Stereo3DRenderer.texture(device, .rgba8Unorm, ew, eh) else { enc.endEncoding(); return false }
                    remap(e, t, mode: 1, f: (Double(ew) / 2.0) / half); out.append(t)
                } else { out.append(e) }
            }
            var pm = output.packCode
            enc.setComputePipelineState(packPipe!); enc.setTexture(out[0], index: 0); enc.setTexture(out[1], index: 1); enc.setTexture(sbsOut, index: 2); enc.setBytes(&pm, length: 4, index: 0)
            enc.dispatchThreads(MTLSize(width: c.w, height: c.h, depth: 1), threadsPerThreadgroup: tg)
        }
        enc.endEncoding(); cb.commit(); lastCommandBuffer = cb
        return true
    }
}
struct S3DRemapParams { var mode: UInt32; var srcW: UInt32; var srcH: UInt32; var outW: UInt32; var outH: UInt32; var f: Float; var thetaOrHFov: Float }   // = MSL S3DRemap (7 x 4 bytes)
#endif
// END relocated Stereo3DKernel.swift
// BEGIN relocated SurroundGeometry.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190v s20 (r2): the content-independent half of s3d_surround and the footprint test of s3d_fill's edge-run fill, computed once per geometry on the CPU in float64
/// (the same maths as tools/depth_analysis/reference_render.py footprint_mask / _surround_soft_vec). Why on the CPU: the nearest-footprint extension chooses WHICH footprint pixel
/// every outside pixel copies using only the mask (never the colours), so it is a gather map; the distance blend weight is also mask-only. The GPU then does the
/// colour work (normalised pre-blur, gather, box blur, blend). Pure Foundation: compiled and tested against the Python reference on Linux.
final class SurroundGeometry {
    let ow: Int, oh: Int
    /// 1 = canvas pixel whose direction lands inside the source frustum (the film footprint).
    let inside: [UInt8]
    var allInside: Bool { !inside.contains(0) }
    /// s31 (d): bounding box of the footprint as (x0, y0, w, h); the full canvas when the footprint is empty. The surround pre-blur is dispatched over this box only.
    var footprintBox: SIMD4<UInt32> {
        var x0 = ow, y0 = oh, x1 = -1, y1 = -1
        for y in 0..<oh { for x in 0..<ow where inside[y * ow + x] != 0 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        if x1 < 0 { return SIMD4<UInt32>(0, 0, UInt32(ow), UInt32(oh)) }
        return SIMD4<UInt32>(UInt32(x0), UInt32(y0), UInt32(x1 - x0 + 1), UInt32(y1 - y0 + 1))
    }

    init(w: Int, h: Int, f: Double, conv: Double, ow: Int, oh: Int) {
        self.ow = ow; self.oh = oh
        var m = [UInt8](repeating: 0, count: ow * oh)
        for y in 0..<oh {
            let lat = (0.5 - (Double(y) + 0.5) / Double(oh)) * Double.pi, cl = cos(lat), sl = sin(lat)
            for x in 0..<ow {
                let lon = ((Double(x) + 0.5) / Double(ow) - 0.5) * Double.pi - conv
                let dx = sin(lon) * cl, dy = sl, dz = cos(lon) * cl, dzc = max(dz, 1e-4)
                let sx = f * dx / dzc + Double(w) * 0.5, sy = Double(h) * 0.5 - f * dy / dzc
                if dz > 0 && sx >= 0 && sx < Double(w) && sy >= 0 && sy < Double(h) { m[y * ow + x] = 1 }
            }
        }
        inside = m
    }

    /// Per canvas pixel: the flat index of the footprint pixel whose (pre-blurred) value it copies (itself inside the footprint), -1 where the extension never reaches
    /// (empty footprint). Exact port of the reference's pass structure: 8 directions in the fixed (dy, dx) scan order, each pass reads the state at its start
    /// ("take = unfilled & neighbour filled"), sweeps repeat until a whole sweep takes nothing. Sparse (only pixels next to the filled set are visited).
    private(set) lazy var sourceIndex: [Int32] = {
        let n = ow * oh
        var idx = [Int32](repeating: -1, count: n), filled = [Bool](repeating: false, count: n)
        var active: [Int32] = [], queued = [Bool](repeating: false, count: n)
        for i in 0..<n where inside[i] != 0 { idx[i] = Int32(i); filled[i] = true }
        func enqueueNeighbours(_ p: Int) {
            let y = p / ow, x = p % ow
            for j in -1...1 { for i in -1...1 where !(j == 0 && i == 0) {
                let yy = y + j, xx = x + i
                if yy < 0 || yy >= oh || xx < 0 || xx >= ow { continue }
                let q = yy * ow + xx
                if !filled[q] && !queued[q] { queued[q] = true; active.append(Int32(q)) }
            } }
        }
        for p in 0..<n where filled[p] { enqueueNeighbours(p) }       // O(n) once; the first sweep's candidates
        var progressed = true
        while progressed && !active.isEmpty {
            progressed = false
            for j in -1...1 { for i in -1...1 where !(j == 0 && i == 0) {
                var takes: [(Int32, Int32)] = []
                for q32 in active {
                    let q = Int(q32); if filled[q] { continue }
                    let y = q / ow + j, x = q % ow + i
                    if y < 0 || y >= oh || x < 0 || x >= ow { continue }
                    let s = y * ow + x
                    if filled[s] { takes.append((q32, idx[s])) }
                }
                if takes.isEmpty { continue }
                progressed = true
                for (q, src) in takes { idx[Int(q)] = src; filled[Int(q)] = true }
                for (q, _) in takes { enqueueNeighbours(Int(q)) }
                active = active.filter { !filled[Int($0)] }
                for q in active { queued[Int(q)] = true }
            } }
        }
        return idx
    }()

    /// r4 (CONTRACT-190v s28/s28b): nearest footprint pixel + L1 distance by the reference's slice-shift BFS, ported step for step. Up to 121 iterations; each runs the four
    /// directions (dy, dx) = (-1,0), (1,0), (0,-1), (0,1) in that order; a direction compares dist[y,x] with dist[y+dy, x+dx] + 1 on a SNAPSHOT (numpy computes the whole
    /// slice before assigning), the strictly smaller one wins and copies the source's index. No wrap-around (unlike the r3 dilation). Unreached pixels keep dist 1e9 and index (0, 0).
    /// The in-place loops below reproduce the snapshot by walking against the shift direction, so a pixel never reads a value written in the same direction pass.
    static let bfsSteps = 121, bfsInf: Int32 = 1_000_000_000
    private(set) lazy var nearest: (index: [Int32], dist: [Int32]) = {
        let n = ow * oh, INF = SurroundGeometry.bfsInf
        var dist = [Int32](repeating: INF, count: n), idx = [Int32](repeating: 0, count: n)
        for i in 0..<n where inside[i] != 0 { dist[i] = 0; idx[i] = Int32(i) }
        let dirs: [(Int, Int)] = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for _ in 0..<SurroundGeometry.bfsSteps {
            var changed = false
            for (dy, dx) in dirs {
                let y0 = max(0, -dy), y1 = oh + min(0, -dy), x0 = max(0, -dx), x1 = ow + min(0, -dx)     // destination ranges
                if y0 >= y1 || x0 >= x1 { continue }
                // source = destination + (dy, dx): iterate destinations away from the source side so the source is still the snapshot value
                let ys: [Int] = dy > 0 ? Array(y0..<y1) : Array((y0..<y1).reversed()), xs: [Int] = dx > 0 ? Array(x0..<x1) : Array((x0..<x1).reversed())
                let yOrder = dy == 0 ? Array(y0..<y1) : ys, xOrder = dx == 0 ? Array(x0..<x1) : xs
                for y in yOrder { for x in xOrder {
                    let d = y * ow + x, s = (y + dy) * ow + (x + dx)
                    if dist[s] >= INF { continue }              // rd = 1e9 + 1 is never < dst (<= 1e9)
                    let rd = dist[s] + 1
                    if rd < dist[d] { dist[d] = rd; idx[d] = idx[s]; changed = true }
                } }
            }
            if !changed { break }
        }
        return (idx, dist)
    }()
    var nearIndex: [Int32] { nearest.index }

    /// Per pixel (t1, t2, wcorr, vert), float32 x 4. t1 = clip((dist - 1) / 39, 0, 1) (R1 -> R2), t2 = clip((dist - 40) / 80, 0, 1) (R2 -> far trend), wcorr = clip(1 - dist / 24, 0, 1)
    /// (r4 boundary-correction fade), dist = the BFS L1 distance above (unreached 1e9: t1 = t2 = 1, wcorr = 0). vert = 1 where |y - cy| >= |x - cx| (cy, cx = footprint centroid,
    /// float64): the wide-short 256x64 far-trend window (pixels above/below), else 0 = tall-narrow 64x256. Computed in float64 like the reference.
    static let d2 = 40.0, d3 = 120.0, dCorr = 24.0
    private(set) lazy var blendWeights: [Float] = {
        let n = ow * oh, dist = nearest.dist
        var sy = 0.0, sx = 0.0, cnt = 0.0
        for y in 0..<oh { for x in 0..<ow where inside[y * ow + x] != 0 { sy += Double(y); sx += Double(x); cnt += 1 } }
        let cy = cnt > 0 ? sy / cnt : 0, cx = cnt > 0 ? sx / cnt : 0
        var w = [Float](repeating: 0, count: 4 * n)
        for y in 0..<oh { for x in 0..<ow {
            let i = y * ow + x, dd = Double(dist[i])
            w[4 * i] = Float(min(max((dd - 1.0) / (SurroundGeometry.d2 - 1.0), 0.0), 1.0))
            w[4 * i + 1] = Float(min(max((dd - SurroundGeometry.d2) / (SurroundGeometry.d3 - SurroundGeometry.d2), 0.0), 1.0))
            w[4 * i + 2] = Float(min(max(1.0 - dd / SurroundGeometry.dCorr, 0.0), 1.0))
            w[4 * i + 3] = abs(Double(y) - cy) >= abs(Double(x) - cx) ? 1 : 0
        } }
        return w
    }()

    // Small cache: the geometry only changes with the shot's fov, the canvas size or the eye's convergence angle.
    private static var cache: [(key: [Double], geo: SurroundGeometry)] = []
    private static let lock = NSLock()
    static func cached(w: Int, h: Int, f: Double, conv: Double, ow: Int, oh: Int) -> SurroundGeometry {
        let key = [Double(w), Double(h), f, conv, Double(ow), Double(oh)]
        lock.lock(); defer { lock.unlock() }
        if let hit = cache.first(where: { $0.key == key }) { return hit.geo }
        let g = SurroundGeometry(w: w, h: h, f: f, conv: conv, ow: ow, oh: oh)
        cache.append((key, g)); if cache.count > 4 { cache.removeFirst() }
        return g
    }
}
// END relocated SurroundGeometry.swift
// BEGIN relocated OutputModes.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190v s36 port of tools/depth_analysis/output_modes.py: the output mode set behind the 3D menu. Pure Foundation (compiled and run on Linux, Tests/Stereo3DKernel/output_modes_swift_test.py).
/// The Metal side (Stereo3DKernel.swift) renders the eye with the perspective branch (flat modes) or the equirect180 branch (vr180) and packs with `s3d_pack`.
enum OutputMode: String, CaseIterable {
    case fullSBS = "full_sbs", halfSBS = "half_sbs", overUnder = "over_under", anaglyph, vr180

    static let screenDeg = 75.0                  // the flat modes' virtual screen (perspective fov across the eye width)
    /// Flat display -> full_sbs (full per-eye resolution, universal player support); headset -> vr180.
    static func defaultMode(headset: Bool) -> OutputMode { headset ? .vr180 : .fullSBS }
    /// Menu / prefs spelling. The legacy "sbs" of the pre-s36 menu was the vr180 placeholder; it now means the flat default, full_sbs.
    static func parse(_ s: String) -> OutputMode? { s == "sbs" ? .fullSBS : OutputMode(rawValue: s) }
    var isFlat: Bool { self != .vr180 }
    /// Square VR180 eye side (mirrors ThreeDRenderCoordinator.eyeN).
    static func eyeN(sourceHeight h: Int) -> Int { max(256, min(4096, h - h % 2)) }
    /// (W, H) of the packed output frame for a source of w x h (half_sbs needs an even eye width: callers pass the even-padded proxy size).
    func canvasSize(srcW w: Int, srcH h: Int) -> (w: Int, h: Int) {
        switch self {
        case .fullSBS: return (2 * w, h)
        case .halfSBS: return (w, h)
        case .overUnder: return (w, 2 * h)
        case .anaglyph: return (w, h)
        case .vr180: let n = OutputMode.eyeN(sourceHeight: h); return (2 * n, n)
        }
    }
    /// Per-eye render canvas: the source size for the flat modes, N x N for vr180.
    func eyeSize(srcW w: Int, srcH h: Int) -> (w: Int, h: Int) { isFlat ? (w, h) : (OutputMode.eyeN(sourceHeight: h), OutputMode.eyeN(sourceHeight: h)) }
    /// Frame-packing metadata the player needs (MODE_METADATA): mpv stereo-mode name (nil = ordinary 2D), SAR stretch for half_sbs, spherical V2 for vr180.
    var mpvStereoMode: String? {
        switch self { case .fullSBS, .halfSBS, .vr180: return "sbsl"; case .overUnder: return "abl"; case .anaglyph: return nil }
    }
    var playbackSARStretch: Double { self == .halfSBS ? 2.0 : 1.0 }          // player stretches horizontally 2:1
    var sphericalV2: Bool { self == .vr180 }
    /// s3d_pack mode code: 0 side by side, 1 half sbs, 2 over under, 3 anaglyph (vr180 packs with s3d_sbs).
    var packCode: UInt32 { switch self { case .fullSBS, .vr180: return 0; case .halfSBS: return 1; case .overUnder: return 2; case .anaglyph: return 3 } }

    static let duboisL: [[Float]] = [[0.437, 0.449, 0.164], [-0.062, -0.062, -0.024], [-0.048, -0.050, -0.017]]
    static let duboisR: [[Float]] = [[-0.011, -0.032, -0.007], [0.377, 0.761, 0.009], [-0.026, -0.093, 1.234]]
    /// Per-eye size recovered from a flat canvas (vr180 source reprojected to a flat mode: the eye size is the canvas divided back by the pack).
    func eyeW(canvasW w: Int) -> Int { self == .fullSBS ? w / 2 : w }
    func eyeH(canvasH h: Int) -> Int { self == .overUnder ? h / 2 : h }
}
// END relocated OutputModes.swift
// BEGIN relocated ThreeDPresentation.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190t part I: what the viewer sees when. Open = 2D at once. When rendered 3D covers the playhead the picture crossfades 2D -> 3D
/// over `fadeSeconds`. A seek into the rendered range shows 3D instantly (no fade); a seek outside it drops to 2D until it is covered.
/// A shot change clears the per-shot state (depth / FoV are never carried across a cut). Pure state: the caller supplies time and coverage.
struct ThreeDPresentation: Equatable {
    static let fadeSeconds = 0.5
    enum Phase: Equatable { case flat, fading(since: Double), solid }
    private(set) var phase: Phase = .flat
    private(set) var shot: Int?

    /// 0 = 2D only, 1 = 3D only.
    func alpha(now: Double) -> Double {
        switch phase {
        case .flat: return 0
        case .solid: return 1
        case .fading(let t0): return max(0, min(1, (now - t0) / ThreeDPresentation.fadeSeconds))
        }
    }

    /// `covered`: rendered 3D exists for the playhead. `shot`: shot index at the playhead (nil = unknown). `seeked`: the playhead jumped.
    /// Returns true when per-shot depth/FoV state must be dropped (shot changed).
    @discardableResult
    mutating func update(now: Double, covered: Bool, shot newShot: Int?, seeked: Bool, enabled: Bool) -> Bool {
        let cut = newShot != shot
        shot = newShot
        guard enabled, covered else { phase = .flat; return cut }
        switch phase {
        case .flat: phase = seeked ? .solid : .fading(since: now)
        case .fading(let t0): if now - t0 >= ThreeDPresentation.fadeSeconds { phase = .solid }
        case .solid: break
        }
        return cut
    }
}
// END relocated ThreeDPresentation.swift
// BEGIN relocated SubtitleDepth.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190t part H: subtitle / OSD depth placement. One distance per subtitle event: the nearest valid depth under the event's box
/// minus a margin, so text never sits behind the picture it overlaps. Constant for the whole event (no per-frame jitter).
/// Depth samples are 10-bit w10 from the depth mp4 (CONTRACT-190v section 1): Z = 256 / (w10 / 1023 * 1024) metres, w10 == 0 = masked.
struct SubtitleDepth {
    static let marginM = 0.10, minZ = 0.30, maxZ = 50.0, fallbackZ = 2.0
    private var placed: [Int: Double] = [:]

    static func metres(w10: Int) -> Double? { w10 > 0 ? 256.0 / (Double(w10) / 1023.0 * 1024.0) : nil }

    /// Pure rule. `w10` = depth samples inside the event box (any order). No valid sample -> fallbackZ.
    static func placement(w10: [Int], margin: Double = marginM) -> Double {
        guard let near = w10.compactMap({ metres(w10: $0) }).min() else { return fallbackZ }
        return min(maxZ, max(minZ, near - margin))
    }

    /// First call for an event id fixes its distance; later calls (other frames of the same event) return the same value.
    mutating func distance(event: Int, w10: @autoclosure () -> [Int]) -> Double {
        if let z = placed[event] { return z }
        let z = SubtitleDepth.placement(w10: w10()); placed[event] = z; return z
    }
    mutating func end(event: Int) { placed.removeValue(forKey: event) }
}
// END relocated SubtitleDepth.swift
// BEGIN relocated ThreeDSubtitleDepth.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AVFoundation)
import AVFoundation
import CoreVideo
#endif

/// 190t H: subtitle depth while a ready 3D shot plays. The existing dial (VR180Controller.subtitleDepthPoints, a dimensionless factor: crossed
/// disparity = eye width * 0.004 * factor for subtitles) is replaced by a factor derived from the rendered geometry: SubtitleDepth.placement
/// of the depth under the subtitle band, then the renderer's own disparity rule (eye offset ipd/2 each way, screen at `convergence`), as a
/// fraction of the picture width f*2*tan(thetaH/2). No per-film constants. Not 3D (or no sample yet) = the user's dial, untouched.
/// Per SHOT, not per event: the subtitle event boxes are not visible at the dial path. The band is a fixed bottom strip of the picture.
final class ThreeDSubtitleDepth {
    static let shared = ThreeDSubtitleDepth()
    static let band = (x0: 0.10, x1: 0.90, y0: 0.78, y1: 0.95), perSubtitleFraction = 0.004, dialLimit = 8.0
    var changed: (() -> Void)?                       // set by the wiring: re-run the subtitle geometry pass
    private let lock = NSLock(), queue = DispatchQueue(label: "gor.3d.subdepth", qos: .utility)
    private var factor: Double?, token = 0

    /// The dial the placement code should use: the 3D-derived factor while a ready 3D shot plays, else `base`.
    static func dial(_ base: Double) -> Double { shared.lock.lock(); defer { shared.lock.unlock() }; return shared.factor ?? base }

    // Prepared-depth experiment only. No new live-plane estimate or GPU readback.
    private var experimental = false
    static var experimentalOn: Bool { shared.lock.lock(); defer {shared.lock.unlock()}; return shared.experimental }
    static func setExperimental(_ on: Bool) {
        shared.lock.lock(); shared.experimental=on
        shared.captionEvent=nil; shared.captionPX=nil; shared.captionTime=nil
        shared.lock.unlock(); shared.changed?()
    }
    private var nearestFraction: Double?, captionEvent: String?, captionPX: Double?, captionTime: Double?
    #if canImport(AVFoundation)
    private var preparedContext: (URL, Double, RenderParams)?
    private var sampleBusy = false
    #endif

    /// A physical-pixel margin, not metres. Elapsed-time form of k=.15 and
    /// .5px/frame at24fps, so geometry calls cannot change smoothing speed.
    static func captionTarget(nearest: Double, width: Double, previous: Double?, dt: Double) -> Double {
        let target = max(0, min(width * 0.010, nearest * width + 1.5))
        guard let previous else { return target }
        let frames = max(0, dt * 24), k = 1 - pow(0.85, frames)
        let step = (target - previous) * k, slew = 0.5 * frames
        return max(0, min(width * 0.010, previous + max(-slew, min(slew, step))))
    }
    static func subtitleFraction(base: Double, width: Double, event: String?, now: Double) -> Double {
        guard experimentalOn, width.isFinite, width > 0 else { return base }
        shared.lock.lock(); defer { shared.lock.unlock() }
        guard let event, let nearest = shared.nearestFraction else {
            shared.captionEvent=nil; shared.captionPX=nil; shared.captionTime=nil; return base
        }
        let previous = shared.captionEvent == event ? shared.captionPX : nil
        let dt = shared.captionTime.map { max(0, now - $0) } ?? 0
        let value = captionTarget(nearest:nearest,width:width,previous:previous,dt:dt)
        shared.captionEvent=event; shared.captionTime=now; shared.captionPX=value
        return value / width
    }

    /// Crossed disparity (positive = nearer than the screen) as a fraction of the picture width.
    static func disparityFraction(z: Double, ipd: Double, convergence: Double?, thetaH: Double) -> Double {
        guard z > 0, ipd > 0, thetaH > 0, thetaH < Double.pi else { return 0 }
        let screenAngle = (convergence ?? 0) > 0 ? 2 * atan2(ipd / 2, convergence!) : 0
        return (2 * atan2(ipd / 2, z) - screenAngle) / (2 * tan(thetaH / 2))
    }
    static func factor(z: Double, ipd: Double, convergence: Double?, thetaH: Double) -> Double {
        max(0, min(dialLimit, disparityFraction(z: z, ipd: ipd, convergence: convergence, thetaH: thetaH) / perSubtitleFraction))
    }

    /// What the render of this shot used (CONTRACT s25/s27): eye offset, convergence plane z_c and near clamp. Under the comfort policy these are per shot
    /// (ipd * B_eff/IPD * strength factor, z_c = shot median depth, z_near); otherwise the fixed prefs values and no clamp.
    struct RenderParams: Equatable { var ipd: Double, convergence: Double?, zNear: Double? }
    /// Pure: exactly the arguments the coordinator hands RenderShotWriter.write (ipd:, convergence:, zNear:), so the subtitle dial follows the same geometry as the picture.
    static func params(ipdM: Double, effectiveIPD: Double, convergenceM: Double?, comfort: ShotComfort?, comfortIPD: Double?) -> RenderParams {
        guard let c = comfort else { return RenderParams(ipd: effectiveIPD, convergence: convergenceM, zNear: nil) }
        return RenderParams(ipd: comfortIPD ?? ipdM * c.depthScale, convergence: c.convergenceM, zNear: c.zNear)
    }
    /// The render clamps scene depth to >= z_near before projecting; the subtitle is placed against the depth the viewer actually sees there.
    static func seenZ(_ z: Double, zNear: Double?) -> Double { zNear.map { max(z, $0) } ?? z }

    func end() { lock.lock(); token += 1; let had = factor != nil; factor = nil
        nearestFraction=nil; captionEvent=nil; captionPX=nil; captionTime=nil
        #if canImport(AVFoundation)
        preparedContext=nil
        #endif
        lock.unlock(); if had { DispatchQueue.main.async { self.changed?() } } }

    #if canImport(AVFoundation)
    /// Samples the depth under the band at `pts` on a utility queue, then sets the factor and asks for one geometry pass.
    /// `render` runs on the utility queue (it may read the whole shot container for the comfort median) and must return what the render of this shot used.
    func begin(depth: URL, pts: Double, thetaH: Double, render: @escaping () -> RenderParams) {
        lock.lock(); token += 1; let t = token; lock.unlock()
        queue.async { [self] in
            let samples = Self.sampleBand(depth, at: pts, rows:Self.experimentalOn ? 4:6)
            let z = SubtitleDepth.placement(w10: samples)
            let r = render()
            let f = Self.factor(z: Self.seenZ(z, zNear: r.zNear), ipd: r.ipd, convergence: r.convergence, thetaH: thetaH)
            lock.lock(); let ok = token == t
            if ok {
                factor = f
                preparedContext=(depth,thetaH,r)
                if experimental {
                    captionEvent=nil; captionPX=nil; captionTime=nil
                    nearestFraction=samples.compactMap { SubtitleDepth.metres(w10:$0) }.min().map {
                        Self.disparityFraction(z:Self.seenZ($0,zNear:r.zNear),ipd:r.ipd,convergence:r.convergence,thetaH:thetaH)
                    }
                }
            }
            lock.unlock()
            if ok { DispatchQueue.main.async { self.changed?() } }
        }
    }

    /// Real mapped playhead from the coordinator; no wall-clock media estimate.
    /// At most one utility sample in flight. end()/new shot fence completion.
    func refreshPrepared(pts: Double) {
        guard Self.experimentalOn, pts.isFinite else { return }
        lock.lock()
        guard !sampleBusy, let (url,theta,r)=preparedContext else { lock.unlock(); return }
        let t=token; sampleBusy=true; lock.unlock()
        queue.async { [self] in
            let samples=Self.sampleBand(url,at:pts,rows:4)
            let nearest=samples.compactMap { SubtitleDepth.metres(w10:$0) }.min().map {
                Self.disparityFraction(z:Self.seenZ($0,zNear:r.zNear),ipd:r.ipd,convergence:r.convergence,thetaH:theta)
            }
            lock.lock(); sampleBusy=false; let ok=token==t
            if ok, let nearest { nearestFraction=nearest }
            lock.unlock()
            if ok, nearest != nil { DispatchQueue.main.async { self.changed?() } }
        }
    }

    /// w10 samples (grid over the band) of the first container frame at/after `pts` (lossless w10, no shift). [] on any failure.
    static func sampleBand(_ url: URL, at pts: Double, rows: Int = 6) -> [Int] {
        guard let f = DZCFile(url: url), let p = f.plane(f.index(atOrAfter: pts)) else { return [] }
        let w = Int(f.meta.width), h = Int(f.meta.height)
        var s: [Int] = []
        for j in 0..<rows { for i in 0..<16 {
            let x = min(w - 1, Int((band.x0 + (band.x1 - band.x0) * (Double(i) + 0.5) / 16) * Double(w)))
            let y = min(h - 1, Int((band.y0 + (band.y1 - band.y0) * (Double(j) + 0.5) / Double(rows)) * Double(h)))
            s.append(Int(p[y * w + x]))
        } }
        return s
    }
    #endif
}

/// Container fps and estimated frame count of the open film, fed from the player's observed properties (PPController results), keyed by path.
final class ThreeDFilmInfo {
    static let shared = ThreeDFilmInfo()
    private let lock = NSLock(); private var path: String?, fps = 0.0, frames = 0
    func set(path: String?, fps: Double?, frames: Int?) {
        lock.lock(); defer { lock.unlock() }
        if path != self.path { self.path = path; self.fps = 0; self.frames = 0 }
        if let f = fps, f.isFinite, f > 0 { self.fps = f }
        if let n = frames, n > 0 { self.frames = n }
    }
    /// (fps, frames) for `film`, nil until both are known for that exact file.
    func info(for film: URL) -> (fps: Double, frames: Int)? {
        lock.lock(); defer { lock.unlock() }
        return path == film.path && fps > 0 && frames > 0 ? (fps, frames) : nil
    }
}
// END relocated ThreeDSubtitleDepth.swift
// BEGIN relocated ThreeDShotPlayLog.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// X1 (190x, A-D request 14:41): the gor log of a played film never said which 3D render a shot was played with, so a diag pack could not be tied to
/// a method, IPD, convergence or mode. One `gor3d-shot v1` line per shot the moment it starts showing, plus one `gor3d-osd v1` line per distinct OSD
/// text (written even when the "osd line" menu toggle is off, so the pack carries what the owner would have seen). Both go to stdout, i.e. the same
/// gor log the first-Mac kit uploads. Text only: no setting, pixel or timing changes. Not compiled on a Mac yet; the pure formatters are pinned on
/// Linux by Tests/FirstMacKit (field names and order must match the render key v4 format of ThreeDRenderCoordinator.key).
enum ThreeDShotPlayLog {
    /// Field order of render key v4, split on "|": comfort keys carry three ipd fields (comfort|ipd..|sf..), fixed keys carry two (fixed|ipd..).
    static let keyFields = ["version", "method", "ipd", "mode", "convergence", "eye_n", "codec", "swap", "screen_deg", "surround"]

    /// Pure: `gor3d-shot v1 shot=<n> pts=<s> menu_mode=<name> method=.. ipd=comfort/ipd0.063/sf1.0 mode=.. convergence=.. eye_n=.. codec=.. swap=.. screen_deg=.. surround=.. key=<full key>`.
    /// A key that does not parse is still logged whole (key=) with parsed=no, never dropped.
    static func shotLine(shot: Int, pts: Double, menuMode: String, key: String) -> String {
        var parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.count > 1, parts[0] == "v5", parts[1] == "span-p5p95" { parts.remove(at: 1); parts[0] = "v4" }
        let head = "gor3d-shot v1 shot=\(shot) pts=\(String(format: "%.3f", pts)) menu_mode=\(clean(menuMode))"
        guard parts.count >= 10, parts[0] == "v4" else { return head + " parsed=no key=\(key)" }
        let comfort = parts[2] == "comfort"
        let ipdLen = comfort ? 3 : 2
        guard parts.count == 9 + ipdLen else { return head + " parsed=no key=\(key)" }
        let ipd = parts[2..<(2 + ipdLen)].joined(separator: "/")
        let rest = Array(parts[(2 + ipdLen)...])
        let names = ["mode", "convergence", "eye_n", "codec", "swap", "screen_deg", "surround"]
        let tail = zip(names, rest).map { "\($0)=\($1)" }.joined(separator: " ")
        return head + " parsed=yes method=\(parts[1]) ipd=\(ipd) \(tail) key=\(key)"
    }

    /// Pure: the OSD line. Text keeps its spaces (it is the tail of the line, like `note` text in PrepareTelemetry).
    static func osdLine(_ text: String) -> String { "gor3d-osd v1 " + text.replacingOccurrences(of: "\n", with: " ") }

    /// Pure: menu mode names never contain spaces or pipes, so the line stays one token per field.
    static func clean(_ s: String) -> String { s.isEmpty ? "none" : String(s.map { $0 == " " || $0 == "|" ? Character("_") : $0 }) }

    /// Pure: `gor3d-shot v1 k=v k=v ... key=<key>` back into a dictionary (the key value is everything after `key=`, it contains pipes but no spaces).
    /// Returns nil for any other line. Used by the pins here and available to the log checkers.
    static func parse(line: String) -> [String: String]? {
        let prefix = "gor3d-shot v1 "
        guard line.hasPrefix(prefix) else { return nil }
        var out: [String: String] = [:]
        for token in line.dropFirst(prefix.count).split(separator: " ") {
            guard let eq = token.firstIndex(of: "=") else { return nil }
            out[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        return out
    }

    /// Pure: how many shots were played per synthesis method in a log (for a one-line summary in diag packs). Lines that do not parse are skipped.
    static func methodCounts(_ lines: [String]) -> [String: Int] {
        var n: [String: Int] = [:]
        for l in lines { if let f = parse(line: l), f["parsed"] == "yes", let m = f["method"] { n[m, default: 0] += 1 } }
        return n
    }

    /// Pure: the field names a complete parsed line must carry, for the pin and for any consumer that wants to reject a half line.
    static let requiredParsed = ["shot", "pts", "menu_mode", "parsed", "method", "ipd", "mode", "convergence", "eye_n", "codec", "swap", "screen_deg", "surround", "key"]

    /// Most recent shot index logged, nil after a shot ended; exposed read-only so a test or the diag pack can tell whether a shot is being shown.
    static var currentShot: Int? { lock.lock(); defer { lock.unlock() }; return lastShot }

    private static let lock = NSLock()
    private static var seenOSD = Set<String>(), lastShot: Int?

    /// Called where a shot starts showing. A shot logs once per start; re-showing the same shot index back to back does not repeat the line.
    static func logShot(shot: Int, pts: Double, menuMode: String, key: String) {
        lock.lock(); let again = lastShot == shot; lastShot = shot; lock.unlock()
        guard !again else { return }
        print(shotLine(shot: shot, pts: pts, menuMode: menuMode, key: key)); fflush(stdout)
    }

    /// Called for every OSD text the 3D coordinator would announce, before the "osd line" toggle is read. Each distinct text is logged once per launch.
    static func logOSD(_ text: String) {
        lock.lock(); let fresh = seenOSD.insert(text).inserted; lock.unlock()
        guard fresh else { return }
        print(osdLine(text)); fflush(stdout)
    }

    /// The shot stopped showing (back to 2D): its next start logs again.
    static func shotEnded() { lock.lock(); lastShot = nil; lock.unlock() }

    /// Forgotten between films so the next film logs its first shot and its OSD lines again.
    static func reset() { lock.lock(); seenOSD.removeAll(); lastShot = nil; lock.unlock() }
}
// END relocated ThreeDShotPlayLog.swift
