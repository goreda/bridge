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

// ================================================================
//  DraggableOverlayWindow - drag destination window
// ================================================================
final class DraggableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var logWriterProcess: Process?

    var mpvProcess: Process?
    var overlayWin: NSWindow?
    var controller: PPController?
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
    private var mpvRestoreWritePending = false
    private var mpvFullscreenEpoch: UInt64 = 0
    // Observation windows, not measured native performance claims. Native AX false
    // uses the shorter window; unsupported AX needs a longer property-backed settle.
    private static let mpvGeometryNativeSettle: TimeInterval = 0.35
    private static let mpvGeometryFallbackSettle: TimeInterval = 0.60
    private static let mpvGeometryTimeout: TimeInterval = 5
    private var mpvEntryTarget: NSRect?
    private var mpvEntryDisplays: [NSRect] = []
    private var mpvEntryStarted: TimeInterval = 0
    private var mpvEntryStableFrame: NSRect?
    private var mpvEntryStableSince: TimeInterval = 0
    private var mpvEntryAttempted = false
    private var mpvEntryWritePending = false
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
    private var overlayDragActive = false
    private var overlayDragSettleUntil: TimeInterval = 0
    private var overlayPositionInitializing = false
    private var overlayBufferedDelta = CGPoint.zero
    private var overlayPositionWriteInFlight = false
    private var overlayPendingPosition: CGPoint?
    private let minimizeQueue = DispatchQueue(label: "gor.window.minimize", qos: .userInitiated)
    private var minimizeGeneration: UInt64 = 0
    private var minimizePending = false
    // Overlay is hidden the instant a miniaturize starts (AX notification or confirmed
    // window-minimized command); a lagging AX sample that still says "not minimized"
    // must not re-show it until this deadline passes or AX reports minimized=true.
    private var overlayMinimizeHoldUntil: TimeInterval = 0

    
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
    var ytdlpUpdateCheckedThisSession = false
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
            lock.lock(); restartRequested = requested; lock.unlock()
        }
        func claimRestart() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard restartRequested, !restartClaimed else { return false }
            restartClaimed = true
            return true
        }
    }
    private let quitWatchdogState = QuitWatchdogState()
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
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
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
        guard !Self.hasLaunched else { return }
        Self.hasLaunched = true

        Thread.current.qualityOfService = .userInteractive
        ThreadCpuDiag.start()  // diagnostic: set ThreadCpuDiag.enabled = false to turn off
        MainThreadDiag.start()  // diagnostic: main run loop busy time and counted callbacks

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
                    existing.activate(options: [.activateAllWindows])
                    exit(0)
                }
                Self.consumeQuitToken()
                quitDebug("startup takeover: other instances exited")
            }
        }

        let logPath = "/tmp/gor_direct.log"
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
        writer.arguments = ["--quiet", "--timestamp", String(timestamp), "--cpu-info", String(cpuInfo)]
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
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        ProcessInfo.processInfo.disableAutomaticTermination("mpv ipc sync active")
        
        let cleanupTorrent = Process()
        cleanupTorrent.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        cleanupTorrent.arguments = ["-f", "wt_server\\.mjs"]
        try? cleanupTorrent.run()
        
        buildMenuBar()
        
        try? FileManager.default.removeItem(atPath: "/tmp/gor_watch_later")
        try? FileManager.default.createDirectory(atPath: "/tmp/gor_watch_later", withIntermediateDirectories: true)
        
        // rm argv never globbed without a shell - enumerate /tmp instead.
        if let tmpItems = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") {
            for item in tmpItems where item.hasPrefix("gor-chrome-")
                || item.hasPrefix("hidden_mpv_") || item.hasPrefix("crop_frame_") {
                try? FileManager.default.removeItem(atPath: "/tmp/\(item)")
            }
        }

        killOrphanedMPVProcesses()

        
        try? FileManager.default.removeItem(atPath: ipcPath)
        launchMPV(file: videoPath.isEmpty ? nil : videoPath)

        installMPVOutputDeviceListener()

        setupEventTap()
        
        let args = CommandLine.arguments
        if args.contains("--music") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.controller?.toggleMusicMode()
            }
        }
        
        ArchiveLibrary.shared.load()
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
                    if selfPtr.isShowingInputPanel {
                        return Unmanaged.passRetained(event)
                    }
                    if let tap = selfPtr.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown else { return Unmanaged.passRetained(event) }

                if selfPtr.isShowingInputPanel {
                    return Unmanaged.passRetained(event)
                }

                let flags = event.flags
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

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

    // A dev source path is explicit and never inferred from a nearby app.
    static func devVendorRoot() -> URL? {
        let fm = FileManager.default
        let setting = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        let source = dev ?? Bundle.main.resourceURL?
            .appendingPathComponent("vendor/mpv", isDirectory: true)
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
        // Prefer the verified onedir release. Keep its complete _internal tree
        // beside the executable; copying only the executable breaks loading.
        let standalone = Bundle.main.resourcePath! + "/vendor/yt-dlp-standalone/yt-dlp_macos"
        let root = URL(fileURLWithPath: standalone).deletingLastPathComponent()
        if fm.isExecutableFile(atPath: standalone),
           let data = try? Data(contentsOf: root.appendingPathComponent("GOR-CLOSURE.json")),
           let files = try? JSONDecoder().decode([String: String].self, from: data),
           files.count == 134,
           files.keys.allSatisfy({ rel in
               !rel.hasPrefix("/") && !rel.split(separator: "/").contains("..") &&
               ((try? root.appendingPathComponent(rel).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
           }) {
            return standalone
        }
        let bundled = Bundle.main.resourcePath! + "/vendor/yt-dlp"
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gor", isDirectory: true)
        let staged = support.appendingPathComponent("yt-dlp").path
        func mtime(_ p: String) -> Date {
            (try? fm.attributesOfItem(atPath: p)[.modificationDate] as? Date) ?? .distantPast
        }
        if !fm.fileExists(atPath: staged) || mtime(bundled) > mtime(staged) {
            try? fm.createDirectory(at: support, withIntermediateDirectories: true)
            try? fm.removeItem(atPath: staged)
            guard (try? fm.copyItem(atPath: bundled, toPath: staged)) != nil else { return bundled }
        }
        return staged
    }

    // NOT_APPLIED F9/F10 trial: default OFF until native startup/exit tests.
    private func armStartupExitLogCollector(configDir: String) {
        // Recover a prior interrupted watch, then arm this process's exit collector.
        // No collection in build.sh; the detached helper waits for owner exit.
        if let helper = Bundle.main.resourceURL?.appendingPathComponent("gor-session-log-helper.py"),
           FileManager.default.isReadableFile(atPath: helper.path) {
            let watcher = Process()
            watcher.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            watcher.arguments = [helper.path, "arm", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath, configDir]
            watcher.standardInput = FileHandle.nullDevice
            watcher.standardOutput = FileHandle.nullDevice
            watcher.standardError = FileHandle.nullDevice
            watcher.terminationHandler = { process in
                if process.terminationStatus != 0 { NSLog("[GOR] exit log watcher failed to arm") }
            }
            do {
                try watcher.run()
            } catch { NSLog("[GOR] exit log watcher unavailable: %@", error.localizedDescription) }
        }
    }

    // MARK: - MPV Launch
    func launchMPV(file: String?) {
        photonMenuStates = Self.photonMenuDefaults
        for key in ["bright", "sharp", "grain"] { photonMenuStates[key] = photonEnabled }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: findMPV())

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
        var args: [String] = [
            "--config-dir=\(configDir)",
            "--input-ipc-server=\(ipcPath)",
            "--idle=yes",
            "--force-window=yes",
            "--keep-open=yes",
            "--no-native-fs",
            "--geometry=40%+50%+50%",
            "--pause",
            
            "--no-border",
            "--no-osc",
            "--cursor-autohide=no",
            "--cursor-autohide-fs-only=no",
            "--script-opts=osc-visibility=never",
            "--osd-level=0",
            "--sub-visibility=no",
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
            "--watch-later-directory=/tmp/gor_watch_later",
        ]
        if let f = file { args.append(f) }
        
        
        let ytdlpPath = AppDelegate.stagedYtDlpPath()
        if FileManager.default.fileExists(atPath: ytdlpPath) {
            args.append("--script-opts=ytdl_hook-ytdl_path=\(ytdlpPath)")
            // Official 2026.08.19 supports Node >=22 but enables only Deno
            // by default. Use the working bundled runtime, not the source tree.
            let nodePath = Bundle.main.resourcePath! + "/vendor/node/node"
            if ytdlpPath.contains("/yt-dlp-standalone/"),
               FileManager.default.isExecutableFile(atPath: nodePath) {
                let runtime = "node:" + nodePath
                args.append("--ytdl-raw-options-append=js-runtimes=\(runtime)")
            }
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

        p.terminationHandler = { [weak self] _ in
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
                print("[mpv] \(rawLine)")

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
                            let isHUD = clean.hasPrefix("photon")
                            let msg = clean
                            // photon's own state prints are bare lines
                            // ("photon" / "photoff" / "photoff  (203 nit)");
                            // photon-hud's 4Hz frames always carry a tab.
                            // Only bare lines may move the mirror - HUD frames
                            // used to force it back to true ~250ms after F9
                            // (pass-5 #1).
                            DispatchQueue.main.async { [weak self, weak p] in
                                guard let self, let p, self.mpvProcess === p else { return }
                                if !clean.contains("\t") {
                                    if clean == "photon" {
                                        self.photonEnabled = true
                                    } else if clean.hasPrefix("photoff") {
                                        self.photonEnabled = false
                                    }
                                }
                                self.controller?.spineUI.showMPVOSD(msg, animated: !isHUD)
                            }
                        }
                    }
                }
            }
        }

        do { try p.run() } catch { return }
        ScreenCaptureEngine.shared.stopAudioCapture()
        mpvProcess = p
        ScreenCaptureEngine.shared.mpvPID = p.processIdentifier
        setpgid(p.processIdentifier, ProcessInfo.processInfo.processIdentifier)

        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainThreadDiag.count("checkTimer")
            guard let self = self else { return }
            
            if self.controller == nil && FileManager.default.fileExists(atPath: self.ipcPath) {
                let ctrl = PPController(frame: .zero, ipcPath: self.ipcPath)
                self.controller = ctrl
                ctrl.ipcCommand("{\"command\":[\"keybind\",\"Meta+o\",\"ignore\"]}")
            }
            
            self.findMPVWindow()
            
            guard !self.isQuittingDeliberately else { return }

            if let mpv = self.mpvProcess, mpv.isRunning {
                if self.controller != nil && !FileManager.default.fileExists(atPath: self.ipcPath) {
                    kill(self.mpvProcess?.processIdentifier ?? 0, SIGKILL)
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

        let script = Bundle.main.resourcePath! + "/vendor/update-chromium.py"
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
        guard let binary = Bundle.main.path(
            forResource: ArchiveConfig.chromiumResource,
            ofType: nil,
            inDirectory: ArchiveConfig.chromiumDirectory
        ) else {
            print("[chromium-update] bundled browser missing")
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
        if ytdlpPath.contains("/yt-dlp-standalone/") {
            // One bounded fresh URL resolution per load intent, WITHOUT -U.
            // This is a retry, not proof the CDN403 root cause is cured.
            ytdlpUpdateInProgress = false
            guard youtubePlaybackGeneration == generation, lastPlayedURL == url,
                  mpvProcess === playbackProcess else { return }
            print("[yt-dlp-recovery] standalone extractor: one fresh resolution, no updater")
            playMedia(url: url, title: title, startPos: failurePosition, subtitleURLs: subtitles)
            youtubeRetryAttempted = true
            return
        }
        guard !ytdlpUpdateCheckedThisSession else { ytdlpUpdateInProgress = false; return }
        ytdlpUpdateCheckedThisSession = true
        print("[yt-dlp-recovery] verified player failure; checking extractor update once this session")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let update = Process()
            update.executableURL = URL(fileURLWithPath: ytdlpPath)
            update.arguments = ["-U"]
            update.standardOutput = FileHandle.nullDevice
            update.standardError = FileHandle.nullDevice
            let before = try? Data(contentsOf: URL(fileURLWithPath: ytdlpPath))
            var succeeded = false
            do {
                try update.run()
                update.waitUntilExit()
                let after = try? Data(contentsOf: URL(fileURLWithPath: ytdlpPath))
                succeeded = update.terminationStatus == 0 && before != nil && after != nil && before != after
                print("[yt-dlp-recovery] update status=\(update.terminationStatus) extractorChanged=\(succeeded)")
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
        win.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        win.ignoresMouseEvents = false
        win.delegate = self

        let ctrl = PPController(frame: NSRect(origin: .zero, size: frame.size), ipcPath: ipcPath)
        ctrl.autoresizingMask = [.width, .height]
        win.contentView = ctrl

        win.alphaValue = 0
        win.orderFrontRegardless()
        win.makeKeyAndOrderFront(nil)
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
            NSApp.activate(ignoringOtherApps: true)
            self.overlayWin?.orderFrontRegardless()
        }

        let o2 = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == ProcessInfo.processInfo.processIdentifier,
                  let mpvPID = self.mpvProcess?.processIdentifier else { return }
            let axApp = AXUIElementCreateApplication(mpvPID)
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, true as CFTypeRef)
        }

        appActivationObservers = [o1, o2]
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

    func syncOverlay() {
        MainThreadDiag.count("syncOverlay")
        guard !isQuittingDeliberately, let ax = axWindow, let win = overlayWin else { return }
        // Mouse-up can be lost when focus/window/Space changes mid-drag.
        if overlayDragActive && NSEvent.pressedMouseButtons & 1 == 0 {
            resetMpvPositionCache()
            return
        }
        if overlaySampleInFlight { overlaySamplePending = true; return }
        overlaySampleInFlight = true
        let generation = overlaySyncGeneration
        let dragGeneration = overlayDragGeneration
        let fullscreenEpoch = mpvFullscreenEpoch
        let screenFrames = NSScreen.screens.map { $0.frame }
        let screenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 1280
        overlayAXQueue.async { [weak self, weak win] in
            let minimized = Self.axBool(ax, kAXMinimizedAttribute)
            let nativeFullscreen = Self.axBool(ax, "AXFullScreen")
            let frame = Self.readAXFrame(ax, screenHeight: screenHeight)
            DispatchQueue.main.async { [weak self, weak win] in
                guard let self else { return }
                self.overlaySampleInFlight = false
                guard generation == self.overlaySyncGeneration, let win,
                      self.overlayWin === win, !self.isQuittingDeliberately else {
                    if self.overlaySamplePending { self.overlaySamplePending = false; self.syncOverlay() }
                    return
                }
                if fullscreenEpoch == self.mpvFullscreenEpoch {
                    self.trackMPVFullscreen(native: nativeFullscreen, minimized: minimized,
                        frame: frame, screenFrames: screenFrames, ax: ax,
                        screenHeight: screenHeight, generation: generation)
                }
                if minimized == true {
                    self.overlayMinimizeHoldUntil = 0
                    win.alphaValue = 0
                    win.orderOut(nil)
                    win.ignoresMouseEvents = true
                } else if minimized == false {
                    if ProcessInfo.processInfo.systemUptime < self.overlayMinimizeHoldUntil {
                        // Minimize in flight: AX has not caught up yet. Stay hidden.
                    } else if !win.isVisible || win.alphaValue < 1 {
                        win.alphaValue = 1
                        win.orderFrontRegardless()
                    }
                    // Locally driven drag owns the frame until mouse-up. Old AX samples
                    // must not pull the overlay back behind the user's latest pointer.
                    if dragGeneration == self.overlayDragGeneration, !self.overlayDragActive,
                       !self.overlayPositionInitializing, !self.overlayPositionWriteInFlight,
                       self.overlayPendingPosition == nil, !self.mpvRestoreWritePending, !self.mpvEntryWritePending,
                       let frame, ProcessInfo.processInfo.systemUptime >= self.overlayDragSettleUntil,
                       !frame.isAlmostEqual(to: self.lastFrame) {
                        self.lastFrame = frame
                        win.setFrame(frame, display: false, animate: false)
                        self.boostOverlaySync()
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
        overlayDragGeneration &+= 1
        overlayDragActive = false
        cachedMpvPosition = nil
        overlayBufferedDelta = .zero
        overlayPendingPosition = nil
        mpvWindowedCandidate = nil
    }

    private func beginMPVFullscreenEntry(frame: NSRect?, displays: [NSRect]) {
        prepareMPVFullscreenTransition()
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
                    self.overlayWin?.setFrame(receipt, display: false, animate: false)
                    print("[window-sync] fullscreen entry AX-verified")
                } else { print("[window-sync] fullscreen entry correction not confirmed; no retry") }
                self.syncOverlay()
            }
        }
    }

    // mpv property changes include double-clicks handled inside mpv, not only gor menu commands.
    func noteMPVFullscreen(_ fullscreen: Bool, from source: PPController) {
        guard controller === source, !isQuittingDeliberately else { return }
        if mpvObservedFullscreen != fullscreen {
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
            mpvRestoreFrame = mpvWindowedFrame
            mpvRestoreStarted = now
            mpvRestoreStableFrame = nil
            mpvRestoreStableSince = now
            cachedMpvPosition = nil
        }
        if let target = mpvRestoreFrame {
            guard !mpvRestoreWritePending else { return }
            if now - mpvRestoreStarted > Self.mpvGeometryTimeout {
                mpvRestoreFrame = nil
                print("[window-sync] fullscreen restore timed out; saved frame retained")
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
            // Do not invent coordinates after a display disconnect. Keep the saved frame for review.
            guard screenFrames.contains(where: { $0.intersects(target) }) else {
                mpvRestoreFrame = nil
                print("[window-sync] fullscreen restore stopped: saved display is unavailable")
                return
            }
            mpvRestoreWritePending = true
            let epoch = mpvFullscreenEpoch
            overlayAXQueue.async { [weak self] in
                let current = DispatchQueue.main.sync { [weak self] in
                    guard let self, let currentAX = self.axWindow else { return false }
                    return CFEqual(currentAX, ax) && NSScreen.screens.map({ $0.frame }) == screenFrames &&
                        generation == self.overlaySyncGeneration && epoch == self.mpvFullscreenEpoch &&
                        !self.isQuittingDeliberately && self.mpvObservedFullscreen != true &&
                        !self.overlayDragActive && self.mpvRestoreWritePending
                }
                var success = false
                if current, Self.axBool(ax, "AXFullScreen") != true,
                   Self.axBool(ax, kAXMinimizedAttribute) == false {
                    var size = target.size
                    var point = CGPoint(x: target.minX, y: screenHeight - target.maxY)
                    if let sizeValue = AXValueCreate(.cgSize, &size),
                       let pointValue = AXValueCreate(.cgPoint, &point) {
                        let a = AXUIElementSetAttributeValue(ax, kAXSizeAttribute as CFString, sizeValue)
                        let b = AXUIElementSetAttributeValue(ax, kAXPositionAttribute as CFString, pointValue)
                        let actual = Self.readAXFrame(ax, screenHeight: screenHeight)
                        success = a == .success && b == .success &&
                            (actual.map { $0.isAlmostEqual(to: target) } ?? false)
                    }
                }
                let verified = success
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.overlaySyncGeneration,
                          epoch == self.mpvFullscreenEpoch else { return }
                    self.mpvRestoreWritePending = false
                    self.cachedMpvPosition = nil
                    if verified && NSScreen.screens.map({ $0.frame }) == screenFrames {
                        self.mpvRestoreFrame = nil
                        self.lastFrame = target
                        self.overlayWin?.setFrame(target, display: false, animate: false)
                        print("[window-sync] fullscreen frame restored and AX-verified")
                    } else {
                        print("[window-sync] fullscreen restore not confirmed; no success receipt")
                    }
                    self.boostOverlaySync()
                    self.syncOverlay()
                }
            }
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
        // New user movement wins over an in-flight fullscreen restoration.
        mpvWindowedCandidate = nil
        if mpvRestoreFrame != nil { mpvFullscreenEpoch &+= 1 }
        mpvRestoreFrame = nil
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
                    self.overlayWin?.setFrame(receipt, display: false, animate: false)
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

    /// Crop-detect progress from PPController: while the detector is still
    /// seeking usable frames the menu item says so, instead of looking dead
    /// after a click during a dark scene. nil restores the plain title.
    func setCropDetectMenuStatus(_ status: String?) {
        cropDetectMenuItem?.title = status.map { "re-detect crop (\($0))" } ?? "re-detect crop"
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
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
        if action == #selector(menuVRMono) {
            menuItem.state = (currentVRMode == .mono) ? .on : .off
            return true
        }
        if action == #selector(menuVRSideBySide) {
            menuItem.state = (currentVRMode == .sideBySide) ? .on : .off
            return true
        }
        if action == #selector(menuVRMode180) {
            menuItem.state = (currentVRMode == .vr180) ? .on : .off
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
        if action == #selector(menuHeadTracking) {
            menuItem.state = (controller?.headTrackingEnabled == true) ? .on : .off
            return true
        }
        if action == #selector(menuSaveSrcSubtitle) {
            return controller?.subtitleView.canExportSrcSubtitle ?? false
        }
        return true
    }

    func buildMenuBar() {
        let main = NSMenu()

        // ── app ─────────────────────────────────────────────────────────────────
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(item("about", action: #selector(showAbout), key: "", mods: []))
        appMenu.addItem(.separator())
        appMenu.addItem(item("check chromium update", action: #selector(menuCheckChromiumUpdate), key: ""))
        // No key: Shift+Q is forwarded to mpv by InputController, never reaching menus.
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
        fileMenu.addItem(item("open archive…", action: #selector(openArchive), key: "a", mods: [.command, .shift]))
        fileMenu.addItem(item("search magnets…", action: #selector(openMagnetSearch), key: "m"))
        fileMenu.addItem(item("iptv",          action: #selector(menuIptvMode), key: "t"))
        fileMenu.addItem(item("music mode",    action: #selector(menuMusicMode), key: ""))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("reload",      action: #selector(menuReload), key: "r", mods: .command))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("stop",        action: #selector(menuStop), key: ""))
        fileMenu.addItem(item("quit & save position", action: #selector(menuQuitSave), key: "q", mods: [.command, .shift]))

        // ── playback ────────────────────────────────────────────────────────────
        let playItem = NSMenuItem(); playItem.title = "playback"; main.addItem(playItem)
        let playMenu = NSMenu(title: "playback"); playItem.submenu = playMenu
        playMenu.addItem(item("play / pause",       action: #selector(menuPlayPause), key: " ", mods: []))
        playMenu.addItem(.separator())
        playMenu.addItem(item("mute",                 action: #selector(menuMute),      key: "←", mods: .command))
        playMenu.addItem(item("max volume",           action: #selector(menuVolMax),    key: "→", mods: .command))
        playMenu.addItem(item("seek forward 60s",     action: #selector(menuSeekF60),   key: "↑", mods: []))
        playMenu.addItem(item("seek backward 60s",    action: #selector(menuSeekB60),   key: "↓", mods: []))
        playMenu.addItem(item("seek forward 20s",     action: #selector(menuSeekF20),   key: "↑", mods: .command))
        playMenu.addItem(item("seek backward 20s",    action: #selector(menuSeekB20),   key: "↓", mods: .command))
        playMenu.addItem(item("seek forward 5s",      action: #selector(menuSeekF5),    key: ""))
        playMenu.addItem(item("seek backward 5s",     action: #selector(menuSeekB5),    key: ""))
        // "." is mpv's default frame-step. frame-back's default "," is bound to
        // sub-scale in input.conf, so previous frame stays click-only.
        playMenu.addItem(item("next frame",           action: #selector(menuFrameNext), key: ".", mods: []))
        playMenu.addItem(item("previous frame",       action: #selector(menuFramePrev), key: ""))
        
        playMenu.addItem(item("seek to beginning",  action: #selector(menuSeekStart), key: ""))
        playMenu.addItem(.separator())
        playMenu.addItem(item("next chapter",       action: #selector(menuChapterNext), key: ""))
        playMenu.addItem(item("previous chapter",   action: #selector(menuChapterPrev), key: ""))
        playMenu.addItem(.separator())
        playMenu.addItem(item("speed up",           action: #selector(menuSpeedUp),    key: "]", mods: []))
        playMenu.addItem(item("speed down",         action: #selector(menuSpeedDown),  key: "[", mods: []))
        playMenu.addItem(item("speed ×2",           action: #selector(menuSpeedDouble), key: ""))
        playMenu.addItem(item("speed ×0.5",         action: #selector(menuSpeedHalf),   key: ""))
        playMenu.addItem(item("reset speed",        action: #selector(menuSpeedReset),  key: ""))
        playMenu.addItem(.separator())
        playMenu.addItem(item("loop file",          action: #selector(menuLoopFile),    key: "l", mods: [.command, .shift]))
        playMenu.addItem(item("a-b loop",           action: #selector(menuABLoop),      key: ""))
        playMenu.addItem(.separator())
        playMenu.addItem(item("next in playlist",   action: #selector(menuPlaylistNext), key: ">", mods: []))
        playMenu.addItem(item("previous in playlist", action: #selector(menuPlaylistPrev), key: "<", mods: []))

        // ── video ───────────────────────────────────────────────────────────────
        let videoItem = NSMenuItem(); videoItem.title = "video"; main.addItem(videoItem)
        let videoMenu = NSMenu(title: "video"); videoItem.submenu = videoMenu
        videoMenu.addItem(item("toggle fullscreen",     action: #selector(menuFullscreen),  key: "f", mods: []))
        videoMenu.addItem(item("toggle always on top",  action: #selector(menuOntop),       key: ""))
        videoMenu.addItem(.separator())
        videoMenu.addItem(item("zoom in",               action: #selector(menuZoomIn),      key: "=", mods: []))
        videoMenu.addItem(item("zoom out",              action: #selector(menuZoomOut),     key: "-", mods: []))
        videoMenu.addItem(item("reset zoom & pan",      action: #selector(menuZoomReset),   key: ""))
        videoMenu.addItem(.separator())
        videoMenu.addItem(item("panscan +",             action: #selector(menuPanscanIn),   key: "e", mods: []))
        videoMenu.addItem(item("panscan −",             action: #selector(menuPanscanOut),  key: "w", mods: []))
        videoMenu.addItem(.separator())
        videoMenu.addItem(item("rotate clockwise",      action: #selector(menuRotateCW),    key: ""))
        videoMenu.addItem(item("rotate counter-clockwise", action: #selector(menuRotateCCW), key: ""))
        videoMenu.addItem(item("reset rotation",        action: #selector(menuRotateReset), key: ""))
        videoMenu.addItem(.separator())
        let aspectItem = NSMenuItem(); aspectItem.title = "aspect ratio"
        let aspectMenu = NSMenu(title: "aspect ratio"); aspectItem.submenu = aspectMenu
        aspectMenu.addItem(item("1.33:1  4:3 Academy",            action: #selector(menuAspect133), key: ""))
        aspectMenu.addItem(item("1.37:1  Academy Sound",          action: #selector(menuAspect137), key: ""))
        aspectMenu.addItem(item("1.43:1  IMAX",                   action: #selector(menuAspect143), key: ""))
        aspectMenu.addItem(item("1.66:1  European Widescreen",    action: #selector(menuAspect166), key: ""))
        aspectMenu.addItem(item("1.78:1  16:9 HDTV",              action: #selector(menuAspect178), key: ""))
        aspectMenu.addItem(item("1.85:1  American Widescreen",    action: #selector(menuAspect185), key: ""))
        aspectMenu.addItem(item("2.00:1  Univisium",              action: #selector(menuAspect200), key: ""))
        aspectMenu.addItem(item("2.20:1  70mm",                   action: #selector(menuAspect220), key: ""))
        aspectMenu.addItem(item("2.35:1  CinemaScope",            action: #selector(menuAspect235), key: ""))
        aspectMenu.addItem(item("2.39:1  Anamorphic Widescreen",  action: #selector(menuAspect239), key: ""))
        aspectMenu.addItem(item("2.55:1  CinemaScope 55",         action: #selector(menuAspect255), key: ""))
        aspectMenu.addItem(item("2.59:1  Cinerama",               action: #selector(menuAspect259), key: ""))
        aspectMenu.addItem(item("2.76:1  Ultra Panavision 70",    action: #selector(menuAspect276), key: ""))
        aspectMenu.addItem(item("3.00:1  Polyvision",             action: #selector(menuAspect300), key: ""))
        aspectMenu.addItem(item("4.00:1  Napoléon Triptych",      action: #selector(menuAspect400), key: ""))
        aspectMenu.addItem(item("5.00:1  Apoléon Riptych",        action: #selector(menuAspect500), key: ""))
        aspectMenu.addItem(item("6.00:1  Poléon Iptych",          action: #selector(menuAspect600), key: ""))
        aspectMenu.addItem(item("7.00:1  Oléon Ptych",            action: #selector(menuAspect700), key: ""))
        aspectMenu.addItem(.separator())
        aspectMenu.addItem(item("16:9    Widescreen",             action: #selector(menuAspect178),  key: ""))
        aspectMenu.addItem(item("16:10",                          action: #selector(menuAspect1610), key: ""))
        aspectMenu.addItem(item("4:3     Standard",               action: #selector(menuAspect133),  key: ""))
        aspectMenu.addItem(item("3:2",                            action: #selector(menuAspect32),   key: ""))
        aspectMenu.addItem(item("1:1     Square",                 action: #selector(menuAspect11),   key: ""))
        aspectMenu.addItem(item("5:4",                            action: #selector(menuAspect54),   key: ""))
        aspectMenu.addItem(.separator())
        aspectMenu.addItem(item("9:16    Vertical",               action: #selector(menuAspect916),  key: ""))
        aspectMenu.addItem(item("3:4     Portrait",               action: #selector(menuAspect34),   key: ""))
        aspectMenu.addItem(.separator())
        aspectMenu.addItem(item("default (no override)",          action: #selector(menuAspectDefault), key: ""))
        aspectMenu.addItem(.separator())
        aspectMenu.addItem(item("expand horizontal  (+0.1)",      action: #selector(menuAspectExpandH), key: ""))
        aspectMenu.addItem(item("shrink horizontal  (−0.1)",      action: #selector(menuAspectShrinkH), key: ""))
        aspectMenu.addItem(item("expand vertical  (+0.1)",        action: #selector(menuAspectExpandV), key: ""))
        aspectMenu.addItem(item("shrink vertical  (−0.1)",        action: #selector(menuAspectShrinkV), key: ""))
        videoMenu.addItem(aspectItem)
        videoMenu.addItem(.separator())
        videoMenu.addItem(item("reset crop",            action: #selector(menuCropReset),    key: ""))
        let redetectCropItem = item("re-detect crop",   action: #selector(menuCropDetect),   key: "")
        videoMenu.addItem(redetectCropItem)
        cropDetectMenuItem = redetectCropItem

        let cropItem = NSMenuItem(); cropItem.title = "crop"
        let cropMenu = NSMenu(title: "crop"); cropItem.submenu = cropMenu
        cropMenu.addItem(item("reset",                action: #selector(menuCropNone),  key: ""))
        cropMenu.addItem(.separator())
        cropMenu.addItem(item("2.39:1  CinemaScope",  action: #selector(menuCrop239),   key: ""))
        cropMenu.addItem(item("2.35:1  CinemaScope",  action: #selector(menuCrop235),   key: ""))
        cropMenu.addItem(item("2.20:1  70mm",         action: #selector(menuCrop220),   key: ""))
        cropMenu.addItem(item("2.00:1  Univisium",    action: #selector(menuCrop200),   key: ""))
        cropMenu.addItem(item("1.85:1  Flat",         action: #selector(menuCrop185),   key: ""))
        cropMenu.addItem(item("1.66:1",               action: #selector(menuCrop166),   key: ""))
        cropMenu.addItem(item("1.43:1  IMAX",         action: #selector(menuCrop143),   key: ""))
        cropMenu.addItem(item("1.37:1  Academy Sound", action: #selector(menuCrop137),  key: ""))
        cropMenu.addItem(.separator())
        cropMenu.addItem(item("2.55:1  CinemaScope 55",     action: #selector(menuCrop255), key: ""))
        cropMenu.addItem(item("2.59:1  Cinerama",           action: #selector(menuCrop259), key: ""))
        cropMenu.addItem(item("2.76:1  Ultra Panavision 70", action: #selector(menuCrop276), key: ""))
        cropMenu.addItem(item("3.00:1  Polyvision",         action: #selector(menuCrop300), key: ""))
        cropMenu.addItem(item("4.00:1  Napoléon Triptych",  action: #selector(menuCrop400), key: ""))
        cropMenu.addItem(item("5.00:1  Apoléon Riptych",    action: #selector(menuCrop500), key: ""))
        cropMenu.addItem(item("6.00:1  Poléon Iptych",      action: #selector(menuCrop600), key: ""))
        cropMenu.addItem(item("7.00:1  Oléon Ptych",        action: #selector(menuCrop700), key: ""))
        cropMenu.addItem(.separator())
        cropMenu.addItem(item("16:9   Widescreen",    action: #selector(menuCrop169),   key: ""))
        cropMenu.addItem(item("16:10",                action: #selector(menuCrop1610),  key: ""))
        cropMenu.addItem(item("4:3    Standard",      action: #selector(menuCrop43),    key: ""))
        cropMenu.addItem(item("3:2",                  action: #selector(menuCrop32),    key: ""))
        cropMenu.addItem(item("1:1    Square",        action: #selector(menuCrop11),    key: ""))
        cropMenu.addItem(item("5:4",                  action: #selector(menuCrop54),    key: ""))
        cropMenu.addItem(.separator())
        cropMenu.addItem(item("9:16   Vertical",      action: #selector(menuCrop916),   key: ""))
        cropMenu.addItem(item("4:5    Instagram",     action: #selector(menuCrop45),    key: ""))
        cropMenu.addItem(item("3:4    Portrait",      action: #selector(menuCrop34),    key: ""))
        videoMenu.addItem(cropItem)
        videoMenu.addItem(.separator())

        videoMenu.addItem(item("screenshot (with subs)", action: #selector(menuScreenshot),       key: "s", mods: []))
        videoMenu.addItem(item("screenshot (video only)", action: #selector(menuScreenshotClean), key: "s", mods: .shift))
        videoMenu.addItem(item("screenshot (window)",    action: #selector(menuScreenshotWin),   key: "s", mods: .command))
        videoMenu.addItem(.separator())
        videoMenu.addItem(item("deband",                action: #selector(menuDeband),      key: ""))
        videoMenu.addItem(item("deinterlace",           action: #selector(menuDeinterlace), key: ""))
        videoMenu.addItem(item("hardware decoding",     action: #selector(menuHwdec),       key: ""))
        videoMenu.addItem(.separator())
        videoMenu.addItem(item("adjust contrast +",     action: #selector(menuContrastUp),   key: ""))
        videoMenu.addItem(item("adjust contrast −",     action: #selector(menuContrastDown), key: ""))
        videoMenu.addItem(item("adjust brightness +",   action: #selector(menuBrightUp),     key: ""))
        videoMenu.addItem(item("adjust brightness −",   action: #selector(menuBrightDown),   key: ""))
        videoMenu.addItem(item("adjust gamma +",        action: #selector(menuGammaUp),      key: ""))
        videoMenu.addItem(item("adjust gamma −",        action: #selector(menuGammaDown),    key: ""))
        videoMenu.addItem(item("adjust saturation +",   action: #selector(menuSatUp),        key: ""))
        videoMenu.addItem(item("adjust saturation −",   action: #selector(menuSatDown),      key: ""))
        videoMenu.addItem(item("reset color adjustments", action: #selector(menuColorReset), key: ""))
        videoMenu.addItem(.separator())
        let vrItem = NSMenuItem(); vrItem.title = "vr"
        let vrMenu = NSMenu(title: "vr"); vrItem.submenu = vrMenu
        vrMenu.addItem(item("mono (no VR)",           action: #selector(menuVRMono),       key: ""))
        vrMenu.addItem(item("side-by-side",           action: #selector(menuVRSideBySide), key: ""))
        vrMenu.addItem(item("VR180",                  action: #selector(menuVRMode180),    key: ""))
        vrMenu.addItem(.separator())
        vrMenu.addItem(item("toggle VR180",           action: #selector(menuVRToggle),     key: "v", mods: [.shift]))
        vrMenu.addItem(item("head tracking",          action: #selector(menuHeadTracking), key: "h", mods: [.shift]))
        vrMenu.addItem(item("recenter head tracking", action: #selector(menuHeadRecenter), key: "r", mods: [.shift]))
        vrMenu.addItem(item("ipd +",                  action: #selector(menuIPDPlus),      key: "]", mods: [.shift]))
        vrMenu.addItem(item("ipd −",                  action: #selector(menuIPDMinus),     key: "[", mods: [.shift]))
        videoMenu.addItem(vrItem)
        videoMenu.addItem(.separator())

        let clipItem = NSMenuItem(); clipItem.title = "clip"
        let clipMenu = NSMenu(title: "clip"); clipItem.submenu = clipMenu
        clipMenu.addItem(item("clip video",   action: #selector(menuClipVideo), key: "c", mods: [.command, .option]))
        clipMenu.addItem(item("clip gif",     action: #selector(menuClipGif),   key: "g", mods: [.command, .option]))
        clipMenu.addItem(item("clip undo",    action: #selector(menuClipUndo),  key: "z", mods: [.command, .option]))
        clipMenu.addItem(item("clip abort",   action: #selector(menuClipAbort), key: "x", mods: [.command, .option]))
        clipMenu.addItem(.separator())
        clipMenu.addItem(item("clip open",    action: #selector(menuClipOpen),  key: "o", mods: [.command, .option]))
        clipMenu.addItem(item("toggle fade",  action: #selector(menuClipFade),  key: "f", mods: [.command, .option]))
        videoMenu.addItem(clipItem)

        // ── photon ─────────────────────────────────────────────────────────────
        // Plain-letter keys are swallowed by InputController and fired from
        // input.conf - the labels document those bindings, actions match them.
        let photonItem = NSMenuItem(); photonItem.title = "photon"; main.addItem(photonItem)
        let photonMenu = NSMenu(title: "photon"); photonItem.submenu = photonMenu
        photonMenu.addItem(item("photon",         action: #selector(menuPhotonToggle),  key: "\u{F70C}", mods: []))
        photonMenu.addItem(item("hud",            action: #selector(menuPhotonHUD),     key: "\u{F70B}", mods: []))
        photonMenu.addItem(.separator())
        photonMenu.addItem(item("bright",         action: #selector(menuPhotonBright),  key: "b", mods: []))
        photonMenu.addItem(item("sharp",          action: #selector(menuPhotonSharp),   key: "x", mods: []))
        photonMenu.addItem(item("grain",          action: #selector(menuPhotonGrain),   key: "g", mods: []))
        photonMenu.addItem(item("chrome",         action: #selector(menuPhotonChrome),  key: "c", mods: []))
        photonMenu.addItem(item("chrome filter",  action: #selector(menuPhotonChromeFilter), key: "c", mods: [.shift]))
        photonMenu.addItem(item("negativ",        action: #selector(menuPhotonNegativ), key: "n", mods: []))
        photonMenu.addItem(.separator())
        photonMenu.addItem(item("stats",          action: #selector(menuStatsToggle),   key: "i", mods: []))

        // ── audio ───────────────────────────────────────────────────────────────
        let audioItem = NSMenuItem(); audioItem.title = "audio"; main.addItem(audioItem)
        let audioMenu = NSMenu(title: "audio"); audioItem.submenu = audioMenu
        audioMenu.addItem(item("volume up",             action: #selector(menuVolUp),       key: "0", mods: []))
        audioMenu.addItem(item("volume down",           action: #selector(menuVolDown),     key: "9", mods: []))
        audioMenu.addItem(item("mute / unmute",         action: #selector(menuMute),        key: "m", mods: []))
        audioMenu.addItem(.separator())
        audioMenu.addItem(item("next audio track",      action: #selector(menuAudioNext),   key: ""))
        audioMenu.addItem(item("previous audio track",  action: #selector(menuAudioPrev),   key: ""))
        audioMenu.addItem(.separator())
        audioMenu.addItem(item("audio delay +0.1s",     action: #selector(menuAudioDelayP), key: ""))
        audioMenu.addItem(item("audio delay −0.1s",     action: #selector(menuAudioDelayM), key: ""))
        audioMenu.addItem(item("reset audio delay",     action: #selector(menuAudioDelayReset), key: ""))

        // ── subtitles ───────────────────────────────────────────────────────────
        let subItem = NSMenuItem(); subItem.title = "subtitles"; main.addItem(subItem)
        let subMenu = NSMenu(title: "subtitles"); subItem.submenu = subMenu
        subMenu.addItem(item("toggle subtitles",        action: #selector(menuSubToggle),   key: "v", mods: []))
        subMenu.addItem(.separator())
        subMenu.addItem(item("next subtitle track",     action: #selector(menuSubNext),     key: "j", mods: []))
        subMenu.addItem(item("previous subtitle track", action: #selector(menuSubPrev),     key: "j", mods: .shift))
        subMenu.addItem(item("load subtitle file…",     action: #selector(menuSubLoad),     key: ""))
        subMenu.addItem(item("save src subtitle",       action: #selector(menuSaveSrcSubtitle), key: ""))
        subMenu.addItem(.separator())
        // Cmd+Shift+Arrows = subtitle delay. Sub-seek removed as unnecessary;
        // plain x/z stay with photon_sharp via input.conf.
        subMenu.addItem(item("subtitle delay +0.1s",    action: #selector(menuSubDelayP),   key: "→", mods: [.command, .shift]))
        subMenu.addItem(item("subtitle delay −0.1s",    action: #selector(menuSubDelayM),   key: "←", mods: [.command, .shift]))
        subMenu.addItem(item("reset subtitle delay",  action: #selector(menuSubDelayReset),  key: ""))
        // "," and "ü" are the real sub-scale keys from input.conf.
        subMenu.addItem(item("subtitle font size +",    action: #selector(menuSubSizeUp),   key: ",", mods: []))
        subMenu.addItem(item("subtitle font size −",    action: #selector(menuSubSizeDown), key: "ü", mods: []))
        subMenu.addItem(.separator())
        subMenu.addItem(item("move subtitles up",       action: #selector(menuSubUp),       key: "r", mods: []))
        subMenu.addItem(item("move subtitles down",     action: #selector(menuSubDown),     key: "t", mods: []))
        subMenu.addItem(item("random subtitle position", action: #selector(menuSubRandomPos), key: "0", mods: [.shift]))
        subMenu.addItem(.separator())
        subMenu.addItem(item("live captions",           action: #selector(menuLiveCaption), key: ""))
        let capModelItem = NSMenuItem(); capModelItem.title = "live caption model"
        let capModelMenu = NSMenu(title: "live caption model"); capModelItem.submenu = capModelMenu
        for model in ["auto", "tiny", "base", "small", "medium", "large", "large-v2", "large-v3", "large-v3-turbo"] {
            let mi = item(model, action: #selector(menuCaptionModel(_:)), key: "")
            mi.representedObject = model
            capModelMenu.addItem(mi)
        }
        subMenu.addItem(capModelItem)

        NSApp.mainMenu = main
    }

    // Observation only. Append-only local file; failures never alter quit decisions.
    private func quitDebug(_ phase: String) {
        let fm = FileManager.default
        let directory = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/gor", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("quit-debug.log").path
        let fd = Darwin.open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        let line = "ts=\(Date().timeIntervalSince1970) pid=\(ProcessInfo.processInfo.processIdentifier) uptime=\(ProcessInfo.processInfo.systemUptime) main=\(Thread.isMainThread) \(phase)\n"
        let data = Data(line.utf8)
        _ = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
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
    static let quitTokenURL = FileManager.default.homeDirectoryForCurrentUser
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
        let children = [mpvProcess, controller?.musicController?.process,
                        torrentProcess, megaRelayProcess].compactMap { $0 }
        state.updateRestart(pendingRestart)
        let restartBundlePath = Bundle.main.bundlePath
        quitWatchdogQueue.asyncAfter(deadline: .now() + 6.0) { [self] in
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
            for process in children where claimedPhase != 3 && process.isRunning {
                let pid = process.processIdentifier
                if pid > 0 {
                    let result = kill(pid, SIGKILL)
                    let error = errno
                    killResults.append("pid=\(pid):kill=\(result):errno=\(error)")
                }
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
            // Kill/restart decisions are already made. This is an attempted
            // write through an arm-time FD, not a durable or nonblocking receipt.
            let exitCode = claimedPhase == 3 ? 71 : 70
            let reason = claimedPhase == 3 ? "post-cleanup-hang" : "cleanup-incomplete"
            let forcedLine = Data("gor quit watchdog epoch=\(epoch) phase=\(claimedPhase) reason=\(reason) exit=\(exitCode) kills=\(killResults.joined(separator: ",")) diagnostic_attempt_only\n".utf8)
            // No filesystem work occurs at arm time. Lazy diagnostics happen
            // after child-kill/restart decisions, and remain best effort.
            let forcedLogPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/gor/quit-debug.log").path
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
        if let pid = mpvProcess?.processIdentifier, pid > 0 {
            isQuittingDeliberately = true
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }

        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        quitDebug("cleanup before torrent stop")
        stopTorrent()
        quitDebug("cleanup before mega stop")
        stopMegaRelay()
        try? FileManager.default.removeItem(atPath: "/tmp/webtorrent_stream")
        try? FileManager.default.removeItem(atPath: ipcPath)
        
        quitDebug("cleanup before crop cancel")
        controller?.cancelCropDetection()
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        quitDebug("cleanup before orphan sweep")
        killOrphanedMPVProcesses()
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        cleanup.arguments = ["-f", "WorkflowServiceRunner"]
        try? cleanup.run()
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        let killChrome = Process()
        killChrome.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killChrome.arguments = ["-9", "chrome-headless-shell"]
        try? killChrome.run()
        
        // Same no-shell glob bug as the startup sweep - enumerate /tmp.
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        if let tmpItems = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") {
            for item in tmpItems where item.hasPrefix("gor-chrome-")
                || item.hasPrefix("hidden_mpv_") || item.hasPrefix("crop_frame_") {
                try? FileManager.default.removeItem(atPath: "/tmp/\(item)")
            }
        }
        
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }


        quitDebug("cleanup complete restart=\(pendingRestart)")
        guard quitWatchdogState.cleanupAllowed(epoch: quitRequestEpoch) else { return }
        if pendingRestart, quitWatchdogState.claimRestart() {
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
            quitDebug("relaunch skipped: pendingRestart=false")
        }
        if quitWatchdogState.finish(epoch: quitRequestEpoch) {
            quitDebug("WillTerminate return: normal cleanup finished")
        } else {
            quitDebug("WillTerminate loser returns; watchdog alone owns exit")
        }
    }

    // MARK: - Orphaned hidden-mpv sweep

    func killOrphanedMPVProcesses() {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-f", "mpv/bin/mpv"]
        let out = Pipe(); pgrep.standardOutput = out
        try? pgrep.run(); pgrep.waitUntilExit()

        let pids = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .split(separator: "\n").compactMap { pid_t($0) } ?? []

        for pid in pids {
            if pid == mpvProcess?.processIdentifier { continue }

            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-o", "ppid=", "-p", "\(pid)"]
            let psOut = Pipe(); ps.standardOutput = psOut
            try? ps.run(); ps.waitUntilExit()

            guard let ppidStr = String(data: psOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let ppid = pid_t(ppidStr) else { continue }

            if ppid == 1 || kill(ppid, 0) != 0 {
                kill(pid, SIGKILL)
            }
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

    func findMPV() -> String {
        Bundle.main.resourcePath! + "/vendor/mpv/bin/mpv"
    }
    
    func setEventTapEnabled(_ enabled: Bool) {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
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
    // New media telemetry only. Test build true; release must set false.
    // Node: --gor-diag=true|false. mpv: --script-opts-add=gor-diag=true|false.
    static let mediaTelemetryEnabled = true

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
        let fd = Darwin.open("/tmp/gor_diag.log", O_WRONLY | O_APPEND | O_CREAT, mode_t(0o600))
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var status = stat()
        guard fstat(fd, &status) == 0, status.st_size >= 0,
              UInt64(status.st_size) + UInt64(data.count) <= 20 * 1048576 else { return }
        let written = data.withUnsafeBytes { buffer -> Int in
            var result: Int
            repeat { result = Darwin.write(fd, buffer.baseAddress, buffer.count) }
                while result < 0 && errno == EINTR
            return result
        }
        if written != data.count { NSLog("[GOR] media append failed or short; remainder dropped") }
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
