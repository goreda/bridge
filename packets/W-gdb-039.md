# W-gdb-039 source-open refusal taxonomy vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-039

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
source-open failures must surface as typed refusals (missing file, zero-byte, unsupported codec, corrupt header, truncated moov, timeout, permission) - a generic failure hides the cause from the user and the gate.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/refusal-tests/RefusalTests.swift (sha256 0a52b823; first 50 lines below) and Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift (sha256 abd87be3, whole below).
- real test command: swift run refusal-tests stays green.

## expected behaviour
a vector set mapping each bad-input class to its typed refusal token - never a generic failure, never a partial success; generator creates the synthetic bad inputs; expected token table per input.

## exact call site and interface
the refusal vocabulary in the pinned suite + SourceOpenOptions (excerpts) is asserted.

## behaviour that must not change
existing refusal checks stay green; no real network faults - synthetic inputs only.

## acceptance test (from the product repo)
every vector produces its exact typed token; a genericized failure (negative control) fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/refusal-tests/RefusalTests.swift (sha256 0a52b823, lines 1-50 of 94)
```swift
import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

// (gdb chief MED r7-review) every battery line routes through here: any line
// containing "(BAD)" or ": FAIL" is counted, and the process exit code
// reflects it - a printed BAD can never again ride out on exit 0.
private var badCount = 0
private func out(_ s: String) { Swift.print(s); if s.contains("(BAD)") || s.contains(": FAIL") { badCount += 1 } }

@main

struct RefusalTests {
    static let fx: [UInt8] = [80, 54, 10, 49, 55, 32, 49, 49, 10, 50, 53, 53, 10, 0, 0, 0, 7, 5, 13, 14, 10, 26, 21, 15, 39, 28, 20, 52, 35, 25, 65, 42, 30, 78, 49, 35, 91, 56, 40, 104, 63, 45, 117, 70, 50, 130, 77, 55, 143, 84, 60, 156, 91, 65, 169, 98, 70, 182, 105, 75, 195, 112, 80, 208, 3, 11, 17, 10, 16, 30, 17, 21, 43, 24, 26, 56, 31, 31, 69, 38, 36, 82, 45, 41, 95, 52, 46, 108, 59, 51, 121, 66, 56, 134, 73, 61, 147, 80, 66, 160, 87, 71, 173, 94, 76, 186, 101, 81, 199, 108, 86, 212, 115, 91, 225, 6, 22, 34, 13, 27, 47, 20, 32, 60, 27, 37, 73, 34, 42, 86, 41, 47, 99, 48, 52, 112, 55, 57, 125, 62, 62, 138, 69, 67, 151, 76, 72, 164, 83, 77, 177, 90, 82, 190, 97, 87, 203, 104, 92, 216, 111, 97, 229, 118, 102, 242, 9, 33, 51, 16, 38, 64, 23, 43, 77, 30, 48, 90, 37, 53, 103, 44, 58, 116, 51, 63, 129, 58, 68, 142, 65, 73, 155, 72, 78, 168, 79, 83, 181, 86, 88, 194, 93, 93, 207, 100, 98, 220, 107, 103, 233, 114, 108, 246, 121, 113, 3, 12, 44, 68, 19, 49, 81, 26, 54, 94, 33, 59, 107, 40, 64, 120, 47, 69, 133, 54, 74, 146, 61, 79, 159, 68, 84, 172, 75, 89, 185, 82, 94, 198, 89, 99, 211, 96, 104, 224, 103, 109, 237, 110, 114, 250, 117, 119, 7, 124, 124, 20, 15, 55, 85, 22, 60, 98, 29, 65, 111, 36, 70, 124, 43, 75, 137, 50, 80, 150, 57, 85, 163, 64, 90, 176, 71, 95, 189, 78, 100, 202, 85, 105, 215, 92, 110, 228, 99, 115, 241, 106, 120, 254, 113, 125, 11, 120, 130, 24, 127, 135, 37, 18, 66, 102, 25, 71, 115, 32, 76, 128, 39, 81, 141, 46, 86, 154, 53, 91, 167, 60, 96, 180, 67, 101, 193, 74, 106, 206, 81, 111, 219, 88, 116, 232, 95, 121, 245, 102, 126, 2, 109, 131, 15, 116, 136, 28, 123, 141, 41, 130, 146, 54, 21, 77, 119, 28, 82, 132, 35, 87, 145, 42, 92, 158, 49, 97, 171, 56, 102, 184, 63, 107, 197, 70, 112, 210, 77, 117, 223, 84, 122, 236, 91, 127, 249, 98, 132, 6, 105, 137, 19, 112, 142, 32, 119, 147, 45, 126, 152, 58, 133, 157, 71, 24, 88, 136, 31, 93, 149, 38, 98, 162, 45, 103, 175, 52, 108, 188, 59, 113, 201, 66, 118, 214, 73, 123, 227, 80, 128, 240, 87, 133, 253, 94, 138, 10, 101, 143, 23, 108, 148, 36, 115, 153, 49, 122, 158, 62, 129, 163, 75, 136, 168, 88, 27, 99, 153, 34, 104, 166, 41, 109, 179, 48, 114, 192, 55, 119, 205, 62, 124, 218, 69, 129, 231, 76, 134, 244, 83, 139, 1, 90, 144, 14, 97, 149, 27, 104, 154, 40, 111, 159, 53, 118, 164, 66, 125, 169, 79, 132, 174, 92, 139, 179, 105, 30, 110, 170, 37, 115, 183, 44, 120, 196, 51, 125, 209, 58, 130, 222, 65, 135, 235, 72, 140, 248, 79, 145, 5, 86, 150, 18, 93, 155, 31, 100, 160, 44, 107, 165, 57, 114, 170, 70, 121, 175, 83, 128, 180, 96, 135, 185, 109, 142, 190, 122]
    static let pgm: [UInt8] = [80, 53, 10, 56, 32, 52, 10, 50, 53, 53, 10, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]
    static let junk: [UInt8] = [110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108, 110, 111, 116, 32, 97, 110, 32, 105, 109, 97, 103, 101, 32, 97, 116, 32, 97, 108, 108]
    static let two: [UInt8] = [80, 54, 10, 49, 55, 32, 49, 49, 10, 50, 53, 53, 10, 0, 0, 0, 7, 5, 13, 14, 10, 26, 21, 15, 39, 28, 20, 52, 35, 25, 65, 42, 30, 78, 49, 35, 91, 56, 40, 104, 63, 45, 117, 70, 50, 130, 77, 55, 143, 84, 60, 156, 91, 65, 169, 98, 70, 182, 105, 75, 195, 112, 80, 208, 3, 11, 17, 10, 16, 30, 17, 21, 43, 24, 26, 56, 31, 31, 69, 38, 36, 82, 45, 41, 95, 52, 46, 108, 59, 51, 121, 66, 56, 134, 73, 61, 147, 80, 66, 160, 87, 71, 173, 94, 76, 186, 101, 81, 199, 108, 86, 212, 115, 91, 225, 6, 22, 34, 13, 27, 47, 20, 32, 60, 27, 37, 73, 34, 42, 86, 41, 47, 99, 48, 52, 112, 55, 57, 125, 62, 62, 138, 69, 67, 151, 76, 72, 164, 83, 77, 177, 90, 82, 190, 97, 87, 203, 104, 92, 216, 111, 97, 229, 118, 102, 242, 9, 33, 51, 16, 38, 64, 23, 43, 77, 30, 48, 90, 37, 53, 103, 44, 58, 116, 51, 63, 129, 58, 68, 142, 65, 73, 155, 72, 78, 168, 79, 83, 181, 86, 88, 194, 93, 93, 207, 100, 98, 220, 107, 103, 233, 114, 108, 246, 121, 113, 3, 12, 44, 68, 19, 49, 81, 26, 54, 94, 33, 59, 107, 40, 64, 120, 47, 69, 133, 54, 74, 146, 61, 79, 159, 68, 84, 172, 75, 89, 185, 82, 94, 198, 89, 99, 211, 96, 104, 224, 103, 109, 237, 110, 114, 250, 117, 119, 7, 124, 124, 20, 15, 55, 85, 22, 60, 98, 29, 65, 111, 36, 70, 124, 43, 75, 137, 50, 80, 150, 57, 85, 163, 64, 90, 176, 71, 95, 189, 78, 100, 202, 85, 105, 215, 92, 110, 228, 99, 115, 241, 106, 120, 254, 113, 125, 11, 120, 130, 24, 127, 135, 37, 18, 66, 102, 25, 71, 115, 32, 76, 128, 39, 81, 141, 46, 86, 154, 53, 91, 167, 60, 96, 180, 67, 101, 193, 74, 106, 206, 81, 111, 219, 88, 116, 232, 95, 121, 245, 102, 126, 2, 109, 131, 15, 116, 136, 28, 123, 141, 41, 130, 146, 54, 21, 77, 119, 28, 82, 132, 35, 87, 145, 42, 92, 158, 49, 97, 171, 56, 102, 184, 63, 107, 197, 70, 112, 210, 77, 117, 223, 84, 122, 236, 91, 127, 249, 98, 132, 6, 105, 137, 19, 112, 142, 32, 119, 147, 45, 126, 152, 58, 133, 157, 71, 24, 88, 136, 31, 93, 149, 38, 98, 162, 45, 103, 175, 52, 108, 188, 59, 113, 201, 66, 118, 214, 73, 123, 227, 80, 128, 240, 87, 133, 253, 94, 138, 10, 101, 143, 23, 108, 148, 36, 115, 153, 49, 122, 158, 62, 129, 163, 75, 136, 168, 88, 27, 99, 153, 34, 104, 166, 41, 109, 179, 48, 114, 192, 55, 119, 205, 62, 124, 218, 69, 129, 231, 76, 134, 244, 83, 139, 1, 90, 144, 14, 97, 149, 27, 104, 154, 40, 111, 159, 53, 118, 164, 66, 125, 169, 79, 132, 174, 92, 139, 179, 105, 30, 110, 170, 37, 115, 183, 44, 120, 196, 51, 125, 209, 58, 130, 222, 65, 135, 235, 72, 140, 248, 79, 145, 5, 86, 150, 18, 93, 155, 31, 100, 160, 44, 107, 165, 57, 114, 170, 70, 121, 175, 83, 128, 180, 96, 135, 185, 109, 142, 190, 122, 80, 54, 10, 49, 55, 32, 49, 49, 10, 50, 53, 53, 10, 0, 0, 0, 7, 5, 13, 14, 10, 26, 21, 15, 39, 28, 20, 52, 35, 25, 65, 42, 30, 78, 49, 35, 91, 56, 40, 104, 63, 45, 117, 70, 50, 130, 77, 55, 143, 84, 60, 156, 91, 65, 169, 98, 70, 182, 105, 75, 195, 112, 80, 208, 3, 11, 17, 10, 16, 30, 17, 21, 43, 24, 26, 56, 31, 31, 69, 38, 36, 82, 45, 41, 95, 52, 46, 108, 59, 51, 121, 66, 56, 134, 73, 61, 147, 80, 66, 160, 87, 71, 173, 94, 76, 186, 101, 81, 199, 108, 86, 212, 115, 91, 225, 6, 22, 34, 13, 27, 47, 20, 32, 60, 27, 37, 73, 34, 42, 86, 41, 47, 99, 48, 52, 112, 55, 57, 125, 62, 62, 138, 69, 67, 151, 76, 72, 164, 83, 77, 177, 90, 82, 190, 97, 87, 203, 104, 92, 216, 111, 97, 229, 118, 102, 242, 9, 33, 51, 16, 38, 64, 23, 43, 77, 30, 48, 90, 37, 53, 103, 44, 58, 116, 51, 63, 129, 58, 68, 142, 65, 73, 155, 72, 78, 168, 79, 83, 181, 86, 88, 194, 93, 93, 207, 100, 98, 220, 107, 103, 233, 114, 108, 246, 121, 113, 3, 12, 44, 68, 19, 49, 81, 26, 54, 94, 33, 59, 107, 40, 64, 120, 47, 69, 133, 54, 74, 146, 61, 79, 159, 68, 84, 172, 75, 89, 185, 82, 94, 198, 89, 99, 211, 96, 104, 224, 103, 109, 237, 110, 114, 250, 117, 119, 7, 124, 124, 20, 15, 55, 85, 22, 60, 98, 29, 65, 111, 36, 70, 124, 43, 75, 137, 50, 80, 150, 57, 85, 163, 64, 90, 176, 71, 95, 189, 78, 100, 202, 85, 105, 215, 92, 110, 228, 99, 115, 241, 106, 120, 254, 113, 125, 11, 120, 130, 24, 127, 135, 37, 18, 66, 102, 25, 71, 115, 32, 76, 128, 39, 81, 141, 46, 86, 154, 53, 91, 167, 60, 96, 180, 67, 101, 193, 74, 106, 206, 81, 111, 219, 88, 116, 232, 95, 121, 245, 102, 126, 2, 109, 131, 15, 116, 136, 28, 123, 141, 41, 130, 146, 54, 21, 77, 119, 28, 82, 132, 35, 87, 145, 42, 92, 158, 49, 97, 171, 56, 102, 184, 63, 107, 197, 70, 112, 210, 77, 117, 223, 84, 122, 236, 91, 127, 249, 98, 132, 6, 105, 137, 19, 112, 142, 32, 119, 147, 45, 126, 152, 58, 133, 157, 71, 24, 88, 136, 31, 93, 149, 38, 98, 162, 45, 103, 175, 52, 108, 188, 59, 113, 201, 66, 118, 214, 73, 123, 227, 80, 128, 240, 87, 133, 253, 94, 138, 10, 101, 143, 23, 108, 148, 36, 115, 153, 49, 122, 158, 62, 129, 163, 75, 136, 168, 88, 27, 99, 153, 34, 104, 166, 41, 109, 179, 48, 114, 192, 55, 119, 205, 62, 124, 218, 69, 129, 231, 76, 134, 244, 83, 139, 1, 90, 144, 14, 97, 149, 27, 104, 154, 40, 111, 159, 53, 118, 164, 66, 125, 169, 79, 132, 174, 92, 139, 179, 105, 30, 110, 170, 37, 115, 183, 44, 120, 196, 51, 125, 209, 58, 130, 222, 65, 135, 235, 72, 140, 248, 79, 145, 5, 86, 150, 18, 93, 155, 31, 100, 160, 44, 107, 165, 57, 114, 170, 70, 121, 175, 83, 128, 180, 96, 135, 185, 109, 142, 190, 122]

    static func run(_ name: String, _ bytes: [UInt8], _ sha: String, _ body: (ImmutableInputSnapshot) async -> String) async {
        guard let snap = ImmutableInputSnapshot(pinned: bytes, expectedBytes: bytes.count, sha256Hex: sha) else {
            out("\(name): PIN_REFUSED"); return
        }
        let result = await body(snap); out("\(name): " + result)
    }

    static func decodeOnce(_ snap: ImmutableInputSnapshot, epoch: UInt64) async -> String {
        let d = FFmpegSoftwareDecoder()
        let sid = SessionID(uncheckedEpoch: epoch)
        do { try await d.openSnapshot(snap, session: sid) } catch { return "OPEN_THROW: \(error)" }
        var out: [String] = []
        while let ev = await d.nextEvent(session: sid) {
            switch ev {
            case .opened(let c, let w, let h): out.append("opened(\(c),\(w)x\(h))")
            case .frameDecoded(let f):
                let dg = await d.frameDigest(handle: f.handle, session: sid) ?? "nil"
                out.append("frame(\(f.width)x\(f.height),\(f.pixelFormatName),key=\(f.isKeyFrame),digest=\(dg))")
                await d.releaseFrame(handle: f.handle, session: sid)
            case .endOfStream: out.append("eos")
            case .failed(let c, let s): out.append("failed(\(c),\(s))")
            case .interrupted(let s): out.append("interrupted(\(s))")
            case .feedSaturated(let n): out.append("feedSaturated(\(n))")
            }
        }
        _ = await d.closeAndReport(session: sid)
        return out.joined(separator: " | ")
    }

    static func main() async {
        // T1: tampered pin - fixture bytes, bogus sha
```

### Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift (sha256 abd87be3, lines 1-113 of 113)
```swift
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

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
