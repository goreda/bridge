import Foundation

/// Named errors of the facade. "Unsupported names throw, no silent success" (P-B1 exact assert).
public enum MediaError: Error, Equatable, Sendable {
    /// Command name not present in the installed row table / engine vocabulary.
    case unsupportedCommand(String)
    /// Property name not present in the installed row table / engine vocabulary.
    case unsupportedProperty(String)
    /// Property access mode violated (e.g. set on a read-only row).
    case invalidAccess(property: String, access: String)
    /// Argument list does not match the row's argument_types.
    case invalidArguments(command: String, expected: [String])
    /// Value type does not match the row's value_type.
    case invalidValueType(property: String, expected: String)
    /// Wrapped engine failure (scripted error legs included).
    case engineFailure(String)
    /// Malformed row-table input.
    case rowTableMalformed(String)
}

public extension MediaError {
    /// True for the invalidArguments case (test convenience).
    var isInvalidArguments: Bool {
        if case .invalidArguments = self { return true }
        return false
    }
}
