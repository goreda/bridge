# W-gdb-198y-in2tinct-27
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-27.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-27",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVCore/AdmissionTable.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-27.py checks Sources/GorAVCore/AdmissionTable.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: AdmissionTable, remoteScheme, isAdmittedRemoteURL, isAdmittedSource, isAdmittedMuxedAudio, shouldAttemptHardware, shouldArmVTZeroCopy",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-27.py",
    "callee": "Sources/GorAVCore/AdmissionTable.swift owning station GorAVCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-27.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-27.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-27.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.314095+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVCore/AdmissionTable.swift",
        "block": "source1",
        "sha256": "ed59ce0f6b3a89fc2290fb5a11ae71f30ded122d99caea68f5962d7c19ab049a"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-27.py",
        "block": "fixtures1",
        "sha256": "8c8ca6d5d3fc93bf231d7d2fa9e20213db0b343e7bc52bba97d018d22779285f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "9014fc2fb7d33797e7ddccc1fda641e4267086b4ca5b02383fedf9cf39fad5ce",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-27: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "42fc2f52bfb2f29091a78082cbfd028db4264c19db576db2fa5e89302253e1ec"
  }
}
```

```swift id=source1
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
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVCore/AdmissionTable.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='ed59ce0f6b3a89fc2290fb5a11ae71f30ded122d99caea68f5962d7c19ab049a', 'pinned source changed: rebase and review, never bless silently'
for token in ['AdmissionTable', 'remoteScheme', 'isAdmittedRemoteURL', 'isAdmittedSource', 'isAdmittedMuxedAudio', 'shouldAttemptHardware', 'shouldArmVTZeroCopy']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='ed59ce0f6b3a89fc2290fb5a11ae71f30ded122d99caea68f5962d7c19ab049a'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-27: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-27: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
