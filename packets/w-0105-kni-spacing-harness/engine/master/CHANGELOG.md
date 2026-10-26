# kni-master changelog

## 0.2.1 (vs 0.1.0, base engine HEAD 38f506e3)
- Add `compat` module: `check_set(&[MasterGlyph])` checks a master set against master 0 (C1 name, C2 upm, C3 contour count, C4 stroke order, C5 segment-kind sequence, C6 winding, C7 node-role sequence) and runs the per-master validator on every master (V0 setup error, V1 violations).
- No numeric thresholds: comparisons are structural; validator tolerances stay per-master derived.
- Add tests/compat.rs (7 tests).
