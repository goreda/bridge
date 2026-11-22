# Player backend seam (block 189)

mpv remains the default and the only active backend. `GOR_ENGINE=gorav` requests the GorAV admission stub, which logs the refusal and falls back to the unchanged mpv launch. No GorAV package is linked until native E1 admission passes; while admission fails, the app menu `engine > gorav` row is grayed out (owner 2026-11-08) and `engine > mpv` carries the checkmark. Reopen gor after any engine change for rollback. A valid GOR_ENGINE environment value overrides the saved preference on process startup; the in-process menu overrides it for that run.

`GOR_ENGINE=gorav bash build.sh --selftest-full` runs the optional GorAV section, while t1/l1-l4 always run with mpv. The optional section does not alter lifecycle counters or delivery-gate183. With no confirmed E1 entry point it prints `E1 asserts: not yet on trunk`, never PASS. Once an entry point is confirmed, set `GORAV_ENGINE_ROOT` to the checkout and `GORAV_E1_ASSERTS` to the absolute shell assertion script path. The hook runs that exact file in the checkout, retaining its output and exit status. It does not fetch, install or assume a package build proves E1.

Source checked: goreda/gorav branch gorav/engine at b8e997007c8f415b9ccb4632e27eabea707eb950. Its Package.swift exposes GorAVEmbeddedShell; `.github/workflows/engine-macos.yml` builds the native embedded target plus subtitle-srt-tests. No docs/NOW, docs/OPS or E1 assertion entry point was found at that SHA. This source read does not qualify the package.

`python Tests/PlayerBackend/run.py` compiles the production Foundation-only seam and tests selection, fallback and rollback, plus absent/success/failure E1 hook behavior with boundary fixtures. Linux only, not native macOS playback or t1/l1-l4 verification.
