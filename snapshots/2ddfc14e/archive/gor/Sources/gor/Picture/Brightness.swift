// Display station: complete source units, with only unconditional imports lifted.
import AppKit
import CoreGraphics
import CoreImage
import Darwin
import Foundation
import IOKit
import IOKit.ps
import QuartzCore

// MARK: - BrightnessController.swift
// ================================================================
//  BrightnessController - display brightness control
// ================================================================
final class BrightnessController {
    // MARK: - Brightness state
    // ── USER-TUNABLE ────────────────────────────────────────────────────────────
    private let minBrightness: Float = 0.3
    private let fadeStepDelay: TimeInterval = 0.05
    private let fadeSteps: Int = 36
    fileprivate let quitFadeStepDelay: TimeInterval = 1.44 / 36
    fileprivate let quitFadeSteps: Int = 36
    private let spikeThreshold: Float = 0.15
    private let monitorInterval: TimeInterval = 1.0
    private let displayID: Int = 1
    // ── DisplayServices ─────────────────────────────────────────────────────
    private var fnSet: (@convention(c) (Int, Float) -> Void)?
    private var fnGet: (@convention(c) (Int, UnsafeMutablePointer<Float>) -> Void)?
    private var dsLoaded = false
    // ── single source of truth ──────────────────────────────────────────────
    private(set) var originalBrightness: Float = 1.0
    private var isOverridden = false
    private var isPlaying = false
    private var hasEverPlayed = false
    private var brightnessSaved = false
    // ── external override hook ──────────────────────────────────────────────
    var sceneTargetOverride: (() -> Float)?
    private var playbackCeiling: Float { sceneTargetOverride?() ?? 1.0 }
    var isBrightnessUserOverridden: Bool { isOverridden }
    // Scene adaptation cannot write over pause/restore, user intent or another fade.
    var permitsSceneBrightnessWrites: Bool { !quitFadeActive && isPlaying && !isOverridden && !isFadingActive }
    var isBrightnessFading: Bool { isFadingActive }
    // ── fade machinery ──────────────────────────────────────────────────────
    private var fadeTimer: Timer?
    private var fadeGeneration: Int = 0
    private var isFadingActive = false
    // Terminal ownership survives completion: no later playback/user fade may win.
    private var quitFadeActive = false
    private var quitFadeSettled = false
    private var quitFadeTarget: Float?
    private var quitFadeCompletions: [() -> Void] = []
    // ── drift monitors ──────────────────────────────────────────────────────
    private var monitorTimer: Timer?
    private var powerTimer: Timer?
    private var lastPowerSource: String?
    private var lastLog: Int = -1
    private var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return sources.contains { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { return false }
            return (description[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSBatteryPowerValue as String)
        }
    }
    // ── public: playback lifecycle ──────────────────────────────────────────
    func updateForPlayback(isPlaying: Bool) {
        guard !quitFadeActive else { return }
        self.isPlaying = isPlaying
        if isPlaying { hasEverPlayed = true }
        isOverridden = false
        if isPlaying {
            if !brightnessSaved {
                originalBrightness = getCurrentBrightness()
                brightnessSaved = true
                print("[brightness] saved: \(Int(originalBrightness * 100))%")
            } else {
                let liveValue = getCurrentBrightness()
                if abs(liveValue - originalBrightness) > 0.02 {
                    originalBrightness = liveValue
                    print("[brightness] updated: \(Int(originalBrightness * 100))%")
                }
            }
            fade(to: playbackCeiling)
            startSystemMonitoring()
            startPowerMonitoring()
        } else {
            stopSystemMonitoring()
            stopPowerMonitoring()
            guard hasEverPlayed else { return }
            fade(to: originalBrightness)
        }
    }
    func captureLaunchBrightnessIfUnsaved() {
        guard !quitFadeActive else { return }
        guard !brightnessSaved else { return }
        originalBrightness = getCurrentBrightness()
        brightnessSaved = true
        print("[brightness] captured at launch: \(Int(originalBrightness * 100))%")
    }
    func restore() {
        guard !quitFadeActive else { return }
        stopPowerMonitoring()
        guard brightnessSaved else { return }
        setBrightness(originalBrightness)
        print("[brightness] restore: \(Int(originalBrightness * 100))%")
    }
    func teardown() {
        stopFadeForTeardown()
        stopSystemMonitoring()
        stopPowerMonitoring()
    }
    // ── public: user-driven brightness changes ──────────────────────────────
    func setUserBrightness(_ value: Float) {
        guard !quitFadeActive else { return }
        let clamped = max(minBrightness, min(1.0, value))
        originalBrightness = clamped
        if isPlaying {
            isOverridden = true
            setBrightness(clamped)
        } else {
            guard hasEverPlayed else { return }
            fade(to: clamped)
        }
    }
    func notifyExternalBrightnessChange() {
        guard !quitFadeActive else { return }
        let current = getCurrentBrightness()
        let clamped = max(minBrightness, min(1.0, current))
        originalBrightness = clamped
        if isPlaying {
            isOverridden = true
        } else {
            guard hasEverPlayed else { return }
        }
        print("[brightness] external key: \(Int(clamped * 100))%")
    }
    // ── hardware read/write ─────────────────────────────────────────────────
    func setBrightness(_ value: Float, terminal: Bool = false) {
        guard !quitFadeActive || terminal else { return }
        loadDisplayServices()
        guard let fn = fnSet else { return }
        let clamped = max(0.0, min(1.0, value))
        fn(displayID, clamped); readCache.wrote(clamped, CACurrentMediaTime())
        let pct = Int(clamped * 100)
        if abs(pct - lastLog) >= 5 {
            print("[brightness] \(pct)%")
            lastLog = pct
        }
    }
    var readCache = BrightnessReadCache()
    func getCurrentBrightness() -> Float {
        if let v = readCache.fresh(CACurrentMediaTime()) { return v }
        loadDisplayServices(); var v: Float = 1.0; guard let fn = fnGet else { return 1.0 }
        fn(displayID, &v); readCache.hardwareRead(v, CACurrentMediaTime())
        return HeatShadow.observeFloat("brightness", v, ttl: 0.5)
    }
    private func loadDisplayServices() {
        guard !dsLoaded else { return }
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            print("[brightness] DisplayServices failed to load")
            return
        }
        if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
            fnSet = unsafeBitCast(sym, to: (@convention(c) (Int, Float) -> Void).self)
        }
        if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
            fnGet = unsafeBitCast(sym, to: (@convention(c) (Int, UnsafeMutablePointer<Float>) -> Void).self)
        }
        dsLoaded = true
        print("[brightness] loaded")
    }
    // ── fade ────────────────────────────────────────────────────────────────
    fileprivate func fade(to target: Float, completion: (() -> Void)? = nil) {
        fade(to: target, stepCount: fadeSteps, stepDelay: fadeStepDelay, completion: completion)
    }
    fileprivate func fade(to target: Float, stepCount: Int, stepDelay: TimeInterval, completion: (() -> Void)? = nil, terminal: Bool = false) {
        precondition(Thread.isMainThread)
        guard !quitFadeActive || terminal else { return }
        let current = getCurrentBrightness()
        guard abs(current - target) > 0.02 else {
            completion?()
            return
        }
        isFadingActive = true
        fadeGeneration += 1
        let myGeneration = fadeGeneration
        let start = current
        print("[brightness] fade: \(Int(start * 100))% -> \(Int(target * 100))%")
        func step(_ i: Int) {
            guard self.fadeGeneration == myGeneration else {
                if terminal && !self.quitFadeSettled { self.finishQuitFade() }
                return
            }
            let p = Float(i) / Float(stepCount)
            let ease = p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
            self.setBrightness(start + (target - start) * ease, terminal: terminal)
            if i < stepCount {
                DispatchQueue.main.asyncAfter(deadline: .now() + stepDelay) { step(i + 1) }
            } else {
                if self.fadeGeneration == myGeneration {
                    self.isFadingActive = false
                }
                print("[brightness] fade done")
                completion?()
            }
        }
        step(1)
    }
    func quitFade(completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        if quitFadeSettled {
            completion()
            return
        }
        quitFadeCompletions.append(completion)
        guard !quitFadeActive else { return }
        quitFadeActive = true
        quitFadeTarget = brightnessSaved ? originalBrightness : nil
        stopSystemMonitoring()
        stopPowerMonitoring()
        // Cancel any ordinary fade even when restore is already within tolerance.
        fadeGeneration += 1
        isFadingActive = false
        guard let target = quitFadeTarget else { finishQuitFade(); return }
        fade(to: target, stepCount: quitFadeSteps, stepDelay: quitFadeStepDelay,
             completion: { [weak self] in self?.finishQuitFade() }, terminal: true)
    }
    func restoreForQuitDeadline() {
        precondition(Thread.isMainThread)
        finishQuitFade()
    }
    private func finishQuitFade() {
        precondition(Thread.isMainThread)
        guard quitFadeActive, !quitFadeSettled else { return }
        // Teardown/cancellation is an explicit restore-and-complete, never silence.
        if let target = quitFadeTarget { setBrightness(target, terminal: true) }
        fadeGeneration += 1
        isFadingActive = false
        quitFadeSettled = true
        let completions = quitFadeCompletions
        quitFadeCompletions.removeAll()
        completions.forEach { $0() }
    }
    private func stopFadeForTeardown() {
        precondition(Thread.isMainThread)
        if quitFadeActive { finishQuitFade() }
        isFadingActive = false
        fadeGeneration += 1
        fadeTimer?.invalidate(); fadeTimer = nil
    }
    // ── drift monitors ──────────────────────────────────────────────────────
    private func startSystemMonitoring() {
        stopSystemMonitoring()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: monitorInterval, repeats: true) { [weak self] _ in
            guard let self, !self.isFadingActive, !self.isOverridden else { return }
            let current = self.getCurrentBrightness()
            let target = self.playbackCeiling
            if current < target - self.spikeThreshold {
                print("[brightness] restore: \(Int(current * 100))% -> \(Int(target * 100))%")
                self.fade(to: target)
            }
        }
    }
    private func stopSystemMonitoring() {
        monitorTimer?.invalidate(); monitorTimer = nil
    }
    private func startPowerMonitoring() {
        stopPowerMonitoring()
        lastPowerSource = isOnBattery ? "battery" : "ac"
        powerTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, !self.isFadingActive, !self.isOverridden else { return }
            let src = self.isOnBattery ? "battery" : "ac"
            guard src != self.lastPowerSource else { return }
            self.lastPowerSource = src
            self.fade(to: self.playbackCeiling)
        }
    }
    private func stopPowerMonitoring() {
        powerTimer?.invalidate(); powerTimer = nil
    }
}

// MARK: - BrightnessReadCache.swift
/// DisplayServicesGetBrightness is a synchronous XPC wait. The scene actuator ticks at display refresh and
/// read it twice per tick (owner log 02:50-02:57: 63 calls/s, 278 of 442 main-thread samples).
/// A value we wrote or read stays valid for `ttl`; the timestamp is kept on writes so a real hardware
/// read still happens every `ttl` (external changes are seen). Output values are unchanged.
struct BrightnessReadCache {
    static let ttl: TimeInterval = 0.25
    private var entry: (value: Float, at: TimeInterval)?
    private(set) var hardwareReads = 0

    func fresh(_ now: TimeInterval) -> Float? {
        guard let e = entry, now - e.at >= 0, now - e.at < Self.ttl else { return nil }
        return e.value
    }
    mutating func hardwareRead(_ value: Float, _ now: TimeInterval) { hardwareReads += 1; entry = (value, now) }
    mutating func wrote(_ value: Float, _ now: TimeInterval) { entry = (value, entry?.at ?? now) }
}
// END station-move BrightnessReadCache.swift
// MARK: - ContentAdaptiveDimming.swift
// ================================================================
//  ContentAdaptiveDimming - scene-based display dimming
// ================================================================
final class ContentAdaptiveDimming {

    static let featureFlagEnabled: Bool = true

    var runtimeEnabled: Bool = false {
        didSet {
            guard runtimeEnabled != oldValue else { return }
            resetSceneTracking()
            if runtimeEnabled {
                setSceneTargetOverride { [weak self] in self?.smoothedBacklight ?? 1.0 }
            } else {
                setSceneTargetOverride(nil)
            }
            updateAmbientCameraFallback()
        }
    }

    // Camera sampling is allowed while a video is loaded, including while paused.
    // Idle, stopped and panel-only states with no video keep the camera off.
    // PPController supplies loaded-file state independently of pause.
    var playbackActive: Bool = false {
        didSet {
            guard playbackActive != oldValue else { return }
            if !playbackActive { playbackStalled = false }
            updateAmbientCameraFallback()
        }
    }

    /// Owner-log 260918 item 2: set by PPController while mpv paints frozen or
    /// black seek/rebuffer frames. Sampling those as scene content dragged the
    /// backlight down during every post-seek wait (field log: hunting 93/88/98
    /// through a 153s stall, then a restore ramp). While stalled, hold the
    /// last real-scene target: no sampling, no target updates; the actuator
    /// converges to the held target and idles. Pause-by-user is NOT a stall;
    /// paused-frame sampling stays intentional.
    var playbackStalled: Bool = false

    private func updateAmbientCameraFallback() {
        guard #available(macOS 12.0, *) else { return }
        let shouldRun = runtimeEnabled && playbackActive && !AmbientLightProvider.shared.isAvailable
        if shouldRun {
            startAmbientDutyCycle()
        } else {
            stopAmbientDutyCycle()
        }
    }

    // MARK: - Ambient camera duty-cycling
    private static let ambientCheckpointFractions: [Double] = [0, 0.125, 0.25, 0.50, 0.75]

    private static let ambientDutyCycleOnDuration: TimeInterval = 2.0

    private static let ambientFirstWindowCeiling: TimeInterval = 15.0

    private var ambientCheckpointsFired: Set<Int> = []

    private var ambientDutyCycleCloseWorkItem: DispatchWorkItem?

    private var ambientRetryWorkItem: DispatchWorkItem?

    private static let ambientRetryDelay: TimeInterval = 7.0

    private var ambientDutyCycleActive = false

    private var firstAmbientWindowWorkItem: DispatchWorkItem?

    private static let firstAmbientWindowDelay: TimeInterval = 0.6

    @available(macOS 12.0, *)
    private func startAmbientDutyCycle() {
        guard !ambientDutyCycleActive else { return }
        ambientDutyCycleActive = true
        let firstWindowWork = DispatchWorkItem { [weak self] in
            self?.ambientCheckpointsFired.insert(0)
            self?.openAmbientWindow(isFirstWindow: true)
        }
        firstAmbientWindowWorkItem = firstWindowWork
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstAmbientWindowDelay, execute: firstWindowWork)
    }

    @available(macOS 12.0, *)
    private func stopAmbientDutyCycle() {
        ambientDutyCycleActive = false
        firstAmbientWindowWorkItem?.cancel()
        firstAmbientWindowWorkItem = nil
        ambientRetryWorkItem?.cancel()
        ambientRetryWorkItem = nil
        closeAmbientWindow(fromCeiling: false)
    }

    @available(macOS 12.0, *)
    func checkAmbientCheckpoints(currentTime: Double, duration: Double) {
        guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }
        guard duration > 0 else { return }
        let progress = currentTime / duration
        for (index, fraction) in Self.ambientCheckpointFractions.enumerated() {
            guard !ambientCheckpointsFired.contains(index) else { continue }
            guard progress >= fraction else { continue }
            ambientCheckpointsFired.insert(index)
            Diag.mediaRecord("AMBIENT-WINDOW trigger=checkpoint fraction=\(fraction)"); openAmbientWindow()
            return
        }
    }

    @available(macOS 12.0, *)
    func handlePlaybackPaused() {
        // Pause-triggered sampling is intentional, but only for a loaded video.
        guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }
        Diag.mediaRecord("AMBIENT-WINDOW trigger=pause"); openAmbientWindow()
    }

    func resetAmbientCheckpoints() {
        ambientCheckpointsFired.removeAll()
    }

    @available(macOS 12.0, *)
    private func openAmbientWindow(isFirstWindow: Bool = false) {
        guard runtimeEnabled, playbackActive, ambientDutyCycleActive else { return }
        ambientRetryWorkItem?.cancel()
        ambientRetryWorkItem = nil
        setAmbientWindowOpen(true)
        let ambientWindowOpenedAt = CACurrentMediaTime()
        Diag.mediaRecord("[AmbientDiag] window OPEN isFirstWindow=\(isFirstWindow) t=\(String(format: "%.2f", ambientWindowOpenedAt))")
        HeadTracker.shared.resetAmbientSettling()
        HeadTracker.shared.onAmbientFrame = { [weak self] in
            self?.closeAmbientWindow(fromCeiling: false, wasFirstWindow: isFirstWindow, openedAt: ambientWindowOpenedAt)
        }
        HeadTracker.shared.startAmbientOnly()
        ambientDutyCycleCloseWorkItem?.cancel()
        let ceilingWork = DispatchWorkItem { [weak self] in
            self?.closeAmbientWindow(fromCeiling: true, wasFirstWindow: isFirstWindow, openedAt: ambientWindowOpenedAt)
        }
        ambientDutyCycleCloseWorkItem = ceilingWork
        let ceiling = isFirstWindow ? Self.ambientFirstWindowCeiling : Self.ambientDutyCycleOnDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + ceiling, execute: ceilingWork)
    }

    @available(macOS 12.0, *)
    private func closeAmbientWindow(fromCeiling: Bool, wasFirstWindow: Bool = false, openedAt: CFTimeInterval? = nil) {
        if let openedAt {
            let lifetime = CACurrentMediaTime() - openedAt
            Diag.mediaRecord("[AmbientDiag] window CLOSE fromCeiling=\(fromCeiling) wasFirstWindow=\(wasFirstWindow) lifetime=\(String(format: "%.2f", lifetime))s ambientNilNow=\(AmbientLightProvider.shared.normalizedLevel() == nil)")
        }
        HeadTracker.shared.onAmbientFrame = nil
        HeadTracker.shared.stopAmbientOnly()
        ambientDutyCycleCloseWorkItem?.cancel()
        ambientDutyCycleCloseWorkItem = nil
        setAmbientWindowOpen(false)

        guard fromCeiling,
              AmbientLightProvider.shared.normalizedLevel() == nil else { return }

        ambientRetryWorkItem?.cancel()
        let retryWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard AmbientLightProvider.shared.normalizedLevel() == nil else { return }
            guard self.runtimeEnabled, self.playbackActive else { return }
            self.openAmbientWindow(isFirstWindow: wasFirstWindow)
        }
        ambientRetryWorkItem = retryWork
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.ambientRetryDelay, execute: retryWork)
    }

    // MARK: - Dependencies (closures back to PPController, same

    private weak var hostView: NSView?
    private let setSceneTargetOverride: ((() -> Float)?) -> Void
    private let setBrightness: (Float) -> Void
    private let getCurrentBrightness: () -> Float
    private let isBrightnessFading: () -> Bool
    private let writeSceneStateToMPV: (_ backlight: Float, _ inertiaMode: String, _ isCut: Bool, _ ambientLevel: Double?, _ ambientSource: String, _ ambientRegions: (face: Double, room: Double)?, _ ambientLux: Double?) -> Void

    private let setAmbientWindowOpen: (Bool) -> Void

    init(
        hostView: NSView,
        setSceneTargetOverride: @escaping ((() -> Float)?) -> Void,
        setBrightness: @escaping (Float) -> Void,
        getCurrentBrightness: @escaping () -> Float,
        isBrightnessFading: @escaping () -> Bool,
        writeSceneStateToMPV: @escaping (_ backlight: Float, _ inertiaMode: String, _ isCut: Bool, _ ambientLevel: Double?, _ ambientSource: String, _ ambientRegions: (face: Double, room: Double)?, _ ambientLux: Double?) -> Void,
        setAmbientWindowOpen: @escaping (Bool) -> Void
    ) {
        self.hostView = hostView
        self.setSceneTargetOverride = setSceneTargetOverride
        self.setBrightness = setBrightness
        self.getCurrentBrightness = getCurrentBrightness
        self.isBrightnessFading = isBrightnessFading
        self.writeSceneStateToMPV = writeSceneStateToMPV
        self.setAmbientWindowOpen = setAmbientWindowOpen
    }

    func setup() {
        sceneTimer?.invalidate()
        if runtimeEnabled {
            setSceneTargetOverride { [weak self] in self?.smoothedBacklight ?? 1.0 }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: sceneTickInterval, repeats: true) { [weak self] _ in
            self?.tickScene()
        }
        RunLoop.main.add(timer, forMode: .common)
        sceneTimer = timer
    }

    deinit {
        sceneTimer?.invalidate()
        microStepTimer?.invalidate()
        setSceneTargetOverride(nil)
        if #available(macOS 12.0, *) {
            stopAmbientDutyCycle()
        }
    }

    // MARK: - A: scene-adaptive backlight

    private let contentTargetFloor: Float = 0.75

    private var ceilingTravel: Float { 1.0 - contentTargetFloor }

    private let lumaDarkThreshold:   CGFloat = 0.13
    private let lumaBrightThreshold: CGFloat = 0.55

    private func smoothstep(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3.0 - 2.0 * t)
    }

    private var sceneTimer: Timer?
    private let sceneTickInterval: TimeInterval = 0.4

    private let lumaSmoothing: Float = 0.12

    private let backlightInertiaDark: Float = 0.88

    // Match the response inertia in both directions. This is a source policy;
    // visual smoothness and native timing still require field verification.
    private let backlightInertiaBright: Float = 0.88

    private let cutThresholdBase:  CGFloat = 0.14
    private let cutThresholdScale: CGFloat = 2.2

    private func dynamicCutThreshold(_ luma: CGFloat) -> CGFloat {
        cutThresholdBase * (0.5 + min(max(luma, 0), 0.6) * cutThresholdScale)
    }

    private var smoothedLuma: CGFloat?
    private var smoothedBacklight: Float?
    private var cutPending: Bool = false

    private var lastConfirmedCutTime: Date?
    private var sceneTarget: Float?
    private var lastActuatorTime: CFTimeInterval?
    private var lastFreshSampleTime: CFTimeInterval?

    private func resetSceneTracking() {
        microStepTimer?.invalidate()
        microStepTimer = nil
        microStepGeneration += 1
        sceneTarget = nil
        lastActuatorTime = nil
        lastFreshSampleTime = nil
        cachedRawLuma = nil
        smoothedLuma = nil
        let heldBrightness = getCurrentBrightness()
        smoothedBacklight = heldBrightness.isFinite ? heldBrightness : smoothedBacklight
        cutPending = false
        captureInterval = 1
        ticksSinceCapture = 0
        consecutiveCalmTicks = 0
    }

    // Bounded sample/actuator telemetry; existing capture and cut behavior unchanged.
    // cutMicroStepDuration provenance is separate/unverified at HEAD 3a247ad0.
    private struct PhotonBrightTrace {
        let tick: UInt64
        let sample: UInt64
        let monotonicTime: TimeInterval
        let sampleAge: TimeInterval?
        let fresh: Bool
        let captureFailed: Bool
        let cutCandidate: Bool
        let confirmedCut: Bool
        let target: Float
        let hardwareReadback: Float
        let proposedBacklight: Float
        let elapsed: TimeInterval?
        let writeSuppressed: Bool
    }
    // Storage budget only, not an adaptive threshold or actuator parameter.
    private let photonBrightTraceCapacity = 512
    private var photonBrightTrace: [PhotonBrightTrace?] = Array(repeating: nil, count: 512)
    private var photonBrightTraceHead = 0
    private var photonBrightTraceCount = 0
    private var photonBrightTraceDropped: UInt64 = 0
    private var photonBrightTickID: UInt64 = 0
    private var photonBrightSampleID: UInt64 = 0
    private var photonBrightSampleAt: TimeInterval?
    private var photonBrightTickAt: TimeInterval?

    // Snapshot is explicit, outside tickScene. No disk IO or extra hardware reads.
    func photonBrightTraceSnapshot() -> [[String: String]] {
        var rows: [[String: String]] = []
        rows.reserveCapacity(photonBrightTraceCount)
        for offset in 0..<photonBrightTraceCount {
            let index = (photonBrightTraceHead - photonBrightTraceCount + offset + photonBrightTraceCapacity) % photonBrightTraceCapacity
            guard let record = photonBrightTrace[index] else { continue }
            rows.append([
                "tick": String(record.tick), "sample": String(record.sample),
                "monotonicTime": String(record.monotonicTime),
                "sampleAge": record.sampleAge.map { String($0) } ?? "unknown",
                "fresh": String(record.fresh), "captureFailed": String(record.captureFailed),
                "cutCandidate": String(record.cutCandidate), "confirmedCut": String(record.confirmedCut),
                "target": String(record.target), "hardwareReadback": String(record.hardwareReadback),
                "proposedBacklight": String(record.proposedBacklight),
                "elapsed": record.elapsed.map { String($0) } ?? "unknown",
                "writeSuppressed": String(record.writeSuppressed),
                "dropped": String(photonBrightTraceDropped)
            ])
        }
        return rows
    }

    private func tickScene() {
        guard runtimeEnabled else { return }
        // Frozen seek/rebuffer frames are not scene content; hold the target.
        guard !playbackStalled else { return }
        guard !isBrightnessFading(), let hostView, let window = hostView.window else {
            resetSceneTracking()
            return
        }

        let screenRect = window.convertToScreen(hostView.convert(lastTarget, to: nil))

        let sampleNow = CACurrentMediaTime()
        var hasFreshSample = false
        var freshElapsed = sceneTickInterval
        ticksSinceCapture += 1
        let shouldCapture = cachedRawLuma == nil || ticksSinceCapture >= captureInterval
        if shouldCapture {
            ticksSinceCapture = 0
            let previousCached = cachedRawLuma
            if let fresh = ScreenCaptureEngine.shared.currentMPVLuma(inScreenRect: screenRect),
               fresh.isFinite, fresh >= 0, fresh <= 1 {
                hasFreshSample = true
                freshElapsed = lastFreshSampleTime.map { max(0, sampleNow - $0) } ?? sceneTickInterval
                lastFreshSampleTime = sampleNow
                if let previousCached, abs(fresh - previousCached) <= dynamicCutThreshold(previousCached) {
                    consecutiveCalmTicks += 1
                    if consecutiveCalmTicks >= Self.calmTicksToWiden {
                        captureInterval = min(captureInterval + 1, Self.maxCaptureInterval)
                    }
                } else {
                    consecutiveCalmTicks = 0
                    captureInterval = 1
                }
                cachedRawLuma = fresh
            } else {
                // Failed capture is not a second observation of cached content.
                resetSceneTracking()
                return
            }
        }
        guard let rawLuma = cachedRawLuma else { return }

        let diagNow = Date()
        if diagNow.timeIntervalSince(lastDiagLog) > 2.0 {
            lastDiagLog = diagNow
            Diag.log("[ContentAdaptiveDimming] rawLuma=\(rawLuma) screenRect=\(screenRect)")
        }

        let prevLuma = smoothedLuma ?? rawLuma

        let cutCandidate = hasFreshSample && abs(rawLuma - prevLuma) > dynamicCutThreshold(prevLuma)
        let isCut = hasFreshSample && cutCandidate && cutPending
        if hasFreshSample { cutPending = cutCandidate }

        let timeSinceLastCut: TimeInterval? = isCut ? lastConfirmedCutTime.map { Date().timeIntervalSince($0) } : nil
        if isCut { lastConfirmedCutTime = Date() }

        // Preserve the existing response at its reference cadence, not per callback.
        // Cuts are observations; they do not bypass the automatic transition.
        let lumaAlpha = hasFreshSample
            ? 1.0 - pow(1.0 - Double(lumaSmoothing), freshElapsed / sceneTickInterval) : 0.0
        let newLuma = prevLuma + (rawLuma - prevLuma) * CGFloat(lumaAlpha)
        smoothedLuma = newLuma

        let contentSceneT = smoothstep(lumaDarkThreshold, lumaBrightThreshold, newLuma)

        let ambientSceneTBoost: Double = 0.35
        let ambientLevel = AmbientLightProvider.shared.normalizedLevel()
        let ambientRegions = HeadTracker.shared.lastAmbientRegions.map {
            (face: min(max($0.faceLuma, 0), 255) / 255.0,
             room: min(max($0.roomLuma, 0), 255) / 255.0)
        }
        let sceneT: CGFloat
        if let ambientLevel {
            let ambientSupport = CGFloat(ambientLevel * ambientSceneTBoost)
            sceneT = max(0.0, contentSceneT - ambientSupport)
        } else {
            sceneT = contentSceneT
        }
        let target = 1.0 - Float(sceneT) * ceilingTravel

        let applied = getCurrentBrightness()
        guard applied.isFinite else { resetSceneTracking(); return }
        sceneTarget = target
        smoothedBacklight = applied
        let inertiaMode = target < applied ? "bright" : "dark"
        startSceneActuatorIfNeeded()
        // Hardware observation, never a future target or an unexecuted fade.
        writeSceneStateToMPV(applied, inertiaMode, isCut, ambientLevel, AmbientLightProvider.shared.currentSourceLabel, ambientRegions, AmbientLightProvider.shared.lastRawLux)
    }

    private var microStepTimer: Timer?
    private var microStepGeneration = 0

    private var microStepInterval: TimeInterval {
        guard #available(macOS 12.0, *) else { return 1.0 / 60.0 }
        if let interval = hostView?.window?.screen?.maximumRefreshInterval, interval > 0 {
            return interval
        }
        return 1.0 / 60.0
    }

    private func startSceneActuatorIfNeeded() {
        guard microStepTimer == nil else { return }
        microStepGeneration += 1
        let generation = microStepGeneration
        lastActuatorTime = CACurrentMediaTime()
        let timer = Timer.scheduledTimer(withTimeInterval: microStepInterval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            // An old generation must not retire the replacement timer/state.
            guard self.microStepGeneration == generation else { timer.invalidate(); return }
            guard self.runtimeEnabled, !self.isBrightnessFading(),
                  self.hostView?.window != nil, let target = self.sceneTarget else {
                timer.invalidate()
                self.resetSceneTracking()
                return
            }
            let now = CACurrentMediaTime()
            let elapsed = max(0, now - (self.lastActuatorTime ?? now))
            self.lastActuatorTime = now
            // A stalled callback is not permission to compress a whole ramp into
            // one write. Resume from the observed value on the next normal tick.
            guard elapsed <= self.sceneTickInterval else { return }
            let current = self.getCurrentBrightness()
            guard current.isFinite, target.isFinite else { self.resetSceneTracking(); return }
            // Derive continuous response from existing directional inertia, without
            // cut snaps, callback-count steps or restart-from-stale-target behavior.
            let inertia = target < current ? self.backlightInertiaBright : self.backlightInertiaDark
            let alpha = 1.0 - pow(Double(inertia), elapsed / self.sceneTickInterval)
            let next = current + (target - current) * Float(alpha)
            guard next.isFinite else { self.resetSceneTracking(); return }
            self.setBrightness(next)
            self.smoothedBacklight = self.getCurrentBrightness()
        }
        RunLoop.main.add(timer, forMode: .common)
        microStepTimer = timer
    }

    // MARK: - lastTarget

    private var lastTarget: CGRect = .zero

    private var lastDiagLog: Date = .distantPast

    private static let maxCaptureInterval = 4
    private static let calmTicksToWiden = 3
    private var captureInterval = 1
    private var ticksSinceCapture = 0
    private var consecutiveCalmTicks = 0
    private var cachedRawLuma: CGFloat?

    func handleVideoFrame(_ bounds: CGRect, _ displayRect: CGRect, _ target: CGRect) {
        if lastTarget != target { resetSceneTracking() }
        lastTarget = target
    }
}
