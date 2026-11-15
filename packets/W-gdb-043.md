# W-gdb-043 195b-N8 streaming WSOLA: consuming pin (reopens W-gdb-010 withdrawal)
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-043

```packet-json
{
 "packet_id": "W-gdb-043",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/AudioMasterScheduler/AudioMasterScheduler.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "AudioMasterScheduler protocol + AudioMasterClock (pinned excerpt): reset/seek/updateAudio/mediaTime/decide; additive module: public struct WSOLAProcessor { init(sampleRate: Int, channels: Int); mutating func setRate(_ rate: Double) -> Bool; mutating func process(_ input: UnsafeBufferPointer<Int16>, into output: UnsafeMutableBufferPointer<Int16>) -> Int (frames written); mutating func reset(); var latencyFrames: Int { get } }",
  "types": "VideoDecision { wait, present, drop }; rate Double in a named supported set; latencyFrames reported and bounded (module names its bound); buffer sizes in frames of packed s16le stereo",
  "ownership_lifetime": "all overlap/add state lives inside the WSOLAProcessor value; input buffers borrowed per call, never retained; output written into caller-owned buffers; clock state owned solely by AudioMasterClock",
  "caller": "audio sink enqueue path after L3SampleConvert",
  "callee": "the lab WSOLA module behind wsolaProcess; timing decisions stay with AudioMasterClock"
 },
 "test": {
  "command": "python3 kits/n8-wsola-pin/check.py kits/n8-wsola-pin/fixtures.json",
  "expected": "exit 0; stdout 'n8-wsola-pin: 3/3 rows PASS'; 1.25x row output count = input/1.25 within 1 frame; reset row witnesses zero pre-reset samples",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVPlaybackCore/",
   "kits/n8-wsola-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
tempo (WSOLA) audio (195b-N8) was withdrawn for want of a pinned consuming seam; unpinned, a tempo module breaks A/V sync or the sink contract.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0278/N8; the lab module implements against the pinned interface below.

## expected behaviour
a STREAMING WSOLA module on the audio path behind the additive stateful WSOLAProcessor (init/setRate/process/reset/latencyFrames per the pinned signatures): AudioMasterClock (maxLate 0.040, tolerance 1e-9, generation counter, reset/seek/updateAudio/mediaTime/decide per the pinned excerpt) stays the ONLY clock authority; all overlap/add state lives inside the processor value, never in globals; setRate accepts only the named supported rate set (false outside, state unchanged); process carries state across calls (streaming, not stateless per-buffer math); reset() clears ALL overlap history so zero pre-reset samples are emitted after it; latencyFrames is reported honestly and the output timeline is compensated by exactly latencyFrames so rate changes preserve the mediaTime/hostTime mapping (tolerance 1e-9); the sink contract stays packed s16le stereo 44.1 kHz (L3SampleConvert output contract).

## exact call site and interface
AudioMasterScheduler.swift (pinned excerpt) defines the clock the module must not reinterpret; the module slots between L3SampleConvert output and sink enqueue; delivery as additive Sources/GorAVPlaybackCore/ or adapter code + kits/n8-wsola-pin/ checker. This packet names the consuming pin: the W-gdb-010 withdrawal condition is closed and W-0278 reopens under it.

## behaviour that must not change
AudioMasterClock thresholds (maxLate 0.040, tolerance 1e-9) and the s16le stereo 44.1 kHz sink contract are untouched; no second clock source.

## acceptance test (from the product repo)
python3 kits/n8-wsola-pin/check.py kits/n8-wsola-pin/fixtures.json exits 0; rate rows match their golden output counts within 1 frame; the reset row witnesses zero pre-reset samples.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/AudioMasterScheduler/AudioMasterScheduler.swift (sha256 1fa0f2e7, lines 1-60 of 71)
```swift id=source1
import Foundation

public enum VideoDecision: Equatable, Sendable { case wait, present, drop }

public protocol AudioMasterScheduler {
    mutating func reset(audioTime: Double, hostTime: Double)
    mutating func seek(to seconds: Double, hostTime: Double)
    mutating func updateAudio(mediaTime: Double, hostTime: Double)
    func mediaTime(at hostTime: Double) -> Double
    @available(*, deprecated, message: "Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity")
    mutating func decide(videoPTS: Double, hostTime: Double) -> VideoDecision
}

/// Rate-one extrapolation of the most recent audio sample, in seconds.
/// Finite timestamps are required. Invalid decisions fail closed with drop;
/// invalid anchors are ignored. reset starts a new timeline and clears counters.
/// The PTS-only API tracks waiting PTS across seek, but has no frame identity.
/// Use the generation overload for complete stale-frame discrimination.
public struct AudioMasterClock: AudioMasterScheduler, Sendable {
    public static let maxLate = 0.040
    public static let tolerance = 1e-9
    public private(set) var generation: UInt64 = 0
    private var audio = 0.0
    private var host = 0.0
    private var waiting: Set<Double> = []
    private var stalePTS: Set<Double> = []
    public init() {}

    public mutating func reset(audioTime: Double, hostTime: Double) {
        guard audioTime.isFinite, hostTime.isFinite else { return }
        generation &+= 1
        waiting.removeAll(); stalePTS.removeAll()
        audio = audioTime; host = hostTime
    }
    public mutating func seek(to seconds: Double, hostTime: Double) {
        guard seconds.isFinite, hostTime.isFinite else { return }
        generation &+= 1
        stalePTS.formUnion(waiting); waiting.removeAll()
        audio = seconds; host = hostTime
    }
    public mutating func updateAudio(mediaTime: Double, hostTime: Double) {
        guard mediaTime.isFinite, hostTime.isFinite else { return }
        audio = mediaTime; host = hostTime
    }
    public func mediaTime(at hostTime: Double) -> Double {
        audio + (hostTime - host)
    }
    @available(*, deprecated, message: "Use enqueue(videoPTS:) and decide(frame:hostTime:) for seek-safe identity")
    public mutating func decide(videoPTS: Double, hostTime: Double) -> VideoDecision {
        guard videoPTS.isFinite, hostTime.isFinite else { return .drop }
        if stalePTS.contains(videoPTS) { return .drop }
        let result = classify(videoPTS: videoPTS, hostTime: hostTime)
        if result == .wait { waiting.insert(videoPTS) } else { waiting.remove(videoPTS) }
        return result
    }
    /// Capture generation when a frame is enqueued, not when it is evaluated.
    /// All pre-seek frames drop, including unseen or repeated-PTS frames.
    /// This additive overload leaves the packet's protocol unchanged.
    public func decide(videoPTS: Double, hostTime: Double, generation frameGeneration: UInt64) -> VideoDecision {
        guard frameGeneration == generation else { return .drop }
```


## roles and state
solver lab: in2tinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"op": "rate 1.0", "expect": "bit-exact passthrough shape after latencyFrames compensation; latencyFrames reported within the module's named bound"}, {"op": "rate 1.25 steady stream (multiple process calls)", "expect": "output frame count = input/1.25 within 1 frame; state carried across calls; AudioMasterClock mediaTime mapping preserved (tolerance 1e-9)"}, {"op": "reset() mid-stream", "expect": "zero pre-reset samples emitted after reset(); overlap history cleared; clock mapping preserved (tolerance 1e-9)"}]
```
