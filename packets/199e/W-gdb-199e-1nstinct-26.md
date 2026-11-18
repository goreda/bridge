# W-gdb-199e-1nstinct-26 - Relay line framing strips CRLF terminators
state: OPEN / unclaimed
lab: 1nstinct

LineAccumulator and ByteLineAccumulator must consume CRLF as a line terminator without retaining trailing CR in a completed protocol line. Preserve LF-only framing, partial tails, empty-line suppression and split UTF8-byte behavior. Strip only the CR immediately before LF, not meaningful internal or leading spaces. No relay launch/network changes.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-1nstinct-26",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorSources/MegaStreamManager.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "LineAccumulator and ByteLineAccumulator must consume CRLF as a line terminator without retaining trailing CR in a completed protocol line. Preserve LF-only framing, partial tails, empty-line suppression and split UTF8-byte behavior. Strip only the CR immediately before LF, not meaningful internal or leading spaces. No relay launch/network changes.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "archive/gor/Sources/gor/GorSources/MegaStreamManager.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-26.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199e-1nstinct-26",
    "paths": [
      "archive/gor/Sources/gor/GorSources/MegaStreamManager.swift",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-26.py",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-26.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-26.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorSources/MegaStreamManager.swift",
        "block": "source1",
        "sha256": "f207c003097927b7a4857c8c54337cd75fb0073ddd0e6b2a7b3cb360b384ff42",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-26.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-26.json",
        "block": "fixtures2",
        "sha256": "6c8a5c09987ce6e310f57e20ca989a73464ae096d80bfe916ea3c2397f62ec3f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "31bb866b40b2c23a78f9c82da35b3a79cf9702147c854bcbb9accda1e88fe689",
    "last_5_lines": [
      "FAIL text CRLF terminator consumed",
      "PASS split CR held",
      "FAIL byte CRLF terminator consumed",
      "PASS LF framing retained",
      ""
    ],
    "receipt_sha256": "0c4801c2df7786b7857e3347e09f29640b743c1298f16542eb65a52fda2655cb"
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
  "source": "archive/gor/Sources/gor/GorSources/MegaStreamManager.swift",
  "markers": [
    "final class LineAccumulator {",
    "final class ByteLineAccumulator {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet text=LineAccumulator()\ncheck(text.append(\"STREAM:https://example.invalid/a\\r\\n\") == [\"STREAM:https://example.invalid/a\"],\"text CRLF terminator consumed\")\nlet bytes=ByteLineAccumulator()\ncheck(bytes.append(Data(\"ERROR:failure\\r\".utf8)).isEmpty,\"split CR held\")\ncheck(bytes.append(Data(\"\\n\".utf8)) == [\"ERROR:failure\"],\"byte CRLF terminator consumed\")\ncheck(text.append(\"x\\n\") == [\"x\"],\"LF framing retained\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL text CRLF terminator consumed
PASS split CR held
FAIL byte CRLF terminator consumed
PASS LF framing retained


```

Publication caveat: NONQUALIFIED: exact-source declaration extraction, not native/full module acceptance. HeatTelemetry in A27 is an explicit test support value, not production telemetry evidence. Own compiler rerun NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
