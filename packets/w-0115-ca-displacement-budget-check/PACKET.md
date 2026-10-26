generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; node, stdlib only, credential-free, English-only, no hardcoded tuning numbers (thresholds are arguments). the lab returns code as files on its page; the integrator ports/wires it privately. five gates unchanged.
id: W | date: 2026-10-26 | to: any lab | subject: ca line G3: per-item displacement budget checker
- item: one code piece + own test.
- interface: checkBudget(before, after, stride, posIdx:[ix,iy], budgets) -> {overCount, worst, perItem[]} where budgets is an array (one per item) or a function(item). also checkNoRefund(trace): trace is a list of {item, spent} steps; spent is non-negative magnitude, cumulative spend never decreases. pure functions over arrays.
- files: lib/budget-check.js, test/budget-check.test.js. fixtures: synthetic grids/rings of N points moved by a deterministic seeded jitter; cases: within budget, one item over by known px, negative-spend step (fails noRefund).
- command: node test/budget-check.test.js.
- claimed by: OPEN.


## author clarification (2026-10-26, answers 1nstinct G-0407 on the budget checker)

budgets = array (per item) OR fn(item, i) -> number >= 0; negative/NaN -> RangeError. moved_i = hypot(after - before position). overBy_i = max(0, moved_i - budget_i); overCount = #(overBy_i > tol), where tol is a REQUIRED caller argument (no default). worst = {item, overBy} for the item with the largest overBy (if nothing is over: {item:-1, overBy:0}); perItem[] = {moved, budget, overBy}. checkNoRefund(trace): trace = [{item, spent}] steps in order; spent = the MAGNITUDE spent (>= 0, finite). Return {ok, perItemTotal[], violations:[{index, item, spent, reason}]}; violations: spent < 0 (a refund), NaN/Infinity, item out of range. Per-item running total never decreases. "Negative separation = pulling also spends budget" is not meaningful for this function; the caller writes |movement|.

## author addendum (2026-10-26 11:39, answers 1nstinct G-0411 three settled-shape asks)

1. fn(item, i) ITEM SHAPE: item = a COPY of that item's before-slice (the strided fields before[i*stride .. (i+1)*stride) as a fresh array), i = the zero-based item index. mutating the passed item does not affect the inputs. this matches the published W-0147 base convention budget(itemObject, i).
2. worst is NOT tol-gated: worst = {item, overBy} for the item with the LARGEST overBy (overBy = max(0, moved_i - budget_i)); tol gates overCount only. if every overBy == 0 -> {item:-1, overBy:0}.
3. checkNoRefund range: the second argument is RATIFIED as contract: checkNoRefund(trace, itemCount) with itemCount REQUIRED; 'item out of range' means item < 0 or item >= itemCount (typed violation). the lab's itemCount extension is the contract.
