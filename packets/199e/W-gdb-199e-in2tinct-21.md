# W-gdb-199e-in2tinct-21 - Torrent fragments cannot bypass resolver routing
state: OPEN / unclaimed
lab: in2tinct

Classify .torrent using parsed URL path, excluding fragment and query components. A .torrent path with #fragment must still require WebTorrent bridge and retain original URL as subject. A non-torrent path whose fragment merely ends in .torrent must remain directRemote. Preserve scheme/provider admission and all existing transfer rules.

OpenURLRouter and AdmissionTable compile in full with the verbatim SourceDescriptor DTO extracted from pinned Boundary.swift, embedded as read-only compile support in the test config. This DTO contains no routing/admission logic. Boundary/CAtomics whole-module integration NOT_RUN; no source behavior is mocked.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-in2tinct-21",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVCore/OpenURLRouter.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Classify .torrent using parsed URL path, excluding fragment and query components. A .torrent path with #fragment must still require WebTorrent bridge and retain original URL as subject. A non-torrent path whose fragment merely ends in .torrent must remain directRemote. Preserve scheme/provider admission and all existing transfer rules.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "Sources/GorAVCore/OpenURLRouter.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199e/W-gdb-199e-in2tinct-21.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199e-in2tinct-21",
    "paths": [
      "Sources/GorAVCore/OpenURLRouter.swift",
      "Tests/Architecture/199e/W-gdb-199e-in2tinct-21.py",
      "Tests/Architecture/199e/W-gdb-199e-in2tinct-21.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199e/W-gdb-199e-in2tinct-21.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-router-and-admission-with-verbatim-SourceDescriptor-DTO",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVCore/OpenURLRouter.swift",
        "block": "source1",
        "sha256": "0f3fa4238a8d7d9e3cff41bf625b20b1f9da28027667720f81f8424bf8c6ead6",
        "read_only_dependency": false
      },
      {
        "path": "Sources/GorAVCore/AdmissionTable.swift",
        "block": "source2",
        "sha256": "ed59ce0f6b3a89fc2290fb5a11ae71f30ded122d99caea68f5962d7c19ab049a",
        "read_only_dependency": true
      },
      {
        "path": "Tests/Architecture/199e/W-gdb-199e-in2tinct-21.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "Tests/Architecture/199e/W-gdb-199e-in2tinct-21.json",
        "block": "fixtures2",
        "sha256": "3ef6edc02f0fd54c173b72f3381d98cff201d0edd8184d0acc7d102dc13b660c"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "d0b0918c686da25eec7682045f6e710dcdb6492de52bfc28eeb4843564a61738",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL torrent fragment still routes bridge",
      "FAIL fragment not path",
      ""
    ],
    "receipt_sha256": "314921ccce6cd32fef4e9e90060880857eb9d2dc0302c85c7499d8ed1778f04b"
  }
}
```

```swift id=source1
import Foundation

// R3 (arch-195l, dispatch L6): open(url:) classification for transfer.it /
// mega / torrent. Pure classification over the URL string; no networking.
// Refusal reasons are typed tokens ONLY - they never carry URL content, so
// nothing here needs redaction. Routing policy follows AdmissionTable: the
// engine admits resolved http(s) URLs only; mega links need the external
// mega resolve/decrypt step first, magnet/.torrent needs the wt_server
// bridge first (both re-enter later as admitted http(s) descriptors).

public enum OpenURLRoute: Equatable, Sendable {
    /// Admitted remote open: the URL goes to the admitted remote path as-is
    /// (only already-resolved media URLs, not transfer.it share pages).
    case directRemote(id: String, seekable: Bool)
    /// mega.nz / mega.co.nz link: the external mega step must resolve and
    /// decrypt to an admitted http(s) URL before the engine can open it.
    case needsTransferResolver
    case needsMegaResolver
    /// magnet: URI or .torrent URL: the wt_server bridge must serve an
    /// admitted http(s) URL first. `subject` is the normalized btih
    /// infohash (40-hex lowercased, or 32-char base32 uppercased) for
    /// magnet:, or the original .torrent URL.
    case needsWebTorrentBridge(subject: String)
    /// Typed refusal; reason is a token, never URL content.
    case refused(Reason)

    public enum Reason: String, Equatable, Sendable {
        case unparseable
        case schemeNotAdmitted
        case emptyHost
        case magnetMissingBtih
        case magnetBadInfoHash
        case megaLinkShape
        case transferLinkShape
    }
}

public enum OpenURLRouter {
    /// Lowercased host of an admitted-scheme URL: userinfo and port
    /// stripped, nil when no "://" or the authority is empty.
    static func host(of url: String, schemeEnd: String.Index) -> String? {
        let rest = url[schemeEnd...].dropFirst(3)   // past "://"
        var authority = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
        let host = authority.prefix { $0 != ":" }
        guard !host.isEmpty else { return nil }
        return host.lowercased()
    }

    static func hostMatches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    /// Normalize a btih infohash: 40-char hex (lowercased) or 32-char
    /// base32 (uppercased); nil otherwise.
    static func normalizeInfoHash(_ raw: String) -> String? {
        if raw.count == 40, raw.allSatisfy({ $0.isHexDigit }) { return raw.lowercased() }
        if raw.count == 32, raw.allSatisfy({ ("A"..."Z").contains($0) || ("a"..."z").contains($0) || ("2"..."7").contains($0) }) {
            return raw.uppercased()
        }
        return nil
    }

    public static func route(_ url: String) -> OpenURLRoute {
        guard !url.isEmpty else { return .refused(.unparseable) }
        // magnet: has no "//", so it never survives the scheme gate; handle first.
        if url.lowercased().hasPrefix("magnet:") {
            guard let q = url.firstIndex(of: "?") else { return .refused(.magnetMissingBtih) }
            let params = url[url.index(after: q)...].split(separator: "&")
            for p in params {
                let lower = p.lowercased()
                if lower.hasPrefix("xt=urn:btih:") {
                    let raw = String(p.dropFirst("xt=urn:btih:".count))
                    guard let hash = normalizeInfoHash(raw) else { return .refused(.magnetBadInfoHash) }
                    return .needsWebTorrentBridge(subject: hash)
                }
            }
            return .refused(.magnetMissingBtih)
        }
        guard let r = url.range(of: "://"),
              let scheme = AdmissionTable.remoteScheme(of: url),
              AdmissionTable.admittedRemoteSchemes.contains(scheme) else {
            return .refused(url.range(of: "://") == nil ? .unparseable : .schemeNotAdmitted)
        }
        guard let host = host(of: url, schemeEnd: r.lowerBound) else { return .refused(.emptyHost) }
        // A share page is not media. Only the measured transfer URL shape
        // reaches explicit preparation; never guess a file within a transfer.
        if hostMatches((URLComponents(string: url)?.host ?? host).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), "transfer.it") {
            // URLComponents.host percent-decodes on corelibs Foundation.
            // Enforce raw authority shape before that normalization.
            let rawAuthority = url[r.upperBound...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            guard !rawAuthority.contains("%") else { return .refused(.transferLinkShape) }
            guard let parsed = URLComponents(string: url),
                  parsed.scheme?.lowercased() == "https", parsed.host?.lowercased() == "transfer.it",
                  parsed.user == nil, parsed.password == nil, parsed.port == nil,
                  parsed.query == nil, parsed.fragment == nil, parsed.percentEncodedPath == parsed.path else { return .refused(.transferLinkShape) }
            let parts = parsed.path.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.count == 2, parts[0] == "t", !parts[1].isEmpty,
                  parts[1].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
                  parsed.path == "/t/" + String(parts[1]) || parsed.path == "/t/" + String(parts[1]) + "/" else { return .refused(.transferLinkShape) }
            return .needsTransferResolver
        }
        // mega links carry their key material in the fragment; the engine
        // never speaks the mega API.
        if hostMatches(host, "mega.nz") || hostMatches(host, "mega.co.nz") {
            let ok = url.contains("/file/") || url.contains("/folder/") || url.contains("#!")
            return ok ? .needsMegaResolver : .refused(.megaLinkShape)
        }
        // A .torrent file URL goes to the bridge like a magnet.
        let pathOnly = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        if pathOnly.lowercased().hasSuffix(".torrent") {
            return .needsWebTorrentBridge(subject: url)
        }
        // Everything else on an admitted scheme is a plain remote source.
        return .directRemote(id: url, seekable: true)
    }
}

```

```swift id=source2
// d4 rung 1 (architect gorav night queue item 7, owner block 190): single
// admission table. ONE source of truth for container/codec admission sets;
// DemuxerPolicy (GorAVNativeProbeKit) and the adapters read it directly
// (forwarding aliases retired at queue 36). No mirrored copies, no KEEP IN SYNC.
import Foundation

/// Container/codec admission sets for the M1/L3 profile, shared by the probe
/// and the adapter. Set names carry their role; anything outside a set is a
/// refusal, never a guess.
public enum AdmissionTable {
    /// Containers the L3 profile admits at all (adapter side; wav is the
    /// PCM WAV profile the adapter decodes directly).
    public static let containers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts", "wav"]
    /// Containers admitted for the muxed (video + audio sibling) shape.
    public static let muxedContainers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts"]
    /// Containers the decoder-only probe admits. Stricter than the adapter
    /// set: no wav (the probe is a video probe; wav carries no video stream).
    public static let probeContainers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts"]
    /// M1 software video codecs; unbuilt codecs are refused. HEVC 10-bit
    /// originals remain preserved; no HDR tone mapping claim. arch-196t
    /// item 4: + av1, vp9 for the real-media matrix.
    public static let videoCodecs: Set<String> = ["mpeg4", "h264", "hevc", "av1", "vp9"]
    /// Audio codecs admitted as the muxed sibling or the wav profile.
    /// arch-196t item 4 (2026-11-15): real-media matrix - DTS, AC3, EAC3,
    /// AAC, Opus, FLAC, TrueHD, MP3, PCM. Admission requires the pinned
    /// FFmpeg to carry the matching decoder; a missing decoder is a typed
    /// "no decoder for admitted codec" refusal at open, never a guess.
    /// Non-pcm codecs decode through FFmpegSoftwareAudioDecoder's L3 path and
    /// are converted to the sink contract (packed s16le stereo 44.1 kHz).
    public static let audioCodecs: Set<String> = ["pcm_s16le", "aac", "dts", "ac3", "eac3", "opus", "flac", "truehd", "mp3"]
    /// Codecs that attempt VideoToolbox with the measured software fallback
    /// (L4, block 168 m2). mpeg4 has no VT hwaccel and av1 stays
    /// software-by-policy. Off-Darwin the shim refuses and decode proceeds in
    /// software - receipt-recorded.
    public static let hardwareAttemptCodecs: Set<String> = ["h264", "hevc"]

    /// d4 rungs 2-7 (queue 30-35, ladder complete): source classes admitted: local,
    /// remote, iptv, webTorrent, ytdl and archiveOrg (all but local only behind the
    /// http/https scheme allowlist below; a webTorrent id is an HTTP(S) URL served
    /// by the wt_server bridge, a ytdl id is an HTTP(S) URL resolved by the ytdl
    /// step, an archiveOrg id is an HTTP(S) URL into the archive).
    /// HLS/.m3u8 and torrent-protocol handling are out of scope: this is a
    /// source-class admission decision only.
    public static let admittedSourceKinds: Set<SourceDescriptor.Kind> = [.local, .remote, .iptv, .webTorrent, .ytdl, .archiveOrg]
    /// Kinds that must also carry an admitted URL scheme.
    public static let schemeGatedKinds: Set<SourceDescriptor.Kind> = [.remote, .iptv, .webTorrent, .ytdl, .archiveOrg]

    /// d4 rung 3 (queue 31): remote schemes admitted. Scheme-prefix parse only.
    public static let admittedRemoteSchemes: [String] = ["http", "https"]

    /// The scheme of a source id ("http" for "HTTP://x"), lowercased; nil when
    /// the id carries no "scheme://" prefix.
    public static func remoteScheme(of url: String) -> String? {
        guard let r = url.range(of: "://") else { return nil }
        let scheme = url[url.startIndex ..< r.lowerBound]
        guard !scheme.isEmpty else { return nil }
        return scheme.lowercased()
    }

    /// Remote URL admission: case-insensitive scheme match against the
    /// allowlist; nothing else is consulted.
    public static func isAdmittedRemoteURL(_ url: String) -> Bool {
        guard let scheme = remoteScheme(of: url) else { return false }
        return admittedRemoteSchemes.contains(scheme)
    }

    /// Source-class admission: the single source of truth for the kind axis.
    public static func isAdmittedSource(kind: SourceDescriptor.Kind) -> Bool {
        admittedSourceKinds.contains(kind)
    }

    /// Muxed audio admission from demuxed facts.
    public static func isAdmittedMuxedAudio(container: String, audioCodec: String) -> Bool {
        muxedContainers.contains(container) && audioCodecs.contains(audioCodec)
    }

    /// Whether a session should try to attach VideoToolbox for the codec.
    /// GORAV_L3_DISABLE_HW=1 forces the software path: the deterministic,
    /// reproducible arm of the clean-fallback acceptance evidence.
    public static func shouldAttemptHardware(videoCodec: String,
                                             environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard hardwareAttemptCodecs.contains(videoCodec) else { return false }
        if environment["GORAV_L3_DISABLE_HW"] == "1" { return false }
        return true
    }

    /// P30/W2 (arch-196z E1, arch-197a item 2, arch-197b): whether an attached
    /// VideoToolbox session keeps VT frames GPU-resident for the zero-copy
    /// present path (CVPixelBuffer -> CVMetalTextureCache, YUV->RGB in the
    /// shader BEFORE the colour stage) instead of transferring every frame to
    /// software (a CPU copy). GORAV_VT_ZEROCOPY=1 arms it; the transfer path
    /// stays the DEFAULT until the native E1 gate (VTRECEIPT cpuCopies=0
    /// cpuYUVtoRGB=0 on h264/hevc/hevc10) has passed on the armed tree.
    /// Inert off-Darwin: no VT-format frame exists there, so an armed
    /// session's zero-copy receive passes software frames through untouched
    /// (l4-hwdecode-tests prove the invariance on Linux).
    public static func shouldArmVTZeroCopy(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment["GORAV_L3_DISABLE_HW"] == "1" { return false }
        return environment["GORAV_VT_ZEROCOPY"] == "1"
    }
}

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
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
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "Sources/GorAVCore/OpenURLRouter.swift",
  "markers": [],
  "wrapper": "",
  "support": "public struct SourceDescriptor: Equatable, Sendable {\n    public enum Kind: Equatable, Sendable { case local, remote, webTorrent, iptv, ytdl, archiveOrg }\n    public let id: String\n    public let kind: Kind\n    public let seekable: Bool\n    public init(id: String, kind: Kind, seekable: Bool) {\n        self.id = id; self.kind = kind; self.seekable = seekable\n    }\n}\n",
  "deps": [
    "Sources/GorAVCore/AdmissionTable.swift"
  ],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet a=\"https://example.invalid/movie.torrent#view\"\nif case .needsWebTorrentBridge(let subject)=OpenURLRouter.route(a) {check(subject == a,\"original subject retained\")} else {check(false,\"torrent fragment still routes bridge\")}\nif case .directRemote = OpenURLRouter.route(\"https://example.invalid/movie.mp4#fake.torrent\") {check(true,\"fragment does not change path kind\")} else {check(false,\"fragment not path\")}\n\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL torrent fragment still routes bridge
FAIL fragment not path


```

Publication caveat: NONQUALIFIED: isolated source semantics, not full package/native acceptance. B21 uses a SourceDescriptor compile-support declaration; actual Core integration remains NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
