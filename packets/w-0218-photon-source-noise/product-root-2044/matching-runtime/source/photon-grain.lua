-- ================================================================
--  photon-grain.lua - OUTPUT-stage film grain
--  Owns: grain shader, scene-adaptive state and messages
--  Answers: I40 · TRAP-09
--  Contract: photon bootstrap precedes require; live shader values use parameters
-- ================================================================
local script_dir = mp.get_opt("photon-scriptdir")
if script_dir then
    local probe = io.open(script_dir .. "/photon-common.lua", "r")
    if probe then
        probe:close()
        package.path = script_dir .. "/?.lua;" .. package.path
    else
        mp.msg.error("photon-grain: photon-scriptdir invalid or photon-common.lua missing - checked: " .. script_dir .. "/photon-common.lua")
    end
end
local common_ok, common = pcall(require, "photon-common")
if not common_ok then
    mp.msg.error("photon-grain: could not load photon-common - " .. tostring(common) .. ". This script is disabled.")
    return
end
local PHOTON_REQUIRED_COMMON_VERSION = 2
if not common.check_version("photon-grain", PHOTON_REQUIRED_COMMON_VERSION) then
    return
end


-- ================================================================
--  1. CONTROL PANEL
-- ================================================================
-- Legacy handlers keep input.conf compatibility:
--   set-fine→FINE, set-mid→CRYSTAL, set-coarse→CLOUD, set-dye-halo→SOFTNESS

local GRAIN_BASE_STRENGTH    =  6.00
local GRAIN_SIZE             =  0.80        -- px (HD ref): 1=fine, 3=normal, 6=coarse
local GRAIN_FINE_WEIGHT      =  0.25
local GRAIN_CRYSTAL_WEIGHT   =  0.40
local GRAIN_CLOUD_WEIGHT     =  0.45
local GRAIN_FINE_SIZE_RATIO  =  0.5
local GRAIN_CLOUD_SIZE_RATIO =  2.2
local GRAIN_SOFTNESS         =  50.00       -- meaningful range ~0.25-0.70
local GRAIN_STOCK_PRESET     =  5           -- 0=Portra,1=Ektar,2=Vision3,3=Kodachrome,4=Tri-X,5=HP5
local GRAIN_DEVELOPMENT      =  0.4         -- 0.3=mild, 1.5=push
local GRAIN_RES_ADAPT        =  1
local GRAIN_CHROMA_SPLIT     =  1.0
local GRAIN_SKEW_STRENGTH    =  0.0
local GRAIN_SHADOW_SENSITIVITY    =  1.8
local GRAIN_MIDTONE_SENSITIVITY   =  1.5
local GRAIN_HIGHLIGHT_SENSITIVITY =  2.70
local GRAIN_DEBUG_VISUALIZE  =  0
local GRAIN_AMOUNT_DEFAULT   =  1.00
local enabled                 = false
local gr_control_revision = 0
local function gr_trace_control(kind)
    gr_control_revision = gr_control_revision + 1
    common.trace_record("control", {control=kind, revision=gr_control_revision})
end
-- Contract: target state persists across file loads, regardless of message order.
local grain_target_enabled = mp.get_opt("photon-menu-enabled") ~= "false"
local gr_adaptive_mode = mp.get_opt("photon-adaptive-program") ~= "false"
if mp.get_opt('gor-diag') == 'true' then
    local d = io.open("/tmp/gor_diag.log", "a")
    if d then d:write("photon-ident photon-grain.lua v2.2.17 loaded " .. os.date("%H:%M:%S") .. "\n"); d:close() end
end
local gr_effective_h
local gr_source_h, gr_output_h, gr_size_coefficient = nil, nil, 0.0
-- Low-resolution measured k is independent of GS HOLD/sample state.
local gr_strength_k, gr_render_density = nil, nil
local function gr_refresh_adaptive()
    local source_property, sw, ow
    gr_source_h, gr_output_h, source_property, gr_effective_h, sw, ow = common.adaptive_rasters()
    gr_size_coefficient, gr_strength_k, gr_render_density = 0.0, nil, nil
    if gr_adaptive_mode and gr_effective_h and sw and ow and sw > 0 and ow > 0 then
        local r = ow / sw                                  -- output px per source px (width: letterbox-safe)
        -- grain is drawn at OUTPUT; it belongs to the picture, so cell size follows r
        gr_size_coefficient = 0.8 * math.max(0.75, math.min(2.5, r))
        -- strength: low-res table (common, nil at >=1080) x visibility of larger cells
        local k_res = common.adaptive_strength_k(gr_effective_h) or 1.0
        local k_scale = r > 1.0 and math.max(0.80, r ^ -0.25) or 1.0
        gr_strength_k = k_res * k_scale
        gr_render_density = math.max(0.55, math.min(1.0, gr_strength_k))
    end
end

-- Window-size compensation clamp
local GR_WINDOW_COMP_MIN = 0.4
local GR_WINDOW_COMP_MAX = GR_WINDOW_COMP_MIN * 2

-- ── adaptive baseline ──
-- gr_amount = clamp(base_amount(scene) + gr_user_offset, MIN, MAX)
local GRAIN_BASE_AMOUNT_MIN  =  0.55  -- was 0.25/2=0.125 — see gr_resolve_adaptive_params two-tier note: darkest-to-brightest ratio cut from 21.6x to ~2.4x, real film's exposure/push relationship, not a mechanism-revealing swing
local GRAIN_BASE_AMOUNT_MAX  =  1.00  -- was 1.35*2=2.7
local GRAIN_OFFSET_STEP      =  0.50
-- Manual strength ladder (v2.2.6): one press used to add a fixed 0.50, about
-- +65% on a base near 0.8, which is too coarse. Presses now climb a ladder:
-- four fine presses of 0.125 reach the old first stop (+0.50), then 0.25
-- steps up to +1.50, then 0.50 steps. Down is the mirror, to -1.00.
-- GR_STEP.level is the press count from 0; the offset is read from the ladder.
local GR_STEP = {
    up   = {0.125, 0.25, 0.375, 0.50, 0.75, 1.00, 1.25, 1.50, 2.00, 2.50, 3.00, 3.50, 4.00, 4.50, 5.00, 6.00, 7.00, 8.00, 9.00, 10.00},
    down = {-0.125, -0.25, -0.375, -0.50, -0.75, -1.00},
    level = 0,
}
function GR_STEP.offset()
    local l = GR_STEP.level
    if l > 0 then return GR_STEP.up[l] end
    if l < 0 then return GR_STEP.down[-l] end
    return 0.0
end
local GRAIN_OFFSET_MIN       = -1.00
local GRAIN_OFFSET_MAX       = 10.00
local GRAIN_AMOUNT_CLAMP_MIN =  0.00
local GRAIN_AMOUNT_CLAMP_MAX = 10.00


-- ================================================================
--  2. STATE
-- ================================================================
local gr_user_offset     = 0.0
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

-- ---- Tier 2: CHARACTER ----
-- gr_char_signal: a long-EMA read on the same peak/contrast/noise/
-- motion scalars, heavily smoothed (tau in the seconds, not the
local gr_char_signal      = 0.50   -- long-EMA "scene exposure character" proxy, 0=bright..1=dark (mirrors dark_t)
local gr_char_committed   = 0.50   -- the dark_t value character params are currently built from
local gr_char_target_t    = 0      -- when the current committed value was last updated (mp.get_time())
local gr_char_dwell_start = nil    -- mp.get_time() when signal first crossed outside the dead-zone; nil = inside it
local gr_char_last_t      = 0      -- for the long-EMA's own dt bookkeeping
local GR_CHAR_TAU          = 9.0    -- seconds; long enough that within-shot brightness variation barely moves this
local GR_CHAR_DEAD_ZONE    = 0.12   -- committed value must be wrong by this much (in dark_t units, 0-1) before a change is even considered
local GR_CHAR_DWELL_MIN    = 2.5    -- seconds the signal must stay outside the dead-zone before a new value commits
local GR_CHAR_EASE_TAU     = 3.0    -- seconds; once committed, how fast the rendered character actually eases to the new value
local GR_CHAR_CUT_EASE_TAU = 0.8    -- faster ease specifically right after a confirmed cut (see gr_resolve_adaptive_params) — a real edit to different footage is exactly when character SHOULD be allowed to reassess promptly, mirroring how a stock/process change actually looks at a real cut, rather than waiting out the normal dwell built for filtering noise within continuous footage

local GRAIN_SIZE_BASE           = GRAIN_SIZE
-- Development B: fixed reference to the user's configured base value.
-- photon-grain-set-size-hint multiplies against this (not GRAIN_SIZE_BASE
-- itself) — otherwise successive hints would compound multiplicatively.
local GRAIN_SIZE_BASE_USER_DEFAULT = GRAIN_SIZE_BASE
local gr_size_hint_suppressed      = false
-- HUD: whether a hint was actually received and applied. Not the inverse
-- of suppressed — suppressed=false can also mean no hint has arrived yet.
local gr_size_hint_received        = false
local gr_size_hint_last_value      = nil

-- Strength adaptation: same pattern as GRAIN_SIZE_BASE.
-- GRAIN_BASE_STRENGTH is the user's main dial and is never zeroed — it is
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
local GR_TRIM_STEP, GR_TRIM_MIN, GR_TRIM_MAX = 1.12, 0.5, 4.0
local function gr_size_log(kind, extra)
    local ok, p = pcall(mp.command_native, {"expand-path", "~~/photon-grain-size.log"})
    local path = (ok and type(p) == "string") and p or ((os.getenv("HOME") or "/tmp") .. "/photon-grain-size.log")
    local f = io.open(path, "a")
    if not f then return end
    f:write(string.format("%s doc_gen=%d file=%q %s %s\n",
        os.date("%Y-%m-%dT%H:%M:%S%z"), gr_doc.gen, gr_doc.name, kind, extra), "")
    f:close()
end
local function gr_str_log(src, value, mult, var_src, share, n)
    local function num(v) return type(v) == "number" and string.format("%.4f", v) or "-" end
    local tail = string.format("doc_gen=%d file=%q STRENGTH src=%s value=%s mult=%s var_src=%s share=%s n=%s",
        gr_doc.gen, gr_doc.name, src, num(value), num(mult), num(var_src), num(share), n and tostring(n) or "-")
    -- Independent evidence first: written even if the primary log cannot open.
    if mp.get_opt('gor-diag') == 'true' then
        local d = io.open("/tmp/gor_diag.log", "a")
        if d then
            d:write(("photon-grain " .. os.date("%H:%M:%S") .. " " .. tail):sub(1, 4000), "\n")
            d:close()
        end
    end
    local ok, p = pcall(mp.command_native, {"expand-path", "~~/photon-grain-size.log"})
    local path = (ok and type(p) == "string") and p or ((os.getenv("HOME") or "/tmp") .. "/photon-grain-size.log")
    local f = io.open(path, "a")
    if not f then return end
    f:write(os.date("%Y-%m-%dT%H:%M:%S%z"), " ", tail, "\n")
    f:close()
end
-- Returns false when the message belongs to an earlier document (dropped).
local function gr_doc_accept(gen_s, name)
    local gen = tonumber(gen_s)
    if not gen then return true end
    if gen < gr_doc.gen then return false end
    if gen > gr_doc.gen then
        gr_doc.gen, gr_doc.name = gen, name or "-"
        gr_mult_applied = false
        gr_last_mult = nil
    end
    return true
end
-- HONEST CAVEAT: this ceiling is NOT evidence-based. There is no data
-- relating diff_energy to how much strength should rise (size had at
-- least 3 real diff_energy samples; this has none).
local GRAIN_STRENGTH_HINT_MAX      = 1.25
local GRAIN_SOFTNESS_BASE       = GRAIN_SOFTNESS
local GRAIN_CHROMA_SPLIT_BASE   = GRAIN_CHROMA_SPLIT
local GRAIN_DEVELOPMENT_BASE    = GRAIN_DEVELOPMENT
local GRAIN_FINE_WEIGHT_BASE    = GRAIN_FINE_WEIGHT
local GRAIN_CRYSTAL_WEIGHT_BASE = GRAIN_CRYSTAL_WEIGHT
local GRAIN_CLOUD_WEIGHT_BASE   = GRAIN_CLOUD_WEIGHT

local math_max, math_min = math.max, math.min
-- clamp defined in photon-common.lua — fix bugs there, not here.
local clamp = common.clamp
local asym_smooth = common.asym_smooth
local reset_char_state = common.reset_char_state
local new_char_state = common.new_char_state

-- ================================================================
--  3. PHOTON FEED
-- ================================================================
local gr_feed_received = false
local gr_is_hdr        = false

-- Development A: scene hue state. 0-360 degree space, matching ffmpeg
-- signalstats' HUEAVG convention (0=red, ~120=green, ~240=blue).
-- gr_scene_hue_smoothed starts at 0.0 only as a "no data yet" placeholder,
local gr_scene_hue          = nil
local gr_scene_hue_smoothed = 0.0
local gr_hue_has_data       = false
-- HUE_EMA_ALPHA defined in photon-common.lua — fix bugs there, not here.
local GR_HUE_EMA_ALPHA = common.HUE_EMA_ALPHA
-- Midpoint of the suggested ±10-15% range; not confirmed, to be tuned by
-- visual test. When gr_hue_has_data is false, 0.0 is pushed as the
-- GR_HUE_MOD_STRENGTH param, so modulation is effectively off until the
local GR_HUE_MOD_STRENGTH_TARGET = 0.12

--  3b. SCENE-ADAPTIVE RESOLUTION — two-tier (see state block above)
--   • gr_amount: dark/static → more, bright/noisy/motion → less + offset.
--     TIER 1 (density) — continuous, organic-eased, see gr_amount_rendered.

-- Generic character-tier tracker: takes a raw instantaneous reading
-- (0-1) for one parameter's driving signal, returns a stable,
-- long-settled value to actually build that parameter from. `state` is
local function gr_char_track(state, raw, now, dt, is_cut)
    return common.char_track(state, raw, now, dt, is_cut,
        GR_CHAR_TAU, GR_CHAR_DEAD_ZONE, GR_CHAR_DWELL_MIN,
        GR_CHAR_EASE_TAU, GR_CHAR_CUT_EASE_TAU)
end

local gr_char_state = {
    size    = new_char_state(0.50),
    soft    = new_char_state(0.10),
    chroma  = new_char_state(0.20),
    devel   = new_char_state(0.35),
    mix     = new_char_state(0.50),
}

-- Snaps every character parameter to its own neutral default with no
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

local function gr_resolve_adaptive_params(is_cut)
    local base_amount = GRAIN_BASE_AMOUNT_MIN
        + (GRAIN_BASE_AMOUNT_MAX - GRAIN_BASE_AMOUNT_MIN) * (1.0 - gr_frame_peak)
    base_amount = base_amount * (1.0 - 0.35 * clamp(gr_noise_level, 0.0, 1.0))
    base_amount = base_amount * (1.0 - 0.15 * clamp(gr_motion_level, 0.0, 1.0))
    gr_amount = clamp(base_amount + gr_user_offset,
        GRAIN_AMOUNT_CLAMP_MIN, GRAIN_AMOUNT_CLAMP_MAX)

    -- TIER 1 — density: exponential ease toward gr_amount, tau depends
    local now = mp.get_time()
    local dt = math_min(now - (gr_amount_last_t > 0 and gr_amount_last_t or now - 0.1), GR_DT_MAX)
    gr_amount_last_t = now
    local density_tau = is_cut and GR_DENSITY_CUT_TAU or GR_DENSITY_TAU
    gr_amount_rendered = asym_smooth(gr_amount_rendered, gr_amount, density_tau, density_tau, dt)

    -- TIER 2 — character: each parameter's own driving signal, all routed
    -- through the same stability machinery (gr_char_track).
    local char_dt = math_min(now - (gr_char_last_t > 0 and gr_char_last_t or now - 0.1), GR_DT_MAX)
    gr_char_last_t = now

    local dark_t     = clamp(1.0 - gr_frame_peak, 0.0, 1.0)
    local noise_t     = clamp(gr_noise_level, 0.0, 1.0)
    local motion_t     = clamp(gr_motion_level, 0.0, 1.0)
    local contrast_t     = clamp(gr_scene_contrast, 0.0, 1.0)

    local size_t    = gr_char_track(gr_char_state.size,   dark_t,     now, char_dt, is_cut)
    local soft_t    = gr_char_track(gr_char_state.soft,   noise_t,    now, char_dt, is_cut)
    local chroma_t  = gr_char_track(gr_char_state.chroma, motion_t,   now, char_dt, is_cut)
    local devel_t   = gr_char_track(gr_char_state.devel,  contrast_t, now, char_dt, is_cut)
    local mix_t     = gr_char_track(gr_char_state.mix,    dark_t,     now, char_dt, is_cut)

    -- SIZE: swing halved (was ±15%, now ±7.5%) on top of already being
    -- driven by a settled, dwell-confirmed size_t instead of raw dark_t —
    -- amplitude AND rate both needed reducing, not just rate (see the
    GRAIN_SIZE = clamp(GRAIN_SIZE_BASE * (0.925 + 0.15 * size_t), 0.3, (gr_size_hint_suppressed or gr_size_trim > 2.0) and 16.0 or 8.0)

    if GRAIN_SOFTNESS_BASE >= 1.0 then
        GRAIN_SOFTNESS = clamp(1.00 - 0.30 * soft_t, 0.70, 1.00)
    else
        GRAIN_SOFTNESS = clamp(
            GRAIN_SOFTNESS_BASE * (1.0 - 0.25 * soft_t) * (1.0 + 0.10 * size_t),
            0.05, 1.0)
    end

    GRAIN_CHROMA_SPLIT = clamp(GRAIN_CHROMA_SPLIT_BASE * (1.0 - 0.5 * chroma_t), 0.0, 0.5)

    GRAIN_DEVELOPMENT = clamp(
        GRAIN_DEVELOPMENT_BASE * (0.80 + 0.45 * devel_t), 0.1, 1.5)

    local shift = 0.30 * (mix_t - 0.5) * 2.0
    gr_weight_shift = shift
    local fine    = clamp(GRAIN_FINE_WEIGHT_BASE    - shift * 0.5, 0.05, 1.0)
    local crystal = clamp(GRAIN_CRYSTAL_WEIGHT_BASE,                 0.05, 1.0)
    local cloud   = clamp(GRAIN_CLOUD_WEIGHT_BASE   + shift * 0.5, 0.05, 1.0)
    local base_total = GRAIN_FINE_WEIGHT_BASE + GRAIN_CRYSTAL_WEIGHT_BASE + GRAIN_CLOUD_WEIGHT_BASE
    local new_total   = fine + crystal + cloud
    local renorm      = (new_total > 0.0001) and (base_total / new_total) or 1.0
    GRAIN_FINE_WEIGHT    = fine    * renorm
    GRAIN_CRYSTAL_WEIGHT = crystal * renorm
    GRAIN_CLOUD_WEIGHT   = cloud   * renorm
end

-- ================================================================
--  4. GORGRAINSOURCE
-- ================================================================
-- I40 / TRAP-09: mpv caches shader text by path; write once and push live PARAMs.
local GOR_GRAIN_SOURCE = [[
// ================================================================
//  photon-grain - OUTPUT hook: blue-noise grain
//  Host: photon-grain.lua (GOR_GRAIN_SOURCE) -> photon-grain.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!TEXTURE TEX_BLUENOISE
//!SIZE 64 64
//!FORMAT r8
//!FILTER LINEAR
//!BORDER REPEAT
7cfa5f9eda6fccbc75745a286e473af678bb326281348555db99e5c13ae26dfefed0d8b1f8a4
bd923863543fad63e6dc150f978f64cd814f9a14bb0cb9e9d7833faba0a93736450a87cb1ed4
7d7386149aae2fe073c22a043689436196097d4c7b2e6e3d6babe20e8fe36ceb1b088c034ce6
8c60a81906dce7b686aec58204431ba3c30cc1e81a1602db966b32213fd96bb07d5899daaf51
be743de4f470ed17578bb06be65165f205549bb1ef8c7c403bc8dd1d7e31ef99850d3db2439d
df7a4e61016ce03c6e0115b63fcb4172dafaf055c8dc10b46ee428b07ffe50931eb99f0adf3b
74d8ab3bb50c4ce34745bc967a280a35cbab6a2a599e108051949049f5d17a3ff64d76a13c65
ba5f9f602ffa4e8f1b52e72a85b0e09e38c71eed824b2ec7745f4ebbb1fdab4bd02690e27f14
864c5b381dfa6d61b2f10fe6ba701db901d6362a66ace1c572d12f2695c5a633d445fb955524
8dee0514ae54af5caaf3e0bd8d3d6301493259866098e53bb0389b45ebbf8f66c6c118f9b838
95fff2d7fe0b92214a4a991b7ae06b456733bd860f97701a298a4b7dc5d9434abc92031a7500
c01b55b342b21b73a79689b7785fec48840b7c0c7a3d0e5c155e1f80718047b7ab05ab065b33
b8c8ec3dad89f9670183df49bbbe2f724328ed905c6ebdb884cd6993ef1b4cf72a39bb723a05
33643767a902993569716f7e98e92a96045252d27653e2a158c96ee42a09d5e99a0afed2fad4
a4dc1f5c260e7191ce19962446df85d2c118ced95f1e0decee16c93327a46206ede2ea27a039
e76ef7c1a5c4540777451a1775b957044ef8b477f381615d192081c94fecd2bfbc3d1044c526
a5e8a62d4034649be2b64cee51e1a71e8c2ac817614d309dca8c7bc3380fcb50cfb561c8cd39
872ef75c3e71c422313139bead1fa4b3f5c95baca202f7ae597ba07c304027b79359f1f6068e
17b32d146ad890eb8845f3188ae11eb6f6a62ce356d115025a44eec614d91c7ace83fa69269c
83dfb8237860207fbc534defa93feb478431bf90b24b57413774d0b28868fee1a8c05022da87
cd73431e8a73547d9da3cf9488c7f33678618fb4479e15e59360120482f2604228c8f4b3dbe2
1b443196bf76bd12a0c90e80409bfa03e7cdf44b27fe68942dde8d501cb56cfd115851442286
a2318941d47bd34bc0b54a6bc4af824d33953ba73879914a9251933f24e3aeeedd91226da781
44136ab20016bf9f0177b5f5229b0b63c9d0e7c1aaedf0c07ee3d397baa4af10d7a911ef882c
d7f8661e9bc5ea189077bb0edf5ba3211dad40e4e34ab2a593a4d6f46553a9325d619f082bbd
6ba1fb86e6705862cab1999ab479abd5efdd25e1c317c348efeb2d203ac9f674ee4ee1cf105f
39d497c211c77b7a914c4302763e17c42bae9a7d56fb4e5d755ca36201fd221dc9490365014b
473cc2167aa702899778693bb6c98f8dc76ad28ead3056cc137aa5e6af09f1d25a50de674d31
b1b63de3c3071486d2fa1bda5bbae0eada25099abd8bae85e6e09ebd579c8be0060cde0cf7d1
90105ebb152e4282b7f229be427cd3f04818a688ecdac3202806906281774df4a6c2535133c4
2422afb351e83a8d57bcdb110fe8f118354d2f883bdd367dbe320b8ff0f66c25640a1d520138
e218047406a12225eb8ca3b0f84d2f44ad8812702adc49119d91d153b63c7975fdcce5569d0a
7aa83b817aa4cffc52257115aa2f3657bcacdb68a3d54a93f1de9dd871d5127904c8986e8beb
69272ea274ed5e5edc40ec5f45724c51c92e2ce149fc860bac41b61cbbbd307bdad8ac729848
3ab3f4821c62118e435e9a926bd087ffcf48d9d5562747285e3e2197fe4ad2e3c4290c74a02c
ce51feddcf69c708e503b1a3fa52d38c804f2f9b28b3555dc0da8111475d748099120348a76f
f91fb185066e446ea152b6a418fb8ae58d49b05e7dad8a15aff25dc52eca459caf47958e684a
01376febcf0d3ccf3e6222f88ff5a46ae9c91e21a589f8d7830c6df9149054d722b11981066a
de57c8872cf6a8f83e9458f20fc0fd08409fe60df348fc40d446f36d0d6f7a91a650348796fa
bcaab99836e961a3f7160565bfbdb823d3809e1b3ab3f170bb3b62fd0259e979a4099ff1cb1b
4fe615829297073ea11c4dc22a045f916dffca4007dd6091d8f02a558ccec1d63965ea3a5763
e5a1aa3bfc2f90074eec40efb06ee34a0880bb58de466df219adae84553c6fc02bdca0f4de6c
037fbe5c30080d559832671f062b422e56a757313bf1ba894f36e9c04f93720b1f97df83a42e
a539eb055541e6dc252ff6e946865eefe9dc576513d96c8b987fd4f495f1af1c5b02c97b8a5b
cad446288d7f72a9badeac7dccefbd95e91703d2e24886c56567ac21c870cd21944820b4b137
beb58915982a5fd488af24fc219d06b2b11268f55b89e8ad31e1a08b949638a763e5cc65208c
672495282676645830e1ec3db7215e0760bea5bf077b2fe43c000fcda19c10b317c17f6caa3a
58b8cd3377f21c35e325c348eea258c16308f50b9b6a7792ee601a67a83a1177eacbf4769ec7
e441221a9e622d093ea5648537b8398b7bddf54aae05e263eafdd97e921252a15e0fdc26be7f
11d8a55fd0a1fd23a25a12ed1b56a6adcd4765f4b3aa8ad9f6770cd76d6cc7c943fbd705d004
4c032fd0d37de11fd6095db96b0605ea339436d528039455abf37567601a35779556aa8009e5
18a68f2664c61fa03a99230f131628df7cf51d95872d78c3439d9b0b03904d8b26446364aaed
f0ba42983761d7a9797f3e9a83321a9200a533f8a5aaa9c84443c4506f9c66dbae543ebaef5b
a9404d9bbc2d1bce95dd9c308ddb84d348b84d258ec764df5f11b57858e615a0a8f7e423f2cc
19ca8adaea46aab671ddc6fc2b7f0db8edc6bc5c3cae7c17dc353156b46a955a5bcf5fc7e668
6342c0f9a876106cd05ebc21a29d9c0c82500cc5cc2789522068ab88f123eaec9c6946311f88
31c5428178e84f729e982f19bffad23740f8ed6f7ec1f7c80bb2307102e573c1e81c13c19bc0
20d0fc873ae0b18d59f9bdad7e9f484985502e968f1526ba6d0fe886ba26da2b3af2646176d6
47a0b8db34c41f88d64129c7731d9fb32e19f614237380b243f3ddb7c2865bb66f4460fd8394
f50e6dc1f91fc4f350c0e35f18aa5afb516db5d26e11bbe4246d69c5347fe5ec24b4bcf3a627
1794186baeec705a2dd8f0746218734759aae7e4e35e05b9d0cb411872af717a2d074204f021
93ef2cbca97854836ad9aa19fa606299964516816537f15260bd537ce7b9c8c43c583fe98a46
c3ef1a8085a6ce1e558834382cff48dea678cae96c662dba9bd54378220534302a7c553c8892
bbea24dbde168dca7d0e78cc949c29426b9ffcfdd61ac7039819d423b2505c19ee16830129be
e0a25d7948255328583db4e6eb3250bf93c6b16500b7f9c5872b33afb0395e4b30d5a81576db
a8cdc61dd7441338fcab2b98008a753fcc08a8f9bf8856d1fe0b57a7c21ae893accfa60a7f9c
a913bfb51f29e48b753b10794ea75365951db78680ee604bf46d3df3bf139bd2f6635c45eff7
b7a80bd82cd69c3852fb6f8d7254b606e94dc90b35f533a10e9919678e793ee5b426cdf10fe0
d425a69dfb5a5337c60f240770071a6e5e1ae99da383148d41f0ec5609782035335fd3d1f02f
440c508ff9d7a520c2f8915ad3537fca1034d5cf764774b3900d83d720c0129af163273f8eba
a5491407923425cedc1d64e7712e0c923bb0a471d358b508ccb7f2cddf0d917275766fd328ba
b667e4243fdb6a8b96b0293b9ad70c2d899aea513facffb5a3e636e2790aac5d3e846842cc90
c19e392b520ad07c6684b85ef91c2c469948a728abfff43714f76b1c96c6157ce62d40f81140
1adc851603569e29e90ebd895387f2b432c65775be7b170dec49061ea98d73e71c7e791e5c2d
7dadd1452a46c3f6330b1f877b76a00247ea5a1754c830684ce122d32c872c4e69f5ee715b05
98cd41781024049ed23537c22b7115b128cced31f572f8401733d94b8c34ceba85b782f6a51d
a9aa3904746ff1cfb779f27bd784f9b56de012c0d534167c820ad650cc7eae6758ffac0166d4
5aaf39bc74a7502b10629355cd7beaf875cb4dfbd09754c7e17ee0137dda9e6cab30a55bc6c5
2b8ae84cadb0037690a6e737fd2319874eefbb0e814fae0819f09a68db598536f976d5da274c
9f4e273ca2cb97410a5f0e360288af694fd9c7971d6a5b4a0b0c0d09b5239c91fc643edd8350
8fb34a7e32d42a983577cdbff06253a7f48159f3d98db99e968e059e2769b020bb04389cf8ce
1d24f06f9546b51d9fceca8ce99aac109f2378341da0fee318f5d586c0df07c253f02c6c70af
89ea2017c4ac26d60ee141b36efa2eac4b8f4e238e4fad72a6924c4da80df5d14efa6b08d4a3
464fcb66ebd877a9103cc785b913304aa72b008c4f8458c3093b91c5b0d69642c9823fbc226d
37ddce4b9ff21b2163cf4b01743d593060cbc690732e32665b10f28f9a2e8b6834946ae41261
8313dcdf667e3c64f335b234b770eb0885fc512591c3c1407fe013a2f5cf98a023d2546682eb
0dd21f957e5a3a3114ecca0690f2f17723621442dde18dde8752a18985b49335b9fdd58f6a36
7efcec07c254017c7d356056b2cad3ee3dbc71f3de14c1f9c49fc6ab0a6f491cc22c7bb4f651
d51e9bca82fb84e29d639c29441af4a95dfabdf48b8664f00ac3d0941c7626323de5998a59dd
648ee88acb728941ee062a4f0e2c67702ca84487e2d125dbcf0ab9413ad9c044fcc0b8216c43
e751a31eb1385e0db10fb984926aae5939d63d84b89b038442fc3f781047f8d4f752d9a1948e
8429f6cc77b4c9deff5d5385a0630f1e7d7942a225a1b916679dfa22f557f76ac8132d8bc423
42f77ecb4c24b4e2830e5761977f9e2733bf5d17973f9826e427bf087cda75f7c663d1539d41
705ba81839c28e37cb8dec028232991ba97e20a4458b9dba8168665d798ec58cfb7b0cbebd46
caa4296ba741a01069edc2e58ed9aa3255e4704dfe8ce22fa203d8edd5ddb349e1824eeb4c4b
5d43ce6c307cd1f799a245eded7605e422928e35e76fad9c6bf9cc0792e28a36120a3d128bb0
097c68a3b70f4689fba83009eb2bc4734bd795b869310a7ef120619412d9d0f61c7a4f5cd1a2
8835059a740413706118fcfd5d1345e7c391dbb421a281386dbb29a2ef5060d8cf349ccde5ce
6e93f76c19775fb60b39ea084604d6809d3b8bb1c616df5680b21c4801bedb203554118e2e3e
ed558cb7823c67e7366ead134c7f4f0d16563eee5ac473453e59d85a27f9ced12b4bc8dfcf51
978fc2b4bbdf399f5a2c0154271f0ee5703f91f065bab5e072c4966b02dffe2468689952fbc3
30fd05db6166a8b80bc39fd75759b887164eae97fbeada7909a17bd3fb36dc5808e6a4cb7aa3
fee3d5298a326254d404df94802d29d159e875a493190807de55b93224b23ae77ad8158a12f3
001fcba5124eb34f9b65b711d62b00665cbfc61e8fd173ca52e834a365215db5ac7d753c4453
c84346bfcae823fed629be5c73a102b6d369a0cc7562f86649abe1699f66e30f4a7011e440e0
8049f3f41168b093717526a71681fbbe5cc2b9ef71c7b6d6098cfc0efd473157b26ae35c993c
de84ebe8fd64ee3784a2d82069ce49dd1bc5d3ac1a77e791736c5914975a791caf385607d80d
6f092dde170280eea3dcda4afebe674921d0d2e82fa625af02833e9aab25

//!PARAM GR_FRAME_PEAK
//!TYPE DYNAMIC float
0.5

//!PARAM GR_SCENE_CONTRAST
//!TYPE DYNAMIC float
0.35

//!PARAM GR_NOISE_LEVEL
//!TYPE DYNAMIC float
0.10

//!PARAM GR_MOTION_LEVEL
//!TYPE DYNAMIC float
0.20

//!PARAM GR_AMOUNT
//!TYPE DYNAMIC float
1.0

//!PARAM GR_ANIM_BUCKET
//!TYPE DYNAMIC float
0.0

//!PARAM GR_IS_HDR
//!TYPE DYNAMIC float
0.0

//!PARAM GR_SCENE_HUE
//!TYPE DYNAMIC float
0.0

//!PARAM GR_HUE_MOD_STRENGTH
//!TYPE DYNAMIC float
0.0

//!PARAM GR_RENDER_DENSITY
//!TYPE DYNAMIC float
0.0

//!PARAM GR_SIZE_COEFFICIENT
//!TYPE DYNAMIC float
0.0

//!PARAM GRAIN_SIZE
//!TYPE DYNAMIC float
1.2

//!PARAM GRAIN_SOFTNESS
//!TYPE DYNAMIC float
1.0

//!PARAM CHROMA_SPLIT
//!TYPE DYNAMIC float
0.5

//!PARAM DEVELOPMENT
//!TYPE DYNAMIC float
0.4

//!PARAM FINE_WEIGHT
//!TYPE DYNAMIC float
0.25

//!PARAM CRYSTAL_WEIGHT
//!TYPE DYNAMIC float
0.40

//!PARAM CLOUD_WEIGHT
//!TYPE DYNAMIC float
0.45

//!PARAM BASE_STRENGTH
//!TYPE float
5.0

//!PARAM FINE_SIZE_RATIO
//!TYPE float
0.5

//!PARAM CLOUD_SIZE_RATIO
//!TYPE float
2.2

//!PARAM SKEW_STRENGTH
//!TYPE float
0.0

//!PARAM GR_SHADOW_SENSITIVITY
//!TYPE float
1.8

//!PARAM GR_MIDTONE_SENSITIVITY
//!TYPE float
1.5

//!PARAM GR_HIGHLIGHT_SENSITIVITY
//!TYPE float
2.7

//!PARAM STOCK_PRESET
//!TYPE int
5

//!PARAM RES_ADAPT
//!TYPE int
1

//!PARAM GR_MONO_MODE
//!TYPE DEFINE
0

//!PARAM GRAIN_DEBUG_VISUALIZE
//!TYPE DEFINE
0

//!HOOK OUTPUT
//!BIND HOOKED
//!BIND TEX_BLUENOISE
//!DESC photon-grain v3.2.0 Halide — hybrid blue-noise tile film grain

// Runtime values arrive as PARAM uniforms (declared above the hook
// block). Only GR_WINDOW_COMP_* stay baked: they never change at
// runtime, and the Lua constants win over these literals at the
// one-time write
#define GR_WINDOW_COMP_MIN    0.5
#define GR_WINDOW_COMP_MAX    1.0

// Film stock profiles (Kodak Vision3 / Fujifilm Eterna / Kodachrome)
const vec3 stock_props[6] = vec3[6](
    vec3(1.00, 0.88, 1.10),  // Portra 400
    vec3(0.90, 0.90, 0.95),  // Ektar 100
    vec3(1.05, 0.85, 1.15),  // Vision3 250D
    vec3(1.10, 0.80, 1.20),  // Kodachrome 64
    vec3(1.00, 0.95, 1.00),  // Tri-X 400
    vec3(0.95, 0.92, 1.05)   // HP5 Plus
);

// Development A: modulates grain-layer multipliers by scene hue
// (ffmpeg HUEAVG: 0°=red, ~120°=green, ~240°=blue). Each channel peaks at
// its own 120° arc center (1.0+strength), identity outside, smoothstep blend.
vec3 scene_hue_modulation(float hue_deg) {
    float d_r = min(abs(hue_deg - 0.0),   360.0 - abs(hue_deg - 0.0));
    float d_g = min(abs(hue_deg - 120.0), 360.0 - abs(hue_deg - 120.0));
    float d_b = min(abs(hue_deg - 240.0), 360.0 - abs(hue_deg - 240.0));
    float w_r = 1.0 - smoothstep(0.0, 60.0, d_r);
    float w_g = 1.0 - smoothstep(0.0, 60.0, d_g);
    float w_b = 1.0 - smoothstep(0.0, 60.0, d_b);
    return vec3(1.0 + GR_HUE_MOD_STRENGTH * w_r,
                1.0 + GR_HUE_MOD_STRENGTH * w_g,
                1.0 + GR_HUE_MOD_STRENGTH * w_b);
}

// Hash: Ashima-Arts permute/mod289 chain
float mod289(float x) { return x - floor(x / 289.0) * 289.0; }
float permute(float x) { float xr = mod289(x); return mod289((34.0 * xr + 1.0) * xr); }
float rand01(float x) { return fract(x / 41.0); }

// Blue-noise tile sampling with per-tile dihedral decorrelation.
// 64×64 tile, FILTER LINEAR, 8 transforms + offset per tile copy.
// Spatial layout frame-independent; only amplitude varies per frame.
vec2 dihedral_transform(vec2 p, int sel) {
    if (sel >= 4) { p.x = mod(64.0 - p.x, 64.0); sel -= 4; }
    if (sel == 1) return vec2(p.y, mod(64.0 - p.x, 64.0));
    if (sel == 2) return vec2(mod(64.0 - p.x, 64.0), mod(64.0 - p.y, 64.0));
    if (sel == 3) return vec2(mod(64.0 - p.y, 64.0), p.x);
    return p;
}

float sample_bluenoise(vec2 pos_px, float cell_size, float salt, float frame_bucket, float time_seed) {
    vec2 cell_pos = pos_px / max(cell_size, 0.01);
    vec2 tile_id = floor(cell_pos / 64.0);
    vec2 local_p = mod(cell_pos, 64.0);

    // Spatial hash: frame-dependent dihedral transform + texel offset
    float h = permute(tile_id.x * 41.0 + tile_id.y * 113.0 + salt * 7.0 + frame_bucket * time_seed);
    int sel = int(floor(rand01(h) * 8.0));
    float oh = permute(h + 5.0);
    float ox = floor(rand01(oh) * 64.0);
    float oy = floor(rand01(permute(oh + 1.0)) * 64.0);
    vec2 lp = mod(local_p + vec2(ox, oy), 64.0);
    vec2 tp = dihedral_transform(lp, sel);

    // 4-sample box blur for organic softness
    vec2 d = vec2(0.5 / 64.0, 0.0);
    float raw = (TEX_BLUENOISE_tex((tp + 0.5) / 64.0 + d.xx).r
              + TEX_BLUENOISE_tex((tp + 0.5) / 64.0 + d.yy).r
              + TEX_BLUENOISE_tex((tp + 0.5) / 64.0 - d.xx).r
              + TEX_BLUENOISE_tex((tp + 0.5) / 64.0 - d.yy).r) * 0.25;
    float dither = raw * 2.0 - 1.0;

    // Per-cell amplitude: independent hash, frame-varying
    vec2 cell_xy = floor(cell_pos);
    float amp_h = permute(cell_xy.x * 53.0 + cell_xy.y * 97.0 + salt * 13.0 + frame_bucket * time_seed);
    float amp = rand01(amp_h);
    return dither * amp;
}

// Source-resolution grain scaling (uses input_size, not HOOKED_size)
int res_profile_grain() {
    float h = input_size.y;
    if (h < 700.0)  return 0;
    if (h < 1100.0) return 1;
    return 2;
}
void res_scale_grain(out float scale_mult, out float density_mult) {
    if (RES_ADAPT == 0) { scale_mult = 1.0; density_mult = 1.0; return; }
    int rp = res_profile_grain();
    if (rp == 0)      { scale_mult = 2.00; density_mult = 0.70; }
    else if (rp == 1) { scale_mult = 1.00; density_mult = 1.00; }
    else              { scale_mult = 0.50; density_mult = 0.85; }
}

// Window-size compensation (sqrt-scaled, 1.5x capped)
float window_compensation() {
    float h = max(HOOKED_size.y, 1.0);
    return clamp(sqrt(1600.0 / h), GR_WINDOW_COMP_MIN, GR_WINDOW_COMP_MAX);
}

// Luma-dependent gain: Gaussian midtone peak + shadow/highlight floors
float luma_adapt(float luma) {
    float deviation = (luma - 0.40) / 0.45;
    float midtone = exp(-deviation * deviation);
    float shadow_floor = 0.12 * (1.0 - smoothstep(0.0, 0.30, luma));
    float highlight_floor = 0.20 * smoothstep(0.5, 0.85, luma);
    return clamp(midtone + shadow_floor + highlight_floor, 0.0, 1.05);
}

// Zone sensitivity sliders (DaVinci Resolve / Exposure X7 style)
float zone_sensitivity(float luma) {
    float shadow_w    = 1.0 - smoothstep(0.0, 0.15, luma);
    float highlight_w = smoothstep(0.95, 1.0, luma);
    float midtone_w   = clamp(1.0 - shadow_w - highlight_w, 0.0, 1.0);
    return shadow_w * GR_SHADOW_SENSITIVITY
         + midtone_w * GR_MIDTONE_SENSITIVITY
         + highlight_w * GR_HIGHLIGHT_SENSITIVITY;
}

// HDR true-black gate
float hdr_black_gate(float luma, float is_hdr) {
    float gate = smoothstep(0.0, 0.06, luma);
    gate = pow(gate, 2.2);
    return mix(1.0, gate, is_hdr);
}

// Three-layer grain core: FINE + CRYSTAL + CLOUD
float soft_grain_layer(vec2 pos_px, float cell_size, float softness,
                        float salt, float frame_bucket, float time_seed) {
    float hard = sample_bluenoise(pos_px, cell_size, salt, frame_bucket, time_seed);
    vec2 soft_offset = vec2(cell_size, cell_size) * 0.750;
    float soft = sample_bluenoise(pos_px + soft_offset, cell_size, salt, frame_bucket, time_seed);
    return mix(hard, soft, clamp(softness, 0.0, 1.0));
}

float grain_layers(vec2 pos_px, float eff_grain_size, float channel_seed, float frame_bucket) {
    float cell_fine    = eff_grain_size * FINE_SIZE_RATIO;
    float cell_crystal = eff_grain_size;
    float cell_cloud   = eff_grain_size * CLOUD_SIZE_RATIO;
    float salt_fine    = 3.0  + channel_seed;
    float salt_crystal = 11.0 + channel_seed;
    float salt_cloud   = 29.0 + channel_seed;
    float tseed_fine    = 3.30277563773  + channel_seed;
    float tseed_crystal = 19.61803398875 + channel_seed;
    float tseed_cloud   = 7.41421356237  + channel_seed;
    float fine    = soft_grain_layer(pos_px, cell_fine,    GRAIN_SOFTNESS, salt_fine,    frame_bucket, tseed_fine);
    float crystal = soft_grain_layer(pos_px, cell_crystal, GRAIN_SOFTNESS, salt_crystal, frame_bucket, tseed_crystal);
    float cloud   = soft_grain_layer(pos_px, cell_cloud,   GRAIN_SOFTNESS, salt_cloud,   frame_bucket, tseed_cloud);
    float w_fn = max(FINE_WEIGHT, 0.0);
    float w_cr = max(CRYSTAL_WEIGHT, 0.0);
    float w_cl = max(CLOUD_WEIGHT, 0.0);
    float wsum = max(w_fn + w_cr + w_cl, 0.001);
    float raw = (fine * w_fn + crystal * w_cr + cloud * w_cl) / wsum;
    return raw * DEVELOPMENT;
}

// 3x3 local luma variance — flat areas → higher grain, textured areas → lower
float local_texture_variance(float center_luma) {
    vec2 d = 1.0 / HOOKED_size;
    vec3 lw = vec3(0.299, 0.587, 0.114);
    float s = 0.0, s2 = 0.0, l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2(-d.x, -d.y)).rgb, lw); s += l; s2 += l*l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2( 0.0, -d.y)).rgb, lw); s += l; s2 += l*l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2( d.x, -d.y)).rgb, lw); s += l; s2 += l*l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2(-d.x,  0.0)).rgb, lw); s += l; s2 += l*l;
    l = center_luma; s += l; s2 += l*l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2( d.x,  0.0)).rgb, lw); s += l; s2 += l*l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2(-d.x,  d.y)).rgb, lw); s += l; s2 += l*l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2( 0.0,  d.y)).rgb, lw); s += l; s2 += l*l;
    l = dot(HOOKED_tex(HOOKED_pos + vec2( d.x,  d.y)).rgb, lw); s += l; s2 += l*l;
    s /= 9.0; s2 /= 9.0;
    return max(0.0, s2 - s * s);
}


// Main hook — //HOOK OUTPUT (after photon-sharp at MAINPRESUB)
vec4 hook() {
    vec4 color = HOOKED_tex(HOOKED_pos);

    // Playback position is the animation clock. The Lua owner advances this
    // bucket only when mpv reports a new time-pos, never on a render/HUD
    // redraw. In a cache stall, the bucket is held even if mpv reports a
    // transient position update. No `frame` or `random` render clock here.
    float frame_bucket = GR_ANIM_BUCKET;

#if GRAIN_DEBUG_VISUALIZE == 1
    vec2 dbg_pos_px = HOOKED_pos * HOOKED_size;
    float dbg_raw = soft_grain_layer(dbg_pos_px, GRAIN_SIZE, GRAIN_SOFTNESS, 11.0, frame_bucket, 19.61803398875) * 50.0;
    return vec4(color.rgb + vec3(dbg_raw), color.a);
#endif

    float peak   = clamp(float(GR_FRAME_PEAK), 0.0, 1.0);
    float noise  = clamp(float(GR_NOISE_LEVEL), 0.0, 1.0);
    float motion = clamp(float(GR_MOTION_LEVEL), 0.0, 1.0);
    float amount = clamp(float(GR_AMOUNT), 0.0, 10.0);
    float hdr_flag = float(GR_IS_HDR);

    float scale_mult, density_mult;
    res_scale_grain(scale_mult, density_mult);
    // HDR: finer grain (75% of nominal size)
    float eff_size = GRAIN_SIZE * scale_mult * window_compensation() * mix(1.0, 0.75, hdr_flag);
    // Host coefficient replaces scale*window; zero preserves the old expression.
    if (GR_SIZE_COEFFICIENT > 0.0)
        eff_size = GRAIN_SIZE * GR_SIZE_COEFFICIENT * mix(1.0, 0.75, hdr_flag);

    vec2 pos_px = HOOKED_pos * HOOKED_size;
    float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    float luma_gain = luma_adapt(luma) * zone_sensitivity(luma);

    // Letterbox/pillarbox gate
    {
        vec2 d = 1.0 / HOOKED_size;
        float l00 = luma;
        float l10 = dot(HOOKED_tex(HOOKED_pos + vec2(d.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
        float l01 = dot(HOOKED_tex(HOOKED_pos + vec2(0.0, d.y)).rgb, vec3(0.299, 0.587, 0.114));
        float l11 = dot(HOOKED_tex(HOOKED_pos + d).rgb, vec3(0.299, 0.587, 0.114));
        float mean = (l00 + l10 + l01 + l11) * 0.25;
        float var  = 0.25 * ((l00-mean)*(l00-mean) + (l10-mean)*(l10-mean) + (l01-mean)*(l01-mean) + (l11-mean)*(l11-mean));
        luma_gain *= smoothstep(0.0, 1e-30, var);
    }

    float adapt = amount;
    adapt *= 1.0 + 0.8 * (1.0 - peak);
    adapt *= 1.0 - smoothstep(0.05, 0.35, noise) * 0.5;
    adapt *= mix(0.80, 1.20, motion);
    float is_hdr = step(1.0, max(max(color.r, color.g), color.b));
    adapt *= mix(1.0, 0.55, is_hdr);
    luma_gain *= hdr_black_gate(luma, is_hdr);

    // Texture-aware grain density: flat areas → full grain, textured → reduced
    float tex_var = local_texture_variance(luma);
    float tex_density = 1.0 - smoothstep(0.0, 0.008, tex_var) * 0.35;

    // Per-pixel motion proxy: horizontal spatial gradient, scaled by scene motion
    float luma_n = dot(HOOKED_tex(HOOKED_pos + vec2(2.0 / HOOKED_size.x, 0.0)).rgb, vec3(0.299, 0.587, 0.114));
    float px_motion = smoothstep(0.02, 0.10, abs(luma - luma_n)) * motion;

    // Hue-modulated stock_props. Under GR_MONO_MODE sp is unused (see the
    // #if GR_MONO_MODE below), so no extra bypass is needed here.
    vec3 sp = stock_props[STOCK_PRESET] * scene_hue_modulation(GR_SCENE_HUE);
    // Host density replaces the old value once; zero preserves static fallback.
    float render_density = GR_RENDER_DENSITY > 0.0 ? GR_RENDER_DENSITY : density_mult;
    float amp = luma_gain * (BASE_STRENGTH / 10.0) * adapt * render_density;
    amp *= tex_density;
    amp *= 1.0 + 0.12 * px_motion;

    // Per-channel RGB grain: each channel independent; CHROMA_SPLIT=0 → independent, 1 → correlated
    float g_r_raw = grain_layers(pos_px, eff_size, 0.0,  frame_bucket);
    float g_g_raw = grain_layers(pos_px, eff_size, 17.0, frame_bucket);
    float g_b_raw = grain_layers(pos_px, eff_size, 37.0, frame_bucket);
    float g_luma  = g_r_raw * 0.299 + g_g_raw * 0.587 + g_b_raw * 0.114;
    float skew = -SKEW_STRENGTH * (luma - 0.5);

    float g_r, g_g, g_b;
#if GR_MONO_MODE
    // photon-chrome active: real B&W stock has ONE silver-halide layer, not
    // three dye layers — R/G/B must be bit-identical, not just correlated
    // via CHROMA_SPLIT (stock_props' per-channel multipliers below would
    float g_mono_raw = g_luma + skew;
    float g_mono = sign(g_mono_raw) * pow(abs(g_mono_raw), 0.85);
    g_r = g_mono; g_g = g_mono; g_b = g_mono;
#else
    g_r = mix(g_r_raw, g_luma, CHROMA_SPLIT) + skew;
    g_g = mix(g_g_raw, g_luma, CHROMA_SPLIT) + skew;
    g_b = mix(g_b_raw, g_luma, CHROMA_SPLIT) + skew;

    float chroma_blend = clamp(CHROMA_SPLIT * 4.0, 0.0, 1.0);
    g_r *= mix(1.0, sp.x, chroma_blend);
    g_g *= mix(1.0, sp.y, chroma_blend);
    g_b *= mix(1.0, sp.z, chroma_blend);
#endif

    vec3 cg = vec3(g_r, g_g, g_b) * amp;
    return vec4(color.rgb + cg, color.a);
}
]]

-- ================================================================
--  5. SHADER WRITE / PARAM PUSH
-- ================================================================
--  used to be baked per-rewrite now arrives as a //!PARAM uniform,
--  pushed via change-list glsl-shader-opts. mpv gpu-next caches parsed

-- shader_dir defined in photon-common.lua — fix bugs there, not here.
local gr_shader_path = nil
local gr_shader_written = false

local function gr_ensure_path()
    if gr_shader_path then return gr_shader_path end
    gr_shader_path = common.shader_path("photon-grain")
    return gr_shader_path
end

-- One-time write at script load. GR_WINDOW_COMP_* are baked from the
-- Lua constants (they always won over the template literals, via the
-- same gsub the old per-rewrite renderer ran).
local function gr_write_shader()
    if gr_shader_written then return true end
    local path = gr_ensure_path()
    if not path then return false end
    local content = GOR_GRAIN_SOURCE
    content = content:gsub("#define GR_WINDOW_COMP_MIN%s+%-?[%d.]+",
        string.format("#define GR_WINDOW_COMP_MIN    %.4f", GR_WINDOW_COMP_MIN))
    content = content:gsub("#define GR_WINDOW_COMP_MAX%s+%-?[%d.]+",
        string.format("#define GR_WINDOW_COMP_MAX    %.4f", GR_WINDOW_COMP_MAX))
    local f = io.open(path, "w")
    if not f then mp.msg.error("photon-grain: failed to write shader: " .. path); return false end
    f:write(content); f:close()
    gr_shader_written = true
    mp.msg.info("photon-grain v3.2.0: shader written -> " .. path)
    return true
end

-- photon-chrome integration: set by photon-chrome-set-mono-grain, NOT a
-- user control (no direct script-message toggles this from input.conf).
-- Chrome owns this — grain only reflects what chrome tells it. Defaults
local gr_mono_mode = false
local gr_mono_saved_stock_preset = nil  -- restore point when mono mode ends
local gr_mono_saved_softness     = nil

-- Every non-baked value, in one payload so multi-field changes (e.g.
-- mono-mode + stock + softness) land in a single render-options update
-- instead of tearing across frames. Deduped in photon-common: an
-- The animation's only clock is playback position. The GPU receives a
-- discrete bucket; repeated renders cannot advance it. The original clock
-- stepped at ~0.75*24 buckets/second (or 0.75*fps below 5 fps).
local gr_anim_bucket = 0.0
local gr_anim_pos = nil
local gr_last_feed_pos = nil
local gr_anim_offset = 0.0

local function gr_push_params()
    gr_refresh_adaptive()
    common.push_params("photon-grain", {
        {"GR_FRAME_PEAK", gr_frame_peak, "f"},
        {"GR_SCENE_CONTRAST", gr_scene_contrast, "f"},
        {"GR_NOISE_LEVEL", gr_noise_level, "f"},
        {"GR_MOTION_LEVEL", gr_motion_level, "f"},
        {"GR_AMOUNT", gr_amount_rendered, "f"},
        {"GR_ANIM_BUCKET", gr_anim_bucket, "f"},
        {"GR_IS_HDR", gr_is_hdr and 1.0 or 0.0, "f"},
        {"GR_SCENE_HUE", gr_scene_hue_smoothed, "f"},
        {"GR_HUE_MOD_STRENGTH", gr_hue_has_data and GR_HUE_MOD_STRENGTH_TARGET or 0.0, "f"},
        {"GRAIN_SIZE", GRAIN_SIZE, "f"},
        {"GR_SIZE_COEFFICIENT", gr_size_coefficient, "f"},
        {"GR_RENDER_DENSITY", gr_render_density or 0.0, "f"},
        {"GRAIN_SOFTNESS", GRAIN_SOFTNESS, "f"},
        {"CHROMA_SPLIT", GRAIN_CHROMA_SPLIT, "f"},
        {"DEVELOPMENT", GRAIN_DEVELOPMENT, "f"},
        {"FINE_WEIGHT", GRAIN_FINE_WEIGHT, "f"},
        {"CRYSTAL_WEIGHT", GRAIN_CRYSTAL_WEIGHT, "f"},
        {"CLOUD_WEIGHT", GRAIN_CLOUD_WEIGHT, "f"},
        {"BASE_STRENGTH", GRAIN_BASE_STRENGTH, "f"},
        {"FINE_SIZE_RATIO", GRAIN_FINE_SIZE_RATIO, "f"},
        {"CLOUD_SIZE_RATIO", GRAIN_CLOUD_SIZE_RATIO, "f"},
        {"SKEW_STRENGTH", GRAIN_SKEW_STRENGTH, "f"},
        {"GR_SHADOW_SENSITIVITY", GRAIN_SHADOW_SENSITIVITY, "f"},
        {"GR_MIDTONE_SENSITIVITY", GRAIN_MIDTONE_SENSITIVITY, "f"},
        {"GR_HIGHLIGHT_SENSITIVITY", GRAIN_HIGHLIGHT_SENSITIVITY, "f"},
        {"STOCK_PRESET", GRAIN_STOCK_PRESET, "i"},
        {"RES_ADAPT", GRAIN_RES_ADAPT, "i"},
        {"GR_MONO_MODE", gr_mono_mode and 1 or 0, "i"},
        {"GRAIN_DEBUG_VISUALIZE", GRAIN_DEBUG_VISUALIZE, "i"},
    })
end

-- Reuse mpv's pause/cache state and time-pos (the same stall signals that
-- stop the live GS probe). A frozen time-pos never creates a new bucket.
-- Cache underruns explicitly hold even if mpv emits a stray position change.
-- Paused seeking is permitted to change grain with the new image.
local function gr_update_anim_pos(pos)
    if type(pos) ~= "number" or pos ~= pos then return end
    if mp.get_property_bool("paused-for-cache", false) then return end
    if pos == gr_anim_pos then return end
    gr_anim_pos = pos
    local rate = gr_fps >= 5.0 and 18.0 or (gr_fps * 0.75)
    local bucket = math.floor(math.max(pos, 0.0) * rate) + gr_anim_offset
    if bucket ~= gr_anim_bucket then
        gr_anim_bucket = bucket
        if enabled then gr_push_params() end
    end
end
mp.observe_property("time-pos", "number", function(_, pos) gr_update_anim_pos(pos) end)
local function gr_update_paused()
    local pc = mp.get_property_bool("paused-for-cache", false)
    -- User pause normally keeps time-pos unchanged. A paused seek updates
    -- the bucket for the newly selected frame through time-pos observation.
    -- Cache exit can arrive without a time-pos observer event. The next
    -- actual position read catches up, with no wall-clock animation jump.
    if not pc then gr_update_anim_pos(mp.get_property_number("time-pos")) end
end
mp.observe_property("pause", "bool", function() gr_update_paused() end)
mp.observe_property("paused-for-cache", "bool", function() gr_update_paused() end)

-- glsl-shaders ownership contract: each script only touches its own path.
local function gr_ensure_glsl_list_sane(shaders)
    return common.ensure_glsl_list_sane(shaders, {gr_ensure_path()})
end

-- Grain anchors the front of the OUTPUT-stage chain: negativ and chrome
-- both position themselves relative to grain's path, never the reverse,
-- so grain always inserts at position 1. Idempotent — enable and the 1Hz
local function gr_add_shader()
    local path = gr_ensure_path()
    if not path then return end
    local shaders = gr_ensure_glsl_list_sane(mp.get_property_native("glsl-shaders") or {})
    local filtered = {}
    for _, p in ipairs(shaders) do
        if p ~= path then table.insert(filtered, p) end
    end
    table.insert(filtered, 1, path)
    mp.set_property_native("glsl-shaders", filtered)
end

-- Enable ordering: file on disk first, params pushed second, path added
-- last — the newly loaded shader's first frame already has live values
-- instead of PARAM defaults.
local function gr_enable()
    common.trace_record("shader-enable-attempt", {revision=gr_control_revision, strength=GRAIN_BASE_STRENGTH, size=GRAIN_SIZE})
    gr_write_shader()
    gr_push_params()
    gr_add_shader()
end

local function gr_shader_in_list()
    local path = gr_ensure_path()
    if not path then return true end  -- can't check, assume fine
    local shaders = mp.get_property_native("glsl-shaders") or {}
    for _, p in ipairs(shaders) do
        if p == path then return true end
    end
    return false
end

local function gr_remove_shader()
    common.trace_record("shader-remove-attempt", {revision=gr_control_revision})
    if not gr_shader_path then return end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local filtered, changed = {}, false
    for _, p in ipairs(shaders) do
        if p == gr_shader_path then changed = true
        else table.insert(filtered, p) end
    end
    if changed then mp.set_property_native("glsl-shaders", filtered) end
end

-- ================================================================
--  6. MPV HOOKS / SCRIPT-MESSAGES
-- ================================================================
-- Handlers change a Lua value, then call gr_push_params() — one deduped
-- change-list add, no file I/O, no shader rebuild. The 1Hz self-heal
-- timer only checks that the path is still in glsl-shaders.

-- Publishes grain state to photon.lua HUD (both on/off branches, instant on toggle).
-- Extended: adaptive grain-size (GRAIN_SIZE_BASE, hint status) and dynamic hue
-- (smoothed scene hue, whether modulation is active) added to the HUD. The
local gr_publish_serial = 0
local function gr_publish_hud_state()
    gr_publish_serial = gr_publish_serial + 1
    mp.commandv("script-message", "photon-grain-hud-state",
        tostring(enabled), string.format("%.2f", gr_amount_rendered), string.format("%.0f", gr_fps),
        string.format("%.3f", GRAIN_SIZE_BASE),
        tostring(gr_size_hint_received),
        tostring(gr_size_hint_suppressed),
        gr_size_hint_last_value and string.format("%.3f", gr_size_hint_last_value) or "",
        tostring(gr_hue_has_data),
        string.format("%.1f", gr_scene_hue_smoothed),
        string.format("%.3f", GRAIN_BASE_STRENGTH),
        tostring(gr_strength_hint_received),
        tostring(gr_strength_hint_suppressed),
        gr_strength_hint_last_value and string.format("%.3f", gr_strength_hint_last_value) or "",
        -- GS deconvolution mirror (appended last; older photon.lua builds
        -- simply never read them): RENDERED size/development/softness —
        -- the probe subtracts the field the GPU is actually drawing.
        string.format("%.4f", GRAIN_SIZE),
        string.format("%.4f", GRAIN_DEVELOPMENT),
        string.format("%.4f", GRAIN_SOFTNESS),
        -- GPU-truth amount (shader clamps GR_AMOUNT to [0,10]) and his
        -- manual offset: the probe subtracts what is actually drawn, and
        -- anchors its strength target at the offset-free amount.
        string.format("%.2f", math.min(math.max(gr_amount_rendered, 0.0), 10.0)),
        string.format("%.2f", gr_user_offset),
        -- layer-weight shift (dark-scene rebalance): moves the baked
        -- tables the probe subtracts; missing on old builds = 0.
        string.format("%.3f", gr_weight_shift),
        -- RES_ADAPT runtime toggle changes the rendered res profile;
        -- the probe's eff model must follow it. Missing = on (1).
        tostring(GRAIN_RES_ADAPT),
        -- Menu state is the enabled target, even before a video has loaded.
        tostring(grain_target_enabled),
        tostring(gr_source_h or 0), tostring(gr_output_h or 0),
        string.format("%.6f", gr_size_coefficient),
        gr_strength_k and tostring(gr_strength_k) or "",
        -- Requested mode; the applied coefficient travels separately above.
        tostring(gr_adaptive_mode),
        gr_render_density and "strength adaptation: measured from sampled source noise, Mac-pending"
            or "strength adaptation: not applied, fixed density",
        gr_render_density and string.format("%.2f", gr_render_density) or "",
        tostring(gr_effective_h or 0),
        gr_strength_src or "",
        string.format("%.3f", gr_size_trim), tostring(gr_doc.gen), tostring(gr_publish_serial), tostring(gr_control_revision),
        -- 118: final rendered effective size, shader-equivalent (append-only
        -- field 35; positions 1-34 unchanged). Exact host expression of the
        -- shader's adaptive branch: eff_size = GRAIN_SIZE * GR_SIZE_COEFFICIENT
        -- * mix(1.0, 0.75, GR_IS_HDR). The legacy branch (coefficient 0) is not
        -- host-reproducible (res_scale_grain x window_compensation read hook
        -- texture size), so it reports "na".
        gr_size_coefficient > 0.0
            and string.format("%.4f", GRAIN_SIZE * gr_size_coefficient * (gr_is_hdr and 0.75 or 1.0))
            or "na")
end

-- One mode writer lives in photon.lua; same-frame atomicity unverified.
mp.register_script_message("photon-adaptive-program-state", function(value)
    gr_adaptive_mode = value == "true"
    if gr_shader_written then gr_push_params() else gr_refresh_adaptive() end
    gr_publish_hud_state()
end)
for _, property in ipairs({"video-dec-params", "video-params", "video-out-params", "osd-dimensions"}) do
    mp.observe_property(property, "native", function()
        if gr_shader_written then gr_push_params() else gr_refresh_adaptive() end
        gr_publish_hud_state()
    end)
end

local gr_known_clear = false  -- skips redundant glsl-shaders reads when disabled

local function gr_periodic_update()
    gr_publish_hud_state()
    if enabled then
        gr_known_clear = false
        if not gr_shader_in_list() then gr_add_shader() end
    elseif not gr_known_clear then
        gr_remove_shader()
        gr_known_clear = true
    end
end

mp.add_periodic_timer(1.0, gr_periodic_update)

mp.register_event("file-loaded", function()
    gr_scene_hue = nil
    gr_scene_hue_smoothed = 0.0
    gr_hue_has_data = false
    gr_anim_pos = nil
    gr_anim_bucket = 0.0
    gr_last_feed_pos = nil
    gr_anim_offset = 0.0
    gr_feed_received  = false
    gr_user_offset = 0.0  -- reset per-file (photon-sharp parity)
    GR_STEP.level = 0
    gr_weight_shift = 0.0
    -- Development B: the per-file automatic pixel-analysis hint must be valid
    -- again for every new file. If the user set it manually on a previous file,
    -- that suppression was specific to that file and must not carry over. The
    gr_size_hint_suppressed = false
    gr_size_hint_received   = false
    gr_size_hint_last_value = nil
    GRAIN_SIZE_BASE = clamp(GRAIN_SIZE_BASE_USER_DEFAULT * gr_size_trim, 0.5, gr_size_trim > 2.0 and 16.0 or 8.0)
    GRAIN_SIZE = GRAIN_SIZE_BASE
    gr_strength_hint_suppressed = false
    gr_strength_hint_received   = false
    gr_strength_hint_last_value = nil
    GRAIN_BASE_STRENGTH = GRAIN_STRENGTH_USER_DEFAULT
    gr_strength_src = nil
    gr_mult_applied = false
    gr_last_mult    = nil
    gr_frame_peak     = 0.50
    gr_scene_contrast = 0.35
    gr_noise_level    = 0.10
    gr_motion_level   = 0.20
    gr_resolve_adaptive_params()
    gr_amount_rendered = gr_amount  -- snap, don't ease in from the previous file's level
    gr_char_state_reset()

    -- grain starts each video load from `grain_target_enabled`, which
    -- photon.lua's file-loaded handler keeps current.
    if grain_target_enabled and not enabled then
        enabled = true
        gr_known_clear = false
        gr_enable()
        mp.msg.info("photon-grain: enabled (carried over)")
    elseif not grain_target_enabled and enabled then
        gr_remove_shader()
        gr_known_clear = true
        enabled = false
        mp.msg.info("photon-grain: disabled (new file, off-by-default)")
    end
    if enabled then gr_push_params() end
    gr_publish_hud_state()
end)

-- gor session state sync — photon.lua's file-loaded handler sends this
-- message on every new mpv spawn / file transition, AFTER its own loadfile
-- (inside its own file-loaded). mpv's script execution order is undefined,
mp.register_script_message("photon-grain-set-target-enabled", function(val)
    grain_target_enabled = (val == "true")
    if grain_target_enabled and not enabled then
        enabled = true
        gr_known_clear = false
        gr_enable()
        mp.msg.info("photon-grain: enabled (carried over)")
        gr_publish_hud_state()
    elseif not grain_target_enabled and enabled then
        gr_remove_shader()
        gr_known_clear = true
        enabled = false
        mp.msg.info("photon-grain: disabled (target off)")
        gr_publish_hud_state()
    end
end)

mp.register_script_message("photon-grain-toggle", function()
    gr_trace_control("photon-grain-toggle")
    grain_target_enabled = not grain_target_enabled
    enabled = grain_target_enabled
    if enabled then
        gr_known_clear = false
        gr_enable()
        mp.msg.info("photon-grain: enabled")
    else
        gr_remove_shader(); gr_known_clear = true
        mp.osd_message("photon-grain v3.2.0: OFF")
        mp.msg.info("photon-grain: disabled")
    end
    gr_publish_hud_state()
end)

-- input.conf Cmd+G/Shift+G: nudge grain amount offset down/up one ladder step (0.125 first, see GR_STEP; not base strength); 1.0 toggles it.
mp.register_script_message("photon-grain-set-amount", function(val)
    gr_trace_control("photon-grain-set-amount")
    local v = tonumber(val)
    if not v then return end
    if math.abs(v - 1.0) < 0.001 then
        GR_STEP.level = (GR_STEP.level > -#GR_STEP.down) and -#GR_STEP.down or 0
    elseif v > 1.0 then
        GR_STEP.level = math.min(GR_STEP.level + 1, #GR_STEP.up)
    else
        GR_STEP.level = math.max(GR_STEP.level - 1, -#GR_STEP.down)
    end
    gr_user_offset = clamp(GR_STEP.offset(), GRAIN_OFFSET_MIN, GRAIN_OFFSET_MAX)
    gr_resolve_adaptive_params()
    gr_amount_rendered = gr_amount  -- user-triggered change: apply immediately, don't ease in
    if enabled then
        mp.osd_message(string.format("grain amount: %.2f  (offset %+.2f)", gr_amount, gr_user_offset))
    else
        mp.osd_message(string.format("grain amount: %.2f  (offset %+.2f, OFF)", gr_amount, gr_user_offset))
    end
    mp.msg.info(string.format("photon-grain amount: %.2f  (offset %+.2f)", gr_amount, gr_user_offset))
    gr_push_params(); gr_publish_hud_state()
end)

-- Independent shadow/midtone/highlight sensitivity (DaVinci Resolve /
-- Exposure X7 style zone sliders).
mp.register_script_message("photon-grain-set-shadow-sensitivity", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_SHADOW_SENSITIVITY = clamp(v, 0.0, 2.0)
    mp.osd_message(string.format("grain shadow sens: %.2f", GRAIN_SHADOW_SENSITIVITY))
    mp.msg.info(string.format("photon-grain shadow_sensitivity: %.2f", GRAIN_SHADOW_SENSITIVITY))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-midtone-sensitivity", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_MIDTONE_SENSITIVITY = clamp(v, 0.0, 2.0)
    mp.osd_message(string.format("grain midtone sens: %.2f", GRAIN_MIDTONE_SENSITIVITY))
    mp.msg.info(string.format("photon-grain midtone_sensitivity: %.2f", GRAIN_MIDTONE_SENSITIVITY))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-highlight-sensitivity", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_HIGHLIGHT_SENSITIVITY = clamp(v, 0.0, 2.0)
    mp.osd_message(string.format("grain highlight sens: %.2f", GRAIN_HIGHLIGHT_SENSITIVITY))
    mp.msg.info(string.format("photon-grain highlight_sensitivity: %.2f", GRAIN_HIGHLIGHT_SENSITIVITY))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-strength", function(val)
    gr_trace_control("photon-grain-set-strength")
    local v = tonumber(val)
    if not v then return end
    GRAIN_BASE_STRENGTH = clamp(v, 0.0, 60.0)
    gr_strength_hint_suppressed = true
    gr_strength_src = "manual"
    gr_str_log("manual", GRAIN_BASE_STRENGTH)
    mp.msg.info(string.format("photon-grain strength: %.2f", GRAIN_BASE_STRENGTH))
    gr_push_params()
    gr_publish_hud_state()
end)

-- photon.lua's strength signal from file-open, derived from the same
-- diff_energy measurement as size (see photon.lua
-- gr_strength_hint_norm_from_energy — no extra ffmpeg/subprocess cost).
mp.register_script_message("photon-grain-doc", function(gen_s, name)
    if gr_doc_accept(gen_s, name) then gr_publish_hud_state() end
end)

mp.register_script_message("photon-grain-set-strength-hint", function(val, gen_s, name)
    local norm = tonumber(val)
    if not norm then return end
    if not gr_doc_accept(gen_s, name) then return end
    if gr_mult_applied then
        mp.msg.info("photon-grain: strength seed-dropped (mult already applied for this document)")
        gr_str_log("seed-dropped", nil)
        return
    end
    if gr_strength_hint_suppressed then
        mp.msg.info(string.format(
            "photon-grain: strength hint received (norm=%.3f), ignored due to manual override", norm))
        return
    end
    norm = clamp(norm, 0.0, 1.0)
    local hint = 1.0 + (GRAIN_STRENGTH_HINT_MAX - 1.0) * norm
    hint = clamp(hint, 1.0, GRAIN_STRENGTH_HINT_MAX)
    GRAIN_BASE_STRENGTH = GRAIN_STRENGTH_USER_DEFAULT * hint
    gr_strength_hint_received   = true
    gr_strength_hint_last_value = hint
    gr_strength_src = "seed"
    gr_str_log("seed", GRAIN_BASE_STRENGTH, hint)
    mp.msg.info(string.format(
        "photon-grain: strength hint applied - hint=%.3f -> GRAIN_BASE_STRENGTH=%.3f",
        hint, GRAIN_BASE_STRENGTH))
    gr_push_params()
    if not enabled then
        -- While the engine is off the hint still updates state and the
        -- dedupe cache; the value lands on the GPU when the next enable
        -- pushes and adds.
        mp.msg.info("photon-grain: strength hint stored while engine is off; applies when enabled")
    end
    gr_publish_hud_state()
end)

-- Absolute strength multiplier from photon.lua's GS probe (live top-up:
-- the probe measures how much grain body the SOURCE already carries and
-- fills only the gap to the accepted target). Unlike the norm hint this
-- can pull BELOW 1.0 - on an already-grainy file blind adding is salt.
mp.register_script_message("photon-grain-set-strength-mult", function(val, gen_s, name, var_src_s, share_s, n_s, measured_s, expected_revision_s)
    common.trace_record("auto-mult-receive", {value=val, current=gr_control_revision, expected=expected_revision_s or "missing"})
    local mult = tonumber(val)
    if not mult then return end
    if not gr_doc_accept(gen_s, name) then return end
    if gr_strength_hint_suppressed then
        mp.msg.info(string.format(
            "photon-grain: strength mult received (%.3f), ignored due to manual override", mult))
        return
    end
    if gr_adaptive_mode then
        -- Sanity guard only (non-finite or absurd value); the probe derives the value.
        if mult ~= mult or mult < 0 or mult > 8 then
            mp.msg.info(string.format("photon-grain: strength mult %.3f rejected (out of sane range)", mult))
            return
        end
    else
        -- Adaptive OFF: legacy fixed envelope, unchanged.
        mult = clamp(mult, 0.40, 1.25)
    end
    GRAIN_BASE_STRENGTH = GRAIN_STRENGTH_USER_DEFAULT * mult
    gr_strength_hint_received   = true
    gr_strength_hint_last_value = mult
    gr_strength_src = gr_adaptive_mode and (measured_s == "1" and "auto-measured" or "auto-clean") or "mult"
    gr_mult_applied = true
    gr_last_mult = mult
    gr_str_log("mult", GRAIN_BASE_STRENGTH, mult, tonumber(var_src_s), tonumber(share_s), tonumber(n_s))
    mp.msg.info(string.format(
        "photon-grain: strength mult applied - mult=%.3f -> GRAIN_BASE_STRENGTH=%.3f",
        mult, GRAIN_BASE_STRENGTH))
    gr_push_params()
    gr_publish_hud_state()
end)

-- Learned look adopted: the manual strength is now the set point, so the
-- measurement takes over again (manual suppression ends for this document).
mp.register_script_message("photon-grain-strength-resume", function(gen_s, name)
    if not gr_adaptive_mode then return end
    if not gr_doc_accept(gen_s, name) then return end
    gr_strength_hint_suppressed = false
    -- The explicit manual revision was consumed; later size/stock controls
    -- must not make this old strength look like a new manual acceptance.
    gr_strength_src = "learned"
    gr_str_log("resume", GRAIN_BASE_STRENGTH)
    mp.msg.info("photon-grain: manual strength adopted as look; auto strength resumes")
    gr_publish_hud_state()
end)

mp.register_script_message("photon-grain-set-size", function(val)
    gr_trace_control("photon-grain-set-size")
    local v = tonumber(val)
    if not v then return end
    -- set GRAIN_SIZE_BASE, never GRAIN_SIZE directly:
    -- gr_resolve_adaptive_params() rewrites GRAIN_SIZE from
    -- GRAIN_SIZE_BASE every feed tick as GRAIN_SIZE_BASE * (0.925 + 0.15 *
    GRAIN_SIZE_BASE = clamp(v, 0.5, 16.0)
    GRAIN_SIZE = GRAIN_SIZE_BASE
    -- User set it manually: the automatic pixel-analysis hint is suppressed
    gr_size_hint_suppressed = true
    mp.msg.info(string.format("photon-grain size (crystal cell px): %.2f", GRAIN_SIZE))
    mp.osd_message(string.format("grain size: %.1f px (~%.0f ISO)",
        GRAIN_SIZE, 50 * math.exp(GRAIN_SIZE * 0.8)))
    gr_push_params()
    gr_publish_hud_state()
end)

-- Development B: pixel-analysis result sent once by photon.lua at file-open
-- (see photon.lua gr_run_grain_size_analysis). The hint multiplies against
-- GRAIN_SIZE_BASE — it does not override an absolute value the user entered
mp.register_script_message("photon-grain-set-size-hint", function(val)
    local hint = tonumber(val)
    if not hint then return end
    if gr_size_hint_suppressed then
        mp.msg.info(string.format(
            "photon-grain: size hint received (%.3f), ignored due to manual override", hint))
        return
    end
    gr_size_hint_last_value = hint
    GRAIN_SIZE_BASE = clamp(GRAIN_SIZE_BASE_USER_DEFAULT * hint * gr_size_trim, 0.5, gr_size_trim > 2.0 and 16.0 or 8.0)
    GRAIN_SIZE = GRAIN_SIZE_BASE
    gr_size_hint_received   = true
    mp.msg.info(string.format(
        "photon-grain: size hint applied - hint=%.3f -> GRAIN_SIZE_BASE=%.3f", hint, GRAIN_SIZE_BASE))
    gr_push_params()
    gr_publish_hud_state()
end)

local function gr_size_trim_change(new_trim, kind)
    new_trim = clamp(new_trim, GR_TRIM_MIN, GR_TRIM_MAX)
    local old = gr_size_trim
    -- A clamped repeat does not change the measurement basis. Leave every
    -- render/control/history side effect untouched until a genuine change.
    if new_trim == old then return end
    if new_trim ~= old then gr_trace_control("size-trim") end
    gr_size_trim = new_trim
    local auto_px = GRAIN_SIZE_BASE_USER_DEFAULT * (gr_size_hint_last_value or 1.0)
    if gr_size_hint_suppressed then
        mp.osd_message(string.format("grain size trim x%.2f (manual size: trim not applied)", gr_size_trim))
        gr_size_log("TRIM", string.format("kind=%s trim=%.3f prev=%.3f applied=false reason=manual-size", kind, gr_size_trim, old))
        gr_publish_hud_state()
        return
    end
    GRAIN_SIZE_BASE = clamp(auto_px * gr_size_trim, 0.5, gr_size_trim > 2.0 and 16.0 or 8.0)
    GRAIN_SIZE = GRAIN_SIZE_BASE
    mp.osd_message(string.format("grain size x%.2f (auto %.2f px -> %.2f px)", gr_size_trim, auto_px, GRAIN_SIZE_BASE))
    gr_size_log("TRIM", string.format("kind=%s trim=%.3f prev=%.3f auto_px=%.4f size_px=%.4f probe_history=clear-requested",
        kind, gr_size_trim, old, auto_px, GRAIN_SIZE_BASE))
    mp.commandv("script-message", "photon-grain-size-trim-state", string.format("%.4f", gr_size_trim), tostring(gr_doc.gen))
    gr_push_params()
    gr_publish_hud_state()
end
mp.register_script_message("photon-grain-size-trim-up",    function() gr_size_trim_change(gr_size_trim * GR_TRIM_STEP, "up") end)
mp.register_script_message("photon-grain-size-trim-down",  function() gr_size_trim_change(gr_size_trim / GR_TRIM_STEP, "down") end)
mp.register_script_message("photon-grain-size-trim-reset", function() gr_size_trim_change(1.0, "reset") end)
-- Named bindings without default keys: bind in input.conf (e.g. `F7 script-binding photon-grain/size-trim-up`).
mp.add_key_binding(nil, "size-trim-up",    function() gr_size_trim_change(gr_size_trim * GR_TRIM_STEP, "up") end)
mp.add_key_binding(nil, "size-trim-down",  function() gr_size_trim_change(gr_size_trim / GR_TRIM_STEP, "down") end)
mp.add_key_binding(nil, "size-trim-reset", function() gr_size_trim_change(1.0, "reset") end)

mp.register_script_message("photon-grain-set-stock", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_STOCK_PRESET = math.floor(clamp(v, 0, 5))
    local names = {"Portra 400", "Ektar 100", "Vision3 250D",
                   "Kodachrome 64", "Tri-X 400", "HP5 Plus"}
    mp.msg.info(string.format("photon-grain stock: %s", names[GRAIN_STOCK_PRESET + 1] or "?"))
    mp.osd_message(string.format("stock: %s", names[GRAIN_STOCK_PRESET + 1] or "?"))
    gr_push_params()
end)

--  PHOTON-CHROME INTEGRATION
--  Only caller: photon-chrome.lua. Not user-facing, no input.conf binding —
--  fires automatically when chrome is toggled (see chrome's toggle handler),
mp.register_script_message("photon-chrome-set-mono-grain", function(val)
    local on = (val == "true")
    if on == gr_mono_mode then return end  -- already in requested state
    gr_mono_mode = on
    if on then
        gr_mono_saved_stock_preset = GRAIN_STOCK_PRESET
        gr_mono_saved_softness     = GRAIN_SOFTNESS_BASE
        GRAIN_STOCK_PRESET = 4  -- Tri-X 400
        -- P0-7: halve the BASE; the rendered var is resolver-owned.
        GRAIN_SOFTNESS_BASE = clamp(GRAIN_SOFTNESS_BASE * 0.5, 0.20, 30.75)
        GRAIN_SOFTNESS = GRAIN_SOFTNESS_BASE
        mp.msg.info("photon-grain: mono mode ON (chrome active) — stock=Tri-X 400, softness halved")
    else
        if gr_mono_saved_stock_preset ~= nil then GRAIN_STOCK_PRESET = gr_mono_saved_stock_preset end
        if gr_mono_saved_softness     ~= nil then GRAIN_SOFTNESS_BASE = gr_mono_saved_softness; GRAIN_SOFTNESS = GRAIN_SOFTNESS_BASE end
        gr_mono_saved_stock_preset = nil
        gr_mono_saved_softness     = nil
        mp.msg.info("photon-grain: mono mode OFF (chrome inactive) — stock/softness restored")
    end
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-res-adapt", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_RES_ADAPT = (v ~= 0) and 1 or 0
    mp.msg.info(string.format("photon-grain res_adapt: %s", GRAIN_RES_ADAPT == 1 and "on" or "off"))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-chroma-split", function(val)
    local v = tonumber(val)
    if not v then return end
    -- Write the BASE, never the rendered var directly (P0-7):
    -- gr_resolve_adaptive_params() recomputes the rendered var from its
    -- BASE every scene-feed tick and would silently discard the write.
    GRAIN_CHROMA_SPLIT_BASE = clamp(v, 0.0, 0.5)
    GRAIN_CHROMA_SPLIT = GRAIN_CHROMA_SPLIT_BASE
    mp.msg.info(string.format("photon-grain chroma_split: %.2f", GRAIN_CHROMA_SPLIT))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-development", function(val)
    local v = tonumber(val)
    if not v then return end
    -- P0-7: BASE write (see set-chroma-split).
    GRAIN_DEVELOPMENT_BASE = clamp(v, 0.1, 1.5)
    GRAIN_DEVELOPMENT = GRAIN_DEVELOPMENT_BASE
    mp.msg.info(string.format("photon-grain development: %.2f", GRAIN_DEVELOPMENT))
    gr_push_params()
end)

-- Luma-dependent tone skew: 0=symmetric, higher values make grain look
-- slightly darker in highlights and lighter in shadows.
mp.register_script_message("photon-grain-set-skew", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_SKEW_STRENGTH = clamp(v, 0.0, 0.7)
    mp.msg.info(string.format("photon-grain skew_strength: %.2f", GRAIN_SKEW_STRENGTH))
    mp.osd_message(string.format("grain tone skew: %.2f", GRAIN_SKEW_STRENGTH))
    gr_push_params()
end)

-- Legacy name, maps to GRAIN_SOFTNESS (closest surviving equivalent of
mp.register_script_message("photon-grain-set-dye-halo", function(val)
    local v = tonumber(val)
    if not v then return end
    -- P0-7: BASE write (see set-chroma-split).
    GRAIN_SOFTNESS_BASE = clamp(v, 0.20, 30.75)
    GRAIN_SOFTNESS = GRAIN_SOFTNESS_BASE
    mp.msg.info(string.format("photon-grain softness (dye-halo alias): %.2f", GRAIN_SOFTNESS))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-softness", function(val)
    local v = tonumber(val)
    if not v then return end
    -- P0-7: BASE write (see set-chroma-split).
    GRAIN_SOFTNESS_BASE = clamp(v, 0.20, 30.75)
    GRAIN_SOFTNESS = GRAIN_SOFTNESS_BASE
    mp.msg.info(string.format("photon-grain softness: %.2f", GRAIN_SOFTNESS))
    gr_push_params()
end)

-- Three real layers exist (FINE/CRYSTAL/CLOUD), so these map directly:
-- set-fine -> FINE_WEIGHT, set-mid -> CRYSTAL_WEIGHT, set-coarse -> CLOUD_WEIGHT.
mp.register_script_message("photon-grain-set-fine", function(val)
    local v = tonumber(val)
    if not v then return end
    -- P0-7: BASE write (see set-chroma-split).
    GRAIN_FINE_WEIGHT_BASE = clamp(v, 0.0, 1.0)
    GRAIN_FINE_WEIGHT = GRAIN_FINE_WEIGHT_BASE
    mp.msg.info(string.format("photon-grain fine_weight: %.2f", GRAIN_FINE_WEIGHT))
    mp.osd_message(string.format("grain fine: %.2f", GRAIN_FINE_WEIGHT))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-mid", function(val)
    local v = tonumber(val)
    if not v then return end
    -- P0-7: BASE write (see set-chroma-split).
    GRAIN_CRYSTAL_WEIGHT_BASE = clamp(v, 0.0, 1.0)
    GRAIN_CRYSTAL_WEIGHT = GRAIN_CRYSTAL_WEIGHT_BASE
    mp.msg.info(string.format("photon-grain crystal_weight (mid): %.2f", GRAIN_CRYSTAL_WEIGHT))
    mp.osd_message(string.format("grain mid: %.2f", GRAIN_CRYSTAL_WEIGHT))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-coarse", function(val)
    local v = tonumber(val)
    if not v then return end
    -- P0-7: BASE write (see set-chroma-split).
    GRAIN_CLOUD_WEIGHT_BASE = clamp(v, 0.0, 1.0)
    GRAIN_CLOUD_WEIGHT = GRAIN_CLOUD_WEIGHT_BASE
    mp.msg.info(string.format("photon-grain cloud_weight (coarse): %.2f", GRAIN_CLOUD_WEIGHT))
    mp.osd_message(string.format("grain coarse: %.2f", GRAIN_CLOUD_WEIGHT))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-cloud-size-ratio", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_CLOUD_SIZE_RATIO = clamp(v, 1.4, 4.0)
    mp.msg.info(string.format("photon-grain cloud_size_ratio: %.2f", GRAIN_CLOUD_SIZE_RATIO))
    gr_push_params()
end)

mp.register_script_message("photon-grain-set-fine-size-ratio", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_FINE_SIZE_RATIO = clamp(v, 0.15, 0.90)
    mp.msg.info(string.format("photon-grain fine_size_ratio: %.2f", GRAIN_FINE_SIZE_RATIO))
    gr_push_params()
end)

mp.register_script_message("photon-grain-debug-visualize", function(val)
    local v = tonumber(val)
    if not v then return end
    GRAIN_DEBUG_VISUALIZE = (v ~= 0) and 1 or 0
    local state = GRAIN_DEBUG_VISUALIZE == 1 and "ON (x50 raw grain)" or "off"
    mp.msg.info("photon-grain DEBUG VISUALIZE: " .. state)
    mp.osd_message("photon-grain DEBUG: " .. state)
    gr_push_params()
end)

-- Listens to photon.lua's single broadcast point, photon-scene-feed (the old
-- per-file feed message is no longer sent). Grain has always received SMOOTHED
-- fields (even in the pre-split monolith, sharp's own smoothed state was sent,
local photon_scene_kv_decode = common.scene_kv_decode

mp.register_script_message("photon-scene-feed", function(payload)
    local f = photon_scene_kv_decode(payload)
    -- Domain guard: a corrupt payload value (NaN, unit garbage, encoding
    -- blow-up) must not drive adaptation. Out-of-domain -> keep last good.
    local function feed_num(v, lo, hi, fallback)
        local x = tonumber(v)
        if not x or x ~= x or x < lo or x > hi then
            if not gr_feed_corrupt_logged then
                gr_feed_corrupt_logged = true
                mp.msg.warn("photon-grain: corrupt scene-feed value ignored (kept last good)")
            end
            return fallback
        end
        return x
    end
    gr_frame_peak     = feed_num(f.smooth_peak, 0.0, 1.0, gr_frame_peak)
    gr_scene_contrast = feed_num(f.smooth_contrast, 0.0, 1.0, gr_scene_contrast)
    gr_noise_level    = feed_num(f.smooth_noise, 0.0, 1.0, gr_noise_level)
    gr_motion_level   = feed_num(f.motion, 0.0, 1.0, gr_motion_level)
    local next_fps    = feed_num(f.fps, 1.0, 240.0, gr_fps)
    if next_fps ~= gr_fps then
        gr_fps = next_fps
        -- Recompute only from a real playback position; a stale feed does
        -- not advance animation while a cache-stalled image is on screen.
        gr_update_anim_pos(mp.get_property_number("time-pos"))
    end
    gr_is_hdr         = (f.is_hdr == "true")
    local is_cut      = (f.is_cut == "true")
    -- A stale scene feed cannot re-seed grain on a frozen playback frame.
    local feed_pos = mp.get_property_number("time-pos")
    if is_cut and feed_pos and feed_pos ~= gr_last_feed_pos
        and not mp.get_property_bool("paused-for-cache", false) then
        gr_anim_offset = gr_anim_offset + 137.0
        gr_anim_bucket = math.floor(math.max(feed_pos, 0.0) *
            (gr_fps >= 5.0 and 18.0 or gr_fps * 0.75)) + gr_anim_offset
        if enabled then gr_push_params() end
    end
    if not mp.get_property_bool("paused-for-cache", false) then
        gr_last_feed_pos = feed_pos
    end
    gr_feed_received  = true

    -- Development A: read scene hue. f.hue may be nil (no hue this frame,
    -- gr_scene_hue is kept (same nil-tolerant pattern as chrome), never
    local raw_hue_norm = tonumber(f.hue)
    if raw_hue_norm and (raw_hue_norm ~= raw_hue_norm or raw_hue_norm < 0.0 or raw_hue_norm > 1.0) then
        raw_hue_norm = nil
    end
    local raw_hue = raw_hue_norm and (raw_hue_norm * 360.0) or nil
    if raw_hue then
        gr_scene_hue = raw_hue
        gr_scene_hue_smoothed = common.smooth_hue(gr_scene_hue_smoothed, raw_hue,
            GR_HUE_EMA_ALPHA, not gr_hue_has_data, 360.0)
        gr_hue_has_data = true
    end
    -- Re-resolve every scene-adaptive parameter (amount, size, softness,
    -- chroma split, development, mix) from fresh feed values on EVERY
    -- call; the arithmetic is cheap and the push below is deduped.
    gr_resolve_adaptive_params(is_cut)
    -- Params land every feed tick via one deduped change-list add — no
    -- file I/O, no rebuild. The push cadence is the feed's own (scene
    -- cut fires the same tick as is_cut), so there is no separate
    if enabled then
        gr_push_params()
    end
end)

-- Startup: delete legacy A/B slot files so the pre-PARAM scheme can
-- never resurface, then write the single PARAM-based file once. Nothing
local function gr_delete_legacy_files()
    local dir = common.shader_dir()
    if not dir then return end
    os.remove(dir .. "photon-grain-shader-a.glsl")
    os.remove(dir .. "photon-grain-shader-b.glsl")
end
gr_delete_legacy_files()
gr_write_shader()

-- toggles, but it's only pushed + added to glsl-shaders (i.e. actually
-- visible) if enabled (default false).
if enabled then
    gr_enable()
end
mp.msg.info("photon-grain v3.2.0 'Halide' loaded (//HOOK OUTPUT, sparse convolution model, default: "
    .. (enabled and "ON" or "OFF") .. ")")
