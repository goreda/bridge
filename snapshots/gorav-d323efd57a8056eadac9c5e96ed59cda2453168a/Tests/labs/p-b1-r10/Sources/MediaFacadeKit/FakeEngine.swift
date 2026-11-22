import Foundation

/// Fake engine for the P-B1 tests. Records every call, returns scripted values,
/// replays scripted errors, and delivers observer callbacks on `set`.
/// Its served vocabulary is the approved E1 row set delivered at bridge commit
/// 0fe957bed27c486a58b19f5515cce7d662cabae5 (commands loadfile/seek/stop; properties
/// pause, time-pos, duration, track-list, speed, volume, sid, mute, audio, sub);
/// unknown names throw, never silently succeed.
public final class FakeEngine: MediaEngine {
    public struct RecordedCall: Equatable, Sendable {
        public enum Op: String, Equatable, Sendable { case command, get, set, observe, unobserve, notify }
        public let op: Op
        public let name: String
        public let arguments: [MediaValue]
        /// The exact engine API token for observe/unobserve calls, kept as UInt64.
        /// Never Double-converted: Double cannot represent UInt64.max or 2^53+1, so a
        /// Double-converted call log would silently corrupt the token (P-B1-R1).
        public let token: UInt64?

        public init(op: Op, name: String, arguments: [MediaValue], token: UInt64? = nil) {
            self.op = op
            self.name = name
            self.arguments = arguments
            self.token = token
        }
    }

    public static let candidateCommands: Set<String> = ["loadfile", "seek", "stop", "cycle", "add", "frame-step", "frame-back-step"]
    public static let candidateProperties: Set<String> = ["pause", "time-pos", "duration", "track-list", "speed", "volume", "sid", "mute", "audio", "sub", "aid", "vid"]

    private var recordedCalls: [RecordedCall] = []
    private var properties: [String: MediaValue] = [:]
    private var observers: [UInt64: (String, (MediaValue) -> Void)] = [:]
    private var scriptedErrors: [String: MediaError] = [:]
    private let lock = NSLock()

    /// Recorded calls, read under the same lock that writes them (a snapshot copy).
    public var calls: [RecordedCall] {
        lock.lock(); defer { lock.unlock() }
        return recordedCalls
    }

    public init(initialProperties: [String: MediaValue] = [:]) {
        self.properties = initialProperties
    }

    /// Script a named error for a command or property ("command:seek" / "property:volume").
    public func scriptError(_ key: String, _ error: MediaError) {
        lock.lock(); defer { lock.unlock() }
        scriptedErrors[key] = error
    }

    public var propertySnapshot: [String: MediaValue] {
        lock.lock(); defer { lock.unlock() }
        return properties
    }

    public func command(_ name: String, arguments: [MediaValue]) throws -> MediaValue {
        lock.lock()
        recordedCalls.append(RecordedCall(op: .command, name: name, arguments: arguments))
        let scripted = scriptedErrors["command:\(name)"]
        let known = Self.candidateCommands.contains(name)
        lock.unlock()
        if let scripted { throw scripted }
        guard known else { throw MediaError.unsupportedCommand(name) }
        // E2 note: cycle/add are the generic property commands. The facade enforces the
        // argument spec only; whether a (cycle|add, name) pair is meaningful is
        // engine-level policy. This fake's documented policy: the target name must be a
        // known property, otherwise it throws unsupportedProperty at the engine level.
        if name == "cycle" || name == "add" {
            guard let target = arguments.first, case .text(let property) = target,
                  Self.candidateProperties.contains(property) else {
                if case .text(let property) = arguments.first {
                    throw MediaError.unsupportedProperty(property)
                }
                throw MediaError.unsupportedProperty(arguments.first.map { "\($0)" } ?? "")
            }
        }
        return .none
    }

    public func get(_ property: String) throws -> MediaValue {
        lock.lock()
        recordedCalls.append(RecordedCall(op: .get, name: property, arguments: []))
        let scripted = scriptedErrors["property:\(property)"]
        let known = Self.candidateProperties.contains(property)
        let value = properties[property]
        lock.unlock()
        if let scripted { throw scripted }
        guard known else { throw MediaError.unsupportedProperty(property) }
        return value ?? .none
    }

    public func set(_ property: String, value: MediaValue) throws {
        lock.lock()
        recordedCalls.append(RecordedCall(op: .set, name: property, arguments: [value]))
        let scripted = scriptedErrors["property:\(property)"]
        let known = Self.candidateProperties.contains(property)
        if scripted == nil && known {
            properties[property] = value
        }
        let callbacks: [(MediaValue) -> Void] = (scripted == nil && known)
            ? observers.values.filter { $0.0 == property }.map { $0.1 }
            : []
        lock.unlock()
        if let scripted { throw scripted }
        guard known else { throw MediaError.unsupportedProperty(property) }
        for callback in callbacks { callback(value) } // property-change notification, mpv-style
    }

    /// Simulates an engine-originated property change (playback position advancing, duration
    /// discovered): stores the value and notifies observers. This is how read-only
    /// observables (time-pos, duration - no set row in the approved table) change value.
    public func simulateChange(_ property: String, value: MediaValue) {
        lock.lock()
        properties[property] = value
        recordedCalls.append(RecordedCall(op: .notify, name: property, arguments: [value]))
        let callbacks: [(MediaValue) -> Void] = observers.values.filter { $0.0 == property }.map { $0.1 }
        lock.unlock()
        for callback in callbacks { callback(value) }
    }

    public func observe(_ property: String, token: UInt64, callback: @escaping (MediaValue) -> Void) throws {
        lock.lock()
        recordedCalls.append(RecordedCall(op: .observe, name: property, arguments: [], token: token))
        let known = Self.candidateProperties.contains(property)
        if known { observers[token] = (property, callback) }
        lock.unlock()
        guard known else { throw MediaError.unsupportedProperty(property) }
    }

    public func unobserve(token: UInt64) {
        lock.lock()
        let removed = observers.removeValue(forKey: token)
        recordedCalls.append(RecordedCall(op: .unobserve, name: removed?.0 ?? "", arguments: [], token: token))
        lock.unlock()
    }
}
