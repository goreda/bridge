# CA 77d(a) v3 overrun-receipt candidate - FAILED HYPOTHESIS, kept for history

Not accepted, not deployed, not pushed. Lineage: base a62be62 (sha256 fa19b3378af05ce6f2ca92b3e3b2d841065fa4689336023265e61148064ee777) + receipt. Sibling of v2 (09619fd74c6e02e9...), not v2 + fix.

Idea: early clamps (ink re-resolve, collective pass) park a fitting body on the wallPull box; a receipt (real - virtual offset per axis) lets wallPull/carrySide run once on the overrun the old centre clamp would have left.

What was shown (local unit level only, actual function texts loaded from the files):
- Exact damping-state equality (vx, vy, envVx, envVy, sqS) vs base for: single early clamp then wallPull (3360 sequences), fraction 0.3/0.5/0.9 multi-pass (1800), coll->ink chain without solver (12019 cells), solver on with no pair contact (single interior, single edge, solverOverlap=0 multi-cell).
- 10268 + test-effr-v3-solver-chain checks; 4 mutants killed.
What failed / limits:
- With the actual constraintSolver pair overlap push active (2-6 cells): 3378 of 12125 cells (28%) differ from base in damping state (max abs diff 3.0). Direction not systematic (cand larger 1578, base larger 1591, equal 8809). Cause: the pair push reads real positions, which differ from base; the virtual counterfactual cannot follow.
- Not run in the engine. No claim that it restores carry counts, path, max step or osc. wasm keep_in (245-256) has no mirror; parity rule open. Render path (SEP.mc) and separatorOn=0 frozen preset differ from the sim path. Receipt cleanup on spawn is by source read only (all spawns use new Cell with named fields). constraintSolver has its own centre-box clamp that was not changed.
- The A/B evidence that led here (clean 6/6 matrix, boundary witness: first difference frame 1 id 5 wp.box y 291.937 vs 292.672, carry events 6.4-7.1k -> 1.2-1.6k, dvPos 0) belongs to F70's custody (organic-walls ef7c676e...).
Reproduce: node test-effr-v3-receipt.mjs ; node test-effr-v3-solver-chain.mjs
