/// Per-row comparison status. `error` carries a sanitized detail string so
/// failures are explicit inside the fixed eight-column TSV shape.
public enum ParityStatus: Equatable, Sendable {
    /// Both backends measured every field and all values are exactly equal.
    case pass
    /// Both backends measured every field and at least one value differs.
    case different
    /// A measured value is missing on either side, or the peer backend
    /// failed, so parity could not be assessed. Never a pass.
    case unavailable
    /// This backend threw; the detail is TSV-sanitized.
    case error(String)

    public var token: String {
        switch self {
        case .pass: return "pass"
        case .different: return "different"
        case .unavailable: return "unavailable"
        case .error(let detail): return "error(" + TSVEscape.sanitize(detail) + ")"
        }
    }
}
