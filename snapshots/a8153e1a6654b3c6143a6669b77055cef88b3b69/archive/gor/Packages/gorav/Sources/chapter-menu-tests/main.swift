import Foundation
import GorAVPlaybackCore

// MENU-CAPABILITY-PARITY slice 1: chapter menu step routing semantics.
// Reference expectations are pinned per case; mutants of ChapterMenuStep must
// fail this suite (compiled separately by the packet's linux proof).

var failures = 0
func check(_ id: String, _ cond: Bool, _ detail: String) {
    if cond { print("\(id) PASS \(detail)") } else { failures += 1; print("\(id) FAIL \(detail)") }
}

func run(_ delta: Double?) -> Result<ChapterDirection, ChapterMenuStepRefusal> {
    ChapterMenuStep.direction(forDelta: delta)
}

// C1/C2: the two menu deltas route.
check("C1", (try? run(1).get()) == .next, "add chapter 1 -> next")
check("C2", (try? run(-1).get()) == .previous, "add chapter -1 -> previous")
// C3: missing argument refuses loudly.
check("C3", run(nil) == .failure(.missingDelta), "no delta -> missingDelta")
// C4: zero is not a navigation.
check("C4", run(0) == .failure(.zero), "add chapter 0 -> zero refusal")
// C5/C6: skips beyond one refuse, no silent clamp.
check("C5", run(2) == .failure(.skipBeyondOne), "add chapter 2 -> skipBeyondOne")
check("C6", run(-3) == .failure(.skipBeyondOne), "add chapter -3 -> skipBeyondOne")
// C7: fractional deltas refuse, no floor/round into a fake step.
check("C7", run(1.5) == .failure(.nonInteger), "add chapter 1.5 -> nonInteger")
// C8/C9: non-finite deltas refuse.
check("C8", run(.nan) == .failure(.nonFinite), "add chapter NaN -> nonFinite")
check("C9", run(.infinity) == .failure(.nonFinite), "add chapter inf -> nonFinite")
// C10: tokens are non-empty and distinct per refusal (visible, not generic).
let tokens: [ChapterMenuStepRefusal] = [.missingDelta, .nonFinite, .nonInteger, .zero, .skipBeyondOne]
check("C10", Set(tokens.map { $0.token }).count == tokens.count && tokens.allSatisfy { !$0.token.isEmpty },
      "every refusal has its own non-empty token")

// C11-C14: the routed direction drives the real ChapterNavigation target, so a
// menu step at a table boundary refuses instead of wrapping (mpv wraps).
let entries = [
    ChapterNavigationEntry(index: 0, startSeconds: 0, endSeconds: 60),
    ChapterNavigationEntry(index: 1, startSeconds: 60, endSeconds: 120),
    ChapterNavigationEntry(index: 2, startSeconds: 120, endSeconds: 180),
]
// mid-film next lands on the next chapter start.
if case .success(let dir) = run(1) {
    do {
        let target = try ChapterNavigation.target(entries: entries, position: 65, direction: dir)
        check("C11", target.index == 2, "position 65 + next -> chapter index 2")
    } catch { check("C11", false, "unexpected throw \(error)") }
} else { check("C11", false, "run(1) refused") }
// previous from inside the first chapter refuses at the boundary (no wrap to last).
if case .success(let dir) = run(-1) {
    do {
        _ = try ChapterNavigation.target(entries: entries, position: 30, direction: dir)
        check("C12", false, "expected boundary refusal")
    } catch let e as ChapterNavigationRefusal {
        check("C12", e == .boundary, "position 30 + previous -> boundary")
    } catch { check("C12", false, "unexpected error \(error)") }
} else { check("C12", false, "run(-1) refused") }
// next from the last chapter refuses at the boundary.
if case .success(let dir) = run(1) {
    do {
        _ = try ChapterNavigation.target(entries: entries, position: 150, direction: dir)
        check("C13", false, "expected boundary refusal")
    } catch let e as ChapterNavigationRefusal {
        check("C13", e == .boundary, "position 150 + next -> boundary")
    } catch { check("C13", false, "unexpected error \(error)") }
} else { check("C13", false, "run(1) refused") }
// previous across a chapter start lands on the previous chapter.
if case .success(let dir) = run(-1) {
    do {
        let target = try ChapterNavigation.target(entries: entries, position: 119, direction: dir)
        check("C14", target.index == 0, "position 119 + previous -> chapter index 0")
    } catch { check("C14", false, "unexpected throw \(error)") }
} else { check("C14", false, "run(-1) refused") }

print(failures == 0 ? "chapter-menu-tests PASS (14/14)" : "chapter-menu-tests FAIL (\(failures) failed)")
exit(failures == 0 ? 0 : 1)
