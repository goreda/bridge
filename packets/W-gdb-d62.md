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
