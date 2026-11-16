# M2-ARCHIVE-PCM-02: discriminating metadata faults and independent PCM anchor
state: candidate

```packet-json
{
  "packet_id": "M2-ARCHIVE-PCM-02",
  "writer": "gdb",
  "code_owner": "M2-source product lane",
  "product_repo": "goreda/gorav",
  "product_sha": "a34e2cd96b6825932a196424a17cc62962e910a7",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ArchiveItemSource.swift",
      "excerpt_block": "candidate"
    }
  ],
  "interface": {
    "signatures": "ArchiveItemSource.downloadURL(metadata:identifier:filename:base:) throws -> URL; ArchiveMetadataFetch.start(identifier:base:timeout:cap:completion:) throws -> ArchiveMetadataFetch; cancel()",
    "types": "ArchiveItemSourceError typed metadata/file/cap/HTTP refusals; bounded Data metadata; exact caller-selected filename",
    "ownership_lifetime": "Operation retains URLSession until completion; serial delegate; task publication/cancel snapshot/completion nil are NSLock guarded; caller owns handle. PCM anchor generated independently of any decoder.",
    "caller": "Packet archive-main integration witness; future source coordinator consumes explicit result",
    "callee": "Proposed GorAVPlaybackCore ArchiveItemSource plus actual FFmpegSoftwareAudioDecoder"
  },
  "test": {
    "command": "bash kits/m2-source-packets/archive-v2-canonical.sh",
    "expected": "exit0; exact typed metadata/file/HTTP refusals; cancelled URLError before1s with8s timeout; content-length and length-omitted running-cap refusals; wrong-item URL404; remote fullPCM equals independently packed integer-sample rawPCM and local decode. m2-archive-pcm-v2: all pass. Controlled fixture only.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/GorAVPlaybackCore/ArchiveItemSource.swift",
      "kits/m2-source-packets/archive-v2-canonical.sh",
      "kits/m2-source-packets/archive-main-v2.swift",
      "kits/m2-source-packets/generate-archive-anchor.py"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ArchiveItemSource.swift",
        "block": "candidate"
      },
      {
        "path": "kits/m2-source-packets/archive-v2-canonical.sh",
        "block": "runner"
      },
      {
        "path": "kits/m2-source-packets/archive-main-v2.swift",
        "block": "harness"
      },
      {
        "path": "kits/m2-source-packets/generate-archive-anchor.py",
        "block": "generator"
      }
    ]
  }
}
```

## Scope and decision
Supersedes fixture coverage claims ofM2-ARCHIVE-PCM-01, not its historical receipt. Proposed portable source now locks external task access and normalizes invalidJSON to exact badMetadata. Original8MiB response bound and exact callerfilename policy retained. Independent deterministic44100Hz stereo packed samples are the PCM oracle, no FFmpeg generator/decoder/resampler supplies expectedbytes. Actual service/nativeUI/coordinator wiring remain separate owned outcomes. Fresh lane/ingest replay needed; no manufactured proof.

```swift id=candidate
// Proposed original-engine P4 source adapter. No player/ffmpeg wrapper.
// Metadata contract: archive.org/developers/md-read.html and md-record.html.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ArchiveItemSourceError: Error, Equatable {
    case invalidIdentifier, invalidFilename, badMetadata, unavailable
    case missingFile, duplicateFile, privateFile, responseTooLarge, httpStatus(Int)
}

public enum ArchiveItemSource {
    public static let maxMetadataBytes = 8 * 1024 * 1024
    public static func identifier(_ id: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard !id.isEmpty, id != ".", id != "..", id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ArchiveItemSourceError.invalidIdentifier
        }
        return id
    }
    public static func fileComponents(_ filename: String) throws -> [String] {
        let parts = filename.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 92 }) else {
            throw ArchiveItemSourceError.invalidFilename
        }
        return parts
    }
    public static func downloadURL(metadata: Data, identifier id: String, filename: String,
                                   base: URL = URL(string: "https://archive.org")!) throws -> URL {
        _ = try identifier(id); let parts = try fileComponents(filename)
        guard metadata.count <= maxMetadataBytes else { throw ArchiveItemSourceError.responseTooLarge }
        guard let obj = (try? JSONSerialization.jsonObject(with: metadata)) as? [String: Any],
              let files = obj["files"] as? [[String: Any]] else { throw ArchiveItemSourceError.badMetadata }
        func set(_ v: Any?) -> Bool {
            if let b = v as? Bool { return b }
            if let s = v as? String { return s == "true" || s == "1" }
            return false
        }
        guard !set(obj["is_dark"]), !set(obj["nodownload"]) else { throw ArchiveItemSourceError.unavailable }
        let matches = files.filter { ($0["name"] as? String) == filename }
        guard !matches.isEmpty else { throw ArchiveItemSourceError.missingFile }
        guard matches.count == 1 else { throw ArchiveItemSourceError.duplicateFile }
        guard !set(matches[0]["private"]) else { throw ArchiveItemSourceError.privateFile }
        var url = base.appendingPathComponent("download").appendingPathComponent(id)
        for part in parts { url.appendPathComponent(part) }
        return url
    }
}

// Caller owns cancellation via the returned operation. Response collection is
// bounded before appending bytes, and completion fires once on a serial queue.
public final class ArchiveMetadataFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var data = Data()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let taskLock = NSLock()
    private var failure: Error?
    private let completion: (Result<Data, Error>) -> Void
    private let cap: Int
    private init(cap: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        self.cap = cap; self.completion = completion
    }
    @discardableResult
    public static func start(identifier: String, base: URL = URL(string: "https://archive.org")!,
                             timeout: TimeInterval = 25, cap: Int = ArchiveItemSource.maxMetadataBytes,
                             completion: @escaping (Result<Data, Error>) -> Void) throws -> ArchiveMetadataFetch {
        _ = try ArchiveItemSource.identifier(identifier)
        guard cap > 0, timeout.isFinite, timeout > 0 else { throw ArchiveItemSourceError.badMetadata }
        let op = ArchiveMetadataFetch(cap: cap, completion: completion)
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout
        config.httpCookieStorage = nil; config.urlCache = nil
        op.session = URLSession(configuration: config, delegate: op, delegateQueue: queue)
        var request = URLRequest(url: base.appendingPathComponent("metadata").appendingPathComponent(identifier))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = op.session!.dataTask(with: request)
        op.taskLock.lock(); op.task = task; op.taskLock.unlock()
        task.resume()
        return op
    }
    public func cancel() {
        taskLock.lock(); let current = task; taskLock.unlock()
        current?.cancel()
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            failure = ArchiveItemSourceError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            completionHandler(.cancel); return
        }
        if response.expectedContentLength > Int64(cap) {
            failure = ArchiveItemSourceError.responseTooLarge; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard failure == nil else { return }
        guard chunk.count <= cap - data.count else {
            failure = ArchiveItemSourceError.responseTooLarge; dataTask.cancel(); return
        }
        data.append(chunk)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = failure ?? error { completion(.failure(e)) } else { completion(.success(data)) }
        data.removeAll()
        taskLock.lock(); self.task = nil; taskLock.unlock()
        self.session = nil
        session.finishTasksAndInvalidate()
    }
}
```

```sh id=runner
#!/usr/bin/env bash
set -u -o pipefail
: "${M2_FF_PREFIX:?exact provider prefix required}"
ff=$(realpath "$M2_FF_PREFIX")
export PKG_CONFIG_PATH="$ff/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$ff/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
python3 kits/m2-source-packets/generate-archive-anchor.py || exit 2
sha256sum fixtures/anchor44100.wav fixtures/archive-anchor.pcm
cp kits/m2-source-packets/archive-main-v2.swift Sources/remote-source-tests/main.swift
mapfile -t flags < <(pkg-config --static --libs libavformat libavcodec libavutil libswscale libswresample | python3 -c 'import shlex,sys; print("\n".join(shlex.split(sys.stdin.read())))')
args=(-Xcc "-I$ff/include")
for flag in "${flags[@]}"; do args+=(-Xlinker "$flag"); done
timeout 300 swift run "${args[@]}" remote-source-tests
```

```swift id=harness
// Proposed archive metadata -> real product decoder integration, local fixture only.
import Foundation
#if os(Linux)
import Glibc
#endif
setbuf(stdout, nil)
import GorAVCore
import GorAVFFmpegAdapter
import GorAVPlaybackCore

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
let fixture = root + "/fixtures/anchor44100.wav"
let independentPCM = try! Data(contentsOf: URL(fileURLWithPath: root + "/fixtures/archive-anchor.pcm"))
let tmp = NSTemporaryDirectory() + "r3srv-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
let serverPy = tmp + "/server.py"
let portFile = tmp + "/port"
let script = """
import http.server, sys, threading, json, time
fixture = sys.argv[1]
portfile = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/metadata/'):
            ident = self.path.split('/')[-1]
            if ident == 'slow': time.sleep(5)
            body = json.dumps({'files': [{'name': 'anchor44100.wav', 'size': '192044'}]}).encode()
            if ident == 'huge': body = b' ' * 9000000
            if ident == 'unknown-length':
                self.send_response(200); self.end_headers()
                try:
                    for _ in range(8): self.wfile.write(b'x'*1024);self.wfile.flush();time.sleep(.01)
                except (BrokenPipeError, ConnectionResetError): pass
                return
            if ident == 'status': self.send_response(503);self.end_headers();return
            self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
            try: self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError): pass
            return
        if self.path in ('/share', '/hop'):
            self.send_response(302)
            self.send_header('Location', '/hop' if self.path == '/share' else '/anchor44100.wav')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.headers.get('X-GorAV-Test') != 'yes' or ('session=abc' not in (self.headers.get('Cookie') or '') or 'other=def' not in (self.headers.get('Cookie') or '')):
            self.send_response(403); self.end_headers(); return
        if self.path != '/download/test/anchor44100.wav':
            self.send_response(404);self.end_headers();return
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
let base = URL(string: "http://127.0.0.1:\(port)")!
func fetch(_ id: String, cap: Int = 8 * 1024 * 1024, cancel: Bool = false) async -> Result<Data, Error> {
    await withCheckedContinuation { continuation in
        do {
            let op = try ArchiveMetadataFetch.start(identifier: id, base: base, timeout: 8, cap: cap) {
                continuation.resume(returning: $0)
            }
            if cancel { op.cancel() }
        } catch { continuation.resume(returning: .failure(error)) }
    }
}
let metadata: Data
switch await fetch("test") {
case .success(let value): metadata = value
case .failure(let error): fatalError("metadata fetch failed: \(error)")
}
let resolved = try! ArchiveItemSource.downloadURL(metadata: metadata, identifier: "test", filename: "anchor44100.wav", base: base)
let url = resolved.absoluteString
check("archive exact metadata file resolved to bounded download path", resolved.path == "/download/test/anchor44100.wav")
func refuses(_ name: String, expected: ArchiveItemSourceError, _ body: () throws -> Void) {
    do { try body(); check(name, false) }
    catch { check(name, (error as? ArchiveItemSourceError) == expected, "\(error)") }
}
refuses("missing file", expected: .missingFile) { _ = try ArchiveItemSource.downloadURL(metadata: metadata, identifier: "test", filename: "missing.wav", base: base) }
refuses("traversal", expected: .invalidFilename) { _ = try ArchiveItemSource.downloadURL(metadata: metadata, identifier: "test", filename: "../tone.wav", base: base) }
refuses("identifier", expected: .invalidIdentifier) { _ = try ArchiveItemSource.downloadURL(metadata: metadata, identifier: "../test", filename: "tone.wav", base: base) }
for bad in ["[]", "{broken"] {
    refuses("bad metadata", expected: .badMetadata) { _ = try ArchiveItemSource.downloadURL(metadata: Data(bad.utf8), identifier: "test", filename: "tone.wav", base: base) }
}
for (name, json, expected) in [
    ("duplicate", "{\"files\":[{\"name\":\"tone.wav\"},{\"name\":\"tone.wav\"}]}", ArchiveItemSourceError.duplicateFile),
    ("private", "{\"files\":[{\"name\":\"tone.wav\",\"private\":true}]}", .privateFile),
    ("dark", "{\"files\":[],\"is_dark\":true}", .unavailable),
    ("nodownload", "{\"files\":[],\"nodownload\":true}", .unavailable)
] {
    refuses(name, expected: expected) { _ = try ArchiveItemSource.downloadURL(metadata: Data(json.utf8), identifier: "test", filename: "tone.wav", base: base) }
}
for route in ["huge", "unknown-length"] {
    let value = await fetch(route, cap: 4096)
    if case .failure(let error) = value { check(route + " exact cap", (error as? ArchiveItemSourceError) == .responseTooLarge) }
    else { check(route + " exact cap", false) }
}
let status = await fetch("status")
if case .failure(let error) = status { check("HTTP503 typed", (error as? ArchiveItemSourceError) == .httpStatus(503)) }
else { check("HTTP503 typed", false) }
let cancelStart = DispatchTime.now().uptimeNanoseconds
let cancelled = await fetch("slow", cancel: true)
let cancelSeconds = Double(DispatchTime.now().uptimeNanoseconds - cancelStart) / 1e9
if case .failure(let error) = cancelled { check("cancel exact URLError.cancelled not timeout", (error as? URLError)?.code == .cancelled && cancelSeconds < 1.0, "\(error) seconds=\(cancelSeconds)") }
else { check("cancel exact URLError.cancelled not timeout", false) }

var storedPCM: [String: Data] = [:]


func probeOpen(withOptions opts: SourceOpenOptions?, epoch: UInt64, input: String? = nil) async -> String {
    let d = FFmpegSoftwareAudioDecoder()
    do { try d.pinLocalRoots([root]) } catch { return "pin \(error)" }
    if let opts { d.remoteOpenOptions = opts }
    let selected = input ?? url
    let src = SourceDescriptor(id: selected, kind: selected.hasPrefix("http") ? .remote : .local, seekable: true)
    do {
        try await d.open(source: src, session: SessionID(uncheckedEpoch: epoch))
    } catch { return "open-error: \(error)" }
    // drain the .opened event
    var seen = "no-event"
    if let ev = await d.nextEvent(session: SessionID(uncheckedEpoch: epoch)), case .opened(let c, let r, let ch, _, _) = ev {
        seen = "\(c) \(r)Hz x\(ch)"
    }
    var fullPCM = Data()
    var bytes = 0, chunks = 0, eof = false
    var digest: UInt64 = 14695981039346656037
    for _ in 0..<10000 {
        guard let event = await d.nextEvent(session: SessionID(uncheckedEpoch: epoch)) else { break }
        switch event {
        case .pcm(let frame):
            fullPCM.append(contentsOf: frame.bytes)
            bytes += frame.bytes.count; chunks += 1
            for b in frame.bytes { digest = (digest ^ UInt64(b)) &* 1099511628211 }
        case .endOfStream: eof = true
        case .failed(let code, _): seen = "decode-failed: \(code)"
        default: break
        }
        if eof { break }
    }
    await d.close(session: SessionID(uncheckedEpoch: epoch))
    storedPCM[selected] = fullPCM
    return "\(seen) bytes=\(bytes) chunks=\(chunks) eof=\(eof) fnv=\(String(digest, radix:16))"
}

let noCred = await probeOpen(withOptions: nil, epoch: 91)
check("S1 remote open without credentials is refused by the server", noCred.hasPrefix("open-error"), noCred)
let withCred = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes"], cookies: ["session": "abc", "other": "def"]), epoch: 92)
let wrongRoute = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes"], cookies: ["session": "abc", "other": "def"]), epoch: 97, input: base.appendingPathComponent("download/wrong/anchor44100.wav").absoluteString)
check("wrong item authenticated request refused not same media", wrongRoute.hasPrefix("open-error"), wrongRoute)
let local = await probeOpen(withOptions: nil, epoch: 96, input: fixture)
print("archive-resolved-remote: \(withCred)")
print("reference-local: \(local)")
check("archive metadata-to-download actual product PCM equals local product decode", withCred == local && withCred.contains("eof=true") && !withCred.contains("bytes=0 "), withCred)

check("stored remote PCM equals independent integer-sample anchor", storedPCM[url] == independentPCM && !independentPCM.isEmpty)
check("stored PCM byte-array identity", storedPCM[url] == storedPCM[fixture] && !(storedPCM[url]?.isEmpty ?? true))
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
print(failures == 0 ? "m2-archive-pcm-v2: all pass" : "remote-source-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
```

```python id=generator
#!/usr/bin/env python3
# Independent PCM oracle: integer stereo samples packed directly, no decoder,
# resampler, FFmpeg, network input or floating-point signal generator involved.
import pathlib,struct,wave,hashlib
root=pathlib.Path('fixtures');root.mkdir(exist_ok=True)
raw=b''.join(struct.pack('<hh', ((i*97)%60001)-30000, -(((i*97)%60001)-30000)) for i in range(44100))
(root/'archive-anchor.pcm').write_bytes(raw)
with wave.open(str(root/'anchor44100.wav'),'wb') as output:
    output.setnchannels(2);output.setsampwidth(2);output.setframerate(44100);output.writeframes(raw)
for name in ('anchor44100.wav','archive-anchor.pcm'):
    data=(root/name).read_bytes();print('ARCHIVE_ORACLE',name,len(data),hashlib.sha256(data).hexdigest())
```

```text id=fixtures1
Generated anchor44100.wav/rawPCM from integer stereo sample formula. Unknown-length8KiB response crosses4096-byte limit after receive; cancellation has exact URLError and1s elapsed bound against8s requesttimeout; wrongitem path404 distinguishes routing.
```
