# W-gdb-198z-in2tinct-04 - Relocated fixture consumer admission-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-04",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/admission-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer admission-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/admission-tests/main.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-04.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-04",
    "paths": [
      "Sources/admission-tests/main.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-04.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-04.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.528464+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/admission-tests/main.swift",
        "block": "source1",
        "sha256": "9f33357bb1261d03ecd6792e3e332786b9243e731cdb992cf6525da082826d4f"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-04.py",
        "block": "fixtures1",
        "sha256": "dbbced465f8f73190613cd17f79de0692bee8bff4e0fc9b50710768b68d08995"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "34393061626d6d288047a60c7a622cfab9d14f5883773e620772c7b7ca236877",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-04; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "8e6545637f2ab9111edae5116a85abab0920a389c3a97232bb4dbd9fc77f98cb"
  }
}
```

```swift id=source1
// d4 rung 1 tests (architect gorav night queue item 7, owner block 190):
// the single admission table is the only source of truth; both legacy
// surfaces forward to it; the probe evaluate() contract is unchanged by the
// collapse. Pure logic, no media: NOT_RUN does not apply here.
import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

var failures = 0
func check(_ cond: Bool, _ name: String, _ detail: String = "") {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail)") }
}

// A1: table contents are exact. arch-196t r2 item 4a (2026-11-15) widened
// the probe-era profile to the real-media matrix: mpegts container; audio
// dts/ac3/eac3/opus/flac/truehd/mp3; video av1/vp9.
check(AdmissionTable.containers == ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts", "wav"], "A1 containers exact")
check(AdmissionTable.muxedContainers == ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts"], "A1 muxedContainers exact")
check(AdmissionTable.probeContainers == ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts"], "A1 probeContainers exact (no wav)")
check(AdmissionTable.videoCodecs == ["mpeg4", "h264", "hevc", "av1", "vp9"], "A1 videoCodecs exact")
check(AdmissionTable.audioCodecs == ["pcm_s16le", "aac", "dts", "ac3", "eac3", "opus", "flac", "truehd", "mp3"], "A1 audioCodecs exact")
check(AdmissionTable.hardwareAttemptCodecs == ["h264", "hevc"], "A1 hardwareAttemptCodecs exact (widening does not change hw policy)")

// A2: shape invariants the two consumers implicitly relied on.
check(AdmissionTable.probeContainers.isSubset(of: AdmissionTable.containers), "A2 probe set is a subset of the adapter set")
check(AdmissionTable.muxedContainers.isSubset(of: AdmissionTable.containers), "A2 muxed set is a subset of the adapter set")
check(AdmissionTable.hardwareAttemptCodecs.isSubset(of: AdmissionTable.videoCodecs), "A2 hw-attempt set is a subset of the video set")


// A4: function parity across the matrix, both surfaces, including the env override.
let matrix: [(String, String, Bool)] = [
    ("mov,mp4,m4a,3gp,3g2,mj2", "aac", true),
    ("matroska,webm", "pcm_s16le", true),
    ("wav", "pcm_s16le", false),          // wav is adapter-only, never a muxed shape
    ("mov,mp4,m4a,3gp,3g2,mj2", "mp3", true),   // arch-196t r2: mp3 admitted
    ("matroska,webm", "dts", true),             // arch-196t r2: owner regression case
    ("mpegts", "ac3", true),                    // arch-196t r2: mpegts admitted
    ("mpegts", "eac3", true),
    ("matroska,webm", "truehd", true),
    ("mov,mp4,m4a,3gp,3g2,mj2", "flac", true),
    ("matroska,webm", "opus", true),
    ("avi", "aac", false),
    ("mov,mp4,m4a,3gp,3g2,mj2", "vorbis", false), // still outside the matrix
]
for (c, a, want) in matrix {
    check(AdmissionTable.isAdmittedMuxedAudio(container: c, audioCodec: a) == want, "A4 table muxed \(c)/\(a)")
}
check(AdmissionTable.shouldAttemptHardware(videoCodec: "h264", environment: [:]), "A4 h264 attempts hw")
check(AdmissionTable.shouldAttemptHardware(videoCodec: "hevc", environment: [:]), "A4 hevc attempts hw")
check(!AdmissionTable.shouldAttemptHardware(videoCodec: "mpeg4", environment: [:]), "A4 mpeg4 stays software")
check(!AdmissionTable.shouldAttemptHardware(videoCodec: "av1", environment: [:]), "A4 av1 stays software-by-policy")
check(!AdmissionTable.shouldAttemptHardware(videoCodec: "h264", environment: ["GORAV_L3_DISABLE_HW": "1"]), "A4 env override forces software")

// A5: probe evaluate() contract unchanged by the collapse.
let policy = DemuxerPolicy()
check(policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0) == .admit(container: "mov,mp4,m4a,3gp,3g2,mj2", videoCodec: "h264"), "A5 video-only mov admitted")
check(policy.evaluate(containerName: "matroska,webm", videoCodecName: "hevc", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 0, audioCodecName: "aac") == .admit(container: "matroska,webm", videoCodec: "hevc"), "A5 muxed mkv hevc+aac admitted")
if case .reject = policy.evaluate(containerName: "wav", videoCodecName: nil, videoStreamCount: 0, audioStreamCount: 1, otherStreamCount: 0, audioCodecName: "pcm_s16le") {} else { check(false, "A5 wav rejected at probe (probe set is stricter)") ; }
check(true, "A5 wav rejected at probe (probe set is stricter)")
if case .reject = policy.evaluate(containerName: "avi", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0) {} else { check(false, "A5 unknown container rejected") }
check(true, "A5 unknown container rejected")
if case .reject = policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 1) {} else { check(false, "A5 other streams rejected pre-decode") }
check(true, "A5 other streams rejected pre-decode")
if case .reject = policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 2, otherStreamCount: 0, audioCodecName: "aac") {} else { check(false, "A5 two audio streams rejected") }
check(true, "A5 two audio streams rejected")
if case .reject = policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 0, audioCodecName: "vorbis") {} else { check(false, "A5 non-admitted muxed audio rejected") }
check(true, "A5 non-admitted muxed audio rejected")
// arch-196t r2 regression rows: the owner's refusal case and its siblings.
check(policy.evaluate(containerName: "matroska,webm", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 0, audioCodecName: "dts") == .admit(container: "matroska,webm", videoCodec: "h264"), "A5 owner case mkv+dts admitted")
check(policy.evaluate(containerName: "matroska,webm", videoCodecName: "hevc", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 0, audioCodecName: "dts") == .admit(container: "matroska,webm", videoCodec: "hevc"), "A5 mkv hevc+dts admitted")
check(policy.evaluate(containerName: "mpegts", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 0, audioCodecName: "ac3") == .admit(container: "mpegts", videoCodec: "h264"), "A5 ts h264+ac3 admitted")
check(policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "av1", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0) == .admit(container: "mov,mp4,m4a,3gp,3g2,mj2", videoCodec: "av1"), "A5 av1 video admitted")
check(policy.evaluate(containerName: "matroska,webm", videoCodecName: "vp9", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 0, audioCodecName: "opus") == .admit(container: "matroska,webm", videoCodec: "vp9"), "A5 mkv vp9+opus admitted")
// Subtitle streams are admitted (routed to seams on the playback path), not
// counted as "other"; unknown stream types still refuse.
check(policy.evaluate(containerName: "matroska,webm", videoCodecName: "hevc", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 0, subtitleStreamCount: 1, audioCodecName: "dts") == .admit(container: "matroska,webm", videoCodec: "hevc"), "A5 mkv+PGS subtitle stream admitted")
if case .reject = policy.evaluate(containerName: "matroska,webm", videoCodecName: "hevc", videoStreamCount: 1, audioStreamCount: 1, otherStreamCount: 1, subtitleStreamCount: 1, audioCodecName: "dts") {} else { check(false, "A5 unknown stream still rejected beside subtitles") }
check(true, "A5 unknown stream still rejected beside subtitles")
if case .reject = policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "wmv3", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0) {} else { check(false, "A5 wmv3 video refused") }
check(true, "A5 wmv3 video refused")


// ---- B-block (queue 30, d4 rung 2): source-class axis, local first. A-block above is untouched.
check(AdmissionTable.isAdmittedSource(kind: .local), "B1 local admitted")
check(AdmissionTable.admittedSourceKinds == [.local, .remote, .iptv, .webTorrent, .ytdl, .archiveOrg], "B1 admitted source kinds exact (local + remote + iptv + webTorrent + ytdl + archiveOrg)")
check(!AdmissionTable.isAdmittedRemoteURL("file:///tmp/x"), "B2 remote kind alone does not admit a non-http URL")
check(policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .local) == .admit(container: "mov,mp4,m4a,3gp,3g2,mj2", videoCodec: "h264"), "B3 local kind passes policy")
check(policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0) == .admit(container: "mov,mp4,m4a,3gp,3g2,mj2", videoCodec: "h264"), "B4 nil source kind keeps the A-block behavior")

// B5/B6: real fixtures through FFmpegSoftwareDecoder.open.
let cwd = FileManager.default.currentDirectoryPath
var epoch: UInt64 = 100
for name in ["seekcheck-src.mp4", "clip-bbb-10s.mov"] {
    let path = "\(cwd)/fixtures/\(name)"
    guard FileManager.default.fileExists(atPath: path) else { check(false, "B5 fixture present \(name)", path); continue }
    epoch += 1
    let d = FFmpegSoftwareDecoder()
    do {
        try d.pinLocalRoots(["\(cwd)/fixtures"])
        try await d.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: SessionID(uncheckedEpoch: epoch))
        check(true, "B5 local open reaches the decoder \(name)")
        await d.close(session: SessionID(uncheckedEpoch: epoch))
    } catch { check(false, "B5 local open reaches the decoder \(name)", "\(error)") }
    epoch += 1
    let d2 = FFmpegSoftwareDecoder()
    do {
        try d2.pinLocalRoots(["\(cwd)/fixtures"])
        try await d2.open(source: SourceDescriptor(id: path, kind: .remote, seekable: true), session: SessionID(uncheckedEpoch: epoch))
        check(false, "B6 remote kind rejected before any network access \(name)", "open succeeded")
    } catch let e as FFmpegSoftwareDecoder.OpenError {
        if case .rejected(let m) = e { check(m.contains("remote scheme not admitted"), "B6 remote kind with a scheme-less local path rejected by the admission decision, not I/O \(name)", m) }
        else { check(false, "B6 remote kind rejected by the admission decision \(name)", "\(e)") }
    } catch { check(false, "B6 remote kind rejected by the admission decision \(name)", "\(error)") }
}


// ---- C-block (queue 31, d4 rung 3): http source class behind a scheme allowlist. A and B above keep their checks (B1/B2/B6 edited, see report).
check(AdmissionTable.admittedRemoteSchemes == ["http", "https"], "C1 scheme allowlist exact")
check(AdmissionTable.isAdmittedRemoteURL("http://127.0.0.1:8901/clip-bbb-10s.mov"), "C1 http:// admitted")
check(AdmissionTable.isAdmittedRemoteURL("https://example.invalid/x.mov"), "C1 https:// admitted")
check(AdmissionTable.isAdmittedRemoteURL("HTTP://127.0.0.1/x.mov"), "C1 scheme match is case-insensitive")
for u in ["ftp://h/x.mov", "file:///tmp/x.mov", "rtmp://h/x", "x.mov", "/tmp/x.mov"] {
    check(!AdmissionTable.isAdmittedRemoteURL(u), "C2 \(u) rejected")
    let d = policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1,
                            audioStreamCount: 0, otherStreamCount: 0, sourceKind: .remote, sourceURL: u)
    let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
    if case .reject(let reason) = d { check(reason.contains(named), "C2 \(u) rejection names the scheme \(named)", reason) } else { check(false, "C2 \(u) rejected by policy") }
}
check(policy.evaluate(containerName: "mov,mp4,m4a,3gp,3g2,mj2", videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .remote, sourceURL: "http://127.0.0.1:8901/a.mov") == .admit(container: "mov,mp4,m4a,3gp,3g2,mj2", videoCodec: "h264"), "C2 policy admits remote http")

let httpURL = "http://127.0.0.1:8901/clip-bbb-10s.mov"
epoch += 1
let dr = FFmpegSoftwareDecoder()
var c4Admission = true
var c4Info = "open ok"
do {
    try await dr.open(source: SourceDescriptor(id: httpURL, kind: .remote, seekable: true), session: SessionID(uncheckedEpoch: epoch))
    await dr.close(session: SessionID(uncheckedEpoch: epoch))
} catch let e as FFmpegSoftwareDecoder.OpenError {
    c4Info = "\(e)"
    if case .rejected(let m) = e, m.contains("not admitted") || m.contains("local sources only") { c4Admission = false }
} catch { c4Info = "\(error)" }
check(c4Admission, "C4 http URL passes admission and the open reaches the decoder (decode outcome out of scope)", c4Info)
print("INFO C4 open outcome after admission: \(c4Info)")
// C2b: remote ftp/file/rtmp opens are rejected by the adapter before any I/O.
for u in ["ftp://127.0.0.1/x.mov", "file:///etc/hostname", "rtmp://127.0.0.1/x"] {
    epoch += 1
    let du = FFmpegSoftwareDecoder()
    do {
        try await du.open(source: SourceDescriptor(id: u, kind: .remote, seekable: true), session: SessionID(uncheckedEpoch: epoch))
        check(false, "C2b adapter rejects remote \(u)", "open succeeded")
    } catch let e as FFmpegSoftwareDecoder.OpenError {
        let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
        if case .rejected(let m) = e { check(m.contains("remote scheme not admitted: \(named)"), "C2b adapter rejects remote \(u) naming the scheme", m) }
        else { check(false, "C2b adapter rejects remote \(u)", "\(e)") }
    } catch { check(false, "C2b adapter rejects remote \(u)", "\(error)") }
}

// ---- D-block (queue 32, d4 rung 4): iptv source class behind the same http/https allowlist. Admission decision only; no HLS/.m3u8 or IPTV decode claim.
let mp4c = "mov,mp4,m4a,3gp,3g2,mj2"
check(AdmissionTable.isAdmittedSource(kind: .iptv), "D1 iptv kind admitted by table")
check(AdmissionTable.isAdmittedRemoteURL("http://127.0.0.1:8901/clip-bbb-10s.mov") && AdmissionTable.isAdmittedRemoteURL("https://example.invalid/x"), "D1 iptv uses the http/https allowlist")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .iptv, sourceURL: "http://127.0.0.1:8901/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "D1 policy admits iptv http")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .iptv, sourceURL: "https://example.invalid/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "D1 policy admits iptv https")
for u in ["ftp://127.0.0.1/x", "file:///etc/hostname", "rtmp://127.0.0.1/x", "rtsp://127.0.0.1/x", "plain-id-no-scheme"] {
    let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
    check(!AdmissionTable.isAdmittedRemoteURL(u), "D2 iptv \(u) not on allowlist")
    let d = policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .iptv, sourceURL: u)
    if case .reject(let reason) = d { check(reason.contains("iptv scheme not admitted: \(named)"), "D2 iptv \(u) policy rejection names kind and scheme", reason) } else { check(false, "D2 iptv \(u) rejected by policy") }
}
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .iptv) == .reject(reason: "iptv source without a URL"), "D2 iptv without a URL rejected")
check(AdmissionTable.schemeGatedKinds == [.remote, .iptv, .webTorrent, .ytdl, .archiveOrg], "D3 scheme-gated kinds exact")
for u in ["ftp://127.0.0.1/x.mov", "file:///etc/hostname", "rtmp://127.0.0.1/x"] {
    epoch += 1
    let di = FFmpegSoftwareDecoder()
    do {
        try await di.open(source: SourceDescriptor(id: u, kind: .iptv, seekable: true), session: SessionID(uncheckedEpoch: epoch))
        check(false, "D3 adapter rejects iptv \(u)", "open succeeded")
    } catch let e as FFmpegSoftwareDecoder.OpenError {
        let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
        if case .rejected(let m) = e { check(m.contains("iptv scheme not admitted: \(named)"), "D3 adapter rejects iptv \(u) naming kind and scheme", m) }
        else { check(false, "D3 adapter rejects iptv \(u)", "\(e)") }
    } catch { check(false, "D3 adapter rejects iptv \(u)", "\(error)") }
}
epoch += 1
let dpt = FFmpegSoftwareDecoder()
var d4Admission = true
var d4Info = "open ok"
do {
    try await dpt.open(source: SourceDescriptor(id: httpURL, kind: .iptv, seekable: true), session: SessionID(uncheckedEpoch: epoch))
    await dpt.close(session: SessionID(uncheckedEpoch: epoch))
} catch let e as FFmpegSoftwareDecoder.OpenError {
    d4Info = "\(e)"
    if case .rejected(let m) = e, m.contains("not admitted") || m.contains("local sources only") { d4Admission = false }
} catch { d4Info = "\(error)" }
check(d4Admission, "D4 iptv http URL passes admission and the open reaches the decoder (decode outcome out of scope)", d4Info)
print("INFO D4 open outcome after admission: \(d4Info)")
// ---- E-block (queue 33, d4 rung 5): webTorrent source class behind the same http/https allowlist (id is an HTTP(S) URL via the wt_server bridge). D5 of rung 4 (webTorrent rejected) flips to admitted. Admission decision only; no torrent/bridge decode claim.
check(AdmissionTable.isAdmittedSource(kind: .webTorrent), "E1 webTorrent kind admitted by table (D5 flipped)")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .webTorrent, sourceURL: "http://127.0.0.1:8901/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "E1 policy admits webTorrent http")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .webTorrent, sourceURL: "https://example.invalid/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "E1 policy admits webTorrent https")
for u in ["ftp://127.0.0.1/x", "file:///etc/hostname", "rtmp://127.0.0.1/x", "magnet://x", "plain-id-no-scheme"] {
    let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
    let d = policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .webTorrent, sourceURL: u)
    if case .reject(let reason) = d { check(reason.contains("webTorrent scheme not admitted: \(named)"), "E2 webTorrent \(u) policy rejection names kind and scheme", reason) } else { check(false, "E2 webTorrent \(u) rejected by policy") }
}
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .webTorrent) == .reject(reason: "webTorrent source without a URL"), "E2 webTorrent without a URL rejected")
for u in ["ftp://127.0.0.1/x.mov", "file:///etc/hostname", "rtmp://127.0.0.1/x"] {
    epoch += 1
    let dw = FFmpegSoftwareDecoder()
    do {
        try await dw.open(source: SourceDescriptor(id: u, kind: .webTorrent, seekable: true), session: SessionID(uncheckedEpoch: epoch))
        check(false, "E3 adapter rejects webTorrent \(u)", "open succeeded")
    } catch let e as FFmpegSoftwareDecoder.OpenError {
        let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
        if case .rejected(let m) = e { check(m.contains("webTorrent scheme not admitted: \(named)"), "E3 adapter rejects webTorrent \(u) naming kind and scheme", m) }
        else { check(false, "E3 adapter rejects webTorrent \(u)", "\(e)") }
    } catch { check(false, "E3 adapter rejects webTorrent \(u)", "\(error)") }
}
epoch += 1
let dwt = FFmpegSoftwareDecoder()
var e4Admission = true
var e4Info = "open ok"
do {
    try await dwt.open(source: SourceDescriptor(id: httpURL, kind: .webTorrent, seekable: true), session: SessionID(uncheckedEpoch: epoch))
    await dwt.close(session: SessionID(uncheckedEpoch: epoch))
} catch let e as FFmpegSoftwareDecoder.OpenError {
    e4Info = "\(e)"
    if case .rejected(let m) = e, m.contains("not admitted") || m.contains("local sources only") { e4Admission = false }
} catch { e4Info = "\(error)" }
check(e4Admission, "E4 webTorrent http URL passes admission and the open reaches the decoder (decode outcome out of scope)", e4Info)
print("INFO E4 open outcome after admission: \(e4Info)")
check(AdmissionTable.admittedSourceKinds == [.local, .remote, .iptv, .webTorrent, .ytdl, .archiveOrg] && AdmissionTable.schemeGatedKinds == [.remote, .iptv, .webTorrent, .ytdl, .archiveOrg], "E5 admitted and scheme-gated kinds exact")

// ---- F-block (queue 34, d4 rung 6): ytdl source class (new SourceDescriptor.Kind.ytdl) behind the same http/https allowlist. Admission decision only; no ytdl resolution or network decode claim.
check(AdmissionTable.isAdmittedSource(kind: .ytdl), "F1 ytdl kind admitted by table")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .ytdl, sourceURL: "http://127.0.0.1:8901/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "F1 policy admits ytdl http")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .ytdl, sourceURL: "https://example.invalid/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "F1 policy admits ytdl https")
for u in ["ftp://127.0.0.1/x", "rtsp://127.0.0.1/x", "plain-id-no-scheme"] {
    let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
    let d = policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .ytdl, sourceURL: u)
    if case .reject(let reason) = d { check(reason.contains("ytdl scheme not admitted: \(named)"), "F2 ytdl \(u) policy rejection names kind and scheme", reason) } else { check(false, "F2 ytdl \(u) rejected by policy") }
}
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .ytdl) == .reject(reason: "ytdl source without a URL"), "F2 ytdl without a URL rejected")
epoch += 1
let dyf = FFmpegSoftwareDecoder()
do {
    try await dyf.open(source: SourceDescriptor(id: "ftp://127.0.0.1/x.mov", kind: .ytdl, seekable: true), session: SessionID(uncheckedEpoch: epoch))
    check(false, "F3 adapter rejects ytdl ftp:// before any I/O", "open succeeded")
} catch let e as FFmpegSoftwareDecoder.OpenError {
    if case .rejected(let m) = e { check(m.contains("ytdl scheme not admitted: ftp"), "F3 adapter rejects ytdl ftp:// naming kind and scheme", m) } else { check(false, "F3 adapter rejects ytdl ftp://", "\(e)") }
} catch { check(false, "F3 adapter rejects ytdl ftp://", "\(error)") }
epoch += 1
let dyt = FFmpegSoftwareDecoder()
var f4Admission = true
var f4Info = "open ok"
do {
    try await dyt.open(source: SourceDescriptor(id: httpURL, kind: .ytdl, seekable: true), session: SessionID(uncheckedEpoch: epoch))
    await dyt.close(session: SessionID(uncheckedEpoch: epoch))
} catch let e as FFmpegSoftwareDecoder.OpenError {
    f4Info = "\(e)"
    if case .rejected(let m) = e, m.contains("not admitted") || m.contains("local sources only") { f4Admission = false }
} catch { f4Info = "\(error)" }
check(f4Admission, "F4 ytdl http URL passes admission and the open reaches the decoder (decode outcome out of scope)", f4Info)
print("INFO F4 open outcome after admission: \(f4Info)")
check(AdmissionTable.admittedSourceKinds == [.local, .remote, .iptv, .webTorrent, .ytdl, .archiveOrg] && AdmissionTable.schemeGatedKinds == [.remote, .iptv, .webTorrent, .ytdl, .archiveOrg] && AdmissionTable.admittedRemoteSchemes == ["http", "https"], "F5 admitted and scheme-gated kinds exact, allowlist unchanged")

// ---- G-block (queue 35, d4 rung 7, final): archiveOrg source class (new SourceDescriptor.Kind.archiveOrg) behind the same http/https allowlist. Admission decision only; no archive.org network or decode claim.
check(AdmissionTable.isAdmittedSource(kind: .archiveOrg), "G1 archiveOrg kind admitted by table")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .archiveOrg, sourceURL: "http://127.0.0.1:8901/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "G1 policy admits archiveOrg http")
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .archiveOrg, sourceURL: "https://example.invalid/a.mov") == .admit(container: mp4c, videoCodec: "h264"), "G1 policy admits archiveOrg https")
for u in ["ftp://127.0.0.1/x", "rtsp://127.0.0.1/x", "plain-id-no-scheme"] {
    let named = AdmissionTable.remoteScheme(of: u) ?? "(none)"
    let d = policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .archiveOrg, sourceURL: u)
    if case .reject(let reason) = d { check(reason.contains("archiveOrg scheme not admitted: \(named)"), "G2 archiveOrg \(u) policy rejection names kind and scheme", reason) } else { check(false, "G2 archiveOrg \(u) rejected by policy") }
}
check(policy.evaluate(containerName: mp4c, videoCodecName: "h264", videoStreamCount: 1, audioStreamCount: 0, otherStreamCount: 0, sourceKind: .archiveOrg) == .reject(reason: "archiveOrg source without a URL"), "G2 archiveOrg without a URL rejected")
epoch += 1
let dag = FFmpegSoftwareDecoder()
do {
    try await dag.open(source: SourceDescriptor(id: "ftp://127.0.0.1/x.mov", kind: .archiveOrg, seekable: true), session: SessionID(uncheckedEpoch: epoch))
    check(false, "G3 adapter rejects archiveOrg ftp:// before any I/O", "open succeeded")
} catch let e as FFmpegSoftwareDecoder.OpenError {
    if case .rejected(let m) = e { check(m.contains("archiveOrg scheme not admitted: ftp"), "G3 adapter rejects archiveOrg ftp:// naming kind and scheme", m) } else { check(false, "G3 adapter rejects archiveOrg ftp://", "\(e)") }
} catch { check(false, "G3 adapter rejects archiveOrg ftp://", "\(error)") }
epoch += 1
let dat = FFmpegSoftwareDecoder()
var g4Admission = true
var g4Info = "open ok"
do {
    try await dat.open(source: SourceDescriptor(id: httpURL, kind: .archiveOrg, seekable: true), session: SessionID(uncheckedEpoch: epoch))
    await dat.close(session: SessionID(uncheckedEpoch: epoch))
} catch let e as FFmpegSoftwareDecoder.OpenError {
    g4Info = "\(e)"
    if case .rejected(let m) = e, m.contains("not admitted") || m.contains("local sources only") { g4Admission = false }
} catch { g4Info = "\(error)" }
check(g4Admission, "G4 archiveOrg http URL passes admission and the open reaches the decoder (decode outcome out of scope)", g4Info)
print("INFO G4 open outcome after admission: \(g4Info)")
check(AdmissionTable.admittedSourceKinds == [.local, .remote, .iptv, .webTorrent, .ytdl, .archiveOrg] && AdmissionTable.schemeGatedKinds == [.remote, .iptv, .webTorrent, .ytdl, .archiveOrg] && AdmissionTable.admittedRemoteSchemes == ["http", "https"], "G5 admitted and scheme-gated kinds exact, allowlist unchanged (d4 ladder complete)")

print(failures == 0 ? "ALL ADMISSION TESTS PASS" : "ADMISSION TEST FAILURES: \(failures)")
Foundation.exit(failures == 0 ? 0 : 1)

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/admission-tests/main.swift').read_bytes()).hexdigest()=='9f33357bb1261d03ecd6792e3e332786b9243e731cdb992cf6525da082826d4f'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-04; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-04; baseline only, product change and semantic test still required
```

secret scan: clean
