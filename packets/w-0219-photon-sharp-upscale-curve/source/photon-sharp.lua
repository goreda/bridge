-- ================================================================
--  photon-sharp.lua - MAINPRESUB adaptive sharpening
--  Owns: sharp shader, temporal modes and messages
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
        mp.msg.error("photon-sharp: photon-scriptdir invalid or photon-common.lua missing - checked: " .. script_dir .. "/photon-common.lua")
    end
end
local common_ok, common = pcall(require, "photon-common")
if not common_ok then
    mp.msg.error("photon-sharp: could not load photon-common - " .. tostring(common) .. ". This script is disabled.")
    return
end
local PHOTON_REQUIRED_COMMON_VERSION = 2
if not common.check_version("photon-sharp", PHOTON_REQUIRED_COMMON_VERSION) then
    return
end


-- ================================================================
--  1. SHARED HELPERS
-- ================================================================
local math_max, math_min, math_abs = math.max, math.min, math.abs
-- clamp defined in photon-common.lua — fix bugs there, not here.
local clamp = common.clamp

-- ================================================================
--  2. CONTROL PANEL
-- ================================================================
-- FACTOR: the one user-facing strength knob. Uncapped — raise it as
-- high as wanted. Applied as a single eased multiplier on the final
-- shader strength (see TIER 1B below), never added or double-scaled.
local PHOTON_SHARP_FACTOR            =  1.50  -- ★ master strength, uncapped
local PHOTON_SHARP_HALO_GUARD        =  0.50  -- ★ 0=off(sharpest), 1=full(film-friendly)
local PHOTON_SHARP_TEXTURE_BIAS      =  0.50  -- ★ 0=fine detail, 1=coarse structure
local PHOTON_SHARP_ALGO_DEFAULT      =  0     -- ★ 0=Hybrid,1=Perceptual,2=Structural,3=Conservative,4=Aggressive
local PHOTON_SHARP_TEMPORAL_ALPHA    =  0.65 * (1.0 - 0.12 * PHOTON_SHARP_HALO_GUARD) -- temporal blend factor, tracks HALO_GUARD

-- DaVinci-style 3-band strength. 1.0 = full weight, multiplies on top
local PHOTON_SHARP_FINE_STRENGTH     =  1.00  -- ★ fine texture (skin, fabric, leaves)
local PHOTON_SHARP_MEDIUM_STRENGTH   =  1.00  -- ★ medium detail (facial features)
local PHOTON_SHARP_COARSE_STRENGTH   =  1.00  -- ★ coarse structure (edges, silhouettes)

-- 0=EMA scene-level smoothing (default, all backends). 1=per-pixel
-- compute-buffer temporal blend (Vulkan/D3D11/GL4.3+ only).
local PHOTON_SHARP_TEMPORAL_MODE     =  0     -- ★ 0=EMA, 1=compute-buffer

-- Per-pixel animation-vs-live-action heuristic shifting coring/noise
-- gate. 0 disables (resolution-profile-only behavior).
local PHOTON_SHARP_CONTENT_ADAPT     =  1     -- ★ 1=on, 0=off

-- Encode block-artifact defense. photon.lua's BK probe measures the
-- file's 8px grid-step signature (harsh encodes read as clean masters
-- to the temporal noise sensor) and feeds a 0-1 block level; this knob
-- scales how strongly sharp responds (strength damping + coring lift).
local PHOTON_SHARP_BLOCK_GUARD       =  0.85  -- ★ 0=off, 1=max response
local PHOTON_SHARP_RING_GUARD        =  0.85  -- ★ 0=off, 1=max response (RG ring level)

-- Scene-derived strength range (peak=1 bright → MIN, peak=0 dark →
-- MAX). Kept narrow (~3.75x) so mid-scene peak fluctuations don't read
local PHOTON_SHARP_BASE_AMOUNT_MIN   =  2.50  -- bright scene floor
local PHOTON_SHARP_BASE_AMOUNT_MAX   =  4.00  -- dark scene ceiling
local PHOTON_SHARP_AMOUNT_CLAMP_MIN  =  0.025 -- absolute floor after FACTOR
local PHOTON_SHARP_AMOUNT_CLAMP_MAX  =  128.0 -- absolute ceiling after FACTOR (uncapped in practice)
local PHOTON_SHARP_FACTOR_STEP       =  0.10  -- per-keypress FACTOR increment
local PHOTON_SHARP_FACTOR_MIN        =  0.05  -- FACTOR floor
local PHOTON_SHARP_FACTOR_MAX        =  128.0 -- FACTOR ceiling (uncapped in practice)

local photon_sharp_current_algo      = PHOTON_SHARP_ALGO_DEFAULT

-- Must be declared before every function that reads it — Lua resolves
-- erroring, which silently no-ops any `if not photon_sharp_active`
local photon_sharp_active            = false

-- ================================================================
--  3. RUNTIME STATE
-- ================================================================

-- TIER 1 — STRENGTH: photon_sharp_user_strength (target, scene-derived)
-- eased into photon_sharp_strength_rendered (shader #define) so scene
-- brightness changes settle organically instead of snapping per-frame.
local photon_sharp_user_strength     = 1.05
local photon_sharp_strength_rendered = photon_sharp_user_strength
local photon_sharp_strength_last_t   = 0

local photon_sharp_fine_coarse        = 0.50
local photon_sharp_fine_coarse_manual = false
local photon_sharp_noise_manual       = false
local PHOTON_SHARP_MANUAL_OVERRIDE_TTL = 20.0
local photon_sharp_fine_coarse_manual_t = 0
local photon_sharp_noise_manual_t       = 0

local photon_sharp_smooth_coarse    = 0.50  -- TIER 2 rendered fine/coarse mix
local photon_sharp_last_uniform_t   = 0

-- Per-scene mini-calibration mirror (producer side lives in photon.lua,
local photon_sharp_scene_baseline_pbs      = nil
local photon_sharp_scene_baseline_contrast = nil
local photon_sharp_scene_baseline_t        = 0
local PHOTON_SHARP_SCENE_BASELINE_WINDOW   = 3.0
local PHOTON_SHARP_SCENE_BASELINE_TTL      = 8.0

-- TIER 1 tau — asymmetric, mirrors dark/light eye adaptation: darkening
-- (attack) is slow, brightening (release) is fast. A confirmed cut
-- settles fastest of all three (real scene change, not noise).
local photon_sharp_dyn_tau_release  = nil
local PHOTON_SHARP_TAU_ATTACK       = 9.00  * 3  -- scene darkening
local PHOTON_SHARP_TAU_RELEASE      = 0.03  * 3  -- scene brightening
local PHOTON_SHARP_CUT_TAU          = 0.024 * 3  -- confirmed cut

-- TIER 1B — FACTOR: separate symmetric tau from TIER 1's asymmetric
-- one. FACTOR is a deliberate user action (keypress/slider), not an
-- automatic scene response, so there's no perceptual reason to pace it
local PHOTON_SHARP_FACTOR_TAU = 0.45
local photon_sharp_factor_rendered = PHOTON_SHARP_FACTOR
local photon_sharp_factor_last_t   = 0
local ps_adaptive_mode = mp.get_opt("photon-adaptive-program") ~= "false"
local ps_effective_h
local ps_source_h, ps_output_h, ps_multiplier = nil, nil, 1.0
local function ps_refresh_adaptive()
    local source_property, sw, ow
    ps_source_h, ps_output_h, source_property, ps_effective_h, sw, ow = common.adaptive_rasters()
    ps_multiplier = 1.0
    if ps_adaptive_mode and ps_source_h and ps_output_h and ps_source_h > 0 and ps_output_h > 0 then
        -- 118a: m = output height / source height (owner definition). With the
        -- 116a common picture area (osd-dimensions minus margins) this equals
        -- the width ratio for aspect-preserved fits and differs only for
        -- anamorphic (SAR != 1), where height is the owner's explicit basis.
        local r = ps_output_h / ps_source_h
        -- 118g: bidirectional response, "attenuation only" removed (owner:
        -- upscale raises the amount, downscale lowers it; 480p at ~1280 out
        -- must reach >= 1.5x the 4k at ~1100 amount). sqrt is the delivered
        -- r^-0.5 attenuation with its sign flipped; m = 1 -> 1.0 keeps the
        -- delivered look at native size. Rails [0.5, 2.0] bound extreme
        -- windows; no owner-specified rails exist. Applied to AMOUNT only
        -- (coordinator review): FACTOR stays geometry-free, and the 116-era
        -- inverse-r band damping is removed because it cancelled the raise.
        ps_multiplier = math.max(0.5, math.min(2.0, r ^ 0.5))
    end
end

-- TIER 2 — character tracker: long-EMA + dead-zone + dwell-confirm,
-- same machinery as photon-grain's character tier. Fine/coarse is a
-- structural choice that should stay fixed within a shot, not drift
local PHOTON_SHARP_CHAR_TAU          = 9.0   -- long-EMA on raw driving signal
local PHOTON_SHARP_CHAR_DEAD_ZONE    = 0.12  -- min drift before a change is considered
local PHOTON_SHARP_CHAR_DWELL_MIN    = 2.5   -- seconds outside dead-zone before commit
local PHOTON_SHARP_CHAR_EASE_TAU     = 3.0   -- ease to committed value
local PHOTON_SHARP_CHAR_CUT_EASE_TAU = 0.8   -- faster ease right after a confirmed cut

-- ── mirror of core scene signal written by the photon-scene ──
-- lives in core because more than one consumer uses it; sharp receives
-- already-smoothed values and does NOT recompute smooth_peak/contrast/
-- noise on its own). Named identically to core's photon_scene_* so the
local PHOTON_SHARP_MOTION_TAU = 0.35
local photon_scene_smooth_motion  = 0.20
local photon_sharp_motion_last_t  = 0

local photon_scene_peak            = 0.50
local photon_scene_contrast        = 0.35
local photon_scene_noise           = 0.10
-- Encode block-artifact level from photon.lua's BK probe (0-1, per file).
local photon_scene_block           = 0.0
local photon_scene_ring            = 0.0
local photon_scene_rlevel          = 0.0
local photon_scene_sat             = 0.10
local photon_scene_motion          = 0.20
local photon_scene_is_cut          = false
local photon_scene_has_feed        = false
local photon_scene_smooth_peak     = 0.50
local photon_scene_smooth_contrast = 0.35
local photon_scene_smooth_noise    = 0.10

-- Fine/coarse mix from scene contrast. High contrast → fine (sharp edges),
-- low contrast → coarse (DaVinci "Large Texture" equivalent). 0=fine, 1=coarse.
local function photon_sharp_fine_coarse_from_contrast(scene_contrast)
    return clamp(1.0 - scene_contrast, 0.0, 1.0)
end

-- Manual override with TTL: user script-message overrides auto for
-- PHOTON_SHARP_MANUAL_OVERRIDE_TTL seconds, then silently reverts.
local function photon_sharp_auto_set_fine_coarse(scene_contrast)
    if photon_sharp_fine_coarse_manual then
        if mp.get_time() - photon_sharp_fine_coarse_manual_t < PHOTON_SHARP_MANUAL_OVERRIDE_TTL then
            return
        end
        photon_sharp_fine_coarse_manual = false
    end
    photon_sharp_fine_coarse = photon_sharp_fine_coarse_from_contrast(scene_contrast)
end

local function photon_sharp_auto_set_noise(noise_value)
    if photon_sharp_noise_manual then
        if mp.get_time() - photon_sharp_noise_manual_t < PHOTON_SHARP_MANUAL_OVERRIDE_TTL then
            return
        end
        photon_sharp_noise_manual = false
    end
    photon_scene_noise = noise_value
end

--  PHOTON-SHARP EMBEDDED SHADER
--  Full GLSL shader source stored as a Lua long-string, written ONCE
--  per session to <config-dir>/shader/photon-sharp.glsl (and

local PHOTON_SHARP_SHADER_SOURCE = [[
// ================================================================
//  photon-sharp - MAINPRESUB hook: adaptive sharpening
//  Host: photon-sharp.lua (PHOTON_SHARP_SHADER_SOURCE) -> photon-sharp.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!PARAM PHOTON_SHARP_FRAME_PEAK
//!TYPE DYNAMIC float
-1.0

//!PARAM PHOTON_SHARP_SCENE_CONTRAST
//!TYPE DYNAMIC float
0.35

//!PARAM PHOTON_SHARP_NOISE_LEVEL
//!TYPE DYNAMIC float
0.10

//!PARAM PHOTON_SHARP_MOTION_LEVEL
//!TYPE DYNAMIC float
0.20

//!PARAM PHOTON_SHARP_AMOUNT
//!TYPE DYNAMIC float
1.05

//!PARAM PHOTON_SHARP_FINE_COARSE
//!TYPE DYNAMIC float
0.50

//!PARAM PHOTON_SHARP_FACTOR_RENDERED
//!TYPE DYNAMIC float
3.05

//!PARAM PHOTON_SHARP_TEMPORAL_ALPHA
//!TYPE DYNAMIC float
0.611

//!PARAM PHOTON_SHARP_HALO_GUARD
//!TYPE DYNAMIC float
0.50

//!PARAM PHOTON_SHARP_TEXTURE_BIAS
//!TYPE DYNAMIC float
0.50

//!PARAM PHOTON_SHARP_FINE_STRENGTH
//!TYPE DYNAMIC float
1.00

//!PARAM PHOTON_SHARP_MEDIUM_STRENGTH
//!TYPE DYNAMIC float
1.00

//!PARAM PHOTON_SHARP_COARSE_STRENGTH
//!TYPE DYNAMIC float
1.00

//!PARAM PHOTON_SHARP_ALGO
//!TYPE DEFINE
0

//!PARAM PHOTON_SHARP_BLOCK_LEVEL
//!TYPE DYNAMIC float
0.0

//!PARAM PHOTON_SHARP_RING_LEVEL
//!TYPE DYNAMIC float
0.0

//!PARAM PHOTON_SHARP_CONTENT_ADAPT
//!TYPE DEFINE
1

//!PARAM PHOTON_SHARP_MEDIUM_BAND_ACTIVE
//!TYPE DEFINE
1

//!PARAM PHOTON_SHARP_COARSE_BAND_ACTIVE
//!TYPE DEFINE
1

//!HOOK MAINPRESUB
//!BIND HOOKED
//!DESC photon-sharp v8.1 — Perceptual Multi-Mode Adaptive Sharpener (Vulkan safe)

// Runtime values arrive as PARAM uniforms (declared above the hook
// block). Only the never-changing sentinels/clamps stay baked; the Lua
// constants win over these literals at the one-time write
#define PHOTON_SHARP_AMOUNT_FLOOR     0.0
#define PHOTON_SHARP_AMOUNT_CEIL      20.00
#define PHOTON_SHARP_FEED_MISSING    -0.5   // no-feed sentinel

// Integer band flags drive #if (preprocessor needs integer literals);
// Phase 2 (COMPUTE+STORAGE) is a separate fixed file, because mpv's

const vec3  LUMA_COEFF   = vec3(0.2126, 0.7152, 0.0722);
const float EPS          = 1.0e-5;
const float RCAS_LIMIT   = 0.1875; // 0.25 - 1/16, AMD's original value

float get_luma(vec3 c) { return dot(c, LUMA_COEFF); }

float read_luma(ivec2 p) {
    return get_luma(texelFetch(HOOKED_raw, p, 0).rgb);
}

int res_profile() {
    float h = HOOKED_size.y;
    if (h < 720.0)  return 0;
    if (h <= 1088.0) return 1;
    return 2;
}

// ── Parameters ──
struct Params {
    float peak;
    float contrast;
    float noise;
    float motion;
    float amount;
    float fine_mix;   // 0=fine, 1=coarse
    float alpha;
    float block;      // encode block-artifact level (BK probe, knob-applied)
    float ring;       // edge-ringing level (RG probe, knob-applied)
    bool  has_feed;
};

Params unpack_params() {
    Params p;
    p.amount    = clamp(float(PHOTON_SHARP_AMOUNT), PHOTON_SHARP_AMOUNT_FLOOR, PHOTON_SHARP_AMOUNT_CEIL);
    p.fine_mix  = clamp(float(PHOTON_SHARP_FINE_COARSE) + float(PHOTON_SHARP_TEXTURE_BIAS), 0.0, 1.0);
    p.motion    = clamp(float(PHOTON_SHARP_MOTION_LEVEL), 0.0, 1.0);
    p.alpha     = clamp(float(PHOTON_SHARP_TEMPORAL_ALPHA), 0.0, 1.0);

    float fed_peak     = float(PHOTON_SHARP_FRAME_PEAK);
    float fed_contrast = float(PHOTON_SHARP_SCENE_CONTRAST);
    float fed_noise    = float(PHOTON_SHARP_NOISE_LEVEL);

    p.has_feed = (fed_peak > float(PHOTON_SHARP_FEED_MISSING));
    p.peak     = p.has_feed ? clamp(fed_peak,     0.0, 1.0) : 0.5;
    p.contrast = p.has_feed ? clamp(fed_contrast, 0.0, 1.0) : 0.35;
    p.noise    = p.has_feed ? clamp(fed_noise,    0.0, 1.0) : 0.10;
    p.block    = clamp(float(PHOTON_SHARP_BLOCK_LEVEL), 0.0, 1.0);
    p.ring     = clamp(float(PHOTON_SHARP_RING_LEVEL), 0.0, 1.0);
    return p;
}

struct Nbhd3 {
    float c, n, s, e, w, nw, ne, sw, se;
    float lo, hi;
    float rcas_lo, rcas_hi; // 4x stabil RCAS min/max
};

Nbhd3 sample_nbhd3(ivec2 sp) {
    Nbhd3 v;
    v.c  = read_luma(sp);
    v.n  = read_luma(sp + ivec2( 0,-1));
    v.s  = read_luma(sp + ivec2( 0, 1));
    v.e  = read_luma(sp + ivec2( 1, 0));
    v.w  = read_luma(sp + ivec2(-1, 0));
    v.nw = read_luma(sp + ivec2(-1,-1));
    v.ne = read_luma(sp + ivec2( 1,-1));
    v.sw = read_luma(sp + ivec2(-1, 1));
    v.se = read_luma(sp + ivec2( 1, 1));

    // Standard 3x3 min/max
    v.lo = min(v.c, min(min(v.n, v.s), min(v.e, v.w)));
    v.lo = min(v.lo, min(min(v.nw, v.ne), min(v.sw, v.se)));
    v.hi = max(v.c, max(max(v.n, v.s), max(v.e, v.w)));
    v.hi = max(v.hi, max(max(v.nw, v.ne), max(v.sw, v.se)));

    float cross_sum = v.n + v.e + v.w + v.s;
    v.rcas_lo = 4.0 * v.lo - cross_sum + v.c;
    v.rcas_hi = 4.0 * v.hi - cross_sum + v.c;

    return v;
}

float blur_fine(Nbhd3 v) {
    return v.c * 0.40
         + (v.n + v.s + v.e + v.w)       * 0.10
         + (v.nw + v.ne + v.sw + v.se)   * 0.025;
}

// ── Medium band blur 13-tap ──
const float MEDIUM_NORM = 1.020408; // 1/0.98

float blur_medium(ivec2 sp, Nbhd3 v) {
    float h2 = read_luma(sp + ivec2( 0,-2));
    float v2 = read_luma(sp + ivec2( 0, 2));
    float l2 = read_luma(sp + ivec2(-2, 0));
    float r2 = read_luma(sp + ivec2( 2, 0));

    float sum = v.c * 0.18
              + (v.n + v.s + v.w + v.e)         * 0.10
              + (h2  + v2  + l2  + r2)           * 0.07
              + (v.nw + v.ne + v.sw + v.se)      * 0.03;
    return sum * MEDIUM_NORM;
}

const float COARSE_NORM = 1.111111;

float blur_coarse(ivec2 sp, float center) {
    int rp  = res_profile();
    int off = (rp == 0) ? 2 : (rp == 1) ? 3 : 4;

    float d1 = read_luma(sp + ivec2(-off,-off));
    float d2 = read_luma(sp + ivec2( off,-off));
    float d3 = read_luma(sp + ivec2(-off, off));
    float d4 = read_luma(sp + ivec2( off, off));

    float sum = center * 0.50 + (d1 + d2 + d3 + d4) * 0.10;
    return sum * COARSE_NORM;
}

vec2 edge_struct(Nbhd3 v) {
    float gx = (v.ne - v.nw) + 2.0*(v.e - v.w) + (v.se - v.sw);
    float gy = (v.sw - v.nw) + 2.0*(v.s - v.n) + (v.se - v.ne);
    float S  = sqrt(gx*gx + gy*gy + EPS);
    float C  = (abs(gx) + abs(gy)) > EPS
               ? abs(abs(gx) - abs(gy)) / (abs(gx) + abs(gy))
               : 0.0;
    return vec2(S, C);
}

// Learned edge-confidence kernel (3x3 fixed weights, ArtCNN/FSRCNNX pattern).
// edge signal at zero extra fetch cost (reuses already-sampled 3x3 Nbhd3).
float learned_edge_confidence(Nbhd3 v) {
    const float k_c  =  1.60;
    const float k_4  = -0.35; // n,s,e,w
    const float k_d  = -0.22; // nw,ne,sw,se (stronger diagonals vs Sobel)
    float resp = v.c*k_c + (v.n+v.s+v.e+v.w)*k_4 + (v.nw+v.ne+v.sw+v.se)*k_d;
    return clamp(abs(resp) * 2.2, 0.0, 1.0);
}

// Content-type adaptation (zero extra fetches). Derives an "animation
// score" from existing Nbhd3/edge_struct/rcas_noise data:
//   low variance + low noise + high coherence → animation (→1)
float content_class(Nbhd3 v, float noise_det, float edge_coherence) {
    float local_range = v.hi - v.lo;
    float flatness     = 1.0 - smoothstep(0.0, 0.12, local_range);
    float clean_noise  = 1.0 - noise_det;
    float anim_score = flatness * 0.40 + clean_noise * 0.35 + edge_coherence * 0.25;
    return clamp(anim_score, 0.0, 1.0);
}


void estimate_fallback(Nbhd3 v, out float peak_est,
                       out float contrast_est, out float noise_est) {
    peak_est     = clamp(v.c, 0.0, 1.0);
    float local_range = v.hi - v.lo;
    contrast_est = clamp(local_range * 1.35, 0.0, 1.0);

    float mean3  = (v.c + v.n + v.s + v.e + v.w) * 0.2;
    float dev    = (abs(v.c-mean3) + abs(v.n-mean3) + abs(v.s-mean3)
                  + abs(v.e-mean3) + abs(v.w-mean3)) * 0.2;
    float noisiness = clamp(dev * 9.0, 0.0, 1.0);
    noise_est = noisiness * (1.0 - smoothstep(0.0, 0.25, local_range));
}

float soft_lim(float v, float s) {
    float vs  = v / s;
    float vs2 = vs * vs;
    return clamp(abs(vs) * (27.0 + vs2) / (27.0 + 9.0*vs2), 0.0, 1.0) * s * sign(v);
}

float rcas_noise(Nbhd3 v) {
    float local_range = v.hi - v.lo;
    if (local_range < EPS) return 1.0;
    float hp = abs(v.n + v.s + v.e + v.w - 4.0*v.c);
    float norm_hp = hp / (local_range + EPS);
    return smoothstep(0.15, 0.35, norm_hp);
}

// AMD FSR1/2/3 full form: with 4x stable min/max
float rcas_weight(Nbhd3 v, float sharp_lin) {
    float mn4 = v.rcas_lo;
    float mx4 = v.rcas_hi;

    float cross_sum = v.n + v.e + v.w + v.s;
    // From the lower clip: w = -mn / (sum_cross)
    float w_lo = (mn4 < 0.0) ? (-mn4 / (cross_sum + EPS)) : 0.0;
    float w_hi = (mx4 > 1.0) ? ((1.0 - mx4) / (cross_sum - 4.0 * mx4 + EPS)) : 0.0;
    float w    = max(w_lo, w_hi);

    w = min(w, RCAS_LIMIT);
    w = min(w, sharp_lin);

    return w;
}

// Shared clip-aware push: strength-scaled overshoot allowance.
// Used by algo_hybrid, algo_structural, algo_aggressive.
float clip_aware_push(float push, float orig_l, Nbhd3 v, float strength) {
    float overshoot_allow = 1.0 + 1.2 * log2(1.0 + strength);
    float headroom_hi = max(v.hi - orig_l, EPS) * overshoot_allow;
    float headroom_lo = max(orig_l - v.lo, EPS) * overshoot_allow;
    float room = (push >= 0.0) ? headroom_hi : headroom_lo;
    return push * (room / (room + abs(push) * 0.15 + EPS));
}

// ALGORITHM 0: Hybrid RCAS + 3-band USM (default)
float algo_hybrid(ivec2 sp, float orig_l, Nbhd3 v, Params p,
                  float strength, float gf) {
    // 3-band highpass.
    // PERF: medium/coarse bant fetch'leri (4+4 read_luma), ilgili
    float fine_b   = blur_fine(v);
    float hp_fine   = orig_l - fine_b;

    float hp_medium = 0.0;
#if PHOTON_SHARP_MEDIUM_BAND_ACTIVE
    float medium_b = blur_medium(sp, v);
    hp_medium = orig_l - medium_b;
#endif

    float hp_coarse = 0.0;
#if PHOTON_SHARP_COARSE_BAND_ACTIVE
    float coarse_b = blur_coarse(sp, v.c);
    hp_coarse = orig_l - coarse_b;
#endif

    float w_fine   = (1.0 - p.fine_mix) * (1.0 - 0.5*p.fine_mix);
    float w_coarse = p.fine_mix * (1.0 - 0.5*(1.0-p.fine_mix));
    float w_medium = max(0.0, 1.0 - w_fine - w_coarse);

    // DaVinci 3-band independent strength (multiplies on top of auto mix)
    float highpass = hp_fine   * w_fine   * float(PHOTON_SHARP_FINE_STRENGTH)
                    + hp_medium * w_medium * float(PHOTON_SHARP_MEDIUM_STRENGTH)
                    + hp_coarse * w_coarse * float(PHOTON_SHARP_COARSE_STRENGTH);

    // Resolution-based coring threshold
    int rp = res_profile();
    float coring_base = (rp == 0) ? 0.010 : (rp == 1) ? 0.007 : 0.004;
    float local_range = v.hi - v.lo;
    float coring_floor = mix(coring_base, coring_base*2.5, p.noise);
    // Blocky-file lift: grid steps in a dead-flat file are small enough
    // to pass the normal floor; raise it before they read as detail.
    coring_floor *= (1.0 + 1.5 * p.block);

    float noise_det = rcas_noise(v);

    // Content adaptation: lower coring for animation, raise for live-action
    vec2 ec_for_content = edge_struct(v);
    float anim_score = 0.5;
    if (PHOTON_SHARP_CONTENT_ADAPT == 1) {
        anim_score = content_class(v, noise_det, ec_for_content.y);
        coring_floor *= mix(1.15, 0.70, anim_score);
    }

    float coring_w = smoothstep(coring_floor, coring_floor*3.5, local_range);
    highpass *= coring_w;

    float rcas_noise_gate = 1.0 - noise_det;

    // Learned edge-confidence boost (relaxes noise gate on real edges)
    float learned_conf = learned_edge_confidence(v);
    rcas_noise_gate = mix(rcas_noise_gate, max(rcas_noise_gate, learned_conf * 0.85),
                          float(PHOTON_SHARP_CONTENT_ADAPT));

    float push = strength * highpass;

    float sharp_luma = orig_l + clip_aware_push(push, orig_l, v, strength) * rcas_noise_gate;
    return sharp_luma;
}

// ALGORITHM 1: Perceptual (bacondither-style power-mean edge)
float algo_perceptual(ivec2 sp, float orig_l, Nbhd3 v, Params p,
                      float strength) {
    float blur = (2.0*(v.n + v.e + v.w + v.s)
                + (v.nw + v.ne + v.sw + v.se)
                + 4.0*v.c) / 16.0;

    float c_comp = clamp(0.266666681 + 0.9*exp2(blur*blur*-7.4), 0.0, 1.0);

    float b_diff_c  = (blur - v.c)  * (blur - v.c);
    float b_diff_n  = (blur - v.n)  * (blur - v.n);
    float b_diff_s  = (blur - v.s)  * (blur - v.s);
    float b_diff_e  = (blur - v.e)  * (blur - v.e);
    float b_diff_w  = (blur - v.w)  * (blur - v.w);
    float b_diff_nw = (blur - v.nw) * (blur - v.nw);
    float b_diff_ne = (blur - v.ne) * (blur - v.ne);
    float b_diff_sw = (blur - v.sw) * (blur - v.sw);
    float b_diff_se = (blur - v.se) * (blur - v.se);

    float edge_val = (1.38*b_diff_c
                    + 1.15*(b_diff_n + b_diff_s + b_diff_e + b_diff_w)
                    + 0.92*(b_diff_nw + b_diff_ne + b_diff_sw + b_diff_se))
                   * c_comp;

    float pm_p  = 1.0;
    float edge_sharp = pow(edge_val, 0.5/(pm_p + EPS));
    edge_sharp = clamp(edge_sharp * strength * 0.5, 0.0, 1.0);

    float hp = orig_l - blur;

    float scale_lim = 0.06 * (1.0 + strength);
    float boosted = hp * (1.0 + edge_sharp + strength * 0.3);
    float limited = soft_lim(boosted, scale_lim + EPS);

    float sharp_luma = orig_l + limited;
    return sharp_luma;
}

// ALGORITHM 2: Structural (Sobel directional, halo-free)
float algo_structural(ivec2 sp, float orig_l, Nbhd3 v, Params p,
                      float strength) {
    vec2 ec = edge_struct(v);
    float edge_strength  = ec.x;
    float edge_coherence = ec.y;

    float directional_gain = smoothstep(0.02, 0.15, edge_strength)
                           * mix(0.3, 1.0, edge_coherence);

    // Learned edge-confidence boost (zero extra fetches)
    if (PHOTON_SHARP_CONTENT_ADAPT == 1) {
        float learned_conf = learned_edge_confidence(v);
        directional_gain = mix(directional_gain,
                               max(directional_gain, learned_conf), 0.5);
    }

    float fine_b = blur_fine(v);
    float hp     = orig_l - fine_b;

    float push = strength * hp * directional_gain;
    float sharp_luma = orig_l + clip_aware_push(push, orig_l, v, strength);
    return sharp_luma;
}

// ALGORITHM 3: Conservative (film-friendly, fine band only, tight coring)
float algo_conservative(ivec2 sp, float orig_l, Nbhd3 v, Params p,
                        float strength) {
    float fine_b = blur_fine(v);
    float hp     = orig_l - fine_b;

    float local_range = v.hi - v.lo;
    float coring_w = smoothstep(0.025, 0.075, local_range);
    hp *= coring_w;

    float noise_det = rcas_noise(v);
    hp *= (1.0 - noise_det);

    float push = strength * 0.4 * hp;
    float headroom_hi = max(v.hi - orig_l, EPS);
    float headroom_lo = max(orig_l - v.lo, EPS);
    float room = (push >= 0.0) ? headroom_hi : headroom_lo;
    float w    = room / (room + abs(push) + EPS);

    return orig_l + push * w;
}

// ALGORITHM 4: Aggressive (wide-band, full RCAS power)
float algo_aggressive(ivec2 sp, float orig_l, Nbhd3 v, Params p,
                      float strength, float gf) {
    float fine_b   = blur_fine(v);
    float coarse_b = blur_coarse(sp, v.c);

    float hp_fine   = orig_l - fine_b;
    float hp_coarse = orig_l - coarse_b;

    float w_c = mix(0.6, 0.9, 1.0 - p.fine_mix);
    float w_f = 1.0 - w_c * 0.5;
    float highpass = hp_fine * w_f + hp_coarse * w_c;

    int rp = res_profile();
    float coring_base = (rp == 0) ? 0.003 : (rp == 1) ? 0.002 : 0.001;
    coring_base *= (1.0 + 1.5 * p.block);
    float local_range = v.hi - v.lo;
    float coring_w = smoothstep(coring_base, coring_base*2.0, local_range);
    highpass *= coring_w;

    float push = strength * 1.4 * highpass;
    return orig_l + clip_aware_push(push, orig_l, v, strength);
}

vec4 hook() {
    vec4  orig   = HOOKED_tex(HOOKED_pos);
    float orig_l = get_luma(orig.rgb);
    ivec2 sp     = ivec2(HOOKED_pos * HOOKED_size - 0.5);

    Params p = unpack_params();
    Nbhd3  v = sample_nbhd3(sp);

    if (!p.has_feed) {
        float fb_peak, fb_contrast, fb_noise;
        estimate_fallback(v, fb_peak, fb_contrast, fb_noise);
        p.peak = fb_peak; p.contrast = fb_contrast; p.noise = fb_noise;
    }

    float gf      = max(float(PHOTON_SHARP_FACTOR_RENDERED), 0.01);
    float hg      = clamp(float(PHOTON_SHARP_HALO_GUARD), 0.0, 1.0);
    int   algo    = int(PHOTON_SHARP_ALGO);
    int   rp      = res_profile();

    // Adaptive strength
    // Dark-scene boost has exactly one decision point: Lua base_amount.
    // Applying it here too would double it.
    float strength = p.amount * gf;
    // Static per-resolution headroom. res_profile() only changes when
    // video dimensions change, never mid-playback of the same file, so
    // this multiplier is constant within a file.
    float res_headroom = (rp == 0) ? 1.15 : (rp == 1) ? 1.10 : 1.05;
    strength *= res_headroom;
    float contrast_scale = (rp == 0) ? 0.5 : (rp == 1) ? 0.45 : 0.3;
    strength *= (0.65 + contrast_scale * p.contrast);
    // Motion damping: stronger when hg is low (halo guard off → more ghost risk)
    float motion_damp = mix(0.45, 0.25, hg);
    strength *= (1.0 - motion_damp * p.motion);
    float noise_ceil = (rp == 0) ? 0.35 : (rp == 1) ? 0.28 : 0.20;
    float noise_gate = 1.0 - smoothstep(0.03, noise_ceil, p.noise);
    strength *= mix(0.5, 1.0, noise_gate);
    // Encode-block damping: a blocky file's surviving "detail" is mostly
    // artifact; soften the push so reconstruction does not outline it.
    strength *= mix(1.0, 0.45, p.block);
    // Ring damping: sharpening already-ringed content re-rings it. Same
    // guard shape as p.block, fed by photon's RG probe via scene-feed.
    strength *= mix(1.0, 0.45, p.ring);
    strength = clamp(strength, float(PHOTON_SHARP_AMOUNT_FLOOR), float(PHOTON_SHARP_AMOUNT_CEIL));


    // Algorithm selection
    float sharp_luma;
    if      (algo == 1) sharp_luma = algo_perceptual  (sp, orig_l, v, p, strength);
    else if (algo == 2) sharp_luma = algo_structural   (sp, orig_l, v, p, strength);
    else if (algo == 3) sharp_luma = algo_conservative (sp, orig_l, v, p, strength);
    else if (algo == 4) sharp_luma = algo_aggressive   (sp, orig_l, v, p, strength, gf);
    else                sharp_luma = algo_hybrid       (sp, orig_l, v, p, strength, gf);

    float local_range    = v.hi - v.lo;
    float flat_factor    = 1.0 - smoothstep(0.0, 0.10, local_range);
    float temporal_base  = p.alpha * (1.0 - 0.35 * p.motion);
    float temporal        = mix(temporal_base, min(1.0, temporal_base * 1.15 + 0.10), 1.0 - flat_factor);
    sharp_luma = mix(orig_l, sharp_luma, temporal);
    sharp_luma = clamp(sharp_luma, 0.0, 1.0);

    // Edge-aware halo mask: suppress at edge peaks, full gain in flat regions
    float edge_proximity = (local_range > EPS)
        ? clamp(abs(orig_l - mix(v.lo, v.hi, 0.5)) / (local_range * 0.5 + EPS) - 0.5, 0.0, 1.0)
        : 0.0;
    float halo_suppress = mix(1.0, 1.0 - edge_proximity * 0.4, hg);
    float delta = sharp_luma - orig_l;
    sharp_luma = orig_l + delta * halo_suppress;

    // Chroma ratio clamp (4th layer of halo defense).
    // hg=0 → wider window (max sharpness), hg=1 → narrow (film-friendly).
    float halo_base = (rp == 0) ? 0.28 : (rp == 1) ? 0.20 : 0.14;
    float halo_clamp = mix(halo_base * 1.4, halo_base * 0.6, hg);

    float safe_luma = max(orig_l, 0.001);
    float ratio     = sharp_luma / safe_luma;
    ratio = clamp(ratio, 1.0 - halo_clamp, 1.0 + halo_clamp);
    vec3 color = clamp(orig.rgb * ratio, 0.0, 1.0);

    return vec4(color, orig.a);
}
]]

--  NOT placed inside GLSL #if/#endif because mpv's block-splitter
--  parses directives BEFORE the preprocessor — a GLSL #if cannot
--  control block headers. Instead, conditionally concatenated in Lua
local PHOTON_SHARP_SHADER_SOURCE_PHASE2 = [[
// ================================================================
//  photon-sharp-temporal - MAINPRESUB hook: temporal luma buffer
//  Host: photon-sharp.lua (PHOTON_SHARP_SHADER_SOURCE_PHASE2) -> photon-sharp-temporal.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!TEXTURE photon_sharp_prev_luma_init
//!SIZE 2 2
//!FORMAT r16f
//!STORAGE
0000000000000000

//!HOOK MAINPRESUB
//!BIND HOOKED
//!BIND photon_sharp_prev_luma_init
//!SAVE photon_sharp_prev_luma
//!WIDTH HOOKED.w
//!HEIGHT HOOKED.h
//!DESC photon-sharp v8.1 Phase 2 — temporal luma buffer write (optional)
//!COMPONENTS 1
//!COMPUTE 32 32

// Writes this frame's luma to STORAGE image2D for the NEXT frame's
// MAINPRESUB hook. Self-contained — duplicates BT.709 luma coefs
// (libplacebo compiles each HOOK block independently, no cross-block
void hook() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= int(HOOKED_size.x) || pos.y >= int(HOOKED_size.y)) return;
    vec3 c = texelFetch(HOOKED_raw, pos, 0).rgb;
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    imageStore(out_image, pos, vec4(l, 0.0, 0.0, 1.0));
}

//!HOOK MAINPRESUB
//!BIND HOOKED
//!BIND photon_sharp_prev_luma
//!DESC photon-sharp v8.1 Phase2 — temporal reject blend (optional)

// Temporal reject via luma-difference threshold (no motion vectors).
// Large diff = motion/cut → reject old buffer, use spatial result only.
// Motion rejection, not compensation — ghost risk near zero.
vec4 hook() {
    vec4  orig = HOOKED_tex(HOOKED_pos);
    float cur_l = dot(orig.rgb, vec3(0.2126, 0.7152, 0.0722));
    ivec2 sp = ivec2(HOOKED_pos * HOOKED_size - 0.5);
    float prev_l = texelFetch(photon_sharp_prev_luma_raw, sp, 0).r;

    float diff = abs(cur_l - prev_l);
    float reject = smoothstep(0.04, 0.18, diff);

    float blended = mix(mix(prev_l, cur_l, 0.35), cur_l, reject);
    vec3 ratio_color = orig.rgb * (max(blended, 0.001) / max(cur_l, 0.001));
    return vec4(clamp(ratio_color, 0.0, 1.0), orig.a);
}
]]

--  photon-sharp SHADER WRITE / PARAM PUSH
--  One fixed file per temporal mode, each written ONCE per session:
--  mpv gpu-next caches parsed user shaders by path for the VO's

-- shader_dir defined in photon-common.lua — fix bugs there, not here.
local photon_sharp_paths = { main = nil, temporal = nil }
local photon_sharp_shader_written = false
local photon_sharp_shader_ready = false  -- HUD field; true once the startup write succeeds

local function photon_sharp_ensure_paths()
    if photon_sharp_paths.main then return photon_sharp_paths end
    photon_sharp_paths.main = common.shader_path("photon-sharp")
    photon_sharp_paths.temporal = common.shader_path("photon-sharp-temporal")
    return photon_sharp_paths
end

local function photon_sharp_active_path()
    local paths = photon_sharp_ensure_paths()
    return (PHOTON_SHARP_TEMPORAL_MODE == 1) and paths.temporal or paths.main
end

-- PARAM pushes target one file's basename, so each temporal mode has
-- its own prefix; the two files declare identical PARAMs.
local function photon_sharp_active_prefix()
    return (PHOTON_SHARP_TEMPORAL_MODE == 1) and "photon-sharp-temporal" or "photon-sharp"
end

-- Bakes only the never-changing values (clamps/sentinels) at the
-- one-time write; everything else is a //!PARAM uniform.
local function photon_sharp_bake(content)
    content = content:gsub("#define PHOTON_SHARP_AMOUNT_CEIL%s+%-?[%d.]+",
        string.format("#define PHOTON_SHARP_AMOUNT_CEIL      %.2f", PHOTON_SHARP_AMOUNT_CLAMP_MAX))
    return content
end

-- Writes both fixed files once. The temporal variant is the same text
-- plus the Phase 2 COMPUTE/STORAGE block — a separate file rather than
-- a #if because mpv's block-splitter parses directives before the
local function photon_sharp_write_shader()
    if photon_sharp_shader_written then return true end
    local paths = photon_sharp_ensure_paths()
    if not (paths.main and paths.temporal) then return false end
    local main = photon_sharp_bake(PHOTON_SHARP_SHADER_SOURCE)
    if main:find("//!COMPUTE", 1, true) then
        mp.msg.error("photon-sharp: UNEXPECTED //!COMPUTE in main template — report this.")
        return false
    end
    local temporal = main .. PHOTON_SHARP_SHADER_SOURCE_PHASE2
    for _, pair in ipairs({{paths.main, main}, {paths.temporal, temporal}}) do
        local f = io.open(pair[1], "w")
        if not f then
            mp.msg.error("photon-sharp: failed to write shader: " .. pair[1])
            return false
        end
        f:write(pair[2]); f:close()
    end
    photon_sharp_shader_written = true
    photon_sharp_shader_ready = true
    mp.msg.info("photon-sharp: shaders written -> " .. paths.main)
    return true
end

-- Every non-baked value, in one payload so multi-field changes land in
-- unchanged payload costs nothing.
local function photon_sharp_push_params()
    ps_refresh_adaptive()
    common.push_params(photon_sharp_active_prefix(), {
        {"PHOTON_SHARP_FRAME_PEAK", photon_scene_has_feed and photon_scene_smooth_peak or -1.0, "f"},
        {"PHOTON_SHARP_SCENE_CONTRAST", photon_scene_smooth_contrast, "f"},
        {"PHOTON_SHARP_NOISE_LEVEL", photon_scene_noise, "f"},
        {"PHOTON_SHARP_MOTION_LEVEL", photon_scene_smooth_motion, "f"},
        -- 118g: geometric m scales the AMOUNT (what the owner watches), not the factor.
        {"PHOTON_SHARP_AMOUNT", photon_sharp_strength_rendered * ps_multiplier, "f"},
        {"PHOTON_SHARP_FINE_COARSE", photon_sharp_smooth_coarse, "f"},
        -- Factor is geometry-free (coordinator: factor must not double m); the
        -- eased manual factor only, base knob/key step unchanged.
        {"PHOTON_SHARP_FACTOR_RENDERED", photon_sharp_factor_rendered, "f"},
        {"PHOTON_SHARP_TEMPORAL_ALPHA", PHOTON_SHARP_TEMPORAL_ALPHA, "f"},
        {"PHOTON_SHARP_HALO_GUARD", PHOTON_SHARP_HALO_GUARD, "f"},
        {"PHOTON_SHARP_BLOCK_LEVEL", photon_scene_block * PHOTON_SHARP_BLOCK_GUARD, "f"},
        {"PHOTON_SHARP_RING_LEVEL", photon_scene_rlevel * PHOTON_SHARP_RING_GUARD, "f"},
        {"PHOTON_SHARP_TEXTURE_BIAS", PHOTON_SHARP_TEXTURE_BIAS, "f"},
        {"PHOTON_SHARP_FINE_STRENGTH", PHOTON_SHARP_FINE_STRENGTH, "f"},
        {"PHOTON_SHARP_MEDIUM_STRENGTH", PHOTON_SHARP_MEDIUM_STRENGTH, "f"},
        {"PHOTON_SHARP_COARSE_STRENGTH", PHOTON_SHARP_COARSE_STRENGTH, "f"},
        {"PHOTON_SHARP_ALGO", photon_sharp_current_algo, "i"},
        {"PHOTON_SHARP_CONTENT_ADAPT", PHOTON_SHARP_CONTENT_ADAPT, "i"},
        {"PHOTON_SHARP_MEDIUM_BAND_ACTIVE", (PHOTON_SHARP_MEDIUM_STRENGTH > 0.001) and 1 or 0, "i"},
        {"PHOTON_SHARP_COARSE_BAND_ACTIVE", (PHOTON_SHARP_COARSE_STRENGTH > 0.001) and 1 or 0, "i"},
    })
end

-- glsl-shaders ownership contract: each script only touches its own paths.
local function photon_sharp_ensure_glsl_list_sane(shaders)
    local paths = photon_sharp_ensure_paths()
    return common.ensure_glsl_list_sane(shaders, {paths.main, paths.temporal})
end

-- Sharp hooks MAINPRESUB and the OUTPUT-stage effects hook OUTPUT, so
-- cross-effect order comes from the hook stage, not list position;
-- appending at the end is sufficient. Idempotent — enable, the temporal
local function photon_sharp_add_shader()
    local paths = photon_sharp_ensure_paths()
    local active = photon_sharp_active_path()
    if not active then return end
    local shaders = photon_sharp_ensure_glsl_list_sane(mp.get_property_native("glsl-shaders") or {})
    local filtered = {}
    for _, p in ipairs(shaders) do
        if p ~= paths.main and p ~= paths.temporal then table.insert(filtered, p) end
    end
    table.insert(filtered, active)
    mp.set_property_native("glsl-shaders", filtered)
end

local function photon_sharp_shader_in_list()
    local active = photon_sharp_active_path()
    if not active then return true end  -- can't check, assume fine
    for _, p in ipairs(mp.get_property_native("glsl-shaders") or {}) do
        if p == active then return true end
    end
    return false
end

-- Removes both mode paths from glsl-shaders (toggle off). Files intact.
local function photon_sharp_remove_from_list()
    local paths = photon_sharp_ensure_paths()
    if not paths.main then return end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local filtered, changed = {}, false
    for _, p in ipairs(shaders) do
        if p == paths.main or p == paths.temporal then changed = true
        else table.insert(filtered, p) end
    end
    if changed then mp.set_property_native("glsl-shaders", filtered) end
end

-- Enable ordering: files on disk first, params pushed second, path
-- added last — the newly loaded shader's first frame already has live
-- values instead of PARAM defaults.
local function photon_sharp_enable()
    photon_sharp_write_shader()
    photon_sharp_push_params()
    photon_sharp_add_shader()
end

-- asym_smooth defined in photon-common.lua — fix bugs there, not here.
local photon_sharp_smooth = common.asym_smooth
local reset_char_state = common.reset_char_state
local new_char_state = common.new_char_state

-- character tiers: dwell confirmation → commit → exponential ease to committed.
-- char_track defined in photon-common.lua — fix bugs there, not here.
local function ps_char_track(state, raw, now, dt, is_cut)
    return common.char_track(state, raw, now, dt, is_cut,
        PHOTON_SHARP_CHAR_TAU, PHOTON_SHARP_CHAR_DEAD_ZONE, PHOTON_SHARP_CHAR_DWELL_MIN,
        PHOTON_SHARP_CHAR_EASE_TAU, PHOTON_SHARP_CHAR_CUT_EASE_TAU)
end

local ps_char_state = {
    fine_coarse = new_char_state(0.50),
}
local ps_char_last_t = 0

local function ps_char_state_reset()
    local defaults = {fine_coarse = 0.50}
    for key, s in pairs(ps_char_state) do
        reset_char_state(s, defaults[key])
    end
end

-- photon_sharp_active is declared exactly once, at the top of the file
-- — a second local here once shadowed it and silently split the file
-- into two disconnected copies of the flag.

-- sharp_target_enabled: target state carried by photon.lua's
-- "photon-sharp-set-target-enabled" message on every file load.
-- Deliberately NOT reset in file-loaded — it persists for the whole
local sharp_target_enabled = mp.get_opt("photon-menu-enabled") ~= "false"


-- smooth_peak/contrast/noise are computed in photon.lua's
-- photon_scene_update_smoothing() and arrive already-smoothed via
-- "photon-scene-feed"; only smooth_coarse (Category C, sharp-only)
-- DT CEILING — the easing below is driven almost entirely by the ~4s
-- scene feed (the 1Hz periodic only publishes HUD state). Capping dt at
-- 1.0 made every tau run ~4x slower than its written value (a 9s tau
-- behaved as ~36s) and the char tier needed minutes before visibly
-- moving. dt now uses true elapsed time, capped at three feed ticks so a
-- stalled feed snaps instead of easing through a stale gap.
local PS_DT_MAX = 12.0

local function photon_sharp_update()
    -- Skip when sharpening is off (toggle only adds/removes from list)
    if not photon_sharp_active then return end

    local now = mp.get_time()

    -- TIER 1 dt (strength) and TIER 2 dt (fine_coarse) are computed
    -- separately, same as grain's gr_amount_last_t / gr_char_last_t split
    -- — two independent tiers, each with its own "time since I was last
    local dt = math_min(now - (photon_sharp_last_uniform_t > 0 and photon_sharp_last_uniform_t or now - 1.0), PS_DT_MAX)
    photon_sharp_last_uniform_t = now

    -- ── TIER 1  STRENGTH exponential ease toward photonsharpuse ──
    -- strength (the target, recomputed every feed by the photon-scene-
    -- Motion-adaptive tau_release: shorter release in fast scenes → less
    -- ghosting. Coefficient lowered from 0.55 — the original made release
    local strength_tau_release = PHOTON_SHARP_TAU_RELEASE * (1.0 - 0.25 * photon_scene_smooth_motion)
    strength_tau_release = math_max(strength_tau_release, PHOTON_SHARP_TAU_RELEASE * 0.25)
    photon_sharp_dyn_tau_release = strength_tau_release  -- kept for HUD/debug visibility, same field as before

    local strength_dt = math_min(now - (photon_sharp_strength_last_t > 0 and photon_sharp_strength_last_t or now - 0.1), PS_DT_MAX)
    photon_sharp_strength_last_t = now
    local strength_tau_attack = photon_scene_is_cut and PHOTON_SHARP_CUT_TAU or PHOTON_SHARP_TAU_ATTACK
    local strength_tau_release_eff = photon_scene_is_cut and PHOTON_SHARP_CUT_TAU or strength_tau_release
    photon_sharp_strength_rendered = photon_sharp_smooth(photon_sharp_strength_rendered, photon_sharp_user_strength,
        strength_tau_attack, strength_tau_release_eff, strength_dt)

    -- TIER 1B — FACTOR: separate eased chase, symmetric tau (deliberate
    -- user action, not a scene response). Computed unconditionally like
    -- TIER 1 above — force only paces the disk write further down.
    local factor_dt = math_min(now - (photon_sharp_factor_last_t > 0 and photon_sharp_factor_last_t or now - 0.1), PS_DT_MAX)
    photon_sharp_factor_last_t = now
    photon_sharp_factor_rendered = photon_sharp_smooth(photon_sharp_factor_rendered,
        PHOTON_SHARP_FACTOR, PHOTON_SHARP_FACTOR_TAU, PHOTON_SHARP_FACTOR_TAU, factor_dt)

    -- TIER 1C — MOTION: own short EMA (see state comment above for why).
    local motion_dt = math_min(now - (photon_sharp_motion_last_t > 0 and photon_sharp_motion_last_t or now - 0.1), PS_DT_MAX)
    photon_sharp_motion_last_t = now
    photon_scene_smooth_motion = photon_sharp_smooth(photon_scene_smooth_motion,
        photon_scene_motion, PHOTON_SHARP_MOTION_TAU, PHOTON_SHARP_MOTION_TAU, motion_dt)

    -- ── TIER 2  FINE/COARSE MIX long-EMA  dead-zone  dwell ──
    -- confirmation, same machinery as grain's character tier (ps_
    -- char_track mirrors gr_char_track exactly — see that function's
    -- comment header). photon_sharp_fine_coarse is the raw, possibly-
    local char_dt = math_min(now - (ps_char_last_t > 0 and ps_char_last_t or now - 0.1), PS_DT_MAX)
    ps_char_last_t = now
    if photon_sharp_fine_coarse_manual then
        -- User-triggered override (photon-sharp-fine-coarse script-message):
        -- applies instantly, bypassing dwell entirely — mirrors grain's
        -- "user-triggered places skip the rate-limit" rule for its n/m
        local fc = ps_char_state.fine_coarse
        fc.signal = photon_sharp_fine_coarse; fc.committed = photon_sharp_fine_coarse
        fc.rendered = photon_sharp_fine_coarse; fc.dwell_start = nil
        photon_sharp_smooth_coarse = photon_sharp_fine_coarse
    else
        photon_sharp_smooth_coarse = ps_char_track(ps_char_state.fine_coarse, photon_sharp_fine_coarse,
            now, char_dt, photon_scene_is_cut)
    end

    -- Params land every feed tick via one deduped change-list add — no
    -- file I/O, no shader rebuild, no flip to debounce.
    photon_sharp_push_params()
end

-- photon.lua's OSD Section 2 has no other way to see global_factor/
-- halo_guard/texture_bias/fine_strength/medium_strength/coarse_strength/
-- content_adapt/temporal_mode — those PHOTON_SHARP_* constants now live
local function photon_sharp_publish_hud_state()
    mp.commandv("script-message", "photon-sharp-hud-state",
        tostring(photon_sharp_active),
        tostring(photon_sharp_shader_ready),
        string.format("%d", photon_sharp_current_algo),
        string.format("%.4f", photon_sharp_strength_rendered * ps_multiplier),  -- actual baked AMOUNT (TIER 1 rendered x geometric m), matching what is baked into the shader
        string.format("%.4f", photon_sharp_smooth_coarse),
        string.format("%.4f", PHOTON_SHARP_FACTOR),
        string.format("%.4f", PHOTON_SHARP_HALO_GUARD),
        string.format("%.4f", PHOTON_SHARP_TEXTURE_BIAS),
        string.format("%.4f", PHOTON_SHARP_FINE_STRENGTH),
        string.format("%.4f", PHOTON_SHARP_MEDIUM_STRENGTH),
        string.format("%.4f", PHOTON_SHARP_COARSE_STRENGTH),
        string.format("%d", PHOTON_SHARP_CONTENT_ADAPT),
        string.format("%d", PHOTON_SHARP_TEMPORAL_MODE),
        string.format("%.4f", photon_scene_rlevel * PHOTON_SHARP_RING_GUARD),
        -- Menu state is the enabled target, even before a video has loaded.
        tostring(sharp_target_enabled),
        tostring(ps_source_h or 0), tostring(ps_output_h or 0),
        string.format("%.6f", ps_multiplier), tostring(ps_adaptive_mode and ps_source_h ~= nil),
        -- Field 20 (append-only): actual factor baked into the shader this tick
        -- (eased user factor, geometry-free). Field 21: base TIER 1 rendered
        -- amount before the geometric multiplier. Fields 1-19 unchanged.
        string.format("%.6f", photon_sharp_factor_rendered),
        string.format("%.4f", photon_sharp_strength_rendered))
end

-- Absolute shared mode, one writer in photon.lua; same-frame atomicity unverified.
mp.register_script_message("photon-adaptive-program-state", function(value)
    ps_adaptive_mode = value == "true"
    if photon_sharp_shader_ready then photon_sharp_push_params() else ps_refresh_adaptive() end
    photon_sharp_publish_hud_state()
end)
for _, property in ipairs({"video-dec-params", "video-params", "video-out-params", "osd-dimensions"}) do
    mp.observe_property(property, "native", function()
        if photon_sharp_shader_ready then photon_sharp_push_params() else ps_refresh_adaptive() end
        photon_sharp_publish_hud_state()
    end)
end

--  Fields 13-14 (scene_baseline_pbs/contrast) are populated only in SDR-VOD mode
local photon_scene_kv_decode = common.scene_kv_decode

-- Ring fields arrive inside photon-scene-feed (RG probe lives in
-- photon.lua next to BK — block and ring damage ride the same feed).
-- Declarations live next to photon_scene_block above: Lua locals are
-- scoped from the declaration line, and push_params / the hud publish
-- above this point must see them.
mp.register_script_message("photon-scene-feed", function(payload)
    local f = photon_scene_kv_decode(payload)

    photon_scene_peak            = clamp(tonumber(f.peak) or 0.50, 0.0, 1.0)
    photon_scene_contrast        = tonumber(f.contrast) or 0.35
    photon_scene_sat             = tonumber(f.sat) or 0.10
    photon_scene_motion          = clamp(tonumber(f.motion) or 0.0, 0.0, 1.0)
    photon_scene_is_cut          = (f.is_cut == "true")
    photon_scene_has_feed        = (f.has_feed == "true")
    photon_scene_smooth_peak     = tonumber(f.smooth_peak)     or photon_scene_smooth_peak
    photon_scene_smooth_contrast = tonumber(f.smooth_contrast) or photon_scene_smooth_contrast
    photon_scene_smooth_noise    = tonumber(f.smooth_noise)    or photon_scene_smooth_noise
    local prev_block = photon_scene_block
    photon_scene_block           = clamp(tonumber(f.block) or 0.0, 0.0, 1.0)
    if photon_scene_block >= 0.05 and prev_block < 0.05 then
        local lvl = photon_scene_block * PHOTON_SHARP_BLOCK_GUARD
        mp.msg.info(string.format(
            "photon-sharp: block guard engaged level=%.2f - strength x%.2f coring x%.2f",
            lvl, 1.0 - 0.55 * lvl, 1.0 + 1.5 * lvl))
    end

    local prev_rlevel = photon_scene_rlevel
    photon_scene_ring            = tonumber(f.ring)   or 0.0
    photon_scene_rlevel          = clamp(tonumber(f.rlevel) or 0.0, 0.0, 1.0)
    if photon_scene_rlevel >= 0.05 and prev_rlevel < 0.05 then
        local lvl = photon_scene_rlevel * PHOTON_SHARP_RING_GUARD
        mp.msg.info(string.format(
            "photon-sharp: ring guard engaged level=%.2f - strength x%.2f",
            lvl, 1.0 - 0.55 * lvl))
    end

    -- smooth_* values arrive already smoothed by photon.lua (see photon_scene_update_smoothing).

    photon_sharp_auto_set_noise(photon_scene_smooth_noise)

    photon_sharp_auto_set_fine_coarse(photon_scene_smooth_contrast)

    local base_amount = PHOTON_SHARP_BASE_AMOUNT_MIN
        + (PHOTON_SHARP_BASE_AMOUNT_MAX - PHOTON_SHARP_BASE_AMOUNT_MIN) * (1.0 - photon_scene_smooth_peak)

    local sdb_pbs = tonumber(f.baseline_pbs)
    if sdb_pbs then
        photon_sharp_scene_baseline_pbs      = sdb_pbs
        photon_sharp_scene_baseline_contrast = tonumber(f.baseline_contrast) or photon_scene_contrast
        photon_sharp_scene_baseline_t        = mp.get_time()
        local scene_dev = (photon_sharp_scene_baseline_pbs - 50.0) / 50.0 -- -1..1
        base_amount = base_amount - clamp(scene_dev * 0.12, -0.12, 0.12)
    end

    photon_sharp_user_strength = clamp(base_amount,
        PHOTON_SHARP_AMOUNT_CLAMP_MIN, PHOTON_SHARP_AMOUNT_CLAMP_MAX)

    photon_sharp_update()
end)

--  photon-sharp SCRIPT MESSAGE HANDLERS
--  All handlers change Lua state, then call photon_sharp_update() — one
--  deduped change-list add, no file I/O, no shader rebuild.

mp.register_script_message("photon-sharp-toggle", function()
    -- This handler OWNS the glsl-shaders list. If your input.conf has
    -- "change-list glsl-shaders toggle ..." bound to the same key,
    -- REMOVE it — two mechanisms managing the same list cause sync loss.
    sharp_target_enabled = not sharp_target_enabled
    photon_sharp_active = sharp_target_enabled
    if photon_sharp_active then
        mp.msg.info("photon-sharp: on")
        photon_sharp_enable()
    else
        mp.msg.info("photon-sharp: off")
        photon_sharp_remove_from_list()
    end
    photon_sharp_publish_hud_state()
end)

mp.register_script_message("photon-sharp-fine-coarse", function(val)
    photon_sharp_fine_coarse = clamp(tonumber(val) or 0.50, 0.0, 1.0)
    photon_sharp_fine_coarse_manual, photon_sharp_fine_coarse_manual_t = true, mp.get_time()
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-noise-gate", function(val)
    photon_scene_noise = clamp(tonumber(val) or 0.10, 0.0, 1.0)
    photon_sharp_noise_manual, photon_sharp_noise_manual_t = true, mp.get_time()
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-up", function()
    PHOTON_SHARP_FACTOR = clamp(PHOTON_SHARP_FACTOR + PHOTON_SHARP_FACTOR_STEP, PHOTON_SHARP_FACTOR_MIN, PHOTON_SHARP_FACTOR_MAX)
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-down", function()
    PHOTON_SHARP_FACTOR = clamp(PHOTON_SHARP_FACTOR - PHOTON_SHARP_FACTOR_STEP, PHOTON_SHARP_FACTOR_MIN, PHOTON_SHARP_FACTOR_MAX)
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-amount", function(val)
    local v = tonumber(val)
    if v then PHOTON_SHARP_FACTOR = clamp(v, PHOTON_SHARP_FACTOR_MIN, PHOTON_SHARP_FACTOR_MAX) end
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-algo", function(val)
    photon_sharp_current_algo = clamp(math.floor(tonumber(val) or 0), 0, 4)
    local names = {"Hybrid","Perceptual","Structural","Conservative","Aggressive"}
    print("gor-osd:" .. string.format("photon-sharp algo: %s (%d)", names[photon_sharp_current_algo+1] or "?", photon_sharp_current_algo))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-global", function(val)
    local v = tonumber(val)
    if not v then return end
    -- FACTOR applies once, at the very end of the shader strength
    -- chain — never added to or double-scaled against base_amount.
    PHOTON_SHARP_FACTOR  = clamp(v, PHOTON_SHARP_FACTOR_MIN, PHOTON_SHARP_FACTOR_MAX)
    print("gor-osd:" .. string.format("photon-sharp factor: %.2f", PHOTON_SHARP_FACTOR))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-halo", function(val)
    local v = tonumber(val)
    if not v then return end
    PHOTON_SHARP_HALO_GUARD     = clamp(v, 0.0, 1.0)
    PHOTON_SHARP_TEMPORAL_ALPHA = 0.65 * (1.0 - 0.12 * PHOTON_SHARP_HALO_GUARD)
    print("gor-osd:" .. string.format("photon-sharp halo_guard: %.2f", PHOTON_SHARP_HALO_GUARD))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-texture", function(val)
    local v = tonumber(val)
    if not v then return end
    PHOTON_SHARP_TEXTURE_BIAS = clamp(v, 0.0, 1.0)
    print("gor-osd:" .. string.format("photon-sharp texture_bias: %.2f", PHOTON_SHARP_TEXTURE_BIAS))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-cycle-algo", function()
    photon_sharp_current_algo = (photon_sharp_current_algo + 1) % 5
    local names = {"Hybrid","Perceptual","Structural","Conservative","Aggressive"}
    print("gor-osd:" .. string.format("photon-sharp algo → %s", names[photon_sharp_current_algo+1] or "?"))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-fine", function(val)
    local v = tonumber(val)
    if not v then return end
    PHOTON_SHARP_FINE_STRENGTH = clamp(v, 0.0, 4.0)
    print("gor-osd:" .. string.format("photon-sharp fine_strength: %.2f", PHOTON_SHARP_FINE_STRENGTH))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-medium", function(val)
    local v = tonumber(val)
    if not v then return end
    PHOTON_SHARP_MEDIUM_STRENGTH = clamp(v, 0.0, 4.0)
    print("gor-osd:" .. string.format("photon-sharp medium_strength: %.2f", PHOTON_SHARP_MEDIUM_STRENGTH))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-coarse", function(val)
    local v = tonumber(val)
    if not v then return end
    PHOTON_SHARP_COARSE_STRENGTH = clamp(v, 0.0, 4.0)
    print("gor-osd:" .. string.format("photon-sharp coarse_strength: %.2f", PHOTON_SHARP_COARSE_STRENGTH))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-content-adapt", function(val)
    local v = tonumber(val)
    if not v then return end
    PHOTON_SHARP_CONTENT_ADAPT = (v ~= 0) and 1 or 0
    print("gor-osd:" .. string.format("photon-sharp content_adapt: %s", PHOTON_SHARP_CONTENT_ADAPT == 1 and "on" or "off"))
    photon_sharp_update()
end)

mp.register_script_message("photon-sharp-set-temporal-mode", function(val)
    local v = tonumber(val)
    if not v then return end
    local new_mode = (v ~= 0) and 1 or 0
    if new_mode == 1 and PHOTON_SHARP_TEMPORAL_MODE == 0 then
        mp.msg.warn("photon-sharp: Phase 2 requires //!COMPUTE + //!STORAGE (Vulkan/D3D11/OpenGL 4.3+). Revert to 0 if shader fails.")
    end
    PHOTON_SHARP_TEMPORAL_MODE = new_mode
    print("gor-osd:" .. string.format("photon-sharp temporal_mode: %s", PHOTON_SHARP_TEMPORAL_MODE == 1 and "Phase2(buf)" or "Phase1(EMA)"))
    if photon_sharp_active then
        -- Push targets the new mode's file prefix, then swap the path:
        photon_sharp_push_params()
        photon_sharp_add_shader()
    end
end)

--  FILE-LOADED / SESSION STATE
mp.register_event("file-loaded", function()
    photon_sharp_user_strength    = 0.78
    photon_sharp_fine_coarse      = 0.50
    photon_sharp_smooth_coarse    = 0.50
    photon_sharp_last_uniform_t   = 0
    photon_sharp_current_algo     = PHOTON_SHARP_ALGO_DEFAULT

    -- TIER 1: snap rendered straight to target — a file load is a clean
    -- start, not a mid-playback cut.
    photon_sharp_strength_rendered = photon_sharp_user_strength
    photon_sharp_strength_last_t   = 0

    -- TIER 1B: same snap reasoning. FACTOR itself (the control-panel
    -- value) persists across file loads — only the eased mirror snaps.
    photon_sharp_factor_rendered = PHOTON_SHARP_FACTOR
    photon_sharp_factor_last_t   = 0

    -- TIER 2 (fine/coarse character): reset to neutral with no pending
    -- dwell — a new file shouldn't inherit a dwell timer or committed
    -- value that was mid-flight for a completely different piece of
    ps_char_state_reset()
    ps_char_last_t = 0

    photon_scene_peak            = 0.50
    photon_scene_contrast        = 0.35
    photon_scene_noise           = 0.10
    photon_scene_sat             = 0.10
    photon_scene_motion          = 0.20
    photon_scene_is_cut          = false
    photon_scene_has_feed        = false
    photon_scene_smooth_peak     = 0.50
    photon_scene_smooth_contrast = 0.35
    photon_scene_smooth_noise    = 0.10
    photon_scene_block           = 0.0
    photon_scene_ring            = 0.0
    photon_scene_rlevel          = 0.0
    photon_scene_smooth_motion   = 0.20
    photon_sharp_motion_last_t   = 0

    photon_sharp_fine_coarse_manual   = false
    photon_sharp_noise_manual         = false

    photon_sharp_scene_baseline_pbs      = nil
    photon_sharp_scene_baseline_contrast = nil
    photon_sharp_scene_baseline_t        = 0

    if sharp_target_enabled and not photon_sharp_active then
        photon_sharp_active = true
        photon_sharp_enable()
        mp.msg.info("photon-sharp: enabled (carried over)")
    elseif not sharp_target_enabled and photon_sharp_active then
        photon_sharp_remove_from_list()
        photon_sharp_active = false
        mp.msg.info("photon-sharp: disabled (target off)")
    end

    if photon_sharp_active then photon_sharp_push_params() end
    photon_sharp_publish_hud_state()
end)

-- Contract: load event and target message may arrive in either order.
mp.register_script_message("photon-sharp-set-target-enabled", function(val)
    sharp_target_enabled = (val == "true")
    if sharp_target_enabled and not photon_sharp_active then
        photon_sharp_active = true
        photon_sharp_enable()
        mp.msg.info("photon-sharp: enabled (carried over)")
        photon_sharp_publish_hud_state()
    elseif not sharp_target_enabled and photon_sharp_active then
        photon_sharp_remove_from_list()
        photon_sharp_active = false
        mp.msg.info("photon-sharp: disabled (target off)")
        photon_sharp_publish_hud_state()
    end
end)

--  TIMER
-- 1Hz HUD publish, same cadence as grain/chrome. Self-heal re-adds the
-- active path if something external cleared glsl-shaders (grain has the
local function photon_sharp_periodic_update()
    photon_sharp_publish_hud_state()
    if photon_sharp_active and not photon_sharp_shader_in_list() then
        photon_sharp_add_shader()
    end
end

mp.add_periodic_timer(1.0, photon_sharp_periodic_update)

-- Startup: delete legacy A/B slot files so the pre-PARAM scheme can
-- never resurface, then write both fixed mode files once. Nothing in
-- this session rewrites those paths (mpv gpu-next caches shader text by
local function photon_sharp_delete_legacy_files()
    local dir = common.shader_dir()
    if not dir then return end
    os.remove(dir .. "photon-sharp-shader-a.glsl")
    os.remove(dir .. "photon-sharp-shader-b.glsl")
end
photon_sharp_delete_legacy_files()
photon_sharp_write_shader()
