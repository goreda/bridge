# W-gdb-199e-1nstinct-23 - Google Drive download query must be a real parameter
state: OPEN / unclaimed
lab: 1nstinct

In classifyURL, admit /uc download shape only when parsed queryItems contains export=download as its own key/value. Substring occurrence inside another value or key must not trigger a Drive-file route. Preserve valid provider routes and explicit pseudo-links. No browser process or socket behavior edits.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-1nstinct-23",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorSources/CDPSession.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "In classifyURL, admit /uc download shape only when parsed queryItems contains export=download as its own key/value. Substring occurrence inside another value or key must not trigger a Drive-file route. Preserve valid provider routes and explicit pseudo-links. No browser process or socket behavior edits.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "archive/gor/Sources/gor/GorSources/CDPSession.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-23.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199e-1nstinct-23",
    "paths": [
      "archive/gor/Sources/gor/GorSources/CDPSession.swift",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-23.py",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-23.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-23.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorSources/CDPSession.swift",
        "block": "source1",
        "sha256": "7e29882b1d3ba4b427d202d3faf9ff950295194e23d2c5955bf2c6e5e5ecf18b",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-23.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-23.json",
        "block": "fixtures2",
        "sha256": "7fed0d79862e627570adcd56f5c543bea38243514c25e2ba3ebde2c3398b02c8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "b9087c65224f8007fb540f51cd6cdc37c46f61a53009a759a0effff0d082eb58",
    "last_5_lines": [
      "semantic_exit=1",
      "FAIL query value cannot impersonate download parameter",
      "FAIL suffix key cannot impersonate parameter",
      "PASS real parameter retained",
      ""
    ],
    "receipt_sha256": "e87ba7a5b66b65238a22e86cbce7a75839d639929f94524d59c9d2197f323cd7"
  }
}
```

```swift id=source1
// ================================================================
//  CDPSession.swift - Chrome DevTools Protocol session
//  Owns: Chromium process, WebSocket requests, transfer link capture
//  Contract: Callbacks complete once; pending handlers are cleaned up
// ================================================================

import AppKit
import Foundation
import Darwin
import CommonCrypto

// Gofile folder companion revision: 260930.1
// MARK: - CDPSession

// ================================================================
//  CDPSession - CDPSession
// ================================================================
final class CDPSession {
    // MARK: - Chromium
    private static var gofileCache: [String: (files: [ArchiveFile], timestamp: Date)] = [:]
    private static let gofileCacheTTL: TimeInterval = 300
    private var process: Process?
    private var userDataDir: String = ""
    private var debugPort: Int = 0
    
    // MARK: - WebSocket
    private var wsTask: URLSessionWebSocketTask?
    private var nextId = 1
    private var pending: [Int: ([String: Any]) -> Void] = [:]
    private var eventHandlers: [String: ([String: Any]) -> Void] = [:]
    
    // MARK: - Link Types
    enum LinkType {
        case transferIt
        case transferItFolder(shareURL: String, folderHandle: String)
        case mega(folderId: String, key: String)
        case megaFolder(shareURL: String, folderHandle: String)
        case megaFile(handle: String, key: String)
        case gofile(contentId: String)
        case gofileFolder(contentId: String)
        case gofileDirect(signed: String)
        case googleDriveFile(fileId: String)
        case googleDriveFolder(folderId: String)
        case pixeldrain(fileId: String)
        case archiveOrgProfile(username: String)
        case archiveOrgItem(identifier: String)
    }
    
    /// Parsed admission: provider routes are decided from scheme, host and path, never from
    /// substrings of the whole URL (a query or path containing "transfer.it" is not transfer.it).
    private struct ParsedLink {
        let host: String      // lowercased
        let path: String      // percent-decoded path, starts with "/"
        let query: String
        func host(is name: String) -> Bool { host == name || host.hasSuffix("." + name) }
        func pathAfter(_ prefix: String) -> String? {
            guard path.hasPrefix(prefix) else { return nil }
            return String(path.dropFirst(prefix.count))
        }
        func firstSegment(after prefix: String) -> String? {
            pathAfter(prefix)?.split(separator: "/").first.map(String.init)
        }
    }
    private static func parsedLink(_ url: String) -> ParsedLink? {
        guard let c = URLComponents(string: url), let scheme = c.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = c.host?.lowercased(), !host.isEmpty
        else { return nil }
        return ParsedLink(host: host, path: c.path, query: c.query ?? "")
    }

    static func classifyURL(_ url: String) -> LinkType? {
        // Internal pseudo-links are not URLs; keep them first and unchanged.
        if url.hasPrefix("mega-folder::") {
            let parts = url.components(separatedBy: "::")
            let shareURL = parts.count > 1 ? parts[1] : ""
            let handle   = parts.count > 2 ? parts[2] : ""
            return .megaFolder(shareURL: shareURL, folderHandle: handle)
        }
        if url.hasPrefix("transferit-folder::") {
            let parts = url.components(separatedBy: "::")
            let shareURL = parts.count > 1 ? parts[1] : ""
            let handle   = parts.count > 2 ? parts[2] : ""
            return .transferItFolder(shareURL: shareURL, folderHandle: handle)
        }
        if url.hasPrefix("gofile-folder::") {
            let contentId = url.components(separatedBy: "::").count > 1
                ? url.components(separatedBy: "::")[1] : ""
            return .gofileFolder(contentId: contentId)
        }
        if url.hasPrefix("gofile-direct::") {
            return .gofileDirect(signed: url)
        }
        guard let link = parsedLink(url) else { return nil }
        // The mega.nz key lives in the fragment; read it from the original string.
        let fragment = url.firstIndex(of: "#").map { String(url[url.index(after: $0)...]) } ?? ""
        if link.host(is: "mega.nz") {
            if let rest = link.pathAfter("/folder/") {
                return .mega(folderId: rest.split(separator: "/").first.map(String.init) ?? "", key: fragment)
            }
            if let rest = link.pathAfter("/file/") {
                return .megaFile(handle: rest.split(separator: "/").first.map(String.init) ?? "", key: fragment)
            }
        }
        if link.host(is: "transfer.it") { return .transferIt }
        if link.host(is: "gofile.io") {
            if link.path.hasPrefix("/download/") || link.host != "gofile.io" { return .gofile(contentId: "") }
            if let id = link.firstSegment(after: "/d/") { return .gofile(contentId: id) }
        }
        if link.host == "drive.google.com" {
            if let id = link.firstSegment(after: "/file/d/") { return .googleDriveFile(fileId: id) }
            if let id = link.firstSegment(after: "/drive/folders/") { return .googleDriveFolder(folderId: id) }
            if link.path == "/uc", link.query.contains("export=download") { return .googleDriveFile(fileId: "") }
        }
        if link.host == "drive.usercontent.google.com", link.path == "/download" {
            let id = URLComponents(string: url)?.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            return .googleDriveFile(fileId: id)
        }
        if link.host(is: "pixeldrain.com") {
            if let rest = link.pathAfter("/u/") { return .pixeldrain(fileId: rest.split(separator: "/").first.map(String.init) ?? "") }
            if let rest = link.pathAfter("/api/file/") { return .pixeldrain(fileId: rest.split(separator: "/").first.map(String.init) ?? "") }
        }
        if link.host(is: "archive.org") {
            if let rest = link.pathAfter("/details/@") {
                let username = rest.split(separator: "/").first.map(String.init) ?? ""
                return username.isEmpty ? nil : .archiveOrgProfile(username: username)
            }
            if let rest = link.pathAfter("/download/") {
                let identifier = rest.split(separator: "/").first.map(String.init) ?? ""
                return identifier.isEmpty ? nil : .archiveOrgItem(identifier: identifier)
            }
        }
        return nil
    }

    // MARK: - State
    private enum State {
        case idle
        case navigating
        case fetchingFiles
        case capturingURL
        case done
    }
    private var state: State = .idle
    private let stateLock = NSLock()
    
    private func setState(_ newState: State) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
    }
    
    private func isState(_ checkState: State) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state == checkState
    }
    
    // MARK: - Launch & Connect
    
    func start() throws {
        try launchChromium()
        let wsURL = try resolveWebSocketURL()
        connectWebSocket(wsURL)
        sendCommand("Network.enable")
        sendCommand("Page.enable")
        sendCommand("Runtime.enable")
    }
    
    // Fresh capture contract: launch/endpoint discovery on resolver worker;
    // WebSocket handlers, commands and retirement on main, like dispatch().
    func prepareCaptureTransport() throws -> URL {
        try launchChromium()
        return try resolveWebSocketURL()
    }

    func activateCaptureTransport(_ url: URL) {
        dispatchPrecondition(condition: .onQueue(.main))
        connectWebSocket(url)
        sendCommand("Network.enable")
        sendCommand("Page.enable")
        sendCommand("Runtime.enable")
    }

    func retireCaptureTransport() {
        dispatchPrecondition(condition: .onQueue(.main))
        activeCaptureID = nil
        setState(.done)
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        pending.removeAll()
        eventHandlers.removeAll()
        let retiredProcess = process
        let retiredDirectory = userDataDir
        process = nil
        userDataDir = ""
        // Never waitUntilExit on main. Cleanup is bounded even when Chromium
        // does not honor SIGTERM; do not hold URL completion behind teardown.
        DispatchQueue.global(qos: .utility).async {
            if let p = retiredProcess, p.isRunning {
                p.terminate()
                let deadline = Date().addingTimeInterval(1.0)
                while p.isRunning && Date() < deadline { usleep(20_000) }
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
            if !retiredDirectory.isEmpty {
                try? FileManager.default.removeItem(atPath: retiredDirectory)
            }
        }
    }

    private func launchChromium() throws {
        guard let bin = GORResources.vendor()?
            .appendingPathComponent(ArchiveConfig.chromiumPathUnderVendor).path,
            FileManager.default.isExecutableFile(atPath: bin) else {
            throw ArchiveError.chromiumNotFound
        }
        
        AppDelegate.checkChromiumOnUse(binary: bin)

        debugPort = findAvailablePort()
        userDataDir = "/tmp/gor-chrome-\(UUID().uuidString)"
        
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = [
            "--headless=new",
            "--remote-debugging-port=\(debugPort)",
            "--user-data-dir=\(userDataDir)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-gpu",
            "--disable-software-rasterizer",
            "--disable-dev-shm-usage",
            "--no-sandbox",
            "--window-size=1920,1080",
            "--disable-blink-features=AutomationControlled",
            "--network-timeout=15000",
            "about:blank",
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p
        
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let url = URL(string: "http://127.0.0.1:\(debugPort)/json/version"),
               let _ = try? Data(contentsOf: url) {
                return
            }
            usleep(100_000)
        }
        throw ArchiveError.chromiumTimeout
    }
    
    private func findAvailablePort() -> Int {
        for _ in 0..<100 {
            let port = Int.random(in: 20000...59000)
            let sock = socket(AF_INET, SOCK_STREAM, 0)
            if sock >= 0 {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(port).bigEndian
                addr.sin_addr.s_addr = in_addr_t(0)
                
                let bindResult = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                
                close(sock)
                if bindResult == 0 {
                    return port
                }
            }
        }
        return Int.random(in: 20000...59000)
    }
    
    private func resolveWebSocketURL() throws -> URL {
        let endpoints = [
            "http://127.0.0.1:\(debugPort)/json/list",
            "http://127.0.0.1:\(debugPort)/json",
        ]
        
        for ep in endpoints {
            guard let url = URL(string: ep),
                  let data = try? Data(contentsOf: url),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let ws = arr.first?["webSocketDebuggerUrl"] as? String,
                  let wsURL = URL(string: ws)
            else { continue }
            return wsURL
        }
        throw ArchiveError.cdpNoTarget
    }
    
    // MARK: - WebSocket
    
    private func connectWebSocket(_ url: URL) {
        Diag.log("[TRACE CDPSession] connecting WebSocket to \(url)")
        wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask?.resume()
        receiveLoop()
    }
    
    private func receiveLoop() {
        wsTask?.receive { [weak self] result in
            guard let self, self.isState(.done) == false else { return }
            switch result {
            case .success(.string(let text)):
                DispatchQueue.main.async { [weak self] in self?.dispatch(text) }
            case .success(.data):
                Diag.log("[TRACE CDPSession] receiveLoop got unexpected .data frame, ignoring")
            case .failure(let error):
                Diag.log("[TRACE CDPSession] receiveLoop FAILED: \(error.localizedDescription) — WebSocket is dead, no further CDP responses will arrive")
                return
            @unknown default:
                break
            }
            self.receiveLoop()
        }
    }
    
    private func dispatch(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        
        if let id = json["id"] as? Int {
            if let callback = pending.removeValue(forKey: id) {
                callback(json)
            }
            return
        }
        
        if let method = json["method"] as? String,
           let params = json["params"] as? [String: Any] {
            eventHandlers[method]?(params)
        }
    }
    
    @discardableResult
    private func sendCommand(_ method: String,
                             params: [String: Any] = [:],
                             completion: (([String: Any]) -> Void)? = nil) -> Int {
        let id = nextId
        nextId += 1
        
        var obj: [String: Any] = ["id": id, "method": method]
        if !params.isEmpty {
            obj["params"] = params
        }
        
        if let cb = completion {
            pending[id] = cb
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8)
        else {
            Diag.log("[TRACE CDPSession] sendCommand(\(method)) failed to serialize params, not sent")
            return id
        }
        
        if wsTask == nil {
            Diag.log("[TRACE CDPSession] sendCommand(\(method)) called but wsTask is nil — nothing will be sent")
        }
        
        wsTask?.send(.string(str)) { error in
            if let error {
                Diag.log("[TRACE CDPSession] sendCommand(\(method)) send FAILED: \(error.localizedDescription)")
            }
        }
        return id
    }
    
    // MARK: - Public API
    
    func fetchFileList(transferURL url: String, completion: @escaping ([ArchiveFile]) -> Void) {
        setState(.fetchingFiles)
        
        guard let linkType = CDPSession.classifyURL(url) else {
            completion([])
            return
        }
        
        switch linkType {
        case .gofileDirect:
            setState(.idle)
            completion([])
            return
            
        case .gofile(let contentId):
            resolveGofileFilesCDP(contentId:contentId, transferURL:url) { files, _ in completion(files) }
            return

        case .gofileFolder(let contentId):
            resolveGofileFilesCDP(contentId: contentId, transferURL: url) { files, _ in
                completion(files)
            }
            return
            
        case .googleDriveFolder(let folderId):
            resolveDriveFolder(folderId: folderId) { [weak self] driveFiles in
                let files = driveFiles.map { dict in
                    let isFolder = dict["folder"] == "true"
                    let url = isFolder ? "https://drive.google.com/drive/folders/\(dict["id"] ?? "")" : "\(ArchiveConfig.driveDownloadTemplate)\(dict["id"] ?? "")"
                    return ArchiveFile(
                        name: dict["name"] ?? "Unknown",
                        size: isFolder ? "📁" : "",
                        elementId: dict["id"] ?? "",
                        transferURL: url,
                        isFolder: isFolder
                    )
                }
                self?.setState(.idle)
                completion(files)
            }
            return
            
        case .googleDriveFile(let fileId):
            let file = ArchiveFile(
                name: "Drive File",
                size: "",
                elementId: fileId,
                transferURL: "\(ArchiveConfig.driveDownloadTemplate)\(fileId)", isFolder: false
                )
            setState(.idle)
            completion([file])
            return
            
        case .transferItFolder(let shareURL, let folderHandle):
            fetchTransferItNodes(shareURL: shareURL, parentHandle: folderHandle, completion: completion)
            return

        case .transferIt:
            fetchTransferItNodes(shareURL: url, parentHandle: nil, completion: completion)

            /* DispatchQueue.main.asyncAfter(deadline: .now() + ArchiveConfig.fileListTimeout) { [weak self] in
                guard let self, self.isState(.fetchingFiles) else { return }
                self.setState(.idle)
                completion([])
            } */

        case .megaFolder(let shareURL, let folderHandle):
            fetchMegaNodes(shareURL: shareURL, parentHandle: folderHandle, completion: completion)
            return

        case .mega:
            fetchMegaNodes(shareURL: url, parentHandle: nil, completion: completion)

        case .megaFile:
            // Single-file links never reach CDP - TransferResolver.fetchFiles
            // answers them directly; defensive only.
            setState(.idle)
            completion([])
            return
            
        case .pixeldrain:
            setState(.idle)
            completion([])
            return

        case .archiveOrgProfile, .archiveOrgItem:
            setState(.idle)
            completion([])
            return
        }
    }
    
    private func fetchTransferItNodes(shareURL: String, parentHandle: String?, completion: @escaping ([ArchiveFile]) -> Void) {
        let parentHandleJS = parentHandle ?? ""

        func readFromMd() {
            let js = """
            (function() {
                if (typeof M === 'undefined' || !M.d) return JSON.stringify({error: 'M_not_ready'});
                var videoExts = ['mkv','mp4','avi','webm','mov','ts','m2ts','mpg','mpeg','wmv','flv','ogv','divx','vob'];
                function isVideo(name) {
                    var ext = (name || '').split('.').pop().toLowerCase();
                    return videoExts.indexOf(ext) !== -1;
                }
                var parentId = '\(parentHandleJS)' || M.RootID;
                var nodes = Object.values(M.d).filter(function(n) { return n.p === parentId; });
                var result = nodes.map(function(n) {
                    var isFolder = n.t === 1;
                    var sizeStr = '';
                    if (!isFolder && n.s) {
                        var mb = n.s / 1048576;
                        sizeStr = mb >= 1024 ? (mb/1024).toFixed(2) + ' GB' : mb.toFixed(0) + ' MB';
                    }
                    return { h: n.h, name: n.name, isFolder: isFolder, size: sizeStr, isVideo: !isFolder && isVideo(n.name) };
                }).filter(function(n) { return n.isFolder || n.isVideo; });
                return JSON.stringify({parentId: parentId, nodes: result});
            })()
            """

            func tryRead(attemptsLeft: Int) {
                sendCommand("Runtime.evaluate", params: ["expression": js, "returnByValue": true]) { [weak self] response in
                    guard let self, self.isState(.fetchingFiles) else { return }

                    guard let result  = response["result"] as? [String: Any],
                          let value   = result["result"] as? [String: Any],
                          let jsonStr = value["value"] as? String,
                          let data    = jsonStr.data(using: .utf8),
                          let dict    = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else {
                        Diag.log("🔄 Transfer.it parse error, attemptsLeft=\(attemptsLeft)")
                        guard attemptsLeft > 0 else {
                            print("⚠️ Transfer.it nodes unreadable, giving up")
                            self.setState(.idle)
                            completion([])
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { tryRead(attemptsLeft: attemptsLeft - 1) }
                        return
                    }

                    if dict["error"] != nil {
                        // One shared budget for every failure mode - the old
                        // reset-to-8 made an unreadable share retry forever.
                        guard attemptsLeft > 0 else {
                            print("⚠️ Transfer.it M.d never became ready, giving up")
                            self.setState(.idle)
                            completion([])
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { tryRead(attemptsLeft: attemptsLeft - 1) }
                        return
                    }

                    guard let nodes = dict["nodes"] as? [[String: Any]] else {
                        Diag.log("🔄 Transfer.it nodes parse error, attemptsLeft=\(attemptsLeft)")
                        guard attemptsLeft > 0 else {
                            print("⚠️ Transfer.it nodes unreadable, giving up")
                            self.setState(.idle)
                            completion([])
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { tryRead(attemptsLeft: attemptsLeft - 1) }
                        return
                    }

                    let files: [ArchiveFile] = nodes.compactMap { node in
                        guard let h    = node["h"]    as? String, !h.isEmpty,
                              let name = node["name"] as? String, !name.isEmpty else { return nil }
                        let isFolder = node["isFolder"] as? Bool ?? false
                        let isRoot = (parentHandle == nil)
                        let cleanShare = shareURL.components(separatedBy: "::").last ?? shareURL
                        let effectiveURL = (isRoot && !isFolder) ? cleanShare : "transferit-folder::\(cleanShare)::\(h)"
                        return ArchiveFile(name: name,
                                           size: node["size"] as? String ?? "",
                                           elementId: h,
                                           transferURL: effectiveURL,
                                           isFolder: isFolder)
                    }.sorted {
                        if $0.isFolder != $1.isFolder { return $0.isFolder }
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    print("Transfer.it M.d: \(files.count) items")
                    self.setState(.idle)
                    completion(files)
                }
            }
            tryRead(attemptsLeft: 8)
        }

        if parentHandle != nil {
            readFromMd()
        } else {
            sendCommand("Page.navigate", params: ["url": shareURL])
            DispatchQueue.main.asyncAfter(deadline: .now() + ArchiveConfig.pageSettleDelay) { [weak self] in
                guard let self, self.isState(.fetchingFiles) else { return }
                self.sendCommand("Runtime.evaluate", params: [
                    "expression": "document.querySelector('.js-view-content')?.click()"
                ])
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    readFromMd()
                }
            }
        }
    }
    
    // MARK: - Mega.nz (independent of transfer.it — different domain, own case,
    private static func megaNodeKeyString(handle: String, rawK: Any?) -> String? {
        guard let words = rawK as? [Any], !words.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(words.count * 4)
        for word in words {
            let signed: Int32
            if let n = word as? NSNumber {
                signed = n.int32Value
            } else if let s = word as? String, let parsed = Int32(s) {
                signed = parsed
            } else {
                Diag.log("[TRACE fetchMegaNodes] megaNodeKeyString: unexpected k element shape \(word), aborting for handle=\(handle)")
                return nil
            }
            let unsigned = UInt32(bitPattern: signed)
            bytes.append(UInt8((unsigned >> 24) & 0xff))
            bytes.append(UInt8((unsigned >> 16) & 0xff))
            bytes.append(UInt8((unsigned >> 8) & 0xff))
            bytes.append(UInt8(unsigned & 0xff))
        }
        let base64url = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(handle):\(base64url)"
    }

    private func fetchMegaNodes(shareURL: String, parentHandle: String?, completion: @escaping ([ArchiveFile]) -> Void) {
        let parentHandleJS = parentHandle ?? ""

        func readFromMd() {
            let js = """
            (function() {
                if (typeof M === 'undefined' || !M.d) return JSON.stringify({error: 'M_not_ready'});
                var videoExts = ['mkv','mp4','avi','webm','mov','ts','m2ts','mpg','mpeg','wmv','flv','ogv','divx','vob'];
                function isVideo(name) {
                    var ext = (name || '').split('.').pop().toLowerCase();
                    return videoExts.indexOf(ext) !== -1;
                }
                var parentId = '\(parentHandleJS)' || M.RootID;
                var nodes = Object.values(M.d).filter(function(n) { return n.p === parentId; });
                var result = nodes.map(function(n) {
                    var isFolder = n.t === 1;
                    var sizeStr = '';
                    if (!isFolder && n.s) {
                        var mb = n.s / 1048576;
                        sizeStr = mb >= 1024 ? (mb/1024).toFixed(2) + ' GB' : mb.toFixed(0) + ' MB';
                    }
                    return { h: n.h, name: n.name, isFolder: isFolder, size: sizeStr, isVideo: !isFolder && isVideo(n.name), k: n.k };
                }).filter(function(n) { return n.isFolder || n.isVideo; });
                return JSON.stringify({parentId: parentId, nodes: result});
            })()
            """

            func tryRead(attemptsLeft: Int) {
                sendCommand("Runtime.evaluate", params: ["expression": js, "returnByValue": true]) { [weak self] response in
                    guard let self, self.isState(.fetchingFiles) else {
                        Diag.log("[TRACE fetchMegaNodes] Runtime.evaluate callback fired but state is not fetchingFiles — dropping")
                        return
                    }

                    guard let result  = response["result"] as? [String: Any],
                          let value   = result["result"] as? [String: Any],
                          let jsonStr = value["value"] as? String,
                          let data    = jsonStr.data(using: .utf8),
                          let dict    = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else {
                        Diag.log("[TRACE fetchMegaNodes] parse error on Runtime.evaluate response, attemptsLeft=\(attemptsLeft), raw response=\(response)")
                        guard attemptsLeft > 0 else {
                            print("⚠️ Mega nodes unreadable, giving up")
                            self.setState(.idle)
                            completion([])
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { tryRead(attemptsLeft: attemptsLeft - 1) }
                        return
                    }

                    if dict["error"] != nil {
                        Diag.log("[TRACE fetchMegaNodes] M_not_ready, attemptsLeft=\(attemptsLeft)")
                        // One shared budget for every failure mode - the old
                        // reset-to-8 made an unreadable share retry forever.
                        guard attemptsLeft > 0 else {
                            print("⚠️ Mega M.d never became ready, giving up")
                            self.setState(.idle)
                            completion([])
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { tryRead(attemptsLeft: attemptsLeft - 1) }
                        return
                    }

                    guard let nodes = dict["nodes"] as? [[String: Any]] else {
                        Diag.log("[TRACE fetchMegaNodes] nodes field missing/wrong type, dict=\(dict)")
                        guard attemptsLeft > 0 else {
                            print("⚠️ Mega nodes unreadable, giving up")
                            self.setState(.idle)
                            completion([])
                            return
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { tryRead(attemptsLeft: attemptsLeft - 1) }
                        return
                    }

                    let files: [ArchiveFile] = nodes.compactMap { node in
                        guard let h    = node["h"]    as? String, !h.isEmpty,
                              let name = node["name"] as? String, !name.isEmpty else { return nil }
                        let isFolder = node["isFolder"] as? Bool ?? false
                        let isRoot = (parentHandle == nil)
                        let cleanShare = shareURL.components(separatedBy: "::").last ?? shareURL
                        let effectiveURL = (isRoot && !isFolder) ? cleanShare : "mega-folder::\(cleanShare)::\(h)"
                        let nodeKey = Self.megaNodeKeyString(handle: h, rawK: node["k"])
                        return ArchiveFile(name: name,
                                           size: node["size"] as? String ?? "",
                                           elementId: h,
                                           transferURL: effectiveURL,
                                           isFolder: isFolder,
                                           nodeKey: nodeKey)
                    }.sorted {
                        if $0.isFolder != $1.isFolder { return $0.isFolder }
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    Diag.log("[DEBUG fetchMegaNodes] \(files.count) items found (parentHandle=\(parentHandle ?? "root"))")
                    self.setState(.idle)
                    completion(files)
                }
            }
            tryRead(attemptsLeft: 8)
        }

        if parentHandle != nil {
            Diag.log("[TRACE fetchMegaNodes] subfolder request, handle=\(parentHandle ?? ""), reading from in-memory M.d")
            readFromMd()
        } else {
            Diag.log("[TRACE fetchMegaNodes] root request, navigating to \(shareURL)")
            sendCommand("Page.navigate", params: ["url": shareURL])
            DispatchQueue.main.asyncAfter(deadline: .now() + ArchiveConfig.pageSettleDelay) { [weak self] in
                guard let self, self.isState(.fetchingFiles) else {
                    Diag.log("[TRACE fetchMegaNodes] page-settle callback fired but state is not fetchingFiles — dropping")
                    return
                }
                Diag.log("[TRACE fetchMegaNodes] page settled, attempting to click view-content equivalent")
                self.sendCommand("Runtime.evaluate", params: [
                    "expression": "document.querySelector('.js-view-content')?.click()"
                ])
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    readFromMd()
                }
            }
        }
    }
    
    // MARK: - Gofile HTTP API
    
    func resolveGofileFilesAPI(contentId: String, transferURL: String, completion: @escaping ([ArchiveFile]) -> Void) {
        print("🔍 Gofile API: contentId=\(contentId)")
        
        guard let accountURL = URL(string: "\(ArchiveConfig.gofileAPIBase)/accounts") else {
            completion([]); return
        }
        var req = URLRequest(url: accountURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokenData = json["data"] as? [String: Any],
                  let token = tokenData["token"] as? String else {
                DispatchQueue.main.async { completion([]) }; return
            }
            let ts = Int64(Date().timeIntervalSince1970 / 14400)
            let raw = "\(ArchiveConfig.gofileUserAgent)::en-US::\(token)::\(ts)::\(ArchiveConfig.gofileWT)"
            let hash = self.sha256(raw)
            self.fetchGofileContent(contentId: contentId, token: token, hash: hash, transferURL: transferURL, completion: completion)
        }.resume()
    }
    
    private func fetchGofileContent(contentId: String, token: String, hash: String, transferURL: String, completion: @escaping ([ArchiveFile]) -> Void) {
        guard let url = URL(string: "\(ArchiveConfig.gofileAPIBase)/contents/\(contentId)") else {
            completion([]); return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(hash, forHTTPHeaderField: "X-Website-Token")
        req.setValue("en-US", forHTTPHeaderField: "X-BL")
        req.setValue(ArchiveConfig.gofileUserAgent, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String, status == "ok",
                  let dataDict = json["data"] as? [String: Any],
                  let children = dataDict["children"] as? [String: Any] ?? dataDict["childs"] as? [String: Any]
            else {
                DispatchQueue.main.async { completion([]) }; return
            }
            
            var files: [ArchiveFile] = []
            for (_, child) in children {
                guard let childDict = child as? [String: Any],
                      let name = childDict["name"] as? String,
                      let id = childDict["id"] as? String ?? childDict["code"] as? String
                else { continue }
                let lower = name.lowercased()
                let isVideo = ArchiveConfig.videoExtensions.contains(where: { lower.hasSuffix(".\($0)") })
                if isVideo || ["srt", "ass", "ssa", "vtt"].contains((name as NSString).pathExtension.lowercased()) {
                    let link = childDict["link"] as? String ?? ""
                    let cdnURL = link.isEmpty ? "" : link.replacingOccurrences(of: "store-", with: "file-")
                    let fileTransferURL = cdnURL.isEmpty ? transferURL : "gofile-direct::\(token)::\(cdnURL)"
                    files.append(ArchiveFile(name: name, size: childDict["size"] as? String ?? "", elementId: id, transferURL: fileTransferURL, isFolder: false, gofileFolderID: contentId))
                    continue
                }
                if (childDict["type"] as? String) == "folder" {
                    files.append(ArchiveFile(name: name, size: "📁", elementId: id,
                                              transferURL: "https://gofile.io/d/\(id)", isFolder: true))
                } else {
                    files.append(ArchiveFile(name: "⚠️ \(name)", size: "desteklenmiyor", elementId: id,
                                              transferURL: "gofile-unresolved::\(id)", isFolder: false))
                }
            }
            print("📂 Gofile API: \(files.count) items")
            DispatchQueue.main.async { completion(files) }
        }.resume()
    }
    
    private func sha256(_ str: String) -> String {
        let data = Data(str.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
        
    // Read the page's own contents response only after its body has finished.
    // Keep the DOM route as a bounded fallback, not an empty-success shortcut.
    func resolveGofileFilesCDP(contentId: String, transferURL: String,
                               completion: @escaping ([ArchiveFile], String?) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.resolveGofileFilesCDP(contentId:contentId, transferURL:transferURL, completion:completion)
            }
            return
        }
        guard contentId.range(of: #"^[A-Za-z0-9_-]{4,80}$"#, options: .regularExpression) != nil else {
            completion([], "Invalid Gofile folder code"); return
        }
        setState(.fetchingFiles)
        var accountToken = ""
        var primaryDone = false
        var delivered = false
        var requests = Set<String>()
        var responseIds = Set<String>()
        var completedIds = Set<String>()
        var extraHeaders: [String: [String: Any]] = [:]
        let handlerNames = ["Network.requestWillBeSent", "Network.requestWillBeSentExtraInfo",
                            "Network.responseReceived", "Network.loadingFinished", "Network.loadingFailed"]
        func deliver(_ files: [ArchiveFile], _ error: String?) {
            guard !delivered else { return }
            delivered = true
            self.setState(.idle)
            completion(files, error)
        }
        func finish(_ files: [ArchiveFile], _ error: String?) {
            guard !primaryDone, self.isState(.fetchingFiles) else { return }
            primaryDone = true
            for name in handlerNames { self.eventHandlers.removeValue(forKey:name) }
            if let error {
                Diag.log("Gofile API-backed route failed: \(error); trying legacy DOM")
                self.resolveGofileFilesDOMLegacy(contentId:contentId, transferURL:transferURL, completion:deliver)
            } else { deliver(files, nil) }
        }
        func readToken(_ headers: [String: Any]) {
            for (key, value) in headers where key.lowercased() == "authorization" {
                if let auth = value as? String, auth.hasPrefix("Bearer ") {
                    let token = String(auth.dropFirst(7))
                    if token.range(of: #"^[A-Za-z0-9_-]{8,512}$"#, options:.regularExpression) != nil { accountToken = token }
                }
            }
        }
        func parseResponse(_ response: [String: Any]) {
            guard !primaryDone, self.isState(.fetchingFiles), response["result"] != nil else { return }  // failed body read (preflight) is not a verdict
            guard let result = response["result"] as? [String: Any], let body = result["body"] as? String,
                  let data = (result["base64Encoded"] as? Bool == true ? Data(base64Encoded:body) : body.data(using:.utf8)),
                  data.count <= 2_000_000,
                  let envelope = try? JSONSerialization.jsonObject(with:data) as? [String: Any],
                  envelope["status"] as? String == "ok",
                  let folder = envelope["data"] as? [String: Any], folder["type"] as? String == "folder",
                  let children = folder["children"] as? [String: Any] else {
                finish([], "Unreadable or inaccessible Gofile folder response"); return
            }
            let declared = (folder["childrenCount"] as? NSNumber)?.intValue ?? children.count
            guard declared == children.count, declared <= 100 else {
                finish([], "Gofile listing is incomplete or has more than one page"); return
            }
            var files: [ArchiveFile] = []
            for child in children.values {
                guard let item = child as? [String: Any], let id = item["id"] as? String, !id.isEmpty,
                      let name = item["name"] as? String, !name.isEmpty, let type = item["type"] as? String else {
                    finish([], "Incomplete Gofile child entry"); return
                }
                if type == "folder" {
                    let code = item["code"] as? String ?? id
                    guard code.range(of: #"^[A-Za-z0-9_-]{4,80}$"#, options:.regularExpression) != nil else {
                        finish([], "Invalid Gofile child folder code"); return
                    }
                    files.append(ArchiveFile(name:name, size:"", elementId:id,
                                             transferURL:"gofile-folder::\(code)", isFolder:true))
                } else if type == "file" {
                    let ext = (name as NSString).pathExtension.lowercased()
                    guard ArchiveConfig.videoExtensions.contains(ext) || ["srt", "ass", "ssa", "vtt"].contains(ext) else { continue }
                    guard let link = item["link"] as? String, let url = URL(string:link), url.scheme == "https",
                          let host = url.host?.lowercased(), host.hasSuffix(".gofile.io"),
                          url.user == nil, url.password == nil, url.path.hasPrefix("/download/"), !accountToken.isEmpty else {
                        finish([], "Gofile media link or account token missing"); return
                    }
                    let bytes = (item["size"] as? NSNumber)?.int64Value ?? 0
                    files.append(ArchiveFile(name:name,
                        size:bytes > 0 ? ByteCountFormatter.string(fromByteCount:bytes, countStyle:.file) : "",
                        elementId:id, transferURL:"gofile-direct::\(accountToken)::\(link)", isFolder:false, gofileFolderID: contentId))
                } else { finish([], "Unknown Gofile child type"); return }
            }
            files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            print("[gofile-subtitles 260930.1] folder listing: \(files.filter { !$0.isFolder && !$0.isGofileSubtitle }.count) videos, \(files.filter { $0.isGofileSubtitle }.count) subtitles")
            finish(files, nil)
        }
        func readBody(_ requestId: String) {
            guard !primaryDone, responseIds.contains(requestId), completedIds.contains(requestId) else { return }
            responseIds.remove(requestId)
            self.sendCommand("Network.getResponseBody", params:["requestId":requestId], completion:parseResponse)
        }
        func contentsURL(_ value: Any?) -> Bool {
            guard let value = value as? String, let url = URL(string:value) else { return false }
            return url.scheme == "https" && url.host == "api.gofile.io" && url.path == "/contents/\(contentId)"
        }
        eventHandlers["Network.requestWillBeSentExtraInfo"] = { params in
            guard let id = params["requestId"] as? String, let headers = params["headers"] as? [String: Any] else { return }
            if requests.contains(id) { readToken(headers) }
            else if extraHeaders.count < 256 { extraHeaders[id] = headers }
        }
        eventHandlers["Network.requestWillBeSent"] = { params in
            guard let request = params["request"] as? [String: Any], contentsURL(request["url"]), params["type"] as? String != "Preflight",
                  ((request["method"] as? String) ?? "GET").uppercased() == "GET", let id = params["requestId"] as? String else { return }
            requests.insert(id)
            readToken(request["headers"] as? [String: Any] ?? [:])
            if let headers = extraHeaders.removeValue(forKey:id) { readToken(headers) }
        }
        eventHandlers["Network.responseReceived"] = { params in
            guard let response = params["response"] as? [String: Any], contentsURL(response["url"]),
                  let id = params["requestId"] as? String, requests.contains(id) else { return }
            responseIds.insert(id); readBody(id)
        }
        eventHandlers["Network.loadingFinished"] = { params in
            guard let id = params["requestId"] as? String, requests.contains(id) || responseIds.contains(id) else { return }
            completedIds.insert(id); readBody(id)
        }
        eventHandlers["Network.loadingFailed"] = { params in
            guard let id = params["requestId"] as? String, requests.contains(id) else { return }
            finish([], "Gofile contents request failed")
        }
        sendCommand("Page.navigate", params:["url":"https://gofile.io/d/\(contentId)"])
        DispatchQueue.main.asyncAfter(deadline:.now()+35) { [weak self] in
            guard self != nil else { return }
            finish([], "Gofile folder did not respond within 35 seconds")
        }
    }

    // Kept as a maintained fallback if the site's API-backed route changes.
    private func resolveGofileFilesDOMLegacy(contentId: String, transferURL: String, completion: @escaping ([ArchiveFile], String?) -> Void) {
        setState(.fetchingFiles)
        var finished = false
        func finishLegacy(_ files: [ArchiveFile], _ error: String?) {
            guard !finished else { return }
            finished = true
            self.setState(.idle)
            completion(files, error)
        }
        
        if let cached = CDPSession.gofileCache[contentId],
           Date().timeIntervalSince(cached.timestamp) < CDPSession.gofileCacheTTL {
            print("Gofile cached: \(cached.files.count) videos")
            setState(.idle)
            finishLegacy(cached.files, nil)
            return
        }
        
        let url = "https://gofile.io/d/\(contentId)"
        
        Diag.log("[TRACE resolveGofileFilesCDP] sending Page.navigate to \(url)")
        sendCommand("Page.navigate", params: ["url": url])
        
        var attempts = 0
        let maxAttempts = 16 // guest account boot + SPA listing can exceed ten seconds
        func tryJS() {
            guard !finished else { return }
            attempts += 1
            Diag.log("[TRACE resolveGofileFilesCDP] tryJS() start, attempt=\(attempts), state=\(self.isState(.fetchingFiles) ? "fetchingFiles" : "OTHER")")
            let js = """
            (function() {
                // The current SPA renders API-backed rows; the legacy #filemanager_itemslist is gone.
                var rows = document.querySelectorAll('#fm-list .fm-row[data-id][data-type]');
                var bodyText = (document.body.innerText || '').toLowerCase();
                if (!rows.length) {
                    if (bodyText.indexOf('currently unavailable') !== -1 ||
                        bodyText.indexOf('cannot be used right now') !== -1) return 'api_unavailable';
                    if (bodyText.indexOf('password') !== -1 && document.querySelector('input[type=password]')) return 'access_denied';
                    if (bodyText.indexOf('no items to display') !== -1) return '[]';
                    if (bodyText.indexOf('this file does not exist') !== -1 ||
                        bodyText.indexOf('could not be found') !== -1) return 'not_found';
                    return 'wait';
                }
                var result = [];
                rows.forEach(function(el) {
                    var isFolder = el.getAttribute('data-type') === 'folder';
                    var isVideo = /\\.(mkv|mp4|mov|m4v|avi|webm|wmv|flv|ts|m2ts|mpg|mpeg)$/i.test(
                                      el.querySelector('[data-action="open-file"] p')?.textContent || '');
                    var isSubtitle = /\\.(srt|ass|ssa|vtt)$/i.test(
                                         el.querySelector('[data-action="open-file"] p')?.textContent || '');
                    if (!isVideo && !isSubtitle && !isFolder) return;
                    var nameEl = el.querySelector('[data-action="open-file"] p, a[data-action="navigate"] p');
                    var name = nameEl ? (nameEl.textContent || '').trim() : '';
                    var href = el.querySelector('a[data-action="navigate"]')?.getAttribute('href') || '';
                    var code = href.match(/\\/d\\/([A-Za-z0-9_-]+)/)?.[1] || el.getAttribute('data-id');
                    result.push({name: name, id: el.getAttribute('data-id'), code: code, isFolder: isFolder});
                });
                // Never silently label page 1 a complete listing when the SPA paginates.
                var pagination = document.querySelector('#fm-pagination-top, #fm-pagination');
                var nextPage = pagination && pagination.querySelector('[data-action="page-next"]:not([disabled])');
                return nextPage ? 'pagination_required' : JSON.stringify(result);
            })();
            """
            
            self.sendCommand("Runtime.evaluate", params: ["expression": js, "returnByValue": true]) { [weak self] response in
                guard let self else {
                    Diag.log("[TRACE resolveGofileFilesCDP] Runtime.evaluate callback fired but self is nil — session was deallocated")
                    return
                }
                guard !finished, self.isState(.fetchingFiles) else {
                    Diag.log("[TRACE resolveGofileFilesCDP] Runtime.evaluate callback fired but state is no longer fetchingFiles — dropping silently, this is the bug if you see it")
                    return
                }
                
                let value = (response["result"] as? [String: Any])?["result"] as? [String: Any]
                let raw = value?["value"] as? String ?? ""
                Diag.log("[DEBUG resolveGofileFilesCDP] attempt=\(attempts) raw=\(raw)")
                
                if raw == "wait" && attempts < maxAttempts {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { tryJS() }
                    return
                }

                if raw == "api_unavailable" {
                    self.setState(.idle)
                    print("Gofile API unavailable (page is showing an error message) — empty list does not mean no files")
                    finishLegacy([], "Gofile API is currently unavailable, please try again later")
                    return
                }

                if raw == "wait" {
                    // The shared-link page may be delayed by guest-account boot or a failed
                    // /contents call. Capture a bounded diagnostic, not an invented cause.
                    let diagnosticJS = """
                    (function() {
                        var root = document.querySelector('#fm-root');
                        return JSON.stringify({
                            url: location.origin + location.pathname,
                            title: document.title,
                            state: document.readyState,
                            root: !!root,
                            rows: document.querySelectorAll('#fm-list .fm-row[data-id]').length,
                            text: (document.body?.innerText || '').slice(0, 700)
                        });
                    })();
                    """
                    self.sendCommand("Runtime.evaluate", params: ["expression": diagnosticJS, "returnByValue": true]) { diagnosticResponse in
                        let result = (diagnosticResponse["result"] as? [String: Any])?["result"] as? [String: Any]
                        let detail = result?["value"] as? String ?? "no page snapshot"
                        guard !finished else { return }
                        Diag.log("[Gofile listing timeout] \(detail)")
                        self.setState(.idle)
                        print("Gofile page did not show file list within 32 seconds (see gor_direct.log)")
                        finishLegacy([], "Gofile page did not load as expected, please try again later")
                    }
                    return
                }

                if raw == "not_found" {
                    self.setState(.idle)
                    finishLegacy([], "Gofile says this link could not be found")
                    return
                }
                
                if raw == "pagination_required" || raw == "access_denied" {
                    self.setState(.idle)
                    finishLegacy([], raw == "pagination_required"
                        ? "Gofile folder has more than one page; listing all pages is not implemented"
                        : "Gofile folder requires access or a password")
                    return
                }

                self.setState(.idle)
                
                guard let data = raw.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    Diag.log("[DEBUG resolveGofileFilesCDP] JSON parse failed, raw=\(raw)")
                    finishLegacy([], "Gofile DOM returned an unreadable listing"); return
                }
                
                let files = arr.compactMap { dict -> ArchiveFile? in
                    guard let name = dict["name"] as? String, !name.isEmpty,
                          let id = dict["id"] as? String, !id.isEmpty
                    else { return nil }
                    let isFolder = dict["isFolder"] as? Bool ?? false
                    let effectiveURL = isFolder ? "gofile-folder::\(dict["code"] as? String ?? id)" : url
                    return ArchiveFile(name: name, size: "", elementId: id, transferURL: effectiveURL, isFolder: isFolder, gofileFolderID: contentId)
                }
                CDPSession.gofileCache[contentId] = (files, Date())
                print("Gofile CDP: \(files.count) items found (\(files.filter { $0.isFolder }.count) folders, \(files.filter { !$0.isFolder && !$0.isGofileSubtitle }.count) videos, \(files.filter { $0.isGofileSubtitle }.count) subtitles) (cached)")
                finishLegacy(files, nil)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { tryJS() }
        
        // Longer than the 2 + 15*2s readiness loop, so only a stalled CDP
        // evaluation reaches this hard stop. Do not silently report an empty folder.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45.0) { [weak self] in
            guard let self, !finished, self.isState(.fetchingFiles) else { return }
            self.setState(.idle)
            Diag.log("[Gofile listing timeout] No CDP result in 45 seconds; check WebSocket/network")
            finishLegacy([], "Gofile page did not respond within 45 seconds")
        }
    }
    
    // MARK: - Google Drive
    
    func resolveDriveFolder(folderId: String, completion: @escaping ([[String: String]]) -> Void) {
        let cleanFolderId = folderId.components(separatedBy: "?").first ?? folderId
        print("🔍 Drive folder: \(cleanFolderId)")
        
        guard let url = URL(string: "https://drive.google.com/drive/folders/\(cleanFolderId)") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            var files: [[String: String]] = []
            
            if let ivdRange = html.range(of: "_DRIVE_ivd'] = '"),
               let ivdEnd = html[ivdRange.upperBound...].range(of: "';") {
                let ivdStr = String(html[ivdRange.upperBound..<ivdEnd.lowerBound])
                
                let decoded = ivdStr
                    .replacingOccurrences(of: "\\x5b", with: "[")
                    .replacingOccurrences(of: "\\x5d", with: "]")
                    .replacingOccurrences(of: "\\x22", with: "\"")
                    .replacingOccurrences(of: "\\u003d", with: "=")
                    .replacingOccurrences(of: "\\/", with: "/")
                
                if let pattern = try? NSRegularExpression(pattern: #"\["([A-Za-z0-9_-]{25,35})",\[[^\]]*\],"([^"]+\.(mp4|mkv|avi|webm|mov|ts|m2ts))""#) {
                    let matches = pattern.matches(in: decoded, range: NSRange(location: 0, length: decoded.utf16.count))
                    for match in matches {
                        let fileId = (decoded as NSString).substring(with: match.range(at: 1))
                        let fileName = (decoded as NSString).substring(with: match.range(at: 2))
                        files.append(["name": fileName, "id": fileId, "folder": "false"])
                    }
                }

                if let folderPattern = try? NSRegularExpression(pattern: #"\["([A-Za-z0-9_-]{25,35})",\[[^\]]*\],"([^"]+)",\s*"application/vnd\.google-apps\.folder""#) {
                    let folderMatches = folderPattern.matches(in: decoded, range: NSRange(location: 0, length: decoded.utf16.count))
                    for match in folderMatches {
                        let folderId = (decoded as NSString).substring(with: match.range(at: 1))
                        let folderName = (decoded as NSString).substring(with: match.range(at: 2))
                        if !files.contains(where: { $0["id"] == folderId }) {
                            files.append(["name": folderName, "id": folderId, "folder": "true"])
                        }
                    }
                }
            }
            
            if files.isEmpty, let pattern = try? NSRegularExpression(pattern: #"/file/d/([A-Za-z0-9_-]{25,35})"#) {
                let ns = html as NSString
                for match in pattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                    let fileId = ns.substring(with: match.range(at: 1))
                    if !files.contains(where: { $0["id"] == fileId }) {
                        files.append(["name": "Drive File", "id": fileId])
                    }
                }
            }
            
            print("📂 Drive folder: \(files.count) files")
            for f in files { print("   📄 \(f["name"] ?? "?") -> \(f["id"] ?? "?")") }
            DispatchQueue.main.async { completion(files) }
        }.resume()
    }
    
    func resolveDriveFileWithUUID(fileId: String, completion: @escaping (String?) -> Void) {
        let url = "https://drive.usercontent.google.com/download?export=download&id=\(fileId)"
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion("\(ArchiveConfig.driveDownloadTemplate)\(fileId)") }
                return
            }
            
            if html.contains("Virus scan warning") {
                if let uuidRange = html.range(of: "name=\"uuid\" value=\""),
                   let uuidEnd = html[uuidRange.upperBound...].range(of: "\"") {
                    let uuid = String(html[uuidRange.upperBound..<uuidEnd.lowerBound])
                    let finalURL = "https://drive.usercontent.google.com/download?export=download&confirm=t&id=\(fileId)&uuid=\(uuid)"
                    print("🔗 Drive with uuid: \(finalURL)")
                    DispatchQueue.main.async { completion(finalURL) }
                } else {
                    DispatchQueue.main.async { completion("\(ArchiveConfig.driveDownloadTemplate)\(fileId)") }
                }
            } else {
                DispatchQueue.main.async { completion("\(ArchiveConfig.driveDownloadTemplate)\(fileId)") }
            }
        }.resume()
    }
    
    
    private var activeCaptureID: UUID?
    private func isCurrentCapture(_ id: UUID) -> Bool { activeCaptureID == id }

    // Preserve transport/cookie jar while invalidating only this capture's
    // timers, recursive polls, response callbacks and handlers.
    func cancelCapture(_ id: UUID) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard activeCaptureID == id else { return }
        activeCaptureID = nil
        cleanupEventHandlers()
        sendCommand("Runtime.evaluate", params: ["expression": "window.__gorCaptureID = '';", "returnByValue": false])
        setState(.idle)
    }

    func captureSignedURL(transferURL url: String,
                          elementId: String,
                          captureID: UUID = UUID(),
                          completion: @escaping (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let previous = activeCaptureID { cancelCapture(previous) }
        activeCaptureID = captureID
        Diag.log("🚨 [DEBUG] CDPSession.captureSignedURL ENTERED url=\(url) elementId=\(elementId)")
        setState(.capturingURL)
        
        guard let linkType = CDPSession.classifyURL(url) else {
            Diag.log("🚨 [DEBUG] captureSignedURL: classifyURL nil, bailing")
            completion(nil)
            return
        }
        Diag.log("🚨 [DEBUG] captureSignedURL: linkType=\(linkType)")
        
        switch linkType {
        case .gofileDirect(let signed):
            let parts = signed.components(separatedBy: "::")
            let token = parts.count > 2 ? parts[1] : ""
            let cdnURL = parts.count > 2 ? parts[2...].joined(separator: "::") : (parts.count > 1 ? parts[1] : "")
            setState(.idle)
            if cdnURL.isEmpty {
                completion(nil)
            } else if token.isEmpty {
                completion(cdnURL)
            } else {
                let cookieStr = "accountToken=\(token)"
                completion("\(cdnURL)|gofile-token=\(token)|cookie=\(cookieStr)")
            }
            return
            
        case .gofile:
            break

        case .gofileFolder:
            Diag.log("🚨 [DEBUG] captureSignedURL: .gofileFolder — not downloadable; returning nil")
            setState(.idle)
            completion(nil)
            return
            
        case .googleDriveFile(let fileId):
            resolveDriveFileWithUUID(fileId: fileId) { finalURL in
                guard self.isCurrentCapture(captureID) else { return }
                self.setState(.idle)
                completion(finalURL)
            }
            return
            
        case .googleDriveFolder:
            setState(.idle)
            completion(elementId)
            return
            
        case .transferItFolder(let shareURL, _):
            let shareID = shareURL.components(separatedBy: "::").last?.components(separatedBy: "/t/").last?.components(separatedBy: "/").first ?? ""
            guard !shareID.isEmpty, elementId.count == 8 else { break }
            captureTransferItURL(shareID: shareID, elementId: elementId, captureID: captureID, completion: completion)
            return

        case .transferIt:
            let shareURL = url
            let shareID = shareURL.components(separatedBy: "/t/").last?.components(separatedBy: "/").first ?? ""
            guard !shareID.isEmpty, elementId.count == 8 else { break }

            sendCommand("Page.navigate", params: ["url": shareURL])
            DispatchQueue.main.asyncAfter(deadline: .now() + ArchiveConfig.pageSettleDelay) { [weak self] in
                guard let self, self.isCurrentCapture(captureID) else { return }
                guard self.isState(.capturingURL) else { return }
                self.sendCommand("Runtime.evaluate", params: [
                    "expression": "document.querySelector('.js-view-content')?.click()"
                ])
                self.waitForMd(attemptsLeft: 20, captureID: captureID) { [weak self] ready in
                    guard let self, self.isCurrentCapture(captureID) else { return }
                    guard self.isState(.capturingURL) else { return }
                    if ready {
                        self.captureTransferItURL(shareID: shareID, elementId: elementId, captureID: captureID, completion: completion)
                    } else {
                        print("⚠️ Transfer.it: M.d never populated")
                        self.setState(.idle)
                        DispatchQueue.main.async { completion(nil) }
                    }
                }
            }
            return

        case .megaFolder(let shareURL, _):
            // The megajs relay resolves the share, node keys and CDN URL from
            // the link itself - no in-page "g" XHR, no CDP capture. Hand the
            // share URL straight through; the file handle travels in
            // ArchiveFile.nodeKey ("<handle>:<b64>") from the M.d scrape.
            Diag.log("[TRACE captureSignedURL] .megaFolder - relay resolves, passing share URL through")
            setState(.idle)
            DispatchQueue.main.async { completion(shareURL) }
            return

        case .mega, .megaFile:
            // Root folder link or single-file link: the link is all the relay
            // needs (megajs reads the key from the #fragment).
            Diag.log("[TRACE captureSignedURL] .mega/.megaFile - relay resolves, passing link through")
            setState(.idle)
            DispatchQueue.main.async { completion(url) }
            return
            
        case .pixeldrain:
            setState(.idle)
            completion(url)
            return

        case .archiveOrgProfile, .archiveOrgItem:
            setState(.idle)
            completion(url)
            return
        }
        
        var captured = false
        let captureLock = NSLock()
        // Several event handlers, main-thread click retries, and the timeout
        // all race to fire completion once. The lock alone didn't help while
        // half the touch points bypassed it - route every access through
        // these two.
        func claimCapture() -> Bool {
            guard self.isCurrentCapture(captureID) else { return false }
            captureLock.lock()
            defer { captureLock.unlock() }
            if captured { return false }
            captured = true
            return true
        }
        func isCaptured() -> Bool {
            captureLock.lock()
            defer { captureLock.unlock() }
            return captured
        }

        if url.contains("gofile.io") {
            sendCommand("Fetch.enable", params: [
                "patterns": [["urlPattern": "*gofile.io/download/*", "requestStage": "Request"]]
            ])

            eventHandlers["Fetch.requestPaused"] = { [weak self] params in
                guard let self, self.isCurrentCapture(captureID) else { return }
                guard let requestId = params["requestId"] as? String else { return }

                captureLock.lock()
                let alreadyCaptured = captured
                captureLock.unlock()

                guard !alreadyCaptured else {
                    self.sendCommand("Fetch.failRequest", params: ["requestId": requestId, "errorReason": "Aborted"])
                    return
                }

                guard let requestInfo = params["request"] as? [String: Any],
                      let reqUrl = requestInfo["url"] as? String,
                      reqUrl.contains("gofile.io/download/"), !reqUrl.contains("/thumb_")
                else {
                    self.sendCommand("Fetch.continueRequest", params: ["requestId": requestId])
                    return
                }

                guard claimCapture() else {
                    self.sendCommand("Fetch.failRequest", params: ["requestId": requestId, "errorReason": "Aborted"])
                    return
                }

                // Cookies are attached by Chrome and need not appear in request.headers.
                // Query the cookie jar for the storage hostname before handing the URL to mpv.
                self.sendCommand("Network.getCookies", params: ["urls": [reqUrl]]) { response in
                    guard self.isCurrentCapture(captureID) else { return }
                    let cookies = (response["result"] as? [String: Any])?["cookies"] as? [[String: Any]] ?? []
                    let cookieValue = cookies.compactMap { cookie -> String? in
                        guard let name = cookie["name"] as? String,
                              let value = cookie["value"] as? String else { return nil }
                        return "\(name)=\(value)"
                    }.joined(separator: "; ")
                    self.setState(.idle)
                    self.cleanupEventHandlers()
                    self.sendCommand("Fetch.failRequest", params: ["requestId": requestId, "errorReason": "Aborted"])
                    let finalURL = cookieValue.isEmpty ? reqUrl : "\(reqUrl)|cookie=\(cookieValue)"
                    print("🔗 Gofile intercepted before download: \(reqUrl.prefix(120)) hasCookie=\(!cookieValue.isEmpty)")
                    DispatchQueue.main.async { completion(finalURL) }
                }
            }
        }
        
        let urlHandler: ([String: Any]) -> Void = { [weak self] params in
            guard let self, self.isCurrentCapture(captureID) else { return }
            captureLock.lock()
            defer { captureLock.unlock() }
            guard !captured else { return }
            let capturedURL = (params["request"] as? [String: Any])?["url"] as? String
                   ?? (params["response"] as? [String: Any])?["url"] as? String
                   ?? ""
            if capturedURL.contains("mega.co.nz/dl/") && capturedURL.count > 80 {
                captured = true
                self.setState(.idle)
                self.cleanupEventHandlers()
                DispatchQueue.main.async { completion(capturedURL) }
            }
        }
        
        if !url.contains("gofile.io") {
            eventHandlers["Network.requestWillBeSent"] = urlHandler
            eventHandlers["Network.responseReceived"] = urlHandler
        }
        
        if !url.contains("gofile.io") {
            eventHandlers["Browser.downloadWillBegin"] = { [weak self] params in
                guard let self, self.isCurrentCapture(captureID) else { return }
                if let downloadUrl = params["url"] as? String,
                   !downloadUrl.contains("/thumb_") {
                    guard claimCapture() else { return }
                    self.setState(.idle)
                    self.cleanupEventHandlers()
                    DispatchQueue.main.async { completion(downloadUrl) }
                }
            }
            
            eventHandlers["Page.frameRequestedNavigation"] = { [weak self] params in
                guard let self, self.isCurrentCapture(captureID) else { return }
                if let url = params["url"] as? String,
                   !url.contains("/thumb_") {
                    guard claimCapture() else { return }
                    self.sendCommand("Network.getCookies", params: ["urls": [url]]) { response in
                    guard self.isCurrentCapture(captureID) else { return }
                        let cookies = (response["result"] as? [String: Any])?["cookies"] as? [[String: Any]] ?? []
                        let cookieStr = cookies.compactMap { c -> String? in
                            guard let name = c["name"] as? String, let value = c["value"] as? String else { return nil }
                            return "\(name)=\(value)"
                        }.joined(separator: "; ")
                        self.setState(.idle)
                        self.cleanupEventHandlers()
                        let finalURL = cookieStr.isEmpty ? url : "\(url)|cookie=\(cookieStr)"
                        print("🔗 Captured via frameRequestedNavigation: \(finalURL)")
                        DispatchQueue.main.async { completion(finalURL) }
                    }
                }
            }
            
            eventHandlers["Target.targetCreated"] = { [weak self] params in
                guard let self, self.isCurrentCapture(captureID) else { return }
                if let targetInfo = params["targetInfo"] as? [String: Any],
                   let url = targetInfo["url"] as? String,
                   !url.contains("/thumb_") {
                    guard claimCapture() else { return }
                    self.setState(.idle)
                    self.cleanupEventHandlers()
                    print("🔗 Captured via targetCreated: \(url)")
                    DispatchQueue.main.async { completion(url) }
                }
            }
        }
        
        sendCommand("Page.navigate", params: ["url": url])
        
        if url.contains("gofile.io") {
            let delays: [TimeInterval] = [3, 4, 4, 4]

            func attemptClick(_ index: Int) {
                guard index < delays.count else { return }
                let delay = delays[index]
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.isCurrentCapture(captureID) else { return }
                    guard self.isState(.capturingURL), !isCaptured() else { return }

                    let js = """
                    (function() {
                        var el = Array.from(document.querySelectorAll('#fm-list .fm-row[data-id]'))
                            .find(function(row) { return row.getAttribute('data-id') === "\(elementId)"; });
                        if (!el) return 'el_not_found';
                        var btn = el.querySelector('button[data-action="download"]');
                        if (!btn) return 'btn_not_found';
                        btn.click();
                        return 'clicked';
                    })();
                    """

                    self.sendCommand("Runtime.evaluate", params: ["expression": js, "returnByValue": true]) { [weak self] response in
                        guard let self, self.isCurrentCapture(captureID) else { return }
                        guard self.isState(.capturingURL), !isCaptured() else { return }
                        let value = (response["result"] as? [String: Any])?["result"] as? [String: Any]
                        let result = value?["value"] as? String ?? "?"
                        Diag.log("🔍 [DEBUG t=\(Int(delay))s attempt=\(index + 1)/\(delays.count)] Gofile click result: \(result)")

                        if result == "clicked" {
                            return
                        }

                        attemptClick(index + 1)
                    }
                }
            }

            attemptClick(0)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + ArchiveConfig.pageSettleDelay) { [weak self] in
                guard let self, self.isCurrentCapture(captureID) else { return }
                guard self.isState(.capturingURL), !isCaptured() else { return }

                self.sendCommand("Runtime.evaluate", params: [
                    "expression": "document.querySelector('.js-view-content')?.click()"
                ])

                let js = """
                (function() {
                    window.__gorCaptureID = '\(captureID.uuidString)';
                    var tries = 0;
                    var interval = setInterval(function() {
                        if (window.__gorCaptureID !== '\(captureID.uuidString)') { clearInterval(interval); return; }
                        var el = document.getElementById('\(elementId)');
                        if (el) {
                            var btn = el.querySelector('button.js-download')
                                   || el.querySelector('button[class*="download"]')
                                   || el.querySelector('button');
                            if (btn) {
                                btn.click();
                                clearInterval(interval);
                                return;
                            }
                        }
                        tries++;
                        if (tries > 30) clearInterval(interval);
                    }, 300);
                })();
                """

                self.sendCommand("Runtime.evaluate", params: ["expression": js, "returnByValue": true]) { response in
                    guard self.isCurrentCapture(captureID) else { return }
                    let value = (response["result"] as? [String: Any])?["result"] as? [String: Any]
                    let result = value?["value"] as? String ?? "?"
                    Diag.log("🔍 Stream click result: \(result)")
                }
            }
        }

        let effectiveTimeout: TimeInterval = url.contains("gofile.io") ? 25.0 : ArchiveConfig.urlCaptureTimeout

        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveTimeout) { [weak self] in
            guard let self, self.isCurrentCapture(captureID) else { return }
            guard claimCapture() else { return }
            self.setState(.idle)
            self.cleanupEventHandlers()
            print("⚠️ URL capture timeout (after \(Int(effectiveTimeout))s)")
            completion(nil)
        }
    }
    
    private func waitForMd(attemptsLeft: Int, captureID: UUID, completion: @escaping (Bool) -> Void) {
        guard isCurrentCapture(captureID) else { return }
        let js = "typeof M !== 'undefined' && M.d && Object.keys(M.d).length > 0 ? 'ready' : 'wait'"
        sendCommand("Runtime.evaluate", params: ["expression": js, "returnByValue": true]) { [weak self] response in
            guard let self, self.isCurrentCapture(captureID) else { return }
            let val = (response["result"] as? [String: Any]).flatMap { $0["result"] as? [String: Any] }.flatMap { $0["value"] as? String } ?? "wait"
            if val == "ready" {
                completion(true)
            } else if attemptsLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, self.isCurrentCapture(captureID) else { return }
                    self.waitForMd(attemptsLeft: attemptsLeft - 1, captureID: captureID, completion: completion)
                }
            } else {
                completion(false)
            }
        }
    }

    private func captureTransferItURL(shareID: String,
                                      elementId: String,
                                      captureID: UUID,
                                      xhrAttemptsLeft: Int = 4,
                                      completion: @escaping (String?) -> Void) {
        guard isCurrentCapture(captureID) else { return }
        sendCommand("Runtime.evaluate", params: ["expression": "delete window['__xhrCDN_\(captureID.uuidString)'];", "returnByValue": false])

        let xhrJS = """
        (function() {
            window['__xhrCDN_\(captureID.uuidString)'] = '';
            var xhr = new XMLHttpRequest();
            xhr.open('GET', 'https://bt7.api.mega.co.nz/cs/g?x=\(shareID)&n=\(elementId)&fn=x', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState >= 2 && xhr.responseURL && xhr.responseURL.length > 0) {
                    window['__xhrCDN_\(captureID.uuidString)'] = xhr.responseURL;
                    xhr.abort();
                }
            };
            xhr.send();
        })();
        'sent';
        """
        sendCommand("Runtime.evaluate", params: ["expression": xhrJS, "returnByValue": true]) { [weak self] _ in
            guard let self, self.isCurrentCapture(captureID) else { return }
            self.pollXhrCDN(attemptsLeft: 15, captureID: captureID) { [weak self] val in
                guard let self, self.isCurrentCapture(captureID) else { return }
                if let val, val.contains("userstorage") {
                    print("🔗 Transfer.it XHR CDN: \(val.prefix(2222))...")
                    self.setState(.idle)
                    self.cleanupEventHandlers()
                    DispatchQueue.main.async { completion(val) }
                } else if xhrAttemptsLeft > 0 {
                    print("⚠️ Transfer.it XHR empty, retrying (\(xhrAttemptsLeft) left)…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self, self.isCurrentCapture(captureID) else { return }
                        self.captureTransferItURL(shareID: shareID, elementId: elementId,
                                                   captureID: captureID, xhrAttemptsLeft: xhrAttemptsLeft - 1,
                                                   completion: completion)
                    }
                } else {
                    print("⚠️ Transfer.it XHR exhausted")
                    self.setState(.idle)
                    self.cleanupEventHandlers()
                    DispatchQueue.main.async { completion(nil) }
                }
            }
        }
    }

    private func pollXhrCDN(attemptsLeft: Int, captureID: UUID, completion: @escaping (String?) -> Void) {
        guard isCurrentCapture(captureID) else { return }
        sendCommand("Runtime.evaluate", params: ["expression": "window['__xhrCDN_\(captureID.uuidString)'] || ''", "returnByValue": true]) { [weak self] response in
            guard let self, self.isCurrentCapture(captureID) else { return }
            let val = (response["result"] as? [String: Any]).flatMap { $0["result"] as? [String: Any] }.flatMap { $0["value"] as? String } ?? ""
            if !val.isEmpty {
                completion(val)
            } else if attemptsLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, self.isCurrentCapture(captureID) else { return }
                    self.pollXhrCDN(attemptsLeft: attemptsLeft - 1, captureID: captureID, completion: completion)
                }
            } else {
                completion(nil)
            }
        }
    }

    private func cleanupEventHandlers() {
        eventHandlers.removeValue(forKey: "Network.requestWillBeSent")
        eventHandlers.removeValue(forKey: "Network.responseReceived")
        eventHandlers.removeValue(forKey: "Page.loadEventFired")
        eventHandlers.removeValue(forKey: "Page.frameStoppedLoading")
        eventHandlers.removeValue(forKey: "Browser.downloadWillBegin")
        eventHandlers.removeValue(forKey: "Page.frameRequestedNavigation")
        eventHandlers.removeValue(forKey: "Target.targetCreated")
        if eventHandlers.removeValue(forKey: "Fetch.requestPaused") != nil {
            sendCommand("Fetch.disable")
        }
    }
    
    func terminate() {
        setState(.done)
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        pending.removeAll()
        eventHandlers.removeAll()
        if let p = process, p.isRunning {
            p.terminate()
            p.waitUntilExit()
        }
        process = nil
        if !userDataDir.isEmpty {
            try? FileManager.default.removeItem(atPath: userDataDir)
        }
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
  "source": "archive/gor/Sources/gor/GorSources/CDPSession.swift",
  "markers": [
    "enum LinkType {",
    "private struct ParsedLink {",
    "private static func parsedLink(",
    "static func classifyURL("
  ],
  "wrapper": "enum CDPSession",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\ncheck(CDPSession.classifyURL(\"https://drive.google.com/uc?note=export=download\") == nil,\"query value cannot impersonate download parameter\")\ncheck(CDPSession.classifyURL(\"https://drive.google.com/uc?notexport=download\") == nil,\"suffix key cannot impersonate parameter\")\nif case .googleDriveFile? = CDPSession.classifyURL(\"https://drive.google.com/uc?export=download&id=123\") {check(true,\"real parameter retained\")} else {check(false,\"real parameter retained\")}\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL query value cannot impersonate download parameter
FAIL suffix key cannot impersonate parameter
PASS real parameter retained


```

Publication caveat: NONQUALIFIED: exact-source declaration extraction, not native/full module acceptance. HeatTelemetry in A27 is an explicit test support value, not production telemetry evidence. Own compiler rerun NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
