// ================================================================
//  AppDelegate.swift - application and mpv lifecycle
//  Owns: mpv process, overlay attachment, window and audio-device synchronization
//  Answers: I3 I13 I14 · TRAP-11
//  Contract: PPController is created in launchMPV's checkTimer, handleWakeUp and attachOverlay (I14)
// ================================================================
import AppKit
import CoreAudio
import CoreGraphics
import Dispatch
import QuartzCore
import Darwin
import CryptoKit

// [attribution comment elided]
// [attribution comment elided]
private final class OwnedPlayerSocket {
    private let path: String
    private let lock = NSLock()
    private var identity: (dev_t, ino_t)?
    private let eligible: Bool
    init(path: String) {
        self.path = path
        var st = stat()
        eligible = lstat(path, &st) != 0 && errno == ENOENT
    }
    func observe() {
        guard eligible else { return } // never claim a path that predates this launch
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK), st.st_uid == getuid() else { return }
        lock.lock(); defer { lock.unlock() }
        if identity == nil { identity = (st.st_dev, st.st_ino) }
    }
    func childExited() {
        lock.lock(); defer { lock.unlock() }
        guard let owned = identity else { return }
        var st = stat()
        guard lstat(path, &st) == 0, st.st_dev == owned.0, st.st_ino == owned.1,
              (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK), st.st_uid == getuid() else { return }
        _ = unlink(path)
        identity = nil
    }
}

// ================================================================
//  DraggableOverlayWindow - drag destination window
// ================================================================
final class DraggableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { !NoActivate.active }
    override var canBecomeMain: Bool { !NoActivate.active }

    // Claim the activating down-event before AppKit dispatches to a child view.
    // PPController.mouseDown is not called when a control handles the click.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, attachedSheet == nil, NSApp.modalWindow == nil {
            NoActivate.userInteraction()
            if !NSApp.isActive { if !StagedRunPaths.active && !NoActivate.suppressAutomatic { NSApp.activate(ignoringOtherApps: true) } }
            // An open input panel owns the key window; an overlay click must not steal it.
            if !isKeyWindow, PanelKeyOwnership.shared.mayKeyPlayerWindow() { makeKeyAndOrderFront(nil) }
        }
        super.sendEvent(event)
    }

    // The overlay is the key window, but it is borderless and cannot miniaturize
    // itself, so any standard minimize action reaching it (Window menu, remapped
    // key, fullscreen) would fall through to NSBeep. Route it to the mpv window
    // minimize chain (exit fullscreen, wait for geometry, then minimize).
    override func performMiniaturize(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.requestMPVMinimize()
    }
    override func miniaturize(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.requestMPVMinimize()
    }
}

// ================================================================
//  AppDelegate - application lifecycle
// ================================================================
// TRAP-11: decode process stdout only after a complete newline-delimited UTF-8 line.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
    private var logWriterProcess: Process?

    var mpvProcess: Process?
    var overlayWin: NSWindow?
    var controller: PPController? {
        didSet { installThreeDSourceResolution()
            controller?.synchronizeSubtitlePresentation(pictureInPicture:pictureInPictureActive && !windowGeometryTransitionActive)
            controller?.ipcCommand(MPVCommand.make(["set_property","user-data/gor/pip-window-owned",pictureInPictureActive]))
        }
    }
    /// The video menu's re-detect item doubles as the crop detector's status
    /// line while a detection is still accumulating frames.
    private weak var cropDetectMenuItem: NSMenuItem?
    var checkTimer: Timer?
    var syncTimer:  Timer?
    var axWindow:   AXUIElement?
    var lastFrame = NSRect.zero
    // Real mpv AX frame, never the overlay's optimistic drag frame. Main-thread state.
    private var mpvWindowedFrame: NSRect?
    private var mpvWindowedCandidate: NSRect?
    private var mpvWindowedCandidateSince: TimeInterval = 0
    private var mpvObservedFullscreen: Bool?
    private var mpvWasFullscreen = false
    private var mpvRestoreFrame: NSRect?
    private var mpvRestoreStarted: TimeInterval = 0
    private var mpvRestoreStableFrame: NSRect?
    private var mpvRestoreStableSince: TimeInterval = 0
    var mpvRestoreWritePending = false
    private var mpvFullscreenEpoch: UInt64 = 0
    // Observation windows, not measured native performance claims. Native AX false
    // uses the shorter window; unsupported AX needs a longer property-backed settle.
    private static let mpvGeometryNativeSettle: TimeInterval = 0.35
    private static let mpvGeometryFallbackSettle: TimeInterval = 0.60
    private static let mpvGeometryTimeout: TimeInterval = 5
    private var mpvEntryTarget: NSRect?
    private var mpvEntryDisplays: [NSRect] = []
    private var mpvEntryStarted: TimeInterval = 0
    // gor 514 trigger/clamp (candidate v4, static review only):
    // re-evaluate the existing mpv window when a usable area changes
    // (notification + snapshot poll) or the user resizes/moves it.
    // gor 514 v5: completion-based own-write fence (GorClampFence): awaitingAck (mpv reply to our request_id)
    // -> landing (receipt of the final frame) -> idle. Replaces the 0.60 s timer; time is only a safety net.
    var clampFence = GorClampFence()
    var windowClampWritePending: Bool { clampFence.isUp }
    var windowClampWorkItem: DispatchWorkItem?
    var lastKnownVisibleFrames: [GorFitRect] = []
    var windowClampPollTimer: Timer?
    // v3 (reviewer F-1): a guard-blocked evaluation stays PENDING and
    // retries on a deadline instead of being dropped. v4 (peer TCv3-F1):
    // the own-write fence also releases at the receipt site once expired.
    var windowClampRetryUntil: TimeInterval = 0
    static let windowClampRetryInterval: TimeInterval = 0.50
    static let windowClampRetryBudget: TimeInterval = 5.0
    private var mpvEntryStableFrame: NSRect?
    private var mpvEntryStableSince: TimeInterval = 0
    private var mpvEntryAttempted = false
    var mpvEntryWritePending = false
    var eventTap: CFMachPort?
    var appActivationObservers: [NSObjectProtocol] = []
    private var mainThreadPriorityActivity: NSObjectProtocol?

    private var mpvOutputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var mpvOutputDeviceChangeGeneration = 0

    private let overlayAXQueue = DispatchQueue(label: "gor.overlay.ax", qos: .userInteractive)
    private var overlayAXObserver: AXObserver?
    private var overlayAXNotifications: [String] = []
    private var overlaySyncGeneration: UInt64 = 0
    private var overlayDragGeneration: UInt64 = 0
    private var overlaySampleInFlight = false
    private var overlaySamplePending = false
    private var overlayFastTimer: Timer?
    private var overlayFastUntil: TimeInterval = 0
    var overlayDragActive = false
    private var overlayDragSettleUntil: TimeInterval = 0
    private var overlayPositionInitializing = false
    private var overlayBufferedDelta = CGPoint.zero
    var overlayPositionWriteInFlight = false
    private var overlayPendingPosition: CGPoint?
    private let minimizeQueue = DispatchQueue(label: "gor.window.minimize", qos: .userInitiated)
    private var minimizeGeneration: UInt64 = 0
    private var minimizePending = false
    // Overlay is hidden the instant a miniaturize starts (AX notification or confirmed
    // window-minimized command); a lagging AX sample that still says "not minimized"
    // must not re-show it until this deadline passes or AX reports minimized=true.
    private var overlayMinimizeHoldUntil: TimeInterval = 0; private var overlaySpace = OverlaySpaceGate()

    
    var isShowingInputPanel = false
    var isDragging = false
    
    var urlPanel: NSPanel?
    
    var cachedMpvPosition: CGPoint? = nil
    
    var osdLineBuffer = Data()

    var lastPlayedURL: String? = nil
    var lastPlayedTitle: String = ""
    var lastPlayedStartPos: Double? = nil
    var youtubePlaybackGeneration: UInt64 = 0
    var lastPlayedSubtitleURLs: [String] = []
    var youtubeRetryAttempted = false
    var ytdlpUpdateInProgress = false
    private static let chromiumUpdateLock = NSLock()
    private static var chromiumUpdateChecked = false
    private static var chromiumUpdateInProgress = false

    var photonEnabled = true
    private static let photonMenuDefaults: [String: Bool] = [
        "bright": true, "sharp": true, "grain": true,
        "hud": false, "chrome": false, "chrome-filter": false, "negativ": false,
    ]
    private var photonMenuStates = AppDelegate.photonMenuDefaults

    // Start from engine defaults; Lua target-state reports replace them, never menu clicks.
    private static let photonMenuStateKeys: Set<String> = [
        "photon", "hud", "bright", "sharp", "grain", "chrome", "chrome-filter", "negativ",
    ]

    // mpv 0.41.0 common/msg.c: terminal time prefix is [%10.6f].
    // Compiled once only for media-telemetry builds; disabled path is unchanged.
    private static let mediaTimestampPrefix: NSRegularExpression? = Diag.mediaTelemetryEnabled
        ? try? NSRegularExpression(pattern: #"^\s*\[\s*[0-9]+(?:\.[0-9]+)?\]\s*"#)
        : nil

    private static func photonMenuState(from line: String) -> (String, Bool)? {
        let marker = "gor-photon-menu:"
        guard let range = line.range(of: marker) else { return nil }
        let fields = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "=", omittingEmptySubsequences: false)
        guard fields.count == 2, photonMenuStateKeys.contains(String(fields[0])),
              fields[1] == "0" || fields[1] == "1" else { return nil }
        return (String(fields[0]), fields[1] == "1")
    }



    var torrentProcess: Process?
    var torrentTitle: String = ""
    var currentTorrentURL: String = ""
    var lastMagnetURL: String = ""

    var torrentStdinPipe: Pipe?
    var torrentStdoutPipe: Pipe?
    var torrentStderrPipe: Pipe?
    weak var torrentBrowserPanel: ArchiveBrowserPanel?
    var magnetBrowser: MagnetBrowserController?
    /// Survives the magnet panel (it is discarded on every pick); owns the
    /// armed next-episode advance between a pick and its playback EOF.
    var magnetEpisodeTracker = MagnetEpisodeTracker()

    var megaRelayProcess: Process?
    var megaStdoutPipe: Pipe?
    var megaStderrPipe: Pipe?
    
    // I13: prevent a second stdout redirect or launch sequence.
    private static var hasLaunched = false

    var pendingRestart = false {
        didSet {
            quitWatchdogState.updateRestart(pendingRestart)
            quitDebug("pendingRestart old=\(oldValue) new=\(pendingRestart)")
        }
    }

    private var isQuittingDeliberately = false
    private var quitReplyPending = false
    private var quitApproved = false
    private var quitMusicDrainStarted = false
    private var quitMusicDrainFinished = false
    private enum QuitMusicResult: String { case termExit = "term-exit", killExit = "kill-exit", timeoutStillRunning = "timeout-still-running" }
    private var quitMusicResult: QuitMusicResult?
    private var quitMusicCapturedPID: pid_t?
    private var quitMusicDrainWaiters: [() -> Void] = []
    private var quitRequestEpoch: UInt64 = 0
    private final class QuitWatchdogState {
        private let lock = NSLock()
        private var phase = 0 // 0 idle, 1 pending, 2 cleanup, 3 finished, 4 emergency
        private var finishedAt: TimeInterval = 0
        private var epoch: UInt64 = 0
        private var restartClaimed = false
        // 176a/q5: arm-time freeze of the restart decision. After freezeRestart,
        // the arm-time value is the only value either restart path can observe;
        // a mid-teardown pendingRestart flip is unapproved and never restarts.
        private var restartFrozen = false
        private var frozenRestartRequested = false
        private var restartRequested = false
        private var emergencyRestartGranted = false
        private var timedOutMusicPID: pid_t?
        func publishMusicTimeout(_ pid: pid_t?) {
            lock.lock(); timedOutMusicPID = pid; lock.unlock()
        }
        func musicTimeoutPID() -> pid_t? {
            lock.lock(); defer { lock.unlock() }
            return timedOutMusicPID
        }
        func arm(epoch: UInt64) {
            lock.lock(); self.epoch = epoch; phase = 1; lock.unlock()
        }
        func approve(epoch: UInt64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard self.epoch == epoch, phase == 1 else { return false }
            phase = 2
            return true
        }
        func finish(epoch: UInt64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard self.epoch == epoch, phase == 2 else { return false }
            phase = 3
            finishedAt = ProcessInfo.processInfo.systemUptime
            return true
        }
        func remainingPostCleanupDelay(epoch: UInt64) -> TimeInterval {
            lock.lock(); defer { lock.unlock() }
            guard self.epoch == epoch, phase == 3 else { return 0 }
            return max(0, finishedAt + 2.0 - ProcessInfo.processInfo.systemUptime)
        }
        func claimEmergency(epoch: UInt64) -> Int {
            lock.lock(); defer { lock.unlock() }
            guard self.epoch == epoch, phase == 1 || phase == 2 || phase == 3 else { return 0 }
            if phase == 3, ProcessInfo.processInfo.systemUptime < finishedAt + 2.0 { return -1 }
            let claimedPhase = phase
            phase = 4
            if claimedPhase != 3, restartRequested, !restartClaimed {
                restartClaimed = true
                emergencyRestartGranted = true
            }
            return claimedPhase
        }
        func cleanupAllowed(epoch: UInt64) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return self.epoch == epoch && phase == 2
        }
        func takeEmergencyRestart() -> Bool {
            lock.lock(); defer { lock.unlock() }
            let granted = emergencyRestartGranted
            emergencyRestartGranted = false
            return granted
        }
        func updateRestart(_ requested: Bool) {
            lock.lock(); defer { lock.unlock() }
            // 176a/q5: post-freeze writes are late flips; the arm-time value stands.
            guard !restartFrozen else { return }
            restartRequested = requested
        }
        func freezeRestart(_ requested: Bool) {
            lock.lock(); defer { lock.unlock() }
            guard !restartFrozen else { return }
            restartFrozen = true
            frozenRestartRequested = requested
        }
        func claimRestart() -> Bool {
            lock.lock(); defer { lock.unlock() }
            let requested = restartFrozen ? frozenRestartRequested : restartRequested
            guard requested, !restartClaimed else { return false }
            restartClaimed = true
            return true
        }
    }
    private let quitWatchdogState = QuitWatchdogState()
    private let quitChildKiller = QuitChildKiller.shared
    private let quitWatchdogQueue = DispatchQueue(label: "gor.quit.watchdog", qos: .userInitiated)
    private var quitDeadlineWorkItem: DispatchWorkItem?
    
    let ipcPath   = NSTemporaryDirectory() + "pp-\(ProcessInfo.processInfo.processIdentifier).sock"
    let videoPath: String

    private var terminationSignalSources: [DispatchSourceSignal] = []

    override init() {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        videoPath = args.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? ""
        
        super.init()
        
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: DispatchQueue.global(qos: .userInitiated))
            source.setEventHandler {
                // SIGTERM/INT/HUP stop owned players without waiting for UI
                // startup, fades, or a blocked AppKit main queue.
                MPVLifeline.closeForTerminationSignal()
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            source.resume()
            terminationSignalSources.append(source)
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSleep()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleWakeUp()
        }
    }
    
    // I3: launch the app bundle for TCC, not the bare mpv binary.
    func applicationDidFinishLaunching(_ n: Notification) {
        guard StagedRunPaths.prepare() else { quitDebug("staged prepare failed"); exit(1) }
        guard !Self.hasLaunched else { return }
        Self.hasLaunched = true

        Thread.current.qualityOfService = .userInteractive
        DisplayHeadroomDiag.start()
        ThreadCpuDiag.start()  // diagnostic: set ThreadCpuDiag.enabled = false to turn off
        MainThreadDiag.start()  // diagnostic: main run loop busy time and counted callbacks
        installWindowClampTrigger()  // gor 514 trigger/clamp (candidate v4)

        mainThreadPriorityActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "UI thread must stay responsive alongside mpv's elevated-QoS decode/tone-map work"
        )

        if let bundleID = Bundle.main.bundleIdentifier {
            let ownPID = ProcessInfo.processInfo.processIdentifier
            func liveOthers() -> [NSRunningApplication] {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                    .filter { $0.processIdentifier != ownPID && !$0.isTerminated }
            }
            var others = liveOthers()
            if !others.isEmpty {
                // Relaunch may arrive while the old instance is still exiting.
                // A fresh quit token means the other instance is mid-quit: wait
                // out its teardown instead of losing the relaunch at 3s.
                // Without a token the old instance is healthy: keep the
                // historical 3s duplicate behavior. Never start mpv or enter
                // shared-resource startup while another instance is alive.
                let budget = Self.restartWaitBudget(token: Self.readQuitToken(), otherPIDs: others.map { $0.processIdentifier }, now: Date().timeIntervalSince1970)
                quitDebug("startup duplicate wait others=\(others.map { $0.processIdentifier }) budget=\(budget)")
                let deadline = ProcessInfo.processInfo.systemUptime + budget
                while !others.isEmpty && ProcessInfo.processInfo.systemUptime < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                    others = liveOthers()
                }
                if let existing = others.first {
                    quitDebug("startup duplicate retained existingPID=\(existing.processIdentifier); activate and exit")
                    if !StagedRunPaths.active && !NoActivate.suppressAutomatic { existing.activate(options: [.activateAllWindows]) }
                    exit(0)
                }
                Self.consumeQuitToken()
                quitDebug("startup takeover: other instances exited")
            }
        }

        let logPath = StagedRunPaths.tmp("/tmp/gor_direct.log")
        // Append, not truncate: build.sh tee-writes this log before launch
        // (support lad's half) - "w" used to erase the build half.
        let writerURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/gor-log-writer")
        var timestamp = true
        var cpuInfo = true
        if let url = Bundle.main.url(forResource: "gor-log-config", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: Bool] {
            timestamp = config["timestamp"] ?? true
            cpuInfo = config["cpu_info"] ?? true
        }
        let writer = Process()
        let pipe = Pipe()
        writer.executableURL = writerURL
        writer.arguments = ["--quiet", "--timestamp", String(timestamp), "--cpu-info", String(cpuInfo)] + ["--output", logPath]
        writer.standardInput = pipe
        writer.standardOutput = FileHandle.nullDevice
        writer.standardError = FileHandle.nullDevice
        writer.terminationHandler = { process in
            if process.terminationStatus != 0 {
                // Independent unified logging remains usable after the pipe fails.
                NSLog("[GOR] log writer exited unexpectedly; captured output may be lost")
            }
        }
        do {
            try writer.run()
            signal(SIGPIPE, SIG_IGN)
            guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0,
                  dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            pipe.fileHandleForWriting.closeFile()
            pipe.fileHandleForReading.closeFile()
            logWriterProcess = writer
        } catch {
            // Preserve diagnostics if the optional writer cannot launch.
            freopen(logPath, "a", stdout)
            freopen(logPath, "a", stderr)
            fputs("[GOR] log telemetry unavailable: writer launch failed\n", stderr)
        }
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        fflush(stdout)

        print("[GOR] bundleID: \(Bundle.main.bundleIdentifier ?? "nil"), path: \(Bundle.main.bundlePath), executable: \(CommandLine.arguments[0])")
        // K8(b): build identity line, written on every launch (including "unknown").
        print(BuildID.logLine(BuildID.value()))
        
        NSApp.setActivationPolicy(StagedRunPaths.active ? .prohibited : .regular)
        if !StagedRunPaths.active && !NoActivate.suppressAutomatic { NSApp.activate(ignoringOtherApps: true) }
        
        ProcessInfo.processInfo.disableAutomaticTermination("mpv ipc sync active")
        
        buildMenuBar()
        
        try? FileManager.default.removeItem(atPath: StagedRunPaths.tmp("/tmp/gor_watch_later"))
        try? FileManager.default.createDirectory(atPath: StagedRunPaths.tmp("/tmp/gor_watch_later"), withIntermediateDirectories: true)
        
        if !StagedRunPaths.active, let tmpItems = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") {
            for item in tmpItems where item.hasPrefix("gor-chrome-")
                || item.hasPrefix("hidden_mpv_") || item.hasPrefix("crop_frame_") {
                try? FileManager.default.removeItem(atPath: "/tmp/\(item)")
            }
        }

        if !StagedRunPaths.active { OrphanSweep.sweep(vendorExecutables: [
            GORResources.vendorPath("mpv/bin/mpv"), GORResources.vendorPath("node/node")
        ], nodeExecutable: GORResources.vendorPath("node/node"), nodeScripts: [
            GORResources.vendorPath("wt_server/wt_server.mjs"),
            GORResources.vendorPath("mega_relay/mega_relay.mjs")
        ]) { [weak self] line in self?.quitDebug(line) } }

        
        try? FileManager.default.removeItem(atPath: ipcPath)
        launchMPV(file: videoPath.isEmpty ? nil : videoPath)

        if !StagedRunPaths.active { installMPVOutputDeviceListener() }

        if !StagedRunPaths.active { setupEventTap() }
        
        let args = CommandLine.arguments
        if args.contains("--music") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.controller?.toggleMusicMode()
            }
        }
        
        ArchiveLibrary.shared.load()
    }

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    func routeRandomKey() {
        if controller?.isPlaying == true {
            menuRandomSeek()
        } else {
            controller?.randomPlaylistEntry()
        }
    }

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    func menuRandomSeek() {
        guard let c = controller, c.duration > 1 else { return }
        let buckets = 20
        guard let bucket = ArchiveRandom.shared.drawIndex(count: buckets, session: "random-seek"),
              let offset = ArchiveRandom.shared.chooseIndex(count: 1000) else { return }
        c.seek(to: (Double(bucket) + Double(offset) / 1000.0) / Double(buckets))
    }

    /// The frontmost searchable browser panel (file browser, archive, magnet
    /// results) in front-to-back window order - the Cmd+F target. Panels are
    /// nested inside container views, so the scan recurses. A search field's
    /// own NSPanel is never itself searchable, so panel windows are skipped by
    /// the type checks, not by window filtering.
    func frontmostSearchablePanel() -> NSView? {
        func deepFind(_ v: NSView) -> NSView? {
            if v is FileBrowserPanel || v is ArchiveBrowserPanel || v is MagnetResultsPanel { return v }
            for s in v.subviews { if let hit = deepFind(s) { return hit } }
            return nil
        }
        for win in NSApp.orderedWindows {
            guard let cv = win.contentView else { continue }
            if let hit = deepFind(cv) { return hit }
        }
        return nil
    }

    func setupEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let selfPtr = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()

                guard NSApp.isActive else {
                    return Unmanaged.passRetained(event)
                }

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if selfPtr.isShowingInputPanel || PanelKeyOwnership.shared.panelOwnsKey {
                        return Unmanaged.passRetained(event)
                    }
                    if let tap = selfPtr.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown else { return Unmanaged.passRetained(event) }

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

                if selfPtr.isShowingInputPanel || PanelKeyOwnership.shared.panelOwnsKey {
                    return Unmanaged.passRetained(event)
                }

                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
                if !flags.contains(.maskCommand) && !flags.contains(.maskShift) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate) && keyCode == 15 {
                    DispatchQueue.main.async { selfPtr.routeRandomKey() }
                    return nil
                }

                if flags.contains(.maskCommand) && keyCode == 31 {
                    selfPtr.isShowingInputPanel = true
                    DispatchQueue.main.async { selfPtr.openFile() }
                    return nil
                }
                
                if flags.contains(.maskCommand) && flags.contains(.maskShift) && keyCode == 0 {
                    selfPtr.isShowingInputPanel = true
                    DispatchQueue.main.async { selfPtr.openArchive() }
                    return nil
                }

                if flags.contains(.maskCommand) && keyCode == 32 {
                    selfPtr.isShowingInputPanel = true
                    DispatchQueue.main.async { selfPtr.menuOpenURL() }
                    return nil
                }

                if flags.contains(.maskCommand) && keyCode == 17 {
                    DispatchQueue.main.async { selfPtr.menuIptvMode() }
                    return nil
                }

                if flags.contains(.maskShift) && !flags.contains(.maskCommand) && keyCode == 12 {
                    DispatchQueue.main.async { selfPtr.menuRestartQuit() }
                    return nil
                }

                if flags.contains(.maskShift) && NSApp.isActive {
                    let numberKeys: [Int64: Int] = [
                        18:1, 19:2, 20:3, 21:4, 23:5, 22:6, 26:7, 28:8, 25:9, 29:0
                    ]
                    if let number = numberKeys[keyCode] {
                        DispatchQueue.main.async {
                            if number == 0 {
                                selfPtr.controller?.subtitleView.toggleRandomMode()
                            } else {
                                selfPtr.controller?.subtitleView.moveToDefaultPosition(number)
                            }
                        }
                        return nil
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    

    // MARK: - Writable app-support paths (packaging interface)

    /// One-time user-visible notice for playback-affecting vendor absence.
    /// Logs alone are too quiet when the player cannot start; still once
    /// per launch (no alert spam).
    private static var vendorAssetsNoticeShown = false
    static func notifyVendorAssetsMissingOnce() {
        guard !vendorAssetsNoticeShown else { return }
        vendorAssetsNoticeShown = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "gor vendor assets not found"
            alert.informativeText = "Playback is unavailable: no real Resources/vendor next to gor.app (daily layout) or inside the app (DMG layout)."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // A dev source path is explicit and never inferred from a nearby app.
    static func devVendorRoot() -> URL? {
        let fm = FileManager.default
        let setting = StagedRunPaths.support(fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("gor/dev-source-root.txt")
        guard let value = try? String(contentsOf: setting, encoding: .utf8),
              let firstLine = value.split(whereSeparator: \.isNewline).first else { return nil }
        let raw = String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("/"), !raw.contains("\0") else { return nil }
        let root = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        let vendor = root.appendingPathComponent("Resources/vendor", isDirectory: true)
        guard fm.fileExists(atPath: vendor.path) else {
            NSLog("[gor] dev source invalid; Resources/vendor not found")
            return nil
        }
        return vendor
    }

    /// Writable home for mpv's config dir. The bundled vendor/mpv is sealed
    /// with the app, but photon writes generated GLSL and mpv writes its GPU
    /// shader cache into the config dir. Every launch re-seeds the bundled
    /// defaults into Application Support (fresh scripts per build), skipping
    /// the generated subtrees (shader/, cache/) that only exist locally.
    enum ScriptsSeedResult { case installed, failedOldIntact, failedBroken }
    static let requiredLua = ["photon.lua", "photon-common.lua", "photon-grain.lua", "photon-hud.lua", "autoload.lua"]
    static func seedLuaScripts(from srcIn: URL, into dst: URL, parent: URL) -> ScriptsSeedResult {
        let fm = FileManager.default
        let tmp = parent.appendingPathComponent(".seed-\(UUID().uuidString)-scripts")
        let backup = parent.appendingPathComponent(".old-\(UUID().uuidString)-scripts")
        func log(_ m: String) { NSLog("[gor] scripts seed: %@", m); Diag.mediaRecord("SEED " + m) }
        func fail(_ op: String, _ code: Int) -> Error {
            log("FAILED op=\(op) code=\(code)")
            return NSError(domain: "gor.mpv.seed", code: code)
        }
        func posix(_ op: String, _ e: Int32) -> Error {
            log("FAILED op=\(op) errno=\(e)")
            return NSError(domain: NSPOSIXErrorDomain, code: Int(e))
        }
        func info(_ u: URL) throws -> stat? {
            var st = stat()
            if lstat(u.path, &st) == 0 { return st }
            let e = errno
            if e == ENOENT { return nil }
            throw posix("lstat-\(u.lastPathComponent)", e)
        }
        // Includes every entry name, including links, without traversing links.
        // Used for rollback readback, where old non-Lua files must be preserved.
        func names(_ root: URL, strict: Bool = false, source: Bool = false) throws -> [String] {
            var failure: Error?
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, e in failure = e; return false }) else { throw fail("enumerate", 1) }
            var out: [String] = []
            for case let u as URL in en {
                guard let st = try info(u) else { throw fail("entry-disappeared", 2) }
                let kind = st.st_mode & S_IFMT
                let rel = String(u.path.dropFirst(root.path.count + 1))
                if kind == S_IFLNK {
                    en.skipDescendants()
                    if source {
                        if requiredLua.contains(rel) { throw fail("required-symlink-\(rel)", 3) }
                        log("SKIPPED symlink file=\(rel)"); continue
                    }
                    if strict { throw fail("verify-symlink-\(rel)", 4) }
                }
                if strict || source {
                    if kind == S_IFDIR { continue }
                    guard kind == S_IFREG else { throw fail("kind-changed-\(rel)", 5) }
                }
                out.append(rel)
            }
            if let failure { log("FAILED op=enumerate-error code=\((failure as NSError).code)"); throw failure }
            return out.sorted()
        }
        func digest(_ url: URL) throws -> String {
            guard let st = try info(url), (st.st_mode & S_IFMT) == S_IFREG else { throw fail("kind-changed-\(url.lastPathComponent)", 6) }
            return SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        }
        // Live dev-directory links are legitimate; dangling/unreadable entries are not.
        func usable(_ root: URL) -> Bool {
            var st = stat()
            guard stat(root.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return false }
            for rel in requiredLua {
                let file = root.appendingPathComponent(rel).path
                guard stat(file, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
                      fm.isReadableFile(atPath: file) else { return false }
            }
            return true
        }
        var oldStat: stat?
        var oldNames: [String] = []
        var snapshotReady = false
        var mutated = false
        var movedOld = false
        var newPlaced = false
        func oldIntact() -> Bool {
            guard snapshotReady else { return false }
            do {
                let now = try info(dst)
                guard let old = oldStat else { if let _ = now { return false }; return true }
                guard let now, old.st_dev == now.st_dev, old.st_ino == now.st_ino,
                      (old.st_mode & S_IFMT) == (now.st_mode & S_IFMT) else { return false }
                if (old.st_mode & S_IFMT) == S_IFDIR { return try names(dst) == oldNames }
                return true
            } catch { return false }
        }
        func restore() -> Bool {
            if newPlaced {
                let bad = parent.appendingPathComponent(".bad-\(UUID().uuidString)-scripts")
                if rename(dst.path, bad.path) != 0 {
                    let e = errno; log("ROLLBACK FAILED op=retire-new errno=\(e) previous scripts kept at \(backup.lastPathComponent)")
                    return false
                }
                newPlaced = false // quarantine retained; never delete an unverified tree
            }
            if movedOld {
                do {
                    if let _ = try info(dst) {
                        // Never overwrite an unexpected entry. Readback below must prove identity.
                    } else {
                        if rename(backup.path, dst.path) != 0 {
                            let e = errno; log("ROLLBACK FAILED op=restore-old errno=\(e) previous scripts kept at \(backup.lastPathComponent)")
                            return false
                        }
                        movedOld = false
                    }
                } catch { return false }
            }
            if oldIntact() {
                if oldStat != nil { log("ROLLBACK OK previous scripts identity/kind/names verified") }
                else { log("ROLLBACK UNVERIFIED no previous installation") }
                return true
            }
            log("ROLLBACK UNVERIFIED previous scripts kept at \(backup.lastPathComponent)")
            return false
        }
        do {
            oldStat = try info(dst)
            if let old = oldStat, (old.st_mode & S_IFMT) == S_IFDIR { oldNames = try names(dst) }
            snapshotReady = true
            let src = srcIn.resolvingSymlinksInPath() // source read only
            guard let root = try info(src), (root.st_mode & S_IFMT) == S_IFDIR else { throw fail("source-kind", 7) }
            for rel in requiredLua {
                guard let st = try info(src.appendingPathComponent(rel)), (st.st_mode & S_IFMT) == S_IFREG else { throw fail("required-not-regular-\(rel)", 8) }
            }
            let lua = try names(src, source: true).filter { $0.hasSuffix(".lua") }
            var hashes: [String: String] = [:]
            for rel in lua { hashes[rel] = try digest(src.appendingPathComponent(rel)) }
            func verify(_ root: URL) throws {
                let files = try names(root, strict: true)
                guard files == lua else { throw fail("verify-exact-inventory", 9) }
                for rel in requiredLua {
                    guard let st = try info(root.appendingPathComponent(rel)), (st.st_mode & S_IFMT) == S_IFREG else { throw fail("verify-required-\(rel)", 10) }
                }
                for rel in lua {
                    guard try digest(root.appendingPathComponent(rel)) == hashes[rel] else { throw fail("verify-sha256-\(rel)", 11) }
                }
            }
            try fm.createDirectory(at: tmp, withIntermediateDirectories: false)
            for rel in lua {
                let input = src.appendingPathComponent(rel)
                guard let st = try info(input), (st.st_mode & S_IFMT) == S_IFREG else { throw fail("source-kind-changed-\(rel)", 12) }
                let target = tmp.appendingPathComponent(rel)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: input, to: target)
            }
            try verify(tmp)
            guard oldIntact() else { throw fail("old-changed-before-swap", 13) }
            if oldStat != nil {
                if rename(dst.path, backup.path) != 0 { let e = errno; throw posix("rename-old-aside", e) }
                movedOld = true
                mutated = true
                guard let saved = try info(backup), let old = oldStat,
                      saved.st_dev == old.st_dev, saved.st_ino == old.st_ino,
                      (saved.st_mode & S_IFMT) == (old.st_mode & S_IFMT) else { throw fail("backup-identity", 14) }
            }
            if rename(tmp.path, dst.path) != 0 { let e = errno; throw posix("rename-new-into-place", e) }
            newPlaced = true
            mutated = true
            try verify(dst)
            if movedOld {
                do { try fm.removeItem(at: backup); movedOld = false }
                catch { log("BACKUP cleanup failed code=\((error as NSError).code) kept at \(backup.lastPathComponent)") }
            }
            log("OK lua=\(lua.count) nonLua=0 sha256=verified")
            return .installed
        } catch {
            log("FAILED op=seed code=\((error as NSError).code) domain=\((error as NSError).domain)")
            try? fm.removeItem(at: tmp)
            // A failed snapshot does not imply a broken installation: no dst mutation occurred.
            // Recheck the already observed entry identity without requiring enumeration.
            if !mutated, let old = oldStat {
                do {
                    if let now = try info(dst), old.st_dev == now.st_dev, old.st_ino == now.st_ino,
                       (old.st_mode & S_IFMT) == (now.st_mode & S_IFMT) {
                        guard usable(dst) else {
                            log("FAILED op=old-not-usable")
                            return .failedBroken
                        }
                        log("FAILED op=\(snapshotReady ? "prepare" : "snapshot"), nothing changed")
                        log("FALLBACK none: running with previously installed scripts; non-Lua files may remain")
                        return .failedOldIntact
                    }
                } catch { log("FAILED op=unchanged-readback code=\((error as NSError).code)") }
            }
            // At most two restore attempts, never an unbounded launch-time retry.
            if (restore() || restore()), oldStat != nil {
                guard usable(dst) else {
                    log("FAILED op=old-not-usable")
                    return .failedBroken
                }
                log("FALLBACK none: running with previously installed scripts; non-Lua files may remain")
                return .failedOldIntact
            }
            log("FAILED BROKEN launch blocked previous scripts kept at \(backup.lastPathComponent)")
            return .failedBroken
        }
    }

    // Resolve only; no seeding, filesystem writes or selection of a source tree.
    static func writableMPVConfigDestination() -> URL {
        StagedRunPaths.support(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("gor", isDirectory: true)
            .appendingPathComponent("mpv", isDirectory: true)
    }

    static func writableMPVConfigDir() -> String? {
        let fm = FileManager.default
        let dest = writableMPVConfigDestination()
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let candidate = devVendorRoot()?.appendingPathComponent("mpv", isDirectory: true)
        let dev = candidate.flatMap { mpvRoot -> URL? in
            let required = ["mpv.conf"] + requiredLua.map { "scripts/" + $0 }
            let missing = required.filter { rel in
                let path = mpvRoot.appendingPathComponent(rel).path
                var st = stat()
                return lstat(path, &st) != 0 || (st.st_mode & S_IFMT) != S_IFREG || !fm.isReadableFile(atPath: path)
            }
            guard missing.isEmpty else {
                NSLog("[gor] dev source rejected; missing/non-regular: %@", missing.joined(separator: ", "))
                return nil
            }
            return mpvRoot
        }
        let source = dev ?? GORResources.vendor()?
            .appendingPathComponent("mpv", isDirectory: true)
        if let source {
            do {
                let items = try fm.contentsOfDirectory(atPath: source.path)
                var failed: [String] = []
                guard items.contains("scripts") else {
                    Diag.mediaRecord("SEED FAILED BROKEN op=source-scripts-missing launch blocked")
                    return nil
                }
                for item in items where item != "shader" && item != "cache" {
                    let src = source.appendingPathComponent(item)
                    let dst = dest.appendingPathComponent(item)
                    do {
                        if item == "scripts" {
                            switch AppDelegate.seedLuaScripts(from: src, into: dst, parent: dest) {
                            case .installed: break
                            case .failedOldIntact: failed.append(item)
                            case .failedBroken:
                                Diag.mediaRecord("SEED FAILED BROKEN launchMPV blocked")
                                return nil
                            }
                        } else if dev != nil {
                            // Build the link beside the target, then swap it in. The old
                            // item is moved aside first when a plain rename cannot replace
                            // it (e.g. a real directory from a bundled seed) and put back
                            // if the swap fails, so a failed link never loses the old config.
                            let tmp = dest.appendingPathComponent(".seed-\(UUID().uuidString)-\(item)")
                            do {
                                try fm.createSymbolicLink(at: tmp, withDestinationURL: src)
                                if rename(tmp.path, dst.path) != 0 {
                                    let renameErr = errno
                                    let hasOld = (try? fm.attributesOfItem(atPath: dst.path)) != nil
                                    guard hasOld else {
                                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(renameErr))
                                    }
                                    let backup = dest.appendingPathComponent(".old-\(UUID().uuidString)-\(item)")
                                    try fm.moveItem(at: dst, to: backup)
                                    do {
                                        try fm.moveItem(at: tmp, to: dst)
                                    } catch {
                                        try? fm.moveItem(at: backup, to: dst)
                                        throw error
                                    }
                                    try? fm.removeItem(at: backup)
                                }
                            } catch {
                                try? fm.removeItem(at: tmp)
                                throw error
                            }
                        } else {
                            // Copy to a sibling first; the existing item is replaced only
                            // after the copy succeeded, so a failed copy never leaves the
                            // config dir without it.
                            let tmp = dest.appendingPathComponent(".seed-\(UUID().uuidString)-\(item)")
                            do {
                                try fm.copyItem(at: src, to: tmp)
                                if fm.fileExists(atPath: dst.path) {
                                    _ = try fm.replaceItemAt(dst, withItemAt: tmp)
                                } else {
                                    try fm.moveItem(at: tmp, to: dst)
                                }
                            } catch {
                                try? fm.removeItem(at: tmp)
                                throw error
                            }
                        }
                    } catch {
                        failed.append(item)
                        NSLog("[gor] mpv config seed failed for %@: %@", item, error.localizedDescription)
                    }
                }
                if !failed.isEmpty {
                    NSLog("[gor] mpv config seed incomplete (%d of %d items): %@",
                          failed.count, items.count, failed.joined(separator: ", "))
                }
            } catch {
                NSLog("[gor] mpv config seed: cannot list %@: %@", source.path, error.localizedDescription)
                Diag.mediaRecord("SEED FAILED BROKEN op=list-source launch blocked")
                return nil
            }
        } else {
            NSLog("[gor] mpv config seed: no source (no dev root, no bundled vendor/mpv)")
            Diag.mediaRecord("SEED FAILED BROKEN op=no-source launch blocked")
            return nil
        }
        return dest.path
    }

    /// Writable staged copy of the vendored yt-dlp. `yt-dlp -U` rewrites the
    /// binary in place, which a sealed bundle forbids, so updates run against
    /// this copy. A newer vendored build replaces the staged copy.
    static func stagedYtDlpPath() -> String {
        let fm = FileManager.default
        // Resolved via GORResources: vendored path when vendor/ resolves,
        // conventional sibling path when not (miss already logged; the copy
        // below then fails cleanly and the callers' fileExists checks degrade).
        let vendored = GORResources.vendorPath("yt-dlp")
        let support = StagedRunPaths.support(fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("gor", isDirectory: true)
        let staged = support.appendingPathComponent("yt-dlp").path
        func mtime(_ p: String) -> Date {
            (try? fm.attributesOfItem(atPath: p)[.modificationDate] as? Date) ?? .distantPast
        }
        if !fm.fileExists(atPath: staged) || mtime(vendored) > mtime(staged) {
            try? fm.createDirectory(at: support, withIntermediateDirectories: true)
            try? fm.removeItem(atPath: staged)
            guard (try? fm.copyItem(atPath: vendored, toPath: staged)) != nil else { return vendored }
        }
        return staged
    }

    // NOT_APPLIED F9/F10 trial: default OFF until native startup/exit tests.
    private func armStartupExitLogCollector(configDir: String) {
        guard !StagedRunPaths.active else { return }
        if let helper = Bundle.main.resourceURL?.appendingPathComponent("gor-session-log-helper.py"),
           FileManager.default.isReadableFile(atPath: helper.path) {
            let watcher = Process()
            watcher.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            watcher.arguments = [helper.path, "arm", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath, configDir, SessionLogPaths.root.path]
            watcher.standardInput = FileHandle.nullDevice
            watcher.standardOutput = FileHandle.nullDevice
            watcher.standardError = FileHandle.standardError
            watcher.terminationHandler = { process in
                if process.terminationStatus != 0 { NSLog("[GOR] exit log watcher failed to arm") }
            }
            do {
                try watcher.run()
            } catch { NSLog("[GOR] exit log watcher unavailable: %@", error.localizedDescription) }
        }
    }

    // MARK: - MPV Launch
    private var goravHost: GorAVPlayerHost?
    private(set) var activePlayerEngine: PlayerEngine = .mpv
    var goravCurrentTime: Double? { MainActor.assumeIsolated { goravHost?.currentTime } }
    /// native104 (D-stage app gate; additive READ-ONLY seam, no behavior
    /// change): the gate driver observes/drives the NORMAL path's own gorav
    /// host through the production host's existing native87 gate surface.
    /// Same isolation shape as goravCurrentTime; goravHost stays private.
    var goravHostForAppGate: GorAVPlayerHost? { MainActor.assumeIsolated { goravHost } }
    var goravSourceURL: URL? { MainActor.assumeIsolated { goravHost?.sourceURL } }
    var goravPreparedPlayback: PreparedShotPlayback? { MainActor.assumeIsolated { goravHost?.preparedPlayback } }
    private var engineSelectionOverride: PlayerEngine?
    var selectedPlayerEngine: PlayerEngine {
        engineSelectionOverride ?? PlayerEngine.selected(environment: ProcessInfo.processInfo.environment,
            saved: UserDefaults.standard.string(forKey: PlayerEngine.preferenceKey))
    }
    @objc func menuPlayerEngine(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let engine = PlayerEngine(rawValue: value) else { return }
        engineSelectionOverride = engine
        UserDefaults.standard.set(engine.rawValue, forKey: PlayerEngine.preferenceKey)
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        print("[engine] selected=\(engine.rawValue); persisted; applies to next open")
        controller?.spineUI.showMPVOSD("engine: \(engine.rawValue)", force: true)
    }
    func launchMPV(file: String?) {
        let route = PlayerBackendRoute.resolve(selectedPlayerEngine)
        print("[engine] requested=\(route.requested.rawValue) active=\(route.active.rawValue)\(route.fallbackReason.map { "; " + $0 } ?? "")")
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        if route.active == .gorav && ProcessInfo.processInfo.environment["GOR_ENGINE"] != "gorav" {
            goravOfferLocalFile(file: file)
            return
        }
        activePlayerEngine = route.active
        route.launch(file: file, gorav: { [weak self] file in
            // The route callback is synchronous/nonisolated. Hop only the
            // gorav host lifecycle to its actor; leave the mpv launch untouched.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.goravHost?.closeSession()
                let host = GorAVPlayerHost()
                self.goravHost = host
                host.open(file: file)
            }
        }, mpv: { [unowned self] file in self.launchMPVImplementation(file: file) })
    }
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    private var goravOfferInFlight = false
    private func goravOfferLocalFile(file: String?) {
        guard let file, !file.isEmpty else { goravFallbackToMPV(file: file, reason: "no file"); return }
        // A-D successor reading (2026-11-15): the ffprobe spawn + JSON parse run
        // OFF the main thread and the probe itself is hard-bounded; a slow disk
        // or a stuck ffprobe must never freeze the open path. The fallback hops
        // back to main, the thread every launchMPV caller uses.
        guard !goravOfferInFlight else { return }
        goravOfferInFlight = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = GorAVLocalOffer.offer(path: file)
            DispatchQueue.main.async {
                guard let self else { return }
                self.goravOfferInFlight = false
                switch outcome {
                case .refused(let reason):
                    self.goravFallbackToMPV(file: file, reason: reason)
                case .admitted(let detail):
                    self.goravFallbackToMPV(file: file, reason: "admitted (\(detail)); in-window gorav host pending")
                case .probeUnavailable(let reason):
                    self.goravFallbackToMPV(file: file, reason: reason)
                }
            }
        }
    }
    private func goravFallbackToMPV(file: String?, reason: String) {
        activePlayerEngine = .mpv
        print("[engine] gorav -> mpv: \(reason)")
        Diag.mediaRecord("GORAV-FALLBACK \(reason)")
        controller?.spineUI.showMPVOSD("gorav: \(reason) -> mpv", force: true)
        launchMPVImplementation(file: file)
    }
    /// T4 M1 gap 1: gorav stream route. Pre-open admission only - a refusal
    /// returns false and the caller's mpv load path runs untouched; once the
    /// gorav engine accepts the open, its typed refusals never replay on mpv.
    /// The gorav host lifecycle hops to its actor exactly like launchMPV's.
    func goravAdmitAndOpen(url: String, headerCount: Int, subtitleCount: Int, startPos: Double?) -> Bool {
        let route = PlayerBackendRoute.resolve(selectedPlayerEngine)
        guard route.active == .gorav else { return false }
        switch GorAVStreamAdmission.admit(url: url, headerCount: headerCount, subtitleCount: subtitleCount,
                                          startPos: startPos, needsTunnel: TunnelForBlockedHosts.shared.needsTunnel(url)) {
        case .failure(let refusal):
            print("[engine] backend=gorav stream admission refused (\(refusal.rawValue)); mpv path unchanged")
            Diag.mediaRecord("GORAV-FALLBACK stream: \(refusal.rawValue)")
            controller?.spineUI.showMPVOSD("gorav: \(refusal.rawValue) -> mpv", force: true)
            return false
        case .success(let admitted):
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
            guard ProcessInfo.processInfo.environment["GOR_ENGINE"] == "gorav" else {
                print("[engine] gorav stream admitted; in-window host pending, mpv path unchanged")
                Diag.mediaRecord("GORAV-FALLBACK stream admitted; in-window host pending")
                controller?.spineUI.showMPVOSD("gorav: in-window playback pending -> mpv", force: true)
                return false
            }
            activePlayerEngine = .gorav
            print("[engine] requested=\(route.requested.rawValue) active=gorav stream-open")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.goravHost?.closeSession()
                let host = GorAVPlayerHost()
                self.goravHost = host
                host.open(url: admitted)
            }
            return true
        }
    }
    private func launchMPVImplementation(file: String?) {
        photonMenuStates = Self.photonMenuDefaults
        for key in ["bright", "sharp", "grain"] { photonMenuStates[key] = photonEnabled }
        let p = Process()
        guard let mpvPath = findMPV() else {
            NSLog("[gor] playback unavailable: vendor/mpv/bin/mpv unresolved (external assets missing)")
            Self.notifyVendorAssetsMissingOnce()
            return
        }
        p.executableURL = URL(fileURLWithPath: mpvPath)
        p.environment = ProcessInfo.processInfo.environment
        if !StagedRunPaths.active {p.environment?.removeValue(forKey:"GOR_LOG_SESSION_DIR")}

        // Default OFF preserves the installed startup order pending native proof.
        let startupLogBeforeSeed = UserDefaults.standard.bool(forKey: "gor.startupLogBeforeSeed")
        if startupLogBeforeSeed {
            let collectionConfigDir = AppDelegate.writableMPVConfigDestination().path
            armStartupExitLogCollector(configDir: collectionConfigDir)
        }
        guard let configDir = AppDelegate.writableMPVConfigDir() else {
            NSLog("[gor] launchMPV blocked: scripts seed could not prove a usable installation")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Script installation could not be verified. Playback was not started."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        if !startupLogBeforeSeed {
            armStartupExitLogCollector(configDir: configDir)
        }
        Diag.verifyBuildManifest(configDir: configDir)
        // gor-fit.lua (sizes the window before the first frame and animates later size changes) is only used
        // when the seeded scripts folder really holds it; otherwise every size path is the old one.
        PPController.gorFitScriptActive = FileManager.default.isReadableFile(atPath: configDir + "/scripts/gor-fit.lua")
        var args: [String] = [
            "--config-dir=\(configDir)",
            "--input-ipc-server=\(ipcPath)",
            "--idle=yes",
            "--force-window=yes",
            "--keep-open=yes",
            "--no-native-fs",
            // gor 514: the initial window must never overflow the screen, even for a portrait
            // video, because it is visible until the opening fit (GorOpeningFit) corrects it
            // after file-loaded. Was "--geometry=40%+50%+50%": a fixed 40% WIDTH with the height
            // following the video aspect, so 720x1280 opened 819x1456 on a 2048x1280 screen.
            // Now position-only geometry + autofit 40% width / 90% height: landscape opens exactly
            // as before (40% width), portrait is capped at 90% of the usable height, aspect kept.
            // (Reproduced with mpv 0.41 on X11; the Cocoa reference rect is mpv's, not verified.)
            "--geometry=+50%+50%",
            "--autofit=40%x90%",
            "--pause",
            
            "--no-border",
            "--no-osc",
            "--cursor-autohide=no",
            "--cursor-autohide-fs-only=no",
            "--script-opts=osc-visibility=never" + GorOpeningFit.fitScriptOptSuffix(),
            "--osd-level=0",
            "--sub-visibility=no",
            "--sub-scale=\(SubtitleSizePreference.restored() ?? 1)",
            "--macos-app-activation-policy=prohibited",
            "--cover-art-auto=fuzzy",
            "--drag-and-drop=no",
            
            "--cache=yes",
            "--cache-secs=8",
            "--cache-pause-initial=no",
            "--demuxer-max-bytes=128M",
            "--demuxer-max-back-bytes=32M",
            "--demuxer-readahead-secs=10",
            "--prefetch-playlist=no",

            "--audio-buffer=0.5",
            "--ao=coreaudio",
            "--coreaudio-change-physical-format=no",
            "--audio-exclusive=no",
            "--audio-wait-open=0.5",
            "--audio-client-name=gor",
            "--audio-samplerate=48000",
            "--volume=\(Int(PPController.defaultVolume * 100))",
            
            "--msg-level=ffmpeg=fatal,demuxer=fatal,shader=v,statusline=no",
            "--term-status-msg=",
            
            "--save-position-on-quit=no",
            "--watch-later-directory=\(StagedRunPaths.tmp("/tmp/gor_watch_later"))",
        ]
        if let f = file { args.append(f) }
        
        
        let ytdlpPath = AppDelegate.stagedYtDlpPath()
        if FileManager.default.fileExists(atPath: ytdlpPath) {
            args.append("--script-opts=ytdl_hook-ytdl_path=\(ytdlpPath)")
            print("✅ yt-dlp found")
        } else {
            print("❌ yt-dlp NOT found at \(ytdlpPath)")
        }

        let photonScriptsDir = configDir + "/scripts"
        args.append("--script-opts-add=photon-scriptdir=\(photonScriptsDir)")
        args.append("--script-opts-add=photon-menu-enabled=\(photonEnabled ? "true" : "false")")

        args.append("--script-opts-add=gor-diag=\(Diag.mediaTelemetryEnabled ? "true" : "false")")
        if Diag.mediaTelemetryEnabled { args.append("--msg-time=yes") }
        p.arguments = args
        p.qualityOfService = .userInteractive

        let ownedSocket = OwnedPlayerSocket(path: ipcPath)
        p.terminationHandler = { [weak self] _ in
            // Process has exited: independently of queued AppKit shutdown, release its exact owned socket.
            ownedSocket.childExited()
            DispatchQueue.main.async {
                guard self?.isQuittingDeliberately != true else { return }
                self?.stopOverlaySync()
                self?.overlayWin?.orderOut(nil)
                NSApp.terminate(nil)
            }
        }
        
        let mpvStderrPipe = Pipe()
        p.standardOutput = mpvStderrPipe
        p.standardError = mpvStderrPipe
        
        mpvStderrPipe.fileHandleForReading.readabilityHandler = { [weak self, weak p] handle in
            let data = handle.availableData
            // EOF: an empty read repeats forever (busy loop) unless the handler is removed.
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let self, let p else { return }
            self.osdLineBuffer.append(data)
            var lines: [String] = []
            while let nl = self.osdLineBuffer.firstIndex(of: 0x0A) {
                let line = String(data: self.osdLineBuffer[self.osdLineBuffer.startIndex..<nl], encoding: .utf8)
                self.osdLineBuffer.removeSubrange(self.osdLineBuffer.startIndex...nl)
                if let line { lines.append(line) }
            }
            for rawLine in lines {
                // msg-time adds a leading [seconds] field. Strip only that
                // field for consumers; retain the timestamp in the raw log.
                let line: String
                if Diag.mediaTelemetryEnabled, let regex = Self.mediaTimestampPrefix {
                    line = regex.stringByReplacingMatches(in: rawLine, range: NSRange(rawLine.startIndex..., in: rawLine), withTemplate: "")
                } else {
                    line = rawLine
                }
                if line.hasPrefix("AV:") || line.contains("Multiple Dolby Vision RPUs") { continue }
                if let record = SharedDiagnosticRecord.payload(from: line) {
                    _ = BoundedDiskWriter.append(record, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
                }
                print("[mpv] \(rawLine)")
                if line.contains(SharedDiagnosticRecord.marker) { continue }
                if line.contains("3D-REJECTED ") || line.contains("3D-LUA ") {Diag.mediaRecord(line)}

                if let (key, enabled) = Self.photonMenuState(from: line) {
                    DispatchQueue.main.async { [weak self, weak p] in
                        guard let self, let p, self.mpvProcess === p else { return }
                        self.photonMenuStates[key] = enabled
                        if key == "photon" { self.photonEnabled = enabled }
                    }
                    continue
                }

                // Classify diagnostic text, never arbitrary digits in media URLs.
                // Main owns playback identity and the current resume position.
                if Self.isYoutubeOpenFailureDiagnostic(line) {
                    DispatchQueue.main.async { [weak self, weak p] in
                        guard let self, let p, self.mpvProcess === p else { return }
                        self.handleYoutubeOpenFailure()
                    }
                }

                if line.contains("gor-osd:") {
                    let parts = line.components(separatedBy: "gor-osd:")
                    if let raw = parts.last {
                        let clean = raw.replacingOccurrences(
                            of: #"\u{1B}\[[0-9;]*m"#,
                            with: "",
                            options: .regularExpression
                        ).trimmingCharacters(in: .whitespaces)
                        if clean.isEmpty {
                            DispatchQueue.main.async {
                                self.controller?.spineUI.clearMPVOSD(animated: false)
                            }
                        } else {
                            let msg = clean
                            // P4 (card 713): photon-hud.lua's 4Hz frames carry a
                            // "section\t" prefix on every line and always start
                            // "photon\t". Fresh grounding on ffd66a9c: photon-hud
                            // is the only gor-osd producer emitting tabs
                            // (gor_stats.lua has none; wt_server REQ: lines never
                            // reach this routing). These frames belong to the
                            // crop-bounded scrollable renderer (showPhotonHUD):
                            // routing them through showMPVOSD wiped the magnet HUD
                            // every 4Hz and drew rows unbounded past the crop.
                            let isHUDFrame = clean.hasPrefix("photon\t")
                            // photon's own state prints are bare lines
                            // ("photon" / "photoff" / "photoff  (203 nit)");
                            // photon-hud's 4Hz frames always carry a tab.
                            // Only bare lines may move the mirror - HUD frames
                            // used to force it back to true ~250ms after F9
                            // (pass-5 #1).
                            DispatchQueue.main.async { [weak self, weak p] in
                                guard let self, let p, self.mpvProcess === p else { return }
                                if !isHUDFrame {
                                    if clean == "photon" {
                                        self.photonEnabled = true
                                    } else if clean.hasPrefix("photoff") {
                                        self.photonEnabled = false
                                    }
                                }
                                if isHUDFrame {
                                    self.controller?.spineUI.showPhotonHUD(msg)
                                } else {
                                    // Unchanged for every non-HUD message:
                                    // bare "photon"/"photoff" prints stay unanimated.
                                    self.controller?.spineUI.showMPVOSD(msg, animated: !clean.hasPrefix("photon"))
                                }
                            }
                        }
                    }
                }
            }
        }

        do { try MPVLifeline.run(p) } catch { return }
        ScreenCaptureEngine.shared.stopAudioCapture()
        mpvProcess = p
        ScreenCaptureEngine.shared.mpvPID = p.processIdentifier
        setpgid(p.processIdentifier, ProcessInfo.processInfo.processIdentifier)

        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainThreadDiag.count("checkTimer")
            guard let self = self else { return }
            
            ownedSocket.observe()
            if self.controller == nil && FileManager.default.fileExists(atPath: self.ipcPath) {
                let ctrl = PPController(frame: .zero, ipcPath: self.ipcPath)
                self.controller = ctrl
                ctrl.ipcCommand("{\"command\":[\"keybind\",\"Meta+o\",\"ignore\"]}")
            }
            
            self.findMPVWindow()
            
            guard !self.isQuittingDeliberately else { return }

            if let mpv = self.mpvProcess, mpv.isRunning {
                if self.controller != nil && !FileManager.default.fileExists(atPath: self.ipcPath) {
                    MPVLifeline.close(for: mpv)
                    kill(mpv.processIdentifier, SIGKILL)
                    NSApp.terminate(nil)
                }

                if let win = self.overlayWin, !win.isVisible {
                    win.orderFrontRegardless()
                    self.syncOverlay()
                }
            } else if self.mpvProcess != nil {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Default output device → mpv audio-reload

    private func installMPVOutputDeviceListener() {
        removeMPVOutputDeviceListener()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.mpvOutputDeviceChangeGeneration += 1
            let myGeneration = self.mpvOutputDeviceChangeGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.mpvOutputDeviceChangeGeneration == myGeneration else { return }
                self.controller?.ipcCommand("{\"command\":[\"audio-reload\"]}")
            }
        }
        AudioObjectAddPropertyListenerBlock(.system, &address, DispatchQueue.main, block)
        mpvOutputDeviceListenerBlock = block
    }

    private func removeMPVOutputDeviceListener() {
        guard let block = mpvOutputDeviceListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(.system, &address, DispatchQueue.main, block)
        mpvOutputDeviceListenerBlock = nil
    }

    // MARK: - Chromium update (staged for the next signed build)
    static func checkChromiumOnUse(binary: String, force: Bool = false) {
        chromiumUpdateLock.lock()
        if chromiumUpdateInProgress || (chromiumUpdateChecked && !force) {
            chromiumUpdateLock.unlock()
            return
        }
        chromiumUpdateChecked = true
        chromiumUpdateInProgress = true
        chromiumUpdateLock.unlock()

        guard let script = GORResources.vendor()?.appendingPathComponent("update-chromium.py").path else {
            print("[chromium-update] vendor unresolved; update check skipped")
            chromiumUpdateLock.lock()
            chromiumUpdateInProgress = false
            chromiumUpdateLock.unlock()
            return
        }
        let sourceRoot = URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent().path
        DispatchQueue.global(qos: .utility).async {
            defer {
                chromiumUpdateLock.lock()
                chromiumUpdateInProgress = false
                chromiumUpdateLock.unlock()
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = [script, "--binary", binary, "--source-root", sourceRoot]
            let output = Pipe()
            task.standardOutput = output
            task.standardError = output
            do {
                try task.run()
                task.waitUntilExit()
                let bytes = output.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: bytes, encoding: .utf8) ?? ""
                if task.terminationStatus != 0 || message.contains("STAGED:") || force {
                    print("[chromium-update] status=\(task.terminationStatus) \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } catch {
                print("[chromium-update] failed to launch: \(error)")
            }
        }
    }

    @objc func menuCheckChromiumUpdate() {
        guard let binary = GORResources.vendor()?
            .appendingPathComponent(ArchiveConfig.chromiumPathUnderVendor).path,
            FileManager.default.isExecutableFile(atPath: binary) else {
            print("[chromium-update] browser missing")
            return
        }
        AppDelegate.checkChromiumOnUse(binary: binary, force: true)
    }

    // MARK: - YouTube auto-recovery
    static func isYoutubeURL(_ value: String) -> Bool {
        guard let host = URLComponents(string: value)?.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }

    static func isYoutubeOpenFailureDiagnostic(_ line: String) -> Bool {
        // Opening URLs and nested script probes are NOT player failures.
        // For example slices=38455247-40324801 triggered the former contains(403).
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("Failed to open ") || text.hasPrefix("[cplayer] Failed to open ") { return true }
        let pattern = #"^(?:\[(?:https?|tls|ffmpeg(?:/https?)?|ytdl_hook)(?: @ 0x[0-9a-fA-F]+)?\]\s*)?(?:HTTP error 403(?:\s|:|$)|Server returned 403(?:\s|:|$)|ERROR:.*(?:HTTP Error 403:|403 Forbidden))"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // Called at load intent, not after the asynchronous path poll catches up.
    func invalidateYoutubeRecovery() {
        dispatchPrecondition(condition: .onQueue(.main))
        youtubePlaybackGeneration &+= 1
        lastPlayedURL = nil
        lastPlayedSubtitleURLs = []
        youtubeRetryAttempted = false
    }

    func handleYoutubeOpenFailure() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !youtubeRetryAttempted, !ytdlpUpdateInProgress,
              let url = lastPlayedURL, Self.isYoutubeURL(url) else { return }
        youtubeRetryAttempted = true
        ytdlpUpdateInProgress = true
        let generation = youtubePlaybackGeneration
        let playbackProcess = mpvProcess
        let title = lastPlayedTitle
        let subtitles = lastPlayedSubtitleURLs
        let observed = controller?.currentTime ?? 0
        let failurePosition = observed.isFinite && observed > 0 ? observed : (lastPlayedStartPos ?? 0)
        let ytdlpPath = AppDelegate.stagedYtDlpPath()
        guard FileManager.default.fileExists(atPath: ytdlpPath) else {
            print("[yt-dlp-recovery] staged binary missing; no reload")
            ytdlpUpdateInProgress = false
            return
        }
        print("[yt-dlp-recovery] verified player failure; updating extractor")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let update = Process()
            update.executableURL = URL(fileURLWithPath: ytdlpPath)
            update.arguments = ["-U"]
            update.standardOutput = FileHandle.nullDevice
            update.standardError = FileHandle.nullDevice
            var succeeded = false
            do {
                try update.run()
                update.waitUntilExit()
                succeeded = update.terminationStatus == 0
                print("[yt-dlp-recovery] update status=\(update.terminationStatus)")
            } catch {
                print("[yt-dlp-recovery] update launch failed: \(error)")
            }
            let updateSucceeded = succeeded
            DispatchQueue.main.async {
                guard let self else { return }
                self.ytdlpUpdateInProgress = false
                guard updateSucceeded, self.youtubePlaybackGeneration == generation,
                      self.lastPlayedURL == url, self.mpvProcess === playbackProcess else { return }
                let current = self.controller?.currentTime ?? 0
                let resume = current.isFinite && current > 0 ? current : failurePosition
                print("[yt-dlp-recovery] retry current source at \(resume)s")
                self.playMedia(url: url, title: title, startPos: resume, subtitleURLs: subtitles)
                self.youtubeRetryAttempted = true
            }
        }
    }

    func handleSleep() {
        controller?.suspendPlaybackCamera()
        stopOverlaySync()
        axWindow = nil
        appActivationObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        appActivationObservers.removeAll()
        if let ctrl = controller, ctrl.cursorHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            ctrl.cursorHidden = false
        }
        controller = nil
    }

    func handleWakeUp() {
        stopOverlaySync()
        axWindow = nil
        controller = nil
        for _ in 0..<5 { CGDisplayShowCursor(CGMainDisplayID()) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }

            guard let pid = self.mpvProcess?.processIdentifier, kill(pid, 0) == 0 else {
                self.launchMPV(file: self.videoPath)
                return
            }

            if FileManager.default.fileExists(atPath: self.ipcPath) {
                let ctrl = PPController(frame: .zero, ipcPath: self.ipcPath)
                self.controller = ctrl

                ctrl.ipcCommand("{\"command\":[\"set\",\"pause\",\"yes\"]}")
                ctrl.ipcCommand("{\"command\":[\"audio-reload\"]}")

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    ctrl.ipcCommand("{\"command\":[\"set\",\"pause\",\"no\"]}")
                    self.overlayWin?.orderOut(nil)
                    self.overlayWin = nil
                    self.checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                        guard let self = self else { return }
                        guard self.controller == nil else {
                            self.findMPVWindow()
                            if self.overlayWin != nil {
                                self.checkTimer?.invalidate()
                                self.checkTimer = nil
                            }
                            return
                        }
                        if FileManager.default.fileExists(atPath: self.ipcPath) {
                            self.controller = PPController(frame: .zero, ipcPath: self.ipcPath)
                        }
                        self.findMPVWindow()
                        if self.overlayWin != nil {
                            self.checkTimer?.invalidate()
                            self.checkTimer = nil
                        }
                    }
                }
            } else {
                self.launchMPV(file: self.videoPath)
            }
        }
    }

    // MARK: - Window Detection
    func findMPVWindow() {
        guard let pid = mpvProcess?.processIdentifier else { return }
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let win = windows.first else { return }

        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef)
        guard let sRef = sizeRef, CFGetTypeID(sRef) == AXValueGetTypeID(),
              let sz = (sRef as! AXValue).toSize(), sz.height > 100 else { return }

        axWindow = win
        if overlayWin == nil {
            checkTimer?.invalidate()
            checkTimer = nil
            attachOverlay(axWindow: win)
        }
    }

    // MARK: - Overlay
    // I14: launchMPV's checkTimer and handleWakeUp create PPController; attachOverlay swaps in a fresh one and releases the previous.
    func attachOverlay(axWindow: AXUIElement) {
        let frame = mpvFrame(from: axWindow)

        let win = DraggableOverlayWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = false
        win.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]  // never on a Space without mpv; OverlaySpaceGate moves it when mpv's Space changes
        win.ignoresMouseEvents = false
        win.delegate = self

        let ctrl = PPController(frame: NSRect(origin: .zero, size: frame.size), ipcPath: ipcPath)
        ctrl.autoresizingMask = [.width, .height]
        win.contentView = ctrl

        win.alphaValue = 0
        win.orderFrontRegardless()
        if PanelKeyOwnership.shared.mayKeyPlayerWindow() { win.makeKeyAndOrderFront(nil) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1
        }

        overlayWin = win

        let previousController = controller
        controller = ctrl
        releaseOldController(previousController)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.controller?.startPolling()
        }

        findMPVWindowID(retriesLeft: 10)
        ScreenCaptureEngine.shared.start()
        ctrl.setupAdaptiveColor()
        
        overlayWin?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)

        startOverlaySync(axWindow: axWindow)

        appActivationObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        appActivationObservers.removeAll()

        let o1 = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == self.mpvProcess?.processIdentifier else { return }
            if !StagedRunPaths.active && !NoActivate.suppressAutomatic { NSApp.activate(ignoringOtherApps: true) }
            self.overlayWin?.ignoresMouseEvents=false
            // An open input panel owns the key window; recovering from an mpv
            // activation must not tear key away from it.
            if PanelKeyOwnership.shared.mayKeyPlayerWindow() {
                self.overlayWin?.makeKeyAndOrderFront(nil)
            }
        }

        let o2 = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == ProcessInfo.processInfo.processIdentifier,
                  self.mpvProcess != nil else { return }
            // Raise the player window without making the separate mpv app
            // frontmost again after gor has just received an activating click.
            // Activating mpv here races gor's key-window claim on short clicks.
            if let ax = self.axWindow {
                let generation = self.overlaySyncGeneration
                self.overlayAXQueue.async { [weak self] in
                    let current = DispatchQueue.main.sync { [weak self] in
                        guard let self, let currentAX = self.axWindow else { return false }
                        return generation == self.overlaySyncGeneration && CFEqual(currentAX, ax) &&
                            !self.isQuittingDeliberately && NSApp.isActive && PanelKeyOwnership.shared.mayKeyPlayerWindow()
                    }
                    if current { AXUIElementPerformAction(ax, kAXRaiseAction as CFString) }
                }
            }
            // An open input panel owns the key window; the post-activation re-key
            // must not steal it back a beat after the panel's own focus assert.
            if PanelKeyOwnership.shared.mayKeyPlayerWindow() {
                self.overlayWin?.makeKeyAndOrderFront(nil)
            }
        }

        let o3=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didDeactivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in
            self?.overlayWin?.ignoresMouseEvents=false
        }
        appActivationObservers = [o1,o2,o3, OverlaySpaceGate.observeSpaceChange { [weak self] in self?.boostOverlaySync(); self?.syncOverlay() }]
    }

    private func releaseOldController(_ oldController: PPController?) {
    }

    private func findMPVWindowID(retriesLeft: Int) {
        guard let pid = mpvProcess?.processIdentifier else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for dict in list {
            if let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32,
               ownerPID == pid,
               let wid = dict[kCGWindowNumber as String] as? Int {
                ScreenCaptureEngine.shared.mpvWindowID = CGWindowID(wid)
                return
            }
        }
        guard retriesLeft > 0 else {
            print("[AppDelegate] findMPVWindowID: mpv window not found in CGWindowList after 10 attempts; adaptive-brightness feed will not run.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.findMPVWindowID(retriesLeft: retriesLeft - 1)
        }
    }

    // One AX sample at a time. Notifications trigger immediate sampling; common-mode
    // timers cover live drag, fullscreen animation, and unsupported notifications.
    private func startOverlaySync(axWindow: AXUIElement) {
        stopOverlaySync()
        if let pid = mpvProcess?.processIdentifier {
            AXUIElementSetMessagingTimeout(axWindow, 0.08)
            var observer: AXObserver?
            let result = AXObserverCreate(pid, { _, _, notification, context in
                guard let context else { return }
                let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                let name = notification as String
                if name == kAXWindowMiniaturizedNotification {
                    owner.hideOverlayForMinimize()
                } else if name == kAXWindowDeminiaturizedNotification {
                    owner.overlayMinimizeHoldUntil = 0
                }
                owner.boostOverlaySync()
                owner.syncOverlay()
            }, &observer)
            if result == .success, let observer {
                overlayAXObserver = observer
                for name in [kAXMovedNotification, kAXResizedNotification,
                             kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                    if AXObserverAddNotification(observer, axWindow, name as CFString,
                        Unmanaged.passUnretained(self).toOpaque()) == .success {
                        overlayAXNotifications.append(name)
                    }
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.commonModes)
            }
        }
        let timer = Timer(timeInterval: 0.13, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Even a backend which only sends end-of-drag notifications gets fast tracking.
            if NSEvent.pressedMouseButtons & 1 != 0 { self.boostOverlaySync() }
            self.syncOverlay()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
        boostOverlaySync()
        syncOverlay()
    }

    private func stopOverlaySync() {
        mpvFullscreenEpoch &+= 1
        mpvEntryTarget = nil
        mpvEntryWritePending = false
        mpvWindowedFrame = nil
        mpvWindowedCandidate = nil
        mpvObservedFullscreen = nil
        mpvWasFullscreen = false
        mpvRestoreFrame = nil
        mpvRestoreWritePending = false
        overlaySyncGeneration &+= 1
        overlayDragGeneration &+= 1
        minimizeGeneration &+= 1
        minimizePending = false
        syncTimer?.invalidate()
        syncTimer = nil
        overlayFastTimer?.invalidate()
        overlayFastTimer = nil
        overlaySamplePending = false
        overlayDragActive = false
        overlayPendingPosition = nil
        overlayBufferedDelta = .zero
        cachedMpvPosition = nil
        if let observer = overlayAXObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.commonModes)
            if let ax = axWindow {
                for name in overlayAXNotifications {
                    AXObserverRemoveNotification(observer, ax, name as CFString)
                }
            }
        }
        overlayAXNotifications.removeAll()
        overlayAXObserver = nil
    }

    func boostOverlaySync() {
        guard syncTimer != nil, !isQuittingDeliberately else { return }
        overlayFastUntil = ProcessInfo.processInfo.systemUptime + 2.0
        guard overlayFastTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if ProcessInfo.processInfo.systemUptime >= self.overlayFastUntil &&
               NSEvent.pressedMouseButtons & 1 == 0 && !self.minimizePending {
                timer.invalidate()
                self.overlayFastTimer = nil
                return
            }
            self.syncOverlay()
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        overlayFastTimer = timer
    }

    /// Hide the overlay synchronously, before the next AX sample, so it never
    /// lingers over the genie animation or the fullscreen exit.
    func hideOverlayForMinimize() {
        guard let win = overlayWin, !isQuittingDeliberately else { return }
        overlayMinimizeHoldUntil = ProcessInfo.processInfo.systemUptime + 0.8
        win.alphaValue = 0
        win.orderOut(nil)
        win.ignoresMouseEvents = true
    }

    /// Position and layer geometry must share the same frame receipt, not wait
    /// for another run-loop layout pass after native controls have moved.
    private func commitOverlayFrame(_ frame:NSRect,window:NSWindow) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        window.setFrame(frame,display:false,animate:false)
        window.contentView?.needsLayout=true
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
    }

    func syncOverlay() {
        MainThreadDiag.count("syncOverlay")
        guard !isQuittingDeliberately, let ax = axWindow, let win = overlayWin else { return }
        if ProcessInfo.processInfo.systemUptime >= overlayMinimizeHoldUntil { let pid = mpvProcess?.processIdentifier; _ = overlaySpace.apply(win, onScreen: HeatShadow.observeBool("mpvOnScreen", OverlaySpaceGate.mpvOnScreen(pid: pid), ttl: 0.25), pid: pid) } // Space follow: sync, every tick and on activeSpaceDidChange
        // Mouse-up can be lost when focus/window/Space changes mid-drag.
        if overlayDragActive && NSEvent.pressedMouseButtons & 1 == 0 {
            resetMpvPositionCache()
            return
        }
        if overlaySampleInFlight { overlaySamplePending = true; return }
        overlaySampleInFlight = true
        let generation = overlaySyncGeneration
        let dragGeneration = overlayDragGeneration, fullscreenEpoch = mpvFullscreenEpoch
        let screenFrames = NSScreen.screens.map { $0.frame }
        let screenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 1280
        overlayAXQueue.async { [weak self, weak win] in
            let snapshot=Self.readAXOverlaySnapshot(ax,screenHeight:screenHeight)
            let minimized=snapshot.minimized,nativeFullscreen=snapshot.fullscreen,frame=snapshot.frame
            DispatchQueue.main.async { [weak self, weak win] in
                guard let self else { return }
                self.overlaySampleInFlight = false
                guard generation == self.overlaySyncGeneration, let win,
                      self.overlayWin === win, !self.isQuittingDeliberately else {
                    if self.overlaySamplePending { self.overlaySamplePending = false; self.syncOverlay() }
                    return
                }
                guard fullscreenEpoch == self.mpvFullscreenEpoch else {
                    self.syncOverlay();return
                }
                self.trackMPVFullscreen(native: nativeFullscreen, minimized: minimized,
                    frame: frame, screenFrames: screenFrames, ax: ax,
                    screenHeight: screenHeight, generation: generation)
                if minimized == true {
                    self.overlayMinimizeHoldUntil = 0
                    win.alphaValue = 0; win.orderOut(nil)
                    win.ignoresMouseEvents = true
                } else if minimized == false {
                    if ProcessInfo.processInfo.systemUptime < self.overlayMinimizeHoldUntil {
                        // Minimize in flight: AX has not caught up yet. Stay hidden.
                    } else if self.overlaySpace.hidden { // mpv is on another Space: overlay stays ordered out (apply ran at the top of syncOverlay).
                    } else if !win.isVisible || win.alphaValue < 1 {
                        win.alphaValue = 1
                        win.orderFrontRegardless()
                    }
                    // Locally driven drag owns the frame until mouse-up. Old AX samples
                    // must not pull the overlay back behind the user's latest pointer.
                    if dragGeneration == self.overlayDragGeneration, !self.overlayDragActive,
                       !self.overlayPositionInitializing, !self.overlayPositionWriteInFlight,
                       self.overlayPendingPosition == nil,
                       let frame, !frame.isAlmostEqual(to: win.frame,epsilon:0.1) {
// [attribution comment elided]
// [attribution comment elided]
                        self.lastFrame = frame
                        self.commitOverlayFrame(frame,window:win)
                        self.boostOverlaySync()
                        // gor 514 v2: this receipt passed every gor-write
                        // fence above, so it is an external (user/mpv)
                        // frame change - the user-resize clamp trigger.
                        if !self.windowGeometryTransitionActive {
                            self.noteExternalWindowFrameChange()
                        }
                    }
                    self.updateOverlayHitTesting(win)
                }
                if self.overlaySamplePending { self.overlaySamplePending = false; self.syncOverlay() }
            }
        }
    }

    // Fence queued windowed writes before gor IPC changes fullscreen. mpv-native
    // double-clicks reach the same fence through property/native observations.
    func prepareMPVFullscreenTransition() {
        mpvFullscreenEpoch &+= 1
        controller?.cancelFitAnimation()
        controller?.ipcCommand(#"{"command":["set_property","user-data/gor/window-transition",true]}"#)
        clampFence.abort()
        overlayDragGeneration &+= 1
        overlayDragActive = false
        cachedMpvPosition = nil
        overlayBufferedDelta = .zero
        overlayPendingPosition = nil
        mpvWindowedCandidate = nil
    }

    private func beginMPVFullscreenEntry(frame: NSRect?, displays: [NSRect]) {
        prepareMPVFullscreenTransition()
        controller?.synchronizeSubtitlePresentation(pictureInPicture:false)
        mpvEntryDisplays = displays
        let origin = mpvWindowedFrame ?? frame
        if let origin {
            let areas = displays.map { rect -> CGFloat in
                let overlap = rect.intersection(origin)
                return overlap.isNull ? 0 : overlap.width * overlap.height
            }
            let largest = areas.max() ?? 0
            let current = frame.flatMap { f in displays.firstIndex { $0.contains(NSPoint(x: f.midX, y: f.midY)) } }
            let index = current.flatMap { areas[$0] == largest ? $0 : nil }
                ?? areas.firstIndex(of: largest)
            mpvEntryTarget = index.map { displays[$0] }
        } else { mpvEntryTarget = nil }
        mpvEntryStarted = ProcessInfo.processInfo.systemUptime
        mpvEntryStableFrame = nil
        mpvEntryAttempted = false
        mpvEntryWritePending = false
    }

    private func settleMPVFullscreenEntry(frame: NSRect, native: Bool?,
        displays: [NSRect], ax: AXUIElement, height: CGFloat, generation: UInt64) {
        guard let target = mpvEntryTarget, !mpvEntryAttempted else { return }
        guard displays == mpvEntryDisplays else {
            mpvFullscreenEpoch &+= 1
            mpvEntryTarget = nil
            print("[window-sync] fullscreen entry stopped: display layout changed")
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - mpvEntryStarted <= Self.mpvGeometryTimeout else {
            mpvEntryTarget = nil
            print("[window-sync] fullscreen entry timed out")
            return
        }
        if mpvEntryStableFrame.map({ frame.isAlmostEqual(to: $0) }) != true {
            mpvEntryStableFrame = frame
            mpvEntryStableSince = now
            return
        }
        guard now - mpvEntryStableSince >= (native == nil ? Self.mpvGeometryFallbackSettle : Self.mpvGeometryNativeSettle) else { return }
        mpvEntryAttempted = true // One correction at most, including failure.
        guard !frame.isAlmostEqual(to: target) else { mpvEntryTarget = nil; return }
        mpvEntryWritePending = true
        let epoch = mpvFullscreenEpoch
        let drag = overlayDragGeneration
        overlayAXQueue.async { [weak self] in
            let valid = DispatchQueue.main.sync { [weak self] in
                guard let self, let currentAX = self.axWindow else { return false }
                return CFEqual(currentAX, ax) && generation == self.overlaySyncGeneration &&
                    epoch == self.mpvFullscreenEpoch && drag == self.overlayDragGeneration &&
                    self.mpvWasFullscreen && (self.mpvObservedFullscreen == true || native == true) &&
                    !self.isQuittingDeliberately && NSScreen.screens.map({ $0.frame }) == displays
            }
            var verifiedFrame: NSRect?
            if valid, Self.axBool(ax, kAXMinimizedAttribute) == false,
               (Self.axBool(ax, "AXFullScreen") != false || native == false) {
                var size = target.size
                var point = CGPoint(x: target.minX, y: height - target.maxY)
                if let a = AXValueCreate(.cgSize, &size), let b = AXValueCreate(.cgPoint, &point),
                   AXUIElementSetAttributeValue(ax, kAXSizeAttribute as CFString, a) == .success,
                   AXUIElementSetAttributeValue(ax, kAXPositionAttribute as CFString, b) == .success,
                   let actual = Self.readAXFrame(ax, screenHeight: height), actual.isAlmostEqual(to: target) {
                    verifiedFrame = actual
                }
            }
            let receipt = verifiedFrame
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.overlaySyncGeneration,
                      epoch == self.mpvFullscreenEpoch else { return }
                self.mpvEntryWritePending = false
                self.mpvEntryTarget = nil
                if let receipt, NSScreen.screens.map({ $0.frame }) == displays {
                    self.lastFrame = receipt
                    if let win=self.overlayWin { self.commitOverlayFrame(receipt,window:win) }
                    print("[window-sync] fullscreen entry AX-verified")
                } else { print("[window-sync] fullscreen entry correction not confirmed; no retry") }
                self.syncOverlay()
            }
        }
    }

    /// The PLAYER's fullscreen state as mpv reports it (nil until mpv has reported once).
    /// Overlay and search panels read this; the borderless overlay window never carries .fullScreen.
    var playerFullscreenState: Bool? { mpvObservedFullscreen }
    /// A false property receipt can precede the native exit animation. No windowed writer may use its intermediate frame.
    var windowGeometryTransitionActive: Bool { mpvObservedFullscreen == true || mpvWasFullscreen || mpvRestoreFrame != nil }
    static let playerFullscreenChanged = Notification.Name("gor.playerFullscreenChanged")

    // mpv property changes include double-clicks handled inside mpv, not only gor menu commands.
    func noteMPVFullscreen(_ fullscreen: Bool, from source: PPController) {
        guard controller === source, !isQuittingDeliberately else { return }
        if mpvObservedFullscreen != fullscreen {
            defer { NotificationCenter.default.post(name: AppDelegate.playerFullscreenChanged, object: self) }
            mpvFullscreenEpoch &+= 1
            mpvObservedFullscreen = fullscreen
            if fullscreen {
                if !mpvWasFullscreen {
                    beginMPVFullscreenEntry(frame: lastFrame, displays: NSScreen.screens.map { $0.frame })
                }
                mpvWindowedCandidate = nil
                mpvWasFullscreen = true
                mpvRestoreFrame = nil
                mpvRestoreWritePending = false
            } else {
                prepareMPVFullscreenTransition()
                mpvEntryTarget = nil
                mpvEntryWritePending = false
            }
        }
        boostOverlaySync()
        syncOverlay()
    }

    private func trackMPVFullscreen(native: Bool?, minimized: Bool?, frame: NSRect?,
        screenFrames: [NSRect], ax: AXUIElement, screenHeight: CGFloat, generation: UInt64) {
        guard let frame, minimized == false else {
            mpvWindowedCandidate = nil
            return
        }
        let screenSized = screenFrames.contains { frame.isAlmostEqual(to: $0) }
        let fullscreen: Bool?
        if native == true || mpvObservedFullscreen == true { fullscreen = true }
        else if native == false || mpvObservedFullscreen == false { fullscreen = false }
        else { fullscreen = nil }
        guard let fullscreen else {
            mpvWindowedCandidate = nil
            return // Unknown is never windowed evidence.
        }
        if fullscreen {
            if !mpvWasFullscreen {
                beginMPVFullscreenEntry(frame: frame, displays: screenFrames)
                // Mode-change tick: commit this first fullscreen receipt to the
                // overlay now; every HUD inside follows in the same no-animation
                // transaction. prepareMPVFullscreenTransition just advanced the
                // drag generation, which would fence this receipt off in
                // syncOverlay's generic follow and leave the UI one sample behind.
                if let win = overlayWin, !frame.isAlmostEqual(to: win.frame, epsilon: 0.1) {
                    print("[window-sync] transition receipt entry: mpv=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))) overlay=(\(Int(win.frame.minX)),\(Int(win.frame.minY)) \(Int(win.frame.width))x\(Int(win.frame.height)))")
                    lastFrame = frame
                    commitOverlayFrame(frame, window: win)
                }
            }
            mpvWindowedCandidate = nil
            mpvWasFullscreen = true
            mpvRestoreFrame = nil
            settleMPVFullscreenEntry(frame: frame, native: native, displays: screenFrames,
                ax: ax, height: screenHeight, generation: generation)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if mpvWasFullscreen {
            prepareMPVFullscreenTransition()
            mpvEntryTarget = nil
            mpvEntryWritePending = false
            mpvWindowedCandidate = nil
            mpvWasFullscreen = false
            // Sentinel only: native mpv owns its restoration. Never replay this old size over a current fit.
            mpvRestoreFrame = mpvWindowedFrame ?? frame
            mpvRestoreWritePending = true
            mpvRestoreStarted = now
            mpvRestoreStableFrame = nil
            mpvRestoreStableSince = now
            cachedMpvPosition = nil
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
            if let win = overlayWin, !frame.isAlmostEqual(to: win.frame, epsilon: 0.1) {
                print("[window-sync] transition receipt exit: mpv=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))) overlay=(\(Int(win.frame.minX)),\(Int(win.frame.minY)) \(Int(win.frame.width))x\(Int(win.frame.height))) pip=\(pictureInPictureActive)")
                lastFrame = frame
                commitOverlayFrame(frame, window: win)
            }
        }
        if mpvRestoreFrame != nil {
            if now - mpvRestoreStarted > Self.mpvGeometryTimeout {
                mpvRestoreFrame = nil
                mpvRestoreWritePending = false
                controller?.ipcCommand(#"{"command":["set_property","user-data/gor/window-transition",false]}"#)
                print("[window-sync] native fullscreen exit did not settle; no forced restore")
                return
            }
            guard !screenSized, !overlayDragActive, !overlayPositionWriteInFlight,
                  overlayPendingPosition == nil else { return }
            if mpvRestoreStableFrame.map({ frame.isAlmostEqual(to: $0) }) != true {
                mpvRestoreStableFrame = frame
                mpvRestoreStableSince = now
                return
            }
            guard now - mpvRestoreStableSince >= (native == false ? Self.mpvGeometryNativeSettle : Self.mpvGeometryFallbackSettle) else { return }
            mpvRestoreFrame = nil
            mpvRestoreWritePending = false
            mpvWindowedFrame = frame
            // Commit the restored physical frame before any new intent. Setting
            // lastFrame alone made the visual follower skip the required receipt.
            lastFrame = frame
            if let win=overlayWin {
                if !frame.isAlmostEqual(to: win.frame, epsilon: 0.1) {
                    print("[window-sync] restore settled: mpv=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))) overlay=(\(Int(win.frame.minX)),\(Int(win.frame.minY)) \(Int(win.frame.width))x\(Int(win.frame.height))) after=\(String(format: "%.2f", now - mpvRestoreStarted))s")
                }
                commitOverlayFrame(frame,window:win)
            }
            // Native restored once. A mode/aspect selected while fullscreen gets ONE latest-intent
            // refit through gor-fit, never a second AX size/position restoration.
            controller?.synchronizeSubtitlePresentation(pictureInPicture:pictureInPictureActive)
            if pictureInPictureActive {restorePictureInPictureAfterFullscreen()}
            else {controller?.finishFullscreenGeometryTransition(frame: frame)}
            controller?.ipcCommand(#"{"command":["set_property","user-data/gor/window-transition",false]}"#)
            return
        }
        // Commit only settled real AX geometry. Entry animation samples reset the
        // candidate; fullscreen intent discards it and freezes the committed frame.
        // A screen-sized window intentionally retains the previous committed frame.
        guard !screenSized, !overlayDragActive, !overlayPositionWriteInFlight,
              overlayPendingPosition == nil, now >= overlayDragSettleUntil,
              native == false || (native == nil && mpvObservedFullscreen == false) else {
            mpvWindowedCandidate = nil
            return
        }
        if mpvWindowedCandidate.map({ frame.isAlmostEqual(to: $0) }) != true {
            mpvWindowedCandidate = frame
            mpvWindowedCandidateSince = now
            return
        }
        if now - mpvWindowedCandidateSince >= (native == false ? Self.mpvGeometryNativeSettle : Self.mpvGeometryFallbackSettle) {
            mpvWindowedFrame = frame
        }
    }

    private func updateOverlayHitTesting(_ win: NSWindow) {
        // An inactive overlay must receive the activating click, not pass it to
        // the separate mpv process whose activation races our key-window claim.
        guard !pictureInPictureActive,NSApp.isActive,win.isKeyWindow else {win.ignoresMouseEvents=false;return}
        let hasOpenBrowserPanel = win.contentView?.subviews.contains(where: { $0 is FileBrowserPanel }) ?? false
        if isShowingInputPanel || hasOpenBrowserPanel { win.ignoresMouseEvents = false; return }
        let mouse = NSEvent.mouseLocation
        let local = win.convertPoint(fromScreen: mouse)
        let margin: CGFloat = 8
        let onEdge = local.x < margin || local.x > win.frame.width - margin ||
                     local.y < margin || local.y > win.frame.height - margin
        if let screen = NSScreen.main {
            let menuBar = CGRect(x: screen.frame.minX, y: screen.frame.maxY - 25,
                                 width: screen.frame.width, height: 25)
            if menuBar.contains(mouse) { win.ignoresMouseEvents = true; return }
        }
        if NSApp.currentEvent?.type != .leftMouseDragged { win.ignoresMouseEvents = onEdge }
    }

    private static func axBool(_ ax: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    /// One IPC receipt for frame and mode flags; never combine an older position with a newer size.
    private static func readAXOverlaySnapshot(_ ax:AXUIElement,screenHeight:CGFloat)->(frame:NSRect?,minimized:Bool?,fullscreen:Bool?) {
        let names=[kAXPositionAttribute,kAXSizeAttribute,kAXMinimizedAttribute,"AXFullScreen"] as CFArray
        var result:CFArray?
        guard AXUIElementCopyMultipleAttributeValues(ax,names,AXCopyMultipleAttributeOptions(rawValue:0),&result) == .success,
              let result else {return (nil,nil,nil)}
        let values=result as [AnyObject]
        guard values.count==4 else {return (nil,nil,nil)}
        let minimized=values[2] as? Bool,fullscreen=values[3] as? Bool
        guard CFGetTypeID(values[0] as CFTypeRef)==AXValueGetTypeID(),CFGetTypeID(values[1] as CFTypeRef)==AXValueGetTypeID(),
              let point=(values[0] as! AXValue).toPoint(),let dimensions=(values[1] as! AXValue).toSize(),
              point.x.isFinite,point.y.isFinite,dimensions.width.isFinite,dimensions.height.isFinite,
              dimensions.width>0,dimensions.height>0 else {return (nil,minimized,fullscreen)}
        return (NSRect(x:point.x,y:screenHeight-point.y-dimensions.height,width:dimensions.width,height:dimensions.height),minimized,fullscreen)
    }

    private static func readAXFrame(_ ax: AXUIElement, screenHeight: CGFloat) -> NSRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(ax, kAXSizeAttribute as CFString, &size) == .success,
              let position, CFGetTypeID(position) == AXValueGetTypeID(),
              let size, CFGetTypeID(size) == AXValueGetTypeID(),
              let point = (position as! AXValue).toPoint(),
              let dimensions = (size as! AXValue).toSize(),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite,
              dimensions.height.isFinite, dimensions.width > 0, dimensions.height > 0 else { return nil }
        return NSRect(x: point.x, y: screenHeight - point.y - dimensions.height,
                      width: dimensions.width, height: dimensions.height)
    }

    // mpv's Mac backend performs miniaturize directly. Exit fullscreen first,
    // then wait for both IPC state and native window geometry before minimizing.
    var playerWindowIsMinimized:Bool {
        guard let ax=axWindow else{return false}
        return Self.axBool(ax,kAXMinimizedAttribute) == true
    }
    func togglePlayerMinimize() {
        guard let ax=axWindow else{return}
        if playerWindowIsMinimized {
            cancelPendingMPVMinimize()
            AXUIElementSetAttributeValue(ax,kAXMinimizedAttribute as CFString,kCFBooleanFalse)
            AXUIElementPerformAction(ax,kAXRaiseAction as CFString)
            overlayMinimizeHoldUntil=0
            if !StagedRunPaths.active && !NoActivate.suppressAutomatic { NSApp.activate(ignoringOtherApps:true) }
            overlayWin?.ignoresMouseEvents=false
            if PanelKeyOwnership.shared.mayKeyPlayerWindow() {
                overlayWin?.makeKeyAndOrderFront(nil)
            }
            boostOverlaySync();syncOverlay()
        } else {requestMPVMinimize()}
    }

    func requestMPVMinimize() {
        guard !minimizePending, !isQuittingDeliberately,
              let ax = axWindow, let win = overlayWin else { return }
        minimizePending = true
        minimizeGeneration &+= 1
        let generation = minimizeGeneration
        let client = IPCClient(path: ipcPath)
        let deadline = ProcessInfo.processInfo.systemUptime + 8.0
        boostOverlaySync()
        pollMinimizeReadiness(client: client, ax: ax, win: win, generation: generation,
                              deadline: deadline, exitRequested: false,
                              lastWindowedFrame: nil, stableSince: nil, minimizeSent: false)
    }

    private static func ipcReply(_ lines: [String]) -> [String: Any]? {
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  reply["error"] as? String == "success" else { continue }
            return reply
        }
        return nil
    }

    private func pollMinimizeReadiness(client: IPCClient, ax: AXUIElement, win: NSWindow,
        generation: UInt64, deadline: TimeInterval, exitRequested: Bool,
        lastWindowedFrame: NSRect?, stableSince: TimeInterval?, minimizeSent: Bool) {
        guard generation == minimizeGeneration, minimizePending,
              overlayWin === win, !isQuittingDeliberately else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            minimizePending = false
            controller?.spineUI.showMPVOSD("minimize: window transition timed out")
            print("[window-sync] minimize timed out; no forced miniaturize")
            return
        }
        if mpvRestoreFrame != nil || mpvRestoreWritePending || (exitRequested && mpvWasFullscreen) {
            // A fullscreen exit restore must settle before the native window is miniaturized.
            syncOverlay()
            scheduleMinimizePoll(client: client, ax: ax, win: win, generation: generation,
                deadline: deadline, exitRequested: exitRequested, frame: nil,
                stableSince: nil, minimizeSent: minimizeSent)
            return
        }
        let height = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 1280
        let screenFrames = NSScreen.screens.map { $0.frame }
        minimizeQueue.async { [weak self, weak win] in
            let property = minimizeSent ? "window-minimized" : "fullscreen"
            let payload = "{\"command\":[\"get_property\",\"\(property)\"]}"
            let reply = Self.ipcReply(client.queryBatch(payload, timeout: 0.25))
            let state = reply?["data"] as? Bool
            let nativeFullscreen = Self.axBool(ax, "AXFullScreen")
            let nativeMinimized = Self.axBool(ax, kAXMinimizedAttribute)
            let frame = Self.readAXFrame(ax, screenHeight: height)
            DispatchQueue.main.async { [weak self, weak win] in
                guard let self, let win, generation == self.minimizeGeneration,
                      self.minimizePending, self.overlayWin === win, !self.isQuittingDeliberately else { return }
                if minimizeSent {
                    if nativeMinimized == true {
                        self.minimizePending = false
                        self.syncOverlay()
                        return
                    }
                } else if state == true && !exitRequested {
                    // Command success is not animation completion. Continue sampling.
                    self.performMinimizeCommand(client: client, ax: ax, win: win,
                        generation: generation, deadline: deadline,
                        command: #"{"command":["set_property","fullscreen",false]}"#,
                        minimize: false)
                    return
                } else if state == true && exitRequested {
                    // The exit can still report true while its animation is in progress.
                    // A gor fullscreen request cancels this chain in ipcCommand().
                } else if state == false, nativeFullscreen != true, let frame,
                          nativeFullscreen == false || !screenFrames.contains(where: { frame.isAlmostEqual(to: $0) }) {
                    let now = ProcessInfo.processInfo.systemUptime
                    let stable = lastWindowedFrame.map { frame.isAlmostEqual(to: $0) } ?? false
                    let since = stable ? (stableSince ?? now) : now
                    // AXFullScreen can be unsupported. Use a longer geometry gate then.
                    let settleTime: TimeInterval = nativeFullscreen == false ? 0.10 : 0.35
                    if now - since >= settleTime {
                        self.performMinimizeCommand(client: client, ax: ax, win: win,
                            generation: generation, deadline: deadline,
                            command: #"{"command":["set_property","window-minimized",true]}"#,
                            minimize: true)
                        return
                    }
                    self.scheduleMinimizePoll(client: client, ax: ax, win: win,
                        generation: generation, deadline: deadline, exitRequested: exitRequested,
                        frame: frame, stableSince: since, minimizeSent: false)
                    return
                }
                self.scheduleMinimizePoll(client: client, ax: ax, win: win,
                    generation: generation, deadline: deadline, exitRequested: exitRequested,
                    frame: nil, stableSince: nil, minimizeSent: minimizeSent)
            }
        }
    }

    private func performMinimizeCommand(client: IPCClient, ax: AXUIElement, win: NSWindow,
        generation: UInt64, deadline: TimeInterval, command: String, minimize: Bool) {
        guard generation == minimizeGeneration, minimizePending, !isQuittingDeliberately else { return }
        minimizeQueue.async { [weak self, weak win] in
            let current = DispatchQueue.main.sync { [weak self, weak win] in
                guard let self, let win else { return false }
                return generation == self.minimizeGeneration && self.minimizePending &&
                    self.overlayWin === win && !self.isQuittingDeliberately
            }
            guard current else { return }
            let success = Self.ipcReply(client.queryBatch(command, timeout: 0.25)) != nil
            DispatchQueue.main.async { [weak self, weak win] in
                guard let self, let win, generation == self.minimizeGeneration,
                      self.minimizePending, self.overlayWin === win, !self.isQuittingDeliberately else { return }
                if success && minimize { self.hideOverlayForMinimize() }
                guard success else {
                    self.minimizePending = false
                    self.controller?.spineUI.showMPVOSD("minimize: mpv did not confirm the command")
                    print("[window-sync] minimize command unconfirmed; chain stopped")
                    return
                }
                self.scheduleMinimizePoll(client: client, ax: ax, win: win,
                    generation: generation, deadline: deadline, exitRequested: true,
                    frame: nil, stableSince: nil, minimizeSent: minimize)
            }
        }
    }

    private func scheduleMinimizePoll(client: IPCClient, ax: AXUIElement, win: NSWindow,
        generation: UInt64, deadline: TimeInterval, exitRequested: Bool,
        frame: NSRect?, stableSince: TimeInterval?, minimizeSent: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak win] in
            guard let self, let win else { return }
            self.pollMinimizeReadiness(client: client, ax: ax, win: win,
                generation: generation, deadline: deadline, exitRequested: exitRequested,
                lastWindowedFrame: frame, stableSince: stableSince, minimizeSent: minimizeSent)
        }
    }

    func cancelPendingMPVMinimize() {
        minimizeGeneration &+= 1
        minimizePending = false
        boostOverlaySync()
    }

    func mpvWindowLevel() -> Int? {
        guard let pid = mpvProcess?.processIdentifier else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for dict in list {
            guard let ownerPID = dict[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let level = dict[kCGWindowLayer as String] as? Int else { continue }
            return level
        }
        return nil
    }


    func isMPVFrontmost() -> Bool {
        guard let mpvPID = mpvProcess?.processIdentifier else { return false }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return frontPID == mpvPID
    }

    func moveMpv(dx: CGFloat, dy: CGFloat) {
        guard let ax = axWindow, let win = overlayWin, !mpvWasFullscreen,
              mpvObservedFullscreen != true, !mpvRestoreWritePending else { return }
        if pictureInPictureActive {
            var candidate=pipDragCandidate ?? win.frame
            candidate.origin.x+=dx;candidate.origin.y-=dy
            pipDragCandidate=candidate
            return // No free AX move in PiP. Mouse-up commits one corner through gor-fit.
        }
        // New user movement wins over an in-flight fullscreen restoration.
        mpvWindowedCandidate = nil
        if mpvRestoreFrame != nil { mpvFullscreenEpoch &+= 1 }
        mpvRestoreFrame = nil
        if !overlayDragActive { controller?.cancelFitAnimation() }   // a running 140 ms window animation must not fight the user's drag
        overlayDragActive = true
        overlayDragGeneration &+= 1
        boostOverlaySync()
        
        if var position = cachedMpvPosition {
            position.x += dx
            position.y += dy
            cachedMpvPosition = position
            overlayPendingPosition = position
            writePendingOverlayPosition(ax: ax)
        } else {
            overlayBufferedDelta.x += dx
            overlayBufferedDelta.y += dy
            initializeOverlayDragPosition(ax: ax, win: win)
        }
    }

    private func initializeOverlayDragPosition(ax: AXUIElement, win: NSWindow) {
        guard !overlayPositionInitializing else { return }
        overlayPositionInitializing = true
        let generation = overlaySyncGeneration
        let epoch = mpvFullscreenEpoch
        overlayAXQueue.async { [weak self, weak win] in
            var value: CFTypeRef?
            var position: CGPoint?
            if AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXValueGetTypeID() {
                position = (value as! AXValue).toPoint()
            }
            DispatchQueue.main.async { [weak self, weak win] in
                guard let self, generation == self.overlaySyncGeneration else { return }
                self.overlayPositionInitializing = false
                guard epoch == self.mpvFullscreenEpoch, let win, let currentAX = self.axWindow,
                      CFEqual(currentAX, ax), self.overlayWin === win,
                      !self.mpvWasFullscreen, self.mpvObservedFullscreen != true,
                      !self.isQuittingDeliberately else { return }
                let delta = self.overlayBufferedDelta
                self.overlayBufferedDelta = .zero
                guard var position, position.x.isFinite, position.y.isFinite else {
                    self.overlayDragActive = false
                    self.cachedMpvPosition = nil
                    self.syncOverlay()
                    return
                }
                position.x += delta.x
                position.y += delta.y
                self.cachedMpvPosition = self.overlayDragActive ? position : nil
                self.overlayPendingPosition = position
                self.writePendingOverlayPosition(ax: ax)
            }
        }
    }

    private func writePendingOverlayPosition(ax: AXUIElement) {
        guard !overlayPositionWriteInFlight, let position = overlayPendingPosition,
              !isQuittingDeliberately, !mpvWasFullscreen, mpvObservedFullscreen != true else { return }
        overlayPendingPosition = nil
        overlayPositionWriteInFlight = true
        let generation = overlaySyncGeneration
        let epoch = mpvFullscreenEpoch
        let height = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 1280
        overlayAXQueue.async { [weak self] in
            let current = DispatchQueue.main.sync { [weak self] in
                guard let self, let currentAX = self.axWindow else { return false }
                return generation == self.overlaySyncGeneration && epoch == self.mpvFullscreenEpoch &&
                    CFEqual(currentAX, ax) && !self.isQuittingDeliberately &&
                    !self.mpvWasFullscreen && self.mpvObservedFullscreen != true
            }
            var actualFrame: NSRect?
            if current, Self.axBool(ax, "AXFullScreen") != true,
               Self.axBool(ax, kAXMinimizedAttribute) == false {
                var point = position
                if let value = AXValueCreate(.cgPoint, &point),
                   AXUIElementSetAttributeValue(ax, kAXPositionAttribute as CFString, value) == .success {
                    actualFrame = Self.readAXFrame(ax, screenHeight: height)
                }
            }
            let receipt = actualFrame
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.overlaySyncGeneration else { return }
                self.overlayPositionWriteInFlight = false
                guard epoch == self.mpvFullscreenEpoch else {
                    self.syncOverlay()
                    return
                }
                if let receipt {
                    self.lastFrame = receipt
                    // This is a completed, AX-read-back windowed user move.
                    // Keep its full frame now: an immediate fullscreen can
                    // arrive before the settled sampler commits the new origin.
                    self.mpvWindowedFrame = receipt
                    if let win=self.overlayWin { self.commitOverlayFrame(receipt,window:win) }
                    // gor 514 v3: write-completion receipts (overlay-drag
                    // position, fullscreen restore) land the window at its
                    // FINAL frame - classify them too so a user drag or a
                    // restore that parks out of bounds still gets clamped.
                    self.noteExternalWindowFrameChange()
                }
                // Both layers follow the same completed AX frame; pending deltas
                // coalesce, never an unbounded per-pointer-event queue.
                if self.overlayPendingPosition != nil { self.writePendingOverlayPosition(ax: ax) }
                else {
                    self.overlayDragSettleUntil = ProcessInfo.processInfo.systemUptime + 0.15
                    self.syncOverlay()
                }
            }
        }
    }

    func resetMpvPositionCache() {
        if let candidate=pipDragCandidate {
            pipDragCandidate=nil
            snapPictureInPicture(candidate)
        }
        cachedMpvPosition = nil
        overlayDragActive = false
        overlayDragGeneration &+= 1
        // Let the final AX position write reach mpv before trusting a divergent read.
        overlayDragSettleUntil = ProcessInfo.processInfo.systemUptime + 0.15
        boostOverlaySync()
        syncOverlay()
    }

    func mpvFrame(from ax: AXUIElement) -> NSRect {
        var posRef:  CFTypeRef?
        var sizeRef: CFTypeRef?
        let posResult  = AXUIElementCopyAttributeValue(ax, kAXPositionAttribute as CFString, &posRef)
        let sizeResult = AXUIElementCopyAttributeValue(ax, kAXSizeAttribute as CFString, &sizeRef)
        guard posResult == .success, sizeResult == .success,
              let pRef = posRef,  CFGetTypeID(pRef)  == AXValueGetTypeID(),
              let sRef = sizeRef, CFGetTypeID(sRef)  == AXValueGetTypeID() else {
            return lastFrame.isEmpty ? NSRect(x: 0, y: 0, width: 1280, height: 800) : lastFrame
        }
        let pos = (pRef as! AXValue).toPoint() ?? .zero
        let sz  = (sRef as! AXValue).toSize()  ?? NSSize(width: 1280, height: 800)

        let mainScrH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
                       ?? NSScreen.main?.frame.height
                       ?? 1280
        return NSRect(x: pos.x, y: mainScrH - pos.y - sz.height, width: sz.width, height: sz.height)
    }

    // MARK: - Menu

    func item(_ title: String, action: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.target = target ?? self
        return i
    }

    /// Keep menu width stable. Progress belongs in the tooltip, never the title.
    func setCropDetectMenuStatus(_ status: String?) {
        cropDetectMenuItem?.title = "detect"
        cropDetectMenuItem?.toolTip = status
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(menuPlayerEngine(_:)) {
            menuItem.state = menuItem.representedObject as? String == selectedPlayerEngine.rawValue ? .on : .off
            // A backend failing admission (gorav stub) is grayed out; the checkmark still reflects the saved selection.
            let engine = (menuItem.representedObject as? String).flatMap(PlayerEngine.init(rawValue:)) ?? .mpv
            return PlayerBackendRoute.resolve(engine).active == engine
        }
        guard let action = menuItem.action else { return true }
        if action == #selector(menuVideoFormat(_:)),let choice=menuItem.representedObject as? [String:String],let ratio=Double(choice["ratio"] ?? "") {
            let active:Double?
            if choice["kind"] == "crop" {active=controller?.selectedMenuCropAspect}
            else if case .ratio(let value)=currentAspectPreset {active=value} else {active=nil}
            menuItem.state=active.map{abs($0-ratio)<0.000001} == true ? .on : .off
            return controller != nil
        }

        if action == #selector(menuPictureInPicture) {
            let available=overlayWin != nil && playerFullscreenState != true && controller?.vrModeEnabled != true
            menuItem.title=available ? "pip" : "pip (mono window only)"
            menuItem.state=pictureInPictureActive ? .on : .off
            return available
        }
        if action == #selector(menuWindowPlacement(_:)) {return overlayWin != nil && playerFullscreenState != true}
        if action == #selector(menuWindowMinimize) {
            menuItem.title=playerWindowIsMinimized ? "restore" : "minimize"
            return overlayWin != nil
        }
        if action == #selector(menuWindowFront) {return overlayWin != nil}

        // gor motion items carry display-only key equivalents: a KEYBOARD event never runs them through the menu (the player's
        // key monitor owns the keys; with a text field focused the key must reach the field). Mouse clicks are unaffected.
        let gorMotionSelectors: [Selector] = [#selector(menuZoomIn), #selector(menuZoomOut), #selector(menuPanVideoLeft),
            #selector(menuPanVideoRight), #selector(menuPanVideoUp), #selector(menuPanVideoDown)]
        if gorMotionSelectors.contains(action), NSApp.currentEvent?.type == .keyDown { return false }
        let ratioSelectors: [Selector: Double] = [
            #selector(menuAspect133): 1.33, #selector(menuAspect137): 1.37,
            #selector(menuAspect143): 1.43, #selector(menuAspect166): 1.66,
            #selector(menuAspect178): 1.78, #selector(menuAspect185): 1.85,
            #selector(menuAspect200): 2.00, #selector(menuAspect220): 2.20,
            #selector(menuAspect235): 2.35, #selector(menuAspect239): 2.39,
            #selector(menuAspect255): 2.55, #selector(menuAspect259): 2.59,
            #selector(menuAspect276): 2.76, #selector(menuAspect300): 3.00,
            #selector(menuAspect400): 4.00, #selector(menuAspect500): 5.00,
            #selector(menuAspect600): 6.00, #selector(menuAspect700): 7.00,
            #selector(menuAspect1610): 1.60, #selector(menuAspect32): 1.50,
            #selector(menuAspect11): 1.00, #selector(menuAspect54): 1.25,
            #selector(menuAspect916): 0.56, #selector(menuAspect34): 0.75,
        ]
        if let ratio = ratioSelectors[action] {
            if case .ratio(let active) = currentAspectPreset {
                menuItem.state = abs(active - ratio) < 0.001 ? .on : .off
            } else {
                menuItem.state = .off
            }
            return true
        }
        if action == #selector(menuAspectDefault) {
            menuItem.state = (currentAspectPreset == .defaultAR) ? .on : .off
            return true
        }
        let photonSelectors: [Selector: String] = [
            #selector(menuPhotonToggle): "photon", #selector(menuPhotonHUD): "hud",
            #selector(menuPhotonBright): "bright", #selector(menuPhotonSharp): "sharp",
            #selector(menuPhotonGrain): "grain", #selector(menuPhotonChrome): "chrome",
            #selector(menuPhotonChromeFilter): "chrome-filter", #selector(menuPhotonNegativ): "negativ",
        ]
        if let key = photonSelectors[action] {
            let enabled = key == "photon" ? photonEnabled : (photonMenuStates[key] ?? false)
            menuItem.state = enabled ? .on : .off
            return true
        }
        if action == #selector(menuMusicMode) {
            menuItem.state = (controller?.isMusicMode == true) ? .on : .off
            return true
        }
        if action == #selector(menuIptvMode) {
            menuItem.state = (controller?.isIptvMode == true) ? .on : .off
            return true
        }
        if action == #selector(menuLiveCaption) {
            menuItem.state = LiveCaptionController.shared.isActive ? .on : .off
            return true
        }
        if action == #selector(menuCaptionModel(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == LiveCaptionController.shared.modelName ? .on : .off
            return true
        }
        if action == #selector(menuNightMode) {
            menuItem.state = AudioMenuState.nightMode ? .on : .off
            return true
        }
        if action == #selector(menuNormalize) {
            menuItem.state = AudioMenuState.normalize ? .on : .off
            return true
        }
        if action == #selector(menuAudioChannels(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == AudioMenuState.channelLayout ? .on : .off
            return true
        }
        if action == #selector(menuAudioEqualizer(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == AudioMenuState.equalizer ? .on : .off
            return true
        }
        if action == #selector(menuSaveSrcSubtitle) {
            return controller?.subtitleView.canExportSrcSubtitle ?? false
        }
        return true
    }

    // The PiP target is intent, separate from the current physical overlay frame.
    // A fullscreen receipt can never become the next PiP size/corner proposal.
    private var pipWindowFrame:NSRect?
    private var pipPreferredFrame:NSRect?
    func restorePictureInPictureAfterFullscreen() {
        guard pictureInPictureActive,let ctrl=controller else{return}
        if ctrl.finishFullscreenGeometryTransition(frame:pipWindowFrame ?? overlayWin?.frame ?? .zero) {return}
        guard let target=pipWindowFrame,let win=overlayWin,
              let screen=NSScreen.screens.max(by:{
                  let a=$0.frame.intersection(target),b=$1.frame.intersection(target)
                  return (a.isNull ? 0:a.width*a.height) < (b.isNull ? 0:b.width*b.height)
              }),
              let geom=GorOpeningFit.clampGeometry(frame:target,screen:screen,chromeStyleMask:.borderless),
              !win.frame.isAlmostEqual(to:target,epsilon:0.1) else{return}
        issueFencedGeometry(geom,before:win.frame,target:target)
    }
    func refitPictureInPicture(aspect:Double) {
        guard pictureInPictureActive,!windowGeometryTransitionActive,let win=overlayWin,aspect>0 else{return}
        let current=pipWindowFrame ?? win.frame
        guard let screen=NSScreen.screens.first(where:{$0.frame.contains(NSPoint(x:current.midX,y:current.midY))}) ?? win.screen ?? NSScreen.main else{return}
        let target=PlayerPictureInPicture.croppedFrame(current:current,screen:screen.frame,aspect:aspect)
        guard let geom=GorOpeningFit.clampGeometry(frame:target,screen:screen,chromeStyleMask:.borderless) else{return}
        pipWindowFrame=target
        issueFencedGeometry(geom,before:win.frame,target:target)
    }
    private var pipDragCandidate:NSRect?
    func snapPictureInPicture(_ candidate:NSRect) {
        guard pictureInPictureActive,!windowGeometryTransitionActive,let win=overlayWin,let screen=win.screen ?? NSScreen.main else{return}
        let target=PlayerPictureInPicture.nearestCorner(candidate:candidate,screen:screen.frame)
        guard let geom=GorOpeningFit.clampGeometry(frame:target,screen:screen,chromeStyleMask:.borderless) else{return}
        pipWindowFrame=target;pipPreferredFrame=target
        UserDefaults.standard.set(NSStringFromRect(target),forKey:"gor.pip.preferredFrame")
        issueFencedGeometry(geom,before:win.frame,target:target)
    }
    private var pipRestoreFrame:NSRect?
    private var pipRestoreOnTop:Bool?
    var pictureInPictureActive:Bool {pipRestoreFrame != nil}
    func togglePlayerPictureInPicture() {
        guard let win=overlayWin,let ctrl=controller,!windowGeometryTransitionActive,!ctrl.vrModeEnabled,
              let screen=win.screen ?? NSScreen.main else{return}
        let before=win.frame
        if let restore=pipRestoreFrame,let onTop=pipRestoreOnTop {
            guard let geom=GorOpeningFit.clampGeometry(frame:restore,screen:screen,chromeStyleMask:.borderless) else{return}
            issueFencedGeometry(geom,before:before,target:restore);ctrl.logPipCrop("exit-issued",frame:restore);DispatchQueue.main.asyncAfter(deadline:.now()+1.2){[weak self] in if let w=self?.overlayWin{ctrl.logPipCrop("exit+1.2s",frame:w.frame)}}
            ctrl.ipcCommand(onTop ? #"{"command":["set_property","ontop",true]}"# : #"{"command":["set_property","ontop",false]}"#)
            pipRestoreFrame=nil;pipRestoreOnTop=nil;pipDragCandidate=nil;pipWindowFrame=nil
        } else {
            // Do not change a state we cannot restore exactly.
            guard let onTop=ctrl.nativeOnTopState() else{return}
            let usable=screen.frame
            let video=ctrl.windowMenuVideoSize
            let shaped=PlayerPictureInPicture.croppedFrame(current:before,screen:usable,aspect:Double(video.width/max(1,video.height)))
            let saved=pipPreferredFrame ?? UserDefaults.standard.string(forKey:"gor.pip.preferredFrame").map{NSRectFromString($0)}
            let target=PlayerPictureInPicture.frame(current:shaped,visible:usable,preferred:saved)
            guard let geom=GorOpeningFit.clampGeometry(frame:target,screen:screen,chromeStyleMask:.borderless) else{return}
            pipRestoreFrame=before;pipRestoreOnTop=onTop;pipWindowFrame=target
            ctrl.ipcCommand(MPVCommand.make(["set_property","user-data/gor/pip-window-owned",true]))
            ctrl.ipcCommand(#"{"command":["set_property","ontop",true]}"#)
            ctrl.logPipCrop("enter-before shaped-aspect=\(video.width/max(1,video.height))",frame:before);issueFencedGeometry(geom,before:before,target:target);DispatchQueue.main.asyncAfter(deadline:.now()+1.2){[weak self] in if let w=self?.overlayWin{ctrl.logPipCrop("enter+1.2s",frame:w.frame)}}
        }
        ctrl.ipcCommand(MPVCommand.make(["set_property","user-data/gor/pip-window-owned",pictureInPictureActive]))
        ctrl.synchronizeSubtitlePresentation(pictureInPicture:pictureInPictureActive && !windowGeometryTransitionActive)
    }

    private var windowUserSizeScale:Double = {
        let stored=UserDefaults.standard.double(forKey:"gor.window.userSizeScale")
        return stored>0 ? stored : 1
    }()
    private var menuWindowRestoreFrame:NSRect?
    func placePlayerWindow(_ mode:String) {
        guard let win=overlayWin,!windowGeometryTransitionActive,
              let screen=win.screen ?? NSScreen.main else{return}
        let before=win.frame
        let usable=pictureInPictureActive ? screen.frame : PlayerWindowPlacement.usableFrame(screen:screen.frame,visible:screen.visibleFrame,menuAutoHides:false) // corners are of the usable area (menu bar/Dock/notch excluded); only pip owns true screen corners
        let video=controller?.windowMenuVideoSize ?? before.size
        let position=["top-left","top-right","bottom-left","bottom-right","center"].contains(mode)
        if pictureInPictureActive {
            guard position else{return}
            let target=mode == "center" ? PlayerPictureInPicture.nearestCorner(candidate:before,screen:usable) : PlayerWindowPlacement.frame(mode:mode,current:before,visible:usable)
            guard let geom=GorOpeningFit.clampGeometry(frame:target,screen:screen,chromeStyleMask:.borderless) else{return}
            pipWindowFrame=target
            issueFencedGeometry(geom,before:before,target:target)
            return
        }
        if mode == "smaller" || mode == "larger" {
            windowUserSizeScale=PlayerWindowSizing.nextScale(windowUserSizeScale,mode:mode)
            UserDefaults.standard.set(windowUserSizeScale,forKey:"gor.window.userSizeScale")
        }
        let reset=position || mode == "smaller" || mode == "larger"
        let base=PlayerWindowSizing.frame(mode:mode,current:before,screen:usable,video:video,resetDefault:reset,userScale:windowUserSizeScale)
        var target=PlayerWindowPlacement.frame(mode:reset ? (position ? mode : "center") : mode,current:base,visible:usable)
        if mode == "zoom" {
            if let saved=menuWindowRestoreFrame {target=saved;menuWindowRestoreFrame=nil}
            else {menuWindowRestoreFrame=before}
        }
        guard let geom=GorOpeningFit.clampGeometry(frame:target,screen:screen,chromeStyleMask:.borderless) else{return}
        issueFencedGeometry(geom,before:before,target:target);print("[window-place] mode=\(mode) before=\(before) target=\(target) screen=\(usable) geom=\(geom)")
    }

    func buildMenuBar() {
        let main = NSMenu()

        // One-line submenu group: item and menu share the title.
        func group(_ t: String, in parent: NSMenu) -> NSMenu { let i = NSMenuItem(); i.title = t; let m = NSMenu(title: t); i.submenu = m; parent.addItem(i); return m }
        // ── app ─────────────────────────────────────────────────────────────────
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(item("about", action: #selector(showAbout), key: "5", mods: [.command, .control, .option]))
        appMenu.addItem(.separator())
        let engineItem = NSMenuItem(title: "engine", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu(title: "engine")
        engineItem.submenu = engineMenu
        for engine in PlayerEngine.allCases {
            let choice = NSMenuItem(title: engine.rawValue, action: #selector(menuPlayerEngine(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = engine.rawValue
            engineMenu.addItem(choice)
        }
        appMenu.addItem(engineItem)
        appMenu.addItem(item("update", action: #selector(menuUpdate), key: "4", mods: [.command, .control, .option]))
        appMenu.addItem(.separator())
        // Shift+Q follows the player restart route; Command+Q remains standard quit.
        appMenu.addItem(item("restart", action: #selector(menuRestartQuit), key: "q", mods: [.shift]))
        appMenu.addItem(item("quit", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))

        // ── edit ────────────────────────────────────────────────────────────────
        let editItem = NSMenuItem(); editItem.title = "edit"; main.addItem(editItem)
        let editMenu = NSMenu(title: "edit"); editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "select all", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // ── file ────────────────────────────────────────────────────────────────
        let fileItem = NSMenuItem(); fileItem.title = "file"; main.addItem(fileItem)
        let fileMenu = NSMenu(title: "file"); fileItem.submenu = fileMenu
        fileMenu.addItem(item("open…",       action: #selector(openFile), key: "o"))
        fileMenu.addItem(item("open url…",   action: #selector(menuOpenURL), key: "u"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("archive", action: #selector(openArchive), key: "a", mods: [.command, .shift]))
        fileMenu.addItem(item("magnet", action: #selector(openMagnetSearch), key: "m"))
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        fileMenu.addItem(item("find in panel", action: #selector(menuFindInPanel), key: "f"))
        fileMenu.addItem(item("iptv",          action: #selector(menuIptvMode), key: "t"))
        fileMenu.addItem(item("music",    action: #selector(menuMusicMode), key: "u", mods: [.command, .control, .option]))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("stop",        action: #selector(menuStop), key: "k", mods: [.command, .control, .option]))
        fileMenu.addItem(item("reload",      action: #selector(menuReload), key: "r", mods: .command))
        fileMenu.addItem(item("quit and save", action: #selector(menuQuitSave), key: "q", mods: [.command, .shift]))

        // ── playback ────────────────────────────────────────────────────────────
        let playItem = NSMenuItem(); playItem.title = "playback"; main.addItem(playItem)
        let playMenu = NSMenu(title: "playback"); playItem.submenu = playMenu
        playMenu.addItem(item("play / pause",       action: #selector(menuPlayPause), key: " ", mods: []))
        playMenu.addItem(.separator())
        let playVolumeMenu = group("volume", in: playMenu)
        playVolumeMenu.addItem(item("mute",                 action: #selector(menuMute),      key: "←", mods: .command))
        playVolumeMenu.addItem(item("max volume",           action: #selector(menuVolMax),    key: "→", mods: .command))
        let seekMenu = group("seek", in: playMenu)
        seekMenu.addItem(item("seek forward 60s",     action: #selector(menuSeekF60),   key: "↑", mods: []))
        seekMenu.addItem(item("seek backward 60s",    action: #selector(menuSeekB60),   key: "↓", mods: []))
        seekMenu.addItem(item("seek forward 20s",     action: #selector(menuSeekF20),   key: "↑", mods: .command))
        seekMenu.addItem(item("seek backward 20s",    action: #selector(menuSeekB20),   key: "↓", mods: .command))
        seekMenu.addItem(item("seek forward 5s",      action: #selector(menuSeekF5),    key: "]", mods: [.command, .control, .option]))
        seekMenu.addItem(item("seek backward 5s",     action: #selector(menuSeekB5),    key: "[", mods: [.command, .control, .option]))
        seekMenu.addItem(item("seek to beginning",  action: #selector(menuSeekStart), key: "0", mods: [.command, .control, .option]))
        // "." is mpv's default frame-step. frame-back's default "," is bound to
        // sub-scale in input.conf; previous frame uses the reserved menu modifier family.
        seekMenu.addItem(.separator())
        seekMenu.addItem(item("next frame",           action: #selector(menuFrameNext), key: ".", mods: []))
        seekMenu.addItem(item("previous frame",       action: #selector(menuFramePrev), key: ",", mods: [.command, .control, .option]))
        let speedMenu = group("speed", in: playMenu)
        speedMenu.addItem(item("speed up",           action: #selector(menuSpeedUp),    key: "]", mods: []))
        speedMenu.addItem(item("speed down",         action: #selector(menuSpeedDown),  key: "[", mods: []))
        speedMenu.addItem(item("speed ×2",           action: #selector(menuSpeedDouble), key: "=", mods: [.command, .control, .option]))
        speedMenu.addItem(item("speed ×0.5",         action: #selector(menuSpeedHalf),   key: "-", mods: [.command, .control, .option]))
        speedMenu.addItem(item("reset speed",        action: #selector(menuSpeedReset),  key: "1", mods: [.command, .control, .option]))
        let chapterMenu = group("chapters", in: playMenu)
        chapterMenu.addItem(item("next chapter",       action: #selector(menuChapterNext), key: ".", mods: [.command, .control, .option]))
        chapterMenu.addItem(item("previous chapter",   action: #selector(menuChapterPrev), key: "/", mods: [.command, .control, .option]))
        let loopMenu = group("loop", in: playMenu)
        loopMenu.addItem(item("loop file",          action: #selector(menuLoopFile),    key: "l", mods: [.command, .shift]))
        loopMenu.addItem(item("a-b loop",           action: #selector(menuABLoop),      key: "l", mods: [.command, .control, .option]))
        let playlistMenu = group("playlist", in: playMenu)
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
        playlistMenu.addItem(item("next in playlist",   action: #selector(menuPlaylistNext), key: String(UnicodeScalar(NSRightArrowFunctionKey)!), mods: [.command, .shift]))
        playlistMenu.addItem(item("previous in playlist", action: #selector(menuPlaylistPrev), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), mods: [.command, .shift]))
        playlistMenu.addItem(item("open playlist folder", action: #selector(menuOpenPlaylistFolder), key: "p"))

        // ── video ───────────────────────────────────────────────────────────────
        let videoItem = NSMenuItem(); videoItem.title = "video"; main.addItem(videoItem)
        let videoMenu = NSMenu(title: "video"); videoItem.submenu = videoMenu
        installTrackSubmenu(in:videoMenu,type:"video")
        // 191b B4: the ONE "3d" menu (was "vr" + vr-tools extras). Rows and key equivalents come from ThreeDKeymap (B5);
        // every handler is a ThreeDStore dispatch and state reads happen only in validateMenuItem (B1).
        MainActor.assumeIsolated {ThreeDMenu.shared.install(in: videoMenu)}; startThreeDCoordinator(); let clipMenu = group("clip", in: videoMenu)
        clipMenu.addItem(item("clip video",   action: #selector(menuClipVideo), key: "c", mods: [.command, .option]))
        clipMenu.addItem(item("clip gif",     action: #selector(menuClipGif),   key: "g", mods: [.command, .option]))
        clipMenu.addItem(item("clip undo",    action: #selector(menuClipUndo),  key: "z", mods: [.command, .option]))
        clipMenu.addItem(item("clip abort",   action: #selector(menuClipAbort), key: "x", mods: [.command, .option]))
        clipMenu.addItem(.separator())
        clipMenu.addItem(item("clip open",    action: #selector(menuClipOpen),  key: "o", mods: [.command, .option]))
        clipMenu.addItem(item("toggle fade",  action: #selector(menuClipFade),  key: "f", mods: [.command, .option]))
        // gor motion: the shortcut is shown as the item's tooltip (titles and key equivalents are unchanged).
        func gorTip(_ i: NSMenuItem, _ t: String) -> NSMenuItem { i.toolTip = t; return i }
        // The key equivalents are DISPLAY (shown in the menu's shortcut column): the keys themselves are handled by the
        // player's key monitor (hold-to-move, easing), and validateMenuItem disables these items for keyboard events so the
        // menu never double-fires. Plain = and - still zoom (handled by the monitor).
        func fnShift(_ f: Int) -> String { String(UnicodeScalar(UInt32(f))!) }
        let fs: NSEvent.ModifierFlags = [.shift, .function]
// [attribution comment elided]
// [attribution comment elided]
        let cropMenu = group("crop", in: videoMenu)
        let redetectCropItem=item("detect",action:#selector(menuCropDetect),key:"d",mods:[.command,.control,.option])
        cropMenu.addItem(redetectCropItem);cropDetectMenuItem=redetectCropItem
        populateVideoFormats(cropMenu,crop:true)
        let aspectMenu = group("aspect ratio", in: videoMenu)
        populateVideoFormats(aspectMenu,crop:false)
        let zoomMenu = group("zoom", in: videoMenu)
        zoomMenu.addItem(gorTip(item("zoom in",               action: #selector(menuZoomIn),      key: ",", mods: fs), "fn+shift+, (also =)"))
        zoomMenu.addItem(gorTip(item("zoom out",              action: #selector(menuZoomOut),     key: ".", mods: fs), "fn+shift+. (also -)"))
        zoomMenu.addItem(item("reset zoom & pan",      action: #selector(menuZoomReset),   key: "z", mods: [.command, .control, .option]))
        let moveMenu = group("move", in: videoMenu)
        moveMenu.addItem(gorTip(item("move video left",      action: #selector(menuPanVideoLeft),   key: fnShift(NSLeftArrowFunctionKey), mods: fs), "fn+shift+←"))
        moveMenu.addItem(gorTip(item("move video right",      action: #selector(menuPanVideoRight),   key: fnShift(NSRightArrowFunctionKey), mods: fs), "fn+shift+→"))
        moveMenu.addItem(gorTip(item("move video up",      action: #selector(menuPanVideoUp),   key: fnShift(NSUpArrowFunctionKey), mods: fs), "fn+shift+↑"))
        moveMenu.addItem(gorTip(item("move video down",      action: #selector(menuPanVideoDown),   key: fnShift(NSDownArrowFunctionKey), mods: fs), "fn+shift+↓"))
        let rotateMenu = group("rotate", in: videoMenu)
        rotateMenu.addItem(item("rotate clockwise",      action: #selector(menuRotateCW),    key: "r", mods: [.command, .control, .option]))
        rotateMenu.addItem(item("rotate counter-clockwise", action: #selector(menuRotateCCW), key: "e", mods: [.command, .control, .option]))
        rotateMenu.addItem(item("reset rotation",        action: #selector(menuRotateReset), key: "2", mods: [.command, .control, .option]))
        let screenshotMenu = group("screenshot", in: videoMenu)
        screenshotMenu.addItem(item("screenshot (with subs)", action: #selector(menuScreenshot),       key: "s", mods: []))
        screenshotMenu.addItem(item("screenshot (video only)", action: #selector(menuScreenshotClean), key: "s", mods: .shift))
        screenshotMenu.addItem(item("screenshot (window)",    action: #selector(menuScreenshotWin),   key: "s", mods: .command))
        let qualityMenu = group("quality", in: videoMenu)
        qualityMenu.addItem(item("deband",                action: #selector(menuDeband),      key: "b", mods: [.command, .control, .option]))
        qualityMenu.addItem(item("deinterlace",           action: #selector(menuDeinterlace), key: "i", mods: [.command, .control, .option]))
        qualityMenu.addItem(item("hardware decoding",     action: #selector(menuHwdec),       key: "h", mods: [.command, .control, .option]))
        qualityMenu.addItem(.separator())
        qualityMenu.addItem(item("panscan +",             action: #selector(menuPanscanIn),   key: "e", mods: []))
        qualityMenu.addItem(item("panscan −",             action: #selector(menuPanscanOut),  key: "w", mods: []))
        let adjustMenu = group("adjust", in: videoMenu)
        adjustMenu.addItem(item("adjust contrast +",     action: #selector(menuContrastUp),   key: "c", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("adjust contrast −",     action: #selector(menuContrastDown), key: "v", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("adjust brightness +",   action: #selector(menuBrightUp),     key: "b", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("adjust brightness −",   action: #selector(menuBrightDown),   key: "n", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("adjust gamma +",        action: #selector(menuGammaUp),      key: "g", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("adjust gamma −",        action: #selector(menuGammaDown),    key: "h", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("adjust saturation +",   action: #selector(menuSatUp),        key: "s", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("adjust saturation −",   action: #selector(menuSatDown),      key: "a", mods: [.command, .control, .shift]))
        adjustMenu.addItem(item("reset color adjustments", action: #selector(menuColorReset), key: "3", mods: [.command, .control, .option]))
        let toggleMenu = group("toggle", in: videoMenu)
        toggleMenu.addItem(item("toggle fullscreen",     action: #selector(menuFullscreen),  key: "f", mods: []))
        toggleMenu.addItem(item("toggle always on top",  action: #selector(menuOntop),       key: "t", mods: [.command, .control, .option]))

        // ── photon ─────────────────────────────────────────────────────────────
        // Plain-letter keys are swallowed by InputController and fired from
        // input.conf - the labels document those bindings, actions match them.
        let photonItem = NSMenuItem(); photonItem.title = "photon"; main.addItem(photonItem)
        let photonMenu = NSMenu(title: "photon"); photonItem.submenu = photonMenu
        photonMenu.addItem(item("photon",         action: #selector(menuPhotonToggle),  key: "\u{F70C}", mods: []))
        photonMenu.addItem(item("hud",            action: #selector(menuPhotonHUD),     key: "\u{F70B}", mods: []))
        photonMenu.addItem(item("stats",          action: #selector(menuStatsToggle),   key: "i", mods: []))
        photonMenu.addItem(.separator())
        let photonAdjustMenu = group("adjust", in: photonMenu)
        photonAdjustMenu.addItem(item("bright",         action: #selector(menuPhotonBright),  key: "b", mods: []))
        photonAdjustMenu.addItem(item("sharp",          action: #selector(menuPhotonSharp),   key: "x", mods: []))
        photonAdjustMenu.addItem(item("grain",          action: #selector(menuPhotonGrain),   key: "g", mods: []))
        let photonFiltersMenu = group("filters", in: photonMenu)
        photonFiltersMenu.addItem(item("chrome",         action: #selector(menuPhotonChrome),  key: "c", mods: []))
        photonFiltersMenu.addItem(item("chrome filter",  action: #selector(menuPhotonChromeFilter), key: "c", mods: [.shift]))
        photonFiltersMenu.addItem(item("negativ",        action: #selector(menuPhotonNegativ), key: "n", mods: []))

        // ── audio ───────────────────────────────────────────────────────────────
        let audioItem = NSMenuItem(); audioItem.title = "audio"; main.addItem(audioItem)
        let audioMenu = NSMenu(title: "audio"); audioItem.submenu = audioMenu
        installTrackSubmenu(in:audioMenu,type:"audio")
        let audioVolumeMenu = group("volume", in: audioMenu)
        audioVolumeMenu.addItem(item("volume up",             action: #selector(menuVolUp),       key: "0", mods: []))
        audioVolumeMenu.addItem(item("volume down",           action: #selector(menuVolDown),     key: "9", mods: []))
        audioVolumeMenu.addItem(item("mute / unmute",         action: #selector(menuMute),        key: "m", mods: []))
        // The 2026-11-08 audio expansion: one-of lists and toggles stay
        // chord-free like the format/model rows (reasons pinned in
        // MenuShortcuts); each row's wiring is pinned in Tests/AudioMenu.
        let audioBoostMenu = group("boost", in: audioMenu)
        audioBoostMenu.addItem(item("volume boost +10%",      action: #selector(menuVolBoostUp),   key: ""))
        audioBoostMenu.addItem(item("volume boost −10%",      action: #selector(menuVolBoostDown), key: ""))
        audioBoostMenu.addItem(item("volume boost off",       action: #selector(menuVolBoostOff),  key: ""))
        installAudioDeviceSubmenu(in:audioMenu)
        let audioChannelsMenu = group("channels", in: audioMenu)
        let chAuto=item("auto (source)",action:#selector(menuAudioChannels(_:)),key:"");chAuto.representedObject="auto-safe";audioChannelsMenu.addItem(chAuto)
        let chStereo=item("stereo downmix",action:#selector(menuAudioChannels(_:)),key:"");chStereo.representedObject="stereo";audioChannelsMenu.addItem(chStereo)
        let chMono=item("mono",action:#selector(menuAudioChannels(_:)),key:"");chMono.representedObject="mono";audioChannelsMenu.addItem(chMono)
        let ch51=item("surround 5.1",action:#selector(menuAudioChannels(_:)),key:"");ch51.representedObject="5.1";audioChannelsMenu.addItem(ch51)
        let ch71=item("surround 7.1",action:#selector(menuAudioChannels(_:)),key:"");ch71.representedObject="7.1";audioChannelsMenu.addItem(ch71)
        let audioDynamicsMenu = group("dynamics", in: audioMenu)
        audioDynamicsMenu.addItem(item("night mode",          action: #selector(menuNightMode),    key: ""))
        audioDynamicsMenu.addItem(item("normalize (loudnorm)", action: #selector(menuNormalize),   key: ""))
        let audioEqMenu = group("equalizer", in: audioMenu)
        let eqFlat=item("flat (off)",action:#selector(menuAudioEqualizer(_:)),key:"");eqFlat.representedObject="off";audioEqMenu.addItem(eqFlat)
        let eqBass=item("bass boost",action:#selector(menuAudioEqualizer(_:)),key:"");eqBass.representedObject="bass boost";audioEqMenu.addItem(eqBass)
        let eqVoice=item("voice",action:#selector(menuAudioEqualizer(_:)),key:"");eqVoice.representedObject="voice";audioEqMenu.addItem(eqVoice)
        let eqTreble=item("treble",action:#selector(menuAudioEqualizer(_:)),key:"");eqTreble.representedObject="treble";audioEqMenu.addItem(eqTreble)
        let audioDelayMenu = group("delay", in: audioMenu)
        audioDelayMenu.addItem(item("audio delay +0.1s",     action: #selector(menuAudioDelayP), key: "9", mods: [.command, .control, .option]))
        audioDelayMenu.addItem(item("audio delay −0.1s",     action: #selector(menuAudioDelayM), key: "8", mods: [.command, .control, .option]))
        audioDelayMenu.addItem(item("reset audio delay",     action: #selector(menuAudioDelayReset), key: "7", mods: [.command, .control, .option]))

        // ── subtitles ───────────────────────────────────────────────────────────
        let subItem = NSMenuItem(); subItem.title = "subtitles"; main.addItem(subItem)
        let subMenu = NSMenu(title: "subtitles"); subItem.submenu = subMenu
        installTrackSubmenu(in:subMenu,type:"sub")
        subMenu.addItem(item("toggle subtitles",        action: #selector(menuSubToggle),   key: "v", mods: []))
        subMenu.addItem(.separator())
        let subFilesMenu = group("files", in: subMenu)
        subFilesMenu.addItem(item("load subtitle file…",     action: #selector(menuSubLoad),     key: "o", mods: [.command, .control, .option]))
        subFilesMenu.addItem(item("save src subtitle",       action: #selector(menuSaveSrcSubtitle), key: "f", mods: [.command, .control, .option]))
        // Cmd+Shift+Arrows = subtitle delay. Sub-seek removed as unnecessary;
        // plain x/z stay with photon_sharp via input.conf.
        let subDelayMenu = group("delay", in: subMenu)
        subDelayMenu.addItem(item("subtitle delay +0.1s",    action: #selector(menuSubDelayP),   key: String(UnicodeScalar(NSRightArrowFunctionKey)!), mods: [.command, .shift]))
        subDelayMenu.addItem(item("subtitle delay −0.1s",    action: #selector(menuSubDelayM),   key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), mods: [.command, .shift]))
        subDelayMenu.addItem(item("reset subtitle delay",  action: #selector(menuSubDelayReset),  key: "6", mods: [.command, .control, .option]))
        // "," and "ü" are the real sub-scale keys from input.conf.
        let fontSizeMenu = group("font size", in: subMenu)
        fontSizeMenu.addItem(item("subtitle font size +",    action: #selector(menuSubSizeUp),   key: ",", mods: []))
        fontSizeMenu.addItem(item("subtitle font size −",    action: #selector(menuSubSizeDown), key: "ü", mods: []))
        fontSizeMenu.addItem(item("subtitle font size reset",action:#selector(menuSubSizeReset),key:"0",mods:[.command, .control, .option, .shift]))
        let subPosMenu = group("position", in: subMenu)
        subPosMenu.addItem(item("↑",       action: #selector(menuSubUp),       key: "r", mods: []))
        subPosMenu.addItem(item("↓",     action: #selector(menuSubDown),     key: "t", mods: []))
        subPosMenu.addItem(item("random subtitle position", action: #selector(menuSubRandomPos), key: "0", mods: [.shift]))
// [attribution comment elided]
// [attribution comment elided]
        subPosMenu.addItem(.separator())
        let sp1=item("position 10",action:#selector(menuSubPosPreset(_:)),key:"1",mods:.shift);sp1.representedObject=10;subPosMenu.addItem(sp1)
        let sp2=item("position 20",action:#selector(menuSubPosPreset(_:)),key:"2",mods:.shift);sp2.representedObject=20;subPosMenu.addItem(sp2)
        let sp3=item("position 30",action:#selector(menuSubPosPreset(_:)),key:"3",mods:.shift);sp3.representedObject=30;subPosMenu.addItem(sp3)
        let sp4=item("position 40",action:#selector(menuSubPosPreset(_:)),key:"4",mods:.shift);sp4.representedObject=40;subPosMenu.addItem(sp4)
        let sp5=item("position 50",action:#selector(menuSubPosPreset(_:)),key:"5",mods:.shift);sp5.representedObject=50;subPosMenu.addItem(sp5)
        let sp6=item("position 60",action:#selector(menuSubPosPreset(_:)),key:"6",mods:.shift);sp6.representedObject=60;subPosMenu.addItem(sp6)
        let sp7=item("position 70",action:#selector(menuSubPosPreset(_:)),key:"7",mods:.shift);sp7.representedObject=70;subPosMenu.addItem(sp7)
        let sp8=item("position 80",action:#selector(menuSubPosPreset(_:)),key:"8",mods:.shift);sp8.representedObject=80;subPosMenu.addItem(sp8)
        let sp9=item("position 90",action:#selector(menuSubPosPreset(_:)),key:"9",mods:.shift);sp9.representedObject=90;subPosMenu.addItem(sp9)
        subMenu.addItem(.separator())
        // Recovery hammer: deliberately click-only, not a chord to hit by accident.
        subMenu.addItem(item("reset subtitles",action:#selector(menuSubtitlesReset),key:""))
        subMenu.addItem(.separator())
        subMenu.addItem(item("live captions",           action: #selector(menuLiveCaption), key: "j", mods: [.command, .control, .option]))
        let capModelMenu = group("live caption model", in: subMenu)
        for model in ["auto", "tiny", "base", "small", "medium", "large", "large-v2", "large-v3", "large-v3-turbo"] {
            let mi = item(model, action: #selector(menuCaptionModel(_:)), key: "")
            mi.representedObject = model
            capModelMenu.addItem(mi)
        }

        // Keep processing ahead of picture controls, as requested.
        main.removeItem(photonItem)
        main.insertItem(photonItem,at:main.index(of:subItem)+1)

        let windowItem=NSMenuItem(title:"window",action:nil,keyEquivalent:"")
        let windowMenu=NSMenu(title:"window");windowItem.submenu=windowMenu
        windowMenu.addItem(item("minimize",action:#selector(menuWindowMinimize),key:"m",mods:[.command,.control,.option,.shift]))
        windowMenu.addItem(item("full screen",action:#selector(menuFullscreen),key:"f",mods:[.command,.control]))
        let pipItem=item("pip",action:#selector(menuPictureInPicture),key:"p",mods:[.command,.control,.option,.shift])
        pipItem.toolTip="small always-on-top mono player; toggle again to restore geometry and on-top state"
        windowMenu.addItem(pipItem)
        windowMenu.addItem(.separator())
        let positionMenu = group("position", in: windowMenu)
        for (title,mode,key) in [("•","center","."),
            ("↖","top-left",String(UnicodeScalar(NSUpArrowFunctionKey)!)),("↗","top-right",String(UnicodeScalar(NSRightArrowFunctionKey)!)),("↙","bottom-left",String(UnicodeScalar(NSLeftArrowFunctionKey)!)),("↘","bottom-right",String(UnicodeScalar(NSDownArrowFunctionKey)!))] {
            let entry=item(title,action:#selector(menuWindowPlacement(_:)),key:key,mods:[.function,.control,.option,.command])
            entry.representedObject=mode;positionMenu.addItem(entry);if title != "•",let f=NSFont(name:"Apple Symbols",size:NSFont.systemFontSize*8/6){entry.attributedTitle=NSAttributedString(string:title,attributes:[.font:f])} // [attribution comment elided]
        }
        let sizeMenu = group("size", in: windowMenu)
        for (title,mode,key) in [("zoom / restore","zoom","z"),("fill screen","fill","f"),
            ("smaller","smaller","-"),("larger","larger","=")] {
            let entry=item(title,action:#selector(menuWindowPlacement(_:)),key:key,mods:[.command,.control,.option,.shift])
            entry.representedObject=mode;sizeMenu.addItem(entry)
        }
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("bring to front",action:#selector(menuWindowFront),key:"b",mods:[.command,.control,.option,.shift]))
        // This is gor's geometry menu, not AppKit's automatic Window menu.
        // Registering it as windowsMenu injects system tiling actions that target
        // the transparent overlay rather than the mpv picture window.
        main.addItem(windowItem)

        let helpItem=NSMenuItem(title:"help",action:nil,keyEquivalent:"")
        let helpMenu=NSMenu(title:"help");helpItem.submenu=helpMenu
        helpMenu.addItem(item("shortcuts",action:#selector(menuHelpShortcuts),key:"/",mods:[.command,.control,.option,.shift]))
        helpMenu.addItem(item("issue report",action:#selector(menuHelpIssueReport),key:"i",mods:[.command,.control,.option,.shift]))
        helpMenu.addItem(item("about gor",action:#selector(showAbout),key:""))
        main.addItem(helpItem);NSApp.helpMenu=helpMenu
        NSApp.mainMenu = main
    }

    // Observation only. Append-only local file; failures never alter quit decisions.
    private func quitDebug(_ phase: String) {
        let fm = FileManager.default
        let directory = StagedRunPaths.home(fm.homeDirectoryForCurrentUser).appendingPathComponent("Library/Logs/gor", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("quit-debug.log").path
        let line = "ts=\(Date().timeIntervalSince1970) pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(ProcessInfo.processInfo.systemUptime) main=\(Thread.isMainThread) \(phase)\n"
        _ = BoundedDiskWriter.append(Data(line.utf8),to:URL(fileURLWithPath:path))
    }

    // MARK: - Scoped restart token (quit/relaunch ordering)
    // The duplicate-guard cannot tell "old instance is mid-quit" from "old
    // instance is healthy". A magnet teardown can keep the old process alive
    // past the 3s wait; the new instance then activate-exits and the relaunch
    // is silently lost. The quitting instance writes this token; a launching
    // instance that sees a FRESH token naming a live other PID extends its
    // wait to the teardown budget. Guard stays; no helper returns.
    struct QuitToken: Equatable {
        let pid: pid_t
        let epoch: UInt64
        let wall: TimeInterval
    }
    // Pure arbitration, Linux-tested: fresh token naming a live other -> long
    // budget; anything else -> the historical 3s duplicate behavior.
    static func restartWaitBudget(token: QuitToken?, otherPIDs: [pid_t], now: TimeInterval, maxTokenAge: TimeInterval = 120) -> TimeInterval {
        guard let t = token, otherPIDs.contains(t.pid) else { return 3.0 }
        let age = now - t.wall
        guard age >= 0, age < maxTokenAge else { return 3.0 }
        return 20.0
    }
    static let quitTokenURL = StagedRunPaths.home(FileManager.default.homeDirectoryForCurrentUser)
        .appendingPathComponent("Library/Logs/gor/quit-token.json")
    static func writeQuitToken(epoch: UInt64) {
        let token: [String: Any] = ["pid": Int(ProcessInfo.processInfo.processIdentifier),
                                    "epoch": Int(epoch),
                                    "wall": Date().timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: token) else { return }
        try? FileManager.default.createDirectory(at: quitTokenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: quitTokenURL, options: .atomic)
    }
    static func readQuitToken() -> QuitToken? {
        guard let data = try? Data(contentsOf: quitTokenURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = obj["pid"] as? Int,
              let epoch = (obj["epoch"] as? Int) ?? (obj["epoch"] as? NSNumber)?.intValue,
              let wall = (obj["wall"] as? Double) ?? (obj["wall"] as? NSNumber)?.doubleValue else { return nil }
        return QuitToken(pid: pid_t(pid), epoch: UInt64(epoch), wall: wall)
    }
    static func consumeQuitToken() { try? FileManager.default.removeItem(at: quitTokenURL) }

    // MARK: - Quit-time brightness fade

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitDebug("ShouldTerminate enter restart=\(pendingRestart)")
        Self.writeQuitToken(epoch: quitRequestEpoch &+ 1) // lets a relaunch wait out our teardown
        // AppKit may ask again while the first asynchronous quit is pending.
        // Reuse that request rather than schedule competing fade groups.
        if quitApproved { return .terminateNow }
        guard !quitReplyPending else {
            quitDebug("ShouldTerminate reentry -> existing terminateLater")
            return .terminateLater
        }
        isQuittingDeliberately = true
        GORInputPanel.closeAllForQuit(); controller?.suspendPresentationForQuit()
        quitRequestEpoch &+= 1
        let requestEpoch = quitRequestEpoch
        armQuitWatchdog(epoch: requestEpoch)
        let fadeGroup = DispatchGroup()
        fadeGroup.enter()
        drainQuitMusic { fadeGroup.leave() }
        controller?.shutDownPlaybackCamera()

        guard let controller else {
            quitReplyPending = true
            fadeGroup.notify(queue: .main) { [self] in
                completeQuitRequest(epoch: requestEpoch, reason: "no controller music drain")
            }
            quitDebug("ShouldTerminate no controller -> gated terminateLater")
            return .terminateLater
        }

        stopOverlaySync()
        checkTimer?.invalidate()

        quitReplyPending = true
        let deadline = DispatchWorkItem { [weak self] in
            self?.completeQuitRequest(epoch: requestEpoch, reason: "deadline")
        }
        quitDeadlineWorkItem = deadline
        // Normal fades finish within 1.44 seconds. Missing animation/fade
        // callbacks must not leave an invisible app waiting indefinitely.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: deadline)
        fadeGroup.enter()
        if let win = overlayWin {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.77
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                win.animator().alphaValue = 0
            }, completionHandler: {
                self.quitDebug("gate overlay complete")
                fadeGroup.leave()
            })
        } else {
            quitDebug("gate overlay skipped: no window")
            fadeGroup.leave()
        }

        if mpvProcess != nil {
            fadeGroup.enter()


            quitDebug("gate mpv fade scheduled")
            let satSteps = 22
            let satDelay = 0.44 / Double(satSteps)
            for i in 0...satSteps {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * satDelay) {
                    guard !self.quitApproved else { return }
                    let t = Double(i) / Double(satSteps)
                    let eased = t * t
                    let saturation = Int(eased * (-100))
                    controller.ipcCommand(#"{"command":["set_property","saturation",\#(saturation)]}"#)
                }
            }

            let volSteps = 33
            let volDelay = 0.66 / Double(volSteps)
            let startVolume = Double(controller.volume) * 100.0
            for i in 0...volSteps {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * volDelay) {
                    guard !self.quitApproved else { return }
                    let t = Double(i) / Double(volSteps)
                    let eased = t * t
                    let volume = Int(startVolume * (1.0 - eased))
                    controller.ipcCommand(#"{"command":["set_property","volume",\#(volume)]}"#)
                }
            }

            let briSteps = 44
            let briDelay = 0.88 / Double(briSteps)
            for i in 0...briSteps {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * briDelay) {
                    if self.quitApproved {
                        if i == briSteps { fadeGroup.leave() }
                        return
                    }
                    let t = Double(i) / Double(briSteps)
                    let eased = t * t
                    let brightness = Int(eased * (-100))
                    controller.ipcCommand(#"{"command":["set_property","brightness",\#(brightness)]}"#)
                    if i == briSteps {
                        self.quitDebug("gate mpv fade commands enqueued (not ACKed)")
                        fadeGroup.leave()
                    }
                }
            }
        }

        fadeGroup.enter()
        quitDebug("gate hardware fade requested")
        controller.fadeToOriginalBrightnessForQuit {
            self.quitDebug("gate hardware fade complete")
            fadeGroup.leave()
        }

        fadeGroup.notify(queue: .main) {
            self.completeQuitRequest(epoch: requestEpoch, reason: "all gates complete")
        }
        quitDebug("ShouldTerminate returns terminateLater")
        return .terminateLater
    }

    private func armQuitWatchdog(epoch: UInt64) {
        // Arm before synchronous camera/overlay shutdown. This is an emergency
        // best-effort exit backstop, not a wall-clock bound or HAL cleanup proof.
        let state = quitWatchdogState
        state.arm(epoch: epoch)
        quitChildKiller.log = { [weak self] message in
            guard let self = self else { return }
            self.quitDebug(message)
        }
        quitChildKiller.snapshotArmSet()
        state.updateRestart(pendingRestart)
        // Freeze the approved restart decision; late writes cannot approve it.
        state.freezeRestart(pendingRestart)
        let restartBundlePath = Bundle.main.bundlePath
        let watchdogDelay = 6.0
        quitWatchdogQueue.asyncAfter(deadline: .now() + watchdogDelay) { [self] in
            var claimedPhase = state.claimEmergency(epoch: epoch)
            while claimedPhase == -1 {
                let remaining = state.remainingPostCleanupDelay(epoch: epoch)
                Thread.sleep(forTimeInterval: max(0.01, remaining))
                claimedPhase = state.claimEmergency(epoch: epoch)
            }
            guard claimedPhase != 0 else { return }
            var killResults: [String] = []
            // Post-cleanup is exit-only except this explicit unverified-child
            // carveout: one known-PID SIGKILL attempt, no restart or restore.
            if claimedPhase == 3, let pid = state.musicTimeoutPID(), pid > 0 {
                let result = kill(pid, SIGKILL)
                let error = errno
                killResults.append("music-timeout-pid=\(pid):kill-attempt=\(result):errno=\(error)")
            }
            // Phase 3 means normal cleanup/restart arbitration returned. Only
            // exit is allowed here; never start a second restart attempt.
            // Shared helper (176a/176c): runs the graceful sequence once or
            // joins it, then always applies the idempotent SIGKILL floor
            // (watchdog reason) before the exit below.
            if claimedPhase != 3 {
                killResults.append("killOwnedChildren=\(quitChildKiller.killOwnedChildren(reason: .watchdog).summary)")
            }
            if claimedPhase != 3, state.takeEmergencyRestart() {
                // A bounded wait for the attempt, not a guarantee that open
                // or the replacement app started. Do not delay emergency exit.
                let attempted = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async { [self] in
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    task.arguments = ["-n", restartBundlePath]
                    do {
                        try task.run()
                        quitDebug("emergency restart spawn attempted childPID=\(task.processIdentifier)")
                    } catch {
                        quitDebug("emergency restart spawn failed error=\(error)")
                    }
                    attempted.signal()
                }
                let result = attempted.wait(timeout: .now() + 0.2)
                _ = result // spawn attempt unverified if wait times out
            }
            // Restore is requested on main, never call main-only brightness/HAL
            // code on this queue or wait for it before emergency exit.
            if claimedPhase != 3 {
                DispatchQueue.main.async { [weak self] in
                    self?.controller?.restoreOriginalBrightnessForQuitDeadline()
                }
            }
            // Kill/restart decisions are already made. This write opens, appends
            // and closes per call; it is an attempt, not a durable receipt.
            let exitCode = claimedPhase == 3 ? 71 : 70
            let reason = claimedPhase == 3 ? "post-cleanup-hang" : "cleanup-incomplete"
            let forcedLine = Data("gor quit watchdog epoch=\(epoch) phase=\(claimedPhase) reason=\(reason) exit=\(exitCode) kills=\(killResults.joined(separator: ",")) diagnostic_attempt_only\n".utf8)
            // No filesystem work occurs at arm time. Lazy diagnostics happen
            // after child-kill/restart decisions, and remain best effort.
            let forcedLogPath = StagedRunPaths.home(FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("Library/Logs/gor/quit-debug.log").path
            let forcedFD = Darwin.open(forcedLogPath, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600))
            if forcedFD >= 0 {
                _ = forcedLine.withUnsafeBytes { Darwin.write(forcedFD, $0.baseAddress, forcedLine.count) }
                Darwin.close(forcedFD)
            }
            Darwin._exit(claimedPhase == 3 ? 71 : 70)
        }
    }

    private func drainQuitMusic(completion: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        if quitMusicDrainFinished { completion(); return }
        quitMusicDrainWaiters.append(completion)
        guard !quitMusicDrainStarted else { return }
        quitMusicDrainStarted = true
        let child = controller?.musicController?.process
        guard let child, child.isRunning else {
            _ = controller?.musicController?.detachForQuit()
            quitDebug("music drain no-running-child; gate result=term-exit vacuous=true")
            finishQuitMusicDrain(result: .termExit)
            return
        }
        let pid = child.processIdentifier
        quitMusicCapturedPID = pid
        DispatchQueue.global(qos: .utility).async { [self] in
            if child.isRunning { child.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.3
            while child.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            var escalated = false
            if child.isRunning, pid > 0 {
                escalated = true
                let result = kill(pid, SIGKILL)
                let error = errno
                quitDebug("music escalation pid=\(pid) killResult=\(result) errno=\(error)")
            }
            quitDebug("music grace complete after escalation decision pid=\(pid) running=\(child.isRunning)")
            let reapDeadline = ProcessInfo.processInfo.systemUptime + 0.3
            while child.isRunning, ProcessInfo.processInfo.systemUptime < reapDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            let drainResult: QuitMusicResult = child.isRunning ? .timeoutStillRunning : (escalated ? .killExit : .termExit)
            if !child.isRunning {
                quitDebug("music drain result=\(escalated ? "kill-exit" : "term-exit") attribution=attempt-plus-observed-exit pid=\(pid) status=\(child.terminationStatus) reason=\(child.terminationReason.rawValue)")
            } else {
                quitDebug("music drain result=timeout-still-running pid=\(pid); child exit unverified")
            }
            DispatchQueue.main.async { [self] in finishQuitMusicDrain(result: drainResult) }
        }
        // The independent child worker is armed before Foundation handler
        // detach/reference release, which have no native nonblocking proof.
        _ = controller?.musicController?.detachForQuit()
    }

    private func finishQuitMusicDrain(result: QuitMusicResult) {
        precondition(Thread.isMainThread)
        guard !quitMusicDrainFinished else { return }
        quitMusicDrainFinished = true
        quitMusicResult = result
        quitWatchdogState.publishMusicTimeout(result == .timeoutStillRunning ? quitMusicCapturedPID : nil)
        let waiters = quitMusicDrainWaiters
        quitMusicDrainWaiters.removeAll()
        waiters.forEach { $0() }
    }

    private func completeQuitRequest(epoch: UInt64, reason: String) {
        precondition(Thread.isMainThread)
        guard quitReplyPending, epoch == quitRequestEpoch else { return }
        if !quitMusicDrainFinished {
            drainQuitMusic { [weak self] in
                self?.completeQuitRequest(epoch: epoch, reason: reason)
            }
            return
        }
        guard let musicResult = quitMusicResult else { return }
        // Timeout is an explicit unverified-child result, not success. The
        // emergency watchdog retains authority while cleanup proceeds.
        quitDebug("quit gate music result=\(musicResult.rawValue) allow-cleanup=true child-exit-verified=\(musicResult != .timeoutStillRunning)")
        guard quitWatchdogState.approve(epoch: epoch) else { return }
        quitReplyPending = false
        quitApproved = true
        quitDeadlineWorkItem?.cancel()
        quitDeadlineWorkItem = nil
        if reason == "deadline" {
            // Main-thread restore is best effort. The independent watchdog
            // can still attempt exit if this HAL call blocks; scheduling is not guaranteed.
            controller?.restoreOriginalBrightnessForQuitDeadline()
        }
        quitDebug("terminate reply true reason=\(reason)")
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    // MARK: - Menu Actions

    func applicationWillTerminate(_ aNotification: Notification) {
        quitDebug("WillTerminate enter restart=\(pendingRestart)")
        _ = PoseTraceRing.shared.writeOnQuit()
        _ = AVSessionTrace.shared.writeOnQuit()
        CommandLatencyTrace.shared.writeOnQuit()
        // 176a: owned children die on every termination, before the
        // phase/epoch gate below. No state writes, no exit in here.
        _ = quitChildKiller.killOwnedChildren(reason: .willTerminate)
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        // Release the audio tap before its mpv target and unrelated cleanup.
        quitDebug("cleanup before SCE stop")
        if #available(macOS 14.2, *) {
            ScreenCaptureEngine.shared.stopForQuit()
        } else {
            ScreenCaptureEngine.shared.stop()
        }
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        magnetBrowser?.stop()
        TunnelForBlockedHosts.shared.shutdown()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        removeMPVOutputDeviceListener()
        
        stopOverlaySync()
        checkTimer?.invalidate()
        
        if let activity = mainThreadPriorityActivity {
            ProcessInfo.processInfo.endActivity(activity)
            mainThreadPriorityActivity = nil
        }
        
        overlayWin?.orderOut(nil)
        overlayWin = nil
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        quitDebug("cleanup before music")
        // Music generation/pipe cleanup and bounded child drain were awaited
        // before approval. Never schedule an unawaited grace during app exit.
        _ = controller?.musicController?.detachForQuit()

        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        quitDebug("cleanup before mpv kill")
        // Deliberate-quit flag stays in the chain (state write). The shared
        // helper already ran at willTerminate entry, so this is normally a
        // fast already-done. Group kill dropped (176a: own PIDs only).
        isQuittingDeliberately = true
        _ = quitChildKiller.killOwnedChildren(reason: .approvedChain)

        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        quitDebug("cleanup before torrent stop")
        stopTorrent()
        quitDebug("cleanup before mega stop")
        stopMegaRelay()
        try? FileManager.default.removeItem(atPath: StagedRunPaths.tmp("/tmp/webtorrent_stream"))
        try? FileManager.default.removeItem(atPath: ipcPath)
        
        quitDebug("cleanup before crop cancel")
        controller?.cancelCropDetection()
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        if !StagedRunPaths.active {
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        cleanup.arguments = ["-f", "WorkflowServiceRunner"]
        try? cleanup.run()
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        let killChrome = Process()
        killChrome.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killChrome.arguments = ["-9", "chrome-headless-shell"]
        try? killChrome.run()
        }
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        if !StagedRunPaths.active, let tmpItems = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") {
            for item in tmpItems where item.hasPrefix("gor-chrome-")
                || item.hasPrefix("hidden_mpv_") || item.hasPrefix("crop_frame_") {
                try? FileManager.default.removeItem(atPath: "/tmp/\(item)")
            }
        }
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }


        quitDebug("cleanup complete restart=\(pendingRestart)")
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        if quitWatchdogState.claimRestart() {
            let bundlePath = Bundle.main.bundlePath
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", bundlePath]
            task.terminationHandler = { process in
                self.quitDebug("open child exit status=\(process.terminationStatus) reason=\(process.terminationReason.rawValue)")
            }
            quitDebug("open spawn attempt bundle=\(bundlePath)")
            do {
                try task.run()
                quitDebug("open spawn success childPID=\(task.processIdentifier); exit status callback is best-effort during app exit")
            } catch {
                quitDebug("open spawn failed error=\(error.localizedDescription)")
            }
        } else {
            quitDebug("relaunch skipped: no arm-time approved restart (pendingRestart live=\(pendingRestart))")
        }
        if quitWatchdogState.finish(epoch: quitRequestEpoch) {
            quitDebug("WillTerminate return: normal cleanup finished")
        } else {
            quitDebug("WillTerminate loser returns; watchdog alone owns exit")
        }
    }

    // MARK: - Chrome-driven HDR hwdec override


    // MARK: - IPTV mpv Profile

    func applyIPTVProfile() {
        guard controller != nil else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let ctrl = self.controller else { return }

            let profile = """
            {"command":["set","demuxer-readahead-secs","8"]}
            {"command":["set","demuxer-max-bytes","32M"]}
            {"command":["set","demuxer-max-back-bytes","8M"]}
            {"command":["set","prefetch-playlist","no"]}
            {"command":["set","cache-pause-initial","yes"]}
            {"command":["set","cache-pause","no"]}
            {"command":["set","cache-secs","6"]}
            {"command":["set","audio-buffer","0.5"]}
            {"command":["set","hwdec","no"]}
            {"command":["set","hls-bitrate","max"]}
            {"command":["set","network-timeout","5"]}
            {"command":["set","pause","no"]}
            """
            ctrl.batchIPC(profile)

            print("[GOR] IPTV profile applied + forced play")
        }
    }

    /// Canonical per-file baseline: the launch-arg profile plus mpv defaults
    /// for every option a stream branch mutates. Runs on each file open so
    /// pixeldrain/MEGA/torrent settings cannot leak into the next file
    /// (pass-5 #7).
    func restoreDefaultProfile() {
        guard let ctrl = controller else { return }

        let restore = """
        {"command":["script-message-to","photon","set-live","false"]}
        {"command":["set","cache","yes"]}
        {"command":["set","cache-secs","8"]}
        {"command":["set","cache-pause-initial","no"]}
        {"command":["set","cache-pause","yes"]}
        {"command":["set","cache-pause-wait","10"]}
        {"command":["set","cache-on-disk","no"]}
        {"command":["set","demuxer-readahead-secs","10"]}
        {"command":["set","demuxer-max-bytes","128M"]}
        {"command":["set","demuxer-max-back-bytes","32M"]}
        {"command":["set","demuxer-seekable-cache","auto"]}
        {"command":["set","prefetch-playlist","no"]}
        {"command":["set","audio-buffer","0.5"]}
        {"command":["set","hwdec","auto-safe"]}
        {"command":["set","vd-lavc-skiploopfilter","default"]}
        {"command":["set","hls-bitrate","0"]}
        {"command":["set","network-timeout","60"]}
        {"command":["set","stream-buffer-size","128k"]}
        """
        ctrl.batchIPC(restore)

        print("[GOR] Default profile restored")
    }

    /// Playback binary. nil when vendor assets are unresolved (the miss is
    /// already logged by GORResources; the caller degrades explicitly).
    func findMPV() -> String? {
        GORResources.vendor()?.appendingPathComponent("mpv/bin/mpv").path
    }
    
    func setEventTapEnabled(_ enabled: Bool) {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: enabled && PanelKeyOwnership.shared.mayKeyPlayerWindow())
        }
    }
}

// MARK: - extensions
// ================================================================
//  AXUIElement - AXUIElement
// ================================================================
extension AXUIElement {
    func isMinimized() -> Bool {
        var val: CFTypeRef?
        if AXUIElementCopyAttributeValue(self, kAXMinimizedAttribute as CFString, &val) == .success,
           let number = val as? NSNumber { return number.boolValue }
        return false
    }
}

// ================================================================
//  AXValue - AXValue
// ================================================================
extension AXValue {
    func toPoint() -> CGPoint? { var v = CGPoint.zero;  return AXValueGetValue(self, .cgPoint, &v) ? v : nil }
    func toSize()  -> CGSize?  { var v = CGSize.zero;   return AXValueGetValue(self, .cgSize,  &v) ? v : nil }
}

// ================================================================
//  NSRect - NSRect
// ================================================================
extension NSRect {
    func isAlmostEqual(to other: NSRect, epsilon: CGFloat = 0.5) -> Bool {
        abs(origin.x - other.origin.x) < epsilon &&
        abs(origin.y - other.origin.y) < epsilon &&
        abs(size.width  - other.size.width)  < epsilon &&
        abs(size.height - other.size.height) < epsilon
    }
}

// ================================================================
//  AppDelegate - application lifecycle
// ================================================================
extension AppDelegate: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let tf = control as? NSTextField {
                commitURL(tf)
            }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            (control.window as? NSPanel)?.close()
            isShowingInputPanel = false
            overlayWin?.ignoresMouseEvents = false
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        return false
    }
    
}


enum Diag {
    // New media telemetry only; build.sh sets the signed bundle policy.
    // Missing key is OFF. The two Diag.swift loggers stay independently ON.
    // Node: --gor-diag=true|false. mpv: --script-opts-add=gor-diag=true|false.
    static let mediaTelemetryEnabled = Bundle.main.object(forInfoDictionaryKey: "GORMediaTelemetry") as? Bool ?? false

    static func mediaRecord(_ line: @autoclosure () -> String) {
        guard mediaTelemetryEnabled else { return }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        let prefix = "\(f.string(from: Date())) "
        let marker = "...[truncated]"
        var text = line().replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let budget = 4096 - prefix.utf8.count - 1
        if text.utf8.count > budget {
            while text.utf8.count + marker.utf8.count > budget { text.removeLast() }
            text += marker
        }
        let data = Data((prefix + text + "\n").utf8)
        _ = BoundedDiskWriter.append(data, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
    }

    // Called after writable config seeding, before the mpv subprocess starts.
    // A bundle manifest is immutable; hashes are from the actual installed tree.
    static func verifyBuildManifest(configDir: String) {
        guard mediaTelemetryEnabled else { return }
        let fm = FileManager.default
        guard let resource = Bundle.main.resourceURL else {
            mediaRecord("MANIFEST file=gor-build-manifest.json missing reason=no-resource-root")
            return
        }
        let manifest = resource.appendingPathComponent("gor-build-manifest.json")
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = object["scripts"] as? [String: String], !scripts.isEmpty else {
            mediaRecord("MANIFEST file=gor-build-manifest.json missing reason=absent-or-invalid")
            return
        }
        mediaRecord("MANIFEST version=\(object["version"] as? String ?? "unknown") build_time=\(object["build_time"] as? String ?? "unknown")")
        let root = URL(fileURLWithPath: configDir).appendingPathComponent("scripts", isDirectory: true)
        for name in scripts.keys.sorted() {
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.hasPrefix("/"), !parts.contains(".."), !parts.contains(""), name.hasSuffix(".lua") else {
                mediaRecord("MANIFEST file=\(name) MISMATCH reason=invalid-path")
                continue
            }
            let file = root.appendingPathComponent(name)
            guard let bytes = try? Data(contentsOf: file) else {
                mediaRecord("MANIFEST file=\(name) missing")
                continue
            }
            let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let status = actual == scripts[name] ? "MATCH" : "MISMATCH"
            mediaRecord("MANIFEST file=\(name) \(status) actual=\(actual) expected=\(scripts[name] ?? "missing")")
        }
        if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in enumerator {
                let name = String(file.path.dropFirst(root.path.count + 1))
                if file.pathExtension == "lua", scripts[name] == nil {
                    mediaRecord("MANIFEST file=\(name) MISMATCH reason=unlisted-script")
                }
            }
        }
    }

    static let enabled: Bool = ProcessInfo.processInfo.environment["GOR_DIAG"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print(message())
    }
}
