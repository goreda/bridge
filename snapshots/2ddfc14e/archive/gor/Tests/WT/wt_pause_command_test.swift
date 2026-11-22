// wt_pause_command_test.swift - semantic gate for the WT sender row.
// The run script (wt_pause_command_run.sh) extracts the real
// wtPauseCommand function out of the product file under test and prepends
// it above this main, so the assertions below always run the shipped code,
// never a copy. Extraction failing means the seam is absent (pre-fix base)
// and the run is RED by construction.
//
// Cases (owner log via Main 2026-11-19: pause reached WT at 17:45:14, the
// resume never did, while the position advanced for 40 minutes):
//   1. resume while the EOF latch is set   -> must be RESUME (was nil: gated)
//   2. resume with a clear latch           -> RESUME
//   3. user pause with a clear latch       -> PAUSE
//   4. automatic keep-open EOF pause       -> nil (still suppressed)

var failures = 0
func check(_ name: String, _ actual: String?, _ expected: String?) {
    if actual == expected {
        print("PASS \(name)")
    } else {
        print("FAIL \(name): expected \(expected ?? "nil"), got \(actual ?? "nil")")
        failures += 1
    }
}

check("resume-while-latched", wtPauseCommand(isPlaying: true, playbackEnded: true), "RESUME")
check("resume-clear-latch", wtPauseCommand(isPlaying: true, playbackEnded: false), "RESUME")
check("user-pause-clear-latch", wtPauseCommand(isPlaying: false, playbackEnded: false), "PAUSE")
check("automatic-eof-pause", wtPauseCommand(isPlaying: false, playbackEnded: true), nil)

if failures > 0 {
    print("RESULT: FAIL \(failures)/4")
} else {
    print("RESULT: PASS 4/4")
}
