# W-gdb-198y-1nstinct-13
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/MegaStreamManager.swift -> GorSources. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-13.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-13",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/MegaStreamManager.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/MegaStreamManager.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: LineAccumulator, append, ByteLineAccumulator, append, RelayReadyOnce, showMegaOSD, isTransferItCDN, streamMega, stopMegaRelay",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-13.py",
    "callee": "archive/gor/Sources/gor/MegaStreamManager.swift owning station GorSources"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-13.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-13.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-13.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.491414+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/MegaStreamManager.swift",
        "block": "source1",
        "sha256": "f207c003097927b7a4857c8c54337cd75fb0073ddd0e6b2a7b3cb360b384ff42"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-13.py",
        "block": "fixtures1",
        "sha256": "f54fd5ecbe390676c48a708808f190a10ba5cc750165d56ecd911493363a5cbe"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "06d588f437fff0523b16a23c3fdba6cdb8cd8d54675d76faa65cba7374813449",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-13: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "d71bce14aaa0e22255ae1367d088b082b2a236dff00a653f2a147a3bab26d754"
  }
}
```

```swift id=source1
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

        let port = 2223
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
            guard !data.isEmpty else { return }
            for line in stdoutBuffer.append(data) {
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
            guard !data.isEmpty else { return }
            for line in stderrBuffer.append(data) {
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
        // Detach handlers so they can't outlive the process (buffer/handle
        // leak), then reap off-main.
        megaStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        megaStderrPipe?.fileHandleForReading.readabilityHandler = nil
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

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/MegaStreamManager.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='f207c003097927b7a4857c8c54337cd75fb0073ddd0e6b2a7b3cb360b384ff42', 'pinned source changed: rebase and review, never bless silently'
for token in ['LineAccumulator', 'append', 'ByteLineAccumulator', 'append', 'RelayReadyOnce', 'showMegaOSD', 'isTransferItCDN', 'streamMega', 'stopMegaRelay']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='f207c003097927b7a4857c8c54337cd75fb0073ddd0e6b2a7b3cb360b384ff42'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-13: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-13: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
