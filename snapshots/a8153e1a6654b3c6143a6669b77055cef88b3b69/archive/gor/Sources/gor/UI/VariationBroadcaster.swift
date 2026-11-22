// ================================================================
//  VariationBroadcaster.swift - mouse/audio axis signal source + helpers
//  Owns: AudioNormalizer (AGC), 60fps tick, smoothAudio, listener fan-out,
//  DriveProfile, applyVariation helpers
//  Answers: I4 I8 I9 I10 I15 · TRAP-05
//  Contract: listeners read smoothAudio via audioBlend(proxCurve), never
//  SCE.currentAudioLevel directly (I9)
// ================================================================
import AppKit
import CoreText

// ================================================================
//  AudioNormalizer - mean-centered AGC, single source for audio->axis
//  normalization. Returns shaped [0,1]; caller applies its own smoother.
// ================================================================

struct AudioNormalizer {

    // ── USER-TUNABLE ─────────────────────────────────────────────
    // I10: never hardcode these values anywhere else; retune only here.
    static let meanTau:            Double = 4.0    // s - long-term mean tracker (scene change settles ~4-8s)
    static let peakAttackTau:      Double = 0.005  // s - peak grab on loud transients
    static let peakDecayTau:       Double = 3.0    // s - peak release after loud passage
    static let varianceTau:        Double = 2.0    // s - E[(level-mean)^2] tracker; faster than mean so it
                                                   // adapts to scenes without chasing beats
    static let gamma:              Double = 0.70   // pow() shaping; lifts quiet passages
    static let volumeSensitivity:  Double = 0.20   // 0-1 blend invariant vs raw level - I10 range 0.10-0.50
    static let attackTau:          Double = 0.018  // s - smoother attack (snappy on beats) - I10
    static let releaseTau:         Double = 0.140  // s - smoother release (organic decay) - I10

    // ── SV axis band - full-range t-space [0,1] ──────────────────
    // Band within the full axis range the SV wght pipeline uses, derived
    // from the original hardcoded [300,700] wght against the default font
    // (min=100, max=900): (300-100)/800 = 0.25, (700-100)/800 = 0.75.
    // Scales proportionally on custom fonts; no axis values hardcoded.
    static let svAxisLow:  Double = 0.20   // shaped=0 -> quiet/thin end
    static let svAxisHigh: Double = 0.82   // shaped=1 -> loud/bold end

    // ── Per-instance smooth state (SV axis-space smoother) ──────
    private var _smoothAxis: Double = Self.svAxisLow

    /// Shaped [0,1] -> axis-space smooth -> tFull [0,1] for
    /// PhotonFont.buildSVVars(signal0T:). TRAP-05: the smoother runs in
    /// axis-space, never t-space (t-space compresses dynamics).
    mutating func smoothForAxis(level: Double, dt: Double) -> Double {
        guard let shaped = acceptedSample(level: level, dt: dt) else {
            return (_smoothAxis - Self.svAxisLow) / (Self.svAxisHigh - Self.svAxisLow)
        }
        let raw    = Self.svAxisLow + shaped * (Self.svAxisHigh - Self.svAxisLow)

        let tau   = raw > _smoothAxis ? Self.attackTau : Self.releaseTau
        let alpha = 1.0 - exp(-dt / tau)
        _smoothAxis += alpha * (raw - _smoothAxis)

        return (_smoothAxis - Self.svAxisLow) / (Self.svAxisHigh - Self.svAxisLow)
    }

    // ── State (per-instance) ─────────────────────────────────────
    private var agcMean:     Double = 0.5
    private var agcPeak:     Double = 0.01
    private var agcVariance: Double = 0.04   // initial stdDev ~0.2, avoids zero-div at startup

    /// Feed one raw audio sample, get back shaped [0,1].
    /// dt = elapsed seconds since last call (clamped externally to 0.1s max).
    // The last accepted shaped sample is the hold value for invalid input.
    private var lastShaped: Double = 0

    /// Feed one sample transactionally. A rejected sample changes no state.
    private mutating func acceptedSample(level: Double, dt: Double) -> Double? {
        guard level.isFinite, dt.isFinite, dt >= 0 else { return nil }
        let meanAlpha = 1.0 - exp(-dt / Self.meanTau)
        var nextMean = agcMean + meanAlpha * (level - agcMean)
        nextMean = max(0.01, nextMean)

        let peakTau = level > agcPeak ? Self.peakAttackTau : Self.peakDecayTau
        let peakAlpha = 1.0 - exp(-dt / peakTau)
        var nextPeak = agcPeak + peakAlpha * (max(level, 0.01) - agcPeak)
        nextPeak = max(nextPeak, 0.01)

        let varAlpha = 1.0 - exp(-dt / Self.varianceTau)
        let diff = level - nextMean
        let square = diff * diff
        let nextVariance = agcVariance + varAlpha * (square - agcVariance)
        guard nextMean.isFinite, nextPeak.isFinite, square.isFinite,
              nextVariance.isFinite, nextVariance >= 0 else { return nil }
        let stdDev = max(sqrt(nextVariance), 0.01)
        let stdDevNorm = max(0.0, min(1.0, 0.5 + diff / (stdDev * 3.0)))
        let blended = stdDevNorm * (1.0 - Self.volumeSensitivity)
                    + level * Self.volumeSensitivity
        let shaped = blended > 0 ? pow(blended, Self.gamma) : 0.0
        // This helper's delivered contract is shaped [0,1]. Refuse invalid
        // derived values instead of clamping and contaminating future state.
        guard shaped.isFinite, shaped >= 0, shaped <= 1 else { return nil }
        agcMean = nextMean
        agcPeak = nextPeak
        agcVariance = nextVariance
        lastShaped = shaped
        return shaped
    }

    /// Feed one raw audio sample, or hold the last accepted shaped value.
    mutating func tick(level: Double, dt: Double) -> Double {
        acceptedSample(level: level, dt: dt) ?? lastShaped
    }
}

// ================================================================
//  VariationBroadcaster - 60fps mouse/audio fan-out to axis listeners
// ================================================================

/// Weak liveness probe for opt-in listener pruning; independent of the
/// closure's own [weak self] capture.
final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
    var isAlive: Bool { value != nil }
}

final class VariationBroadcaster {
    static let shared = VariationBroadcaster()
    private init() {}

    private(set) var mouseWindowPt: CGPoint = CGPoint(x: -9999, y: -9999)

    // MARK: - State

    // liveness is opt-in: entries without one are never pruned and rely on
    // their own [weak self] guard becoming a no-op.
    private var listeners: [(token: UUID, block: () -> Void, liveness: WeakBox?, site: String)] = []
    private var updateTimer: Timer?
    private var fanoutGovernor = FanoutGovernor()
    private var audioFanoutCoalescer = AudioFanoutCoalescer()
    /// Listeners of NSView lifetimes that were skipped because their view is not effectively visible (output invisible).
    /// They re-run as soon as the view is visible again (sweep in the timer, 4 Hz), so a shown view never keeps a stale font.
    private var skippedHidden = Set<UUID>()
    private var siteRuns: [String: Int] = [:]
    private(set) var hiddenSkips = 0
    private var callbackPhase = "idle"
    private var callbackEnteredAt: Double = 0
    private var callbackCompletedAt: Double = 0
    private var listenerInFlight: UUID?
    private var listenerEnteredAt: Double = 0
    private var notifyDepth = 0
    private var listenerSite = "none"
    private var openPath = "launch"

    func noteOpenPath(_ path: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.noteOpenPath(path) }
            return
        }
        openPath = path
        print("[VB][open] path=\(path) \(clockStatus())")
    }

    /// Independent main-queue status: does not reset any clock or capture.
    func clockStatus() -> String {
        dispatchPrecondition(condition: .onQueue(.main))
        let now = CACurrentMediaTime()
        let mode = RunLoop.main.currentMode?.rawValue ?? "none"
        return "source=NSTimer openPath=\(openPath) listenerSite=\(listenerSite) valid=\(updateTimer?.isValid ?? false) fireIn=\(updateTimer?.fireDate.timeIntervalSinceNow ?? -1) mode=\(mode) phase=\(callbackPhase) enteredAge=\(callbackEnteredAt > 0 ? now - callbackEnteredAt : -1) completedAge=\(callbackCompletedAt > 0 ? now - callbackCompletedAt : -1) listener=\(listenerInFlight?.uuidString ?? "none") listenerAge=\(listenerEnteredAt > 0 ? now - listenerEnteredAt : -1) depth=\(notifyDepth) ticks=\(diagnosticTicks) fanouts=\(diagnosticFanouts)"
    }

    private var cleanupCounter = 0
    private var diagnosticTicks: UInt64 = 0
    private var diagnosticFanouts: UInt64 = 0
    private var diagnosticLastReport: Double = 0
    private var diagnosticRawMin: Double = 1
    private var diagnosticRawMax: Double = 0
    private var diagnosticFanoutWindowMS: Double = 0
    private var diagnosticFanoutMaxMS: Double = 0
    private var diagnosticFanoutSamples: Int = 0

    // ── No-op tick suppression ───────────────────────────────────
    // Pointer movement fans out immediately; audio-only movement fans out only
    // when it crosses PhotonFont's quantized cache bucket, coalesced off the
    // video-frame cadence by AudioFanoutCoalescer.
    private var lastNotifiedMouseWindowPt: CGPoint = CGPoint(x: -9999, y: -9999)
    private static let NoOpMouseThreshold: CGFloat = 0.5   // points - below visible change

    // ── Listener pruning ─────────────────────────────────────────
    // Tokenless listeners outlive their owners as no-ops; periodic
    // compaction removes only entries that opted in via weakLifetime.
    private static let CleanupIntervalTicks = 300  // ~5s at 60fps

    // MARK: - Smoothed audio (UI envelope)

    // Pipeline: AudioNormalizer.tick() -> shaped [0,1] -> asymmetric exp
    // smoother -> smoothAudio [0,1].
    // I9: all UI listeners read smoothAudio (via audioBlend); never read
    // SCE.currentAudioLevel directly.
    private(set) var smoothAudio: Double = 0.0
    private(set) var perceptualAudio: Double = 0.0   // shaped [0,1], pre-smoother
    private var smoothAudioLastTime: Double = 0
    // audio share of wght when the mouse is absent - I8
    static let audioWeight: Double = 0.85

    private var normalizer = AudioNormalizer()

    // MARK: - Updates

    func startUpdates() {
        // I15: never start a second timer loop.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startUpdates() }
            return
        }
        guard updateTimer == nil else { return }
        MainLoopLoad.shared.start()
        print("[VB][next] start main=\(Thread.isMainThread) listeners=\(listeners.count)")
        // 16ms Timer ≈ 60fps. Simple, main-thread-safe, no CVDisplayLink jitter.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.callbackEnteredAt = CACurrentMediaTime()
            self.callbackPhase = "audio"
            defer {
                self.callbackPhase = "idle"
                self.callbackCompletedAt = CACurrentMediaTime()
            }
            self.tickAudio()
            self.diagnosticTicks &+= 1
            let raw = Double(ScreenCaptureEngine.shared.currentAudioLevel)
            self.diagnosticRawMin = min(self.diagnosticRawMin, raw)
            self.diagnosticRawMax = max(self.diagnosticRawMax, raw)
            let now = CACurrentMediaTime()
            if self.diagnosticTicks == 1 || now - self.diagnosticLastReport >= 10 {
                let fanoutAvgMS = self.diagnosticFanoutSamples > 0 ? self.diagnosticFanoutWindowMS / Double(self.diagnosticFanoutSamples) : 0
                print("[VB][next] tick=\(self.diagnosticTicks) fanouts=\(self.diagnosticFanouts) listeners=\(self.listeners.count) mouse=\(self.mouseWindowPt) rawRange=\(self.diagnosticRawMin)...\(self.diagnosticRawMax) smooth=\(self.smoothAudio) fanout_ms=\(String(format: "%.2f", fanoutAvgMS))/\(String(format: "%.2f", self.diagnosticFanoutMaxMS)) audio_skips=\(self.audioFanoutCoalescer.sameBucketSkips)+\(self.audioFanoutCoalescer.coalesced) [heat] main_load=\(String(format: "%.2f", MainLoopLoad.shared.load)) proc_cpu_pct=\(String(format: "%.0f", HeatTelemetry.processCPUPercent())) governed=\(self.fanoutGovernor.governed) governor=\(HeatTelemetry.governorEnabled ? "on" : "off") hidden_skips=\(self.hiddenSkips) top_sites_10s=[\(self.heatSiteSummary())] font_changed_over_same_10s=[\(HeatTelemetry.fontSiteSummary())] mpv_cpu_pct=\(HeatTelemetry.mpvCPUPercent()) vision_frames=\(HeatTelemetry.visionFrames)")
                self.diagnosticLastReport = now
                self.diagnosticRawMin = raw
                self.diagnosticRawMax = raw
                self.diagnosticFanoutWindowMS = 0
                self.diagnosticFanoutMaxMS = 0
                self.diagnosticFanoutSamples = 0
            }

            let dx = self.mouseWindowPt.x - self.lastNotifiedMouseWindowPt.x
            let dy = self.mouseWindowPt.y - self.lastNotifiedMouseWindowPt.y
            let mouseMoved = (dx * dx + dy * dy) > (Self.NoOpMouseThreshold * Self.NoOpMouseThreshold)
            let audioBucketChanged = self.audioFanoutCoalescer.hasBucketChange(self.smoothAudio)

            if !self.skippedHidden.isEmpty, self.diagnosticTicks % 15 == 0 { self.runResumedListeners() }
            guard mouseMoved || audioBucketChanged else { return }
            if HeatTelemetry.governorEnabled,
               !self.fanoutGovernor.allow(now: now, audioOnly: !mouseMoved, load: MainLoopLoad.shared.load) { return }
            if mouseMoved {
                self.audioFanoutCoalescer.noteFanout(now: now, smoothAudio: self.smoothAudio)
            } else {
                guard self.audioFanoutCoalescer.allow(now: now, smoothAudio: self.smoothAudio) else { return }
            }

            self.lastNotifiedMouseWindowPt = self.mouseWindowPt
            let fanoutBegan = CACurrentMediaTime()
            self.notifyListeners()
            let fanoutMS = (CACurrentMediaTime() - fanoutBegan) * 1000
            self.diagnosticFanoutWindowMS += fanoutMS
            self.diagnosticFanoutMaxMS = max(self.diagnosticFanoutMaxMS, fanoutMS)
            self.diagnosticFanoutSamples += 1
        }
        RunLoop.main.add(updateTimer!, forMode: .common)
    }

    /// Re-run listeners skipped while hidden once their view is visible again (same block a fan-out would have run).
    private func runResumedListeners() {
        for entry in listeners where skippedHidden.contains(entry.token) {
            guard let view = entry.liveness?.value as? NSView, view.isEffectivelyVisible else { continue }
            skippedHidden.remove(entry.token); siteRuns[entry.site, default: 0] += 1
            entry.block()
        }
    }

    func heatSiteSummary() -> String {
        let top = siteRuns.sorted { $0.value > $1.value }.prefix(4).map { "\($0.key.split(separator: "/").last ?? "")=\($0.value)" }
        siteRuns.removeAll(keepingCapacity: true)
        return top.joined(separator: ",")
    }

    func stopUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// Force one listener fan-out regardless of the no-op suppression.
    /// PhotonFont calls this after a face change so listeners re-apply
    /// driven fonts built from the new face without waiting for mouse or
    /// audio motion. Main-thread only: listeners touch views.
    func poke() {
        dispatchPrecondition(condition: .onQueue(.main))
        lastNotifiedMouseWindowPt = mouseWindowPt
        audioFanoutCoalescer.noteFanout(now: CACurrentMediaTime(), smoothAudio: smoothAudio)
        notifyListeners()
    }

    private func tickAudio() {
        let now = CACurrentMediaTime()
        let dt  = smoothAudioLastTime > 0 ? min(now - smoothAudioLastTime, 0.1) : (1.0 / 60.0)
        smoothAudioLastTime = now
        let rawLevel = Double(ScreenCaptureEngine.shared.currentAudioLevel)

        perceptualAudio = normalizer.tick(level: rawLevel, dt: dt)

        let tau   = perceptualAudio > smoothAudio ? AudioNormalizer.attackTau : AudioNormalizer.releaseTau
        let alpha = 1.0 - exp(-dt / tau)
        smoothAudio += alpha * (perceptualAudio - smoothAudio)
    }

    func update(windowPt: CGPoint) {
        mouseWindowPt = windowPt
    }

    // I4: no pendingUpdate guard here - fires on every qualifying tick.
    private func notifyListeners() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        diagnosticFanouts &+= 1
        let previousPhase = callbackPhase
        let previousListener = listenerInFlight
        let previousListenerAt = listenerEnteredAt
        let previousSite = listenerSite
        notifyDepth += 1
        defer {
            notifyDepth -= 1
            callbackPhase = previousPhase
            listenerInFlight = previousListener
            listenerEnteredAt = previousListenerAt
            listenerSite = previousSite
        }
        let snapshot = listeners
        for entry in snapshot {
            callbackPhase = "listener"
            listenerInFlight = entry.token
            listenerSite = entry.site
            listenerEnteredAt = CACurrentMediaTime()
            if let view = entry.liveness?.value as? NSView, !view.isEffectivelyVisible {
                skippedHidden.insert(entry.token); hiddenSkips &+= 1; continue
            }
            skippedHidden.remove(entry.token)
            siteRuns[entry.site, default: 0] += 1
            entry.block()
        }

        cleanupCounter += 1
        guard cleanupCounter >= Self.CleanupIntervalTicks else { return }
        cleanupCounter = 0
        listeners.removeAll { entry in
            guard let liveness = entry.liveness else { return false }
            return !liveness.isAlive
        }
        if !skippedHidden.isEmpty { skippedHidden.formIntersection(listeners.map { $0.token }) }
    }


    /// weakLifetime defaults to nil; passing `weakLifetime: self` makes the
    /// entry eligible for pruning once `self` deallocates.
    @discardableResult
    func addListener(weakLifetime: AnyObject? = nil,
                     file: String = #fileID, line: Int = #line,
                     _ block: @escaping () -> Void) -> UUID {
        let token = UUID()
        let liveness = weakLifetime.map { WeakBox($0) }
        listeners.append((token: token, block: block, liveness: liveness, site: "\(file):\(line)"))
        return token
    }

    func removeListener(_ token: UUID) {
        listeners.removeAll { $0.token == token }
    }

    // MARK: - Proximity helpers

    /// Distance to a view's center point, in window coordinates.
    func distance(to view: NSView) -> CGFloat {
        guard let win = view.window else { return 9999 }
        let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: win.contentView)
        let dx = mouseWindowPt.x - center.x
        let dy = mouseWindowPt.y - center.y
        return sqrt(dx*dx + dy*dy)
    }

    func proximity(to view: NSView, radius: CGFloat) -> CGFloat {
        let d = distance(to: view)
        return max(0, min(1, 1.0 - d / radius))
    }

    /// 0.0 (far) -> 1.0 (on it).
    /// WHY: edge distance, not center distance - a wide row would read "far"
    /// at its own ends and dim too early. dx is 0 inside the row's X-range,
    /// so proximity stays uniform along the row (per-word split is out of scope).
    func proximity(to layer: CALayer, in parentView: NSView?, radius: CGFloat) -> CGFloat {
        guard let win = parentView?.window else { return 0 }
        let layerFrameInWindow = parentView!.convert(layer.frame, to: win.contentView)
        let dx = max(layerFrameInWindow.minX - mouseWindowPt.x, 0,
                      mouseWindowPt.x - layerFrameInWindow.maxX)
        let dy = max(layerFrameInWindow.minY - mouseWindowPt.y, 0,
                      mouseWindowPt.y - layerFrameInWindow.maxY)
        let d = sqrt(dx*dx + dy*dy)
        return max(0, min(1, 1.0 - d / radius))
    }

    func curve(_ t: CGFloat, power: Double = 2.0) -> CGFloat {
        CGFloat(pow(Double(t), power))
    }

    /// Additive blend: proximity + audio, each can independently drive full range.
    /// result = clamp(proxCurve + smoothAudio * audioWeight, 0, 1)
    /// When mouse is absent (proxCurve=0): audio alone pushes up to audioWeight.
    /// When mouse is close (proxCurve=1): audio adds on top, always reaches 1.
    /// wght = base + range * audioBlend(proxCurve)
    /// I8: wraps proxCurve only - SIZE/ROTA never touch audio.
    func audioBlend(_ proxCurve: CGFloat) -> CGFloat {
        let audio = CGFloat(smoothAudio * Self.audioWeight)
        return min(1.0, proxCurve + audio)
    }

    // MARK: - Axis availability

    // No variable font -> applyVariation calls are silently ignored.
    var isVariable: Bool {
        PhotonFont._axisRanges.count > 0
    }
}

// ================================================================
//  DriveProfile - per-element-type proximity/audio behavior
//  Listeners define the profile once; font/axis changes never touch it.
// ================================================================
enum DriveProfile {
    case button          // TrafficTextBtn, VolumeSliderBtn
    case title           // SpineUI title, MusicPanel header
    case row             // list rows
    case osd             // OSD layers
    case panel           // ArchiveBrowser, FileBrowser panel
    case logo            // MenuActions about panel
    case layered(Int)    // SidebarUI TimecodeLabel layers, by index
    case custom(radius: CGFloat, power: Double, vertical: Bool)

    var radius: CGFloat {
        switch self {
        case .button:              return 200
        case .title:               return 200
        case .row:                 return 140
        case .osd:                 return 800
        case .panel:               return 300
        case .logo:                return 400
        case .layered(let i):      return [280, 220, 160, 120][safe: i] ?? 120
        case .custom(let r, _, _): return r
        }
    }

    var power: Double {
        switch self {
        case .button:              return 2.0
        case .title:               return 1.8
        case .row:                 return 2.0
        case .osd:                 return 2.0
        case .panel:               return 2.0
        case .logo:                return 2.0
        case .layered:             return 2.0
        case .custom(_, let p, _): return p
        }
    }

    var vertical: Bool {
        switch self {
        case .row:                    return true
        case .custom(_, _, let v):    return v
        default:                      return false
        }
    }
}

// ================================================================
//  VariationBroadcaster - DriveProfile proximity helper
// ================================================================
extension VariationBroadcaster {
    func proximity(to view: NSView, profile: DriveProfile) -> CGFloat {
        if profile.vertical {
            guard let win = view.window else { return 0 }
            let center = view.convert(NSPoint(x: 0, y: view.bounds.midY), to: win.contentView)
            let dy = abs(mouseWindowPt.y - center.y)
            return max(0, min(1, 1.0 - dy / profile.radius))
        }
        return proximity(to: view, radius: profile.radius)
    }
}

// ================================================================
//  PhotonFont - ctDriven / nsDriven view convenience overloads
// ================================================================
extension PhotonFont {
    static func ctDriven(view: NSView, profile: DriveProfile, size sz: CGFloat? = nil) -> CTFont {
        let vb   = VariationBroadcaster.shared
        let p    = vb.proximity(to: view, profile: profile)
        let curv = vb.curve(p, power: profile.power)
        let t_audio = Double(vb.audioBlend(curv))
        return ctDriven(p: p, t_audio: t_audio, size: sz)
    }

    static func chromeCtDriven(view: NSView, profile: DriveProfile, size sz: CGFloat? = nil) -> CTFont {
        let vb   = VariationBroadcaster.shared
        let p    = vb.proximity(to: view, profile: profile)
        let curv = vb.curve(p, power: profile.power)
        let t_audio = Double(vb.audioBlend(curv))
        return chromeCtDriven(p: p, t_audio: t_audio, size: sz)
    }

    static func nsDriven(view: NSView, profile: DriveProfile, size sz: CGFloat? = nil) -> NSFont {
        let vb   = VariationBroadcaster.shared
        let p    = vb.proximity(to: view, profile: profile)
        let curv = vb.curve(p, power: profile.power)
        let t_audio = Double(vb.audioBlend(curv))
        return nsDriven(p: p, t_audio: t_audio, size: sz)
    }

    static func chromeNsDriven(view: NSView, profile: DriveProfile, size sz: CGFloat? = nil) -> NSFont {
        let vb   = VariationBroadcaster.shared
        let p    = vb.proximity(to: view, profile: profile)
        let curv = vb.curve(p, power: profile.power)
        let t_audio = Double(vb.audioBlend(curv))
        return chromeNsDriven(p: p, t_audio: t_audio, size: sz)
    }
}

// ================================================================
//  VariationTarget protocol
// ================================================================
protocol VariationTarget: AnyObject {
    func applyVariation(proximity p: CGFloat)
}

// ================================================================
//  CATextLayer extension
// ================================================================
extension CATextLayer {
    func applyVariation(wght: Double? = nil, SIZE: Double? = nil, ROTA: Double? = nil) {
        guard VariationBroadcaster.shared.isVariable else { return }
        let newFont = PhotonFont.ct(size: CGFloat(self.fontSize), wght: wght, SIZE: SIZE, ROTA: ROTA)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.font = newFont
        CATransaction.commit()
    }
}

// ================================================================
//  NSTextField extension
// ================================================================
extension NSTextField {
    func applyVariation(wght: Double? = nil, SIZE: Double? = nil, ROTA: Double? = nil) {
        guard VariationBroadcaster.shared.isVariable else { return }
        let s = self.font?.pointSize ?? PhotonFont.chromeSize
        self.font = PhotonFont.ns(size: s, wght: wght, SIZE: SIZE, ROTA: ROTA)
    }
}

// ================================================================
//  NSView.isEffectivelyVisible
//  WHY: PPController.wakeUI() fades containers via animator().alphaValue
//  and never sets isHidden, so neither isHiddenOrHasHiddenAncestor nor a
//  view's own alpha detects it - walk the chain checking both. Skips
//  window.isVisible on purpose: unused elsewhere here, unverified under occlusion.
// ================================================================
extension NSView {
    var isEffectivelyVisible: Bool {
        guard let window = self.window, window.alphaValue > 0.01 else { return false }
        var v: NSView? = self
        while let view = v {
            if view.isHidden || view.alphaValue <= 0.01 { return false }
            v = view.superview
        }
        return true
    }
}
