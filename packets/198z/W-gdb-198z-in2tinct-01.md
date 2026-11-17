# W-gdb-198z-in2tinct-01 - Relocated fixture consumer media-inventory-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-01",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/media-inventory-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer media-inventory-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/media-inventory-tests/main.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-01.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-01",
    "paths": [
      "Sources/media-inventory-tests/main.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-01.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-01.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.469006+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/media-inventory-tests/main.swift",
        "block": "source1",
        "sha256": "ac93a35e5b8c924163518df6266bf2e72d722424a1c7fe185e9e00d6e63d7b9b"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-01.py",
        "block": "fixtures1",
        "sha256": "3c701bc27d0d858cddc02cbdfdb83073c2656081f5aed6802878d69f63750806"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "73765d805561a172cc55f3b5762d33dc055355dcdede08cd8d0a29d3248bd8af",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-01; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "c95c57da659f25328a7901c8c86027b822130d0abd4dbabd1132759d6e7cf57a"
  }
}
```

```swift id=source1
import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// R10 (arch-195b) witness: media inventory over real containers through the
// admitted open path; image-duration rule as pure behavior on typed tracks.

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
let pins = [URL(fileURLWithPath: root)]

// M-series: muxed mp4 inventory
do {
    let inv = try MediaInventory.load(path: root + "/fixtures/e1-h264-aac-10s.mp4", pinnedRoots: pins)
    check("M1 two tracks", inv.tracks.count == 2, "\(inv.tracks.count)")
    let v = inv.tracks.first { $0.kind == .video }
    let a = inv.tracks.first { $0.kind == .audio }
    check("M2 video track h264 default", v?.codec == "h264" && v?.isDefault == true, "\(String(describing: v))")
    check("M3 audio track aac", a?.codec == "aac", "\(String(describing: a))")
    check("M4 duration about 10s from container", inv.durationSeconds != nil && abs(inv.durationSeconds! - 10.0) < 0.5, "\(String(describing: inv.durationSeconds))")
    check("M5 duration provenance container", inv.effectiveDurationSeconds().provenance == .container)
    check("M6 no chapters is a fact", inv.chapters.isEmpty)
    check("M7 metadata map is typed (may be empty)", inv.metadata.count >= 0)
} catch {
    check("M1 load threw", false, "\(error)")
}

// A-series: audio-only wav inventory
do {
    let inv = try MediaInventory.load(path: root + "/fixtures/tone-48k.wav", pinnedRoots: pins)
    check("A1 one audio track pcm_s16le", inv.tracks.count == 1 && inv.tracks[0].kind == .audio && inv.tracks[0].codec == "pcm_s16le", "\(inv.tracks)")
    check("A2 wav has a container duration", inv.durationSeconds != nil && abs(inv.durationSeconds! - 1.0) < 0.2, "\(String(describing: inv.durationSeconds))")
    check("A3 effective duration is the container one", inv.effectiveDurationSeconds().provenance == .container)
} catch {
    check("A1 wav load threw", false, "\(error)")
}

// I-series: image-duration rule (pure behavior on typed tracks)
func fakeTrack(pic: Bool) -> MediaInventory.Track {
    MediaInventory.Track(index: 0, kind: .video, codec: "mjpeg", language: nil, title: nil, isDefault: true, isAttachedPicture: pic, durationSeconds: nil)
}
let picInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I1 picture-only source gets the image duration", picInv.effectiveDurationSeconds().seconds == MediaInventory.defaultImageDurationSeconds && picInv.effectiveDurationSeconds().provenance == .imageDurationRule)
check("I2 image duration configurable", picInv.effectiveDurationSeconds(imageDuration: 42).seconds == 42)
let vidInv = MediaInventory(tracks: [fakeTrack(pic: false)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I3 non-picture source without duration stays unknown", vidInv.effectiveDurationSeconds().seconds == nil && vidInv.effectiveDurationSeconds().provenance == .unknown)
let durInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: 3.5, durationProvenance: .container)
check("I4 container duration wins over the rule", durInv.effectiveDurationSeconds().seconds == 3.5 && durInv.effectiveDurationSeconds().provenance == .container)

// X-series: admission parity with the decoders
do {
    _ = try MediaInventory.load(path: "/etc/hostname", pinnedRoots: pins)
    check("X1 outside pinned roots refused", false, "loaded")
} catch MediaInventory.LoadError.rejected(let m) {
    check("X1 outside pinned roots refused", m.contains("outside pinned roots"), m)
} catch { check("X1 outside pinned roots refused", false, "\(error)") }
do {
    _ = try MediaInventory.load(path: "ftp://example.com/x.mp4", pinnedRoots: pins)
    check("X2 non-admitted scheme refused", false, "loaded")
} catch MediaInventory.LoadError.rejected(let m) {
    check("X2 non-admitted scheme refused", m.contains("scheme not admitted"), m)
} catch { check("X2 non-admitted scheme refused", false, "\(error)") }
do {
    _ = try MediaInventory.load(path: "http://user:s3cr3t@127.0.0.1:1/x.mp4?token=abc123", pinnedRoots: pins)
    check("X3 dead endpoint throws", false, "loaded")
} catch {
    let m = "\(error)"
    check("X3 error redacts credentials", m.contains("REDACTED") && !m.contains("s3cr3t") && !m.contains("abc123"), m)
}

check("I5 shipped image default is two seconds", MediaInventory.defaultImageDurationSeconds == 2)
check("I6 invalid image duration stays unknown", picInv.effectiveDurationSeconds(imageDuration: .nan).seconds == nil)
print(failures == 0 ? "media-inventory-tests: all pass" : "media-inventory-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/media-inventory-tests/main.swift').read_bytes()).hexdigest()=='ac93a35e5b8c924163518df6266bf2e72d722424a1c7fe185e9e00d6e63d7b9b'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-01; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-01; baseline only, product change and semantic test still required
```

secret scan: clean
