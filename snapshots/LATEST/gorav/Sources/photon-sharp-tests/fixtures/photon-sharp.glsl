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
#define PHOTON_SHARP_AMOUNT_CEIL      128.00
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
