# Null-calibration harness

Command-line harness for ablation threshold calibration. Follows
`docs/research/null-calibration-harness-preregistration-proposal.md` and
`docs/research/statistical-annex-proposal.md`. It has not been run on real
ledger data, and there is no real predictor-error ledger yet.

Subcommands: `oc` (operating characteristics, writes
`operating_characteristics.tsv`, `decision_input.json`, `replay_receipt.json`;
never selects a setting), `calibrate` (freezes critical values from the
family-level sign-flip null on fit/train data), `decide` (single use on a
family-disjoint decision file, pinned by the frozen file hash).

Input ledger columns: pair, family, partition, namespace, unit, plus exactly one
of (err_abs_base, err_abs_cand) absolute errors, or (resid_base, resid_cand)
signed predicted-minus-observed residuals. Both forms or neither is refused;
for signed input the absolute value is taken explicitly and the form is recorded
as error_form (frozen, replay and decision files). Endpoint d = |cand| - |base|;
negative favours the candidate.
Statistic: equal-weight mean of per-family means. All numeric settings
(confidence levels, counts, effect multipliers, seed, margin multiplier) come
from manifests as named CONVENTION fields; no defaults are supplied.

Behavior
- A level alpha is attainable only if alpha >= 2^-k for k families; otherwise
  the row is INSUFFICIENT_POWER_ADOPTION_BLOCKED with blank numerics.
- Allowed partition labels are an explicit required argument (`--allow`, no default) of `oc`, `calibrate` and `decide`; rows with any other label are refused. The manifest maps each fold role to a label.
- `oc` requires `--k-draw`: each replicate draws that many families without replacement (it must not exceed the number of families in the input), so the decision fold size can be emulated. Noise is scaled by sqrt(K0/k_draw), an approximation. `oc` tests only the bootstrap upper-bound part of the decision rule, so its rates are upper bounds for the combined rule.
- The frozen file records attained_alpha, null_patterns and null_grid_step.
- `decide` refuses any family id shared with the calibration data. The check is
  exact string equality; no instance/family mapping manifest is checked.
- The frozen critical value derives from the fit/train null dispersion. If the
  decision fold dispersion differs, it is not calibrated for it.
- `preapproved_rule_rank` is the output of the preregistered ordering rule, not
  a selection.
- `effective_coverage` is NOT_MEASURED until the ledger has a coverage column.
- The label-permutation false-positive rate shares its null with the critical
  value, so it is a sanity check only. Effect injection resamples fit/train
  family means, so the minimum detectable effect depends on that dispersion.
- The sign-flip null assumes a symmetric family-level effect distribution under
  no difference. Margin claims stay UNVERIFIABLE until a unit/gauge exists.
- Multiplicity across confidence levels is declared, not corrected.

Tests: `python3 test_nc.py` from this directory (synthetic data).
- `calibrate` requires `--k-decision` and `--n-spread`. The frozen critical value is scaled by sqrt(k_cal/k_decision) (assumes iid families with equal variance, an approximation labelled CONVENTION); the unscaled value, both family counts and the factor are stored. `decide` refuses a decision fold whose family count differs from k_decision. The factor applies only to the frozen critical value; the sqrt(K0/k_draw) factor applies only to the `oc` noise estimate.
- `crit_spread_resampled` resamples the calibration families with replacement n_spread times and stores p05/p50/p95 of the scaled critical value as a noise estimate. It makes no precision claim and does not change the rule.
- `oc` requires `--draw-mode`: `without_replacement` (primary, k_draw must not exceed the number of families) or `with_replacement` (sensitivity, conditional on the observed family means). Without replacement the replicates overlap, so the Wilson interval is too narrow; distinct_subsets is recorded beside it.
