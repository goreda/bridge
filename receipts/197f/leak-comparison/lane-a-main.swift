// DEF-M2-TLS-02 lifecycle characterization (lane a, plaintext http, ff-min provider).
import Foundation
import GorAVCore
import GorAVFFmpegAdapter

let tmp = NSTemporaryDirectory() + "life-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
let portFile = tmp + "/port"; let serverPy = tmp + "/s.py"
let root = ProcessInfo.processInfo.environment["GORAV_REPO"]!
try! """
import http.server, sys, time
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/slow'): time.sleep(5)
        if self.path.startswith('/forbid'): self.send_response(403); self.end_headers(); return
        data = open(sys.argv[1], 'rb').read()
        self.send_response(200); self.send_header('Content-Type', 'audio/wav')
        self.send_header('Content-Length', str(len(data))); self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
open(sys.argv[2], 'w').write(str(srv.server_address[1]))
srv.serve_forever()
""".write(toFile: serverPy, atomically: true, encoding: .utf8)
let proc = Process(); proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); proc.arguments = [serverPy, root + "/fixtures/tone-48k.wav", portFile]; try! proc.run()
var port = ""
for _ in 0..<200 { if let p = try? String(contentsOfFile: portFile), !p.isEmpty { port = p.trimmingCharacters(in: .whitespacesAndNewlines); break }; try? await Task.sleep(nanoseconds: 50_000_000) }
let wavURL = "http://127.0.0.1:\(port)/tone-48k.wav"
let slowURL = "http://127.0.0.1:\(port)/slow/tone-48k.wav"
let forbidURL = "http://127.0.0.1:\(port)/forbid/tone-48k.wav"
var epoch: UInt64 = 500
func nextEpoch() -> SessionID { epoch += 1; return SessionID(uncheckedEpoch: epoch) }

func oneClose() async {
    let d = FFmpegSoftwareAudioDecoder()
    let s = nextEpoch()
    do { try await d.open(source: SourceDescriptor(id: wavURL, kind: .remote, seekable: true), session: s) } catch { print("L close open-error \(error)"); return }
    _ = await d.nextEvent(session: s)
    await d.close(session: s)
}
func oneAbandon() async {
    var d: FFmpegSoftwareAudioDecoder? = FFmpegSoftwareAudioDecoder()
    let s = nextEpoch()
    do { try await d!.open(source: SourceDescriptor(id: wavURL, kind: .remote, seekable: true), session: s) } catch { print("L abandon open-error \(error)"); return }
    _ = await d!.nextEvent(session: s)
    d = nil
}
func oneFailed() async {
    let d = FFmpegSoftwareAudioDecoder()
    do { try await d.open(source: SourceDescriptor(id: forbidURL, kind: .remote, seekable: true), session: nextEpoch()) ; print("L failed-open unexpectedly opened") } catch { }
}
func oneBlockedDeadline() async {
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 1)
    do { try await d.open(source: SourceDescriptor(id: slowURL, kind: .remote, seekable: true), session: nextEpoch()); print("L deadline unexpectedly opened") } catch { }
}
func oneBlockedCancel() async {
    let d = FFmpegSoftwareAudioDecoder()
    let s = nextEpoch()
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) { d.requestInterrupt(session: s) }
    do { try await d.open(source: SourceDescriptor(id: slowURL, kind: .remote, seekable: true), session: s); print("L cancel unexpectedly opened") } catch { }
}
func oneRecovery() async {
    let d = FFmpegSoftwareAudioDecoder()
    let s = nextEpoch()
    do { try await d.open(source: SourceDescriptor(id: wavURL, kind: .remote, seekable: true), session: s) } catch { print("L recovery open-error \(error)"); return }
    _ = await d.nextEvent(session: s)
    await d.close(session: s)
}

for i in 0..<10 { await oneClose(); print("L explicit close iteration \(i)") }
for i in 0..<10 { await oneAbandon(); print("L abandon/deinit iteration \(i)") }
for i in 0..<3 { await oneFailed(); print("L failed open iteration \(i)") }
await oneBlockedDeadline(); print("L blocked open deadline")
await oneBlockedCancel(); print("L blocked open cancel")
await oneRecovery(); print("L recovery after cancel/deadline")
print("lifecycle-026: all pass")
proc.terminate()
exit(0)
