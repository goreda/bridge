# P-B3: HDR10 PQ/BT.2020 -> SDR BT.709 tone-map reference

Bridge packet P-B3 (E3/E4, lab-b). Return path: lab-b bridge, tag P-B3.
Contents: spec + scalar Double CPU reference (Swift) + Metal shader + XCTest
suite + generated fixtures + executed numeric evidence.

- spec/SPEC.md — exact transfer/matrix/tone-curve/output-encoding definition
  with published constants and source URLs. Read first.
- Sources/HDRReference/HDRReference.swift — RGB, HDRReference protocol,
  ScalarHDRReference (Double CPU reference).
- Shaders/tone_map.metal — float3 equivalent (kept outside the Swift target
  so the package builds without Metal tooling; tests load it from disk).
- Tests/HDRReferenceTests/HDRReferenceTests.swift — XCTest suite; consumes
  the saved fixture oracle. `swift test` (needs Swift 5.7+ toolchain).
- tools/generate_fixtures.py — deterministic generator + numeric assert
  runner (Python 3 stdlib). `python3 tools/generate_fixtures.py`.
- fixtures/ — generated CSV/PPM oracles (hashes in MANIFEST.sha256).
- TEST-RUN.md — what was executed where, with measured numbers, and what is
  delivered-but-unrun (XCTest, Metal parity) plus the precise missing input.
- MANIFEST.sha256 — sha256 of every file in the package.

Status summary: XCTest suite executed and PASS with the official swift.org
Swift 5.10.1 Ubuntu 22.04 toolchain (8/8, see TEST-RUN.md); generator numeric
asserts executed and PASS; Metal execution UNRUN (Linux has no Metal).
secret scan: clean.
