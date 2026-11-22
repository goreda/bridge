// ================================================================
//  TransferResolver.swift - CDPSession lifecycle for transfer links
//  (gofile, transfer.it, mega, drive, pixeldrain) plus the archive.org
//  catalogue and resolver
//  Owns: gor.archive.cdp serial queue, the single CDPSession,
//  ArchiveOrgCatalogue disk state, archive.org HTTP fetches
//  Contract: one CDP operation at a time on the serial queue; the
//  session survives the root fetch for subfolder navigation; catalogue
//  data is append-only, never re-fetched once written
//  Not here: CDP command mechanics (CDPSession.swift)
// ================================================================
import AppKit
import Foundation

// ================================================================
//  TransferResolver - one CDPSession at a time on a serial queue
// ================================================================

// WARP is a system-wide tunnel. Only gor-created connections may be undone.
// Keep this list in one place when a new host requires the tunnel.
final class TunnelForBlockedHosts {
    static let shared = TunnelForBlockedHosts()
    private let exactHosts: Set<String> = ["gofile.io", "api.gofile.io"]
    private let storeSuffix = ".gofile.io" // region-specific store-* hosts

    func needsTunnel(_ rawURL: String) -> Bool {
        let address = rawURL.hasPrefix("gofile-folder::")
            ? "https://gofile.io/d/" + String(rawURL.dropFirst("gofile-folder::".count))
            : rawURL
        guard let host = URLComponents(string: address)?.host?.lowercased() else { return false }
        return exactHosts.contains(host) ||
            ((host.hasPrefix("store-") || host.hasPrefix("file-")) && host.hasSuffix(storeSuffix))
    }

    // Inject a fake runner in a test without installing warp-cli.
    var run: (_ arguments: [String], _ timeout: TimeInterval) -> (Int32, String)? = TunnelForBlockedHosts.shellRun
    private let lock = NSRecursiveLock()
    private let eventQueue = DispatchQueue(label: "gor.warp.playback", qos: .utility)
    private var connectedByGOR = false
    private var resolving = 0
    private var playing = false
    private var browsing = false
    private var waitingForLoad = false
    private var quit = false

    private static func shellRun(_ arguments: [String], _ timeout: TimeInterval) -> (Int32, String)? {
        let process = Process()
        let paths = ["/usr/local/bin/warp-cli", "/opt/homebrew/bin/warp-cli", "/usr/bin/warp-cli"]
        if let installed = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            process.executableURL = URL(fileURLWithPath: installed)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["warp-cli"] + arguments
        }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private enum Status { case connected, disconnected, unknown }
    private func status() -> Status {
        guard let (code, text) = run(["status"], 3), code == 0 else { return .unknown }
        // Match only a status field; "Disconnected" contains "Connected".
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        for line in lines where line.hasPrefix("status:") || line.hasPrefix("status update:") {
            let value = line.components(separatedBy: ":").dropFirst().joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)
            if value == "connected" || value.hasPrefix("connected ") { return .connected }
            if value == "disconnected" || value.hasPrefix("disconnected ") { return .disconnected }
        }
        return .unknown
    }

    @discardableResult func beginResolution(for url: String) -> Bool {
        guard needsTunnel(url) else { return true }
        lock.lock(); defer { lock.unlock() }
        guard !quit else { return false }
        resolving += 1
        switch status() {
        case .connected: browsing = true; return true
        case .unknown:
            resolving -= 1
            Diag.log("[WARP] warp-cli missing or status unknown; blocked host needs WARP")
            return false
        case .disconnected: break
        }
        guard let (code, _) = run(["connect"], 4), code == 0 else {
            resolving -= 1
            Diag.log("[WARP] connect failed; blocked host needs WARP")
            return false
        }
        connectedByGOR = true
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if status() == .connected { browsing = true; return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        resolving -= 1
        Diag.log("[WARP] connect timed out after 15s; blocked host needs WARP")
        restoreIfIdle()
        return false
    }

    func endResolution() {
        lock.lock(); defer { lock.unlock() }
        resolving = max(0, resolving - 1)
        restoreIfIdle()
    }

    // Called before loadfile. A second blocked-host load preserves the tunnel.
    func willLoad(_ url: String) {
        lock.lock(); defer { lock.unlock() }
        let blocked = needsTunnel(url)
        playing = blocked
        browsing = blocked
        waitingForLoad = blocked
        restoreIfIdle()
    }

    func fileLoaded() {
        eventQueue.async { [self] in
            lock.lock(); defer { lock.unlock() }
            waitingForLoad = false
        }
    }

    func browserClosed() {
        lock.lock(); defer { lock.unlock() }
        browsing = false
        restoreIfIdle()
    }

    func fileEnded(reason: String) {
        eventQueue.async { [self] in
            lock.lock(); defer { lock.unlock() }
            // mpv emits end-file(stop) for the replaced item before file-loaded.
            guard !waitingForLoad else { return }
            if reason == "error" { Diag.log("[WARP] blocked-host playback ended with mpv error") }
            playing = false
            restoreIfIdle()
        }
    }

    func stopOrQuit() {
        lock.lock(); defer { lock.unlock() }
        playing = false
        browsing = false
        waitingForLoad = false
        restoreIfIdle()
    }

    func shutdown() {
        lock.lock(); defer { lock.unlock() }
        quit = true
        resolving = 0
        playing = false
        browsing = false
        waitingForLoad = false
        restoreIfIdle()
    }

    private func restoreIfIdle() {
        guard connectedByGOR, resolving == 0, !playing, !browsing, !waitingForLoad else { return }
        // User may have manually changed WARP while gor was playing.
        if status() == .connected {
            guard let (code, _) = run(["disconnect"], 4), code == 0 else {
                Diag.log("[WARP] disconnect failed; gor-created tunnel remains connected")
                return
            }
        }
        connectedByGOR = false
    }
}

final class TransferResolver {
    private let queue = DispatchQueue(label: "gor.archive.cdp", qos: .userInitiated)
    private var session: CDPSession?
    // Read on worker queues, written by cancel() on main.
    private let isCancelledLock = NSLock()
    private var _isCancelled = false
    private var isCancelled: Bool {
        get { isCancelledLock.lock(); defer { isCancelledLock.unlock() }; return _isCancelled }
        set { isCancelledLock.lock(); _isCancelled = newValue; isCancelledLock.unlock() }
    }
    
    func fetchFiles(url: String, completion: @escaping ([ArchiveFile], String?) -> Void) {
        isCancelled = false
        if url.hasPrefix("gor-archive-container:") {
            ArchiveContainerBrowser.resolve(url) { files, error in
                DispatchQueue.main.async { completion(files, error) }
            }
            return
        }

        guard let linkType = CDPSession.classifyURL(url) else {
            DispatchQueue.main.async { completion([], nil) }
            return
        }

        switch linkType {
        case .gofileDirect:
            DispatchQueue.main.async { completion([], nil) }
            return

        case .gofile(let contentId):
            // WHY: api.gofile.io is unreachable from this network, so the
            // CDP path reads the file list from the gofile.io/d/<id> page's
            // own DOM in headless Chrome - needs a live DevTools session.
            session?.terminate(); session = nil
            let session = CDPSession()
            self.session = session
            queue.async { [weak self] in
                guard let self, !self.isCancelled else {
                    DispatchQueue.main.async { completion([], nil) }
                    return
                }
                guard TunnelForBlockedHosts.shared.beginResolution(for: url) else {
                    DispatchQueue.main.async { completion([], "Gofile needs WARP to connect") }
                    return
                }
                do {
                    try session.start()
                    session.resolveGofileFilesCDP(contentId: contentId, transferURL: url) { files, errorMessage in
                        TunnelForBlockedHosts.shared.endResolution()
                        DispatchQueue.main.async { completion(files, errorMessage) }
                    }
                } catch {
                    TunnelForBlockedHosts.shared.endResolution()
                    print("❌ TransferResolver.fetchFiles (.gofile/CDP): \(error.localizedDescription)")
                    session.terminate()
                    self.session = nil
                    DispatchQueue.main.async { completion([], nil) }
                }
            }
            return

        case .gofileFolder(let contentId):
            // same as .gofile; the contentId is the tapped folder's own id
            // (gofile folders are self-contained UUIDs, no parent handle)
            session?.terminate(); session = nil
            let session = CDPSession()
            self.session = session
            queue.async { [weak self] in
                guard let self, !self.isCancelled else {
                    DispatchQueue.main.async { completion([], nil) }
                    return
                }
                guard TunnelForBlockedHosts.shared.beginResolution(for: url) else {
                    DispatchQueue.main.async { completion([], "Gofile needs WARP to connect") }
                    return
                }
                do {
                    try session.start()
                    session.resolveGofileFilesCDP(contentId: contentId, transferURL: url) { files, errorMessage in
                        TunnelForBlockedHosts.shared.endResolution()
                        DispatchQueue.main.async { completion(files, errorMessage) }
                    }
                } catch {
                    TunnelForBlockedHosts.shared.endResolution()
                    print("❌ TransferResolver.fetchFiles (.gofileFolder/CDP): \(error.localizedDescription)")
                    session.terminate()
                    self.session = nil
                    DispatchQueue.main.async { completion([], nil) }
                }
            }
            return

        case .googleDriveFolder(let folderId):
            session?.terminate(); session = nil
            let session = CDPSession()
            session.resolveDriveFolder(folderId: folderId) { driveFiles in
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
                DispatchQueue.main.async { completion(files, nil) }
            }
            return

        case .googleDriveFile(let fileId):
            session?.terminate(); session = nil
            let file = ArchiveFile(
                name: "Drive File",
                size: "",
                elementId: fileId,
                transferURL: "\(ArchiveConfig.driveDownloadTemplate)\(fileId)", isFolder: false
            )
            DispatchQueue.main.async { completion([file], nil) }
            return

        case .transferItFolder(_, _):
            // keep the current session - M.d is already in memory
            guard let session = self.session else {
                DispatchQueue.main.async { completion([], nil) }
                return
            }
            session.fetchFileList(transferURL: url) { files in
                DispatchQueue.main.async { completion(files, nil) }
            }
            return

        case .transferIt:
            session?.terminate(); session = nil
            break

        case .megaFolder(_, _):
            // Mega.nz subfolder — reuse existing session, M.d already in memory.
            // Fully independent of transfer.it's session/state.
            guard let session = self.session else {
                DispatchQueue.main.async { completion([], nil) }
                return
            }
            session.fetchFileList(transferURL: url) { files in
                DispatchQueue.main.async { completion(files, nil) }
            }
            return

        case .mega:
            // Mega.nz root link — fresh session, falls through to the generic
            // CDP-start block below (same as .transferIt does).
            session?.terminate(); session = nil
            break

        case .megaFile(let handle, _):
            // Single-file mega link — one placeholder row, no CDP. The megajs
            // relay resolves the real name/size/key from the link at play time.
            session?.terminate(); session = nil
            let file = ArchiveFile(name: "MEGA file \(handle)", size: "", elementId: handle, transferURL: url, isFolder: false)
            DispatchQueue.main.async { completion([file], nil) }
            return
            
        case .pixeldrain(let fileId):
            session?.terminate(); session = nil
            guard let url = URL(string: "https://pixeldrain.com/api/file/\(fileId)/info") else {
                DispatchQueue.main.async { completion([], nil) }
                return
            }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async { completion([], nil) }
                    return
                }
                let name = json["name"] as? String ?? "Unknown"
                let sizeBytes = json["size"] as? Int64 ?? 0
                let sizeStr = sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file) : ""
                let downloadURL = "https://pixeldrain.com/api/file/\(fileId)?download"
                let file = ArchiveFile(name: name, size: sizeStr, elementId: fileId, transferURL: downloadURL, isFolder: false)
                DispatchQueue.main.async { completion([file], nil) }
            }.resume()
            return

        case .archiveOrgProfile:
            // Profile links never reach fetchFiles — ArchiveBrowser resolves
            // them through TransferResolver.fetchArchiveOrgProfileItems
            // first (to build the year/creator/language/subject filter
            // tree) and only calls fetchFiles per-item afterward via
            // .archiveOrgItem. Landing here means something skipped that
            // step; nothing to do but report empty.
            DispatchQueue.main.async { completion([], nil) }
            return

        case .archiveOrgItem(let identifier):
            session?.terminate(); session = nil
            ArchiveOrgResolver.resolveItem(identifier: identifier) { files, errorMessage in
                DispatchQueue.main.async { completion(files, errorMessage) }
            }
            return
        }

        // transfer.it / mega root: start CDP (fetchFileList dispatches by LinkType)
        queue.async { [weak self] in
            guard let self, !self.isCancelled else {
                DispatchQueue.main.async { completion([], nil) }
                return
            }

            let session = CDPSession()
            self.session = session

            do {
                try session.start()
                let sem = DispatchSemaphore(value: 0)
                var files: [ArchiveFile] = []

                session.fetchFileList(transferURL: url) { result in
                    files = result
                    sem.signal()
                }

                sem.wait()
                // keep the session after the root fetch - subfolders reuse it
                DispatchQueue.main.async {
                    completion(files, nil)
                }
            } catch {
                print("❌ TransferResolver.fetchFiles: \(error.localizedDescription)")
                session.terminate()
                self.session = nil
                DispatchQueue.main.async { completion([], nil) }
            }
        }
    }
    
    // Capture requests and CDP callbacks are main-queue-owned. Startup stays
    // on the worker queue; a timed-out startup is retired when it returns.
    private final class CaptureRequest {
        let completion: (String?) -> Void
        let captureID = UUID()
        var reusedSession: CDPSession?
        private let finishedLock = NSLock()
        private var _finished = false
        var finished: Bool {
            get { finishedLock.lock(); defer { finishedLock.unlock() }; return _finished }
            set { finishedLock.lock(); _finished = newValue; finishedLock.unlock() }
        }
        var session: CDPSession?
        var startupComplete = false
        var tunnelHeld = false
        init(completion: @escaping (String?) -> Void) { self.completion = completion }
    }
    private var activeCapture: CaptureRequest?

    private func finishCapture(_ request: CaptureRequest, url: String?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !request.finished else { return }
        request.finished = true
        request.reusedSession?.cancelCapture(request.captureID)
        request.reusedSession = nil
        if activeCapture === request { activeCapture = nil }
        if request.startupComplete, let owned = request.session {
            owned.retireCaptureTransport()
            if session === owned { session = nil }
            request.session = nil
        }
        if request.tunnelHeld {
            request.tunnelHeld = false
            TunnelForBlockedHosts.shared.endResolution()
        }
        request.completion(url)
    }

    private static func isArchiveDownload(_ value: String) -> Bool {
        guard let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              parts.host?.lowercased() == "archive.org",
              parts.user == nil, parts.password == nil else { return false }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        return path.count >= 4 && path[0].isEmpty && path[1] == "download"
            && !path[2].isEmpty && path[3...].allSatisfy { !$0.isEmpty }
    }

    func captureURL(transferURL: String,
                    elementId: String,
                    completion: @escaping (String?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let previous = activeCapture { finishCapture(previous, url: nil) }
        let request = CaptureRequest(completion: completion)
        activeCapture = request
        let completion: (String?) -> Void = { [weak self, request] url in
            DispatchQueue.main.async { TransferTicketContext.remember(url:url,shareURL:transferURL,node:elementId); self?.finishCapture(request,url:url) }
        }
        // Includes Chromium's nominal 10s startup and the longest CDP
        // capture timeout (Gofile: 25s), plus scheduling margin.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15 + max(25, ArchiveConfig.urlCaptureTimeout)) { [weak self, request] in
            self?.finishCapture(request, url: nil)
        }
        Diag.log("🚨 [DEBUG] captureURL ENTERED transferURL=\(transferURL) elementId=\(elementId) thread=\(Thread.isMainThread ? "main" : "background")")
        isCancelled = false

        // archive.org file URL - already the direct playable link; checked
        // first so a leftover transfer.it/mega session never touches it
        if Self.isArchiveDownload(transferURL) {
            DispatchQueue.main.async { completion(transferURL) }
            return
        }

        // mega: the megajs relay resolves the share, node keys and CDN URL
        // from the link itself — no CDP capture, no "g" XHR, no session.
        if let megaType = CDPSession.classifyURL(transferURL) {
            switch megaType {
            case .mega, .megaFolder, .megaFile:
                DispatchQueue.main.async { completion(transferURL) }
                return
            default: break
            }
        }

        // reuse the current session for transfer.it / mega (M.d already loaded)
        if let existingSession = self.session,
           let linkType = CDPSession.classifyURL(transferURL) {
            switch linkType {
            case .transferIt, .transferItFolder:
                request.reusedSession = existingSession
                existingSession.captureSignedURL(transferURL: transferURL, elementId: elementId,
                                                 captureID: request.captureID, completion: completion)
                return
            case .gofile, .gofileDirect:
                // 260930.1: keep the listing's account/cookie jar across the
                // video and every companion. Fresh Chromium profiles create
                // different guest accounts and their URLs cannot share headers.
                request.reusedSession = existingSession
                existingSession.captureSignedURL(transferURL: transferURL, elementId: elementId,
                                                 captureID: request.captureID, completion: completion)
                return
            case .mega, .megaFolder:
                // Mega.nz — reuse existing session, same reasoning as transfer.it:
                // M.d is already loaded in the browser's memory from fetchFiles.
                request.reusedSession = existingSession
                existingSession.captureSignedURL(transferURL: transferURL, elementId: elementId,
                                                 captureID: request.captureID, completion: completion)
                return
            default: break
            }
        }
        // fresh session for everything else
        Diag.log("🚨 [DEBUG] before session?.retireCaptureTransport() — session is \(session == nil ? "nil" : "non-nil")")
        session?.retireCaptureTransport()
        session = nil
        Diag.log("🚨 [DEBUG] after session terminate/nil")
        
        if transferURL.contains("uc?export=download") && !transferURL.contains("drive.usercontent.google.com") {
            print("🔗 Drive direct download: \(transferURL)")
            DispatchQueue.main.async { completion(transferURL) }
            return
        }
        
        guard let linkType = CDPSession.classifyURL(transferURL) else {
            Diag.log("🚨 [DEBUG] classifyURL returned nil for \(transferURL)")
            DispatchQueue.main.async { completion(nil) }
            return
        }
        Diag.log("🚨 [DEBUG] classifyURL resolved to: \(linkType)")
        
        switch linkType {
        case .gofileDirect(let signed):
            let parts = signed.components(separatedBy: "::")
            let token = parts.count > 2 ? parts[1] : ""
            let cdnURL = parts.count > 2 ? parts[2...].joined(separator: "::") : (parts.count > 1 ? parts[1] : "")
            if cdnURL.isEmpty {
                DispatchQueue.main.async { completion(nil) }
            } else if token.isEmpty {
                DispatchQueue.main.async { completion(cdnURL) }
            } else {
                let cookieStr = "accountToken=\(token)"
                DispatchQueue.main.async { completion("\(cdnURL)|gofile-token=\(token)|cookie=\(cookieStr)") }
            }
            return
            
        case .gofile:
            Diag.log("🚨 [DEBUG] .gofile case — break, falling through to queue.async")
            break

        case .gofileFolder:
            // folders are not downloadable - a folder tap should re-run
            // fetchFiles, so landing here means a UI mistake; return nil
            Diag.log("🚨 [DEBUG] .gofileFolder — not downloadable, returning nil")
            DispatchQueue.main.async { completion(nil) }
            return
            
        case .googleDriveFile:
            break
            
        case .googleDriveFolder:
            let downloadURL = "\(ArchiveConfig.driveDownloadTemplate)\(elementId)"
            print("🔗 Drive download: \(downloadURL)")
            DispatchQueue.main.async { completion(downloadURL) }
            return
            
        case .transferItFolder:
            if let existingSession = self.session {
                request.reusedSession = existingSession
                existingSession.captureSignedURL(transferURL: transferURL, elementId: elementId,
                                                 captureID: request.captureID, completion: completion)
            } else {
                completion(nil)
            }
            return
            
        case .transferIt:
            break

        case .megaFolder:
            if let existingSession = self.session {
                request.reusedSession = existingSession
                existingSession.captureSignedURL(transferURL: transferURL, elementId: elementId,
                                                 captureID: request.captureID, completion: completion)
            } else {
                completion(nil)
            }
            return

        case .mega:
            break
            
        case .megaFile:
            // unreachable — short-circuited above; keeps the switch exhaustive
            DispatchQueue.main.async { completion(transferURL) }
            return

        case .pixeldrain:
            // Pixeldrain download URL is already direct — no capture needed
            DispatchQueue.main.async { completion(transferURL) }
            return

        case .archiveOrgProfile, .archiveOrgItem:
            // Leaf files never reach captureURL as one of these — the direct-file
            // shortcut above catches them first. A bare profile/item URL landing
            // here means selectFile was called on something that should have
            // gone through fetchFiles instead; nothing to capture.
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let owned = CDPSession()
        request.session = owned
        let needsWARP = TunnelForBlockedHosts.shared.needsTunnel(transferURL)
        if needsWARP {
            guard TunnelForBlockedHosts.shared.beginResolution(for: transferURL) else {
                finishCapture(request, url: nil)
                return
            }
            request.tunnelHeld = true
        }
        queue.async { [weak self, request, owned] in
            guard !request.finished else { return }
            let transport: URL?
            do { transport = try owned.prepareCaptureTransport() }
            catch { transport = nil }
            DispatchQueue.main.async {
                request.startupComplete = true
                guard let self, !request.finished, let transport else {
                    owned.retireCaptureTransport()
                    request.session = nil
                    if let self { self.finishCapture(request, url: nil) }
                    return
                }
                owned.activateCaptureTransport(transport)
                self.session = owned
                owned.captureSignedURL(transferURL: transferURL, elementId: elementId,
                                       captureID: request.captureID, completion: completion)
            }
        }
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        isCancelled = true
        if let request = activeCapture { finishCapture(request, url: nil) }
        // Listing-session cleanup is separate from fresh capture completion.
        let cancelledSession = session
        session = nil
        // Do not put cancellation behind the listing worker's legacy waits.
        cancelledSession?.retireCaptureTransport()
    }

    // archive.org profile link entry point - a profile expands to a
    // filterable item list, not a flat file list, and uses no CDP session.
    // Goes through ArchiveOrgCatalogue: completion fires with whatever is
    // catalogued, the background worker backfills, onUpdated grows the
    // screen live.
    func fetchArchiveOrgProfileItems(username: String, onUpdated: @escaping ([ArchiveOrgItem]) -> Void, completion: @escaping ([ArchiveOrgItem], String?) -> Void) {
        if ArchiveOrgCatalogue.shared.hasAnyData(for: username) {
            // known profile: cached items at once, worker backfills.
            // forceIdentifierRefresh re-checks the identifier list on every
            // open so items added since the first fetch appear; it only
            // ever adds, never replaces.
            completion(ArchiveOrgCatalogue.shared.currentItems(for: username), nil)
            ArchiveOrgCatalogue.shared.ensureFetching(username: username, forceIdentifierRefresh: true) { items, _ in
                onUpdated(items)
            }
        } else {
            // First-ever open: completion resolves only on a tick with
            // real items or the worker's authoritative `finished` tick -
            // an early empty tick just means "hasn't arrived yet" and must
            // not be reported as "no items found".
            var completedOnce = false
            ArchiveOrgCatalogue.shared.ensureFetching(username: username) { items, finished in
                guard !completedOnce else {
                    onUpdated(items)
                    return
                }
                guard !items.isEmpty || finished else { return }
                completedOnce = true
                completion(items, items.isEmpty ? "no items found for @\(username)" : nil)
            }
        }
    }

    // Refresh button: returns the catalogue immediately, then
    // ensureFetching picks up identifiers added since the last check.
    func forceRefreshArchiveOrgProfile(username: String, completion: @escaping ([ArchiveOrgItem], String?) -> Void) {
        completion(ArchiveOrgCatalogue.shared.currentItems(for: username), nil)
        // a manual refresh checks for identifiers added since the last
        // check, not the frozen list
        ArchiveOrgCatalogue.shared.ensureFetching(username: username, forceIdentifierRefresh: true) { items, _ in
            completion(items, nil)
        }
    }

    // curated "Lists" link entry point - mirrors
    // fetchArchiveOrgProfileItems against a list's members; the compound
    // catalogue key (see keyForList) keeps lists and uploads independent.
    func fetchArchiveOrgListItems(username: String, listID: Int, onUpdated: @escaping ([ArchiveOrgItem]) -> Void, completion: @escaping ([ArchiveOrgItem], String?) -> Void) {
        let key = ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
        if ArchiveOrgCatalogue.shared.hasAnyData(for: key) {
            // same contract as fetchArchiveOrgProfileItems: re-check the
            // member list on every open, merge in additions
            completion(ArchiveOrgCatalogue.shared.currentItems(for: key), nil)
            ArchiveOrgCatalogue.shared.ensureFetchingList(username: username, listID: listID, forceIdentifierRefresh: true) { items, _ in
                onUpdated(items)
            }
        } else {
            // same contract as fetchArchiveOrgProfileItems: resolve only
            // on a real-items tick or the `finished` tick, never on an
            // early empty one.
            var completedOnce = false
            ArchiveOrgCatalogue.shared.ensureFetchingList(username: username, listID: listID) { items, finished in
                guard !completedOnce else {
                    onUpdated(items)
                    return
                }
                guard !items.isEmpty || finished else { return }
                completedOnce = true
                completion(items, items.isEmpty ? "no items found in this list" : nil)
            }
        }
    }

    // Lists refresh button - same contract as forceRefreshArchiveOrgProfile.
    func forceRefreshArchiveOrgList(username: String, listID: Int, completion: @escaping ([ArchiveOrgItem], String?) -> Void) {
        let key = ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
        completion(ArchiveOrgCatalogue.shared.currentItems(for: key), nil)
        // a manual refresh finds members added since the last check
        ArchiveOrgCatalogue.shared.ensureFetchingList(username: username, listID: listID, forceIdentifierRefresh: true) { items, _ in
            completion(items, nil)
        }
    }

    // id-less "all lists" row entry point - fetchAllLists returns every
    // list's members in one request, so no worker; each list's
    // identifiers are seeded into its own catalogue entry. Returns
    // id/name/count summaries for ArchiveBrowser's picker.
    func fetchArchiveOrgAllLists(username: String, completion: @escaping ([(id: Int, name: String, count: Int)]?, String?) -> Void) {
        ArchiveOrgResolver.fetchAllLists(username: username) { lists, errorMessage in
            guard let lists else {
                completion(nil, errorMessage)
                return
            }
            for list in lists {
                ArchiveOrgCatalogue.shared.seedListIdentifiers(username: username, listID: list.id, name: list.name, identifiers: list.identifiers)
            }
            completion(lists.map { (id: $0.id, name: $0.name, count: $0.identifiers.count) }, nil)
            // Backfill every list's facets one at a time, chained:
            // concurrent workers would multiply the load against
            // archive.org that the gentle pacing exists to avoid (see
            // interRequestDelay). Silent and best-effort; screens redraw
            // live via their own listeners.
            Self.backfillAllListsSequentially(username: username, listIDs: lists.map { $0.id })
        }
    }

    // ensureFetchingList per id in turn, advancing on `finished`; an
    // in-flight worker keeps its own listeners (they append), so the
    // chain never steals or duplicates progress.
    private static func backfillAllListsSequentially(username: String, listIDs: [Int], index: Int = 0) {
        guard index < listIDs.count else { return }
        let listID = listIDs[index]
        ArchiveOrgCatalogue.shared.ensureFetchingList(username: username, listID: listID) { _, finished in
            guard finished else { return }
            backfillAllListsSequentially(username: username, listIDs: listIDs, index: index + 1)
        }
    }
}

// ================================================================
//  ArchiveOrgCatalogue - append-only on-disk record of every
//  identifier, facet and file list ever learned per profile/list
// ================================================================

final class ArchiveOrgCatalogue {
    static let shared = ArchiveOrgCatalogue()
    private init() {}

    // WHY: off by default - uncapped per-item failure logging produced
    // hundreds of near-identical lines per run. log() below keeps only
    // worker start/finish and periodic progress summaries.
    static var verboseLogging = false

    private static func log(_ message: @autoclosure () -> String) {
        guard verboseLogging else { return }
        print("[catalogue] \(message())")
    }

    // MARK: - On-disk record

    // Which endpoint supplies the identifier list (Step 1 of runWorker);
    // everything downstream is identical for both. A profile keys on the
    // bare username; a list uses the compound keyForList.
    private enum CatalogueSource {
        case profile(username: String)
        case list(username: String, listID: Int)
    }

    // Compound catalogue key for a curated list, kept out of the
    // username namespace so a profile and its lists never share a file.
    // Internal (not private) so TransferResolver's list entry points use
    // this same derivation.
    static func keyForList(username: String, listID: Int) -> String {
        "list:\(username):\(listID)"
    }

    // Everything ever learned about one item; `files` is nil until the
    // item is opened once (resolved lazily, then persisted).
    struct Entry: Codable {
        var title: String
        var year: String?
        var creator: String?
        var language: String?
        var subject: String?
        var files: [FileEntry]?
        var filesVersion: Int? = nil

        // WHY: Codable mirror of ArchiveFile - making ArchiveFile itself
        // Codable would risk its ~10 construction sites for a need only
        // this cache has.
        struct FileEntry: Codable {
            let name: String
            let size: String
            let transferURL: String
            var isFolder: Bool? = nil
            var stableElementId: String? = nil

            init(_ file: ArchiveFile) {
                name = file.name
                size = file.size
                transferURL = file.transferURL
                isFolder = file.isFolder
                stableElementId = file.elementId
            }

            func toArchiveFile(elementId: String) -> ArchiveFile {
                ArchiveFile(name: name, size: size, elementId: stableElementId ?? elementId, transferURL: transferURL, isFolder: isFolder ?? false)
            }
        }
    }

    // One profile's whole catalogue. `identifierOrder` preserves
    // discovery order (publicdate:desc) since dictionary iteration is
    // unordered and the film list must stay stable across loads.
    struct ProfileCatalogue: Codable {
        var identifierOrder: [String] = []
        var entries: [String: Entry] = [:]
        // set once the full identifier list has been fetched - nil means
        // "fetch the list first", non-nil means "only fill missing entries"
        var knownIdentifierCount: Int?
        // WHY: Optional so catalogue files predating this field decode
        // as nil/"not done" (Codable only defaults Optionals for missing
        // keys). Gates the one-time year repair (runWorker Step 1.5).
        var yearRepairDone: Bool?
        // a list's own display name, nil for an uploads catalogue;
        // Optional so pre-field files decode cleanly
        var displayName: String?
    }

    // MARK: - Disk I/O

    private static var catalogueDir: URL? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appDir = dir.appendingPathComponent("gor", isDirectory: true).appendingPathComponent("archive_org_catalogues", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }()

    private static func catalogueURL(for username: String) -> URL? {
        guard let dir = catalogueDir else { return nil }
        let unsafe = CharacterSet(charactersIn: "/\\:")
        let safeName = username.components(separatedBy: unsafe).joined(separator: "_")
        let fallback = safeName.isEmpty ? String(username.hashValue) : safeName
        return dir.appendingPathComponent("\(fallback).json")
    }

    // session-scoped in-memory copies; every change still writes
    // straight to disk so a quit mid-fetch loses nothing
    private var loaded: [String: ProfileCatalogue] = [:]
    private let stateLock = NSLock()

    private func readFromDisk(_ username: String) -> ProfileCatalogue? {
        guard let url = Self.catalogueURL(for: username),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ProfileCatalogue.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func writeToDisk(_ username: String, _ catalogue: ProfileCatalogue) {
        guard let url = Self.catalogueURL(for: username),
              let data = try? JSONEncoder().encode(catalogue) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func catalogue(for username: String) -> ProfileCatalogue {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let existing = loaded[username] { return existing }
        let fromDisk = readFromDisk(username) ?? ProfileCatalogue()
        loaded[username] = fromDisk
        return fromDisk
    }

    // every mutation: read-modify-write under stateLock, then persist
    // immediately per item, so an interrupted fetch keeps what it got
    private func mutate(_ username: String, _ change: (inout ProfileCatalogue) -> Void) {
        stateLock.lock()
        let current = mutateLocked(username, change)
        stateLock.unlock()
        writeToDisk(username, current)
    }

    // mutate for callers already holding stateLock (NSLock is not
    // reentrant); skips locking, caller persists via the returned value
    @discardableResult
    private func mutateLocked(_ username: String, _ change: (inout ProfileCatalogue) -> Void) -> ProfileCatalogue {
        var current = loaded[username] ?? readFromDisk(username) ?? ProfileCatalogue()
        change(&current)
        loaded[username] = current
        return current
    }

    // MARK: - Reading (what ArchiveBrowser calls)

    // known items in discovery order, always instant, never network;
    // call ensureFetching alongside to backfill what's missing
    func currentItems(for username: String) -> [ArchiveOrgItem] {
        let cat = catalogue(for: username)
        return cat.identifierOrder.compactMap { identifier in
            guard let entry = cat.entries[identifier] else { return nil }
            return ArchiveOrgItem(identifier: identifier, title: entry.title, year: entry.year, creator: entry.creator, language: entry.language, subject: entry.subject)
        }
    }

    // distinguishes "brand new, show a loading state" from "known,
    // display the cache immediately"
    func hasAnyData(for username: String) -> Bool {
        !catalogue(for: username).entries.isEmpty
    }

    // a list's own name if known; ArchiveBrowser's title bar uses it to
    // tell a user's lists apart
    func displayName(for key: String) -> String? {
        catalogue(for: key).displayName
    }

    // seeds a list's identifiers + name from fetchAllLists' single
    // response, only when unknown (knownIdentifierCount == nil) - an
    // already-opened list keeps its richer record
    func seedListIdentifiers(username: String, listID: Int, name: String, identifiers: [String]) {
        let key = Self.keyForList(username: username, listID: listID)
        guard catalogue(for: key).knownIdentifierCount == nil else { return }
        mutate(key) { cat in
            for id in identifiers where !cat.identifierOrder.contains(id) {
                cat.identifierOrder.append(id)
            }
            cat.knownIdentifierCount = identifiers.count
            cat.displayName = name
        }
    }

    // (have, total) so ArchiveBrowser can show "812 of 1105 catalogued"
    func progress(for username: String) -> (have: Int, total: Int?) {
        let cat = catalogue(for: username)
        return (cat.entries.count, cat.knownIdentifierCount)
    }

    // cached file list; nil means never opened, needs a live fetch
    func cachedFiles(identifier: String, username: String) -> [ArchiveFile]? {
        guard let entry = catalogue(for: username).entries[identifier], entry.filesVersion == 2 else { return nil }
        return entry.files?.map { $0.toArchiveFile(elementId: identifier) }
    }

    // fetches and permanently caches one item's file list; once written,
    // that identifier's /metadata endpoint is never hit again
    func resolveFiles(identifier: String, username: String, completion: @escaping ([ArchiveFile], String?) -> Void) {
        if let cached = cachedFiles(identifier: identifier, username: username) {
            completion(cached, nil)
            return
        }
        ArchiveOrgResolver.resolveItem(identifier: identifier) { [weak self] files, error in
            guard let self else { return }
            if !files.isEmpty {
                self.mutate(username) { cat in
                    var entry = cat.entries[identifier] ?? Entry(title: identifier, year: nil, creator: nil, language: nil, subject: nil, files: nil)
                    entry.files = files.map { Entry.FileEntry($0) }
                    entry.filesVersion = 2
                    cat.entries[identifier] = entry
                    if !cat.identifierOrder.contains(identifier) { cat.identifierOrder.append(identifier) }
                }
            }
            completion(files, error)
        }
    }

    // MARK: - Background fetch worker

    // one worker per key - a refresh during a backfill joins the running
    // worker instead of competing with it
    private var activeWorkers: Set<String> = []
    // WHY: listeners are a list (every ensureFetching call registers its
    // own) and carry a `finished` flag true only on the worker's last
    // notification - an empty mid-run tick means "not arrived yet", and
    // only finished+empty may be reported as "no items found".
    private var progressListeners: [String: [([ArchiveOrgItem], Bool) -> Void]] = [:]
    // WHY: strictly one request at a time with a real pause - concurrent
    // /metadata requests got this machine's IP connection-refused by
    // archive.org. A slow fill that completes beats a fast blocked one.
    private static let interRequestDelay: TimeInterval = 0.6

    // call on profile open or refresh; safe while a worker runs (the
    // listener appends). onProgress fires on main per newly-learned item.
    func ensureFetching(username: String, forceIdentifierRefresh: Bool = false, onProgress: @escaping ([ArchiveOrgItem], Bool) -> Void) {
        startWorkerIfNeeded(key: username, source: .profile(username: username), forceIdentifierRefresh: forceIdentifierRefresh, onProgress: onProgress)
    }

    // ensureFetching for a curated list; separate name so the call site
    // states plainly which endpoint kind is meant
    func ensureFetchingList(username: String, listID: Int, forceIdentifierRefresh: Bool = false, onProgress: @escaping ([ArchiveOrgItem], Bool) -> Void) {
        let key = Self.keyForList(username: username, listID: listID)
        startWorkerIfNeeded(key: key, source: .list(username: username, listID: listID), forceIdentifierRefresh: forceIdentifierRefresh, onProgress: onProgress)
    }

    private func startWorkerIfNeeded(key: String, source: CatalogueSource, forceIdentifierRefresh: Bool = false, onProgress: @escaping ([ArchiveOrgItem], Bool) -> Void) {
        stateLock.lock()
        progressListeners[key, default: []].append(onProgress)
        let alreadyRunning = activeWorkers.contains(key)
        if !alreadyRunning { activeWorkers.insert(key) }
        // WHY: forceIdentifierRefresh clears knownIdentifierCount under
        // stateLock so Step 1 re-fetches and merges the identifier list
        // (Step 1 only ever appends) - a set count is correct for the
        // silent worker but wrong for an explicit "check for new items".
        var catalogueAfterClear: ProfileCatalogue?
        if forceIdentifierRefresh {
            catalogueAfterClear = mutateLocked(key) { cat in cat.knownIdentifierCount = nil }
        }
        stateLock.unlock()
        if let catalogueAfterClear { writeToDisk(key, catalogueAfterClear) }
        guard !alreadyRunning else { return }

        Self.log("worker started for \(key)")
        let workerQueue = DispatchQueue(label: "archive.org.catalogue.\(key)")
        workerQueue.async { [weak self] in
            self?.runWorker(key: key, source: source)
        }
    }

    // notifies every listener for the key on main. `finished` is true
    // only for the worker's very last notification, fired after the
    // listener list is cleared (via progressListenersPendingFinish).
    private func notifyProgress(key: String, finished: Bool = false) {
        stateLock.lock()
        let listeners = finished ? (progressListenersPendingFinish[key] ?? []) : (progressListeners[key] ?? [])
        if finished { progressListenersPendingFinish[key] = nil }
        stateLock.unlock()
        guard !listeners.isEmpty else { return }
        let items = currentItems(for: key)
        DispatchQueue.main.async {
            listeners.forEach { $0(items, finished) }
        }
    }
    // listener snapshot taken before runWorker's defer clears the list,
    // so the final finished notification still reaches them
    private var progressListenersPendingFinish: [String: [([ArchiveOrgItem], Bool) -> Void]] = [:]

    private func runWorker(key: String, source: CatalogueSource) {
        defer {
            stateLock.lock()
            activeWorkers.remove(key)
            // listeners clear at finish; screens re-register on their
            // next ensureFetching. Snapshotted first so the finished
            // notification still reaches them.
            progressListenersPendingFinish[key] = progressListeners[key] ?? []
            progressListeners[key] = nil
            stateLock.unlock()
            Self.log("worker finished for \(key)")
            // the ONLY notification callers may treat as authoritative
            // for "truly nothing here"; every mid-run tick fires with
            // finished: false
            notifyProgress(key: key, finished: true)
        }
        // WHY: guarantees at least one notification on every path - an
        // early return with no callback would leave a first-open screen
        // stuck on "opening..." forever.
        defer { notifyProgress(key: key) }

        // Step 1: the full identifier list, fetched once per catalogue
        // (cheap; not the endpoint that needed the gentle pacing).
        let knownCount = catalogue(for: key).knownIdentifierCount
        let identifiers: [String]
        if knownCount != nil {
            identifiers = catalogue(for: key).identifierOrder
        } else {
            let sem = DispatchSemaphore(value: 0)
            var fetched: [String] = []
            var fetchedDisplayName: String? = nil
            switch source {
            case .profile(let username):
                ArchiveOrgResolver.fetchUploaderIdentifiersPublic(username: username) { ids, _ in
                    fetched = ids ?? []
                    sem.signal()
                }
            case .list(let username, let listID):
                ArchiveOrgResolver.fetchListMembers(username: username, listID: listID) { ids, listName, _ in
                    fetched = ids ?? []
                    fetchedDisplayName = listName
                    sem.signal()
                }
            }
            sem.wait()
            guard !fetched.isEmpty else { return }
            // WHY: merge `fetched` into identifierOrder (append-only) and
            // read back the merged list + count - a force-refresh must
            // never replace what is already tracked.
            mutate(key) { cat in
                for id in fetched where !cat.identifierOrder.contains(id) {
                    cat.identifierOrder.append(id)
                }
                cat.knownIdentifierCount = cat.identifierOrder.count
                if let fetchedDisplayName { cat.displayName = fetchedDisplayName }
            }
            identifiers = catalogue(for: key).identifierOrder
        }

        // Step 1.5: one-time repair (yearRepairDone) re-deriving year from
        // `date` for entries catalogued before year was read correctly;
        // everything else already known stays untouched.
        if catalogue(for: key).yearRepairDone != true {
            let toRepair = identifiers.filter { catalogue(for: key).entries[$0] != nil }
            if !toRepair.isEmpty {
                Self.log("worker: one-time year repair for \(toRepair.count) already-catalogued identifiers for \(key)")
                for identifier in toRepair {
                    let sem = DispatchSemaphore(value: 0)
                    ArchiveOrgResolver.fetchOneItemFacet(identifier: identifier) { [weak self] freshEntry in
                        guard let self else { sem.signal(); return }
                        if let year = freshEntry?.year {
                            self.mutate(key) { cat in
                                cat.entries[identifier]?.year = year
                            }
                        }
                        sem.signal()
                    }
                    sem.wait()
                    Thread.sleep(forTimeInterval: Self.interRequestDelay)
                }
            }
            mutate(key) { cat in cat.yearRepairDone = true }
            notifyProgress(key: key)
        }

        // Step 2: facets for identifiers without any - already-catalogued
        // ones are skipped (append-only, never re-fetch).
        let missing = identifiers.filter { catalogue(for: key).entries[$0] == nil }
        // WHY: cached facets can still lack file links; an empty facet
        // pass must continue to the independent file backfill below.
        Self.log("worker: \(missing.count) of \(identifiers.count) identifiers need facets for \(key)")

        var completedThisRun = 0
        for identifier in missing {
            let sem = DispatchSemaphore(value: 0)
            ArchiveOrgResolver.fetchOneItemFacet(identifier: identifier) { [weak self] entry in
                guard let self else { sem.signal(); return }
                if let entry {
                    self.mutate(key) { cat in
                        cat.entries[identifier] = entry
                        if !cat.identifierOrder.contains(identifier) { cat.identifierOrder.append(identifier) }
                    }
                    completedThisRun += 1
                    if completedThisRun % 25 == 0 {
                        Self.log("worker: \(key) progress \(completedThisRun)/\(missing.count) this run")
                    }
                    self.notifyProgress(key: key)
                }
                sem.signal()
            }
            sem.wait()
            Thread.sleep(forTimeInterval: Self.interRequestDelay)
        }

        // Step 3: file links for identifiers without them, same gentle
        // pace - once done, opening a film needs no network request.
        let missingFiles = identifiers.filter { catalogue(for: key).entries[$0]?.files == nil }
        guard !missingFiles.isEmpty else { return }
        Self.log("worker: \(missingFiles.count) of \(identifiers.count) identifiers need files for \(key)")

        var filesCompletedThisRun = 0
        for identifier in missingFiles {
            let sem = DispatchSemaphore(value: 0)
            ArchiveOrgResolver.resolveItem(identifier: identifier) { [weak self] files, _ in
                guard let self else { sem.signal(); return }
                if !files.isEmpty {
                    self.mutate(key) { cat in
                        var entry = cat.entries[identifier] ?? Entry(title: identifier, year: nil, creator: nil, language: nil, subject: nil, files: nil)
                        entry.files = files.map { Entry.FileEntry($0) }
                        cat.entries[identifier] = entry
                        if !cat.identifierOrder.contains(identifier) { cat.identifierOrder.append(identifier) }
                    }
                    filesCompletedThisRun += 1
                    if filesCompletedThisRun % 25 == 0 {
                        Self.log("worker: \(key) files progress \(filesCompletedThisRun)/\(missingFiles.count) this run")
                    }
                }
                sem.signal()
            }
            sem.wait()
            Thread.sleep(forTimeInterval: Self.interRequestDelay)
        }
    }
}

// ================================================================
//  ArchiveOrgResolver - plain HTTPS + JSON fetches against
//  archive.org (no CDP); callbacks arrive on URLSession's queue
// ================================================================

enum ArchiveOrgResolver {
    // verbose fetch logging (URLs, sizes, capped samples); single flag
    // so it is one line to silence again
    static var verboseLogging = true

    // caps per-line log dumps so a 1105-item profile doesn't flood the console
    private static let logSampleLimit = 200

    private static func log(_ message: @autoclosure () -> String) {
        guard verboseLogging else { return }
        print("[archive.org] \(message())")
    }

    // generous: a slow response must surface as a result, not a false
    // "no files found"
    private static let requestTimeout: TimeInterval = 25

    // WHY: .urlPathAllowed leaves "()" and "&" unescaped but archive.org's
    // own links encode them - alphanumerics plus safe punctuation only.
    private static let filenamePathAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~/")
        return set
    }()

    private static func makeRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: requestTimeout)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        // WHY: without Accept: application/json the lists endpoint
        // returns a differently-shaped body that fails to parse; matching
        // real browser behavior on every request is harmless.
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    // single-item facet fetch for the catalogue worker. nil means
    // genuine failure (leave uncached, retry later), distinct from a
    // valid Entry whose facets are all nil.
    static func fetchOneItemFacet(identifier: String, completion: @escaping (ArchiveOrgCatalogue.Entry?) -> Void) {
        guard let url = URL(string: "https://archive.org/metadata/\(identifier)") else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: makeRequest(url)) { data, _, error in
            if let error {
                log("catalogue facet: /metadata/\(identifier) failed — \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let metadata = json["metadata"] as? [String: Any] else {
                log("catalogue facet: /metadata/\(identifier) returned unparseable data (\(data?.count ?? 0) bytes)")
                completion(nil)
                return
            }
            let title = (metadata["title"] as? String)?.trimmingCharacters(in: .whitespaces)
            completion(ArchiveOrgCatalogue.Entry(
                title: (title?.isEmpty == false ? title : nil) ?? identifier,
                // WHY: /metadata has no "year" key; the "date" field
                // (bare year or ISO timestamp) is what the search index's
                // Year facet derives from.
                year: yearFromDateField(metadata["date"]),
                creator: firstFacetValue(metadata["creator"]),
                language: firstFacetValue(metadata["language"]),
                subject: firstFacetValue(metadata["subject"]),
                files: nil
            ))
        }.resume()
    }

    // 4-digit year from the "date" field's leading digits, either shape
    private static func yearFromDateField(_ raw: Any?) -> String? {
        guard let dateValue = firstFacetValue(raw) else { return nil }
        let leadingDigits = dateValue.prefix(while: { $0.isNumber })
        return leadingDigits.count == 4 ? String(leadingDigits) : nil
    }


    // facet fields arrive as string, array, number, or missing;
    // normalize to first value or nil, converting non-strings rather
    // than dropping them
    private static func firstFacetValue(_ raw: Any?) -> String? {
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let arr = raw as? [Any] {
            for element in arr {
                if let v = firstFacetValue(element) { return v }
            }
            return nil
        }
        if let n = raw as? NSNumber {
            return n.stringValue
        }
        return nil
    }

    // WHY: this is the exact request archive.org's own /details/@user
    // page makes (page_production), verified against the real response
    // shape; the documented alternatives return wrong or empty data.
    // Identifiers at .uploads.hits.hits[].fields.identifier, count at
    // .uploads.hits.total. No uid/cookies needed.
    private static let maxProfilePages = 50
    private static let profilePageSize = 100

    // identifier pagination for the catalogue worker
    static func fetchUploaderIdentifiersPublic(username: String, completion: @escaping ([String]?, String?) -> Void) {
        fetchUploaderIdentifiers(username: username, completion: completion)
    }

    // members of one curated list. GET /services/users/@<user>/lists/<id>
    // returns {"success", "value": [{list_name, id, members:
    // [{identifier...]}]} for EVERY list - the match is picked by id, the
    // path does not filter server-side. Public lists need no login.
    // Returns identifiers + list_name (the title bar needs it).
    // every list at once (id-less path): "value" is the array of all
    // lists, each with id/list_name/members; ArchiveBrowser's picker uses
    // the summaries without a second round trip.
    static func fetchAllLists(username: String, completion: @escaping ([(id: Int, name: String, identifiers: [String])]?, String?) -> Void) {
        guard let url = URL(string: "https://archive.org/services/users/@\(username)/lists") else {
            completion(nil, "bad lists URL for @\(username)")
            return
        }
        log("lists: fetching @\(username)/lists — \(url.absoluteString)")
        URLSession.shared.dataTask(with: makeRequest(url)) { data, _, error in
            if let error {
                log("lists: @\(username)/lists network error — \(error.localizedDescription)")
                completion(nil, "archive.org lists lookup failed: \(error.localizedDescription)")
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["success"] as? Bool == true else {
                let rawBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<non-UTF8 data>"
                log("lists: @\(username)/lists returned unparseable/unsuccessful data (\(data?.count ?? 0) bytes): \(rawBody)")
                completion(nil, "archive.org lists lookup returned bad data for @\(username)")
                return
            }
            // same dual-shape tolerance as fetchListMembers (see below)
            let lists: [[String: Any]]
            if let asArray = json["value"] as? [[String: Any]] {
                lists = asArray
            } else if let asObject = json["value"] as? [String: Any] {
                lists = [asObject]
            } else {
                log("lists: @\(username)/lists — \"value\" was neither an array nor an object")
                completion(nil, "archive.org lists lookup returned an unexpected shape for @\(username)")
                return
            }
            let results: [(id: Int, name: String, identifiers: [String])] = lists.compactMap { list in
                guard let id = list["id"] as? Int else { return nil }
                let name = (list["list_name"] as? String)?.trimmingCharacters(in: .whitespaces)
                let members = list["members"] as? [[String: Any]] ?? []
                let identifiers = members.compactMap { $0["identifier"] as? String }
                return (id: id, name: (name?.isEmpty == false ? name! : "list \(id)"), identifiers: identifiers)
            }
            log("lists: @\(username)/lists — \(results.count) list(s): \(results.map { "\($0.name) (\($0.identifiers.count))" }.joined(separator: ", "))")
            guard !results.isEmpty else {
                completion([], nil)
                return
            }
            completion(results, nil)
        }.resume()
    }

    static func fetchListMembers(username: String, listID: Int, completion: @escaping ([String]?, String?, String?) -> Void) {
        guard let url = URL(string: "https://archive.org/services/users/@\(username)/lists/\(listID)") else {
            completion(nil, nil, "bad list URL for @\(username)/lists/\(listID)")
            return
        }
        log("list: fetching @\(username)/lists/\(listID) — \(url.absoluteString)")
        URLSession.shared.dataTask(with: makeRequest(url)) { data, _, error in
            if let error {
                log("list: @\(username)/lists/\(listID) network error — \(error.localizedDescription)")
                completion(nil, nil, "archive.org list lookup failed: \(error.localizedDescription)")
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["success"] as? Bool == true else {
                let rawBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<non-UTF8 data>"
                log("list: @\(username)/lists/\(listID) returned unparseable/unsuccessful data (\(data?.count ?? 0) bytes): \(rawBody)")
                completion(nil, nil, "archive.org list lookup returned bad data for @\(username)/lists/\(listID)")
                return
            }
            // WHY: "value" is a bare object when an id is in the path,
            // an array otherwise - accept both; the shape is not
            // predictable from the request alone.
            let lists: [[String: Any]]
            if let asArray = json["value"] as? [[String: Any]] {
                lists = asArray
            } else if let asObject = json["value"] as? [String: Any] {
                lists = [asObject]
            } else {
                log("list: @\(username)/lists/\(listID) — \"value\" was neither an array nor an object")
                completion(nil, nil, "archive.org list lookup returned an unexpected shape for @\(username)/lists/\(listID)")
                return
            }
            guard let matchingList = lists.first(where: { ($0["id"] as? Int) == listID }) else {
                completion(nil, nil, "list \(listID) not found for @\(username) (private, deleted, or wrong id)")
                return
            }
            let members = matchingList["members"] as? [[String: Any]] ?? []
            let identifiers = members.compactMap { $0["identifier"] as? String }
            let listName = (matchingList["list_name"] as? String)?.trimmingCharacters(in: .whitespaces)
            log("list: @\(username)/lists/\(listID) — \(identifiers.count) member(s), name=\(listName ?? "nil")")
            completion(identifiers, listName?.isEmpty == false ? listName : nil, nil)
        }.resume()
    }

    private static func fetchUploaderIdentifiers(username: String, completion: @escaping ([String]?, String?) -> Void) {
        var identifiers: [String] = []
        var seenIdentifiers = Set<String>()

        func fetchPage(_ page: Int) {
            guard page <= maxProfilePages else {
                log("identifiers: hit maxProfilePages (\(maxProfilePages)) for @\(username), stopping with \(identifiers.count) collected")
                completion(identifiers, nil)  // not an error — just stop paging further
                return
            }
            var comps = URLComponents(string: "https://archive.org/services/search/beta/page_production/")!
            comps.queryItems = [
                URLQueryItem(name: "page_type", value: "account_details"),
                URLQueryItem(name: "page_target", value: "@\(username)"),
                URLQueryItem(name: "page_elements", value: "[\"uploads\"]"),
                URLQueryItem(name: "hits_per_page", value: "\(profilePageSize)"),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "sort", value: "publicdate:desc"),
                URLQueryItem(name: "aggregations", value: "false"),
            ]
            guard let url = comps.url else {
                completion(identifiers.isEmpty ? nil : identifiers, "bad profile URL for @\(username)")
                return
            }
            log("identifiers: fetching page \(page) — \(url.absoluteString)")

            URLSession.shared.dataTask(with: makeRequest(url)) { data, response, error in
                if let error {
                    log("identifiers: page \(page) network error — \(error.localizedDescription)")
                    completion(identifiers.isEmpty ? nil : identifiers, "archive.org profile lookup failed: \(error.localizedDescription)")
                    return
                }
                log("identifiers: page \(page) response — \(data?.count ?? 0) bytes")
                let parsedJSON = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                guard let json = parsedJSON,
                      let responseObj = json["response"] as? [String: Any],
                      let body = responseObj["body"] as? [String: Any],
                      let pageElements = body["page_elements"] as? [String: Any],
                      let uploads = pageElements["uploads"] as? [String: Any],
                      let hitsWrapper = uploads["hits"] as? [String: Any],
                      let hits = hitsWrapper["hits"] as? [[String: Any]] else {
                    // separate chain steps so the log can name exactly
                    // which level of the response path broke
                    let responseObj = parsedJSON?["response"] as? [String: Any]
                    let body = responseObj?["body"] as? [String: Any]
                    log("identifiers: page \(page) — path broke at: response=\(parsedJSON != nil) → response.body=\(responseObj?["body"] != nil) → body.keys=\(body?.keys.sorted() ?? [])")
                    completion(identifiers.isEmpty ? nil : identifiers, "archive.org profile lookup returned bad data for @\(username)")
                    return
                }

                if hits.isEmpty {
                    log("identifiers: page \(page) returned 0 hits — treating as end of list, total collected = \(identifiers.count)")
                    completion(identifiers, nil)
                    return
                }

                var duplicatesThisPage = 0
                for hit in hits {
                    guard let fields = hit["fields"] as? [String: Any],
                          let id = fields["identifier"] as? String else { continue }
                    if seenIdentifiers.insert(id).inserted {
                        identifiers.append(id)
                    } else {
                        duplicatesThisPage += 1
                    }
                }
                let total = hitsWrapper["total"] as? Int
                log("identifiers: page \(page) — \(hits.count) hits, \(duplicatesThisPage) already seen, running total \(identifiers.count) of reported \(total.map(String.init) ?? "?")")
                if page == 1 {
                    log("identifiers: first page sample (up to \(logSampleLimit)) — \(identifiers.prefix(logSampleLimit).joined(separator: ", "))")
                }

                // stop at `total` or on a short page; one more page
                // would return empty anyway
                let reachedTotal = total.map { identifiers.count >= $0 } ?? false
                if reachedTotal || hits.count < profilePageSize {
                    log("identifiers: done for @\(username) — \(identifiers.count) collected (reachedTotal=\(reachedTotal), lastPageShort=\(hits.count < profilePageSize))")
                    completion(identifiers, nil)
                } else {
                    fetchPage(page + 1)
                }
            }.resume()
        }

        fetchPage(1)
    }

    // MARK: - Item → files

    // a bare "/download/<id>" link: same per-item metadata lookup,
    // entered directly
    static func resolveItem(identifier: String, completion: @escaping ([ArchiveFile], String?) -> Void) {
        fetchItemFiles(identifier: identifier) { files, error in
            let message: String? = files.isEmpty ? (error ?? "no video files found in \(identifier)") : nil
            completion(files, message)
        }
    }

    // WHY: the "format" field, not the extension, reliably tells video
    // from the thumbnails/xml/torrent files every item carries.
    private static let videoFormats: Set<String> = [
        "matroska", "mpeg4", "h.264", "h.264 iiv", "h.264 hd", "512kb mpeg4",
        "ogg video", "webm", "mpeg2", "quicktime", "flash video",
    ]

    // one /metadata call to the item's video files; mkv preferred, all
    // distinct videos kept, deduped by name stem
    private static func fetchItemFiles(identifier: String, completion: @escaping ([ArchiveFile], String?) -> Void) {
        guard let url = URL(string: "https://archive.org/metadata/\(identifier)") else {
            completion([], "bad metadata URL for \(identifier)")
            return
        }

        URLSession.shared.dataTask(with: makeRequest(url)) { data, response, error in
            if let error {
                completion([], "archive.org metadata failed for \(identifier): \(error.localizedDescription)")
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion([], "archive.org metadata returned bad data for \(identifier)")
                return
            }
            guard let files = json["files"] as? [[String: Any]] else {
                completion([], nil)
                return
            }

            let metadata = json["metadata"] as? [String: Any]
            let itemTitle = (metadata?["title"] as? String)?.trimmingCharacters(in: .whitespaces)

            // WHY: every video file is kept with its size - the user
            // picks the smaller one on a slow connection, which a silent
            // per-stem collapse would defeat.
            var videoEntries: [(name: String, ext: String, sizeBytes: Int64)] = []
            var containers: [ArchiveFile] = []
            for file in files {
                guard let name = file["name"] as? String else { continue }
                if ["zip", "rar"].contains((name as NSString).pathExtension.lowercased()),
                   let route = ArchiveContainerBrowser.route(identifier: identifier, archive: name, prefix: "") {
                    containers.append(ArchiveFile(name: name, size: "", elementId: identifier + "|" + name,
                                                 transferURL: route, isFolder: true))
                    continue
                }
                guard let format = (file["format"] as? String)?.lowercased(),
                      videoFormats.contains(format) else { continue }
                let ext = (name as NSString).pathExtension.lowercased()
                guard ArchiveConfig.videoExtensions.contains(ext) else { continue }
                let sizeBytes = Int64(file["size"] as? String ?? "") ?? 0
                videoEntries.append((name, ext, sizeBytes))
            }

            // mkv first, largest first within a format
            videoEntries.sort { a, b in
                if (a.ext == "mkv") != (b.ext == "mkv") { return a.ext == "mkv" }
                return a.sizeBytes > b.sizeBytes
            }

            let archiveFiles: [ArchiveFile] = videoEntries.map { entry in
                let encodedName = entry.name.addingPercentEncoding(withAllowedCharacters: filenamePathAllowed) ?? entry.name
                let downloadURL = "https://archive.org/download/\(identifier)/\(encodedName)"
                let sizeStr = entry.sizeBytes > 0 ? ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file) : ""
                // single-file items show the item title; multi-file items
                // keep each file's name so versions stay distinguishable.
                // Long names shorten in the middle - the extension must
                // stay visible ("is this the mkv or the mp4").
                let displayName = truncatedFilename((videoEntries.count == 1 ? itemTitle : nil) ?? entry.name)
                return ArchiveFile(name: displayName, size: sizeStr, elementId: identifier, transferURL: downloadURL, isFolder: false)
            }
            completion(containers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } + archiveFiles, nil)
        }.resume()
    }

    // shortens to maxLength, always keeping the extension visible
    private static func truncatedFilename(_ name: String, maxLength: Int = 42) -> String {
        guard name.count > maxLength else { return name }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty else {
            // no recognizable extension: plain end cut with ellipsis
            return String(name.prefix(maxLength - 1)) + "…"
        }
        let reserved = ext.count + 2
        let prefixLength = max(1, maxLength - reserved)
        let stem = String(name.dropLast(ext.count + 1))  // drop ".ext"
        return String(stem.prefix(prefixLength)) + "…." + ext
    }
}


// Archive.org's existing music bridge uses view_archive for RAR and canonical
// /download/item/container/member links. Reuse that service contract, not its
// separate music IPC protocol. No local extraction, shell command or disk path.
private enum ArchiveContainerBrowser {
    struct Route: Codable { let identifier: String; let archive: String; let prefix: String }
    struct Member { let path: String; let url: String; let size: String }
    private static let scheme = "gor-archive-container:"
    private static let lock = NSLock()
    private static var listings: [String: [Member]] = [:]
    private static let maxListingBytes = 8 * 1024 * 1024

    static func safePath(_ path: String, allowEmpty: Bool = false) -> Bool {
        if path.isEmpty { return allowEmpty }
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func route(identifier: String, archive: String, prefix: String) -> String? {
        guard safePath(identifier), !identifier.contains("/"), safePath(archive), safePath(prefix, allowEmpty: true),
              ["zip", "rar"].contains((archive as NSString).pathExtension.lowercased()) else { return nil }
        guard let data = try? JSONEncoder().encode(Route(identifier: identifier, archive: archive, prefix: prefix)) else { return nil }
        return scheme + data.base64EncodedString()
    }
    private static func decode(_ raw: String) -> Route? {
        guard raw.hasPrefix(scheme), let data = Data(base64Encoded: String(raw.dropFirst(scheme.count))),
              let value = try? JSONDecoder().decode(Route.self, from: data),
              route(identifier: value.identifier, archive: value.archive, prefix: value.prefix) != nil else { return nil }
        return value
    }
    private static func entityDecode(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range(at: 1), in: result), let full = Range(match.range, in: result) else { continue }
                let value = String(result[range]); let number = value.hasPrefix("x") ? UInt32(value.dropFirst(), radix: 16) : UInt32(value)
                if let number, let scalar = UnicodeScalar(number) { result.replaceSubrange(full, with: String(scalar)) }
            }
        }
        return result
    }
    static func parse(_ html: String, route: Route) -> [Member] {
        guard let regex = try? NSRegularExpression(pattern: "href\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive]) else { return [] }
        let expected = "/download/" + route.identifier + "/" + route.archive + "/"
        var members: [Member] = []; var seen = Set<String>()
        for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let raw = entityDecode(String(html[range])); let absolute = raw.hasPrefix("//") ? "https:" + raw : raw
            guard let url = URL(string: absolute), url.scheme == "https", url.host?.lowercased() == "archive.org",
                  url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
                  let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
                  let decoded = encodedPath.removingPercentEncoding, decoded.hasPrefix(expected) else { continue }
            let path = String(decoded.dropFirst(expected.count))
            guard safePath(path), ArchiveConfig.videoExtensions.contains((path as NSString).pathExtension.lowercased()), seen.insert(path).inserted else { continue }
            members.append(Member(path: path, url: url.absoluteString, size: ""))
        }
        return members
    }
    private static func rows(_ members: [Member], route value: Route) -> [ArchiveFile] {
        let prefix = value.prefix.isEmpty ? "" : value.prefix + "/"
        var folders = Set<String>(); var files: [ArchiveFile] = []
        for member in members where member.path.hasPrefix(prefix) {
            let remainder = String(member.path.dropFirst(prefix.count)); let components = remainder.split(separator: "/")
            if components.count > 1 { folders.insert(String(components[0])) }
            else if !remainder.isEmpty {
                files.append(ArchiveFile(name: remainder, size: member.size, elementId: value.identifier + "|" + value.archive + "|" + member.path,
                                         transferURL: member.url, isFolder: false))
            }
        }
        let directoryRows = folders.sorted().compactMap { name -> ArchiveFile? in
            guard let next = route(identifier: value.identifier, archive: value.archive, prefix: prefix + name) else { return nil }
            return ArchiveFile(name: name, size: "", elementId: value.identifier + "|" + value.archive + "|" + prefix + name, transferURL: next, isFolder: true)
        }
        return directoryRows + files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    // Bound bytes while receiving, not after a giant response is in memory.
    private final class LimitedFetch: NSObject, URLSessionDataDelegate {
        let limit: Int; let completion: (Data?, URLResponse?, Error?) -> Void
        var bytes = Data(); var response: URLResponse?; var session: URLSession?
        init(limit: Int, completion: @escaping (Data?, URLResponse?, Error?) -> Void) { self.limit = limit; self.completion = completion }
        func start(_ request: URLRequest) {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = request.timeoutInterval
            config.timeoutIntervalForResource = 45
            session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session?.dataTask(with: request).resume()
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            self.response = response
            guard let url = response.url, url.scheme == "https", let host = url.host?.lowercased(),
                  host == "archive.org" || host.hasSuffix(".us.archive.org"),
                  response.expectedContentLength <= Int64(limit) else { completionHandler(.cancel); return }
            completionHandler(.allow)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard data.count <= limit - bytes.count else { dataTask.cancel(); return }
            bytes.append(data)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            completion(error == nil ? bytes : nil, response, error)
            session.finishTasksAndInvalidate(); self.session = nil
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            guard let url = request.url, url.scheme == "https", let host = url.host?.lowercased(),
                  host == "archive.org" || host.hasSuffix(".us.archive.org") else { completionHandler(nil); return }
            completionHandler(request)
        }
    }
    private static func fetchLimited(_ request: URLRequest, limit: Int,
                                     completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        LimitedFetch(limit: limit, completion: completion).start(request)
    }
    static func resolve(_ raw: String, completion: @escaping ([ArchiveFile], String?) -> Void) {
        guard let value = decode(raw) else { completion([], "invalid archive folder path"); return }
        let key = value.identifier + "\n" + value.archive
        lock.lock(); let cached = listings[key]; lock.unlock()
        if let cached { completion(rows(cached, route: value), nil); return }
        guard let id = value.identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let metadataURL = URL(string: "https://archive.org/metadata/" + id) else { completion([], "invalid archive item"); return }
        fetchLimited(URLRequest(url: metadataURL, timeoutInterval: 25), limit: 2 * 1024 * 1024) { data, response, error in
            guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let data, let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let server = meta["server"] as? String, server.hasSuffix(".us.archive.org"),
                  !server.contains("/"), !server.contains(":"),
                  let directory = meta["dir"] as? String, directory.hasPrefix("/"),
                  directory.hasSuffix("/items/" + value.identifier), !directory.contains(".."), !directory.contains("?") else {
                completion([], "archive metadata unavailable: " + (error?.localizedDescription ?? "bad response")); return
            }
            var components = URLComponents(); components.scheme = "https"; components.host = server; components.path = "/view_archive.php"
            components.queryItems = [URLQueryItem(name: "archive", value: directory + "/" + value.archive)]
            guard let listingURL = components.url else { completion([], "invalid archive listing URL"); return }
            var request = URLRequest(url: listingURL, timeoutInterval: 30); request.setValue("text/html", forHTTPHeaderField: "Accept")
            fetchLimited(request, limit: maxListingBytes) { data, response, error in
                guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data, data.count <= maxListingBytes, let html = String(data: data, encoding: .utf8) else {
                    completion([], "couldn't open archive: " + (error?.localizedDescription ?? "unsupported, encrypted or unavailable listing")); return
                }
                let members = parse(html, route: value)
                guard !members.isEmpty else { completion([], "no playable videos in archive, or archive listing is unsupported/encrypted"); return }
                lock.lock(); if listings.count >= 16 { listings.removeAll() }; listings[key] = members; lock.unlock()
                completion(rows(members, route: value), nil)
            }
        }
    }
}
