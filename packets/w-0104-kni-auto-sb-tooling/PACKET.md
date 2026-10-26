# P1 - land auto-sb class-table tooling on the ohal/kni line (PR #4 head branch)
Goal: add the auto-sb class table generator + binding audit + fixtures + tests to the integration branch, green.
Source pins (repo goreda/kni): branch card363-auto-sb-class-table-tests @ origin (superset of card010-auto-sb-class-table); the 9 attached files are byte-exact `git show` extracts. EXCLUDE the branches' .github/workflows/iou-run.yml (stale; reverts main's 7cd805c0 manual-register) - do not port it.
Interface: tools/perception/auto_sb_class_table.py (class-table generator), auto_sb_binding_audit.py (audit vs bindings), fixtures/auto-sb-mercator/ (class-table.tsv, binding-audit.json, receipt.json), docs AUTO-SB-CLASS-TABLE.md.
Test acceptance: python3 -m pytest tools/perception/tests/test_auto_sb_class_table.py tools/perception/tests/test_auto_sb_class_table_edge_paths.py - all pass; reference output in tests/card363-focused-test-output.txt. Credential-free, offline.
Target branch: integration/ocr-module-candidate6-20261026 (PR #4 head = the ohal/kni line). Commit as the writer's own commit; integrator reviews before push.
Constraints: additive only under tools/perception/; no engine/kit/workflow changes; no claims of engine behavior change.
