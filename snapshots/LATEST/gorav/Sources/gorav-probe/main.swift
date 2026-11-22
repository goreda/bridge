import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// Read-only native engine measurement. No shell or external-tool fallback.
// A/V offset stays unavailable until paired physical playback is measured.
@main struct GorAVProbe {
    enum ProbeFailure: Error { case toolFailed(String), unparseable(String) }
    struct Measurement { var frames = 0; var first: Double?; var end: Double?; var landing: Double? }
    static let header = "fixture\tbackend\tseek_target_s\tframes\tduration_s\tseek_landing_s\tav_offset_s\tstatus"
    static func field(_ s: String) -> String { s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
    static func number(_ n: Double?) -> String { n.map { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "NA" }
    static func measure(_ path: String, seek: Double?) async throws -> Measurement {
        let decoder = FFmpegSoftwareDecoder()
        let authority = PlaybackIdentityAuthority.shared
        guard let session = authority.issue() else { throw ProbeFailure.toolFailed("identityExhausted") }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        try decoder.pinLocalRoots([url.deletingLastPathComponent().path])
        do { try await decoder.open(source: SourceDescriptor(id: url.path, kind: .local, seekable: true), session: session) }
        catch { throw ProbeFailure.unparseable("open: \(error)") }
        var result = Measurement()
        do {
            if let seek { try await decoder.seek(toSeconds: seek, session: session) }
            var ended = false
            while !ended, let event = await decoder.nextEvent(session: session) {
                switch event {
                case .frameDecoded(let frame):
                    result.frames += 1
                    if case .success(let observation) = await decoder.observeRetainedFrame(handle: frame.handle, session: session),
                       let pts = observation.pts, observation.ptsTimeBaseNum > 0, observation.ptsTimeBaseDen > 0 {
                        let scale = Double(observation.ptsTimeBaseNum) / Double(observation.ptsTimeBaseDen)
                        let start = Double(pts) * scale
                        if start.isFinite {
                            if result.landing == nil { result.landing = start }
                            result.first = min(result.first ?? start, start)
                            let end = start + Double(max(0, observation.duration)) * scale
                            if end.isFinite { result.end = max(result.end ?? end, end) }
                        }
                    }
                    await decoder.releaseFrame(handle: frame.handle, session: session)
                case .endOfStream: ended = true
                case .failed(let code, let summary): throw ProbeFailure.toolFailed("decode \(code): \(summary)")
                case .interrupted(let summary): throw ProbeFailure.toolFailed("interrupted: \(summary)")
                case .feedSaturated(let count): throw ProbeFailure.toolFailed("feedSaturated: \(count)")
                case .opened: break
                }
            }
            let receipt = await decoder.closeAndReport(session: session)
            guard let receipt, receipt.leakedHandles.isEmpty, receipt.leaseTableLeaks.isEmpty,
                  receipt.ledgerLeaks.isEmpty else { throw ProbeFailure.toolFailed("closeLeaks") }
            return result
        } catch {
            _ = await decoder.closeAndReport(session: session)
            throw error
        }
    }
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let path = args.first else { fail("usage: gorav-probe <file> [--seek <seconds>]...", 65) }
        var seeks: [Double] = []; var i = 1
        while i < args.count {
            guard args[i] == "--seek", i + 1 < args.count, let s = Double(args[i+1]), s.isFinite, s >= 0 else { fail("unparseable: invalid --seek", 65) }
            seeks.append(s); i += 2
        }
        if seeks.isEmpty { seeks = [0] }
        do {
            let whole = try await measure(path, seek: nil)
            guard whole.frames > 0 else { throw ProbeFailure.unparseable("no video frames") }
            let duration = whole.first.flatMap { first in whole.end.map { $0 - first } }
            var rows = [header]
            for target in seeks {
                let landed = try await measure(path, seek: target)
                rows.append([field(path), "gorav-native", number(target), String(whole.frames), number(duration), number(landed.landing), "NA", "na"].joined(separator: "\t"))
            }
            print(rows.joined(separator: "\n"))
        } catch ProbeFailure.unparseable(let message) { fail("unparseable: " + message, 65) }
        catch { fail("toolFailed: \(error)", 70) }
    }
    static func fail(_ message: String, _ code: Int32) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8)); exit(code)
    }
}
