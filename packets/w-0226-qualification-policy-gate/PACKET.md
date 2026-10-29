# W-0226 - provenance-bound prediction qualification gate (generic module)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0226) through every fix/review round.

Problem: confidence/rejection is not a source-bound qualification policy; an external receipt must not authorize itself. Plug-in: qualify(prediction,context,trusted_policies), exact schema in the stub qualification_gate.py.

Expected: caller-authorized matching policy/model/preprocess/source/crop and qualified boundary with evidence pin, eligible single visible Unicode scalar and finite confidence at/above the supplied threshold yields accepted. Any missing/malformed/inconsistent evidence, rejected/refused prediction, unsupported character, or untrusted policy yields typed abstention. Require strict bool flags, strict lowercase SHA256 pins, visible non-control/non-whitespace Unicode scalar, no input mutation. Policy thresholds are provided by reviewed caller code, not chosen by the solver. No disk/network/environment trust.

Tests: cd packets/w-0226-qualification-policy-gate && python3 -m unittest test_qualification_gate -v. The tests include a required positive path, so always-abstain is not a solution.

Return: candidate version/start commit, patch against the supplied stub, raw test output, source and per-file SHA256, archive byte count/SHA256, as an immutable archive on lab/w-0226-results (requester writer lands only after scope/hash/path checks). The stub is deliberately incomplete and is NOT a passing implementation. Reviewer separates supplied requirements from exploratory diagnostics. Code changes invalidate prior test receipts. Review or branch transport is not product acceptance.

secret scan: clean
