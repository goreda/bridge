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
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
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
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVFFmpegAdapter/",
   "kits/loopback-server/"
  ],
  "return_form": "patch"
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
