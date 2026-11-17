# W-gdb-198z-in2tinct-02 - Relocated fixture consumer decoder-lifetime-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-02",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/decoder-lifetime-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer decoder-lifetime-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/decoder-lifetime-tests/main.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-02.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-02",
    "paths": [
      "Sources/decoder-lifetime-tests/main.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-02.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-02.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.488771+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/decoder-lifetime-tests/main.swift",
        "block": "source1",
        "sha256": "5d91891d75a33456a96002b6e1649a02e3d0ea5e99cd4d8df3cd2355f3964330"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-02.py",
        "block": "fixtures1",
        "sha256": "2edcaa37e611ff9df8ef266637c6f6b54cb4ed04040dbeb54b97ca09a77ef352"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "8e4cfd4eb1dd16f220c16061ba8252832b7a97b44b69d10688969ad786b8c29f",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-02; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "bff1f093a83a46d12eaf5b16ac40d2dab3fa370841f9287bfd09c6f507e62b9e"
  }
}
```

```swift id=source1
import Foundation
import GorAVPlaybackCore
import GorAVFFmpegAdapter
import GorAVCore

// 195b-59: REAL software adapters and tracked local fixtures. Needs the pinned
// FFmpeg headers/libs. No hardware/device/native session acceptance is implied.
@main struct DecoderLifetimeChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let fixture=root.appendingPathComponent("fixtures/clip-bbb-10s.mov").path
        let tone=root.appendingPathComponent("fixtures/tone-48k.wav").path
        let registry=DecoderInventoryStore()
        let sid=SessionID(uncheckedEpoch:901)
        let foreign=SessionID(uncheckedEpoch:902)
        let reopened=SessionID(uncheckedEpoch:903)
        var video:FFmpegSoftwareDecoder?=FFmpegSoftwareDecoder(decoderInventory:registry)
        try video!.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        do {
            try await video!.open(source:SourceDescriptor(id:"/missing-decoder-lifetime",kind:.local,seekable:true),session:sid)
            fatalError("missing video opened")
        } catch { }
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS failed video open registers nothing")
        try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:sid)
        let first=registry.activeSnapshots(session:sid.epoch)
        precondition(first.count == 1 && first[0].kind == .videoSoftware)
        precondition(first[0].sourceID?.hasPrefix("video:") == true && first[0].revisionAtOpen == 1)
        print("PASS real video open registers immutable opaque identity")
        do {
            try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:foreign)
            fatalError("busy video reopen admitted")
        } catch { }
        precondition(registry.snapshot(first[0].identity) != nil)
        _ = await video!.closeAndReport(session:foreign)
        precondition(registry.snapshot(first[0].identity) != nil)
        print("PASS failed reopen and foreign close preserve live registration")
        _ = await video!.closeAndReport(session:sid)
        precondition(registry.snapshot(first[0].identity) == nil)
        try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:reopened)
        let second=registry.activeSnapshots(session:reopened.epoch)
        precondition(second.count == 1 && second[0].identity != first[0].identity)
        precondition(second[0].sourceID != first[0].sourceID)
        print("PASS close/reopen never revives prior registration")
        video=nil
        precondition(registry.activeSnapshots(session:reopened.epoch).isEmpty)
        print("PASS abandoned real video deinit deregisters")
        var audio:FFmpegSoftwareAudioDecoder?=FFmpegSoftwareAudioDecoder(decoderInventory:registry)
        try audio!.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        do {
            try await audio!.open(source:SourceDescriptor(id:"/missing-audio-lifetime",kind:.local,seekable:true),session:sid)
            fatalError("missing audio opened")
        } catch { }
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS failed audio open registers nothing")
        try await audio!.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        let sound=registry.activeSnapshots(session:sid.epoch)
        precondition(sound.count == 1 && sound[0].kind == .audioSoftware)
        precondition(sound[0].sourceID != nil && sound[0].revisionAtOpen == 1)
        await audio!.close(session:foreign)
        precondition(registry.snapshot(sound[0].identity) != nil)
        await audio!.close(session:sid)
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS real audio lifetime/foreign close fence")
        try await audio!.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        audio=nil
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS abandoned real audio deinit deregisters")
        registry.invalidateSession(sid.epoch)
        let stale=FFmpegSoftwareAudioDecoder(decoderInventory:registry)
        try stale.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        try await stale.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        await stale.close(session:sid)
        print("PASS invalidated-session successful adapter open cannot revive metadata")
        print("ALL DECODER LIFETIME CHECKS PASS (software registry only)")
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/decoder-lifetime-tests/main.swift').read_bytes()).hexdigest()=='5d91891d75a33456a96002b6e1649a02e3d0ea5e99cd4d8df3cd2355f3964330'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-02; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-02; baseline only, product change and semantic test still required
```

secret scan: clean
