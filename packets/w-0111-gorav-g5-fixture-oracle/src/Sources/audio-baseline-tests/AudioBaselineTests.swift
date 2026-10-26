// Bounded legacy PCM regression. This is not an audio-seek or delayed-codec test.
import Foundation
import GorAVCore
import GorAVFFmpegAdapter

@main struct AudioBaselineTests {
    static func main() async {
        guard let path = ProcessInfo.processInfo.environment["GORAV_AUDIO_BASELINE_FILE"],
              let expectedBytesText = ProcessInfo.processInfo.environment["GORAV_AUDIO_EXPECTED_BYTES"],
              let expectedBytes = Int(expectedBytesText), expectedBytes >= 0 else {
            print("NOT_RUN: set GORAV_AUDIO_BASELINE_FILE and GORAV_AUDIO_EXPECTED_BYTES")
            exit(2)
        }
        let decoder = FFmpegSoftwareAudioDecoder()
        guard let session = PlaybackIdentityAuthority.shared.issue() else {
            print("FAIL session identity exhaustion"); exit(1)
        }
        do {
            try decoder.pinLocalRoots([URL(fileURLWithPath: path).deletingLastPathComponent().path])
            try await decoder.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: session)
            var opened = 0, pcm = 0, bytes = 0, eos = 0
            var handles = Set<UInt64>()
            var terminal = false
            for _ in 0..<100_000 {
                guard let event = await decoder.nextEvent(session: session) else { break }
                switch event {
                case .opened: opened += 1
                case .pcm(let frame):
                    guard !terminal, frame.sampleRate > 0, frame.channels > 0,
                          frame.samples > 0, frame.bytes.count == frame.samples * frame.channels * 2,
                          frame.bytes.count <= FFmpegSoftwareAudioDecoder.maxFrameBytes,
                          handles.insert(frame.handle).inserted else {
                        print("FAIL PCM shape/order/handle"); exit(1)
                    }
                    pcm += 1; bytes += frame.bytes.count
                case .endOfStream: eos += 1; terminal = true
                case .failed(let code, let summary):
                    print("FAIL native \(code) \(summary)"); exit(1)
                }
            }
            let afterTerminal = await decoder.nextEvent(session: session)
            guard opened == 1, pcm > 0, bytes == expectedBytes, eos == 1,
                  afterTerminal == nil else {
                print("FAIL opened=\(opened) pcm=\(pcm) bytes=\(bytes) eos=\(eos)"); exit(1)
            }
            await decoder.close(session: session)
            guard await decoder.nextEvent(session: session) == nil else {
                print("FAIL closed pull"); exit(1)
            }
            print("PASS legacy PCM opened=\(opened) frames=\(pcm) bytes=\(bytes) EOS=\(eos), postEOS/closed=nil")
        } catch {
            print("FAIL open \(error)"); exit(1)
        }
    }
}
