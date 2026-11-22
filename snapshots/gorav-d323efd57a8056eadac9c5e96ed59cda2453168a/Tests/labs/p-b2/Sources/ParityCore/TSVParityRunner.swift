/// Deterministic TSV parity runner. Row order is always left then right.
/// Probe errors are captured per backend and reported in the status column;
/// `run` itself throws only for invalid runner inputs (non-finite seekTo).
public struct TSVParityRunner: ParityRunner {
    public init() {}

    public static let header =
        "fixture\tbackend\tframes\tduration_s\tseek_target_s\tseek_landing_s\tav_offset_s\tstatus"

    public func run(fixture: String, seekTo: Double, left: any ProbeBackend, right: any ProbeBackend) throws -> String {
        guard seekTo.isFinite else { throw ParityError.nonFiniteSeekTarget }

        let outcomes: [Result<PlaybackProbe, Error>] = [left, right].map { backend in
            do {
                return .success(try backend.probe(fixture: fixture, seekTo: seekTo))
            } catch {
                return .failure(error)
            }
        }

        let statuses: [ParityStatus]
        switch (outcomes[0], outcomes[1]) {
        case let (.failure(e0), .failure(e1)):
            statuses = [.error(String(describing: e0)), .error(String(describing: e1))]
        case let (.failure(e0), .success):
            statuses = [.error(String(describing: e0)), .unavailable]
        case let (.success, .failure(e1)):
            statuses = [.unavailable, .error(String(describing: e1))]
        case let (.success(p0), .success(p1)):
            let s = TSVParityRunner.compare(p0, p1)
            statuses = [s, s]
        }

        var lines = [TSVParityRunner.header]
        let backends = [left, right]
        for i in 0..<2 {
            lines.append(TSVParityRunner.row(
                fixture: fixture,
                backend: backends[i].name,
                probe: try? outcomes[i].get(),
                seekTo: seekTo,
                status: statuses[i]
            ))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Exact numeric equality on every measured field. Any field missing on
    /// either side forces `.unavailable` (NA is never equal to a number and
    /// never silently pass); otherwise any mismatch yields `.different`.
    static func compare(_ a: PlaybackProbe, _ b: PlaybackProbe) -> ParityStatus {
        var anyMissing = false
        var anyDifferent = false
        func cmp<T: Equatable>(_ x: T?, _ y: T?) {
            if x == nil || y == nil {
                anyMissing = true
            } else if x != y {
                anyDifferent = true
            }
        }
        cmp(a.frames, b.frames)
        cmp(a.duration, b.duration)
        cmp(a.seekLanding, b.seekLanding)
        cmp(a.avOffset, b.avOffset)
        if anyMissing { return .unavailable }
        return anyDifferent ? .different : .pass
    }

    static func row(fixture: String, backend: String, probe: PlaybackProbe?, seekTo: Double, status: ParityStatus) -> String {
        let fields = [
            TSVEscape.sanitize(fixture),
            TSVEscape.sanitize(backend),
            TSVFormat.field(probe?.frames ?? nil),
            TSVFormat.field(probe?.duration ?? nil),
            TSVFormat.double(seekTo),
            TSVFormat.field(probe?.seekLanding ?? nil),
            TSVFormat.field(probe?.avOffset ?? nil),
            status.token, // already sanitized at construction
        ]
        return fields.joined(separator: "\t")
    }
}
