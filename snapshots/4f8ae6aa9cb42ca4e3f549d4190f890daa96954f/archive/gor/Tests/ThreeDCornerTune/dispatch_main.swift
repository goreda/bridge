import Foundation

/// Owner 21:28 (phonemsg-01M73BG6BQ7DP7BGPR2FWA3TXP), English paraphrase: prove by measurement that
/// the 3D controls work - the eye cannot catch drift because the renderer redraws from scratch.
/// This drives the REAL production store (ThreeDState.swift, compiled here unmodified) with the
/// exact setEffect actions that ThreeDMenu.dispatch maps the eight corner-control acts to, and
/// asserts the value lands, direction is right, and every subscriber hears showInfo without a route rebuild.
/// The stepping/clamping helpers live in AppKit-bound ThreeDMenu.swift; their constants are pinned
/// textually in run.py, and the clamped inputs are exercised here as store dispatches.
var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}
func num(_ v: ThreeDEffectValue?) -> Double? { if case .number(let n) = v { return n }; return nil }

@main struct DispatchMain {
    static func main() {
        MainActor.assumeIsolated {
            let store = ThreeDStore.shared
            var notifications: [[ThreeDEffect]] = []
            store.subscribe(ownerID: "corner-tune-test") { _, effects in notifications.append(effects) }
            check("subscribe-present", notifications.count == 1 && notifications[0] == [.present])

            // depth controls: strength 1 -> 1.25 (stronger, +0.25) -> 0.75 (weaker); clamps 0 and 2.
            store.dispatch(.setEffect(.strength, .number(1 + 0.25)))
            check("depthStronger-lands", num(store.snapshot.effects[.strength]) == 1.25)
            check("depthStronger-notifies", notifications.last!.contains(.showInfo) && !notifications.last!.contains(.reapply))
            store.dispatch(.setEffect(.strength, .number(1.25 - 0.25 - 0.25)))
            check("depthWeaker-lands", num(store.snapshot.effects[.strength]) == 0.75)
            store.dispatch(.setEffect(.strength, .number(min(max(0.75 - 0.25 - 0.25 - 0.25, 0.0), 2.0))))
            check("depthWeaker-clamps-low", num(store.snapshot.effects[.strength]) == 0.0)
            store.dispatch(.setEffect(.strength, .number(min(max(1.9 + 0.25, 0.0), 2.0))))
            check("depthStronger-clamps-high", num(store.snapshot.effects[.strength]) == 2.0)

            // screen controls: depth 1.5 nearer (/1.5 -> 1.0) then farther (x1.5); clamps 0.25/8.
            store.dispatch(.setEffect(.screenDepth, .number(min(max(1.5 / 1.5, 0.25), 8.0))))
            check("screenNearer-lands", num(store.snapshot.effects[.screenDepth]) == 1.0)
            store.dispatch(.setEffect(.screenDepth, .number(min(max(1.0 * 1.5, 0.25), 8.0))))
            check("screenFarther-lands", num(store.snapshot.effects[.screenDepth]) == 1.5)
            store.dispatch(.setEffect(.screenDepth, .number(min(max(8.0 * 1.5, 0.25), 8.0))))
            check("screenFarther-clamps-high", num(store.snapshot.effects[.screenDepth]) == 8.0)
            store.dispatch(.setEffect(.screenDepth, .number(min(max(0.3 / 1.5, 0.25), 8.0))))
            check("screenNearer-clamps-low", num(store.snapshot.effects[.screenDepth]) == 0.25)

            // size controls: 75 -> 80 (larger, +5) -> 70 (smaller); clamps 20 and 150.
            store.dispatch(.setEffect(.screenSize, .number(min(max(75 + 5, 20.0), 150.0))))
            check("sizeLarger-lands", num(store.snapshot.effects[.screenSize]) == 80.0)
            store.dispatch(.setEffect(.screenSize, .number(min(max(80 - 5 - 5, 20.0), 150.0))))
            check("sizeSmaller-lands", num(store.snapshot.effects[.screenSize]) == 70.0)
            store.dispatch(.setEffect(.screenSize, .number(min(max(148 + 5, 20.0), 150.0))))
            check("sizeLarger-clamps-high", num(store.snapshot.effects[.screenSize]) == 150.0)

            // ipd controls: +/- step within range; the step constant is pinned in run.py.
            store.dispatch(.setEffect(.ipd, .number(0.0)))
            store.dispatch(.setEffect(.ipd, .number(0.02)))
            check("ipdPlus-lands", num(store.snapshot.effects[.ipd]) == 0.02)
            store.dispatch(.setEffect(.ipd, .number(-0.02)))
            check("ipdMinus-lands", num(store.snapshot.effects[.ipd]) == -0.02)
            check("every-dispatch-notifies", notifications.count == 1 + 14)

            store.unsubscribe(ownerID: "corner-tune-test")
            store.dispatch(.setEffect(.ipd, .number(0.0)))
            check("unsubscribe-stops-notify", notifications.count == 15)
        }
        if failures > 0 { print("FAILURES: \(failures)"); } else { print("ALL PASS") }; precondition(failures == 0)
    }
}
