# Lab packet: 191c R4 acceptance - roll fusion under head roll (real mpv)

Worker: B3-1. Branch: b3/191c-r-fusion (publisher files). Lab: 1nstinct.
Date: 2026-11-21. Prepared after static verification (test v3, see bottom).

## Source under test
- Repo/tree: zuellue/gorav-native-ci @ 2ca10de8ab767d8a24d8c3f4b481e5d6984701e0
- Shader: payload/gor/Resources/vendor/mpv/scripts/vr180-look.lua
  (gor.tsv path: payload/gor/Resources/vendor/mpv/scripts/vr180-look.lua)
- Roll-relevant code: stereo_disparity_axis ~1667, stereo_pair_uv ~1675,
  stereo_partition ~1700, flat-SBS chain 1759-1834, flat_mono 1815-1833,
  native baseline shift ~1916-1919. Lua pushes vr_roll and vr_head_roll from
  the same filtered pose p[4] (lines 647-660).

## Invariant (S10)
1. Equation: e_v = (p_R - p_L) . a_perp = 0, a = (cos th, sin th),
   a_perp = (-sin th, cos th), th = filtered head-roll pose (rollSign convention).
2. Hardware scale (M1 Air, 2560 px @ 227 ppi = 286 mm): a screen-horizontal
   separation S=143mm would give |e_v| = S sin th = 12.5mm @5deg, 24.9mm @10deg.
   Comfort tolerance: |e_v| <= 1 px at 2560x1600.
3. Static model says the current shader PASSES (all paths exact). This run is
   the real-GPU acceptance gate. If it FAILS, the static port missed real
   pipeline behavior (GPU dFdx granularity, clamp01, blending) - report numbers.

## Protocol
1. Synthetic SBS source: 32:9 packed (2560x800 per eye pair class is fine),
   per-eye aspect 16:9. Place a 3x3 grid of high-contrast cross markers per eye
   at eye-uv (0.2/0.5/0.8)^2. Right-eye markers offset by disparity delta in
   {-2%, 0, +2%} of eye width (horizontal, packed-x = eye-uv delta / 2).
2. Run mpv with vr180-look.lua, flat-SBS mode, defaults (fov 135, no yaw/pitch,
   no head x/y, no surface override), output surface 2560x1600.
3. For each theta in {-30,-15,-5,0,5,15,30} deg: inject the roll pose through
   the SAME input path production uses (script-message pose or the pose test
   hook; document which), settle, capture a frame.
4. Locate markers per eye (template match), compute p_L/p_R in px, then
   e_v = (p_R - p_L) . a_perp for every marker and disparity.
5. PASS: max|e_v| <= 1 px at every angle. Also record clipped/missing markers
   (partition gap losses) per angle - expected none for interior markers.
6. Repeat for flat_mono (2D->3D preview) mode with the same marker grid and
   default d3 gain; and for native 180 mode with a synthetic VR180 marker pair.
7. Cross-eyed mode: one run at +15/-15 deg with the production rollSign path
   to confirm the sign convention (PASS = same 1px bound).
8. theta=0 regression: capture must be pixel-identical to the current shipping
   build at theta=0 (golden frame diff = 0) - guards future roll changes.

## Report back
Table max|e_v| (px) per angle per mode, clipped-marker counts, mpv version,
GPU, build sha, command lines, raw captures path. Verdict PASS/FAIL vs 1px.

## References
- Plan: goreda/instinct docs/plan/191c-quality-tiers-stereo-fusion.md (R0/R1/R4)
- Static test: test-191c-roll-invariant.py v3
  sha256 8a2fff457862ca568468b744693a7b6e23c6cb50b91f985f7ce1bce9271c6f4a
  (PASS on the ported math; run: python3 test-191c-roll-invariant.py, exit=0)
- Note: the pre-199u test-vr-flat-glsl.py no longer exists in the current tree;
  this packet replaces it for the roll-fusion acceptance.


GO: 1nstinct, 199bd item 4, November 21 2026 18:52 +03.
Start the following three code tasks now on b3/191c-r-fusion. This is a coding assignment, not a capacity question. Return executable code and tests, not a plan or receipt. The three files below are new files to add under packets/191c-roll-fusion/; keep their interfaces together on this branch. Product consumer: 191c R4 roll-fusion acceptance. These tasks turn the existing manual protocol into a reproducible real-mpv test, so the product lane can fix measured fusion defects rather than rely on a static model.

Task 1: synthetic marker generator.
file: packets/191c-roll-fusion/generate_roll_markers.py
change: implement deterministic synthetic SBS, half-SBS, top-bottom and mono marker fixtures. Emit paired marker IDs, eye-local coordinates, signed disparity, dimensions and content hashes in a machine-readable manifest. Use only generated pixels, no user captures or licensed assets. Build the protocol's 3x3 grid with -2%, zero and +2% disparity, and a synthetic native VR180 case with its coordinate mapping stated. Keep generation independent from the capture/scoring implementation.
test: add test_generate_roll_markers.py. Assert reproducible byte hashes; correct dimensions and marker correspondences; both disparity signs and zero present; half-SBS/TB coordinate conversion correct; invalid sizes and overlapping/unresolvable markers rejected. Run tests in this return. A model-generated PASS is not a real-mpv PASS.

Task 2: production-input mpv capture runner.
file: packets/191c-roll-fusion/run_roll_capture.py
change: implement a Linux mpv runner using the actual vr180-look.lua at zuellue/gorav-native-ci 2ca10de8ab767d8a24d8c3f4b481e5d6984701e0, path payload/gor/Resources/vendor/mpv/scripts/vr180-look.lua. Verify its hash. Inspect and use the actual registered production pose input, do not invent or directly set a different transform. Capture 2560x1600 frames at -30,-15,-5,0,5,15,30 degrees and crossed +/-15 for the fixture modes. Record injected pose, effective shader options, actual renderer/GPU, mpv version, command, source hash, capture hashes and explicit errors. Synchronize on frames/options rather than a fixed sleep. Keep the zero-roll baseline separate and bind it to the exact baseline shader. Do not start Codemagic or mutate the owner's machine.
test: add test_run_roll_capture.py for protocol serialization, angle/mode completeness, timeout/nonzero mpv/missing capture/stale option refusal. Then run the real Linux mpv path when available. If renderer support is absent, return the runnable code and exact error, never synthetic captures presented as rendered output. Software rendering must be labeled software, not Mac/GPU acceptance.

Task 3: measured pixel scorer and fusion regression.
file: packets/191c-roll-fusion/score_roll_fusion.py
change: implement marker matching from captured pixels with explicit image-y versus screen-y convention, eye assignment and a_perp sign. Compute per-marker e_v, mode/angle maxima, unmatched/clipped counts and zero-roll pixel diff. Consume the generator manifest and capture index. Missing markers, malformed metadata or incomplete angles cannot pass. Produce a nonzero exit on failed acceptance, not merely a report field. Expose native results separately from preview results. If the real run reveals a production defect, return the smallest named diff to stereo_pair_uv / stereo_partition / stereo_disparity_axis or the flat preview sampling in vr180-look.lua, backed by that failing capture and a fixed run; do not change working native geometry speculatively.
test: add test_score_roll_fusion.py with known pixel-space pairs along the eye axis at every angle, a deliberate screen-horizontal mutant that fails under roll, crossed-sign and image-y mutants, >1px vertical error, missing marker, duplicate marker, incomplete angle set and changed zero-roll pixel. Run this scorer on the actual captures from Task 2. Preview limit is max abs(e_v)<=1px; zero-roll comparison is exact. Native baked-disparity measurements are a regression result, not a new all-path 1px approval.

Source correction for implementation: the pinned source was read before this GO. Actual flat preview sampling is 1822-1827, native optical-centre rotation is 1919-1928, and native split remains screen-aligned. The older packet's line descriptions and static all-path PASS are not evidence of current rendered behavior. The referenced 191c plan distinguishes native residual disparity from synthetic-preview fusion. Report native raw measurements and preserve its existing behavior; do not silently make the packet's blanket 1px line a new native design requirement.
Return: branch commit plus code patch/full files, exact test commands/exits and real capture/scorer outputs. No capacity questions, heartbeat or receipt-only commit. No deployment, pipeline dispatch, native acceptance or release permission is added by this GO.
secret scan: clean
