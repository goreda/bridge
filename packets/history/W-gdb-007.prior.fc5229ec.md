# W-gdb-007 B7 HTTP range/reconnect provider on synthetic server (rewrites W-0286)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-007

```packet-json
{
  "packet_id": "W-gdb-007",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
  "touched_files": [
    {
      "path": "Sources/GorAVFFmpegAdapter/SnapshotAVIOOwner.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "read: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32; seek: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64",
    "types": "SnapshotAVIOBridge trampolines -> SnapshotAVIOBox.readPacket/seek; distinct AVERROR_EOF vs AVERROR(EINVAL) signals, never bare 0",
    "ownership_lifetime": "opaque = retained SnapshotAVIOBox via Unmanaged; AVIO buffer ownership per the pinned public FFmpeg 8.0 source note in SnapshotInput.swift",
    "caller": "avformat AVIO layer (the pinned FFmpeg 8.0 kit)",
    "callee": "SnapshotAVIOBridge.read/seek @convention(c) trampolines -> SnapshotAVIOBox.readPacket/seek"
  },
  "test": {
    "command": "swift run remote-source-tests && swift run audio-interrupt-tests",
    "expected": "exit 0 for both; final lines 'remote-source-tests: 13 PASS, 0 FAIL' and 'audio-interrupt-tests: 23 PASS, 0 FAIL'; new scripted range/reconnect legs add PASS rows; a range-ignoring server yields the typed fallback row, never a counted-success full re-download",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/GorAVFFmpegAdapter/",
      "kits/loopback-server/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/remote-source-tests/main.swift",
        "block": "rf0"
      },
      {
        "path": "Sources/audio-interrupt-tests/main.swift",
        "block": "rf1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a359f7b38cc0e6c4974661d85f389ef6041b1f",
    "command": "swift run remote-source-tests && swift run audio-interrupt-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:39:46.301231+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "audio-interrupt-tests: all pass",
    "inline_files": [
      {
        "path": "Sources/remote-source-tests/main.swift",
        "block": "rf0",
        "sha256": "b7bfea6247706c227449110ab72eee88b3ddba2fa72370187517dfbc73718128"
      },
      {
        "path": "Sources/audio-interrupt-tests/main.swift",
        "block": "rf1",
        "sha256": "9738d9fbffaf9f0a0ce062a29a4bff19d80658128a8853f2113cefe86887c2fb"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "7c4ff21d7134a8cdfba0cac8038a5cebaec997ae3229a960a1d55ff59b74787d",
    "last_5_lines": [
      "PASS D5 interrupted named plainly",
      "PASS D5 no credential or URL leak",
      "PASS D6 invalid options refused",
      "PASS D7 plain remote open decodes wav",
      "audio-interrupt-tests: all pass"
    ],
    "receipt_sha256": "278766d3d6ab9a758ad76bd78fc364614cb078ea85b8732f52d5bc826712f577"
  }
}
```

## problem (what fails for the user)
remote sources over HTTP need range/reconnect/cancel/seek/backpressure handling provider-side; without it a seek on a remote file re-downloads from byte zero or stalls, and a dropped connection kills playback instead of resuming. the existing suites cover interrupt/deadline and redaction, not range semantics.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav).
- real source: Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift (sha256 1ad7c017, 139532B) - provider incl. pinLocalRoots and open admission; Sources/GorAVFFmpegAdapter/SnapshotAVIOOwner.swift (sha256 f18d8732, 1505B) - AVIO snapshot owner; Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift (sha256 abd87be3, 5916B) - open options; Sources/GorAVFFmpegAdapter/SnapshotInput.swift (sha256 60e41cf9) - the AVIO read/seek callback bodies (excerpt below).
- real test command: swift run remote-source-tests + swift run audio-interrupt-tests (13 + 23 PASS on Linux with the http/tcp-enabled pinned kit).

## expected behaviour
provider-side range request/reconnect/cancel/seek/backpressure behavior on avformat with capability signaling, driven against a synthetic scripted server (dribble, range honored/ignored, drop mid-body); redaction and credential-free diagnostics stay exact.

## exact call site and interface
the AVIO read/seek callbacks owned by SnapshotAVIOOwner + SourceOpenOptions (pinned files); the synthetic server interface follows the existing python loopback suites.

## pinned ABI decisions (integrator, 2026-11-15)
the AVIO callback ABI is SnapshotAVIOBridge (Sources/GorAVFFmpegAdapter/SnapshotInput.swift, sha256 60e41cf9; excerpt appended below):
- read: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 - >0 = bytes copied, clamped to the pinned length; pinned-data end = AVERROR_EOF via gorav_av_err_eof(); nil/invalid callback state = AVERROR(EINVAL) via gorav_av_err_einval(); distinct signals, never bare 0.
- seek: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 - SEEK_SET/CUR/END bounds-checked (negative/past-end rejected); AVSEEK_SIZE returns the total length WITHOUT moving; any other whence explicitly rejected; failures EINVAL.
SnapshotAVIOOwner.swift (excerpt above) installs (read, nil, seek) into the AVIO context; capability signaling rides SourceOpenOptions (excerpt above). the synthetic-server legs drive range/reconnect THROUGH this callback pair.

## behaviour that must not change
local file behavior; the 13+23 existing checks; credential redaction; no live external endpoint, ever.

## acceptance test (from the product repo)
new scripted-server legs pass on Linux; a server that ignores range produces the typed fallback (not a silent full re-download counted as success); existing suites stay green.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVFFmpegAdapter/SnapshotAVIOOwner.swift (sha256 f18d8732, lines 1-37 of 37)
```swift id=source1
// AUTHORED NEW, SOURCE ONLY / NOT_RUN. Owns custom IO, not AVFormatContext.
import Foundation
import CFFmpeg

final class SnapshotAVIOOwner {
    private(set) var io: UnsafeMutablePointer<AVIOContext>?
    private var opaque: UnsafeMutableRawPointer?

    init(snapshot: ImmutableInputSnapshot) throws {
        let retained = Unmanaged.passRetained(SnapshotAVIOBox(snapshot: snapshot))
        let pointer = retained.toOpaque()
        guard let allocation = av_malloc(4096) else {
            retained.release()
            throw FFmpegSoftwareDecoder.OpenError.rejected("custom IO buffer allocation failed")
        }
        let buffer = allocation.assumingMemoryBound(to: UInt8.self)
        guard let context = avio_alloc_context(buffer, 4096, 0, pointer,
                                               SnapshotAVIOBridge.read, nil, SnapshotAVIOBridge.seek) else {
            av_free(allocation) // no context took ownership
            retained.release()
            throw FFmpegSoftwareDecoder.OpenError.rejected("custom IO context allocation failed")
        }
        io = context
        opaque = pointer
    }

    // Must run only after the owning format stopped using pb/callbacks.
    // Same serialized native queue as open/nextEvent/close; no host-thread proof.
    func close() {
        gorav_free_custom_avio(&io)
        if let pointer = opaque {
            opaque = nil
            Unmanaged<SnapshotAVIOBox>.fromOpaque(pointer).release()
        }
    }
    deinit { close() }
}
```

### Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift (sha256 abd87be3, lines 1-113 of 113)
```swift id=source2
import Foundation
import GorAVCore
import CFFmpeg

// R3 (arch-195b): production open options for admitted remote source classes
// (http/https per AdmissionTable) plus URL redaction for every string that can
// reach a log or an error. Credentials and query values never leave this file
// in plaintext form.

/// Per-open transport options for remote (scheme-gated) sources. Local opens
/// ignore this value entirely.
public struct SourceOpenOptions: Equatable, Sendable {
    /// Extra HTTP request headers (e.g. Authorization). Keys and values are
    /// emitted verbatim into the request; they are SECRETS-ADJACENT and are
    /// never included in redactedSummary.
    public var headers: [String: String]
    /// HTTP cookies as name=value pairs.
    public var cookies: [String: String]
    /// 195b-54: optional per-open deadline in seconds, bounding the remote
    /// open + stream-info phase only (streaming reads answer cancellation
    /// instead). nil means no deadline. Must be finite, > 0 and <= 86400.
    public var openDeadlineSeconds: Double?
    public init(headers: [String: String] = [:], cookies: [String: String] = [:], openDeadlineSeconds: Double? = nil) {
        self.headers = headers
        self.cookies = cookies
        self.openDeadlineSeconds = openDeadlineSeconds
    }
    /// Log-safe description: counts and presence only, never keys or values.
    public var redactedSummary: String {
        "headers=\(headers.count) cookies=\(cookies.count) deadline=\(openDeadlineSeconds == nil ? "none" : "armed")"
    }
    /// Monotonic-nanosecond deadline for the interrupt box, from `now`.
    /// Validation bounds the value at 86400 s, so the addition cannot wrap.
    func openDeadlineNanos(from now: DispatchTime = .now()) -> UInt64? {
        guard let seconds = openDeadlineSeconds else { return nil }
        return now.uptimeNanoseconds + UInt64(seconds * 1e9)
    }
}

/// Typed validation failures for remote open options (195b-54).
public enum SourceOpenOptionsError: Error, Equatable, Sendable {
    case headerInjection
    case cookieInjection
    case cookieHeaderConflict
    case deadlineInvalid
}

extension SourceOpenOptions {
    /// 195b-54: validate a per-open copy BEFORE any network access, mirroring
    /// the transport backstop's rules in goravR3OpenInput so the caller gets
    /// a typed refusal instead of a bare -22 from the C boundary. The
    /// returned value is intended to be captured and held immutable for the
    /// whole open attempt.
    public func validatedForOpen() throws -> SourceOpenOptions {
        let forbidden = CharacterSet(charactersIn: "\r\n\0")
        guard headers.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(":") && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else {
            throw SourceOpenOptionsError.headerInjection
        }
        guard cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else {
            throw SourceOpenOptionsError.cookieInjection
        }
        if !cookies.isEmpty {
            guard !headers.keys.contains(where: { $0.lowercased() == "cookie" }) else {
                throw SourceOpenOptionsError.cookieHeaderConflict
            }
        }
        if let deadline = openDeadlineSeconds {
            guard deadline.isFinite, deadline > 0, deadline <= 86400 else {
                throw SourceOpenOptionsError.deadlineInvalid
            }
        }
        return self
    }
}

/// Error-safe source label. Never retain URL components: paths and even query
/// keys can contain credentials, including malformed or percent-encoded ones.
public enum URLRedaction {
    public static func redact(_ raw: String) -> String {
        "REDACTED"
    }
}

/// Opens a remote source with the transport options applied. The option
/// dictionary is built, consumed and freed on the C side (AVDictionary is
/// not Swift-importable); this wrapper only joins and passes the strings.
/// Local opens never reach here - callers keep the plain open path.
func goravR3OpenInput(_ ctx: UnsafeMutablePointer<UnsafeMutablePointer<AVFormatContext>?>, url: String, options: SourceOpenOptions) -> Int32 {
    // Refuse CR/LF/NUL injection before C string transport; never log secret values.
    let forbidden = CharacterSet(charactersIn: "\r\n\0")
    guard options.headers.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(":") && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }),
          options.cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else { return -22 }
    var lines = options.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
    // FFmpeg's cookies option expects Set-Cookie response syntax, not a Cookie
    // request field. Serialize the request explicitly, retaining every pair.
    if !options.cookies.isEmpty {
        guard !options.headers.keys.contains(where: { $0.lowercased() == "cookie" }) else { return -22 }
        lines.append("Cookie: " + options.cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))
    }
    let headers: String? = lines.isEmpty ? nil : lines.joined(separator: "\r\n") + "\r\n"
    let cookies: String? = nil
    func withOpt(_ s: String?, _ body: (UnsafePointer<CChar>?) -> Int32) -> Int32 {
        guard let s else { return body(nil) }
        return s.withCString { body($0) }
    }
    return url.withCString { urlC in
        withOpt(headers) { hC in
            withOpt(cookies) { cC in
                gorav_r3_open_input(ctx, urlC, hC, cC)
            }
        }
    }
}
```

### Sources/GorAVFFmpegAdapter/SnapshotInput.swift (sha256 60e41cf9, lines 110-165 of 218)
```swift id=source99
    /// AVIO read_packet contract (r3 fix 2 - distinct signals, never bare 0):
    ///   - bytes copied > 0: normal read, clamped to the pinned length (the
    ///     provider can never observe bytes beyond the pinned content);
    ///   - end of pinned data: AVERROR_EOF via gorav_av_err_eof() (shim r8);
    ///   - invalid callback state (nil pointers, non-positive size): a SEPARATE
    ///     error, AVERROR(EINVAL) via PROPOSED gorav_av_err_einval() shim delta.
    /// Immutable snapshot => no I/O error path exists at this layer.
    func readPacket(_ dst: UnsafeMutablePointer<UInt8>?, _ bufSize: Int32) -> Int32 {
        guard let dst = dst, bufSize > 0 else { return gorav_av_err_einval() }
        lock.lock(); defer { lock.unlock() }
        let remaining = snapshot.bytes.count - offset
        guard remaining > 0 else { return gorav_av_err_eof() } // pinned-data EOF
        let n = min(Int(bufSize), remaining)
        snapshot.bytes.withUnsafeBytes { src in
            dst.update(from: src.bindMemory(to: UInt8.self).baseAddress!.advanced(by: offset), count: n)
        }
        offset += n
        return Int32(n)
    }

    /// AVIO seek contract: SEEK_SET/CUR/END with checked bounds (negative or
    /// past-end targets rejected, no force); AVSEEK_SIZE returns the total
    /// snapshot length WITHOUT moving the offset; every other whence is an
    /// explicit rejection. All failures return AVERROR(EINVAL) via the PROPOSED
    /// shim delta. SEEK_* importer types and AVERROR mapping are UNVERIFIED
    /// against pinned headers.
    func seek(_ off: Int64, _ whence: Int32) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let count = Int64(snapshot.bytes.count)
        if whence == AVSEEK_SIZE { return count }
        let base: Int64
        switch whence {
        case SEEK_SET: base = 0
        case SEEK_CUR: base = Int64(offset)
        case SEEK_END: base = count
        default: return Int64(gorav_av_err_einval()) // unsupported whence: explicit
        }
        let (target, overflow) = base.addingReportingOverflow(off)
        guard !overflow, target >= 0, target <= count else { return Int64(gorav_av_err_einval()) }
        offset = Int(target)
        return target
    }
}

/// C-interop trampoline surface (PROPOSED). Opaque is a RETAINED SnapshotAVIOBox.
/// r3 fix 2: nil opaque is invalid state -> EINVAL, never conflated with EOF.
enum SnapshotAVIOBridge {
    static let read: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = { opaque, buf, size in
        guard let opaque = opaque else { return gorav_av_err_einval() }
        return Unmanaged<SnapshotAVIOBox>.fromOpaque(opaque).takeUnretainedValue().readPacket(buf, size)
    }
    static let seek: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 = { opaque, off, whence in
        guard let opaque = opaque else { return Int64(gorav_av_err_einval()) }
        return Unmanaged<SnapshotAVIOBox>.fromOpaque(opaque).takeUnretainedValue().seek(off, whence)
    }
}
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```python id=fixtures1
scenarios = {"range-honored": {"206": True, "dribble": None}, "range-ignored-full-200": {"206": False, "fallback": "typed-full-reload-flagged"}, "drop-mid-body": {"cut_at": 0.5, "expect": "reconnect-range-resume"}}
# each scenario behind one typed switch with a request log; loopback only, no external endpoints
```





```text id=rf0
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

```

```text id=rf1
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

```

```text id=actual_run_log
Building for debugging...
[0/14] Write sources
[5/14] Compiling GorAVCAtomics gorav_atomics.c
[6/14] Write swift-version--6630B1A18289934C.txt
[8/17] Emitting module GorAVCore
[9/17] Compiling GorAVCore AdmissionTable.swift
[10/17] Compiling GorAVCore Boundary.swift
[11/18] Compiling GorAVCore OpenURLRouter.swift
[12/19] Wrapping AST for GorAVCore for debugging
[14/23] Emitting module GorAVNativeProbeKit
[15/25] Compiling GorAVNativeProbeKit NativeProbe.swift
[16/25] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[17/25] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[18/25] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[19/25] Compiling GorAVNativeProbeKit LeaseTable.swift
[20/26] Wrapping AST for GorAVNativeProbeKit for debugging
[22/49] Emitting module GorAVPlaybackCore
[23/49] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[24/49] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[25/49] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[26/49] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[27/49] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[28/49] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[29/49] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[30/49] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[31/49] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[32/49] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[33/49] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[34/49] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[35/49] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[36/49] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[37/49] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[38/49] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[39/49] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[40/49] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[41/49] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[42/49] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[43/49] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[44/49] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:215:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
213 |     @discardableResult
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:216:46: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
214 |     public func close(drainBudgetNanoseconds: UInt64 = 2_000_000_000) async -> CloseReport {
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
    |                                              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
217 |         lock.unlock()
218 | 

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:217:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
215 |         lock.lock()
216 |         if let report = latchedReport { lock.unlock(); return report }
217 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
218 | 
219 |         store.close()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:223:18: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
221 |         let deadline = DispatchTime.now().uptimeNanoseconds &+ drainBudgetNanoseconds
222 |         while true {
223 |             lock.lock()
    |                  `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:225:18: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
223 |             lock.lock()
224 |             let inFlight = inFlightDecoderReleases
225 |             lock.unlock()
    |                  `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
226 |             if inFlight == 0 || DispatchTime.now().uptimeNanoseconds >= deadline { break }
227 |             try? await Task.sleep(nanoseconds: 1_000_000)

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:230:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
228 |         }
229 | 
230 |         lock.lock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
231 |         var report = CloseReport()
232 |         report.retainedTotal = retainedTotal

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:238:14: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
236 |         report.undrainedDecoderReleases = inFlightDecoderReleases
237 |         latchedReport = report
238 |         lock.unlock()
    |              `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
239 |         return report
240 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:251:23: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
249 |         Task {
250 |             await decoder.releaseFrame(handle: handle, session: session)
251 |             self.lock.lock()
    |                       `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/DecodedFrameLeaseBridge.swift:253:23: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
251 |             self.lock.lock()
252 |             self.inFlightDecoderReleases -= 1
253 |             self.lock.unlock()
    |                       `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
254 |         }
255 |     }

/tmp/packet-proof-t4oyzaj3/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[45/70] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[46/70] Compiling GorAVPlaybackCore Lane0Contract.swift
[47/70] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[48/70] Compiling GorAVPlaybackCore ObservationSurface.swift
[49/70] Compiling GorAVPlaybackCore PlayArguments.swift
[50/70] Compiling GorAVPlaybackCore PlaybackCore.swift
[51/70] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[52/70] Compiling GorAVPlaybackCore PlayheadObservers.swift
[53/70] Compiling GorAVPlaybackCore PlayheadPosition.swift
[54/70] Compiling GorAVPlaybackCore PreparedAdoption.swift
[55/70] Compiling GorAVPlaybackCore PreparedShotSession.swift
[56/70] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[57/70] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[58/70] Compiling GorAVPlaybackCore RenderGraph.swift
[59/70] Compiling GorAVPlaybackCore SPSC.swift
[60/70] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[61/70] Compiling GorAVPlaybackCore StageGeometry.swift
[62/70] Compiling GorAVPlaybackCore TapCropDetector.swift
[63/70] Compiling GorAVPlaybackCore TimingLedger.swift
[64/70] Compiling GorAVPlaybackCore UniformPacking.swift
[65/70] Compiling GorAVPlaybackCore WindowModePlan.swift
[66/71] Wrapping AST for GorAVPlaybackCore for debugging
[68/79] Emitting module GorAVFFmpegAdapter
[69/79] Compiling GorAVFFmpegAdapter ActiveTransportSnapshot.swift
[70/79] Compiling GorAVFFmpegAdapter FFmpegSoftwareAudioDecoder.swift
[71/79] Compiling GorAVFFmpegAdapter FFmpegSoftwareDecoder.swift
[72/79] Compiling GorAVFFmpegAdapter FrameObservation.swift
[73/79] Compiling GorAVFFmpegAdapter L3AVCoordinator.swift
[74/79] Compiling GorAVFFmpegAdapter L3Admission.swift
[75/79] Compiling GorAVFFmpegAdapter L3HardwareDecode.swift
[76/85] Compiling GorAVFFmpegAdapter L3PixelConvert.swift
[77/85] Compiling GorAVFFmpegAdapter L3SampleConvert.swift
[78/85] Compiling GorAVFFmpegAdapter MediaInventory.swift
[79/85] Compiling GorAVFFmpegAdapter SnapshotAVIOOwner.swift
[80/85] Compiling GorAVFFmpegAdapter SnapshotInput.swift
[81/85] Compiling GorAVFFmpegAdapter SourceOpenOptions.swift
[82/86] Wrapping AST for GorAVFFmpegAdapter for debugging
[84/88] Compiling remote_source_tests main.swift
[85/88] Emitting module remote_source_tests
[86/89] Wrapping AST for remote-source-tests for debugging
[87/89] Write Objects.LinkFileList
[88/89] Linking remote-source-tests
Build of product 'remote-source-tests' complete! (15.47s)
[http @ 0x7ff330003680] HTTP error 403 Forbidden
[tcp @ 0x7ff3300053c0] Connection to tcp://127.0.0.1:1 failed: Connection refused
PASS U1 userinfo redacted
PASS U2 query values and keys redacted
PASS U3 fragment and path redacted
PASS U4 local path not exposed
PASS U6 malformed credential redacted
PASS U7 encoded credential redacted
PASS U5 summary counts only
PASS S0 server started on 127.0.0.1:40685
PASS S1 remote open without credentials is refused by the server
PASS S2 remote open with header+cookie decodes wav stream
PASS S2b header newline injection refused
PASS S3 error redacts userinfo and query
PASS S4 non-admitted scheme refused
remote-source-tests: all pass
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-t4oyzaj3/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-t4oyzaj3/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/ASSTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SRTTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-t4oyzaj3/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
[0/1] Planning build
Building for debugging...
[0/5] Write sources
[1/9] Write swift-version--6630B1A18289934C.txt
[3/7] Emitting module audio_interrupt_tests
[4/7] Compiling audio_interrupt_tests main.swift
[5/8] Wrapping AST for audio-interrupt-tests for debugging
[6/8] Write Objects.LinkFileList
[7/8] Linking audio-interrupt-tests
Build of product 'audio-interrupt-tests' complete! (1.64s)
PASS V1 valid options validate
PASS V2 zero deadline refused
PASS V3 negative deadline refused
PASS V4 non-finite deadline refused
PASS V5 header CR/LF injection refused typed
PASS V6 cookie CR/LF injection refused typed
PASS V7 cookie/header conflict refused typed
PASS V8 summary stays credential-free
PASS V9 no deadline by default
PASS D0 server started on 127.0.0.1:33505
PASS D1 cancel blocked open throws interrupted
PASS D1 bounded wait (server delay is 20s)
PASS D1 diagnostics credential-free
PASS D2 deadline exceeded error
PASS D2 bounded wait
PASS D3 deadline exceeded on dribble
PASS D3 bounded wait
PASS D4 next session opens after cancelled attempt
PASS D4 stale-session interrupt is a fenced no-op
PASS D5 interrupted named plainly
PASS D5 no credential or URL leak
PASS D6 invalid options refused
PASS D7 plain remote open decodes wav
audio-interrupt-tests: all pass
```
