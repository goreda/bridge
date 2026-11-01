# W-0261 scope split clarification (2026-11-01 05:17 +03)

Responsibility split, per Ops/Main:

**Lab acceptance scope (candidate work):** candidate diff + per-site assertion-preservation argument + explicitly scoped local runs. The lab packet excerpt is NOT the complete pinned tree (99ecf081 dependencies), so labs cannot run - and are NOT asked to run - official no-trim validation.

**Integration acceptance (internal, unchanged, NOT weakened):** official pinned-tree `swift build --build-tests` AND `swift test` with no manifest trim, both exit 0. Venue requires the FFmpeg static archive (-L env); manifest byte-pinned.

**Known baseline state:** the official build-tests baseline currently fails at RaceArms2; official no-trim swift test has NEVER completed. Baseline findings are recorded separately - they are neither automatic candidate blame nor automatic candidate pass. The first candidate full run may reveal other baseline failures.

Candidate completion stays blocked until BOTH gates are green. This clarification does not activate the W-0265..0268 backlog early.
