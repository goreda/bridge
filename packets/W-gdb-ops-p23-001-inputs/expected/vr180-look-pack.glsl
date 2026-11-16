//!HOOK MAIN
//!BIND HOOKED
//!SAVE D3_TITLE
//!WIDTH 1
//!HEIGHT 1
//!DESC 2D3D title source statistics (25 taps per frame, not per output pixel)
vec4 hook() {
    float dark=0.0;
    for(int y=0;y<5;y++)for(int x=0;x<5;x++) {
        vec3 c=HOOKED_tex(vec2((float(x)+0.5)/5.0,(float(y)+0.5)/5.0)).rgb;
        float l=dot(c,vec3(0.2126,0.7152,0.0722));
        float chroma=max(c.r,max(c.g,c.b))-min(c.r,min(c.g,c.b));
        if(l<0.08 && chroma<0.06)dark+=1.0/25.0;
    }
    return vec4(dark,0.0,0.0,1.0);
}
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

//!PARAM vr_surface_w
//!TYPE float
0.0

//!PARAM vr_surface_h
//!TYPE float
0.0

//!PARAM vr_surface_x
//!TYPE float
0.0

//!PARAM vr_surface_y
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

//!PARAM vr_flat_sbs
//!TYPE float
0.0

//!PARAM vr_pack
//!TYPE float
0.0

//!PARAM vr_pk_conv
//!TYPE float
0.5

//!PARAM vr_pk_zoom
//!TYPE float
1.0

//!PARAM vr_pk_soft
//!TYPE float
1.0

//!PARAM vr_pk_surround_invert
//!TYPE float
0.0

//!PARAM vr_flat_mono
//!TYPE float
0.0

//!PARAM vr_d3_gain
//!TYPE float
0.02

//!PARAM vr_eye_aspect
//!TYPE float
0.0

//!PARAM vr_frame_fit
//!TYPE float
0.0

//!PARAM vr_frame_spacing
//!TYPE float
0.0

//!PARAM vr_source_x
//!TYPE float
0

//!PARAM vr_source_y
//!TYPE float
0

//!PARAM vr_source_w
//!TYPE float
1

//!PARAM vr_source_h
//!TYPE float
1

//!PARAM vr_crop_x
//!TYPE float
1.0

//!PARAM vr_crop_y
//!TYPE float
1.0

//!PARAM vr_aspect_override
//!TYPE float
0.0

//!PARAM vr_manual_yaw
//!TYPE float
0.0

//!PARAM vr_manual_pitch
//!TYPE float
0.0

//!PARAM vr_manual_view
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

//!PARAM blink_top_bottom
//!TYPE float
0.0

//!PARAM blink_lid_l
//!TYPE float
0

//!PARAM blink_lid_r
//!TYPE float
0

//!PARAM blink_reopen_l
//!TYPE float
0

//!PARAM blink_reopen_r
//!TYPE float
0

//!PARAM blink_close_ms
//!TYPE float
80

//!PARAM blink_open_ms
//!TYPE float
180

//!PARAM blink_failopen_ms
//!TYPE float
200

//!PARAM blink_adapt_ms
//!TYPE float
250

//!PARAM blink_upper
//!TYPE float
0.92

//!PARAM blink_lower
//!TYPE float
0.08

//!PARAM blink_arc
//!TYPE float
0.08

//!PARAM blink_fringe
//!TYPE float
0.03

//!PARAM blink_glow
//!TYPE float
0.05

//!PARAM blink_glow_radius
//!TYPE float
0.08

//!PARAM blink_slit_blur
//!TYPE float
0.004

//!PARAM blink_contrast
//!TYPE float
0.4

//!PARAM blink_lift
//!TYPE float
0.15

//!PARAM blink_sbs_strength
//!TYPE float
1.0

//!PARAM blink_warm_r
//!TYPE float
1.0

//!PARAM blink_warm_g
//!TYPE float
1.0

//!PARAM blink_warm_b
//!TYPE float
1.0

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

//!PARAM vr_zoomcomp_baseline
//!TYPE float
0.007500
//!PARAM vr_gap_frac
//!TYPE float
0.012500
//!PARAM vr_gap_blur_frac
//!TYPE float
0.500000
//!PARAM vr_vignette_ref_fov
//!TYPE float
90.000000
//!PARAM vr_parallax_strength
//!TYPE float
0.400000
//!PARAM vr_parallax_disparity
//!TYPE float
-0.400000
//!PARAM vr_vignette_start
//!TYPE float
0.250000
//!PARAM vr_vignette_darken
//!TYPE float
1.000000
//!PARAM vr_vignette_blur
//!TYPE float
0.001500
//!HOOK MAIN
//!BIND HOOKED
//!BIND D3_TITLE
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!DESC vr180-look v1.3 — VR180 SBS equirectangular look-around

#define PI 3.14159265359
#define PHYSICAL_GAP_FRAC vr_gap_frac

#define EYE_GAP_BLUR_FRAC vr_gap_blur_frac

#define PERIPHERAL_VIGNETTE_MODE 1
#define PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG vr_vignette_ref_fov

#define ZOOM_COMPENSATION_ENABLED 1
#define ZOOM_COMPENSATION_STRENGTH 0.007500
#define ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC vr_zoomcomp_baseline

#define ZOOM_REFERENCE_FOV_DEG 90.000000
#define PARALLAX_CORRECTION_ENABLED 1
#define PARALLAX_CORRECTION_STRENGTH vr_parallax_strength

#define PARALLAX_CORRECTION_DISPARITY vr_parallax_disparity

#define PERIPHERAL_VIGNETTE_START_FRAC vr_vignette_start

#define PERIPHERAL_VIGNETTE_DARKEN_STRENGTH vr_vignette_darken

#define PERIPHERAL_VIGNETTE_BLUR_STRENGTH vr_vignette_blur

#define PERIPHERAL_VIGNETTE_BLUR_SAMPLES 9
#define SPHERE_RADIUS_METERS 1.700000
// Block185a: per-eye curved lid, diffusion, scene-dependent warm glow and reopening.
vec2 blink_clamp(vec2 p,float eye) {
    vec2 px=vec2(0.5)/HOOKED_size;
    vec2 lo=vec2(vr_source_x,vr_source_y),hi=lo+vec2(vr_source_w,vr_source_h);
    if(vr_source_layout<2.5) {
        if(vr_plain>0.5 || vr_flat_mono>0.5)p=clamp(p,lo+px,hi-px);
        else if(blink_top_bottom>0.5)p=clamp(p,vec2(lo.x,(lo.y+eye)*0.5)+px,vec2(hi.x,(hi.y+eye)*0.5)-px);
        else p=clamp(p,vec2((lo.x+eye)*0.5,lo.y)+px,vec2((hi.x+eye)*0.5,hi.y)-px);
    }
    if(vr_plain>0.5 || vr_flat_mono>0.5)return clamp(p,px,vec2(1.0)-px);
    if(blink_top_bottom>0.5)return vec2(clamp(p.x,px.x,1.0-px.x),clamp(p.y,eye*0.5+px.y,(eye+1.0)*0.5-px.y));
    return vec2(clamp(p.x,eye*0.5+px.x,(eye+1.0)*0.5-px.x),clamp(p.y,px.y,1.0-px.y));
}
vec3 blink_gauss(vec2 p,float eye,float radius) {
    vec3 sum=vec3(0);float weight=0;
    for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++) {
        float w=exp(-float(x*x+y*y)*0.5);weight+=w;
        sum+=HOOKED_tex(blink_clamp(p+vec2(float(x)*0.5,float(y))*radius,eye)).rgb*w;
    }
    return sum/weight;
}
vec4 blink_render(vec4 base,vec2 uv,vec2 sample_pos,float eye,float right) {
    float lid=right>0.5 ? blink_lid_r:blink_lid_l;
    float adapt=right>0.5 ? blink_reopen_r:blink_reopen_l;
    // Exact bypass: no lookup, arithmetic, tint or extra resampling when open and settled.
    if(lid<=0.0 && adapt<=0.0)return base;
    float strength=vr_flat_sbs>0.5 ? blink_sbs_strength:1.0;
    float arch=blink_arc*lid*(1.0-pow(2.0*uv.x-1.0,2.0));
    float upper=1.0-blink_upper*lid-arch;
    float lower=blink_lower*lid+arch*0.25;
    float edge=min(upper-uv.y,uv.y-lower);
    float feather=max(blink_fringe,0.001);
    float covered=1.0-smoothstep(-feather,feather,edge);
    // Both eyes use the same taps, strictly clamped to their own source half.
    float meanY=0.0;
    for(int y=0;y<5;y++)for(int x=0;x<5;x++) {
        vec2 cp=vec2((eye+(float(x)+0.5)/5.0)*0.5,(float(y)+0.5)/5.0);
        if(blink_top_bottom>0.5)cp=vec2((float(x)+0.5)/5.0,(eye+(float(y)+0.5)/5.0)*0.5);
        if(vr_plain>0.5 || vr_flat_mono>0.5)cp=vec2((float(x)+0.5)/5.0,(float(y)+0.5)/5.0);
        vec3 c=HOOKED_tex(cp).rgb;
        meanY+=dot(c,vec3(0.2126,0.7152,0.0722))/25.0;
    }
    vec3 diffuse=blink_gauss(sample_pos,eye,blink_glow_radius);
    float diffuseY=dot(diffuse,vec3(0.2126,0.7152,0.0722));
    vec3 warm=vec3(blink_warm_r,blink_warm_g,blink_warm_b);
    warm/=dot(warm,vec3(0.2126,0.7152,0.0722));
    vec3 glow=warm*max(0.00001,meanY*blink_glow)*(0.8+0.2*diffuseY/max(meanY,0.00001));
    float radius=blink_slit_blur*max(lid,adapt);
    vec3 soft=blink_gauss(sample_pos,eye,radius);
    vec3 visible=mix(base.rgb,soft,strength);
    visible=mix(visible,vec3(meanY),blink_contrast*lid*strength);
    visible*=1.0+blink_lift*adapt*strength;
    // Vertical fringe smearing, no random flicker or geometry discontinuity.
    vec3 streak=(HOOKED_tex(blink_clamp(sample_pos+vec2(0,feather*.5),eye)).rgb+
                 HOOKED_tex(blink_clamp(sample_pos-vec2(0,feather*.5),eye)).rgb+soft)/3.0;
    float fringe=(1.0-smoothstep(0.0,feather*1.3,abs(edge)))*lid*strength;
    visible=mix(visible,streak*0.4,fringe);
    vec3 coveredColor=mix(glow,base.rgb,1.0-strength);
    return vec4(mix(visible,coveredColor,covered),base.a);
}

// Live fallback is one sloped plane. Texture brightness is NOT scene depth:
// modulating disparity by luma bends a flat textured surface into a wavy sheet.
// Learned prepared depth stays on the separate rendered-shot path.
float d3_depth(vec2 q,float plane) {
    // Depth is film-local, not the rejected-bar coordinate system.
    vec2 local=(q-vec2(vr_source_x,vr_source_y))/vec2(vr_source_w,vr_source_h);
    float prior=clamp(0.5+0.1*(local.y-0.5),0.0,1.0);
    float title_weight=clamp((D3_TITLE_tex(vec2(0.5)).r-0.60)/(0.80-0.60),0.0,1.0);
    return mix(prior,plane,title_weight);
}

//192c E1: both eyes use one interior source window, never edge extension
// or black support bands. Uniform crop retains source aspect and content scale.
vec2 d3_common_uv(vec2 uv,vec2 axis,float plane,float convergence) {
    vec2 support=(abs(vr_d3_gain)*(0.05+abs(0.5-plane))+abs(convergence)*0.25)*abs(axis);
    float margin=min(0.49,max(support.x,support.y));
    return (uv-vec2(0.5))*(1.0-2.0*margin)+vec2(0.5);
}
float d3_edge_coverage(vec2 uv,vec2 displaced,vec2 axis,float plane) {
    return any(lessThan(displaced,vec2(0.0))) || any(greaterThan(displaced,vec2(1.0))) ? 0.0:1.0;
}

// The output horizontal axis expressed in warped source coordinates. Adding source-x
// AFTER roll creates vertical eye disparity. Derivatives also follow the nonlinear preview warp.
vec2 flat_roll_offset(vec2 offset,float aspect,float roll) {
    float cr=cos(roll),sr=sin(roll);
    offset.x*=aspect;offset=mat2(cr,sr,-sr,cr)*offset;offset.x/=aspect;
    return offset;
}
// A flat film's head look-around uses only the crop exposed by approach.
// Manual pan remains explicit and unchanged. This is a viewport boundary,
// never an input confidence gate or a change to the spherical VR camera.
vec2 flat_tracked_offset(vec2 head,vec2 manual,float aspect,float roll) {
    float scale=max(0.1,1.0-vr_head_z)*tan(vr_fov*0.5)/tan(radians(135.0)*0.5);
    float margin=max(0.0,(1.0-scale)*0.5);
    return clamp(flat_roll_offset(head,aspect,roll),vec2(-margin),vec2(margin))
        +flat_roll_offset(manual,aspect,roll);
}
// 191c R3: synthetic disparity must lie along the interocular axis a=(cos th,
// sin th) in screen space, so the source-space axis is J*a with J=d(uv)/d(screen):
// axis = dFdx(uv)*cos(th) + dFdy(uv)*sin(th). The old dFdx(uv)-only axis is the
// screen-x direction: right at th=0, but it added e_v=d*sin(th) of vertical
// disparity under head roll. At th=0 this reduces exactly to dFdx(uv).
vec2 stereo_disparity_axis(vec2 uv,float aspect,float pixel_baseline) {
    float angle=vr_head_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);
    return (dFdx(uv)*cos(angle)+dFdy(uv)*sin(angle))*pixel_baseline;
}

//192b S1: GL y is up. Vision left-ear-down is negative roll; in cross-eye
// mode the left-side picture must move up. Parallel mode reverses the shift.
// No yaw, pitch, FOV, head distance or translation participates in fit/layout.
vec2 stereo_pair_uv(vec2 uv,float right,float eye_aspect,vec2 content) {
    float oa=vr_surface_w>0.0 && vr_surface_h>0.0 ? vr_surface_w/vr_surface_h:target_size.x/target_size.y;
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

float screen_coverage(vec2 uv) {
    vec2 aa=max(fwidth(uv),vec2(0.000001));
    vec2 lo=smoothstep(-aa*0.5,aa*0.5,uv);
    vec2 hi=vec2(1.0)-smoothstep(vec2(1.0)-aa*0.5,vec2(1.0)+aa*0.5,uv);
    return lo.x*lo.y*hi.x*hi.y;
}

// Apply AFTER eye partition: current pixels keep their eye and map onto that eye's fixed surface.
vec2 surface_uv(vec2 uv,vec2 actual) {
    vec2 anchor=vec2(vr_surface_w,vr_surface_h);
    if(anchor.x<=0.0 || anchor.y<=0.0)return uv;
    return (uv-vec2(0.5))*actual/anchor+vec2(0.5)+vec2(vr_surface_x,vr_surface_y);
}
// Outside-only background. Each tap stays inside its own original source eye.
// Wide inward taps remove edge streaks; the film footprint is never filtered.
float pack_gutter=0.0; // 1.0 only for pixels in the physical gap between the eyes
vec4 pack_surround(vec2 uv,float eye) {
    vec2 edge=clamp(uv,vec2(0.02),vec2(0.98));
    vec2 centre=mix(edge,vec2(0.5),0.18);
    vec4 color=vec4(0.0);float mass=0.0;
    for(int y=-2;y<=2;y++)for(int x=-2;x<=2;x++) {
        float weight=exp(-float(x*x+y*y)*0.5);
        vec2 p=clamp(centre+vec2(float(x),float(y))*0.045,vec2(0.002),vec2(0.998));
        p=vec2(vr_source_x,vr_source_y)+p*vec2(vr_source_w,vr_source_h);
        if(vr_source_layout>0.5 && vr_source_layout<2.5) {
            p=vr_source_layout>1.5 ? vec2(p.x,(p.y+eye)*0.5):vec2((p.x+eye)*0.5,p.y);
            vec2 lo=vec2(0.5)/HOOKED_size,hi=vec2(1.0)-lo;
            if(vr_source_layout>1.5) {lo.y=eye*0.5+lo.y;hi.y=(eye+1.0)*0.5-0.5/HOOKED_size.y;}
            else {lo.x=eye*0.5+lo.x;hi.x=(eye+1.0)*0.5-0.5/HOOKED_size.x;}
            p=clamp(p,lo,hi);
        }
        color+=HOOKED_tex(p)*weight;mass+=weight;
    }
    float distance=length(max(max(-uv,uv-vec2(1.0)),vec2(0.0)));
    float fade=(1.0-smoothstep(0.0,0.65,distance))*0.45;
    // Change the backing only. Original blurred RGB stays in its own channels.
    return vec4(color.rgb/max(mass,0.0001)*fade+vec3(vr_pk_surround_invert)*(1.0-fade),1.0);
}
vec4 pack_eye(vec2 uv, float right, float viewport_aspect) {
    vec2 output_uv=uv;
    vec2 lid_uv;
    float source_aspect = vr_aspect_override > 0.0 ? vr_aspect_override : vr_eye_aspect;
    if (source_aspect <= 0.0) source_aspect = HOOKED_size.x / HOOKED_size.y;
    source_aspect *= vr_crop_x * vr_source_w / (vr_crop_y * vr_source_h);
    vec2 content = vec2(1.0);
    if (source_aspect > viewport_aspect) content.y = viewport_aspect / source_aspect;
    else content.x = source_aspect / viewport_aspect;
    float ref_tan = tan(radians(ZOOM_REFERENCE_FOV_DEG) * 0.5);
    float excess = PARALLAX_CORRECTION_DISPARITY * (ref_tan / tan(vr_fov * 0.5) - 1.0) * PARALLAX_CORRECTION_STRENGTH;
    float total_shift = clamp(excess + vr_base_ipd + vr_ipd_nudge, -0.8, 0.8);
    if(vr_pack>2.5 && vr_pack<3.5)uv=stereo_pair_uv(uv,right,viewport_aspect,content);
    // IPD reserves only source content; distance must never change S1 pair fit.
    if(vr_source_layout>0.5 && vr_pack>2.5 && vr_pack<3.5)content*=1.0-abs(total_shift)*0.5;
    output_uv=uv;
    float zoom = exp2(-vr_manual_view / 60.0) * vr_pk_zoom;
    if (vr_pack > 3.5) {
        // vr180 preview: this eye canvas is an equirect-180 picture (lon/lat +-90 deg) of the flat film standing on a virtual screen of 75 deg width
        float lon = (uv.x - 0.5) * 3.14159265;
        float lat = (uv.y - 0.5) * 3.14159265;
        float th = tan(radians(37.5)) / zoom;
        float asp = max(source_aspect, 0.1);
        // Head pose drives this view too. Rotate the eye ray, then intersect the virtual screen at z=1 m from the tracked camera position.
        vec3 ray = vec3(sin(lon)*cos(lat),sin(lat),cos(lon)*cos(lat));
        float cr=cos(vr_roll), sr=sin(vr_roll);
        ray.xy=mat2(cr,sr,-sr,cr)*ray.xy;
        float cp=cos(vr_pitch), sp=sin(vr_pitch);
        ray.yz=mat2(cp,sp,-sp,cp)*ray.yz;
        float cy=cos(vr_yaw), sy=sin(vr_yaw);
        ray.xz=mat2(cy,-sy,sy,cy)*ray.xz;
        vec2 plane=vec2(vr_head_x,vr_head_y)+ray.xy*((max(0.1,1.0-vr_head_z)*tan(vr_fov*0.5)/tan(radians(135.0)*0.5))/max(ray.z,0.001));
        uv=vec2(0.5)+0.5*plane/vec2(th,th/asp);
        if (ray.z <= 0.001) uv = vec2(-1.0);   // s44: the abs(lon)>1.5 clause blacked the outer 4.1 deg columns of every eye canvas (the black wedges) — lon can never exceed +-90 deg here
    } else {
        uv = (uv - vec2(0.5)) / (content * zoom) + vec2(0.5);
        float cr=cos(-vr_roll), sr=sin(-vr_roll);
        uv-=vec2(0.5); uv.x*=source_aspect; uv=mat2(cr,sr,-sr,cr)*uv; uv.x/=source_aspect;
        // Restore the approved approach/retreat content zoom; S1 fit stays independent.
        uv=uv*(max(0.1,1.0-vr_head_z)*tan(vr_fov*0.5)/tan(radians(135.0)*0.5))+vec2(0.5);
        uv+=flat_tracked_offset((vec2(vr_yaw,vr_pitch))/1.5707963+vec2(-vr_head_x,vr_head_y)*0.5,vec2(vr_manual_yaw,-vr_manual_pitch)/1.5707963,source_aspect,-vr_roll);
    }
    if(vr_pack>3.5) uv += vec2(vr_manual_yaw, -vr_manual_pitch) / 1.5707963;
    // Keep normalized film support separate from final texture displacement.
    vec2 domain_axis=stereo_disparity_axis(uv,source_aspect,(vr_surface_w>0.0 ? vr_surface_w:target_size.x)*(vr_pack>2.5 ? 0.5:1.0));
    vec2 disparity_axis=domain_axis*vec2(vr_crop_x*vr_source_w,vr_crop_y*vr_source_h);
    // Convergence precedes coverage/clamp, so reset retains all original corners.
    lid_uv=vec2(uv.x,1.0-uv.y); // Same inverse film transform and frame edges as coverage.
    float coverage=screen_coverage(uv);
    vec2 surround_uv=uv;float film_coverage=coverage;
    if(vr_source_layout<0.5)uv=d3_common_uv(uv,domain_axis,vr_pk_conv,total_shift);
    if(vr_pack>2.5 && vr_pack<3.5)uv+=(right>0.5 ? -1.0:1.0)*total_shift*0.25*domain_axis;
    if(vr_source_layout>0.5) {coverage=screen_coverage(uv);lid_uv=vec2(uv.x,1.0-uv.y);}
    if (any(lessThan(uv,vec2(0))) || any(greaterThan(uv,vec2(1)))) {
        uv = clamp(uv, vec2(0.0), vec2(1.0));
    }
    uv = (uv - vec2(0.5)) * vec2(vr_crop_x,vr_crop_y) + vec2(0.5);
    uv = vec2(vr_source_x,vr_source_y) + uv * vec2(vr_source_w,vr_source_h);
    vec2 pixel = vec2(0.5) / HOOKED_size;
    if(!(vr_pack>2.5 && vr_pack<3.5))uv+=(right>0.5 ? -1.0:1.0)*total_shift*0.25*disparity_axis;
    float disp = vr_d3_gain * (d3_depth(uv,vr_pk_conv) - vr_pk_conv);
    float source_right=vr_swap_eyes>0.5 ? 1.0-right : right;
    vec2 displaced=uv+(source_right > 0.5 ? -1.0 : 1.0)*disp*disparity_axis;
    if(vr_source_layout<0.5) coverage*=d3_edge_coverage(uv,displaced,disparity_axis,vr_pk_conv);
    vec2 sample_pos=displaced; //192b: synthetic border fill removed; baked paths below are unchanged
    if(vr_source_layout>0.5 && vr_source_layout<2.5) {
        sample_pos=vr_source_layout>1.5 ? vec2(uv.x,(uv.y+source_right)*0.5):vec2((uv.x+source_right)*0.5,uv.y);
    }
    if(vr_source_layout>2.5) {
        // Native spherical source: bake no new baseline, preserve original eye pairing.
        vec2 p=output_uv*2.0-1.0;
        vec3 ray;
        if(vr_pack>3.5) {float lon=p.x*1.5707963268,lat=p.y*1.5707963268;ray=vec3(sin(lon)*cos(lat),sin(lat),cos(lon)*cos(lat));}
        else {ray=normalize(vec3(p.x*tan(vr_fov*.5),p.y*tan(vr_fov*.5)/viewport_aspect,1));}
        float cr=cos(vr_roll),sr=sin(vr_roll);ray.xy=mat2(cr,sr,-sr,cr)*ray.xy;
        float cp=cos(vr_pitch),sp=sin(vr_pitch);ray.yz=mat2(cp,sp,-sp,cp)*ray.yz;
        float cy=cos(vr_yaw),sy=sin(vr_yaw);ray.xz=mat2(cy,-sy,sy,cy)*ray.xz;
        float lon=atan(ray.x,ray.z),lat=asin(clamp(ray.y,-1.0,1.0));
        bool full=vr_source_layout>4.5;
        vec2 native_uv=vec2(lon/(full ? 6.2831853072:3.1415926536)+.5,lat/3.1415926536+.5);
        coverage=full ? 1.0:screen_coverage(native_uv);
        native_uv.x=full ? fract(native_uv.x):clamp(native_uv.x,0.0,1.0);
        native_uv.y=clamp(native_uv.y,pixel.y,1.0-pixel.y);
        bool tb=abs(vr_source_layout-4.0)<.1 || vr_source_layout>5.5;
        sample_pos=abs(vr_source_layout-5.0)<.1 ? native_uv:(tb ? vec2(native_uv.x,(native_uv.y+source_right)*.5):vec2((native_uv.x+source_right)*.5,native_uv.y));
    }
    vec4 background=vec4(vec3(vr_pk_surround_invert),1.0);
    // The gap between the eyes and every partial-coverage pixel (film edge, depth
    // edge) take the same surround as the outside. Black or white backing there
    // drew a thin seam, most visible on Soft and on inverted surround.
    coverage*=1.0-pack_gutter;
    if(vr_pk_soft>0.5 && (film_coverage<=0.0 || coverage<1.0) && vr_source_layout<2.5)
        background=pack_surround(surround_uv,source_right);
    return mix(background,blink_render(HOOKED_tex(vr_source_layout<2.5 ? blink_clamp(sample_pos,source_right):sample_pos),lid_uv,sample_pos,right,right),coverage);
}

vec4 hook() {
    // MAIN hook with WIDTH/HEIGHT OUTPUT.w/h: this pass IS the output-sized pass and HOOKED_tex()
    // samples the original source texture, so the reprojection is the only resample (block 182 1.1).
    // HOOKED_size is the SOURCE size here, so the output size comes from target_size.
    vec2 actual_size=target_size;
    vec2 out_size = vr_surface_w>0.0 && vr_surface_h>0.0 ? vec2(vr_surface_w,vr_surface_h) : actual_size;
    vec2 surface_pos=surface_uv(HOOKED_pos,actual_size);
    if(vr_plain>0.5) {
        vec2 uv=surface_pos-vec2(0.5);
        // Flat screen backward sampling must use the opposite roll to the tracked pose.
        float cr=cos(-vr_roll),sr=sin(-vr_roll);
        float asp=out_size.x/out_size.y;
        //194q film aspect lock: the film keeps its own aspect inside the surface (bars
        // outside), so head tracking can never stretch it to the window/surface aspect.
        // vr_plain_aspect=0 (unknown) keeps the old full-surface mapping.
        vec2 plain_content=vec2(1.0);
        if(vr_plain_aspect>0.0) {
            if(vr_plain_aspect>asp)plain_content.y=asp/vr_plain_aspect;else plain_content.x=vr_plain_aspect/asp;
        }
        //194i plain-only automatic rotate fit. Tilt alone retains all source
        // corners; tracked distance and explicit manual FOV remain multipliers.
        // 194q: bound the rotated FILM rectangle (not the surface) so tilt never crops it,
        // The published frame fit (same rule, Lua film_frame_snapshot) is used as given.
        float film_w=plain_content.x*asp,film_h=plain_content.y;
        float rotate_bound=max((abs(cr)*film_w+abs(sr)*film_h)/asp,abs(sr)*film_w+abs(cr)*film_h);
        uv*=vr_frame_fit>0.0 ? 1.0/vr_frame_fit:max(1.0,rotate_bound);
        uv.x*=asp; uv=mat2(cr,sr,-sr,cr)*uv; uv.x/=asp;
        uv/=plain_content; // film-normalised after the physical rotation
        uv=uv*(max(0.1,1.0-vr_head_z)*tan(vr_fov*0.5)/tan(radians(135.0)*0.5))+vec2(0.5);
        uv+=flat_tracked_offset(vec2(vr_yaw,vr_pitch)/1.5707963+vec2(-vr_head_x,vr_head_y)*0.5,vec2(0.0),asp,-vr_roll);
        float coverage=screen_coverage(uv);
        uv=clamp(uv,vec2(0),vec2(1));
        return mix(vec4(0,0,0,1),blink_render(HOOKED_tex(blink_clamp(vec2(vr_source_x,vr_source_y)+uv*vec2(vr_source_w,vr_source_h),0.0)),vec2(uv.x,1.0-uv.y),vec2(vr_source_x,vr_source_y)+uv*vec2(vr_source_w,vr_source_h),0.0,0.0),coverage);
    }
    if (vr_source_layout < 2.5 && vr_pack > 0.5) {
        vec2 pp = HOOKED_pos;
        float oa = out_size.x / out_size.y;
        if (vr_pack < 1.5) {
            float pr = step(0.5, pp.y);
            return pack_eye(surface_uv(vec2(pp.x, fract(pp.y * 2.0)),actual_size), pr, oa * 2.0);
        }
        if (vr_pack > 2.5) {
            //192b automatic gutter: same live physical gap as the flat/native path and chrome.
            float le=0.5-vr_gap_frac*0.25,rs=0.5+vr_gap_frac*0.25;
            // Evaluate derivatives through the gutter. Early return made the last
            // visible quad undefined and grew a black band beyond the physical gap.
            vec2 split_pos=stereo_partition(pp,oa);
            float ps=step(0.5,split_pos.x);
            vec2 eye_uv=vec2(ps>0.5 ? (pp.x-rs)/(1.0-rs):pp.x/le,pp.y);
            // The gap shows the eye's own surround (Black, White or Soft), never a fixed black.
            pack_gutter=(split_pos.x>=le && split_pos.x<rs) ? 1.0:0.0;
            return pack_eye(surface_uv(eye_uv,actual_size), ps, oa * le);
        }
        vec3 pl = pack_eye(surface_uv(pp,actual_size), 0.0, oa).rgb;
        vec3 pq = pack_eye(surface_uv(pp,actual_size), 1.0, oa).rgb;
        return vec4(pl.r, pq.g, pq.b, 1.0);
    }
    if (vr_flat_sbs > 0.5) {
        // Flat stereo is a pair of rectilinear images, never equirectangular sphere data.
        // 191c R2: roll-compensated eye partition, same construction as the VR path
        // below. The partition line passes through the screen centre perpendicular to
        // the interocular axis a=(cos th, sin th): the eye centres sit at
        // C -/+ (S/2)*a and each eye viewport is rotated by the head roll th, so the
        // viewport-centre offset lies along a and e_v=(p_R-p_L).a_perp stays 0 (R0).
        // The picture orientation is untouched (world-fixed horizon, owner 5 Nov):
        // the rotated eye frame carries the roll that the removed per-eye inverse
        // roll used to apply. At th=0 every formula below reduces exactly to the
        // pre-191c screen-aligned split (cos=1, sin=0, pos=HOOKED_pos).
        float half_gap = vr_gap_frac * 0.25;
        float le = 0.5 - half_gap, rs = 0.5 + half_gap;
        vec2 pos=HOOKED_pos;
        vec2 split_pos=stereo_partition(pos,out_size.x/out_size.y);
        if (split_pos.x >= le && split_pos.x < rs) return vec4(0,0,0,1);
        float right = step(0.5, split_pos.x);
        vec2 uv = vec2(right > 0.5 ? (pos.x-rs)/(1.0-rs) : pos.x/le, pos.y);
        uv=surface_uv(uv,actual_size);
        float viewport_aspect = out_size.x * le / out_size.y;
        float source_aspect = vr_aspect_override > 0.0 ? vr_aspect_override : vr_eye_aspect;
        if (source_aspect <= 0.0) source_aspect = (HOOKED_size.x * (vr_flat_mono > 0.5 ? 1.0 : 0.5)) / HOOKED_size.y;
        source_aspect *= vr_crop_x * vr_source_w / (vr_crop_y * vr_source_h);
        vec2 content = vec2(1.0);
        if (source_aspect > viewport_aspect) content.y = viewport_aspect / source_aspect;
        else content.x = source_aspect / viewport_aspect;
        // Keep the approved distance model's exact total shift; do not reinterpret the anatomical dial.
        float ref_tan = tan(radians(ZOOM_REFERENCE_FOV_DEG) * 0.5);
        float excess = PARALLAX_CORRECTION_DISPARITY * (ref_tan / tan(vr_fov * 0.5) - 1.0) * PARALLAX_CORRECTION_STRENGTH;
        float total_shift = clamp(excess + vr_base_ipd + vr_ipd_nudge, -0.8, 0.8);
        uv=stereo_pair_uv(uv,right,viewport_aspect,content);
        if(vr_flat_mono<0.5)content*=1.0-abs(total_shift)*0.5;
        float zoom = exp2(-vr_manual_view / 60.0);
        uv = (uv - vec2(0.5)) / (content * zoom);
        // Native SBS / half-SBS / top-bottom share the tracked virtual screen, not a frozen UV path.
        // 191c R2: the per-eye inverse roll ("independently in each eye") is gone -
        // the roll-compensated eye frame at the partition above already expresses
        // this pixel in the rolled viewport, so the sampled picture keeps its
        // world-fixed orientation without a second, eye-local rotation.
        float cr=cos(-vr_roll),sr=sin(-vr_roll);
        uv.x*=source_aspect;uv=mat2(cr,sr,-sr,cr)*uv;uv.x/=source_aspect;
        // Distance and explicit FOV change content scale, never S1 pair layout.
        uv=uv*(max(0.1,1.0-vr_head_z)*tan(vr_fov*0.5)/tan(radians(135.0)*0.5))+vec2(0.5);
        uv += flat_tracked_offset((vec2(vr_yaw,vr_pitch))/1.5707963+vec2(-vr_head_x,vr_head_y)*0.5,vec2(vr_manual_yaw,-vr_manual_pitch)/1.5707963,source_aspect,-vr_roll);
        // Keep normalized film support separate from final texture displacement.
        vec2 domain_axis=stereo_disparity_axis(uv,source_aspect,viewport_aspect*out_size.y);
        vec2 disparity_axis=domain_axis*vec2(vr_crop_x*vr_source_w,vr_crop_y*vr_source_h);
        // Keep the approved IPD/distance convergence, now along the eye axis;
        // convergence must not resize or move the pair layout.
        vec2 lid_uv=uv; // Film-local frame before depth sampling or source crop.
        float coverage=screen_coverage(uv);
        if(vr_flat_mono>0.5)uv=d3_common_uv(uv,domain_axis,0.5,total_shift);
        uv+=(right>0.5 ? -1.0:1.0)*total_shift*0.25*domain_axis;
        if(vr_flat_mono<0.5) {coverage=screen_coverage(uv);lid_uv=uv;}
        uv=clamp(uv,vec2(0),vec2(1));
        uv = (uv - vec2(0.5)) * vec2(vr_crop_x,vr_crop_y) + vec2(0.5);
        uv=vec2(vr_source_x,vr_source_y)+uv*vec2(vr_source_w,vr_source_h);
        float src_eye = vr_swap_eyes > 0.5 ? 1.0-right : right;
        vec2 sample_pos = vec2((uv.x + src_eye)*0.5, uv.y);
        vec2 pixel = vec2(0.5) / HOOKED_size;
        sample_pos.x = clamp(sample_pos.x, src_eye*0.5+pixel.x, (src_eye+1.0)*0.5-pixel.x);
        if(blink_top_bottom>0.5) sample_pos=vec2(uv.x,(uv.y+src_eye)*0.5);
        // 2D film -> synthetic stereo: both eyes sample the whole frame, shifted opposite ways by depth (backward warp: no holes, no inpaint).
        if(vr_flat_mono>0.5) {
            float disp=vr_d3_gain*(d3_depth(uv,0.5)-0.5);
            vec2 displaced=uv+(right>0.5 ? -1.0 : 1.0)*disp*disparity_axis;
            coverage*=d3_edge_coverage(uv,displaced,disparity_axis,0.5);
            sample_pos=displaced; // uncovered border is black, never stretched
        }
        return mix(vec4(0,0,0,1),blink_render(HOOKED_tex(blink_clamp(sample_pos,src_eye)),vec2(lid_uv.x,1.0-lid_uv.y),sample_pos,src_eye,right),coverage);
    }

    // A flat source can never fall through into the native camera-ray path.
    if(vr_source_layout<=2.5)return HOOKED_tex(HOOKED_pos);
    // ── Roll-compensated eye partition ──
    // Native viewports stay fixed; roll exists only in the camera ray.
    // Everything below this point that reads surface_pos (the physical
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

    // vr_fov is the horizontal fov; the vertical fov follows the eye's own aspect (unchanged from before the
    // full-fill change, so filling the drawable does not rescale the image).
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
    float eye_aspect = vr_aspect_override > 0.0 ? vr_aspect_override : (out_size.x * 0.5) / out_size.y;
    eye_aspect *= vr_crop_y / vr_crop_x;

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
    eye_uv=surface_uv(eye_uv,actual_size);
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

    ndc_x *= vr_crop_x; ndc_y *= vr_crop_y; // menu viewport crop, never packed-eye seam

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
    // Blink composes on the UNMASKED image first; the peripheral darken and the strip
    // fade apply LAST so the black fade always stays in front of the blink (owner
    // 2026-11-06: the fade must never disappear during a blink, the blink sits behind
    // it). With lid and reopen at zero, blink_render early-returns its base untouched,
    // so the non-blink output is byte-identical to the old order.
    vec4 blinked = blink_render(blurred_color, vec2(fract(eye_pos.x*2.0),1.0-eye_pos.y),native_source_uv(src_u,v),src_right_half ? 1.0:0.0,is_right_eye);
    float darken_amount = PERIPHERAL_VIGNETTE_DARKEN_STRENGTH * peripheral_factor;
    vec4 peripheral_color = mix(blinked, vec4(0.0, 0.0, 0.0, 1.0), darken_amount);

    // Fade toward the black strip inside the blurred edge band
    // (strip_blend < 1.0); everywhere else strip_blend is exactly 1.0
    // so this mix is a no-op and peripheral_color passes through
    return mix(vec4(0.0, 0.0, 0.0, 1.0), peripheral_color, strip_blend);
}
