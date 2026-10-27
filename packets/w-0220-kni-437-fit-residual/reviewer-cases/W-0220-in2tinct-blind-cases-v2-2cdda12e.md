# W-0220 in2tinct blind failure cases v2 (kni 437 fit residual)
History: v1 frozen earlier, sha256 c2cca288caad2e0ee92e8fbb67521ee5c80be5b07a51168ea18ce5b2603161db. v2 only re-labels tiers and fixes wording; vectors unchanged. Still no source/fix/test/1nstinct design read.

## Blindness statement
Read: only W-0220-PROBLEM-0004ed49.md (published PROBLEM contract, sha256 fee80938d2b8977c267c7f120c75601e97a7f0281204828f1c02c041ff6e6622, commit 7216b03974ab11459bd0e7eb06d6ba975c248bcb). It describes the existing damped fallback in words; it has no code.
Not read: any implementation bytes, tests, fix, or 1nstinct design. Not claimed: that we are unaware the damped per-point fallback exists. The contract told us.
Status of every case: PROPOSED. Nothing was executed. The full crate is absent, so cargo test from three files was not possible. The adapter from abstract points to the real API (SearchContext, CandidateState) is unknown to us; the solver maps it.

## Tiers
HARD = stated in the PROBLEM contract text. PROPOSED = our authored stress/metamorphic expectation, NOT contract, NOT an acceptance gate. Tolerances and checks below the HARD list are authored by us.

## HARD gates (from PROBLEM contract wording)
H1 Open-gate fit either converges within the certified residual budget or returns a typed refusal carrying the per-span residual; no silent no-fit. (We name no API type. For non-finite input the residual may be undefined; see P4.)
H2 The residual never ratchets upward from an unconditional accept (cubic_fit.rs:208 comment). Exact metric is the contract's ratchet metric, which we have not seen. We do NOT claim per-span monotonic across all steps.
H3 Closed gates stay bit-identical: compare EXACT bytes against the base pin named in PROBLEM, c3efcd8f (verified present in PROBLEM text, not invented), and against the branch commit 420c2280. closed_gate_bit_identity_sweep stays green.
H4 Certification, budget, cap, stop rules unchanged; identity/tool/package files untouched; fallback stays opt-in.
H5 Acceptance list in PROBLEM: cargo test fit_search green, per-span residual report, curve_stress byte-identical, eacute known-fail hash unchanged.

## PROPOSED expectations (authored, not contract)
P1 No panic and no infinite loop; work bounded by the existing budget/cap.
P2 Non-finite input: explicit rejection with a structured reason and residual marked undefined (not a NaN numeric). Replaces the earlier "finite residual" wording. A NaN candidate must not be accepted as an improvement.
P3 Determinism: same input twice gives identical bytes (bit-determinism is our proposal).
P4 Metamorphic checks, tolerances authored by us: reversal residual equal within 1e-9 relative; translation by large offset within 1e-6 relative; idempotent refit does not raise residual; neighbour spans byte-identical to fitting alone. Do not harden into contract.
P5 ON/OFF parity: byte-identical only for inputs where the fallback is NOT invoked and gate config is the same. Any "fallback ON" run needs an API adapter first; no claim without it.
P6 Work bound (old C17): no default is authorized. The bound with fallback must be established from the budget contract; we state no "base + constant".
P7 Fallback does not worsen the accepted residual (stated as H2 only to the extent the contract's ratchet metric covers it).

Mapping of old labels: H1->H1, H2->H2 (qualified), H3->H3, P1/P2->P1+P2, P3->P3, P5->P5, H4->H4.

## Cases
Coordinates are (x,y) f64. "eps" = f64::EPSILON. All gate=open unless stated.

C01 closed-gate bit identity, failing-class input
 input: any point set that makes undamped return CandidateFailed (take from landed case), mode Off.
 procedure: run Off on branch and on base; hash outputs.
 oracle: H3. Outcome may be no-fit (that is existing behaviour) but bytes equal.
 must not change: closed_gate_bit_identity_sweep stays green.
C02 fallback ON/OFF parity where undamped succeeds
 input: 20 well-conditioned smooth arcs (circle quarter, sine, S-curve), n=8..64.
 oracle: P5 byte-identical ON vs OFF.
C03 collinear
 input: [(0,0),(1,1),(2,2),(3,3),(4,4)]; also horizontal [(0,0)..(4,0)] and vertical.
 oracle: H1,P1. Fit is a straight cubic with residual <= 1e-12 or typed refusal. No division by zero from zero curvature or singular Newton Jacobian.
C04 near-collinear
 input: C03 with y offsets of +-1e-9, +-1e-12 alternating.
 oracle: H1,H2,P1. Residual reported is not smaller than true residual (recompute independently).
C05 all points duplicate
 input: [(5,5)]*6.
 oracle: typed refusal or zero-length degenerate fit with residual 0; no NaN tangent (zero-length normalise).
C06 consecutive duplicates
 input: [(0,0),(0,0),(1,2),(1,2),(3,3),(4,1)].
 oracle: H1,P1. Zero chord lengths must not enter parametrisation as divide-by-zero.
C07 two-point and one-point spans
 input: [(0,0),(1,1)]; [(0,0)].
 oracle: typed refusal or exact line; never index panic.
C08 reversed order
 input: curve P and reverse(P) for 5 smooth curves.
 oracle: residuals equal within 1e-9 relative; fitted curve is the same set reversed; both Fitted or both Refused.
C09 closed loop duplicate endpoint
 input: circle points with last == first.
 oracle: H1,P1; endpoint tangent handled.
C10 spike / backtrack
 input: [(0,0),(1,0),(2,0),(1,0),(0,0)] and [(0,0),(2,0),(1,0),(3,0)].
 oracle: H1,P1. Refusal acceptable; silent drop is not.
C11 extreme aspect ratio
 input: x in [0,1e9], y in [0,1e-9] sine-like; and transpose; and x scale 1e-9, y scale 1e9.
 oracle: P1/P2. Residual reported in a unit consistent with the certified budget; refusal carries the per-span residual (finite here, PROPOSED). Squaring (max_squared_error) must not overflow to inf: check 1e154-magnitude errors separately in C13.
C12 large coordinates, small features
 input: base offset (1e8,1e8) plus a unit-scale arc.
 oracle: cancellation does not make residual 0 falsely. Compare to the same arc at origin; residual within 1e-6 relative of it (f64 loss expected, must be reported not hidden).
C13 overflow in squared error
 input: points at 1e160 magnitude, curve fit.
 oracle: P1/P2. No inf accepted as "<= budget"; inf is treated as failure, not pass (inf <= x is false, but NaN comparisons are also false: confirm ratchet check does not accept on NaN).
C14 non-finite inputs
 input variants: one NaN x; one +inf y; one -inf; all NaN; NaN in last point only.
 oracle: explicit rejection with structured reason and undefined residual (P2). Never Fitted. Never panic. Residual not a NaN number.
C15 NaN residual poisoning
 input: well-formed points where a proposal yields NaN (force via 0/0 tangent case C05).
 oracle: NaN candidate is rejected; accepted best residual unchanged (H2). Check the comparison direction: `new < best` false with NaN is correct, `!(new >= best)` accepts NaN.
C16 budget exhaustion
 input: hard curve (high-frequency sine, 12 points per period, 5 periods) with budget = 1 step, then 0 steps, then cap = 1 span.
 oracle: typed refusal with per-span residual of the best accepted state (or initial); fallback does not run past the budget; H4.
C17 fallback consumes budget
 input: a C01 input in open mode with budget exactly enough for undamped only.
 oracle: fallback either counted against the same budget or documented not; total report actual work with fallback; bound must be derived from the budget contract (P6), no default assumed.
C18 fallback also fails
 input: C05/C10 with open gate.
 oracle: H1: typed refusal carrying residual, not None. Distinguish "no fit" from "bad fit" (the stated production symptom).
C19 fallback worsens residual
 input: curve where undamped initial guess has residual R0 and damped step would reach R1 > R0.
 oracle: H2/P7: output residual <= R0 or refusal; never R1.
C20 plausibility / dense flags
 input: fit with low residual but implausible shape (loop, cusp inside span), and dense=false.
 oracle: plausible=false is not overridden by fallback; spans_used does not exceed cap.
C21 per-span residual observability
 input: a 10-span outline, spans 3 and 7 forced to fail.
 oracle: report has 10 entries; failed spans distinguishable from fitted by type; entries for good spans equal their independent recomputed residual (+-1e-9 relative).
C22 repeat / idempotence
 input: C01 input, run fallback twice and refit the output.
 oracle: P3; second pass does not increase residual.
C23 mixed outline recovery
 input: outline with spans [good, failing, good].
 oracle: failure of the middle span does not alter bytes of the neighbours (compare to fitting them alone). No shared mutable state leaking (e.g. cached tangent, scratch buffer).
C24 mode switch in one process
 input: run On, then Off, then On in one process.
 oracle: Off result bit-identical to a fresh-process Off (no static/global state leak).
C25 regression guards (not new)
 curve_stress TSV+PNGs regenerate byte-identical; eacute known-fail hash unchanged; lib known pristine ljpeg fail remains the only failure.

## Machine vectors (JSON, abstract points; mapping to the crate API is the solver's)
{"id": "C03a", "name": "collinear_diag", "points": [[0, 0], [1, 1], [2, 2], [3, 3], [4, 4]], "gate": "open", "oracle": "fit_or_refuse_finite", "executed": false}
{"id": "C03b", "name": "collinear_horiz", "points": [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0]], "gate": "open", "oracle": "fit_or_refuse_finite", "executed": false}
{"id": "C03c", "name": "collinear_vert", "points": [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]], "gate": "open", "oracle": "fit_or_refuse_finite", "executed": false}
{"id": "C04", "name": "near_collinear", "points": [[0, 1e-09], [1, -1e-09], [2, 1e-12], [3, -1e-12], [4, 0]], "gate": "open", "oracle": "fit_or_refuse_finite", "executed": false}
{"id": "C05", "name": "all_dup", "points": [[5, 5], [5, 5], [5, 5], [5, 5], [5, 5], [5, 5]], "gate": "open", "oracle": "refuse_or_zero_len_no_nan", "executed": false}
{"id": "C06", "name": "consec_dup", "points": [[0, 0], [0, 0], [1, 2], [1, 2], [3, 3], [4, 1]], "gate": "open", "oracle": "fit_or_refuse_finite", "executed": false}
{"id": "C07a", "name": "two_point", "points": [[0, 0], [1, 1]], "gate": "open", "oracle": "exact_line_or_refuse", "executed": false}
{"id": "C07b", "name": "one_point", "points": [[0, 0]], "gate": "open", "oracle": "refuse_no_panic", "executed": false}
{"id": "C10a", "name": "backtrack", "points": [[0, 0], [1, 0], [2, 0], [1, 0], [0, 0]], "gate": "open", "oracle": "refuse_or_fit_reported", "executed": false}
{"id": "C10b", "name": "backtrack2", "points": [[0, 0], [2, 0], [1, 0], [3, 0]], "gate": "open", "oracle": "refuse_or_fit_reported", "executed": false}
{"id": "C11a", "name": "aspect_wide", "points": [[0, 0], [250000000.0, 5e-10], [500000000.0, 0], [750000000.0, -5e-10], [1000000000.0, 0]], "gate": "open", "oracle": "finite_residual_unit_consistent", "executed": false}
{"id": "C11b", "name": "aspect_tall", "points": [[0, 0], [5e-10, 250000000.0], [0, 500000000.0], [-5e-10, 750000000.0], [0, 1000000000.0]], "gate": "open", "oracle": "finite_residual_unit_consistent", "executed": false}
{"id": "C12", "name": "big_offset", "points": [[100000000.0, 100000000.0], [100000001.0, 100000001.5], [100000002.0, 100000001.8], [100000003.0, 100000001.5], [100000004.0, 100000000.0]], "gate": "open", "oracle": "residual_not_falsely_zero", "executed": false}
{"id": "C13", "name": "huge_mag", "points": [[0, 0], [1e+160, 1e+160], [2e+160, 0], [3e+160, -1e+160], [4e+160, 0]], "gate": "open", "oracle": "no_inf_accepted", "executed": false}
{"id": "C14a", "name": "nan_x", "points": [[0, 0], ["NaN", 1], [2, 2], [3, 1]], "gate": "open", "oracle": "refuse", "executed": false}
{"id": "C14b", "name": "inf_y", "points": [[0, 0], [1, "inf"], [2, 2], [3, 1]], "gate": "open", "oracle": "refuse", "executed": false}
{"id": "C14c", "name": "neg_inf", "points": [[0, 0], [1, 1], ["-inf", 2], [3, 1]], "gate": "open", "oracle": "refuse", "executed": false}
{"id": "C14d", "name": "all_nan", "points": [["NaN", "NaN"], ["NaN", "NaN"], ["NaN", "NaN"], ["NaN", "NaN"], ["NaN", "NaN"]], "gate": "open", "oracle": "refuse", "executed": false}
{"id": "C14e", "name": "nan_last", "points": [[0, 0], [1, 1], [2, 2], ["NaN", 0]], "gate": "open", "oracle": "refuse", "executed": false}
{"id": "C16", "name": "hf_sine_budget", "points_gen": "x=i,y=sin(2*pi*i/12), i=0..60", "budgets": [1, 0], "cap_spans": [1], "oracle": "typed_refusal_with_best_residual", "executed": false}
{"id": "C08", "name": "reversal_pairs", "gen": "reverse each of: quarter circle r=1 n=9; sine one period n=13; cubic x^3 n=9; parabola n=7; S-curve n=11", "oracle": "residual_equal_1e-9_rel", "executed": false}
{"id": "C02", "name": "parity_on_off", "gen": "20 smooth arcs n=8..64", "oracle": "byte_identical_ON_OFF", "executed": false}

## Authored limits
- Proposed only; none executed. No crate, no cargo, no private GitHub access (an unauthenticated 404 does not show the reason).
- Only H1-H5 come from the contract. Everything under PROPOSED, all tolerances (1e-9, 1e-6, 1e-12) and case oracles beyond H, are authored by us. Nothing is measured.
- Input shapes are abstract. Closed-gate and budget cases (C01, C16, C17, C24) need real fixtures from the solver.
- No fonts, licensed assets, user data, accounts, money, credentials, or outside publication used.
- Not product acceptance; owner closes it. Later independent review after main's release is a separate step.
