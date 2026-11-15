# W-gdb-025 audio ring-buffer seek-reset model + property tests
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-025

```packet-json
{
 "packet_id": "W-gdb-025",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVPlaybackCore/SPSC.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/GorAVMacShell/AudioUnitSink.swift",
   "excerpt_block": "source2"
  }
 ],
 "interface": {
  "signatures": "push(_ pcm: UnsafeBufferPointer<UInt8>) -> (admittedFrames: UInt64, droppedFrames: UInt64, droppedTailBytes: UInt64); resetForNewGeneration()",
  "types": "RTEvent { kind: underrunStart | underrunEnd | staleFenced, generation: UInt64, tEvent: Double, payload }; AdmissionCell { enter/exit/retire/readers/isRetired }; AtomicU64",
  "ownership_lifetime": "RT plane; AdmissionCell is a LOCAL payload lifetime fence, no provider-quiescence claim",
  "caller": "ring model tests (Linux)",
  "callee": "SPSCPCMRing.push/resetForNewGeneration + AdmissionCell + RTEvent vocabulary (pinned below)"
 },
 "test": {
  "command": "swift run ring-model-tests",
  "expected": "exit 0; final line matches '^ring-model-tests: [1-9][0-9]* PASS, 0 FAIL$'; deterministic seeds printed; a seeded stale-generation write is caught (negative control shown)",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/ring-model/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
the audio ring (SPSC) and the sink's pause-silence contract carry seek generations and counters; without a portable model + property tests over randomized op sequences, a fencing regression (stale-generation write accepted) ships as a post-seek audio pop or bleed.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/SPSC.swift (sha256 fcba3646; ring excerpt below) and Sources/GorAVMacShell/AudioUnitSink.swift (sha256 22cb8c69; pause-contract excerpt below).
- real test command: the returned model runs on Linux; existing seek-ring-reset/audio suites stay green.

## expected behaviour
a portable ring model with seek generations (reset fencing, underrun accounting, pause-silence counters, resume re-arm) plus property tests over randomized push/reset/pause/resume/read sequences asserting counter invariants and fence honesty; deterministic seeds.

## exact call site and interface
the ring's push/reset/read semantics and the sink's silence-counter contract (pinned excerpts) define the model's vocabulary.

## pinned ABI decisions (integrator, 2026-11-15; push/reset fence ABI)
- public func SPSCPCMRing.push(_ pcm: UnsafeBufferPointer<UInt8>) -> (admittedFrames: UInt64, droppedFrames: UInt64, droppedTailBytes: UInt64) (SPSC.swift, same pin); PCMRingReceipt carries the same accounting fields
- reset fencing: resetForNewGeneration() clears per-generation state; a write tagged with an old generation after the bump is fenced - RTEvent.Kind.staleFenced (= 3) is the typed witness; RTEvent { kind, generation: UInt64 (session generation AT POST TIME), tEvent: Double, payload: .frames(UInt64) | .bytes(UInt64) }
- AdmissionCell (LOCAL payload lifetime fence, no provider-quiescence claim): enter() -> Bool, exit(), retire() -> UInt64, readers: UInt64, isRetired: Bool; payload zeroed BEFORE any reset/reuse/dispose
- AtomicU64: load/store/fetchAdd/compareExchange - the counter primitives the model mirrors
property invariants the model asserts: admitted + dropped == offered per push; a stale-generation push is fenced (staleFenced, never admitted); underrun accounting matches underrunStart/underrunEnd events.

## behaviour that must not change
the pause contract (callbacks continue rendering intentional silence) is preserved exactly; no audio-device claim.

## acceptance test (from the product repo)
property tests PASS on Linux across seeds; a seeded stale-generation write is caught (negative control shown).

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/SPSC.swift (sha256 fcba3646, lines 260-290 of 333)
```swift id=source1
            pushCount.fetchAdd(1)
            admittedBytes.fetchAdd(admit &* UInt64(SPSCPCMRing.bytesPerFrame))
        }
        if drop > 0 {
            droppedFrames.fetchAdd(drop)
            droppedBytes.fetchAdd(drop &* UInt64(SPSCPCMRing.bytesPerFrame))
            droppedAnything.store(1)
        }
        return (admit, drop, tail)
    }
    private var bufCount: Int { Int(capacityFrames) &* SPSCPCMRing.bytesPerFrame }
    /// Consumer side (RT). Renders `frames` frames DIRECTLY into `dst`:
    /// real frames copied, shortfall zero-filled and counted as underrun.
    /// No allocation, no lock, no Array subscript. Returns underrun frames.
    /// v4-5: frames is UInt32 (the AudioUnit unit); byte arithmetic is
    /// range-checked, no UInt64->Int narrowing.
    @discardableResult
    public func render(into dst: UnsafeMutablePointer<UInt8>, frames: UInt32) -> UInt32 {
        let want = UInt64(frames)
        let ri = r.load()                    // own: exact
        let wi = w.load()                    // producer's: acquire; may equal/exceed ri
        let avail = wi >= ri ? wi - ri : 0   // saturating: never underflows
        let real = Swift.min(avail, want)
        if real > 0 {
            var idx = Int(ri % capacityFrames) &* SPSCPCMRing.bytesPerFrame
            var i = 0
            let n = Int(real) &* SPSCPCMRing.bytesPerFrame // real <= UInt32.max frames
            while i < n {
                dst[i] = buf[idx]
                idx = (idx &+ 1) == bufCount ? 0 : idx &+ 1
                i &+= 1
```

### Sources/GorAVMacShell/AudioUnitSink.swift (sha256 22cb8c69, lines 634-678 of 1284)
```swift id=source2
        guard let p = AudioPacingPolicy(hostClock: hostClock,
                                        sampleRate: AudioUnitSink.pcmSampleRate,
                                        consistencyTolerance: consistencyTolerance) else { return false }
        pacingHostClock = hostClock
        pacingPolicy = p
        pacingClock = AudioMasterPacingClock(policy: p, hostClock: hostClock)
        return true
    }

    /// M1 typed pause (condition (a)): quiesce the render path. The ring
    /// residual is HELD (no consumption), intentional silence is NOT
    /// underrun/overrun (its own counter), and no clock-drift decisions
    /// run while quiesced. Typed false when not active, unattached, or
    /// already paused. The J3 pause path calls this.
    /// The WHOLE pause is one stateLock section (20:40 lifecycle race):
    /// lifecycle check + policy pause + RT flag store are atomic against
    /// stop()/start(), so a teardown can never orphan a quiesce into the
    /// next session. Boundary contract (architect 20:12) unchanged:
    /// pushIfUnpaused holds the same lock across admission + pause check
    /// + ring write, so once pauseAudio() returns true no admitted push
    /// can enter the ring; J3's async pre-push audioPaused check is an
    /// optimization, correctness does not depend on it.
    @discardableResult
    public func pauseAudio() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard case .active = lifecycle.current, let p = pacingPolicy, pausedFlag?.load() == 0 else {
            return false
        }
        guard p.pause(atHost: hostSeconds()) else { return false }
        pausedFlag?.store(1)
        return true
    }

    /// M1 typed resume: a NEW clock generation (8.5) anchored on the
    /// device-consumed counter frozen over the pause BEFORE consumption
    /// resumes - the anchor is exact and the value continues from the
    /// frozen point (no jump).
    /// One stateLock section, symmetric with pauseAudio (20:40): the
    /// policy resume (new generation on the frozen device-consumed
    /// counter), the receipt fold, and the RT flag clear are atomic
    /// against stop()/start(). The RT thread is lock-free by design, so
    /// the silence fold carries a one-callback slack at this edge;
    /// receipts reconcile at transition granularity (condition (d)).
    @discardableResult
    public func resumeAudio() -> Bool {
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"seed":42,"ops":[{"push":{"frames":480}},{"resetForNewGeneration":{}},{"push":{"frames":480,"generation":"stale"},"expect":"staleFenced"},{"read":{"frames":480}}],"expectReceipts":[{"admitted":480,"dropped":0},{"admitted":0,"fenced":true}]}
```
