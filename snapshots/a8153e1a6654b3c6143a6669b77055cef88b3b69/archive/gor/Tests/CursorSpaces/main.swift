import Foundation

enum PPController {
    enum CursorHideDecision { case hide, show, keep }

    /// Pure hide/show decision, extracted for platform-independent testing.
    /// Hide only while the pointer rests over a usable (visible, active-Space)
    /// player window; every other state shows a hidden cursor exactly once.
    static func cursorHideDecision(dialogOpen: Bool,
                                   windowUsable: Bool,
                                   mouseInWindow: Bool,
                                   timeSinceLastMove: TimeInterval,
                                   hidden: Bool) -> CursorHideDecision {
        guard !dialogOpen, windowUsable, mouseInWindow else {
            return hidden ? .show : .keep
        }
        if timeSinceLastMove > 1.5, !hidden { return .hide }
        if timeSinceLastMove <= 1.5, hidden { return .show }
        return .keep
    }
}


var checks = 0, fails = 0
func ck(_ b: Bool, _ s: String) { checks += 1; if !b { fails += 1; print("FAIL \(s)") } }
func d(_ dialog: Bool, _ usable: Bool, _ inside: Bool, _ t: TimeInterval, _ h: Bool) -> PPController.CursorHideDecision {
    PPController.cursorHideDecision(dialogOpen: dialog, windowUsable: usable, mouseInWindow: inside, timeSinceLastMove: t, hidden: h)
}
ck(d(false,false,true,10,false) == .keep, "off-Space idle pointer in frame must not hide")
ck(d(false,false,true,10,true) == .show, "off-Space unhides")
ck(d(false,true,true,10,false) == .hide, "active Space idle hides")
ck(d(false,true,true,0.2,true) == .show, "mouse move unhides")
ck(d(false,true,false,10,true) == .show, "outside frame unhides")
ck(d(false,true,true,10,true) == .keep, "hide balanced once")
ck(d(false,true,true,1.5,false) == .keep, "1.5s boundary keeps")
ck(d(false,true,true,1.500001,false) == .hide, "past 1.5s hides")
ck(d(true,true,true,10,true) == .show, "dialog unhides")
ck(d(true,true,true,10,false) == .keep, "dialog never hides")
print("\(checks) checks, \(fails) failures")
if fails > 0 { throw NSError(domain: "cursor-test", code: 1) }
print("PASS actual Swift decision block")
