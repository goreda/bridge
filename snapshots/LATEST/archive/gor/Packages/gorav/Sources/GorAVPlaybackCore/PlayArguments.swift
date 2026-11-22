import Foundation

/// Backward-compatible positional gorav-play grammar. Includes argv[0].
public struct PlayArguments: Sendable, Equatable {
    public let path: String
    public let holdSeconds: Double
    public let seekAtSeconds: Double?
    public let seekTargetSeconds: Double?
    public let pauseAtSeconds: Double?
    public let resumeAtSeconds: Double?
    public let closeAtSeconds: Double?
    public enum Invalid: Error { case usage, number, pair, order }
    public init(_ argv: [String]) throws {
        guard (2...8).contains(argv.count), !argv[1].isEmpty else { throw Invalid.usage }
        var numbers: [Double] = []
        for text in argv.dropFirst(2) {
            guard let v = Double(text), v.isFinite, v < Double(UInt64.max) / 1e9, v > -Double(UInt64.max) / 1e9 else { throw Invalid.number }
            numbers.append(v)
        }
        path = argv[1]
        holdSeconds = numbers.first ?? 4
        guard holdSeconds >= 0 else { throw Invalid.number }
        func pair(_ a: Int, _ b: Int) throws -> (Double?, Double?) {
            guard numbers.count > a else { return (nil, nil) }
            guard numbers.count > b else { throw Invalid.pair }
            let x = numbers[a], y = numbers[b]
            if x < 0 && y < 0 { return (nil, nil) }
            guard x >= 0 && y >= 0 else { throw Invalid.pair }
            return (x, y)
        }
        (seekAtSeconds, seekTargetSeconds) = try pair(1, 2)
        (pauseAtSeconds, resumeAtSeconds) = try pair(3, 4)
        if let p = pauseAtSeconds, let r = resumeAtSeconds, r <= p { throw Invalid.order }
        closeAtSeconds = numbers.count > 5 && numbers[5] >= 0 ? numbers[5] : nil
    }
}

/// Shared combined acceptance predicate: video commit alone is insufficient.
public enum PlaySeekAcceptance {
    public static func accepts(attempted: Bool, video: String, audio: String) -> Bool {
        !attempted || (video == "committedAndReset" && audio == "nativeReady")
    }
}
