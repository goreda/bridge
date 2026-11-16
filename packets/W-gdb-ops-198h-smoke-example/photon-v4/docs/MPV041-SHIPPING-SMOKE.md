# Linux mpv 0.41 source and dynamic shipping smoke

Owner-verified capability rows: unchanged. M1 delivered: no.

These are executable Linux proofs, not the owner Mac, built app bundle, Darwin, HDR or Metal acceptance. The exact binary and release asset SHA are in `mpv041-binary.json`.

## Executed

- `MPV=/path/to/mpv041 python3 photon-v4/tests/mpv041-shipping-smoke.py`
  loads complete modified photon, grain and sharp scripts together on `gpu-next`, verifies both shader paths present, rejects Lua/parser/compiler errors, checks a grain HUD round-trip, then mutates the real strength callback on the same loaded shader. Grain sigma 0.009992706, owner zero exactly 0, double strength 0.019940140. Exit 0. Pixel panel inspected: visible fine grain, flat zero, visibly stronger double grain.
- `MPV=/path/to/mpv041 python3 photon-v4/tests/mpv041-stock-proof.py`
  uses the unadapted generated PARAM multipass shader. Sigma 0.010007310, owner zero exactly 0, nonconstant source-bin case 0.003600527. Exit 0.
- `PHOTON_MPV_LABEL=mpv0.41.0 PHOTON_SOURCE_RECEIPT=/tmp/photon-mpv041-host-source.json MPV=/path/to/mpv041 python3 photon-v4/tests/mpv-host-source.py`
  verifies a +0.2 output shader changes displayed pixels while source sigma stays 0.011683. Source uses exact document/seek fencing and records the capture position interval; it has no exact decoded frame serial. State directory created under isolated XDG_STATE_HOME; HUD reports learned x1.000 n=0. Missing bpp/mono/animation/source size are explicit unknown masks, not measured zeroes. Exit 0.

The 0.41 `gpu` VO still rejects PARAM. The tested dynamic shader path is `gpu-next` with software GL explicitly enabled. Dithering is off in pixel acceptance to avoid output dither masquerading as grain.

## Still open

Continuous sharp cap calibration/application; source size fit; HDR decoded capture; V7 autocorrelation width targets and corpus provenance/taste acceptance; full native graph/P22 consumer; Darwin/built-bundle feature gate. This source overlay remains a partial replacement and must not be delivered as V1-V7 complete.
