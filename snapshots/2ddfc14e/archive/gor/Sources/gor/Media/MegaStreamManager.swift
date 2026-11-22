// ================================================================
//  MegaStreamManager.swift - MEGA local relay (megajs-based)
//  Owns: relay process and STREAM:/ERROR: stdout handling
//  Contract: A complete STREAM: line supplies the playable relay URL.
//  The relay resolves the share, node keys and CDN URL itself from the
//  mega link (megajs, vendored in Resources/vendor/mega_relay/node_modules) -
//  Swift only hands it the link and, for folder taps, the file handle.
// ================================================================

import AppKit
import Foundation

// ================================================================
//  LineAccumulator - relay line framing
// ================================================================
// CONTRACT: STREAM:/ERROR: lines may split across reads; emit only complete lines.
final class LineAccumulator {
    private var pending = ""
    func append(_ chunk: String) -> [String] {
        pending += chunk
        guard let lastNewline = pending.range(of: "\n", options: .backwards) else {
            return []
        }
        let completePart = String(pending[..<lastNewline.upperBound])
        pending = String(pending[lastNewline.upperBound...])
        return completePart.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

/// Byte-level framing: a multibyte UTF-8 scalar split across two reads must not drop the line.
/// Complete lines (up to the last newline) are decoded together; the incomplete tail stays as bytes.
final class ByteLineAccumulator {
    private var pending = Data()
    func append(_ data: Data) -> [String] {
        pending.append(data)
        guard let last = pending.lastIndex(of: 0x0A) else { return [] }
        let complete = pending[..<pending.index(after: last)]
        pending = Data(pending[pending.index(after: last)...])
        return String(decoding: complete, as: UTF8.self).components(separatedBy: "\n").filter { !$0.isEmpty }
    }
    func finish() -> [String] {
        defer { pending.removeAll(keepingCapacity: false) }
        return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
    }
}

/// One terminal "ready" per relay start (main queue only).
final class RelayReadyOnce { var fired = false }

// ================================================================
//  AppDelegate - application lifecycle
// ================================================================
extension AppDelegate {
    /// Relay status lines: while the archive browser shows its interception
    /// placeholder, render there (a row below it — the mpv OSD layer overlaps
    /// the browser's topbar). Otherwise the mpv OSD as before.
    private func showMegaOSD(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let panel = self.overlayWin?.contentView?.subviews
                .first(where: { $0 is ArchiveBrowserPanel }) as? ArchiveBrowserPanel
            if panel?.showMegaRelayStatus(message) == true { return }
            self.controller?.spineUI.showMPVOSD(message)
        }
    }

    /// Signed transfer.it CDN URLs use a bounded parallel range relay rather than one mpv
    /// connection. Host-only routing leaves ordinary MEGA share resolution unchanged.
    static func isTransferItCDN(_ raw: String) -> Bool {
        guard let c = URLComponents(string: raw), c.scheme == "https",
              let host = c.host?.lowercased(), host.hasSuffix(".userstorage.mega.co.nz"),
              c.user == nil, c.password == nil, c.port == nil else { return false }
        return true
    }

    func streamMega(shareLink: String, nodeKeyField: String, folderKeyFragment: String, title: String,
                    startPos: Double? = nil, subtitleURLs: [String] = []) {
        stopMegaRelay()

        guard let scriptPath = GORResources.vendor()?.appendingPathComponent("mega_relay/mega_relay.mjs").path,
              FileManager.default.fileExists(atPath: scriptPath) else {
            showMegaOSD("mega_relay.mjs not found")
            return
        }

        // Homebrew fallback preserved with EXACT old semantics: a vendored
        // node wins whenever it EXISTS (the exec/exists guard below errors
        // exactly as before); only its ABSENCE falls back to Homebrew.
        let vendoredNode = GORResources.vendor()?.appendingPathComponent("node/node").path
        let nodePath = vendoredNode.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            ?? "/opt/homebrew/bin/node"
        guard FileManager.default.fileExists(atPath: nodePath) else {
            showMegaOSD("node not found")
            return
        }

        let capture = PlayerSessionContext.shared
        let resourceProducer: PlayerSessionDrainPlan.Producer?
        do { resourceProducer = try capture?.register(kind: "mega-resource", barriers: ["exit", "stdout-eof-tail", "stderr-eof-tail"]) }
        catch { showMegaOSD("player is closing"); return }
        let port = 0
        let p = Process()
        p.executableURL = URL(fileURLWithPath: nodePath)
        p.arguments = [scriptPath, String(port), shareLink, nodeKeyField, folderKeyFragment]
        p.environment = [
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
        ]

        if Self.isTransferItCDN(shareLink),let ticket=TransferTicketContext.lookup(shareLink) {
            p.environment?["GOR_TRANSFER_SHARE"]=ticket.share;p.environment?["GOR_TRANSFER_NODE"]=ticket.node
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        p.standardOutput = stdoutPipe
        p.standardError = stderrPipe
        megaRelayProcess = p
        megaStdoutPipe = stdoutPipe
        megaStderrPipe = stderrPipe

        let stdoutBuffer = ByteLineAccumulator()
        let stderrBuffer = ByteLineAccumulator()
        let ready = RelayReadyOnce()

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let eof = data.isEmpty
            if eof { handle.readabilityHandler = nil }
            let lines = eof ? stdoutBuffer.finish() : stdoutBuffer.append(data)
            defer {
                if eof, let capture, let producer = resourceProducer {
                    do { try capture.observe("stdout-eof-tail", producer: producer) }
                    catch { NSLog("[GOR] MEGA stdout evidence pending") }
                }
            }
            for line in lines {
                let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard l.hasPrefix("STREAM:") else { continue }
                let url = String(l.dropFirst("STREAM:".count))
                DispatchQueue.main.async { [weak self, weak p] in
                    // A ready already queued on main must not outlive stop/replacement, and
                    // only the first ready of this relay may start playback.
                    guard let self, let p, self.megaRelayProcess === p, !ready.fired else { return }
                    ready.fired = true
                    self.showMegaOSD("stream ready")
                    let transfer = Self.isTransferItCDN(shareLink)
                    TransferProbeAdmission.configure(transfer ? url : nil)
                    self.cmd(TransferProbeAdmission.markerCommand(transfer ? url : nil))
                    self.playMedia(url: url, title: title, startPos: startPos, subtitleURLs: subtitleURLs)
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            let eof = data.isEmpty
            if eof { handle.readabilityHandler = nil }
            let lines = eof ? stderrBuffer.finish() : stderrBuffer.append(data)
            defer {
                if eof, let capture, let producer = resourceProducer {
                    do { try capture.observe("stderr-eof-tail", producer: producer) }
                    catch { NSLog("[GOR] MEGA stderr evidence pending") }
                }
            }
            for line in lines {
                let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if l.hasPrefix("CDN-EVIDENCE:") {print("[mega_relay] \(l)");continue}
                guard l.hasPrefix("ERROR:") else { continue }
                let msg = String(l.dropFirst("ERROR:".count))
                print("[mega_relay] \(msg)")
                DispatchQueue.main.async { [weak self, weak p] in
                    guard let self, let p, self.megaRelayProcess === p else { return }
                    self.showMegaOSD(msg)
                }
            }
        }

        p.terminationHandler = { _ in
            if let capture, let producer = resourceProducer {
                do { try capture.observe("exit", producer: producer) }
                catch { NSLog("[GOR] MEGA exit evidence pending") }
            }
        }
        showMegaOSD("resolving mega link...")
        do {
            try p.run()
            QuitChildKiller.shared.register(p)
        } catch {
            showMegaOSD("failed to start mega relay: \(error.localizedDescription)")
        }
    }

    func stopMegaRelay() {
        TransferProbeAdmission.configure(nil)
        cmd(TransferProbeAdmission.markerCommand(nil))
        // Stop owns this Process; pipe owners remain alive through EOF.
        // Reader closures retain their parser and producer through actual EOF.
        // Detaching here would discard tails and falsely bypass resource proof.
        megaStdoutPipe = nil
        megaStderrPipe = nil
        // isRunning guard: the quit-time helper may already have killed it.
        if let proc = megaRelayProcess, proc.isRunning {
            proc.terminate()
            DispatchQueue.global(qos: .utility).async { proc.waitUntilExit() }
        }
        if let proc = megaRelayProcess { QuitChildKiller.shared.unregisterIfStopped(proc) }
        megaRelayProcess = nil
    }
}
