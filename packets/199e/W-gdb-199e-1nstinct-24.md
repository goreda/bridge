# W-gdb-199e-1nstinct-24 - Audio axis smoother rejects invalid sample time
state: OPEN / unclaimed
lab: 1nstinct

AudioNormalizer.tick/smoothForAxis must reject nonfinite level/dt or nonpositive dt before mutating AGC or axis state. Return finite held output (initial zero shaped output) and recover on the next valid sample. Preserve all finite positive sample behavior and tuning constants. Add held-shaped state if needed; no timer/listener/capture changes.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-1nstinct-24",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorEffectsModel/VariationBroadcaster.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "AudioNormalizer.tick/smoothForAxis must reject nonfinite level/dt or nonpositive dt before mutating AGC or axis state. Return finite held output (initial zero shaped output) and recover on the next valid sample. Preserve all finite positive sample behavior and tuning constants. Add held-shaped state if needed; no timer/listener/capture changes.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "archive/gor/Sources/gor/GorEffectsModel/VariationBroadcaster.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-24.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199e-1nstinct-24",
    "paths": [
      "archive/gor/Sources/gor/GorEffectsModel/VariationBroadcaster.swift",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-24.py",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-24.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-24.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorEffectsModel/VariationBroadcaster.swift",
        "block": "source1",
        "sha256": "886240c5e48f11a71da46b607095ed4a045a4a4d92e49912b7a0386c5aab06af",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-24.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-24.json",
        "block": "fixtures2",
        "sha256": "61646e0a6eaa25697193db9ac9dd04f6fde99db19969b16ae496715a900fa324"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "44963cdd9369b44991fb8c596596eb933af4191ce920d262e1e9bdb2dc646222",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "PASS invalid time produces finite hold",
      "FAIL invalid time does not change smoother state",
      ""
    ],
    "receipt_sha256": "729783c241ec92f6c2e07f7dd816061101e7704f5baef5226285c5d808f1029e"
  }
}
```

```swift id=source1
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
        let shaped = tick(level: level, dt: dt)
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
    mutating func tick(level: Double, dt: Double) -> Double {
        let meanAlpha = 1.0 - exp(-dt / Self.meanTau)
        agcMean += meanAlpha * (level - agcMean)
        agcMean  = max(0.01, agcMean)

        let peakTau   = level > agcPeak ? Self.peakAttackTau : Self.peakDecayTau
        let peakAlpha = 1.0 - exp(-dt / peakTau)
        agcPeak += peakAlpha * (max(level, 0.01) - agcPeak)
        agcPeak  = max(agcPeak, 0.01)

        let varAlpha    = 1.0 - exp(-dt / Self.varianceTau)
        let diff        = level - agcMean
        agcVariance    += varAlpha * (diff * diff - agcVariance)
        let stdDev      = max(sqrt(agcVariance), 0.01)

        // WHY: 3*stdDev spans nearly the full dynamic range of any content,
        // so volume 30 and 100 produce identical normalization curves.
        let stdDevNorm  = max(0.0, min(1.0, 0.5 + diff / (stdDev * 3.0)))

        // WHY: stdDevNorm carries rhythm/dynamics, level carries the user's
        // volume intent; volumeSensitivity sets the mix.
        let blended     = stdDevNorm * (1.0 - Self.volumeSensitivity)
                        + level      *  Self.volumeSensitivity

        return blended > 0 ? pow(blended, Self.gamma) : 0.0
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

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/GorEffectsModel/VariationBroadcaster.swift",
  "markers": [
    "struct AudioNormalizer {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nvar actual=AudioNormalizer(),control=AudioNormalizer()\n_ = actual.smoothForAxis(level:0.4,dt:0.016);_ = control.smoothForAxis(level:0.4,dt:0.016)\nlet rejected=actual.smoothForAxis(level:0.5,dt:.infinity)\ncheck(rejected.isFinite,\"invalid time produces finite hold\")\nlet a=actual.smoothForAxis(level:0.4,dt:0.016),b=control.smoothForAxis(level:0.4,dt:0.016)\ncheck(a.isFinite && abs(a-b)<1e-12,\"invalid time does not change smoother state\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
PASS invalid time produces finite hold
FAIL invalid time does not change smoother state


```

Publication caveat: NONQUALIFIED: exact-source declaration extraction, not native/full module acceptance. HeatTelemetry in A27 is an explicit test support value, not production telemetry evidence. Own compiler rerun NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
