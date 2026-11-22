-- ================================================================
--  photon-negativ.lua - OUTPUT-stage film negative
--  Owns: three independent mode shaders, state and keys
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
        mp.msg.error("photon-negativ: photon-scriptdir invalid or photon-common.lua missing - checked: " .. script_dir .. "/photon-common.lua")
    end
end
local common_ok, common = pcall(require, "photon-common")
if not common_ok then
    mp.msg.error("photon-negativ: could not load photon-common - " .. tostring(common) .. ". This script is disabled.")
    return
end
local PHOTON_REQUIRED_COMMON_VERSION = 2
if not common.check_version("photon-negativ", PHOTON_REQUIRED_COMMON_VERSION) then
    return
end


-- ================================================================
--  1. CONTROL PANEL
-- ================================================================
--  adjacency/post-grade are genuinely mode-independent physical
--  constants. Mask-strength values are mode-specific, called out below.

-- ── D-min mask orange cast  MASK mode only TRANSLUCID/HUEFL ──
-- hold this at true zero via NEGATIV_TRANSLUCID_MASK_GAIN below. ────
local NEGATIV_MASK_STRENGTH    = 1.00
local NEGATIV_TRANSLUCID_MASK_GAIN = 0.00
-- Scene-adaptive mask density: THIN (underexposed) negative shows
-- MORE mask, DENSE (overexposed) shows LESS — mild modulation of
-- apparent visibility by scene exposure, not the mask's own density.
local NEGATIV_MASK_EXPOSURE_GAIN = 0.18   -- how much scene peak shifts apparent mask visibility
local NEGATIV_MASK_EXPOSURE_MID  = 0.45   -- scene peak treated as "normally exposed" (no shift)

-- ── dye-layer cross-talk ──
local NEGATIV_CROSSTALK_STRENGTH = 0.65
local NEGATIV_CYAN_GREEN_LEAK  = 0.22
local NEGATIV_MAGENTA_BLUE_LEAK = 0.12
local NEGATIV_YELLOW_LEAK       = 0.05

-- ── adjacency effect Mackie line  fixed constant not scene ──
-- adaptive (a property of which developer chemistry was used, not
-- something that varies by scene brightness/contrast). ─────────────
local NEGATIV_ADJACENCY_STRENGTH = 0.35

-- ── negative-side characteristic curve ──
local NEGATIV_GAMMA             = 0.60
local NEGATIV_TOE_WIDTH        = 0.22
local NEGATIV_SHOULDER_WIDTH   = 0.24
-- Scene-adaptive gamma: small, deliberately subtle secondary detail.
local NEGATIV_GAMMA_SCENE_GAIN  = 0.10
-- Hard floor/ceiling for scene-adaptive gamma. toward 0.21 (min) ->
-- flatter curve; toward 1.56 (max) -> punchier curve. Keep MIN>0,
-- MAX finite — gamma feeds negativ_curve()'s power term directly.
local NEGATIV_GAMMA_CLAMP_MIN   = 0.22
local NEGATIV_GAMMA_CLAMP_MAX   = 1.22

-- ── film-stock character hue-driven continuous  mirrors chr ──
-- filter system). Index 0 = ECN-2 cinema-style, 1 = C-41 consumer-
-- style (default), 2 = warmer "vintage consumer" character. ────────
local NEGATIV_STOCK              = 1
local NEGATIV_HUE_DRIVEN         = true
local NEGATIV_HUE_ARC_MAX        = 120.0 / 360.0
-- HUE_EMA_ALPHA defined in photon-common.lua — fix bugs there, not here.
local NEGATIV_HUE_EMA_ALPHA      = common.HUE_EMA_ALPHA  -- (reserved; ng_scene_hue_smoothed EMA uses NEGATIV_HUE_EMA_ALPHA's value inline where computed)

-- Per-stock D-min multipliers (applied on top of the base D-min ratio
-- baked into each mode's own GLSL DMIN_BASE const). Index matches
-- NEGATIV_STOCK: 0=ECN-2, 1=C-41, 2=vintage-warm.
local NEGATIV_STOCK_MASK_GAIN = {0.85, 1.00, 1.25}
local NEGATIV_STOCK_GAMMA_NUDGE = {-0.02, 0.00, -0.04}

-- ── shared post-grade vibrance/contrast/black point all 3 m ──
-- VIBRANCE: 0.0 = no boost; 1.0 = strong boost weighted toward
-- low-sat pixels, already-saturated pixels barely touched.
local NEGATIV_POST_VIBRANCE = 0.48
-- CONTRAST: 0.0 = no change; higher = steeper S-curve around mid-grey.
-- Values above ~1.0 start clipping shadows/highlights hard.
local NEGATIV_POST_CONTRAST = 0.12
-- BLACKPOINT: 0.0 = no lift. WARNING: divides (1.0-amount) in
-- apply_blackpoint() — near 1.0 that denominator nears 0, blowing
-- out to white/NaN. Keep well under 1.0; >0.5 already risky.
local NEGATIV_POST_BLACKPOINT = 0.28

-- Bakes the never-changing curve/leak/grade constants at the one-time
-- write; everything live is a //!PARAM uniform (see ng_*_push_params).
local function ng_bake_common(content)
    content = content:gsub("#define NG_TOE_WIDTH%s+%-?[%d.]+",
        string.format("#define NG_TOE_WIDTH           %.4f", NEGATIV_TOE_WIDTH))
    content = content:gsub("#define NG_SHOULDER_WIDTH%s+%-?[%d.]+",
        string.format("#define NG_SHOULDER_WIDTH      %.4f", NEGATIV_SHOULDER_WIDTH))
    content = content:gsub("#define NG_CROSSTALK_STRENGTH%s+%-?[%d.]+",
        string.format("#define NG_CROSSTALK_STRENGTH  %.4f", NEGATIV_CROSSTALK_STRENGTH))
    content = content:gsub("#define NG_CYAN_GREEN_LEAK%s+%-?[%d.]+",
        string.format("#define NG_CYAN_GREEN_LEAK     %.4f", NEGATIV_CYAN_GREEN_LEAK))
    content = content:gsub("#define NG_MAGENTA_BLUE_LEAK%s+%-?[%d.]+",
        string.format("#define NG_MAGENTA_BLUE_LEAK   %.4f", NEGATIV_MAGENTA_BLUE_LEAK))
    content = content:gsub("#define NG_YELLOW_LEAK%s+%-?[%d.]+",
        string.format("#define NG_YELLOW_LEAK         %.4f", NEGATIV_YELLOW_LEAK))
    content = content:gsub("#define NG_ADJACENCY_STRENGTH%s+%-?[%d.]+",
        string.format("#define NG_ADJACENCY_STRENGTH  %.4f", NEGATIV_ADJACENCY_STRENGTH))
    content = content:gsub("#define NG_POST_VIBRANCE%s+%-?[%d.]+",
        string.format("#define NG_POST_VIBRANCE       %.4f", NEGATIV_POST_VIBRANCE))
    content = content:gsub("#define NG_POST_CONTRAST%s+%-?[%d.]+",
        string.format("#define NG_POST_CONTRAST       %.4f", NEGATIV_POST_CONTRAST))
    content = content:gsub("#define NG_POST_BLACKPOINT%s+%-?[%d.]+",
        string.format("#define NG_POST_BLACKPOINT     %.4f", NEGATIV_POST_BLACKPOINT))
    return content
end

-- ── TIER 1/TIER 2 split mirrors photon-chromeluas chfilter ──
-- strength_rendered/ch_char_track). TIER 1 = mask/gamma, continuous.
-- TIER 2 = stock position, long-EMA + dead-zone + dwell-confirm.
local NEGATIV_TAU_ATTACK   = 0.35  -- TIER 1 attack tau
local NEGATIV_CUT_TAU      = 0.6   -- TIER 1 tau on a confirmed cut — faster settle
local NEGATIV_CHAR_TAU          = 9.0   -- seconds; long-EMA on the raw stock-position driving signal
local NEGATIV_CHAR_DEAD_ZONE    = 0.24  -- committed value must be wrong by this much before a change is even considered
local NEGATIV_CHAR_DWELL_MIN    = 2.5   -- seconds outside the dead-zone before a new value commits
local NEGATIV_CHAR_EASE_TAU     = 3.0   -- seconds; once committed, how fast rendered position eases to target
local NEGATIV_CHAR_CUT_EASE_TAU = 0.8   -- faster ease right after a confirmed cut

local math_max, math_min, math_abs, math_floor = math.max, math.min, math.abs, math.floor
-- clamp/hue_circular_dist/lerp_hue defined in photon-common.lua — fix bugs there, not here.
local clamp = common.clamp
local ng_hue_circular_dist = common.hue_circular_dist
local lerp_hue = common.lerp_hue
local asym_smooth = common.asym_smooth
local reset_char_state = common.reset_char_state
local new_char_state = common.new_char_state

-- ================================================================
--  2. SHARED SCENE STATE
-- ================================================================
--  genuinely shared (per-mode copies would just drift). Per-mode
--  state (enabled/TIER1-2/slot) lives in each mode's own block below.
local ng_frame_peak     = 0.50
local ng_scene_contrast = 0.25
local ng_scene_sat      = 0.00   -- -1 sentinel means "no saturation data" (HDR path)
local ng_scene_hue      = nil    -- nil means "no hue data" (HDR path, or no real sample yet)
local ng_scene_hue_smoothed = nil -- EMA of ng_scene_hue
local ng_motion_level   = 0.20
local ng_is_hdr         = false
local ng_is_cut         = false
local ng_has_feed       = false  -- true once at least one real feed has arrived this file

-- (ng_hw_copyback_signaled removed along with ng_signal_hw_copyback —
-- see that removal's comment further down. It was read/written only
-- inside that one function, unlike ng_is_hdr which is kept because it

-- TIER 2 character tracker — ported verbatim from photon-chrome.lua's
-- ch_char_track. Takes an explicit state table so each mode carries
-- its own independent TIER-2 tracking (see NOTE below, why-per-mode).
local function ng_char_track(state, raw, now, dt, is_cut)
    return common.char_track(state, raw, now, dt, is_cut,
        NEGATIV_CHAR_TAU, NEGATIV_CHAR_DEAD_ZONE, NEGATIV_CHAR_DWELL_MIN,
        NEGATIV_CHAR_EASE_TAU, NEGATIV_CHAR_CUT_EASE_TAU)
end

-- Resets a single character-state table to its neutral default with
-- no pending dwell. Takes the table explicitly (rather than a module-
-- level global) so each mode can reset only its own TIER-2 state.
local function ng_char_state_reset(state)
    reset_char_state(state, NEGATIV_STOCK)
end

-- ★ NOTE: TIER-1/2 render state is per-mode, not shared — a shared
-- state would let switching keys (e.g. 'n' then 'h') visibly ease FROM
-- n's last value instead of snapping to h's own target on activation.

-- ================================================================
--  3. ADAPTIVE PARAMETER RESOLUTION
-- ================================================================
--  inputs, passed as params (not module globals) so all 3 modes call
--  this one function body independently with zero shared mutable state.
local function ng_resolve_adaptive_params(mode_mask_strength, char_state, out)
    -- out is a small table the CALLER owns (mask_gain/gamma resolved
    -- + rendered, tier1_last_t, char_last_t, stock_pos_rendered) —
    -- read/written in place so this function itself holds no state.

    -- ── Stock position TIER 2 raw target ──
    local raw_stock_pos
    local hue_arc_clamped = false
    if not NEGATIV_HUE_DRIVEN or ng_scene_hue_smoothed == nil then
        raw_stock_pos = NEGATIV_STOCK
    else
        local in_arc = (ng_scene_hue_smoothed >= 0.0 and ng_scene_hue_smoothed <= NEGATIV_HUE_ARC_MAX)
        local hue_in_arc
        if in_arc then
            hue_in_arc = ng_scene_hue_smoothed
        else
            local dist_to_red   = ng_hue_circular_dist(ng_scene_hue_smoothed, 0.0)
            local dist_to_green = ng_hue_circular_dist(ng_scene_hue_smoothed, NEGATIV_HUE_ARC_MAX)
            hue_in_arc = (dist_to_red <= dist_to_green) and 0.0 or NEGATIV_HUE_ARC_MAX
        end
        hue_arc_clamped = not in_arc
        raw_stock_pos = (hue_in_arc / NEGATIV_HUE_ARC_MAX) * 2.0
    end
    out.hue_arc_clamped = hue_arc_clamped

    -- Mask gain & gamma: reads char_state.rendered (TIER 2's settled
    -- PREVIOUS-tick output), not raw_stock_pos — deliberate: keeps
    -- mask strength and mask color describing the SAME stock identity.
    local stock_idx_for_gain = math_floor(char_state.rendered + 0.5)
    stock_idx_for_gain = math_max(0, math_min(2, stock_idx_for_gain))
    local stock_mask_gain  = NEGATIV_STOCK_MASK_GAIN[stock_idx_for_gain + 1]  -- Lua 1-indexed
    local stock_gamma_nudge = NEGATIV_STOCK_GAMMA_NUDGE[stock_idx_for_gain + 1]

    if ng_scene_sat < 0 then
        -- HDR sentinel: no per-channel/saturation signal on this path.
        out.mask_gain_resolved = mode_mask_strength * stock_mask_gain
    else
        local exposure_delta = ng_frame_peak - NEGATIV_MASK_EXPOSURE_MID
        local exposure_mod = 1.0 - exposure_delta * NEGATIV_MASK_EXPOSURE_GAIN
        out.mask_gain_resolved = clamp(mode_mask_strength * stock_mask_gain * exposure_mod, 0.0, 2.0)
    end

    local contrast_term = -ng_scene_contrast * NEGATIV_GAMMA_SCENE_GAIN
    out.gamma_resolved = clamp(NEGATIV_GAMMA + stock_gamma_nudge + contrast_term,
        NEGATIV_GAMMA_CLAMP_MIN, NEGATIV_GAMMA_CLAMP_MAX)

    -- ── TIER 1/TIER 2 resolve ──
    local now = mp.get_time()

    local tier1_dt = math_min(now - (out.tier1_last_t > 0 and out.tier1_last_t or now - 0.1), 1.0)
    out.tier1_last_t = now
    local tier1_tau = ng_is_cut and NEGATIV_CUT_TAU or NEGATIV_TAU_ATTACK
    out.mask_gain_rendered = asym_smooth(out.mask_gain_rendered, out.mask_gain_resolved, tier1_tau, tier1_tau, tier1_dt)
    out.gamma_rendered      = asym_smooth(out.gamma_rendered,      out.gamma_resolved,      tier1_tau, tier1_tau, tier1_dt)

    local char_dt = math_min(now - (out.char_last_t > 0 and out.char_last_t or now - 0.1), 1.0)
    out.char_last_t = now
    out.stock_pos_rendered = ng_char_track(char_state, raw_stock_pos, now, char_dt, ng_is_cut)
end

-- ================================================================
--  4. MODE N
-- ================================================================
--  PARAMs, enabled flag, and TIER-1/2 state. Reads nothing
local GOR_NEGATIV_SOURCE_TRANSLUCID = [[
// ================================================================
//  photon-negativ-translucid - OUTPUT hook: unmasked negative
//  Host: photon-negativ.lua (GOR_NEGATIV_SOURCE_TRANSLUCID) -> photon-negativ-translucid.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!PARAM NG_GAMMA
//!TYPE DYNAMIC float
0.6

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC photon-negativ v1.2 — true-zero unmasked negative (mode 1)

// Runtime values arrive as PARAM uniforms (declared above the hook
// block). Only the never-changing curve/leak/grade constants stay
// baked; the Lua NEGATIV_* constants win over these literals at the
// one-time write
#define NG_TOE_WIDTH           0.2200
#define NG_SHOULDER_WIDTH      0.2400
#define NG_CROSSTALK_STRENGTH  0.6500
#define NG_CYAN_GREEN_LEAK     0.2200
#define NG_MAGENTA_BLUE_LEAK   0.1200
#define NG_YELLOW_LEAK         0.0500
#define NG_ADJACENCY_STRENGTH  0.3500
#define NG_POST_VIBRANCE       0.3500
#define NG_POST_CONTRAST       0.1800
#define NG_POST_BLACKPOINT     0.0300

// ln(10), for T = 10^-D via exp(-D * LN10) — avoids relying on pow()
// with a non-integer/non-constant base being well-supported across
// every mpv GLSL backend; exp() is universal.
const float LN10 = 2.302585093;

// D-min base density per channel (optical density units, D=-log10(T)).
// Bare physical stock reference — kept as one const per file (each
// mode file has its own copy now; this is not shared across files).
const vec3 DMIN_BASE = vec3(0.30, 0.60, 0.90);

// BT.709 luma weights — likewise a bare physical constant, own copy
// per file for the same reason as DMIN_BASE above.
const vec3 NEUTRAL_LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

mat3 crosstalk_matrix_translucid() {
    float cg = NG_CYAN_GREEN_LEAK * NG_CROSSTALK_STRENGTH;
    float mb = NG_MAGENTA_BLUE_LEAK * NG_CROSSTALK_STRENGTH;
    float yl = NG_YELLOW_LEAK * NG_CROSSTALK_STRENGTH;
    return mat3(
        1.0 - cg,      cg,            0.0,
        0.0,           1.0 - mb,      mb,
        yl * 0.5,      yl * 0.5,      1.0 - yl
    );
}

float negativ_curve_translucid(float x, float gamma, float toe_w, float shoulder_w) {
    float flattened = 0.5 + (x - 0.5) * gamma;
    float toe_taper = 1.0 - smoothstep(0.0, toe_w, flattened);
    float toe_floor = toe_w * 0.35;
    flattened = mix(flattened, toe_floor + flattened * (1.0 - toe_floor / max(toe_w, 0.001)), toe_taper);
    float shoulder_taper = smoothstep(1.0 - shoulder_w, 1.0, flattened);
    float shoulder_ceil = 1.0 - shoulder_w * 0.35;
    flattened = mix(flattened, shoulder_ceil + (flattened - shoulder_ceil) * 0.3, shoulder_taper);
    return clamp(flattened, 0.02, 0.98);
}

float adjacency_term_translucid(vec2 hooked_pos, vec3 luma_weights) {
    vec2 d = 1.0 / HOOKED_size;
    float l_n  = dot(HOOKED_tex(hooked_pos + vec2( 0.0, -d.y)).rgb, luma_weights);
    float l_s  = dot(HOOKED_tex(hooked_pos + vec2( 0.0,  d.y)).rgb, luma_weights);
    float l_e  = dot(HOOKED_tex(hooked_pos + vec2( d.x,  0.0)).rgb, luma_weights);
    float l_w  = dot(HOOKED_tex(hooked_pos + vec2(-d.x,  0.0)).rgb, luma_weights);
    float l_c  = dot(HOOKED_tex(hooked_pos                  ).rgb, luma_weights);
    float blurred = (l_n + l_s + l_e + l_w) * 0.25;
    return l_c - blurred;
}

vec3 apply_vibrance_translucid(vec3 color, float amount) {
    float maxc = max(color.r, max(color.g, color.b));
    float minc = min(color.r, min(color.g, color.b));
    float sat = maxc - minc;
    float boost = amount * (1.0 - sat);
    float avg = (color.r + color.g + color.b) / 3.0;
    return clamp(color + (color - vec3(avg)) * boost, 0.0, 1.0);
}

vec3 apply_contrast_translucid(vec3 color, float amount) {
    return clamp((color - vec3(0.5)) * (1.0 + amount) + vec3(0.5), 0.0, 1.0);
}

vec3 apply_blackpoint_translucid(vec3 color, float amount) {
    return clamp((color - vec3(amount)) / max(1.0 - amount, 0.001), 0.0, 1.0);
}

// Mask stage for TRANSLUCID: pure identity, by definition (this mode's
// whole stock identity IS the unmasked one -- see file header). No
// mask variable of any kind referenced.
vec3 mask_stage_translucid(vec3 curved) {
    return curved;
}

vec4 hook() {
    vec4 orig = HOOKED_tex(HOOKED_pos);
    vec3 color = orig.rgb;

    vec3 dye_response = crosstalk_matrix_translucid() * color;
    vec3 comp = clamp(1.0 - dye_response, 0.0, 1.0);

    vec3 curved;
    curved.r = negativ_curve_translucid(comp.r, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);
    curved.g = negativ_curve_translucid(comp.g, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);
    curved.b = negativ_curve_translucid(comp.b, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);

    float adj = adjacency_term_translucid(HOOKED_pos, NEUTRAL_LUMA_WEIGHTS);
    curved += vec3(adj * NG_ADJACENCY_STRENGTH);
    curved = clamp(curved, 0.0, 1.0);

    curved = apply_vibrance_translucid(curved, NG_POST_VIBRANCE);
    curved = apply_contrast_translucid(curved, NG_POST_CONTRAST);
    curved = apply_blackpoint_translucid(curved, NG_POST_BLACKPOINT);

    vec3 result = mask_stage_translucid(curved);

    return vec4(result, orig.a);
}

]]

-- Grouped to stay under Lua's 200 top-level-local limit.
local NG_N_STATE = {
    enabled = false,
    shader_path = nil,
    shader_written = false,
}
local ng_n_char_state = new_char_state(NEGATIV_STOCK)
local ng_n_resolved = {
    mask_gain_resolved = NEGATIV_TRANSLUCID_MASK_GAIN, gamma_resolved = NEGATIV_GAMMA,
    mask_gain_rendered = NEGATIV_TRANSLUCID_MASK_GAIN, gamma_rendered = NEGATIV_GAMMA,
    tier1_last_t = 0, char_last_t = 0, stock_pos_rendered = NEGATIV_STOCK, hue_arc_clamped = false,
}

-- One fixed file per mode, written ONCE per session: mpv gpu-next
-- caches parsed user shaders by path for the VO's lifetime, so a
-- same-path rewrite would silently keep serving the first version.
local function ng_n_ensure_path()
    if NG_N_STATE.shader_path then return NG_N_STATE.shader_path end
    NG_N_STATE.shader_path = common.shader_path("photon-negativ-translucid")
    return NG_N_STATE.shader_path
end

local function ng_n_write_shader()
    if NG_N_STATE.shader_written then return true end
    local path = ng_n_ensure_path()
    if not path then return false end
    local f = io.open(path, "w")
    if not f then mp.msg.error("photon-negativ(n): failed to write shader: " .. path); return false end
    f:write(ng_bake_common(GOR_NEGATIV_SOURCE_TRANSLUCID)); f:close()
    NG_N_STATE.shader_written = true
    mp.msg.info("photon-negativ(n) v1.2: shader written -> " .. path)
    return true
end

-- Every non-baked value, in one payload. Deduped in photon-common:
local function ng_n_push_params()
    common.push_params("photon-negativ-translucid", {
        {"NG_GAMMA", ng_n_resolved.gamma_rendered, "f"},
    })
end

-- glsl-shaders ownership contract: each script only touches its own path.
local function ng_n_ensure_glsl_list_sane(shaders)
    return common.ensure_glsl_list_sane(shaders, {ng_n_ensure_path()})
end

-- Inserts right after grain's own fixed path (pipeline order: decode ->
-- scale -> sharp -> grain -> negativ -> chrome); position 1 fallback
-- when grain is absent. Idempotent — enable and the 1Hz self-heal
local function ng_n_add_shader()
    local path = ng_n_ensure_path()
    if not path then return end
    local shaders = ng_n_ensure_glsl_list_sane(mp.get_property_native("glsl-shaders") or {})
    local filtered = {}
    for _, p in ipairs(shaders) do
        if p ~= path then table.insert(filtered, p) end
    end
    local dir = common.shader_dir()
    local grain_path = dir and (dir .. "photon-grain.glsl") or nil
    local insert_at = 1
    if grain_path then
        for i, p in ipairs(filtered) do
            if p == grain_path then insert_at = i + 1 end
        end
    end
    table.insert(filtered, insert_at, path)
    mp.set_property_native("glsl-shaders", filtered)
end

local function ng_n_remove_shader()
    if not NG_N_STATE.shader_path then return end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local filtered, changed = {}, false
    for _, p in ipairs(shaders) do
        if p == NG_N_STATE.shader_path then changed = true
        else table.insert(filtered, p) end
    end
    if changed then mp.set_property_native("glsl-shaders", filtered) end
end

local function ng_n_shader_in_list()
    local path = ng_n_ensure_path()
    if not path then return true end  -- can't check, assume fine
    for _, p in ipairs(mp.get_property_native("glsl-shaders") or {}) do
        if p == path then return true end
    end
    return false
end

-- Enable ordering: file on disk first, params pushed second, path
-- added last — the newly loaded shader's first frame already has live
-- values instead of PARAM defaults.
local function ng_n_enable()
    ng_n_write_shader()
    ng_n_push_params()
    ng_n_add_shader()
end

-- ================================================================
--  5. MODE H
-- ================================================================
--  PARAMs, enabled flag, and TIER-1/2 state. Reads nothing
local GOR_NEGATIV_SOURCE_HUEFLIP = [[
// ================================================================
//  photon-negativ-hueflip - OUTPUT hook: hue-flipped negative
//  Host: photon-negativ.lua (GOR_NEGATIV_SOURCE_HUEFLIP) -> photon-negativ-hueflip.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!PARAM NG_GAMMA
//!TYPE DYNAMIC float
0.6

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC photon-negativ v1.2 — unmasked negative, -180deg hue rotation (mode 2)

// Runtime values arrive as PARAM uniforms (declared above the hook
// block). Only the never-changing curve/leak/grade constants stay
// baked; the Lua NEGATIV_* constants win over these literals at the
// one-time write
#define NG_TOE_WIDTH           0.2200
#define NG_SHOULDER_WIDTH      0.2400
#define NG_CROSSTALK_STRENGTH  0.6500
#define NG_CYAN_GREEN_LEAK     0.2200
#define NG_MAGENTA_BLUE_LEAK   0.1200
#define NG_YELLOW_LEAK         0.0500
#define NG_ADJACENCY_STRENGTH  0.3500
#define NG_POST_VIBRANCE       0.3500
#define NG_POST_CONTRAST       0.1800
#define NG_POST_BLACKPOINT     0.0300
// NG_HUE_SHIFT: fraction of a full hue wheel to rotate by (wraps with
// fract()). 0.50 = exact -180deg opposite hue. Practical range ~0.40-
// 0.50: below ~0.35 skin/red tones stop reading as inverted; above
#define NG_HUE_SHIFT            0.4500
// NG_TOE_FLOOR_FACTOR / NG_SHOULDER_CEIL_FACTOR: how hard the toe/
// shoulder taper compresses, as a fraction of NG_TOE_WIDTH /
// NG_SHOULDER_WIDTH's span (0 = taper to a hard wall, 1 = no taper).
#define NG_TOE_FLOOR_FACTOR      0.3500
#define NG_SHOULDER_CEIL_FACTOR  0.3500
// NG_SHOULDER_ROLLOFF: how much of the shoulder's compressed value
// still moves per unit of input inside the taper (0 = dead flat,
// 1 = no softening).
#define NG_SHOULDER_ROLLOFF      0.3000

// ln(10), for T = 10^-D via exp(-D * LN10) — avoids relying on pow()
// with a non-integer/non-constant base being well-supported across
// every mpv GLSL backend; exp() is universal.
const float LN10 = 2.302585093;

// D-min base density per channel (optical density units, D=-log10(T)).
// Bare physical stock reference — kept as one const per file (each
// mode file has its own copy now; this is not shared across files).
const vec3 DMIN_BASE = vec3(0.30, 0.60, 0.90);

// BT.709 luma weights — likewise a bare physical constant, own copy
// per file for the same reason as DMIN_BASE above.
const vec3 NEUTRAL_LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

mat3 crosstalk_matrix_hueflip() {
    float cg = NG_CYAN_GREEN_LEAK * NG_CROSSTALK_STRENGTH;
    float mb = NG_MAGENTA_BLUE_LEAK * NG_CROSSTALK_STRENGTH;
    float yl = NG_YELLOW_LEAK * NG_CROSSTALK_STRENGTH;
    return mat3(
        1.0 - cg,      cg,            0.0,
        0.0,           1.0 - mb,      mb,
        yl * 0.5,      yl * 0.5,      1.0 - yl
    );
}

float negativ_curve_hueflip(float x, float gamma, float toe_w, float shoulder_w) {
    float flattened = 0.5 + (x - 0.5) * gamma;
    float toe_taper = 1.0 - smoothstep(0.0, toe_w, flattened);
    float toe_floor = toe_w * NG_TOE_FLOOR_FACTOR;
    flattened = mix(flattened, toe_floor + flattened * (1.0 - toe_floor / max(toe_w, 0.001)), toe_taper);
    float shoulder_taper = smoothstep(1.0 - shoulder_w, 1.0, flattened);
    float shoulder_ceil = 1.0 - shoulder_w * NG_SHOULDER_CEIL_FACTOR;
    flattened = mix(flattened, shoulder_ceil + (flattened - shoulder_ceil) * NG_SHOULDER_ROLLOFF, shoulder_taper);
    return clamp(flattened, 0.02, 0.98);
}

float adjacency_term_hueflip(vec2 hooked_pos, vec3 luma_weights) {
    vec2 d = 1.0 / HOOKED_size;
    float l_n  = dot(HOOKED_tex(hooked_pos + vec2( 0.0, -d.y)).rgb, luma_weights);
    float l_s  = dot(HOOKED_tex(hooked_pos + vec2( 0.0,  d.y)).rgb, luma_weights);
    float l_e  = dot(HOOKED_tex(hooked_pos + vec2( d.x,  0.0)).rgb, luma_weights);
    float l_w  = dot(HOOKED_tex(hooked_pos + vec2(-d.x,  0.0)).rgb, luma_weights);
    float l_c  = dot(HOOKED_tex(hooked_pos                  ).rgb, luma_weights);
    float blurred = (l_n + l_s + l_e + l_w) * 0.25;
    return l_c - blurred;
}

vec3 apply_vibrance_hueflip(vec3 color, float amount) {
    float maxc = max(color.r, max(color.g, color.b));
    float minc = min(color.r, min(color.g, color.b));
    float sat = maxc - minc;
    float boost = amount * (1.0 - sat);
    float avg = (color.r + color.g + color.b) / 3.0;
    return clamp(color + (color - vec3(avg)) * boost, 0.0, 1.0);
}

vec3 apply_contrast_hueflip(vec3 color, float amount) {
    return clamp((color - vec3(0.5)) * (1.0 + amount) + vec3(0.5), 0.0, 1.0);
}

vec3 apply_blackpoint_hueflip(vec3 color, float amount) {
    return clamp((color - vec3(amount)) / max(1.0 - amount, 0.001), 0.0, 1.0);
}

// Mask stage for HUEFLIP: pure identity, this mode's own independent
// choice (not inherited from mode 1 -- see mask_stage_translucid()
// above, a separate function this block never calls). If hueflip's
vec3 mask_stage_hueflip(vec3 curved) {
    return curved;
}

// Standard normalized (non-degree) RGB<->HSV pair -- hue lives in the
// half-open range 0 up to but not including 1, so a -180deg rotation
vec3 rgb_to_hsv_hueflip(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb_hueflip(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Rotates hue by -180deg/+0.5, wrapping with fract(). Saturation and
// value pass through unchanged.
vec3 hueflip_layer(vec3 color_in) {
    vec3 hsv = rgb_to_hsv_hueflip(color_in);
    hsv.x = fract(hsv.x + NG_HUE_SHIFT);
    return clamp(hsv_to_rgb_hueflip(hsv), 0.0, 1.0);
}

vec4 hook() {
    vec4 orig = HOOKED_tex(HOOKED_pos);
    vec3 color = orig.rgb;

    vec3 dye_response = crosstalk_matrix_hueflip() * color;
    vec3 comp = clamp(1.0 - dye_response, 0.0, 1.0);

    vec3 curved;
    curved.r = negativ_curve_hueflip(comp.r, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);
    curved.g = negativ_curve_hueflip(comp.g, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);
    curved.b = negativ_curve_hueflip(comp.b, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);

    float adj = adjacency_term_hueflip(HOOKED_pos, NEUTRAL_LUMA_WEIGHTS);
    curved += vec3(adj * NG_ADJACENCY_STRENGTH);
    curved = clamp(curved, 0.0, 1.0);

    curved = apply_vibrance_hueflip(curved, NG_POST_VIBRANCE);
    curved = apply_contrast_hueflip(curved, NG_POST_CONTRAST);
    curved = apply_blackpoint_hueflip(curved, NG_POST_BLACKPOINT);

    vec3 result = mask_stage_hueflip(curved);
    result = hueflip_layer(result);

    return vec4(result, orig.a);
}

]]

-- Hue rotation amount, HUEFLIP-only (see matching NG_HUE_SHIFT comment
-- tuned value is 0.45 -- a slight undershoot of true opposite that
-- keeps skin/red tones reading correctly after the full crosstalk +
-- curve + post-grade pipeline above has already run.
local NEGATIV_HUEFLIP_HUE_SHIFT = 0.45

-- Toe/shoulder compression factors (see matching NG_TOE_FLOOR_FACTOR /
-- NG_SHOULDER_CEIL_FACTOR / NG_SHOULDER_ROLLOFF comments in the shader
-- source above). HUEFLIP-only, same reasoning as hue shift above.
local NEGATIV_HUEFLIP_TOE_FLOOR_FACTOR = 0.35
local NEGATIV_HUEFLIP_SHOULDER_CEIL_FACTOR = 0.35
local NEGATIV_HUEFLIP_SHOULDER_ROLLOFF = 0.30

-- Grouped to stay under Lua's 200 top-level-local limit.
local NG_H_STATE = {
    enabled = false,
    shader_path = nil,
    shader_written = false,
}
local ng_h_char_state = new_char_state(NEGATIV_STOCK)
local ng_h_resolved = {
    mask_gain_resolved = NEGATIV_TRANSLUCID_MASK_GAIN, gamma_resolved = NEGATIV_GAMMA,
    mask_gain_rendered = NEGATIV_TRANSLUCID_MASK_GAIN, gamma_rendered = NEGATIV_GAMMA,
    tier1_last_t = 0, char_last_t = 0, stock_pos_rendered = NEGATIV_STOCK, hue_arc_clamped = false,
}

-- One fixed file per mode, written ONCE per session: mpv gpu-next
-- caches parsed user shaders by path for the VO's lifetime, so a
-- same-path rewrite would silently keep serving the first version.
local function ng_h_ensure_path()
    if NG_H_STATE.shader_path then return NG_H_STATE.shader_path end
    NG_H_STATE.shader_path = common.shader_path("photon-negativ-hueflip")
    return NG_H_STATE.shader_path
end

local function ng_h_write_shader()
    if NG_H_STATE.shader_written then return true end
    local path = ng_h_ensure_path()
    if not path then return false end
    local f = io.open(path, "w")
    if not f then mp.msg.error("photon-negativ(h): failed to write shader: " .. path); return false end
    local content = ng_bake_common(GOR_NEGATIV_SOURCE_HUEFLIP)
        :gsub("#define NG_HUE_SHIFT%s+%-?[%d.]+",
            string.format("#define NG_HUE_SHIFT            %.4f", NEGATIV_HUEFLIP_HUE_SHIFT))
        :gsub("#define NG_TOE_FLOOR_FACTOR%s+%-?[%d.]+",
            string.format("#define NG_TOE_FLOOR_FACTOR      %.4f", NEGATIV_HUEFLIP_TOE_FLOOR_FACTOR))
        :gsub("#define NG_SHOULDER_CEIL_FACTOR%s+%-?[%d.]+",
            string.format("#define NG_SHOULDER_CEIL_FACTOR  %.4f", NEGATIV_HUEFLIP_SHOULDER_CEIL_FACTOR))
        :gsub("#define NG_SHOULDER_ROLLOFF%s+%-?[%d.]+",
            string.format("#define NG_SHOULDER_ROLLOFF      %.4f", NEGATIV_HUEFLIP_SHOULDER_ROLLOFF))
    f:write(content); f:close()
    NG_H_STATE.shader_written = true
    mp.msg.info("photon-negativ(h) v1.2: shader written -> " .. path)
    return true
end

-- Every non-baked value, in one payload. Deduped in photon-common:
local function ng_h_push_params()
    common.push_params("photon-negativ-hueflip", {
        {"NG_GAMMA", ng_h_resolved.gamma_rendered, "f"},
    })
end

-- glsl-shaders ownership contract: each script only touches its own path.
local function ng_h_ensure_glsl_list_sane(shaders)
    return common.ensure_glsl_list_sane(shaders, {ng_h_ensure_path()})
end

-- Inserts right after grain's own fixed path (pipeline order: decode ->
-- scale -> sharp -> grain -> negativ -> chrome); position 1 fallback
-- when grain is absent. Idempotent — enable and the 1Hz self-heal
local function ng_h_add_shader()
    local path = ng_h_ensure_path()
    if not path then return end
    local shaders = ng_h_ensure_glsl_list_sane(mp.get_property_native("glsl-shaders") or {})
    local filtered = {}
    for _, p in ipairs(shaders) do
        if p ~= path then table.insert(filtered, p) end
    end
    local dir = common.shader_dir()
    local grain_path = dir and (dir .. "photon-grain.glsl") or nil
    local insert_at = 1
    if grain_path then
        for i, p in ipairs(filtered) do
            if p == grain_path then insert_at = i + 1 end
        end
    end
    table.insert(filtered, insert_at, path)
    mp.set_property_native("glsl-shaders", filtered)
end

local function ng_h_remove_shader()
    if not NG_H_STATE.shader_path then return end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local filtered, changed = {}, false
    for _, p in ipairs(shaders) do
        if p == NG_H_STATE.shader_path then changed = true
        else table.insert(filtered, p) end
    end
    if changed then mp.set_property_native("glsl-shaders", filtered) end
end

local function ng_h_shader_in_list()
    local path = ng_h_ensure_path()
    if not path then return true end  -- can't check, assume fine
    for _, p in ipairs(mp.get_property_native("glsl-shaders") or {}) do
        if p == path then return true end
    end
    return false
end

-- Enable ordering: file on disk first, params pushed second, path
-- added last — the newly loaded shader's first frame already has live
-- values instead of PARAM defaults.
local function ng_h_enable()
    ng_h_write_shader()
    ng_h_push_params()
    ng_h_add_shader()
end

-- ================================================================
--  6. MODE M
-- ================================================================
--  source, own fixed shader path and PARAMs, enabled flag, TIER-1/TIER-2
--  render state. Nothing in this block is read by the other two
--  modes' blocks, and this block reads nothing from theirs.
local GOR_NEGATIV_SOURCE_MASK = [[
// ================================================================
//  photon-negativ-mask - OUTPUT hook: orange-mask negative
//  Host: photon-negativ.lua (GOR_NEGATIV_SOURCE_MASK) -> photon-negativ-mask.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!PARAM NG_GAMMA
//!TYPE DYNAMIC float
0.6

//!PARAM NG_MASK_GAIN
//!TYPE DYNAMIC float
1.0

//!PARAM NG_STOCK_POS
//!TYPE DYNAMIC float
1.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC photon-negativ v1.2 — full orange D-min mask negative (mode 3)

// Runtime values arrive as PARAM uniforms (declared above the hook
// block). Only the never-changing curve/leak/grade constants stay
// baked; the Lua NEGATIV_* constants win over these literals at the
// one-time write
#define NG_TOE_WIDTH           0.2200
#define NG_SHOULDER_WIDTH      0.2400
#define NG_CROSSTALK_STRENGTH  0.6500
#define NG_CYAN_GREEN_LEAK     0.2200
#define NG_MAGENTA_BLUE_LEAK   0.1200
#define NG_YELLOW_LEAK         0.0500
#define NG_ADJACENCY_STRENGTH  0.3500
#define NG_POST_VIBRANCE       0.3500
#define NG_POST_CONTRAST       0.1800
#define NG_POST_BLACKPOINT     0.0300

// ln(10), for T = 10^-D via exp(-D * LN10) — avoids relying on pow()
// with a non-integer/non-constant base being well-supported across
// every mpv GLSL backend; exp() is universal.
const float LN10 = 2.302585093;

// D-min base density per channel (optical density units, D=-log10(T)).
// Bare physical stock reference — kept as one const per file (each
// mode file has its own copy now; this is not shared across files).
const vec3 DMIN_BASE = vec3(0.30, 0.60, 0.90);

// BT.709 luma weights — likewise a bare physical constant, own copy
// per file for the same reason as DMIN_BASE above.
const vec3 NEUTRAL_LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

// Per-stock D-min RATIO shift -- MASK's own copy of this table. Index
// matches NG_STOCK_POS: 0=ECN-2 (tighter mask), 1=C-41 (reference, no
// shift), 2=vintage-warm (heavier mask). Only MASK's block references
const vec3 stock_dmin_shift_mask[3] = vec3[3](
    vec3(0.00, -0.06, -0.08),
    vec3(0.00,  0.00,  0.00),
    vec3(0.00,  0.08,  0.14)
);

mat3 crosstalk_matrix_mask() {
    float cg = NG_CYAN_GREEN_LEAK * NG_CROSSTALK_STRENGTH;
    float mb = NG_MAGENTA_BLUE_LEAK * NG_CROSSTALK_STRENGTH;
    float yl = NG_YELLOW_LEAK * NG_CROSSTALK_STRENGTH;
    return mat3(
        1.0 - cg,      cg,            0.0,
        0.0,           1.0 - mb,      mb,
        yl * 0.5,      yl * 0.5,      1.0 - yl
    );
}

float negativ_curve_mask(float x, float gamma, float toe_w, float shoulder_w) {
    float flattened = 0.5 + (x - 0.5) * gamma;
    float toe_taper = 1.0 - smoothstep(0.0, toe_w, flattened);
    float toe_floor = toe_w * 0.35;
    flattened = mix(flattened, toe_floor + flattened * (1.0 - toe_floor / max(toe_w, 0.001)), toe_taper);
    float shoulder_taper = smoothstep(1.0 - shoulder_w, 1.0, flattened);
    float shoulder_ceil = 1.0 - shoulder_w * 0.35;
    flattened = mix(flattened, shoulder_ceil + (flattened - shoulder_ceil) * 0.3, shoulder_taper);
    return clamp(flattened, 0.02, 0.98);
}

float adjacency_term_mask(vec2 hooked_pos, vec3 luma_weights) {
    vec2 d = 1.0 / HOOKED_size;
    float l_n  = dot(HOOKED_tex(hooked_pos + vec2( 0.0, -d.y)).rgb, luma_weights);
    float l_s  = dot(HOOKED_tex(hooked_pos + vec2( 0.0,  d.y)).rgb, luma_weights);
    float l_e  = dot(HOOKED_tex(hooked_pos + vec2( d.x,  0.0)).rgb, luma_weights);
    float l_w  = dot(HOOKED_tex(hooked_pos + vec2(-d.x,  0.0)).rgb, luma_weights);
    float l_c  = dot(HOOKED_tex(hooked_pos                  ).rgb, luma_weights);
    float blurred = (l_n + l_s + l_e + l_w) * 0.25;
    return l_c - blurred;
}

vec3 apply_vibrance_mask(vec3 color, float amount) {
    float maxc = max(color.r, max(color.g, color.b));
    float minc = min(color.r, min(color.g, color.b));
    float sat = maxc - minc;
    float boost = amount * (1.0 - sat);
    float avg = (color.r + color.g + color.b) / 3.0;
    return clamp(color + (color - vec3(avg)) * boost, 0.0, 1.0);
}

vec3 apply_contrast_mask(vec3 color, float amount) {
    return clamp((color - vec3(0.5)) * (1.0 + amount) + vec3(0.5), 0.0, 1.0);
}

vec3 apply_blackpoint_mask(vec3 color, float amount) {
    return clamp((color - vec3(amount)) / max(1.0 - amount, 0.001), 0.0, 1.0);
}

// Full D-min mask math, exactly as originally written -- untouched by
// this split beyond the name/table suffix.
vec3 mask_stage_masked(vec3 curved) {
    float nsp = clamp(NG_STOCK_POS, 0.0, 2.0);
    int nsi = int(floor(nsp));
    int nsn = min(nsi + 1, 2);
    vec3 stock_shift = mix(stock_dmin_shift_mask[nsi], stock_dmin_shift_mask[nsn], nsp - float(nsi));
    vec3 dmin_density = (DMIN_BASE + stock_shift) * clamp(NG_MASK_GAIN, 0.0, 2.0);
    vec3 mask_transmission = exp(-dmin_density * LN10);  // T = 10^-D

    vec3 result = curved * mask_transmission;

    float mask_norm = max(mask_transmission.r, max(mask_transmission.g, mask_transmission.b));
    result = result / max(mask_norm, 0.001);
    return clamp(result, 0.0, 1.0);
}

vec4 hook() {
    vec4 orig = HOOKED_tex(HOOKED_pos);
    vec3 color = orig.rgb;

    vec3 dye_response = crosstalk_matrix_mask() * color;
    vec3 comp = clamp(1.0 - dye_response, 0.0, 1.0);

    vec3 curved;
    curved.r = negativ_curve_mask(comp.r, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);
    curved.g = negativ_curve_mask(comp.g, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);
    curved.b = negativ_curve_mask(comp.b, NG_GAMMA, NG_TOE_WIDTH, NG_SHOULDER_WIDTH);

    float adj = adjacency_term_mask(HOOKED_pos, NEUTRAL_LUMA_WEIGHTS);
    curved += vec3(adj * NG_ADJACENCY_STRENGTH);
    curved = clamp(curved, 0.0, 1.0);

    curved = apply_vibrance_mask(curved, NG_POST_VIBRANCE);
    curved = apply_contrast_mask(curved, NG_POST_CONTRAST);
    curved = apply_blackpoint_mask(curved, NG_POST_BLACKPOINT);

    vec3 result = mask_stage_masked(curved);

    return vec4(result, orig.a);
}

]]

-- Grouped to stay under Lua's 200 top-level-local limit.
local NG_M_STATE = {
    enabled = false,
    shader_path = nil,
    shader_written = false,
}
local ng_m_char_state = new_char_state(NEGATIV_STOCK)
local ng_m_resolved = {
    mask_gain_resolved = NEGATIV_MASK_STRENGTH, gamma_resolved = NEGATIV_GAMMA,
    mask_gain_rendered = NEGATIV_MASK_STRENGTH, gamma_rendered = NEGATIV_GAMMA,
    tier1_last_t = 0, char_last_t = 0, stock_pos_rendered = NEGATIV_STOCK, hue_arc_clamped = false,
}

-- One fixed file per mode, written ONCE per session: mpv gpu-next
-- caches parsed user shaders by path for the VO's lifetime, so a
-- same-path rewrite would silently keep serving the first version.
local function ng_m_ensure_path()
    if NG_M_STATE.shader_path then return NG_M_STATE.shader_path end
    NG_M_STATE.shader_path = common.shader_path("photon-negativ-mask")
    return NG_M_STATE.shader_path
end

local function ng_m_write_shader()
    if NG_M_STATE.shader_written then return true end
    local path = ng_m_ensure_path()
    if not path then return false end
    local f = io.open(path, "w")
    if not f then mp.msg.error("photon-negativ(m): failed to write shader: " .. path); return false end
    f:write(ng_bake_common(GOR_NEGATIV_SOURCE_MASK)); f:close()
    NG_M_STATE.shader_written = true
    mp.msg.info("photon-negativ(m) v1.2: shader written -> " .. path)
    return true
end

-- Every non-baked value, in one payload. Deduped in photon-common:
local function ng_m_push_params()
    common.push_params("photon-negativ-mask", {
        {"NG_GAMMA", ng_m_resolved.gamma_rendered, "f"},
        {"NG_MASK_GAIN", ng_m_resolved.mask_gain_rendered, "f"},
        {"NG_STOCK_POS", ng_m_resolved.stock_pos_rendered, "f"},
    })
end

-- glsl-shaders ownership contract: each script only touches its own path.
local function ng_m_ensure_glsl_list_sane(shaders)
    return common.ensure_glsl_list_sane(shaders, {ng_m_ensure_path()})
end

-- Inserts right after grain's own fixed path (pipeline order: decode ->
-- scale -> sharp -> grain -> negativ -> chrome); position 1 fallback
-- when grain is absent. Idempotent — enable and the 1Hz self-heal
local function ng_m_add_shader()
    local path = ng_m_ensure_path()
    if not path then return end
    local shaders = ng_m_ensure_glsl_list_sane(mp.get_property_native("glsl-shaders") or {})
    local filtered = {}
    for _, p in ipairs(shaders) do
        if p ~= path then table.insert(filtered, p) end
    end
    local dir = common.shader_dir()
    local grain_path = dir and (dir .. "photon-grain.glsl") or nil
    local insert_at = 1
    if grain_path then
        for i, p in ipairs(filtered) do
            if p == grain_path then insert_at = i + 1 end
        end
    end
    table.insert(filtered, insert_at, path)
    mp.set_property_native("glsl-shaders", filtered)
end

local function ng_m_remove_shader()
    if not NG_M_STATE.shader_path then return end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local filtered, changed = {}, false
    for _, p in ipairs(shaders) do
        if p == NG_M_STATE.shader_path then changed = true
        else table.insert(filtered, p) end
    end
    if changed then mp.set_property_native("glsl-shaders", filtered) end
end

local function ng_m_shader_in_list()
    local path = ng_m_ensure_path()
    if not path then return true end  -- can't check, assume fine
    for _, p in ipairs(mp.get_property_native("glsl-shaders") or {}) do
        if p == path then return true end
    end
    return false
end

-- Enable ordering: file on disk first, params pushed second, path
-- added last — the newly loaded shader's first frame already has live
-- values instead of PARAM defaults.
local function ng_m_enable()
    ng_m_write_shader()
    ng_m_push_params()
    ng_m_add_shader()
end

-- ================================================================
--  7. NGANYENABLED
-- ================================================================
--  used by ng_publish_hud_state. Lives here (after all three mode
--  blocks) because it is the first piece of code that needs to see all
--  three ng_*_enabled flags at once. Used to also back the HDR hwdec
local function ng_any_enabled()
    return NG_N_STATE.enabled or NG_H_STATE.enabled or NG_M_STATE.enabled
end

-- REMOVED: ng_signal_hw_copyback. This function used to tell the Swift
-- host, via gor-osd:negativhwon/negativhwoff, whether any of negativ's
-- three modes wanted hwdec=videotoolbox-copy for the HDR hue vf-filter

-- ================================================================
--  8. HUD PUBLISH
-- ================================================================
--  NG_MODE_NAMES doesn't exist in this version (no single ng_mode
--  integer to look up — each mode's identity is which block it's
--  declared in, not a value); "active_mode" below is derived directly
local function ng_active_mode_name()
    -- "Last pressed wins" means at most one of the three should ever be
    -- true at once in normal operation, but this checks in a fixed,
    -- arbitrary but stable order (n, then h, then m) rather than
    if NG_N_STATE.enabled then return "translucid" end
    if NG_H_STATE.enabled then return "hueflip" end
    if NG_M_STATE.enabled then return "mask" end
    return "off"
end

local function ng_publish_hud_state()
    local active = ng_active_mode_name()
    -- hud_stock_idx / mask_gain / gamma are read from whichever mode is
    -- actually active's own resolved table — an inactive mode's numbers
    -- would be stale (frozen at whatever they last held while that mode
    local resolved, stock_rendered
    if active == "translucid" then resolved, stock_rendered = ng_n_resolved, ng_n_resolved.stock_pos_rendered
    elseif active == "hueflip" then resolved, stock_rendered = ng_h_resolved, ng_h_resolved.stock_pos_rendered
    elseif active == "mask" then resolved, stock_rendered = ng_m_resolved, ng_m_resolved.stock_pos_rendered
    else resolved, stock_rendered = nil, NEGATIV_STOCK
    end
    local hud_stock_idx = math_floor(stock_rendered + 0.5)
    mp.commandv("script-message", "photon-negativ-hud-state",
        tostring(ng_any_enabled()),
        tostring(hud_stock_idx),
        string.format("%.2f", resolved and resolved.mask_gain_rendered or 0.0),
        string.format("%.2f", resolved and resolved.gamma_rendered or NEGATIV_GAMMA),
        tostring(ng_has_feed),
        tostring(NEGATIV_HUE_DRIVEN),
        ng_scene_hue_smoothed and string.format("%.4f", ng_scene_hue_smoothed) or "",
        tostring(resolved and resolved.hue_arc_clamped or false),
        -- 9th field: which mode is actually on screen, or "off" if
        -- none. Bare string, not a table lookup — see block comment.
        active,
        ng_scene_hue~=nil and "sample"or(ng_scene_hue_smoothed~=nil and "held"or "unavailable"))
end

-- ================================================================
--  9. SCENE FEED HANDLER
-- ================================================================
--  point. Resolves and pushes params for EVERY mode that is currently
--  enabled — not just one — since more than one
--  mode's Lua-side state can technically be live even though only one
local photon_scene_kv_decode = common.scene_kv_decode

mp.register_script_message("photon-scene-feed", function(payload)
    local f = photon_scene_kv_decode(payload)
    local is_first_feed = not ng_has_feed
    ng_frame_peak     = tonumber(f.peak)     or ng_frame_peak
    ng_scene_contrast = tonumber(f.contrast) or ng_scene_contrast
    ng_scene_sat      = tonumber(f.sat)      or ng_scene_sat
    ng_motion_level   = tonumber(f.motion)   or ng_motion_level
    ng_is_hdr         = (f.is_hdr == "true")
    ng_is_cut         = (f.is_cut == "true")
    ng_has_feed       = true
    ng_scene_hue      = tonumber(f.hue)

    if ng_scene_hue == nil then
        -- No usable sample this feed — leave the smoothed value as-is.
    else
        ng_scene_hue_smoothed = common.smooth_hue(ng_scene_hue_smoothed, ng_scene_hue,
            NEGATIV_HUE_EMA_ALPHA, ng_is_cut or ng_scene_hue_smoothed == nil)
    end

    -- ── TRANSLUCID n ──
    if NG_N_STATE.enabled then
        ng_resolve_adaptive_params(NEGATIV_TRANSLUCID_MASK_GAIN, ng_n_char_state, ng_n_resolved)
        if is_first_feed then
            ng_n_resolved.mask_gain_rendered = ng_n_resolved.mask_gain_resolved
            ng_n_resolved.gamma_rendered      = ng_n_resolved.gamma_resolved
        end
        -- Params land every feed tick via one deduped change-list
        -- add — no file I/O, no rebuild, no throttle to keep.
        ng_n_push_params()
    end

    -- ── HUEFLIP h ──
    if NG_H_STATE.enabled then
        ng_resolve_adaptive_params(NEGATIV_TRANSLUCID_MASK_GAIN, ng_h_char_state, ng_h_resolved)
        if is_first_feed then
            ng_h_resolved.mask_gain_rendered = ng_h_resolved.mask_gain_resolved
            ng_h_resolved.gamma_rendered      = ng_h_resolved.gamma_resolved
        end
        -- Params land every feed tick via one deduped change-list
        -- add — no file I/O, no rebuild, no throttle to keep.
        ng_h_push_params()
    end

    -- ── MASK m ──
    if NG_M_STATE.enabled then
        ng_resolve_adaptive_params(NEGATIV_MASK_STRENGTH, ng_m_char_state, ng_m_resolved)
        if is_first_feed then
            ng_m_resolved.mask_gain_rendered = ng_m_resolved.mask_gain_resolved
            ng_m_resolved.gamma_rendered      = ng_m_resolved.gamma_resolved
        end
        -- Params land every feed tick via one deduped change-list
        -- add — no file I/O, no rebuild, no throttle to keep.
        ng_m_push_params()
    end
end)

-- ================================================================
--  10. TOGGLE
-- ================================================================
--  translucid -> hueflip -> mask -> off. ★ SAFE despite reintroducing
--  compiled shader; this is 1 index choosing among 3 still-fully-

-- 0=off, 1=translucid, 2=hueflip, 3=mask. Starts at 0 (matches each
-- mode's own ng_*_enabled starting false); file-loaded resets it to 0
-- alongside the three modes it already resets (see handler below).
local ng_relay_pos = 0

-- Turns OFF whichever position is active, if any — calls straight into
-- that mode's own already-independent disable sequence, same as each
-- mode's old standalone handler, just invoked from one shared call site.
local function ng_relay_turn_off_current()
    if ng_relay_pos == 1 and NG_N_STATE.enabled then
        NG_N_STATE.enabled = false
        ng_n_remove_shader()
        mp.msg.info("photon-negativ(n): disabled")
    elseif ng_relay_pos == 2 and NG_H_STATE.enabled then
        NG_H_STATE.enabled = false
        ng_h_remove_shader()
        mp.msg.info("photon-negativ(h): disabled")
    elseif ng_relay_pos == 3 and NG_M_STATE.enabled then
        NG_M_STATE.enabled = false
        ng_m_remove_shader()
        mp.msg.info("photon-negativ(m): disabled")
    end
end

-- Turns ON the position just moved to — calls that mode's own already-
-- independent enable sequence: resolve, snap TIER 1 to target, then
-- write (once) + push + add.
local function ng_relay_turn_on_new()
    if ng_relay_pos == 1 then
        NG_N_STATE.enabled = true
        ng_resolve_adaptive_params(NEGATIV_TRANSLUCID_MASK_GAIN, ng_n_char_state, ng_n_resolved)
        ng_n_resolved.mask_gain_rendered = ng_n_resolved.mask_gain_resolved
        ng_n_resolved.gamma_rendered      = ng_n_resolved.gamma_resolved
        ng_n_enable()
        mp.msg.info("photon-negativ(n): enabled")
    elseif ng_relay_pos == 2 then
        NG_H_STATE.enabled = true
        ng_resolve_adaptive_params(NEGATIV_TRANSLUCID_MASK_GAIN, ng_h_char_state, ng_h_resolved)
        ng_h_resolved.mask_gain_rendered = ng_h_resolved.mask_gain_resolved
        ng_h_resolved.gamma_rendered      = ng_h_resolved.gamma_resolved
        ng_h_enable()
        mp.msg.info("photon-negativ(h): enabled")
    elseif ng_relay_pos == 3 then
        NG_M_STATE.enabled = true
        ng_resolve_adaptive_params(NEGATIV_MASK_STRENGTH, ng_m_char_state, ng_m_resolved)
        ng_m_resolved.mask_gain_rendered = ng_m_resolved.mask_gain_resolved
        ng_m_resolved.gamma_rendered      = ng_m_resolved.gamma_resolved
        ng_m_enable()
        mp.msg.info("photon-negativ(m): enabled")
    else -- ng_relay_pos == 0
        mp.msg.info("photon-negativ: all modes disabled")
    end
end

--  TARGET-ENABLED CARRYOVER (P0-6) — mirrors chrome's pattern.
--  photon.lua's file-loaded broadcasts photon-negativ-set-target-enabled
--  from negativ_user_enabled (Swift's declared state for this axis), but
--  script/file-loaded event order across scripts is undefined. The two
--  flags rendezvous: whichever arrives second applies the target. The
--  declaration is absolute and idempotent (same contract as grain's and
--  sharp's targets): negativ_target_enabled holds the LATEST declared
--  state and every later file-loaded or declaration re-applies it, so
--  the flags latch once instead of resetting per cycle — a declaration
--  that lands while this script's file-loaded is still queued must
--  survive that file-loaded's own reset.
--  ng_saved_relay_pos remembers WHICH mode was on (the target is a bare
--  bool); it is captured at file-loaded before the reset and refreshed
--  on every local toggle, so the user's last choice is what carries.
local negativ_target_enabled            = false
local ng_carryover_saw_file_loaded      = false
local ng_carryover_saw_target_message   = false
local ng_saved_relay_pos                = 0

local function ng_maybe_apply_carryover()
    if not (ng_carryover_saw_file_loaded and ng_carryover_saw_target_message) then return end
    if negativ_target_enabled and not ng_any_enabled() then
        if ng_saved_relay_pos > 0 then
            ng_relay_pos = ng_saved_relay_pos
            mp.set_property("user-data/gor/negativ", "1")
            ng_relay_turn_on_new()
        end
    elseif not negativ_target_enabled and ng_any_enabled() then
        if NG_N_STATE.enabled then NG_N_STATE.enabled = false; ng_n_remove_shader() end
        if NG_H_STATE.enabled then NG_H_STATE.enabled = false; ng_h_remove_shader() end
        if NG_M_STATE.enabled then NG_M_STATE.enabled = false; ng_m_remove_shader() end
        ng_relay_pos = 0
        mp.set_property("user-data/gor/negativ", "0")
    end
    ng_publish_hud_state()
end

mp.register_script_message("photon-negativ-set-target-enabled", function(val)
    negativ_target_enabled = (val == "true")
    ng_carryover_saw_target_message = true
    ng_maybe_apply_carryover()
end)

mp.register_script_message("photon-negativ-toggle", function()
    ng_relay_turn_off_current()
    ng_relay_pos = (ng_relay_pos + 1) % 4
    -- Local toggles redefine what the next file carries over (same sync
    -- chrome does in its own toggle): the target var follows the user's
    -- actual state even if Swift's next declaration is lost.
    negativ_target_enabled = (ng_relay_pos ~= 0)
    ng_saved_relay_pos     = ng_relay_pos
    mp.set_property("user-data/gor/negativ", (ng_relay_pos == 0) and "0" or "1")
    ng_relay_turn_on_new()
    ng_publish_hud_state()
end)

-- ================================================================
--  11. FILE-LOADED
-- ================================================================
--  all 3 modes OFF. Old carry-over machinery only decided inheritance
--  of one shared enabled/mode state — no such shared state exists now.
mp.register_event("file-loaded", function()
    -- Capture the mode to carry over BEFORE the reset below zeroes it
    -- (P0-6). The rendezvous flags LATCH (they are not reset per cycle):
    -- a target declaration that arrived while this file-loaded was
    -- queued declared an absolute state, and the apply at the end of
    -- this handler is what honors it.
    if ng_relay_pos > 0 then ng_saved_relay_pos = ng_relay_pos end
    ng_carryover_saw_file_loaded    = true
    if NG_N_STATE.enabled then NG_N_STATE.enabled = false; ng_n_remove_shader() end
    if NG_H_STATE.enabled then NG_H_STATE.enabled = false; ng_h_remove_shader() end
    if NG_M_STATE.enabled then NG_M_STATE.enabled = false; ng_m_remove_shader() end
    ng_relay_pos = 0
    mp.set_property("user-data/gor/negativ", "0")

    ng_has_feed          = false

    -- Reset raw scene vars to neutral: without this, a fresh load would
    -- briefly resolve from the PREVIOUS video's last peak/contrast/sat
    -- until the new file's first real scene feed arrives.
    ng_frame_peak     = 0.50
    ng_scene_contrast = 0.35
    ng_scene_sat      = 0.10
    ng_motion_level   = 0.20
    ng_scene_hue          = nil
    ng_scene_hue_smoothed = nil

    -- TIER 2 character state reset for all three modes' own tracking
    -- tables — each independently, since each is its own table now.
    ng_char_state_reset(ng_n_char_state)
    ng_char_state_reset(ng_h_char_state)
    ng_char_state_reset(ng_m_char_state)
    ng_n_resolved.tier1_last_t, ng_n_resolved.char_last_t = 0, 0
    ng_h_resolved.tier1_last_t, ng_h_resolved.char_last_t = 0, 0
    ng_m_resolved.tier1_last_t, ng_m_resolved.char_last_t = 0, 0
    ng_n_resolved.stock_pos_rendered = NEGATIV_STOCK
    ng_h_resolved.stock_pos_rendered = NEGATIV_STOCK
    ng_m_resolved.stock_pos_rendered = NEGATIV_STOCK
    ng_n_resolved.mask_gain_rendered, ng_n_resolved.gamma_rendered = NEGATIV_TRANSLUCID_MASK_GAIN, NEGATIV_GAMMA
    ng_h_resolved.mask_gain_rendered, ng_h_resolved.gamma_rendered = NEGATIV_TRANSLUCID_MASK_GAIN, NEGATIV_GAMMA
    ng_m_resolved.mask_gain_rendered, ng_m_resolved.gamma_rendered = NEGATIV_MASK_STRENGTH, NEGATIV_GAMMA

    -- ng_is_hdr may still reflect the previous file here (not reset
    -- above — same as photon.lua's own detect_format hasn't run for

    -- P0-6: if the target declaration already landed (photon.lua's
    -- file-loaded ran first), this restores/disables now; otherwise the
    -- set-target-enabled handler applies it when it arrives.
    ng_maybe_apply_carryover()
    ng_publish_hud_state()
end)

-- ================================================================
--  12. TIMER
-- ================================================================
--  cadence). Runs independently per mode: each checks its OWN shader-
--  in-list state, re-adds only itself, never touches the others.
local function ng_periodic_update()
    ng_publish_hud_state()

    if NG_N_STATE.enabled then
        if not ng_n_shader_in_list() then ng_n_add_shader() end
    end

    if NG_H_STATE.enabled then
        if not ng_h_shader_in_list() then ng_h_add_shader() end
    end

    if NG_M_STATE.enabled then
        if not ng_m_shader_in_list() then ng_m_add_shader() end
    end
end

mp.add_periodic_timer(1.0, ng_periodic_update)

-- Startup: delete legacy A/B slot files so the pre-PARAM scheme can
-- never resurface, then write each mode's PARAM-based file once.
-- Nothing in this session rewrites those paths (mpv gpu-next caches
local function ng_delete_legacy_files()
    local dir = common.shader_dir()
    if not dir then return end
    for _, name in ipairs({"translucid", "hueflip", "mask"}) do
        os.remove(dir .. "photon-negativ-" .. name .. "-a.glsl")
        os.remove(dir .. "photon-negativ-" .. name .. "-b.glsl")
    end
end
ng_delete_legacy_files()
ng_n_write_shader()
ng_h_write_shader()
ng_m_write_shader()
