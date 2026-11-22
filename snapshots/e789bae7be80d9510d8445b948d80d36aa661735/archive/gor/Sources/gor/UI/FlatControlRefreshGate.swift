// Timer-only equality gate. The caller records the state after the original
// refresh returns. Direct layout, mode and pose publishers do not use this gate.
struct FlatControlRefreshGate<Key: Equatable> {
    private var applied: Key?
    func needsRefresh(_ current: Key) -> Bool { applied != current }
    mutating func recordApplied(_ current: Key) { applied = current }
    mutating func invalidate() { applied = nil }
}
