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
