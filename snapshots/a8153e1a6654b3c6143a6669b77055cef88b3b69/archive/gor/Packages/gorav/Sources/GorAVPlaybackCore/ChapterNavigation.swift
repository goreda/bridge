import Foundation

public enum ChapterDirection: Sendable { case next, previous }
public struct ChapterNavigationEntry: Sendable, Equatable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public init(index: Int, startSeconds: Double, endSeconds: Double) {
        self.index = index; self.startSeconds = startSeconds; self.endSeconds = endSeconds
    }
}
public enum ChapterNavigationRefusal: Error, Sendable, Equatable {
    case unavailable, invalidInventory, unknownPosition, boundary
}
/// Container order is preserved. Ambiguous/nonmonotonic chapter tables refuse,
/// rather than silently sorting, guessing, wrapping or seeking a made-up point.
public enum ChapterNavigation {
    public static func target(entries: [ChapterNavigationEntry], position: Double?,
                              direction: ChapterDirection) throws -> ChapterNavigationEntry {
        guard !entries.isEmpty else { throw ChapterNavigationRefusal.unavailable }
        guard let position, position.isFinite, position >= 0 else { throw ChapterNavigationRefusal.unknownPosition }
        var seen = Set<Int>(); var prior = -Double.infinity
        for entry in entries {
            // seek(toSeconds:) currently converts seconds*1000 to Int64.
            // Admit only targets whose conversion is representable, before that call.
            guard entry.index >= 0, seen.insert(entry.index).inserted,
                  entry.startSeconds.isFinite, entry.endSeconds.isFinite,
                  entry.startSeconds >= 0, entry.endSeconds >= entry.startSeconds,
                  entry.startSeconds > prior,
                  Int64(exactly: (entry.startSeconds * 1000).rounded(.towardZero)) != nil else {
                throw ChapterNavigationRefusal.invalidInventory
            }
            prior = entry.startSeconds
        }
        let current = entries.lastIndex { $0.startSeconds <= position }
        let target: Int
        switch direction {
        case .next: target = current.map { $0 + 1 } ?? 0
        case .previous:
            guard let current else { throw ChapterNavigationRefusal.boundary }
            target = current - 1
        }
        guard entries.indices.contains(target) else { throw ChapterNavigationRefusal.boundary }
        return entries[target]
    }
}
