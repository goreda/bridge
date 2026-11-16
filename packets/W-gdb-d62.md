# W-gdb-d62: 195b-62 follow-on: video remote open deadline witness for a dribbled body (rev 2)
> rev 2026-11-16-r4: pin rolled a34e2cd -> bb49fc6 (VT zero-copy/product merges moved FFmpegSoftwareDecoder.swift); the stale excerpts were re-located to identical content at new line ranges and their hashes recomputed; every other excerpt re-verified byte-identical at bb49fc6.

> rev 2026-11-16-r2: excerpt ranges/hashes rebound to pin 8786bfe3 (Team A log-verify fixes: 040 whole-file 1-137, d59 ex_store 119-155, d64 ex_test_tail 115-134, G0761 hash map added, stale header shas replaced). Supersedes the 2026-11-16 minting only after a fresh gate-flow run_proof binds to these bytes
> rev 2026-11-16-r3: pin rolled 8786bfe3 -> a34e2cd (arch-197e item 5 self-decision; the delta is docs/LEDGER.tsv only, every excerpt body re-verified byte-identical and excerpt_sha256_8 unchanged). Supersedes the r2 receipts once a fresh gate-flow run_proof binds at a34e2cd.


Rev 2 after the ops semantic gate. video-remote-open-tests has `/stall` (headers never sent) but no dribbled-body case, while the audio witness has one (D3). Add the dribble route and the checks below. Rev 2 adds an independent 10 s watchdog around every new open, so if open never returns (a deadline regression) the suite prints FAIL and exits 1 instead of hanging; the elapsed-time precondition alone only runs after open returns. The decoder code under test is already landed; if a check fails, fix FFmpegSoftwareDecoder so the open+stream-info deadline also bounds a trickling body and return the fix with the patch.

Not in scope: HTTPS/TLS provider, stuck-decode interruption, cache state, audio decoder. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
  "packet": "W-gdb-d62",
  "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
  "scope": "implementation",
  "product_repo": "goreda/gorav",
  "product_branch": "engine",
  "product_sha": "bb49fc662158f07782baab1c8e8acc940dd07068",
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
      "lines": "739-741"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift",
      "excerpt_block": "ex_deadline_clear",
      "lines": "985-994"
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
  }
}
```

## Excerpt ex_server

```swift id=ex_server
// Sources/video-remote-open-tests/main.swift lines 17-44 @ bb49fc662158f07782baab1c8e8acc940dd07068
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
// Sources/video-remote-open-tests/main.swift lines 76-84 @ bb49fc662158f07782baab1c8e8acc940dd07068
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
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 739-741 @ bb49fc662158f07782baab1c8e8acc940dd07068
                    interruptBox.reset(deadlineNanos:remoteOptions?.openDeadlineNanos())
                    usedEpochs.insert(sid) // spent at first fence exposure (r8 ruling)
                    interruptSlot.install(session: sid) { [weak self] in self?.interruptBox.set() }
```

## Excerpt ex_deadline_clear

```swift id=ex_deadline_clear
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift lines 985-994 @ bb49fc662158f07782baab1c8e8acc940dd07068
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
