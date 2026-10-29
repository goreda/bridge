# W-0249 settings-execution fixture v1

Execution-readiness fixture for the W-0249 black-box acceptance list (v5 doc,
pin 91092ba5...2de) against the INSTALLED build 261029-143306-kni-151c and,
separately, the STAGED sb-sequence bytes (225c9d4e7, not installed).

- build_fixtures.py: deterministic synthetic collections A / B / empty
  (64x64 grayscale PNG glyph tiles; no licensed fonts, no real captures) +
  env JSON implants (valid + the T-10 defect battery) + FIXTURES.json with the
  exact source_sha256 derivations.
- run_entry.py / execute_refusals.py: invoke the pinned installed
  ocr_images.py directly; the refusal battery (T-08, T-10 i-vii, T-12) dies
  before the native engine, so it executes on Linux against the real bytes.
- drive_prompt.py: scripted-answer driver for the settings screen (installed
  and staged prompt modules).
- FIXTURE-CONTRACT.json: per-test execution level, the EXECUTED actual
  outcomes (15:38-15:42), and the exact blocked portions (full-engine tests,
  declared_levels oracle absence, T-02) with their execution route.

Bounds: no engine code duplicated, no new product semantics, no invented
metric oracle. Full-engine tests await the writer-owned Linux chain proof or
the installed Mac build.
