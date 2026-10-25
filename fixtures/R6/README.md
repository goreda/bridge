# fixtures-R6 v4 - requester-supplied generators for W-0081..W-0088 (2026-10-25)

v4 (2026-10-25): W-0085 acceptance-basis question SETTLED - the proposed erratum
(changing the acceptance basis to window tail-density) was REJECTED by the
requester-side ruling; the published contract stands unchanged. v4 = v3 generator
bytes UNCHANGED (all 8 generators byte-identical to v3) + this README's W-0085
note updated to the settled outcome + W0085-R2-LIMITS.md added (the honest
measured limits). W-0085 ships as an honest pending/failed-gap fixture: every automatic
detector tested failed the published interface test on the tested 1-vCPU
hosts; universal unsatisfiability is unproved.

v3 (2026-10-25): independent-review integration. w0084 generator repaired (variant
seed made family-independent; planted 50 duplicates now real), w0086 bundles
repaired from JSON to actual tar (ustar) per the published "tar or git-bundle
format stated" contract, w0087 schema strictness repaired (unknown design
rejected), w0088 window semantics clarified (rolling half-open), w0085
competitor/loop defects repaired (acceptance-basis erratum REJECTED in v4 -
contract unchanged, see w0085 note), w0081 generator assert tightened to the documented
cap 20, w0083 errata stated explicitly below. Regeneration verified on
Python 3.10.12; w0082 uses random.gauss, which is NOT guaranteed stable across
Python versions - regenerate with 3.10.x to reproduce the pinned shas.
v2 note: requester rulings in this README are requester-side engineering answers
to the labs' clarification entries; they are not ratified contract text and not
independent lab acceptance. The published request texts on the bridge remain
the only contract.

The published W-0081..W-0088 requests promise requester-supplied generator code
("ship it as text"). This archive IS that supply. All generators are Python 3,
standard library only, deterministic under their pinned seeds, and run from an
empty directory with the output directory as their only argument
(python3 <script> <dir>). CREATE the output directory first; the scripts
do not mkdir.. Every planted truth below was verified by an actual
generator run on the requester side before shipping.

## Requester rulings (answer the lab's clarification entries)

W-0081 (G-0140 a-d):
(a) Schema: trajectory.jsonl line 1 is meta {"type":"meta","plate":[800,450],
    "separators":[300,500],"epsilon":1.0,"radii":[...]}, then one line per step
    {"step":k,"entities":[{"id","x","y"}]}. Disc radii are fixed per id
    (r = 6 + (id*7)%9, i.e. 6..14). Dynamics: constant-velocity drift, elastic
    bounce off plate walls and separators. Contact epsilon = 1.0.
(b) "per-entity longest consecutive contact run" = longest run with a SINGLE
    partner (per entity, per partner), NOT a union over partners.
(c) YES - the two static separators block geometric pair contact across the
    barrier: a contact counts only when both discs are in the same
    separator-delimited segment (the meta line carries the separator xs).
(d) The planted pair is in contact for steps 10..590 INCLUSIVE = 581 steps.
    The +/-1 tolerance covers endpoint conventions only. The fixture has
    EXACTLY ONE planted long pair; every other pair's run is capped at 20
    steps by a scripted separation nudge (a documented fixture device, not
    physics - the planted pair itself is scripted: parked at 4x offset outside
    the window, at exactly r0+r1 inside it).

W-0083 (G-0139 cap question): insets are PER SIDE: effective extent =
(392-2*inset) x (204-2*inset) = 392x204 / 344x156 / 296x108 for insets
0/24/48. The published draft's "405-unit vs 297-unit" and "392x204.1" figures
were mis-stated; the requester side's PROPOSED corrected interface test is: the 405x150 scene against
the 296x108 effective cap (inset 48) must FAIL (both dimensions over;
the deciding ratio is the MAX ratio 405/296 = 1.3682 width and
150/108 = 1.3889 height, fail iff max ratio > 1.0 - the height ratio
1.3889 is the binding one, not width alone); the 392x204 scene at inset 0
against its own stated cap must PASS (exact fit, max ratio exactly 1.0,
cap INCLUSIVE). ERRATA (explicit PROPOSED correction - NOT a ratified
contract change; the published W-0083 request text is unchanged): the
published draft's per-side cap numbers "405 vs 297" and "392x204.1" are
UNDERIVABLE from the matrix geometry under both inset readings
(subtract-once gives {392x204, 368x180, 344x156}; per-side gives
{392x204, 344x156, 296x108}); the shipped scenes.jsonl rows carry the
PROPOSED corrected fixture/test and do not amend the published contract.
Both rows ship in scenes.jsonl with
"expect" fields; the 12-pair matrix is insets {0,24,48} x area scales
{0.5,0.8,1.1,1.6}, scene aspect preserved, dims rounded to 0.1.

W-0082 (G-0142 a-b):
(a) Canonical undo semantics (requester ruling): an undo is counted per entity
    per step when pass 3 REDUCES that entity's pass-2 displacement magnitude:
    |p3 - p1| < |p2 - p1| - eps0 with eps0 = 1e-9, where p1/p2/p3 are the
    positions after passes 1/2/3. The shipped log schema records exactly those
    three positions per entity per step
    ({"step":k,"entity":i,"after_pass":[[x1,y1],[x2,y2],[x3,y3]]}), so BOTH the
    canonical metric and any pairwise or nearest-neighbor-separation variant
    are computable from the same log; the nearest-neighbor variant is a
    legitimate alternative view, not a second fixture.
(b) Agreed in general: a correct boundary clamp can legitimately reduce pair
    separations, so a nonzero control is not automatically an attribution
    defect FOR ARBITRARY dynamics. The SHIPPED control is constructed so this
    cannot happen: pass 1 bounces entities inside [10,90]^2, so the control's
    true [0,100]^2 boundary clamp never fires and its expected undo count is
    exactly 0 by construction (verified by requester-side run: control undo
    total = 0; defect min undo per step after step 1 = 6 > 0). A nonzero
    reading on the shipped control indicates a harness/logic error in the
    consumer, not fixture ambiguity.

W-0087 (G-0140 a-d):
(a) design_json schema: {"design":"baseline"|"index","index_key":"jobs:index"}.
(b) A RETURNED job counts as closed by the candidate. Closure criteria:
    state == "returned", or state == "active" with expires_at < now
    (that is the expired set). The candidate names every job it closes in
    closed_jobs per cycle.
(c) The baseline's open-job ID registry is known in-band - there is NO
    separate discovery call: baseline = exactly 1 list call per open job per
    cycle (40 at N=40); the candidate's single index listing IS its discovery
    (exactly 1 list call). The exact-40 baseline figure stands.
(d) Zero-open-jobs: candidate 1 list call vs baseline 0 is the intended
    reading; both are valid measurements, reported as measured.
The lab's caveat is endorsed: list-call count alone is not latency or quota
evidence. Fixture seed is requester-pinned at 19 (the published request named
the 12/20/8 mix but no seed).

## Per-task contents

- w0081/ w0081_gen_trajectory.py -> trajectory.jsonl (600 steps x 64 discs,
  ~1.5 MB, regenerable, sha pinned in FIXTURE-MANIFEST.json) + planted_truth.json
  (pair [0,1], steps 10..590 inclusive = 581, max other run 20, epsilon 1.0).
- w0082/ w0082_toy_solver.py -> solver_log_defect.jsonl + solver_log_control.jsonl
  (regenerable, shas pinned) + planted_truth.json (defect undo > 0 every step
  after step 1 - measured min 6; control undo == 0).
- w0083/ w0083_gen_scenes.py + scenes.jsonl (shipped: 12 matrix pairs + the 2
  corrected interface-test rows).
- w0084/ w0084_gen_glyphs.py + families.json + split_clean.json +
  split_leak2.json + split_leakvar.json + planted_truth.json. The 49,600-row
  manifest.jsonl (~9.3 MB) is REGENERABLE - run the generator; its sha is
  pinned in FIXTURE-MANIFEST.json. leakvar mechanism: the split's
  render_param_override gives family-39 test rows for classes 0-9 and
  variants 0-4 the same render parameters as family 31 = 50 PLANTED
  duplicates across the boundary with disjoint family labels (planted by
  construction via identical render params - generator metadata, NOT a
  measured rendered-pixel comparison).
- w0085/ w0085_toy_loop.py + w0085_competitor.py + planted_truth.json
  (schedule: competitor ON at steps 100-199 and 300-349; phase A steps 0-99).
  run_log.jsonl is HOST-DEPENDENT by design: the lab runs the loop on its own
  host; no sha is pinned for it. ACCEPTANCE-BASIS: the published contract
  stands UNCHANGED - the erratum that would have moved acceptance to window
  tail-density was REJECTED by the requester-side ruling (2026-10-25 12:09+).
  Measured outcome under the unchanged contract (see W0085-R2-LIMITS.md for
  the full bounded record):
  - The shipped per-step compute/wall-gap basis: the tested gap-based
    readings failed on two independent time-shared 1-vCPU hosts (R1: gap
    medians identical planted vs control; the first zero-FP gap threshold
    caught 2 of 150 planted steps; CFS alternation dominated those tests).
    Universal unsatisfiability is NOT proved.
  - R2 (CPU-clock instrumentation, schedule/seed/kernel untouched): the
    decision-clause separation WORKED in the tested runs (process-CPU/step
    constant 0.333-0.389 ms across every arm of every run on both sides =>
    constant demanded work in these tests; wall/step rising while cpu/step
    stayed flat was consistent with the controlled competitor's
    descheduling, but the off-CPU gap is not uniquely attributable to the
    competitor; input-wait yield separated in a synthetic side-test). With
    KNOWN truth boundaries both planted arms exceeded every quiet arm in
    12/12 runs across the two sides - an oracle-conditioned scoring
    comparison, NOT a detector.
  - The interface test as written (automatic recovery of every injected
    window, zero quiet false positives) was failed by every tested method:
    the best boundary-free method recovered the 100-step arm in 5/6 runs
    but the 50-step arm in only 1/6; quiet FPs remained (spawn transient;
    removable only by the tested handshake variant); rolling-window and
    CUSUM detectors failed with measured counterexamples incl. fabricated
    windows on the control run.
  - Scope of the negative: the TESTED methods failed on the TESTED 1-vCPU
    hosts. This is NOT a proof of universal impossibility; an off-CPU gap is
    not uniquely attributable to the competitor; multi-core NOT RUN.
  W-0085 therefore ships as an honest pending/failed-gap fixture: generator +
  schedule truth repaired and verified; no tested method passed the interface
  acceptance as written on the tested 1-vCPU hosts; universal
  unsatisfiability unproved; no silent contract amendment.
- w0086/ w0086_tree_exporter.py -> full-06.tar + inc-1-12/inc-2-18/inc-3-24/
  inc-4-30.tar + inc-3-24-CORRUPTED.tar + chain_truth.json. Bundle format is
  ACTUAL tar (ustar), deterministic: sorted members, mtime=0, uid/gid=0,
  uname/gname='', no pax; each tar carries an r6chain.txt header member;
  deletes are empty whiteout members .wh.<path> (overlayfs convention);
  incrementals are full per-file snapshots, last-writer-wins, NOT deltas.
  The corrupted link flips one payload byte (still a valid tar - the
  content-sha mismatch at tip 24 is the detection path). Because a later link
  can heal a corrupt earlier one (measured: good-chain tip 30 matches truth
  even when inc-3-24 is corrupted), EVERY tip must be verified; a final-only
  check passes a corrupted chain. chain_truth.json carries the true per-tip
  file sha256 maps and documents format/header/delete/incremental semantics.
- w0087/ w0087_toy_kv.py + store_fixture.json (40 jobs: 12 active, 20 returned,
  8 expired) + planted_truth.json (baseline 40 list calls, index 1, 28 closed).
- w0088/ w0088_gen_stream.py + schedule_worst_burst.jsonl +
  schedule_idle.jsonl + pace.json (REQUESTER-STATED cap: 40 tokens per 100 ms
  window, target pace 13 tokens/s) + planted_truth.json.

  Window semantics (resolves the fixed-grid vs rolling ambiguity): a
  "100 ms window" is ANY half-open interval [t, t+100 ms), not only
  grid-aligned buckets. The cap check is over all such sliding windows:
  no half-open 100 ms interval may contain more than 40 revealed tokens,
  including immediately after the 400-token burst. Grid-aligned buckets
  MAY be used for the window_rates display series, but acceptance
  (interface test max_rate <= cap) is computed over sliding windows.
  The half-open convention is load-bearing: at the exact minimum spacing
  of 2.5 ms/token a CLOSED interval admits 41 tokens. A scheduler that
  enforces the cap only on aligned buckets can pass a fixed-grid check
  while revealing 80 tokens inside one sliding 100 ms window (measured:
  grid_max 40 / rolling_max 80 on the worst-burst fixture), so
  fixed-grid-only enforcement does not meet the stated proposal.

## Rules of use

Generated inputs only; no private data, no project details. The fixture files
are generated inputs and their planted truths are fixture construction
guarantees, verified by requester-side generation runs. The W0085-R2-LIMITS.md
note is explicit measured evidence from bounded review runs on the requester
side - review evidence, not product acceptance. Labs list exact tool versions
in their pilots as the requests require.
