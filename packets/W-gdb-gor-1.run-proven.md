packet: W-gdb-gor-1
product pin: 408752f7427425c5c55c0fc55cdf6f27f06c8c40
execution time: 2026-11-16 01:05 +03
python: 3.10.12
result: PASS for the named gate only
scope: Actual pinned viewport_s4a_preservation_test.py also executed against exact source and its declared baseline: exit 0. This is a byte-preservation source gate, not native compile or pixel acceptance.

file: portable_move.py
sha256: a2899834c49593ca8af2e820b7183e393bb9395a2915f4fae438553fd7865586

file: W-gdb-gor-1.stdout.txt
sha256: 1306f865ed96871524798235168cec45b01aae12b9e3d8c2cf806343e25ccd79
stdout:
```text
CAUGHT body mutation
CAUGHT residual mutation
CAUGHT lost newline
PASS portable byte-preservation fixture and 3 negative controls
```

file: W-gdb-gor-1.product.stdout.txt
sha256: a42d74a458ca3cdb97d3256a423d0b5e4789b4d2ec99cb91d7d30d22f92c6f17
stdout:
```text
PASS S4a exact source bytes preserved, old residual byte-identical
```

secret scan: clean
