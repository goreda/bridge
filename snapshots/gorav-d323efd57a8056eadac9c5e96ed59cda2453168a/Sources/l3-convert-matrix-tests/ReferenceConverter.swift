import Foundation

/// One fabricated input frame for the reference lane (no AVFrame, no CFFmpeg).
public struct RefFrame {
    public var layout: String
    public var inFormat: String
    public var inRate: Int
    public var inSamples: Int
    public var tone: Double? // Hz; output is a synthesized s16le sine at this frequency
}

/// Portable reference model of the pinned L3SampleConverter's OBSERVABLE
/// contract (kits/l3-matrix reference lane). It mirrors the pinned excerpt
/// Sources/GorAVFFmpegAdapter/L3SampleConvert.swift (sha256 7910337a, product
/// pin 2112af0d, branch ohal/gorav): same counters, same typed nil-failure
/// rule, same legal zero-sample edge, same delay/drain/seek-reset semantics.
/// Admission rule (layout != unknown, rate > 0, known sample format) was
/// MEASURED against real libswresample in the excerpt harness; see matrix.json
/// provenance. It uses no FFmpeg: it exists so the golden matrix replays
/// anywhere Swift runs, without the gorav_l3_swr_* provider.
public final class ReferenceConverter {
    public static let outputRate = 44100
    public static let outputChannels = 2
    /// Modelled resampler input-side delay, in input samples per active config.
    public static let inputDelay = 32

    public private(set) var convertedFrames = 0
    public private(set) var conversionFailures = 0
    public private(set) var inputSamples: Int64 = 0
    public private(set) var outputSamples: Int64 = 0
    public private(set) var inputSamplesByRate: [Int: Int64] = [:]
    public private(set) var seekCount = 0
    public private(set) var reinitCount = 0

    private struct Config: Equatable { var layout: String; var format: String; var rate: Int }
    private var config: Config?     // nil = no context yet (fresh or post-seek-reset)
    private var cumIn: Int64 = 0    // input samples in current config
    private var emitted: Int64 = 0  // output samples emitted in current config
    private var phase = 0.0
    private var valid = true        // false models provider allocation failure

    public init() {}

    public static let knownFormats: Set<String> =
        ["u8", "s16le", "s32le", "f32le", "f64le", "u8p", "s16p", "s32p", "fltp", "dblp"]

    private func admitted(_ f: RefFrame) -> Bool {
        f.layout != "unknown" && f.inRate > 0 && ReferenceConverter.knownFormats.contains(f.inFormat)
    }

    private func totalIdeal(_ cfg: Config, _ cum: Int64) -> Int64 {
        Int64((Double(cum) * Double(ReferenceConverter.outputRate) / Double(cfg.rate)).rounded(.down))
    }

    /// Mirrors the pinned convert(): nil = typed failure (counted); ([],0) =
    /// legal zero-sample edge (not counted); success counts convertedFrames
    /// and accumulates the duration witnesses.
    public func convert(frame f: RefFrame, maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        guard valid else { conversionFailures += 1; return nil }
        guard admitted(f) else { conversionFailures += 1; return nil }
        let cfg = Config(layout: f.layout, format: f.inFormat, rate: f.inRate)
        var out = 0
        if let cur = config, cur != cfg {
            // re-init on (format, rate, layout) change: flush the old delay
            // tail into this output, never drop it (excerpt comment).
            out += Int(totalIdeal(cur, cumIn) - emitted)
            reinitCount += 1
            config = cfg; cumIn = 0; emitted = 0
        } else if config == nil {
            config = cfg; cumIn = 0; emitted = 0
        }
        cumIn += Int64(f.inSamples)
        let delayOut = Int64((Double(ReferenceConverter.inputDelay) * Double(ReferenceConverter.outputRate) / Double(cfg.rate)).rounded(.up))
        let avail = max(Int64(0), totalIdeal(cfg, cumIn) - delayOut)
        out += Int(avail - emitted)
        emitted = avail
        let byteCount = out * ReferenceConverter.outputChannels * 2
        guard byteCount > 0 else { return ([], 0) }
        guard byteCount <= maxFrameBytes else { conversionFailures += 1; return nil }
        convertedFrames += 1
        inputSamples += Int64(f.inSamples)
        inputSamplesByRate[f.inRate, default: 0] += Int64(f.inSamples)
        outputSamples += Int64(out)
        return (synth(tone: f.tone, samples: out), out)
    }

    /// Mirrors the pinned drain(): emits the modelled delay tail.
    public func drain(maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        guard valid else { conversionFailures += 1; return nil }
        guard let cfg = config else { return ([], 0) }
        let out = Int(totalIdeal(cfg, cumIn) - emitted)
        emitted += Int64(out)
        let byteCount = out * ReferenceConverter.outputChannels * 2
        guard byteCount > 0 else { return ([], 0) }
        guard byteCount <= maxFrameBytes else { conversionFailures += 1; return nil }
        outputSamples += Int64(out)
        return (synth(tone: nil, samples: out), out)
    }

    /// Mirrors the pinned resetForSeek(): drops all resampler state (delay
    /// tail gone), keeps the counters, bumps seekCount, returns success.
    @discardableResult
    public func resetForSeek() -> Bool {
        guard valid else { return false }
        config = nil; cumIn = 0; emitted = 0
        seekCount += 1
        return true
    }

    /// Mirrors the pinned currentInputDelay(): -1 unavailable, 0 before the
    /// first convert establishes a context, otherwise the modelled delay.
    public func currentInputDelay(inputRate: Int64) -> Int64 {
        guard valid else { return -1 }
        guard config != nil else { return 0 }
        return Int64(ReferenceConverter.inputDelay)
    }

    private func synth(tone: Double?, samples: Int) -> [UInt8] {
        let f = tone ?? 440.0
        var bytes = [UInt8](); bytes.reserveCapacity(samples * 4)
        for _ in 0..<samples {
            let v = Int16(clamping: Int(sin(2.0 * Double.pi * f * phase / Double(ReferenceConverter.outputRate)) * 12000.0))
            phase += 1
            bytes.append(UInt8(truncatingIfNeeded: v))
            bytes.append(UInt8(truncatingIfNeeded: v >> 8))
            bytes.append(UInt8(truncatingIfNeeded: v))
            bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        }
        return bytes
    }
}
