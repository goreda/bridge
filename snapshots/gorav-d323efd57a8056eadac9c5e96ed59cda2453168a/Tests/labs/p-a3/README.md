# P-A3-SubtitleLayout

Bridge packet P-A3 (lab-a): clean-room SRT/ASS subtitle parser and
deterministic fixed-cell layout boxes. Self-contained Swift package,
Foundation only. No renderer, no Metal/UI, no font measurement, no device
or wall-clock dependency.

## Contents
- `Sources/SubtitleLayout/` - public contract (`Cue`, `CueBox`,
  `SubtitleLayout`) plus `FixedCellSubtitleLayout`, SRT and ASS parsers.
- `Tests/SubtitleLayoutTests/` - 17-test XCTest suite with literal fixtures
  under `Fixtures/`.
- `SPEC.md` - parsing/layout rules. `EXPECTED.md` - hand-computed expected
  parse/layout tables asserted by the tests.
- `TEST-LOG.txt` - captured `swift test` run. `MANIFEST.sha256` - SHA-256
  of every delivered file.

## Build and test
```
swift test
```
Toolchain used for the delivered run: Swift 5.10.1 RELEASE
(swift-5.10.1-RELEASE-ubuntu22.04.tar.gz, public download from swift.org),
x86_64 Ubuntu 22.04. Any Swift 5.9+ toolchain works; no external
dependencies.

## Fixed cell note
Per the packet, layout never measures fonts. Tests and EXPECTED.md use the
supplied fixed cell: width 10, height 20 (grapheme cluster per cell, line
per cell height). The cell is a `FixedCellSubtitleLayout` init parameter
with those values as defaults.

secret scan: clean
