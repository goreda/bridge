# W-gdb-d62: 195b-62 follow-on: video remote open deadline witness for a dribbled body (rev 2)

Rev 2 after the ops semantic gate. video-remote-open-tests has `/stall` (headers never sent) but no dribbled-body case, while the audio witness has one (D3). Add the dribble route and the checks below. Rev 2 adds an independent 10 s watchdog around every new open, so if open never returns (a deadline regression) the suite prints FAIL and exits 1 instead of hanging; the elapsed-time precondition alone only runs after open returns. The decoder code under test is already landed; if a check fails, fix FFmpegSoftwareDecoder so the open+stream-info deadline also bounds a trickling body and return the fix with the patch.

Not in scope: HTTPS/TLS provider, stuck-decode interruption, cache state, audio decoder. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
  "packet": "W-gdb-d62",
  "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
  "scope": "implementation",
  "product_repo": "goreda/gorav",
  "product_branch": "engine",
  "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
  "touched_files": [
    {
      "path": "Sources/video-remote-open-tests/main.swift",
      "excerpt_block": "ex_server",
      "lines": "17-44"
    },
    {
      "path": "Sources/video-remote-open-tests/main.swift",
      "excerpt_block": "ex_stall_test",
      "lines": "76-84"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift",
      "excerpt_block": "ex_deadline_arm",
      "lines": "736-738"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift",
      "excerpt_block": "ex_deadline_clear",
      "lines": "977-986"
    }
  ],
  "excerpt_sha256_8": {
    "ex_server": "638469b8",
    "ex_stall_test": "10f7de1a",
    "ex_deadline_arm": "4323c114",
    "ex_deadline_clear": "26a032ad"
  },
  "interface": {
    "signatures": "No new product API. Existing: FFmpegSoftwareDecoder.remoteOpenOptions: SourceOpenOptions?; open(source: SourceDescriptor, session: SessionID) async throws; closeAndReport(session:) async; activeMediaInventory(session:) -> ActiveMediaInventorySnapshot?. New test-only nested func openWatchdog(_:) -> DispatchWorkItem.",
    "types": "SourceOpenOptions(headers:cookies:openDeadlineSeconds:), SessionID(uncheckedEpoch:), SourceDescriptor(id:kind:seekable:), unchanged.",
    "ownership_lifetime": "Each decoder instance is created per check; the python fixture server is owned by the test process and killed by defer. The open attempt owns its interrupt box and slot; the deadline is cleared at successful open commit. Each watchdog is cancelled right after its open returns.",
    "caller": "VideoRemoteOpenChecks.main in video-remote-open-tests.",
    "callee": "FFmpegSoftwareDecoder.open -> goravR3OpenInput / avformat_open_input and avformat_find_stream_info with the interrupt callback."
  },
  "test": {
    "command": "swift run video-remote-open-tests",
    "expected": "Exit 0. Output has the existing PASS lines plus three new lines after \"PASS deadline interrupts actual URL open before response headers\": \"PASS deadline interrupts actual URL open stalled mid-body (dribble)\", \"PASS same decoder opens a fresh session after a dribble deadline abort\", \"PASS dribble abort diagnostics are credential-free and cost one request\"; ends with \"ALL VIDEO REMOTE OPEN CHECKS PASS (HTTP only, no native/TLS claim)\". If any open never returns, stdout shows \"FAIL <label>: open did not return within 10 s (deadline regression)\" and the exit code is 1 within 10 s. Requires the repo fixture fixtures/clip-bbb-10s.mov.",
    "fixture_block": "fx_video_dribble_swift",
    "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
  },
  "target": {
    "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
    "paths": [
      "Sources/video-remote-open-tests/main.swift",
      "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/video-remote-open-tests/main.swift",
        "block": "merged_main"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
    "command": "swift run video-remote-open-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:20:26.754510+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "ALL VIDEO REMOTE OPEN CHECKS PASS",
    "inline_files": [
      {
        "path": "Sources/video-remote-open-tests/main.swift",
        "block": "merged_main",
        "sha256": "642e80e712e9a72639a8fd8c8786477958b253a090aabe991211290b1286cf3a"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "add3cf652b993f769f98dd6a4680e44b8c7b235a55c0957a38d7fd5bc8f534d9",
    "last_5_lines": [
      "PASS same decoder opens a fresh session after a dribble deadline abort",
      "PASS dribble abort diagnostics are credential-free and cost one request",
      "PASS cancellation interrupts actual remote open",
      "PASS local path ignores remote-only options",
      "ALL VIDEO REMOTE OPEN CHECKS PASS (HTTP only, no native/TLS claim)"
    ],
    "receipt_sha256": "378beb712fb3e4b584b37d42026b6321e3858dbbf8eede5b2407581eb40349f6"
  }
}
```

## Excerpt ex_server

```swift id=ex_server
// Sources/video-remote-open-tests/main.swift lines 17-44 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
        try """
        import http.server,sys,time,threading
        data=open(sys.argv[1],'rb').read(); lock=threading.Lock(); count=0
        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                global count
                with lock:
                    count+=1
                    open(sys.argv[3],'w').write(str(count))
                if self.path.startswith('/stall'):
                    time.sleep(5); return
                if self.headers.get('X-GorAV-Test')!='yes' or 'session=abc' not in (self.headers.get('Cookie') or ''):
                    self.send_response(403);self.end_headers();return
                start=0;end=len(data)-1
                if self.headers.get('Range','').startswith('bytes='):
                    span=self.headers['Range'][6:].split('-')
                    start=int(span[0] or 0)
                    if span[1]:end=min(end,int(span[1]))
                    self.send_response(206)
                    self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
                else:self.send_response(200)
                self.send_header('Content-Length',str(end-start+1))
                self.send_header('Accept-Ranges','bytes');self.end_headers()
                self.wfile.write(data[start:end+1])
            def log_message(self,*a):pass
        s=http.server.ThreadingHTTPServer(('127.0.0.1',0),H)
        open(sys.argv[2],'w').write(str(s.server_address[1]));s.serve_forever()
        """.write(to:py,atomically:true,encoding:.utf8)
```

## Excerpt ex_stall_test

```swift id=ex_stall_test
// Sources/video-remote-open-tests/main.swift lines 76-84 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
        let deadline=FFmpegSoftwareDecoder()
        deadline.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:0.1)
        let began=ProcessInfo.processInfo.systemUptime
        do {try await deadline.open(source:source("/stall"),session:SessionID(uncheckedEpoch:6230));fatalError("deadline did not abort")}
        catch {precondition(String(describing:error).contains("deadline exceeded"))}
        precondition(ProcessInfo.processInfo.systemUptime-began < 3)
        print("PASS deadline interrupts actual URL open before response headers")
        let canceled=FFmpegSoftwareDecoder()
        canceled.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:2)
```

## Excerpt ex_deadline_arm

```swift id=ex_deadline_arm
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 736-738 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
                    interruptBox.reset(deadlineNanos:remoteOptions?.openDeadlineNanos())
                    usedEpochs.insert(sid) // spent at first fence exposure (r8 ruling)
                    interruptSlot.install(session: sid) { [weak self] in self?.interruptBox.set() }
```

## Excerpt ex_deadline_clear

```swift id=ex_deadline_clear
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 977-986 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
                    // Register only after open committed. Hardware-backed lifetime
                    // tracking is a separate row; do not mislabel it as software.
                    if self.l3HW == nil || self.l3HW?.receipt.attempted == false || self.l3HW?.receipt.attachResult != 0 || self.l3HW?.receipt.fallbackArmed == true {
                        self.decoderInventoryID=self.decoderInventory.register(session:sid,
                            kind:.videoSoftware,codec:codecName,
                            sourceID:"video:\(token.instanceID):\(token.openGeneration)",
                            revisionAtOpen:SeekRevision.atOpen.rawValue)
                    }
                    interruptBox.clearDeadline() // reads remain cancellation-only
                    cont.resume()
```

## Fixture fx_video_dribble_python

```python id=fx_video_dribble_python
# Add to the embedded server.py in Sources/video-remote-open-tests/main.swift:
# a branch directly after the "/stall" branch (before the X-GorAV-Test header check).
                if self.path.startswith('/dribble'):
                    try:
                        self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers()
                        for i in range(len(data)):
                            self.wfile.write(data[i:i+1]);self.wfile.flush();time.sleep(0.2)
                    except (BrokenPipeError,ConnectionResetError):pass
                    return
```

## Fixture fx_video_dribble_swift

```swift id=fx_video_dribble_swift
// Insert after the line: print("PASS deadline interrupts actual URL open before response headers")
        // Independent watchdog: if an open never returns, the suite prints FAIL and exits 1 instead of hanging,
        // so a deadline regression is a bounded failure even when the elapsed-time assert below can never run.
        func openWatchdog(_ label: String) -> DispatchWorkItem {
            let w=DispatchWorkItem { print("FAIL \(label): open did not return within 10 s (deadline regression)"); fflush(stdout); exit(1) }
            DispatchQueue.global().asyncAfter(deadline:.now()+10,execute:w)
            return w
        }
        let dribble=FFmpegSoftwareDecoder()
        dribble.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:1.0)
        let dribbleBegan=ProcessInfo.processInfo.systemUptime
        let w1=openWatchdog("dribble deadline abort")
        do {try await dribble.open(source:source("/dribble"),session:SessionID(uncheckedEpoch:6260));fatalError("dribbled body was not aborted by the deadline")}
        catch {precondition(String(describing:error).contains("deadline exceeded"),"unexpected error: \(error)")}
        w1.cancel()
        precondition(ProcessInfo.processInfo.systemUptime-dribbleBegan < 6,"dribble abort was not bounded")
        print("PASS deadline interrupts actual URL open stalled mid-body (dribble)")
        let afterDribbleSID=SessionID(uncheckedEpoch:6261)
        dribble.remoteOpenOptions=SourceOpenOptions(headers:["X-GorAV-Test":"yes"],cookies:["session":"abc"],openDeadlineSeconds:2)
        let w2=openWatchdog("fresh open after dribble abort")
        try await dribble.open(source:source("/film.mov"),session:afterDribbleSID)
        w2.cancel()
        precondition(dribble.activeMediaInventory(session:afterDribbleSID)?.inventory.tracks.count == 2)
        _ = await dribble.closeAndReport(session:afterDribbleSID)
        print("PASS same decoder opens a fresh session after a dribble deadline abort")
        let countBeforeLeak=(try? String(contentsOf:countFile,encoding:.utf8)) ?? "0"
        let w3=openWatchdog("dribble leak probe")
        do {
            let leak=FFmpegSoftwareDecoder()
            leak.remoteOpenOptions=SourceOpenOptions(headers:["Authorization":"Bearer s3cr3t"],openDeadlineSeconds:1.0)
            try await leak.open(source:source("/dribble?token=abc123"),session:SessionID(uncheckedEpoch:6262))
            fatalError("leak probe opened")
        } catch {
            let msg=String(describing:error)
            precondition(msg.contains("deadline exceeded") && !msg.contains("s3cr3t") && !msg.contains("abc123") && !msg.contains("127.0.0.1"),"diagnostic leaked or wrong: \(msg)")
        }
        w3.cancel()
        precondition(Int((try? String(contentsOf:countFile,encoding:.utf8)) ?? "0")! == Int(countBeforeLeak)!+1,"expected exactly one request for the leak probe")
        print("PASS dribble abort diagnostics are credential-free and cost one request")
```

```swift id=merged_main
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import GorAVCore
import GorAVFFmpegAdapter

@main struct VideoRemoteOpenChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let fixture=root.appendingPathComponent("fixtures/clip-bbb-10s.mov")
        let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let py=dir.appendingPathComponent("server.py"),portFile=dir.appendingPathComponent("port"),countFile=dir.appendingPathComponent("count")
        try """
        import http.server,sys,time,threading
        data=open(sys.argv[1],'rb').read(); lock=threading.Lock(); count=0
        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                global count
                with lock:
                    count+=1
                    open(sys.argv[3],'w').write(str(count))
                if self.path.startswith('/stall'):
                    time.sleep(5); return
                # Add to the embedded server.py in Sources/video-remote-open-tests/main.swift:
                # a branch directly after the "/stall" branch (before the X-GorAV-Test header check).
                if self.path.startswith('/dribble'):
                    try:
                        self.send_response(200);self.send_header('Content-Length',str(len(data)));self.end_headers()
                        for i in range(len(data)):
                            self.wfile.write(data[i:i+1]);self.wfile.flush();time.sleep(0.2)
                    except (BrokenPipeError,ConnectionResetError):pass
                    return
                if self.headers.get('X-GorAV-Test')!='yes' or 'session=abc' not in (self.headers.get('Cookie') or ''):
                    self.send_response(403);self.end_headers();return
                start=0;end=len(data)-1
                if self.headers.get('Range','').startswith('bytes='):
                    span=self.headers['Range'][6:].split('-')
                    start=int(span[0] or 0)
                    if span[1]:end=min(end,int(span[1]))
                    self.send_response(206)
                    self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
                else:self.send_response(200)
                self.send_header('Content-Length',str(end-start+1))
                self.send_header('Accept-Ranges','bytes');self.end_headers()
                self.wfile.write(data[start:end+1])
            def log_message(self,*a):pass
        s=http.server.ThreadingHTTPServer(('127.0.0.1',0),H)
        open(sys.argv[2],'w').write(str(s.server_address[1]));s.serve_forever()
        """.write(to:py,atomically:true,encoding:.utf8)
        let server=Process();server.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        server.arguments=[py.path,fixture.path,portFile.path,countFile.path]
        try server.run();defer {kill(server.processIdentifier, SIGKILL);server.waitUntilExit()}
        var port:String?
        for _ in 0..<100 {
            port=try? String(contentsOf:portFile,encoding:.utf8)
            if port != nil {break};try await Task.sleep(nanoseconds:20_000_000)
        }
        guard let port else {fatalError("fixture server not ready")}
        let base="http://127.0.0.1:\(port)"
        func source(_ path:String) -> SourceDescriptor {SourceDescriptor(id:base+path,kind:.remote,seekable:true)}
        let options=SourceOpenOptions(headers:["X-GorAV-Test":"yes"],cookies:["session":"abc"],openDeadlineSeconds:2)
        let video=FFmpegSoftwareDecoder();video.remoteOpenOptions=options
        let sid=SessionID(uncheckedEpoch:6201)
        try await video.open(source:source("/film.mov"),session:sid)
        precondition(video.activeMediaInventory(session:sid)?.inventory.tracks.count == 2)
        // Invalid options for a rejected busy reopen must not touch live fence.
        video.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:.nan)
        do {try await video.open(source:source("/film.mov"),session:SessionID(uncheckedEpoch:6202));fatalError("busy open admitted")} catch { }
        precondition(video.activeMediaInventory(session:sid) != nil)
        _ = await video.closeAndReport(session:sid)
        print("PASS actual video HTTP headers/cookies and busy-open isolation")
        let invalid=FFmpegSoftwareDecoder()
        let before=(try? String(contentsOf:countFile,encoding:.utf8)) ?? "0"
        for (n,opts) in [SourceOpenOptions(headers:["X":"yes\r\nInjected:x"]),SourceOpenOptions(openDeadlineSeconds:0),SourceOpenOptions(openDeadlineSeconds:.infinity)].enumerated() {
            invalid.remoteOpenOptions=opts
            do {try await invalid.open(source:source("/film.mov"),session:SessionID(uncheckedEpoch:UInt64(6210+n)));fatalError("invalid options admitted")}
            catch {precondition(String(describing:error).contains("invalid remote open options"))}
        }
        precondition(((try? String(contentsOf:countFile,encoding:.utf8)) ?? "0") == before)
        print("PASS typed option validation before any HTTP access")
        let deadline=FFmpegSoftwareDecoder()
        deadline.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:0.1)
        let began=ProcessInfo.processInfo.systemUptime
        do {try await deadline.open(source:source("/stall"),session:SessionID(uncheckedEpoch:6230));fatalError("deadline did not abort")}
        catch {precondition(String(describing:error).contains("deadline exceeded"))}
        precondition(ProcessInfo.processInfo.systemUptime-began < 3)
        print("PASS deadline interrupts actual URL open before response headers")
// Insert after the line: print("PASS deadline interrupts actual URL open before response headers")
        // Independent watchdog: if an open never returns, the suite prints FAIL and exits 1 instead of hanging,
        // so a deadline regression is a bounded failure even when the elapsed-time assert below can never run.
        func openWatchdog(_ label: String) -> DispatchWorkItem {
            let w=DispatchWorkItem { print("FAIL \(label): open did not return within 10 s (deadline regression)"); fflush(stdout); exit(1) }
            DispatchQueue.global().asyncAfter(deadline:.now()+10,execute:w)
            return w
        }
        let dribble=FFmpegSoftwareDecoder()
        dribble.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:1.0)
        let dribbleBegan=ProcessInfo.processInfo.systemUptime
        let w1=openWatchdog("dribble deadline abort")
        do {try await dribble.open(source:source("/dribble"),session:SessionID(uncheckedEpoch:6260));fatalError("dribbled body was not aborted by the deadline")}
        catch {precondition(String(describing:error).contains("deadline exceeded"),"unexpected error: \(error)")}
        w1.cancel()
        precondition(ProcessInfo.processInfo.systemUptime-dribbleBegan < 6,"dribble abort was not bounded")
        print("PASS deadline interrupts actual URL open stalled mid-body (dribble)")
        let afterDribbleSID=SessionID(uncheckedEpoch:6261)
        dribble.remoteOpenOptions=SourceOpenOptions(headers:["X-GorAV-Test":"yes"],cookies:["session":"abc"],openDeadlineSeconds:2)
        let w2=openWatchdog("fresh open after dribble abort")
        try await dribble.open(source:source("/film.mov"),session:afterDribbleSID)
        w2.cancel()
        precondition(dribble.activeMediaInventory(session:afterDribbleSID)?.inventory.tracks.count == 2)
        _ = await dribble.closeAndReport(session:afterDribbleSID)
        print("PASS same decoder opens a fresh session after a dribble deadline abort")
        let countBeforeLeak=(try? String(contentsOf:countFile,encoding:.utf8)) ?? "0"
        let w3=openWatchdog("dribble leak probe")
        do {
            let leak=FFmpegSoftwareDecoder()
            leak.remoteOpenOptions=SourceOpenOptions(headers:["Authorization":"Bearer s3cr3t"],openDeadlineSeconds:1.0)
            try await leak.open(source:source("/dribble?token=abc123"),session:SessionID(uncheckedEpoch:6262))
            fatalError("leak probe opened")
        } catch {
            let msg=String(describing:error)
            precondition(msg.contains("deadline exceeded") && !msg.contains("s3cr3t") && !msg.contains("abc123") && !msg.contains("127.0.0.1"),"diagnostic leaked or wrong: \(msg)")
        }
        w3.cancel()
        precondition(Int((try? String(contentsOf:countFile,encoding:.utf8)) ?? "0")! == Int(countBeforeLeak)!+1,"expected exactly one request for the leak probe")
        print("PASS dribble abort diagnostics are credential-free and cost one request")
        let canceled=FFmpegSoftwareDecoder()
        canceled.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:2)
        let cancelSID=SessionID(uncheckedEpoch:6240)
        let stalledSource=source("/stall")
        let task=Task.detached {try await canceled.open(source:stalledSource,session:cancelSID)}
        try await Task.sleep(nanoseconds:100_000_000)
        canceled.requestInterrupt(session:cancelSID)
        do {try await task.value;fatalError("cancel did not abort")}
        catch {precondition(String(describing:error).contains("interrupted"))}
        print("PASS cancellation interrupts actual remote open")
        let local=FFmpegSoftwareDecoder()
        try local.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        local.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:.nan)
        let localSID=SessionID(uncheckedEpoch:6250)
        try await local.open(source:SourceDescriptor(id:fixture.path,kind:.local,seekable:true),session:localSID)
        _ = await local.closeAndReport(session:localSID)
        print("PASS local path ignores remote-only options")
        print("ALL VIDEO REMOTE OPEN CHECKS PASS (HTTP only, no native/TLS claim)")
    }
}

```

```text id=actual_run_log
Building for debugging...
[0/14] Write sources
[5/14] Compiling GorAVCAtomics gorav_atomics.c
[6/14] Write swift-version--6630B1A18289934C.txt
[8/16] Emitting module GorAVCore
[9/16] Compiling GorAVCore AdmissionTable.swift
[10/17] Compiling GorAVCore Boundary.swift
[11/18] Wrapping AST for GorAVCore for debugging
[13/22] Emitting module GorAVNativeProbeKit
[14/22] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[15/22] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[16/22] Compiling GorAVNativeProbeKit LeaseTable.swift
[17/24] Compiling GorAVNativeProbeKit NativeProbe.swift
[18/24] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[19/25] Wrapping AST for GorAVNativeProbeKit for debugging
[21/40] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[22/40] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[23/40] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[24/40] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[25/40] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[26/40] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[27/40] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[28/40] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[29/40] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[30/40] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[31/40] Compiling GorAVPlaybackCore Lane0Contract.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[32/40] Compiling GorAVPlaybackCore LifetimeRegistry.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[33/40] Compiling GorAVPlaybackCore PlayArguments.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[34/40] Compiling GorAVPlaybackCore PlaybackCore.swift
/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:14: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |              `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:84:41: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
    |                                         `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
 86 |         do { try txn.execute() }

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:22: warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                      `- warning: instance method 'lock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:85:49: warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 83 |         let adopted = txn.reservedRevision   // PINNED HANDSHAKE: adopt, never reserve separately
 84 |         lock.lock(); active = txn; lock.unlock()
 85 |         defer { lock.lock(); active = nil; lock.unlock() }
    |                                                 `- warning: instance method 'unlock' is unavailable from asynchronous contexts; Use async-safe scoped locking instead; this is an error in the Swift 6 language mode; this is an error in the Swift 6 language mode
 86 |         do { try txn.execute() }
 87 |         catch {

/tmp/packet-proof-iz8_m6hx/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[35/40] Emitting module GorAVPlaybackCore
[36/53] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[37/53] Compiling GorAVPlaybackCore PlayheadObservers.swift
[38/53] Compiling GorAVPlaybackCore PlayheadPosition.swift
[39/53] Compiling GorAVPlaybackCore PreparedAdoption.swift
[40/53] Compiling GorAVPlaybackCore PreparedShotSession.swift
[41/53] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[42/53] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[43/53] Compiling GorAVPlaybackCore RenderGraph.swift
[44/53] Compiling GorAVPlaybackCore SPSC.swift
[45/53] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[46/53] Compiling GorAVPlaybackCore StageGeometry.swift
[47/53] Compiling GorAVPlaybackCore TimingLedger.swift
[48/53] Compiling GorAVPlaybackCore UniformPacking.swift
[49/54] Wrapping AST for GorAVPlaybackCore for debugging
[51/62] Compiling GorAVFFmpegAdapter ActiveTransportSnapshot.swift
[52/62] Compiling GorAVFFmpegAdapter FFmpegSoftwareAudioDecoder.swift
[53/62] Compiling GorAVFFmpegAdapter FFmpegSoftwareDecoder.swift
[54/62] Compiling GorAVFFmpegAdapter FrameObservation.swift
[55/62] Compiling GorAVFFmpegAdapter L3AVCoordinator.swift
[56/62] Compiling GorAVFFmpegAdapter L3Admission.swift
[57/62] Compiling GorAVFFmpegAdapter L3HardwareDecode.swift
[58/62] Emitting module GorAVFFmpegAdapter
[59/68] Compiling GorAVFFmpegAdapter L3PixelConvert.swift
[60/68] Compiling GorAVFFmpegAdapter L3SampleConvert.swift
[61/68] Compiling GorAVFFmpegAdapter MediaInventory.swift
[62/68] Compiling GorAVFFmpegAdapter SnapshotAVIOOwner.swift
[63/68] Compiling GorAVFFmpegAdapter SnapshotInput.swift
[64/68] Compiling GorAVFFmpegAdapter SourceOpenOptions.swift
[65/69] Wrapping AST for GorAVFFmpegAdapter for debugging
[67/71] Emitting module video_remote_open_tests
[68/71] Compiling video_remote_open_tests main.swift
[69/72] Wrapping AST for video-remote-open-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking video-remote-open-tests
Build of product 'video-remote-open-tests' complete! (12.82s)
----------------------------------------
Exception occurred during processing of request from ('127.0.0.1', 55846)
----------------------------------------
Exception occurred during processing of request from ('127.0.0.1', 55860)
Traceback (most recent call last):
  File "/usr/lib/python3.10/socketserver.py", line 683, in process_request_thread
    self.finish_request(request, client_address)
  File "/usr/lib/python3.10/socketserver.py", line 360, in finish_request
    self.RequestHandlerClass(request, client_address, self)
  File "/usr/lib/python3.10/socketserver.py", line 747, in __init__
    self.handle()
  File "/usr/lib/python3.10/http/server.py", line 433, in handle
    self.handle_one_request()
  File "/usr/lib/python3.10/http/server.py", line 421, in handle_one_request
    method()
  File "/tmp/2CD641B0-3EDB-49C0-AA75-2082ACE0A5B7/server.py", line 32, in do_GET
    self.wfile.write(data[start:end+1])
  File "/usr/lib/python3.10/socketserver.py", line 826, in write
    self._sock.sendall(b)
ConnectionResetError: [Errno 104] Connection reset by peer
----------------------------------------
Traceback (most recent call last):
  File "/usr/lib/python3.10/socketserver.py", line 683, in process_request_thread
    self.finish_request(request, client_address)
  File "/usr/lib/python3.10/socketserver.py", line 360, in finish_request
    self.RequestHandlerClass(request, client_address, self)
  File "/usr/lib/python3.10/socketserver.py", line 747, in __init__
    self.handle()
  File "/usr/lib/python3.10/http/server.py", line 433, in handle
    self.handle_one_request()
  File "/usr/lib/python3.10/http/server.py", line 421, in handle_one_request
    method()
  File "/tmp/2CD641B0-3EDB-49C0-AA75-2082ACE0A5B7/server.py", line 32, in do_GET
    self.wfile.write(data[start:end+1])
  File "/usr/lib/python3.10/socketserver.py", line 826, in write
    self._sock.sendall(b)
ConnectionResetError: [Errno 104] Connection reset by peer
----------------------------------------
----------------------------------------
Exception occurred during processing of request from ('127.0.0.1', 55898)
Traceback (most recent call last):
  File "/usr/lib/python3.10/socketserver.py", line 683, in process_request_thread
    self.finish_request(request, client_address)
  File "/usr/lib/python3.10/socketserver.py", line 360, in finish_request
    self.RequestHandlerClass(request, client_address, self)
  File "/usr/lib/python3.10/socketserver.py", line 747, in __init__
    self.handle()
  File "/usr/lib/python3.10/http/server.py", line 433, in handle
    self.handle_one_request()
  File "/usr/lib/python3.10/http/server.py", line 421, in handle_one_request
    method()
  File "/tmp/2CD641B0-3EDB-49C0-AA75-2082ACE0A5B7/server.py", line 32, in do_GET
    self.wfile.write(data[start:end+1])
  File "/usr/lib/python3.10/socketserver.py", line 826, in write
    self._sock.sendall(b)
ConnectionResetError: [Errno 104] Connection reset by peer
----------------------------------------
----------------------------------------
Exception occurred during processing of request from ('127.0.0.1', 55924)
Traceback (most recent call last):
  File "/usr/lib/python3.10/socketserver.py", line 683, in process_request_thread
    self.finish_request(request, client_address)
  File "/usr/lib/python3.10/socketserver.py", line 360, in finish_request
    self.RequestHandlerClass(request, client_address, self)
  File "/usr/lib/python3.10/socketserver.py", line 747, in __init__
    self.handle()
  File "/usr/lib/python3.10/http/server.py", line 433, in handle
    self.handle_one_request()
  File "/usr/lib/python3.10/http/server.py", line 421, in handle_one_request
    method()
  File "/tmp/2CD641B0-3EDB-49C0-AA75-2082ACE0A5B7/server.py", line 32, in do_GET
    self.wfile.write(data[start:end+1])
  File "/usr/lib/python3.10/socketserver.py", line 826, in write
    self._sock.sendall(b)
ConnectionResetError: [Errno 104] Connection reset by peer
----------------------------------------
PASS actual video HTTP headers/cookies and busy-open isolation
PASS typed option validation before any HTTP access
PASS deadline interrupts actual URL open before response headers
PASS deadline interrupts actual URL open stalled mid-body (dribble)
PASS same decoder opens a fresh session after a dribble deadline abort
PASS dribble abort diagnostics are credential-free and cost one request
PASS cancellation interrupts actual remote open
PASS local path ignores remote-only options
ALL VIDEO REMOTE OPEN CHECKS PASS (HTTP only, no native/TLS claim)
```
