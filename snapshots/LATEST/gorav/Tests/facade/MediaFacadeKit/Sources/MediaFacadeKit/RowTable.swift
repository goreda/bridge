import Foundation

/// One row of the approved E1 TSV (facade-rows.tsv), columns exactly as posted by the
/// integrator at goreda/bridge 0fe957bed27c486a58b19f5515cce7d662cabae5 (INBOX-IN2TINCT.md):
/// kind, name, access, argument_types, value_type, e_step (header spelled lowercase e_step
/// in the posted bytes; the packet prose said E_step - the posted bytes govern).
public struct FacadeRow: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case command
        case propertyGet = "property-get"
        case propertySet = "property-set"
        case propertyMutate = "property-mutate"
        case propertyObserve = "property-observe"
    }
    public enum Access: String, Equatable, Sendable {
        case execute
        case read
        case write
        case readWrite = "read-write"
        case observe
    }

    public let kind: Kind
    public let name: String
    public let access: Access
    public let arguments: [ArgumentSpec]
    public let valueType: ValueType
    public let eStep: String

    /// The kind/access pairings present in the approved rows; anything else is malformed.
    public static func accessMatches(kind: Kind, access: Access) -> Bool {
        switch (kind, access) {
        case (.command, .execute), (.propertyGet, .read), (.propertySet, .write),
             (.propertyMutate, .readWrite), (.propertyObserve, .observe):
            return true
        default:
            return false
        }
    }
}

/// One entry of an argument_types cell: "name:type" (required), "name?:type" (optional),
/// or a bare descriptive token like "callback(value)" as posted on property-observe rows
/// (kept verbatim in raw; type is nil for untyped descriptive entries).
public struct ArgumentSpec: Equatable, Sendable {
    public let name: String
    public let type: String?
    public let optional: Bool
    public let raw: String
}

/// A value_type cell, kept verbatim plus a matcher onto MediaValue. The descriptive
/// forms in the approved rows: "command-result-or-error", "boolean",
/// "number(...)" (optionally "-or-unavailable"), "integer|string(...)",
/// "array(object)-or-unavailable", "boolean-or-unavailable".
public struct ValueType: Equatable, Sendable {
    public let raw: String
    /// When the cell ends in "-or-unavailable", .none is an admitted value.
    public let allowsUnavailable: Bool

    public init(raw: String) {
        self.raw = raw
        self.allowsUnavailable = raw.hasSuffix("-or-unavailable")
    }

    public func matches(_ value: MediaValue) -> Bool {
        if value == .none { return allowsUnavailable || raw == "command-result-or-error" }
        let base = allowsUnavailable ? String(raw.dropLast("-or-unavailable".count)) : raw
        if base == "command-result-or-error" { return true } // any result value; errors travel as throws
        if base == "boolean" { if case .bool = value { return true }; return false }
        if base.hasPrefix("number") { if case .number = value { return true }; return false }
        if base.hasPrefix("integer|string") {
            switch value { case .number, .text: return true; default: return false }
        }
        if base == "array(object)" {
            guard case .list(let items) = value else { return false }
            return items.allSatisfy { if case .object = $0 { return true } else { return false } }
        }
        return false
    }

    /// Maps an argument spec type token onto MediaValue cases, honoring the explicit
    /// ("uint64" appears only in property-observe "token:uint64" specs, which bind through
    /// the observe(token:) API as a real UInt64, never through MediaValue - so there is
    /// deliberately no uint64 case here, and it is not claimed tested.)
    ///
    /// domains the posted rows encode in the token itself:
    /// - "number(<lo>..<hi>)": explicit numeric bounds (speed 0.01..100) - enforced.
    /// - "number(<word>)" (percent, seconds): a unit annotation, not bounds - no range
    ///   is invented; only the numeric type is enforced (documented in README).
    /// - "integer|string(<a>|<b>|...)": .number, or .text equal to one of the listed
    ///   alternatives (sid/audio/sub: auto|no) - the enum is enforced.
    /// Plain "number" tokens are type-only: NaN/infinity pass, because the posted
    /// contract says nothing about finiteness for unconstrained numbers (labeled in
    /// README as unspecified, engine-level policy). Anything else about a value's
    /// domain is engine-level policy, not facade typing.
    public static func argumentType(_ token: String, matches value: MediaValue) -> Bool {
        switch token {
        case "string": if case .text = value { return true }; return false
        case "number": if case .number = value { return true }; return false
        case "integer":
            // Integer means finite and integral: 1.5, NaN and infinity are not integers.
            guard case .number(let d) = value, d.isFinite, d.rounded() == d else { return false }
            return true
        case "boolean": if case .bool = value { return true }; return false
        case "object": if case .object = value { return true }; return false
        default: break
        }
        if token.hasPrefix("number(") && token.hasSuffix(")") {
            guard case .number(let d) = value else { return false }
            let inner = String(token.dropFirst("number(".count).dropLast())
            let parts = inner.components(separatedBy: "..")
            if parts.count == 2, let lo = Double(parts[0]), let hi = Double(parts[1]) {
                return d >= lo && d <= hi // explicit posted bounds
            }
            // (A NaN or infinity fails the range comparisons above, so ranged tokens
            // reject non-finite values implicitly.)
            return true // unit annotation (percent, seconds): type only, no invented bounds
        }
        if token.hasPrefix("integer|string(") && token.hasSuffix(")") {
            if case .number(let d) = value { return d.isFinite && d.rounded() == d }
            guard case .text(let t) = value else { return false }
            let inner = String(token.dropFirst("integer|string(".count).dropLast())
            return inner.components(separatedBy: "|").contains(t)
        }
        return false
    }
}

/// Parsed facade-rows.tsv. Tabs separate the six columns; argument_types holds
/// ';'-separated specs ("none" means empty). CRLF is normalized before splitting
/// (a Swift "\r\n" is one Character; splitting raw input on "\n" glued lines).
public struct RowTable: Equatable, Sendable {
    public let rows: [FacadeRow]

    public init(rows: [FacadeRow]) { self.rows = rows }

    public static let header = "kind\tname\taccess\targument_types\tvalue_type\te_step"

    public static func parse(tsv: String) throws -> RowTable {
        let normalized = tsv.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var parsed: [FacadeRow] = []
        var seenKeys: Set<String> = []
        var seenHeader = false
        for (index, rawLine) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(rawLine)
            if line.isEmpty { continue }
            if !seenHeader {
                guard line == header else { throw MediaError.rowTableMalformed("line \(index + 1): expected header '\(header)', got '\(line)'") }
                seenHeader = true
                continue
            }
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count == 6 else { throw MediaError.rowTableMalformed("line \(index + 1): expected 6 tab-separated columns, got \(cols.count)") }
            guard let kind = FacadeRow.Kind(rawValue: cols[0]) else { throw MediaError.rowTableMalformed("line \(index + 1): unknown kind '\(cols[0])'") }
            guard let access = FacadeRow.Access(rawValue: cols[2]) else { throw MediaError.rowTableMalformed("line \(index + 1): unknown access '\(cols[2])'") }
            guard FacadeRow.accessMatches(kind: kind, access: access) else { throw MediaError.rowTableMalformed("line \(index + 1): kind '\(cols[0])' paired with wrong access '\(cols[2])'") }
            let args = try parseArguments(cell: cols[3], line: index + 1, kind: kind)
            // property-set / property-mutate rows bind exactly one typed "value:" argument;
            // its type token carries the posted domain the facade enforces on set.
            if kind == .propertySet || kind == .propertyMutate {
                guard args.count == 1, args[0].name == "value", args[0].type != nil, !args[0].optional else {
                    throw MediaError.rowTableMalformed("line \(index + 1): \(kind.rawValue) row '\(cols[1])' needs exactly one typed required 'value:' argument spec")
                }
            }
            let key = "\(kind.rawValue)\u{1F}\(cols[1])"
            guard seenKeys.insert(key).inserted else {
                throw MediaError.rowTableMalformed("line \(index + 1): duplicate (kind,name) row '\(cols[0])\t\(cols[1])'")
            }
            parsed.append(FacadeRow(kind: kind, name: cols[1], access: access, arguments: args, valueType: ValueType(raw: cols[4]), eStep: cols[5]))
        }
        guard seenHeader else { throw MediaError.rowTableMalformed("missing header row") }
        return RowTable(rows: parsed)
    }

    static func parseArguments(cell: String, line: Int, kind: FacadeRow.Kind) throws -> [ArgumentSpec] {
        if cell == "none" || cell.isEmpty { return [] }
        return try cell.split(separator: ";", omittingEmptySubsequences: false).map { rawToken in
            let spec = String(rawToken)
            let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 1 {
                // Bare descriptive token (e.g. "callback(value)"). Command rows carry the
                // packet's typed-arguments assert, so their specs must all be typed.
                if kind == .command {
                    throw MediaError.rowTableMalformed("line \(line): untyped argument spec '\(spec)' on a command row")
                }
                return ArgumentSpec(name: spec, type: nil, optional: false, raw: spec)
            }
            guard !parts[0].isEmpty, !parts[1].isEmpty else {
                throw MediaError.rowTableMalformed("line \(line): bad argument spec '\(spec)'")
            }
            let optional = parts[0].hasSuffix("?")
            let name = optional ? String(parts[0].dropLast()) : parts[0]
            return ArgumentSpec(name: name, type: parts[1], optional: optional, raw: spec)
        }
    }

    public func row(kind: FacadeRow.Kind, name: String) -> FacadeRow? {
        rows.first { $0.kind == kind && $0.name == name }
    }
}
