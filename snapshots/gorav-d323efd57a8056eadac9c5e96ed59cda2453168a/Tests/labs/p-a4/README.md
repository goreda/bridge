# BridgeTimeMath (P-A4)

Self-contained Swift package: checked time math for media timestamps -
rational rescale, duration splitting, timestamp add/subtract with typed
overflow (`TimeMathError`: `.overflow`, `.nonPositiveScale`,
`.nonPositiveParts`). Never a silent wrap, never a trap, never a dropped
flag.

    swift build
    swift test            # debug
    swift test -c release # release - identical vectors, must agree

Layout:
- Sources/BridgeTimeMath/TimeMath.swift   TimeMathError, CheckedTimeMath, Int64TimeMath
- Tests/BridgeTimeMathTests/              XCTest suite + Fixtures/*.csv vectors
- tools/make_vectors.py                   deterministic vector generator + big-int oracle
- SPEC.md                                 semantics, coverage, limits, provenance
- TEST-LOG.txt                            recorded debug + release runs
- MANIFEST.sha256                         sha256 of every packaged file

Developed and tested with Swift 5.9.2 (swift-5.9.2-RELEASE-ubuntu22.04, x86_64).
