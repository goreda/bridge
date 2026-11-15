packet: W-gdb-gor-2
product pin: 4579f080d624a30bf3a87e9a4b1e718136380ed6
execution time: 2026-11-16 01:05 +03
python: 3.10.12
result: PASS for the named gate only
scope: Synthetic parser/model only. No production stop test, native execution, hardware stop or current device claim. Do not count this synthetic model as a run-proven product repair under 196s.

file: stop_model.py
sha256: 150976c64286ce224a03d5f48e0e9c9fc5d7a6f78dd9b303f94ab8b595a4061d

file: W-gdb-gor-2.stdout.txt
sha256: 5455682dec47d3a0a8861c38e3f31f076b71eabf32d80dd3cee01eb11d8378de
stdout:
```text
S1 101 -> 102 returned PASS
S2 103 -> 104 self_exit PASS
S3 105 -> 106 parent_kill PASS
S4 107 -> 108 incomplete PASS
S5 109 -> 110 unattributed_completion PASS
CAUGHT stale generation
PASS 5 synthetic stop paths; no hardware claim
```

secret scan: clean
