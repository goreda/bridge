# W-gdb-199f-1nstinct-29 - Torrent stdout CRLF framing
state: OPEN / unclaimed

CLASSIFICATION: Only StdoutLineBuffer is extracted verbatim from TorrentManager.swift and compiled with its test in one Swift file to preserve private access. No process/network stub and no process launch acceptance.
lab: 1nstinct

StdoutLineBuffer.lines must remove the terminal CR immediately before LF while preserving partial UTF8 bytes and internal text. Preserve LF input and existing invalid-UTF8 behavior. Different source and process from the previous MEGA framing packet.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-1nstinct-29",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorSources/TorrentManager.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "StdoutLineBuffer.lines must remove the terminal CR immediately before LF while preserving partial UTF8 bytes and internal text. Preserve LF input and existing invalid-UTF8 behavior. Different source and process from the previous MEGA framing packet.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Only StdoutLineBuffer is extracted verbatim from TorrentManager.swift and compiled with its test in one Swift file to preserve private access. No process/network stub and no process launch acceptance.",
    "callee": "archive/gor/Sources/gor/GorSources/TorrentManager.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-29.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199f-1nstinct-29",
    "paths": [
      "archive/gor/Sources/gor/GorSources/TorrentManager.swift",
      "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-29.py",
      "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-29.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-29.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorSources/TorrentManager.swift",
        "block": "source1",
        "sha256": "6ad6bbef5d9ec07ba989f2adb8eae7bc3774fd431bdeecfa8e4d3e8516f43e2b",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-29.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "archive/gor/Tests/Architecture/199f/W-gdb-199f-1nstinct-29.json",
        "block": "fixtures2",
        "sha256": "ce9ff3a6cb91c4924bd9013420c4f0c5f6cea14d6a961b7272c936a154265482"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "60d861a505e3a20ba2d278365244be01c52d919a4c8f2f6567d488fc6a7cf3f8",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL CRLF clean protocol line",
      "PASS LF unchanged",
      ""
    ]
  },
  "classification": "Only StdoutLineBuffer is extracted verbatim from TorrentManager.swift and compiled with its test in one Swift file to preserve private access. No process/network stub and no process launch acceptance."
}
```

```swift id=source1
// ================================================================
//  TorrentManager.swift - torrent streaming bridge
//  Owns: webtorrent process, stdout protocol, stream setup
//  Contract: Buffer stdout until newline before decoding UTF-8
// ================================================================

import AppKit
import CryptoKit
import Foundation

// ================================================================
//  StdoutLineBuffer - UTF-8 pipe framing
// ================================================================
// A pipe read returns at most ~64 KB, so one long line (FILES: for a big
// torrent) arrives in pieces; splitting each read on its own cut the JSON
// mid-string. Bytes are held until a newline, which also keeps a multi-byte
// character that straddles two reads intact. A class, not a captured var:
// the readabilityHandler closure may be @Sendable and cannot mutate a var.
private final class StdoutLineBuffer {
    private var data = Data()
    
    func lines(appending chunk: Data) -> [String] {
        data.append(chunk)
        guard chunk.contains(0x0A) else { return [] }
        var out: [String] = []
        while let nl = data.firstIndex(of: 0x0A) {
            if let s = String(data: data[data.startIndex..<nl], encoding: .utf8) {
                out.append(s)
            }
            data.removeSubrange(data.startIndex...nl)
        }
        return out
    }
}

// ================================================================
//  AppDelegate - application lifecycle
// ================================================================
/// Keeps the last few KB of wt_server stderr so a crash can be explained in the log.
/// The pipe's readabilityHandler is the only reader. It calls markEOF() when the pipe closes.
/// Redacted before printing: URLs, magnet links, long tokens and home paths are replaced.
final class WtStderrTail {
    private let lock = NSLock()
    private var buffer = Data()
    private var truncated = false
    private var eof = false
    private let eofSignal = DispatchSemaphore(value: 0)
    private let maxBytes = 8192
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        if buffer.count > maxBytes { buffer = buffer.suffix(maxBytes); truncated = true }
    }
    func markEOF() {
        lock.lock(); let first = !eof; eof = true; lock.unlock()
        if first { eofSignal.signal() }
    }
    /// Waits at most `timeout` seconds for the reader to see EOF. Never reads the pipe.
    @discardableResult
    func waitForEOF(timeout: TimeInterval) -> Bool {
        eofSignal.wait(timeout: .now() + timeout) == .success
    }
    func redactedLastLines(_ maxLines: Int = 20) -> String {
        lock.lock(); var data = buffer; let cut = truncated; lock.unlock()
        // After truncation the first line is partial (a URL prefix may be gone): drop it before redacting.
        if cut {
            if let nl = data.firstIndex(of: 0x0A) { data = data.suffix(from: data.index(after: nl)) }
            else { data = Data() }  // no line break in the kept bytes: the whole thing is a partial line, drop it
        }
        var text = String(decoding: data, as: UTF8.self)
        let rules: [(String, String)] = [
            (#"magnet:\S+"#, "<magnet>"),
            (#"https?://\S+"#, "<url>"),
            (#"/Users/[^/\s]+"#, "/Users/~"),
            (#"[A-Za-z0-9_\-]{32,}"#, "<tok>")
        ]
        for (pattern, repl) in rules {
            text = text.replacingOccurrences(of: pattern, with: repl, options: .regularExpression)
        }
        let lines = text.split(whereSeparator: \.isNewline).suffix(maxLines)
        return lines.map { String($0.prefix(480)) }.joined(separator: " | ")
    }
}

extension AppDelegate {
    // MARK: - Properties
    
    
    // PARAMS/METADATA lines are written on the pipe-handler queue and read
    // on main - a lock owns the handshake.
    private static let paramsLock = NSLock()
    private static var _pendingDemuxerMaxBytes: Int = 500_000_000
    private static var _pendingCacheSecs: Int = 30
    private static var _isHDRTorrent: Bool = false

    static var pendingDemuxerMaxBytes: Int {
        get { paramsLock.lock(); defer { paramsLock.unlock() }; return _pendingDemuxerMaxBytes }
        set { paramsLock.lock(); _pendingDemuxerMaxBytes = newValue; paramsLock.unlock() }
    }
    static var pendingCacheSecs: Int {
        get { paramsLock.lock(); defer { paramsLock.unlock() }; return _pendingCacheSecs }
        set { paramsLock.lock(); _pendingCacheSecs = newValue; paramsLock.unlock() }
    }
    static var isHDRTorrent: Bool {
        get { paramsLock.lock(); defer { paramsLock.unlock() }; return _isHDRTorrent }
        set { paramsLock.lock(); _isHDRTorrent = newValue; paramsLock.unlock() }
    }
    
    // MARK: - Stream
    
    private static let swapQueue = DispatchQueue(label: "gor.torrent.swap", qos: .utility)
    private static var swapGeneration = 0

    private static func torrentDiagnostic(_ stage: String) {
        // Capture-time labels, not a guarantee of concurrent print order.
        let monotonic = ProcessInfo.processInfo.systemUptime
        let wall = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: wall)
        let uptime = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), monotonic)
        print("[torrent-start-diag] ts=\(timestamp) uptime_s=\(uptime) \(stage)")
    }

    func streamTorrent(_ magnetOrURL: String) {
        controller?.beginMediaTransition()
        Self.swapGeneration += 1
        let generation = Self.swapGeneration
        let old = torrentProcess
        Self.torrentDiagnostic("ENTRY generation=\(generation) old_present=\(old != nil)")
        Self.swapQueue.async { [weak self] in
            let diagnosticOldThreadName = Thread.current.name
            Thread.current.name = "torrent.swap"
            defer { Thread.current.name = diagnosticOldThreadName }
            Self.torrentDiagnostic("SWAP_QUEUE_ENTER generation=\(generation)")
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killTask.arguments = ["-f", "wt_server.mjs"]
            Self.torrentDiagnostic("PKILL_RUN_BEFORE generation=\(generation)")
            do { try killTask.run(); Self.torrentDiagnostic("PKILL_RUN_OK generation=\(generation)") }
            catch { let e = error as NSError; Self.torrentDiagnostic("PKILL_RUN_ERROR generation=\(generation) code=\(e.code)") }
            if killTask.isRunning {
                Self.torrentDiagnostic("PKILL_WAIT_BEFORE generation=\(generation)")
                killTask.waitUntilExit()
                Self.torrentDiagnostic("PKILL_WAIT_AFTER generation=\(generation)")
            }
            if let old, old.isRunning {
                Self.torrentDiagnostic("OLD_TERMINATE_WAIT_BEFORE generation=\(generation)")
                old.terminate(); old.waitUntilExit()
                Self.torrentDiagnostic("OLD_TERMINATE_WAIT_AFTER generation=\(generation)")
            }
            Self.torrentDiagnostic("REAP_BEFORE generation=\(generation)")
            Self.reapWtServerZombies()
            Self.torrentDiagnostic("REAP_AFTER generation=\(generation)")
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async {
                Self.torrentDiagnostic("MAIN_CALLBACK generation=\(generation) current=\(Self.swapGeneration) self_present=\(self != nil)")
                guard let self, generation == Self.swapGeneration else {
                    Self.torrentDiagnostic("MAIN_CALLBACK_DROP generation=\(generation)"); return
                }
                if let old = self.torrentProcess { QuitChildKiller.shared.unregisterIfStopped(old) }
                self.torrentProcess = nil
                self.torrentStdinPipe = nil
                Self.torrentDiagnostic("START_AFTER_SWAP_CALL generation=\(generation)")
                self.startTorrentAfterSwap(magnetOrURL)
                Self.torrentDiagnostic("START_AFTER_SWAP_RETURN generation=\(generation)")
            }
        }
    }

    /// pkill only *sends* SIGTERM — handle-less zombies (orphaned by a crashed
    /// gor) still hold 2222/51413/6771 for up to their 5s shutdown watchdog while
    /// the new process probes them. Wait until pgrep finds none, SIGKILL after 6s.
    private static func reapWtServerZombies(timeout: TimeInterval = 6.0) {
        func survivors() -> Int {
            let p = Process()
            let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            p.arguments = ["-f", "wt_server.mjs"]
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            Self.torrentDiagnostic("REAP_PGREP_RUN_BEFORE")
            guard (try? p.run()) != nil else { Self.torrentDiagnostic("REAP_PGREP_RUN_ERROR"); return 0 }
            Self.torrentDiagnostic("REAP_PGREP_READ_BEFORE")
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            Self.torrentDiagnostic("REAP_PGREP_READ_AFTER")
            p.waitUntilExit()
            Self.torrentDiagnostic("REAP_PGREP_WAIT_AFTER")
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .count
        }
        let deadline = Date().addingTimeInterval(timeout)
        while survivors() > 0, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard survivors() > 0 else { return }
        let hard = Process()
        hard.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        hard.arguments = ["-9", "-f", "wt_server.mjs"]
        Self.torrentDiagnostic("REAP_HARD_RUN_BEFORE")
        try? hard.run()
        Self.torrentDiagnostic("REAP_HARD_RUN_AFTER")
        if hard.isRunning {
            Self.torrentDiagnostic("REAP_HARD_WAIT_BEFORE")
            hard.waitUntilExit()
            Self.torrentDiagnostic("REAP_HARD_WAIT_AFTER")
        }
        let hardDeadline = Date().addingTimeInterval(2)
        while survivors() > 0, Date() < hardDeadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func startTorrentAfterSwap(_ magnetOrURL: String) {
        Self.torrentDiagnostic("BACKEND_ENTRY")
        // Node, the script and its relative dependencies share the vendor
        // root, resolved via GORResources; the dev override below still wins
        // when its content validation passes.
        let resources = GORResources.vendor()
        let node = resources?.appendingPathComponent("node/node").path
        let candidate = AppDelegate.devVendorRoot()
        let devVendor = candidate.flatMap { vendor -> URL? in
            let script = vendor.appendingPathComponent("wt_server/wt_server.mjs").path
            let dependency = vendor.appendingPathComponent("webtorrent-cli/node_modules/webtorrent/index.js").path
            return FileManager.default.isReadableFile(atPath: script)
                && FileManager.default.isReadableFile(atPath: dependency) ? vendor : nil
        }
        let script = devVendor?
            .appendingPathComponent("wt_server/wt_server.mjs").path
            ?? resources?.appendingPathComponent("wt_server/wt_server.mjs").path
        let dependency = devVendor?
            .appendingPathComponent("webtorrent-cli/node_modules/webtorrent/index.js").path
            ?? resources?.appendingPathComponent("webtorrent-cli/node_modules/webtorrent/index.js").path
        Self.torrentDiagnostic("BACKEND_CHECK node_executable=\(node.map { FileManager.default.isExecutableFile(atPath: $0) } ?? false) script_exists=\(script.map { FileManager.default.fileExists(atPath: $0) } ?? false) dependency_exists=\(dependency.map { FileManager.default.fileExists(atPath: $0) } ?? false) dev_vendor=\(devVendor != nil)")
        if let node, let script, let dependency,
           FileManager.default.isExecutableFile(atPath: node),
           FileManager.default.fileExists(atPath: script),
           FileManager.default.fileExists(atPath: dependency) {
            // WT install-gap diagnostic (owner 2026-11-15): name the exact file
            // the process will run, so a post-update pre-fix server is traceable
            // to the resolved path instead of inferred from missing STATS fields.
            if let scriptData = try? Data(contentsOf: URL(fileURLWithPath: script)) {
                let scriptSHA = SHA256.hash(data: scriptData).map { String(format: "%02x", $0) }.joined()
                Self.torrentDiagnostic("BACKEND_ACCEPT script=\(script) sha256=\(scriptSHA) dev_vendor=\(devVendor != nil)")
            } else {
                Self.torrentDiagnostic("BACKEND_ACCEPT script=\(script) sha256=unreadable dev_vendor=\(devVendor != nil)")
            }
            streamWithWebTorrent(source: magnetOrURL)
        } else {
            Self.torrentDiagnostic("BACKEND_REJECT")
            showTorrentOverlay(status: "torrent backend missing (Node, wt_server or WebTorrent)")
        }
    }

    private func streamWithWebTorrent(source: String) {
        Self.torrentDiagnostic("WEBTORRENT_ENTRY_STOP_BEFORE")
        stopTorrent()
        Self.torrentDiagnostic("STOP_RETURN")
        lastMagnetURL = source
        try? FileManager.default.removeItem(atPath: "/tmp/gor_watch_later")
        try? FileManager.default.createDirectory(atPath: "/tmp/gor_watch_later", withIntermediateDirectories: true)
        Self.torrentDiagnostic("CONNECTING_OVERLAY_BEFORE controller_present=\(controller != nil)")
        showTorrentOverlay(status: "connecting to peers...")
        Self.torrentDiagnostic("CONNECTING_OVERLAY_AFTER")
        
        let candidate = AppDelegate.devVendorRoot()
        let devVendor = candidate.flatMap { vendor -> URL? in
            let script = vendor.appendingPathComponent("wt_server/wt_server.mjs").path
            let dependency = vendor.appendingPathComponent("webtorrent-cli/node_modules/webtorrent/index.js").path
            return FileManager.default.isReadableFile(atPath: script)
                && FileManager.default.isReadableFile(atPath: dependency) ? vendor : nil
        }
        let scriptPath = devVendor?
            .appendingPathComponent("wt_server/wt_server.mjs").path
            ?? GORResources.vendor()?.appendingPathComponent("wt_server/wt_server.mjs").path
        guard let scriptPath, FileManager.default.fileExists(atPath: scriptPath) else {
            Self.torrentDiagnostic("SCRIPT_MISSING")
            showTorrentOverlay(status: "wt_server.mjs not found")
            return
        }
        
        // Homebrew fallback preserved with EXACT old semantics: a vendored
        // node wins whenever it EXISTS (the exec/exists guard below errors
        // exactly as before); only its ABSENCE falls back to Homebrew.
        let vendoredNode = GORResources.vendor()?.appendingPathComponent("node/node").path
        let nodePath = vendoredNode.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            ?? "/opt/homebrew/bin/node"
        guard FileManager.default.isExecutableFile(atPath: nodePath) else {
            Self.torrentDiagnostic("NODE_NOT_EXECUTABLE")
            showTorrentOverlay(status: "node not found")
            return
        }
        
        var nodeSource = source
        if source.lowercased().hasPrefix("file://") {
            if let u = URL(string: source), u.isFileURL {
                nodeSource = u.path
            } else {
                nodeSource = String(source.dropFirst("file://".count))
            }
        }
        
        let p = Process()
        p.executableURL = URL(fileURLWithPath: nodePath)
        p.arguments = ["--expose-gc", "--max-old-space-size=512", scriptPath, "2222", nodeSource, "--gor-diag=\(Diag.mediaTelemetryEnabled ? "true" : "false")"]
        p.environment = [
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "NODE_PATH": (devVendor?.path ?? GORResources.vendorRootPath())
                + "/webtorrent-cli/node_modules",
        ]
        
        if !StagedRunPaths.active {p.environment?.removeValue(forKey:"GOR_LOG_SESSION_DIR")}

        // Test-only pump receipts: allow one explicit opt-in, never inherit the full environment.
        if ProcessInfo.processInfo.environment["GOR_WT_PUMP_RECEIPTS"] == "1" {
            p.environment?["GOR_WT_PUMP_RECEIPTS"] = "1"
        }

        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError  = stderrPipe
        p.standardInput = stdinPipe
        torrentProcess = p
        torrentStdinPipe = stdinPipe
        torrentStdoutPipe = stdoutPipe
        torrentStderrPipe = stderrPipe
        
        let stdoutLines = StdoutLineBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self, weak p] handle in
            let data = handle.availableData
            // EOF: an empty read repeats forever (busy loop) unless the handler is removed.
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            for line in stdoutLines.lines(appending: data) {
                let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if l.hasPrefix("FILES:") {
                    Self.torrentDiagnostic("FILES_RECEIVED")
                    let json = String(l.dropFirst("FILES:".count))
                    DispatchQueue.main.async { [weak self] in
                        Self.torrentDiagnostic("FILES_MAIN_CALLBACK self_present=\(self != nil)")
                        self?.openTorrentBrowserPanel()
                        Self.torrentDiagnostic("FILES_PANEL_PRESENT value=\(self?.torrentBrowserPanel != nil)")
                        self?.torrentBrowserPanel?.showTorrentFiles(json: json) { [weak self] index in
                            guard let pipe = self?.torrentStdinPipe else { return }
                            if let d = "SELECT:\(index)\n".data(using: .utf8) {
                                pipe.fileHandleForWriting.write(d)
                            }
                        }
                    }
                } else if l.hasPrefix("STATS:") {
                    let json = String(l.dropFirst("STATS:".count))
                    DispatchQueue.main.async { [weak self, weak p] in
                        // Bind queued metrics to their originating process even if an
                        // older server omits the JSON session field. Check on main:
                        // the active process may have changed since the pipe read.
                        guard let self = self, let sourceProcess = p,
                              self.torrentProcess === sourceProcess,
                              let spineUI = self.controller?.spineUI,
                              spineUI.alphaValue > 0 else { return }
                        guard let data = json.data(using: .utf8),
                              let stats = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                        // A dying previous wt_server keeps this pipe handler alive
                        // and can paint zeroed STATS over the new session's HUD.
                        // v20.2 stamps each STATS with its process pid — drop mismatches.
                        if let session = stats["session"] as? Int,
                           session != Int(self.torrentProcess?.processIdentifier ?? -1) { return }
                        let dl = stats["downloadSpeed"] as? Double ?? 0
                        let peers = stats["numPeers"] as? Int ?? 0
                        let dlStr = dl > 1_000_000 ? String(format: "%.1f MB/s", dl / 1_000_000) :
                        dl > 1_000 ? String(format: "%.0f KB/s", dl / 1_000) :
                        "\(Int(dl)) B/s"
                        // The SKIP row is session piece payload, not socket traffic or resident progress.
                        // Missing mixed-version data must never fall back to downloaded.
                        let dlTotalStr: String
                        if let received = stats["receivedPayloadBytes"] as? Double,
                           received.isFinite, received >= 0 {
                            dlTotalStr = received >= 1_000_000_000 ? String(format: "%.1f GB", received / 1_000_000_000) :
                            received >= 1_000_000 ? String(format: "%.0f MB", received / 1_000_000) :
                            received >= 1_000 ? String(format: "%.0f KB", received / 1_000) :
                            String(format: "%.0f B", received)
                        } else {
                            dlTotalStr = "unknown"
                        }
                        let fileLen = stats["fileLength"] as? Double ?? 0
                        let totalStr = fileLen > 1_000_000_000 ? String(format: "%.1f GB", fileLen / 1_000_000_000) :
                        fileLen > 1_000_000 ? String(format: "%.0f MB", fileLen / 1_000_000) :
                        "\(Int(fileLen)) B"

                        let osdFont = PhotonFont.ns()
                        let spaceW = " ".width(using: osdFont)

                        func splitVal(_ str: String) -> (num: String, unit: String) {
                            let parts = str.components(separatedBy: " ")
                            if parts.count >= 2, Double(parts[0]) != nil {
                                return (parts[0], parts.dropFirst().joined(separator: " "))
                            }
                            return (str, "")
                        }

                        let dlSplit = splitVal(dlStr)
                        let dlTotalSplit = splitVal(dlTotalStr)
                        let totalSplit = splitVal(totalStr)

                        let peersStr = String(peers)

                        let numColW: CGFloat = 60
                        let unitColW: CGFloat = 50

                        func alignRight(_ s: String, width: CGFloat) -> String {
                            let w = s.width(using: osdFont)
                            let pad = Int(ceil((width - w) / spaceW))
                            return String(repeating: " ", count: max(0, pad)) + s
                        }

                        func alignLeft(_ s: String, width: CGFloat) -> String {
                            let w = s.width(using: osdFont)
                            let pad = Int(ceil((width - w) / spaceW))
                            return s + String(repeating: " ", count: max(0, pad))
                        }

                        let msg = """
                        ░  \(alignRight(peersStr, width: numColW))  \(alignLeft("peers", width: unitColW))
                        ↓  \(alignRight(dlSplit.num, width: numColW))  \(alignLeft(dlSplit.unit, width: unitColW))
                        ↴  \(alignRight(dlTotalSplit.num, width: numColW))  \(alignLeft(dlTotalSplit.unit, width: unitColW))
                          \(alignRight(totalSplit.num, width: numColW))  \(alignLeft(totalSplit.unit, width: unitColW))
                        """
                        
                        self.controller?.spineUI.showMPVOSD(msg, animated: false)
                    }
                } else if l.hasPrefix("VERDICT:") {
                    // v21.0: wt_server suspects a corrupt swarm (a piece keeps
                    // failing hash from every peer) — name it on the HUD
                    // instead of letting the stats grid spin silently.
                    let payload = String(l.dropFirst("VERDICT:".count))
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self,
                              let spineUI = self.controller?.spineUI,
                              spineUI.alphaValue > 0 else { return }
                        let piece = payload.components(separatedBy: "piece=").dropFirst().first?
                            .components(separatedBy: .whitespaces).first ?? "?"
                        let fails = payload.components(separatedBy: "fails=").dropFirst().first?
                            .components(separatedBy: .whitespaces).first ?? "?"
                        spineUI.showMPVOSD("piece \(piece) failed hash \(fails)x — swarm looks corrupt, try another release", animated: false)
                    }
                } else if l.hasPrefix("STORE:") {
                    let json = String(l.dropFirst("STORE:".count))
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self,
                              let spineUI = self.controller?.spineUI,
                              let data = json.data(using: .utf8),
                              let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                        spineUI.torrentStalling = store["stalling"] as? Bool ?? false
                        spineUI.torrentStalledPiece = store["stalledPiece"] as? Int
                        spineUI.torrentWindowActive = store["windowActive"] as? Bool ?? false
                    }
                } else if l.hasPrefix("CMD:") {
                    let cmdLine = String(l.dropFirst("CMD:".count))
                    print("[Torrent] CMD received: \(cmdLine)")
                    let parts = cmdLine.components(separatedBy: " ")
                    let cmd = parts.first ?? ""
                    let text = parts.dropFirst().joined(separator: " ")
                    DispatchQueue.main.async { [weak self] in
                        self?.controller?.spineUI.reportTorrentCommandFeedback(forCmd: cmd, text: text)
                    }
                } else if l.hasPrefix("PARAMS:") {
                    let json = String(l.dropFirst("PARAMS:".count))
                    if let data = json.data(using: .utf8),
                       let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let demux = params["demuxerMaxBytes"] as? Int {
                            AppDelegate.pendingDemuxerMaxBytes = demux
                        }
                        if let cache = params["cacheSecs"] as? Int {
                            AppDelegate.pendingCacheSecs = cache
                        }
                    }
                } else if l.hasPrefix("METADATA:") {
                    AppDelegate.isHDRTorrent = l.contains("HDR")
                } else if l.hasPrefix("FILM_ID:") {
                    if let data=String(l.dropFirst("FILM_ID:".count)).data(using:.utf8),let info=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let url=info["url"] as? String,let hash=info["infohash"] as? String,let index=info["index"] as? Int,index>=0,let name=info["basename"] as? String,let size=info["size"] as? NSNumber {
                        DispatchQueue.main.async {ThreeDRecognitionBridge.bindTorrent(path:url,infohash:hash,index:index,basename:name,size:size.int64Value)}
                    }
                } else if l.hasPrefix("STREAM:") {
                    Self.torrentDiagnostic("STREAM_RECEIVED")
                    let url = String(l.dropFirst("STREAM:".count))
                    self?.currentTorrentURL = url
                    let demuxerMaxBytes = AppDelegate.pendingDemuxerMaxBytes
                    let cacheSecs = AppDelegate.pendingCacheSecs
                    self?.controller?.ipcCommand(#"{"command":["script-message-to","photon","set-live","true"]}"#)
                    DispatchQueue.main.async { [weak self] in
                        // Baseline first so a previous file's branch profile
                        // (pixeldrain/MEGA) cannot leak in; PARAMS then owns
                        // cache/demuxer/decode for this torrent (pass-5 #4/#7).
                        Self.torrentDiagnostic("STREAM_MAIN_CALLBACK self_present=\(self != nil) controller_present=\(self?.controller != nil)")
                        self?.restoreDefaultProfile()
                        self?.controller?.ipcCommand(#"{"command":["set","cache","yes"]}"#)
                        self?.controller?.ipcCommand(#"{"command":["set","cache-secs","\#(cacheSecs)"]}"#)
                        self?.controller?.ipcCommand(#"{"command":["set","cache-pause-initial","yes"]}"#)
                        self?.controller?.ipcCommand(#"{"command":["set","demuxer-readahead-secs","\#(cacheSecs)"]}"#)
                        self?.controller?.ipcCommand(#"{"command":["set","demuxer-max-bytes","\#(demuxerMaxBytes / 1_000_000)M"]}"#)
                        // Live SDR photon samples an occasional screenshot instead of
                        // running signalstats as a per-frame vf. Keep hardware decode
                        // available for both SDR and HDR magnets (runtime fallback remains mpv's).
                        self?.controller?.ipcCommand(#"{"command":["set","hwdec","auto-safe"]}"#)
                        self?.controller?.ipcCommand(#"{"command":["set","cache-pause","no"]}"#)
                        self?.controller?.ipcCommand(#"{"command":["set","vd-lavc-skiploopfilter","all"]}"#)
                        
                        self?.torrentBrowserPanel?.removeFromSuperview()
                        self?.torrentBrowserPanel = nil
                        self?.isShowingInputPanel = PanelKeyOwnership.shared.panelOwnsKey
                        self?.overlayWin?.ignoresMouseEvents = false
                        self?.setEventTapEnabled(true)
                        self?.showTorrentOverlay(status: "stream ready")
                        
                        let pos = self?.controller?.pendingStreamStartPos
                        self?.controller?.pendingStreamStartPos = nil
                        self?.playMedia(url: url, title: self?.torrentTitle ?? "Torrent", startPos: pos)
                        
                        Self.torrentDiagnostic("STREAM_CONTROLS_BEFORE")
                        self?.controller?.spineUI.showStreamControls()
                        Self.torrentDiagnostic("STREAM_CONTROLS_AFTER")
                    }
                } else if l.hasPrefix("TITLE:") {
                    let title = String(l.dropFirst("TITLE:".count))
                    self?.torrentTitle = title
                    DispatchQueue.main.async { [weak self] in
                        self?.showTorrentOverlay(status: title)
                    }
                } else if l.hasPrefix("REQ:magnet-fallback ") {
                    // wt v22.6 dead-end request: search by media name, swap silently.
                    let payload = String(l.dropFirst("REQ:magnet-fallback ".count))
                    print("[wt] \(l)")
                    DispatchQueue.main.async { [weak self] in
                        // A dying previous wt_server must not trigger a swap for the new session.
                        guard let self, let p, self.torrentProcess === p else { return }
                        MagnetFallbackSearch.shared.handle(requestLine: payload, app: self)
                    }
                } else if l.hasPrefix("REQ:stream-dead ") {
                    let fields = l.split(separator: " ")
                    let token = fields.first(where: { $0.hasPrefix("token=") }).map { String($0.dropFirst(6)) }
                    print("[wt] \(l)")
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let p, self.torrentProcess === p, let token else { return }
                        self.controller?.recoverFrozenWTStream(token: token)
                    }
                } else if let status = AppDelegate.requestStatus(forLine: l) {
                    // wt escalations (REQ:integrity-stalled, stream-dead, swarm-too-slow,
                    // seek-no-follow) were only printed; the owner saw a silent stall.
                    print("[wt] \(l)")
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let p, self.torrentProcess === p else { return }
                        self.showTorrentOverlay(status: status)
                    }
                } else if l.hasPrefix("PUMP_RECEIPT:"),
                          ProcessInfo.processInfo.environment["GOR_WT_PUMP_RECEIPTS"] == "1" {
                    print("[wt-test] \(l)")
                } else if l.hasPrefix("REQ:") {
                    print("[wt] \(l)")
                }
            }
        }
        
        let stderrTail = WtStderrTail()
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // EOF: remove the handler (an empty read repeats forever otherwise) and tell the tail.
            guard !data.isEmpty else { handle.readabilityHandler = nil; stderrTail.markEOF(); return }
            stderrTail.append(data)
            guard let text = String(data: data, encoding: .utf8) else { return }
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("ERROR:") {
                DispatchQueue.main.async { [weak self] in
                    self?.showTorrentOverlay(status: line.dropFirst(6).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        Self.torrentDiagnostic("PROCESS_RUN_BEFORE")
        p.terminationHandler = { process in
            Self.torrentDiagnostic("PROCESS_TERMINATED pid=\(process.processIdentifier) status=\(process.terminationStatus) reason=\(process.terminationReason.rawValue)")
            // The stderr handler is the only reader. Wait briefly for its EOF (0.5 s cap, never reads), then log what it collected.
            let sawEOF = stderrTail.waitForEOF(timeout: 0.5)
            let tail = stderrTail.redactedLastLines()
            if !tail.isEmpty || process.terminationReason == .uncaughtSignal {
                Self.torrentDiagnostic("WT_STDERR_TAIL pid=\(process.processIdentifier) signal=\(process.terminationReason == .uncaughtSignal) eof=\(sawEOF) tail=[\(tail)]")
            }
        }
        do {
            try p.run()
            Self.torrentDiagnostic("PROCESS_RUN_OK pid=\(p.processIdentifier)")
            QuitChildKiller.shared.register(p) // post-run: pid registered once known
        } catch {
            let e = error as NSError
            Self.torrentDiagnostic("PROCESS_RUN_ERROR code=\(e.code)")
            showTorrentOverlay(status: "failed to start node: \(error.localizedDescription)")
        }
    }
    
    private func streamWithPeerflix(_ path: String, source: String) {
        showTorrentOverlay(status: "starting peerflix...")
        
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = [source, "-p", "8888", "-q"]
        
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        
        torrentProcess = p
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // EOF: an empty read repeats forever (busy loop) unless the handler is removed.
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let line = String(data: data, encoding: .utf8) else { return }
            
            if let range = line.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
                let streamURL = String(line[range]).trimmingCharacters(in: .init(charactersIn: "\r\n "))
                DispatchQueue.main.async { [weak self] in
                    self?.showTorrentOverlay(status: "stream ready")
                    self?.playMedia(url: streamURL, title: "Torrent")
                }
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }
        
        p.terminationHandler = { _ in
            try? FileManager.default.removeItem(atPath: "/tmp/webtorrent_stream")
        }
        
        do {
            try p.run()
            QuitChildKiller.shared.register(p) // post-run; the pre-run assignment had no pid
        } catch {
            showTorrentOverlay(status: "failed to start peerflix: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helpers
    
    func stopTorrent() {
        Self.swapGeneration += 1
        let hadActiveSession = torrentProcess != nil
            || torrentBrowserPanel != nil
            || !currentTorrentURL.isEmpty

        // Detach pipe handlers before teardown: a handler that outlives
        // the process keeps its captured buffers and the FileHandle alive.
        torrentStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        torrentStderrPipe?.fileHandleForReading.readabilityHandler = nil
        torrentStdoutPipe = nil
        torrentStderrPipe = nil
        torrentStdinPipe = nil
        torrentBrowserPanel?.removeFromSuperview()
        torrentBrowserPanel = nil
        // isRunning guard: the quit-time helper may already have killed it
        // (reachable before 176a via child self-crash as well).
        if let proc = torrentProcess, proc.isRunning {
            proc.terminate()
            // Reap off-main; wt_server's own watchdog exits within seconds.
            DispatchQueue.global(qos: .utility).async { proc.waitUntilExit() }
        }
        if let proc = torrentProcess { QuitChildKiller.shared.unregisterIfStopped(proc) }
        torrentProcess = nil
        torrentTitle = ""
        currentTorrentURL = ""

        guard hadActiveSession else { return }

        controller?.spineUI.hideStreamControls()
        controller?.ipcCommand(#"{"command":["script-message-to","photon","set-live","false"]}"#)
        controller?.ipcCommand(#"{"command":["set","hwdec","auto-safe"]}"#)
    }
    
    /// Short user-facing text for the wt requests that have no automatic Swift action.
    /// Returns nil for every other REQ line (caps, magnet-fallback and unknown kinds).
    static func requestStatus(forLine line: String) -> String? {
        if line.hasPrefix("REQ:integrity-stalled") { return "no verified data from the swarm - try another release" }
        if line.hasPrefix("REQ:stream-dead") { return "stream stalled - file > reload to reconnect" }
        if line.hasPrefix("REQ:swarm-too-slow") { return "swarm too slow for this file - try another release" }
        if line.hasPrefix("REQ:seek-no-follow") { return "player did not follow the seek - seek again" }
        return nil
    }

    private func showTorrentOverlay(status: String) {
        controller?.spineUI.showMPVOSD(status)
    }
    
    private func openTorrentBrowserPanel() {
        Self.torrentDiagnostic("PANEL_GUARD window_present=\(overlayWin != nil) content_present=\(overlayWin?.contentView != nil) controller_present=\(controller != nil)")
        guard let parentWin = overlayWin, let contentView = parentWin.contentView,
              let ctrl = controller else { Self.torrentDiagnostic("PANEL_GUARD_REJECT"); return }
        
        let padL: CGFloat = 40; let padR: CGFloat = 54; let padT: CGFloat = 9
        let base = ctrl.appliedVideoFrame == .zero ? contentView.bounds : ctrl.appliedVideoFrame
        // 197j (owner 11-16 17:10): with a fixed 9pt top inset the multi-file
        // selection panel's top rows opened inside the magnet/torrent HUD's
        // top region - the panel read as clipped at the top and outside the
        // player area. Anchor the top edge one text row below the HUD's
        // upper rows (SpineUI.hudUpperAnchorY, a uniform one-row gap in every
        // HUD state), floored at the old 9pt inset so the no-HUD case keeps
        // its exact previous frame, and clamped so a tall HUD always leaves
        // the top bar plus one list row visible (barH = PhotonFont.chromeLineH
        // + 4 and row = PhotonFont.chromeLineH, measured in
        // ArchiveBrowserPanel.layout).
        let hudAnchorY = ctrl.spineUI.hudUpperAnchorY
        let minPanelH = (PhotonFont.chromeLineH + 4) + PhotonFont.chromeLineH
        let topInset = min(max(padT, base.maxY - hudAnchorY),
                           max(padT, base.height - padT - minPanelH))
        let frame = CGRect(x: base.minX + padL, y: base.minY + padT,
                           width: base.width - padL - padR, height: base.height - padT - topInset)
        let panel = ArchiveBrowserPanel(frame: frame)
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor.clear.cgColor
        panel.autoresizingMask = [.width, .height]
        panel.onClose = { [weak self] in
            panel.removeFromSuperview()
            self?.torrentProcess?.terminate()
            self?.torrentBrowserPanel = nil
            self?.isShowingInputPanel = PanelKeyOwnership.shared.panelOwnsKey
            self?.overlayWin?.ignoresMouseEvents = false
            self?.setEventTapEnabled(true)
        }
        torrentBrowserPanel = panel
        Self.torrentDiagnostic("PANEL_ADD_BEFORE")
        contentView.addSubview(panel)
        Self.torrentDiagnostic("PANEL_ADD_AFTER attached=\(panel.superview != nil)")
        isShowingInputPanel = true
        setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = false
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            if event.keyCode == 53, panel?.superview != nil {
                panel?.removeFromSuperview(); return nil
            }
            return event
        }
    }
    
    
}

// ================================================================
//  String - String
// ================================================================
private extension String {
    func width(using font: NSFont) -> CGFloat {
        (self as NSString).size(withAttributes: [.font: font]).width
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
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')) else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/GorSources/TorrentManager.swift",
  "markers": [
    "private final class StdoutLineBuffer {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nprivate let p=StdoutLineBuffer()\ncheck(p.lines(appending:Data(\"STREAM:x\\r\\n\".utf8)) == [\"STREAM:x\"],\"CRLF clean protocol line\")\ncheck(p.lines(appending:Data(\"x\\n\".utf8)) == [\"x\"],\"LF unchanged\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL CRLF clean protocol line
PASS LF unchanged


```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. Single production path plus own test, no adoption or runtime closure.
