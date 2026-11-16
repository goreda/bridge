-- ================================================================
--  photon-chrome.lua - OUTPUT-stage monochrome print
--  Owns: chrome shader, filter state and messages
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
        mp.msg.error("photon-chrome: photon-scriptdir invalid or photon-common.lua missing - checked: " .. script_dir .. "/photon-common.lua")
    end
end
local common_ok, common = pcall(require, "photon-common")
if not common_ok then
    mp.msg.error("photon-chrome: could not load photon-common - " .. tostring(common) .. ". This script is disabled.")
    return
end
local PHOTON_REQUIRED_COMMON_VERSION = 2
if not common.check_version("photon-chrome", PHOTON_REQUIRED_COMMON_VERSION) then
    return
end


-- ================================================================
--  1. CONTROL PANEL
-- ================================================================

-- Virtual color filter. 0=red, 1=orange, 2=yellow, 3=green. Orange is the
-- default: closest single-filter match to the Black & Chrome palette
-- (desert orange/sand + blue sky + fire — orange gives strong sky
local CHROME_FILTER          = 1
-- Filter strength: how far the virtual filter pulls channel weights
-- away from neutral Rec.709 luma. 0 = plain luma (filter has no effect,
-- pure desaturate). 1 = full filter character as tuned below.
local CHROME_FILTER_STRENGTH = 0.75
-- Hue-driven continuous filter position: instead of CHROME_FILTER always
-- selecting one of the 4 discrete filters, blend between the two nearest
-- filters based on the scene's actual dominant hue (fed via photon-scene-
local CHROME_HUE_DRIVEN      = true
-- The filter set only spans red(0)→orange(1)→yellow(2)→green(3), a
-- one-way arc roughly 0°-120° on the hue wheel (see filter_weights'
-- GLSL comment for the Wratten sourcing). A scene whose dominant hue
local CHROME_HUE_FILTER_ARC_MAX = 120.0 / 360.0
-- Hue temporal smoothing (EMA), applied BEFORE the hue→filter-position
-- math below. Without this, ch_scene_hue is the raw per-frame ffmpeg
-- HUEAVG sample — it jitters frame to frame (observed: swings of 0.01-
-- ch_filter_pos_resolved is recomputed straight from it on every feed,
-- mix() between neighboring filter_weights entries is a perfectly
-- settling time to a step change — slow enough to erase frame-to-frame
-- ffmpeg measurement noise, fast enough that a real hard cut (which
-- ch_is_cut already resets outright, see below) or a genuine slow pan
local CHROME_HUE_EMA_ALPHA       = common.HUE_EMA_ALPHA
-- S-curve contrast amount. See ch_apply_scurve; scaled per-scene by
-- CHROME_CONTRAST_SCENE_GAIN below.
local CHROME_CONTRAST_BASE       = 0.11 / 2
local CHROME_CONTRAST_SCENE_GAIN = 0.22 / 2  -- extra contrast added in high-contrast scenes
local CHROME_CONTRAST_CLAMP_MAX  = 0.44 / 2  -- hard ceiling — never fully posterize
-- Shadow crush / highlight protection (independent fine-tuning on top of
local CHROME_SHADOW_LIFT     = -0.04     -- negative = crush, per Miller/noir research
local CHROME_HIGHLIGHT_ROLLOFF = 0.80    -- <1 = softer highlight compression
-- Split toning: cool shadows, warm bias, film white ceiling — real
-- celluloid B&W prints are never perfectly neutral gray. Shadow tint
-- fades out by lower midtones (smoothstep taper in GLSL); warmth bias
local CHROME_SHADOW_TONE_R = 0.85
local CHROME_SHADOW_TONE_B = 1.0
local CHROME_WARMTH_BIAS   = 0.025
local CHROME_FILM_WHITE    = 0.85
-- Filter-strength scene modulation: low-saturation scenes get less
-- filter pull (a filter has nothing to grab onto in a near-gray scene;
-- forcing full strength there just adds noise/artifacts, not signal).
local CHROME_SAT_FLOOR       = 0.15      -- below this scene sat, filter strength floors out
local CHROME_SAT_CEIL        = 0.55      -- at/above this scene sat, filter runs at full strength
-- Minimum strength fraction the filter is allowed to fall to even in a
-- low-saturation scene. A real physical filter doesn't vanish just
-- because the scene in front of it happens to be muted — its own
local CHROME_SAT_STRENGTH_MIN = 0.35
-- Grain integration toggle: whether chrome tells grain to go monochrome.
-- Left as a real control (not hardcoded true) in case someone wants
-- chrome's tone/filter behavior without touching grain's shader at all
local CHROME_DRIVE_MONO_GRAIN = true

-- ── TIER 1/TIER 2 split mirrors photon-grainluas gramountre ──
-- gr_char_track split, and photon-sharp.lua's equivalent strength /
-- full rationale). Chrome has THREE live-recomputed shader parameters;
-- examining each one's actual mechanical role (see ch_resolve_adaptive_
local PHOTON_CHROME_TAU_ATTACK  = 0.35  -- TIER 1 (strength/contrast) attack tau — mirrors sharp's own TIER 1 tau (same physical role, same organic-settling reasoning)
local PHOTON_CHROME_TAU_RELEASE = 0.30  -- TIER 1 (strength/contrast) release tau
local PHOTON_CHROME_CUT_TAU     = 0.6   -- TIER 1 tau on a confirmed cut — still eased, just far faster (mirrors GR_DENSITY_CUT_TAU / PHOTON_SHARP_CUT_TAU)

-- TIER 2 — character tracker constants for filter position (see
-- gr_char_track in photon-grain.lua for the reference implementation;
-- same starting constants as grain/sharp's character tiers — the
local PHOTON_CHROME_CHAR_TAU          = 9.0   -- seconds; long-EMA on the raw filter-position driving signal (hue-derived)
local PHOTON_CHROME_CHAR_DEAD_ZONE    = 0.36  -- committed value must be wrong by this much (0-3 units, i.e. 0.12 of the full arc) before a change is even considered
local PHOTON_CHROME_CHAR_DWELL_MIN    = 2.5   -- seconds the signal must stay outside the dead-zone before a new value commits
local PHOTON_CHROME_CHAR_EASE_TAU     = 3.0   -- seconds; once committed, how fast the rendered position eases to the new target
local PHOTON_CHROME_CHAR_CUT_EASE_TAU = 0.8   -- faster ease specifically right after a confirmed cut — a real edit is exactly when filter character SHOULD reassess promptly

local enabled = false
-- chrome_target_enabled: mirrors photon-grain.lua's grain_target_enabled
-- pattern — carries the user's last F9-independent choice across a file
-- change within the same gor session (episode/channel change shouldn't
local chrome_target_enabled = false

-- The latest absolute target declaration is latched even if it arrives
-- before this script's file-loaded. A later declaration replaces it.
local ch_carryover_saw_file_loaded    = false
local ch_carryover_saw_target_message = false

-- ── Live scene state written by the scene feed handler belo ──
local ch_frame_peak     = 0.50
local ch_scene_contrast = 0.25
local ch_scene_sat      = 0.00   -- -1 sentinel means "no saturation data" (HDR path)
local ch_scene_hue      = nil    -- nil means "no hue data" (HDR path, or a frame ffmpeg
                                  -- couldn't compute hue for) — unlike sat, hue has no
                                  -- meaningful numeric neutral, so it mirrors photon.lua's
                                  -- own nil-based contract for this field rather than
local ch_scene_hue_smoothed = nil -- EMA of ch_scene_hue (see CHROME_HUE_EMA_ALPHA). nil
                                  -- until the first real hue sample arrives, same contract
local ch_motion_level   = 0.20
local ch_is_hdr         = false
local ch_is_cut         = false
local ch_has_feed       = false  -- true once at least one real feed has arrived this file

-- Forward-declared: ch_maybe_apply_carryover (defined earlier in the file,
-- called from ch-file-loaded/set-target-enabled) calls these two
-- unconditionally or near-unconditionally on every rendezvous. Lua's
local ch_remove_shader
local ch_publish_hud_state

-- ── Resolved post-formula shader parameters ──
-- ch_*_resolved below are TARGETS, recomputed every feed tick directly
-- rendered" split as photon-sharp.lua's user_strength vs.
local ch_filter_strength_resolved = CHROME_FILTER_STRENGTH
local ch_contrast_resolved        = CHROME_CONTRAST_BASE

-- TIER 1 RENDERED — filter strength & contrast. Exponential attack/
local ch_filter_strength_rendered = ch_filter_strength_resolved
local ch_contrast_rendered        = ch_contrast_resolved
local ch_tier1_last_t             = 0
local ch_char_last_t              = 0  -- TIER 2's own independent dt bookkeeping — see ch_resolve_adaptive_params

-- Continuous filter position in [0,3] filter-index space (0=red..3=green).
-- Only meaningful when CHROME_HUE_DRIVEN is true; otherwise holds
-- CHROME_FILTER's fixed value so the GLSL write path (below) has a
local ch_filter_pos_resolved      = CHROME_FILTER
-- TIER 2 — character tracker for filter position. Same long-EMA +
-- dead-zone + dwell-confirmation machinery as photon-grain.lua's
-- gr_char_state / photon-sharp.lua's ps_char_state (ch_char_track,
local ch_char_state = {
    filter_pos = common.new_char_state(CHROME_FILTER),
}
-- Manual filter override (shift+c toggle, see TOGGLE section below).
-- When active, ch_resolve_adaptive_params() forces ch_filter_pos_
-- resolved to ch_manual_filter_pos instead of the scene-driven hue
local ch_manual_filter_active = false
local ch_manual_filter_pos    = CHROME_FILTER
-- ch_filter_pos_rendered: kept as a field name (read by ch_render_
-- filter_pos.rendered's output — the settled, dwell-confirmed position,
-- not a linearly-stepped chase target. Declared here (rather than only
local ch_filter_pos_rendered      = CHROME_FILTER
-- True whenever ch_scene_hue fell outside CHROME_HUE_FILTER_ARC_MAX and
-- got pinned to the green endpoint rather than genuinely resolved from
local ch_hue_arc_clamped          = false

local ch_fps                     = 24.0

local ch_shader_path = nil

-- mpv runs every script in its own isolated Lua chunk — nothing declared
-- `local` in photon-grain.lua (or photon.lua) is visible here, no matter
-- how deliberately this file's architecture mirrors grain's. This must be
local math_max, math_min = math.max, math.min
-- clamp/lerp_hue/hue_circular_dist defined in photon-common.lua — fix bugs there, not here.
local clamp = common.clamp
local lerp_hue = common.lerp_hue
local ch_hue_circular_dist = common.hue_circular_dist
local asym_smooth = common.asym_smooth
local reset_char_state = common.reset_char_state

-- TIER 2 character tracker — photon-grain.lua's gr_char_track ported
-- verbatim (long-EMA raw signal → dead-zone → dwell-confirmation →
-- commit → exponential ease to committed). Same function shape as
local function ch_char_track(state, raw, now, dt, is_cut)
    return common.char_track(state, raw, now, dt, is_cut,
        PHOTON_CHROME_CHAR_TAU, PHOTON_CHROME_CHAR_DEAD_ZONE, PHOTON_CHROME_CHAR_DWELL_MIN,
        PHOTON_CHROME_CHAR_EASE_TAU, PHOTON_CHROME_CHAR_CUT_EASE_TAU)
end

-- Resets every character-tier parameter to its own neutral default with
-- no pending dwell — called at file-loaded, same reasoning as grain's
-- gr_char_state_reset: a new file shouldn't inherit a dwell timer or
local function ch_char_state_reset()
    local defaults = {filter_pos = CHROME_FILTER}
    for key, s in pairs(ch_char_state) do
        reset_char_state(s, defaults[key])
    end
end

-- ================================================================
--  2. EMBEDDED SHADER
-- ================================================================
--  Written ONCE per session to a single fixed path (mpv gpu-next caches
--  shader text by path — a same-path rewrite never reaches the GPU).
--  Runtime values arrive as //!PARAM uniforms (see ch_push_params).
local GOR_CHROME_SOURCE = [[
// ================================================================
//  photon-chrome - OUTPUT hook: monochrome print
//  Host: photon-chrome.lua (GOR_CHROME_SOURCE) -> photon-chrome.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!PARAM CH_FILTER_POS
//!TYPE DYNAMIC float
1.0

//!PARAM CH_FILTER_STRENGTH
//!TYPE DYNAMIC float
0.75

//!PARAM CH_CONTRAST_AMOUNT
//!TYPE DYNAMIC float
0.055

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC photon-chrome v1.1 — scene-adaptive celluloid black & chrome

// Runtime values arrive as PARAM uniforms (declared above the hook
// block). Only the never-changing curve/toning constants stay baked;
#define CH_SHADOW_LIFT        -0.0400
#define CH_HIGHLIGHT_ROLLOFF  0.8500
#define CH_SHADOW_TONE_R      0.8800
#define CH_SHADOW_TONE_B      1.0000
#define CH_WARMTH_BIAS        0.0150
#define CH_FILM_WHITE         0.9800

// Rec.709 neutral luma reference (what CH_FILTER_STRENGTH=0 falls back to)
const vec3 NEUTRAL_LUMA = vec3(0.2126, 0.7152, 0.0722);

// Virtual filter channel weights. Calibrated against REAL Wratten
// transmission behavior, not a soft/energy-preserving reweighting —
// researched filter factors: yellow ~2x light loss, orange ~3-4x, red
const vec3 filter_weights[4] = vec3[4](
    vec3(0.92, 0.07, 0.02),  // red    — near-total blue/green suppression (Wratten #25-like)
    vec3(0.78, 0.28, 0.06),  // orange — strong but noticeably milder than red (default)
    vec3(0.58, 0.48, 0.14),  // yellow — mildest of the "warm" filters, most even-handed
    vec3(0.22, 0.62, 0.10)   // green  — suppresses red/skin tones, lifts foliage
);

// S-curve: y = x + amount * (x - 0.5) * (1 - |2x - 1|)
// Zero-crossings pinned at x=0 and x=1 (no clipping regardless of
// amount) — steepens midtone slope, which is what reads as "punchy"
float s_curve(float x, float amount) {
    return clamp(x + amount * (x - 0.5) * (1.0 - abs(2.0 * x - 1.0)), 0.0, 1.0);
}

vec4 hook() {
    vec4 orig = HOOKED_tex(HOOKED_pos);
    vec3 color = orig.rgb;

    // ── 1 Virtual color filter ──
    // CH_FILTER_POS is the continuous filter position (0=red..3=green),
    // defines, and non-const uniforms index const arrays fine. Integer
    float fp = clamp(CH_FILTER_POS, 0.0, 3.0);
    int fi = int(floor(fp));
    int fn = min(fi + 1, 3);
    vec3 chosen_filter = mix(filter_weights[fi], filter_weights[fn], fp - float(fi));
    vec3 w = mix(NEUTRAL_LUMA, chosen_filter, clamp(CH_FILTER_STRENGTH, 0.0, 1.0));
    // Filter weights intentionally do not sum to 1 (rows span 0.94-1.20).
    float gray = dot(color, w);
    gray = clamp(gray, 0.0, 1.0);

    // ── 2 Film-curve S-contrast ──
    float toned = s_curve(gray, clamp(CH_CONTRAST_AMOUNT, 0.0, 1.0));

    // Shadow lift/crush: negative = crush (per Miller/noir research —
    // lowering shadow detail while preserving midtone clarity).
    // Applied as an additive offset weighted toward the shadow end
    float shadow_taper = 1.0 - smoothstep(0.0, 0.35, toned);
    toned += CH_SHADOW_LIFT * shadow_taper;

    // Highlight rolloff: compress the top end toward CH_HIGHLIGHT_ROLLOFF
    // instead of letting it reach 1.0 — protects against a hard clip
    // look on blown highlights (sky, practical lights), matching the
    float highlight_taper = smoothstep(0.65, 1.0, toned);
    float rolled = CH_HIGHLIGHT_ROLLOFF + (toned - 0.65) * (1.0 - CH_HIGHLIGHT_ROLLOFF) / 0.35;
    float result = clamp(mix(toned, rolled, highlight_taper), 0.0, 1.0);

    // Split toning + film white
    float shadow_weight = 1.0 - smoothstep(0.0, 0.35, result);
    vec3 shadow_tint = vec3(CH_SHADOW_TONE_R, 1.0, CH_SHADOW_TONE_B);
    vec3 toned_result = result * mix(vec3(1.0), shadow_tint, shadow_weight * 0.3);
    toned_result = mix(toned_result, toned_result * vec3(1.0, 0.985, 0.97), CH_WARMTH_BIAS);
    
    return vec4(toned_result * CH_FILM_WHITE, orig.a);
}
]]

-- ================================================================
--  3. SHADER WRITE / PARAM PUSH
-- ================================================================
--  used to be baked per-rewrite now arrives as a //!PARAM uniform,
--  pushed via change-list glsl-shader-opts. mpv gpu-next caches parsed

-- shader_dir defined in photon-common.lua — fix bugs there, not here.
local ch_shader_written = false

local function ch_ensure_path()
    if ch_shader_path then return ch_shader_path end
    ch_shader_path = common.shader_path("photon-chrome")
    return ch_shader_path
end

-- One-time write at script load; the CHROME_* curve/toning constants
-- are baked via the same gsubs the old per-rewrite renderer ran.
local function ch_write_shader()
    if ch_shader_written then return true end
    local path = ch_ensure_path()
    if not path then return false end
    local content = GOR_CHROME_SOURCE
    content = content:gsub("#define CH_SHADOW_LIFT%s+%-?[%d.]+",
        string.format("#define CH_SHADOW_LIFT        %.4f", CHROME_SHADOW_LIFT))
    content = content:gsub("#define CH_HIGHLIGHT_ROLLOFF%s+%-?[%d.]+",
        string.format("#define CH_HIGHLIGHT_ROLLOFF  %.4f", CHROME_HIGHLIGHT_ROLLOFF))
    content = content:gsub("#define CH_SHADOW_TONE_R%s+%-?[%d.]+",
        string.format("#define CH_SHADOW_TONE_R      %.4f", CHROME_SHADOW_TONE_R))
    content = content:gsub("#define CH_SHADOW_TONE_B%s+%-?[%d.]+",
        string.format("#define CH_SHADOW_TONE_B      %.4f", CHROME_SHADOW_TONE_B))
    content = content:gsub("#define CH_WARMTH_BIAS%s+%-?[%d.]+",
        string.format("#define CH_WARMTH_BIAS        %.4f", CHROME_WARMTH_BIAS))
    content = content:gsub("#define CH_FILM_WHITE%s+%-?[%d.]+",
        string.format("#define CH_FILM_WHITE         %.4f", CHROME_FILM_WHITE))
    local f = io.open(path, "w")
    if not f then mp.msg.error("photon-chrome: failed to write shader: " .. path); return false end
    f:write(content); f:close()
    ch_shader_written = true
    mp.msg.info("photon-chrome v1.1: shader written -> " .. path)
    return true
end

-- Every non-baked value, in one payload so the three fields land in a
-- single render-options update. Deduped in photon-common: an unchanged
-- payload costs nothing.
local function ch_push_params()
    common.push_params("photon-chrome", {
        {"CH_FILTER_POS", ch_filter_pos_rendered, "f"},
        {"CH_FILTER_STRENGTH", ch_filter_strength_rendered, "f"},
        {"CH_CONTRAST_AMOUNT", ch_contrast_rendered, "f"},
    })
end

-- glsl-shaders ownership contract: deduplicates our own path before any
-- write — same pattern as photon-grain's gr_ensure_glsl_list_sane.
local function ch_ensure_glsl_list_sane(shaders)
    return common.ensure_glsl_list_sane(shaders, {ch_ensure_path()})
end

-- photon-grain's own fixed path, computed directly rather than asked
-- script-messaging, and grain's naming is fixed/stable). Used only to
local function ch_grain_paths()
    local dir = common.shader_dir()
    if not dir then return nil end
    return { dir .. "photon-grain.glsl" }
end

-- Same "compute the sibling's own fixed path formula directly" reasoning
-- chrome (decode → sharp → grain → negativ → chrome — see
local function ch_negativ_paths()
    local dir = common.shader_dir()
    if not dir then return nil end
    return {
        dir .. "photon-negativ-translucid.glsl",
        dir .. "photon-negativ-hueflip.glsl",
        dir .. "photon-negativ-mask.glsl",
    }
end

-- Shared by ch_add_shader. Given the CURRENT contents of `filtered`
-- (this script's own path already removed), returns the index chrome's
-- path should be inserted at: immediately after the LAST-occurring path
local function ch_path_in_list(p, list)
    for _, candidate in ipairs(list) do
        if p == candidate then return true end
    end
    return false
end

local function ch_predecessor_insert_index(filtered)
    local insert_at, found = 0, false
    local grain_paths = ch_grain_paths()
    if grain_paths then
        for idx, p in ipairs(filtered) do
            if p == grain_paths[1] then
                insert_at = math.max(insert_at, idx + 1); found = true
            end
        end
    end
    local negativ_paths = ch_negativ_paths()
    if negativ_paths then
        for idx, p in ipairs(filtered) do
            if ch_path_in_list(p, negativ_paths) then
                insert_at = math.max(insert_at, idx + 1); found = true
            end
        end
    end
    -- Neither found: append (grain/negativ both disabled or feed hasn't
    -- started; chrome runs on its own at the end of whatever's there).
    if not found then insert_at = #filtered + 1 end
    return insert_at
end

-- Ordering guarantee: chrome converts to B&W as the LAST pipeline step
-- (see GOR_CHROME_SOURCE header), inserting after whichever print-family
-- predecessor is furthest down the list. Idempotent — enable and the
local function ch_add_shader()
    local path = ch_ensure_path()
    if not path then return end
    local shaders = ch_ensure_glsl_list_sane(mp.get_property_native("glsl-shaders") or {})
    local filtered = {}
    for _, p in ipairs(shaders) do
        if p ~= path then table.insert(filtered, p) end
    end
    table.insert(filtered, ch_predecessor_insert_index(filtered), path)
    mp.set_property_native("glsl-shaders", filtered)
end

local function ch_shader_in_list()
    local path = ch_ensure_path()
    if not path then return true end  -- can't check, assume fine
    for _, p in ipairs(mp.get_property_native("glsl-shaders") or {}) do
        if p == path then return true end
    end
    return false
end

-- Enable ordering: file on disk first, params pushed second, path added
-- last — the newly loaded shader's first frame already has live values
-- instead of PARAM defaults.
local function ch_enable()
    ch_write_shader()
    ch_push_params()
    ch_add_shader()
end

-- Runs the actual carry-over enable/disable decision — see
-- ch_carryover_saw_*'s own declaration comment for the race this exists
local function ch_maybe_apply_carryover()
    if not (ch_carryover_saw_file_loaded and ch_carryover_saw_target_message) then return end
    if chrome_target_enabled and not enabled then
        enabled = true
        ch_enable()
        mp.msg.info("photon-chrome: enabled (carried over)")
        if CHROME_DRIVE_MONO_GRAIN then
            mp.commandv("script-message", "photon-chrome-set-mono-grain", "true")
        end
    elseif not chrome_target_enabled and enabled then
        ch_remove_shader()
        enabled = false
        mp.msg.info("photon-chrome: disabled (carried over)")
        if CHROME_DRIVE_MONO_GRAIN then
            mp.commandv("script-message", "photon-chrome-set-mono-grain", "false")
        end
    elseif enabled then
        -- Same target, already on: shader file may be gone (fresh mpv
        -- process/config reload) — re-write (no-op if present) and
        -- re-apply rather than assume the glsl-shaders property survived.
        ch_enable()
    end
    ch_publish_hud_state()
end

-- ================================================================
--  4. SELF-HEAL / HUD
-- ================================================================
--  No debounce anymore: a push is one deduped change-list add, not a
--  glsl-shaders rebuild, so there is nothing to pace.

-- 1Hz self-heal: mpv occasionally drops entries from glsl-shaders on its
-- own (external tools, other scripts writing the property, etc). If
-- chrome's path silently vanished while chrome is supposed to be on,
local ch_periodic_timer = nil

-- Publishes chrome state to photon.lua's HUD (display only — photon.lua
-- does NOT use this to drive any toggle logic, unlike its grain
-- equivalent. Chrome's on/off is independent of F9 by design).
function ch_publish_hud_state()
    -- Nearest-integer round of the RENDERED continuous filter position
    -- (ch_filter_pos_rendered, not the raw ch_filter_pos_resolved
    -- target) — not CHROME_FILTER directly: when CHROME_HUE_DRIVEN is
    local hud_filter_idx = math.floor(ch_filter_pos_rendered + 0.5)
    mp.commandv("script-message", "photon-chrome-hud-state",
        tostring(enabled), tostring(hud_filter_idx),
        string.format("%.2f", ch_filter_strength_rendered),  -- was ch_filter_strength_resolved (target) — now TIER 1 rendered, same "HUD reflects screen, not target" reasoning as hud_filter_idx above
        string.format("%.2f", ch_contrast_rendered),          -- was ch_contrast_resolved (target) — same reasoning
        tostring(ch_has_feed),
        tostring(CHROME_HUE_DRIVEN),
        ch_scene_hue and string.format("%.4f", ch_scene_hue) or "",
        string.format("%.2f", CHROME_SHADOW_LIFT),
        string.format("%.2f", CHROME_HIGHLIGHT_ROLLOFF),
        tostring(CHROME_DRIVE_MONO_GRAIN),
        -- ch_hue_arc_clamped: see its assignment in ch_resolve_adaptive_
        -- params. Appended as the 11th field rather than inserted earlier
        tostring(ch_hue_arc_clamped),
        -- ch_manual_filter_active: same append-only reasoning as
        -- ch_hue_arc_clamped immediately above — 12th field, added at
        tostring(ch_manual_filter_active))
end

local function ch_periodic_update()
    ch_publish_hud_state()
    if not enabled then return end
    if not ch_shader_in_list() then
        ch_add_shader()
    end
end

-- ================================================================
--  5. ADAPTIVE PARAMETER RESOLUTION
-- ================================================================
--  Turns raw scene stats (ch_scene_sat, ch_scene_contrast) into resolved
--  shader parameters (ch_filter_strength_resolved, ch_contrast_resolved).
--  Called unconditionally on every feed (see the scene feed handler

function ch_remove_shader()
    if not ch_shader_path then return end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local filtered, changed = {}, false
    for _, p in ipairs(shaders) do
        if p == ch_shader_path then changed = true
        else table.insert(filtered, p) end
    end
    if changed then mp.set_property_native("glsl-shaders", filtered) end
end

local function ch_resolve_adaptive_params()
    if ch_scene_sat < 0 then
        -- HDR sentinel: no per-channel/saturation signal on this path
        -- (video-out-params exposes only avg-pq-y/max-pq-y). Filter
        -- strength falls back to the user's flat preference rather than
        ch_filter_strength_resolved = CHROME_FILTER_STRENGTH
    else
        local sat_t_raw = clamp((ch_scene_sat - CHROME_SAT_FLOOR) / (CHROME_SAT_CEIL - CHROME_SAT_FLOOR), 0.0, 1.0)
        -- Remapped into [CHROME_SAT_STRENGTH_MIN, 1.0] rather than [0, 1] —
        -- see that constant's own comment for why a hard floor of 0 was
        -- wrong. sat_t_raw==0 (scene at/below CHROME_SAT_FLOOR) now yields
        local sat_t = CHROME_SAT_STRENGTH_MIN + sat_t_raw * (1.0 - CHROME_SAT_STRENGTH_MIN)
        ch_filter_strength_resolved = CHROME_FILTER_STRENGTH * sat_t
    end
    ch_contrast_resolved = clamp(
        CHROME_CONTRAST_BASE + ch_scene_contrast * CHROME_CONTRAST_SCENE_GAIN,
        0.0, CHROME_CONTRAST_CLAMP_MAX)

    -- Continuous filter position: off by default (CHROME_HUE_DRIVEN),
    -- usable hue signal (HDR path, or no real sample has arrived yet
    if ch_manual_filter_active then
        ch_filter_pos_resolved = ch_manual_filter_pos
        ch_hue_arc_clamped = false
    elseif not CHROME_HUE_DRIVEN or ch_scene_hue_smoothed == nil then
        ch_filter_pos_resolved = CHROME_FILTER
        -- flag below doesn't apply; leave it false rather than carrying
        ch_hue_arc_clamped = false
    else
        -- ch_scene_hue_smoothed is normalized 0-1 over the full 360°
        -- hue wheel, same convention as the raw field it's derived from.
        -- Clamp to the filter set's arc (red→green, 0-120°) before
        local in_arc = (ch_scene_hue_smoothed >= 0.0 and ch_scene_hue_smoothed <= CHROME_HUE_FILTER_ARC_MAX)
        local hue_in_arc
        if in_arc then
            hue_in_arc = ch_scene_hue_smoothed
        else
            local dist_to_red   = ch_hue_circular_dist(ch_scene_hue_smoothed, 0.0)
            local dist_to_green = ch_hue_circular_dist(ch_scene_hue_smoothed, CHROME_HUE_FILTER_ARC_MAX)
            hue_in_arc = (dist_to_red <= dist_to_green) and 0.0 or CHROME_HUE_FILTER_ARC_MAX
        end
        -- arc_clamped: true exactly when the scene's real hue sits
        -- outside the red→green arc entirely and the resolved position
        -- is sitting at an endpoint by construction, not because the
        ch_hue_arc_clamped = not in_arc
        ch_filter_pos_resolved = (hue_in_arc / CHROME_HUE_FILTER_ARC_MAX) * 3.0
    end

    -- ── TIER 1/TIER 2 resolve  computed HERE so both tiers conv ──
    -- every feed tick (dt~0.1s). Measuring dt across sparse writes
    -- instead would make alpha/step huge per call and collapse the ease
    -- toward a snap rather than genuine continuous convergence.
    local now = mp.get_time()

    -- TIER 1 — filter strength & contrast: exponential ease toward the
    -- _resolved targets computed above. tau depends on whether this is a
    -- confirmed cut (faster settle), mirroring GR_DENSITY_TAU/
    local tier1_dt = math_min(now - (ch_tier1_last_t > 0 and ch_tier1_last_t or now - 0.1), 1.0)
    ch_tier1_last_t = now
    local tier1_tau = ch_is_cut and PHOTON_CHROME_CUT_TAU or PHOTON_CHROME_TAU_ATTACK
    ch_filter_strength_rendered = asym_smooth(ch_filter_strength_rendered, ch_filter_strength_resolved, tier1_tau, tier1_tau, tier1_dt)
    ch_contrast_rendered        = asym_smooth(ch_contrast_rendered,        ch_contrast_resolved,        tier1_tau, tier1_tau, tier1_dt)

    -- TIER 2 — filter position: long-EMA + dead-zone + dwell-confirmation
    -- (ch_char_track, mirrors gr_char_track exactly). Replaces the
    -- previous linear max-step-per-second rate limiter. char_dt tracked
    local char_dt = math_min(now - (ch_char_last_t > 0 and ch_char_last_t or now - 0.1), 1.0)
    ch_char_last_t = now
    ch_filter_pos_rendered = ch_char_track(ch_char_state.filter_pos, ch_filter_pos_resolved, now, char_dt, ch_is_cut)
end

-- REMOVED: ch_signal_hw_copyback. This function used to tell the Swift
-- host, via gor-osd:chromehwon/chromehwoff, whether chrome wanted
-- hwdec=videotoolbox-copy for the HDR hue vf-filter photon.lua used to

-- ================================================================
--  6. FEED HANDLER
-- ================================================================
--  Fed by photon.lua's update_hdr/update_sdr/update_sdr_live — see the
--  "photon-chrome feed" comments added to each of those three functions.
--  Unconditional there (not gated on photon_sharp_active): chrome is a
local photon_scene_kv_decode = common.scene_kv_decode

mp.register_script_message("photon-scene-feed", function(payload)
    local f = photon_scene_kv_decode(payload)
    -- Captured BEFORE the unconditional assignment two lines below
    -- overwrites it: true only on the very first real feed this file/
    -- run (mirrors ch_scene_hue_smoothed's own "== nil" first-sample
    local is_first_feed = not ch_has_feed
    ch_frame_peak     = tonumber(f.peak)     or ch_frame_peak
    ch_scene_contrast = tonumber(f.contrast) or ch_scene_contrast
    ch_scene_sat      = tonumber(f.sat)      or ch_scene_sat
    ch_motion_level   = tonumber(f.motion)   or ch_motion_level
    ch_is_hdr         = (f.is_hdr == "true")
    ch_is_cut         = (f.is_cut == "true")
    ch_has_feed       = true
    -- f.hue is nil when photon_scene_hue is nil upstream (HDR path, or a
    -- frame ffmpeg didn't compute HUEAVG for) — tonumber(nil) is nil, so
    -- this naturally falls through to nil rather than fabricating 0.
    ch_scene_hue      = tonumber(f.hue)

    -- Smooth hue into ch_scene_hue_smoothed — see CHROME_HUE_EMA_ALPHA
    -- peak/contrast, and feeding its per-frame jitter straight into
    if ch_scene_hue == nil then
        -- No usable sample this feed (HDR path, or ffmpeg couldn't
        -- compute HUEAVG this frame) — leave whatever smoothed value is
        -- already held untouched rather than collapsing it to nil.
    else
        -- Snaps on cut/first-sample instead of easing across it, lerps
        -- otherwise — see common.smooth_hue.
        ch_scene_hue_smoothed = common.smooth_hue(ch_scene_hue_smoothed, ch_scene_hue,
            CHROME_HUE_EMA_ALPHA, ch_is_cut or ch_scene_hue_smoothed == nil)
    end

    -- Host hwdec signal used to be evaluated here, unconditionally,
    -- before the `enabled` early-return below — removed along with
    -- ch_signal_hw_copyback itself (see that removal's comment above

    if not enabled then return end  -- armed but not on; don't burn cycles writing shaders nobody's using

    ch_resolve_adaptive_params()

    if is_first_feed then
        -- First real feed this file/run: ch_filter_strength_resolved/
        -- ch_contrast_resolved just resolved above are the first REAL
        -- scene-derived values chrome has ever seen this file/run.
        ch_filter_strength_rendered = ch_filter_strength_resolved
        ch_contrast_rendered        = ch_contrast_resolved
    end

    -- Params land every feed tick via one deduped change-list add — no
    -- file I/O, no rebuild. The push cadence is the feed's own (a scene
    -- cut fires the same tick as is_cut), so there is no separate
    ch_push_params()
end)

-- ================================================================
--  7. TOGGLE
-- ================================================================
--  input.conf: c script-message-to photon_chrome photon-chrome-toggle
--  ★ This is the ONLY handler that sets `enabled`. Deliberately NOT
--  wired into photon.lua's F9 handler (see photon.lua's F9 block —
mp.register_script_message("photon-chrome-toggle", function()
    enabled = not enabled
    chrome_target_enabled = enabled
    if enabled then
        ch_resolve_adaptive_params()
        mp.set_property("user-data/gor/chrome", "1")
        ch_enable()
        mp.osd_message("photon-chrome v1.1: ON" .. (ch_has_feed and "" or "  (waiting for photon)"))
        mp.msg.info("photon-chrome: enabled")
        if CHROME_DRIVE_MONO_GRAIN then
            mp.commandv("script-message", "photon-chrome-set-mono-grain", "true")
        end
    else
        mp.set_property("user-data/gor/chrome", "0")
        ch_remove_shader()
        mp.osd_message("photon-chrome v1.1: OFF")
        mp.msg.info("photon-chrome: disabled")
        if CHROME_DRIVE_MONO_GRAIN then
            mp.commandv("script-message", "photon-chrome-set-mono-grain", "false")
        end
    end
    ch_publish_hud_state()
end)

-- input.conf: shift+c script-message-to photon_chrome photon-chrome-filter-toggle
-- Manual filter cycle: red -> orange -> yellow -> green -> off (back to
-- CHROME_HUE_DRIVEN's scene-adaptive selection) -> red -> ... A separate
mp.register_script_message("photon-chrome-filter-toggle", function()
    if not enabled then return end

    if not ch_manual_filter_active then
        ch_manual_filter_active = true
        ch_manual_filter_pos = 0  -- red
    elseif ch_manual_filter_pos < 3 then
        ch_manual_filter_pos = ch_manual_filter_pos + 1
    else
        ch_manual_filter_active = false  -- was green (3), next press releases back to scene-adaptive
    end

    -- Instant snap, not an eased chase toward the new target — a
    -- deliberate keypress selecting a specific filter should show that
    -- filter immediately, the same way negativ's mode keys snap rather
    local snap_target = ch_manual_filter_active and ch_manual_filter_pos or CHROME_FILTER
    ch_char_state.filter_pos.signal     = snap_target
    ch_char_state.filter_pos.committed  = snap_target
    ch_char_state.filter_pos.rendered   = snap_target
    ch_char_state.filter_pos.dwell_start = nil
    ch_filter_pos_rendered = snap_target

    ch_resolve_adaptive_params()
    ch_enable()

    local filter_names = {"red", "orange", "yellow", "green"}
    if ch_manual_filter_active then
        mp.osd_message("photon-chrome filter: " .. filter_names[ch_manual_filter_pos + 1] .. " (manual, until pause)")
    else
        mp.osd_message("photon-chrome filter: scene-adaptive" .. (CHROME_HUE_DRIVEN and "" or " (CHROME_HUE_DRIVEN is off, holding CHROME_FILTER)"))
    end
    mp.msg.info("photon-chrome: manual filter toggle -> " ..
        (ch_manual_filter_active and filter_names[ch_manual_filter_pos + 1] or "scene-adaptive"))

    ch_publish_hud_state()
end)

-- Clears the manual filter override on pause — per explicit user
-- mean: the PAUSE transition itself, not unpause, and not a full
-- pause-then-unpause round trip). Fires only when pause transitions to
mp.observe_property("pause", "bool", function(_, val)
    if val and ch_manual_filter_active then
        ch_manual_filter_active = false
        if enabled then
            ch_resolve_adaptive_params()
            ch_enable()
            ch_publish_hud_state()
        end
    end
end)

-- ================================================================
--  8. FILE-LOADED / SESSION STATE
-- ================================================================
mp.register_event("file-loaded", function()
    -- photon.lua may have declared the target before this handler runs.
    -- Keep that latest absolute declaration across the file load.
    ch_carryover_saw_file_loaded    = true

    ch_has_feed       = false

    -- Reset raw scene variables to neutral defaults — same fix applied
    -- here, correctly from the start). Without this, a fresh load would
    ch_frame_peak         = 0.50
    ch_scene_contrast     = 0.35
    ch_scene_sat          = 0.10
    ch_motion_level       = 0.20
    ch_scene_hue          = nil
    ch_scene_hue_smoothed = nil

    -- TIER 2 (filter position) character state MUST be reset BEFORE
    -- calling ch_resolve_adaptive_params() below — that call now also
    -- advances ch_char_state.filter_pos via ch_char_track (see TIER 1/
    ch_char_state_reset()
    -- Manual filter override does NOT survive a file load — per
    -- explicit user decision, a new file is a fresh evaluation, same
    -- "clean start, nothing to organically hold onto" reasoning as
    ch_manual_filter_active = false
    ch_char_last_t = 0
    ch_tier1_last_t = 0

    ch_resolve_adaptive_params()
    -- ch_resolve_adaptive_params() above just reset the TARGETS
    -- (ch_filter_pos_resolved to CHROME_FILTER via its own nil-hue
    -- fallback; ch_filter_strength_resolved/ch_contrast_resolved from
    ch_filter_pos_rendered      = ch_filter_pos_resolved
    ch_filter_strength_rendered = ch_filter_strength_resolved
    ch_contrast_rendered        = ch_contrast_resolved

    ch_maybe_apply_carryover()

    -- ch_is_hdr may still reflect the previous file here (not reset
    -- above — same as photon.lua's own detect_format hasn't run for the
    -- new file yet at this point in file-loaded). This used to also
    ch_publish_hud_state()
end)

mp.register_script_message("photon-chrome-set-target-enabled", function(val)
    chrome_target_enabled = (val == "true")
    ch_carryover_saw_target_message = true
    ch_maybe_apply_carryover()
end)

-- ================================================================
--  9. TIMER
-- ================================================================
--  1Hz self-heal + HUD publish, matching photon-grain.lua's cadence.
ch_periodic_timer = mp.add_periodic_timer(1.0, ch_periodic_update)

-- Startup: delete legacy A/B slot files so the pre-PARAM scheme can
-- never resurface, then write the single PARAM-based file once. Nothing
local function ch_delete_legacy_files()
    local dir = common.shader_dir()
    if not dir then return end
    os.remove(dir .. "photon-chrome-shader-a.glsl")
    os.remove(dir .. "photon-chrome-shader-b.glsl")
end
ch_delete_legacy_files()
ch_write_shader()
