# W-gdb-199g-in2tinct-34 - Demux admission rejects negative stream counts
state: OPEN / unclaimed

LIVE-CALLER BOUND: FFmpegSoftwareDecoder.swift line883 calls DemuxerPolicy.evaluate. Exact policy and AdmissionTable/SourceDescriptor declarations compile without provider headers. Negative inventory hardening only: native current loop produces nonnegative counts. No native file failure claimed.
lab: in2tinct

Reject negative counts on every inventory axis, including subtitleStreamCount, before admitting profile. Preserve valid subtitle-bearing input and all current codec/container rules. FFmpegSoftwareDecoder calls evaluate at line883. This is malformed-caller ingress hardening; native current loop produces nonnegative counts, so no current native media failure is claimed. Exact policy/table/descriptor declarations compile without provider headers.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199g-in2tinct-34",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVNativeProbeKit/DemuxerPolicy.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Reject negative counts on every inventory axis, including subtitleStreamCount, before admitting profile. Preserve valid subtitle-bearing input and all current codec/container rules. FFmpegSoftwareDecoder calls evaluate at line883. This is malformed-caller ingress hardening; native current loop produces nonnegative counts, so no current native media failure is claimed. Exact policy/table/descriptor declarations compile without provider headers.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "LIVE-CALLER BOUND: FFmpegSoftwareDecoder.swift line883 calls DemuxerPolicy.evaluate. Exact policy and AdmissionTable/SourceDescriptor declarations compile without provider headers. Negative inventory hardening only: native current loop produces nonnegative counts. No native file failure claimed.",
    "callee": "Sources/GorAVNativeProbeKit/DemuxerPolicy.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-34.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199g-in2tinct-34",
    "paths": [
      "Sources/GorAVNativeProbeKit/DemuxerPolicy.swift",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-34.py",
      "Tests/Architecture/199g/W-gdb-199g-in2tinct-34.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199g/W-gdb-199g-in2tinct-34.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVNativeProbeKit/DemuxerPolicy.swift",
        "block": "source1",
        "sha256": "d90229e6fa304ebc56de48c3fe0f798a79d18650ad4f50b838160a490ece2efa",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-34.py",
        "block": "fixtures1",
        "sha256": "ca73de002a7ea6df0372f590d1eead763fa38702b16e21455076dcf870d2dcae"
      },
      {
        "path": "Tests/Architecture/199g/W-gdb-199g-in2tinct-34.json",
        "block": "fixtures2",
        "sha256": "a235d684fa5e5d07b063c4205de9cfda6b6f0520b6806fbeabcb2ce2a12606a5"
      },
      {
        "path": "Sources/GorAVCore/Boundary.swift",
        "block": "frozen_dependency_0",
        "sha256": "29e29ac1cf6dbb2e4a0552c9016347b2a3a5a4aaacceecda6d1b50b8c58fdfef",
        "read_only_dependency": true,
        "role": "Full original provenance for pinned declaration extraction; not an edit lease or an extra compile input."
      },
      {
        "path": "Sources/GorAVCore/AdmissionTable.swift",
        "block": "frozen_dependency_1",
        "sha256": "ed59ce0f6b3a89fc2290fb5a11ae71f30ded122d99caea68f5962d7c19ab049a",
        "read_only_dependency": true,
        "role": "Full original provenance for pinned declaration extraction; not an edit lease or an extra compile input."
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "85469c8c44eeb872ba42f9f145e31f7c00d7e5b4fcb99256c46232d68f1d31f2",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL negative subtitle count refused",
      "PASS positive subtitle count unchanged",
      ""
    ]
  },
  "classification": "LIVE-CALLER BOUND: FFmpegSoftwareDecoder.swift line883 calls DemuxerPolicy.evaluate. Exact policy and AdmissionTable/SourceDescriptor declarations compile without provider headers. Negative inventory hardening only: native current loop produces nonnegative counts. No native file failure claimed."
}
```

```swift id=source1
// AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
// NOT the pinned r1 member (pin 1747B/0650f2b8...); byte identity is not claimed.
// Role per DECODER-ONLY-TARGET-WIRING-r1: explicit demux admission.
import Foundation
import GorAVCore

/// Explicit demux admission for the decoder-only probe. An input is either
/// admitted with a recorded reason or rejected with a recorded reason; there is
/// no implicit fallback. Mixed-media sources are rejected pre-open (Stage 3 P-14).
public struct DemuxerPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case admit(container: String, videoCodec: String)
        case reject(reason: String)
    }
    /// d4 close-out (queue 36): the forwarding aliases are retired. Every
    /// admission set is read directly from GorAVCore AdmissionTable, the single
    /// source of truth; this type keeps only evaluate() and its decisions.
    public init() {}

    /// Admission check from probe facts. Runs post-open/post-stream-inventory and
    /// pre-decode (r4 D12: it cannot run before avformat_find_stream_info; the
    /// pre-open stage is the source-id allowlist in the adapter). streamCounts
    /// must come from actual demuxed
    /// stream inventory, never from filename or container sniffing alone.
    /// audioCodecName (card 465, 2026-10-25): actual demuxed audio codec for the
    /// bounded muxed profile below; nil preserves the original no-audio rule.
    public func evaluate(containerName: String,
                         videoCodecName: String?,
                         videoStreamCount: Int,
                         audioStreamCount: Int,
                         otherStreamCount: Int,
                         subtitleStreamCount: Int = 0,
                         audioCodecName: String? = nil,
                         sourceKind: SourceDescriptor.Kind? = nil,
                         sourceURL: String? = nil) -> Decision {
        // Queue 30: when the caller supplies the source class, a non-admitted
        // class is a loud rejection naming the kind (P14).
        if let kind = sourceKind, !AdmissionTable.isAdmittedSource(kind: kind) {
            return .reject(reason: "source kind not admitted: \(kind)")
        }
        // Queue 31/32: a remote or iptv source needs an admitted scheme; rejection names it.
        if let kind = sourceKind, AdmissionTable.schemeGatedKinds.contains(kind) {
            guard let url = sourceURL else { return .reject(reason: "\(kind) source without a URL") }
            guard AdmissionTable.isAdmittedRemoteURL(url) else {
                return .reject(reason: "\(kind) scheme not admitted: \(AdmissionTable.remoteScheme(of: url) ?? "(none)")")
            }
        }
        guard AdmissionTable.probeContainers.contains(containerName) else {
            return .reject(reason: "container not admitted: \(containerName)")
        }
        // arch-196t r2 item 4a: embedded subtitle streams (PGS, VobSub,
        // WebVTT) are admitted and counted separately by the caller; routing
        // them into the subtitle seams is a playback-path wiring step, not an
        // admission rejection. Truly unknown stream types still refuse.
        guard otherStreamCount == 0 else {
            return .reject(reason: "unsupported stream types rejected before first decode read (other=\(otherStreamCount), subtitles=\(subtitleStreamCount))")
        }
        // Card 465 bounded muxed profile: real owner media is one container with
        // sibling A/V streams, and the probe's original no-audio rule made every
        // such file inadmissible. Admitted muxed shape: exactly one admitted
        // video codec stream plus exactly one admitted audio stream in MOV or Matroska
        // containers (the audio sibling is decoded by FFmpegSoftwareAudioDecoder's
        // matching profile). Every other mixed shape keeps the rejection.
        if audioStreamCount == 1 {
            // L3 (2026-10-25): muxed audio widened from pcm_s16le-in-mov to the
            // L3 audio set across the mov family and matroska. Conversion to
            // the sink contract is owned by FFmpegSoftwareAudioDecoder.
            guard AdmissionTable.muxedContainers.contains(containerName),
                  let audio = audioCodecName, AdmissionTable.audioCodecs.contains(audio) else {
                return .reject(reason: "mixed-media audio profile not admitted (container=\(containerName) audioCodec=\(audioCodecName ?? "none"))")
            }
        } else if audioStreamCount != 0 {
            return .reject(reason: "expected at most one audio stream, found \(audioStreamCount)")
        }
        guard videoStreamCount == 1 else {
            return .reject(reason: "expected exactly one video stream, found \(videoStreamCount)")
        }
        guard let codec = videoCodecName, AdmissionTable.videoCodecs.contains(codec) else {
            return .reject(reason: "video codec not admitted: \(videoCodecName ?? "none")")
        }
        return .admit(container: containerName, videoCodec: codec)
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
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+('private let fenceLock = NSLock()\nprivate var fence: SeekFenceBinding?\npublic init() {}\n' if cfg['source'].endswith('ShellSeekBridge.swift') else '')+selected+'\n}'
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
  "source": "Sources/GorAVNativeProbeKit/DemuxerPolicy.swift",
  "markers": [
    "public struct DemuxerPolicy:"
  ],
  "wrapper": "",
  "support": "public struct SourceDescriptor: Equatable, Sendable {\n    public enum Kind: Equatable, Sendable { case local, remote, webTorrent, iptv, ytdl, archiveOrg }\n    public let id: String\n    public let kind: Kind\n    public let seekable: Bool\n    public init(id: String, kind: Kind, seekable: Bool) {\n        self.id = id; self.kind = kind; self.seekable = seekable\n    }\n}\npublic enum AdmissionTable {\n    /// Containers the L3 profile admits at all (adapter side; wav is the\n    /// PCM WAV profile the adapter decodes directly).\n    public static let containers: Set<String> = [\"mov,mp4,m4a,3gp,3g2,mj2\", \"matroska,webm\", \"mpegts\", \"wav\"]\n    /// Containers admitted for the muxed (video + audio sibling) shape.\n    public static let muxedContainers: Set<String> = [\"mov,mp4,m4a,3gp,3g2,mj2\", \"matroska,webm\", \"mpegts\"]\n    /// Containers the decoder-only probe admits. Stricter than the adapter\n    /// set: no wav (the probe is a video probe; wav carries no video stream).\n    public static let probeContainers: Set<String> = [\"mov,mp4,m4a,3gp,3g2,mj2\", \"matroska,webm\", \"mpegts\"]\n    /// M1 software video codecs; unbuilt codecs are refused. HEVC 10-bit\n    /// originals remain preserved; no HDR tone mapping claim. arch-196t\n    /// item 4: + av1, vp9 for the real-media matrix.\n    public static let videoCodecs: Set<String> = [\"mpeg4\", \"h264\", \"hevc\", \"av1\", \"vp9\"]\n    /// Audio codecs admitted as the muxed sibling or the wav profile.\n    /// arch-196t item 4 (2026-11-15): real-media matrix - DTS, AC3, EAC3,\n    /// AAC, Opus, FLAC, TrueHD, MP3, PCM. Admission requires the pinned\n    /// FFmpeg to carry the matching decoder; a missing decoder is a typed\n    /// \"no decoder for admitted codec\" refusal at open, never a guess.\n    /// Non-pcm codecs decode through FFmpegSoftwareAudioDecoder's L3 path and\n    /// are converted to the sink contract (packed s16le stereo 44.1 kHz).\n    public static let audioCodecs: Set<String> = [\"pcm_s16le\", \"aac\", \"dts\", \"ac3\", \"eac3\", \"opus\", \"flac\", \"truehd\", \"mp3\"]\n    /// Codecs that attempt VideoToolbox with the measured software fallback\n    /// (L4, block 168 m2). mpeg4 has no VT hwaccel and av1 stays\n    /// software-by-policy. Off-Darwin the shim refuses and decode proceeds in\n    /// software - receipt-recorded.\n    public static let hardwareAttemptCodecs: Set<String> = [\"h264\", \"hevc\"]\n\n    /// d4 rungs 2-7 (queue 30-35, ladder complete): source classes admitted: local,\n    /// remote, iptv, webTorrent, ytdl and archiveOrg (all but local only behind the\n    /// http/https scheme allowlist below; a webTorrent id is an HTTP(S) URL served\n    /// by the wt_server bridge, a ytdl id is an HTTP(S) URL resolved by the ytdl\n    /// step, an archiveOrg id is an HTTP(S) URL into the archive).\n    /// HLS/.m3u8 and torrent-protocol handling are out of scope: this is a\n    /// source-class admission decision only.\n    public static let admittedSourceKinds: Set<SourceDescriptor.Kind> = [.local, .remote, .iptv, .webTorrent, .ytdl, .archiveOrg]\n    /// Kinds that must also carry an admitted URL scheme.\n    public static let schemeGatedKinds: Set<SourceDescriptor.Kind> = [.remote, .iptv, .webTorrent, .ytdl, .archiveOrg]\n\n    /// d4 rung 3 (queue 31): remote schemes admitted. Scheme-prefix parse only.\n    public static let admittedRemoteSchemes: [String] = [\"http\", \"https\"]\n\n    /// The scheme of a source id (\"http\" for \"HTTP://x\"), lowercased; nil when\n    /// the id carries no \"scheme://\" prefix.\n    public static func remoteScheme(of url: String) -> String? {\n        guard let r = url.range(of: \"://\") else { return nil }\n        let scheme = url[url.startIndex ..< r.lowerBound]\n        guard !scheme.isEmpty else { return nil }\n        return scheme.lowercased()\n    }\n\n    /// Remote URL admission: case-insensitive scheme match against the\n    /// allowlist; nothing else is consulted.\n    public static func isAdmittedRemoteURL(_ url: String) -> Bool {\n        guard let scheme = remoteScheme(of: url) else { return false }\n        return admittedRemoteSchemes.contains(scheme)\n    }\n\n    /// Source-class admission: the single source of truth for the kind axis.\n    public static func isAdmittedSource(kind: SourceDescriptor.Kind) -> Bool {\n        admittedSourceKinds.contains(kind)\n    }\n\n    /// Muxed audio admission from demuxed facts.\n    public static func isAdmittedMuxedAudio(container: String, audioCodec: String) -> Bool {\n        muxedContainers.contains(container) && audioCodecs.contains(audioCodec)\n    }\n\n    /// Whether a session should try to attach VideoToolbox for the codec.\n    /// GORAV_L3_DISABLE_HW=1 forces the software path: the deterministic,\n    /// reproducible arm of the clean-fallback acceptance evidence.\n    public static func shouldAttemptHardware(videoCodec: String,\n                                             environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {\n        guard hardwareAttemptCodecs.contains(videoCodec) else { return false }\n        if environment[\"GORAV_L3_DISABLE_HW\"] == \"1\" { return false }\n        return true\n    }\n\n    /// P30/W2 (arch-196z E1, arch-197a item 2, arch-197b): whether an attached\n    /// VideoToolbox session keeps VT frames GPU-resident for the zero-copy\n    /// present path (CVPixelBuffer -> CVMetalTextureCache, YUV->RGB in the\n    /// shader BEFORE the colour stage) instead of transferring every frame to\n    /// software (a CPU copy). GORAV_VT_ZEROCOPY=1 arms it; the transfer path\n    /// stays the DEFAULT until the native E1 gate (VTRECEIPT cpuCopies=0\n    /// cpuYUVtoRGB=0 on h264/hevc/hevc10) has passed on the armed tree.\n    /// Inert off-Darwin: no VT-format frame exists there, so an armed\n    /// session's zero-copy receive passes software frames through untouched\n    /// (l4-hwdecode-tests prove the invariance on Linux).\n    public static func shouldArmVTZeroCopy(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {\n        if environment[\"GORAV_L3_DISABLE_HW\"] == \"1\" { return false }\n        return environment[\"GORAV_VT_ZEROCOPY\"] == \"1\"\n    }\n}",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet p=DemuxerPolicy()\nif case .reject = p.evaluate(containerName:\"matroska,webm\",videoCodecName:\"h264\",videoStreamCount:1,audioStreamCount:0,otherStreamCount:0,subtitleStreamCount:-1) {check(true,\"negative subtitle count refused\")} else {check(false,\"negative subtitle count refused\")}\nif case .admit = p.evaluate(containerName:\"matroska,webm\",videoCodecName:\"h264\",videoStreamCount:1,audioStreamCount:0,otherStreamCount:0,subtitleStreamCount:1) {check(true,\"positive subtitle count unchanged\")} else {check(false,\"positive subtitle count unchanged\")}\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL negative subtitle count refused
PASS positive subtitle count unchanged


```

```swift id=frozen_dependency_0
import Foundation
import GorAVCAtomics

/// No media bytes, credentials or runtime player are part of this Stage 0 contract.
///
/// IDENTITY AUTHORITY (architect full verdict S4): a SessionID's public
/// init carries NO authority. Production playback identity is issued ONLY
/// by PlaybackIdentityAuthority - one owner-issued opaque identity shared
/// across decoder/audio/display/ledger for a run, with a separate
/// seek/presentation revision. Per-lane minting (String+UInt64 forms,
/// hashes, fixed shell epochs) is a contract violation; explicit-epoch
/// construction remains for TEST FIXTURES ONLY and mints nothing.
public struct SessionID: Hashable, Sendable {
    public let epoch: UInt64
    /// S7: NOT a mint. Production identities come ONLY from
    /// PlaybackIdentityAuthority.issue() (one owner-issued opaque
    /// identity per run). This unchecked constructor exists for
    /// REFUSAL/FOREIGN-SESSION TESTS, which must fabricate arbitrary
    /// unissued ids to prove they are refused; naming it unchecked
    /// keeps forgery out of production call sites by inspection.
    public init(uncheckedEpoch: UInt64) { self.epoch = uncheckedEpoch }
}

/// The single owner of playback identity issuance (S4). Monotonic atomic
/// issuance; wrap is TYPED EXHAUSTION (nil), never a recycled identity.
public final class PlaybackIdentityAuthority: @unchecked Sendable {
    public static let shared = PlaybackIdentityAuthority()
    /// C-owned atomic cell (GorAVCAtomics); failable alloc = typed refusal.
    private let lastIssued: UnsafeMutableRawPointer?
    private init() { lastIssued = gorav_acell_create(0) }
    deinit { if let c = lastIssued { gorav_acell_destroy(c) } }
    /// Issue the next opaque session identity, or nil at typed exhaustion.
    public func issue() -> SessionID? {
        guard let c = lastIssued else { return nil }     // typed cell refusal
        while true {
            let last = gorav_aload(c)
            if last == UInt64.max { return nil }         // typed exhaustion, never wrap
            var e = last
            if gorav_acas(c, &e, last &+ 1) != 0 { return SessionID(uncheckedEpoch: last &+ 1) }
        }
    }
    /// Seek/presentation revision (S4): separate from session identity.
    /// A seek NEVER mints a new session; it bumps the run's revision.
    public final class PresentationRevision: @unchecked Sendable {
        private let cell: UnsafeMutableRawPointer?
        public init() { cell = gorav_acell_create(0) }
        deinit { if let c = cell { gorav_acell_destroy(c) } }
        public var current: UInt64 { guard let c = cell else { return 0 }; return gorav_aload(c) }
        public func bump() -> UInt64 { guard let c = cell else { return 0 }; return gorav_afetch_add(c, 1) &+ 1 }
    }
}

public struct SourceDescriptor: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case local, remote, webTorrent, iptv, ytdl, archiveOrg }
    public let id: String
    public let kind: Kind
    public let seekable: Bool
    public init(id: String, kind: Kind, seekable: Bool) {
        self.id = id; self.kind = kind; self.seekable = seekable
    }
}

public enum StopReason: Equatable, Sendable { case user, replaced, endOfFile, failure }
public enum Lifecycle: Equatable, Sendable {
    case idle, opening, ready, playing, paused, buffering, ended(StopReason), failed
}
public struct SessionSnapshot: Equatable, Sendable {
    public let id: SessionID
    public let source: SourceDescriptor
    public let lifecycle: Lifecycle
    public init(id: SessionID, source: SourceDescriptor, lifecycle: Lifecycle) {
        self.id = id; self.source = source; self.lifecycle = lifecycle
    }
}

/// A backend can be an mpv adapter first. Native demux/decode and render backends
/// are later implementations, not capabilities asserted by this interface.
public protocol PlaybackBackend: AnyObject {
    func open(_ source: SourceDescriptor, session: SessionID) async throws
    func stop(session: SessionID, reason: StopReason) async
    func seek(seconds: Double, session: SessionID, requestID: UInt64) async throws
    func snapshot(session: SessionID) async -> SessionSnapshot?
}

/// Pure epoch gate for callbacks from async backends. Source/event correlation
/// remains backend-specific and must not be inferred from arrival order alone.
public struct SessionGate: Sendable {
    public private(set) var active: SessionID?
    public init() {}
    /// S7: the gate CONSUMES an owner-issued identity; it never mints
    /// one (PlaybackIdentityAuthority is the single issuance owner).
    @discardableResult public mutating func begin(_ id: SessionID) -> SessionID {
        active = id
        return id
    }
    public mutating func stop() { active = nil }
    public func accepts(_ id: SessionID) -> Bool { active == id }
}

```

```swift id=frozen_dependency_1
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

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Read-only caller bindings independently checked at cf3: ShellFrameSource ledger/bridge; MetalPresenter cue consumer; FFmpegSoftwareDecoder demux policy/lease table. B32 reduced wrapper/provider double and B31/B34 declaration extraction only, no full module claim. B33-35 malformed ingress hardening, not observed runtime incidents. Single production path plus own test, no adoption or runtime closure.
