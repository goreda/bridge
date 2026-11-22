# P-B2 Provenance

- Bridge packet: P-B2 | E2/E4 | lab-b, from goreda/bridge GROUP-INBOX.md head
  d37421b04b06d7c07eef36daf3ac8c0e6569cfb4 (inbox sha256
  bd5d47d7b552f12d486ad43268a1ea41fb987bb1f7a467305365d6af99c205be).
- All code is a new clean-room implementation of the public interface quoted
  in the packet. No private repo access, source, identifiers, or paths used.
- Toolchain: Swift 6.0.3 (swift-6.0.3-RELEASE-ubuntu22.04, public download
  from swift.org), Ubuntu 22.04.5 LTS x86_64. Package uses
  swift-tools-version:5.9; no dependencies beyond the Swift standard library
  and Foundation.
- Fixture generation: ffmpeg version 4.4.2-0ubuntu0.22.04.1 (locally
  installed; no downloads of media). LC_ALL=C. Exact command:
  `ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=64x64:rate=24 -t 2 -an -c:v libx264 -bf 0 -pix_fmt yuv420p parity-a24.mp4`
  (the P-A1 public testsrc command, output renamed to the P-B2 fixture name).
- parity-stub-equal.json, parity-stub-different.json, parity-missing.json are
  hand-authored generated JSON (no user data, no captures). Canonical copies
  in fixtures/; byte-identical copies in Tests/ParityCoreTests/Fixtures/ for
  the XCTest resource bundle (see SHA256SUMS.txt).
- sample-output/*.tsv produced by the built `parity-runner` CLI from those
  fixtures; commands recorded in RESULTS.md.
- Native parity is NOT claimed: no mpv/engine adapters exist yet, stubs do
  not read media bytes, and a stub `pass` only exercises the runner.
- secret scan: clean. No credentials, tokens, user data, licensed media, or
  third-party fonts anywhere in this package.
