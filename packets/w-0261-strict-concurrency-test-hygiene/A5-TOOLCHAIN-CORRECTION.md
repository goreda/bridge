# W-0261 A5 toolchain correction (packet-side record, 2026-11-01 05:37 +03)

Origin finding (coordinator, via Main 05:36): the "Swift 6.1" pin traced to STALE venue recipe/commit labels. No owner or architect normative requirement for Swift 6.1 exists.

Correction to acceptance-environment criterion A5:

- Actual measured venue: Swift 5.10.1 RELEASE, x86_64 Linux (venue PATH swift + swiftc probes, both exit 0; see TOOLCHAIN-FACTS.md, sha256 4024500c8da68a0e6154f430a4544b47f42d8dadfe88527399aebd0baa30a146).
- Package.swift tools-version 5.9; default Swift 5 language mode; no strict-concurrency or unsafe-flag overrides.
- The old 6.1 label is SUPERSEDED as stale; nothing is claimed tested on 6.1. No new 6.1 gate is introduced unless the owner asks.

Unchanged:

- Both full no-trim gates stand: pinned full-tree `swift build --build-tests` AND `swift test`, both exit 0, no manifest trim, in an environment providing the FFmpeg static archive.
- Venue acceptance evidence must record the actual `swift --version` output and the effective language mode / strict-concurrency setting (freeze addendum B-T1), so any future toolchain drift is visible in the log itself.
- The reviewer lab's frozen documents (H-0495 freeze + addenda) are NOT retroactively rewritten; any freeze amendment lands as the lab's own separate, explicitly-named amendment. This note is the packet-side contract correction only.

Related (Main 05:36): the repo's actual FFmpeg v2 recipe + tracked tar were found; the writer is rebuilding a correctly-labeled artifact (integration-gate prerequisite, in flight). No duplicate W-0264 candidate push - the reviewing lab already has the v2 candidate.
