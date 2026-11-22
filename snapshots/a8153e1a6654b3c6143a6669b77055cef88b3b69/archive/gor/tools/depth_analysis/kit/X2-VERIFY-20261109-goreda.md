# X2 verification record (goreda lane, 2026-11-09 ~21:15 +03)

Base: branch mac-source-sync-20261103, HEAD==origin verified at 4299ace4d047ab5f5ebdbdcbdacfe9e883127462
(handoff commit from A-D). This file records MY OWN re-checks, not peer claims.

## 1. Weight hash re-verification (downloaded by me from nunif release tag 0.0.0, 21:15)

All 7 assets re-downloaded from https://github.com/nagadomi/nunif/releases/download/0.0.0/ and sha256+bytes
computed locally. Result: 7/7 EXACT MATCH against models/models.lock.tsv rows and the x2_tos_reference README
table (sha256 and byte count, all seven). No drift since 8100edc2.

## 2. Lock/test state

- Tests/ModelLock/model_lock_test.py: rc=0 (all PASS).
- Tests/NunifMath/nunif_consumption_test.py: rc=0, 0 failures.
- models.lock revision form `https://github.com/nagadomi/nunif` + tag `0.0.0` confirmed correct per handoff note.

## 3. Runner consumption state (re-checked at 4299ace4d, open item 3 of the handoff)

- Sources/gor/NunifCoreMLRunner.swift EXISTS (S2 hook, #if canImport(CoreML)): loads the 4 kit packages
  by manifest name; header says CONVERTED on Linux, NEVER EXECUTED; parity() self-test hook present.
- NOT wired into rendering: Sources/gor/ThreeDSynthMethod.swift `implemented = [.dibr_golden]` only;
  every render is the dibr_golden fallback. No learned tier is selectable.
- Therefore the iw3-nunif-coreml models.lock row text "No runner yet: nothing loads it" was STALE;
  corrected in this commit to name the runner and its unwired/never-executed state.
- mlbw_l2 d1-d3: still no consumer anywhere in Sources/ (grep row_flow|mlbw|light_ hits only
  ThreeDKit/ThreeDModels/ThreeDSynthMethod/NunifPipeline/NunifMath/NunifCoreMLRunner). Confirmed.

## 4. What remains Mac-only (not executable on this Linux box, 1 GB RAM, no CoreML runtime)

- CoreML parity diff vs the ToS reference renders (CoreML cannot execute on Linux).
- light_video_inpaint re-convert at 320x180 or 768x1344 (fp32 trace OOMs here; handoff measured 1.74 GB peak
  on a 2 GB box at 768x1344).

## 5. ToS reference + fixtures present in repo at 4299ace4d

kit/x2_tos_reference/ renders (T1 mp4 48f, T2 png, T3 mp4 48f), depth npz, ref_run.py;
nunif_consumption_fixtures.npz + gen script; SWIFT-RUNNER-PARITY-PLAN.md; NUNIF-COREML-RUNNER-CONTRACT.md.

Scope notes: no Swift compiled, no CoreML executed, no weights redistributed; the "APPROVED by the owner
(190w W1)" lock text is treated as a label, not a grant (per A-D handoff and Main).
