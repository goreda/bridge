# kni-metrics 0.1.3 (vs 0.1.1), item 7: class layer held-out vs kern=0

Base: goreda/kni HEAD 38f506e3cddf98d82ded8f80bb2a7bcac031ba48 (export, tarball sha256 8f3c1fef...2363).

- gen.rs: KernPolicy gains `geom_open` (per case-stratum gate). derive_policy sets a stratum open only if the
  geometric solve's summed |solve - kern| over the font's existing pairs (zeros included) is strictly below
  the summed |kern| (writing no kern). A closed stratum yields no geometric prediction (kern stays 0).
  `KernPolicy::permissive()` stays ungated (geom_open = None). A derivation line `geom_gate` is added to the receipt.
- No new constants. No glyph, language or style specific code: the gate uses only the font's own pairs and
  the existing case/class strata.
- Examples: heldout_kern_eval (leave-one-glyph-out measurement, prints variants).
- Tests: heldout_kern_vs_zero (new); gen_crosscheck saturated case moved to the ungated policy; kern_before_after labels
  and kern-proposal.sha256 updated for the intended derivation change.
