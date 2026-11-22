# ParityKit (bridge packet P-B2)

Parity runner that compares two injected backend adapters on the same fixture
and emits measured TSV with explicit unavailable measurements.

- `Sources/ParityCore` - public contract (`PlaybackProbe`, `ProbeBackend`,
  `ParityRunner`), the deterministic `TSVParityRunner`, TSV
  escaping/formatting, and `StubProbeBackend` fake adapters.
- `Sources/ParityRunnerCLI` - `parity-runner --stubs <stub.json> --fixture
  <name> --seek <seconds>`, prints the measured TSV.
- `Tests/ParityCoreTests` - 10 XCTest cases covering the packet's exact
  asserts (round-trip, visible differences, NA/unavailable, explicit errors,
  escaping, validation).
- `SPEC.md` - the TSV contract. `PROVENANCE.md` - toolchain, fixture
  commands, scope limits. `RESULTS.md` - the recorded test run.
- `fixtures/` - parity-stub-equal.json, parity-stub-different.json,
  parity-missing.json, parity-a24.mp4. `sample-output/` - sample measured TSV.

Build and test: `swift build --build-tests && swift test`
(Swift 5.9+ toolchain, standard library + Foundation only).
