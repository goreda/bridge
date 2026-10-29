# W-0233 - typed contour grammar property generator (seeded cases + independent oracle) (generic production-code unit)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0233) through every fix/review round.

##8 / lab1: typed contour grammar property generator

contour_properties.py: generate(seed,count)->list[contour_cases]; each case {nodes,expected_valid,tag}. Seeded stdlib generator constructs closed line/cubic rings and targeted malformed variants (0/1/3 controls per curve, controls before line, all-offcurve, nonfinite rejected separately not emitted as JSONNaN). oracle_signature(nodes)->canonical cyclic segment signature using explicit formal grammar, not a supplied codec. exercise(codec,cases)->{pass,failures}. Must find intentionally broken codecs: drops terminal controls, reverses winding, invents closing edge, loses smooth endpoint. Rotate starts across every node and compare modulo cyclic rotation. This is executable property-test infrastructure complementing unit1, not another codec; no imports of solver implementation in independent oracle. Tests demonstrate each seeded defect caught and correct reference cases pass.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
