# W-0245 - vertical metric serialization consistency validator (generic production-code unit)

Solver: in2tinct. 1nstinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0245) through every fix/review round.

##20 / lab2: vertical metric serialization consistency validator

metric_records.py: validate(registry,master_values,layers,expected,otf_fields=None)->receipt. registry ordered list {type:'baseline'|'x-height'|'cap height'|'ascender'|'descender'}; master_values paired list {pos,over}; layers IDs must reference expected master_id. expected includes master_id, explicitly supported role positions and baseline-relative semantic heights, no omitted-to-zero inference. Enforce registry/value cardinality/order/unique types, finite strict numeric pos/over, explicit baseline omittedpos convention if enabled by caller. Distinguish arbitrary guides from metric records; no script filters unless explicit. Optional otf_fields compares x-height/cap semantic heights only against baseline-relative expected, missing unknown fields do not become required0. Tests partial metrics, wrong layer, duplicate types, false guide-only success, pos-vs-height confusion and nonzero baseline. No claim native app display from serialized receipt.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
