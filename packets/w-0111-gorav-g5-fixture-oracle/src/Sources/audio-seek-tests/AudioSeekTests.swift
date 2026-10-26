// Native PCM seek + exact arithmetic checks. NOT a core/ring/presentation test.
import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

@main struct AudioSeekTests {
    static func main() async {
        func require(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL \(message)"); exit(1) }
        }
        do {
            let zero = try RationalTime(value: 0, timescale: 1)
            let half = try RationalTime(value: 1, timescale: 2)
            let negative = try RationalTime(value: -1, timescale: 4)
            require(try AudioMediaTime.add(half, negative) == RationalTime(value: 1, timescale: 4), "signed common origin")
            require(try AudioMediaTime.trimSamples(target: RationalTime(value: 1, timescale: 3), frameStart: zero, rate: 10) == 4, "ceil sample trim")
            require(try AudioMediaTime.trimSamples(target: zero, frameStart: half, rate: 44100) == 0, "late audio gap preserves start")
            guard let path = ProcessInfo.processInfo.environment["GORAV_AUDIO_SEEK_FILE"] else {
                print("NOT_RUN native: set GORAV_AUDIO_SEEK_FILE; arithmetic passed"); exit(2)
            }
            guard let session = PlaybackIdentityAuthority.shared.issue() else { print("FAIL session exhaustion"); exit(1) }
            let decoder = FFmpegSoftwareAudioDecoder()
            try decoder.pinLocalRoots([URL(fileURLWithPath: path).deletingLastPathComponent().path])
            try await decoder.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: session)
            guard var d = await decoder.seekDescriptor(session: session), d.seekable, let origin = d.referenceOrigin else {
                print("FAIL descriptor"); exit(1)
            }
            // Fixture-specific exact expectation. Offset fixture: 4410/44100;
            // canonical/noel: 0/44100. Do not accept mere >=target as offset proof.
            let expectedZeroPTS = ProcessInfo.processInfo.environment["GORAV_AUDIO_EXPECT_ZERO_PTS"].flatMap(Int64.init)
            if let expectedZeroPTS {
                let expectedStart = try AudioMediaTime.timestamp(expectedZeroPTS, timebase: d.audioTimebase)
                require(d.audioStart == expectedStart, "fixture audio start descriptor")
            }
            for (i, target) in [zero, half, zero].enumerated() {
                let old = d.binding
                let common = try AudioMediaTime.add(origin, target)
                let result = await decoder.seek(binding: old, videoRelativeTarget: target, correlation: UInt64(i + 1))
                guard case .nativeReady(let binding, let correlation, let actualTarget, let ticks) = result else {
                    print("FAIL seek \(result)"); exit(1)
                }
                require(actualTarget == common && binding.source == old.source && binding.revision == old.revision + 1, "seek identity/common target")
                require(ticks == (try common.floorTicks(toTimebaseNumerator: d.audioTimebase.value, denominator: Int64(d.audioTimebase.timescale))), "floor audio ticks")
                let stale = await decoder.nextBoundEvent(binding: old)
                require(stale == nil, "stale binding pulls nothing")
                let legacy = await decoder.nextEvent(session: session)
                require(legacy == nil, "legacy cannot consume coordinated PCM")
                var found = false
                for _ in 0..<100_000 {
                    guard let envelope = await decoder.nextBoundEvent(binding: binding) else { break }
                    require(envelope.binding == binding && envelope.correlation == correlation, "origin captured with event")
                    switch envelope.event {
                    case .pcm(let frame):
                        guard let timing = envelope.timing, let gap = timing.gapFromTarget else { print("FAIL missing PCM timing"); exit(1) }
                        require(timing.seekTarget == common && timing.firstSample >= common && gap.value >= 0, "no pretarget sample / honest gap")
                        require(frame.bytes.count == frame.samples * frame.channels * 2, "trimmed bytes match samples")
                        if target == zero, let expectedZeroPTS {
                            let expectedFirst = try AudioMediaTime.timestamp(expectedZeroPTS, timebase: d.audioTimebase)
                            require(timing.firstSample == expectedFirst, "exact zero-seek fixture landing preserves offset")
                            require(gap == (try AudioMediaTime.subtract(expectedFirst, common)), "exact zero-seek gap")
                        }
                        print("LANDING target=\(common.value)/\(common.timescale) first=\(timing.firstSample.value)/\(timing.firstSample.timescale) gap=\(gap.value)/\(gap.timescale) trim=\(timing.trimmedSamples) pts=\(timing.decodedPTS)")
                        found = true
                    case .failed(let code, let summary): print("FAIL PCM \(code) \(summary)"); exit(1)
                    case .endOfStream: print("FAIL EOS before landing"); exit(1)
                    case .opened: break
                    }
                    if found { break }
                }
                require(found, "postseek PCM observed")
                guard let next = await decoder.seekDescriptor(session: session) else { print("FAIL descriptor after seek"); exit(1) }
                d = next
            }
            await decoder.close(session: session)
            let closed = await decoder.nextBoundEvent(binding: d.binding)
            require(closed == nil, "closed binding")
            print("PASS audio provider native seek/flush/trim/origin, 3 landings; NOT core/presentation")
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
