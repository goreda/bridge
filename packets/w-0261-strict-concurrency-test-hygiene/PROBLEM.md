# Strict-concurrency repair: race-witness-tests + AudioPacingTests

## Problem
On the official gorav package tree (pin 99ecf081c3af2ed1e65317814f72e5cda37d4fbf,
branch l3-subtitle-overlay-m2; the failing units are unchanged on main
2d8f7373c332b9c99cbe2002c2af5d4db2cd8ea8), `swift build --build-tests` and
`swift test` FAIL. This blocks any official full-tree test run; current
verification flows work around it with manifest trims, which means the
official tree is never green.

## Evidence
- LOG-VERIFIED: Sources/race-witness-tests/RaceArms2.swift - 20+ Swift 6
  strict-concurrency errors, "mutation of captured var ... in
  concurrently-executing code", lines 231-625 (statsA/statsB/ackA-D/pulled/
  pulledB/barrier/statsC/statsE). Error extract in evidence/.
- VENUE-ASSERTED, NOT log-verified: AudioPacingTests reported as the same
  failure class by the venue that ran the trim; its error output has not been
  captured (build halts at race-witness). Treat as unverified until
  reproduced; reproducing it is part of the task.

## Task
Produce a candidate diff that makes the OFFICIAL tree's
`swift build --build-tests` AND `swift test` pass with NO manifest trim.

Hard constraints:
- Do NOT weaken what the units assert. RaceArms2 is a race-witness harness:
  the arms must still exercise the same concurrent interleavings and detect
  the same races. Moving shared mutable state behind actors/locks/ManagedAtomic
  must preserve the detection semantics and the witness output shape.
- Source-only change; no new dependencies; Swift 6.1 Linux toolchain.
- No changes to the units' public entry points (they are executableTarget /
  testTarget entries in Package.swift).
- If a correct repair requires changing what a test asserts, STOP and report
  why instead of doing it.

## Acceptance
1. Official tree + candidate diff: `swift build --build-tests` EXIT 0.
2. `swift test` EXIT 0, all suites, no trim, no skipped tests.
3. A short note per changed site: what shared state, what isolation chosen,
   why detection semantics are preserved.

## Role
Solver: candidate diff + acceptance evidence. Reviewer (separate lab):
re-run acceptance from the diff alone, check assertion preservation site by
site. Integration stays internal; labs do not merge.
