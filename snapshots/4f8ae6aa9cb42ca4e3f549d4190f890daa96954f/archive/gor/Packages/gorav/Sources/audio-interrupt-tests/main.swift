import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// 195b-54 witness: bounded cancellation/deadline for remote audio open and
// stream-info through the provider interrupt path, per-open immutable
// validated options, credential-free diagnostics. Local python http fixtures
// (delayed headers, dribbled body) prove cancellation lands in bounded time.
// No HTTPS-provider or cache-state claim: loopback http only.

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

func validationError(_ o: SourceOpenOptions) -> SourceOpenOptionsError? {
    do { _ = try o.validatedForOpen(); return nil }
    catch let e as SourceOpenOptionsError { return e }
    catch { return nil }
}

// V-series: per-open option validation (pure, no network)
check("V1 valid options validate", validationError(SourceOpenOptions(headers: ["X-A": "b"], cookies: ["k": "v"], openDeadlineSeconds: 2)) == nil)
check("V2 zero deadline refused", validationError(SourceOpenOptions(openDeadlineSeconds: 0)) == .deadlineInvalid)
check("V3 negative deadline refused", validationError(SourceOpenOptions(openDeadlineSeconds: -1)) == .deadlineInvalid)
check("V4 non-finite deadline refused", validationError(SourceOpenOptions(openDeadlineSeconds: .infinity)) == .deadlineInvalid)
check("V5 header CR/LF injection refused typed", validationError(SourceOpenOptions(headers: ["X": "a\r\nB: c"])) == .headerInjection)
check("V6 cookie CR/LF injection refused typed", validationError(SourceOpenOptions(cookies: ["k": "a\r\nb"])) == .cookieInjection)
check("V7 cookie/header conflict refused typed", validationError(SourceOpenOptions(headers: ["Cookie": "x=1"], cookies: ["a": "b"])) == .cookieHeaderConflict)
check("V8 summary stays credential-free", SourceOpenOptions(headers: ["Authorization": "s3cr3t"], cookies: ["k": "v"], openDeadlineSeconds: 3).redactedSummary == "headers=1 cookies=1 deadline=armed")
check("V9 no deadline by default", SourceOpenOptions().redactedSummary == "headers=0 cookies=0 deadline=none")

// D-series: live http fixtures
let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
let fixture = root + "/fixtures/tone-48k.wav"
let tmp = NSTemporaryDirectory() + "aisrv-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
let serverPy = tmp + "/server.py"
let portFile = tmp + "/port"
let script = """
import http.server, sys, time
fixture = sys.argv[1]
portfile = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def _wav(self):
        with open(fixture, 'rb') as fh: return fh.read()
    def do_GET(self):
        try:
            path = self.path.split('?')[0]
            if path.startswith('/slow-header'):
                # Headers delayed 20s: a non-interruptible open hangs here.
                time.sleep(20)
                data = self._wav()
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            elif path.startswith('/dribble'):
                # Headers at once, body one byte per 0.2s: open/probe stalls
                # mid-body. Client abort raises BrokenPipeError, caught below.
                data = self._wav()
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                for i in range(len(data)):
                    self.wfile.write(data[i:i+1]); self.wfile.flush(); time.sleep(0.2)
            else:
                data = self._wav()
                self.send_response(200)
                self.send_header('Content-Type', 'audio/wav')
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Accept-Ranges', 'bytes')
                self.end_headers()
                self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
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
    check("D0 server started", false)
    print("audio-interrupt-tests: \(failures) FAIL"); exit(1)
}
check("D0 server started on 127.0.0.1:\(port)", true)
let base = "http://127.0.0.1:\(port)"

func remote(_ path: String) -> SourceDescriptor {
    SourceDescriptor(id: base + path, kind: .remote, seekable: true)
}

// D1: requestInterrupt cancels an open blocked on delayed headers.
do {
    let d = FFmpegSoftwareAudioDecoder()
    let session = SessionID(uncheckedEpoch: 201)
    let start = DispatchTime.now()
    let openTask = Task { try await d.open(source: remote("/slow-header.wav"), session: session) }
    try await Task.sleep(nanoseconds: 1_000_000_000)
    d.requestInterrupt(session: session)
    do {
        try await openTask.value
        check("D1 cancel blocked open", false, "opened")
    } catch {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        let msg = "\(error)"
        check("D1 cancel blocked open throws interrupted", msg.contains("open interrupted"), msg)
        check("D1 bounded wait (server delay is 20s)", elapsed < 8, String(format: "%.2fs", elapsed))
        check("D1 diagnostics credential-free", !msg.contains("127.0.0.1") && !msg.contains("/slow-header"), msg)
    }
}

// D2: per-open deadline aborts the same blocked open without any interrupt.
do {
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 0.75)
    let start = DispatchTime.now()
    do {
        try await d.open(source: remote("/slow-header.wav"), session: SessionID(uncheckedEpoch: 202))
        check("D2 deadline aborts blocked open", false, "opened")
    } catch {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        check("D2 deadline exceeded error", "\(error)".contains("deadline exceeded"), "\(error)")
        check("D2 bounded wait", elapsed < 8, String(format: "%.2fs", elapsed))
    }
}

// D3: deadline aborts an open stalled mid-body (dribbled bytes).
do {
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 1.0)
    let start = DispatchTime.now()
    do {
        try await d.open(source: remote("/dribble.wav"), session: SessionID(uncheckedEpoch: 203))
        check("D3 deadline aborts dribbled body", false, "opened")
    } catch {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        check("D3 deadline exceeded on dribble", "\(error)".contains("deadline exceeded"), "\(error)")
        check("D3 bounded wait", elapsed < 10, String(format: "%.2fs", elapsed))
    }
}

// D4: no completion after close; a stale-session interrupt is a fenced no-op
// against the NEXT session on the same decoder.
do {
    let d = FFmpegSoftwareAudioDecoder()
    let old = SessionID(uncheckedEpoch: 204)
    let openTask = Task { try await d.open(source: remote("/slow-header.wav"), session: old) }
    try await Task.sleep(nanoseconds: 1_000_000_000)
    d.requestInterrupt(session: old)
    _ = try? await openTask.value
    await d.close(session: old)
    let next = SessionID(uncheckedEpoch: 205)
    do {
        try await d.open(source: remote("/fast.wav"), session: next)
        d.requestInterrupt(session: old) // stale: must not reach the live session
        if let ev = await d.nextEvent(session: next), case .opened = ev {
            check("D4 next session opens after cancelled attempt", true)
        } else {
            check("D4 next session opens after cancelled attempt", false, "no .opened event")
        }
        var sawPCM = false
        for _ in 0..<50 {
            if let ev = await d.nextEvent(session: next) {
                if case .pcm = ev { sawPCM = true; break }
                if case .failed = ev { break }
            } else { break }
        }
        check("D4 stale-session interrupt is a fenced no-op", sawPCM)
        await d.close(session: next)
    } catch {
        check("D4 next session opens after cancelled attempt", false, "\(error)")
    }
}

// D5: interrupt diagnostics never carry credentials, header/cookie values,
// or any URL component.
do {
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(headers: ["Authorization": "Bearer s3cr3t"], cookies: ["session": "abc"])
    let session = SessionID(uncheckedEpoch: 206)
    let openTask = Task { try await d.open(source: remote("/slow-header.wav?token=abc123"), session: session) }
    try await Task.sleep(nanoseconds: 1_000_000_000)
    d.requestInterrupt(session: session)
    do {
        try await openTask.value
        check("D5 cancel with credentials", false, "opened")
    } catch {
        let msg = "\(error)"
        check("D5 interrupted named plainly", msg.contains("interrupted"), msg)
        check("D5 no credential or URL leak", !msg.contains("s3cr3t") && !msg.contains("abc123") && !msg.contains("session=abc") && !msg.contains("127.0.0.1"), msg)
    }
}

// D6: invalid options are a typed refusal before any network access.
do {
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: -1)
    do {
        try await d.open(source: remote("/fast.wav"), session: SessionID(uncheckedEpoch: 207))
        check("D6 invalid options refused", false, "opened")
    } catch {
        check("D6 invalid options refused", "\(error)".contains("invalid remote open options"), "\(error)")
    }
}

// D7: regression - a plain remote open with valid options still decodes.
do {
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 30)
    let session = SessionID(uncheckedEpoch: 208)
    do {
        try await d.open(source: remote("/fast.wav"), session: session)
        var seen = "no-event"
        if let ev = await d.nextEvent(session: session), case .opened(let c, let r, let ch, _, _) = ev {
            seen = "\(c) \(r)Hz x\(ch)"
        }
        check("D7 plain remote open decodes wav", seen == "pcm_s16le 48000Hz x2", seen)
        await d.close(session: session)
    } catch {
        check("D7 plain remote open decodes wav", false, "\(error)")
    }
}

proc.terminate()
print(failures == 0 ? "audio-interrupt-tests: all pass" : "audio-interrupt-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
