# Mac owner-action leg

Run `python3 tools/owner_action_acceptance.py /path/to/gor` while the interactive app is closed.
Delivery owns adding this bounded (60s plus frame flush/cleanup) action leg to the update.
The driver refuses any existing exact-binary process. It launches the installed binary on the
hash-pinned public plain2D fixture and records installed build-id (source-manifest, not Git SHA),
binary SHA256, fresh child PID, process start time and launch timestamp.
It terminates only its own child when finished. No ffprobe is required.

The environment-gated Swift runner uses real menu rows with 1.5-second settle intervals:
Film2D+ViewOff -> Toggle3D -> ViewSBS -> ViewVR180 -> ViewSBS -> ViewOff. It writes per-step store snapshots,
applier commands, controller vrModeEnabled, and read-only IPC replies; commands are not treated
as proof they applied. Screenshots remain private artifacts requiring actual visual inspection.
The model prepare/render coordinator is suppressed only in this test process so the public fixture
cannot be replaced by a cached generated shot during this route test. This does not exercise
model inference or generated-shot handoff. It also does not reproduce an already-corrupt saved
state or an arbitrary owner film's classifier. Those remain separate action legs.

Existing IPC reads: path, video-params/stereo-in, video-params/spherical-mapping, glsl-shaders,
user-data/vr180-look/enabled, user-data/gor/3d-internal, user-data/gor/3d-parent-film-id.
Photon receipt schema:
- user-data/gor/3d-applied-state: pid, build, timestamp, stereoSource, engine, output, vr_mode
- user-data/vr180-look/applied-state: source_layout, flat_pack, plan_lock, enabled

A missing receipt/field is NOT_RUN. A mismatched PID/build/stale timestamp, wrong source,
native-engine selection, failed SBS, or enabled VR after Off is FAIL. A PASS is applied-state
acceptance only, not a pixel/visual quality verdict. Full Swift/AppKit compilation and real Mac
execution must be performed by the verifier. Python verdict-unit tests can run on Linux.

Schema expectations: stereoSource is `flat` (store source remains `flat2D`).
Baseline/Off: flat_off, output off, vr_mode false; Lua layout0/pack0/locknull/enabledfalse.
Toggle: flat_full_sbs or flat_half_sbs (saved last output), matching output, vr_mode true;
Lua layout0/pack3/enabledtrue. Explicit SBS: flat_full_sbs/full_sbs/vr_mode true, Lua0/3/true.
Here vr_mode is the app's common shader enable, not proof of native VR engine selection.
A tilt test is not included: this lane has no pre-tagged fixture and raw roll IPC field contract.

191o: the action leg now includes explicit VR180 and return-to-SBS. Interim TWO_D_VR180
must remain engine twoDVR180/source flat, not native; pack4 is a failure. Photon confirmed pack3 flat virtual-screen SBS for the interim route; all other packs fail.
`tools/owner_action_capture_grep.py` prints bounded exact lines for store_applier, lua_enable,
shader variant, and store_applier_reject, or explicit NO_MATCH. Delivery should append its output
to the kit capture. It never infers a rejected Off merely from a missing line.

Native route-only leg: `python3 tools/owner_action_acceptance.py /path/to/gor --native`.
The driver tags a copy of the hash-pinned public fixture using the existing MP4 patch helper;
no ffprobe runtime dependency. The app drives FilmAuto+ViewVR180 -> Off -> ViewVR180 and requires
native source classification plus Lua source_layout3/pack0. Off must disable the shader.
The tagged source contains NO real stereo disparity: this is classification/route/pack acceptance,
not optical stereo quality, vertical-disparity/tilt acceptance, or a replacement for a native e_v sweep.

Native mode also drives +15-degree roll (0.261799388 radians) for runtime tools-active false/true
(legacy/extended), queries after 0.1s without a 1.5s settling delay, and restores tools-active false.
Reads glsl-shaders and glsl-shader-opts; matches the active shader-a/b basename and its /vr_roll key.
Missing option schema/slot/roll is NOT_RUN; wrong raw roll is FAIL. This is a raw uniform receipt,
not a screenshot-based e_v/partition test or proof the variant actually selected matches its label.
Actual variant diagnostic lines must accompany these receipts. No preferences are changed.

191t: provider is late-bound at menu construction; bounded readiness waits for player, current film and menu. Missing readiness produces a named NOT_RUN. Timeout capture retains readiness/partial action JSON and routing diagnostics. Both owner-action and store-acceptance children use transient film records; the owner durable film database is neither loaded nor written. Store matrix/sequence cases launch separate processes through actual fixture opens. Sequence 1 still does not measure its logged 120-second stability or generated-shot playback leg; sequence 2 still lacks a real close/reopen pixel comparison. These remain unverified, not newly accepted.

Applied Swift receipt timestamp is epoch milliseconds; action timestamp is epoch seconds. Driver divides the applied timestamp by 1000 before freshness comparison. Engine schema uses flat_off and flat_full_sbs (underscore), matching ThreeDEngine.rawValue.
