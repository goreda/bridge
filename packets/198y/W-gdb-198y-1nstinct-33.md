# W-gdb-198y-1nstinct-33
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-33.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-33",
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
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-33.py checks archive/gor/Sources/gor/MegaStreamManager.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: LineAccumulator, append, ByteLineAccumulator, append, RelayReadyOnce, showMegaOSD, isTransferItCDN, streamMega, stopMegaRelay",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-33.py",
    "callee": "archive/gor/Sources/gor/MegaStreamManager.swift owning station GorSources"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-33.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-33.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-33.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.043008+00:00",
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
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-33.py",
        "block": "fixtures1",
        "sha256": "d231182eabda45238a704ef3a2b61ac0ad3191419b6174b916cd641a842884b8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "3854a9f4e48145ea503e961188fa5e7bb02f1bbef68ae5ab1b05d6bc4d299b3c",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-33: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "8403f6812857f4bf824e5f22135148ed6c6192c811d4fa5b1bd95266cf6f73b2"
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
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-33: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-33: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
