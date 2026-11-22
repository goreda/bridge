/// A pluggable measurement backend. Implementations may wrap real engines
/// (out of scope for the stub phase) or return fixed stub values for tests.
public protocol ProbeBackend {
    var name: String { get }
    func probe(fixture: String, seekTo: Double) throws -> PlaybackProbe
}
