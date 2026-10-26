# Test fixtures and KNI_G_FIXTURES

Some gates and parity tests need source material that does not belong inline in
code. This document names where that material lives and how tests find it.

## Policy

- Tests fail loudly when a fixture is missing or corrupted. They never skip,
  and they never fall back to a machine-local scratch path (an absolute path
  outside the repo is a defect, not a configuration).
- Fixture bytes are pinned by sha256 in the test that consumes them; a stale
  or regenerated-away file fails the pin check.
- Fixtures are committed under the consuming crate's `tests/fixtures/`
  directory, or supplied externally through the environment variables below
  when the material is too large or too sensitive to commit.

## KNI_G_FIXTURES

`KNI_G_FIXTURES` points at a directory of externally supplied fixture material.
Current consumers:

- `core/tests/economy_eval.rs` and `core/tests/iou_parity.rs`: the directory
  itself holds the five pinned scan PNGs (`r_scan.png`, `s_scan.png`,
  `u_scan.png`, `dot_00b7.png`, `quote_2018.png`); each test pins the expected
  sha256 of its file.
- `pipeline` name-gate tests (`pipeline/src/main.rs`, `name_gate_tests`):
  `$KNI_G_FIXTURES/name_gate/defective-shipped-name.otf` overrides the
  committed repo fixture.

## KNI_NAME_GATE_FIXTURE

`KNI_NAME_GATE_FIXTURE` is an explicit file path to the name-gate fixture and
takes precedence over `KNI_G_FIXTURES`. Use it to point the gate tests at a
candidate fixture without arranging a directory tree.

An empty value for either variable counts as unset.

## name-gate fixture

Committed at `pipeline/tests/fixtures/name_gate/defective-shipped-name.otf`
with its deterministic generator and provenance notes; see the README in that
directory.
