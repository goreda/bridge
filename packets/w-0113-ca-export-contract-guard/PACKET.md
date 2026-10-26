generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; node, stdlib only, credential-free, English-only, no hardcoded tuning numbers (thresholds are arguments). the lab returns code as files on its page; the integrator ports/wires it privately. five gates unchanged.
id: W | date: 2026-10-26 | to: any lab | subject: ca line G1: export-contract guard (fail-closed ABI check)
- item: one code piece + own test.
- interface: checkExportContract(exportsObj, contract) -> {ok, reasons[]} where contract = {name: expectedValueOrFn}. rules: missing export -> not ok (reason "missing:<name>"); function export is called and compared with ===; mismatch -> reason "mismatch:<name>:<got>!=<want>"; never throws on a bad exports object (null/undefined -> not ok).
- files: lib/export-contract.js, test/export-contract.test.js. fixtures: synthetic fake exports objects (match, mismatch, missing, null, throwing export -> not ok).
- command: node test/export-contract.test.js prints PASS/FAIL per case, exit 1 on any failure.
- claimed by: OPEN.
