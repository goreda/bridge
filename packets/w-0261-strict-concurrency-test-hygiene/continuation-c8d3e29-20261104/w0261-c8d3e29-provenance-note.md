# W-0261 integrated gate evidence - provenance note

## Tree provenance: 99ecf081 is lost; the rebuild line carries the gates

- Official pin 99ecf081c3af2ed1e65317814f72e5cda37d4fbf (branch
  l3-subtitle-overlay-m2) and the range 4bb068cc..e399471 are not present in
  the current repository history; that historical pre-repair tree state is
  unavailable. Those ids are PROVENANCE ONLY (REBUILD-NOTE.md at 4b93230b).
- Rebuild base: 63a413082e71ec7d3b15be1756048a2e751e253f (4bb068cc + main
  2d8f7373 merge). The wider tree is honest rederivation with new pins; zero
  historical green carried (REBUILD-NOTE).
- UNIT PRE-IMAGE BYTE-EQUIVALENCE (machine-verified 2026-11-04): at 63a41308 the
  three unit files are byte-identical to the public packet baselines:
  RaceArms2.swift sha256 c82882b8ef189d1389108834b00755705e3a218289b4d0beba754e995e03f73f
  main.swift sha256 5667a37dc37eb7598d90267673e369e7194becb977c9d86f838c378626a3d788
  AudioPacingTests.swift sha256 2ef8056aea209fadc3a5de21378957bd82a82fb6da8eeb564540d3c9af390258
  Consequence: the integrated diff (63a41308..c8d3e29, exactly those 3 files)
applies against the PUBLIC baseline bytes; no other tree content is needed to
APPLY it. Reviewing the synchronization changes additionally references two
integrated-pin package sources at c8d3e29 (FramePump actor in
Sources/GorAVPlaybackCore/PlaybackCore.swift, TimingLedger in
Sources/GorAVPlaybackCore/TimingLedger.swift). Comment-sanitized derivatives of both callgraph sources are included in THIS
packet with the A3 notes (see the manifest for original-to-derivative hashes).
These are NOT byte-identical source; executable-bearing lines and line counts
are unchanged. The diff remains the unchanged pin-exact repair artifact.

## Gate evidence inventory (actual bytes, measured sha256)

- build-tests-ae35565a.log (4,826B) sha256 34c1041784f3dbc45c2be0b025aecaae2049831aff31c97db03ab5c4bafadd7f
  `swift build --build-tests` full untrimmed @ c8d3e29, FFmpeg 894da5ca rebuild
  link paths, Build complete 2.15s, CHUNK_EXIT=0.
- swift-test-814a8b69.log (14,881B) sha256 78972409395d37558cee29a13bb33ce3f2f04c0a9b32ceda24ea4eae110e734d
  `swift test` full suite @ c8d3e29, no filter: 57/57, 0 failures, CHUNK_EXIT=0;
  all 15 AudioPacingTests methods named and passed; suites 6+9+15+1+3+11+12=57.
- postrun-provenance-815b4de4.log (347B) sha256 400aab2f730a25c0b79e89386ba7422533a5ecdbea8197db2a30b5c508762ec9
  git rev-parse HEAD = c8d3e29 (executed); Package.swift sha256
  ee2bd3a5893fc1f064500b783d0dfa950ef3544a0da2142ab09c3c2a88c19336 matches
  expected; git diff --exit-code clean; only .build/ untracked.
- race-witness-runtime-6ebed44a.log (16,318B) sha256 702037a3efddfceab69af3d28386ba1927f51ee0f542a34891595472aa6f8df5
  `swift run race-witness-tests` @4b93230 (= c8d3e29 sources), 228 check PASS
  lines, 0 FAIL, "ALL RACE WITNESSES PASS (incl RW34/RW35)", RUN_EXIT=0.
  Mac-seam arms (RW6/RW8/RW9/RW10/RW22/RW23) recorded as native=BLOCKED,
  owner-run, NOT claimed from Linux.

## A6 / B-T1 coverage against the frozen fields

A6: command (yes, full CMD lines), exit codes (yes), tree pin (header assertions
plus executed rev-parse in the provenance log), suite/test counts (yes, incl.
all-15-method AudioPacing visibility), race-witness executable run (yes).
DIFF PIN: no diff sha recorded - the repair is committed, so the pin role is
served by commit c8d3e29 + byte-pinned pre-image (63a41308 = public baselines);
state this mapping explicitly anywhere the evidence is used.
B-T1 GAP: no gate log contains an executed `swift --version` /
language-mode / strict-concurrency probe - the headers ASSERT "Swift 5.10.1
RELEASE x86_64 Linux" and "no filter, no exclusions" but no version command
output is in the logs; the headers are NOT promoted to executed version proof
anywhere this evidence is used. The actual probe DID execute historically:
its original artifact was compiler-version-ee406555.log, but the probe BYTES
are not part of the current evidence set (no rerun, no reconstruction). The venue is meanwhile supported by:
(a) public packet TOOLCHAIN-FACTS.md (sha256 4024500c8da68a0e6154f430a4544b47f42d8dadfe88527399aebd0baa30a146,
the packet-side record of the actual 2026-11-01 venue probes, Swift 5.10.1
RELEASE x86_64 Linux, tools-version 5.9), and (b) the executed gate logs
above, whose headers match those facts. Effective language mode is
SOURCE-DERIVED (Package.swift tools-version 5.9, no swift-version/strict
overrides, manifest sha256 ee2bd3a5 verified in the provenance log), NOT an
executed mode probe. Explicit current byte gap: the executed probe output
itself.
AudioPacing baseline failure class: venue-asserted, never log-captured (build
halted at race-witness); post-repair all-15 green is the available run evidence
(swift-test log above).

## Hash lineage discrepancy (kept explicit)

Prior reported log hash prefixes 197b3493.../6fa36933... do not match any
measured hash of the four executed logs in this evidence set. Those prior
values are unresolved and superseded; the measured set above is authoritative.

## Bounds

Static/analytical evidence only on the reviewer side; no empirical race-freedom
proof (no TSan on either byte line); Mac/Darwin native unrun; nothing here is
acceptance or closure.
