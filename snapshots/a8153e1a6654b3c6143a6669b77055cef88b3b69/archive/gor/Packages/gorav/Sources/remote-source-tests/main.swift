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
guard let port else {
    check("S0 server started", false)
    print("remote-source-tests: \(failures) FAIL"); exit(1)
}
check("S0 server started on 127.0.0.1:\(port)", true)
let url = "http://127.0.0.1:\(port)/tone-48k.wav"

func probeOpen(withOptions opts: SourceOpenOptions?, epoch: UInt64) async -> String {
    let d = FFmpegSoftwareAudioDecoder()
    do { try d.pinLocalRoots([root]) } catch { return "pin \(error)" }
    if let opts { d.remoteOpenOptions = opts }
    let src = SourceDescriptor(id: url, kind: .remote, seekable: true)
    do {
        try await d.open(source: src, session: SessionID(uncheckedEpoch: epoch))
    } catch { return "open-error: \(error)" }
    // drain the .opened event
    var seen = "no-event"
    if let ev = await d.nextEvent(session: SessionID(uncheckedEpoch: epoch)), case .opened(let c, let r, let ch, _, _) = ev {
        seen = "\(c) \(r)Hz x\(ch)"
    }
    await d.close(session: SessionID(uncheckedEpoch: epoch))
    return seen
}

let noCred = await probeOpen(withOptions: nil, epoch: 91)
check("S1 remote open without credentials is refused by the server", noCred.hasPrefix("open-error"), noCred)
let withCred = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes"], cookies: ["session": "abc", "other": "def"]), epoch: 92)
check("S2 remote open with header+cookie decodes wav stream", withCred == "pcm_s16le 48000Hz x2", withCred)

let injected = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes\r\nX-Injected: true"]), epoch: 95)
check("S2b header newline injection refused", injected.hasPrefix("open-error"), injected)

// S3: transport failure errors carry the redacted URL, never the secret
let d2 = FFmpegSoftwareAudioDecoder()
try! d2.pinLocalRoots([root])
let secretURL = "http://user:s3cr3t@127.0.0.1:1/x.wav?token=abc123"
do {
    try await d2.open(source: SourceDescriptor(id: secretURL, kind: .remote, seekable: true), session: SessionID(uncheckedEpoch: 93))
    check("S3 dead-endpoint open throws", false, "opened")
} catch {
    let msg = "\(error)"
    check("S3 error redacts userinfo and query", msg.contains("REDACTED") && !msg.contains("s3cr3t") && !msg.contains("abc123"), msg)
}

// S4: scheme admission still enforced for the audio path
do {
    try await d2.open(source: SourceDescriptor(id: "ftp://127.0.0.1/x.wav", kind: .remote, seekable: true), session: SessionID(uncheckedEpoch: 94))
    check("S4 non-admitted scheme refused", false, "opened")
} catch {
    check("S4 non-admitted scheme refused", "\(error)".contains("scheme not admitted"), "\(error)")
}

proc.terminate()
print(failures == 0 ? "remote-source-tests: all pass" : "remote-source-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
