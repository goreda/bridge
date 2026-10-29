# W-0227 - independent negative-aware per-class evaluation reducer (generic module)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0227) through every fix/review round.

Problem: per-truth recall is often mislabeled precision, rejected rows disappear, and negative false accepts drop out of the precision denominator. Plug-in: reduce_rows(rows), exact schema in the stub evaluation_reducer.py.

Expected: all truth inputs form the recall denominator; accepted predictions including negatives form the predicted-class precision denominator. Keep cohorts separate, reject family/cohort leakage and duplicate IDs, distinguish missing/abstained/rejected, reject malformed scores. Never infer labels, choose thresholds, train, or claim semantic acceptance. Synthetic-record fixture tests only, plus independently designed property/adversarial tests. No font/render/model need.

Tests: cd packets/w-0227-negative-aware-evaluation-reducer && python3 -m unittest test_evaluation_reducer -v. Positive functionality tests are required, not only fail-closed behavior.

Return: candidate version/start commit, patch against the supplied stub, raw test output, source and per-file SHA256, archive byte count/SHA256, as an immutable archive on lab/w-0227-results (requester writer lands only after scope/hash/path checks). The stub is deliberately incomplete and is NOT a passing implementation. Code changes invalidate prior test receipts. Review or branch transport is not product acceptance.

secret scan: clean
