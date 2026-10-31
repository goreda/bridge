// Q4 decided-rule venue tests (Linux, Swift 5.10.1): compile WITH
// SubtitleCueSelection.swift; this file must be named main.swift.
// Recipe: swiftc SubtitleCueSelection.swift main.swift -o q4tests && ./q4tests
// Expected: 9 lines "PASS <name>", then "ALL PASS 9/9", exit 0. Any mismatch: FAIL line, exit 1.
import Foundation

var pass = 0, fail = 0
func check(_ name: String, _ got: SubtitleCueSelection, active: Int?, suppressed: [Int]) {
    if got.activeIndex == active && got.suppressedIndices == suppressed {
        pass += 1; print("PASS \(name)")
    } else {
        fail += 1
        print("FAIL \(name): got active=\(String(describing: got.activeIndex)) suppressed=\(got.suppressedIndices), want active=\(String(describing: active)) suppressed=\(suppressed)")
    }
}
let R = SubtitleCueSelectionRule.self

// 1. no cue covers t
check("no-active", R.select(at: 5.0, cues: [CueInterval(index: 0, startSeconds: 0, endSeconds: 2)]), active: nil, suppressed: [])
// 2. exactly one active
check("single", R.select(at: 1.0, cues: [CueInterval(index: 0, startSeconds: 0, endSeconds: 2), CueInterval(index: 1, startSeconds: 5, endSeconds: 7)]), active: 0, suppressed: [])
// 3. two overlapping: latest-starting wins, other suppressed
check("overlap-2", R.select(at: 1.5, cues: [CueInterval(index: 0, startSeconds: 0, endSeconds: 4), CueInterval(index: 1, startSeconds: 1, endSeconds: 3)]), active: 1, suppressed: [0])
// 4. three overlapping: latest-starting wins, suppressed ascending
check("overlap-3", R.select(at: 2.5, cues: [CueInterval(index: 0, startSeconds: 0, endSeconds: 5), CueInterval(index: 2, startSeconds: 2, endSeconds: 4), CueInterval(index: 1, startSeconds: 1, endSeconds: 6)]), active: 2, suppressed: [0, 1])
// 5. equal start tie: earliest index wins
check("tie-earliest-index", R.select(at: 1.0, cues: [CueInterval(index: 7, startSeconds: 0, endSeconds: 3), CueInterval(index: 3, startSeconds: 0, endSeconds: 3)]), active: 3, suppressed: [7])
// 6. half-open: t == end is NOT active; t == start IS active
check("half-open-end", R.select(at: 2.0, cues: [CueInterval(index: 0, startSeconds: 0, endSeconds: 2)]), active: nil, suppressed: [])
check("half-open-start", R.select(at: 0.0, cues: [CueInterval(index: 0, startSeconds: 0, endSeconds: 2)]), active: 0, suppressed: [])
// 7. input order independence (reversed input, same result as overlap-3)
check("order-independent", R.select(at: 2.5, cues: [CueInterval(index: 1, startSeconds: 1, endSeconds: 6), CueInterval(index: 2, startSeconds: 2, endSeconds: 4), CueInterval(index: 0, startSeconds: 0, endSeconds: 5)]), active: 2, suppressed: [0, 1])
// 8. empty cue list
check("empty", R.select(at: 1.0, cues: []), active: nil, suppressed: [])

print(fail == 0 ? "ALL PASS \(pass)/9" : "FAILURES \(fail)/9")
exit(fail == 0 ? 0 : 1)
