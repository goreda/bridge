# W-gdb-044 195b-N9 resampling: consuming pin
state: candidate
solver lab: in2tinct
reviewer lab: unclaimed
id: W-gdb-044

```packet-json
{
 "packet_id": "W-gdb-044",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVFFmpegAdapter/L3SampleConvert.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "L3SampleConverter.convert(frame:maxFrameBytes:) -> (bytes, samples)?; drain(maxFrameBytes:) -> (bytes, samples)?; resetForSeek() -> Bool; currentInputDelay(inputRate:) -> Int64",
  "types": "outputRate 44100 / outputChannels 2 fixed; counters convertedFrames/conversionFailures/inputSamples/outputSamples/inputSamplesByRate/reinitCount/seekCount; nil-return typed failure",
  "ownership_lifetime": "converter context cached per (format, rate, layout), re-initialized on change (reinitCount); resetForSeek closes and reopens the context; no global state",
  "caller": "FFmpegSoftwareAudioDecoder",
  "callee": "the lab converter module behind the pinned surface; delay per gorav_l3_swr_delay semantics"
 },
 "test": {
  "command": "python3 kits/n9-resample-pin/check.py kits/n9-resample-pin/fixtures.json",
  "expected": "exit 0; stdout 'n9-resample-pin: 3/3 rows PASS'; delay accounting within one output frame of the pinned formula; mutated expected row fails",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVFFmpegAdapter/",
   "kits/n9-resample-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
resampling (195b-N9) rides L3SampleConvert; without pinned delay/lifetime/reset semantics a replacement converter drifts A/V sync silently.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0279/N9; the lab module implements against the pinned interface below.

## expected behaviour
a swresample-backed converter implementing the pinned L3SampleConverter surface exactly: convert(frame:maxFrameBytes:) -> (bytes, samples)?, drain(maxFrameBytes:) -> (bytes, samples)?, resetForSeek() -> Bool, currentInputDelay(inputRate:) -> Int64, counters (convertedFrames, conversionFailures, inputSamples, outputSamples, inputSamplesByRate, reinitCount, seekCount); fixed output contract packed s16le stereo 44.1 kHz (outputRate 44100, outputChannels 2); conversion failure is a nil return counted in conversionFailures, never a trap; a fresh converter reports exactly zero delay (pinned semantics).

## exact call site and interface
L3SampleConvert.swift (pinned excerpt): the module replaces the gorav_l3_swr_* shim behind the same Swift surface; FFmpegSoftwareAudioDecoder stays the caller; delivery as Sources/GorAVFFmpegAdapter/ code + kits/n9-resample-pin/ golden matrix.

## behaviour that must not change
the fixed 44.1 kHz stereo s16le output contract, the counter semantics and the zero-initial-delay rule are untouched; existing audio suites stay green.

## acceptance test (from the product repo)
python3 kits/n9-resample-pin/check.py kits/n9-resample-pin/fixtures.json exits 0; matrix rows match golden converted/typed-failure outcomes; delay accounting matches sum_r(input_r * 44100 / r) within one output frame.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVFFmpegAdapter/L3SampleConvert.swift (sha256 7910337a, lines 11-116 of 116)
```swift id=source1
public final class L3SampleConverter {
    public static let outputRate: Int32 = 44100
    public static let outputChannels = 2

    private var swr: UnsafeMutablePointer<GorAVL3Swr>?
    private(set) public var convertedFrames = 0
    private(set) public var conversionFailures = 0
    /// Duration-conservation witness (blocker 4): input vs output sample
    /// counts let the run report check output duration against the rate
    /// ratio instead of losing resampler delay silently.
    private(set) public var inputSamples: Int64 = 0
    private(set) public var outputSamples: Int64 = 0
    /// v4 (architect): input samples per SOURCE rate - a cross-rate sum
    /// without time normalization is not a duration witness. Duration checks
    /// compare output (fixed 44.1 kHz) against sum_r(input_r * 44100 / r).
    private(set) public var inputSamplesByRate: [Int: Int64] = [:]
    /// Actual re-init count (first init excluded); a reinit drains the old
    /// configuration's delay tail into the next output, never drops it.
    public var reinitCount: Int { Int(gorav_l3_swr_reinits(swr)) }
    /// v4.4 (r6 g3): the resampler's current input-side delay in input
    /// samples at the given input rate (negative = unavailable). The audio
    /// decoder subtracts it when computing an emitted chunk's first-sample
    /// time; the pointer itself stays private.
    public func currentInputDelay(inputRate: Int64) -> Int64 {
        guard let s = swr else { return -1 }
        // A newly allocated converter has no context/buffer until the first
        // convert. Its delay is exactly zero, not an unavailable old phase.
        if s.pointee.ctx == nil { return 0 }
        return gorav_l3_swr_delay(s, inputRate)
    }
    /// v4.2 (blocker 5): seeks the decoder runs through this lane reset the
    /// converter - typed counter for the run report, matching the video
    /// decoder's seekCount.
    private(set) public var seekCount = 0

    public init() {
        swr = gorav_l3_swr_open()
    }
    deinit {
        gorav_l3_swr_close(&swr)
    }

    /// Converts one decoded frame to packed s16le stereo at 44.1 kHz.
    /// Returns (bytes, samplesPerChannel). A zero-sample result (legal for a
    /// drained resampler edge) returns empty bytes with samples == 0 and is
    /// NOT a failure. Any real failure returns nil and is counted.
    public func convert(frame: UnsafeMutablePointer<AVFrame>,
                        maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        var outData: UnsafeMutablePointer<UInt8>?
        var outSamples: Int32 = 0
        let rc = gorav_l3_swr_convert(swr, frame, Self.outputRate, &outData, &outSamples)
        guard rc == 0 else {
            conversionFailures += 1
            return nil
        }
        guard outSamples > 0, let data = outData else {
            return ([], 0)
        }
        defer { gorav_l3_av_freep(&outData) }
        let byteCount = Int(outSamples) * Self.outputChannels * 2
        guard byteCount > 0, byteCount <= maxFrameBytes else {
            conversionFailures += 1
            return nil
        }
        convertedFrames += 1
        let inS = Int64(frame.pointee.nb_samples)
        inputSamples += inS
        inputSamplesByRate[Int(frame.pointee.sample_rate), default: 0] += inS
        outputSamples += Int64(outSamples)
        return (Array(UnsafeBufferPointer(start: data, count: byteCount)), Int(outSamples))
    }

    /// v4.2 (blocker 5): drop all resampler state for a seek. The shim
    /// re-initializes the context (delay tail gone, per-format state clean);
    /// the NEXT convert() re-establishes format/rate from the post-seek
    /// frame exactly like the first one. Counted, so the report can pair
    /// converter resets with decoder seeks.
    /// Returns false when the provider reset itself failed - the caller
    /// turns that into a typed seek failure instead of reporting success
    /// over a dirty converter (architect r5).
    @discardableResult
    public func resetForSeek() -> Bool {
        guard swr != nil else { return false }
        gorav_l3_swr_close(&swr)
        swr = gorav_l3_swr_open()
        guard swr != nil else { return false }
        seekCount += 1
        return true
    }

    /// EOF drain (blocker 4): emits the resampler delay tail after the last
    /// decoded frame. Call once at end-of-stream before .endOfStream.
    /// nil = failure; ([], 0) = nothing buffered.
    public func drain(maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        var outData: UnsafeMutablePointer<UInt8>?
        var outSamples: Int32 = 0
        let rc = gorav_l3_swr_drain(swr, &outData, &outSamples)
        guard rc == 0 else { conversionFailures += 1; return nil }
        guard outSamples > 0, let data = outData else { return ([], 0) }
        defer { gorav_l3_av_freep(&outData) }
        let byteCount = Int(outSamples) * Self.outputChannels * 2
        guard byteCount > 0, byteCount <= maxFrameBytes else { conversionFailures += 1; return nil }
        outputSamples += Int64(outSamples)
        return (Array(UnsafeBufferPointer(start: data, count: byteCount)), Int(outSamples))
    }
}
```


## roles and state
solver lab: in2tinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"in": "f32le stereo 48000", "expect": "converted to s16le stereo 44100; inputSamplesByRate[48000] grows"}, {"op": "drain after convert", "expect": "drain returns tail samples then empty; samples==0 rows are valid empties"}, {"op": "resetForSeek", "expect": "returns true; delay counters restart; zero pre-reset samples after"}]
```
