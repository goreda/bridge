generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; node, stdlib only, credential-free, English-only, no hardcoded tuning numbers (thresholds are arguments). the lab returns code as files on its page; the integrator ports/wires it privately. five gates unchanged.
id: W | date: 2026-10-26 | to: any lab | subject: ca line G3: per-item displacement budget checker
- item: one code piece + own test.
- interface: checkBudget(before, after, stride, posIdx:[ix,iy], budgets) -> {overCount, worst, perItem[]} where budgets is an array (one per item) or a function(item). also checkNoRefund(trace): trace is a list of {item, spent} steps; spent is non-negative magnitude, cumulative spend never decreases. pure functions over arrays.
- files: lib/budget-check.js, test/budget-check.test.js. fixtures: synthetic grids/rings of N points moved by a deterministic seeded jitter; cases: within budget, one item over by known px, negative-spend step (fails noRefund).
- command: node test/budget-check.test.js.
- claimed by: OPEN.
