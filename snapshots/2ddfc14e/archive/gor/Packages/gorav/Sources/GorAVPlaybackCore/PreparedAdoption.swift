import Foundation

public enum PreparedAdoptionRelease: Equatable, Sendable {
    case released
    case noAdoption
    /// Retry after the suspended staging/boundary operation returns. No live state changed.
    case operationInFlight
    /// A swap changed the video source. Use explicit session cancellation to stop playback.
    case alreadyCommitted
}

/// Shared by the live session and portable coordinator. This is ownership only:
/// release never closes a decoder, touches audio, changes the pump or resets a clock.
public struct PreparedAdoption: Sendable {
    private var adopted = false
    private var committed = false
    private var operation = false
    public init() {}
    public mutating func adopt() { adopted = true; committed = false; operation = false }
    public mutating func beginOperation() -> Bool {
        guard adopted, !operation else { return false }
        operation = true; return true
    }
    public mutating func finishOperation(didCommit: Bool) {
        committed = committed || didCommit; operation = false
    }
    public mutating func abortUncommitted() -> PreparedAdoptionRelease {
        guard adopted else { return .noAdoption }
        guard !operation else { return .operationInFlight }
        guard !committed else { return .alreadyCommitted }
        adopted = false
        return .released
    }
    public mutating func clear() { self = PreparedAdoption() }
}
