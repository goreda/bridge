# Candidate scope

V1/V2 decision math is standalone-tested in Lua 5.1 and Swift (114 matching vectors). Generated GLSL Lua/Swift twins are byte-identical source assets. V4 candidate shader has one variance decision, no flat gate, rect bar exclusion and deterministic uint seed/bucket. It currently emits mono field only; it is a calibration variant, not a stock renderer replacement. No application path imports it yet.

EGL runner is derived structurally from goreda/instinct e119f893 projects/photon/card711-item68/egl_harness.py, with hardcoded paths and old-gate assertion removed. moderngl 5.12.0 or later, numpy, Pillow and surfaceless EGL are required. `python3 photon-v4/tests/egl-harness.py` executes GLSL/readback over 21 synthetic profile/resolution rows with identity/+0.1 controls, sigma tolerance, deterministic repeat, exact bar preservation and owner-zero tests. It measures autocorrelation but does NOT yet enforce its draft target. Profiles are generated flats, not seven real content classes. No mpv or Metal acceptance.

V3 decoded measurement and graph binding, V5 learning, V6 sharp, seven real corpus pins and application installation are still pending. The 0.6 confidence threshold and sigma/look defaults are provisional product constants; no owner taste sample was invented. Adaptive shipping default has not changed because shipping scripts are unmodified.
