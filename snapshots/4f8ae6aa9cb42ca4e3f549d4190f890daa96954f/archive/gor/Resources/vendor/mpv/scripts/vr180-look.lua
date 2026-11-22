-- ================================================================
--  vr180-look.lua - VR180 SBS look-around
--  Owns: reprojection shader, yaw, pitch and FOV state
--  Answers: I40 · TRAP-09
--  Contract: keep state and code paths unchanged
-- ================================================================

-- ================================================================
--  1. STATE
-- ================================================================
local tools_active = false
local enabled             = false     -- Swift-side VR mode switch. Default OFF: shader
                                      -- must never be resident during ordinary playback.

local vr_f                = 45.0      -- global vr factor

local vr_yaw              = 0.0       -- radians, 0 = forward
local vr_pitch            = 0.0       -- radians, clamped to avoid gimbal flip past the poles
local vr_fov              = 135.0     -- degrees, horizontal FOV of the virtual pinhole camera
-- Manual view offsets are separate from camera pose. Camera frames must not erase a menu/gesture.
local manual_yaw, manual_pitch, manual_fov, manual_roll = 0, 0, 0, 0
local flat_sbs = false
local flat_tb = false
local source_layout = 0 --0 mono,1 flatSBS,2 flatTB,3 VR180SBS,4 VR180TB,5 VR360mono,6 VR360TB
local flat_mono = false   -- "flat-2d3d": one ordinary 2D frame, each eye displaced by a synthetic depth prior (default OFF, menu choice)
local flat_pack = 0       -- 3D menu preview layout for flat-2d3d: 0 original side by side path (unchanged), 1 top/bottom, 2 anaglyph, 3 side by side through the pack variant, 4 vr180 (equirect-180 warp, side by side)
local pk_surround_invert = 0.0 -- default-off white backing; never invert source RGB
local pk_conv, pk_zoom, pk_soft = 0.5, 1.0, 1.0   -- screen depth (depth on the screen plane), screen size (film zoom), surround (1 = edge fill, 0 = black)
-- Shader compile probe contract (tools/vr_pack_probe.py): script-opt vr180-look-vr_pack = off|tb|anaglyph|sbs forces the layout (sbs = the unchanged side by side path), and
-- the marker file written by a failed probe disables every pack layout (vr_pack=off) before any pack shader is built.
local vr_pack_blocked = false
local function vr_pack_check_marker()
    local path = os.getenv("GOR_VR_SAFE_MARKER") or ((os.getenv("HOME") or "") .. "/Library/Application Support/gor/vr-pack-safe")
    local f = io.open(path, "r")
    if f then f:close(); vr_pack_blocked = true else vr_pack_blocked = false end
end
vr_pack_check_marker()
local vr_pack_opt = ({off = 0, tb = 1, anaglyph = 2, sbs = 3})[(mp.get_opt and mp.get_opt("vr180-look-vr_pack")) or ""]
local vr_pack_forced = vr_pack_opt ~= nil and vr_pack_opt > 0 and not vr_pack_blocked
if vr_pack_forced then flat_pack = vr_pack_opt end
local D3_GAIN = 0.02      -- max per-eye shift = D3_GAIN/2 of frame width (2% total disparity at the extremes)
local flat_eye_aspect = 0
local plan_lock = nil   -- s36: set while a rendered-shot file plays; {enabled=bool}. The player's auto-detect messages are ignored meanwhile (see vr180-look-plan-lock)
local vr_roll             = 0.0       -- radians, 0 = level. Head-tracking only (Phase 2) --
                                      -- no gesture currently drives this, so it has no
                                      -- clamp of its own: unlike vr_pitch (gimbal limit)

local VR_PITCH_LIMIT_DEG  = 85.0
local VR_PITCH_DOWN_LIMIT_DEG = 85.0 -- positive pitch looks down; keep a five-degree margin from the camera pole
local VR_YAW_CLAMP        = vr_f / 4
local VR_FOV_MIN          = vr_f / 2
local VR_FOV_MAX          = vr_f * 3.5
-- Spherical FOV rails must not permanently hide a tilted flat film's corners.
-- Flat zoom-out remains finite below180 degrees; source sampling/crop stays untouched.
local function vr_fov_max() return source_layout<3 and 179.0 or VR_FOV_MAX end

-- Width of the soft blur/gradient on EACH edge of the physical gap
-- below, in the SAME unit as VR_PHYSICAL_GAP_FRAC (fraction of one
-- eye's width). Still purely a color fade at the edge where each
local VR_EYE_GAP_BLUR_FRAC = 0.5

-- ── Physical gap between the two eyes REPURPOSED from the o ──
--    VR_EYE_GAP_FRAC, which used to control a color-only black strip
--    painted OVER the joint between the two eyes at the existing 0.5
--    center boundary -- that strip's job is now fully covered by
-- ORIGINAL is_right_eye/eye_uv computation with no gap at all --
-- confirmed by direct calculation before writing this, not assumed).
local VR_PHYSICAL_GAP_FRAC = 0.0125

-- ── Peripheral-vision vignette mimics falloff in acuity/foc ──
--    corners included) ─────────────────────────────────────────────
-- This is INDEPENDENT of the eye-gap strip above: the strip is a
-- divider AT the 0.5 boundary between the two eyes; this vignette is a
-- falloff from EACH eye's own center toward that eye's own outer edges
local VR_PERIPHERAL_VIGNETTE_MODE = 1

-- Reference FOV (degrees) that mode 2 above normalizes against. Mode 1
-- mode 2 diverges from mode 1 as vr_fov moves away from it (weaker
local VR_PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG = 90.0

-- Radial distance (0.0 = dead center of the eye, 1.0 = the eye's own
-- corner) at which the vignette effect BEGINS. Below this, the pixel
local VR_PERIPHERAL_VIGNETTE_START_FRAC = 0.25

-- How much DARKENING is applied at the outer edge/corner (radial
-- distance 1.0), as a fraction from 0.0 (no darkening at all, pure
-- blur-only peripheral effect) to 1.0 (fully black at the corner).
local VR_PERIPHERAL_VIGNETTE_DARKEN_STRENGTH = 1.0

-- How much BLUR (real defocus, averaging neighboring source pixels --
local VR_PERIPHERAL_VIGNETTE_BLUR_STRENGTH = 0.006 / 4

-- Number of texture taps used for the peripheral blur: 1 center tap
-- plus a ring of (N-1) taps spaced evenly around it. Odd numbers >= 5
-- recommended -- 5 is a cheap, visible-enough ring; 9 is smoother but
local VR_PERIPHERAL_VIGNETTE_BLUR_SAMPLES = 9

-- ── Zoom-bleed correction pinch-zoom / narrow-vrfov ──
-- Two INDEPENDENT correction mechanisms for the crossed-eye bleed that
-- appears when vr_fov narrows (pinching in). Independent on purpose --
-- each has its own enable flag and strength dial, so either can be
local VR_ZOOM_COMPENSATION_ENABLED = true

-- Fraction of full screen height each eye uses AT REST (vr_fov ==
-- ZOOM_REFERENCE_FOV_DEG, STRENGTH == 1.0) -- this is a taste/comfort
-- question, not something derivable from geometry, so 0.7 below is an
local VR_ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC = 0.0075

-- vr_fov -- identical to how this shader behaved before this
-- mechanism existed at all) up to 1.0 = the full grow-toward-max
-- curve described above, bottoming out at
local VR_ZOOM_COMPENSATION_STRENGTH = 0.0075

-- Shared by ZOOM_COMPENSATION and PARALLAX_CORRECTION below -- both
-- represent the same physical fact (the FOV at which the footage
-- needs zero correction, i.e. this shader's resting/un-zoomed FOV),
local VR_ZOOM_REFERENCE_FOV_DEG = 90.0

-- MECHANISM B -- PARALLAX_CORRECTION (theoretical, complementary to A):
-- separate from the frame-width bleed above, if the source footage
-- carries its own baked-in stereo parallax (genuine left/right
local VR_PARALLAX_CORRECTION_ENABLED = true

-- Same 0.0..1.0 role as VR_ZOOM_COMPENSATION_STRENGTH above, applied
local VR_PARALLAX_CORRECTION_STRENGTH = 0.4

-- VR_ZOOM_REFERENCE_FOV_DEG, in the same normalized NDC-fraction unit
-- ndc_x itself uses (-1..1 across one eye's full width). This is a
local VR_PARALLAX_CORRECTION_DISPARITY = VR_PARALLAX_CORRECTION_STRENGTH * -1

-- ── Virtual IPD ──
-- Architecturally the same shift PARALLAX_CORRECTION_DISPARITY above
-- already performs (a per-eye, eye_sign-flipped horizontal ray shift
-- into ndc_x) but keyed to a DIFFERENT physical quantity: not "how
local base_ipd  = 0.0
local ipd_nudge = 0.0

-- ── Head position / motion parallax ──
-- Everything above (vr_yaw/vr_pitch/vr_roll) rotates the ray but
-- always casts it from a fixed origin -- equivalent to a camera that
-- can only swivel in place. Real parallax needs the ORIGIN to move
local vr_head_x = 0.0
local vr_head_y = 0.0
local vr_head_z = 0.0
-- Cross-eye order (block 180 3a). 0 = default order (left half of the SBS frame
-- feeds the output-left eye); 1 = swapped. Pushed as the vr_swap_eyes PARAM.
local vr_swap_eyes = 1.0
local viewer_cross_eye,calibration_on=0,0

-- Radius, in meters, of the imaginary sphere VR180 equirect content
-- video carries no real depth -- every pixel is painted onto one
-- nothing in the footage itself to measure this against -- but this
-- number is now reasoned from the actual offset it needs to read
-- against, not picked independently of it the way 10.0 was.
local VR_SPHERE_RADIUS_METERS = 1.7

-- ── Pure look override ──
-- When true, forces VR_PHYSICAL_GAP_FRAC, VR_EYE_GAP_BLUR_FRAC,
-- VR_PERIPHERAL_VIGNETTE_DARKEN_STRENGTH, and
-- VR_PERIPHERAL_VIGNETTE_BLUR_STRENGTH to behave as if they were all
-- no peripheral vignette, regardless of what those four constants
-- above are actually set to. Their own values are left untouched (so
-- flipping this back to false immediately restores whatever they were
local VR_PURE_LOOK_ENABLED = false

local math_max, math_min = math.max, math.min
local function clamp(v, lo, hi) return math_max(lo, math_min(hi, v)) end
local function deg2rad(d) return d * math.pi / 180.0 end

-- ================================================================
--  2. SHADER FILE PLUMBING
-- ================================================================
--     (gr_shader_dir / gr_rewrite_shader / gr_apply_shader_list), used
--     here ONLY for the one-time enable-time write+add. The GLSL text
--     never changes while enabled, so unlike photon-grain this never

local function vr_shader_dir()
    local dir = mp.get_property("config-dir")
    if not dir then return nil end
    return dir:gsub("[/\\]+$", "") .. "/shader/"
end

local vr_shader_paths = nil
local vr_shader_epoch = 0
local vr_active_slot = 1

local function vr_ensure_paths()
    if vr_shader_paths then return vr_shader_paths end
    local dir = vr_shader_dir()
    if not dir then return nil end
    dir=dir.."epoch-"..tostring(vr_shader_epoch).."/"
    os.execute(string.format('mkdir -p "%s" 2>/dev/null || mkdir "%s" >nul 2>nul', dir, dir))
    vr_shader_paths = { dir .. "vr180-look-shader-a.glsl", dir .. "vr180-look-shader-b.glsl" }
    return vr_shader_paths
end

-- Startup: delete both slot files so a stale shader from a previous
-- gor session never bleeds into this one (same reasoning as
-- photon-grain.lua's gr_delete_slot_files). Always freshly written
local function vr_delete_slot_files()
    -- A previous PASS stops being evidence as soon as its files are retired.
    -- IPC readers may run between this invalidation and a completed repair.
    mp.set_property_native("user-data/vr180-look/installed-shader",{verdict="PENDING",expected="unverified",entry="none",sha256="none",variant="none"})
    local dir = vr_shader_dir()
    if not dir then return end
    os.remove(dir .. "vr180-look-shader-a.glsl")
    os.remove(dir .. "vr180-look-shader-b.glsl")
    if vr_shader_paths then
        for _,path in ipairs(vr_shader_paths) do os.remove(path) end
        local old=vr_shader_paths[1]:match("^(.*)/[^/]+$");if old then os.remove(old) end
    end
    vr_shader_paths=nil;vr_shader_epoch=vr_shader_epoch+1
end
vr_delete_slot_files()

local vr_shader_written = false
local vr_shader_variant = nil
local vr_tune_defaults = {}
local vr_select_shader
local vr_full_fit
local smooth_fit=nil
local vr_shader_receipt
local vr_pending_shader_list = nil

-- The EFFECTIVE physical gap (the value baked into the shader) is published for the app's chrome
-- replication so the Swift layout and the shader share one number: user-data/vr180-look/physical-gap-frac
-- (decimal string). Published at init and on every shader write; a future live-tune path must call it too.
local vr_published_gap = nil
local function vr_publish_gap()
    if vr_published_gap == nil then return end
    mp.set_property("user-data/vr180-look/physical-gap-frac", string.format("%.6f", vr_published_gap))
end

local function vr_write_shader_once()
    if vr_shader_written then return true end
    if type(VR180_LOOK_SOURCE)~="string" then return false end
    local paths = vr_ensure_paths()
    if not paths then return false end
    local path = paths[vr_active_slot]
    local f = io.open(path, "w")
    if not f then mp.msg.error("vr180-look: failed to write shader: " .. path); return false end
    local wrote, write_error = f:write(VR180_LOOK_SOURCE)
    local closed, close_error = f:close()
    if not wrote or not closed then
        mp.msg.error("vr180-look: shader write/close failed: " .. tostring(write_error or close_error))
        return false
    end
    vr_shader_written = true
    vr_publish_gap()
    mp.msg.info("vr180-look v1.3: shader written -> " .. path)
    return true
end

-- glsl-shaders ownership contract (same as photon-grain.lua): only
-- touch our own paths, never disturb entries other scripts (e.g.
-- photon-grain itself) have added.
local function vr_ensure_glsl_list_sane(shaders)
    local paths = vr_ensure_paths()
    if not paths then return shaders end
    local seen_a, seen_b, out = false, false, {}
    for _, p in ipairs(shaders) do
        if p == paths[1] then if not seen_a then table.insert(out, p); seen_a = true end
        elseif p == paths[2] then if not seen_b then table.insert(out, p); seen_b = true end
        else table.insert(out, p) end
    end
    return out
end

local function vr_shader_in_list()
    local paths = vr_ensure_paths()
    if not paths then return false end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    for _, p in ipairs(shaders) do
        if p == paths[1] or p == paths[2] then return true end
    end
    return false
end

-- Adds our shader to glsl-shaders. Called once on enable (and by the
-- self-heal timer in part 6 if something else clobbers the property
-- list out from under us). Does NOT alternate slots on every call the
local function vr_apply_shader_list()
    local paths = vr_ensure_paths()
    if not paths then return end
    if not vr_write_shader_once() then return end
    if vr_shader_in_list() then return end
    local path = paths[vr_active_slot]
    local shaders = vr_ensure_glsl_list_sane(mp.get_property_native("glsl-shaders") or {})
    local filtered = {}
    for _, p in ipairs(shaders) do
        if p ~= path then table.insert(filtered, p) end
    end
    table.insert(filtered, path)
    mp.set_property_native("glsl-shaders", filtered)
end

-- Removes our shader from glsl-shaders entirely. This is the gate that
-- keeps the shader from ever running on ordinary, non-VR footage: on
-- disable, the shader isn't just told to no-op internally, it's not
local function vr_remove_shader()
    if not vr_shader_paths then return end
    local shaders = mp.get_property_native("glsl-shaders") or {}
    local filtered, changed = {}, false
    for _, p in ipairs(shaders) do
        if p == vr_shader_paths[1] or p == vr_shader_paths[2] then changed = true
        else table.insert(filtered, p) end
    end
    if changed then mp.set_property_native("glsl-shaders", filtered) end
end

-- ================================================================
--  3. LIVE UNIFORM PUSH
-- ================================================================
--     recompile. This is the part that actually runs at gesture
--     speed. Called on every yaw/pitch/fov script-message while
--     enabled; safe to call at high frequency (many times/sec during

-- ── Distance-aware separation clamp (block 182 2) ──
-- All of this is Lua so the real mpv can test it with synthetic distances. Swift sends the filtered face
-- distance d_mm = f_px * 140 / w_box_px (one-euro channel, same heavy tau as the fov-from-box) or "none" plus a
-- reason, and the display's mm per pixel. Rule (owner, block 182): the RENDERED horizontal separation total
-- (the same quantity the shader sums: parallax excess + base + head-lean nudge, in ndc units) is converted to mm
-- with the eye viewport width, and capped so the vergence demand 2*atan((ipd+s)/(2d)) never exceeds its value at
-- d = 500 mm:  s_total <= min(s_today, (d/500)*(ipd_eff + s_today) - ipd_eff),  ipd_eff = 63 + offset (offset = the
-- ipd dial in mm), s_today = the separation today's pipeline renders at this instant (dynamic: parallax excess at
-- the current fov and the head-lean nudge; constant: today's base_ipd default, 0.0 normalized = 0 mm).
-- A negative s is allowed (it reduces below zero separation, i.e. converges the eyes); if the resulting shift
-- would exceed the shader's own +-0.8 clamp it is reported as infeasible, never as a met cap.
local blink_target = {0,0}
local blink_lids = {0,0}
local blink_from = {0,0}
local blink_at = {0,0}
local blink_reopen = {-100,-100}
local blink_uncertain = false
local blink_analog = true   -- gor.vr.blinkAnalog (Swift sends vr180-look-set-blink-analog): continuous lid, linear 60 ms close, shader variant held while blink measures
local blink_measurement_at = nil
local vr_tune = {}   -- live-tunable former #defines, filled below where the effective defaults exist
local VR_FACE_WIDTH_MM          = 140.0      -- owner block 182: adult face-width constant (used by Swift for d)
local VR_DEFAULT_IPD_MM         = 63.0       -- owner block 182
local VR_REFERENCE_DISTANCE_MM  = 500.0      -- owner block 182: the cap is today's value at this distance
local VR_DISTANCE_HOLD_S        = 2.0        -- owner block 182: no face -> hold the last d this long
-- Today's separation, converted to mm once. Today's rendered shift is clamp(parallax_excess + base_ipd + head_nudge);
-- base_ipd's default is 0.0 (NDC, session-only: Swift currentBaseIPD = 0.0, Lua base_ipd = 0.0), so its mm value
-- is 0.0 * the M1 full-screen eye half-width = 0 mm. The excess and nudge terms are today's own rendered terms and
-- stay computed per frame (they are not part of the base constant); the dial is now the ipd offset in mm.
local VR_TODAY_BASE_IPD_NDC     = 0.0
local VR_TODAY_BASE_IPD_MM      = VR_TODAY_BASE_IPD_NDC * (2560.0 / 2.0 / 2.0) * (25.4 / 227.0)
-- MacBook Air M1 13.3in panel: 2560 px at 227 ppi (Apple, support.apple.com/en-us/111883): 25.4/227 mm per px.
local VR_MACBOOK_MM_PER_PX      = 25.4 / 227.0
local VR_SHADER_SHIFT_LIMIT     = 0.8        -- the shader's clamp(combined_horizontal_shift, -0.8, 0.8)
local dist_in_d, dist_in_reason, dist_in_at, dist_in_mmpx = nil, "no-input", nil, nil
local vr_ipd_applied_base = nil              -- the vr_base_ipd value actually pushed (nil = dial value as is)
local vr_distance_trace = ""

local ipd_offset_mm = nil   -- canonical dial (block 182 2): offset in mm on the 63 mm default; base_ipd is derived from it
local function vr_apply_ipd_mm()
    if not ipd_offset_mm then return end
    local osdw = mp.get_property_number("osd-width") or 0
    if osdw <= 0 then return end
    local mmpx = (dist_in_mmpx and dist_in_mmpx > 0) and dist_in_mmpx or VR_MACBOOK_MM_PER_PX
    base_ipd = ipd_offset_mm / ((osdw / 2.0) * mmpx / 2.0)
end
-- Block182 semantics also apply before the first camera sample: dial is anatomical IPD, not screen shift.
local function vr_update_distance()
    vr_ipd_applied_base = nil
    vr_apply_ipd_mm()
    local osdw = mp.get_property_number("osd-width") or 0
    if osdw <= 0 then
        vr_distance_trace = '{"k":"vrDistance","reason":"no-osd-size","applied":false}'
        return
    end
    local have_mmpx = dist_in_mmpx and dist_in_mmpx > 0
    local mmpx = have_mmpx and dist_in_mmpx or VR_MACBOOK_MM_PER_PX
    local eye_w_mm = (osdw / 2.0) * mmpx
    local half_w = eye_w_mm / 2.0
    local excess = 0.0
    if VR_PARALLAX_CORRECTION_ENABLED then
        local mag = math.tan(math.rad(VR_ZOOM_REFERENCE_FOV_DEG) * 0.5) / math.tan(deg2rad(clamp(vr_fov + manual_fov, VR_FOV_MIN, vr_fov_max())) * 0.5)
        excess = (vr_tune.vr_parallax_disparity or VR_PARALLAX_CORRECTION_DISPARITY) * (mag - 1.0) * (vr_tune.vr_parallax_strength or VR_PARALLAX_CORRECTION_STRENGTH)
    end
    local today_norm = excess + ipd_nudge + 0.0   -- 0.0 = today's base_ipd default (dial is the ipd offset now)
    local offset_mm = base_ipd * half_w
    local s_today = today_norm * half_w + VR_TODAY_BASE_IPD_MM + offset_mm
    local ipd_eff = VR_DEFAULT_IPD_MM + offset_mm
    local d, reason = nil, dist_in_reason
    if dist_in_d and dist_in_at then
        local age = mp.get_time() - dist_in_at
        if age <= VR_DISTANCE_HOLD_S then
            d = dist_in_d; reason = (age <= 0.5) and "ok" or "hold-last-d"
        else
            reason = "no-face-hold-expired"
        end
    end
    local s_requested, capped, s_cap = s_today, false, nil
    if d then
        s_cap = (d / VR_REFERENCE_DISTANCE_MM) * (ipd_eff + s_today) - ipd_eff
        if s_cap < s_today then s_requested = s_cap; capped = true end
    end
    local shift = s_requested / half_w
    local infeasible = math.abs(shift) > VR_SHADER_SHIFT_LIMIT
    if infeasible then shift = clamp(shift, -VR_SHADER_SHIFT_LIMIT, VR_SHADER_SHIFT_LIMIT) end
    local s_total = shift * half_w -- actual separation after the renderer limit, not the requested cap
    local cap_met = (not d) or (ipd_eff + s_total <= (d / VR_REFERENCE_DISTANCE_MM) * (ipd_eff + s_today) + 1e-9)
    -- shader total = clamp(excess + base + nudge): choose base so the total is exactly `shift`
    vr_ipd_applied_base = shift - excess - ipd_nudge
    vr_distance_trace = string.format(
        '{"k":"vrDistance","d_mm":%s,"s_today_mm":%.4f,"s_cap_mm":%s,"s_total_mm":%.4f,"s_requested_mm":%.4f,"offset_mm":%.4f,"ipd_eff_mm":%.4f,"capped":%s,"infeasible":%s,"cap_met":%s,"reason":"%s","mm_per_px":%.6f,"mm_per_px_src":"%s","eye_w_mm":%.3f}',
        d and string.format("%.2f", d) or "null", s_today, s_cap and string.format("%.4f", s_cap) or "null", s_total, s_requested,
        offset_mm, ipd_eff, tostring(capped), tostring(infeasible), tostring(cap_met), reason, mmpx,
        have_mmpx and "CGDisplayScreenSize" or "macbook-227ppi", eye_w_mm)
end

local vr_menu_crop_x, vr_menu_crop_y = 1, 1
local surface_w,surface_h,surface_x,surface_y=0,0,0,0
local source_eye_crop={0,0,1,1}
local vr_last_payload = nil

--192d all tracked pose filtering is in Swift, before the message.
local vr_fusion_roll,vr_native_raw_roll=nil,nil
local function cinema_reset()
    vr_fusion_roll,vr_native_raw_roll=nil,nil
    manual_yaw,manual_pitch,manual_fov,manual_roll=0,0,0,0
    vr_yaw,vr_pitch,vr_fov,vr_roll=0,0,135,0;vr_head_x,vr_head_y,vr_head_z=0,0,0;ipd_nudge=0
    surface_w,surface_h,surface_x,surface_y=0,0,0,0;pk_zoom=1
end

-- Numeric convergence evidence only, bounded to the collector's existing900row budget.
-- Never read back a video texture or retain media names. Shader title statistics
-- remain GPU-only and are explicitly unavailable, not guessed from scene content.
local convergence_rows,convergence_latest={},nil
local convergence_birth,convergence_epoch=mp.get_time(),os.time()
local convergence_written=-math.huge
local function convergence_flush()
    local dir=mp.get_property("config-dir")
    if not dir or #convergence_rows==0 then return end
    local path=dir.."/gor-convergence.jsonl"
    local f=io.open(path..".tmp","w")
    if not f then return end
    f:write(table.concat(convergence_rows,"\n").."\n");f:close()
    if os.rename(path..".tmp",path) then convergence_written=mp.get_time() end
end
local function convergence_record(payload)
    local t=mp.get_time()
    local position=mp.get_property_number("time-pos") or -1
    local fields={string.format('"t":%.9f,"position":%.6f,"sessionBirth":%.9f,"sessionEpoch":%d',t,position,convergence_birth,convergence_epoch)}
    for _,name in ipairs({"vr_fov","vr_roll","vr_head_roll","vr_cross_eye","vr_swap_eyes","vr_manual_view","vr_eye_aspect","vr_aspect_override","vr_surface_w","vr_surface_h","vr_base_ipd","vr_ipd_nudge","vr_head_x","vr_head_y","vr_head_z","vr_source_layout","vr_flat_mono","vr_flat_sbs","vr_pack","vr_pk_conv","vr_d3_gain","vr_parallax_strength","vr_parallax_disparity","vr_gap_frac"}) do
        local value=tonumber(payload:match("/"..name.."=([-+%d.eE]+)"))
        if value and value==value and math.abs(value)<1e12 then fields[#fields+1]=string.format('"%s":%.9f',name,value) end
    end
    local internal=mp.get_property_native("user-data/gor/3d-internal")==true and 1 or 0
    fields[#fields+1]=string.format('"internal":%d,"planLock":%d,"titleStatAvailable":0',internal,plan_lock and 1 or 0)
    local row="{"..table.concat(fields,",").."}"
    convergence_rows[#convergence_rows+1]=row
    if #convergence_rows>900 then table.remove(convergence_rows,1) end
    convergence_latest=payload
    if t-convergence_written>=5 then convergence_flush() end
end
mp.add_periodic_timer(5,function()
    if (enabled or tools_active) and convergence_latest and convergence_latest==vr_last_payload then
        pcall(function() convergence_record(convergence_latest);convergence_flush() end)
    end
end)

-- One film-frame calculation, consumed by GLSL and committed AppKit chrome.
-- Coordinates here are output-normalized, Y-up; AppKit converts Y at its boundary.
local frame_sequence=0
mp.register_script_message("vr180-look-republish-film-frame",function()
    local frame=mp.get_property_native("user-data/vr180-look/film-frame")
    if type(frame)=="table" and frame.path==(mp.get_property("path") or "") then
        mp.set_property_native("user-data/vr180-look/film-frame",frame)
    end
end)
-- Film display aspect for plain 2D, shared by the shader uniform and the published frame so UI and
-- film use ONE rule. Order: aspect override, mpv display aspect, decoded display size, decoded
-- size times pixel aspect; then the accepted bar crop. 0 = unknown (old full-surface mapping).
local function plain_film_aspect(override)
    local a=override or 0
    if a<=0 then a=tonumber((mp.get_property("video-params/aspect"))) or 0 end
    if a<=0 then
        local dw,dh=tonumber((mp.get_property("video-params/dw"))) or 0,tonumber((mp.get_property("video-params/dh"))) or 0
        if dw>0 and dh>0 then a=dw/dh end
    end
    if a<=0 then
        local w,h=tonumber((mp.get_property("video-params/w"))) or 0,tonumber((mp.get_property("video-params/h"))) or 0
        local par=tonumber((mp.get_property("video-params/par"))) or 1
        if par<=0 then par=1 end
        if w>0 and h>0 then a=w*par/h end
    end
    local cw,ch=source_eye_crop[3] or 1,source_eye_crop[4] or 1
    if a>0 and cw>0 and ch>0 then return a*cw/ch end
    return 0
end
local aspect_fallback_key=nil
local aspect_fallback_basis="swift-projection"
local function finite_positive(v) return type(v)=="number" and v==v and v>0 and v<math.huge end
local function effective_flat_eye_aspect()
    if not flat_mono or flat_pack~=3 or finite_positive(flat_eye_aspect) then
        aspect_fallback_basis="swift-projection";return flat_eye_aspect
    end
    local a,iw,ih,par=0,0,0,1
    local origin="pending-current-paired-geometry"
    for _,entry in ipairs({{"video-dec-params/",true},{"video-dec-params/d",false},{"video-params/",true},{"video-params/d",false},{"video-out-params/",false}}) do
        local domain,coded=entry[1],entry[2]
        iw=tonumber((mp.get_property(domain.."w"))) or 0
        ih=tonumber((mp.get_property(domain.."h"))) or 0
        par=coded and (tonumber((mp.get_property(domain.."par"))) or 1) or 1
        if not finite_positive(par) then par=1 end
        if finite_positive(iw) and finite_positive(ih) and finite_positive(iw*par/ih) then a=iw*par/ih;origin=domain..(coded and "coded-par" or "display");break end
    end
    aspect_fallback_basis=origin
    local key=tostring(mp.get_property("path"))..":"..tostring(a)..":"..origin
    if key~=aspect_fallback_key then
        aspect_fallback_key=key
        mp.msg.info("3D-ASPECT-FALLBACK path="..tostring(mp.get_property("path")).." rawAspect="..tostring(flat_eye_aspect).." effectiveAspect="..tostring(a).." basis="..origin.." w="..tostring(iw).." h="..tostring(ih).." par="..tostring(par))
    end
    return a
end
local function film_frame_snapshot(p,override,base)
    if source_layout>=3 or flat_pack>=4 then return nil end
    local w=surface_w>0 and surface_w or mp.get_property_number("osd-width") or 0
    local h=surface_h>0 and surface_h or mp.get_property_number("osd-height") or 0
    if w<=0 or h<=0 then return nil end
    local oa=w/h
    local plain=(tools_active and not enabled) or (flat_pack<=0 and not flat_sbs)
    local roll=p[4];local c,sn=math.cos(roll),math.sin(roll)
    local distance=math.max(0.1,1-p[7])*math.tan(deg2rad(clamp(p[3],VR_FOV_MIN,vr_fov_max()))/2)/math.tan(math.rad(135)/2)
    local fit,spacing,cx,cy,aspect=1,0,1,1,oa
    local zoom=1
    local pairAngle=roll*(viewer_cross_eye>0.5 and 1 or -1)
    local preview=flat_pack==1 or flat_pack==2
    local bandW,bandH,baseX,baseY,replicaX,replicaY=1,1,0.5,0.5,0,0
    if preview then
        bandH=flat_pack==1 and 0.5 or 1
        baseY=flat_pack==1 and 0.25 or 0.5
        replicaY=flat_pack==1 and 0.5 or 0
        aspect=override>0 and override or flat_eye_aspect
        if aspect<=0 then return nil end
        aspect=aspect*source_eye_crop[3]/source_eye_crop[4]
        local eye=oa/bandH
        if aspect>eye then cy=eye/aspect else cx=aspect/eye end
        zoom=2^(-manual_fov/60)*pk_zoom
    elseif plain then
        -- Same rule as the shader: the FILM keeps its own aspect inside the surface and the
        -- rotated film rectangle (not the surface) bounds the tilt fit.
        local fa=plain_film_aspect(override)
        if fa>0 then if fa>oa then cy=oa/fa else cx=fa/oa end end
        local fw,fh=cx*oa,cy
        fit=1/math.max(1,(math.abs(c)*fw+math.abs(sn)*fh)/oa,math.abs(sn)*fw+math.abs(c)*fh)
    else
        local le=0.5-(vr_tune.vr_gap_frac or 0)*0.25
        local eye=oa*le
        -- Only a missing flat2D-to-SBS aspect uses current media geometry. Both
        -- shader uniform and film receipt use this same value; valid routes stay exact.
        aspect=override>0 and override or effective_flat_eye_aspect()
        if aspect<=0 then return nil end
        aspect=aspect*source_eye_crop[3]/source_eye_crop[4]
        if aspect>eye then cy=eye/aspect else cx=aspect/eye end
        local fw,fh=cx*eye,cy
        local held=roll*(viewer_cross_eye>0.5 and 1 or -1)
        local delta=roll-held
        spacing=math.max((0.5+(vr_tune.vr_gap_frac or 0)*0.25)*oa,fw*math.abs(math.cos(delta))+fh*math.abs(math.sin(delta))+(vr_tune.vr_gap_frac or 0)*oa*0.5)
        local bw=spacing*math.abs(math.cos(held))+fw*math.abs(c)+fh*math.abs(sn)
        local bh=spacing*math.abs(math.sin(held))+fh*math.abs(c)+fw*math.abs(sn)
        fit=math.min(1,oa/math.max(bw,0.000001),1/math.max(bh,0.000001))
        zoom=2^(-manual_fov/60)*(flat_pack>0 and pk_zoom or 1)
    end
    local reserve=1
    local total=clamp((vr_tune.vr_parallax_disparity or VR_PARALLAX_CORRECTION_DISPARITY)*(math.tan(math.rad(VR_ZOOM_REFERENCE_FOV_DEG)/2)/math.tan(deg2rad(clamp(p[3],VR_FOV_MIN,vr_fov_max()))/2)-1)*(vr_tune.vr_parallax_strength or VR_PARALLAX_CORRECTION_STRENGTH)+base+ipd_nudge,-0.8,0.8)
    if not plain and not preview and source_layout>0 then reserve=1-math.abs(total)*0.5 end
    local scale=fit*zoom*reserve/distance
    local hx=p[1]/1.5707963-vr_head_x*0.5
    local hy=p[2]/1.5707963+vr_head_y*0.5
    local margin=math.max(0,(1-distance)*0.5)
    local ox=clamp((c*hx*aspect+sn*hy)/aspect,-margin,margin)
    local oy=clamp(-sn*hx*aspect+c*hy,-margin,margin)
    if not plain then
        local mx,my=manual_yaw/1.5707963,-manual_pitch/1.5707963
        ox=ox+(c*mx*aspect+sn*my)/aspect;oy=oy-sn*mx*aspect+c*my
    end
    -- Forward image of the common film-local origin after the inverse sample offset.
    local px=(c*ox*aspect-sn*oy)/aspect
    local py=sn*ox*aspect+c*oy
    local panx,pany
    if preview then panx=-px*cx*bandW*scale;pany=-py*cy*bandH*scale
    elseif plain then panx=-px*cx*scale;pany=-py*cy*scale
    else
        -- UI ceiling guard (flat 2D->3D SBS only). This frame drives only the
        -- committed AppKit chrome; the film reads the shader uniforms and keeps
        -- its full zoom and pan. fit is exactly the scale at which the rotated
        -- chrome fills its reserved zone, so scale past fit is zoom overflow:
        -- the UI waits at its zone edge instead of leaving the window or
        -- crossing the other eye's zone. Pan is clamped below the same way.
        -- At or below the limits every published value is unchanged.
        if scale>fit then scale=fit end
        local le=0.5-(vr_tune.vr_gap_frac or 0)*0.25
        panx=-px*cx*le*scale;pany=-py*cy*scale
    end
    local dx=(plain or preview) and 0 or spacing*math.cos(pairAngle)*fit/oa
    local dy=(plain or preview) and 0 or spacing*math.sin(pairAngle)*fit
    if not plain and not preview and source_layout>0 then
        local baseline=flat_pack==3 and 0.5 or (0.5-(vr_tune.vr_gap_frac or 0)*0.25)
        dx=dx+total*0.5*baseline*math.cos(pairAngle)
        dy=dy+total*0.5*baseline*oa*math.sin(pairAngle)
    end
    if not plain and not preview then
        -- Window containment of the UI guard: the rotated chrome pair (both eye
        -- instances) must stay inside the window. The clamp engages only when
        -- pan would push an edge outside; inside the window pan is unchanged.
        local le=0.5-(vr_tune.vr_gap_frac or 0)*0.25
        local hwx=(cx*le*math.abs(c)+cy*math.abs(sn)/oa)*scale/2
        local hwy=(cx*oa*le*math.abs(sn)+cy*math.abs(c))*scale/2
        local xlo,xhi=math.abs(dx)/2+hwx-0.5,0.5-math.abs(dx)/2-hwx
        local ylo,yhi=math.abs(dy)/2+hwy-0.5,0.5-math.abs(dy)/2-hwy
        panx=xlo>xhi and 0 or clamp(panx,xlo,xhi)
        pany=ylo>yhi and 0 or clamp(pany,ylo,yhi)
    end
    if preview then
        return {fit=fit,spacing=spacing,scale=scale,angle=-roll,
            leftX=baseX+panx,leftY=baseY+pany,replicaX=replicaX,replicaY=replicaY,
            width=w,height=h,plain=false,frameW=cx*bandW,frameH=cy*bandH,
            baseX=baseX,baseY=baseY,layout=flat_pack,instances=flat_pack==1 and 2 or 1,
            clipX=0,clipY=0,clipW=1,clipH=bandH}
    end
    return {fit=fit,spacing=spacing,scale=scale,angle=-roll,
        leftX=0.5-dx/2+panx,leftY=0.5-dy/2+pany,
        replicaX=dx,replicaY=dy,width=w,height=h,plain=plain,
        baseY=0.5,layout=plain and 0 or 3,instances=plain and 1 or 2,clipX=0,clipY=0,clipW=0,clipH=0,
        frameW=plain and cx or cx*(0.5-(vr_tune.vr_gap_frac or 0)*0.25),frameH=cy,baseX=plain and 0.5 or (0.5-(vr_tune.vr_gap_frac or 0)*0.25)*0.5}
end

local function vr_push_uniforms()
    if not enabled and not tools_active then mp.set_property_native("user-data/vr180-look/film-frame",false);return end
    if vr_select_shader then vr_select_shader() end
    local paths = vr_ensure_paths()
    if not paths then return end
    -- Per-file prefix targets only this shader. A whole-map
    -- set_property_native("glsl-shader-opts", ...) would REPLACE the
    -- map, wiping every other script's keys — photon's //!PARAM
    local prefix = paths[vr_active_slot]:match("([^/\\]+)%.glsl$")
    vr_update_distance()
    local base_to_push = vr_ipd_applied_base or base_ipd
    local override = tonumber((mp.get_property("video-aspect-override"))) or 0
    if override <= 0 then override = 0 end
    -- Spherical cameras compose head+manual angles. Flat shaders already have
    -- explicit manual pan/zoom uniforms, so composing them here applies them twice.
    local native=source_layout>=3
    local p={vr_yaw+(native and manual_yaw or 0),clamp(vr_pitch+(native and manual_pitch or 0),-deg2rad(89),deg2rad(89)),vr_fov+(native and manual_fov or 0),vr_roll+manual_roll,vr_head_x,vr_head_y,vr_head_z}
    --192d D5 native roll keeps its previous raw path pending fusion measurement.
    if source_layout>=3 and vr_native_raw_roll then p[4]=vr_native_raw_roll+manual_roll end
    local frame=film_frame_snapshot(p,override,base_to_push)
    local payload = string.format(
        "%s/vr_yaw=%.6f,%s/vr_pitch=%.6f,%s/vr_fov=%.6f,%s/vr_roll=%.6f,"
        .. "%s/vr_base_ipd=%.6f,%s/vr_ipd_nudge=%.6f,"
        .. "%s/vr_head_x=%.6f,%s/vr_head_y=%.6f,%s/vr_head_z=%.6f,"
        .. "%s/vr_swap_eyes=%.1f" .. ",%s/vr_zoomcomp_baseline=%.6f" .. ",%s/vr_gap_frac=%.6f" .. ",%s/vr_gap_blur_frac=%.6f" .. ",%s/vr_vignette_ref_fov=%.6f" .. ",%s/vr_parallax_strength=%.6f" .. ",%s/vr_parallax_disparity=%.6f" .. ",%s/vr_vignette_start=%.6f" .. ",%s/vr_vignette_darken=%.6f" .. ",%s/vr_vignette_blur=%.6f",
        prefix,p[1],prefix,p[2],prefix,deg2rad(clamp(p[3],VR_FOV_MIN,vr_fov_max())),prefix,p[4],
        prefix, base_to_push, prefix, ipd_nudge,
        prefix,p[5],prefix,p[6],prefix,p[7],
        prefix, vr_swap_eyes, prefix, vr_tune.vr_zoomcomp_baseline, prefix, vr_tune.vr_gap_frac, prefix, vr_tune.vr_gap_blur_frac, prefix, vr_tune.vr_vignette_ref_fov, prefix, vr_tune.vr_parallax_strength, prefix, vr_tune.vr_parallax_disparity, prefix, vr_tune.vr_vignette_start, prefix, vr_tune.vr_vignette_darken, prefix, vr_tune.vr_vignette_blur)
    payload=payload..string.format(",%s/vr_head_roll=%.6f,%s/vr_cross_eye=%.1f,%s/vr_calibration=%.1f,%s/vr_native_tb=%.1f",prefix,p[4],prefix,viewer_cross_eye,prefix,calibration_on,prefix,(source_layout==4 or source_layout==6) and 1 or 0)
    payload=payload..string.format(",%s/vr_surface_w=%.6f,%s/vr_surface_h=%.6f,%s/vr_surface_x=%.6f,%s/vr_surface_y=%.6f",prefix,surface_w,prefix,surface_h,prefix,surface_x,prefix,surface_y)
    payload = payload .. string.format(",%s/vr_crop_x=%.6f,%s/vr_crop_y=%.6f",prefix,vr_menu_crop_x,prefix,vr_menu_crop_y)
    payload = payload .. string.format(",%s/vr_flat_sbs=%.1f,%s/vr_eye_aspect=%.6f,%s/vr_aspect_override=%.6f,%s/vr_manual_view=%.6f,%s/vr_manual_yaw=%.6f,%s/vr_manual_pitch=%.6f",
        prefix, flat_sbs and 1 or 0, prefix, effective_flat_eye_aspect(), prefix, override, prefix, manual_fov, prefix, manual_yaw, prefix, manual_pitch)
    payload=payload..string.format(",%s/vr_source_x=%.6f,%s/vr_source_y=%.6f,%s/vr_source_w=%.6f,%s/vr_source_h=%.6f",prefix,source_eye_crop[1],prefix,source_eye_crop[2],prefix,source_eye_crop[3],prefix,source_eye_crop[4])
    for name,value in pairs(vr_tune) do
        if name:match("^blink_") then payload=payload..string.format(",%s/%s=%.6f",prefix,name,value) end
    end
    payload=payload..string.format(",%s/vr_plain=%.1f",prefix,((tools_active and not enabled) or (source_layout<3 and flat_pack<=0 and not flat_sbs)) and 1 or 0)
    -- Plain 2D must keep the FILM aspect, never the window/surface aspect. Published
    -- from the override, else the stream's display aspect, times the accepted bar crop.
    local plain_aspect=plain_film_aspect(override)
    payload=payload..string.format(",%s/vr_plain_aspect=%.6f",prefix,plain_aspect)
    payload=payload..string.format(",%s/blink_top_bottom=%.1f",prefix,flat_tb and 1 or 0)
    payload=payload..string.format(",%s/vr_source_layout=%.1f",prefix,source_layout)
    payload=payload..string.format(",%s/vr_flat_mono=%.1f,%s/vr_d3_gain=%.6f,%s/vr_pack=%.1f,%s/vr_pk_conv=%.4f,%s/vr_pk_zoom=%.4f,%s/vr_pk_soft=%.1f",prefix,flat_mono and 1 or 0,prefix,D3_GAIN,prefix,flat_pack,prefix,pk_conv,prefix,pk_zoom,prefix,pk_soft)
    payload=payload..string.format(",%s/vr_pk_surround_invert=%.1f",prefix,pk_surround_invert)
    if frame then payload=payload..string.format(",%s/vr_frame_fit=%.9f,%s/vr_frame_spacing=%.9f",prefix,frame.fit,prefix,frame.spacing) end
    -- Dedupe: without it a paused player fires a render-options update
    mp.set_property("user-data/vr180-look/distance-trace", vr_distance_trace)
    if payload == vr_last_payload then return end
    local pushed, push_error = mp.commandv("change-list", "glsl-shader-opts", "add", payload)
    local pending = vr_pending_shader_list
    local activated, activation_error = true, nil
    if pushed and pending then
        activated, activation_error = mp.set_property_native("glsl-shaders", pending.shaders)
    end
    if not pushed or not activated then
        if pending then
            local previous = pending.previous
            if vr_shader_paths then for _,path in ipairs(vr_shader_paths) do os.remove(path) end end
            vr_shader_paths=previous.paths;vr_shader_epoch=previous.epoch
            vr_active_slot = previous.slot; vr_shader_variant = previous.variant
            VR180_LOOK_SOURCE = previous.source; vr_shader_written = previous.written
            vr_last_payload = previous.payload
        end
        vr_pending_shader_list = nil
        mp.msg.error("vr180-look: shader publication failed: " .. tostring(push_error or activation_error))
        return
    end
    if pending and pending.previous.paths then
        for _,path in ipairs(pending.previous.paths) do os.remove(path) end
        local dir=pending.previous.paths[1]:match("^(.*)/[^/]+$");if dir then os.remove(dir) end
    end
    vr_pending_shader_list = nil
    vr_last_payload = payload
    if frame then
        frame_sequence=frame_sequence+1;frame.sequence=frame_sequence
        frame.path=mp.get_property("path") or ""
        mp.set_property_native("user-data/vr180-look/film-frame",frame)
    else mp.set_property_native("user-data/vr180-look/film-frame",false) end
    pcall(convergence_record,payload)
end

-- Measured per-eye closure, separate from the intentional double-blink command.
-- Animation continues when camera frames are absent so uncertainty never leaves a frozen lid.
mp.register_script_message("vr180-look-set-lids", function(left,right,uncertain)
    local now=mp.get_time()
    blink_measurement_at=now
    blink_uncertain=uncertain=="true"
    -- Correct the observed camera-to-screen side inversion once, before animation.
    -- Stereo source order does not change the physical output-side lid mapping.
    for i,v in ipairs({tonumber(right) or 0,tonumber(left) or 0}) do
        v=clamp(v,0,1)
        if math.abs(v-blink_target[i])>0.001 then
            blink_from[i]=blink_lids[i];blink_at[i]=now;blink_target[i]=v
        end
    end
    -- Pre-warm: the legacy->extended shader swap (file write + glsl-shaders reload) used to happen at the FIRST
    -- closing lid, a stall that looked like a dropped frame. Do it once when blink measurement starts instead.
    if blink_analog and vr_shader_variant ~= "extended" and vr_push_uniforms then vr_push_uniforms() end
end)
mp.register_script_message("vr180-look-set-blink-analog",function(v) blink_analog=(v~="false") end)
mp.add_periodic_timer(1/60,function()
    if (not enabled and not tools_active) or not blink_measurement_at then return end
    local now=mp.get_time()
    if now-blink_measurement_at>0.2 and not blink_uncertain then
        blink_uncertain=true
        for i=1,2 do blink_from[i]=blink_lids[i];blink_at[i]=now;blink_target[i]=0 end
    end
    -- Settled lids and no reopen glow running: nothing to compute or push (no payload format at 60 Hz).
    if blink_analog and blink_lids[1]==blink_target[1] and blink_lids[2]==blink_target[2]
       and vr_tune.blink_reopen_l==0 and vr_tune.blink_reopen_r==0 then return end
    for i=1,2 do
        local closing=blink_target[i]>blink_from[i]
        local ms=closing and (blink_analog and 60 or vr_tune.blink_close_ms) or (blink_uncertain and vr_tune.blink_failopen_ms or vr_tune.blink_open_ms)
        local t=clamp((now-blink_at[i])*1000/math.max(1,ms),0,1)
        local ease=closing and (blink_analog and t or t*t) or 1-(1-t)*(1-t)
        local old=blink_lids[i]
        blink_lids[i]=blink_from[i]+(blink_target[i]-blink_from[i])*ease
        if old>=0.5 and blink_lids[i]<0.5 then blink_reopen[i]=now end
        vr_tune[i==1 and "blink_lid_l" or "blink_lid_r"]=blink_lids[i]
        vr_tune[i==1 and "blink_reopen_l" or "blink_reopen_r"]=clamp(1-(now-blink_reopen[i])*1000/math.max(1,vr_tune.blink_adapt_ms),0,1)
    end
    vr_push_uniforms()
end)

-- ================================================================
--  4. SCRIPT-MESSAGES
-- ================================================================
--     script-message-to "vr180-look" ...

-- Explicit on/off switch, Swift-controlled. This is the ONLY thing
-- that puts the shader in glsl-shaders or takes it out — the shader
-- is never loaded globally for every video mpv plays.
-- Live tuning of one former #define: script-message-to vr180_look vr180-look-set-tune <name> <value>
mp.register_script_message("vr180-look-set-tune", function(name, val)
    local v = tonumber(val)
    if v == nil or vr_tune[name] == nil then
        mp.msg.warn("vr180-look-set-tune: unknown name or bad value")
        return
    end
    vr_tune[name] = v
    if name == "vr_gap_frac" then
        -- the Swift chrome reads the published gap: keep it equal to the value the shader now uses
        vr_published_gap = v
        vr_publish_gap()
    end
    vr_push_uniforms()
end)

mp.register_script_message("vr180-look-menu-crop",function(x,y)
    local function axis(v)
        local scale,center,size=tostring(v or "1"):match("^([^|]+)|([^|]+)|([^|]+)$")
        if not scale then scale,center=tostring(v or "1"):match("^([^|]+)|([^|]+)$") end
        return tonumber(scale or v) or 1,tonumber(center) or 0.5,tonumber(size)
    end
    local sx,cx,w=axis(x);local sy,cy,h=axis(y)
    if sx<0.999999 or sy<0.999999 then
        if surface_w<=0 or surface_h<=0 then
            -- Real drawable receipt before Swift submits its window refit; never infer from film dimensions.
            w=tonumber(w) or mp.get_property_number("osd-width") or 0
            h=tonumber(h) or mp.get_property_number("osd-height") or 0
            if w>0 and h>0 then surface_w=w;surface_h=h end
        end
        surface_x=cx-0.5;surface_y=cy-0.5
    else surface_w=0;surface_h=0;surface_x=0;surface_y=0 end
    source_eye_crop={0,0,1,1} -- manual viewport; a following verified bar-crop restores its domain.
    vr_menu_crop_x=1; vr_menu_crop_y=1 -- crop belongs to window/UI, never film sampling
    vr_push_uniforms()
end)

-- Only accepted crop-detect-fit bounds use this source-local domain. Pose never edits it.
mp.register_script_message("vr180-look-bar-crop",function(x,y,w,h)
    if source_layout>=3 then return end
    x,y,w,h=tonumber(x),tonumber(y),tonumber(w),tonumber(h)
    if not x or not y or not w or not h or x<0 or y<0 or w<=0 or h<=0 or x+w>1.000001 or y+h>1.000001 then return end
    source_eye_crop={x,y,w,h}
    if source_layout<3 then surface_w,surface_h,surface_x,surface_y=0,0,0,0 end
    vr_push_uniforms()
end)

-- Projection and packing are separate from eye order and anatomical IPD.
mp.register_script_message("vr180-look-source-eye-crop",function(x,y,w,h)
    if plan_lock then return end
    -- Source packing is separate; only bar-crop may set the accepted content domain.
    vr_push_uniforms()
end)
--193b one route writer. Pose/lids remain independent; route messages require the
-- current store revision and store kind. No player metadata callback can classify.
local store_revision,store_kind,completed_revision=nil,nil,nil
local rejected={}
local route_context=nil
-- Route-state evidence is independent of debug environment flags. No pixels or
-- GPU success is inferred here. Append only bounded records to the existing log.
local function route_record(line)
    line=tostring(line):gsub("[\r\n]"," "):sub(1,3900)
    mp.msg.info(line)
    mp.msg.info("GOR_DIAG_RECORD " .. os.date("%H:%M:%S ") .. line)
end
local route_arity={ ["vr180-look-set-projection"]=2,["vr180-look-set-output"]=1,["vr180-look-set-pack"]=5,["vr180-look-surround-invert"]=1,["vr180-look-set-enabled"]=1,["vr180-look-plan-lock"]=2 }
mp.register_script_message("vr180-look-store-revision",function(revision,kind,sender,want_enabled,want_layout,want_pack,output,engine,generation,file,app_pid)
    local n=tonumber(revision)
    if sender~="store-applier" or not n or (store_revision and n<store_revision) then return end
    if n~=store_revision then completed_revision=nil end
    store_revision=n;store_kind=kind
    route_context=want_enabled and {enabled=want_enabled=="true",layout=tonumber(want_layout),pack=tonumber(want_pack),output=output,engine=engine,generation=generation,file=file,app_pid=app_pid} or nil
end)
local route_unpack = table.unpack or unpack -- Lua5.2+ and mpv LuaJIT/Lua5.1
local function register_route(name,handler)
    mp.register_script_message(name,function(...)
        local args={...};local count=route_arity[name]
        local revision,sender=args[count+1],args[count+2]
        local flat=store_kind=="flat-2d3d" or store_kind=="flat-sbs" or store_kind=="flat-tb"
        local reason=(sender~="store-applier" or store_revision==nil or tonumber(revision)~=store_revision) and "revision" or nil
        if name=="vr180-look-set-projection" and args[1]~=store_kind then reason="store_kind" end
        if flat and name=="vr180-look-set-projection" and args[1]~=store_kind then reason="flat_engine" end
        if reason then
            local values=table.concat(args,",");local key=tostring(sender)..name..values
            if not rejected[key] then rejected[key]=true;mp.msg.warn("3D-REJECTED sender="..tostring(sender).." message="..name.." values="..values.." revision="..tostring(revision).." reason="..reason) end
            return
        end
        handler(route_unpack(args,1,count))
        -- The new store kind precedes cleanup of the previous engine. Unlock
        -- must run while the old native layout still exists; projection is the
        -- only message that can establish a new source layout.
        if flat and name=="vr180-look-set-projection" and source_layout>=3 then error("flat projection crossed native engine") end
        mp.msg.info(string.format("3D-LUA sender=%s message=%s revision=%s vr_source_layout=%d vr_flat_mono=%d vr_pack=%d",sender,name,revision,source_layout,flat_mono and 1 or 0,flat_pack))
    end)
end

-- Preview layout + strength for the 2d->3d pseudo preview (3D menu mode / strength). pack 0/1/2 as flat_pack; gain scale 0..2 of D3_GAIN.
local function vr_publish_applied_state()
    mp.set_property_native("user-data/vr180-look/applied-state", string.format(
        '{"source_layout":%d,"aspect":%.6f,"aspect_effective":%.6f,"aspect_basis":"%s","flat_pack":%d,"plan_lock":%s,"enabled":%s,"revision":%s,"completed_revision":%s}',
        source_layout, flat_eye_aspect, effective_flat_eye_aspect(),aspect_fallback_basis,flat_pack,
        plan_lock == nil and "null" or (plan_lock.enabled and "true" or "false"),
        enabled and "true" or "false",tostring(store_revision or "null"),tostring(completed_revision or "null")))
end

-- Receipt barrier only. No route state changes; queued after every applier batch.
mp.register_script_message("vr180-look-route-complete",function(revision,sender)
    if sender~="store-applier" or store_revision==nil or tonumber(revision)~=store_revision then return end
    completed_revision=store_revision
    vr_publish_applied_state()
    if vr_shader_receipt then vr_shader_receipt("route") end
    local c=route_context
    local verdict=c and ((enabled==c.enabled and source_layout==c.layout and flat_pack==c.pack) and "PASS" or "FAIL") or "UNVERIFIED"
    route_record(string.format("3D-VERIFIED file=%s generation=%s revision=%s output=%s engine=%s verdict=%s verification=route_state layout=%d pack=%d enabled=%s expected_layout=%s expected_pack=%s expected_enabled=%s app_pid=%s playing_file=%s",c and c.file or (mp.get_property("path") or "none"):match("[^/]+$"),c and c.generation or "none",tostring(store_revision),c and c.output or "none",c and c.engine or "none",verdict,source_layout,flat_pack,tostring(enabled),c and tostring(c.layout) or "none",c and tostring(c.pack) or "none",c and tostring(c.enabled) or "none",c and tostring(c.app_pid or "none") or "none",(mp.get_property("path") or "none"):match("[^/]+$") or "none"))
end)

register_route("vr180-look-surround-invert", function(on)
    pk_surround_invert = on == "1" and 1.0 or 0.0
    vr_push_uniforms()
end)
register_route("vr180-look-set-pack", function(pack, gain_scale, conv, zoom, soft)
    -- Current revision-owned parameters remain live on prepared shots too.
    vr_pack_check_marker()
    flat_pack = source_layout >= 3 and 0 or (vr_pack_blocked and 0 or math.max(0, math.min(3, math.floor(tonumber(pack) or 0))))
    D3_GAIN = 0.04 * math.max(0, math.min(2, tonumber(gain_scale) or 1))   -- 0.04 base: twice the old 0.02 (owner 15:58: depth too weak)
    pk_conv = math.max(0.1, math.min(0.9, tonumber(conv) or 0.5)); pk_zoom = math.max(0.4, math.min(2.0, tonumber(zoom) or 1.0)); pk_soft = (tonumber(soft) or 1) >= 0.5 and 1.0 or 0.0
    vr_push_uniforms()
    vr_publish_applied_state()
end)
register_route("vr180-look-set-projection", function(kind, aspect)
    mp.msg.info("3D-PROJECTION path="..tostring(mp.get_property("path") or "").." kind="..tostring(kind).." aspect="..tostring(aspect).." outputW="..tostring(mp.get_property("video-out-params/w")).." outputH="..tostring(mp.get_property("video-out-params/h")).." decodedW="..tostring(mp.get_property("video-params/w")).." decodedH="..tostring(mp.get_property("video-params/h")))
    if plan_lock then return end
    source_layout=({["flat-2d3d"]=0,["flat-sbs"]=1,["flat-tb"]=2,["vr180"]=3,["vr180-tb"]=4,["vr360-mono"]=5,["vr360-tb"]=6})[kind] or 0
    flat_sbs = kind == "flat-sbs" or kind == "flat-tb" or kind == "flat-2d3d"
    flat_tb = kind == "flat-tb"
    flat_mono = kind == "flat-2d3d"
    flat_eye_aspect = math.max(0, tonumber(aspect) or 0)
    if flat_mono and not finite_positive(flat_eye_aspect) then flat_eye_aspect=0 end
    vr_push_uniforms()
    vr_publish_applied_state()
end)

-- OUTPUT is selected separately from source packing/projection.
register_route("vr180-look-set-output",function(mode)
    if plan_lock then return end
    -- Output is receipt-only here. Only the store applier's set-pack owns packing.
    vr_push_uniforms()
    vr_publish_applied_state()
end)

-- s36 deterministic path (replaces re-asserting the look after the player's own stereo auto-detect re-read the freshly loaded render file):
-- "vr180-look-plan-lock on <enabled>" is sent AFTER the plan's look messages and BEFORE the loadfile; "off" must come first when the next shot's look is
-- sent. While locked, set-projection / source-eye-crop from the auto-detect are dropped, and set-enabled true is dropped when the plan is a plain 2D
-- picture (anaglyph). The lock lifts by itself when a file that is not a render_shot_NNNNN.mp4 starts (back to the 2D film, or another film).
register_route("vr180-look-plan-lock", function(state, plan_enabled)
    if state == "on" then plan_lock = { enabled = (plan_enabled ~= "false") } else plan_lock = nil end
    vr_publish_applied_state()
end)
local vr_original_properties={}
local vr_raw_properties=nil
local vr_original_opts=nil
local vr_owned_properties={"video-crop","video-aspect-override","video-zoom","video-pan-x","video-pan-y","panscan","video-scale-x","video-scale-y"}
local function vr_record_originals()
    if vr_original_opts==nil then
        vr_original_opts={}
        for key,value in pairs(mp.get_property_native("glsl-shader-opts") or {}) do
            if tostring(key):match("^vr180%-look%-shader%-[ab]/") then vr_original_opts[key]=value end
        end
    end
    for _,key in ipairs(vr_owned_properties) do
        if vr_original_properties[key]==nil then vr_original_properties[key]={value=mp.get_property_native(key)} end
    end
end
local vr_file_off
mp.register_event("start-file", function()
    local path = mp.get_property("path") or ""
    if plan_lock and path:match("render_shot_%d+%.mp4$") then return end
    completed_revision=nil
    if vr_file_off then vr_file_off() end
    route_record("3D-FILE-RESET path="..(path:match("[^/]+$") or "none"))
end)

mp.register_event("end-file",function(event)
    route_record("3D-CLOSE file="..(route_context and route_context.file or (mp.get_property("path") or "none"):match("[^/]+$") or "none").." generation="..(route_context and route_context.generation or "none").." revision="..tostring(store_revision or "none").." reason="..tostring(event and event.reason or "unknown"))
end)
local vr_saved_keepaspect = nil
-- One renderer owns fit: shader while VR/tools are active, mpv otherwise.
local function vr_reconcile_fit_owner()
    if enabled or tools_active then
        if vr_saved_keepaspect==nil then vr_saved_keepaspect={value=mp.get_property_native("keepaspect")} end
        mp.set_property_native("keepaspect",false)
    elseif vr_saved_keepaspect~=nil then
        mp.set_property_native("keepaspect",vr_saved_keepaspect.value)
        vr_saved_keepaspect=nil
    end
end
mp.register_script_message("vr180-look-tools-active", function(val)
    tools_active = val == "true"
    vr_reconcile_fit_owner()
    -- Submit the selected plain/native uniforms BEFORE exposing its shader.
    -- Installing the old legacy slot first briefly displayed native VR defaults
    -- when ordinary-film head/blink tools were enabled with 3D Off.
    if tools_active or enabled then vr_push_uniforms(); vr_apply_shader_list();if vr_shader_receipt then vr_shader_receipt("tools") end else vr_remove_shader() end
end)

vr_file_off=function()
        enabled=false;tools_active=false;plan_lock=nil
        flat_pack=0;source_layout=0;flat_sbs=false;flat_tb=false;flat_mono=false;flat_eye_aspect=0
        source_eye_crop={0,0,1,1};vr_menu_crop_x=1;vr_menu_crop_y=1
        vr_pending_shader_list=nil;vr_last_payload=nil
        if vr_full_fit then vr_full_fit() end
        mp.set_property("video-crop","")
        vr_reconcile_fit_owner()
        vr_remove_shader()
        vr_shader_variant=nil;vr_shader_written=false;VR180_LOOK_SOURCE=nil
        vr_active_slot=1;vr_delete_slot_files()
        if next(vr_original_properties) then vr_raw_properties=vr_original_properties end
        for key,original in pairs(vr_raw_properties or {}) do mp.set_property_native(key,original.value) end
        vr_original_properties={}
        local options=mp.get_property_native("glsl-shader-opts") or {}
        for key,_ in pairs(options) do if tostring(key):match("^vr180%-look%-shader%-[ab]/") then options[key]=nil end end
        for key,value in pairs(vr_original_opts or {}) do options[key]=value end
        mp.set_property_native("glsl-shader-opts",options);vr_original_opts=nil
        local dump={}
        for _,key in ipairs(vr_owned_properties) do dump[key]=mp.get_property_native(key) end
        dump["glsl-shaders"]=mp.get_property_native("glsl-shaders") or {}
        -- Read-only IPC receipt from the real properties after cleanup, not intended state.
        mp.set_property_native("user-data/vr180-look/off-properties",dump)
        mp.set_property_native("user-data/vr180-look/enabled",false)
        vr_publish_applied_state()
end

register_route("vr180-look-set-enabled", function(val)
    local target = (val == "true")
    mp.msg.info(string.format("3D-DECISION lua_enable requested=%s source_layout=%d output_pack=%d plan_lock=%s",tostring(target),source_layout,flat_pack,tostring(plan_lock ~= nil)))
    if plan_lock and plan_lock.enabled == false and target then return end
    -- Off is raw playback, including repeated Off used to recover stale state.
    -- Tools callbacks must not retain/reinstall a projection shader while Off.
    if not target then
        vr_file_off()
        return
    end
    if target == enabled then
        mp.set_property_native("user-data/vr180-look/enabled", enabled)
        vr_publish_applied_state()
        return
    end
    vr_record_originals()
    enabled = target
    mp.set_property_native("user-data/vr180-look/enabled", enabled)
    if not enabled then manual_yaw, manual_pitch, manual_fov, manual_roll = 0, 0, 0, 0 end
    if enabled then
        vr_publish_gap()
        -- Fill the whole drawable (screen when fullscreen, window when windowed): keepaspect=no makes
        -- the video rect equal the drawable, the shader takes each eye's aspect from that size.
        -- The user's prior keepaspect value is saved here and restored on disable.
        vr_reconcile_fit_owner()
        vr_push_uniforms()  -- publish selected uniforms before exposing the fresh slot
        vr_apply_shader_list()
        mp.msg.info("vr180-look: enabled")
    else
        if tools_active then vr_push_uniforms() else vr_remove_shader() end
        vr_reconcile_fit_owner()
        mp.msg.info("vr180-look: disabled")
    end
    vr_publish_applied_state()
end)

-- Absolute set (used on VR-mode entry, or if Swift ever needs to snap
-- roll_s is the Phase 2 addition and is OPTIONAL: mpv passes script-
mp.register_script_message("vr180-look-set-orientation", function(yaw_s, pitch_s, fov_s, roll_s, ipd_nudge_s, head_x_s, head_y_s, head_z_s, dist_mm_s, dist_reason_s, mm_per_px_s, fusion_roll_s, native_raw_roll_s)
    local yaw    = tonumber(yaw_s)
    local pitch  = tonumber(pitch_s)
    local fov    = tonumber(fov_s)
    local roll   = tonumber(roll_s)
    local ipdNdg = tonumber(ipd_nudge_s)
    local headX  = tonumber(head_x_s)
    local headY  = tonumber(head_y_s)
    local headZ  = tonumber(head_z_s)
    if yaw    then vr_yaw   = yaw end
    if pitch  then vr_pitch = clamp(pitch, -deg2rad(VR_PITCH_LIMIT_DEG), deg2rad(VR_PITCH_DOWN_LIMIT_DEG)) end
    if fov    then vr_fov   = clamp(fov, VR_FOV_MIN, vr_fov_max()) end
    if roll then
        local atan2=math.atan2 or math.atan
        vr_roll=vr_roll+atan2(math.sin(roll-vr_roll),math.cos(roll-vr_roll)) -- unwrap, never clamp tilt
    end
    if ipdNdg then ipd_nudge = ipdNdg end
    -- block 182 2: distance inputs ride on the same per-frame message (no extra IPC message).
    local dmm = tonumber(dist_mm_s)
    if dmm and dmm > 0 then dist_in_d = dmm; dist_in_at = mp.get_time(); dist_in_reason = "ok"
    elseif dist_reason_s and dist_reason_s ~= "" and dist_reason_s ~= "ok" then dist_in_d = nil; dist_in_reason = dist_reason_s end
    local mmpx = tonumber(mm_per_px_s)
    if mmpx then dist_in_mmpx = mmpx end   -- 0 = CGDisplayScreenSize unavailable -> the MacBook constant
    if headX  then vr_head_x = headX end
    if headY  then vr_head_y = headY end
    if headZ  then vr_head_z = headZ end
    vr_fusion_roll=tonumber(fusion_roll_s)
    vr_native_raw_roll=tonumber(native_raw_roll_s)
    vr_push_uniforms()
end)

-- Session-scale IPD preference (Phase 3). Deliberately separate from
-- vr180-look-set-orientation above rather than a 6th argument bolted
-- onto that call: base_ipd is a "set it once, maybe revisit later"
mp.register_script_message("vr180-look-set-ipd-mm", function(mm_s)
    local mm = tonumber(mm_s)
    if not mm then return end
    ipd_offset_mm = mm
    vr_apply_ipd_mm()
    vr_push_uniforms()
end)

mp.register_script_message("vr180-look-set-ipd", function(ipd_s)
    local ipd = tonumber(ipd_s)
    if not ipd then return end
    ipd_offset_mm = nil   -- the legacy NDC message is the latest writer
    base_ipd = ipd
    vr_push_uniforms()
end)

-- Cross-eye order switch (block 180 3a). "1"/"true" = swap, anything else = default.
-- Only the SBS source-half choice changes in the shader; the gap/vignette layout
-- is output-side and stays as is. Sent by Swift on VR entry and on toggle.
mp.register_script_message("vr180-look-viewing-cross",function(val)
    viewer_cross_eye=(val=="1" or val=="true") and 1 or 0;vr_push_uniforms()
end)
mp.register_script_message("vr180-look-calibration",function(val)
    calibration_on=(val=="1" or val=="true") and 1 or 0;vr_push_uniforms()
end)
mp.register_script_message("vr180-look-set-swap-eyes", function(val)
    vr_swap_eyes = (val == "1" or val == "true") and 1.0 or 0.0
    vr_push_uniforms()
end)

-- Relative nudge — this is the one the two-finger pan/pinch handler
-- calls, potentially many times per second while actively dragging.
-- dyaw/dpitch in radians, dfov in degrees; all deltas so PPController
mp.register_script_message("vr180-look-nudge", function(dyaw_s, dpitch_s, dfov_s, droll_s)
    if not enabled then return end
    local dyaw   = tonumber(dyaw_s)   or 0.0
    local dpitch = tonumber(dpitch_s) or 0.0
    local dfov   = tonumber(dfov_s)   or 0.0
    manual_roll = manual_roll + (tonumber(droll_s) or 0.0)

    manual_yaw = clamp(manual_yaw + dyaw, -math.pi / VR_YAW_CLAMP, math.pi / VR_YAW_CLAMP)
    manual_pitch = clamp(manual_pitch + dpitch, -deg2rad(VR_PITCH_LIMIT_DEG), deg2rad(VR_PITCH_DOWN_LIMIT_DEG))
    manual_fov = clamp(manual_fov + dfov, VR_FOV_MIN - vr_fov, vr_fov_max() - vr_fov)

    vr_push_uniforms()
end)

-- Same menu/held-key protocol as gor-fit, but in projection space rather than the discarded video map.
local held_x, held_y, held_z, held_at = 0, 0, 0, -1
local manual_tick_at = mp.get_time()
mp.register_script_message("vr180-look-motion", function(kind, x, y, z)
    if not enabled then return end
    x, y, z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    if kind == "hold" then
        held_x, held_y, held_z, held_at = x, y, z, mp.get_time()
    elseif kind == "reset" then
        cinema_reset()
        held_x, held_y, held_z = 0, 0, 0
    else
        -- A 5% screen pan at 90-degree rest FOV is 4.5 degrees; zoom step uses existing 60deg/unit mapping.
        manual_yaw = clamp(manual_yaw - deg2rad(x * 4.5), -math.pi / VR_YAW_CLAMP, math.pi / VR_YAW_CLAMP)
        manual_pitch = clamp(manual_pitch + deg2rad(y * 4.5), -deg2rad(VR_PITCH_LIMIT_DEG), deg2rad(VR_PITCH_DOWN_LIMIT_DEG))
        manual_fov = clamp(manual_fov - z * 6, VR_FOV_MIN - vr_fov, vr_fov_max() - vr_fov)
    end
    vr_push_uniforms()
end)
vr_full_fit=function()
    smooth_fit=nil
    if enabled then vr_record_originals() end
    cinema_reset();held_x,held_y,held_z=0,0,0
    mp.set_property("video-aspect-override","no")
    mp.set_property_number("video-zoom",0);mp.set_property_number("video-pan-x",0);mp.set_property_number("video-pan-y",0)
    mp.set_property_number("panscan",0);mp.set_property_number("video-scale-x",1);mp.set_property_number("video-scale-y",1)
    vr_reconcile_fit_owner()
    vr_push_uniforms()
end
mp.register_script_message("vr180-look-full-fit",vr_full_fit)
mp.register_script_message("vr180-look-cancel-fit",function() smooth_fit=nil end)
--195k default SBS entry: same endpoint as Shift+R, eased over 0.3s.
-- Continuous tracked pose stays live; only the manual view and player fit animate.
mp.register_script_message("vr180-look-smooth-fit",function()
    if not enabled or not flat_sbs then return end
    local from={yaw=manual_yaw,pitch=manual_pitch,fov=manual_fov,roll=manual_roll,zoom=pk_zoom,props={}}
    local targets={["video-zoom"]=0,["video-pan-x"]=0,["video-pan-y"]=0,["panscan"]=0,["video-scale-x"]=1,["video-scale-y"]=1}
    for key,target in pairs(targets) do from.props[key]={mp.get_property_number(key,target),target} end
    mp.set_property("video-aspect-override","no")
    held_x,held_y,held_z=0,0,0
    smooth_fit={started=mp.get_time(),from=from}
end)
mp.add_periodic_timer(1 / 60, function()
    local now = mp.get_time()
    if smooth_fit then
        local t=clamp((now-smooth_fit.started)/0.3,0,1)
        local remain=1-t*t*(3-2*t);local f=smooth_fit.from
        manual_yaw=f.yaw*remain;manual_pitch=f.pitch*remain;manual_fov=f.fov*remain;manual_roll=f.roll*remain;pk_zoom=1+(f.zoom-1)*remain
        for key,v in pairs(f.props) do mp.set_property_number(key,v[2]+(v[1]-v[2])*remain) end
        if t>=1 then smooth_fit=nil end
        vr_push_uniforms()
    end
    local measured_tick=now-manual_tick_at
    local dt = math.max(0, math.min(0.05, measured_tick)); manual_tick_at = now
    if not enabled and not tools_active then return end
    if now - held_at > 0.6 then held_x, held_y, held_z = 0, 0, 0 end
    if held_x == 0 and held_y == 0 and held_z == 0 then vr_push_uniforms();return end
    manual_yaw = clamp(manual_yaw - deg2rad(held_x * 54 * dt), -math.pi / VR_YAW_CLAMP, math.pi / VR_YAW_CLAMP)
    manual_pitch = clamp(manual_pitch + deg2rad(held_y * 54 * dt), -deg2rad(VR_PITCH_LIMIT_DEG), deg2rad(VR_PITCH_DOWN_LIMIT_DEG))
    manual_fov = clamp(manual_fov - held_z * 60 * dt, VR_FOV_MIN - vr_fov, vr_fov_max() - vr_fov)
    vr_push_uniforms()
end)

-- ================================================================
--  5. SELF-HEAL
-- ================================================================
-- if something else (another script, a user glsl-shaders edit)
-- clobbers the property list, re-add our slot without disturbing
-- anything else in it. Only acts while enabled.
local function vr_periodic_update()
    vr_push_uniforms()
    if (enabled or tools_active) and not vr_shader_in_list() then
        vr_apply_shader_list()
    end
    vr_push_uniforms()   -- re-evaluates the distance rule (hold expiry, window resize); deduped when unchanged
end
mp.add_periodic_timer(1.0, vr_periodic_update)
mp.observe_property("video-aspect-override", "string", function() vr_push_uniforms() end)
mp.observe_property("osd-width", "number", function() vr_push_uniforms() end)
mp.observe_property("osd-height", "number", function() vr_push_uniforms() end)

-- ================================================================
--  6. GLSL SOURCE
-- ================================================================
-- Hooks MAIN with an OUTPUT-sized pass (was OUTPUT, same point as photon-grain.lua), which runs the full,
-- already-composited SBS frame through HOOKED — exactly the input
-- this reprojection needs (both eyes present, pre-crop, so it can
local vr_effective_physical_gap_frac  = VR_PURE_LOOK_ENABLED and 0.0 or VR_PHYSICAL_GAP_FRAC
vr_published_gap = vr_effective_physical_gap_frac
vr_publish_gap()
local vr_effective_eye_gap_blur_frac  = VR_PURE_LOOK_ENABLED and 0.0 or VR_EYE_GAP_BLUR_FRAC
local vr_effective_vignette_darken    = VR_PURE_LOOK_ENABLED and 0.0 or VR_PERIPHERAL_VIGNETTE_DARKEN_STRENGTH
local vr_effective_vignette_blur      = VR_PURE_LOOK_ENABLED and 0.0 or VR_PERIPHERAL_VIGNETTE_BLUR_STRENGTH

-- Live-tunable shader values (were compile-time #defines). Defaults are the old constants, pushed as
-- //!PARAMs; vr180-look-set-tune <name> <value> changes one live without a recompile.
vr_tune.vr_zoomcomp_baseline = VR_ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC
vr_tune.vr_gap_frac = vr_effective_physical_gap_frac
vr_tune.vr_gap_blur_frac = vr_effective_eye_gap_blur_frac
vr_tune.vr_vignette_ref_fov = VR_PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG
vr_tune.vr_parallax_strength = VR_PARALLAX_CORRECTION_STRENGTH
vr_tune.vr_parallax_disparity = VR_PARALLAX_CORRECTION_DISPARITY
vr_tune.vr_vignette_start = VR_PERIPHERAL_VIGNETTE_START_FRAC
vr_tune.vr_vignette_darken = vr_effective_vignette_darken
vr_tune.vr_vignette_blur = vr_effective_vignette_blur

vr_tune.blink_lid_l = 0
vr_tune.blink_lid_r = 0
vr_tune.blink_reopen_l = 0
vr_tune.blink_reopen_r = 0
vr_tune.blink_close_ms = 80
vr_tune.blink_open_ms = 180
vr_tune.blink_failopen_ms = 200
vr_tune.blink_adapt_ms = 250
vr_tune.blink_upper = 0.92
vr_tune.blink_lower = 0.08
vr_tune.blink_arc = 0.08
vr_tune.blink_fringe = 0.03
vr_tune.blink_glow = 0.05   -- owner 2026-11-06: lid shading close to black, not a visible glow
vr_tune.blink_glow_radius = 0.08
vr_tune.blink_slit_blur = 0.004   -- owner 2026-11-06: blink blur was far too strong
vr_tune.blink_contrast = 0.4
vr_tune.blink_lift = 0.15
vr_tune.blink_sbs_strength = 1.0
vr_tune.blink_warm_r = 1.0   -- owner 2026-11-06: neutral dark lid, the brown tint is gone
vr_tune.blink_warm_g = 1.0
vr_tune.blink_warm_b = 1.0

VR180_LOOK_SOURCE = [[
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
]] .. string.format("%.6f", VR_ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC) .. [[

//!PARAM vr_gap_frac
//!TYPE float
]] .. string.format("%.6f", vr_effective_physical_gap_frac) .. [[

//!PARAM vr_gap_blur_frac
//!TYPE float
]] .. string.format("%.6f", vr_effective_eye_gap_blur_frac) .. [[

//!PARAM vr_vignette_ref_fov
//!TYPE float
]] .. string.format("%.6f", VR_PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG) .. [[

//!PARAM vr_parallax_strength
//!TYPE float
]] .. string.format("%.6f", VR_PARALLAX_CORRECTION_STRENGTH) .. [[

//!PARAM vr_parallax_disparity
//!TYPE float
]] .. string.format("%.6f", VR_PARALLAX_CORRECTION_DISPARITY) .. [[

//!PARAM vr_vignette_start
//!TYPE float
]] .. string.format("%.6f", VR_PERIPHERAL_VIGNETTE_START_FRAC) .. [[

//!PARAM vr_vignette_darken
//!TYPE float
]] .. string.format("%.6f", vr_effective_vignette_darken) .. [[

//!PARAM vr_vignette_blur
//!TYPE float
]] .. string.format("%.6f", vr_effective_vignette_blur) .. [[

//!HOOK MAIN
//!BIND HOOKED
//!WIDTH OUTPUT.w
//!HEIGHT OUTPUT.h
//!DESC vr180-look v1.3 — VR180 SBS equirectangular look-around

#define PI 3.14159265359
#define PHYSICAL_GAP_FRAC vr_gap_frac

#define EYE_GAP_BLUR_FRAC vr_gap_blur_frac

#define PERIPHERAL_VIGNETTE_MODE ]] .. string.format("%d", VR_PERIPHERAL_VIGNETTE_MODE) .. [[

#define PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG vr_vignette_ref_fov

#define ZOOM_COMPENSATION_ENABLED ]] .. (VR_ZOOM_COMPENSATION_ENABLED and "1" or "0") .. [[

#define ZOOM_COMPENSATION_STRENGTH ]] .. string.format("%.6f", VR_ZOOM_COMPENSATION_STRENGTH) .. [[

#define ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC vr_zoomcomp_baseline

#define ZOOM_REFERENCE_FOV_DEG ]] .. string.format("%.6f", VR_ZOOM_REFERENCE_FOV_DEG) .. [[

#define PARALLAX_CORRECTION_ENABLED ]] .. (VR_PARALLAX_CORRECTION_ENABLED and "1" or "0") .. [[

#define PARALLAX_CORRECTION_STRENGTH vr_parallax_strength

#define PARALLAX_CORRECTION_DISPARITY vr_parallax_disparity

#define PERIPHERAL_VIGNETTE_START_FRAC vr_vignette_start

#define PERIPHERAL_VIGNETTE_DARKEN_STRENGTH vr_vignette_darken

#define PERIPHERAL_VIGNETTE_BLUR_STRENGTH vr_vignette_blur

#define PERIPHERAL_VIGNETTE_BLUR_SAMPLES ]] .. string.format("%d", VR_PERIPHERAL_VIGNETTE_BLUR_SAMPLES) .. [[

#define SPHERE_RADIUS_METERS ]] .. string.format("%.6f", VR_SPHERE_RADIUS_METERS) .. [[

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
// 191c R2: centre_angle is the interocular-axis direction IN THE CALLER'S uv
// frame. The native path's uv frame is screen-aligned, so it passes the head
// roll. The flat branch's uv frame IS the rotated eye frame (stereo_partition),
// where the interocular axis is the frame x-axis, so it passes 0: the centre
// offset is horizontal in the eye frame and the frame rotation carries it onto
// a on screen. spacing/fit keep using held roll only (S1 layout unchanged).
vec2 stereo_pair_uv(vec2 uv,float right,float eye_aspect,vec2 content,float centre_angle) {
    float oa=vr_surface_w>0.0 && vr_surface_h>0.0 ? vr_surface_w/vr_surface_h:target_size.x/target_size.y;
    float separation=0.5+PHYSICAL_GAP_FRAC*0.25;
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
    uv.x-=side*(spacing*cos(centre_angle)*fit-separation*oa)/eye_aspect;
    uv.y-=side*spacing*sin(centre_angle)*fit;
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
        // 191c R2: the eye-local coordinate comes from the ROTATED eye frame
        // (split_pos), not from the screen-aligned pos. Ownership and sampling
        // then agree: the viewport-centre offset lies along a=(cos th,sin th)
        // on screen and e_v=(p_R-p_L).a_perp stays 0 for the geometric chain
        // (plan R0). At th=0 split_pos==pos and this reduces to the pre-191c
        // screen-aligned split exactly (cos=1, sin=0).
        vec2 uv = vec2(right > 0.5 ? (split_pos.x-rs)/(1.0-rs) : split_pos.x/le, split_pos.y);
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
        uv=stereo_pair_uv(uv,right,viewport_aspect,content,0.0);
        if(vr_flat_mono<0.5)content*=1.0-abs(total_shift)*0.5;
        float zoom = exp2(-vr_manual_view / 60.0);
        uv = (uv - vec2(0.5)) / (content * zoom);
        // Native SBS / half-SBS / top-bottom share the tracked virtual screen, not a frozen UV path.
        // The partition rotates the sampling frame by -held_angle. Its inverse
        // picture rotation must use +held_angle in both viewing modes. A fixed
        // -vr_roll cancels the parallel frame but doubles the crossed frame.
        // Centre placement stays horizontal in this frame (centre_angle=0).
        // This changes orientation only; tracked pan and pack/native paths stay as before.
        float eye_roll=vr_roll*(vr_cross_eye>0.5 ? 1.0:-1.0);
        float cr=cos(eye_roll),sr=sin(eye_roll);
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
        blurred_color_accum += HOOKED_tex(vec2(src_u, v));  // center tap
        for (int i = 0; i < PERIPHERAL_VIGNETTE_BLUR_SAMPLES - 1; i++) {
            float angle = 6.28318530718 * float(i) / float(PERIPHERAL_VIGNETTE_BLUR_SAMPLES - 1);
            vec2 ring_offset = vec2(cos(angle), sin(angle)) * blur_radius;
            blurred_color_accum += HOOKED_tex(vec2(src_u, v) + ring_offset);
        }
        blurred_color = blurred_color_accum / float(PERIPHERAL_VIGNETTE_BLUR_SAMPLES);
    } else {
        blurred_color = HOOKED_tex(vec2(src_u, v));
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
    vec4 blinked = blink_render(blurred_color, vec2(fract(eye_pos.x*2.0),1.0-eye_pos.y),vec2(src_u,v),src_right_half ? 1.0:0.0,is_right_eye);
    float darken_amount = PERIPHERAL_VIGNETTE_DARKEN_STRENGTH * peripheral_factor;
    vec4 peripheral_color = mix(blinked, vec4(0.0, 0.0, 0.0, 1.0), darken_amount);

    // Fade toward the black strip inside the blurred edge band
    // (strip_blend < 1.0); everywhere else strip_blend is exactly 1.0
    // so this mix is a no-op and peripheral_color passes through
    return mix(vec4(0.0, 0.0, 0.0, 1.0), peripheral_color, strip_blend);
}
]]

-- Preserve the exact approved spherical/default shader, including compiler constants.
-- Tuned/flat/aspect mode uses the extended shader; returning all settings restores it.
local D3_TITLE_STATS = [[
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
]]
local VR180_LOOK_EXTENDED_SOURCE = D3_TITLE_STATS .. VR180_LOOK_SOURCE:gsub("//!BIND HOOKED\n", "//!BIND HOOKED\n//!BIND D3_TITLE\n",1)
local function vr_replace_once(source, before, after)
    local first, last = source:find(before, 1, true)
    if not first or source:find(before, last + 1, true) then
        error("vr180-look: legacy source template mismatch")
    end
    return source:sub(1, first - 1) .. after .. source:sub(last + 1)
end
local function vr_remove_span(source, first_marker, last_marker)
    local first = source:find(first_marker, 1, true)
    local last = first and source:find(last_marker, first + #first_marker, true)
    if not first or not last then error("vr180-look: legacy source span mismatch") end
    return source:sub(1, first - 1) .. source:sub(last)
end
local function vr_default_source(source)
    source=vr_remove_span(source,"//!PARAM vr_surface_w\n","//!PARAM vr_source_layout\n")
    source=source:gsub("    vec2 actual_size=target_size;\n    vec2 out_size = [^\n]+\n    vec2 surface_pos=[^\n]+\n", "    vec2 out_size = target_size;\n")
    source=source:gsub("surface_pos", "HOOKED_pos"):gsub("actual_size.y / actual_size.x", "out_size.y / out_size.x")
    source=source:gsub("    eye_uv=surface_uv%(eye_uv,actual_size%);\n", "")

    source = vr_remove_span(source, "    if(vr_plain>0.5) {\n", "    if (vr_flat_sbs > 0.5) {\n")
    source = vr_remove_span(source, "//!PARAM vr_source_x\n", "//!PARAM vr_aspect_override\n")
    source = source:gsub("vec2 blink_clamp", "#define vr_source_x 0.0\n#define vr_source_y 0.0\n#define vr_source_w 1.0\n#define vr_source_h 1.0\nvec2 blink_clamp",1)
    source = vr_replace_once(source, "    eye_aspect *= vr_crop_y / vr_crop_x;\n", "")
    source = vr_replace_once(source, "    ndc_x *= vr_crop_x; ndc_y *= vr_crop_y; // menu viewport crop, never packed-eye seam\n\n", "")
    source = vr_remove_span(source, "//!PARAM vr_flat_sbs\n", "//!PARAM vr_yaw\n")
    source = vr_remove_span(source, "//!PARAM vr_zoomcomp_baseline\n", "//!HOOK MAIN\n")
    source = vr_remove_span(source, "    if (vr_flat_sbs > 0.5) {\n", "    // ── Roll-compensated eye partition")
    source = vr_replace_once(source, "#define PHYSICAL_GAP_FRAC vr_gap_frac\n\n", "#define PHYSICAL_GAP_FRAC " .. string.format("%.6f", vr_effective_physical_gap_frac) .. "\n")
    source = vr_replace_once(source, "#define EYE_GAP_BLUR_FRAC vr_gap_blur_frac\n\n", "#define EYE_GAP_BLUR_FRAC " .. string.format("%.6f", vr_effective_eye_gap_blur_frac) .. "\n")
    source = vr_replace_once(source, "#define PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG vr_vignette_ref_fov\n\n", "#define PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG " .. string.format("%.6f", VR_PERIPHERAL_VIGNETTE_REFERENCE_FOV_DEG) .. "\n")
    source = vr_replace_once(source, "#define ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC vr_zoomcomp_baseline\n\n", "#define ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC " .. string.format("%.6f", VR_ZOOM_COMPENSATION_BASELINE_HEIGHT_FRAC) .. "\n")
    source = vr_replace_once(source, "#define PARALLAX_CORRECTION_STRENGTH vr_parallax_strength\n\n", "#define PARALLAX_CORRECTION_STRENGTH " .. string.format("%.6f", VR_PARALLAX_CORRECTION_STRENGTH) .. "\n")
    source = vr_replace_once(source, "#define PARALLAX_CORRECTION_DISPARITY vr_parallax_disparity\n\n", "#define PARALLAX_CORRECTION_DISPARITY " .. string.format("%.6f", VR_PARALLAX_CORRECTION_DISPARITY) .. "\n")
    source = vr_replace_once(source, "#define PERIPHERAL_VIGNETTE_START_FRAC vr_vignette_start\n\n", "#define PERIPHERAL_VIGNETTE_START_FRAC " .. string.format("%.6f", VR_PERIPHERAL_VIGNETTE_START_FRAC) .. "\n")
    source = vr_replace_once(source, "#define PERIPHERAL_VIGNETTE_DARKEN_STRENGTH vr_vignette_darken\n\n", "#define PERIPHERAL_VIGNETTE_DARKEN_STRENGTH " .. string.format("%.6f", vr_effective_vignette_darken) .. "\n")
    source = vr_replace_once(source, "#define PERIPHERAL_VIGNETTE_BLUR_STRENGTH vr_vignette_blur\n\n", "#define PERIPHERAL_VIGNETTE_BLUR_STRENGTH " .. string.format("%.6f", vr_effective_vignette_blur) .. "\n")
    source = vr_replace_once(source, "    // vr_fov is the horizontal fov; the vertical fov follows the eye's own aspect (unchanged from before the\n    // full-fill change, so filling the drawable does not rescale the image).\n", "")
    source = vr_replace_once(source, "    vec2 out_size = target_size;\n    // ── Roll-compensated", "    vec2 out_size = target_size;\n\n    // ── Roll-compensated")
    source = vr_replace_once(source, "vr_aspect_override > 0.0 ? vr_aspect_override : (out_size.x * 0.5) / out_size.y", "(out_size.x * 0.5) / out_size.y")
    return source
end
local VR180_LOOK_LEGACY_SOURCE = vr_default_source(VR180_LOOK_SOURCE)
--[[ PACK-VARIANT-BEGIN (3D menu preview layouts). Built from the extended source by guarded text edits; the extended and legacy sources are never touched. Any failure here leaves
     VR180_LOOK_PACK_SOURCE nil and the preview stays side by side. Mac-compile unverified: vr_select_shader's rollback restores the previous variant if mpv rejects the shader. ]]
local VR180_LOOK_PACK_SOURCE = nil
do
    local ok, built = pcall(function()
        local src = VR180_LOOK_EXTENDED_SOURCE
        src = vr_replace_once(src, "//!PARAM vr_flat_mono\n", "//!PARAM vr_pack\n//!TYPE float\n0.0\n\n//!PARAM vr_pk_conv\n//!TYPE float\n0.5\n\n//!PARAM vr_pk_zoom\n//!TYPE float\n1.0\n\n//!PARAM vr_pk_soft\n//!TYPE float\n1.0\n\n//!PARAM vr_pk_surround_invert\n//!TYPE float\n0.0\n\n//!PARAM vr_flat_mono\n")
        -- Pack previews sample a MONO source for both eyes. Blink taps must not clamp to a nonexistent source-eye half.
        src = vr_replace_once(src, "vec4 hook() {\n    // MAIN hook with WIDTH/HEIGHT OUTPUT.w/h", [=[
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
    if(vr_pack>2.5 && vr_pack<3.5)uv=stereo_pair_uv(uv,right,viewport_aspect,content,vr_head_roll*(vr_cross_eye>0.5 ? 1.0:-1.0));
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
    // MAIN hook with WIDTH/HEIGHT OUTPUT.w/h]=])
        src = vr_replace_once(src, "    if (vr_flat_sbs > 0.5) {\n", [=[
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
]=])
        return src
    end)
    if ok then VR180_LOOK_PACK_SOURCE = built else mp.msg.error("vr180-look: pack variant unavailable: " .. tostring(built)) end
end
-- PACK-VARIANT-END
local pa=VR180_LOOK_LEGACY_SOURCE:find("//!PARAM blink_top_bottom",1,true)
local pb=VR180_LOOK_LEGACY_SOURCE:find("//!PARAM vr_base_ipd",pa,true)
VR180_LOOK_LEGACY_SOURCE=VR180_LOOK_LEGACY_SOURCE:sub(1,pa-1)..VR180_LOOK_LEGACY_SOURCE:sub(pb)
local layout_start=VR180_LOOK_SOURCE:find("vec2 stereo_pair_uv",1,true)
local layout_end=VR180_LOOK_SOURCE:find("float screen_coverage",layout_start,true)
local stereo_layout_helpers=VR180_LOOK_SOURCE:sub(layout_start,layout_end-1)
-- Legacy is selected only without a surface anchor and strips its uniforms.
stereo_layout_helpers=vr_replace_once(stereo_layout_helpers,"vr_surface_w>0.0 && vr_surface_h>0.0 ? vr_surface_w/vr_surface_h:target_size.x/target_size.y","target_size.x/target_size.y")
local first=VR180_LOOK_LEGACY_SOURCE:find("// Block185a: per-eye curved lid",1,true)
local last=VR180_LOOK_LEGACY_SOURCE:find("vec4 hook() {",first,true)
VR180_LOOK_LEGACY_SOURCE=VR180_LOOK_LEGACY_SOURCE:sub(1,first-1)..VR180_LOOK_LEGACY_SOURCE:sub(last)
-- Legacy strips the frame PARAMs but retains these helpers. Zero selects their existing local fallback.
VR180_LOOK_LEGACY_SOURCE=vr_replace_once(VR180_LOOK_LEGACY_SOURCE,"vec4 hook() {","#define vr_frame_fit 0.0\n#define vr_frame_spacing 0.0\n"..stereo_layout_helpers.."vec4 hook() {")
VR180_LOOK_LEGACY_SOURCE=vr_replace_once(VR180_LOOK_LEGACY_SOURCE,
    "    // Blink composes on the UNMASKED image first; the peripheral darken and the strip\n    // fade apply LAST so the black fade always stays in front of the blink (owner\n    // 2026-11-06: the fade must never disappear during a blink, the blink sits behind\n    // it). With lid and reopen at zero, blink_render early-returns its base untouched,\n    // so the non-blink output is byte-identical to the old order.\n    vec4 blinked = blink_render(blurred_color, vec2(fract(eye_pos.x*2.0),1.0-eye_pos.y),vec2(src_u,v),src_right_half ? 1.0:0.0,is_right_eye);\n    float darken_amount = PERIPHERAL_VIGNETTE_DARKEN_STRENGTH * peripheral_factor;\n    vec4 peripheral_color = mix(blinked, vec4(0.0, 0.0, 0.0, 1.0), darken_amount);",
    "    float darken_amount = PERIPHERAL_VIGNETTE_DARKEN_STRENGTH * peripheral_factor;\n    vec4 peripheral_color = mix(blurred_color, vec4(0.0, 0.0, 0.0, 1.0), darken_amount);")

-- Native top/bottom source sampling uses its own eye domain, never SBS reinterpretation.
for _,slot in ipairs({"extended","legacy","pack"}) do
    local source=slot=="extended" and VR180_LOOK_EXTENDED_SOURCE or (slot=="legacy" and VR180_LOOK_LEGACY_SOURCE or VR180_LOOK_PACK_SOURCE)
    if source then
        source=source:gsub("vec2%(src_u, v%)","native_source_uv(src_u,v)"):gsub("vec2%(src_u,v%)","native_source_uv(src_u,v)")
        if slot=="extended" then VR180_LOOK_EXTENDED_SOURCE=source elseif slot=="legacy" then VR180_LOOK_LEGACY_SOURCE=source else VR180_LOOK_PACK_SOURCE=source end
    end
end

-- Default-off synthetic-depth experiment. Stored SBS/native eye pairs never
-- enter it. Limits are TOTAL disparity fractions, mapped to per-eye UV here.
local d3_budget = {on=mp.get_opt and mp.get_opt("gor3d_budget")=="yes", conv=0, comp=0.35, near=0.010, far=0.015}
-- Affine gain preserves straight lines in the fallback plane; no middle-depth bulge.
function d3_budget.map(disp,conv,comp,dmax,dnear,dfar)
    if dmax<=0 then return 0 end
    local m=math.max(-1,math.min(1,(disp-conv*dmax)/dmax))
    local a=math.abs(m)
    local out=dmax*(m<0 and -1 or 1)*((1+comp)*a)
    return math.max(-dfar,math.min(dnear,out))
end
function d3_budget.source(source)
    if not d3_budget.on or not flat_mono or source_layout~=0 then return source end
    local helper=string.format([[
float d3_budget_map(float disp) {
    float dm=max(abs(vr_d3_gain)*0.5,0.0000001);
    float m=clamp((disp-(%.9f)*dm)/dm,-1.0,1.0);
    float a=abs(m);
    float mapped=dm*sign(m)*((1.0+%.9f)*a);
    return clamp(mapped,-%.9f,%.9f);
}
]],d3_budget.conv,d3_budget.comp,d3_budget.far*0.5,d3_budget.near*0.5)
    source=source:gsub("float d3_depth",helper.."float d3_depth",1)
    source=source:gsub("(float disp=vr_d3_gain%*%(d3_depth%(uv,0%.5%)%-0%.5%);)","%1\n            disp=d3_budget_map(disp);")
    source=source:gsub("(float disp = vr_d3_gain %* %(d3_depth%(uv,vr_pk_conv%) %- vr_pk_conv%);)","%1\n    disp=d3_budget_map(disp);")
    return source
end
mp.register_script_message("gor3d-budget",function(args)
    -- Explicit tuning only, no persistent setting or panel behavior change.
    for key,value in tostring(args):gmatch("([%a_]+)=([%w.+-]+)") do
        if key=="on" then d3_budget.on=value=="yes"
        else
            local n=tonumber(value)
            if n and n==n and math.abs(n)<math.huge then
                if key=="conv" then d3_budget.conv=clamp(n,-0.5,0.5)
                elseif key=="comp" then d3_budget.comp=clamp(n,0,1)
                elseif key=="near" then d3_budget.near=clamp(n,0,0.02)
                elseif key=="far" then d3_budget.far=clamp(n,0,0.03) end
            end
        end
    end
    vr_last_payload=nil
    if enabled or tools_active then vr_push_uniforms(); vr_apply_shader_list(); if vr_shader_receipt then vr_shader_receipt("budget") end end
end)

for k,v in pairs(vr_tune) do vr_tune_defaults[k] = v end
VR180_LOOK_SOURCE = VR180_LOOK_LEGACY_SOURCE
vr_shader_variant = "legacy"
vr_select_shader = function()
    if not enabled and not tools_active then return end
    local blink_active=vr_tune.blink_lid_l>0 or vr_tune.blink_lid_r>0 or vr_tune.blink_reopen_l>0 or vr_tune.blink_reopen_r>0
    -- analog: keep the extended variant (exact bypass at lid 0) while camera lids stream, so a blink never triggers a shader swap
    if blink_analog and blink_measurement_at and mp.get_time()-blink_measurement_at<1.0 then blink_active=true end
    local legacy = source_layout>=3 and flat_pack<=0 and surface_w<=0 and not tools_active and vr_menu_crop_x == 1 and vr_menu_crop_y == 1 and not blink_active and not flat_sbs and (tonumber((mp.get_property("video-aspect-override"))) or 0) <= 0
    for k,v in pairs(vr_tune_defaults) do if vr_tune[k] ~= v then legacy = false end end
    local variant = legacy and "legacy" or (((enabled or flat_mono or vr_pack_forced) and flat_pack > 0 and not vr_pack_blocked and VR180_LOOK_PACK_SOURCE) and "pack" or "extended")
    local budget_key=(d3_budget.on and flat_mono and source_layout==0) and string.format(":budget:%.9f:%.9f:%.9f:%.9f",d3_budget.conv,d3_budget.comp,d3_budget.near,d3_budget.far) or ""
    if variant..budget_key == vr_shader_variant then return end
    local paths = vr_ensure_paths()
    if not paths then return end
    -- mpv caches shader source by path, not file hash. Never overwrite a path
    -- that previously held another variant (two alternating slots are unsafe).
    local old_paths,old_epoch=paths,vr_shader_epoch
    vr_shader_paths=nil;vr_shader_epoch=vr_shader_epoch+1
    paths=vr_ensure_paths()
    local next_slot = 3 - vr_active_slot
    local source = legacy and VR180_LOOK_LEGACY_SOURCE or (variant == "pack" and VR180_LOOK_PACK_SOURCE or VR180_LOOK_EXTENDED_SOURCE)
    source=d3_budget.source(source)
    variant=variant..budget_key
    local f = io.open(paths[next_slot], "w")
    if not f then vr_shader_paths=old_paths;vr_shader_epoch=old_epoch;mp.msg.error("vr180-look: shader variant write failed"); return end
    local wrote, write_error = f:write(source)
    local closed, close_error = f:close()
    if not wrote or not closed then
        vr_shader_paths=old_paths;vr_shader_epoch=old_epoch
        mp.msg.error("vr180-look: shader variant write/close failed: " .. tostring(write_error or close_error))
        return
    end
    local out = {}; local inserted = false
    for _,p in ipairs(mp.get_property_native("glsl-shaders") or {}) do
        if p == old_paths[1] or p == old_paths[2] then
            if not inserted then table.insert(out,paths[next_slot]); inserted = true end
        else table.insert(out,p) end
    end
    if not inserted then table.insert(out,paths[next_slot]) end
    local previous = { slot = vr_active_slot, variant = vr_shader_variant, paths=old_paths, epoch=old_epoch,
        source = VR180_LOOK_SOURCE, written = vr_shader_written, payload = vr_last_payload }
    mp.msg.info(string.format("vr180-look: shader variant %s -> %s (blink_active=%s)",tostring(vr_shader_variant),variant,tostring(blink_active)))
    vr_active_slot = next_slot; vr_shader_variant = variant
    VR180_LOOK_SOURCE = source; vr_shader_written = true; vr_last_payload = nil
    vr_pending_shader_list = { shaders = out, previous = previous }
end

-- Read actual installed slot bytes/list, not just the route's intended variables.
local function vr_slot_hash(path)
    local args=package.config:sub(1,1)=="/" and {"shasum","-a","256",path} or nil
    if not args then return "unavailable" end
    local ok,result=pcall(mp.command_native,{name="subprocess",args=args,playback_only=false,capture_stdout=true,capture_stderr=true})
    return ok and result and result.status==0 and (result.stdout or ""):match("^([a-fA-F0-9]+)") or "unavailable"
end
vr_shader_receipt=function(reason,repairing)
    local active=enabled or tools_active
    local expected=not active and "none" or (source_layout>=3 and "native" or (flat_pack>0 and "pack" or "extended"))
    local paths=vr_ensure_paths();if not paths then return false end
    local entry=nil;local owned_count=0
    for _,path in ipairs(mp.get_property_native("glsl-shaders") or {}) do
        if path:match("vr180%-look%-shader%-[ab]%.glsl$") then owned_count=owned_count+1 end
        if path==paths[1] or path==paths[2] then entry=path end
    end
    local file=entry and io.open(entry,"rb");local bytes=file and file:read("*a") or nil;if file then file:close() end
    local installed=entry and vr_shader_variant or "none"
    local installed_base=tostring(installed):match("^[^:]+")
    local match=expected=="none" and owned_count==0 or active and owned_count==1 and entry==paths[vr_active_slot] and bytes==VR180_LOOK_SOURCE and
        ((expected=="native" and (installed_base=="legacy" or installed_base=="extended")) or installed_base==expected)
    local opts=mp.get_property_native("glsl-shader-opts") or {}
    local prefix=entry and entry:match("([^/\\]+)%.glsl$") or "none"
    local plain_expected=active and source_layout<3 and flat_pack<=0 and not flat_sbs
    if plain_expected and tonumber(opts[prefix.."/vr_plain"])~=1 then match=false end
    local sha=entry and vr_slot_hash(entry) or "none"
    if active and (#sha~=64 or not sha:match("^[a-fA-F0-9]+$")) then match=false end
    if not match then
        mp.msg.error("3D-SHADER-MISMATCH expected="..expected.." installed="..tostring(installed))
        if not repairing and active then
            vr_remove_shader();vr_shader_variant=nil;vr_shader_written=false;VR180_LOOK_SOURCE=nil
            vr_pending_shader_list=nil;vr_last_payload=nil;vr_delete_slot_files()
            vr_push_uniforms();vr_apply_shader_list()
            return vr_shader_receipt(reason,true)
        end
    end
    mp.set_property_native("user-data/vr180-look/installed-shader",{variant=installed,expected=expected,sha256=sha,entry=entry or "none",verdict=match and "PASS" or "FAIL",revision=store_revision,epoch=vr_shader_epoch})
    route_record(string.format("3D-SHADER reason=%s expected=%s installed=%s sha256=%s entry=%s verdict=%s verification=installed_shader",reason,expected,tostring(installed),sha,entry or "none",match and "PASS" or "FAIL"))
    return match
end

vr_publish_applied_state()

mp.msg.info("vr180-look v1.3 loaded (VR180 SBS equirect reprojection, default: "
    .. (enabled and "ON" or "OFF")
    .. " | zoom-compensation: " .. (VR_ZOOM_COMPENSATION_ENABLED and "ON" or "OFF")
    .. " | parallax-correction: " .. (VR_PARALLAX_CORRECTION_ENABLED and "ON" or "OFF")
    .. " | pure-look: " .. (VR_PURE_LOOK_ENABLED and "ON" or "OFF")
    .. ")")
