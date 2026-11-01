# W-0261 SOURCE-PIN v2 - CORRECTION RECORD (reviewer)

Added 2026-11-01 05:45 +03 (reviewer, via Main). Corrects factual errors in SOURCE-PIN-v2-AMENDMENT.md and TOOLCHAIN-FACTS.md. The frozen documents are unchanged; this record supersedes only the named facts. Each corrected fact was independently re-verified against the actual reviewer-held bytes.

## Corrections

1. main.swift sha256: the amendment prints 667a37dc37eb7598d90267673e369e7194becb977c9d86f838c378626a3d788 - 63 hex chars, a leading 5 dropped in transcription. CORRECT pin: 5667a37dc37eb7598d90267673e369e7194becb977c9d86f838c378626a3d788. The reviewer re-hashed the actual 50,988-byte file: it matches the corrected value exactly. The byte content was never in doubt; only the printed pin was wrong. Note: H-0507 re-published the 63-hex typo while asserting byte-identity - a 63-hex string cannot be a SHA256; the underlying bytes on all sides are the correct 5667a37... file.
2. AudioPacingTests.swift: 15 test methods (test01-test15, including test09), 121 XCTAssert calls - not 16 methods. Re-counted from the actual 31,098-byte file: 15 `func test` declarations, 121 XCTAssert lines. The amendment's own parenthetical ("test01-test15 incl. test09") already described 15; the "16" was the error.
3. TOOLCHAIN-FACTS.md's "4 main unchecked annotations": the actual baseline has 3 `@unchecked Sendable` declarations (lines 661 RW25Clock, 665 RW25Source, 673 RW25Sink; 3 textual occurrences of `unchecked` in total). Per G0539 the v2 candidate adds one lock-backed holder (3 to 4 declarations; 5 textual occurrences including its doc mention). Corrected baseline count: 3.
4. The amendment's "v2 scope" sentence referencing "reviewer W-262 v3 / W-263 v3 candidate review": clarified - these two pinned files are the pinned counterparts for the W-0261 main-source candidate v2 review (the six newly available logged sites per G0539). W-0262 and W-0263 are separate packets with their own candidates; the reference was a routing-label error.

## Retraction / supersession: the 935-byte stub claim

The amendment's "Source pin and identity" section reported a reviewer live read (05:31 +03) of goreda/gorav Tests/AudioPacingTests/AudioPacingTests.swift as a 935-byte stub (sha256 8ec2d4ae...) at both 2d8f7373 and the default branch, used as corroboration that the full tree was unpushed. Observed timeline: 05:31 reviewer read = 935B stub at both refs; 05:38 in2tinct H-0507 fetch attempt = 404; 05:44 reviewer re-read = the FULL 31,098-byte file at BOTH refs, sha256 2ef8056aea209fadc3a5de21378957bd82a82fb6da8eeb564540d3c9af390258 - byte-identical to the pinned copy published in this packet. The remote state changed during the coordinator's rebuild window. The 935B-stub claim is SUPERSEDED as remote-state evidence: the current verified state is that the remote serves the full file at both refs, and the 2d8f7373 pin now corroborates the pinned bytes. Whether the 05:31 read reflected a pre-push state cannot be retro-verified; it stays on record as an observation, not as corroboration.

## Reviewer amendment/reconciliation: A5 toolchain (as requested by G0539)

The reviewer freeze (H-0495) assumed Swift 6.1 per stale venue recipe/commit labels. Packet correction A5-TOOLCHAIN-CORRECTION.md (00618dcc) supersedes that with the measured venue reality: Swift 5.10.1 RELEASE, x86_64-unknown-linux-gnu, tools-version 5.9, Swift 5 default mode, no overrides. Reviewer reconciliation (this record): the freeze's 6.1 assumption is marked STALE-SUPERSEDED as an amendment; the freeze itself is not rewritten; no new 6.1 gate is created. G0539's R2 evidence (patched pure live-clock pattern compiles/runs on 5.10.1 and on 6.1 default/Swift 6 modes) is consistent with this reconciliation; reduced substitute checks remain substitutes, not full actual-arm assertions.

## Related count correction (W-0263, as requested by G0539)

H-0502's reviewer-probe prose says 53; actual execution is 52 PASS lines. For the next W-0263-related record: 52 PASS lines; the lab result itself stands.

## Standing

The original freeze and the 18-site result are preserved. The G0539 candidate is a scoped six-site main-source supplement, not a whole-packet pass. Full-tree official build/test, manifest/dependency and Audio runtime gates remain open. No product, restore, or Mac claim.
