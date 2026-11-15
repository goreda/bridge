# W-gdb-d54: 195b-54 follow-on: audio witnesses for deadline-ends-at-open and mid-stream interrupt (rev 2)

Rev 2 after the ops semantic gate. The 195b-54 witness covers blocked headers (D1, D2) and a dribbled body at open time (D3). Two landed claims are not witnessed: (a) clearDeadline() at open commit means a streaming read slower than the open deadline is not aborted (D8); (b) requestInterrupt reaches a read that stalls AFTER a successful open (D9). Rev 2 changes: D9 now records whether the reader ended before the interrupt (D9a fails if so, so an early EOS/nil/failed can no longer pass), checks data flowed (D9b), and requires failed or nil as the terminal result (D9c). D8 and D9 each sit under an independent watchdog that prints FAIL and exits 1, so a hung await cannot hang the suite. If D9 fails, fix FFmpegSoftwareAudioDecoder so the session-owned interrupt slot aborts the stalled streaming read and return that fix with the patch.

Not in scope: video decoder, HTTPS/TLS, cache state, hardware audio. Excerpts are verbatim lines from the pinned product sha; the first comment line of each block is a label added by the packet writer and is not part of the excerpt hash. Fixture blocks are new text proposed by this packet.

```packet-json
{
 "packet": "W-gdb-d54",
 "code_owner": "gdb gorav integrator (decoder lane), owner of Sources/GorAVPlaybackCore and Sources/GorAVFFmpegAdapter on gorav/engine",
 "scope": "implementation",
 "product_repo": "goreda/gorav",
 "product_branch": "engine",
 "product_sha": "8eaffc75b331a9d65ddce404266738a9d42043ed",
 "touched_files": [
  {
   "path": "Sources/audio-interrupt-tests/main.swift",
   "excerpt_block": "ex_test_head",
   "lines": "1-22"
  },
  {
   "path": "Sources/audio-interrupt-tests/main.swift",
   "excerpt_block": "ex_d3",
   "lines": "139-151"
  },
  {
   "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift",
   "excerpt_block": "ex_interrupt_box",
   "lines": "195-215"
  },
  {
   "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift",
   "excerpt_block": "ex_request_interrupt",
   "lines": "224-227"
  }
 ],
 "excerpt_sha256_8": {
  "ex_test_head": "f24858c8",
  "ex_d3": "627b2ae1",
  "ex_interrupt_box": "45ea6926",
  "ex_request_interrupt": "8e880efb"
 },
 "interface": {
  "signatures": "No new product API. Existing: FFmpegSoftwareAudioDecoder.remoteOpenOptions, open(source:session:) async throws, nextEvent(session:) async returning an optional event with cases .opened, .pcm, .failed, .endOfStream, requestInterrupt(session:), close(session:) async. New test-only helpers: watchdog(_:_:) -> DispatchWorkItem, final class Flag, secondsSince(_:).",
  "types": "SessionID(uncheckedEpoch:), SourceOpenOptions(openDeadlineSeconds:), SourceDescriptor, as used by D1..D7.",
  "ownership_lifetime": "Per-check decoder instances; python server killed by the existing process teardown. The interrupt slot is committed to the session on successful open and cleared on close. Each watchdog is cancelled on normal completion.",
  "caller": "audio-interrupt-tests top-level script (top-level await).",
  "callee": "FFmpegSoftwareAudioDecoder read loop and its AudioInterruptBox shouldAbort callback."
 },
 "test": {
  "command": "swift run audio-interrupt-tests",
  "expected": "Exit 0. Output contains the existing PASS lines, then PASS D8, PASS D9a, PASS D9b, PASS D9c (D9c detail shows terminal=failed or terminal=nil and an elapsed time under 5 s), and ends with the existing final line reporting 0 FAIL. A hang prints \"FAIL D8 ...\" or \"FAIL D9 ... watchdog expired\" and exits 1 within 20 s. Requires the repo fixture used by the existing routes.",
  "fixture_block": "fx_audio_d8_d9_swift",
  "note": "Run by the integrator on Linux with the pinned provider; a lab without the repo returns the patch and states \"unrun\"."
 },
 "target": {
  "branch": "lane/gdb-196p-decoder (integrator creates it from product_sha; never ohal/gorav main or PR 3)",
  "paths": [
   "Sources/audio-interrupt-tests/main.swift",
   "Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift"
  ],
  "return_form": "patch"
 }
}
```

## Excerpt ex_test_head

```swift id=ex_test_head
// Sources/audio-interrupt-tests/main.swift lines 1-22 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// 195b-54 witness: bounded cancellation/deadline for remote audio open and
// stream-info through the provider interrupt path, per-open immutable
// validated options, credential-free diagnostics. Local python http fixtures
// (delayed headers, dribbled body) prove cancellation lands in bounded time.
// No HTTPS-provider or cache-state claim: loopback http only.

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

func validationError(_ o: SourceOpenOptions) -> SourceOpenOptionsError? {
    do { _ = try o.validatedForOpen(); return nil }
    catch let e as SourceOpenOptionsError { return e }
    catch { return nil }
}

```

## Excerpt ex_d3

```swift id=ex_d3
// Sources/audio-interrupt-tests/main.swift lines 139-151 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
// D3: deadline aborts an open stalled mid-body (dribbled bytes).
do {
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 1.0)
    let start = DispatchTime.now()
    do {
        try await d.open(source: remote("/dribble.wav"), session: SessionID(uncheckedEpoch: 203))
        check("D3 deadline aborts dribbled body", false, "opened")
    } catch {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        check("D3 deadline exceeded on dribble", "\(error)".contains("deadline exceeded"), "\(error)")
        check("D3 bounded wait", elapsed < 10, String(format: "%.2fs", elapsed))
    }
```

## Excerpt ex_interrupt_box

```swift id=ex_interrupt_box
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift lines 195-215 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    private final class AudioInterruptBox {
        private let lock = NSLock()
        private var flag = false
        private var deadlineNanos: UInt64?
        func set() { lock.lock(); flag = true; lock.unlock() }
        func reset(deadlineNanos: UInt64?) { lock.lock(); flag = false; self.deadlineNanos = deadlineNanos; lock.unlock() }
        func clearDeadline() { lock.lock(); deadlineNanos = nil; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        var deadlineExceeded: Bool {
            lock.lock(); defer { lock.unlock() }
            guard !flag, let d = deadlineNanos else { return false }
            return DispatchTime.now().uptimeNanoseconds >= d
        }
        var shouldAbort: Bool {
            lock.lock(); defer { lock.unlock() }
            if flag { return true }
            guard let d = deadlineNanos else { return false }
            return DispatchTime.now().uptimeNanoseconds >= d
        }
    }
    private let interruptBox = AudioInterruptBox()
```

## Excerpt ex_request_interrupt

```swift id=ex_request_interrupt
// Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift lines 224-227 @ 8eaffc75b331a9d65ddce404266738a9d42043ed
    public func requestInterrupt(session: SessionID) {
        interruptSlot.request(session: session.epoch)
    }

```

## Fixture fx_audio_server_python

```python id=fx_audio_server_python
# Add to the embedded server.py of Sources/audio-interrupt-tests/main.swift (inside do_GET, new elif branches before the final else).
# The WAV is generated by the server, so D8/D9 need no repo fixture for these routes: 8 kHz mono 16-bit, 20 s, zero samples (320044 bytes).
            elif path.startswith('/paced') or path.startswith('/late-stall'):
                import struct
                pcm = b'\x00\x00' * 8000 * 20
                data = b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 8000, 16000, 2, 16) + b'data' + struct.pack('<I', len(pcm)) + pcm
                self.send_response(200)
                self.send_header('Content-Length', str(len(data)))
                self.end_headers()
                self.wfile.write(data[:65536]); self.wfile.flush()
                if path.startswith('/late-stall'):
                    time.sleep(20)
                else:
                    pos = 65536
                    while pos < len(data):
                        self.wfile.write(data[pos:pos+4096]); self.wfile.flush(); pos += 4096; time.sleep(0.25)
```

## Fixture fx_audio_d8_d9_swift

```swift id=fx_audio_d8_d9_swift
// Add after the D3 block of Sources/audio-interrupt-tests/main.swift (before D4).
// Independent watchdog: any await below that never returns turns into a bounded FAIL + exit(1).
func watchdog(_ seconds: Double, _ label: String) -> DispatchWorkItem {
    let w = DispatchWorkItem { print("FAIL \(label): watchdog expired after \(seconds)s"); fflush(stdout); exit(1) }
    DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: w)
    return w
}
final class Flag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
}
func secondsSince(_ t: DispatchTime) -> Double { Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e9 }

// D8: the open deadline bounds open + stream-info only. A stream that opens fast and then
// trickles slower than the deadline must keep decoding past the deadline.
do {
    let w = watchdog(20, "D8 open or event loop never returned")
    let d = FFmpegSoftwareAudioDecoder()
    d.remoteOpenOptions = SourceOpenOptions(openDeadlineSeconds: 1.0)
    let session = SessionID(uncheckedEpoch: 208)
    do {
        try await d.open(source: remote("/paced.wav"), session: session)
        let began = DispatchTime.now()
        var pcmAfterDeadline = 0
        var failed = false
        while secondsSince(began) < 3.0 {
            guard let ev = await d.nextEvent(session: session) else { break }
            if case .failed = ev { failed = true; break }
            if case .pcm = ev, secondsSince(began) > 1.5 { pcmAfterDeadline += 1 }
        }
        check("D8 deadline does not abort streaming reads", !failed && pcmAfterDeadline > 0, "failed=\(failed) pcmAfterDeadline=\(pcmAfterDeadline)")
        await d.close(session: session)
    } catch {
        check("D8 deadline does not abort streaming reads", false, "open failed: \(error)")
    }
    w.cancel()
}

// D9: requestInterrupt unblocks a streaming read that stalls AFTER a successful open.
// The reader records whether it ended before the interrupt was sent; that makes the check non-vacuous.
do {
    let w = watchdog(20, "D9 open, reader or close never returned")
    let d = FFmpegSoftwareAudioDecoder()
    let session = SessionID(uncheckedEpoch: 209)
    let interrupted = Flag()
    do {
        try await d.open(source: remote("/late-stall.wav"), session: session)
        let reader = Task { () -> (sawPCM: Bool, endedBeforeInterrupt: Bool, terminal: String) in
            var sawPCM = false
            while true {
                guard let ev = await d.nextEvent(session: session) else { return (sawPCM, !interrupted.value, "nil") }
                if case .pcm = ev { sawPCM = true }
                if case .failed = ev { return (sawPCM, !interrupted.value, "failed") }
                if case .endOfStream = ev { return (sawPCM, !interrupted.value, "endOfStream") }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let began = DispatchTime.now()
        interrupted.set()
        d.requestInterrupt(session: session)
        let r = await reader.value
        let elapsed = secondsSince(began)
        check("D9a stream was still stalled when the interrupt was sent", !r.endedBeforeInterrupt, "terminal=\(r.terminal) before interrupt")
        check("D9b data flowed before the stall", r.sawPCM)
        check("D9c interrupt ended the read with failed or nil (not endOfStream), bounded", (r.terminal == "failed" || r.terminal == "nil") && elapsed < 5, String(format: "terminal=%@ %.2fs", r.terminal, elapsed))
        await d.close(session: session)
    } catch {
        check("D9 setup: open of /late-stall.wav", false, "open failed: \(error)")
    }
    w.cancel()
}
```
