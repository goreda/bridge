# W-0220 kni 437 fit residual
state: candidate
solver lab: 1nstinct
reviewer lab: in2tinct (writes failure cases first, blind to the fix)
id: W-0220 (one id for the whole life of this problem; every round updates this id)

## problem (what fails for the user)
in the KNI fit core, an open-gate fit whose undamped Newton proposal returns None / CandidateFailed produces no fit at all: that outline span has no vector fit and falls out of the fitted output. a damped per-point proposal fallback landed on 2026-10-27 (branch card437-damped-fallback-20261027, commit 420c2280), but it is opt-in (FIT_SEARCH default is Off / closed), not production-wired, and its convergence benefit is unproved. the production path still shows: open-gate CandidateFailed -> no fit, and the residual error is not observable to the caller per span (no per-span residual is reported, so a bad fit and a missing fit look the same downstream).

## reproducer
- repo: goreda/kni, branch card437-damped-fallback-20261027 @ 420c2280c801f873dde72fb82d8b49012f7782d9 (base card437-iou-marq-alternate @ c3efcd8f).
- real source: source/src/cubic_fit.rs (sha256 7f3d0fa3...), source/src/fit_search.rs (9277b310...), source/tests/fit_search.rs (5e37af17...). these are the exact landed bytes; pins are the first 8 of sha256.
- failing input class: point configurations that drive the undamped proposal to CandidateFailed under FitSearchMode::On. the landed tests contain one such case ("open CandidateFailed -> Fitted with closed-gate bit-identical output"); the production-visible failure is the same class with the default closed gate, where no fallback runs.
- real test command: cargo test fit_search (Rust 1.99.1, run at 2026-10-27 18:05: lib 480 pass, 1 known pristine ljpeg fail unchanged; fit_search 5/5 pass; cubic 6, capture 3, float 3, overshoot 1, plausibility 1, requirements 3, economy 22, lever 7 pass).

## expected behaviour
every open-gate fit either converges within the certified residual budget or returns a typed refusal carrying the per-span residual; no silent no-fit; the residual never ratchets upward from an unconditional accept (cubic_fit.rs:208 comment); closed gates stay bit-identical.

## exact call site and interface
fit_search.rs proposal loop: SearchContext -> CandidateState (max_squared_error, dense, plausible, spans_used), FitSearchPolicy/FitSearchMode gate; cubic_fit.rs newton_step residual and the line-208 ratchet comment; the damped fallback is pub(crate), called only on undamped None/CandidateFailed.

## behaviour that must not change
certification, budget, cap, stop and closed gates: bit-identical output on every closed-gate input (closed_gate_bit_identity_sweep must stay green); identity, tool and package files untouched; the fallback stays opt-in until the owner says otherwise.

## acceptance test (from the product repo)
cargo test fit_search all green, plus a per-span residual report on the test battery showing no ratchet and no silent no-fit; curve_stress TSV+PNGs regenerate byte-identical; eacute known-fail hash unchanged. reviewer failure cases first (blind): degenerate point sets (collinear, duplicate, reversed), extreme aspect ratios, non-finite inputs, budget exhaustion, fallback ON/OFF parity on closed gates.

## roles and state
1nstinct solves: fix + regression test. in2tinct reviews: failure cases first without reading the fix (data loss, limits, rollback, recovery after error), then the review. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
