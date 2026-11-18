# W-gdb-199i-in2tinct-36 - Cookie value semicolon injects an undeclared header pair

state: FIX PROPOSED / verified Swift 6.0.3 Linux (-Onone and -O)
lab: in2tinct

SourceOpenOptions.validatedForOpen and the goravR3OpenInput backstop must refuse ';' inside cookie values, because the serializer joins pairs with '; ' and the C shim adds no validation. Preserve key rules, CR/LF/NUL refusal, the cookie/header conflict and the deadline rules.

CALLER SCOPE: validatedForOpen runs at FFmpegSoftwareDecoder.swift:759 (shipping remote video open) and FFmpegSoftwareAudioDecoder.swift:310 (shipping remote audio open); the serializer goravR3OpenInput runs at FFmpegSoftwareDecoder.swift:814, FFmpegSoftwareAudioDecoder.swift:341 and MediaInventory.swift:121, the last reachable from MediaInventory.load at MediaInventory.swift:101 with no prior typed validation. The C shim gorav_r3_open_input performs no cookie validation, so these two Swift predicates are the only injection fence. Defensive input-validation hardening; not an observed live incident.

Selected production declarations are extracted verbatim at compile time from the listed complete pinned source. No algorithm rewrite or model is compiled. This is an isolated shipping-path semantic proof, not the full FFmpeg module.

VERIFICATION (actual runs, Swift 6.0.3 Linux):
- pinned -Onone: compile_exit=0, semantic_exit=1
- pinned -O: compile_exit=0, semantic_exit=1
- fixed -Onone: compile_exit=0, semantic_exit=0
- fixed -O: compile_exit=0, semantic_exit=0

FIX: Refuse ';' inside cookie values in validatedForOpen and in the mirrored goravR3OpenInput backstop, so one declared cookie can no longer serialize into an extra undeclared pair; keys, CR/LF/NUL, conflict and deadline rules unchanged.

Native AppKit, Metal, camera capture, network, actual FFmpeg opens, process launch, font rendering and UI are NOT_RUN.

REPRODUCE from the packet materialized root: set SWIFTC to a Swift compiler, then `python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.py` for the pinned run, `GOR_SOURCE_ROOT=$PWD/fixed python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.py` for the fixed run, adding `SWIFTFLAGS=-O` for the optimized run. Missing compiler exits 77 NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199i-in2tinct-36",
  "lab": "in2tinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "SourceOpenOptions.validatedForOpen refuses ';' inside cookie values, and the mirrored goravR3OpenInput backstop refuses the same before C string transport. Keys, CR/LF/NUL, the cookie/header conflict and the deadline rules are unchanged. validatedForOpen runs at FFmpegSoftwareDecoder.swift:759 (shipping remote video open) and FFmpegSoftwareAudioDecoder.swift:310 (shipping remote audio open); the serializer goravR3OpenInput runs at FFmpegSoftwareDecoder.swift:814, FFmpegSoftwareAudioDecoder.swift:341 and MediaInventory.swift:121, the last reachable from MediaInventory.load at MediaInventory.swift:101 with no prior typed validation. The C shim gorav_r3_open_input performs no cookie validation, so these two Swift predicates are the only injection fence. Defensive input-validation hardening; not an observed live incident.",
    "ownership_lifetime": "Only the listed production source and its own tests.",
    "caller": "validatedForOpen runs at FFmpegSoftwareDecoder.swift:759 (shipping remote video open) and FFmpegSoftwareAudioDecoder.swift:310 (shipping remote audio open); the serializer goravR3OpenInput runs at FFmpegSoftwareDecoder.swift:814, FFmpegSoftwareAudioDecoder.swift:341 and MediaInventory.swift:121, the last reachable from MediaInventory.load at MediaInventory.swift:101 with no prior typed validation. The C shim gorav_r3_open_input performs no cookie validation, so these two Swift predicates are the only injection fence. Defensive input-validation hardening; not an observed live incident.",
    "callee": "archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.py   (pinned);   GOR_SOURCE_ROOT=<packet root>/fixed python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.py   (fixed);   add SWIFTFLAGS=-O for the optimized run; set SWIFTC to the compiler path",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Pinned source: compile_exit=0 then RED (semantic_exit=1). Fixed source: compile_exit=0 then GREEN (semantic_exit=0). Both verified in -Onone and -O under Swift 6.0.3 Linux."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199i-in2tinct-36",
    "paths": [
      "archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
      "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.py",
      "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
        "block": "source1",
        "sha256": "abd87be3380ff8abf503b36c86873f9da94cf2c1e6959d8226ac7d9b342a6180",
        "read_only_dependency": false,
        "role": "Pinned production source at the base pin."
      },
      {
        "path": "archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift (fixed)",
        "block": "fixed_source",
        "sha256": "456d7f6f9ca28e9392147282885b7081d1d8ae2ccf6135efa74a6bd811100fe2",
        "role": "Same production file with only the minimal fix applied."
      },
      {
        "path": "archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift (diff)",
        "block": "fix_diff",
        "sha256": "376d659eea6f310c7ebd0d2bc5807ed1a9562b528aa831be7da92acb24231c30",
        "role": "Unified diff pinned to fixed."
      },
      {
        "path": "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.py",
        "block": "fixtures1",
        "sha256": "603f6c4ae13e2c890959a85390f5c498d8f8facfbffa6d6b2add19032856390a"
      },
      {
        "path": "archive/gor/Tests/Architecture/199i/W-gdb-199i-in2tinct-36.json",
        "block": "fixtures2",
        "sha256": "285a6a6b31d7f48028be395be3904b78cd9bae59bc02252be1c5f3caccdf9682"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "989a18612b8c72a16646ae203b93b11266182b8a3665dfad7ff98959b81f9e84",
    "last_5_lines": [
      "PASS CR value refused",
      "PASS key ';' refused",
      "PASS deadline rule intact",
      "PASS cookie/header conflict intact",
      ""
    ],
    "verification": {
      "red_Onone": {
        "log_block": "red_Onone",
        "log_sha256": "989a18612b8c72a16646ae203b93b11266182b8a3665dfad7ff98959b81f9e84",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "red_O": {
        "log_block": "red_O",
        "log_sha256": "989a18612b8c72a16646ae203b93b11266182b8a3665dfad7ff98959b81f9e84",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "green_Onone": {
        "log_block": "green_Onone",
        "log_sha256": "96f7c05890441a32aef2a78b1953fa3eb9bb1061ef886f176ef7fdffda61eea9",
        "semantic_exit": 0,
        "compile_exit": 0
      },
      "green_O": {
        "log_block": "green_O",
        "log_sha256": "96f7c05890441a32aef2a78b1953fa3eb9bb1061ef886f176ef7fdffda61eea9",
        "semantic_exit": 0,
        "compile_exit": 0
      }
    },
    "expected": "fixed source GREEN exit0 in -Onone and -O"
  },
  "state": "FIX PROPOSED - verified Swift 6.0.3 Linux, -Onone and -O",
  "classification": "validatedForOpen runs at FFmpegSoftwareDecoder.swift:759 (shipping remote video open) and FFmpegSoftwareAudioDecoder.swift:310 (shipping remote audio open); the serializer goravR3OpenInput runs at FFmpegSoftwareDecoder.swift:814, FFmpegSoftwareAudioDecoder.swift:341 and MediaInventory.swift:121, the last reachable from MediaInventory.load at MediaInventory.swift:101 with no prior typed validation. The C shim gorav_r3_open_input performs no cookie validation, so these two Swift predicates are the only injection fence. Defensive input-validation hardening; not an observed live incident.",
  "fix": {
    "summary": "Refuse ';' inside cookie values in validatedForOpen and in the mirrored goravR3OpenInput backstop, so one declared cookie can no longer serialize into an extra undeclared pair; keys, CR/LF/NUL, conflict and deadline rules unchanged.",
    "diff_block": "fix_diff",
    "diff_sha256": "376d659eea6f310c7ebd0d2bc5807ed1a9562b528aa831be7da92acb24231c30",
    "fixed_block": "fixed_source",
    "fixed_sha256": "456d7f6f9ca28e9392147282885b7081d1d8ae2ccf6135efa74a6bd811100fe2",
    "pinned_sha256": "abd87be3380ff8abf503b36c86873f9da94cf2c1e6959d8226ac7d9b342a6180"
  }
}
```

```swift id=source1
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

```swift id=fixed_source
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
        guard cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil && !$0.value.contains(";") }) else {
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
          options.cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil && !$0.value.contains(";") }) else { return -22 }
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

```diff id=fix_diff
--- a/archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift
+++ b/archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift
@@ -56,7 +56,7 @@
         guard headers.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(":") && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else {
             throw SourceOpenOptionsError.headerInjection
         }
-        guard cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else {
+        guard cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil && !$0.value.contains(";") }) else {
             throw SourceOpenOptionsError.cookieInjection
         }
         if !cookies.isEmpty {
@@ -89,7 +89,7 @@
     // Refuse CR/LF/NUL injection before C string transport; never log secret values.
     let forbidden = CharacterSet(charactersIn: "\r\n\0")
     guard options.headers.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(":") && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }),
-          options.cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else { return -22 }
+          options.cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil && !$0.value.contains(";") }) else { return -22 }
     var lines = options.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
     // FFmpeg's cookies option expects Set-Cookie response syntax, not a Cookie
     // request field. Serialize the request explicitly, retaining every pair.

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
SRCROOT=Path(os.environ.get('GOR_SOURCE_ROOT',str(ROOT)))
FLAGS=os.environ.get('SWIFTFLAGS','').split()
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(SRCROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n')
  main=td/'main.swift';main.write_text(source.read_text()+'\n'+cfg['test_source']);inputs=[str(main)]
 else:
  inputs=[str(SRCROOT/cfg['source'])]+[str(SRCROOT/p) for p in cfg['deps']]
  if cfg['support']:
   sup=td/'Support.swift';sup.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(sup))
  main=td/'main.swift';main.write_text(cfg['test_source']);inputs.append(str(main))
 exe=td/'test'
 c=subprocess.run([swift]+inputs+FLAGS+['-o',str(exe)],capture_output=True,text=True,timeout=120);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Packages/gorav/Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
  "markers": [
    "public struct SourceOpenOptions",
    "public enum SourceOpenOptionsError",
    "extension SourceOpenOptions"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nfunc validate(_ o:SourceOpenOptions)->SourceOpenOptionsError? { do { _ = try o.validatedForOpen(); return nil } catch let e as SourceOpenOptionsError { return e } catch { return nil } }\nvar isCookieInjection=false\nif case .cookieInjection = validate(SourceOpenOptions(cookies:[\"session\":\"abc; admin=1\"])) { isCookieInjection=true }\ncheck(isCookieInjection,\"cookie value ';' refused\")\nlet joined=[\"session=abc; admin=1\"].joined(separator:\"; \")\ncheck(joined.split(separator:\";\").count==2,\"serialized header would carry 2 pairs from 1 declared cookie\")\ncheck(validate(SourceOpenOptions(cookies:[\"sig\":\"YWJj==\"]))==nil,\"base64 '=' value allowed\")\nvar ctrl=false; if case .cookieInjection = validate(SourceOpenOptions(cookies:[\"a\":\"b\\rc\"])) { ctrl=true }\ncheck(ctrl,\"CR value refused\")\nvar keysc=false; if case .cookieInjection = validate(SourceOpenOptions(cookies:[\"a;b\":\"v\"])) { keysc=true }\ncheck(keysc,\"key ';' refused\")\ncheck(validate(SourceOpenOptions(cookies:[\"a\":\"b\"],openDeadlineSeconds:5))==nil,\"deadline rule intact\")\ncheck(validate(SourceOpenOptions(headers:[\"Cookie\":\"x\"],cookies:[\"a\":\"b\"])) != nil,\"cookie/header conflict intact\")\nexit(failures==0 ? 0:1)\n"
}
```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL cookie value ';' refused
PASS serialized header would carry 2 pairs from 1 declared cookie
PASS base64 '=' value allowed
PASS CR value refused
PASS key ';' refused
PASS deadline rule intact
PASS cookie/header conflict intact


```

```text id=red_Onone
compile_exit=0

semantic_exit=1
FAIL cookie value ';' refused
PASS serialized header would carry 2 pairs from 1 declared cookie
PASS base64 '=' value allowed
PASS CR value refused
PASS key ';' refused
PASS deadline rule intact
PASS cookie/header conflict intact


```

```text id=red_O
compile_exit=0

semantic_exit=1
FAIL cookie value ';' refused
PASS serialized header would carry 2 pairs from 1 declared cookie
PASS base64 '=' value allowed
PASS CR value refused
PASS key ';' refused
PASS deadline rule intact
PASS cookie/header conflict intact


```

```text id=green_Onone
compile_exit=0

semantic_exit=0
PASS cookie value ';' refused
PASS serialized header would carry 2 pairs from 1 declared cookie
PASS base64 '=' value allowed
PASS CR value refused
PASS key ';' refused
PASS deadline rule intact
PASS cookie/header conflict intact


```

```text id=green_O
compile_exit=0

semantic_exit=0
PASS cookie value ';' refused
PASS serialized header would carry 2 pairs from 1 declared cookie
PASS base64 '=' value allowed
PASS CR value refused
PASS key ';' refused
PASS deadline rule intact
PASS cookie/header conflict intact


```

Publication caveat: NONQUALIFIED. Host-vendored gorav snapshot pinned b603, NOT current gorav main cf3. Writer-reported Swift6.0.3 both-mode baseline RED/fixed GREEN; independent replay awaited. Defensive hardening, not observed live incidents. B36 cookie header boundary call sites FFmpegSoftwareDecoder759/814, AudioDecoder310/341, MediaInventory101/121; B37 subtitle schedule consumer41/48 and plan221. No native/network/fullpackage acceptance. Proposed fixes require independent mutants/boundary replay.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
