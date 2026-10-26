# SP-PROOF — bit-identity proof harness for off-target styles/pairs

Gate for every change that must leave untouched styles byte-identical
(A/B/C/D/SP-OOHH and any future gated module): prove that the candidate
engine produces byte-for-byte the same outputs as the base engine for every
style and pair outside the change's target scope.

## Usage

Compare two already-produced run roots:

    sp_proof.py compare --kit KIT.tsv --base-root DIR --cand-root DIR \
        --base-label <base-sha> --cand-label <candidate-sha> \
        [--styles style-a,style-b] \
        --report-json report.json --report-md report.md

`--styles` restricts the proof to the named kit rows (comma-separated
style_ids). Unknown ids are a typed refusal, never a silent skip; an
off-subset tamper cannot change the verdict.

Build both revisions from one repo checkout, run the off-target styles, then
compare (tiles/manifests resolve via `$KNI_G_FIXTURES`, never a hardcoded path):

    KNI_G_FIXTURES=/path/to/kit-fixtures sp_proof.py run --kit KIT.tsv \
        --repo /path/to/kni --base-sha <sha> --cand-sha <sha> --work /tmp/sp-proof-work \
        --report-json report.json --report-md report.md

## Kit manifest (TSV)

One row per style, `#` comment lines allowed:

    style_id <TAB> family <TAB> subfamily <TAB> manifest_relpath <TAB> out_relpath <TAB> scope

- `scope` is exactly `on-target` or `off-target`. Only off-target rows are
  compared; on-target rows are reported as SKIPPED. A kit with no off-target
  row is refused: there is nothing to prove.
- `manifest_relpath` is the engine manifest for `run` mode; relative paths
  resolve against `$KNI_G_FIXTURES`. Use `-` for compare-only kits.
- `out_relpath` is the style's out-dir relative to each run root; the font
  file name is derived as `font-<style_id>.otf` (the pipeline's own rule).

## What is compared (declared CONVENTION)

- `font-<style_id>.otf`: whole-file bytes first; on DIFF the CFF CharStrings
  INDEX is parsed per glyph (names from the font's own charset/String INDEX),
  yielding the full style x glyph matrix and the first differing glyph in
  glyph order. The font must exist on both sides; a missing font is a FAIL.
- `mapping.tsv`, `spacing.tsv`, `spacing-pair-ledger.tsv`, `kern-ledger.tsv`,
  `kern-diagnostic.tsv`, `iou.tsv`, `iou-population.tsv`,
  `profile-metadata.tsv`: byte-for-byte. Identical absence on both sides
  counts as identical (stage not reached equally in both runs).
- Excluded: `receipt-<style_id>.txt`, `run-provenance.tsv`,
  `stage1-cache.txt`, `floor.otf` — these can embed run-local absolute paths
  and diagnostic prose, so cross-root byte equality is not defined for them.
  Geometry, spacing and kern evidence all live in the compared artifacts.

## Exit codes (declared CONVENTION)

- 0 PASS — every off-target artifact byte-identical.
- 4 FAIL — at least one difference; the report names the first differing
  glyph per differing style.
- 3 REFUSED — malformed/unreadable inputs; nothing was compared.

## Quick gate (no collection fixtures)

A self-contained 6-glyph diagnostic style ships in `fixtures/diagnostic/`
(scans included, independent of the collection styles). Two kits exercise the
flag OFF/ON lane semantics end to end in under a minute:

    # one engine run per side per style (base build and candidate build):
    kni-pipeline fixtures/diagnostic/manifest.txt OUT/base/diag  --style-id diag    [flags]
    kni-pipeline fixtures/diagnostic/manifest.txt OUT/base/diagctl --style-id diagctl [flags]
    kni-pipeline fixtures/diagnostic/manifest.txt OUT/cand/diag  --style-id diag    [flags]
    kni-pipeline fixtures/diagnostic/manifest.txt OUT/cand/diagctl --style-id diagctl [flags]

    # flag OFF lane: candidate built with the layer disabled
    sp_proof.py compare --kit kits/quick-gate-flag-off.tsv \
        --base-root OUT/base --cand-root OUT/cand \
        --base-label <base-sha> --cand-label <candidate-sha>

    # flag ON lane: candidate built with the layer enabled; the kit scopes
    # the layer's target style on-target, everything else must stay identical
    sp_proof.py compare --kit kits/quick-gate-flag-on-example.tsv \
        --base-root OUT/base --cand-root OUT/cand \
        --base-label <base-sha> --cand-label <candidate-sha>

(`run` mode also works fixtureless with these kits: a relative
manifest_relpath resolves against the kit file's own directory when
`KNI_G_FIXTURES` is unset.)

Captured example outputs (real runs of this tree; the "ON" candidate is
simulated by `fixtures/diagnostic/manifest-on-sim.txt`, which changes glyph
r's input - a stand-in for any layer output change):

    # [1] flag-OFF kit, candidate == base behaviour:
    sp_proof: PASS — 2 off-target style(s), 2 identical, 0 FAILED   (exit 0)

    # [2] flag-OFF kit against a changed candidate: unscoped change is caught
    sp_proof: FAIL — 2 off-target style(s), 1 identical, 1 FAILED
      FAIL diag first differing glyph: r (GID 1)                    (exit 4)

    # [3] flag-ON example kit against the same changed candidate:
    #     diag is on-target (SKIPPED), control style proven identical
    sp_proof: PASS — 1 off-target style(s), 1 identical, 0 FAILED   (exit 0)

## Gate run: full collection (kni-kit/collection)

The acceptance gate for gated modules (A/B/C/D/SP-OOHH ...) runs the harness
against the real collection tree. `KNI_G_FIXTURES` points at the collection
root in the repo checkout; per-style engine manifests live under
`manifests/<style_id>.txt` there (generate them from each style's tile folder
with `engine/pipeline/tests/fixtures/kit-v415/kit_manifest.py`; the harness
never invents a manifest). One command line is the whole gate:

    export KNI_G_FIXTURES=<repo>/kni-kit/collection
    python3 engine/harness/sp-proof/sp_proof.py run \
        --kit engine/harness/sp-proof/kits/w7-sp-oohh-flag-off.tsv \
        --repo <repo> --base-sha <base-sha> --cand-sha <candidate-sha> \
        --work /tmp/sp-proof-gate \
        --report-json sp-proof-report.json --report-md sp-proof-report.md
    # exit 0 = gate PASS; exit 4 = FAIL (report names the first differing
    # glyph per style); exit 3 = refused (fixtures/manifests missing)

The driver creates one git worktree per sha, builds
`kni-kit/out8-runkit-v2/engine/pipeline` (release) in each, runs every
off-target kit row in both trees, then compares. `--work` must not exist (no
overwrite). Extra pipeline tokens are passed to BOTH builds equally, one per
flag, dashed values in `=` form:
`--run-extra-args=--jobs --run-extra-args=2 --run-extra-args=--allow-partial`.

## Status (honest labels)

- Unit tests: RUN — `python3 test_sp_proof.py`, 17 tests (PASS/FAIL/REFUSED
  arms, first-differing-glyph naming, glyph-count changes, ledger diffs,
  missing-font arms, on-target skipping, malformed-kit refusals, --styles
  subset behavior, missing-manifest typed refusal in run mode, kit-relative
  manifest resolution).
- Real engine end-to-end: RUN — engine built from this tree
  (`cargo build --release`), 6-glyph diagnostic manifest executed twice
  (`--jobs 1` vs `--jobs 2`): PASS, fonts byte-identical. Same manifest with
  one glyph's source scan swapped: FAIL, first differing glyph named `r`
  (GID 1), glyph matrix 1 DIFF of 7.
- Quick gate (fixtures/diagnostic, both kits, all three example lanes):
  RUN — captured verbatim above.
- Full-collection `run` mode against kni-kit/collection: NOT RUN here (needs
  the kit fixtures and a repo checkout; the driver refuses without
  `KNI_G_FIXTURES` and refuses on any missing per-style manifest before
  building anything).

Stdlib only. Reads files, writes reports only where told.
