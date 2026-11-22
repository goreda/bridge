import Foundation

/// The facade: maps public media commands/properties/observers onto a pluggable
/// MediaEngine (P-B1). Pure forwarding plus validation against the installed approved
/// E1 row table (facade-rows.tsv). Gating, from the approved rows only:
/// - command: a `command` row; arguments bind positionally in the row's declared
///   order (required specs first in order, optionals may be appended in order) and
///   each supplied argument is type-checked against its spec. Command results pass
///   through unchecked ("command-result-or-error": any result value, errors thrown).
/// - get: a `property-get` or `property-mutate` row.
/// - set: a `property-set` or `property-mutate` row (the property-set row governs
///   when both exist); the value is bound against the row's single typed "value:"
///   argument spec, whose token carries the posted domain: "number(0.01..100)"
///   enforces the explicit bounds, "number(percent)" enforces the numeric type only
///   (percent is a unit annotation - no 0..100 range is invented), and
///   "integer|string(auto|no)" enforces finite integral numbers or the exact enum
///   strings. The value_type column is the property's looser result type
///   ("-or-unavailable" admits .none), kept for get/observe shape reference.
/// - observe: a `property-observe` row only.
/// - unobserve: no row gate.
public final class Facade: MediaFacade {
    private let engine: MediaEngine
    private var rows: RowTable?
    private let lock = NSLock()

    public init(engine: MediaEngine, rows: RowTable? = nil) {
        self.engine = engine
        self.rows = rows
    }

    /// Install the approved E1 row set (facade-rows.tsv) once delivered.
    public func installRows(_ table: RowTable) {
        lock.lock(); defer { lock.unlock() }
        rows = table
    }

    private func currentRows() -> RowTable? {
        lock.lock(); defer { lock.unlock() }
        return rows
    }

    public func command(_ name: String, arguments: [MediaValue]) throws -> MediaValue {
        if let rows = currentRows() {
            guard let row = rows.row(kind: .command, name: name) else { throw MediaError.unsupportedCommand(name) }
            try Self.check(arguments: arguments, against: row)
        }
        return try engine.command(name, arguments: arguments)
    }

    public func get(_ property: String) throws -> MediaValue {
        if let rows = currentRows() {
            let row = rows.row(kind: .propertyGet, name: property) ?? rows.row(kind: .propertyMutate, name: property)
            guard let row else { throw MediaError.unsupportedProperty(property) }
            _ = row // presence gates; value shape is asserted in the row tests
        }
        return try engine.get(property)
    }

    public func set(_ property: String, value: MediaValue) throws {
        if let rows = currentRows() {
            let row = rows.row(kind: .propertySet, name: property) ?? rows.row(kind: .propertyMutate, name: property)
            guard let row else { throw MediaError.unsupportedProperty(property) }
            // The set argument is the row's single typed "value:" spec; its token carries
            // the posted domain (number(0.01..100), integer|string(auto|no), ...). The
            // value_type column is the property's looser result type, kept for get/observe.
            let spec = row.arguments.first { $0.name == "value" }
            guard let spec, let type = spec.type, ValueType.argumentType(type, matches: value) else {
                throw MediaError.invalidValueType(property: property, expected: spec?.type ?? row.valueType.raw)
            }
        }
        try engine.set(property, value: value)
    }

    public func observe(_ property: String, token: UInt64, callback: @escaping (MediaValue) -> Void) throws {
        if let rows = currentRows() {
            guard rows.row(kind: .propertyObserve, name: property) != nil else {
                throw MediaError.unsupportedProperty(property)
            }
        }
        try engine.observe(property, token: token, callback: callback)
    }

    public func unobserve(token: UInt64) {
        engine.unobserve(token: token)
    }

    /// Positional binding in declared order: required specs must all be present, optionals
    /// may be appended in order, nothing beyond the declared list; types checked per spec.
    static func check(arguments: [MediaValue], against row: FacadeRow) throws {
        let rendered = row.arguments.map { $0.raw }
        let required = row.arguments.filter { !$0.optional }
        guard arguments.count >= required.count, arguments.count <= row.arguments.count else {
            throw MediaError.invalidArguments(command: row.name, expected: rendered)
        }
        for (value, spec) in zip(arguments, row.arguments) {
            guard let type = spec.type, ValueType.argumentType(type, matches: value) else {
                throw MediaError.invalidArguments(command: row.name, expected: rendered)
            }
        }
    }
}
