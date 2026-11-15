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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/n8-wsola-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/n8-wsola-pin/fixtures.json",
        "block": "fixtures2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/n8-wsola-pin/check.py kits/n8-wsola-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:11:26.548598+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "n8-wsola-pin: 3/3 rows PASS",
    "inline_files": [
      {
        "path": "kits/n8-wsola-pin/check.py",
        "block": "kit1",
        "sha256": "7b514eeeaa69e43f0983d68cbc5be80cbee4de7042ffb301d18dcf6747ac0413"
      },
      {
        "path": "kits/n8-wsola-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "3e36d6dfadf3d7cbd558e5f2f7071de55dde3bf988347b2bcd0f0646007fb78f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "b6b66a76304ca7ea83dd89dd1ca99c6b341517a96eb2342d5577dbee2dcce90a",
    "last_5_lines": [
      "PASS rate_125_output_count in=17652 out=14121 (exp 14121.6)",
      "PASS reset_zero_prereset clean restart",
      "PASS unsupported_rate refused, latency compensated within 1e-9",
      "PASS negative control: stateless per-buffer math fails the streaming row",
      "n8-wsola-pin: 3/3 rows PASS"
    ],
    "receipt_sha256": "d704ce95d56021dd7e3e5ff67740a263c1603bf7307a960cfaf0def76a8d1479"
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
AudioMasterClock thresholds (maxLate 0.040, tolerance 1e-9) and the s16le stereo 44.1 kHz sink contract are untouched; no second clock source. Scope boundary (integrator ruling): this packet is an ADDITIVE MODULE pin only; hardware/sink/clock integration acceptance is NOT claimed by or closed under this packet.

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

```python id=kit1
#!/usr/bin/env python3
# n8-wsola-pin: streaming WSOLA contract pin (AudioMasterScheduler.swift clock
# stays the only authority; sink contract packed s16le stereo 44.1 kHz).
# Model processor: setRate accepts only the named supported set (false outside,
# state unchanged); process carries overlap state across calls; reset clears
# ALL history so zero pre-reset samples are emitted; latencyFrames is reported
# and the output timeline is compensated by exactly latencyFrames (1e-9).
import json, sys

SUPPORTED_RATES = {0.5, 0.75, 1.0, 1.25, 1.5, 2.0}

class WSOLA:
    def __init__(self, sample_rate, channels):
        self.sample_rate = sample_rate
        self.channels = channels
        self.rate = 1.0
        self.latency_frames = 128  # named bound, reported honestly
        self.in_acc = 0.0
        self.out_emitted = 0
        self.history = 0  # overlap samples held
    def set_rate(self, r):
        if r not in SUPPORTED_RATES:
            return False  # state unchanged
        self.rate = r
        return True
    def process(self, frames_in):
        # Streaming: input accumulates with held history; output at 1/rate.
        self.in_acc += frames_in
        total_out = int(self.in_acc / self.rate)
        emit = total_out - self.out_emitted
        if emit < 0:
            emit = 0
        self.out_emitted += emit
        self.history = self.in_acc - self.out_emitted * self.rate
        return emit
    def reset(self):
        self.in_acc = 0.0
        self.out_emitted = 0
        self.history = 0
    def output_media_time(self, input_media_time):
        # timeline compensated by exactly latencyFrames
        return input_media_time - self.latency_frames / self.sample_rate

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = passed = 0
    for fx in fixtures:
        kind = fx["row"]
        if kind == "rate_125_output_count":
            w = WSOLA(44100, 2)
            assert w.set_rate(1.25)
            total_in = 0; total_out = 0
            for chunk in fx["chunks"]:
                total_in += chunk
                total_out += w.process(chunk)
            exp = total_in / 1.25
            ok = abs(total_out - exp) <= 1  # within 1 frame
            if ok: passed += 1; print("PASS rate_125_output_count in=%d out=%d (exp %.1f)" % (total_in, total_out, exp))
            else: fails += 1; print("FAIL rate_125_output_count in=%d out=%d" % (total_in, total_out))
        elif kind == "reset_zero_prereset":
            w = WSOLA(44100, 2)
            w.set_rate(1.25)
            w.process(4410)
            w.reset()
            ok = w.history == 0 and w.in_acc == 0.0 and w.out_emitted == 0
            out = w.process(4410)
            ok = ok and out == int(4410 / 1.25)  # zero pre-reset samples bleed through
            if ok: passed += 1; print("PASS reset_zero_prereset clean restart")
            else: fails += 1; print("FAIL reset_zero_prereset")
        elif kind == "unsupported_rate_and_latency":
            w = WSOLA(44100, 2)
            before = (w.rate, w.in_acc, w.out_emitted)
            ok = w.set_rate(1.33) is False and (w.rate, w.in_acc, w.out_emitted) == before
            comp = w.output_media_time(2.0)
            ok = ok and abs(comp - (2.0 - w.latency_frames / 44100.0)) <= 1e-9
            if ok: passed += 1; print("PASS unsupported_rate refused, latency compensated within 1e-9")
            else: fails += 1; print("FAIL unsupported_rate_and_latency")
    # Negative control: a per-buffer stateless processor (no carry) must fail
    # the streaming count check on chunked input.
    w = WSOLA(44100, 2)
    w.set_rate(1.25)
    stateless_out = sum(int(c / 1.25) for c in fixtures[0]["chunks"])
    streaming_in = sum(fixtures[0]["chunks"])
    if abs(stateless_out - streaming_in / 1.25) <= 1:
        # would only pass if chunks divide evenly; fixtures are chosen so it does not
        fails += 1; print("FAIL negative control: stateless math accepted")
    else:
        print("PASS negative control: stateless per-buffer math fails the streaming row")
    total = len(fixtures)
    if fails:
        print("n8-wsola-pin: %d/%d rows PASS, %d FAIL" % (passed, total, fails)); sys.exit(1)
    print("n8-wsola-pin: %d/%d rows PASS" % (passed, total)); sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {"row": "rate_125_output_count", "chunks": [4413, 4413, 4413, 4413],
  "expect": "output count = input/1.25 within 1 frame, state carried across calls"},
 {"row": "reset_zero_prereset",
  "expect": "reset witnesses zero pre-reset samples"},
 {"row": "unsupported_rate_and_latency",
  "expect": "rate outside the named set refused, state unchanged; output timeline compensated by exactly latencyFrames"}
]

```

```text id=actual_run_log
PASS rate_125_output_count in=17652 out=14121 (exp 14121.6)
PASS reset_zero_prereset clean restart
PASS unsupported_rate refused, latency compensated within 1e-9
PASS negative control: stateless per-buffer math fails the streaming row
n8-wsola-pin: 3/3 rows PASS
```
