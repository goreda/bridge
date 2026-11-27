// Picture/CropDetector.swift
// Accepted content crop analysis: one monotonic phase drives source UV and window frame.
// Uses: AppKit, Foundation, App, Engine, Platform, Session, Stereo
// Engine: none
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Viewport station: accepted content crop analysis (S4a pure move)
// Moved byte-identical from PPController.swift (CropDetector class).

// One monotonic phase drives source UV and window frame together. No independent
// window spring is allowed to chase the crop endpoint.
struct CropMotionClock {
    let started:Double
    let duration:Double
    func phase(_ now:Double)->Double {
        guard now.isFinite,started.isFinite,duration.isFinite,duration>0 else{return 1}
        let t=max(0,min(1,(now-started)/duration))
        return t*t*(3-2*t)
    }
    static func mix(_ a:CGRect,_ b:CGRect,_ phase:Double)->CGRect {
        let t=CGFloat(max(0,min(1,phase)))
        if t==1{return b};if t==0{return a}
        return CGRect(x:a.minX+(b.minX-a.minX)*t,y:a.minY+(b.minY-a.minY)*t,
                      width:a.width+(b.width-a.width)*t,height:a.height+(b.height-a.height)*t)
    }
}

final class CropDetector {
    private let sourceScanner = SourcePixelCropScanner()
    /// Receives the admitted sample positions of this detector's scans (the owning player's CropScanGuard).
    var sampleRecorder: ((Double) -> Void)? {
        get { sourceScanner.sampleRecorder }
        set { sourceScanner.sampleRecorder = newValue }
    }
    var stereoSBS = false
    var viewportOnly = false
    var sourcePixelWidth:Int { sourceScanner.decodedWidth }
    var sourcePixelHeight:Int { sourceScanner.decodedHeight }
    var perEyeAspect:Double? {sourceScanner.perEyeAspect}
    var stereoTopBottom = false
    private let mpvPath: String
    /// Typed probe source, injected by the composition root; the Picture
    /// layer never names the backend command owner that mints these.
    private let probeFactory: CropProbeFactory
    /// Main player IPC socket. Streams are sampled from the already-playing
    /// mpv through this: signed URLs (transfer.it) expire right after the main
    /// player opens them, so probe mpvs re-opening the URL got a 403 and
    /// manufactured black-frame crops (same wall photon hit). Set by
    /// PPController at init.
    var mainIPCPath: String?
    private let mainPlaybackCondition = NSCondition()
    private var mainPlaybackReady = false
    private var mainPlaybackGeneration = 0
    private var mainPlaybackActive = false
    // Playback lifetime differs from a crop detection lifetime. Both guards apply.
    @discardableResult
    func resetMainPlayback(active: Bool) -> Int {
        mainPlaybackCondition.lock()
        mainPlaybackGeneration += 1
        mainPlaybackActive = active
        mainPlaybackReady = false
        let generation = mainPlaybackGeneration
        mainPlaybackCondition.broadcast()
        mainPlaybackCondition.unlock()
        return generation
    }
    func currentMainPlayback() -> Int? {
        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }
        return mainPlaybackActive ? mainPlaybackGeneration : nil
    }
    func isMainPlaybackCurrent(_ generation: Int) -> Bool {
        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }
        return mainPlaybackActive && mainPlaybackGeneration == generation
    }
    func isMainPlaybackReady() -> Bool {
        mainPlaybackCondition.lock(); defer { mainPlaybackCondition.unlock() }
        return mainPlaybackActive && mainPlaybackReady
    }
    func setMainPlaybackReady(_ ready: Bool) {
        mainPlaybackCondition.lock()
        let changed = mainPlaybackReady != ready
        mainPlaybackReady = ready && mainPlaybackActive
        mainPlaybackCondition.broadcast()
        mainPlaybackCondition.unlock()
        if changed, Diag.mediaTelemetryEnabled {
            Diag.mediaRecord("[media-ready] ready=\(ready)")
        }
    }
    /// Runs only on the capture worker. Wait for a decoded-frame restart,
    /// not dimensions. Cancellation/file generation is checked every bounded wait.
    private func waitForMainPlayback(filePath: String, generation: Int, playback: Int?) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        mainPlaybackCondition.lock()
        defer { mainPlaybackCondition.unlock() }
        guard let playback, mainPlaybackActive, mainPlaybackGeneration == playback else { return false }
        while !mainPlaybackReady {
            guard mainPlaybackActive, mainPlaybackGeneration == playback, isCurrent(filePath, generation), ProcessInfo.processInfo.systemUptime < deadline else {
                return false
            }
            _ = mainPlaybackCondition.wait(until: Date(timeIntervalSinceNow: 0.25))
        }
        return mainPlaybackActive && mainPlaybackGeneration == playback && isCurrent(filePath, generation)
    }
    private(set) var isPending        = false; var hasScanProgress: Bool { sourceScanner.hasProgress() }
    private var lastDetectedFile      = ""
    /// Generation guard for the one-shot dark-scene retry: cancel() and every
    /// committed detection invalidate any pending retry.
    private var retryGeneration       = 0
    /// Main-thread owner token fences scheduled retries against cancel/manual/file lifetimes.
    var retryToken:Int {retryGeneration}
    // One generation per detection, invalidated on cancel/file switch. A slow
    // screenshot from an old file must never vote or finish a newer run.
    // Lock order: never call mainPlayback* while holding detectionLock.
    // Readiness waits may acquire detectionLock under mainPlaybackCondition.
    private let detectionLock = NSLock()
    private var detectionGeneration = 0
    private var detectionFile = ""
    private func isCurrent(_ filePath: String, _ generation: Int) -> Bool {
        detectionLock.lock(); defer { detectionLock.unlock() }
        return detectionGeneration == generation && detectionFile == filePath
    }
    private func currentGeneration(for filePath: String) -> Int? {
        detectionLock.lock(); defer { detectionLock.unlock() }
        return detectionFile == filePath ? detectionGeneration : nil
    }
    private var activeProcesses: [Process]    = []
    private var activeSocketPaths: [String]   = []
    /// Owns activeProcesses/activeSocketPaths. Callers span probe/round
    /// worker queues and main; the old main.sync plaster was a deadlock
    /// hazard, not synchronization.
    private let activeLock = NSLock()
    private let analysisQueue = DispatchQueue(
        label: "gor.cropdetect.concurrent",
        qos: .utility,
        attributes: .concurrent
    )
    private static let maxParallelLocal  = 4
    private static let maxParallelStream = 2
    private static let staleFrameSettleDelay: TimeInterval = 0.3
    /// Wall-clock spacing between live stream captures: spreads samples across
    /// scenes without seeking the user's playback.
    private static let streamLiveSampleInterval: TimeInterval = 1.0
    /// Live frames are already decoded by the player; a capture should land
    /// well inside this.
    private static let liveScreenshotWait: TimeInterval = 1.0
    /// Manual redetect: denser spacing than background sampling — the user is
    /// watching this moment now.
    private static let manualWindowSampleInterval: TimeInterval = 0.5
    private static let streamRoundCoolDown: TimeInterval = 4.0
    /// Below this center luminance a frame carries no evidence in either
    /// direction: bars and picture are both black, so it can vote neither
    /// "crop" nor "no crop". Dark openings and credit sequences must not
    /// fill the quorum; the detector keeps waiting for bright frames.
    private static let darkFrameCenterLumThreshold: Double = 15.0
    /// WT windows accumulate bright votes across healthy playback bursts.
    /// Dark/stalled streams cannot consume the bright-sample ceiling, so the
    /// separate attempt and elapsed-time budget limits their capture cost.
    private static let wtBrightSampleCeiling = 32
    private static let wtMinValidSamples = 4
    // Screenshots execute inside the playback mpv. Keep the producer, not just
    // the Swift analysis, at a low duty cycle even when redetect is tapped.
    private static let wtSampleInterval: TimeInterval = 4.0
    private static let wtManualSampleInterval: TimeInterval = 3.0
    private static let wtMaxAttempts = 24
    private static let wtMaxElapsed: TimeInterval = 120.0
    private static let analysisMaxWidth = 960
    // Auto-only: black-dominated frames cannot establish picture boundaries.
    // This is deliberately above ordinary letter/pillarbox area, not a claim
    // that all film formats have bars smaller than a fixed quarter-frame.
    private static let autoBlackDominanceFraction = 0.55
    private static let autoNearBlackLuminance = 12.0
    private let wtQueue = DispatchQueue(label: "gor.cropdetect.wt", qos: .utility)
    private func sleepWhileCurrent(_ seconds: TimeInterval, filePath: String, generation: Int) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard isCurrent(filePath, generation) else { return false }
            Thread.sleep(forTimeInterval: min(0.1, deadline - ProcessInfo.processInfo.systemUptime))
        }
        return isCurrent(filePath, generation)
    }
    var onResult: ((CGRect?, Bool, Double) -> Void)?
    /// Progress for the menu-bar item (and, on manual runs, the on-screen
    /// text). nil clears. Always delivered on the main queue.
    var onStatus: ((String?) -> Void)?
    private func reportStatus(_ status: String?) {
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }
    init(mpvPath: String, probeFactory: @escaping CropProbeFactory) { self.mpvPath = mpvPath; self.probeFactory = probeFactory }
    /// The wt server's playback endpoint, not its control POSTs or an
    /// arbitrary localhost web stream. Match the URL components so a port
    /// lookalike cannot accidentally enter the magnet-specific path.
    static func isWTPlayback(_ path: String) -> Bool {
        PlayerTorrentEndpoint.playbackToken(path) != nil
    }
    // MARK: - Crop analysis
    // ── Polling helpers ──────────────────
    private func waitForFileLoaded(client: CropProbeTransport, maxWait: TimeInterval) -> Bool {
        let pollInterval: TimeInterval = 0.1
        let startedAt = Date().timeIntervalSince1970

        while Date().timeIntervalSince1970 - startedAt < maxWait {
            if let duration = client.fileDuration(timeout: 0.15), duration > 0 {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }

    private func waitForSeekCompletion(client: CropProbeTransport, maxWait: TimeInterval) {
        let pollInterval: TimeInterval = 0.1
        var elapsed: TimeInterval = 0

        while elapsed < maxWait {
            if let seeking = client.isSeeking(), !seeking { return }
            Thread.sleep(forTimeInterval: pollInterval)
            elapsed += pollInterval
        }
    }

    private func waitForScreenshotFile(at screenshotPath: String, maxWait: TimeInterval) {
        let pollInterval: TimeInterval = 0.02
        var elapsed: TimeInterval = 0

        while elapsed < maxWait {
            if FileManager.default.fileExists(atPath: screenshotPath) { return }
            Thread.sleep(forTimeInterval: pollInterval)
            elapsed += pollInterval
        }
    }

    // ── Public API ──────────────────────────────────────────────────────────

    private var automaticSamplePlanPath=""
    private var automaticWidenLevel=0
    /// Automatic scans start with a narrow playhead-anchored window and widen it on each indecisive result
    /// until the window covers the downloaded cache (199bp option A); the sample count never grows with
    /// the window. Manual scans neither consume nor change this automatic search cursor.
    private func nextAutomaticWidenLevel(path:String,manual:Bool)->Int {
        guard !manual,Self.isWTPlayback(path) else{return 0}
        if automaticSamplePlanPath != path {automaticSamplePlanPath=path;automaticWidenLevel=0}
        return automaticWidenLevel
    }

    func detect(filePath: String, videoW: Double, videoH: Double, fallbackDuration: Double, manualPriority: Bool = false, caller: String = #function) {
        guard !isPending, !filePath.isEmpty, filePath != lastDetectedFile else { return }
        let widenLevel=nextAutomaticWidenLevel(path:filePath,manual:manualPriority)
        retryGeneration += 1
        let token=retryGeneration
        isPending = true; if manualPriority { sourceScanner.dropCarry() }   // a clicked Detect measures afresh around the frame on screen
        reportStatus(Self.isWTPlayback(filePath) ? "crop: scanning the downloaded part of the stream" : "crop: scanning 40 original decoded samples")
        sourceScanner.scan(path:filePath,duration:fallbackDuration,stereo:stereoSBS,topBottom:stereoTopBottom,viewportOnly:viewportOnly,caller:(manualPriority ? "manual:" : "auto:") + caller,fresh:manualPriority,positions:{ WTCropSamples.positions(path:filePath,mainIPCPath:self.mainIPCPath,manual:manualPriority,widenLevel:widenLevel) },interim:{ [weak self] rect,conf in guard let self,self.retryGeneration==token else{return};self.onResult?(rect,true,conf) }) { [weak self] rect,decisive,confidence in
            guard let self, self.retryGeneration==token else { return }
            self.isPending = false
            if decisive { self.lastDetectedFile = filePath }
            if !manualPriority, CropDetector.isWTPlayback(filePath) { self.automaticWidenLevel = decisive ? 0 : self.automaticWidenLevel + 1 }
            self.reportStatus(nil)
            self.onResult?(rect,decisive,confidence)
        }
    }

    private func terminateAllActive() {
        activeLock.lock()
        let procs = activeProcesses
        let paths = activeSocketPaths
        activeProcesses   = []
        activeSocketPaths = []
        activeLock.unlock()
        for proc in procs where proc.isRunning {
            MPVLifeline.close(for: proc)
            if proc.isRunning {
                let deadline = DispatchTime.now() + 2.0
                let sem = DispatchSemaphore(value: 0)
                let waiter = DispatchQueue(label: "terminateAllActive.wait")
                waiter.async {
                    let diagnosticOldThreadName = Thread.current.name
                    Thread.current.name = "crop.wait"
                    defer { Thread.current.name = diagnosticOldThreadName }
                    proc.waitUntilExit()
                    sem.signal()
                }
                if sem.wait(timeout: deadline) == .timedOut, proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                    proc.waitUntilExit()
                }
            }
        }
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func invalidateMeasurementContext() {
        cancel()
        sourceScanner.invalidateMeasurementContext()
        lastDetectedFile=""
    }
    func cancel() {
        retryGeneration += 1 // fence interim/final delivery before cancellation can call back
        sourceScanner.cancel()
        detectionLock.lock()
        detectionGeneration += 1
        detectionFile = ""
        detectionLock.unlock()
        terminateAllActive()
        isPending = false
        reportStatus(nil)
    }

    /// An all-dark stream window is not evidence about bars: wait for the
    /// scene to brighten, then measure again. WT never reaches this - its
    /// accumulation loop keeps waiting on its own.
    private func scheduleDarkRetry(filePath: String, videoW: Double, videoH: Double, duration: Double) {
        retryGeneration += 1
        let generation = retryGeneration
        print("[cropdetect] no usable frames - one retry in 30s up=\(cropUptime())")
        analysisQueue.asyncAfter(deadline: .now() + 30.0) { [weak self] in
            guard let self = self else { return }
            guard self.retryGeneration == generation, !self.isPending else { return }
            print("[cropdetect] dark-scene retry firing up=\(cropUptime())")
            self.detect(filePath: filePath, videoW: videoW, videoH: videoH, fallbackDuration: duration)
        }
    }

    func resetLastFile() {
        lastDetectedFile = ""
    }

    /// 199az: a seek restarts the search with a fresh cadence; the playhead-anchored window starts
    /// narrow again at the new position. PPController's seek event calls this; ordinary indecisive
    /// retries and buffer-growth restarts keep the cursor so the window keeps widening.
    func resetAutomaticWidenCursor() {
        automaticWidenLevel = 0
    }

    // WT playback decides on confidence, not on a fixed window: bars are a
    // static property of the file, so votes can accumulate across any bright
    // frames whenever healthy playback delivers them. A stalled capture is a
    // skip, a dark frame is a skip; neither costs anything and neither votes.
    // The loop ends at quorum, the bright-sample ceiling, the capture budget,
    // or on cancel/file switch.
    private func runWTAccumulation(filePath: String, videoW: Double, videoH: Double, manual: Bool) {
        guard let mainPath = mainIPCPath, let generation = currentGeneration(for: filePath) else {
            finish(finalCrop: nil, filePath: filePath, definitive: false)
            return
        }
        wtQueue.async { [weak self] in
            let diagnosticOldThreadName = Thread.current.name
            Thread.current.name = "crop.wait"
            defer { Thread.current.name = diagnosticOldThreadName }
            guard let self = self, self.isCurrent(filePath, generation) else { return }
            let state = RoundState(rng: SeededRandomNumberGenerator(seed: 1),
                                   duration: 120, maxFrames: Self.wtBrightSampleCeiling,
                                   generation: generation, playback: self.currentMainPlayback())
            self.reportStatus("seeking frames")
            self.captureWTFramesUntilSettled(
                mainIPCPath: mainPath, videoW: videoW, videoH: videoH,
                state: state, stateQueue: DispatchQueue(label: "gor.cropdetect.wt.state"),
                filePath: filePath, manual: manual
            )
        }
    }

    private func captureWTFramesUntilSettled(
        mainIPCPath: String, videoW: Double, videoH: Double,
        state: RoundState, stateQueue: DispatchQueue, filePath: String, manual: Bool
    ) {
        let client = probeFactory(mainIPCPath)
        // The main player need not change its screenshot preferences: mpv
        // chooses the screenshot-to-file encoder from this unique extension.
        let ext = "jpg"
        var lastPlaybackPosition: Double?
        var lastFrame: Data?
        let interval = manual ? Self.wtManualSampleInterval : Self.wtSampleInterval
        let started = ProcessInfo.processInfo.systemUptime
        var iteration = 0

        while isCurrent(filePath, state.generation) {
            if iteration > 0, !sleepWhileCurrent(interval, filePath: filePath, generation: state.generation) { return }
            // Dark frames, a stalled player and failed captures cannot consume
            // the bright-frame quorum, but cannot run forever on a hot laptop.
            if iteration >= Self.wtMaxAttempts || ProcessInfo.processInfo.systemUptime - started >= Self.wtMaxElapsed {
                print("[cropdetect] wt capture budget reached (attempts=\(iteration)) - file stays unlocked")
                finish(finalCrop: nil, filePath: filePath, definitive: false, expectedGeneration: state.generation)
                return
            }
            iteration += 1
            guard isCurrent(filePath, state.generation) else { return }

            if !manual, !waitForMainPlayback(filePath: filePath, generation: state.generation, playback: state.playback) {
                guard isCurrent(filePath, state.generation) else { return }
                // A nil/stale playback binding is not a completed detector.
                // Release pending so the next decoded restart can re-arm it.
                if Diag.mediaTelemetryEnabled {
                    Diag.mediaRecord("[media-shot] caller=wt-live outcome=readiness-timeout wait_s=30")
                }
                finish(finalCrop: nil, filePath: filePath, definitive: false, expectedGeneration: state.generation)
                return
            }
            let paused = client.isPaused()
            let loadedPath = client.currentPath()
            let position = client.timePosition()
            // Missing player status cannot vote, and a still playhead
            // cannot be mistaken for independent screenshot evidence.
            guard paused == false, loadedPath == filePath,
                  let position = position,
                  position.isFinite,
                  lastPlaybackPosition.map({ position > $0 + 0.05 }) ?? true else {
                continue
            }
            lastPlaybackPosition = position

            let shotPath = "/tmp/crop_frame_live_\(Int(Date().timeIntervalSince1970 * 1000))_\(iteration).\(ext)"
            guard let shotCommand = client.screenshotCommand(to: shotPath) else {
                continue
            }
            // mpv can finish writing the screenshot after the IPC response
            // times out (and logs a broken pipe when replying). The uniquely
            // named file is the evidence of capture, not the reply socket.
            if Diag.mediaTelemetryEnabled {
                Diag.mediaRecord("[media-shot] caller=wt-live phase=request manual=\(manual)")
            }
            client.sendPrepared(shotCommand)
            waitForScreenshotFile(at: shotPath, maxWait: 3.0)
            guard isCurrent(filePath, state.generation) else {
                try? FileManager.default.removeItem(atPath: shotPath)
                return
            }
            let postShotPath = client.currentPath()
            guard postShotPath == filePath else {
                try? FileManager.default.removeItem(atPath: shotPath)
                continue
            }
            guard let imageBytes = try? Data(contentsOf: URL(fileURLWithPath: shotPath)),
                  !imageBytes.isEmpty,
                  let image = NSImage(data: imageBytes),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                try? FileManager.default.removeItem(atPath: shotPath)
                stateQueue.sync { state.failCount += 1 }
                continue
            }
            try? FileManager.default.removeItem(atPath: shotPath)
            if lastFrame == imageBytes {
                // Duplicate decoded frame: the player is stuck on one image,
                // so this capture is not independent evidence.
                continue
            }
            lastFrame = imageBytes
            guard isCurrent(filePath, state.generation) else { return }

            let result = self.detectBlackBars(in: cgImage, containerWidth: videoW, containerHeight: videoH,
                                              safeSymmetric: true, auto: !manual)
            guard isCurrent(filePath, state.generation) else { return }
            if result.centerLum < Self.darkFrameCenterLumThreshold || !result.eligible {
                stateQueue.sync { state.darkSceneNoCropCount += 1 }
                continue
            }
            let independent = stateQueue.sync {
                manual || state.acceptsIndependentFrame(result.signature)
            }
            guard independent else {
                print("[cropdetect] correlated frame skipped (no new vote)")
                continue
            }
            stateQueue.sync {
                if let crop = result.crop {
                    print("[cropdetect] crop found on live frame \(iteration): \(crop)")
                    state.allCrops.append(crop)
                } else {
                    print("[cropdetect] no crop on live frame \(iteration)")
                    state.noCropCount += 1
                }
            }
            let bright = stateQueue.sync { state.allCrops.count + state.noCropCount }
            reportStatus("seeking frames (\(bright) usable)")
            if decideWTWindow(filePath: filePath, state: state, videoW: videoW, videoH: videoH) { return }
            if bright >= Self.wtBrightSampleCeiling {
                print("[cropdetect] wt accumulation ceiling (\(bright) usable frames) without a settled vote - file stays unlocked")
                finish(finalCrop: nil, filePath: filePath, definitive: false, expectedGeneration: state.generation)
                return
            }
        }
    }

    /// WT quorum over the bright frames accumulated so far. Returns true once
    /// the vote has settled (finish() ran); false means keep accumulating.
    /// Only bright frames reach the counters: bars can only be measured on a
    /// bright frame, and a no-bars verdict can only come from bright frames.
    private func decideWTWindow(filePath: String, state: RoundState,
                                videoW: Double, videoH: Double) -> Bool {
        guard isCurrent(filePath, state.generation) else { return true }
        let valid = state.allCrops.count + state.noCropCount
        guard valid >= Self.wtMinValidSamples else { return false }
        print("[cropdetect] wt window: bright=\(valid) crop=\(state.allCrops.count) noCrop=\(state.noCropCount) dark=\(state.darkSceneNoCropCount) failed=\(state.failCount)")
        // WT crops use the smaller measured edge margin on each frame,
        // then the smallest across supporting frames. Larger opposing
        // margins cannot drag a crop inward; a one-sided frame cannot vote for
        // the corresponding axis because detectBlackBars rejected it.
        let horizontal = state.allCrops.filter { $0.minX >= 0.01 && $0.width <= 0.98 }
        let vertical = state.allCrops.filter { $0.minY >= 0.01 && $0.height <= 0.98 }
        let hVotes = horizontal.count
        let vVotes = vertical.count
        let hConfidence = Double(hVotes) / Double(valid)
        let vConfidence = Double(vVotes) / Double(valid)
        let hMargin = hConfidence >= 2.0 / 3.0 ? horizontal.map { min($0.minX, 1 - $0.maxX) }.min() : nil
        let vMargin = vConfidence >= 2.0 / 3.0 ? vertical.map { min($0.minY, 1 - $0.maxY) }.min() : nil
        if hMargin != nil || vMargin != nil {
            let x = hMargin ?? 0
            let y = vMargin ?? 0
            let crop = CGRect(x: x, y: y, width: 1 - 2*x, height: 1 - 2*y)
            let confidence = max(hMargin != nil ? hConfidence : 0, vMargin != nil ? vConfidence : 0)
            print("[cropdetect] wt quorum: horizontal=\(hVotes)/\(valid) vertical=\(vVotes)/\(valid) crop=\(crop)")
            finish(finalCrop: crop, filePath: filePath, confidence: confidence, expectedGeneration: state.generation)
            return true
        }
        let noCropConfidence = Double(state.noCropCount) / Double(valid)
        guard noCropConfidence >= 2.0 / 3.0 else { return false }
        finish(finalCrop: nil, filePath: filePath, definitive: true,
               confidence: noCropConfidence, expectedGeneration: state.generation)
        return true
    }

    // ── Round-based parallel analysis ───────────────────────────────────────

    private func beginRound(
        filePath: String, videoW: Double, videoH: Double,
        fallbackDuration: Double, isStream: Bool,
        sampleCount: Int, maxParallel: Int, manual: Bool = false
    ) {
        analysisQueue.async { [weak self] in
            guard let self = self else { return }

            self.resolveDurationThenRun(
                filePath: filePath, videoW: videoW, videoH: videoH,
                fallbackDuration: fallbackDuration, isStream: isStream,
                sampleCount: sampleCount, maxParallel: maxParallel, manual: manual
            )
        }
    }

    private func resolveDurationThenRun(
        filePath: String, videoW: Double, videoH: Double,
        fallbackDuration: Double, isStream: Bool,
        sampleCount: Int, maxParallel: Int, manual: Bool = false
    ) {
        guard currentGeneration(for: filePath) != nil else { return }
        if fallbackDuration > 0 {
            print("[cropdetect] using fallback duration (\(fallbackDuration)s), skipping probe")
            beginSampling(
                filePath: filePath, videoW: videoW, videoH: videoH,
                duration: fallbackDuration, isStream: isStream,
                sampleCount: sampleCount, maxParallel: maxParallel, manual: manual
            )
            return
        }

        if Self.isWTPlayback(filePath) {
            // Timeline slots are only bookkeeping for live captures. A wt
            // stream may not expose duration while buffering, so never probe
            // wt_server or wait for a duration before sampling decoded frames.
            beginSampling(filePath: filePath, videoW: videoW, videoH: videoH,
                          duration: 120, isStream: true,
                          sampleCount: sampleCount, maxParallel: maxParallel, manual: manual)
            return
        }

        if isStream {
            // A probe mpv re-opening a stream URL 403s on expired signatures;
            // the running player already knows the duration. Stream positions
            // only pace live captures from here on, never seeks.
            guard let mainPath = mainIPCPath else {
                print("[cropdetect] stream duration probe needs main-player IPC (unset)")
                self.finish(finalCrop: nil, filePath: filePath, definitive: false)
                return
            }
            let mainClient = probeFactory(mainPath)
            guard waitForFileLoaded(client: mainClient, maxWait: 10.0) else {
                print("[cropdetect] stream duration unavailable from player")
                self.finish(finalCrop: nil, filePath: filePath, definitive: false)
                return
            }
            let duration = mainClient.fileDuration() ?? 0
            guard duration > 0 else {
                print("[cropdetect] could not determine duration")
                self.finish(finalCrop: nil, filePath: filePath, definitive: false)
                return
            }
            beginSampling(
                filePath: filePath, videoW: videoW, videoH: videoH,
                duration: duration, isStream: isStream,
                sampleCount: sampleCount, maxParallel: maxParallel, manual: manual
            )
            return
        }

        let probeSocket = "/tmp/hidden_mpv_probe_\(Int(Date().timeIntervalSince1970 * 1000)).sock"
        guard let probeProc = launchHiddenMpv(filePath: filePath, socketPath: probeSocket, isStream: isStream) else {
            print("[cropdetect] probe mpv failed to launch")
            self.finish(finalCrop: nil, filePath: filePath, definitive: false)
            return
        }
        registerActive(process: probeProc, socketPath: probeSocket)

        guard waitForSocket(at: probeSocket, maxAttempts: 50) else {
            print("[cropdetect] probe socket timeout")
            terminate(probeProc, socketPath: probeSocket)
            self.finish(finalCrop: nil, filePath: filePath, definitive: false)
            return
        }

        let client = probeFactory(probeSocket)
        var duration: Double = 0
        if let d = client.fileDuration() { duration = d }
        terminate(probeProc, socketPath: probeSocket)

        guard duration > 0 else {
            print("[cropdetect] could not determine duration")
            self.finish(finalCrop: nil, filePath: filePath, definitive: false)
            return
        }

        beginSampling(
            filePath: filePath, videoW: videoW, videoH: videoH,
            duration: duration, isStream: isStream,
            sampleCount: sampleCount, maxParallel: maxParallel, manual: manual
        )
    }

    private func slottedPositions(
        count: Int, duration: Double, rng: inout SeededRandomNumberGenerator,
        headMargin: Double = 0.15, tailMargin: Double = 0.10
    ) -> [Int] {
        guard count > 0 else { return [] }
        let usableStart = duration * headMargin
        let usableEnd   = duration * (1.0 - tailMargin)
        let usableSpan  = usableEnd - usableStart
        guard usableSpan > 0 else { return [] }
        let slotWidth = usableSpan / Double(count)
        return (0..<count).map { slotIndex in
            let slotStart = usableStart + Double(slotIndex) * slotWidth
            let ratio     = Double(rng.next()) / Double(UInt64.max)
            return Int(slotStart + ratio * slotWidth)
        }.sorted()
    }

    private func beginSampling(
        filePath: String, videoW: Double, videoH: Double,
        duration: Double, isStream: Bool,
        sampleCount: Int, maxParallel: Int, manual: Bool = false
    ) {
        var rng = SeededRandomNumberGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
        let initialPositions = slottedPositions(count: sampleCount, duration: duration, rng: &rng)
        print("[cropdetect] initial positions (parallel, max \(maxParallel) concurrent): \(initialPositions)")

        let state = RoundState(rng: rng, duration: duration, maxFrames: sampleCount * 2,
                               generation: currentGeneration(for: filePath) ?? -1, playback: currentMainPlayback())
        runRound(
            positions: initialPositions, filePath: filePath,
            videoW: videoW, videoH: videoH, isStream: isStream,
            maxParallel: maxParallel, state: state, manual: manual
        )
    }

    private final class RoundState {
        var rng: SeededRandomNumberGenerator
        let duration: Double
        let maxFrames: Int
        let generation: Int
        var allCrops: [CGRect] = []
        var noCropCount = 0
        var failCount = 0
        var seekWait: TimeInterval = 0.5
        var screenshotWait: TimeInterval = 0.5
        var processedPositions: Set<Int> = []
        var fileConfirmedLoaded = false
        var readinessTimedOut = false
        let playback: Int?
        var consecutiveCleanSamples = 0
        var darkSceneNoCropCount = 0
        var votedFrameSignatures: [[UInt8]] = []
        // Crop and no-crop votes both require different image evidence, not
        // merely distinct screenshot bytes or progressing playback position.
        func acceptsIndependentFrame(_ signature: [UInt8]) -> Bool {
            guard !signature.isEmpty else { return false }
            for previous in votedFrameSignatures where previous.count == signature.count {
                let changed = zip(previous, signature).reduce(0) { count, pair in
                    count + (abs(Int(pair.0) - Int(pair.1)) >= 2 ? 1 : 0)
                }
                if changed < 4 { return false }
            }
            votedFrameSignatures.append(signature)
            return true
        }

        init(rng: SeededRandomNumberGenerator, duration: Double, maxFrames: Int, generation: Int, playback: Int?) {
            self.rng = rng
            self.duration = duration
            self.maxFrames = maxFrames
            self.generation = generation
            self.playback = playback
        }
    }

    private func runRound(
        positions: [Int], filePath: String, videoW: Double, videoH: Double,
        isStream: Bool, maxParallel: Int, state: RoundState, manual: Bool = false
    ) {
        guard isCurrent(filePath, state.generation) else { return }
        guard positions.count < 20 else {
            print("[cropdetect] too many failed attempts, giving up")
            finish(finalCrop: nil, filePath: filePath, definitive: false)
            return
        }

        let newPositions = positions.filter { !state.processedPositions.contains($0) }
        guard !newPositions.isEmpty else {
            decideAfterRound(
                allPositions: positions, filePath: filePath,
                videoW: videoW, videoH: videoH, isStream: isStream,
                maxParallel: maxParallel, state: state, manual: manual
            )
            return
        }

        state.seekWait       = isStream ? 1.0 : 0.5
        state.screenshotWait = isStream ? 1.0 : 0.5

        let group = DispatchQueue(label: "gor.cropdetect.stateq")

        if isStream {
            guard let mainPath = mainIPCPath else {
                print("[cropdetect] stream sampling needs main-player IPC (unset)")
                finish(finalCrop: nil, filePath: filePath, definitive: false)
                return
            }
            let isFirstRound = state.processedPositions.isEmpty
            analysisQueue.async { [weak self] in
                guard let self = self else { return }
                if !isFirstRound {
                    // Retry rounds wait so dark or inconclusive scenes can pass
                    // under the live captures; there is no probe load to throttle.
                    print("[cropdetect] stream inter-round cooldown: \(String(format: "%.1f", CropDetector.streamRoundCoolDown))s")
                    Thread.sleep(forTimeInterval: CropDetector.streamRoundCoolDown)
                }
                self.sampleLiveStreamFrames(
                    count: newPositions.count, interval: Self.streamLiveSampleInterval,
                    mainIPCPath: mainPath, videoW: videoW, videoH: videoH,
                    state: state, stateQueue: group, filePath: filePath, manual: manual
                )
                // A cancel during sampling means silence: no decision, no apply.
                guard self.isCurrent(filePath, state.generation) else { return }
                if group.sync(execute: { state.readinessTimedOut }) {
                    self.finish(finalCrop: nil, filePath: filePath, definitive: false)
                    return
                }
                group.sync { for p in newPositions { state.processedPositions.insert(p) } }
                self.decideAfterRound(
                    allPositions: positions, filePath: filePath,
                    videoW: videoW, videoH: videoH, isStream: isStream,
                    maxParallel: maxParallel, state: state, manual: manual
                )
            }
            return
        }

        let sem   = DispatchSemaphore(value: maxParallel)
        let dgroup = DispatchGroup()

        for seekSec in newPositions {
            dgroup.enter()
            analysisQueue.async { [weak self] in
                guard let self = self else { dgroup.leave(); return }
                sem.wait()
                self.sampleOnePosition(
                    seekSec: seekSec, filePath: filePath, videoW: videoW, videoH: videoH,
                    isStream: isStream, state: state, stateQueue: group, manual: manual
                )
                sem.signal()
                dgroup.leave()
            }
        }

        dgroup.notify(queue: analysisQueue) { [weak self] in
            guard let self = self else { return }
            group.sync { for p in newPositions { state.processedPositions.insert(p) } }
            self.decideAfterRound(
                allPositions: positions, filePath: filePath,
                videoW: videoW, videoH: videoH, isStream: isStream,
                maxParallel: maxParallel, state: state, manual: manual
            )
        }
    }

    private func sampleAtPosition(
        client: CropProbeTransport, seekSec: Int, filePath: String, videoW: Double, videoH: Double,
        isStream: Bool, state: RoundState, stateQueue: DispatchQueue, manual: Bool = false
    ) {
        let alreadyLoaded = stateQueue.sync { state.fileConfirmedLoaded }
        let fileLoadWait: TimeInterval = isStream ? (alreadyLoaded ? 1.5 : 10.0) : 1.5
        guard waitForFileLoaded(client: client, maxWait: fileLoadWait) else {
            print("[cropdetect] file not loaded, skipping sample at \(seekSec)s")
            stateQueue.sync { state.failCount += 1 }
            return
        }
        stateQueue.sync { state.fileConfirmedLoaded = true }

        client.seekAbsolute(seconds: seekSec)
        waitForSeekCompletion(client: client, maxWait: state.seekWait)

        let screenshotPath = "/tmp/crop_frame_\(seekSec)_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        if Diag.mediaTelemetryEnabled {
            Diag.mediaRecord("[media-shot] caller=hidden-probe phase=request manual=\(manual)")
        }
        _ = client.screenshotVideo(to: screenshotPath)
        waitForScreenshotFile(at: screenshotPath, maxWait: state.screenshotWait)

        defer { try? FileManager.default.removeItem(atPath: screenshotPath) }

        func decodeAndAnalyze() -> (crop: CGRect?, centerLum: Double, eligible: Bool, signature: [UInt8], imageOK: Bool) {
            guard let image   = NSImage(contentsOfFile: screenshotPath),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return (nil, 0, false, [], false) }
            let result = self.detectBlackBars(in: cgImage, containerWidth: videoW, containerHeight: videoH,
                                              auto: !manual)
            return (result.crop, result.centerLum, result.eligible, result.signature, true)
        }

        var result = decodeAndAnalyze()
        var usedStaleFrameRetry = false

        if isStream, result.imageOK,
           !result.eligible || result.centerLum < Self.darkFrameCenterLumThreshold {
            usedStaleFrameRetry = true
            Thread.sleep(forTimeInterval: CropDetector.staleFrameSettleDelay)
            try? FileManager.default.removeItem(atPath: screenshotPath)
            if Diag.mediaTelemetryEnabled {
                Diag.mediaRecord("[media-shot] caller=hidden-probe-retry phase=request manual=\(manual)")
            }
            _ = client.screenshotVideo(to: screenshotPath)
            waitForScreenshotFile(at: screenshotPath, maxWait: state.screenshotWait)
            let retryResult = decodeAndAnalyze()
            if retryResult.eligible,
               retryResult.centerLum >= Self.darkFrameCenterLumThreshold {
                print("[cropdetect] stale frame retry recovered at \(seekSec)s")
            }
            result = retryResult
        }

        if result.imageOK {
            let crop = result.crop
            stateQueue.sync {
                if !result.eligible || result.centerLum < Self.darkFrameCenterLumThreshold {
                    print("[cropdetect] ineligible frame at \(seekSec)s ignored")
                    state.darkSceneNoCropCount += 1
                } else if !manual && !state.acceptsIndependentFrame(result.signature) {
                    print("[cropdetect] correlated frame at \(seekSec)s ignored")
                } else if let crop = crop {
                    print("[cropdetect] crop found at \(seekSec)s: \(crop)")
                    state.allCrops.append(crop)
                } else {
                    print("[cropdetect] no crop at \(seekSec)s")
                    state.noCropCount += 1
                }
                if isStream, !usedStaleFrameRetry {
                    state.consecutiveCleanSamples += 1
                    if state.consecutiveCleanSamples >= 3 {
                        state.seekWait       = max(state.seekWait * 0.5, 0.5)
                        state.screenshotWait = max(state.screenshotWait * 0.5, 0.5)
                        state.consecutiveCleanSamples = 0
                    }
                }
            }
        } else {
            print("[cropdetect] failed to decode frame at \(seekSec)s")
            stateQueue.sync {
                state.failCount += 1
                state.consecutiveCleanSamples = 0
                if isStream {
                    state.seekWait       = min(state.seekWait * 2.0, 8.0)
                    state.screenshotWait = min(state.screenshotWait * 2.0, 8.0)
                }
            }
        }
    }

    private func sampleOnePosition(
        seekSec: Int, filePath: String, videoW: Double, videoH: Double,
        isStream: Bool, state: RoundState, stateQueue: DispatchQueue, manual: Bool = false
    ) {
        let socketPath = "/tmp/hidden_mpv_\(seekSec)_\(Int(Date().timeIntervalSince1970 * 1000)).sock"
        guard let proc = launchHiddenMpv(filePath: filePath, socketPath: socketPath, isStream: isStream) else {
            stateQueue.sync { state.failCount += 1 }
            return
        }
        registerActive(process: proc, socketPath: socketPath)
        defer { terminate(proc, socketPath: socketPath) }

        guard waitForSocket(at: socketPath, maxAttempts: 50) else {
            stateQueue.sync { state.failCount += 1 }
            return
        }

        let client = probeFactory(socketPath)
        sampleAtPosition(
            client: client, seekSec: seekSec, filePath: filePath, videoW: videoW, videoH: videoH,
            isStream: isStream, state: state, stateQueue: stateQueue, manual: manual
        )
    }

    /// Streams: capture live frames from the already-playing main mpv instead
    /// of probing the URL with hidden mpvs. Positions are meaningless without
    /// seeking the user's playback, so `count` wall-clock-spaced captures
    /// stand in for them; scene diversity comes from playback progressing.
    /// WT playback never comes through here - it accumulates in
    /// captureWTFramesUntilSettled until the vote settles.
    private func sampleLiveStreamFrames(
        count: Int, interval: TimeInterval, mainIPCPath: String, videoW: Double, videoH: Double,
        state: RoundState, stateQueue: DispatchQueue, filePath: String, manual: Bool = false
    ) {
        let client = probeFactory(mainIPCPath)

        if !manual, !waitForMainPlayback(filePath: filePath, generation: state.generation, playback: state.playback) {
            guard isCurrent(filePath, state.generation), let playback = state.playback,
                  isMainPlaybackCurrent(playback) else { return }
            Diag.mediaRecord("[media-shot] caller=stream-live outcome=readiness-timeout wait_s=30")
            stateQueue.sync { state.readinessTimedOut = true; state.failCount += count }
            return
        }

        if !waitForFileLoaded(client: client, maxWait: 5.0) {
            print("[cropdetect] player has no loaded file, aborting live sampling")
            stateQueue.sync { state.failCount += count }
            return
        }

        let ext = client.screenshotFormat()

        for i in 0..<count {
            guard isCurrent(filePath, state.generation) else { return }
            if i > 0 { Thread.sleep(forTimeInterval: interval) }
            guard isCurrent(filePath, state.generation) else { return }

            if !manual, !waitForMainPlayback(filePath: filePath, generation: state.generation, playback: state.playback) {
                guard isCurrent(filePath, state.generation), let playback = state.playback,
                      isMainPlaybackCurrent(playback) else { return }
                if Diag.mediaTelemetryEnabled {
                    Diag.mediaRecord("[media-shot] caller=stream-live outcome=readiness-timeout wait_s=30")
                }
                stateQueue.sync { state.failCount += count - i; state.readinessTimedOut = true }
                return
            }
            let shotPath = "/tmp/crop_frame_live_\(Int(Date().timeIntervalSince1970 * 1000))_\(i).\(ext)"
            defer { try? FileManager.default.removeItem(atPath: shotPath) }
            if Diag.mediaTelemetryEnabled {
                Diag.mediaRecord("[media-shot] caller=stream-live phase=request manual=\(manual)")
            }
            _ = client.screenshotVideo(to: shotPath)
            waitForScreenshotFile(at: shotPath, maxWait: Self.liveScreenshotWait)
            guard let image = NSImage(contentsOfFile: shotPath),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                stateQueue.sync { state.failCount += 1 }
                continue
            }
            let result = detectBlackBars(in: cgImage, containerWidth: videoW, containerHeight: videoH,
                                         auto: !manual)
            stateQueue.sync {
                if !result.eligible || result.centerLum < Self.darkFrameCenterLumThreshold {
                    // No evidence in either direction: the frame votes
                    // neither accept nor reject.
                    state.darkSceneNoCropCount += 1
                } else if !manual && !state.acceptsIndependentFrame(result.signature) {
                    print("[cropdetect] correlated live frame skipped")
                } else if let crop = result.crop {
                    state.allCrops.append(crop)
                } else {
                    state.noCropCount += 1
                }
            }
        }
    }

    private func appendSlottedPositions(
        _ count: Int, to positions: inout [Int], duration: Double,
        rng: inout SeededRandomNumberGenerator,
        headMargin: Double = 0.15, tailMargin: Double = 0.10
    ) {
        var newlySlotted = slottedPositions(
            count: count, duration: duration, rng: &rng,
            headMargin: headMargin, tailMargin: tailMargin
        )
        let usableStart = duration * headMargin
        let usableSpan  = duration * (1.0 - headMargin - tailMargin)
        let slotWidth   = usableSpan / Double(max(count, 1))
        for i in newlySlotted.indices {
            var attempts = 0
            while positions.contains(newlySlotted[i]), attempts < 10 {
                let ratio     = Double(rng.next()) / Double(UInt64.max)
                let slotStart = usableStart + Double(i) * slotWidth
                newlySlotted[i] = Int(slotStart + ratio * slotWidth)
                attempts += 1
            }
        }
        positions.append(contentsOf: newlySlotted)
        positions.sort()
    }

    private func decideAfterRound(
        allPositions: [Int], filePath: String, videoW: Double, videoH: Double,
        isStream: Bool, maxParallel: Int, state: RoundState, manual: Bool = false
    ) {
        guard isCurrent(filePath, state.generation) else { return }
        let validSamples = state.allCrops.count + state.noCropCount
        let totalSamples = validSamples + state.failCount
        print("[cropdetect] round complete, crop=\(state.allCrops.count) noCrop=\(state.noCropCount) failed=\(state.failCount) total=\(totalSamples)")

        guard validSamples >= 4 else {
            if isStream, !manual, state.allCrops.isEmpty, state.noCropCount == 0,
               state.darkSceneNoCropCount > 0, let mainPath = mainIPCPath {
                // Every captured frame was below the brightness threshold:
                // no evidence either way, so don't burn more rounds on the
                // same dark stretch - wait for the scene to brighten. A
                // paused player will still be dark in 30s, so don't schedule.
                let paused = probeFactory(mainPath).isPaused()
                finish(finalCrop: nil, filePath: filePath, definitive: false)
                if paused != false {
                    print("[cropdetect] all-dark window but player paused - no retry scheduled up=\(cropUptime())")
                } else {
                    scheduleDarkRetry(filePath: filePath, videoW: videoW, videoH: videoH, duration: state.duration)
                }
                return
            }
            print("[cropdetect] not enough valid samples (\(validSamples)), continuing...")
            var positions = allPositions
            appendSlottedPositions(4, to: &positions, duration: state.duration, rng: &state.rng)
            print("[cropdetect] new positions: \(positions)")
            runRound(
                positions: positions, filePath: filePath, videoW: videoW, videoH: videoH,
                isStream: isStream, maxParallel: maxParallel, state: state, manual: manual
            )
            return
        }

        // Variable-aspect content (IMAX-style shifts): substantial votes both
        // ways mean no single crop is right - apply none. Locals only: stream
        // sampling sees a narrow time window, where split votes mean scene
        // changes, not aspect shifts. Skipped for the manual-redetect window
        // (empty positions): the user asked to crop what they are watching.
        if !isStream, !allPositions.isEmpty,
           Double(state.noCropCount) >= Double(validSamples) * 0.25,
           Double(state.allCrops.count) >= Double(validSamples) * 0.25 {
            print("[cropdetect] variable aspect ratio (crop=\(state.allCrops.count) measuredNoCrop=\(state.noCropCount) of \(validSamples)) - no single crop is right, applying none")
            finish(finalCrop: nil, filePath: filePath, confidence: 1.0)
            return
        }

        if state.noCropCount > state.allCrops.count, validSamples >= 2 {
            // Lock only a confident measurement: no-bar votes must hold two
            // thirds of all valid (bright) samples, otherwise the file stays
            // open for a later trigger.
            let confident = Double(state.noCropCount) / Double(validSamples) >= 2.0 / 3.0
            print("[cropdetect] no-crop votes in majority, not applying a crop")
            finish(finalCrop: nil, filePath: filePath, definitive: confident,
                   confidence: Double(state.noCropCount) / Double(validSamples))
            return
        }

        let (result, needsMoreSamples, winningVotes) = self.findConsistentCropWithFeedback(from: state.allCrops)

        if needsMoreSamples, validSamples < state.maxFrames {
            print("[cropdetect] inconclusive, adding 2 new positions...")
            var positions = allPositions
            appendSlottedPositions(2, to: &positions, duration: state.duration, rng: &state.rng)
            print("[cropdetect] new positions: \(positions)")
            runRound(
                positions: positions, filePath: filePath, videoW: videoW, videoH: videoH,
                isStream: isStream, maxParallel: maxParallel, state: state, manual: manual
            )
        } else {
            // Two thirds of all valid samples or it stays open: an inconclusive
            // exhaustion (result nil) and a narrow win both re-measure later.
            let confident = result != nil &&
                Double(winningVotes) / Double(validSamples) >= 2.0 / 3.0
            finish(finalCrop: result, filePath: filePath, definitive: confident,
                   confidence: result != nil ? Double(winningVotes) / Double(validSamples) : 0.0)
        }
    }

    private func finish(finalCrop: CGRect?, filePath: String, definitive: Bool = true, confidence: Double = 0.0, expectedGeneration: Int? = nil) {
        guard let generation = currentGeneration(for: filePath),
              expectedGeneration == nil || expectedGeneration == generation else { return }
        reportStatus(nil)
        print("[cropdetect] final: \(finalCrop?.debugDescription ?? "nil")\(definitive ? "" : " (non-definitive, file not locked — automatic retry possible)")")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isCurrent(filePath, generation) else { return }
            self.activeLock.lock()
            let procs = self.activeProcesses
            let paths = self.activeSocketPaths
            self.activeProcesses   = []
            self.activeSocketPaths = []
            self.activeLock.unlock()
            for proc in procs where proc.isRunning { MPVLifeline.close(for: proc) }
            for path in paths { try? FileManager.default.removeItem(atPath: path) }
            self.isPending          = false
            if definitive {
                self.lastDetectedFile = filePath
            }
            self.onResult?(finalCrop, definitive, confidence)
        }
    }

    // ── Hidden mpv instance helpers ─────────────────────────────────────────

    private func launchHiddenMpv(filePath: String, socketPath: String, isStream: Bool) -> Process? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: mpvPath)
        var args = [
            "--no-config",
            "--vo=null",
            "--msg-level=all=fatal",
            "--ao=null",
            "--no-osc",
            "--no-input-default-bindings",
            "--hr-seek=no",
            "--screenshot-format=jpg",
            "--screenshot-jpeg-quality=30",
            "--screenshot-sw=no",
            "--vf=scale=1280:-1",
            "--demuxer-lavf-analyzeduration=10",
            "--demuxer-lavf-probescore=30",
            "--hwdec=auto-safe",
        ]
        if isStream {
            args += [
                "--cache=yes",
                "--demuxer-max-bytes=10M",
                "--demuxer-max-back-bytes=5M",
            ]
        } else {
            args += ["--cache=no"]
        }
        args += [
            "--input-ipc-server=\(socketPath)",
            filePath
        ]
        proc.arguments = args
        // I16: hidden cropdetect mpv stderr stays /dev/null.
        proc.standardError = FileHandle.nullDevice
        do {
            try MPVLifeline.run(proc)
            return proc
        } catch {
            print("[cropdetect] mpv failed to launch: \(error)")
            return nil
        }
    }

    private func registerActive(process: Process, socketPath: String) {
        activeLock.lock()
        activeProcesses.append(process)
        activeSocketPaths.append(socketPath)
        activeLock.unlock()
    }

    private func terminate(_ proc: Process, socketPath: String) {
        if proc.isRunning {
            MPVLifeline.close(for: proc)
            if proc.isRunning {
                let deadline = DispatchTime.now() + 2.0
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    proc.waitUntilExit()
                    sem.signal()
                }
                if sem.wait(timeout: deadline) == .timedOut, proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                    proc.waitUntilExit()
                }
            }
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        DispatchQueue.main.async { [weak self] in
            self?.activeProcesses.removeAll { $0 === proc }
        }
    }

    private func waitForSocket(at path: String, maxAttempts: Int) -> Bool {
        var attempts = 0
        while attempts < maxAttempts {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.1)
            attempts += 1
        }
        return false
    }
    
    // ── Consistency analysis ────────────────────────────────────────────────

    private func findConsistentCropWithFeedback(from crops: [CGRect]) -> (crop: CGRect?, needsMoreSamples: Bool, winningVotes: Int) {
        guard crops.count >= 2 else { return (nil, true, 0) }

        let tolerance: CGFloat = 0.02
        var groups: [[CGRect]] = []

        for crop in crops {
            var found = false
            for i in 0..<groups.count {
                let first = groups[i][0]
                if abs(first.minX  - crop.minX)  < tolerance &&
                   abs(first.minY  - crop.minY)  < tolerance &&
                   abs(first.width - crop.width) < tolerance &&
                   abs(first.height - crop.height) < tolerance {
                    groups[i].append(crop)
                    found = true
                    break
                }
            }
            if !found { groups.append([crop]) }
        }

        let sorted = groups.sorted { $0.count > $1.count }
        guard let largest = sorted.first else { return (nil, true, 0) }

        let total = crops.count

        if sorted.count == 1 || Double(largest.count) / Double(total) >= 0.5 {
            return (crops.reduce(largest[0]) {$0.union($1)}, false, largest.count)
        }

        let secondLargest = sorted[1]
        if largest.count == secondLargest.count { return (nil, true, 0) }

        if Double(largest.count) / Double(total) < 0.4 { return (nil, true, 0) }

        return (crops.reduce(largest[0]) {$0.union($1)}, false, largest.count)
    }

    // ── Black-bar pixel analysis ────────────────────────────────────────────

    private func detectBlackBars(in image: CGImage, containerWidth: Double, containerHeight: Double,
                                 safeSymmetric: Bool = false, auto: Bool = true)
        -> (crop: CGRect?, centerLum: Double, eligible: Bool, signature: [UInt8]) {
        let originalWidth = image.width
        let originalHeight = image.height
        guard originalWidth > 0, originalHeight > 0 else { return (nil, 0, false, []) }
        // Decode the screenshot off-main, then rasterize only the geometry
        // needed by the luminance scan. Never allocate a full-resolution RGBA
        // buffer for a 4K/8K screenshot.
        let sampleWidth = min(originalWidth, Self.analysisMaxWidth)
        let sampleHeight = max(1, Int((Double(originalHeight) * Double(sampleWidth) / Double(originalWidth)).rounded()))
        let bytesPerPixel = 4
        let bytesPerRow   = sampleWidth * bytesPerPixel
        var pixelData     = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * bytesPerPixel)

        guard let context = CGContext(
            data:           &pixelData,
            width:          sampleWidth,
            height:         sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow:    bytesPerRow,
            space:          CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo:     CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return (nil, 0, false, []) }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        let width = sampleWidth
        let height = sampleHeight

        func rowLuminance(_ y: Int) -> Double {
            let rowStart = y * bytesPerRow
            var total: Double = 0
            for x in 0..<width {
                let r = Double(pixelData[rowStart + x * bytesPerPixel])
                let g = Double(pixelData[rowStart + x * bytesPerPixel + 1])
                let b = Double(pixelData[rowStart + x * bytesPerPixel + 2])
                total += r * 0.299 + g * 0.587 + b * 0.114
            }
            return total / Double(width)
        }

        func columnLuminance(_ x: Int) -> Double {
            var total: Double = 0
            for y in 0..<height {
                let idx = y * bytesPerRow + x * bytesPerPixel
                let r   = Double(pixelData[idx])
                let g   = Double(pixelData[idx + 1])
                let b   = Double(pixelData[idx + 2])
                total  += r * 0.299 + g * 0.587 + b * 0.114
            }
            return total / Double(height)
        }

        // One raster pass for black occupancy and a coarse frame signature.
        // The signature uses cell means, so JPEG noise and tiny line motion
        // cannot turn one static title card into independent votes.
        let cellsX = 8, cellsY = 8
        var cellTotals = [Int](repeating: 0, count: cellsX * cellsY)
        var cellCounts = [Int](repeating: 0, count: cellsX * cellsY)
        var nearBlack = 0
        if auto {
            for y in 0..<height {
                for x in 0..<width {
                    let idx = y * bytesPerRow + x * bytesPerPixel
                    let l = (Int(pixelData[idx]) * 77 + Int(pixelData[idx + 1]) * 150
                        + Int(pixelData[idx + 2]) * 29) / 256
                    if l <= Int(Self.autoNearBlackLuminance) { nearBlack += 1 }
                    let cell = min(cellsY - 1, y * cellsY / height) * cellsX
                        + min(cellsX - 1, x * cellsX / width)
                    cellTotals[cell] += l
                    cellCounts[cell] += 1
                }
            }
        }
        let signature: [UInt8] = auto ? cellTotals.indices.map { i in
            UInt8(min(255, cellTotals[i] / max(1, cellCounts[i]) / 8))
        } : []
        let blackFraction = auto ? Double(nearBlack) / Double(width * height) : 0
        let eligible = !auto || blackFraction < Self.autoBlackDominanceFraction
        if !eligible {
            print("[cropdetect] auto frame skipped: black-dominated (nearBlack=\(String(format: "%.2f", blackFraction)))")
            return (nil, 0, false, signature)
        }

        let centerYStart = height * 2 / 10
        let centerYEnd   = height * 8 / 10
        var centerLumSum: Double = 0
        var centerCount          = 0
        for y in centerYStart..<centerYEnd {
            centerLumSum += rowLuminance(y)
            centerCount  += 1
        }
        let centerLum = centerLumSum / Double(centerCount)

        guard centerLum >= 15.0 else {
            print("[cropdetect] dark scene (centerLum=\(Int(centerLum))), frame skipped")
            return (nil, centerLum, eligible, signature)
        }

        let blackThreshold = min(20.0, max(8.0, centerLum * 0.20))

        var topBlackRows = 0
        var topHitScanCeiling = false
        for y in 0..<height/3 {
            if rowLuminance(y) < blackThreshold {
                topBlackRows += 1
                if y == height/3 - 1 { topHitScanCeiling = true }
            } else { break }
        }

        var bottomBlackRows = 0
        var bottomHitScanCeiling = false
        for y in stride(from: height-1, through: height-height/3, by: -1) {
            if rowLuminance(y) < blackThreshold {
                bottomBlackRows += 1
                if y == height-height/3 { bottomHitScanCeiling = true }
            } else { break }
        }

        var leftBlackCols = 0
        for x in 0..<width/3 {
            if columnLuminance(x) < blackThreshold { leftBlackCols += 1 } else { break }
        }

        var rightBlackCols = 0
        for x in stride(from: width-1, through: width-width/3, by: -1) {
            if columnLuminance(x) < blackThreshold { rightBlackCols += 1 } else { break }
        }

        let minPx: CGFloat = max(2, 6 * CGFloat(sampleWidth) / CGFloat(originalWidth))

        // Only a pair of bands can support a symmetric crop. One-sided
        // black space must not remove picture from the opposite edge.
        let topBottomRatio = topBlackRows == 0 && bottomBlackRows == 0 ? 1.0
            : Double(min(topBlackRows, bottomBlackRows)) / Double(max(topBlackRows, bottomBlackRows))
        let leftRightRatio = leftBlackCols == 0 && rightBlackCols == 0 ? 1.0
            : Double(min(leftBlackCols, rightBlackCols)) / Double(max(leftBlackCols, rightBlackCols))

        let verticalScanUnreliable = (topHitScanCeiling || bottomHitScanCeiling)
            && leftBlackCols < width/3 && rightBlackCols < width/3

        let hasVerticalBand   = (topBlackRows > Int(minPx) || bottomBlackRows > Int(minPx)) && topBottomRatio > 0.5 && !verticalScanUnreliable
        let hasHorizontalBand = (leftBlackCols > Int(minPx) || rightBlackCols > Int(minPx)) && leftRightRatio > 0.5

        if verticalScanUnreliable {
            print("[cropdetect] top/bottom scan hit height/3 ceiling (no real edge found), treated as dark scene overall — vertical band rejected")
        }
        print("[cropdetect] top=\(topBlackRows) bottom=\(bottomBlackRows) left=\(leftBlackCols) right=\(rightBlackCols) centerLum=\(Int(centerLum)) threshold=\(Int(blackThreshold))")

        var finalCropX: CGFloat = 0
        var finalCropY: CGFloat = 0
        var finalCropW: CGFloat = 1
        var finalCropH: CGFloat = 1

        if hasHorizontalBand {
            let leftRatio  = CGFloat(leftBlackCols)  / CGFloat(width)
            let rightRatio = CGFloat(rightBlackCols) / CGFloat(width)
            let margin     = min(leftRatio, rightRatio)
            finalCropX     = margin
            finalCropW     = 1 - margin * 2
        }

        if hasVerticalBand {
            let topRatio    = CGFloat(topBlackRows)    / CGFloat(height)
            let bottomRatio = CGFloat(bottomBlackRows) / CGFloat(height)
            let margin      = min(topRatio, bottomRatio)
            finalCropY      = margin
            finalCropH      = 1 - margin * 2
        }

        guard finalCropW < 0.98 || finalCropH < 0.98 else { return (nil, centerLum, eligible, signature) }

        // Bars never remove half the frame; a "crop" that tight is a logo or
        // title card on black, not letterboxing — vote no-crop instead.
        guard finalCropW >= 0.5, finalCropH >= 0.5 else {
            print("[cropdetect] implausible crop rejected (w=\(String(format: "%.2f", finalCropW)) h=\(String(format: "%.2f", finalCropH))) — logo/title frame, voting no-crop")
            return (nil, centerLum, eligible, signature)
        }

        return (CGRect(x: finalCropX, y: finalCropY, width: finalCropW, height: finalCropH), centerLum, eligible, signature)
    }
}

// One bounded wall-clock stamp for every cropdetect boundary line (199ec logging split).
private func cropUptime() -> String { String(format: "%.3f", ProcessInfo.processInfo.systemUptime) }
