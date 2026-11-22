public enum ParityError: Error, CustomStringConvertible {
    /// seekTo must be finite; NaN/infinity would corrupt numeric columns.
    case nonFiniteSeekTarget
    /// Stub fixture JSON must define exactly two backends.
    case stubFixtureMustContainTwoBackends(found: Int)
    /// Stub fixture JSON is malformed.
    case stubFixtureInvalid(String)

    public var description: String {
        switch self {
        case .nonFiniteSeekTarget:
            return "seek target must be a finite number"
        case .stubFixtureMustContainTwoBackends(let n):
            return "stub fixture must contain exactly two backends, found \(n)"
        case .stubFixtureInvalid(let why):
            return "stub fixture invalid: \(why)"
        }
    }
}
