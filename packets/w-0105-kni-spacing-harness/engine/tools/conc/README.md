# CONC integration harness (W15)

Tooling for the multi-writer parallel flow: writers deliver diffs through the
bridge, the chief architect alone intakes, gates, merges and commits. These
scripts are the architect's book of record. None of them applies a diff to the
real tree, merges, or commits anything.

Flow per diff:

1. `conc_queue.py intake` — store the diff bytes and append an intake event to
   the ledger. The intake records the writer id, the base tree sha the diff was
   produced against, the diff's own sha256, and the touched files extracted
   from the diff itself.
2. `conc_conflicts.py --queue` — check every queued diff against the module map
   (`module-map.json`): a writer touching paths outside its entry is a
   violation, two writers touching the same non-shared path is a conflict,
   shared paths (e.g. the single call-site line) are reported for hand-merge.
3. `conc_gate.py` — apply the diff onto a pristine copy of the base tree in a
   scratch dir, run the check and test commands, write a receipt. A diff
   without a PASS receipt is NOT RUN; author reports are not evidence.
4. `conc_queue.py resolve` — append the architect's decision (merged /
   rejected / superseded). The ledger is append-only; a resolved entry cannot
   be re-resolved.
5. `conc_queue.py order` — replay the merged diffs in queue sequence. This is
   the merge-order ledger: the exact order in which accepted diffs land.

## Layout

- `conc_queue.py` — intake queue + merge-order ledger (state: a queue dir with
  `ledger.jsonl` and `diffs/`, both created on first intake; the queue dir is
  operational state, not committed).
- `conc_conflicts.py` — module-map conflict check over queued or ad-hoc diffs.
- `conc_gate.py` — per-diff compile+test gate with a JSON receipt.
- `diffpaths.py` — shared touched-file extraction from unified diffs.
- `module-map.json` — the writer-to-file map (schema `kni-conc-module-map/1`).
  Seeded from the writer briefs; the chief architect keeps it current. A writer
  with empty `paths`/`globs` is unmapped and its touches are flagged until the
  map assigns it files.
- `tests/` — unittest suite, runnable with no engine build and no fixtures:

      python3 -m unittest discover -s tools/conc/tests -v

## Ledger gate tooling (lane deliverables)

- `ledger_check.py` - conformance checker for the unified typed ledger schema
  (docs/conc/ledger-schema.md). Runs in every lane gate over the lane's
  ledger/receipt outputs. The three pre-existing emitters' formats are
  accepted as documented variants (architect decision); new rows must use the
  canonical form. `--self-test` runs its embedded suite; `--strict-legacy` /
  `--strict-variants` counts variant lines as violations for migration
  audits.
- `ledger_gate.sh` - one-command gate wrapper over ledger_check.py. Takes
  FILE args, --files-from MANIFEST (one path per line), or --pre-ship
  OUT_DIR (discovers every *.txt/*.tsv under a run output tree; zip junk
  filtered). Prints one summary line per file plus a GATE PASS/FAIL footer,
  and exits with the checker's code (0 pass, 1 violations, 2 usage/io) so
  the per-diff gate wires it directly. Flags pass through to the checker.

  Pre-ship / CI wiring: the single command is

      tools/conc/ledger_gate.sh --pre-ship <engine output dir>

  Scope rules do the selection: typed ledgers and receipts (including
  run-failure-receipt.txt) are checked, known columnar tables and run
  artifacts are skipped, any new file kind is checked by default (fail
  closed). The kit pre-ship flow (FORMAT-PASS + VERIFY + fresh-unzip
  smoke, W19's tools/kit_preship.py) runs it once per style output dir or
  once over the whole output tree after the VERIFY step; CI does the same
  on the run artifacts. Measured on a 13-style real output tree (94
  discovered files, 25 checked, 10,965 checked lines): about 0.12 s
  end-to-end per run - negligible against the engine run itself.
- `receipt_head_drift.py` - drift test binding the receipt kv-head registry
  in ledger_check.py to the emitter source. Extracts candidate tab-row
  heads from the Rust emitters (test code excluded) and fails when an
  emitted head is unregistered, a registered head lost its emitter, or a
  known non-receipt exception (cache, evidence, bench, table-header rows)
  went stale. Heads with a proposed but unlanded emitter sit in
  PENDING_EMITTER_HEADS and must leave it in the landing diff. Runs over
  the engine tree, no file args; `--self-test` runs its embedded suite. A
  new receipt emitter must extend the registry in the same diff or this
  test fails intake.
- `ledger_mutation_test.py` - mutation test for the gate's negative scope.
  Mutates real receipt lines (head typos, deleted/duplicated/blanked
  fields, NaN/Inf values, whitespace and tab damage, CR injection, arity
  breaks) plus synthetic canonical/summary rows, and fails when any
  catchable mutation classifies as valid. Mutations landing on a
  grammar-covered head are must-catch; structurally undetectable ones
  outside the grammars are reported as known escapes for the architect.
  `--receipt PATH` adds a real fixture; the embedded synthetic set always
  runs.
- `merge-ledger.json` - the merge order computed from the active queue at
  map-seed time. Re-run whenever a lane lands, spawns, or blocks. Gate
  status fields are honest: NOT RUN never counts as acceptance.
- `docs/conc/ledger-schema.md` - the stage/code/subject/reason schema, the
  code registry, the receipt kv-head registry with arities and field
  grammars, the gate scope (typed-flag ledgers and receipts in, columnar
  tables out), and the documented-variant list.
- `docs/conc/landed-lane-audit.md` - conformance audit of the gate-chain
  lanes against the map at map-seed time, with the architect-confirmation
  list.
- `docs/conc/receipt-segment-metrics-proposal.md` - row format, checker
  grammar, and Rust emitter draft (NOT_RUN) for the proposed per-glyph
  glyph_segments receipt row.

## Conventions

- Diff paths are normalized (`a/` / `b/` stripped); the map's `root_prefix`
  (or `--root-prefix`) is stripped before matching, so repo-root-relative and
  engine-root-relative diffs both match engine-root-relative map entries.
- No wall-clock anywhere: queue order is the integer sequence, gate receipts
  carry shas and exit codes. Ledgers and receipts diff cleanly across machines.
- No behavior switches: the tools only read diffs and run commands passed on
  the command line; they change no engine output.
