# W-0229 - qualified axis quantization + verification (explicit constraints only) (generic production-code unit 2)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0229) through every fix/review round.

## 2. Qualified axis quantization and verification

Module qualified_axis.py, apply(points,constraints,integer_export=False)->{points,changes}; verify(points,constraints)->{ok,violations}. points list[{id:str,x:finite,y:finite}]. constraints list[{axis:'x'|'y',point_ids:list[str],target:finite,evidence_pin:lowercaseSHA256}]. Caller supplies explicit role-qualified constraints; proximity/angle does not grant one. No constraints means byte-value unchanged geometry, even shallow diagonal. Only named axis coordinates may move, other coordinates and unmentioned nodes untouched. Contradictory targets for same point/axis refuse. Fractional targets exact unless integer_export=True; then deterministic documented rounding applied once. verify uses same explicit constraints and export rounding contract, never re-discovers near-axis segments. Caller qualification is data provenance, not automatic style inference. Tests: unqualified[(0,0),(1,300)] stays diagonal and verifies clean with no constraints; target.4 retained noninteger; qualified vertical/horizontal exact; unknown/duplicate IDs and malformed/bool numbers refuse; no mutation/idempotent apply.

## Delivery and review for every unit
Return real implementation plus tests (not report-only), module schema/API.md, version/start commit, patch against supplied contract stub, exact run command/output, archive byte count/SHA256/per-file pins. Reviewer writes failure cases before seeing solver code then independently executes it. Requirements versus diagnostic probes distinguished. No training/font/render assets needed. A code change invalidates earlier run receipts. Requester integrates/tests on real engine; lab tests/review/branch landing are NOT product acceptance. No new message/user permission or production deployment grant is encoded here. One ID per unit for all fixes. Existing queue >2h unconsumed-return rule checked by writer.

secret scan: clean

NOTE: requester clarification PENDING on this same id (API ambiguity, not privacy): whether verify(points,constraints) takes the integer_export rounding contract as an explicit argument or derives it; until the clarification lands the solver must NOT guess the verify rounding binding - failure cases may proceed.


secret scan: clean
