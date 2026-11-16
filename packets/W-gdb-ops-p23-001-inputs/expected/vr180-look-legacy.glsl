// ================================================================
//  vr180-look - MAIN hook, OUTPUT-sized: SBS reprojection
//  Host: vr180-look.lua (VR180_LOOK_SOURCE) -> vr180-look.glsl
//  Contract: live PARAMs match host pushes; shader path remains stable
//  Answers: I40 · TRAP-09
// ================================================================
//!PARAM vr_native_tb
//!TYPE float
0.0

//!PARAM vr_cross_eye
//!TYPE float
0.0

//!PARAM vr_calibration
//!TYPE float
0.0

//!PARAM vr_head_roll
//!TYPE float
0.0

//!PARAM vr_source_layout
//!TYPE float
0.0

//!PARAM vr_plain
//!TYPE float
0.0

//!PARAM vr_plain_aspect
//!TYPE float
0.0

//!PARAM vr_yaw
//!TYPE float
0.0

//!PARAM vr_pitch
//!TYPE float
0.0

//!PARAM vr_fov
//!TYPE float
1.5707963

//!PARAM vr_roll
//!TYPE float
0.0

//!PARAM vr_base_ipd
//!TYPE float
0.0

//!PARAM vr_ipd_nudge
//!TYPE float
0.0

//!PARAM vr_head_x
//!TYPE float
0.0

//!PARAM vr_head_y
//!TYPE float
0.0

//!PARAM vr_head_z
//!TYPE float
0.0

//!PARAM vr_swap_eyes
//!TYPE float
1.0

//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!DESC vr180-look v1.3 — VR180 SBS equirectangular look-around

#define PI 3.14159265359
#define PHYSICAL_GAP_FRAC 0.012500
#define EYE_GAP_BLUR_FRAC 0.500000
#define PERIPHERAL_VIGNETTE_MODE 1
#define PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG 90.000000
#define ZOOM_COMPENSATION_ENABLED 1
#define ZOOM_COMPENSATION_STRENGTH 0.007500
#define ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC 0.007500
#define ZOOM_REFERENCE_FOV_DEG 90.000000
#define PARALLAX_CORRECTION_ENABLED 1
#define PARALLAX_CORRECTION_STRENGTH 0.400000
#define PARALLAX_CORRECTION_DISPARITY -0.400000
#define PERIPHERAL_VIGNETTE_START_FRAC 0.250000
#define PERIPHERAL_VIGNETTE_DARKEN_STRENGTH 1.000000
#define PERIPHERAL_VIGNETTE_BLUR_STRENGTH 0.001500
#define PERIPHERAL_VIGNETTE_BLUR_SAMPLES 9
#define SPHERE_RADIUS_METERS 1.700000
#define vr_frame_fit 0.0
#define vr_frame_spacing 0.0
vec2 stereo_pair_uv(vec2 uv,float right,float eye_aspect,vec2 content) {
    float oa=target_size.x/target_size.y;
    float separation=0.5+PHYSICAL_GAP_FRAC*0.25;
    float angle=vr_head_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);
    float held_angle=vr_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);
    float cr=abs(cos(vr_roll)),sr=abs(sin(vr_roll));
    float fw=content.x*eye_aspect,fh=content.y;
    // Minimum centre spacing that puts every film corner on its own side
    // of the rotating divider, including parallel/crossed pairing.
    float delta=vr_roll-held_angle;
    float spacing=vr_frame_spacing>0.0 ? vr_frame_spacing:max(separation*oa,fw*abs(cos(delta))+fh*abs(sin(delta))+PHYSICAL_GAP_FRAC*oa*0.5);
    float bound_w=spacing*abs(cos(held_angle))+fw*cr+fh*sr;
    float bound_h=spacing*abs(sin(held_angle))+fh*cr+fw*sr;
    // Largest uniform scale allowed by BOTH physical screen dimensions.
    // Only held roll enters this fit. Fusion noise moves centres, not scale.
    float fit=vr_frame_fit>0.0 ? vr_frame_fit:min(1.0,min(oa/max(bound_w,0.000001),1.0/max(bound_h,0.000001)));
    float side=right-0.5;
    uv.x-=side*(spacing*cos(angle)*fit-separation*oa)/eye_aspect;
    uv.y-=side*spacing*sin(angle)*fit;
    return (uv-vec2(0.5))/fit+vec2(0.5);
}

// Owner192d ruling: eye ownership and the physical divider tilt with the pair.
// Inverse rotate in physical pixel space, only for ownership/gutter. Sampling
// remains in screen coordinates, so the existing S1 centres are not rotated twice.
vec2 stereo_partition(vec2 pos,float aspect) {
    float angle=-vr_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);
    vec2 q=(pos-vec2(0.5))*vec2(aspect,1.0);
    q=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*q;
    return q/vec2(aspect,1.0)+vec2(0.5);
}

vec2 native_source_uv(float packed_x,float y) {
    float eye=step(0.5,packed_x);
    return vr_native_tb>0.5 ? vec2((packed_x-eye*0.5)*2.0,(y+eye)*0.5):vec2(packed_x,y);
}

vec4 hook() {
    // MAIN hook with WIDTH/HEIGHT OUTPUT.w/h: this pass IS the output-sized pass and HOOKED_tex()
    // samples the original source texture, so the reprojection is the only resample (block 182 1.1).
    // HOOKED_size is the SOURCE size here, so the output size comes from target_size.
    vec2 out_size = target_size;

    // ── Roll-compensated eye partition ──
    // Native viewports stay fixed; roll exists only in the camera ray.
    // Everything below this point that reads HOOKED_pos (the physical
    // gap, the vertical zoom-compensation margin, the edge blur, and
    // is_right_eye itself) assumes a SCREEN-ALIGNED eye split: left eye
    vec2 eye_pos = HOOKED_pos;

    // ── Physical gap between the two eyes see VRPHYSICALGAPFRAC ──
    //    above for the full repurposing rationale) ──────────────────
    // Each eye's DISPLAYED region shrinks inward to make room for a
    // real gap in the middle -- this changes WHICH output positions
    // belong to which eye (the actual layout), not just what color
    float half_gap    = PHYSICAL_GAP_FRAC * 0.25;
    float half_blur   = EYE_GAP_BLUR_FRAC * 0.25;  // still the blur-edge color fade width, same unit family
    float left_end    = 0.5 - half_gap;
    float right_start = 0.5 + half_gap;

    float tan_half_fov = tan(vr_fov * 0.5);

    // ── Zoom-compensation vertical-height growth Mechanism A se ──
    //    VR_ZOOM_COMPENSATION_ENABLED above for the corrected mechanism
    // vertical_height_scale: 1.0 = full screen height (no effect --
    // either disabled, or already at/past the point where growth
    float vertical_height_scale = 1.0;
#if ZOOM_COMPENSATION_ENABLED
    float zoom_ref_tan_half_fov = tan(radians(ZOOM_REFERENCE_FOV_DEG) * 0.5);
    float zoom_magnification = zoom_ref_tan_half_fov / tan_half_fov;
    float height_scale_full = clamp(
        ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC * zoom_magnification,
        ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC, 1.0
    );
    vertical_height_scale = mix(1.0, height_scale_full, ZOOM_COMPENSATION_STRENGTH);
#endif

    // No pre-existing vertical split to layer onto (SBS eyes already
    // each span the full [0,1] height), so top_margin and bottom_margin
    // are always equal, both measured against the full [0,1] range.
    float top_margin    = (1.0 - vertical_height_scale) * 0.5;
    float bottom_margin = top_margin;
    float y_draw_start = top_margin;
    float y_draw_end   = 1.0 - bottom_margin;

    // No eye owns: the gap band itself (horizontal, unchanged from
    // before this mechanism ever existed -- Mechanism A never touches
    // left_end/right_start), OR either eye's own vertical margin
    bool in_gap = (eye_pos.x >= left_end && eye_pos.x < right_start);
    // Block 182 1.2 (full fill): the vertical margin is no longer painted black and no longer fades to black.
    // Measured on Linux mpv 0.41: at rest it blanked the 2 outermost rows (about 3 px at 1600 rows) of every
    // eye. The vertical MAPPING (y_draw_start/y_draw_end, so the effective vertical fov) is unchanged; the rows
    // that fell in the margin now sample the nearest valid row (eye_uv.y is clamped below).
    if (in_gap) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }

    // Distance from whichever drawn-content edge is nearest THIS
    // pixel's own eye -- used below purely for the blur-edge color
    // fade (softening the boundary where each eye's reprojected image
    float dist_from_edge = (eye_pos.x < 0.5) ? (left_end - eye_pos.x) : (eye_pos.x - right_start);
    // 0.0 at either edge (would still be black) rising to 1.0 at
    // half_blur further into the eye's own drawn content -- same
    // S-curve smoothstep shape as before.
    float strip_blend = smoothstep(0.0, half_blur, dist_from_edge);
    strip_blend = pow(strip_blend, 0.25);

    // Aspect ratio of ONE eye's SOURCE content (out_size.x * 0.5 is
    // still the ORIGINAL half-frame width, deliberately UNCHANGED by
    float eye_aspect = (out_size.x * 0.5) / out_size.y;

    // Figure out which eye this output pixel belongs to and its
    // position WITHIN that eye's own (vertically, possibly less-than-
    // full-height) drawn region, remapped to [0,1] -- this is what all the
    float is_right_eye = step(right_start, eye_pos.x);
    vec2 eye_uv = vec2(
        is_right_eye > 0.5
            ? (eye_pos.x - right_start) / (1.0 - right_start)
            : (eye_pos.x / left_end),
        eye_pos.y
    );

    // Pinhole camera ray in camera space. eye_uv in [0,1] -> NDC-like
    // [-1,1], scaled by tan(fov/2) so vr_fov is the camera's true
    // horizontal field of view.
    //194h fixed full-height viewports, rotating native optical-centre baseline.
    // a426265 rotated pair ownership; retain its rigid centre rotation without
    // rotating the divider or applying flat fit/zoom. Cross/parallel reverse
    // the viewer eye axis. Camera ray roll below remains unchanged.
    float native_angle=vr_head_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);
    float native_spacing=(0.5+PHYSICAL_GAP_FRAC*0.25)*out_size.x/out_size.y;
    float native_side=is_right_eye-0.5;
    eye_uv.x-=native_side*native_spacing*(cos(native_angle)-1.0)/(out_size.x*left_end/out_size.y);
    eye_uv.y-=native_side*native_spacing*sin(native_angle);
    eye_uv.y=clamp((eye_uv.y-y_draw_start)/(y_draw_end-y_draw_start),0.0,1.0);
    float ndc_x = (eye_uv.x * 2.0 - 1.0);
    float ndc_y = (1.0 - eye_uv.y * 2.0);  // flip: image v grows downward, ray y should grow upward

    // ── Peripheral-vision vignette factor ──
    // peripheral_factor: 0.0 at this eye's own center, ramping to 1.0
    // exactly at this eye's own corner -- radial, so it's naturally
    // larger at a corner than at a mid-edge point at the same "ring",
#if PERIPHERAL_VIGNETTE_MODE == 2
    float true_x = ndc_x * tan_half_fov;
    float true_y = (ndc_y / eye_aspect) * tan_half_fov;
    float reference_tan_half_fov = tan(radians(PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG) * 0.5);
    float ref_corner_x = reference_tan_half_fov;
    float ref_corner_y = reference_tan_half_fov / eye_aspect;
    float peripheral_radial = length(vec2(true_x, true_y)) / length(vec2(ref_corner_x, ref_corner_y));
#else
    float dx = ndc_x * eye_aspect;  // un-squash x by aspect so corner normalizes correctly regardless of aspect ratio
    float dy = ndc_y;
    float corner_mag = length(vec2(eye_aspect, 1.0));
    float peripheral_radial = length(vec2(dx, dy)) / corner_mag;
#endif
    // Smooth ramp from 0.0 at VR_PERIPHERAL_VIGNETTE_START_FRAC up to
    // 1.0 at the corner (peripheral_radial == 1.0). Pixels closer to
    // center than the start fraction are completely unaffected.
    float peripheral_factor = smoothstep(PERIPHERAL_VIGNETTE_START_FRAC, 1.0, peripheral_radial);

    // ── Parallax correction Mechanism B see ──
    //    VR_PARALLAX_CORRECTION_ENABLED above for the full rationale) ──
    // Deliberately placed AFTER the vignette factor above and BEFORE
    // screen/viewing-cone position (must use the ORIGINAL ndc_x/ndc_y),
    float eye_sign = is_right_eye > 0.5 ? 1.0 : -1.0;

#if PARALLAX_CORRECTION_ENABLED
    float parallax_ref_tan_half_fov = tan(radians(ZOOM_REFERENCE_FOV_DEG) * 0.5);
    float magnification = parallax_ref_tan_half_fov / tan_half_fov;
    float excess_disparity = PARALLAX_CORRECTION_DISPARITY * (magnification - 1.0) * PARALLAX_CORRECTION_STRENGTH;
#else
    float excess_disparity = 0.0;
#endif

    // ── Virtual IPD ──
    // See the Lua-side VR_PARALLAX_CORRECTION_DISPARITY-adjacent
    // comment above for the full rationale. Two independent
    // contributions to the same per-eye horizontal shift
    float ipd_shift = vr_base_ipd + vr_ipd_nudge;

    // Combined into ONE shift, ONE clamp, ONE ndc_x write -- not two
    // separate `ndc_x -=` lines. A single combined clamp (rather than
    // clamping excess_disparity and ipd_shift independently before
    float combined_horizontal_shift = clamp(excess_disparity + ipd_shift, -0.8, 0.8);
    ndc_x -= eye_sign * combined_horizontal_shift * 0.5;

    vec3 ray = normalize(vec3(
        ndc_x * tan_half_fov,
        ndc_y * tan_half_fov / eye_aspect,
        1.0
    ));

    // ── Roll ──
    // Applied here -- on ray.xy, AFTER the eye_aspect divide above and
    // BEFORE pitch/yaw below -- and nowhere else, for two reasons:
    // 1. Must be after eye_aspect correction. ray.xy at this point is
    float cr = cos(vr_roll), sr = sin(vr_roll);
    vec3 ray_rolled = vec3(
        ray.x * cr - ray.y * sr,
        ray.x * sr + ray.y * cr,
        ray.z
    );

    // Rotate ray by pitch (around camera-space X) then yaw (around
    // world-space Y) — standard look-around order, pitch first so
    // "up/down" stays relative to the head, then yaw sweeps that
    float cp = cos(vr_pitch), sp = sin(vr_pitch);
    vec3 ray_pitched = vec3(
        ray_rolled.x,
        ray_rolled.y * cp - ray_rolled.z * sp,
        ray_rolled.y * sp + ray_rolled.z * cp
    );
    float cy = cos(vr_yaw), sy = sin(vr_yaw);
    vec3 ray_world = vec3(
        ray_pitched.x * cy + ray_pitched.z * sy,
        ray_pitched.y,
        -ray_pitched.x * sy + ray_pitched.z * cy
    );

    // ── Motion parallax from head position ──
    // Everything above builds ray_world as a pure ROTATION from a
    // fixed origin -- yaw/pitch/roll alone can never produce parallax,
    // since a direction-only change shifts every point in the frame by
    vec3 head_offset = vec3(vr_head_x, vr_head_y, vr_head_z);
    vec3 sphere_hit  = ray_world * SPHERE_RADIUS_METERS;
    ray_world = normalize(sphere_hit - head_offset);

    // Spherical coordinates from the world-space ray. VR180 content
    // covers a 180-degree hemisphere (theta in [-pi/2, pi/2] maps to
    float u;
    if (ray_world.z <= 0.0) {
        u = (ray_world.x >= 0.0) ? 1.0 : 0.0;
    } else {
        float theta = atan(ray_world.x, ray_world.z);  // now guaranteed in (-pi/2, pi/2)
        u = (theta / PI) + 0.5;
        u = clamp(u, 0.0, 1.0);
    }

    float phi = asin(clamp(ray_world.y, -1.0, 1.0));  // -pi/2..pi/2
    float v = 0.5 - (phi / PI);
    v = clamp(v, 0.0, 1.0);

    // Map back into the correct eye's half of the actual SBS source
    // texture (HOOKED_tex samples the ORIGINAL full frame, so u must
    // be re-offset into whichever half we determined this output
    bool src_right_half = (is_right_eye > 0.5) != (vr_swap_eyes > 0.5);
    float src_u = src_right_half ? (u * 0.5 + 0.5) : (u * 0.5);

    // ── Peripheral blur real defocus averages neighboring SOURC ──
    // Engineering note: the sampling offset below is applied directly
    // OUTPUT screen space. A true screen-space defocus would need each
    float blur_radius = PERIPHERAL_VIGNETTE_BLUR_STRENGTH * peripheral_factor;
    vec4 blurred_color = vec4(0.0);
    if (blur_radius > 0.0) {
        // 1 center tap + (PERIPHERAL_VIGNETTE_BLUR_SAMPLES - 1) taps
        // evenly spaced around a ring of radius blur_radius, uniformly
        // weighted -- at blur_radius==0 every tap would land on the
        vec4 blurred_color_accum = vec4(0.0);
        blurred_color_accum += HOOKED_tex(native_source_uv(src_u,v));  // center tap
        for (int i = 0; i < PERIPHERAL_VIGNETTE_BLUR_SAMPLES - 1; i++) {
            float angle = 6.28318530718 * float(i) / float(PERIPHERAL_VIGNETTE_BLUR_SAMPLES - 1);
            vec2 ring_offset = vec2(cos(angle), sin(angle)) * blur_radius;
            blurred_color_accum += HOOKED_tex(native_source_uv(src_u,v) + ring_offset);
        }
        blurred_color = blurred_color_accum / float(PERIPHERAL_VIGNETTE_BLUR_SAMPLES);
    } else {
        blurred_color = HOOKED_tex(native_source_uv(src_u,v));
    }

    // ── Peripheral darken ──
    // Fades the (possibly already blurred) color toward black, up to
    // PERIPHERAL_VIGNETTE_DARKEN_STRENGTH at the corner
    // (peripheral_factor==1). Separate control from the blur above so
    float darken_amount = PERIPHERAL_VIGNETTE_DARKEN_STRENGTH * peripheral_factor;
    vec4 peripheral_color = mix(blurred_color, vec4(0.0, 0.0, 0.0, 1.0), darken_amount);

    // Fade toward the black strip inside the blurred edge band
    // (strip_blend < 1.0); everywhere else strip_blend is exactly 1.0
    // so this mix is a no-op and peripheral_color passes through
    return mix(vec4(0.0, 0.0, 0.0, 1.0), peripheral_color, strip_blend);
}
