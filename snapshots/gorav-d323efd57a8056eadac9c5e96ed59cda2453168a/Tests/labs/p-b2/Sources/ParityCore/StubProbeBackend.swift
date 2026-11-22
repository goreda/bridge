import Foundation

/// Error thrown by a stub backend configured to fail. The description is
/// deterministic and appears verbatim (sanitized) in the TSV status column.
public struct StubFailure: Error, CustomStringConvertible, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { "stub failure: \(message)" }
}

/// Fake adapter for the first P-B2 result. It returns configured values and
/// never reads fixture bytes; the fixture name is only passed through to the
/// TSV. A stub PASS is evidence about the runner, not about native parity.
public struct StubProbeBackend: ProbeBackend {
    public let name: String
    private let result: Result<PlaybackProbe, StubFailure>

    public init(name: String, probe: PlaybackProbe) {
        self.name = name
        self.result = .success(probe)
    }

    public init(name: String, failingWith message: String) {
        self.name = name
        self.result = .failure(StubFailure(message))
    }

    public func probe(fixture: String, seekTo: Double) throws -> PlaybackProbe {
        try result.get()
    }

    // MARK: JSON fixture loading

    private struct StubFile: Decodable {
        let backends: [StubEntry]
    }
    private struct StubEntry: Decodable {
        let name: String
        let result: ProbeJSON?
        let error: String?
    }
    private struct ProbeJSON: Decodable {
        let frames: Int?
        let duration: Double?
        let seekLanding: Double?
        let avOffset: Double?
    }

    /// Loads exactly two stub backends from a fixture JSON document:
    /// {"backends":[{"name":"a","result":{"frames":48,"duration":2.0,
    /// "seekLanding":1.0,"avOffset":0.0}}, ...]} — any field may be null,
    /// and "error":"<message>" makes the stub throw instead.
    public static func load(fromJSON data: Data) throws -> [StubProbeBackend] {
        let decoded: StubFile
        do {
            decoded = try JSONDecoder().decode(StubFile.self, from: data)
        } catch {
            throw ParityError.stubFixtureInvalid(String(describing: error))
        }
        guard decoded.backends.count == 2 else {
            throw ParityError.stubFixtureMustContainTwoBackends(found: decoded.backends.count)
        }
        return decoded.backends.map { entry in
            if let message = entry.error {
                return StubProbeBackend(name: entry.name, failingWith: message)
            }
            let r = entry.result ?? ProbeJSON(frames: nil, duration: nil, seekLanding: nil, avOffset: nil)
            return StubProbeBackend(name: entry.name, probe: PlaybackProbe(
                frames: r.frames, duration: r.duration, seekLanding: r.seekLanding, avOffset: r.avOffset
            ))
        }
    }
}
