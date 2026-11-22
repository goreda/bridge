# P-A3-R1-SubtitleLayout

Bridge packet P-A3-R1 (lab-a): strict configuration validation and
metadata-isolation regression tests layered on the unchanged P-A3 package.

- `Vendor/P-A3-SubtitleLayout/` - the original P-A3 package, byte-identical
  (hash-pinned; verify with `sha256sum -c Vendor/P-A3-SubtitleLayout/MANIFEST.sha256`
  from that directory). One correction vs the first P-A3 delivery: the
  manifest file's separator format was fixed for GNU `sha256sum -c`; every
  hash value and every other file is unchanged.
- `Sources/SubtitleLayoutStrict/` - new R1 module: `StrictSubtitleLayout`
  and `SubtitleConfigError`.
- `Tests/SubtitleLayoutStrictTests/` - 14-test XCTest suite, fixtures
  (6 byte-identical P-A3 fixtures + 2 generated bad-PlayRes variants).
- `SPEC-R1.md`, `EXPECTED-R1.md`, `TEST-LOG-R1.txt`, `VERIFY-LOG.txt`,
  `MANIFEST.sha256`.

## Build and test
```
swift test
```
Toolchain used for the delivered run: Swift 5.10.1 RELEASE
(swift-5.10.1-RELEASE-ubuntu22.04.tar.gz, public download from swift.org),
x86_64 Ubuntu 22.04. No external dependencies beyond the vendored package.

secret scan: clean
