# arch-198w L2 - Adversarial review: variance-gate removal in 629d4fb

Reviewer: in2tinct (this Instinct). Date: 2026-11-17. Bridge tip under review: `fb828d25d5d1910f08e0c43c0b983d2d28ce1b32`.
Artifact under review: `packets/198w-in2tinct/629d4fb-grain.diff` (7944 bytes, sha256 `6a935915cb104fe0461713ed2f56a7917f73691fa2d33eab977943a809045ccf`), commit `629d4fb9421066402b5df410faa138653b5e2358` ("U-G1 Class S: preserve interior flat grain, nonzero floor and visible amount").

## Scope and provenance

- Public diff bytes only. photon-grain.lua remains under license hold (receipt 338421ea); the held private file was never read, mirrored or forwarded. Everything cited below is visible in the Ops-published diff; line numbers refer to lines of that diff file.
- Executed evidence comes from an independent re-implementation of the diff's mask/gate logic (the four `ug1_*` stages and the final gate) in plain GLSL passes, run surfaceless on Linux Mesa llvmpipe via EGL, with the REMOVED 2x2 variance gate run alongside for old-vs-new discrimination. Rig: `ug1_masks.py`, sha256 `842461ae80a9ec088891f8977c794cb19394149dfd4e5b14cab6aa8bad7c8abf`, fail-closed, exit 0 with all internal expectations met. Synthetic inputs only.
- This is not a native mpv run, not Darwin, not GPU-pixel acceptance, and not a verdict on the shipped shader's full grain path (the bucket/grain synthesis code is not in the public diff and was not touched).

## What the change does (from the diff)

1. Adds four reduction stages: `ug1_row_black` / `ug1_col_black` mark rows/columns whose every pixel is exactly `vec3(0.0)` (diff lines 19-45; equality test at lines 27 and 42). `ug1_row_edge` / `ug1_col_edge` then mark rows/columns connected to an image edge through an unbroken run of black rows/columns (lines 47-75).
2. Removes the 2x2 luma-variance letterbox gate (deleted lines 88-98: `luma_gain *= smoothstep(0.0, 1e-30, var)`) and replaces it with: pixel exactly black AND (edge-connected row OR edge-connected column) => `luma_gain = 0.0` (lines 99-103).
3. Removes the shader-side source-noise attenuation `adapt *= 1.0 - smoothstep(0.05, 0.35, noise) * 0.5` (deleted line 107) with the comment "U-G1: source-noise attenuation is applied once, by Lua." (line 108). No Lua hunk in this diff adds that attenuation.
4. Switches gr_add_shader/gr_remove_shader from `set_property_native("glsl-shaders", ...)` to `change-list` operations wrapped in a `common.recovery.suspended` guard (lines 124-155), and adds a hard top-level `require('photon-shader-recovery')` (line 176) watching `sourceSHA256 5b96daf329ca...`.
5. Adds a HUD "grain effective amount / size" OSD overlay (lines 162-168).

## Executed old-vs-new discrimination (synthetic, llvmpipe)

`gain` is the gate multiplier: 1 = grain passes, 0 = grain suppressed. Table is verbatim rig output.

```
case                                         region             NEW_gain OLD_gain
A clean letterbox, flat interior             top_bar               0.000    0.007
A clean letterbox, flat interior             interior              1.000    0.000
B +stray 1/255 pixel at bar row 100          bar_above_stray       0.000    0.000
B +stray 1/255 pixel at bar row 100          bar_below_stray       1.000    0.026
B +stray 1/255 pixel at bar row 100          interior              1.000    0.000
C interior black rect (not edge-connected)   black_rect            1.000    0.000
C interior black rect (not edge-connected)   interior             1.000    0.000
D full-black frame (fade)                    whole                 0.000    0.000
E 16x16 all-black crop                       whole                 0.000    0.000
F near-black bars at 1/255                   top_bar               1.000    0.007
F near-black bars at 1/255                   interior              1.000    0.000
H flat clipped-white frame                   whole                 1.000    0.000
```

Case A confirms the intended fix: flat interior keeps grain under the new gate (OLD killed it, gain 0.000) while clean bars stay suppressed. The remaining cases are where the adversarial findings live.

## Inputs where grain can still vanish (packet ask), each with a fixture

1. **Very small all-black crops / thumbnails (executed, case E).** Every row and column of a tiny all-black surface is edge-connected by construction, so the whole crop is masked: grain = 0. A 16x16 black crop is indistinguishable from letterbox under this rule. Fixture: crop-size sweep of all-black surfaces (1x1, 4x4, 16x16, 64x64) asserting the masked fraction, with the intended policy per size made explicit.
2. **Full-black frames / fades to black (executed, case D).** All rows and columns are black and edge-connected: grain vanishes on the entire frame. Old gate also removed grain here (both 0.000), so this is not a regression, but it remains a "grain vanishes" input and contradicts any reading of "preserve interior flat grain" that includes fade frames. Fixture: full-black 1080p frame and a black-to-black fade sequence, asserting grain gain per frame.
3. **Film-frame bucket edges straddling the mask boundary (not executable from public bytes).** The mask switches `luma_gain` to 0 exactly at the last exact-black row/column. Grain buckets (the film-frame tiling the diff does not show) do not align to that boundary, so a bucket straddling it carries grain on one half and zero on the other: a visible seam inside a single grain cell at the bar/picture transition. Fixture: letterboxed frame with the grain phase frozen (fixed bucket offset), diff the rows within one bucket height above and below the boundary, assert the transition width in pixels.
4. **Pure-black clipping inside content (conditional).** Only FULL rows/columns of exact black mask; a crushed-black region inside the picture that touches an edge but does not span a full row/column is NOT masked (verified by inspection of lines 47-75: both lo/hi runs require every intermediate row/col black). So interior crushed blacks keep grain (good). The vanish risk is the converse: any content that produces complete exact-black rows or columns (hard telecine transitions, generated black slates) loses grain on those rows entirely. Fixture: synthetic slate with N full black rows mid-frame, assert masked row set equals exactly those rows.
5. **White clipping / HDR highlights (executed for white, conditional for HDR).** Flat clipped-white keeps grain under the new gate (case H: NEW 1.000 where OLD 0.000) - a deliberate-looking behavior change, but it is silent in the commit message and unverifiable as intent; if post-grain output clipping crushes the grain on whites, that happens downstream and is outside this shader. HDR: the exact-equality black test (lines 27, 42, 101) never matches any nonzero black floor; on PQ/HLG paths where "black" bars arrive with a nonzero offset, the gate fails open exactly as in case F. Fixture: HDR10-letterboxed clip with bars at the code's delivered black level, assert bar grain gain; flat-white frame, assert grain present and state the intended policy.

## Adversarial findings against the removal

- **F1 (executed, case B): one stray nonzero pixel splits edge connectivity and un-masks the rest of the bar.** A single 1/255 pixel at bar row 100 leaves rows 0-99 masked (gain 0.000) but rows 101-139 fully grained (gain 1.000). Real letterboxed encodes routinely carry stray nonzero pixels in bars (compression noise, dither, subtitles residue, baked-in timecode). Per-frame, as noise flickers, the unmasked segment boundary jumps row to row: visible bar-grain flicker localized below/above the stray pixel. The old variance gate degraded gracefully here (case B OLD: 0.026, only specks near the pixel). This is the sharpest regression the removal introduces.
- **F2 (executed, cases D, E): edge-connected-by-construction inputs are fully masked.** Covered in the vanish list above.
- **F3 (executed, case F): exact equality misses near-black bars.** Bars at 1/255 keep full grain (NEW 1.000; OLD 0.007). Limited-range video is the bigger instance: TV-range black sits at code 16/255, so untouched limited-range letterbox bars NEVER match `vec3(0.0)` and are grained at full amount, unless the pipeline normalizes black to 0 before this hook runs (not determinable from the public diff). The removed variance gate was amplitude-blind and suppressed any flat bar regardless of level.
- **F4 (source-only): "applied once, by Lua" is not demonstrated in this diff.** Line 107 deletes the shader attenuation; line 108 asserts Lua applies it once; no added Lua hunk in the diff implements it. From public bytes it is unverifiable whether attenuation is applied once, twice (if existing Lua code plus a future shader both apply), or zero times. Effective-amount parity on a noise sweep is therefore unverifiable for this change as published.
- **F5 (source-only): hard top-level `require('photon-shader-recovery')` (line 176) makes the whole script fail to load if that module is absent.** The recovery module is not part of the public diff, so its presence on target installs is unverifiable. The defensive guard `common.recovery and common.recovery.prefix or "photon-grain"` (line 120) is dead code under a hard require at line 176 that runs before any push_params call: either the module loads (guard always true) or the script is already dead. The posture is inconsistent: soft-fail at line 120, hard-fail at line 176.
- **F6 (source-only): watched hash vs shipped artifact generation.** Recovery watches `sourceSHA256 5b96daf329ca73d09536519bf0ce79d48a994e3269e04bd6e77c6fcbe06f9e61` (line 178), which is distinct from the candidate-v1 grain.frag hash `5ead78cf8439c4f6a5787fb2b5ed9bea26788785a60e632bcf335bd0962559f8` seen in the earlier kit work. These are plausibly different artifact generations (embedded GOR_GRAIN_SOURCE vs standalone candidate file), but if the watched hash does not track the actually shipped file bytes, recovery either never fires or restores mismatched bytes. Unverifiable from public bytes; stated so the Ops side can confirm the pairing.
- **F7 (source-only, minor): double read of glsl-shaders in gr_add_shader.** The function builds `filtered` from an earlier snapshot `shaders` (lines 125-128, definition above the hunk) and then re-reads the property as `raw` (line 130), removing every entry of `raw` not in `shaders` (lines 132-135). Any entry a concurrent script appends between the two reads is silently removed. Low likelihood in mpv's single-threaded script runtime, but the old single-snapshot code did not have this window.
- **F8 (source-only): HUD "effective amount" is pre-attenuation.** Lines 163-166 compute `amount = clamp(gr_amount_rendered,0,10) * (GRAIN_BASE_STRENGTH/10)`; with noise attenuation now claimed on the Lua side (F4), whether this HUD number matches what the shader actually applies is unverifiable from public bytes. The HUD reports a rendered-amount proxy, not the effective post-attenuation amount its label claims.

## What the old gate caught that now passes silently

The removed variance gate suppressed grain on every locally flat 2x2 neighborhood. That over-caught (flat interiors - the bug this commit fixes, confirmed case A) but it also caught, and the new gate deliberately passes: flat clipped whites (H), interior black rectangles (C), near-black flat bars at any nonzero level (F). Of those, F is the only one that looks like a genuine regression class (letterbox bars that should stay clean); C and H read as intended intent changes, but they are behavior changes shipped without fixtures and without mention in the commit message.

## What I could NOT attack from public bytes

- The grain synthesis itself (buckets, blue-noise tile, luma_adapt, zone_sensitivity) is not in the diff; the V3 bucket-seam case above is argued, not executed.
- Lua-side attenuation parity (F4) and HUD accuracy (F8) on real footage.
- Native mpv hook ordering, `HOOKED_pos` rounding behavior at odd sizes, and `change-list` semantics on a live player; my replay assumes texel-exact fetches as written.
- Recovery module behavior (F5, F6): the module is not public.

No claims beyond this scope. Linux llvmpipe is not a Darwin or native-GPU verdict.
