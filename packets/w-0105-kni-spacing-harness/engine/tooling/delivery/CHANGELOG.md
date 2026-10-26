# Delivery tooling changelog

## 1.1.0 - 2026-10-18 (engine HEAD 38f506e3cddf98d82ded8f80bb2a7bcac031ba48)

### Added
- `tests/test_full_cmap_render_sweep.py`: the complete glyph sweep as a
  permanent delivery gate. A generated complete-cmap CFF1 reference font
  (contiguous Unicode blocks U+0020-U+007E, U+00A0-U+00FF, U+0100-U+017F;
  319 codepoints, 318 after the fixture drops the one codepoint that text
  layout renders invisible) goes through the production entrypoint
  (`canonical_delivery.py`) with the compiled `capture_audit` Rust binary:
  per-codepoint source tiles, real fit audits, honest outline measurements
  (symmetric-difference area and boundary Hausdorff against the reference
  outlines), vector receipt, mandatory full-cmap render sweep, evidence pack
  hash binding, and visual seal. Negative permanence: an incomplete-cmap
  plan is refused and evidence tampering breaks the seal.

### Changed (owner directive 2026-10-18: one general rule set for all
### languages, no per-language code)
- Removed the hardcoded language-specific `require_turkish` expansion from
  `delivery_gate.py`, `capture_coverage.py`, and the manifest flow
  (`build_delivery_manifest.py`, `canonical_delivery.py`,
  `assemble_synthetic_evidence_pack.py`). Declared coverage requirements
  travel only through the general `required_codepoints` list. The gate and
  the entrypoint reject manifests/plans still carrying the removed field
  (fail-closed; a stale manifest never silently loses a requirement).
- README updated for the field removal and the permanent full-cmap sweep.

### Test counts
- Before: 350 tests, all passing (synthetic 2-3 glyph fixtures only; the
  producer had never run against a render sweep).
- After: 357 tests, all passing on Linux (Python 3.10, fontTools 4.65.0,
  Pillow 12.3.0, rustc 1.99.1), including 7 full-cmap sweep tests over a
  318-codepoint cmap.

## 1.0.0 - baseline
- Source-bound delivery gate, vector-fidelity receipt, canonical production
  entrypoint, visual seal (state before this entry; version assigned
  retroactively).
