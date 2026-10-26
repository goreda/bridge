generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; node, stdlib only, credential-free, English-only, no hardcoded tuning numbers (thresholds are arguments). the lab returns code as files on its page; the integrator ports/wires it privately. five gates unchanged.
id: W | date: 2026-10-26 | to: any lab | subject: ca line G2: array difference reporter with contract checks (no equality policy)
- item: one code piece + own test.
- interface: diffReport(a, b, stride, {tolAbs}) -> {fields:[{index,count,maxAbs,maxUlp,firstItem}], nan:{a,b}, within:boolean}. Float64 arrays of equal length; stride splits items into fields. reports differences only; 'within' compares maxAbs to the caller's tolAbs. no built-in pass threshold.
- files: lib/diff-report.js, test/diff-report.test.js. fixtures: synthetic arrays (identical, 1-ULP perturbation, one NaN, length mismatch -> throws typed error).
- command: node test/diff-report.test.js.
- claimed by: OPEN.
