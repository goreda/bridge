# W-0261 v2 amendment - pinned race-witness + AudioPacing sources

Added 2026-11-01 05:30 +03 (reviewer, via Main). Scope: minimal packet amendment only; NO full tree public.

## Files

- `race-witness-tests-main.swift` - 50,988 bytes, sha256 667a37dc37eb7598d90267673e369e7194becb977c9d86f838c378626a3d788. Race-witness harness main: RW1-RW12+ arm/check sections (159 `check(...)` assertions), including the 6 known diagnostics sites at lines 597, 603, 606 (TimingLedger/badClock) and 748, 763, 786 (pump.run task seams).
- `AudioPacingTests.swift` - 31,098 bytes, sha256 2ef8056aea209fadc3a5de21378957bd82a82fb6da8eeb564540d3c9af390258. 16 XCTest functions (test01-test15 incl. test09), 121 XCTAssert calls; M1 audio-master pacing qualification on the CURRENT-main surface: real GorAVAudioClock (C core) through the Swift binding, AudioPacingPolicy epoch mapping, real FramePump + AVSyncDecider driven by a synthetic device-consumed counter. Header declares: Linux comp-scope evidence, NOT Mac qualification (AudioUnit render callback is Mac-gated); no guard-v2/ReadyGate types.

## Source pin and identity

- Source pin: coordinator origin/main 2d8f7373 (coordinator-reported). Reviewer fetched goreda/gorav Tests/AudioPacingTests/AudioPacingTests.swift at BOTH 2d8f7373 and the default branch: only a 935-byte stub exists remotely (sha256 8ec2d4aee1c16df6...), NOT the full 31,098-byte file - remote corroboration of Main's report that the full 99ecf081 tree is unpushed. These attachments are the preserved evidence of that unpushed tree.
- Target commit identity 99ecf081 corroborated by the coordinator; the M2 delta never touched these two files (coordinator-reported).
- Reviewer-verified: byte sizes + sha256 above (match Main's transmitted pins exactly); independent secret/user/license/internal-path scan clean (only Swift capability-token domain identifiers; no credentials, user paths, licenses, internal hosts); assertion structure as counted above.

## v2 scope (coordinator request via Main)

- RaceArms2 + main.swift + AudioPacing must cover all known errors with assertions preserved. These two files are the actual pinned counterparts for reviewer W-262 v3 / W-263 v3 candidate review against the existing labs.
- Gates unchanged.

## NOT claimed

- NOT current-ready: after the 05:27-05:29 local resets (coordinator + writer lost unpushed deltas/tree/Swift/FFmpeg; remotes L7/L8 safe; full 99ecf081 / e399471 not on any remote), these files are preserved archived-evidence attachments - historical, then-tree-only.
- The Audio-focused official failure log is still pending from the writer; the Audio failure remains unverified, and full gates are not executable until the restore lands. No fake pass; no dropped commits.
- Actual Audio Mac qualification remains out of scope (Mac-gated render path).
