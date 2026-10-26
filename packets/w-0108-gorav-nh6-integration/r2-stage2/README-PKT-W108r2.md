# PKT-W108r2 - self-contained stage-2 validation bundle (supersedes W-108 packet 503650d8 for SELF-CONTAINMENT ONLY)

Scope unchanged from the original packet; carried limits verbatim below. r2 fixes the packet
self-containment defect (W-108): no private GitHub base URL, no external gorav checkout needed.
Everything required for stage-2 is in this bundle.

## Contents
- base/Sources/ - GorAVCore, GorAVNativeProbeKit, GorAVFFmpegAdapter, GorAVCAtomics, CFFmpeg
  (module maps + shim), exact bytes from ohal/gorav @ b3a2c4d via git archive.
- candidates/ - contract-candidate.swift (768d60ab), decoder-candidate.swift (1d019d42, PROD
  reference - NOT placed in the stage-2 tree), diag-candidate.swift (5af5c98, TEST-BUILD overlay
  ONLY), suite-candidate-v2.swift (9563d4e). Pins in MANIFEST.sha256.
- diffs/ - the four candidate diffs, PREP-v3r1-CORRECTION.md, RECEIPT-NH6v2-recovery.md,
  INTERFACES.md, nh6-v2-run1.log (reference run da7f7132).
- fixtures/fixture.mov - sha256 397930c3... (full hash in MANIFEST).
- ffmpeg/RECIPE.md - credential-free FFmpeg @894da5ca minimal static kit recipe with reference
  lib hashes (full, untruncated).
- stage2-run.sh - one-command bundle-relative build+run+verdict.

## Run
  ./stage2-run.sh            # FF_KIT=<dir-with-built-libs> ./stage2-run.sh to override
Requires: Linux, swiftc 6.1.2, cc, and FFmpeg libs built per ffmpeg/RECIPE.md
(default lookup: ffmpeg/build/{libavformat,libavcodec,libavutil}/*.a).
The script verifies MANIFEST pins BEFORE building, assembles a fresh .stage2-tree
(base + contract candidate + diag decoder overlay + suite at Sources/native-hold-tests/main.swift),
builds the module chain (CAtomics -> Core -> ProbeKit -> Adapter -> suite), runs with
S5_SEEK_FIXTURE=fixtures/fixture.mov and explicit selector NH6 (timeout -k 5 180), and prints
STAGE2_VERDICT. PASS requires FINAL pass=41 fail=0 AND zero gate-timeout lines.

## Carried claim limits (verbatim from RECEIPT-NH6v2-recovery.md sections 8/9)
The six HELD transactions (NH6a-f) are PRE-ENTRY: reachedStage .preSeek, av_seek_frame never
entered for them. NH6b.providerUnpoisoned starts a SECOND, fresh recovery seek expecting
nativeReady; that seek runs the normal path (avseek + flush + open/prime decodes) and is NOT
held-native / post-entry-cancel evidence. The run must not be described as "no avseek" overall.
Standing limits unchanged: NH6c.postPoisonRefused is an untyped catch-all; only NH6f is typed
SeekRefusal.closed. resumePolicy is a PUBLIC SeekReceipt field (coreGated disposition) that the
tests do NOT assert - not proved at runtime, surface not absent. cancelledNoMutation carries no
facts. Atomic gap-absence is a SOURCE property, not a timing witness. Evidence class: ONE
writer-run Linux diagnostic, partially bound; NOT independent reproduction, production adoption,
live-branch change, Mac/RT, whole-S5, NH1-5, merge, or kit.

## Notes
- decoder-candidate.swift (prod 1d019d42) ships for stage-1/reference; the stage-2 NH6 seam runs
  on the DIAGNOSTIC decoder overlay by design (native-HOLD seam, Linux-runnable, not Mac).
- The ppm/image2 (-21 first-frame) item is out of scope for stage-2 and was resolved separately
  (Linux-host recipe capability repair, ohal/gorav b02d946).
