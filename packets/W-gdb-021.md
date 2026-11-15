# W-gdb-021 scripted loopback HTTP edge-case server kit
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-021

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
rows 54/61/62/64 (remote audio/video open, transport snapshots) each spawn ad-hoc python loopback servers; there is no shared scripted edge-case server, so edge behaviors (dribble, range, drop mid-body) are covered unevenly and new remote code ships untested against them.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/remote-source-tests/main.swift (sha256 b7bfea62) - one of the ad-hoc servers to unify; scripts/ci/native-harness-map-195b.md (same pin) - the four rows that need the kit.
- real test command: swift run remote-source-tests (13 PASS on Linux with the http/tcp kit).

## expected behaviour
a python-stdlib-only scripted server kit: dribbled bodies, trickled headers, range honored/ignored/partial, redirect chains/loops, chunked/gzip, content-length mismatch, drop mid-body, slow EOF; each scenario behind one typed switch with a request log; reusable by any client transport test.

## exact call site and interface
the kit's scenario API is the deliverable; the pinned suite shows the consumer pattern.

## behaviour that must not change
the existing 13+23+5+16 checks across the four rows stay green; loopback only - no external endpoints, no credentials.

## acceptance test (from the product repo)
the kit replays every existing loopback leg green plus its new scenarios; a scenario switch produces exactly its scripted behavior (request log shown).

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/remote-source-tests/main.swift (sha256 b7bfea62, lines 1-60 of 115)
```swift
import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// R3 (arch-195b) witness: remote (http) source open with headers/cookies,
// redaction, and refusal without credentials. Local python http server
// requires a header AND a cookie; serves a PCM wav (stream-friendly probe).

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

// U-series: redaction and option summary (pure)
check("U1 userinfo redacted", URLRedaction.redact("http://user:secret@example.com/a.wav") == "REDACTED")
check("U2 query values and keys redacted", URLRedaction.redact("https://h/p?token=abc&x=1") == "REDACTED")
check("U3 fragment and path redacted", URLRedaction.redact("http://h/secret#frag") == "REDACTED")
check("U4 local path not exposed", URLRedaction.redact("/plain/path.wav") == "REDACTED")
check("U6 malformed credential redacted", URLRedaction.redact("http://user:slash/secret@host/p?bareSecret") == "REDACTED")
check("U7 encoded credential redacted", URLRedaction.redact("http://%73ecret@host/%74oken?%73ecret") == "REDACTED")
check("U5 summary counts only", SourceOpenOptions(headers: ["Authorization": "s3cr3t"], cookies: ["k": "v"]).redactedSummary == "headers=1 cookies=1 deadline=none")

// S-series: live http open through the admitted remote path
let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
let fixture = root + "/fixtures/tone-48k.wav"
let tmp = NSTemporaryDirectory() + "r3srv-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
let serverPy = tmp + "/server.py"
let portFile = tmp + "/port"
let script = """
import http.server, sys, threading
fixture = sys.argv[1]
portfile = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get('X-GorAV-Test') != 'yes' or ('session=abc' not in (self.headers.get('Cookie') or '') or 'other=def' not in (self.headers.get('Cookie') or '')):
            self.send_response(403); self.end_headers(); return
        with open(fixture, 'rb') as fh: data = fh.read()
        self.send_response(200)
        self.send_header('Content-Type', 'audio/wav')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
with open(portfile, 'w') as fh: fh.write(str(srv.server_address[1]))
srv.serve_forever()
"""
try! script.write(toFile: serverPy, atomically: true, encoding: .utf8)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
proc.arguments = [serverPy, fixture, portFile]
try! proc.run()
var port: String? = nil
for _ in 0..<200 {
    if let p = try? String(contentsOfFile: portFile, encoding: .utf8), !p.isEmpty { port = p.trimmingCharacters(in: .whitespacesAndNewlines); break }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
