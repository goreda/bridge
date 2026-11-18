# W-gdb-199h-wrr3b-02 - Manual grain range (r3 re-pin)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h WR (r3b, pinned to native50 872dcc32d). Manual grain amount range and step: GRAIN_BASE_AMOUNT_MIN/MAX, GRAIN_OFFSET_STEP and the manual-amount handler state (excerpts below). r3 change: re-pinned to native50 35f553acd (file unchanged). Byte-exact excerpts keep the source's typographic comment punctuation; do not churn the source for it.

Re-pin note: r3b moves the pin 35f553acd -> 872dcc32d; all excerpt bytes are identical to r3 at the recorded ranges (the only shift is +3 lines before the sess_replace excerpt, now carved at 1660-1720).

Required acceptance: Linux test over the pure range/step math matching the pinned constants, including near-zero behavior of GRAIN_OFFSET_STEP.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-wrr3b-02",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
 "touched_files": [
  {
   "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
   "excerpt_block": "grain_baseline (lines 89-96)"
  }
 ],
 "interface": {
  "signatures": "Manual grain amount range and step: GRAIN_BASE_AMOUNT_MIN/MAX, GRAIN_OFFSET_STEP and the manual-amount handler state (excerpts below). r3 change: re-pinned to native50 35f553acd (file unchanged). Byte",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Linux test over the pure range/step math matching the pinned constants, including near-zero behavior of GRAIN_OFFSET_STEP.",
  "callee": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-wrr3b-02.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Linux test over the pure range/step math matching the pinned constants, including near-zero behavior of GRAIN_OFFSET_STEP.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-wrr3b-02",
  "paths": [
   "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
   "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-wrr3b-02.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-wrr3b-02.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T11:50:59.809897+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
    "lines": "89-96",
    "block": "Resources/vendor/mpv/scripts/photon-grain.lua:89-96",
    "sha256": "2d4db7380976f6ab23bf85ed789b15205f576b71650e641fbdaceed60fd7f492"
   },
   {
    "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
    "lines": "281-320",
    "block": "Resources/vendor/mpv/scripts/photon-grain.lua:281-320",
    "sha256": "e3c6dd06715a2d7c4f021913fb7df1ab8d86cf4c39d7b8b764799df9c80e0dab"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-wrr3b-02.py",
    "block": "fixtures1",
    "sha256": "58d728622e06a8a53b1a57ceb604a098c90a0f4260878c318b718a275761eee6"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "6ba9409dd46e20264824dadc2c686be0eb4ca3d9dac62841505ac5e5140fc0eb",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr3b-02; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "0193bdc9f7f4fe8b55a22e66e93623284437533478175deeed9715e553edc3d2"
 }
}
```

```lua id=Resources/vendor/mpv/scripts/photon-grain.lua:89-96
local GR_WINDOW_COMP_MAX = GR_WINDOW_COMP_MIN * 2

-- ── adaptive baseline ──
-- gr_amount = clamp(base_amount(scene) * gr_user_ratio, MIN, MAX)
local GRAIN_BASE_AMOUNT_MIN  =  0.55  -- was 0.25/2=0.125 — see gr_resolve_adaptive_params two-tier note: darkest-to-brightest ratio cut from 21.6x to ~2.4x, real film's exposure/push relationship, not a mechanism-revealing swing
local GRAIN_BASE_AMOUNT_MAX  =  1.00  -- was 1.35*2=2.7
local GRAIN_OFFSET_STEP      =  0.025 -- actual amount per press, including near zero
local GRAIN_OFFSET_MIN       = -1.00
```

```lua id=Resources/vendor/mpv/scripts/photon-grain.lua:281-320
-- pending dwell, used at both file-loaded and the manual amount-key
-- handler — a new file (or a user override) shouldn't inherit a dwell
-- gr_scene_contrast=0.35).
local function gr_char_state_reset()
    local defaults = {size = 0.50, soft = 0.10, chroma = 0.20, devel = 0.35, mix = 0.50}
    for key, s in pairs(gr_char_state) do
        reset_char_state(s, defaults[key])
    end
end

-- DT CEILING — driven by the ~4s scene feed like sharp's (the 1Hz
-- periodic only publishes HUD state). A 1.0 dt cap made every tau run
-- ~4x slow; true elapsed time now, capped at three feed ticks.
local GR_DT_MAX = 12.0

-- 133a: consumer-owned seek prior + measured-strength blend. The b7 x1.0
-- prior lands at once on EVERY seek without waiting for the producer (the
-- producer's own prior may be omitted or arrive late); a measured value
-- then blends in over ~2s of bounded receiver dt, so a wall-timer stall
-- cannot turn the first tick into a jump.
local GR_STR_BLEND_S         = 2.0
-- (per-tick dt cap retired: blend is wall-anchored, see gr_strength_blend_tick)
local gr_str_blend           = nil    -- {from,target,start_t}
local gr_seek_epoch          = 0      -- per-file seek counter (doc + epoch gates the proxy path)
local gr_measured_since_seek = false
local gr_strength_blend_tick        -- defined after gr_push_params/gr_publish_hud_state

local gr_manual_amount_current=false
local gr_learned_amount_factor=1.0
local function gr_scene_base_amount()
    local base_amount = GRAIN_BASE_AMOUNT_MIN
        + (GRAIN_BASE_AMOUNT_MAX - GRAIN_BASE_AMOUNT_MIN) * (1.0 - gr_frame_peak)
    base_amount = base_amount * (1.0 - 0.35 * clamp(gr_noise_level, 0.0, 1.0))
    base_amount = base_amount * (1.0 - 0.15 * clamp(gr_motion_level, 0.0, 1.0))
    return (base_amount)*gr_learned_amount_factor
end

local function gr_resolve_adaptive_params(is_cut)
    local base_amount = gr_scene_base_amount()
    gr_amount = clamp(base_amount * gr_user_ratio,
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Resources/vendor/mpv/scripts/photon-grain.lua", 89, 96, "2d4db7380976f6ab23bf85ed789b15205f576b71650e641fbdaceed60fd7f492"], ["Resources/vendor/mpv/scripts/photon-grain.lua", 281, 320, "e3c6dd06715a2d7c4f021913fb7df1ab8d86cf4c39d7b8b764799df9c80e0dab"]]
bad = []
for rel, a, b, want in CHECKS:
    lines = (ROOT / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr3b-02; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr3b-02; baseline only, product change and semantic test still required
```
