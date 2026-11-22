// Portions of the Core Audio helpers are adapted from insidegui/AudioCap.
// Source: https://github.com/insidegui/AudioCap
// License: BSD-2-Clause
// Copyright (c) 2024 Guilherme Rambo
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// - Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// - Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

// ================================================================
// ScreenCaptureEngine.swift - adaptive color sampling + Process Tap audio level + head/ambient sensing
//
// Owns: CGWindowListCreateImage color sampling of the mpv window; Core Audio
//   Process Tap (14.2+) audio-level capture; webcam head pose; ambient light.
// Contract: single shared engine; callers (SpineUI/SidebarUI/PPController)
//   register callbacks and decide what results mean.
// Color decision (three-level, subtitles): luma > 0.60 black, < 0.40 white,
//   0.40-0.60 yellow.
// WHY Process Tap, not SCStream: any live SCStream (holding "Screen
//   Recording" TCC) makes macOS withhold HDCP-protected frames from external
//   displays system-wide; narrowing the filter does not help. Process Taps
//   use the narrower "System Audio Recording Only" permission and never
//   touch ScreenCaptureKit, so they don't trip it. The two permissions are
//   separate grants now; both are prompted implicitly by the OS on first use.
//   RMS/peak/dBFS math is unchanged; only the PCM source changed.
// Not here: pose -> shader translation (PPController), ambient duty-cycle
//   consumption (PPController_Features).
// ================================================================

import AppKit
import CoreGraphics
import ScreenCaptureKit
import AVFoundation
import CoreAudio
import Accelerate
import Vision
import CoreML
import IOKit

// ================================================================
// SCEWorkerThread
//
// WHY: SCStream init/first start pays a one-time 12-20s cost; on main it
//   freezes the app, and from DispatchQueue.global() the completion is
//   never delivered because nothing pumps that thread's run loop. This
//   thread exists to be "a thread whose run loop is actively pumped"
//   without being main. Hypothesis, not a guarantee - see the note at the
//   call site in startAudioCapture().
// ================================================================
/// Plain reference-type box so the closure can hand the captured CFRunLoop
/// back without capturing `self` (a closure built during init() can't take
/// even a weak ref to a not-fully-initialized object).
private final class RunLoopBox {
    var runLoop: CFRunLoop?
}

private final class SCEWorkerThread {
    static let shared = SCEWorkerThread()

    private let thread: Thread
    private let runLoopBox = RunLoopBox()
    private let readySemaphore = DispatchSemaphore(value: 0)

    private init() {
        print("[SCE] build marker: tapfix2 (PID re-resolve + playback-armed tap retry)")
        let box       = runLoopBox       // local captures only - no `self`
        let semaphore = readySemaphore
        let t = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            // Park a far-future timer so the run loop always has at least
            // one source registered and RunLoop.current.run() never falls
            // through immediately (a run loop with zero sources exits
            // right away instead of waiting for work to be scheduled).
            let parkTimer = Timer(timeInterval: .greatestFiniteMagnitude, repeats: false) { _ in }
            RunLoop.current.add(parkTimer, forMode: .default)
            semaphore.signal()
            RunLoop.current.run()
        }
        t.name = "gor.sce.worker"
        t.qualityOfService = .userInitiated
        t.stackSize = 4 << 20
        t.start()           // start the local `t`, not `self.thread`
        thread = t           // now safe to assign the stored property
        semaphore.wait()
    }

    /// Marshal `block` onto the worker thread's run loop.
    /// Safe to call from any thread, including the worker thread itself.
    func run(_ block: @escaping () -> Void) {
        guard let rl = runLoopBox.runLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(rl)
    }
}

private enum SCERecorderConfig {
    static let enabled = ProcessInfo.processInfo.environment["GOR_SCE_RECORDER"] == "1"
}

final class ScreenCaptureEngine: NSObject {

    static let shared = ScreenCaptureEngine()
    private override init() {}

    // MARK: - Color thresholds

    private let darkThreshold:  CGFloat = 0.40
    private let lightThreshold: CGFloat = 0.60

    static let colorWhite = NSColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1.0)
    static let colorBlack = NSColor.black
    /// "Safe yellow" - readable on most mid-tone backgrounds.
    static let colorGrey  = NSColor(red: 0.98, green: 0.87, blue: 0.35, alpha: 1.0)

    // MARK: - Registered UI elements

    /// Subtitle paint policy, independent of the chosen contrast color.
    enum SubtitleColorTransition: Equatable {
        case normal
        case clearCut
    }

    private struct ColorDecision {
        let color: NSColor
        let mode: SubtitleColorTransition
    }

    struct UIElement {
        let id: String
        let frameProvider: () -> CGRect?
        let callback: (NSColor, SubtitleColorTransition) -> Void
        /// When true, uses three-level decision (white / yellow / black).
        /// When false, uses two-level decision (white / black).
        let threeLevel: Bool
    }
    private var elements: [UIElement] = []
    private var lastColors: [String: NSColor] = [:]
    private var lastSubtitleModes: [String: SubtitleColorTransition] = [:]

    // MARK: - Face detection (async, cached)

    /// Most recently detected face rects in screen-space (origin bottom-left, like NSScreen).
    /// Updated on a background queue every color-sample cycle; safe to read from any thread.
    private(set) var cachedFaces: [CGRect] = []
    private let faceQueue = DispatchQueue(label: "gor.face", qos: .utility)
    private var faceDetectionInFlight = false

    /// Gates the Vision face-detection piggyback in sampleColors() below.
    /// VR requests faces independently; random subtitle placement also enables
    /// the bounded face pass. Normal non-random playback pays no Vision cost.
    private var faceLifecycle: UInt64 = 0
    var vrModeActive = false {
        didSet {
            if vrModeActive != oldValue { faceLifecycle &+= 1; cachedFaces = []; faceSampleTime = 0 }
        }
    }

    // MARK: - Color sampling state

    /// Window ID of the mpv process window.
    /// Set by AppDelegate immediately after the mpv process launches.
    var mpvWindowID: CGWindowID = kCGNullWindowID {
        didSet {
            if mpvWindowID != oldValue { faceLifecycle &+= 1; cachedFaces = []; faceSampleTime = 0 }
        }
    }

    private var colorTimer: Timer?
    private var subtitleColorTimer: Timer?
    private var subtitleFaceTimer: Timer?
    private var faceThermalSkip: UInt = 0
    private var faceSampleTime: CFTimeInterval = 0
    private var faceSampleWindow: CGWindowID = kCGNullWindowID
    var freshSubtitleFaces: [CGRect] {
        guard faceSampleWindow == mpvWindowID,
              CACurrentMediaTime() - faceSampleTime <= 1.5 else { return [] }
        return cachedFaces
    }
    private var subtitleBands: [String: Int] = [:]
    private var subtitlePendingBands: [String: Int] = [:]
    private var subtitlePendingCounts: [String: Int] = [:]

    // MARK: - Audio level (public, read-only)

    /// Normalised audio level in [0, 1], updated on every audio callback.
    /// Read on the main thread from SubtitleView's display-link loop.
    private(set) var currentAudioLevel: Float = 0.0

    // MARK: - Raw PCM tap (for LiveCaptionController / whisper-live)
    //
    // Off by default - zero cost to the existing color/level pipeline when
    // no live-caption session is active. When enabled, _SCHandler additionally
    // resamples each buffer from the capture sampleRate (24000 Hz, see
    // startSCStream's SCStreamConfiguration below) to 16000 Hz - the rate
    // whisper.cpp requires - and forwards it via pcmHandler. This runs on the
    // same SCStream callback queue (.userInteractive) as processAudio(); the
    // resample is linear interpolation, not a full DSP resampler, but
    // sufficient for speech-band content at this 3:2 ratio.
    //
    // pcmHandler is called off the main thread. Callers must dispatch to
    // their own queue for main-thread work.
    var pcmTapEnabled = false
    var pcmHandler: ((UnsafeBufferPointer<Float>) -> Void)?

    /// Fixed by design: whisper.cpp / whisper-live expects 16 kHz mono f32.
    static let pcmTapOutputSampleRate: Double = 16000.0

    // Peak-hold: keeps currentAudioLevel from hard-dropping to 0.0 between
    // Process Tap buffer callbacks (~16-100 ms); decays toward the new
    // buffer's level rather than snapping.
    private var peakHoldLevel: Float = 0.0
    private var lastAudioTime:  Double = 0.0

    // MARK: - Core Audio Process Tap (audio only)

    /// PID of the mpv process to capture audio from.
    /// Set by AppDelegate immediately after the mpv process launches -
    /// mirrors how mpvWindowID is set for color sampling, but this is a
    /// process identifier (for Core Audio's PID->AudioObjectID translation),
    /// not a CGWindowID, so it's a distinct property.
    var mpvPID: pid_t = 0

    private var processTapID:      AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var tapIOProcID:       AudioDeviceIOProcID?
    // Main-queue-owned observation timer; never triggers recovery.
    private var tapObservationTimer: DispatchSourceTimer?
    // Off-main stop captures only this identity, protected independently.
    private let tapObservationTokenLock = NSLock()
    private var tapObservationTokenStorage: UUID?
    private var tapObservationToken: UUID? {
        get {
            tapObservationTokenLock.lock()
            defer { tapObservationTokenLock.unlock() }
            return tapObservationTokenStorage
        }
        set {
            tapObservationTokenLock.lock()
            defer { tapObservationTokenLock.unlock() }
            tapObservationTokenStorage = newValue
        }
    }
    private var tapObservationPending = false
    private var lastNoCallbackReportAt: Double = -.infinity
    private var lastTapZeroReportAt: Double = -.infinity

    // MARK: - Dead tap rebuild (owner-log 260918 item 1)
    /// Last audible-advancing playback note (CACurrentMediaTime). processTapQueue-owned.
    private var lastAudiblePlaybackNoteAt: Double = -.infinity
    /// Last liveness-driven rebuild; enforces the 120s cooldown. processTapQueue-owned.
    private var lastTapRebuildAt: Double = -.infinity
    /// Last successful tap build, set beside _ProcessTapPipeline.resetForNewTap().
    /// processTapQueue-owned. Negative until the first build lands.
    private var lastTapBuildAt: Double = -.infinity
    /// Liveness notes received since launch; proves the PPController->SCE note path in telemetry.
    private var livenessNoteCount: UInt64 = 0
    /// Liveness-driven rebuilds fired since launch.
    private var deadTapRebuildCount: UInt64 = 0
    /// Last level-telemetry print (CACurrentMediaTime). 30s cadence, notes-driven.
    private var lastLevelTelemetryAt: Double = -.infinity
    /// Start of the current low-but-nonzero level run (arm 3). processTapQueue-owned.
    private var lowLevelSince: Double? = nil
    /// Once-per-build diagnostic, not a permission determination.
    private var lastZeroEscalationBuildAt: Double = -.infinity
    /// Token for the kAudioHardwarePropertyDefaultSystemOutputDevice listener.
    /// The aggregate device wraps a specific output device as its main
    /// sub-device; if the user switches output devices (headphones,
    /// Bluetooth, external speakers) the aggregate must be torn down and rebuilt
    /// around the new default, or it silently stops delivering audio.
    private var defaultOutputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    /// Incremented on every listener fire; used to debounce/coalesce rapid
    /// or possibly-self-triggered kAudioHardwarePropertyDefaultSystemOutputDevice
    /// notifications into a single rebuild rather than stacking stop/start
    /// cycles. See installDefaultOutputDeviceListener.
    private let outputDeviceStateLock = NSLock()
    private var outputDeviceListenerLifetime: UInt64 = 0
    private var outputDeviceChangeGeneration = 0
    private var lastDefaultOutputDeviceID: AudioObjectID?
    private var pendingDefaultOutputDeviceID: AudioObjectID?
    // Lock-protected publication status. Resource IDs stay processTapQueue-owned.
    private var publishedAudioGeneration: UInt64?
    var audioRunning: Bool {
        audioRequestLock.lock()
        defer { audioRequestLock.unlock() }
        return publishedAudioGeneration != nil
    }
    // Cross-queue request fence. The lock covers request/publication, never HAL
    // calls or dispatch. Setup/teardown resources remain processTapQueue-owned.
    private let audioRequestLock = NSLock()
    private var audioCaptureRequested = false
    private var audioRequestGeneration: UInt64 = 0

    private func beginAudioCaptureRequest() -> UInt64 {
        audioRequestLock.lock()
        defer { audioRequestLock.unlock() }
        if !audioCaptureRequested {
            audioRequestGeneration &+= 1
            audioCaptureRequested = true
        }
        return audioRequestGeneration
    }

    @discardableResult
    private func cancelAudioCaptureRequest() -> UInt64 {
        audioRequestLock.lock()
        defer { audioRequestLock.unlock() }
        audioRequestGeneration &+= 1
        audioCaptureRequested = false
        publishedAudioGeneration = nil
        return audioRequestGeneration
    }

    // Atomically invalidate only this automatic-rebuild request. Return this
    // transition's own token; never adopt a later explicit stop's generation.
    private func cancelAudioCaptureRequest(ifCurrent generation: UInt64) -> UInt64? {
        audioRequestLock.lock()
        defer { audioRequestLock.unlock() }
        guard audioCaptureRequested, audioRequestGeneration == generation else { return nil }
        audioRequestGeneration &+= 1
        audioCaptureRequested = false
        publishedAudioGeneration = nil
        return audioRequestGeneration
    }

    private func resumeAudioCaptureRequest(ifStopped generation: UInt64) -> UInt64? {
        audioRequestLock.lock()
        defer { audioRequestLock.unlock() }
        guard !audioCaptureRequested, audioRequestGeneration == generation else { return nil }
        audioRequestGeneration &+= 1
        audioCaptureRequested = true
        return audioRequestGeneration
    }

    private func audioRequestIsCurrent(_ generation: UInt64) -> Bool {
        audioRequestLock.lock()
        defer { audioRequestLock.unlock() }
        return audioCaptureRequested && audioRequestGeneration == generation
    }

    fileprivate func currentAudioCaptureRequest() -> UInt64? {
        audioRequestLock.lock()
        defer { audioRequestLock.unlock() }
        return audioCaptureRequested ? audioRequestGeneration : nil
    }

    // processTapQueue only. Identity checks keep already-enqueued retry work inert.
    private func cancelPendingTapSetup() {
        pendingRetryWorkItem?.cancel()
        pendingRetryWorkItem = nil
        waitingForAudioReconfig = false
        tapSetupArmedForPlayback = false
        tapSetupInFlight = false
    }
    /// Guards against buildAndStartProcessTap being entered twice at once.
    /// It has no guard of its own - two overlapping calls would mean two
    /// concurrent AudioHardwareCreateProcessTap attempts. This matters now
    /// that there are two paths that can call it: the existing timed retry
    /// chain (buildAndStartProcessTap's own catch block) and the new
    /// audio-reconfig fast path (signalAudioReconfig, below) that can fire
    /// while a retry is already scheduled. Set the moment either path is
    /// about to call buildAndStartProcessTap; cleared on every exit from
    /// that function (success, a non-retrying failure return, or right
    /// before each retry actually re-enters it) - processTapQueue is
    /// serial, so read/write here never races.
    private var tapSetupInFlight = false

    /// Set when the 10x2s retry budget expired before mpv had any audio to
    /// tap. mpv only registers a Core Audio object once its audio device
    /// actually opens at playback start - on a slow-buffering stream that
    /// can be a minute after launch (field log 260926), long past the fixed
    /// window, so a hard give-up can never succeed there. While armed, the
    /// next playback-start signal (audio-reconfig / playback-restart)
    /// re-runs the whole setup loop. processTapQueue-owned, like
    /// tapSetupInFlight.
    private var tapSetupArmedForPlayback = false

    /// The scheduled blind 2s retry from buildAndStartProcessTap's catch
    /// block; nil while no retry is scheduled (a build can be in flight with
    /// this nil). handleAudioReconfigOnProcessTapQueue distinguishes the two:
    /// non-nil -> cancel the wait and retry on the real event; nil with
    /// tapSetupInFlight -> a build is genuinely running, bail (concurrent
    /// builds are unsafe - see tapSetupInFlight).
    private var pendingRetryWorkItem: DispatchWorkItem?

    /// Dedicated serial queue for Process Tap setup/teardown and as the
    /// IOProc callback queue (AudioDeviceCreateIOProcIDWithBlock takes an
    /// explicit queue rather than relying on an implicit default - passing
    /// nil there would depend on an unspecified/undocumented Core Audio
    /// internal thread, which is unnecessary when we can just supply one).
    /// Serial specifically so setup/teardown/rebuild-on-device-change calls
    /// can't interleave with each other or with an in-flight IOProc callback.
    private let processTapQueue = DispatchQueue(label: "gor.processtap", qos: .userInteractive)

    // MARK: - Element registration

    /// Register a UI element for two-level adaptive color (white / black).
    /// Typical callers: SpineUI, SidebarUI.
    func registerElement(id: String,
                         frameProvider: @escaping () -> CGRect?,
                         callback: @escaping (NSColor) -> Void) {
        elements.removeAll { $0.id == id }
        elements.append(UIElement(id: id,
                                  frameProvider: frameProvider,
                                  callback: { color, _ in callback(color) },
                                  threeLevel: false))
    }

    /// Register a UI element for three-level adaptive color (white / yellow / black).
    /// Intended for subtitle overlays where a mid-tone background requires a third option.
    func registerSubtitle(id: String,
                          frameProvider: @escaping () -> CGRect?,
                          callback: @escaping (NSColor) -> Void) {
        // Keep color-only callers source-compatible; new subtitle paint uses mode.
        registerSubtitle(id: id, frameProvider: frameProvider) { color, _ in callback(color) }
    }

    func registerSubtitle(id: String,
                          frameProvider: @escaping () -> CGRect?,
                          callback: @escaping (NSColor, SubtitleColorTransition) -> Void) {
        elements.removeAll { $0.id == id }
        elements.append(UIElement(id: id,
                                  frameProvider: frameProvider,
                                  callback: callback,
                                  threeLevel: true))
        lastSubtitleModes[id] = nil
    }

    /// Returns the most recently computed color for a registered element ID.
    func currentColor(for id: String) -> NSColor? { lastColors[id] }

    // MARK: - Lifecycle

    func start() {
        startColorSampling()
        startAudioCapture()
    }

    func stop() {
        stopColorSampling()
        stopAudioCapture()
    }

    /// Quit-time counterpart to stop(): identical (color sampling has
    /// nothing async to wait for - its own Timer.invalidate() is already
    /// synchronous), except it routes audio teardown through
    /// stopAudioCaptureSynchronously() instead of stopAudioCapture(). See
    /// that method's own comment for why this distinction exists at all:
    /// in short, applicationWillTerminate needs AudioHardwareDestroyProcessTap
    /// to have actually completed before the process exits, not merely
    /// been enqueued, or replayd's screen-capture attribution for this
    /// process is left stuck on permanently.
    @available(macOS 14.2, *)
    func stopForQuit() {
        stopColorSampling()
        stopAudioCaptureSynchronously()
    }

    // MARK: - Color sampling (CGWindowList)

    func startColorSampling() {
        stopColorSampling()
        colorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sampleColors(subtitleOnly: false)
        }
        RunLoop.main.add(colorTimer!, forMode: .common)
        // Fast contrast checks capture only visible subtitle bounds. Keep
        // panel sampling and VR face detection on their existing slow cadence.
        subtitleColorTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.sampleColors(subtitleOnly: true)
        }
        RunLoop.main.add(subtitleColorTimer!, forMode: .common)
        sampleColors(subtitleOnly: true)
        // Owner 2026-11-15 (95 C report): a screen capture + Vision face pass
        // at 2 Hz is a sustained background load; under thermal pressure drop
        // to 0.5 Hz. Face avoidance keeps working on a slower cadence.
        subtitleFaceTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if HeatTelemetry.thermalPressure {
                self.faceThermalSkip &+= 1
                if self.faceThermalSkip % 4 != 0 { return }
            } else { self.faceThermalSkip = 0 }
            self.sampleSubtitleFaces()
        }
        RunLoop.main.add(subtitleFaceTimer!, forMode: .common)
    }

    func stopColorSampling() {
        faceLifecycle &+= 1
        colorTimer?.invalidate()
        colorTimer = nil
        subtitleColorTimer?.invalidate()
        subtitleColorTimer = nil
        subtitleFaceTimer?.invalidate()
        subtitleFaceTimer = nil
        cachedFaces = []
        faceSampleTime = 0
        subtitleBands.removeAll()
        subtitlePendingBands.removeAll()
        subtitlePendingCounts.removeAll()
        lastSubtitleModes.removeAll()
    }

    private func sampleColors(subtitleOnly: Bool) {
        guard mpvWindowID != kCGNullWindowID else { return }
        let sampledElements = elements.filter { $0.threeLevel == subtitleOnly }
        guard !sampledElements.isEmpty, !subtitleOnly || SubtitleSampleGovernor.shared.shouldSample(signature: { sampledElements.map { $0.frameProvider() } }, now: CACurrentMediaTime()) else { return }

        // Restrict capture to the union of registered UI elements when not
        // in VR mode (face detection below needs the full frame). CG's
        // screenBounds uses top-left-origin/Y-down; frameProvider() rects
        // are AppKit screen-space (bottom-left-origin/Y-up) - flip each
        // before unioning. NSScreen.main matches the reference already
        // used for the scale math below, so both stay consistent.
        var captureBounds = CGRect.null
        if subtitleOnly || !vrModeActive, let mainH = NSScreen.main?.frame.height {
            for element in sampledElements {
                guard let r = element.frameProvider(), r.width > 0, r.height > 0 else { continue }
                captureBounds = captureBounds.union(
                    CGRect(x: r.minX, y: mainH - r.maxY, width: r.width, height: r.height)
                )
            }
        }

        // Hidden subtitles must not turn the fast path into full-window capture.
        if subtitleOnly && captureBounds.isNull { return }
        var image = CGWindowListCreateImage(
            captureBounds,
            .optionIncludingWindow,
            mpvWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        )
        var usedBounds = captureBounds
        if image == nil, !captureBounds.isNull, !subtitleOnly {
            // Restricted capture failed (e.g. rect fell outside the window) -
            // fall back to the previous unrestricted behaviour rather than
            // silently losing this tick's sample.
            image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, mpvWindowID,
                [.boundsIgnoreFraming, .nominalResolution]
            )
            usedBounds = .null
        }
        guard let image else { return }

        let imgW = CGFloat(image.width)
        let imgH = CGFloat(image.height)
        guard imgW > 0, imgH > 0 else { return }

        // Map screen-space element rects into image-space pixel rects.
        let screenW = NSScreen.main?.frame.width  ?? imgW
        let screenH = NSScreen.main?.frame.height ?? imgH
        // When usedBounds is restricted, image-space (0,0) is usedBounds'
        // flipped top-left, not the screen's - rebase before scaling.
        // (Reduces to the prior unrestricted formula when usedBounds is .null:
        // imgH - r.maxY*scaleY == (screenH - r.maxY)*scaleY when scaleY = imgH/screenH.)
        let scaleX  = imgW / (usedBounds.isNull ? screenW : usedBounds.width)
        let scaleY  = imgH / (usedBounds.isNull ? screenH : usedBounds.height)
        let originX = usedBounds.isNull ? 0 : usedBounds.minX
        let originY = usedBounds.isNull ? 0 : usedBounds.minY

        for element in sampledElements {
            guard let screenRect = element.frameProvider(),
                  screenRect.width > 0, screenRect.height > 0 else { continue }

            // CGWindowListCreateImage returns a flipped coordinate image;
            // convert screen-space Y (origin bottom-left) to image-space Y (origin top-left).
            let imgRect = CGRect(
                x:      (screenRect.minX - originX) * scaleX,
                y:      ((screenH - screenRect.maxY) - originY) * scaleY,
                width:  screenRect.width  * scaleX,
                height: screenRect.height * scaleY
            ).integral

            guard let cropped = image.cropping(to: imgRect) else { continue }

            let (luma, avg) = averageLumaAndColor(of: cropped)
            let decision = element.threeLevel
                ? subtitleDominantColor(of: cropped, id: element.id, avgColor: avg)
                : ColorDecision(color: decideColor(luma: luma, threeLevel: false, avgColor: avg), mode: .normal)
            let newColor = decision.color; HeatShadow.count(element.threeLevel ? "subtitleColorTicks" : "panelColorTicks")

            // Color dedup must not hide a normal -> clear-cut promotion of an
            // identical target: SubtitleView may still be painting its fade.
            let promotesCut = element.threeLevel && decision.mode == .clearCut
                && lastSubtitleModes[element.id] != .clearCut
            if element.threeLevel { lastSubtitleModes[element.id] = decision.mode }
            let last = lastColors[element.id]
            guard last == nil || last != newColor || promotesCut else { HeatShadow.count("colorNoChangeTicks"); continue }
            lastColors[element.id] = newColor

            let cb = element.callback
            DispatchQueue.main.async {
                if decision.mode == .clearCut {
                    cb(newColor, decision.mode)
                } else {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.35
                        cb(newColor, decision.mode)
                    }
                }
            }
        }

    }

    // Separate bounded 2Hz face pass, active in normal random subtitles too.
    // No Vision work on the 10Hz contrast path.
    private func sampleSubtitleFaces() {
        guard vrModeActive || (SubtitleView.Config.subPosRandom && SubtitleView.Config.faceAvoidance),
              mpvWindowID != kCGNullWindowID, !faceDetectionInFlight,
              let mainH = NSScreen.main?.frame.height,
              let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, mpvWindowID) as? [[String: Any]],
              let entry = entries.first,
              let dictionary = entry[kCGWindowBounds as String] as? [String: Any],
              let cgBounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
              let image = CGWindowListCreateImage(cgBounds, .optionIncludingWindow, mpvWindowID,
                                                 [.boundsIgnoreFraming, .nominalResolution]) else { return }
        let screenBounds = CGRect(x: cgBounds.minX, y: mainH - cgBounds.maxY,
                                  width: cgBounds.width, height: cgBounds.height)
        let windowID = mpvWindowID
        let sampledAt = CACurrentMediaTime()
        let lifecycle = faceLifecycle
        faceDetectionInFlight = true
        faceQueue.async { [weak self] in
            let request = VNDetectFaceRectanglesRequest()
            guard SubtitleFaceWatchdog.selectCPU(request) else {
                DispatchQueue.main.async { self?.faceDetectionInFlight = false }; return
            }
            let watchdog = SubtitleFaceWatchdog(request)
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let accepted = watchdog.finish()
            let faces = (accepted ? (request.results ?? []) : []).map { face -> CGRect in
                let bb = face.boundingBox
                // Face rectangle is not a full head: reserve hair/crown and sides.
                let head = CGRect(x: bb.minX - bb.width * 0.30,
                                  y: bb.minY - bb.height * 0.15,
                                  width: bb.width * 1.60, height: bb.height * 1.65)
                return CGRect(x: screenBounds.minX + head.minX * screenBounds.width,
                              y: screenBounds.minY + head.minY * screenBounds.height,
                              width: head.width * screenBounds.width, height: head.height * screenBounds.height)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.faceDetectionInFlight = false
                guard accepted, self.faceLifecycle == lifecycle,
                      self.vrModeActive || (SubtitleView.Config.subPosRandom && SubtitleView.Config.faceAvoidance),
                      self.mpvWindowID == windowID, self.subtitleFaceTimer != nil,
                      CACurrentMediaTime() - sampledAt <= 1.5 else { return }
                self.cachedFaces = faces
                self.faceSampleTime = sampledAt
                self.faceSampleWindow = windowID
            }
        }
    }

    // Area votes, not an average that can mistake a split surface for neutral.
    // A 10% winning margin plus 3 consecutive samples prevents threshold chatter.
    private func subtitleDominantColor(of image: CGImage, id: String,
                                      avgColor: (r: CGFloat, g: CGFloat, b: CGFloat)) -> ColorDecision {
        guard let ctx = sampleCtx else { return ColorDecision(color: lastColors[id] ?? Self.colorWhite, mode: .normal) }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let data = ctx.data else { return ColorDecision(color: lastColors[id] ?? Self.colorWhite, mode: .normal) }
        let ptr = data.bindMemory(to: UInt8.self, capacity: 1024)
        var votes = [0, 0, 0] // dark, neutral, light surface
        for i in 0..<256 {
            let y = (0.299 * CGFloat(ptr[i*4]) + 0.587 * CGFloat(ptr[i*4+1]) + 0.114 * CGFloat(ptr[i*4+2])) / 255
            votes[y < 0.40 ? 0 : (y > 0.60 ? 2 : 1)] += 1
        }
        let incumbent = subtitleBands[id] ?? 1
        var winner = incumbent
        for band in 0...2 where votes[band] > votes[winner] { winner = band }
        if subtitleBands[id] == nil {
            subtitleBands[id] = winner
        } else if winner != incumbent && votes[winner] - votes[incumbent] >= 26 {
            let count = subtitlePendingBands[id] == winner ? (subtitlePendingCounts[id] ?? 0) + 1 : 1
            subtitlePendingBands[id] = winner
            subtitlePendingCounts[id] = count
            // Near-uniform dark/light cut can leave an illegible incumbent immediately.
            if count >= 3 || (winner != 1 && votes[winner] >= 218) { subtitleBands[id] = winner }
        } else {
            subtitlePendingBands[id] = nil
            subtitlePendingCounts[id] = nil
        }
        let band = subtitleBands[id] ?? winner
        // Also carry a cut when the band is already accepted: a prior normal
        // callback may still have a 550ms paint transition in flight.
        let mode: SubtitleColorTransition = band != 1 && winner == band && votes[band] >= 218
            ? .clearCut : .normal
        if band == 0 { return ColorDecision(color: Self.colorWhite, mode: mode) }
        if band == 2 { return ColorDecision(color: Self.colorBlack, mode: mode) }
        // Keep neutral surface decisions stable too; avoid an average-luma
        // 0.55 toggle when the neutral surface happens to be yellowish.
        let yellowish = avgColor.r > 0.5 && avgColor.g > 0.4 && avgColor.b < 0.7
        if yellowish {
            let previous = lastColors[id]
            return ColorDecision(color: previous == Self.colorBlack ? Self.colorBlack : Self.colorWhite, mode: .normal)
        }
        return ColorDecision(color: Self.colorGrey, mode: .normal)
    }

    private func decideColor(luma: CGFloat,
                             threeLevel: Bool,
                             avgColor: (r: CGFloat, g: CGFloat, b: CGFloat)) -> NSColor {
        if luma > lightThreshold { return Self.colorBlack }
        if luma < darkThreshold  { return Self.colorWhite }
        guard threeLevel else { return Self.colorWhite }
        // Yellow is illegible on a yellowish background - fall back to black.
        let isYellowish = avgColor.r > 0.5 && avgColor.g > 0.4 && avgColor.b < 0.7
        if isYellowish {
            return luma > 0.55 ? Self.colorBlack : Self.colorWhite
        }
        return Self.colorGrey
    }

    /// Reused across every averageLumaAndColor() call (every registered
    /// element, every 2s tick, for as long as media plays, plus
    /// ContentAdaptiveDimming's own ~0.4s ticks via currentMPVLuma()
    /// below) instead of allocating a fresh 16x16 bitmap context each
    /// time. Safe to reuse: ctx.draw() below always fully overwrites
    /// the canvas, and every caller is main-thread-only (Timer-driven),
    /// so draws are always serialized, never concurrent.
    private lazy var sampleCtx: CGContext? = CGContext(
        data: nil,
        width: 16, height: 16,
        bitsPerComponent: 8,
        bytesPerRow: 64,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )

    private func averageLumaAndColor(of image: CGImage)
        -> (luma: CGFloat, color: (r: CGFloat, g: CGFloat, b: CGFloat)) {

        // Downsample to 16x16 before averaging; fast and sufficient for color decisions.
        guard let ctx = sampleCtx else { return (0.5, (0.5, 0.5, 0.5)) }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let data = ctx.data else { return (0.5, (0.5, 0.5, 0.5)) }

        let ptr   = data.bindMemory(to: UInt8.self, capacity: 16 * 16 * 4)
        let count = 256
        var luma: CGFloat = 0
        var rSum: CGFloat = 0, gSum: CGFloat = 0, bSum: CGFloat = 0

        for i in 0..<count {
            let r = CGFloat(ptr[i * 4])     / 255
            let g = CGFloat(ptr[i * 4 + 1]) / 255
            let b = CGFloat(ptr[i * 4 + 2]) / 255
            luma += 0.299 * r + 0.587 * g + 0.114 * b
            rSum += r; gSum += g; bSum += b
        }
        return (luma / 256, (rSum / 256, gSum / 256, bSum / 256))
    }

    // MARK: - Standalone luma sampling (ContentAdaptiveDimming)

    /// One-shot average luma of the current mpv window content,
    /// independent of the registerElement/registerSubtitle pipeline
    /// above (that path only exposes a threshold-decided NSColor, not
    /// a continuous value, and drives a different feature -
    /// adaptive UI-text color - off its own registered-rect list).
    ///
    /// - Parameter screenRect: AppKit screen-space (bottom-left
    ///   origin), same convention as UIElement.frameProvider() above.
    ///   Pass the actual video content rect so bar/letterbox regions
    ///   (which are already black and would bias the reading dark)
    ///   are excluded. Pass nil, or a zero-size rect, to sample the
    ///   whole mpv window unrestricted - used as a graceful fallback
    ///   before the caller has a real content rect yet.
    /// - Returns: luma in [0, 1], or nil if mpvWindowID isn't set yet
    ///   or the capture itself fails (e.g. window briefly offscreen).
    func currentMPVLuma(inScreenRect screenRect: CGRect? = nil) -> CGFloat? {
        guard mpvWindowID != kCGNullWindowID else { return nil }

        var captureBounds = CGRect.null
        if let screenRect, screenRect.width > 0, screenRect.height > 0,
           let mainH = NSScreen.main?.frame.height {
            // Same top-left/Y-down conversion sampleColors() applies to
            // frameProvider() rects, kept identical for consistency.
            captureBounds = CGRect(x: screenRect.minX, y: mainH - screenRect.maxY,
                                   width: screenRect.width, height: screenRect.height)
        }

        guard let image = CGWindowListCreateImage(
            captureBounds, .optionIncludingWindow, mpvWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else { return nil }

        return averageLumaAndColor(of: image).luma
    }

    // MARK: - Audio capture (SCStream, audio-only)

    func startAudioCapture(retryCount: Int = 0) {
        // Serialize request transitions and queue submission on main. Publication
        // is still on processTapQueue, locked together with request validation.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.startAudioCapture(retryCount: retryCount) }
            return
        }
        let generation = beginAudioCaptureRequest()
        startAudioCapture(retryCount: retryCount, generation: generation)
    }

    private func startAudioCapture(retryCount: Int, generation: UInt64) {
        guard audioRequestIsCurrent(generation), !audioRunning else { return }
        guard #available(macOS 14.2, *) else {
            print("[SCE] macOS 14.2+ required (Core Audio Process Tap).")
            return
        }
        guard mpvPID != 0 else {
            // AppDelegate may not have set mpvPID yet (short window
            // between launchMPV's process launch and this call): wait
            // briefly and retry.
            guard retryCount < 10 else {
                print("[SCE] mpvPID still unset after 10 tries \u{2014} cannot start audio capture.")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startAudioCapture(retryCount: retryCount + 1, generation: generation)
            }
            return
        }
        // No preflight check exists for "System Audio Recording Only" -
        // unlike CGPreflightScreenCaptureAccess, Apple has confirmed there is
        // no public API to check this permission ahead of time. The system
        // prompts automatically the first time an aggregate device containing
        // a tap is started (AudioDeviceStart below), same as the old
        // CGRequestScreenCaptureAccess flow but handled implicitly by the OS
        // rather than requested explicitly by us.
        //
        // NOT routed through SCEWorkerThread: that class exists specifically
        // to give SCShareableContent's completion-handler delivery an
        // actively-pumped run loop (see its own header comment) - a quirk of
        // that specific API, not of Core Audio in general. AudioHardware-
        // CreateProcessTap / AudioHardwareCreateAggregateDevice /
        // AudioDeviceCreateIOProcIDWithBlock are ordinary synchronous HAL
        // calls (the latter even takes an explicit DispatchQueue parameter
        // for its callback, confirmed below) with no documented run-loop
        // dependency. A plain background queue is the correct - and
        // simpler - fit.
        // The event window below matters here: without it, this async
        // block always wins the race against mpv's real audio-reconfig
        // event (confirmed via build log - mpvPID is already nonzero by
        // the time attachOverlay's chain reaches this call, but Core
        // Audio doesn't recognize the PID yet), which meant the fast
        // path in signalAudioReconfig was structurally unreachable: the
        // first blind attempt always got there first and locked
        // tapSetupInFlight before the event could matter.
        processTapQueue.async { [weak self] in
            guard let self, self.audioRequestIsCurrent(generation) else { return }
            self.attemptTapSetupPreferringEvent(generation: generation)
        }
    }

    /// True while startAudioCapture is deliberately holding off its first
    /// buildAndStartProcessTap attempt to give audio-reconfig a chance to
    /// fire first. Distinct from tapSetupInFlight: that flag means "a
    /// build attempt is actively running or about to retry"; this one
    /// means "no attempt has started yet, on purpose." signalAudioReconfig
    /// checks this (not tapSetupInFlight) to decide whether an incoming
    /// event should short-circuit straight to buildAndStartProcessTap.
    private var waitingForAudioReconfig = false

    /// Entry point for the first tap-setup attempt after mpvPID becomes
    /// available. Holds a short window (2s, matching the retry gap) for
    /// mpv's real audio-reconfig event to arrive first, because an eager
    /// blind attempt always loses that race (mpvPID is set well before
    /// mpv's AO actually opens).
    @available(macOS 14.2, *)
    private func attemptTapSetupPreferringEvent(generation: UInt64) {
        guard audioRequestIsCurrent(generation) else { return }
        // A fresh explicit capture cycle supersedes any armed wait left
        // over from a previous file's expired retry budget.
        tapSetupArmedForPlayback = false
        guard !audioRunning, !tapSetupInFlight, !waitingForAudioReconfig else {
            // Another path (a prior call to this same function, or
            // signalAudioReconfig's fast path arriving via its own
            // processTapQueue.async hop) already claimed this attempt.
            // Everything that touches tapSetupInFlight or
            // waitingForAudioReconfig runs on processTapQueue - this
            // function directly, signalAudioReconfig by dispatching onto
            // it before it reads or writes either flag - so this check
            // and the flag set immediately below can't interleave with
            // any of them.
            return
        }
        waitingForAudioReconfig = true
        processTapQueue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            // If audio-reconfig already fired and moved this along
            // (waitingForAudioReconfig flipped false in
            // handleAudioReconfigOnProcessTapQueue, which then called
            // buildAndStartProcessTap directly - that call sets
            // tapSetupInFlight itself, on its own first line), this
            // window closing is a no-op: don't start a second, redundant
            // attempt on top of the one already running.
            guard self.audioRequestIsCurrent(generation), self.waitingForAudioReconfig else { return }
            self.waitingForAudioReconfig = false
            self.buildAndStartProcessTap(retryCount: 0, generation: generation)
        }
    }

    /// Called when PPController's persistent mpv IPC connection observes
    /// an `audio-reconfig` event - the actual moment mpv's AO opens.
    /// attemptTapSetupPreferringEvent holds the first attempt open for a
    /// short window so this has something to short-circuit (mpvPID is set
    /// well before the AO opens, so an eager attempt always won the race).
    /// The event can also fire mid-playback after an unrelated failure, so
    /// the retry chain and tapSetupInFlight check still apply.
    func signalAudioReconfig() {
        guard #available(macOS 14.2, *) else {
            // Matches startAudioCapture's own guard - on older systems
            // there is no Process Tap API for buildAndStartProcessTap to
            // call, so this path (independent of startAudioCapture's own
            // guard - reached directly from PPController.handleMPVEvent
            // every time mpv sends this event) must stop here rather than
            // ever reaching processTapQueue.
            print("[SCE] audio-reconfig received, ignoring (macOS 14.2+ required).")
            return
        }
        // CONTRACT: waitingForAudioReconfig/tapSetupInFlight are only
        // mutated on processTapQueue; this arrives on gor.ipc.persistent,
        // so hop queues before touching them (cross-queue race on plain
        // Bools otherwise).
        guard let generation = currentAudioCaptureRequest() else { return }
        processTapQueue.async { [weak self] in
            guard let self, self.audioRequestIsCurrent(generation) else { return }
            self.handleAudioReconfigOnProcessTapQueue(generation: generation)
        }
    }

    /// PPController calls this at ~1Hz from its mpv poll while playback is
    /// unpaused, unmuted, volume > 0 and the playhead is actually advancing.
    /// This is the independent liveness proof the zero-content diagnostic
    /// always withheld recovery for want of: a tap delivering digital zero
    /// WHILE mpv audibly advances cannot be a quiet passage; the tap is dead.
    /// Field log 260918: unbroken zeros 2-332s during confirmed advancing
    /// playback after the 17:55:34 resume; fonts flat the whole time.
    /// Evaluation rides the note: notes stop when playback pauses, mutes or
    /// freezes, so a rebuild can only fire while recovery is both needed
    /// (zeros) and safe to verify (advancing audible playback). No new timer.
    func notePlaybackLiveness() {
        guard #available(macOS 14.2, *) else { return }
        processTapQueue.async { [weak self] in
            guard let self else { return }
            self.lastAudiblePlaybackNoteAt = CACurrentMediaTime()
            self.livenessNoteCount &+= 1
            self.updateLowLevelRun()
            self.evaluateDeadTapRebuild()
            self.printLevelTelemetryIfDue()
        }
    }

    /// Arm 3 evidence: a tap can deliver NON-zero but inaudible content
    /// (mis-scaled samples, wrong-format readback). That defeats the zero-run
    /// diagnostics, which need exact digital zero, and arms 1/2 alike. Track
    /// how long the published level stays above zero yet below audibility.
    /// Evaluated per liveness note (~1Hz during audible advancing playback).
    @available(macOS 14.2, *)
    private func updateLowLevelRun() {
        let level = currentAudioLevel
        if level > 0, level <= 0.02 {
            if lowLevelSince == nil { lowLevelSince = CACurrentMediaTime() }
        } else {
            lowLevelSince = nil
        }
    }

    /// Bounded proof of WHERE the font signal dies, printed every 30s while
    /// audible-advancing notes arrive (audible playback only): the published
    /// level, the pipeline's own content flags, the note count (proves the
    /// PPController->SCE liveness path end to end) and the rebuild count.
    /// One line per 30s; the next field log reads tap-vs-pipeline directly.
    @available(macOS 14.2, *)
    private func printLevelTelemetryIfDue() {
        let now = CACurrentMediaTime()
        guard now - lastLevelTelemetryAt >= 30.0 else { return }
        lastLevelTelemetryAt = now
        let s = _ProcessTapPipeline.zeroRunState()
        let levelText = String(format: "%.3f", currentAudioLevel)
        let zeroText = String(format: "%.1f", Self.zeroEvidenceSeconds(hasSeenNonZero: s.hasSeenNonZero,
                                      zeroStartedAt: s.zeroStartedAt, callbackCount: s.callbackCount,
                                      tapStartedAt: lastTapBuildAt, now: now))
        // This existing 30s liveness report is always enabled, unlike F3.
        // Snapshot UI state only on main; never log in the real-time callback.
        DispatchQueue.main.async {
            print("[VB][clock] \(VariationBroadcaster.shared.clockStatus())")
        }
        print("[SCE] level telemetry: current=\(levelText) zero_run=\(zeroText)s seen_nonzero=\(s.hasSeenNonZero) callbacks=\(s.callbackCount) notes=\(livenessNoteCount) rebuilds=\(deadTapRebuildCount)")
    }

    @available(macOS 14.2, *)
    private func evaluateDeadTapRebuild() {
        guard let generation = currentAudioCaptureRequest(), audioRunning, !tapSetupInFlight else { return }
        let now = CACurrentMediaTime()
        let s = _ProcessTapPipeline.zeroRunState()
        let zero = Self.zeroEvidenceSeconds(hasSeenNonZero: s.hasSeenNonZero,
                                            zeroStartedAt: s.zeroStartedAt,
                                            callbackCount: s.callbackCount,
                                            tapStartedAt: lastTapBuildAt, now: now)
        if Self.shouldRebuildForZeroTap(zeroSeconds: zero,
                                        sawContentSinceBuild: s.hasSeenNonZero,
                                        secondsSinceLivenessNote: now - lastAudiblePlaybackNoteAt,
                                        secondsSinceLastRebuild: now - lastTapRebuildAt) {
            lastTapRebuildAt = now
            deadTapRebuildCount &+= 1
            let zeroText = String(format: "%.1f", zero)
            print("[SCE] tap rebuild: zero_seconds=\(zeroText) saw_content=\(s.hasSeenNonZero) while playback audibly advancing - dead tap proven by independent liveness, rebuilding (cooldown 120s)")
            // Same rebuild primitive the default-output-device listener uses:
            // cancel the request, full teardown, restart after 0.3s on main.
            DispatchQueue.main.async { [weak self] in
                self?.restartAudioCaptureIfCurrent(generation)
            }
            return
        }
        // Preserve prior never-nonzero telemetry without claiming zero samples
        // prove TCC denial or asking for a per-launch settings workaround.
        if Self.shouldEscalateZeroWithhold(hasSeenNonZero: s.hasSeenNonZero,
                                           callbackCount: s.callbackCount,
                                           secondsSinceBuild: now - lastTapBuildAt,
                                           alreadyEscalatedForBuild: lastZeroEscalationBuildAt == lastTapBuildAt) {
            lastZeroEscalationBuildAt = lastTapBuildAt
            print("[SCE] WARNING: tap has never delivered nonzero audio after 45s with >=1000 callbacks; capture/permission/output routing requires inspection. This is not proof of permission denial.")
        }
        // Arm 3: low-but-nonzero level. Zero-run arms need exact digital zero;
        // an inaudible-but-nonzero tap (mis-scaled samples) slips past all of
        // them and past every existing diagnostic. 20s below audibility while
        /// playback audibly advances is unreachable by content loudness at any
        /// normal mpv volume; same 120s cooldown bounds the false-positive cost
        /// (extended quiet passages) to one 0.3s capture gap per 2 minutes.
        if let since = lowLevelSince {
            let lowSeconds = now - since
            guard Self.shouldRebuildForLowLevel(lowLevelSeconds: lowSeconds,
                                                secondsSinceLastRebuild: now - lastTapRebuildAt) else { return }
            lastTapRebuildAt = now
            deadTapRebuildCount &+= 1
            let lowText = String(format: "%.1f", lowSeconds)
            print("[SCE] tap rebuild: low_level_seconds=\(lowText) (0<level<=0.02) while playback audibly advancing - inaudible tap content, rebuilding (cooldown 120s)")
            DispatchQueue.main.async { [weak self] in
                self?.restartAudioCaptureIfCurrent(generation)
            }
        }
    }

    /// Historical telemetry threshold, not a diagnosis of privacy state.
    static func shouldEscalateZeroWithhold(hasSeenNonZero: Bool,
                                           callbackCount: UInt64,
                                           secondsSinceBuild: Double,
                                           alreadyEscalatedForBuild: Bool) -> Bool {
        !hasSeenNonZero && callbackCount >= 1000 && secondsSinceBuild >= 45 && !alreadyEscalatedForBuild
    }

    /// Pure arm-3 decision, Linux-harness tested.
    static func shouldRebuildForLowLevel(lowLevelSeconds: Double,
                                         secondsSinceLastRebuild: Double) -> Bool {
        guard lowLevelSeconds >= 20.0 else { return false }
        guard secondsSinceLastRebuild >= 120.0 else { return false }
        return true
    }

    /// Pure decision, Linux-harness tested. Post-content zero runs (the tap
    /// saw real audio, then died - the field failure) trip at 10s; a tap that
    /// never saw content gets 20s because genuinely silent openings exist.
    /// 120s cooldown: no rebuild storms, and a useless rebuild on legitimately
    /// silent content costs at most one 0.3s capture gap per 2 minutes.
    static func shouldRebuildForZeroTap(zeroSeconds: Double, sawContentSinceBuild: Bool,
                                        secondsSinceLivenessNote: Double,
                                        secondsSinceLastRebuild: Double) -> Bool {
        guard secondsSinceLivenessNote <= 3.0 else { return false }
        let threshold = sawContentSinceBuild ? 10.0 : 20.0
        guard zeroSeconds >= threshold else { return false }
        guard secondsSinceLastRebuild >= 120.0 else { return false }
        return true
    }

    /// Pure zero-evidence measure, Linux-harness tested. Two arms, both
    /// requiring a live IOProc (callbackCount > 0 on arm 2; zeroStartedAt is
    /// only set by a running callback on arm 1): content-then-zero (the dead
    /// tap we saw), and zero-from-birth (tap born dead). A silent HAL thread
    /// is the callback-absence case, owned by its own diagnostic.
    static func zeroEvidenceSeconds(hasSeenNonZero: Bool, zeroStartedAt: Double?,
                                    callbackCount: UInt64, tapStartedAt: Double,
                                    now: Double) -> Double {
        if hasSeenNonZero {
            guard let zeroStartedAt else { return 0 }
            return max(0, now - zeroStartedAt)
        }
        guard callbackCount > 0, tapStartedAt > 0 else { return 0 }
        return max(0, now - tapStartedAt)
    }

    /// PPController.handleMPVEvent calls this on mpv's "playback-restart"
    /// event (playback start, every unpause/seek). Only acts when the tap
    /// setup exhausted its retry budget before mpv had any audio to tap -
    /// cheap no-op otherwise.
    func signalPlaybackStart() {
        guard #available(macOS 14.2, *) else { return }
        guard let generation = currentAudioCaptureRequest() else { return }
        processTapQueue.async { [weak self] in
            guard let self, self.audioRequestIsCurrent(generation) else { return }
            self.handlePlaybackStartOnProcessTapQueue(generation: generation)
        }
    }

    /// Same queue-hop split as signalAudioReconfig (availability checking
    /// does not propagate across closure boundaries).
    @available(macOS 14.2, *)
    private func handlePlaybackStartOnProcessTapQueue(generation: UInt64) {
        guard audioRequestIsCurrent(generation) else { return }
        guard tapSetupArmedForPlayback, !audioRunning else { return }
        print("[SCE] playback-restart received \u{2014} re-running armed tap setup")
        tapSetupArmedForPlayback = false
        buildAndStartProcessTap(retryCount: 0, generation: generation)
    }

    /// The actual logic for signalAudioReconfig, guaranteed to run on
    /// processTapQueue. Split out from signalAudioReconfig itself so the
    /// queue-hop is visually obvious at the call site above rather than
    /// buried after a first line of real logic. @available here matches
    /// the explicit `if #available` already checked at the call site
    /// above - Swift's availability checking does not propagate across
    /// closure boundaries on its own, so that check has to be written
    /// out there rather than assumed from signalAudioReconfig's own
    /// top-level guard.
    @available(macOS 14.2, *)
    private func handleAudioReconfigOnProcessTapQueue(generation: UInt64) {
        guard audioRequestIsCurrent(generation) else { return }
        if tapSetupArmedForPlayback, !audioRunning {
            // The retry budget expired before mpv had any audio to tap;
            // this event is the audio device actually opening - run the
            // whole loop again.
            print("[SCE] audio-reconfig received \u{2014} re-running armed tap setup")
            tapSetupArmedForPlayback = false
            buildAndStartProcessTap(retryCount: 0, generation: generation)
            return
        }
        if waitingForAudioReconfig {
            // Common case: the 2s window is still open and mpv just told
            // us the real moment to try - go now instead of waiting it out.
            print("[SCE] audio-reconfig received \u{2014} using it to trigger the held first attempt")
            waitingForAudioReconfig = false
            buildAndStartProcessTap(retryCount: 0, generation: generation)
            return
        }
        guard !audioRunning, mpvPID != 0 else {
            // Nothing to do, or too early - startAudioCapture's own guards
            // would just no-op or re-enter its mpvPID-wait retry anyway, so
            // bail before even queueing.
            print("[SCE] audio-reconfig received, not acting (audioRunning=\(audioRunning) mpvPID=\(mpvPID))")
            return
        }
        if tapSetupInFlight {
            if let pending = pendingRetryWorkItem {
                // A blind retry is sleeping and the real signal it stands
                // in for just arrived - cancel the wait and use the event
                // instead of sitting out the rest of a fixed 2s guess.
                pending.cancel()
                pendingRetryWorkItem = nil
                tapSetupInFlight = false
                print("[SCE] audio-reconfig received \u{2014} cancelling pending blind retry, using event instead")
                buildAndStartProcessTap(retryCount: 0, generation: generation)
                return
            }
            // No pending wait to cancel - a build attempt is genuinely
            // executing synchronously right now. Entering again here would
            // risk two concurrent buildAndStartProcessTap calls, which that
            // function has no guard against internally. Let the in-flight
            // attempt run its course - see tapSetupInFlight's own doc
            // comment.
            print("[SCE] audio-reconfig received, not acting (build already in flight)")
            return
        }
        print("[SCE] audio-reconfig received \u{2014} triggering tap setup immediately (bypassing retry wait)")
        buildAndStartProcessTap(retryCount: 0, generation: generation)
    }

    func stopAudioCapture() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stopAudioCapture() }
            return
        }
        cancelAudioCaptureRequest()
        enqueueAudioCaptureTeardown()
    }

    private func enqueueAudioCaptureTeardown() {
        dispatchPrecondition(condition: .onQueue(.main))
        if SCERecorderConfig.enabled { stopTapCallbackObservation() }
        currentAudioLevel = 0
        guard #available(macOS 14.2, *) else { return }
        processTapQueue.async { [weak self] in
            guard let self else { return }
            self.cancelPendingTapSetup()
            self.removeDefaultOutputDeviceListener()
            // Read IDs here, after any already-running build has returned.
            // Caller-thread snapshots could miss the tap that build just created.
            self.teardownProcessTap(tap: self.processTapID,
                                    aggregate: self.aggregateDeviceID,
                                    ioProc: self.tapIOProcID)
            self.processTapID = .unknown
            self.aggregateDeviceID = .unknown
            self.tapIOProcID = nil
        }
    }

    /// SYNCHRONOUS counterpart to stopAudioCapture(), for the one call site
    /// where async teardown is harmful: applicationWillTerminate.
    ///
    /// TRAP: starting a process tap flips replayd's hasStarted=1 for this
    /// process's audit token; only AudioHardwareDestroyProcessTap running
    /// BEFORE exit ends that attribution (replayd has no other signal), or
    /// the menubar "gor is capturing your screen" indicator survives quit.
    /// stopAudioCapture()'s async teardown would still be queued behind the
    /// process exiting. The .sync block here is deliberate and bounded:
    /// teardown is a handful of synchronous HAL calls, runs once at quit
    /// after all fades, and never touches replayd's process directly.
    @available(macOS 14.2, *)
    func stopAudioCaptureSynchronously() {
        // Quit caller must be main; never sync-dispatch onto our own queue.
        dispatchPrecondition(condition: .onQueue(.main))
        cancelAudioCaptureRequest()
        if SCERecorderConfig.enabled { stopTapCallbackObservation() }
        currentAudioLevel = 0
        let teardownSucceeded = processTapQueue.sync { [weak self] () -> Bool in
            guard let self else { return false }
            self.cancelPendingTapSetup()
            self.removeDefaultOutputDeviceListener()
            let succeeded = self.teardownProcessTap(tap: self.processTapID,
                                    aggregate: self.aggregateDeviceID,
                                    ioProc: self.tapIOProcID)
            self.processTapID = .unknown
            self.aggregateDeviceID = .unknown
            self.tapIOProcID = nil
            return succeeded
        }
        print("[SCE] quit: synchronous tap teardown completed, allHALCallsSucceeded=\(teardownSucceeded); attribution state not independently verified")
    }

    /// Full teardown in the order Apple's own forum guidance confirms is
    /// required (restarting the IOProc alone, or recreating only the
    /// aggregate device, is not reliable): stop -> destroy IOProc -> destroy
    /// aggregate -> destroy tap. Safe to call with any subset of IDs already
    /// invalid (e.g. mid-rebuild on an output-device change).
    @available(macOS 14.2, *)
    @discardableResult
    private func teardownProcessTap(tap: AudioObjectID, aggregate: AudioObjectID, ioProc: AudioDeviceIOProcID?) -> Bool {
        var succeeded = true
        func record(_ operation: String, _ status: OSStatus) {
            guard status != noErr else { return }
            succeeded = false
            print("[SCE] teardown failed: \(operation) status=\(status) tap=\(tap) aggregate=\(aggregate)")
        }
        // Attempt every release even if an earlier operation fails. These are
        // queue-owned synchronous HAL calls, never the realtime audio callback.
        if aggregate.isValid, let ioProc {
            record("AudioDeviceStop", AudioDeviceStop(aggregate, ioProc))
            record("AudioDeviceDestroyIOProcID", AudioDeviceDestroyIOProcID(aggregate, ioProc))
        }
        if aggregate.isValid {
            record("AudioHardwareDestroyAggregateDevice", AudioHardwareDestroyAggregateDevice(aggregate))
        }
        if tap.isValid {
            record("AudioHardwareDestroyProcessTap", AudioHardwareDestroyProcessTap(tap))
        }
        return succeeded
    }

    /// Re-resolves the tap target on every attempt. Prefers the live
    /// AppDelegate.mpvProcess, falls back to the stored mpvPID, and only
    /// trusts a candidate that is both alive (kill(pid, 0)) and actually
    /// mpv (a recycled PID could belong to anyone). Runs on
    /// processTapQueue. livePID is read asynchronously on main by the caller;
    /// never synchronously wait for main while quit may wait for this queue.
    private func resolveTapTargetPID(livePID: pid_t) -> pid_t? {
        func usable(_ pid: pid_t) -> Bool {
            guard pid != 0 else { return false }
            // kill(pid, 0): 0 or EPERM = alive, ESRCH = gone.
            guard kill(pid, 0) == 0 || errno == EPERM else { return false }
            return NSRunningApplication(processIdentifier: pid)?
                .executableURL?.lastPathComponent == "mpv"
        }
        if usable(livePID) { mpvPID = livePID; return livePID }
        if usable(mpvPID) { return mpvPID }
        print("[SCE] tap target unresolved: livePID=\(livePID) storedPID=\(mpvPID) (dead, recycled, or not mpv)")
        return nil
    }

    @available(macOS 14.2, *)
    private func buildAndStartProcessTap(retryCount: Int, generation: UInt64) {
        // processTapQueue claim: caller token cannot adopt a replacement request.
        guard audioRequestIsCurrent(generation), !audioRunning, !tapSetupInFlight else { return }
        waitingForAudioReconfig = false
        tapSetupArmedForPlayback = false
        tapSetupInFlight = true
        // Do not main.sync from processTapQueue: quit synchronously drains it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.audioRequestIsCurrent(generation) else { return }
            let livePID = (NSApp.delegate as? AppDelegate)?.mpvProcess?.processIdentifier ?? 0
            self.processTapQueue.async { [weak self] in
                guard let self, self.audioRequestIsCurrent(generation) else { return }
                self.buildAndStartProcessTap(retryCount: retryCount,
                                             generation: generation, livePID: livePID)
            }
        }
    }

    @available(macOS 14.2, *)
    private func buildAndStartProcessTap(retryCount: Int, generation: UInt64, livePID: pid_t) {
        guard audioRequestIsCurrent(generation), tapSetupInFlight, !audioRunning else { return }
        // Attempt-local ownership: every throw (including output UID/ASBD
        // reads) releases resources before a retry. Published resources are
        // transferred to the engine only after the generation fence accepts.
        var ownedTap = AudioObjectID.unknown
        var ownedAggregate = AudioObjectID.unknown
        var ownedIOProc: AudioDeviceIOProcID?
        defer {
            teardownProcessTap(tap: ownedTap, aggregate: ownedAggregate, ioProc: ownedIOProc)
        }
        do {
            // 1. PID -> AudioObjectID. Core Audio doesn't work with PIDs
            //    directly (see kAudioHardwarePropertyTranslatePIDToProcessObject).
            //    Re-resolve the target on every attempt: the stored mpvPID
            //    goes stale the moment mpv is relaunched, crashes, or its
            //    PID is recycled, and a stale value fails this translation
            //    identically on every retry (field log 260926: the same
            //    "Invalid process identifier" 10 times).
            guard let targetPID = resolveTapTargetPID(livePID: livePID) else {
                throw NSError(domain: "gor.CoreAudioUtils", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "No live mpv process to tap"])
            }
            // Distinguishes the two field failure modes: an "Invalid process
            // identifier" AFTER this line means the PID is alive and really
            // mpv but Core Audio has no object for it yet (audio device not
            // open); "tap target unresolved" above means stale/dead PID.
            print("[SCE] tap attempt \(retryCount + 1): pid \(targetPID) alive + identity-verified as mpv")
            let processObjectID = try AudioObjectID.translatePIDToProcessObjectID(pid: targetPID)

            // 2. Tap description targeting just this process's output.
            let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
            tapDescription.uuid = UUID()
            tapDescription.muteBehavior = .unmuted
            tapDescription.isPrivate = true
            tapDescription.name = "gor mpv audio tap"
            let tapUID = tapDescription.uuid.uuidString

            var tapID = AudioObjectID.unknown
            var status = AudioHardwareCreateProcessTap(tapDescription, &tapID)
            ownedTap = tapID
            guard status == noErr, tapID.isValid else {
                // No dead-end: route through the catch's retry (10x2s) and
                // playback-start arming like every other setup failure. A
                // launch-time HAL/TCC failure must not kill audio reactivity
                // for the whole session (field report 261023: font flat
                // until the user re-toggled the macOS audio permission and
                // relaunched).
                print("[SCE] \u{274c} AudioHardwareCreateProcessTap failed: \(status) \u{2014} will retry via the standard setup retry path")
                throw NSError(domain: "gor.CoreAudioUtils", code: -3,
                              userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateProcessTap failed: \(status)"])
            }

            // 3. Aggregate device wrapping the CURRENT default system output
            //    as its main sub-device, with the tap attached as a sub-tap.
            //    The aggregate must be built around a real output device -
            //    it cannot be tap-only - and must be rebuilt whenever the
            //    default output device changes (handled by the listener
            //    registered below), or it silently stops delivering audio.
            let outputDeviceID = try AudioObjectID.readDefaultSystemOutputDevice()
            let outputUID = try outputDeviceID.readDeviceUID()

            let aggregateUID = UUID().uuidString
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "gor-audio-tap-aggregate",
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapDriftCompensationKey: true,
                        kAudioSubTapUIDKey: tapUID
                    ]
                ]
            ]

            var aggregateID = AudioObjectID.unknown
            status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
            ownedAggregate = aggregateID
            guard status == noErr, aggregateID.isValid else {
                print("[SCE] \u{274c} AudioHardwareCreateAggregateDevice failed: \(status) \u{2014} will retry via the standard setup retry path")
                throw NSError(domain: "gor.CoreAudioUtils", code: -4,
                              userInfo: [NSLocalizedDescriptionKey: "AudioHardwareCreateAggregateDevice failed: \(status)"])
            }

            // 4. Stream format for interpreting the IOProc's raw buffers.
            let asbd = try tapID.readAudioTapStreamBasicDescription()

            _ProcessTapPipeline.resetForNewTap()
            lastTapBuildAt = CACurrentMediaTime()

            // 5. IOProc: feed each buffer through the SAME RMS/peak/PCM-tap
            //    pipeline the SCStream version used (_SCHandler.processBuffer
            //    below) - that math is unchanged, only the source changed.
            //
            //    [weak self] here - not on buildAndStartProcessTap itself,
            //    which already runs ON self and can't observe its own
            //    deallocation mid-call - because THIS closure is the one
            //    that actually outlives this setup call: it's handed to
            //    Core Audio and fires repeatedly, asynchronously, for as
            //    long as the IOProc is running, potentially long after
            //    this synchronous function has returned. Capturing self
            //    weakly here is what actually matters for avoiding a
            //    retain cycle between the engine and its own audio pipeline.
            var ioProcID: AudioDeviceIOProcID?
            status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, processTapQueue) { [weak self] _, inputData, _, _, _ in
                guard let self else { return }
                _ProcessTapPipeline.processBuffer(inputData, asbd: asbd, engine: self)
            }
            ownedIOProc = ioProcID
            guard status == noErr, let ioProcID else {
                print("[SCE] \u{274c} AudioDeviceCreateIOProcIDWithBlock failed: \(status) \u{2014} will retry via the standard setup retry path")
                throw NSError(domain: "gor.CoreAudioUtils", code: -5,
                              userInfo: [NSLocalizedDescriptionKey: "AudioDeviceCreateIOProcIDWithBlock failed: \(status)"])
            }

            status = AudioDeviceStart(aggregateID, ioProcID)
            guard status == noErr else {
                print("[SCE] \u{274c} AudioDeviceStart failed: \(status) \u{2014} System Audio Recording permission may be denied. Will retry via the standard setup retry path.")
                throw NSError(domain: "gor.CoreAudioUtils", code: -6,
                              userInfo: [NSLocalizedDescriptionKey: "AudioDeviceStart failed: \(status) (System Audio Recording permission may be denied)"])
            }

            // A synchronous HAL build cannot be interrupted. If stop arrived
            // while it ran, release its new resources instead of publishing them.
            audioRequestLock.lock()
            let canPublish = audioCaptureRequested && audioRequestGeneration == generation
            if canPublish {
                self.processTapID = tapID
                self.aggregateDeviceID = aggregateID
                self.tapIOProcID = ioProcID
                publishedAudioGeneration = generation
            }
            audioRequestLock.unlock()
            guard canPublish else {
                tapSetupInFlight = false
                return
            }
            ownedTap = .unknown
            ownedAggregate = .unknown
            ownedIOProc = nil
            waitingForAudioReconfig = false
            tapSetupArmedForPlayback = false
            tapSetupInFlight = false
            print("[SCE] Process Tap audio active (aggregate around \(outputUID)).")

            if SCERecorderConfig.enabled {
                DispatchQueue.main.async { [weak self] in
                    // Main-owned observer start is fenced by the accepted request
                    // token, not cross-queue resource IDs or a split running check.
                    guard let self, self.audioRequestIsCurrent(generation) else { return }
                    self.startTapCallbackObservation(generation: generation)
                }
            }

            installDefaultOutputDeviceListener(aggregateOutputDeviceID: outputDeviceID, requestGeneration: generation)

        } catch {
            guard audioRequestIsCurrent(generation) else {
                tapSetupInFlight = false
                return
            }
            // gor.CoreAudioUtils -1 = translatePIDToProcessObjectID found
            // no process object for a pid this attempt JUST proved alive
            // and identity-verified as mpv: mpv registers with Core Audio
            // only when its audio device opens at playback start (field
            // log 260926b: stream blocked pre-playback, AO never opened,
            // all 11 attempts failed identically). Expected pre-playback
            // state, not a failure - log it as waiting, not as a
            // misleading "Invalid process identifier" error. Any other
            // error is genuine and stays loud.
            let nsError = error as NSError
            if nsError.domain == "gor.CoreAudioUtils", nsError.code == -1 {
                if retryCount == 0 {
                    print("[SCE] tap: mpv has no Core Audio object yet (its audio device opens at playback start) \u{2014} polling briefly, then armed for playback start.")
                } else {
                    print("[SCE] tap attempt \(retryCount + 1): still no Core Audio object (waiting on playback start)")
                }
            } else {
                print("[SCE] \u{274c} Process Tap setup error: \(error)")
            }
            // WHY 10 x 2.0s: kAudioObjectUnknown for a confirmed-correct
            // PID means Core Audio hasn't registered mpv as audio-producing
            // yet (needs an actually-open audio stream, not just process
            // existence). 20s gives margin against demux/track/filter
            // startup cost. Safety net only; the event-driven path is the
            // primary trigger.
            if retryCount < 10 {
                // tapSetupInFlight stays true across this wait on purpose
                // (see its doc). The wait is a stored, cancellable
                // DispatchWorkItem so handleAudioReconfigOnProcessTapQueue
                // can interrupt the blind sleep when the real event
                // arrives mid-wait.
                var workItem: DispatchWorkItem!
                workItem = DispatchWorkItem { [weak self] in
                    self?.processTapQueue.async {
                        // DispatchWorkItem.cancel() is cooperative, not
                        // preemptive - it only sets isCancelled; a block
                        // already past the queue's dispatch point still
                        // runs. So if handleAudioReconfigOnProcessTapQueue's
                        // cancel() lands right at this closure's own
                        // deadline boundary, cancel() alone can't be trusted
                        // to have stopped it. The real guard is this
                        // identity check: if pendingRetryWorkItem is no
                        // longer this specific item, handleAudioReconfig-
                        // OnProcessTapQueue already consumed this retry slot
                        // (cancelled it, cleared it, and called
                        // buildAndStartProcessTap itself) - bail entirely,
                        // don't call buildAndStartProcessTap a second,
                        // concurrent time. DispatchWorkItem is a class, so
                        // === is genuine reference identity here, not value
                        // equality.
                        guard self?.audioRequestIsCurrent(generation) == true, self?.pendingRetryWorkItem === workItem else { return }
                        self?.pendingRetryWorkItem = nil
                        self?.tapSetupInFlight = false
                        self?.buildAndStartProcessTap(retryCount: retryCount + 1, generation: generation)
                    }
                }
                pendingRetryWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
            } else {
                // mpv only registers a Core Audio object once its audio
                // device opens at playback start; on a slow-buffering stream
                // that can be a minute after launch (field log 260926), long
                // past this fixed window, so a hard give-up can never succeed
                // there. Stay armed - the next playback-start signal re-runs
                // the whole loop (tapSetupArmedForPlayback).
                print("[SCE] Process Tap setup paused after 10 tries \u{2014} armed for retry at playback start.")
                tapSetupInFlight = false
                tapSetupArmedForPlayback = true
            }
        }
    }

    /// Rebuilds the tap + aggregate device whenever the default output
    /// device changes. WHY: an aggregate built around a stale output device
    /// does not error - it just silently stops delivering audio (flat
    /// subtitle animation, no error printed).
    /// Main queue only; delayed automatic rebuild cannot override a later stop.
    fileprivate func restartAudioCaptureIfCurrent(_ generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let stoppedGeneration = cancelAudioCaptureRequest(ifCurrent: generation) else { return }
        enqueueAudioCaptureTeardown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self,
                  let resumedGeneration = self.resumeAudioCaptureRequest(ifStopped: stoppedGeneration) else { return }
            self.startAudioCapture(retryCount: 0, generation: resumedGeneration)
        }
    }

    @available(macOS 14.2, *)
    private func reviewDefaultOutputDevice(lifetime: UInt64, requestGeneration: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard audioRequestIsCurrent(requestGeneration),
              let observedDevice = try? AudioObjectID.readDefaultSystemOutputDevice(), observedDevice.isValid else { return }
        outputDeviceStateLock.lock()
        guard outputDeviceListenerLifetime == lifetime,
              observedDevice != lastDefaultOutputDeviceID,
              observedDevice != pendingDefaultOutputDeviceID else { outputDeviceStateLock.unlock(); return }
        pendingDefaultOutputDeviceID = observedDevice
        outputDeviceChangeGeneration &+= 1
        let event = outputDeviceChangeGeneration
        outputDeviceStateLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.audioRequestIsCurrent(requestGeneration) else { return }
            let observedCurrentDevice = try? AudioObjectID.readDefaultSystemOutputDevice()
            guard let currentDevice = observedCurrentDevice, currentDevice.isValid else {
                self.outputDeviceStateLock.lock()
                if self.outputDeviceListenerLifetime == lifetime && self.outputDeviceChangeGeneration == event {
                    self.pendingDefaultOutputDeviceID = nil
                }
                self.outputDeviceStateLock.unlock()
                return
            }
            self.outputDeviceStateLock.lock()
            guard self.outputDeviceListenerLifetime == lifetime,
                  self.outputDeviceChangeGeneration == event else { self.outputDeviceStateLock.unlock(); return }
            self.pendingDefaultOutputDeviceID = nil
            guard currentDevice != self.lastDefaultOutputDeviceID else { self.outputDeviceStateLock.unlock(); return }
            self.lastDefaultOutputDeviceID = currentDevice
            self.outputDeviceStateLock.unlock()
            self.restartAudioCaptureIfCurrent(requestGeneration)
        }
    }

    @available(macOS 14.2, *)
    private func installDefaultOutputDeviceListener(aggregateOutputDeviceID: AudioObjectID, requestGeneration: UInt64) {
        // A failed removal keeps its block for retry. Do not stack listeners.
        guard removeDefaultOutputDeviceListener() else { return }
        outputDeviceStateLock.lock()
        outputDeviceListenerLifetime &+= 1
        let lifetime = outputDeviceListenerLifetime
        // Baseline is the device actually used to create the aggregate, not
        // a later default read that could bless a stale build.
        lastDefaultOutputDeviceID = aggregateOutputDeviceID
        pendingDefaultOutputDeviceID = nil
        outputDeviceStateLock.unlock()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.reviewDefaultOutputDevice(lifetime: lifetime, requestGeneration: requestGeneration)
        }
        let registrationStatus = AudioObjectAddPropertyListenerBlock(.system, &address, DispatchQueue.main, block)
        guard registrationStatus == noErr else {
            print("[SCE] Default output listener registration failed: status=\(registrationStatus). Device changes are not monitored.")
            return
        }
        defaultOutputDeviceListenerBlock = block
        // Cover a real change between aggregate creation and listener install.
        DispatchQueue.main.async { [weak self] in
            self?.reviewDefaultOutputDevice(lifetime: lifetime, requestGeneration: requestGeneration)
        }
    }

    @discardableResult
    @available(macOS 14.2, *)
    private func removeDefaultOutputDeviceListener() -> Bool {
        outputDeviceStateLock.lock()
        outputDeviceListenerLifetime &+= 1
        outputDeviceChangeGeneration &+= 1
        pendingDefaultOutputDeviceID = nil
        outputDeviceStateLock.unlock()
        guard let block = defaultOutputDeviceListenerBlock else { return true }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let removalStatus = AudioObjectRemovePropertyListenerBlock(.system, &address, DispatchQueue.main, block)
        guard removalStatus == noErr else {
            // Lifetime was invalidated above; stale callbacks cannot rebuild.
            // Keep the exact block so a later teardown/install can retry removal.
            print("[SCE] Default output listener removal failed: status=\(removalStatus). Registration retained for retry.")
            return false
        }
        defaultOutputDeviceListenerBlock = nil
        return true
    }

    // Observation only: absent callbacks are not proof of a broken device.
    // Callers and timer lifecycle are confined to main; state reads use the
    // serial IOProc queue. A pending reply cannot outlive its observer token.
    private func stopTapCallbackObservation() {
        guard SCERecorderConfig.enabled else { return }
        let expectedToken = tapObservationToken
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stopTapCallbackObservation(expectedToken: expectedToken)
            }
            return
        }
        stopTapCallbackObservation(expectedToken: expectedToken)
    }

    private func stopTapCallbackObservation(expectedToken: UUID?) {
        // A nil token also cancels a start that was queued before this stop.
        // A non-nil token protects a newer observer from an older stop.
        if let expectedToken, tapObservationToken != expectedToken { return }
        tapObservationToken = nil
        tapObservationPending = false
        tapObservationTimer?.cancel()
        tapObservationTimer = nil
    }

    @available(macOS 14.2, *)
    private func startTapCallbackObservation(generation: UInt64) {
        guard SCERecorderConfig.enabled else { return }
        dispatchPrecondition(condition: .onQueue(.main))
        guard audioRequestIsCurrent(generation), audioRunning else { return }
        stopTapCallbackObservation()
        let token = UUID()
        tapObservationToken = token
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .milliseconds(250))
        // F3: main-queue tick lateness (expected interval 2.0s) and a 30s
        // measurement report. Main-only state captured by the handler.
        var f3Ticks = 0
        var f3LastTickAt = CACurrentMediaTime()
        var f3MaxTickLateness = 0.0
        timer.setEventHandler { [weak self] in
            guard let self, self.tapObservationToken == token, !self.tapObservationPending else { return }
            let tickNow = CACurrentMediaTime()
            f3MaxTickLateness = max(f3MaxTickLateness, tickNow - f3LastTickAt - 2.0)
            f3LastTickAt = tickNow
            f3Ticks += 1
            let f3Report = f3Ticks % 15 == 0
            let f3Lateness = f3MaxTickLateness
            if f3Report { f3MaxTickLateness = 0 }
            self.tapObservationPending = true
            self.processTapQueue.async { [weak self] in
                guard let self, self.tapObservationToken == token else { return }
                let status = _ProcessTapPipeline.callbackObservation()
                let f3Window: _ProcessTapPipeline.F3Window? = f3Report ? _ProcessTapPipeline.takeF3Window() : nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.tapObservationToken == token else { return }
                    self.tapObservationPending = false
                    if let w = f3Window {
                        // Window length was fixed on processTapQueue at take time, so seconds
                        // and counts cover the same interval even if earlier windows were
                        // dropped by the token guard. nil = start unknown ("first").
                        let windowSeconds = w.windowSeconds
                        let wall = ISO8601DateFormatter().string(from: Date())
                        var buckets = [UInt64](repeating: 0, count: 7)
                        var maxGap = 0.0
                        var maxDuration = 0.0
                        for sample in w.samples {
                            if sample.gap >= 0 {
                                maxGap = max(maxGap, sample.gap)
                                buckets[_ProcessTapPipeline.gapBucket(sample.gap)] &+= 1
                            }
                            maxDuration = max(maxDuration, sample.duration)
                        }
                        print("[SCE][F3] window utc=\(wall) window_seconds=\(windowSeconds.map { String(format: "%.2f", $0) } ?? "first") callbacks=\(w.callbacks) sampled=\(w.samples.count) dropped=\(w.dropped) max_observed_gap_ms=\(Int(maxGap * 1000)) max_observed_callback_body_ms=\(String(format: "%.3f", maxDuration * 1000)) gap_hist_ms[<5,<10,<20,<40,<80,<160,>=160]=\(buckets) main_tick_lateness_max_ms=\(Int(f3Lateness * 1000))")
                    }
                    let zeroNow = CACurrentMediaTime()
                    if status.zeroPending, zeroNow - self.lastTapZeroReportAt >= 30.0 {
                        self.lastTapZeroReportAt = zeroNow
                        print("[SCE] tap zero-content diagnostic: callbacks=\(status.zeroCallbacks) zero_seconds=\(status.zeroSeconds) max_callback_gap=\(status.zeroGap) recovery=withheld-no-independent-liveness-proof")
                    }
                    let now = CACurrentMediaTime()
                    guard now - status.lastActivity >= 2.0,
                          now - self.lastNoCallbackReportAt >= 30.0 else { return }
                    self.lastNoCallbackReportAt = now
                    print("[SCE] tap callback absence observation: callbacks=\(status.count) age_seconds=\(now - status.lastActivity) recovery=withheld-pause-mute-device-state-unverified")
                }
            }
        }
        tapObservationTimer = timer
        timer.resume()
    }

    // MARK: - Audio processing

    /// Called from the audio callback thread. Peak-hold envelope: instant
    /// attack, fast exponential release (tau~0.08s). WHY 0.08 not 0.40:
    /// SubtitleView needs syllable-level dynamics; 0.40 mirrors Web Audio's
    /// spectrum-analyser smoothing and over-smooths reactive font weight.
    fileprivate func processAudio(_ normalized: Float) {
        let clamped = max(0, min(1, normalized))
        let now = CACurrentMediaTime()
        let dt  = lastAudioTime > 0 ? Float(min(now - lastAudioTime, 0.1)) : (1.0 / 60.0)
        lastAudioTime = now

        if clamped >= peakHoldLevel {
            peakHoldLevel = clamped
        } else {
            // tau=0.08s: fast enough to track syllables, slow enough to avoid flicker.
            // SubtitleView adds its own 0.04s smoother for final visual polish.
            let releaseTau: Float = 0.08
            let alpha = 1.0 - exp(-dt / releaseTau)
            peakHoldLevel += alpha * (clamped - peakHoldLevel)
        }
        currentAudioLevel = peakHoldLevel
    }
}

// MARK: - SCStream output handler

@available(macOS 13.0, *)
/// IOProc audio handler: RMS/peak/dBFS math and resample() logic unchanged,
/// input now AudioBufferList instead of CMSampleBuffer. Reports bounded
/// zero-content/callback-gap diagnostics only. It does NOT detect a dead tap and
/// does NOT rebuild capture: sample content alone cannot prove a broken tap.
@available(macOS 14.2, *)
private enum _ProcessTapPipeline {

    // State is used only on processTapQueue.
    private final class State {
        var resamplePhase: Double = 0.0
        var resampleTailSample: Float = 0.0
        var hasResampleTail = false
        var hasSeenNonZero = false
        var zeroStartedAt: Double?
        var lastZeroReportAt: Double = -.infinity
        var lastCallbackAt: Double?
        var largestCallbackGap: Double = 0
        var callbackCount: UInt64 = 0
    }
    private static let state = State()

    static func resetForNewTap() {
        state.resamplePhase = 0
        state.resampleTailSample = 0
        state.hasResampleTail = false
        state.hasSeenNonZero = false
        state.zeroStartedAt = nil
        state.lastCallbackAt = nil
        state.largestCallbackGap = 0
        state.callbackCount = 0
        // The report limit survives rebuilds; no recovery storm logging.
        if SCERecorderConfig.enabled {
            let recorder = F3RecorderState()
            recorder.tapStartedAt = CACurrentMediaTime()
            recorder.winStartAt = recorder.tapStartedAt
            recorderState = recorder
        }
    }

    /// Zero-run snapshot for the dead-tap rebuild evaluation. Same
    /// processTapQueue read pattern as callbackObservation().
    static func zeroRunState() -> (hasSeenNonZero: Bool, zeroStartedAt: Double?, callbackCount: UInt64) {
        (state.hasSeenNonZero, state.zeroStartedAt, state.callbackCount)
    }

    private final class F3RecorderState {
        var tapStartedAt: Double = 0
        var lastCallbackAt: Double?
        var largestCallbackGap: Double = 0
        var callbackCount: UInt64 = 0
        // Preallocated once during resetForNewTap, before IOProc starts.
        let ringCapacity = 2048
        let ring: UnsafeMutablePointer<F3Sample> = {
            let p = UnsafeMutablePointer<F3Sample>.allocate(capacity: 2048)
            p.initialize(repeating: F3Sample(gap: -1, duration: 0), count: 2048)
            return p
        }()
        var ringRead = 0
        var ringWrite = 0
        var ringUsed = 0
        var winCallbacks: UInt64 = 0
        var winDropped: UInt64 = 0
        var winStartAt: Double?
        var zeroReportPending = false
        var zeroReportCallbacks: UInt64 = 0
        var zeroReportSeconds: Double = 0
        var zeroReportGap: Double = 0
        deinit { ring.deinitialize(count: ringCapacity); ring.deallocate() }
    }
    // Allocated ONLY by resetForNewTap before IOProc starts, never by callback.
    private static var recorderState: F3RecorderState?
    struct F3Sample {
        let gap: Double // negative means no preceding callback in this tap
        let duration: Double
    }
    struct F3Window {
        let callbacks: UInt64
        let dropped: UInt64
        let samples: [F3Sample]
        let windowSeconds: Double?
    }
    // Used only by the main-hop aggregator, never by the callback.
    static func gapBucket(_ gap: Double) -> Int {
        let ms = gap * 1000
        if ms < 5 { return 0 }
        if ms < 10 { return 1 }
        if ms < 20 { return 2 }
        if ms < 40 { return 3 }
        if ms < 80 { return 4 }
        if ms < 160 { return 5 }
        return 6
    }
    // Snapshot on processTapQueue. Allocation is outside the IOProc callback.
    // Aggregation and formatting happen after the main hop.
    static func takeF3Window() -> F3Window {
        guard let state = recorderState else { return F3Window(callbacks: 0, dropped: 0, samples: [], windowSeconds: nil) }
        let now = CACurrentMediaTime()
        var samples: [F3Sample] = []
        samples.reserveCapacity(state.ringUsed)
        while state.ringUsed > 0 {
            samples.append(state.ring[state.ringRead])
            state.ringRead = (state.ringRead + 1) % state.ringCapacity
            state.ringUsed -= 1
        }
        let w = F3Window(callbacks: state.winCallbacks, dropped: state.winDropped,
                         samples: samples, windowSeconds: state.winStartAt.map { max(0, now - $0) })
        state.winStartAt = now
        state.winCallbacks = 0
        state.winDropped = 0
        return w
    }
    static func callbackObservation() -> (count: UInt64, lastActivity: Double,
                                         zeroPending: Bool, zeroCallbacks: UInt64,
                                         zeroSeconds: Double, zeroGap: Double) {
        guard let state = recorderState else { return (0, 0, false, 0, 0, 0) }
        let observation = (state.callbackCount, state.lastCallbackAt ?? state.tapStartedAt,
                           state.zeroReportPending, state.zeroReportCallbacks,
                           state.zeroReportSeconds, state.zeroReportGap)
        state.zeroReportPending = false
        return observation
    }

    /// Linear-interpolation resample from `inputRate` to
    /// ScreenCaptureEngine.pcmTapOutputSampleRate (16000 Hz). Unchanged from
    /// the SCStream version's resample(): not a windowed-sinc resampler,
    /// deliberately simple, sufficient for speech-band content.
    private static func resample(_ input: UnsafeBufferPointer<Float>, inputRate: Double) -> [Float] {
        guard inputRate > 0, input.count > 0 else { return [] }
        let ratio = ScreenCaptureEngine.pcmTapOutputSampleRate / inputRate
        guard ratio != 1.0 else { return Array(input) }

        var out: [Float] = []
        out.reserveCapacity(Int(Double(input.count) * ratio) + 2)

        let extended: [Float]
        if state.hasResampleTail {
            extended = [state.resampleTailSample] + Array(input)
        } else {
            extended = Array(input)
        }

        var srcPos = state.resamplePhase
        let step = inputRate / ScreenCaptureEngine.pcmTapOutputSampleRate
        while true {
            let i0 = Int(srcPos)
            let i1 = i0 + 1
            guard i1 < extended.count else { break }
            let frac = Float(srcPos - Double(i0))
            let sample = extended[i0] + (extended[i1] - extended[i0]) * frac
            out.append(sample)
            srcPos += step
        }

        // The next callback prepends this chunk's last sample. Carry the
        // next read position relative to that saved sample, not its fraction.
        state.resamplePhase = srcPos - Double(extended.count - 1)
        if let last = input.last {
            state.resampleTailSample = last
            state.hasResampleTail = true
        }

        return out
    }

    /// Called from the aggregate device's AudioDeviceIOProcIDWithBlock callback.
    ///
    /// Does NOT assume interleaved-stereo-in-one-buffer just because the tap
    /// was created via stereoMixdownOfProcesses - that initializer name
    /// describes the mixdown, not the wire format. Per Apple's own
    /// CAStreamBasicDescription reference (NumberInterleavedChannels vs.
    /// NumberChannelStreams), the only reliable source of truth is
    /// kAudioFormatFlagIsNonInterleaved on the actual returned ASBD, checked
    /// below. If non-interleaved, every channel buffer is combined for
    /// RMS/peak so a signal on a non-first channel can't be silently missed.
    static func processBuffer(_ bufferList: UnsafePointer<AudioBufferList>, asbd: AudioStreamBasicDescription, engine: ScreenCaptureEngine) {
        // Added instrumentation only: fixed-size numeric writes, no allocation,
        // dispatch, lock, HAL query or logging in this prologue/defer.
        let recorder = SCERecorderConfig.enabled ? recorderState : nil
        let arrivedAt = recorder != nil ? CACurrentMediaTime() : 0
        let observedGap = recorder?.lastCallbackAt.map { max(0, arrivedAt - $0) } ?? -1
        defer {
            if let recorder {
                let duration = max(0, CACurrentMediaTime() - arrivedAt)
                if recorder.ringUsed == recorder.ringCapacity {
                    recorder.winDropped &+= 1
                } else {
                    recorder.ring[recorder.ringWrite] = F3Sample(gap: observedGap, duration: duration)
                    recorder.ringWrite = (recorder.ringWrite + 1) % recorder.ringCapacity
                    recorder.ringUsed += 1
                }
            }
        }
        if let recorder {
            if observedGap >= 0 { recorder.largestCallbackGap = max(recorder.largestCallbackGap, observedGap) }
            recorder.winCallbacks &+= 1
            recorder.lastCallbackAt = arrivedAt
            recorder.callbackCount &+= 1
        }
        guard asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }
        let isNonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0

        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard !abl.isEmpty else { return }

        // Collect sample pointers from every AudioBuffer in the list (one
        // per channel if non-interleaved, or the single interleaved buffer
        // if not) rather than assuming abl.first is the whole signal.
        var allSamples: [UnsafeBufferPointer<Float>] = []
        allSamples.reserveCapacity(abl.count)
        for buffer in abl {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            allSamples.append(data.withMemoryRebound(to: Float.self, capacity: count) {
                UnsafeBufferPointer(start: $0, count: count)
            })
            if !isNonInterleaved { break } // one buffer holds everything
        }
        guard let samples = allSamples.first else { return }

        // RMS + peak blend -> dBFS -> normalise to [0, 1] (25% RMS / 75%
        // peak, -52dBFS floor / 44dB range). Non-interleaved multi-channel:
        // max peak across channels (a signal on either should register),
        // average RMS (keeps the blend's balance vs summing energies).
        var rms: Float = 0
        vDSP_rmsqv(samples.baseAddress!, 1, &rms, vDSP_Length(samples.count))
        if isNonInterleaved, allSamples.count > 1 {
            var rmsSum = rms
            for extra in allSamples.dropFirst() {
                var extraRMS: Float = 0
                vDSP_rmsqv(extra.baseAddress!, 1, &extraRMS, vDSP_Length(extra.count))
                rmsSum += extraRMS
            }
            rms = rmsSum / Float(allSamples.count)
        }
        var peak: Float = 0
        vDSP_maxmgv(samples.baseAddress!, 1, &peak, vDSP_Length(samples.count))
        if isNonInterleaved, allSamples.count > 1 {
            for extra in allSamples.dropFirst() {
                var extraPeak: Float = 0
                vDSP_maxmgv(extra.baseAddress!, 1, &extraPeak, vDSP_Length(extra.count))
                peak = max(peak, extraPeak)
            }
        }
        let blended    = 0.25 * rms + 0.75 * peak
        let dBFS       = 20 * log10f(max(blended, 1e-9))
        let normalized = max(0, min(1, (dBFS + 52) / 44))

        if let recorder {
            let now = CACurrentMediaTime()
            if peak > 0 {
                state.hasSeenNonZero = true
                state.zeroStartedAt = nil
            } else if peak == 0, state.hasSeenNonZero {
                if state.zeroStartedAt == nil { state.zeroStartedAt = now }
                if let started = state.zeroStartedAt,
                   now - started >= 2.0, now - state.lastZeroReportAt >= 30.0 {
                    state.lastZeroReportAt = now
                    recorder.zeroReportPending = true
                    recorder.zeroReportCallbacks = recorder.callbackCount
                    recorder.zeroReportSeconds = now - started
                    recorder.zeroReportGap = recorder.largestCallbackGap
                }
            }
        } else {
            // Sample content alone cannot prove a broken tap. Keep capture alive
            // through silence/underrun and report bounded callback evidence only.
            let now = CACurrentMediaTime()
            if let previous = state.lastCallbackAt {
                state.largestCallbackGap = max(state.largestCallbackGap, now - previous)
            }
            state.lastCallbackAt = now
            state.callbackCount &+= 1
            if peak > 0 {
                state.hasSeenNonZero = true
                state.zeroStartedAt = nil
            } else if peak == 0, state.hasSeenNonZero {
                if state.zeroStartedAt == nil { state.zeroStartedAt = now }
                if let started = state.zeroStartedAt,
                   now - started >= 2.0, now - state.lastZeroReportAt >= 30.0 {
                    state.lastZeroReportAt = now
                    let callbacks = state.callbackCount
                    let seconds = now - started
                    let gap = state.largestCallbackGap
                    // No HAL queries, formatting or log I/O inside this callback.
                    DispatchQueue.main.async {
                        print("[SCE] tap zero-content diagnostic: callbacks=\(callbacks) zero_seconds=\(seconds) max_callback_gap=\(gap) recovery=withheld-no-independent-liveness-proof")
                    }
                }
            }

        }

        engine.processAudio(normalized)

        // Raw PCM tap - strictly additive, mirrors the SCStream version.
        //
        // IMPORTANT: resample() is written for mono input - it treats each
        // array index as one sequential time-step. The SCStream version
        // guaranteed mono at the source via config.channelCount = 1; the
        // Process Tap has no equivalent knob, and stereoMixdownOfProcesses
        // most likely yields 2-channel output. Feeding raw interleaved (or
        // multi-buffer non-interleaved) samples straight into resample()
        // would silently misread alternating L/R pairs as sequential mono
        // samples, corrupting the resample and everything downstream in
        // LiveCaptionController/whisper.cpp. Mix down to mono here first -
        // this is a NEW step versus the SCStream version, not a port of
        // existing logic, because the guarantee it depended on no longer
        // holds automatically.
        if engine.pcmTapEnabled, let handler = engine.pcmHandler {
            let channelCount = Int(asbd.mChannelsPerFrame)
            let monoSamples: [Float]
            if channelCount <= 1 {
                monoSamples = Array(samples)
            } else if isNonInterleaved {
                // One buffer per channel - average corresponding frames across buffers.
                let frameCount = allSamples.map(\.count).min() ?? 0
                monoSamples = (0..<frameCount).map { i in
                    allSamples.reduce(Float(0)) { $0 + $1[i] } / Float(allSamples.count)
                }
            } else {
                // Single interleaved buffer - average each frame's channelCount samples.
                let frameCount = samples.count / channelCount
                monoSamples = (0..<frameCount).map { frame in
                    var sum: Float = 0
                    for ch in 0..<channelCount { sum += samples[frame * channelCount + ch] }
                    return sum / Float(channelCount)
                }
            }
            let resampled = monoSamples.withUnsafeBufferPointer {
                resample($0, inputRate: Double(asbd.mSampleRate))
            }
            resampled.withUnsafeBufferPointer { handler($0) }
        }
    }
}

// ================================================================
// Core Audio property-access utilities
//
// Convenience wrappers not in the CoreAudio framework, from Apple engineer
// @insidegui's reference project (github.com/insidegui/AudioCap,
// ProcessTap/CoreAudioUtils.swift, BSD-2-Clause), trimmed to what this file
// actually calls.
// ================================================================

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown

    var isUnknown: Bool { self == .unknown }
    var isValid: Bool { !isUnknown }

    @available(macOS 14.2, *)
    static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try AudioObjectID.system.translatePIDToProcessObjectID(pid: pid)
    }

    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.readDefaultSystemOutputDevice()
    }

    @available(macOS 14.2, *)
    func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try requireSystemObject()
        let processObject = try read(
            kAudioHardwarePropertyTranslatePIDToProcessObject,
            defaultValue: AudioObjectID.unknown,
            qualifier: pid
        )
        guard processObject.isValid else {
            throw NSError(domain: "gor.CoreAudioUtils", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid process identifier: \(pid)"])
        }
        return processObject
    }

    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func readDeviceUID() throws -> String { try readString(kAudioDevicePropertyDeviceUID) }

    @available(macOS 14.2, *)
    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    private func requireSystemObject() throws {
        if self != .system {
            throw NSError(domain: "gor.CoreAudioUtils", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Only supported for the system object."])
        }
    }
}

extension AudioObjectID {
    func read<T, Q>(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                     defaultValue: T,
                     qualifier: Q) throws -> T {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: defaultValue, qualifier: qualifier)
    }

    func read<T>(_ selector: AudioObjectPropertySelector,
                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                  defaultValue: T) throws -> T {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: defaultValue)
    }

    func read<T, Q>(_ address: AudioObjectPropertyAddress, defaultValue: T, qualifier: Q) throws -> T {
        var inQualifier = qualifier
        let qualifierSize = UInt32(MemoryLayout<Q>.size(ofValue: qualifier))
        return try withUnsafeMutablePointer(to: &inQualifier) { qualifierPtr in
            try read(address, defaultValue: defaultValue, inQualifierSize: qualifierSize, inQualifierData: qualifierPtr)
        }
    }

    func read<T>(_ address: AudioObjectPropertyAddress, defaultValue: T) throws -> T {
        try read(address, defaultValue: defaultValue, inQualifierSize: 0, inQualifierData: nil)
    }

    func readString(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> String {
        try read(AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), defaultValue: "" as CFString) as String
    }

    private func read<T>(_ inAddress: AudioObjectPropertyAddress, defaultValue: T, inQualifierSize: UInt32 = 0, inQualifierData: UnsafeRawPointer? = nil) throws -> T {
        var address = inAddress
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, inQualifierSize, inQualifierData, &dataSize)
        guard err == noErr else {
            throw NSError(domain: "gor.CoreAudioUtils", code: Int(err),
                          userInfo: [NSLocalizedDescriptionKey: "Error reading data size for \(inAddress): \(err)"])
        }
        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, inQualifierSize, inQualifierData, &dataSize, ptr)
        }
        guard err == noErr else {
            throw NSError(domain: "gor.CoreAudioUtils", code: Int(err),
                          userInfo: [NSLocalizedDescriptionKey: "Error reading data for \(inAddress): \(err)"])
        }
        return value
    }
}

// Subtitle Vision has its own request lifetime; cancellation never frees a still-running slot.
private final class SubtitleFaceWatchdog {
    private let lock=NSLock()
    private var active=true, expired=false
    init(_ request: VNRequest) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now()+1) { [self] in
            lock.lock(); let cancel=active; if cancel { expired=true; active=false }; lock.unlock()
            if cancel { request.cancel(); Diag.mediaRecord("SUBTITLE-FACE vision watchdog cancel_once=true recovery=await-perform-return") }
        }
    }
    func finish() -> Bool { lock.lock(); defer {lock.unlock()}; active=false; return !expired }
    static func selectCPU(_ request: VNRequest) -> Bool {
        if #available(macOS 14.0, *) {
            do {
                let stages=try request.supportedComputeStageDevices
                guard !stages.isEmpty else {return false}
                for (stage,devices) in stages {
                    guard let cpu=devices.first(where: {if case .cpu = $0 {return true};return false}) else {return false}
                    request.setComputeDevice(cpu,for:stage)
                }
            } catch {return false}
        } else {request.usesCPUOnly=true}
        return true
    }
}
