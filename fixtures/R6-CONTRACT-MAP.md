# fixtures-R6 v4 - generator-to-contract mapping (2026-10-25)

Supply scope: the published requests W-0081..W-0088 (bridge GROUP-INBOX) each
promise requester-supplied generator code ("ship it as text"). This archive is
that supply. W-0089..W-0091 are published requests outside this fixture supply.
Rulings in README.md are requester-side engineering answers to the labs'
clarification entries (G-0140 a-d, G-0142 a-b, the W-0083 cap numbers); the
published request texts remain the only contract.

| request | supplied generator | outputs | contract notes |
|---|---|---|---|
| W-0081 | w0081/w0081_gen_trajectory.py | trajectory.jsonl (600 steps x 64 discs), planted_truth.json | G-0140 (a)-(d) answered in README: meta+per-step schema, per-partner longest-run (not union), separators block cross-barrier contact, planted pair steps 10..590 inclusive = 581, +/-1 endpoint tolerance only |
| W-0082 | w0082/w0082_toy_solver.py | solver_log_defect.jsonl, solver_log_control.jsonl, planted_truth.json | G-0142 (a)-(b) answered in README; regenerate with Python 3.10.x (random.gauss stability pin) |
| W-0083 | w0083/w0083_gen_scenes.py | scenes.jsonl (12 matrix pairs + 2 corrected interface-test rows) | Cap corrections: insets PER SIDE, effective 296x108 at inset 48; PROPOSED corrected interface test (NOT a ratified contract change) FAILS the 405x150 scene (max ratio = height 150/108 = 1.3889 > 1.0); earlier 405-vs-297 and 392x204.1 figures were mis-stated |
| W-0084 | w0084/w0084_gen_glyphs.py | families.json, split_clean/leak2/leakvar.json, planted_truth.json; manifest.jsonl regenerable (pinned 9,274,080 B, not shipped) | leakvar mechanism documented in README: 50 exact-pixel duplicates across the split boundary with disjoint family labels |
| W-0085 | w0085/w0085_toy_loop.py + w0085_competitor.py | run_log.jsonl produced by the LAB on its own host (host-dependent by design, no sha pinned), planted_truth.json (competitor ON steps 100-199 + 300-349) | LIMIT: no tested automatic boundary-free detector recovered both published windows with zero quiet false positives on the tested 1-vCPU hosts (best short-arm recall 1/6); universal unsatisfiability unproved. CPU-clock instrumentation separated workload vs environment in the tested runs; oracle-bounded arm scoring 6/6 both sides (a scoring comparison, not a detector). Contract UNCHANGED; full record in W0085-R2-LIMITS.md |
| W-0086 | w0086/w0086_tree_exporter.py | full-06.tar, inc-1-12/inc-2-18/inc-3-24/inc-4-30.tar, inc-3-24-CORRUPTED.tar, chain_truth.json | Bundle format = actual tar (ustar, deterministic), per the published "tar or git-bundle format stated" contract; final-only verification trap documented in README |
| W-0087 | w0087/w0087_toy_kv.py | store_fixture.json, planted_truth.json | Schema strictness: unknown design rejected |
| W-0088 | w0088/w0088_gen_stream.py | schedule_worst_burst.jsonl, schedule_idle.jsonl, pace.json, planted_truth.json | Window semantics resolved: any half-open [t, t+100ms); cap 40 tokens/100ms including after the 400-token burst; grid-only enforcement measured insufficient |

All generators: Python 3 standard library only, deterministic under pinned
seeds, run from an empty directory with the output directory as the only
argument (python3 <script> <dir>). Per-file bytes/sha256 in
FIXTURE-MANIFEST.json; regenerable outputs reproduce under Python 3.10.12.
