# W-gdb-013 N9 format/rate conversion (rewrites W-0279)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-013

target branch: ohal/gorav @ 2112af0d (lab does not push; gdb integrator integrates)
return: patch or full source + fixtures + test runner files
publication check: pinned excerpts independently matched; product tests NOT_RUN by publisher; candidate open, unclaimed.

## problem (what fails for the user)
audio format/rate conversion rides L3SampleConvert; layout/sample-format negotiation, delay accounting, flush/reset and seek-generation reset have no golden matrix, so a negotiation bug ships as channel-mapped-wrong or drifted audio.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVFFmpegAdapter/L3SampleConvert.swift (sha256 7910337a, 5713B) - the conversion seam; Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift (sha256 49cbf0b3, 51723B) - its consumer.
- real test command: the returned matrix checker runs portable on Linux; existing audio suites (swift run audio-interrupt-tests, 23 PASS) stay green.

## expected behaviour
a reusable converter module boundary with a golden negotiation matrix: layouts x sample formats x rates -> expected outcome (native, converted, typed-refusal), delay accounting, flush/reset, seek-generation reset with timestamps; synthetic rate/layout cases accompany the implementation.

## exact call site and interface
L3SampleConvert's convert/negotiate entry (pinned file) and its caller in FFmpegSoftwareAudioDecoder; the matrix + checker are the deliverable.

## behaviour that must not change
existing audio checks stay green; explicit dependency version and lifetime rules; not an ffmpeg subprocess wrapper.

## acceptance test (from the product repo)
the matrix replays green against the pinned converter; one mutated expected row fails; a seek-generation reset produces zero pre-reset samples (witnessed).

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVFFmpegAdapter/L3SampleConvert.swift (sha256 7910337a, lines 1-116 of 116)
```swift
// AUTHORED NEW (2026-10-25, L3 formats/hardware-decode lane).
// swresample-backed conversion of any L3-admitted decoded audio frame to the
// audio sink contract: packed s16le stereo 44.1 kHz. M1 admission is AAC
// only on this path; broader codec support is not implied by conversion. Conversion context
// is cached per (format, rate, layout) and re-initialized on change.
// Sync policy (when the sink consumes these chunks) stays with L1; this lane
// owns only the format/rate/channel landing.
import Foundation
import CFFmpeg

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
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
