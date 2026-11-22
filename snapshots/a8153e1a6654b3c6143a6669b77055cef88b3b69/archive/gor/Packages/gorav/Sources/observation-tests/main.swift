// G4 (arch-195l, dispatch L6) observation-surface tests. Pure Swift, Linux.
import Foundation
import GorAVPlaybackCore

var pass = 0, fail = 0
func check(_ cond: Bool, _ name: String) {
    if cond { pass += 1; print("PASS \(name)") }
    else { fail += 1; print("FAIL \(name)") }
}

// O1: an unpublished property reads .none (mpv unavailable).
let s = ObservationStore()
check(s.read(.duration) == .none, "O1 unpublished property reads none")

// O2-O4: publish fires the observer once with old/new.
var fired: [ObservationChange] = []
let tok = s.observe(.pause) { fired.append($0) }
check(s.publish(.pause, .bool(true)), "O2 publish reports changed")
check(fired.count == 1, "O3 observer fired exactly once")
check(fired.first == ObservationChange(property: .pause, old: .none, new: .bool(true)),
      "O4 change carries old none -> new true")

// O5-O6: same-value publish dedups: no fire, counted as skip.
check(!s.publish(.pause, .bool(true)), "O5 same-value publish reports unchanged")
check(fired.count == 1 && s.counters.dedupSkips == 1, "O6 dedup skip counted, no second fire")

// O7: read returns the last published value.
check(s.read(.pause) == .bool(true), "O7 read returns last value")

// O8-O9: two observers on one property both fire, in registration set.
var a = 0, b = 0
let tokA = s.observe(.timePos) { _ in a += 1 }
let tokB = s.observe(.timePos) { _ in b += 1 }
_ = s.publish(.timePos, .double(12.5))
check(a == 1 && b == 1, "O8 both observers fire")
check(s.counters.notifications == 3, "O9 notifications counted per handler")

// O10: an observer on a DIFFERENT property does not fire.
var wrong = 0
let tokW = s.observe(.mediaTitle) { _ in wrong += 1 }
_ = s.publish(.timePos, .double(13.0))
check(wrong == 0, "O10 other-property observer not fired")

// O11-O12: explicit cancel unsubscribes; cancel is idempotent. Live
// observers at this point: tok (pause), tokA, tokB (timePos), tokW
// (mediaTitle); the O10 publish already advanced a and b to 2 each.
tokA.cancel()
_ = s.publish(.timePos, .double(14.0))
check(a == 2 && b == 3, "O11 cancelled observer stops, other continues")
tokA.cancel()
check(s.observerCount == 3, "O12 cancel idempotent, three observers left (tok, tokB, tokW)")

// O13: token deinit unsubscribes (a temporary token dies with its scope).
do {
    let temp = s.observe(.duration) { _ in }
    _ = temp
}
check(s.observerCount == 3, "O13 token deinit unsubscribes")

// O14: metadata as a string dictionary round-trips.
_ = s.publish(.metadata, .stringDict(["title": "clip", "encoder": "lavf"]))
check(s.read(.metadata) == .stringDict(["title": "clip", "encoder": "lavf"]),
      "O14 metadata stringDict round-trips")

// O15: every PLAN line-43 property is distinct and registered.
check(ObservationProperty.allCases.count == Set(ObservationProperty.allCases).count
      && ObservationProperty.allCases.count == 17,
      "O15 17 distinct properties")

// O16: mpv names preserved for the script-observed core set.
check(ObservationProperty.timePos.rawValue == "time-pos"
      && ObservationProperty.idleActive.rawValue == "idle-active"
      && ObservationProperty.hwdecCurrent.rawValue == "hwdec-current"
      && ObservationProperty.frameDropCount.rawValue == "frame-drop-count",
      "O16 raw values equal mpv property names")

// O17: handler may re-enter the store (read) without deadlock.
var reentered = false
let tokR = s.observe(.width) { ch in
    if ch.new == .int(1920) { reentered = (s.read(.width) == .int(1920)) }
}
_ = s.publish(.width, .int(1920))
check(reentered, "O17 handler re-entrant read safe")

// O18: counters add up: publishes = changed + dedupSkips.
check(s.counters.publishes == s.counters.changed + s.counters.dedupSkips,
      "O18 publishes == changed + dedupSkips")

// O19: no initial replay on registration.
var replay = 0
let tokN = s.observe(.pause) { _ in replay += 1 }
check(replay == 0, "O19 no replay on registration")
_ = tokN; _ = tok; _ = tokB; _ = tokW; _ = tokR

// O20: publishing .none (unavailable transition) is a real change.
var noneFired = false
let tokE = s.observe(.duration) { ch in if ch.new == .none { noneFired = true } }
_ = s.publish(.duration, .double(241.2))
_ = s.publish(.duration, .none)
check(noneFired, "O20 transition back to none notifies")
_ = tokE

print("observation-tests: \(pass) PASS, \(fail) FAIL")
exit(fail == 0 ? 0 : 1)
