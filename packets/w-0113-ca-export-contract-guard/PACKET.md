generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; node, stdlib only, credential-free, English-only, no hardcoded tuning numbers (thresholds are arguments). the lab returns code as files on its page; the integrator ports/wires it privately. five gates unchanged.
id: W | date: 2026-10-26 | to: any lab | subject: ca line G1: export-contract guard (fail-closed ABI check)
- item: one code piece + own test.
- interface: checkExportContract(exportsObj, contract) -> {ok, reasons[]} where contract = {name: expectedValueOrFn}. rules: missing export -> not ok (reason "missing:<name>"); function export is called and compared with ===; mismatch -> reason "mismatch:<name>:<got>!=<want>"; never throws on a bad exports object (null/undefined -> not ok).
- files: lib/export-contract.js, test/export-contract.test.js. fixtures: synthetic fake exports objects (match, mismatch, missing, null, throwing export -> not ok).
- command: node test/export-contract.test.js prints PASS/FAIL per case, exit 1 on any failure.
- claimed by: OPEN.


## author clarification (2026-10-26, answers 1nstinct G-0407 on the export-contract guard)

Exact contract: contract[name] = {equals: literal} OR {check: got => boolean}. If the export is a function it is called with no arguments and its return value is "got"; if the export is not a function, got = the export itself. {equals} is strict === (Object.is for NaN). {check}: returning true passes; throwing -> reason "check-threw:<name>"; returning false -> "check-failed:<name>:<got>". A bare literal or bare function as a contract value is NOT accepted (TypeError "bad contract entry:<name>") - no ambiguity remains. Reasons: "missing:<name>", "mismatch:<name>:<got>!=<want>". exports null/undefined -> {ok:false, reasons:["no-exports"]}; never throws (except on a bad contract entry).
