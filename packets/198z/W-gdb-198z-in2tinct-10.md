# W-gdb-198z-in2tinct-10 - Relocated fixture consumer active-transport-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-10",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/active-transport-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer active-transport-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/active-transport-tests/main.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-10.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-10",
    "paths": [
      "Sources/active-transport-tests/main.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-10.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-10.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.650327+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/active-transport-tests/main.swift",
        "block": "source1",
        "sha256": "c8278453d29fe5ac7df2dffecd9c0896195f8854220e074f417dbd576aaf093e"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-10.py",
        "block": "fixtures1",
        "sha256": "40626efcb08586024eedd3a6b1352ed3d0478c890cfd940559ec82625fba99ee"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "0bd66a4c857a096055b8151b7663edc06474b3ed66d46dc3537afa4dffc21697",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-10; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "a05e2b9f4c2b7a664194e88a90ecb34cf1be2d064b880a8be50f513fac17b1dd"
  }
}
```

```swift id=source1
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

// Real local HTTP -> active decoder AVIO counter. Requires pinned provider with
// http/tcp + mov/h264 support; never silently skip a failed/missing provider.
var failures = 0
func check(_ name: String, _ value: Bool) {
    print("\(value ? "PASS" : "FAIL") \(name)")
    if !value { failures += 1 }
}
let root = FileManager.default.currentDirectoryPath
let fixture = root + "/fixtures/e1-h264-aac-10s.mp4"
guard FileManager.default.fileExists(atPath: fixture) else {
    print("FAIL missing local fixture"); exit(2)
}
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let script = directory.appendingPathComponent("server.py")
let portFile = directory.appendingPathComponent("port")
let countFile = directory.appendingPathComponent("requests")
try #"""
import http.server, sys, threading
fixture, portfile, counterfile = sys.argv[1:]
lock = threading.Lock()
requests = 0
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global requests
        with lock:
            requests += 1
            with open(counterfile, 'w') as f: f.write(str(requests))
        with open(fixture, 'rb') as f: data = f.read()
        begin = 0
        header = self.headers.get('Range', '')
        if header.startswith('bytes='):
            begin = int(header[6:].split('-')[0] or 0)
        if begin >= len(data):
            self.send_response(416); self.end_headers(); return
        self.send_response(206 if begin else 200)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(len(data)-begin))
        if begin: self.send_header('Content-Range', 'bytes %d-%d/%d' % (begin,len(data)-1,len(data)))
        self.end_headers()
        try: self.wfile.write(data[begin:])
        except (BrokenPipeError, ConnectionResetError): pass
    def log_message(self, *args): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
with open(portfile, 'w') as f: f.write(str(server.server_address[1]))
server.serve_forever()
"""#.write(to: script, atomically: true, encoding: .utf8)
let server = Process()
server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
server.arguments = [script.path, fixture, portFile.path, countFile.path]
try server.run()
func stopServer() { if server.isRunning { kill(server.processIdentifier, SIGKILL); server.waitUntilExit() } }
defer { stopServer() }
var port: String?
for _ in 0..<200 {
    if let p = try? String(contentsOf: portFile), !p.isEmpty { port = p; break }
    try await Task.sleep(nanoseconds: 10_000_000)
}
guard let port else { print("FAIL server startup"); stopServer(); exit(2) }
func requests() -> Int? {
    (try? String(contentsOf: countFile)).flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}
let url = "http://127.0.0.1:\(port)/video.mp4"
let decoder = FFmpegSoftwareDecoder()
try decoder.pinLocalRoots([root])
decoder.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 5)
let sid = SessionID(uncheckedEpoch: 9601)
try await decoder.open(source: SourceDescriptor(id: url, kind: .remote, seekable: true), session: sid)
guard let binding = decoder.currentBinding() else { print("FAIL no active binding"); stopServer(); exit(2) }
func snapshot() -> Result<ActiveTransportSnapshot, ActiveTransportRefusal> {
    decoder.activeTransportSnapshot(source: binding.token, session: binding.session, revision: binding.revision)
}
guard case .success(let first) = snapshot() else { print("FAIL no transport snapshot"); stopServer(); exit(2) }
check("H1 real HTTP read count", (first.bytesRead ?? -1) > 0)
check("H2 current-buffer occupancy known", first.bufferAvailableBytes != nil && first.bufferAvailableBytes! >= 0)
check("H3 no invented error", first.errorCode == nil)
check("H4 source identity", first.source == binding.token && first.session == binding.session && first.revision == binding.revision)
let requestCount = requests()
check("H5 server saw real request", (requestCount ?? 0) > 0)
var stable = true
for _ in 0..<100 {
    if case .success(let value) = snapshot() { stable = stable && value == first }
    else { stable = false }
}
check("H6 snapshot no I/O or reopen", stable && requests() == requestCount)
let wrongRevision = try binding.revision.advanced()
check("H7 stale revision refused", decoder.activeTransportSnapshot(source: binding.token, session: binding.session, revision: wrongRevision) == .failure(.staleBinding))
let wrongSession = try SeekSessionID(rawValue: binding.session.rawValue + 1)
check("H8 foreign session refused", decoder.activeTransportSnapshot(source: binding.token, session: wrongSession, revision: binding.revision) == .failure(.staleBinding))
let wrongSource = try SourceToken(instanceID: binding.token.instanceID, openGeneration: binding.token.openGeneration + 1)
check("H9 foreign source refused", decoder.activeTransportSnapshot(source: wrongSource, session: binding.session, revision: binding.revision) == .failure(.staleBinding))
var frames = 0, ended = false
for _ in 0..<2000 {
    guard let event = await decoder.nextEvent(session: sid) else { break }
    switch event {
    case .frameDecoded(let frame):
        frames += 1; await decoder.releaseFrame(handle: frame.handle, session: sid)
    case .endOfStream: ended = true
    case .failed: failures += 1; print("FAIL real decode failed")
    default: break
    }
    if ended { break }
}
check("H10 real decoded frames and end", frames > 0 && ended)
if case .success(let final) = snapshot() {
    check("H11 cumulative observed reads", final.bytesRead != nil && final.bytesRead! >= first.bytesRead!)
    // EOF may be reached through demux semantics without AVIO observing it.
    // Only true or unknown is permitted, never manufactured false/zero.
    check("H12 EOF no prediction", final.eofObserved == nil || final.eofObserved == true)
} else { check("H11 active at EOF", false) }
_ = await decoder.closeAndReport(session: sid)
check("H13 close clears snapshot", snapshot() == .failure(.notOpen))
let newSID = SessionID(uncheckedEpoch: 9602)
try await decoder.open(source: SourceDescriptor(id: url, kind: .remote, seekable: true), session: newSID)
check("H14 old binding after reopen refused", snapshot() == .failure(.staleBinding))
guard let reopened = decoder.currentBinding() else { print("FAIL reopen binding"); stopServer(); exit(2) }
check("H15 new open generation", reopened.token != binding.token)
_ = await decoder.closeAndReport(session: newSID)
check("H16 close new binding", decoder.activeTransportSnapshot(source: reopened.token, session: reopened.session, revision: reopened.revision) == .failure(.notOpen))
stopServer()
try? FileManager.default.removeItem(at: directory)
print("active-transport-tests: \(failures) FAIL (no buffered-seconds/cache/stall inference)")
exit(failures == 0 ? 0 : 1)

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/active-transport-tests/main.swift').read_bytes()).hexdigest()=='c8278453d29fe5ac7df2dffecd9c0896195f8854220e074f417dbd576aaf093e'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-10; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-10; baseline only, product change and semantic test still required
```

secret scan: clean
