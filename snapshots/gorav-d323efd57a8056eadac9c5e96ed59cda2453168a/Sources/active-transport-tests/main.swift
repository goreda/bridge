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
