# W-gdb-199h-wr-02 - Manual grain range
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h writer/manual-grain-range. Writer item: manual grain range preserved as a scene-ratio multiplier. Manual adjustment steps by GRAIN_OFFSET_STEP per press, clamped to the GRAIN_BASE_AMOUNT_MIN..max band; the strength source is recorded as manual in HUD/log; the target state persists across file loads. The scene-adaptive baseline is unchanged while no manual adjustment is engaged.

Required acceptance: Step up/down lands on the exact clamp bounds with no overshoot; source recorded as manual; adaptive baseline bit-identical when untouched. Lua-side semantics test on Linux; Mac compile through D1.

This is PRODUCT work: at least one listed production file must change with a meaningful behavior change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
  "packet_id": "W-gdb-199h-wr-02",
  "lab": "shared",
  "writer": "1nstinct or in2tinct (earliest claim wins)",
  "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
      "excerpt_block": "see pinned excerpts below"
    }
  ],
  "interface": {
    "signatures": "Manual grain range; Writer item: manual grain range preserved as a scene-ratio multiplier. Manual adjustment steps by GRAIN_OFFSET_STEP per press, clamped to the GRAIN_BASE_AMOUNT_MIN..max band; the s",
    "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit",
    "caller": "Step up/down lands on the exact clamp bounds with no overshoot; source recorded as manual; adaptive baseline bit-identical when untouched. Lua-side semantics test on Linux; Mac compile through D1.",
    "callee": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua"
  },
  "scope": "product",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-02.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Step up/down lands on the exact clamp bounds with no overshoot; source recorded as manual; adaptive baseline bit-identical when untouched. Lua-side semantics test on Linux; Mac compile through D1.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-<claiming-lab>-W-gdb-199h-wr-02",
    "paths": [
      "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
      "archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-02.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_repo": "goreda/instinct",
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "reference_repo": "goreda/bridge",
    "reference_sha": "fbb0932e82fbd1aa22d5792f7cad77f4d45b27ef",
    "command": "python3 archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-02.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-18T10:03:22.841877+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
        "lines": "91-125",
        "sha256": "59ec50f95f74bd7589dfd1edf84a507dbb20d6f73b9cb38a50e83d73863b46f7"
      },
      {
        "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
        "lines": "154-175",
        "sha256": "3ef636d6669a898a925af3535a40a6f85b4f9b33182dd3c849e0fa3a9793affd"
      },
      {
        "path": "archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-02.py",
        "block": "fixtures1",
        "sha256": "d58a35880bb9e145c78602eb874012136030d9ff8b67046a8c9dc30c133d6f88"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "5f042f31ebf28546febd3d5ce9a3e0436708c32d4a51001adf121466424c397e",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-02; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "8a9c2d3ee2fcd798c1836fe9cce96f76f3df4dee9dc68ad1090d8c7d9ee0d40b"
  }
}
```

```lua id=Resources/vendor/mpv/scripts/photon-grain.lua:91-125
-- ── adaptive baseline ──
-- gr_amount = clamp(base_amount(scene) * gr_user_ratio, MIN, MAX)
local GRAIN_BASE_AMOUNT_MIN  =  0.55  -- was 0.25/2=0.125 — see gr_resolve_adaptive_params two-tier note: darkest-to-brightest ratio cut from 21.6x to ~2.4x, real film's exposure/push relationship, not a mechanism-revealing swing
local GRAIN_BASE_AMOUNT_MAX  =  1.00  -- was 1.35*2=2.7
local GRAIN_OFFSET_STEP      =  0.025 -- actual amount per press, including near zero
local GRAIN_OFFSET_MIN       = -1.00
local GRAIN_OFFSET_MAX       = 10.00
local GRAIN_AMOUNT_CLAMP_MIN =  0.00
local GRAIN_AMOUNT_CLAMP_MAX = 10.00


-- ================================================================
--  2. STATE
-- ================================================================
local gr_user_offset     = 0.0 -- derived compatibility/HUD delta, never the control state
local gr_user_ratio      = 1.0
local gr_weight_shift    = 0.0   -- rendered layer-weight shift (GS probe mirror)
local gr_feed_corrupt_logged = false
local gr_amount          = GRAIN_AMOUNT_DEFAULT  -- raw scene-derived TARGET (see gr_resolve_adaptive_params)
local gr_frame_peak       = 0.50
local gr_scene_contrast   = 0.35
local gr_noise_level      = 0.10
local gr_motion_level     = 0.20
local gr_fps              = 24.0

--  TWO-TIER SCENE-ADAPTIVE MODEL
-- size, softness, chroma split, development, mix) straight off frame-

-- ---- Tier 1: DENSITY ----
-- Exponential (attack/release) ease, not a linear max-step ramp — a
-- constant-velocity ramp reads as an "escalator"; exponential decay
local gr_amount_rendered  = GRAIN_AMOUNT_DEFAULT
local gr_amount_last_t    = 0
local GR_DENSITY_TAU         = 7.5   -- seconds; ~4-5x this to fully settle
local GR_DENSITY_CUT_TAU     = 0.3   -- still eased (not an instant snap), just far faster, on a confirmed cut
```

```lua id=Resources/vendor/mpv/scripts/photon-grain.lua:154-175
-- kept as a fixed reference that photon-grain-set-strength-hint multiplies against.
local GRAIN_STRENGTH_USER_DEFAULT  = GRAIN_BASE_STRENGTH
local gr_strength_hint_suppressed  = false
local gr_strength_hint_received    = false
local gr_strength_hint_last_value  = nil
-- B2: strength source for HUD/log ("seed" | "mult" | "auto-measured" | "auto-clean" | "manual" | nil) and
-- document identity from photon.lua. mult_applied guards the seed write.
local gr_strength_src   = nil
local gr_mult_applied   = false
local gr_doc            = { gen = 0, name = "-" }
local gr_last_mult      = nil
-- B2 user size trim: multiplicative, session-persistent, on top of auto size.
local gr_size_trim      = 1.0
local GR_TRIM_STEP, GR_TRIM_MIN, GR_TRIM_MAX = 1.12, 0.25, 4.0

-- 480p grain bounds, owner-steered (2026-10-29): "set the floor to 0.25 for 480p",
-- "the floor and ceiling", "add them to the config", "480p does not produce crystals that small".
-- Config surface: mpv script-opts (same mechanism photon.lua uses for photon_kill).
--   script-opts=photon-grain_floor_480p=0.25   (default 0.25 px)
--   script-opts=photon-grain_ceiling_480p=8.0  (default 8.0 px; the existing
--   trim>2 / hint-suppressed escape doubles it, preserving prior behavior)
-- Other resolutions keep the v3 bounds (0.15 floor, 8/16 ceiling rule).
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
BRIDGE_ROOT = Path(os.environ.get("BRIDGE_ROOT", "/nonexistent"))
CHECKS = [["product", "Resources/vendor/mpv/scripts/photon-grain.lua", 91, 125, "59ec50f95f74bd7589dfd1edf84a507dbb20d6f73b9cb38a50e83d73863b46f7"], ["product", "Resources/vendor/mpv/scripts/photon-grain.lua", 154, 175, "3ef636d6669a898a925af3535a40a6f85b4f9b33182dd3c849e0fa3a9793affd"]]
bad = []
for root, rel, a, b, want in CHECKS:
    base = ROOT if root == "product" else BRIDGE_ROOT
    lines = (base / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-02; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-02; baseline only, product change and semantic test still required
```

secret scan: clean
