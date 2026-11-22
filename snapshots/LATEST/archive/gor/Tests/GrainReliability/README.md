# U-G3 ratio-only candidate and tests

Exact base: c73650542460c96b928711e54ff5a61899d62a9e.
One changed production file: Resources/vendor/mpv/scripts/photon-grain.lua.
No shader edits. No R2 1/255 floor. No HUD UI or publish-field edits. No ambient contract changes. No refs, commit, install or app launch. The older R2 package is superseded for this train and must not be merged.

## Change

The authoritative manual fine-step state is now gr_user_ratio, initially 1. At each fine-step, current = clamp(scene_base * ratio), target changes by the unchanged .025 and stays clamped 0..10, then ratio = target/base. Resolution applies clamp(scene_base * ratio,0,10). File-loaded resets ratio to 1; the existing learned factor reset/replay behavior is retained. A zero from the user's own presses or existing v==1.0 compatibility toggle remains explicit OFF across scene changes.

The existing gr_user_offset variable is retained only as a derived compatibility delta amount-base so HUD/probe consumers keep the same field meaning. It is never read as authoritative control state. All existing HUD strings, field count/order and the full publish function remain byte-identical. The unused old GRAIN_OFFSET_MIN/MAX constants are left in place to avoid unrelated cleanup. Set-strength clamp remains 0..60.

Item 4: DOC.on_loaded.replay_amount uses GS.learned_solve('amount',1.0) and sends it directly. There is no explicit learned-amount emitter clamp or named lower-bound constant. GS.mult_floor=.35 belongs to strength and is not reused. No photon-common.lua constant or receiver clamp has been added. Negative-control input .01 remains .01 in the receiver and yields base .8 * .01 = .008 in the test. The normal learner blend arithmetic is not represented as an explicit emitter clamp.

## Install and Class S

Apply ug3-ratio-only.patch only after checking base_grain_sha256 in ug3-source-proof.json, or install the replacement after the same check. `git apply --check` passed against the exact supplied source. Copy payload/Tests/GrainReliability into gor/Tests/GrainReliability. Other product Lua files remain from the checkout.

Headless Class S source/callback regression entrypoint (Python standard library plus Lua5.1/LuaJIT):

    python3 Tests/GrainReliability/ug3_test.py

It first tries GRAIN_RELIABILITY_LUA, lua5.1 or luajit executables, then a discoverable Lua5.1/LuaJIT shared library. Missing interpreter/library is NOT_RUN exit2. On Darwin the explicit interpreter path is preferred; no interpreter is provisioned at runtime. This entrypoint does not require mpv, numpy, a display or network.

Optional mutation test:

    python3 Tests/GrainReliability/ug3_mutants.py --scripts Resources/vendor/mpv/scripts

Full pixel/learning entrypoint:

    GRAIN_RELIABILITY_MPV=/exact/candidate/mpv python3 Tests/GrainReliability/reliability.py

Full entrypoint also invokes ug3_test.py. It needs numpy, Pillow, ffmpeg, exact candidate mpv0.41 and usable gpu-next graphical session; Linux additionally Xvfb/Mesa. It is NOT a headless-Darwin renderer. No context/binary means NOT_RUN, never a pixel PASS. Carrier may run the headless ug3_test in Class S and keep pixel acceptance separately OPEN/NOT_RUN. Add the chosen success-log names to the carrier output allowlist. Ops owns carrier wiring and fresh Darwin compile/runtime evidence.

## Tests before and after

The complete product grain Lua chunk is executed with test host seams. The real callback closures/locals/file-loaded handlers run. The production common raster math runs; recovery renderer is inert and scene bases .8/.3 are controlled inputs. This is not GPU or app acceptance.

Baseline RED:
- (a) .8 base, 28 fine-down presses gives .1; base falls to .3: actual amount 0, expected .0375.
- (c) .3 base, one fine-up gives .325; base rises to .8: actual .825, expected .8666666667.

Candidate GREEN 8/8:
- (a) amount .0375 >0 after scene decrease.
- (b) compatibility OFF remains 0 across scene change.
- (c) proportional increase after fine-up.
- (d) file-loaded resets manual ratio; learned .7 factor replay still applies (.8*.7=.56).
- (e) set-strength endpoints remain 0..60.
- (f) absent load-time rasters -> coefficients absent, later video-out-params -> size coefficient >0 and strength k set.
- Item4 .01 receiver input unchanged because emitter has no explicit floor.
- Fine-step remains .025.

Restored additive resolve, missing ratio reset, and missing late-raster invalidation mutants are rejected. Full pixel selftests still reject dropped output, persistence loss and ignored learned solve.

## Linux pixel and relaunch result

Actual Linux mpv0.41 gpu-next/Xvfb/Mesa: 9 default flat/near-flat/gradient x low/mid/high fixtures sigma>0, RGB sigma1.903913..3.408860. All default ON/OFF screenshot hashes are bit-identical to c7365054 baseline. Complete unmodified embedded shader executes, not a CPU shader model.

Explicit strength0 and all zone sensitivities0 still produce sigma0. They are recorded as known/separate P0 candidates from explicit user settings, not blockers for this U-G3 request. Fine-down to the user's own0 and compatibility OFF must have zero pixel contribution. The prior offset-floor case is therefore no longer used as an accidental-zero proxy; case (a) is the actual U-G3 scene-drop regression. This scoping change is explicit, not a claim that zero controls were fixed.

Persistence/relaunch still PASS: complete grain manual callbacks/emitter + exact master learner/solve slice + real learner module, separate mpv processes in adaptive ON and OFF modes; 3 event records survive, solve .866025->1.133013 and size1->1.1, no probe-count inflation, no manual-strength overwrite. Not full AppDelegate relaunch coverage.

Darwin NOT_RUN. Owner screen NOT_RUN. G2 learner vectors are connected through g2_learner_test.py, not through the older three-callback JSON interface. G2 shader model buckets are reference-only and not GPU proof. No G2 ratio vectors exist; G4 remains not connected. No claim about all HDR/bit depths/all knob combinations. Evidence JSON is included; source hash assertions prove shader and HUD publish bytes unchanged.

G2 learner Class S command: python3 Tests/GrainReliability/g2_learner_test.py. Same Lua runtime dependency as ug3_test.py, no display/mpv needed. See G2-reference/COMPARISON.md.
