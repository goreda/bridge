// G4 (arch-195l, dispatch L6): observation surface. PLAN.md line 43:
// lifecycle/observations - time-pos, duration, pause, eof, idle, metadata,
// media-title, video-params, dwidth/dheight, fps fields, frame-drop-count,
// hwdec-current -> R2, G4. This is the mpv-style observe_property surface on
// gorav: typed properties, change-only notification, explicit unsubscribe.
// Pure Swift, Linux-tested; session publication points live in
// GorAVEmbeddedSession (Darwin target, UNCOMPILED).
import Foundation

/// Value of an observed property. `.none` is mpv's "unavailable": the
/// property is known but has no value right now (e.g. duration before open).
public enum ObservationValue: Equatable, Sendable {
    case none
    case double(Double)
    case int(Int64)
    case bool(Bool)
    case string(String)
    case stringDict([String: String])
}

/// The PLAN line-43 property set, raw values equal to the mpv property names
/// gor's scripts already observe, so a script-side observer table ports
/// without renaming.
public enum ObservationProperty: String, CaseIterable, Sendable {
    case timePos = "time-pos"
    case duration = "duration"
    case pause = "pause"
    case eofReached = "eof-reached"
    case idleActive = "idle-active"
    case metadata = "metadata"
    case mediaTitle = "media-title"
    case videoParams = "video-params"
    case width = "width"
    case height = "height"
    case dwidth = "dwidth"
    case dheight = "dheight"
    case containerFps = "container-fps"
    case estimatedVfFps = "estimated-vf-fps"
    case frameDropCount = "frame-drop-count"
    case decoderFrameDropCount = "decoder-frame-drop-count"
    case hwdecCurrent = "hwdec-current"
}

public struct ObservationChange: Equatable, Sendable {
    public let property: ObservationProperty
    public let old: ObservationValue
    public let new: ObservationValue

    public init(property: ObservationProperty, old: ObservationValue, new: ObservationValue) {
        self.property = property
        self.old = old
        self.new = new
    }
}

/// Registration handle. Removing it (or letting it deinit) unsubscribes;
/// an observer that cannot be unsubscribed is a leak, so both paths exist.
public final class ObservationToken {
    public let id: UInt64
    public let property: ObservationProperty
    private let onDeinit: (UInt64) -> Void
    private var active = true
    private let lock = NSLock()

    fileprivate init(id: UInt64, property: ObservationProperty, onDeinit: @escaping (UInt64) -> Void) {
        self.id = id
        self.property = property
        self.onDeinit = onDeinit
    }

    /// Idempotent explicit unsubscribe.
    public func cancel() {
        lock.lock()
        let was = active
        active = false
        lock.unlock()
        if was { onDeinit(id) }
    }

    deinit { cancel() }
}

/// Thread-safe property store with change-only notification. Handlers are
/// invoked OUTSIDE the store lock, in publish order; a handler that
/// re-enters the store (reads or publishes) cannot deadlock it.
public final class ObservationStore: @unchecked Sendable {

    public struct Counters: Equatable, Sendable {
        public var publishes = 0          // publish() calls
        public var changed = 0            // publishes that changed the value
        public var dedupSkips = 0         // publishes skipped as unchanged
        public var notifications = 0      // handler invocations
        public init() {}
    }

    private let lock = NSLock()
    private var values: [ObservationProperty: ObservationValue] = [:]
    private var observers: [UInt64: (ObservationProperty, (ObservationChange) -> Void)] = [:]
    private var nextID: UInt64 = 0
    public private(set) var counters = Counters()

    public init() {}

    /// Current value; `.none` when the property was never published.
    public func read(_ property: ObservationProperty) -> ObservationValue {
        lock.lock()
        defer { lock.unlock() }
        return values[property] ?? .none
    }

    /// Publish a value. Change-only: a publish equal to the current value is
    /// counted as a dedup skip and notifies nobody. Returns whether the
    /// value changed.
    @discardableResult
    public func publish(_ property: ObservationProperty, _ value: ObservationValue) -> Bool {
        lock.lock()
        counters.publishes += 1
        let old = values[property] ?? .none
        guard old != value else {
            counters.dedupSkips += 1
            lock.unlock()
            return false
        }
        values[property] = value
        counters.changed += 1
        let change = ObservationChange(property: property, old: old, new: value)
        let targets = observers.values.filter { $0.0 == property }.map { $0.1 }
        counters.notifications += targets.count
        lock.unlock()
        for handler in targets { handler(change) }
        return true
    }

    /// Observe one property. The handler fires on every CHANGE after
    /// registration (no initial replay; read() for the current value).
    public func observe(_ property: ObservationProperty,
                        handler: @escaping (ObservationChange) -> Void) -> ObservationToken {
        lock.lock()
        nextID &+= 1
        let id = nextID
        observers[id] = (property, handler)
        lock.unlock()
        return ObservationToken(id: id, property: property) { [weak self] tokenID in
            self?.remove(tokenID)
        }
    }

    private func remove(_ id: UInt64) {
        lock.lock()
        observers[id] = nil
        lock.unlock()
    }

    /// Number of live observers; test and diagnostic hook.
    public var observerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }
}
