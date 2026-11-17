# W-gdb-198z-in2tinct-03 - Relocated fixture consumer active-media-inventory-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-03",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/active-media-inventory-tests/main.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer active-media-inventory-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/active-media-inventory-tests/main.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-03.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-03",
    "paths": [
      "Sources/active-media-inventory-tests/main.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-03.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-03.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.508605+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/active-media-inventory-tests/main.swift",
        "block": "source1",
        "sha256": "07f1206b44dacb06045f257157b343c3ee5add6205328acfa0decd1873a05580"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-03.py",
        "block": "fixtures1",
        "sha256": "caf148745774e439f61c05b192956d7c21cffa6b59270685aa3adb8aed82ed9c"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "3d8f23ca2a8eea0595d0dac05496282caeb3152519a83f9a6dab0d74bae247c7",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-03; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "7c5d61128069b0366d323bbf37e6d52f347d65bff0dcab5e34da417b57374829"
  }
}
```

```swift id=source1
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import GorAVCore
import GorAVFFmpegAdapter

@main struct ActiveInventoryChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let pins=root.appendingPathComponent("fixtures")
        let fixture=pins.appendingPathComponent("active-inventory-chapters.mkv").path
        let sid=SessionID(uncheckedEpoch:6101), other=SessionID(uncheckedEpoch:6102)
        let video=FFmpegSoftwareDecoder()
        try video.pinLocalRoots([pins.path])
        precondition(video.activeMediaInventory(session:sid) == nil)
        do {
            try await video.open(source:SourceDescriptor(id:"/missing-inventory-fixture",kind:.local,seekable:true),session:sid)
            fatalError("missing source admitted")
        } catch { }
        precondition(video.activeMediaInventory(session:sid) == nil)
        try await video.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:sid)
        let first=video.activeMediaInventory(session:sid)!
        precondition(first.inventory.tracks.contains { $0.kind == .video && $0.codec == "mpeg4" })
        precondition(first.inventory.tracks.contains { $0.kind == .audio && $0.language == "eng" })
        precondition(first.inventory.chapters.count == 2)
        precondition(first.inventory.chapters[0].title == "Opening")
        precondition(first.inventory.metadata["title"] == "GorAV active inventory fixture")
        precondition(abs(first.inventory.durationSeconds! - 1) < 0.1)
        print("PASS actual active video context tracks/duration/tags/chapters")
        precondition(video.activeMediaInventory(session:other) == nil)
        for _ in 0..<100 { precondition(video.activeMediaInventory(session:sid,expected:first.identity) == first) }
        do {
            try await video.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:other)
            fatalError("busy open admitted")
        } catch { }
        precondition(video.activeMediaInventory(session:sid,expected:first.identity) == first)
        try await video.seek(toSeconds:0.5,session:sid)
        precondition(video.activeMediaInventory(session:sid,expected:first.identity) == nil)
        let seeked=video.activeMediaInventory(session:sid)!
        precondition(seeked.identity != first.identity && seeked.inventory == first.inventory)
        print("PASS stale revision fenced without reextract/reopen")
        _ = await video.closeAndReport(session:sid)
        precondition(video.activeMediaInventory(session:sid) == nil)
        try await video.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:other)
        precondition(video.activeMediaInventory(session:other,expected:seeked.identity) == nil)
        precondition(first.inventory.chapters[1].title == "Closing") // immutable detached value
        _ = await video.closeAndReport(session:other)
        print("PASS close/replacement invalidates old identity, detached values remain safe")
        let audio=FFmpegSoftwareAudioDecoder()
        try audio.pinLocalRoots([pins.path])
        try await audio.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:sid)
        let sound=audio.activeMediaInventory(session:sid)!
        precondition(sound.inventory.chapters == first.inventory.chapters)
        precondition(sound.inventory.metadata["title"] == first.inventory.metadata["title"])
        await audio.close(session:sid)
        precondition(audio.activeMediaInventory(session:sid) == nil)
        print("PASS active audio context has actual container inventory")

        // HTTP serves one real WAV. Count requests after initial open, then
        // prove snapshots add none. Initial provider range/probe traffic is not
        // confused with a separate inventory open.
        let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let script=dir.appendingPathComponent("server.py"), portFile=dir.appendingPathComponent("port"), count=dir.appendingPathComponent("count")
        try """
        import http.server,sys,threading
        data=open(sys.argv[1],'rb').read()
        lock=threading.Lock(); n=0
        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                global n
                with lock:
                    n+=1
                    open(sys.argv[3],'w').write(str(n))
                self.send_response(200)
                self.send_header('Content-Length',str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            def log_message(self,*a): pass
        s=http.server.ThreadingHTTPServer(('127.0.0.1',0),H)
        open(sys.argv[2],'w').write(str(s.server_address[1]))
        s.serve_forever()
        """.write(to:script,atomically:true,encoding:.utf8)
        let server=Process();server.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        server.arguments=[script.path,pins.appendingPathComponent("tone-48k.wav").path,portFile.path,count.path]
        try server.run();defer { kill(server.processIdentifier, SIGKILL); server.waitUntilExit() }
        var port:String?
        for _ in 0..<100 {
            port=try? String(contentsOf:portFile,encoding:.utf8)
            if port != nil { break }
            try await Task.sleep(nanoseconds:20_000_000)
        }
        guard let port else { fatalError("HTTP fixture server not ready") }
        let remote=FFmpegSoftwareAudioDecoder()
        remote.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:2)
        try await remote.open(source:SourceDescriptor(id:"http://127.0.0.1:\(port)/tone.wav",kind:.remote,seekable:false),session:sid)
        let before=try String(contentsOf:count,encoding:.utf8)
        let cached=remote.activeMediaInventory(session:sid)!
        for _ in 0..<100 { precondition(remote.activeMediaInventory(session:sid,expected:cached.identity) == cached) }
        let after=try String(contentsOf:count,encoding:.utf8)
        precondition(before == after && Int(before)! > 0)
        await remote.close(session:sid)
        precondition(remote.activeMediaInventory(session:sid) == nil)
        print("PASS HTTP snapshots use original active context, zero additional requests")
        print("ALL ACTIVE MEDIA INVENTORY CHECKS PASS (not track selection/native UI)")
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/active-media-inventory-tests/main.swift').read_bytes()).hexdigest()=='07f1206b44dacb06045f257157b343c3ee5add6205328acfa0decd1873a05580'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-03; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-03; baseline only, product change and semantic test still required
```

secret scan: clean
