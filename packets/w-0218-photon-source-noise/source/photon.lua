-- ================================================================
--  photon.lua - HDR/SDR scene engine
--  Release: 261001-generation-fence-r3 (end-file session invalidation)
--  Owns: scene analysis, brightness, gamma and feed
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
        mp.msg.error("photon: photon-scriptdir invalid or photon-common.lua missing - checked: " .. script_dir .. "/photon-common.lua")
    end
end
local common_ok, common = pcall(require, "photon-common")
if not common_ok then
    mp.msg.error("photon: could not load photon-common - " .. tostring(common) .. ". This script is disabled.")
    return
end
local PHOTON_REQUIRED_COMMON_VERSION = 1
if not common.check_version("photon", PHOTON_REQUIRED_COMMON_VERSION) then
    return
end

--  GVID KILL SWITCH
local sopts = mp.get_property_native("options/script-opts")
if sopts and sopts["photon_kill"] == "yes" then return end
-- ── hdr nit targets ──
local DARK_PEAK           = 100
local BRIGHT_PEAK         = 300
local STATIC_PEAK         = 200
local DARK_THRESH         = 0.13
local BRIGHT_THRESH       = 0.55

-- ── hdr hybrid luma ──
local HDR_AVG_WEIGHT      = 0.70
local HDR_MAX_WEIGHT      = 0.15
local HDR_CONTRAST_WEIGHT_HIGH = 0.28
local HDR_CONTRAST_WEIGHT_LOW  = 0.04
local HDR_CONTRAST_SCALE  = 0.50

-- ── hdr iris simulation ──
local HDR_INERTIA_DARK    = 0.88
local HDR_INERTIA_BRIGHT  = 0.85   -- DRAFT: was 0.12 (near-instant brighten); placeholder until log
local CUT_BASE            = 0.14
local CUT_SCALE           = 2.2
local HDR_VEL_DAMP        = 0.006
local HDR_VEL_SMOOTH      = 0.35

local UPDATE_INTERVAL     = 0.1


-- ── sdr calibration ──
local CALIB_FRAMES        = 12
local CALIB_DEFAULT       = 12

-- PERF: photon is this family's backbone (every subsystem reads its
-- scene feed), so 2 workers here favors fast seek→probe recovery over
-- saving CPU contention. is_network_slow still forces 1 worker regardless.
local ANALYSIS_INTERVAL   = 0.5
local ANALYSIS_PARALLEL   = 2
local LOOKAHEAD_MIN       = 4.0
local LOOKAHEAD_MAX       = 8.0
local RADAR_TICK          = 0.5
-- GC_BEHIND: deepest lookback consumer uses a 3.0s window (see above);
-- 20s is a ~6.7x safety margin, and memory beyond that helps no consumer.
local GC_BEHIND           = 20.0

-- ── sdr gamma ──
local GAMMA_STRENGTH      = 7.5
local GAMMA_MAX           = 7.5
local MOMENTUM_WEIGHT     = 0.35

-- ── sdr adaptation ──
local SDR_ADAPT_DARK      = 0.75   -- legacy per-tick weight, kept for reference
local SDR_ADAPT_BRIGHT    = 0.75
-- Smoothing constants: see SDR_STATE.sm (defined with SDR_STATE; derived from the owner live log, owner-tunable).
local SDR_PROBE_INTERVAL  = 1.0

-- ── sdr live ──
local LIVE_UPDATE_INTERVAL  = 0.25
local SDR_STATIC_GAMMA    = 0
-- Paired with ANALYSIS_PARALLEL above: two workers in flight benefit
local DISPATCH_THROTTLE = 0.05

-- ── photon-sharp adaptive sharpening  CONTROL PANEL ──
-- Single-file unified. Shader source embedded in
-- PHOTON_SHARP_SHADER_SOURCE below.
--  ★★★ META-MULTIPLIER ARCHITECTURE ★★★

--  PHOTON-SHARP EMBEDDED SHADER (moved to photon-sharp.lua — this
--  header stays only as a pointer for anyone grepping this file)
--  Full GLSL shader source lives in photon-sharp.lua, written ONCE per

-- (PHOTON_SHARP_SHADER_SOURCE and PHOTON_SHARP_SHADER_SOURCE_PHASE2 moved to photon-sharp.lua)

--  STATE

local is_hdr = false
local is_sdr = false
local is_live = false

-- ================================================================
--  COST METER (261004 v2.2.3 measurement bundle). Observation only:
--  it changes no probe, cadence, shader or result. It times each
--  full-frame readback consumer, so one run shows which Lua probe
--  costs what. One "photon-cost" log line per 10 s window.
--    shot = wall ms inside screenshot-raw (GPU render + copy)
--    pix  = wall ms in the same probe function outside screenshot-raw
--           (Lua pixel pass; Lua is single-threaded so wall ~= CPU)
--    MB   = frame bytes copied to Lua
-- ================================================================
local COST = { cur = "?", stats = {}, ff = {}, window_start = mp.get_time() }
-- Diagnostic flag: plain true/false, edit here. true = one "photon-cost"
-- line per 10 s goes to /tmp/gor_diag.log (temporary, owner-requested).
-- false = no sampling, no ps call, no file.
COST.diag = true
-- New media telemetry only; existing COST diagnostic switch stays independent.
-- The app passes script option gor-diag with exact value true or false.
COST.media_telemetry = mp.get_opt('gor-diag') == 'true'
-- PHOTON TELEMETRY ADDITION BEGIN
-- Resource budget only. No disk IO, extra readback or control writes.
COST.trace = {capacity=512, head=0, count=0, dropped=0, rows={}}
function COST.trace_record(kind,fields)
    if not COST.media_telemetry then return end
    local trace=COST.trace
    fields.kind=kind;fields.monotonic_time=mp.get_time()
    trace.head=trace.head%trace.capacity+1
    if trace.count<trace.capacity then trace.count=trace.count+1 else trace.dropped=trace.dropped+1 end
    trace.rows[trace.head]=fields
end
function COST.trace_snapshot()
    local trace=COST.trace;local rows={}
    for i=1,trace.count do
        local index=(trace.head-trace.count+i-1)%trace.capacity+1
        local row={};for k,v in pairs(trace.rows[index])do row[k]=v end
        rows[#rows+1]=row
    end
    return rows,trace.dropped
end
-- PHOTON TELEMETRY ADDITION END
-- Evidence mirror: strength/size/document records also go to the one diag
-- log, single write, bounded, only while the diag flag is true.
function COST.diag_mirror(tag, line)
    if not COST.media_telemetry then return end
    local f = io.open("/tmp/gor_diag.log", "a")
    if not f then return end
    local s = ("photon-" .. tag .. " " .. tostring(line)):gsub("[\r\n]", " ")
    f:write(s:sub(1, 4000), "\n")
    f:close()
end
COST.diag_mirror("ident", "photon.lua v2.2.17 loaded " .. os.date("%H:%M:%S"))
function COST.rec(tag)
    local s = COST.stats[tag]
    if not s then
        s = { n = 0, shot_ms = 0, pix_ms = 0, bytes = 0, max_ms = 0, fail = 0 }
        COST.stats[tag] = s
    end
    return s
end
-- SHARED FRAME (v2.2.5): the single-frame probes (RG, HDRHUE, BK, LG, SDR)
-- each ask mpv for the same full-frame screenshot-raw. If one was taken
-- less than SHARE.ttl seconds ago in the same playback state, they read
-- that frame instead of rendering and copying another 4K frame. Same
-- call, same arguments, same bytes layout. GS never reuses (its paired
-- flicker vote needs two different frames at its own spacing) but it
-- does publish its frame for the others. A failed capture is never
-- cached. Any seek, file change, restart or end clears the frame.
-- SHARE.on = false (the shipped default) changes nothing: every probe
-- captures its own frame and the log only counts would=N, how many
-- captures sharing could have skipped. SHARE.on = true enables reuse, which
-- makes a probe read a frame up to SHARE.ttl s older: not bit-identical.
local SHARE = { on = false, ttl = 0.7, t = 0, shot = nil, res = nil }
function SHARE.clear() SHARE.shot = nil end
function COST.shot(role)
    local now0 = mp.get_time()
    if role ~= "own" and SHARE.shot and (now0 - SHARE.t) <= SHARE.ttl then
        local s0 = COST.rec(COST.cur)
        if SHARE.on then
            s0.reuse = (s0.reuse or 0) + 1
            return true, SHARE.shot
        end
        -- measurement only: count what sharing WOULD have saved, still capture
        s0.would = (s0.would or 0) + 1
    end
    local t0 = now0
    if COST.media_telemetry then
        COST.write("media-shot caller=lua-" .. tostring(COST.cur) .. " phase=request")
    end
    local ok, shot = pcall(mp.command_native, {"screenshot-raw", "video"})
    local dt = (mp.get_time() - t0) * 1000
    local s = COST.rec(COST.cur)
    s.shot_ms = s.shot_ms + dt
    s.shot_n = (s.shot_n or 0) + 1
    if ok and type(shot) == "table" and type(shot.data) == "string" then
        s.bytes = s.bytes + #shot.data
        SHARE.shot = shot; SHARE.t = mp.get_time()
    else
        s.fail = s.fail + 1
        SHARE.shot = nil
    end
    return ok, shot
end
function COST.wrap(tag, fn)
    return function(...)
        local prev = COST.cur
        COST.cur = tag
        local s = COST.rec(tag)
        local shot0 = s.shot_ms
        local t0 = mp.get_time()
        local function pack(...) return {n=select("#", ...), ...} end
        local results = pack(fn(...))
        local total = (mp.get_time() - t0) * 1000
        local shot_dt = s.shot_ms - shot0
        s.n = s.n + 1
        s.pix_ms = s.pix_ms + math.max(0, total - shot_dt)
        if total > s.max_ms then s.max_ms = total end
        COST.cur = prev
        return unpack(results, 1, results.n)
    end
end
function COST.ff_inc(name) COST.ff[name] = (COST.ff[name] or 0) + 1 end
-- ffmpeg subprocess wall time (ps cannot see short-lived jobs). Wraps
-- mp.command_native_async: sub-process calls whose command line contains
-- "ffmpeg" are timed from launch to callback; call and result unchanged.
COST.ffw_n, COST.ffw_ms = 0, 0
do
    local orig_async = mp.command_native_async
    mp.command_native_async = function(t, cb, ...)
        if type(t) == "table" and t.name == "subprocess" and type(cb) == "function"
            and type(t.args) == "table" and tostring(t.args[#t.args] or ""):find("ffmpeg", 1, true) then
            local t0 = mp.get_time()
            local user_cb = cb
            cb = function(...)
                COST.ffw_n = COST.ffw_n + 1
                COST.ffw_ms = COST.ffw_ms + (mp.get_time() - t0) * 1000
                return user_cb(...)
            end
        end
        return orig_async(t, cb, ...)
    end
end
local is_network_slow = false  -- true for ALL network streams incl. loopback (gates worker throttle)
local vf_filter_active = false
-- DEFAULT-ON, matching AppDelegate.photonEnabled=true. `enabled` is
-- normally overridden from photon_user_enabled in file-loaded; this
-- `true` only matters if something reads it before that handler runs.
local enabled = mp.get_opt("photon-menu-enabled") ~= "false"
-- Standalone-probe activity gate (P0-3): the RG/GS ring probes, the BK
-- block probe and the LG live probe run on their own wall-clock timers,
-- independent of the feed timers the pause observer kills. They gate on
-- this flag instead of kill/reinstall; a paused or between-files player
-- then costs one boolean check per probe interval instead of a wasted
-- screenshot-raw. Set by file-loaded/end-file and the pause observer.
local playback_active = false
-- A5: the common-exit hud-state publish is display-only against a 4Hz
-- HUD redraw, so it's capped at 2Hz there; toggles publish directly.
local hud_state_last_pub = -10
-- User's last F9 toggle. Unlike `enabled`, NOT reset in file-loaded —
-- persists for the gor session. AppDelegate syncs this via a
-- "set-user-enabled" script-message on every mpv spawn.
local photon_user_enabled = enabled

--  ADAPTIVE BRIGHTNESS SYNC (Swift/ContentAdaptiveDimming)
--  photon_sync_bright_on_enable(target_enabled): shared body of F9's
--  adaptive-brightness side effect (grant permission + set active).
local function photon_sync_bright_on_enable(target_enabled)
    -- Lua boolean by photon-bright-toggle below (set_property_native,
    local adaptive_brightness_user_enabled =
        mp.get_property_bool("user-data/adaptive-brightness-enabled", false)
    if target_enabled and not adaptive_brightness_user_enabled then
        -- Same set_property_native call as B's photon-bright-toggle
        -- handler below: granting the permission when it hasn't been
        -- granted. The off path is deliberately untouched — turning
        adaptive_brightness_user_enabled = true
        mp.set_property_native("user-data/adaptive-brightness-enabled", true)
    end
    if adaptive_brightness_user_enabled then
        mp.set_property_native("user-data/adaptive-brightness-active", target_enabled)
    end
end
-- chrome_user_enabled: same gor-session persistence contract as
-- photon_user_enabled above, but for photon-chrome's INDEPENDENT 'c'
-- toggle. Deliberately a separate variable, not reused from
local chrome_user_enabled = false
-- negativ_user_enabled: same gor-session persistence contract as
-- chrome_user_enabled above, for photon-negativ's own independent 'n'
-- toggle. A third fully independent axis — F9 (photon_user_enabled)
local negativ_user_enabled = false

-- Grouped to stay under Lua's 200 top-level-local limit. cached_hue/
-- cached_warmth, screenshot_last_t, cut_pending, and timer are added
local HDR_STATE = {
    adapted_pq        = 0.30,
    drive_pq          = 0.30,
    pq_velocity       = 0.0,
    prev_adapted_peak = nil,
    adapted_peak      = (DARK_PEAK + BRIGHT_PEAK) / 2,
    last_peak_set     = -1,
}

-- ARCHITECTURE: two sources feed photon_scene_hue/warmth on the HDR
-- path, tried in order: (1) HDR10+ dynamic metadata — free field read
-- off the table update_hdr already has. (2) read_hdr_hue_from_screenshot,
HDR_STATE.cached_hue, HDR_STATE.cached_warmth = nil, nil
HDR_STATE.screenshot_last_t = 0
-- Minimum wall-clock seconds between screenshot-raw calls. Could
-- likely go lower, but there's no evidence a faster rate is visibly
-- different downstream, and sampling at ~10Hz instead of ~1Hz would
local HDR_SCREENSHOT_INTERVAL = 3.0

-- HDR_STATE.cut_pending: set the tick a candidate cut is FIRST seen, cleared
-- once it's either confirmed (next tick still over threshold, against
HDR_STATE.cut_pending = false
HDR_STATE.timer       = nil

-- Grouped to stay under Lua's 200 top-level-local limit.
local SDR_STATE = {
    adapted_gamma    = 0,
    adapted_pbs      = 50,
    last_gamma_set   = -999,
    has_data         = false,
    ffmpeg_running   = false,
    sdr_timer        = nil,
    smooth_timer     = nil,
    radar_timer      = nil,
    prev_pbs         = nil,
    pbs_velocity     = 0.0,
    cut_ramp         = false,
}
-- NO new top-level local: photon.lua sits AT Lua's 200-local limit (a 201st breaks the whole script load).
SDR_STATE.sm = {
    -- Values chosen against the owner's 00:22 live log (153 s): the old 0.75/tick lerp
    -- (tau ~0.35 s at 0.25 s ticks) swung gamma up to ~3.6 units within one second; replaying the
    -- logged pbs samples through this filter gives ~0.5 max 1-s swing. Owner-tunable.
    TAU_DARK = 3.0, TAU_BRIGHT = 4.0,   -- s
    CUT_RAMP_TAU = 0.5,                  -- s, ramp on detected cuts (VOD lookahead + live capture pair)
    -- Shared cut detector convention: a jump beyond 0.65 of a 20-point pbs
    -- span between neighbours is a cut, not motion. VOD applies it to the
    -- 0.5 s lookahead pair, live to consecutive 2.5 s captures.
    CUT_SPAN = 20.0, CUT_SCORE_MIN = 0.65,
    PBS_TAU = 3.0,                       -- s, live pre-filter on the 2.5 s pbs samples
    SLEW_PER_S = 0.75,                   -- gamma units/s output cap (safety; rarely binds with the above)
    tau_alpha = function(dt, tau) return 1 - math.exp(-dt / tau) end,
}
-- RADAR_STATE.reset_cooldown_ticks: for the first few update_sdr ticks
-- after a seek/flush (while SDR_STATE.prev_pbs is nil), forces
-- cut_score to 1.0 so adapted_pbs can't jump in one step (a visible
local RESET_COOLDOWN_TICKS = 3

-- Grouped to stay under Lua's 200 top-level-local limit. RADAR_STATE.last_dispatch_t
-- this same table too — see their own comment for why they're separate.
local RADAR_STATE = {
    reset_cooldown_ticks = 0,
    dynamic_neutral      = CALIB_DEFAULT,
    calib_done           = false,
}
-- BUG-RISK GUARD: calib_done only became true on a successful calibration
-- (pbs_q non-empty, see run_calibration). If every CALIB_FRAMES ffmpeg
-- call fails (transient disk/codec issue), calib_done stays false and
RADAR_STATE.calib_attempted = false

-- Bounded network probes: one shared opts blob for every ffmpeg call
-- site (grain-size sample, radar dispatch, sdr probe, calibration). Caps
-- format analysis at 2MB and I/O waits at 15s, and lets http reconnect,
-- so a slow server can neither serialize nor hang the scene feed (field:
-- an archive.org stream starved the HUD for minutes while 12 serial
-- calibration downloads + radar crawled). Local files keep their exact
-- original command lines; loopback (torrent) counts as network here,
-- same as the worker throttle.
function RADAR_STATE.net_opts()
    return is_network_slow
        and " -analyzeduration 2M -probesize 2M -rw_timeout 15000000 -reconnect 1 -reconnect_delay_max 5"
        or ""
end

-- True while the network is starving mpv (cache underrun). User pause is
-- covered by playback_active elsewhere; this is the buffering stall.
-- Field (archive.org run): ffmpeg -ss probes fired into an underrun
-- collide with mpv's own reads and come back as clean exits with zero
-- frames, and the GS probe committed three escalating sizes off repeated
-- frames. Gates below defer probes and freeze GS while this holds.
function RADAR_STATE.stream_frozen()
    return mp.get_property_bool("paused-for-cache", false) == true
end

-- v15: a 4xx on re-open means the signed URL expired (transfer.it,
-- googlevideo, most stream hosts) - every later re-open fails the same
-- way while mpv keeps playing from its already-open connection (field:
-- hue dead all session, radar hammering the corpse 5x/second). Permanent
-- for this file: one warn, every URL probe path gates on the flag.
function RADAR_STATE.note_url_death(out)
    if RADAR_STATE.url_dead or type(out) ~= "string" then
        return RADAR_STATE.url_dead == true
    end
    if out:find("Server returned 4") or out:find("HTTP error 4") then
        RADAR_STATE.url_dead = true
        mp.msg.warn("photon: stream URL re-open rejected by the server (4xx - expired signed URL?) — URL probes disabled for this file")
    end
    return RADAR_STATE.url_dead == true
end

RADAR_STATE.live_buffer     = {}
RADAR_STATE.buffer_miss     = false
RADAR_STATE.analyzed_times  = {}
RADAR_STATE.pending_queue   = {}
RADAR_STATE.in_pending      = {}
RADAR_STATE.active_workers  = 0
RADAR_STATE.worker_generation = 0

local W_YAVG  = 0.55
local W_YHIGH = 0.20
local W_YLOW  = 0.15
local W_SAT   = 0.10
local LR_MIN  = 16
local LR_MAX  = 235

RADAR_STATE.last_dispatch_t = 0
RADAR_STATE.probe_wall_ema  = nil
RADAR_STATE.last_known_pos  = 0

--  PHOTON SCENE SIGNAL — core scene analysis state
--  Produced by photon's core analysis (HDR/SDR/SDR-live paths), read by
--  sharp/grain/chrome and any future consumer. See

local photon_scene_peak            = 0.50
local photon_scene_contrast        = 0.35
local photon_scene_noise           = 0.10
-- photon_scene_block: encode block-artifact level 0-1, one value per
-- file, measured by the BK probe below (grid-step + quilt ratios).
-- Harsh encodes leave steps on the 8px luma grid that the temporal
-- noise signal cannot see (quantized flat areas are temporally dead),
-- so they read as clean masters without this channel.
local photon_scene_block           = 0.0
-- photon_scene_ring/rlevel: edge-ringing (mosquito) damage from the RG
-- probe below. ring is the smoothed zone/non-zone HF ratio; rlevel is the
-- 0-1 damage level derived from it (0 at ring <= 4, 1 at ring >= 10).
local photon_scene_ring            = 0.0
local photon_scene_rlevel          = 0.0
local photon_scene_sat             = 0.10
-- photon_scene_hue: normalized 0-1 (ffmpeg signalstats HUEAVG degrees /
-- 360; 0≈red, ~0.08≈orange, ~0.17≈yellow, ~0.33≈green, ~0.67≈blue). nil
-- means "no hue signal yet" — HDR path (no per-channel data at all),
local photon_scene_hue              = nil
-- photon_scene_warmth: the SCENE's own blue↔yellow chroma balance
-- (see calc_frame_profile's n_warmth comment for the full derivation
local photon_scene_warmth           = nil
local photon_scene_motion          = 0.20
local photon_scene_is_cut          = false
local photon_scene_has_feed        = false

local photon_scene_smooth_peak     = 0.50
local photon_scene_smooth_contrast = 0.35
local photon_scene_smooth_noise    = 0.10


--  SHARED CONFIG — photon + photon-sharp
-- photon already computes brightness/contrast/noise/motion per frame

--  UTILS

local math_abs, math_max, math_min, math_floor, math_log =
    math.abs, math.max, math.min, math.floor, math.log
local table_insert, table_remove = table.insert, table.remove
local INV_8 = 1/8

local PROP_PATH     = "path"
local PROP_TIME_POS = "time-pos"
local PROP_DURATION = "duration"

local function find_ffmpeg()
    local dir = mp.get_property("config-dir")
    if dir then
        -- dir:match returns nil when config-dir isn't the gor bundle's
        -- vendor/mpv path; concatenating nil crashes script load.
        local base = dir:match("^(.-)vendor/mpv")
        if base then
            local vendor = base .. "vendor/ffmpeg/bin/ffmpeg"
            local f = io.open(vendor)
            if f then f:close(); return vendor end
        end
    end
    -- GUI launches on macOS get a bare system PATH without Homebrew, so
    -- a bare "ffmpeg" depends on how the app was started (field: every
    -- ffmpeg probe failed status=1 under the release app while the same
    -- build worked from a terminal launch). Probe the standard absolute
    -- locations before trusting PATH.
    for _, cand in ipairs({
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
    }) do
        local f = io.open(cand)
        if f then f:close(); return cand end
    end
    return "ffmpeg"
end
-- %q once, at the source: every probe below interpolates FFMPEG into an
-- sh -c string; an unquoted path containing a space would break all of
-- them. Quoting at each call site would drift.
local FFMPEG = string.format("%q", find_ffmpeg())
mp.msg.info("photon: FFMPEG path: " .. FFMPEG)

local function lerp(a, b, t) return a + (b - a) * t end
-- lerp_hue: circular lerp for a 0-1 normalized hue (wraparound angle —
-- 0 and 1 both mean "red"). A plain lerp(a, b, t) is wrong here in two
-- ways: (1) it fabricates a false middle-of-the-wheel value across the
local lerp_hue = common.lerp_hue
local clamp = common.clamp
local function sign(x) return x >= 0 and 1 or -1 end
local function smoothstep(e0, e1, x)
    local t = clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3.0 - 2.0 * t)
end

-- Fine/coarse mix from scene contrast, auto_set_fine_coarse/auto_set_noise
-- moved to photon-sharp.lua (sharp-specific derivation).


--  PBS & GAMMA

local function calc_pbs(yavg, yhigh, ylow, satavg)
    local diff = yhigh - ylow
    if diff < 10 then return nil end

    local inv_255 = 0.00392156862
    local n_avg = yavg * inv_255
    local n_high = yhigh * inv_255
    local n_low = ylow * inv_255
    local n_sat = clamp(satavg * 0.0166666667, 0, 1)

    local score = (W_YAVG * n_avg) + (W_YHIGH * n_high) + (W_YLOW * n_low) + (W_SAT * n_sat)
    return score * 100
end

local function calc_frame_profile(yavg, yhigh, ylow, satavg, hueavg, uavg, bmax)
    local diff = yhigh - ylow
    if diff < 10 then return nil end

    local inv_255 = 0.00392156862
    local n_avg   = yavg * inv_255
    local n_high  = yhigh * inv_255
    local n_low   = ylow * inv_255
    local n_sat   = clamp(satavg * 0.0166666667, 0, 1)
    local n_contrast = n_high - n_low
    -- HUEAVG is a degree value (0-360, ffmpeg signalstats convention:
    -- 0=red, ~60=orange/yellow, ~120=green, ~240=blue) — normalized to
    -- 0-1 by /360, NOT via inv_255 (that's a byte-range normalizer, hue
    local n_hue = hueavg and clamp(hueavg / 360.0, 0, 1) or nil

    -- n_warmth: the scene's own blue↔yellow chroma balance, NOT a viewing or
    -- ambient-light temperature — there is no lamp or light table anywhere in
    -- this pipeline. ffmpeg's UAVG is the raw average of the U (Cb) chroma
    -- blue-yellow axis in YUV (V is the red-green axis); a neutral scene
    -- averages U toward the midpoint, a warm-skewed scene (tungsten
    -- interiors, sunset, amber practicals) pulls it below, a cool-skewed
    local n_warmth = nil
    if uavg and bmax then
        local neutral = bmax / 2.0
        n_warmth = clamp((uavg - neutral) / neutral, -1.0, 1.0)
    end

    local score = (W_YAVG * n_avg) + (W_YHIGH * n_high)
                + (W_YLOW * n_low) + (W_SAT * n_sat)

    return {
        pbs      = score * 100,
        yhigh    = n_high,
        ylow     = n_low,
        yavg     = n_avg,
        sat      = n_sat,
        hue      = n_hue,
        contrast = n_contrast,
        noise    = (diff < 15),
        warmth   = n_warmth,
    }
end

local function pbs_to_gamma(pbs)
    local delta = pbs - RADAR_STATE.dynamic_neutral
    local abs_delta = math_abs(delta)
    local rel = abs_delta / math_max(RADAR_STATE.dynamic_neutral, 1)

    local base_g = -sign(delta) * GAMMA_STRENGTH * math_log(1 + rel)
    local momentum_g = -sign(SDR_STATE.pbs_velocity) * MOMENTUM_WEIGHT * math_log(1 + math_abs(SDR_STATE.pbs_velocity) * INV_8)

    return clamp(base_g + momentum_g, -GAMMA_MAX, GAMMA_MAX)
end

local function parse_frame(stdout)
    local vals = {}
    for line in stdout:gmatch("[^\n]+") do
        local k, v = line:match("lavfi%.signalstats%.(%w+)=([%d%.]+)")
        if k and v then vals[k] = tonumber(v) end
    end
    local yavg, yhigh, ylow, satavg =
        vals["YAVG"], vals["YHIGH"], vals["YLOW"], vals["SATAVG"]
    if not yavg or not yhigh or not ylow or not satavg then return nil end
    local bmax = (yhigh > 255 or yavg > 255) and 1023 or 255
    yavg  = yavg  * 255 / bmax
    yhigh = yhigh * 255 / bmax
    ylow  = ylow  * 255 / bmax
    return calc_pbs(yavg, yhigh, ylow, satavg)
end

local function parse_frame_extended(stdout)
    local vals = {}
    for line in stdout:gmatch("[^\n]+") do
        local k, v = line:match("lavfi%.signalstats%.(%w+)=([%d%.]+)")
        if k and v then vals[k] = tonumber(v) end
    end
    local yavg, yhigh, ylow, satavg =
        vals["YAVG"], vals["YHIGH"], vals["YLOW"], vals["SATAVG"]
    if not yavg or not yhigh or not ylow or not satavg then return nil end
    -- hueavg deliberately excluded from the guard above: a frame with
    -- brightness/contrast/sat but no hue (older ffmpeg build without
    -- HUEAVG, or the grep just missed it) is still a fully usable
    local hueavg = vals["HUEAVG"]
    local uavg   = vals["UAVG"]
    local bmax = (yhigh > 255 or yavg > 255) and 1023 or 255
    yavg  = yavg  * 255 / bmax
    yhigh = yhigh * 255 / bmax
    ylow  = ylow  * 255 / bmax
    -- uavg deliberately NOT rescaled to a 255-equivalent here the way
    -- yavg/yhigh/ylow are above — calc_frame_profile normalizes it
    -- directly against the original bmax (see that function's n_warmth
    return calc_frame_profile(yavg, yhigh, ylow, satavg, hueavg, uavg, bmax)
end

--  ROLLING BUFFER

local DOC -- forward declaration shared by cached profiles and lifecycle
local function buffer_insert(t, profile)
    local entry
    if type(profile) == "number" then
        entry = { t = t, pbs = profile,
                  yhigh = 0.5, ylow = 0.3, yavg = 0.4,
                  sat = 0.1, hue = nil, contrast = 0.2, noise = false,
                  warmth = nil }
    else
        entry = {
            t        = t,
            pbs      = profile.pbs,
            yhigh    = profile.yhigh,
            ylow     = profile.ylow,
            yavg     = profile.yavg,
            sat      = profile.sat,
            hue      = profile.hue,
            contrast = profile.contrast,
            noise    = profile.noise,
            warmth   = profile.warmth
        }
    end
    entry.generation = DOC.gen
    local lo, hi = 1, #RADAR_STATE.live_buffer + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if RADAR_STATE.live_buffer[mid].t < t then lo = mid + 1 else hi = mid end
    end
    table.insert(RADAR_STATE.live_buffer, lo, entry)
end

function RADAR_STATE.buffer_entry_valid(entry)
    return type(entry)=="table" and entry.generation==DOC.gen and
        type(entry.t)=="number" and entry.t==entry.t and entry.t~=math.huge and entry.t~=-math.huge and
        type(entry.pbs)=="number" and entry.pbs==entry.pbs and entry.pbs>=0 and entry.pbs<=100
end

local function buffer_lookup(t)
    local len = #RADAR_STATE.live_buffer
    if len == 0 then return nil end
    local lo, hi = 1, len
    while lo < hi do
        local mid = math_floor((lo + hi) * 0.5)
        if not RADAR_STATE.buffer_entry_valid(RADAR_STATE.live_buffer[mid]) then return nil end
        local val = RADAR_STATE.live_buffer[mid].t
        if val < t then lo = mid + 1 else hi = mid end
    end

    local i = lo
    local j = (lo > 1) and (lo - 1) or 1

    local entry_i = RADAR_STATE.live_buffer[i]
    local entry_j = RADAR_STATE.live_buffer[j]
    if not RADAR_STATE.buffer_entry_valid(entry_i) or not RADAR_STATE.buffer_entry_valid(entry_j) then return nil end

    if math_abs(entry_i.t - t) > 2.0 and math_abs(entry_j.t - t) > 2.0 then
        return nil
    end

    if i == j then return entry_i.pbs end
    local dt = entry_i.t - entry_j.t
    if dt <= 0 then return entry_i.pbs end
    return lerp(entry_j.pbs, entry_i.pbs, clamp((t - entry_j.t) / dt, 0, 1))
end

local function buffer_lookup_full(t)
    local len = #RADAR_STATE.live_buffer
    if len == 0 then return nil end
    local lo, hi = 1, len
    while lo < hi do
        local mid = math_floor((lo + hi) * 0.5)
        if not RADAR_STATE.buffer_entry_valid(RADAR_STATE.live_buffer[mid]) then return nil end
        if RADAR_STATE.live_buffer[mid].t < t then lo = mid + 1 else hi = mid end
    end
    local i = lo
    local j = (lo > 1) and (lo - 1) or 1
    local entry_i = RADAR_STATE.live_buffer[i]
    local entry_j = RADAR_STATE.live_buffer[j]
    if not RADAR_STATE.buffer_entry_valid(entry_i) or not RADAR_STATE.buffer_entry_valid(entry_j) then return nil end
    if math_abs(entry_i.t - t) > 2.0 and math_abs(entry_j.t - t) > 2.0 then
        return nil
    end
    if i == j then return entry_i end
    local dt = entry_i.t - entry_j.t
    if dt <= 0 then return entry_i end
    local alpha = clamp((t - entry_j.t) / dt, 0, 1)
    return {
        t        = t,
        pbs      = lerp(entry_j.pbs, entry_i.pbs, alpha),
        yhigh    = lerp(entry_j.yhigh or 0.5, entry_i.yhigh or 0.5, alpha),
        ylow     = lerp(entry_j.ylow or 0.3, entry_i.ylow or 0.3, alpha),
        yavg     = lerp(entry_j.yavg or 0.4, entry_i.yavg or 0.4, alpha),
        sat      = lerp(entry_j.sat or 0.1, entry_i.sat or 0.1, alpha),
        -- hue is a wraparound angle (0 and 1 both mean "red"), so a plain
        -- lerp would fabricate a false middle-of-the-wheel value across
        hue      = lerp_hue(entry_j.hue, entry_i.hue, alpha),
        contrast = lerp(entry_j.contrast or 0.2, entry_i.contrast or 0.2, alpha),
        noise    = entry_i.noise or false,
        -- warmth: plain lerp, NOT lerp_hue — unlike hue, warmth is a
        -- linear deviation-from-neutral value in [-1, 1] (blue↔yellow
        -- balance), not a circular angle, so there's no wraparound
        warmth   = lerp(entry_j.warmth or 0.0, entry_i.warmth or 0.0, alpha)
    }
end

-- ── per-scene mini-calibration ──
-- Derives "this scene average" from RADAR_STATE.live_buffer (zero
-- extra ffmpeg cost); adds a fine offset to user_strength per
-- DaVinci's shot-by-shot philosophy.
local photon_sharp_scene_baseline_pbs      = nil
local photon_sharp_scene_baseline_contrast = nil
local photon_sharp_scene_baseline_t        = 0
local PHOTON_SHARP_SCENE_BASELINE_WINDOW   = 3.0  -- lookback window (seconds)
local PHOTON_SHARP_SCENE_BASELINE_TTL      = 8.0  -- refresh interval

local function photon_sharp_update_scene_baseline(pos)
    if #RADAR_STATE.live_buffer == 0 then return end
    local now = mp.get_time()
    if photon_sharp_scene_baseline_pbs ~= nil
       and (now - photon_sharp_scene_baseline_t) < PHOTON_SHARP_SCENE_BASELINE_TTL then
        return
    end
    local samples = {}
    for _, fr in ipairs(RADAR_STATE.live_buffer) do
        if fr.t <= pos and (pos - fr.t) <= PHOTON_SHARP_SCENE_BASELINE_WINDOW then
            samples[#samples + 1] = fr
        end
    end
    if #samples == 0 then return end
    table.sort(samples, function(a, b) return a.pbs < b.pbs end)
    local mid_i = math.ceil(#samples / 2)
    photon_sharp_scene_baseline_pbs      = samples[mid_i].pbs
    photon_sharp_scene_baseline_contrast = samples[mid_i].contrast or photon_scene_contrast
    photon_sharp_scene_baseline_t        = now
end

local function region_variance(t)
    local samples, sum, sum2 = 0, 0, 0
    for _, fr in ipairs(RADAR_STATE.live_buffer) do
        if math.abs(fr.t - t) < LOOKAHEAD_MAX then
            samples = samples + 1; sum = sum + fr.pbs; sum2 = sum2 + fr.pbs * fr.pbs
        end
    end
    if samples < 2 then return 100 end
    local mean = sum / samples
    return math.max(0, sum2/samples - mean*mean)
end

-- (photon-sharp SHADER REWRITE ENGINE block -- shader_dir, ensure_paths,
-- ensure_dir, ensure_glsl_list_sane, apply_shader_list, remove_from_list,
-- photon_sharp_smooth, render_shader_content, rewrite_shader -- all moved

--  GRAIN SIZE ANALYSIS — one-shot, file-open pixel analysis
-- Sets photon-grain.lua's GRAIN_SIZE_BASE from a source-derived
-- estimate instead of a fixed default. Runs once per video (unlike the
local GRAIN_ANALYSIS_SAMPLE_FRACTIONS = {0.10, 0.50, 0.90}
local grain_analysis_running  = false
local grain_analysis_samples  = {}
local grain_size_hint_sent    = false
-- duration is regularly not yet known at file-loaded+0.5s (large
-- remuxes, network sources): the interim analysis retries on a bounded
-- cadence instead of giving up silently. A one-shot miss here left the
-- HUD on "analyzing…" for the whole file with no log line (field:
-- recurring "grain stuck on analyzing" reports).
-- One owner for automatic size hints. Producers submit evidence; only this
-- governor publishes photon-grain-set-size-hint. The seed and ceiling are
-- owned by the first accepted live proposal. Unmeasured fallbacks never publish.
-- The source-size/receiver-unit qualification remains a separate producer gate.
local SIZE_GOV = {
    program_on = mp.get_opt("photon-adaptive-program") ~= "false",
    seed = nil, applied = nil, source = nil, ceiling = nil,
    -- drift / step / deadband were fixed numbers: removed, now derived per stream (see SIZE_GOV.derive).
    -- hard_min / hard_max: CONVENTION (product visual safety rail; architect-declared, owner confirmation pending). Basis: receiver clamps
    -- GRAIN_SIZE_BASE to 0.5..8 px, 1.2 px HD reference => absolute hint range 0.42..6.67; 0.70..1.80 is the
    -- narrower look bound; architect-declared product bound, owner confirmation pending. Not derivable from a stream; changing it is an owner decision.
    hard_max = 1.80, hard_min = 0.70,
}
-- Every remaining fixed number, declared once. None is tied to content; none is a measurement.
SIZE_GOV.convention = {
    sigma_k = 3,          -- three-sigma convention applied to the stream's own median-difference scale
    hold_rep_every = 30,  -- log cadence only, no effect on any decision
    floor_tol = 0.8,      -- extrapolation tolerance below the synthetic table's first row (eff >= 0.8*first row).
                          -- Not derivable without new synthetic-table rows below .5 (needs a real 4K HDR capture);
                          -- the clamp is flagged (GS.eff_floor_clamped) and logged, never silent.
}
-- B2 document identity: one counter per file-loaded, sanitized basename.
-- Every strength/size log line carries doc_gen + file; late work of an
-- earlier document is fenced on start-file/end-file (DOC.active).
DOC = { gen = 0, name = "-", active = false, logged = false, header = false }
function DOC.sanitize(raw)
    local s = tostring(raw or ""):gsub("%c", "")
    if s:find("://", 1, true) then
        s = s:gsub("^(%a[%w+.-]*://)[^/@]*@", "%1")
        s = s:gsub("[?#].*$", "")
    end
    s = s:gsub("[/\\]+$", "")
    s = s:match("([^/\\]*)$") or s
    s = s:sub(1, 120)
    if s == "" then s = "-" end
    return s
end
function DOC.append(logname, line)
    COST.diag_mirror(logname, line)  -- independent evidence first
    local ok, p = pcall(mp.command_native, {"expand-path", "~~/" .. logname})
    local path = (ok and type(p) == "string") and p or ((os.getenv("HOME") or "/tmp") .. "/" .. logname)
    local f = io.open(path, "a")
    if not f then return end
    f:write(line, "\n")
    f:close()
end
local gs_path_ok, GS_LOG_PATH = pcall(mp.command_native, {"expand-path", "~~/photon-grain-size.log"})
if not gs_path_ok then GS_LOG_PATH = nil end
local gs_log_warned = false
local function gs_log(kind, source, proposed, applied, share, vote, why)
    local function num(v) return type(v) == "number" and string.format("%.4f",v) or "-" end
    COST.diag_mirror("grain-size.log", string.format(
        "%s doc_gen=%d file=%q pos=%.1f %s source=%s proposed=%s prev=%s next=%s share=%s vote=%s reason=%s",
        os.date("%H:%M:%S"), DOC.gen, DOC.name, mp.get_property_number("time-pos") or -1, kind, source,
        num(proposed), num(SIZE_GOV.applied), num(applied), num(share), num(vote), why or "-"))
    local path = type(GS_LOG_PATH) == "string" and GS_LOG_PATH or
        ((os.getenv("HOME") or "/tmp") .. "/photon-grain-size.log")
    local f, err = io.open(path, "a")
    if not f then
        if not gs_log_warned then
            mp.msg.warn("photon: grain-size trace unavailable at " .. path .. ": " .. tostring(err))
            gs_log_warned = true
        end
        return
    end
    local media = tostring(mp.get_property("path") or ""):gsub("[\r\n\t]", " "):sub(-100)
    f:write(string.format(
        "%s epoch=%d doc_gen=%d file=%q media=%q pos=%.1f %s source=%s proposed=%s seed=%s prev=%s next=%s ceiling=%s share=%s vote=%s reason=%s\n",
        os.date("%Y-%m-%dT%H:%M:%S%z"), os.time(), DOC.gen, DOC.name, media,
        mp.get_property_number("time-pos") or -1, kind, source,
        num(proposed), num(SIZE_GOV.seed), num(SIZE_GOV.applied), num(applied),
        num(SIZE_GOV.ceiling), num(share), num(vote), why or "-"))
    f:close()
end
-- Repeated identical holds (same reason class) are logged on the first tick, then every 30th,
-- with a running count and the value carried (the last committed hint stays applied; hold never resets it).
-- 30 is log cadence only; it does not affect any decision.
SIZE_GOV.hold_rep = { key = nil, n = 0 }
function SIZE_GOV.hold(source, reason, share, vote)
    local key = tostring(reason):gsub("[%d%.%-]+", "#"):sub(1, 40)
    local r = SIZE_GOV.hold_rep
    if r.key == key then r.n = r.n + 1 else r.key = key; r.n = 1 end
    if r.n == 1 or r.n % SIZE_GOV.convention.hold_rep_every == 0 then
        gs_log("HOLD",source,nil,nil,share,vote,
            string.format("%s repeat=%d carry=%s", reason, r.n, SIZE_GOV.applied and string.format("%.4f", SIZE_GOV.applied) or "none"))
    end
end
-- ---- stream-derived bounds (replaces the fixed drift / step / deadband) ----
-- History = raw live proposals that passed the share/vote gates in THIS document (reset with seed/applied).
-- vol       = median |ln(h[i]/h[i-1])| over the history: the stream's own proposal-to-proposal volatility.
-- consensus = median of the last `window` admitted proposals (window = the estimator's own median window, GS.window).
-- A proposal above anchor*exp(K*vol) (anchor = max(applied, consensus)) is an outlier and is HELD, never committed.
-- K = SIZE_GOV.convention.sigma_k (3, three-sigma CONVENTION) is the only constant in the bound. Rails hard_min/hard_max stay as the product's visual safety limit
-- (receiver contract: GRAIN_SIZE_BASE clamps to 0.5..8 px; 1.2 px HD reference gives hint 0.42..6.67; the
-- narrower 0.70..1.80 is an architect-declared product bound, owner confirmation pending, not derived).
SIZE_GOV.hist = {}
function SIZE_GOV.median(t)
    local c = {}
    for i = 1, #t do c[i] = t[i] end
    table.sort(c)
    local n = #c
    if n == 0 then return nil end
    if n % 2 == 1 then return c[math.floor((n + 1) / 2)] end
    return (c[math.floor(n / 2)] + c[math.floor(n / 2) + 1]) / 2
end
function SIZE_GOV.reset_history() SIZE_GOV.hist = {}; SIZE_GOV.hold_rep = { key = nil, n = 0 } end
function SIZE_GOV.derive(raw, window)
    local h = SIZE_GOV.hist
    h[#h + 1] = raw
    local w = window or 5
    while #h > 3 * w do table.remove(h, 1) end
    local out = { n = #h }
    if #h >= 4 then
        local d = {}
        for i = 2, #h do d[#d + 1] = math.abs(math.log(h[i] / h[i - 1])) end
        out.vol = SIZE_GOV.median(d)
        local last = {}
        for i = math.max(1, #h - w + 1), #h do last[#last + 1] = h[i] end
        out.consensus = SIZE_GOV.median(last)
    end
    return out
end
function SIZE_GOV.propose(source, raw, evidence)
    evidence = evidence or {}
    gs_log("PROPOSE", source, raw, nil, evidence.share, evidence.vote, evidence.reason)
    if type(raw) ~= "number" or raw ~= raw or raw == math.huge or raw == -math.huge or raw <= 0 then
        gs_log("HOLD", source, raw, nil, evidence.share, evidence.vote, "invalid")
        return false
    end
    -- File-open measurement seeds the invariant; if it arrives after the
    -- first live commit, it cannot overwrite or shift the seed.
    -- Adaptive OFF means fixed size: no measured hint is committed. The user's
    -- base size stays; the toggle itself resets the hint to 1.0.
    if not SIZE_GOV.program_on then
        gs_log("HOLD", source, raw, nil, evidence.share, evidence.vote, "adaptive-off")
        return false
    end
    -- A fallback is not a measurement and cannot own applied state or emit a hint.
    -- Existing live estimator admission follows below; this does not qualify its units.
    if source ~= "live" then
        gs_log("HOLD", source, raw, nil, evidence.share, evidence.vote, "unmeasured-source")
        return false
    end
    local first = SIZE_GOV.seed == nil
    local candidate_seed = first and raw or SIZE_GOV.seed
    local candidate_ceiling = SIZE_GOV.hard_max
    if not first and source ~= "live" then
        gs_log("HOLD", source, raw, nil, evidence.share, evidence.vote, "seed-already-owned")
        return false
    end
    local prior = SIZE_GOV.applied or candidate_seed
    local upward = source == "live" and raw > prior * 1.05
    -- One confidence rule for every upward live move, including low ranges.
    -- The original >2.2 ramp remains an additional high-end condition.
    if source == "live" then
        if evidence.frame_h and evidence.frame_h < 700 and raw > 1.5 then
            gs_log("HOLD",source,raw,nil,evidence.share,evidence.vote,"sdclass")
            return false
        end
        if SIZE_GOV.program_on or upward or raw > 2.2 then
            if type(evidence.vote) ~= "number" then
                gs_log("HOLD",source,raw,nil,evidence.share,evidence.vote,"no-vote")
                return false
            end
            if evidence.vote > 0.45 then
                gs_log("HOLD",source,raw,nil,evidence.share,evidence.vote,"static")
                return false
            end
        end
        local req = raw > 2.2 and 0.85 or
            ((upward or raw > 1.8 or raw < 0.9) and 0.50 or 0.10)
        if type(evidence.share) ~= "number" or evidence.share < req then
            gs_log("HOLD",source,raw,nil,evidence.share,evidence.vote,"share")
            return false
        end
    end
    local d = SIZE_GOV.derive(raw, evidence.window)
    local deadband, step_cap = 0, math.huge
    if not first then
        if not d.vol then
            gs_log("HOLD",source,raw,nil,evidence.share,evidence.vote,"history-filling")
            return false
        end
        local e = math.exp(SIZE_GOV.convention.sigma_k * d.vol)
        local anchor = math_max(prior, d.consensus)
        local derived_ceiling = anchor * e
        candidate_ceiling = math_min(SIZE_GOV.hard_max, derived_ceiling)
        if raw > derived_ceiling then
            gs_log("HOLD",source,raw,nil,evidence.share,evidence.vote,
                string.format("outlier-above-derived-ceiling ceil=%.4f vol=%.4f cons=%.4f", derived_ceiling, d.vol, d.consensus))
            return false
        end
        deadband = d.vol
        step_cap = math_max(prior * (e - 1), d.consensus - prior)
    end
    local next_hint = math_max(SIZE_GOV.hard_min,
        math_min(SIZE_GOV.hard_max, candidate_ceiling, raw))
    local step_limited = false
    if upward and next_hint > prior + step_cap then next_hint = prior + step_cap; step_limited = true end
    if source == "live" and SIZE_GOV.applied and
        math_abs(next_hint - SIZE_GOV.applied) / SIZE_GOV.applied <= deadband then
        gs_log("HOLD",source,raw,next_hint,evidence.share,evidence.vote,
            raw > candidate_ceiling and "seed-ceiling" or "deadband")
        return false
    end
    if first then
        SIZE_GOV.seed = candidate_seed
        SIZE_GOV.ceiling = candidate_ceiling
        gs_log("SEED",source,raw,nil,evidence.share,evidence.vote,"file-open-anchor")
    end
    mp.commandv("script-message", "photon-grain-set-size-hint", string.format("%.4f",next_hint))
    gs_log("COMMIT",source,raw,next_hint,evidence.share,evidence.vote,
        (raw > candidate_ceiling and next_hint >= candidate_ceiling - 1e-9) and "ceiling-clamped"
        or (step_limited and "step-limited") or "accepted")
    SIZE_GOV.ceiling = candidate_ceiling
    SIZE_GOV.applied = next_hint
    SIZE_GOV.source = source
    if SIZE_GOV.program_on then
        mp.commandv("script-message", "photon-grain-size-evidence", source == "neutral" and "unmeasured" or "instrument-derived")
    end
    return true
end
local grain_analysis_retries  = 0
local grain_analysis_generation = 0
local GRAIN_ANALYSIS_RETRY_MAX = 15  -- 15 x 2s = 30s window, then warn

-- Maps RELATIVE high-frequency energy (avg_diff / avg_raw_YAVG) to a
-- GRAIN_SIZE_BASE multiplier. The raw diff_energy used before was absolute
-- luma, which misread at both ends of the scale: dark films under-read
-- (Himiko avg_diff 0.134 at YAVG ~44 fell below the 0.19 strength
-- threshold despite heavy real grain) and 10-bit HDR over-read (The Paper
-- avg_diff 0.404 at YAVG ~292 hit max boost on luma-scale inflation
-- alone). Relative anchors, measured on the codec corpus + the Jan batch
-- log: harsh modern encodes 0.0005-0.0008, clean natural texture
-- 0.0013-0.0014, synthetic grain 0.0016, Cleaners 0.0024, Himiko 0.0030,
-- Misterije 0.0032.
local function gr_size_hint_from_energy(rel_energy)
    if rel_energy <= 0.0007 then return 1.35 end
    if rel_energy >= 0.0018 then return 0.70 end
    if rel_energy <= 0.0012 then
        local t = (rel_energy - 0.0007) / (0.0012 - 0.0007)
        return 1.35 + (1.00 - 1.35) * t
    else
        local t = (rel_energy - 0.0012) / (0.0018 - 0.0012)
        return 1.00 + (0.70 - 1.00) * t
    end
end

--  STRENGTH ADAPTATION — one-directional multiplier from the same rel
-- Enabling the engine means the user wants grain visible, even on
-- textured sources — so high-texture sources (perceptual masking hides
-- grain) get a boost, never a cut. Same relative scale as the size hint.
local function gr_strength_hint_norm_from_energy(rel_energy)
    if rel_energy <= 0.0012 then return 0.0 end
    if rel_energy >= 0.0020 then return 1.0 end
    return (rel_energy - 0.0012) / (0.0020 - 0.0012)
end

-- Two subprocess calls (raw + unsharp) rather than one combined
-- filtergraph: distinguishing two streams' metadata output is fragile,
local function gr_sample_grain_energy(path, t, on_done)
    local function sample_one(vf, cb)
        COST.ff_inc("grainsize")
        local cmd = string.format(
            FFMPEG .. RADAR_STATE.net_opts() .. " -threads 1 -ss %.3f -i %s -vframes 1 " ..
            -- scale=128:-1 fixed on both measurements so the 5x5 unsharp
            -- kernel's size relative to the image is the same for 4K and
            -- 480p sources (same relative high-frequency band). Both raw
            -- No grep pipe: capture the full output and parse in Lua, so
            -- a failure logs ffmpeg's real error text instead of an empty
            -- post-grep stream (field wedge was undiagnosable: status=1,
            -- output "(empty)").
            "-vf scale=128:-1,%s,metadata=print -f null - 2>&1",
            t, string.format("%q", path), vf)
        mp.command_native_async({
            name = "subprocess", args = {"sh", "-c", cmd},
            capture_stdout = true, capture_stderr = false, playback_only = false,
        }, function(success, res)
            local combined = (res and res.stdout) or ""
            RADAR_STATE.note_url_death(combined)
            local yavg = tonumber(combined:match("lavfi%.signalstats%.YAVG=([%d%.]+)"))
            cb(yavg, success, res, combined)
        end)
    end

    local raw_yavg, hp_yavg
    local raw_done, hp_done = false, false
    local raw_ok, hp_ok = false, false
    local last_success, last_res, last_combined

    local function maybe_finish()
        if not (raw_done and hp_done) then return end
        if raw_ok and hp_ok then
            local diff = math_abs(hp_yavg - raw_yavg)
            mp.msg.info(string.format(
                "photon: grain-size sample t=%.2f — raw_YAVG=%.3f hp_YAVG=%.3f diff=%.3f",
                t, raw_yavg, hp_yavg, diff))
            on_done(diff, raw_yavg)
        else
            mp.msg.warn(string.format(
                "photon: grain-size sample failed (t=%.2f, raw_ok=%s, hp_ok=%s, success=%s, status=%s) — ffmpeg output: %s",
                t, tostring(raw_ok), tostring(hp_ok), tostring(last_success),
                tostring(last_res and last_res.status),
                (last_combined and last_combined ~= "" and last_combined:sub(-300)) or "(empty)"))
            on_done(nil)
        end
    end

    sample_one("signalstats", function(yavg, success, res, combined)
        raw_yavg = yavg
        raw_ok = (yavg ~= nil)
        raw_done = true
        if not raw_ok then last_success, last_res, last_combined = success, res, combined end
        maybe_finish()
    end)
    sample_one("unsharp=5:5:-1.5:5:5:0.0,signalstats", function(yavg, success, res, combined)
        hp_yavg = yavg
        hp_ok = (yavg ~= nil)
        hp_done = true
        if not hp_ok then last_success, last_res, last_combined = success, res, combined end
        maybe_finish()
    end)
end

-- Set by the GS probe on its first committed hint of the file; gates the
-- ffmpeg fast-path interim hint above. Declared before gr_finalize so the
-- function closes over it.
local gr_gs_committed_hint = false

-- Shared final step: avg_diff → two hints (size + strength) → two messages.
-- Common exit for both the ffmpeg-subprocess path (normal files) and the
-- screenshot-raw path (is_live/torrent — see LIVE GRAIN PROBE below);
local function gr_finalize_grain_analysis(avg_diff, n, source_label, avg_raw)
    local rel = avg_diff / math_max(avg_raw or 1.0, 1.0)
    local hint = gr_size_hint_from_energy(rel)
    if SIZE_GOV.program_on then
        -- Interim texture statistics are not source-grain size evidence.
        hint = 1.0
    end
    -- Interim fast-path hint: applied immediately so a near-clean file does
    -- not sit on "analyzing" while the GS probe collects its window (which
    -- can hold forever on dead-clean content). Once the GS probe commits it
    -- owns size; the same receiver, last writer wins. Suppressed after a GS
    -- commit so the probe's measurement is never overridden by the fast path.
    if gr_gs_committed_hint then
        mp.msg.info(string.format(
            "photon: grain-size analysis done [%s] — avg_diff=%.3f avg_raw=%.3f rel=%.5f (n=%d) → hint=%.3f (not sent: GS committed, owns size)",
            source_label, avg_diff, avg_raw or -1, rel, n, hint))
    else
        mp.msg.info(string.format(
            "photon: grain-size analysis done [%s] — avg_diff=%.3f avg_raw=%.3f rel=%.5f (n=%d) → hint=%.3f (interim, GS probe owns size once it commits)",
            source_label, avg_diff, avg_raw or -1, rel, n, hint))
        SIZE_GOV.propose(SIZE_GOV.program_on and "neutral" or "interim", hint,
            {reason=SIZE_GOV.program_on and "adaptive neutral size, unmeasured; " .. source_label or source_label})
    end

    -- Strength adaptation: same rel, second interpretation. No extra
    -- measurement — see gr_strength_hint_norm_from_energy above.
    local strength_norm = gr_strength_hint_norm_from_energy(rel)
    if SIZE_GOV.program_on then
        -- 118c: file-open texture energy is not a noise reading; with no
        -- noise reading the strength is the b7 look (x1.0), so the seed
        -- hint must not pre-boost (norm 0.0 maps to hint x1.0).
        strength_norm = 0.0
    end
    mp.msg.info(string.format(
        "photon: strength-hint (norm) [%s] — rel=%.5f → norm=%.3f",
        source_label, rel, strength_norm))
    mp.commandv("script-message", "photon-grain-set-strength-hint", string.format("%.4f", strength_norm),
        tostring(DOC.gen), DOC.name)
end

-- Once per video: samples at each timestamp in
-- GRAIN_ANALYSIS_SAMPLE_FRACTIONS, averages, feeds
-- gr_size_hint_from_energy, sends to photon-grain via
local function gr_run_grain_size_analysis()
    if not DOC.active then return end
    if grain_analysis_running or grain_size_hint_sent then return end
    local path = mp.get_property("path")
    local duration = mp.get_property_number("duration")
    if not path or is_live then return end
    if not duration or duration <= 0 then
        grain_analysis_retries = grain_analysis_retries + 1
        if grain_analysis_retries <= GRAIN_ANALYSIS_RETRY_MAX then
            mp.add_timeout(2.0, gr_run_grain_size_analysis)
        else
            mp.msg.warn("photon: grain-size analysis gave up - duration still unknown after 30s - grain released to default size (hint 1.0)")
            SIZE_GOV.propose("neutral", 1.0, {reason="duration-unknown"})
        end
        return
    end

    -- v15: URL already rejected a re-open this file - straight to the
    -- neutral release instead of spawning doomed probes.
    if RADAR_STATE.url_dead then
        grain_size_hint_sent = true
        mp.msg.warn("photon: grain-size analysis skipped — stream URL rejected re-open (expired) — grain released to default size (hint 1.0)")
        SIZE_GOV.propose("neutral", 1.0, {reason="url-dead"})
        return
    end
    grain_analysis_running = true
    grain_analysis_samples = {}
    local my_generation = grain_analysis_generation
    -- Network sources: 2 sample points instead of 3 — each sample is two
    -- ranged HTTP fetches, so startup wall-time scales with the count.
    local fractions = is_network_slow and {0.20, 0.70} or GRAIN_ANALYSIS_SAMPLE_FRACTIONS
    local remaining = #fractions

    local function finish()
        if my_generation ~= grain_analysis_generation then return end
        remaining = remaining - 1
        if remaining > 0 then return end
        grain_analysis_running = false
        grain_size_hint_sent = true
        if #grain_analysis_samples == 0 then
            -- No sample succeeded (subprocess error). Release grain from
            -- "analyzing…" with the NEUTRAL hint: 1.0 renders grain's own
            -- base size — a fallback, not a measurement; the GS probe
            -- still overrides the moment it commits a real reading.
            mp.msg.warn("photon: grain-size analysis failed, no samples collected — grain released to default size (hint 1.0)")
            SIZE_GOV.propose("neutral", 1.0, {reason="no-samples"})
            return
        end
        local sum_d, sum_r = 0.0, 0.0
        for _, v in ipairs(grain_analysis_samples) do
            sum_d = sum_d + v.d
            sum_r = sum_r + v.r
        end
        local avg_diff = sum_d / #grain_analysis_samples
        local avg_raw  = sum_r / #grain_analysis_samples
        gr_finalize_grain_analysis(avg_diff, #grain_analysis_samples, "ffmpeg", avg_raw)
    end

    for _, frac in ipairs(fractions) do
        local t = duration * frac
        gr_sample_grain_energy(path, t, function(diff, raw)
            if my_generation ~= grain_analysis_generation then return end
            if diff then table.insert(grain_analysis_samples, {d = diff, r = raw}) end
            finish()
        end)
    end
end

--  LIVE GRAIN PROBE — screenshot-raw alternative for is_live, replaces
--  ffmpeg-subprocess
-- The is_live guard is permanent: an ffmpeg subprocess's seek/open
local LG = {
    grid     = 16,   -- slightly denser than HDR_SAMPLE_GRID because the
                      -- neighbor-diff calculation is noisier than HDR's
                      -- average hue and needs more points.
    interval = 4.0,   -- seconds between frame samples
    count    = 5,     -- total frames to collect
    timer    = nil,
    samples  = {},
    gen      = 0,     -- +1 per gr_run_live_grain_probe() call; tick()
                      -- closures capture their own generation as an
                      -- upvalue and compare against LG.gen at run time.
}

--  ENCODE BLOCK PROBE — screenshot-raw, works for live and file alike
--  (no subprocess, no seek; codec grid only exists at native res, which
--  is exactly what screenshot-raw returns).
local BK = {
    rows     = 12,   -- full-width horizontal scans
    cols     = 12,   -- full-height vertical scans
    interval = 4.0,  -- seconds between frame samples
    count    = 5,    -- total frames to collect
    timer    = nil,
    samples  = {},
    gen      = 0,
    running  = false,
    done     = false, -- one value per file: encode harshness is a file
                      -- property, not a scene property
    reprobe_interval = 300.0, -- opening window can be a clean logo/title;
                              -- re-sample every 5 min of playback and keep
                              -- the worst reading (no seeks, stream-safe)
    reprobe_count    = 3,     -- frames per re-probe
    reprobes         = 0,
}

-- Grid-step signature of codec blocking: pixel-pair steps straddling
-- 8px boundaries vs steps inside blocks, plus the DC quilt (8px segment
-- mean steps vs within-segment std). Clean masters score ~1.1 on both
-- (grid position means nothing to real content); harsh encodes reach
-- 2.0-3.5 because flat areas go dead while block lines keep stepping.
local bk_sample_frame
do
local function bk_sample_frame_raw()
    local ok, shot = COST.shot()
    if not ok or not shot or not shot.data or not shot.w or not shot.h then
        return nil
    end
    if type(shot.data) ~= "string" then return nil end
    local data, w, h = shot.data, shot.w, shot.h
    local stride = shot.stride or (w * 4)

    local b_sum, b_n, i_sum, i_n = 0.0, 0, 0.0, 0
    local q_sum, qn_sum, q_n = 0.0, 0.0, 0

    -- One scanline pass; horiz=1 scans a row, horiz=0 scans a column.
    local function scan(horiz, line)
        local prev = nil
        local seg_sum, seg_sq, seg_k = 0.0, 0.0, 0
        local prev_seg_mean = nil
        local lim = horiz == 1 and w or h
        for t = 0, lim - 1 do
            local x = horiz == 1 and t or line
            local y = horiz == 1 and line or t
            local idx = y * stride + x * 4
            local b, g, r = string.byte(data, idx + 1, idx + 3)
            if not (r and g and b) then break end
            local l = 0.299 * r + 0.587 * g + 0.114 * b
            if prev then
                local d = math_abs(l - prev)
                if t % 8 == 0 then -- pair (t-1, t) straddles a boundary
                    b_sum = b_sum + d; b_n = b_n + 1
                else
                    i_sum = i_sum + d; i_n = i_n + 1
                end
            end
            prev = l
            seg_sum = seg_sum + l; seg_sq = seg_sq + l * l; seg_k = seg_k + 1
            if seg_k == 8 then
                local m = seg_sum / 8
                local var = seg_sq / 8 - m * m
                if prev_seg_mean then q_sum = q_sum + math_abs(m - prev_seg_mean) end
                qn_sum = qn_sum + (var > 0 and var ^ 0.5 or 0.0)
                q_n = q_n + 1
                seg_sum, seg_sq, seg_k = 0.0, 0.0, 0
                prev_seg_mean = m
            end
        end
    end

    for r = 0, BK.rows - 1 do
        scan(1, math_floor((r + 0.5) * h / BK.rows))
    end
    for c = 0, BK.cols - 1 do
        scan(0, math_floor((c + 0.5) * w / BK.cols))
    end

    if b_n == 0 or i_n == 0 or q_n == 0 then return nil end
    local pair_ratio  = (b_sum / b_n) / (i_sum / i_n + 1e-6)
    local quilt_ratio = (q_sum / q_n) / (qn_sum / q_n + 1e-6)
    return { pair = pair_ratio, quilt = quilt_ratio }
end
bk_sample_frame = COST.wrap("BK", bk_sample_frame_raw)
end

-- Calibration measured against real encodes: clean/high-bitrate files
-- sit at 1.1-1.2 on both ratios, mid encodes ~1.6/2.2, harsh ones
-- 2.0-3.5. max() so a deblocker that hides one signature cannot hide
-- the file entirely.
local bk_reprobe -- fwd: initial probe schedules the first re-probe

--  RING PROBE (RG) — edge-ringing / mosquito damage, same screenshot-raw
--  contract as BK. Where BK reads the codec grid sparsely (one value per
--  file), ringing is a scene property: RG samples the center crop densely
--  and keeps a smoothed current reading. Absorbed from photon-ghost.lua —
--  a sensor belongs in the hub, not in its own VM.
--  Calibration (measured corpus): clean 2.3-3.1, grainy 1.3, harsh
--  encodes 10.5-19.6 on the zone/non-zone HF ratio.
local RG = {
    interval = 4.0,   -- seconds between frame samples, same cadence as BK
    crop     = 512,   -- max side of the native-res center crop
    ema      = 0.35,  -- per-sample smoothing
    min_zone = 200,   -- skip frames with too few edge-zone pixels
    timer    = nil,
    ring     = nil,   -- smoothed ratio, nil until first sample
    samples  = 0,
    last_bucket  = nil, -- last logged level bucket (0.25 steps)
    fail_streak  = 0,   -- consecutive nil samples, for the one-shot warn
}

-- One screenshot-raw frame → ring ratio or nil. bgr0/stride contract
-- identical to bk_sample_frame.
local rg_sample_frame
do
local function rg_sample_frame_raw()
    local ok, shot = COST.shot()
    if not ok or not shot or not shot.data or not shot.w or not shot.h then
        return nil
    end
    if type(shot.data) ~= "string" then return nil end
    local data, w, h = shot.data, shot.w, shot.h
    local stride = shot.stride or (w * 4)

    local cw = math_min(w, RG.crop)
    local ch = math_min(h, RG.crop)
    if cw < 32 or ch < 32 then return nil end
    local ox = math_floor((w - cw) / 2)
    local oy = math_floor((h - ch) / 2)

    -- luma plane
    local L = {}
    for y = 0, ch - 1 do
        local row = (oy + y) * stride + ox * 4
        local base = y * cw
        for x = 0, cw - 1 do
            local b, g, r = string.byte(data, row + x * 4 + 1, row + x * 4 + 3)
            if not r then return nil end
            L[base + x] = 0.299 * r + 0.587 * g + 0.114 * b
        end
    end

    -- separable box3 blur. The horizontal pass must cover EVERY row the
    -- vertical pass reads (y-1..y+1 for y=1..ch-2 → rows 0..ch-1) —
    -- an uncovered row nils the vertical pass's arithmetic.
    -- Border columns stay unset and are excluded from all stats.
    local T = {}
    for y = 0, ch - 1 do
        local base = y * cw
        for x = 1, cw - 2 do
            T[base + x] = (L[base + x - 1] + L[base + x] + L[base + x + 1]) / 3
        end
    end
    local B = {}
    for y = 1, ch - 2 do
        local base = y * cw
        for x = 1, cw - 2 do
            B[base + x] = (T[base - cw + x] + T[base + x] + T[base + cw + x]) / 3
        end
    end

    -- edge mask on luma gradient, then Chebyshev-2 dilation in two passes
    local edge = {}
    for y = 1, ch - 2 do
        local base = y * cw
        for x = 1, cw - 2 do
            local i = base + x
            local gx = math_abs(L[i + 1] - L[i])
            local gy = math_abs(L[i + cw] - L[i])
            if gx + gy > 30 then edge[i] = true end
        end
    end
    local hd = {}
    for y = 1, ch - 2 do
        local base = y * cw
        for x = 1, cw - 2 do
            local i = base + x
            if edge[i - 2] or edge[i - 1] or edge[i] or edge[i + 1] or edge[i + 2] then
                hd[i] = true
            end
        end
    end
    local zone = {}
    for y = 3, ch - 4 do
        local base = y * cw
        for x = 1, cw - 2 do
            local i = base + x
            if hd[i - 2 * cw] or hd[i - cw] or hd[i] or hd[i + cw] or hd[i + 2 * cw] then
                zone[i] = true
            end
        end
    end

    local num, den, zn, rn = 0.0, 0.0, 0, 0
    for y = 1, ch - 2 do
        local base = y * cw
        for x = 1, cw - 2 do
            local i = base + x
            local hfv = math_abs(L[i] - B[i])
            if zone[i] and not edge[i] then
                num = num + hfv; zn = zn + 1
            elseif not zone[i] then
                den = den + hfv; rn = rn + 1
            end
        end
    end
    if zn < RG.min_zone or rn < 1 then return nil end
    -- rn >= 1 above counts the denominator PIXELS, not their energy: an
    -- all-flat surround gives den == 0 and the ratio would blow up
    -- instead of reading as "no ring". Unmeasurable, not extreme.
    if den <= 0 then return nil end
    return (num / zn) / (den / rn)
end
rg_sample_frame = COST.wrap("RG", rg_sample_frame_raw)
end

local function rg_level(ring)
    if ring <= 4 then return 0.0 end
    if ring >= 10 then return 1.0 end
    return (ring - 4) / 6
end

local function rg_tick()
    -- Wall-clock timer: gate here instead of kill/reinstall so a paused
    -- player or a toggled-off engine costs one boolean check per tick.
    if not (enabled and playback_active) then return end
    local r = rg_sample_frame()
    if r then
        RG.fail_streak = 0
        RG.ring = RG.ring and (RG.ring + RG.ema * (r - RG.ring)) or r
        RG.samples = RG.samples + 1
        photon_scene_ring   = RG.ring
        photon_scene_rlevel = rg_level(RG.ring)
        -- Log optics: first reading per file, then only meaningful level
        -- moves (0.25 buckets) — a line every 4s would be spam.
        local bucket = math_floor(photon_scene_rlevel * 4 + 0.5) / 4
        if RG.samples == 1 then
            mp.msg.info(string.format(
                "photon: ring first reading — ring=%.2f level=%.3f",
                RG.ring, photon_scene_rlevel))
            RG.last_bucket = bucket
        elseif bucket ~= RG.last_bucket then
            mp.msg.info(string.format(
                "photon: ring level %.3f → %.3f (ring=%.2f)",
                RG.last_bucket, bucket, RG.ring))
            RG.last_bucket = bucket
        end
    else
        RG.fail_streak = RG.fail_streak + 1
        if RG.fail_streak == 5 then
            mp.msg.warn("photon: ring frame sampling failed 5 ticks in a row — screenshot-raw unavailable?")
        end
    end
end

RG.timer = mp.add_periodic_timer(RG.interval, rg_tick)

--  GRAIN-SIZE PROBE (GS) — native-res apparent-grain cluster estimation,
--  live per-scene, deconvolved from the engine's own synthetic field.
--  (Literature: in color negative the image is dye clouds, not crystals;
--  perceived grain is an aggregate far larger than one particle. What GS
--  measures is the cluster's spatial correlation width, not a crystal.) The ffmpeg
--  128px energy path cannot see crystal size: at 128px wide a 2-3px
--  crystal is sub-pixel, so rel energy tracks grain amount and encode
--  harshness, never size (matrix-verified: rel saturates and even
--  inverts for coarse grain). Crystal size is spatial: GS high-passes a
--  native-res crop with a box9 (kills content structure), keeps the
--  flattest third of 32x32 blocks (edges lie), and takes the lag where
--  normalized autocorrelation falls to 0.05 - for blocky crystals that
--  crossing IS the diameter; real film behaves the same way.
--  Validated offline: est 1.0/1.9/2.5 vs true 1/2/3 at 1080p; clean
--  files read 0; saturates above ~4px, floors near ~1.5px below 720p.
--
--  LIVE DECONVOLUTION: screenshot-raw captures the frame WITH the engine's
--  grain applied, so a naive live probe measures its own output and runs
--  away (stress-log confirmed: hint 2.06->2.43->2.98->3.23 in one file).
--  The synthetic field is fully known, though: photon-grain publishes its
--  rendered size/development/strength, the scene feed is ours, and the
--  field's normalized autocovariance + HP variance per eff-size are
--  precomputed below (offline simulator of sample_bluenoise/grain_layers,
--  anchored against the runaway log: probe reads ~2.9/3.5/3.8px for eff
--  ~2.1/2.5/3.1px, model reproduces 3.3/3.5/3.7). The probe subtracts the
--  synthetic covariance from the measured one; the crossing of what is
--  LEFT is the source's own grain size. Deliberately under-subtracts 10%
--  (sub_factor): the amp model overshoots ~6-12% (clean-file residual
--  -6..-12%), and a small synthetic leak is safer than negative energy.
--  Uncertainty NEVER renders an extreme: a weak corrected signal holds
--  the last committed hint; no last hint means the default base stands.
--  Validated offline (sim, canonical tables): source recovery within
--  1-8% whenever the source owns >=10% of measured HP power, degrading
--  to 15-37% at ~5% (gated: those samples hold); clean files subtract to
--  ~0 and fall through to the strength top-up; weight-shift of the layer
--  mix (dark scenes) costs 2-4%.
local GS = {
    interval = 4.0,
    crop     = 384,
    block    = 32,
    max_lag  = 24,
    window   = 5,      -- raw estimates kept for the median filter (live, per scene)
    luma_jump = 0.35,  -- frame-luma jump = scene cut: skip the sample
    timer    = nil,
    hist     = {},     -- raw native-px estimates (median filter)
    prev_luma = nil,
    est      = nil,    -- median cluster px at native res
    samples  = 0,
    -- The governor holds the last size hint through uncertainty.
    last_mult = nil,   -- last strength multiplier sent
    mult_deadband = 0.05,
    mult_slew = 0.10,  -- max change of the applied multiplier per update
    mhist = {},        -- last GS.window valid mult samples, per scene
    -- Size confidence, bounds and deadband live in SIZE_GOV.
    -- TUNABLE strength top-up envelope (1.25 = his accepted max)
    -- No hardcoded strength floor or ceiling: the multiplier is derived each
    -- sample from measured source noise. Only a physical floor of 0 remains.
    mult_floor = 0.0,
    -- F10 OFF keeps the legacy fixed behaviour exactly: fixed target and the
    -- old clamp. These two numbers are used ONLY while adaptive is OFF.
    legacy_min = 0.40, legacy_max = 1.25,
    src_share_min = 0.10,  -- corrected source share below this = noise: hold
    sub_factor  = 0.90,    -- under-subtract: leak beats negative energy
    -- LOOK set point = how much total grain-band power the picture should
    -- carry, in units of the frame's own synthetic power at default strength.
    -- It is the owner's look, not a strength: strength is derived from it and
    -- from the measured source noise on every sample. look_R is learned from
    -- his own manual strength changes (measured on the frame he accepted) and
    -- kept in a state file. look_seed is used only until he has set one
    -- (accepted look 6.25/5.00 squared); disclosed, Mac-pending.
    look_seed = (6.25 / 5.00) ^ 2,
    look_R = nil,
    look_learn = nil,   -- samples collected after a proven manual control revision
    look_learn_revision = nil,
    look_consumed_revision = nil,
    r_total = nil,      -- measured total/ synthetic-basis ratio of the last sample
    last_noise_share = nil, -- 118h: source-noise share of the last valid reading
    last_noise_at = nil,    -- 118h: mp.get_time() of that reading
    look_path = nil,
    strength_default  = 5.00, -- GRAIN_BASE_STRENGTH factory default
    cf2      = 0.40,   -- luma-of-mixed-channels variance factor (CS=0.5, HP5)
}

--  Rendered grain state mirrored from photon-grain's hud-state broadcast.
--  ts staleness gates subtraction: a live engine publishes at 1Hz, so a
--  stale mirror means the values cannot be trusted and the sample is
--  skipped (hold) rather than risking a wrong subtraction.
local GR = {
    enabled = false, amount = 1.0, strength = 5.0,
    size_rendered = 1.2, dev_rendered = 0.4, ts = 0,
    soft_rendered = 1.0,  -- rendered GRAIN_SOFTNESS (0.70-1.00 auto); keys the tables
    weight_shift = 0.0,   -- rendered layer-weight shift (dark-scene rebalance)
    res_adapt = 1,        -- rendered RES_ADAPT toggle (0 = profile off: 1.0/1.0)
    amount_gpu = 1.0,   -- amount AFTER the shader's clamp(GR_AMOUNT,0,2)
    user_offset = 0.0,  -- his manual amount crank; must not move the target
}
local GR_STALE_S = 5.0

--  Synthetic-field deconvolution tables, generated offline by gs_sim
--  (model of photon-grain.lua sample_bluenoise/grain_layers, sigma=0.7
--  blue-noise stand-in, exact 4-tap kernel; baked over softness
--  (0.70/0.85/1.00) x layer-weight shift (-0.30..+0.30) and lerped
--  to the rendered values. ac = normalized autocovariance of the
--  box-k high-
--  passed unit field, pooled over all 32x32 probe blocks; var = its
--  mean block HP variance at unit amplitude. Rows: eff size 0.5..8.
local GS_SYN_S = {0.5,1,1.5,2,2.5,3,3.5,4,4.5,5,5.5,6,6.5,7,7.5,8}
local GS_SOFT_LEVELS = {0.70, 0.85, 1.00}
local GS_MIX_LEVELS = {-0.30, -0.15, 0.0, 0.15, 0.30}
local GS_SYN_AC9 = {
  {
    {
      {0.1789352155,0.01283361327,-0.03642808173,-0.0403353729,-0.005738080196,0.008405905294,0.008686164052,-0.0001021948024,0.01073912991,0.004316276864,0.004395119403,-0.01134030705,-0.01005401659,-0.001422759422,-0.001666233465,0.3139304221,-0.0008155178159,-0.009457715891,-0.0131189928,-0.01443029105,-0.002365873288,-0.00139061933,0.002005827145,-0.003016700431},
      {0.3651346838,0.06937990434,-0.03305864452,-0.05077318918,-0.02655314792,-0.00644456903,-0.001240949016,0.002999515295,0.01072124446,0.009782063639,0.001431027517,0.001497721576,0.003426077859,-0.0004831925133,-0.005702270136,-0.001261893769,-0.002690100355,-0.004283496155,-0.005515016788,-0.007936799468,-0.01185538766,-0.01323473391,-0.008534533171,-0.01581508047},
      {0.5413618678,0.1397119273,-0.03118471579,-0.06820531704,-0.03498954394,-0.004759032489,0.0008908281303,-0.004110782964,-0.007716685017,-0.007036781749,-0.003215337885,0.001964279757,0.004080421938,3.580563422e-05,-0.006104796479,-0.008158029484,-0.003108424286,0.003580710775,0.008610188096,0.008993642163,0.004803393668,0.001758925276,0.001162736374,0.001304726169},
      {0.5650100268,0.1909709694,-0.01321176269,-0.07351728268,-0.05275125307,-0.02195693176,-0.004113260457,0.004471218702,0.004591141343,0.001048616473,-0.0002196729745,0.0004764681196,-0.0002250587649,-0.003227023142,-0.006246765086,-0.001242343176,0.005981024783,0.008845496837,0.004076709326,-0.001499767086,-0.006071706393,-0.00728944441,-0.007734940382,-0.003773059779},
      {0.6573476363,0.2674956283,0.01313255819,-0.0772347785,-0.06814109816,-0.03720805354,-0.01419837735,-0.004760133548,-0.002444607824,-0.002692603118,-0.004349693929,-0.004993656207,-0.001680922628,0.004416256357,0.007112997541,0.007064245248,0.005845809862,0.00262206712,0.0008358801044,0.003094876323,0.006396636452,0.008242179708,0.0066594183,0.004340131388},
      {0.6896108078,0.3191127078,0.03960025934,-0.07062162123,-0.07715244012,-0.05020812408,-0.02474487701,-0.00895545039,-0.001924227221,0.001068129178,0.002938224167,0.003435799295,0.001820737668,-0.002127434737,-0.004056119438,-0.001090086198,0.004507381856,0.009698137234,0.01222709516,0.007376786836,-0.003739392589,-0.01404742635,-0.01752854808,-0.01254144013},
      {0.7054390294,0.3452927228,0.07816239051,-0.06293401703,-0.08102029179,-0.05866083381,-0.03198138969,-0.0177278185,-0.009326525142,-0.004171660335,-0.001247511168,0.0004412182038,0.002564157865,0.003217402313,0.00120414419,-0.003005886911,-0.008020892665,-0.009807518899,-0.006642763744,-0.0002372214701,0.007491565704,0.0142719637,0.01718919052,0.01445449798},
      {0.7218298769,0.3617818272,0.1107909088,-0.05287505232,-0.08058164766,-0.06755542621,-0.0446471083,-0.02594040969,-0.01746651831,-0.009531168449,-0.006573171907,-0.005048905198,-0.004203346517,-0.003195116569,-0.0009506171009,0.0008253708891,0.002211866545,0.001608569002,0.002274276801,0.004524625256,0.006082356903,0.007706078322,0.006302462376,0.004281328907},
      {0.7287548935,0.3940769894,0.1481840713,-0.02065473509,-0.07620408156,-0.07120880737,-0.04892319917,-0.0272957579,-0.0173595796,-0.01320539625,-0.006708530133,-0.002809399459,-0.0005598412715,-0.001040636862,-0.002924499149,-0.003099002307,-0.0021767642,-0.0003831392788,0.0005817133527,9.555965361e-05,-0.001243971332,-0.002603459663,-0.000772727106,0.002002361568},
      {0.7355183524,0.4165526973,0.164956162,0.001342009579,-0.07486832939,-0.07337836465,-0.05345752289,-0.02937906486,-0.01177230776,-0.005625100503,-0.006352818264,-0.003380816215,-0.003108704677,-0.002900391787,-0.002109837181,-0.003440681026,-0.001957860717,0.001117141895,0.003315075761,0.004206694595,0.003961566351,0.0009919586948,-0.001369948591,-0.004842589277},
      {0.7347512793,0.433977891,0.1679156541,0.02788258834,-0.05544992498,-0.08030322405,-0.06316981644,-0.04185753952,-0.02211784175,-0.01334820461,-0.01024711477,-0.01023300131,-0.004639745199,-0.0004731670721,0.0002099366558,0.0001783663613,-0.0006203102923,-0.001433582727,-0.001793704248,-0.002842780673,-0.004418175298,-0.006489249753,-0.006002934946,-0.00543326986},
      {0.740463047,0.4554578189,0.1771016332,0.05014334274,-0.02987475223,-0.07957505453,-0.06585959302,-0.04720837621,-0.02501173104,-0.008572647837,-0.001352611307,0.0001988480055,-0.002529152281,0.0003180376346,0.00317715934,0.005896825082,0.009144400993,0.01084623312,0.0104724507,0.009472330583,0.009122631669,0.007473568391,0.004351963026,0.001892371883},
      {0.7375350955,0.4612431156,0.197243214,0.05956273349,-0.008403476927,-0.06280689678,-0.07269836751,-0.05409703787,-0.03321794801,-0.01442683892,-0.004968752624,-0.0002225851908,-0.001019576224,-0.004412164203,-0.00526756449,-0.00577240869,-0.006738705486,-0.006986100498,-0.00534311768,-0.0017794092,0.002387474608,0.006628938881,0.008256219463,0.006760332232},
      {0.7346216883,0.4674604931,0.222516205,0.0691133159,0.01881154278,-0.03805484681,-0.07390529457,-0.05720404794,-0.03982859316,-0.02095549535,-0.007188935136,-0.00212010995,0.001779427955,-0.0004522796199,-0.004311061845,-0.001876021749,-0.001512015238,-0.0002465740453,-0.000422620031,-0.0005203929178,-0.003456499773,-0.004359760349,-0.002243808441,-0.001318037837},
      {0.7320419334,0.4687139015,0.2360002724,0.06580604571,0.02935234687,-0.01426318371,-0.05326757012,-0.06028362608,-0.04368397729,-0.02550881046,-0.01040042548,-0.0006041500973,0.000396107454,0.003284177136,0.002854124672,0.0005325289415,0.001580597634,0.003880615641,0.004914951756,0.00275559889,-0.0005526752232,-0.005644846406,-0.01058042256,-0.009491423095},
      {0.7237918575,0.4672522475,0.2452054773,0.05826992454,0.03555688983,-0.0002970944953,-0.0369565216,-0.06333725715,-0.04597872077,-0.02586842434,-0.009820417279,-0.001221557743,0.00161489305,0.002544954996,0.002625728292,-0.0001305602544,-0.005085783335,-0.008172220387,-0.003667533707,-0.002125680431,-0.0008523818649,-0.002091419031,-0.004425881046,-0.003070786234},
    },
    {
      {0.1744615313,0.01204242567,-0.03583006225,-0.03973726714,-0.003897517225,0.008166330608,0.009602701156,0.0005156652642,0.01057496481,0.004702154737,0.005179953394,-0.01183648465,-0.009946565361,-0.001916965143,-0.003252776407,0.3088981763,-0.002654433984,-0.008210005155,-0.0132646784,-0.01415026303,-0.002537722177,-0.0030654085,0.002318870545,-0.001567066718},
      {0.3640306377,0.0673956658,-0.03271267035,-0.05037728476,-0.0258265803,-0.006149225051,-0.000789867269,0.00310254474,0.01005598368,0.01016552407,0.001847509676,0.000944480914,0.002822522137,-0.001312205027,-0.006282785367,-0.0006494203323,-0.00186040276,-0.003000067371,-0.0051470304,-0.007555236072,-0.01022951981,-0.01047661535,-0.006567121017,-0.01512774619},
      {0.5181028433,0.1319693105,-0.02968612284,-0.06414786534,-0.03039308158,-0.002533879873,0.001643949511,-0.003044602325,-0.006082198691,-0.004974809948,-0.001628528598,0.001862106801,0.004143149931,0.0009550947318,-0.003572634673,-0.005266295487,-0.0009929098874,0.004995257901,0.009140027062,0.01025322724,0.005633994915,0.0009554488286,-0.001026320162,-0.0009649792922},
      {0.5602763872,0.1856875399,-0.01137524668,-0.07109979645,-0.05008602998,-0.02035342463,-0.004317108303,0.00333368241,0.003164288603,0.0004901587211,0.0003875655066,0.001779995157,0.001380365263,-0.002515392552,-0.006270657014,-0.001872160912,0.005140197865,0.007638349303,0.00289950451,-0.002469217018,-0.006677452705,-0.005783112759,-0.004662812516,-0.001052427932},
      {0.6345160725,0.2521952845,0.009903680691,-0.07290134127,-0.06308342288,-0.0342404282,-0.01266755685,-0.003825051677,-0.0009944388362,-0.0005968052495,-0.002823372423,-0.004750559518,-0.003020802776,0.002397683412,0.005596908615,0.006636118354,0.006203357617,0.003389931798,0.0005818752315,0.001777714096,0.005007628654,0.007888773699,0.006194824976,0.004648630618},
      {0.6688608682,0.3015359046,0.03468438298,-0.06529925762,-0.06716927488,-0.04264333196,-0.02064925613,-0.007006300494,-0.001282930322,0.0007886382335,0.002100352028,0.002217412095,0.0007750440721,-0.002661556322,-0.004329166508,-0.001956606014,0.00253990648,0.007262219398,0.01043734797,0.00670862952,-0.003568239525,-0.01291535637,-0.01601059963,-0.01207000457},
      {0.6873985426,0.3244949114,0.06969617728,-0.06122681595,-0.07223754857,-0.04981702656,-0.02779937313,-0.01713953239,-0.01045895477,-0.00545617996,-0.001866058655,-0.0002158359819,0.002076051021,0.003225212291,0.001676188457,-0.001894000748,-0.006152964941,-0.007197302755,-0.004044155085,0.001237957677,0.007722032384,0.01264443004,0.01377755404,0.009796541326},
      {0.702931335,0.3441408297,0.1045167031,-0.05044103785,-0.07089470635,-0.05728692996,-0.03702839939,-0.02287104092,-0.01648708646,-0.008732043009,-0.005033496415,-0.003006302452,-0.002129359093,-0.001145172254,0.0008363578373,0.002102522028,0.002482329442,0.001114487289,0.001375587302,0.003283482188,0.00367052997,0.005435691798,0.004675729844,0.003136495269},
      {0.7149687252,0.3713133501,0.1330716382,-0.02144712625,-0.06805605535,-0.05922284397,-0.03906966645,-0.02218042421,-0.01511106083,-0.01177684442,-0.004961585468,8.660632464e-05,0.002440069972,0.0009277488155,-0.001911442603,-0.002634514266,-0.001795701426,-0.0003861726541,0.000361112172,-0.001147898666,-0.003497198026,-0.004665495776,-0.002487292723,0.001119740432},
      {0.724022403,0.3959832162,0.1491266699,0.0005294695797,-0.06810931672,-0.06280054937,-0.04333394587,-0.02199575427,-0.007398040736,-0.003120550196,-0.00523500874,-0.002737449093,-0.002885819482,-0.003770574897,-0.003711033888,-0.004049639746,-0.001750804322,0.001374537107,0.004096541945,0.00482206161,0.004916850406,0.002164390878,2.7875265e-05,-0.00437999913},
      {0.7262640207,0.4149322778,0.1535207869,0.02254211764,-0.04783363457,-0.06716009945,-0.05003787569,-0.03105536652,-0.01451428344,-0.008037348086,-0.007096479304,-0.009080731399,-0.004981236008,-0.001587177507,0.0002833359279,0.001026623892,0.0007985227042,-4.111184428e-05,-0.001066813936,-0.002854703628,-0.003937094346,-0.004816787596,-0.00311766889,-0.0009627052558},
      {0.7326411422,0.4339357194,0.1598185946,0.04297881826,-0.02122595658,-0.06477162699,-0.05060902162,-0.03333436986,-0.01368134724,0.0009531605212,0.005714876319,0.005045155041,0.0006923794922,0.001798830817,0.00340296769,0.005540026001,0.008128602441,0.009573982611,0.00903605308,0.008888083138,0.009973377351,0.009231400746,0.007194183575,0.003202153844},
      {0.7319925736,0.4433047567,0.1787522848,0.05064584821,-0.004699330591,-0.04966437127,-0.05877288759,-0.04168663171,-0.02264751475,-0.005932024588,0.002094493534,0.004163488925,0.001740790088,-0.003067626646,-0.004344572657,-0.00465271473,-0.004811633571,-0.004738115418,-0.002999315542,-0.000236865271,0.001739010577,0.004851654356,0.006035753064,0.005674773879},
      {0.7306263957,0.4517058103,0.2037860196,0.0594781073,0.01876562884,-0.02560603064,-0.0595524973,-0.04503503841,-0.03056141818,-0.0150448829,-0.003313856335,0.001269364167,0.002722325373,-0.00113056261,-0.005822491802,-0.003794607202,-0.001750288434,0.0001692572217,-0.0002015682492,-6.335603973e-05,-0.003433960997,-0.004219933849,-0.001820633644,7.129559885e-05},
      {0.7312661198,0.4585775343,0.2206390131,0.05869230033,0.02944689505,-0.005749098815,-0.0408420149,-0.04956248088,-0.03587870305,-0.01993009158,-0.006729788771,0.001427241867,0.002998064657,0.004234819782,0.002127858152,-0.0007751834812,-0.0008947099997,0.0009220159807,0.002187487576,-0.0002787966834,-0.003700409111,-0.008501078091,-0.01238391851,-0.009390069654},
      {0.7195127175,0.4550626749,0.2262822801,0.05267829363,0.03958191354,0.01008631934,-0.01948727938,-0.0487925977,-0.03400731872,-0.01733135356,-0.004253314347,0.003176784242,0.004881682616,0.005665139027,0.005518680431,0.002847552711,-0.002339729629,-0.00619988827,-0.003286502026,-0.002846922321,-0.001484291841,-0.00093496364,-0.001458780485,-0.0004277369568},
    },
    {
      {0.1680005007,0.0108483302,-0.03504261499,-0.03797755746,-0.002717386368,0.007615741906,0.01010707087,0.0008526908434,0.009439650688,0.004596713526,0.005740570006,-0.01154233097,-0.009599009791,-0.002365475133,-0.00519973639,0.3022825549,-0.003596124542,-0.005780248123,-0.01266394629,-0.01267915189,-0.002185055673,-0.004350011469,0.002917435145,0.000146786893},
      {0.3613101273,0.06509301444,-0.03181684982,-0.04848134807,-0.02358131939,-0.005022075374,0.0001303212736,0.003639644054,0.00950077748,0.009128393897,0.002008775564,-9.899518862e-05,0.001924590541,-0.002225439599,-0.006691651307,-0.0008520530308,-0.001646534093,-0.001954882097,-0.003697903221,-0.005850782259,-0.007847774896,-0.007888862568,-0.005738429587,-0.01405829202},
      {0.4905338494,0.1223956813,-0.02840873177,-0.05971726379,-0.02481528342,0.0005758316734,0.003195950805,-0.002190194993,-0.006111743819,-0.004854979053,-0.001301603018,0.001491672334,0.004033635633,0.001473791117,-0.001580528796,-0.002973116681,0.0003887924942,0.005123389684,0.008172893623,0.009303282272,0.005864381735,0.001555376957,-0.001089824142,-5.615429252e-05},
      {0.5544089685,0.1786943968,-0.009024337893,-0.06778990981,-0.04640844031,-0.01694429683,-0.002036173996,0.004827635344,0.003968293137,0.001207372737,0.001035988009,0.001522679004,0.001124251656,-0.003214801323,-0.00658773156,-0.00174222031,0.00617594721,0.009161026014,0.003994192899,-0.001517208861,-0.005510328796,-0.004793880132,-0.003465087332,0.0002083970044},
      {0.6088477945,0.2357548839,0.007447443341,-0.06652294088,-0.05560044433,-0.02925970363,-0.009896175226,-0.002467791603,-0.0004791667725,-0.0006424412665,-0.003445391965,-0.005167541896,-0.003339697511,0.001786608375,0.003999403295,0.004479061664,0.004522773051,0.00305430108,0.001177483029,0.002655470739,0.005865717575,0.008519424208,0.006515366323,0.00514230614},
      {0.6458179113,0.282063935,0.02930363451,-0.05948016665,-0.05637835752,-0.03467721038,-0.0167948833,-0.005240926759,0.0001116514188,0.002191618777,0.003750124809,0.004264731114,0.002890890592,-0.0009624277471,-0.003025745009,-0.0009434885288,0.003456897704,0.007992425882,0.01011948736,0.006079251703,-0.003262384441,-0.01084732161,-0.0130271644,-0.009588582374},
      {0.6676570809,0.3019217046,0.06111361749,-0.05783268751,-0.06057178377,-0.03788954352,-0.02025751681,-0.01327099285,-0.008219562685,-0.004302764562,-0.001060228852,0.000157998666,0.00178496574,0.002650561227,0.001165160599,-0.001802133004,-0.005139355142,-0.005427561118,-0.002361256989,0.001309249581,0.005861335659,0.009390590298,0.01004961715,0.007147557969},
      {0.683252558,0.3246300042,0.0977833495,-0.04787184625,-0.05948359016,-0.04498635154,-0.02754076737,-0.01833450123,-0.01482030719,-0.00679675897,-0.002085460564,0.0005952839464,0.001353162131,0.001067290214,0.00185085456,0.002617677994,0.001848127511,-0.0001050069134,-0.0008439464078,-0.000393980699,-0.0005552799932,0.002211976488,0.003137642127,0.003195009767},
      {0.7005704467,0.3485212062,0.1185027037,-0.02128482126,-0.05825400351,-0.04476116477,-0.02693275258,-0.01587588336,-0.01331549825,-0.01213221777,-0.005905220961,-0.0002327980652,0.002792361775,0.002037408217,-0.0003564585253,-0.0009848797893,-0.000755592132,0.0002111945007,-0.0003459262405,-0.002790009073,-0.005023481455,-0.004462528979,-0.00137508071,0.001399985602},
      {0.7109032677,0.3734826914,0.1321995592,4.392197329e-05,-0.06017783233,-0.05005627227,-0.0312162045,-0.01389580922,-0.003702587804,-0.002677617598,-0.006743842876,-0.004658587226,-0.004195783959,-0.004087932087,-0.002956707198,-0.002485686982,-0.0002883800736,0.002557853867,0.00529521276,0.005265108941,0.00374140055,0.0003121160787,-0.002833157625,-0.007144835208},
      {0.7170053847,0.394480003,0.1381349113,0.01778084797,-0.0390295872,-0.05247584428,-0.0358578915,-0.01996821764,-0.007491678663,-0.004024125559,-0.005690341798,-0.009255620014,-0.00546837006,-0.002042717219,7.255785065e-05,0.0003699909768,4.405548455e-05,-0.0006134937132,-0.00177399983,-0.003771650725,-0.004481361217,-0.004213119199,-0.002754796619,-0.0009845908793},
      {0.7238327098,0.4123384678,0.1426552707,0.03681994454,-0.01166795422,-0.04943441187,-0.03471401638,-0.0195036118,-0.003864836011,0.008047279351,0.009671779468,0.007081327845,0.000965362347,0.0007980246368,0.002433450552,0.004347445287,0.006531213836,0.006898866278,0.006648710786,0.007256313009,0.00905002816,0.008764304257,0.007484488012,0.003891501405},
      {0.725784435,0.4259054404,0.1617055518,0.04355575077,0.001084127847,-0.0354655598,-0.04396993678,-0.03000897109,-0.01437731177,-0.0007138132853,0.004943951073,0.004228746303,-3.686791246e-05,-0.004784751775,-0.005791885693,-0.005088643783,-0.004618960638,-0.003388551689,-0.00167626544,0.0006277174213,0.00144967846,0.003829440922,0.005023576299,0.006122054093},
      {0.7259492403,0.4364656207,0.1864885655,0.05159445918,0.02062568537,-0.0118976248,-0.04416349359,-0.03124699804,-0.01962289791,-0.007557871845,0.000950844393,0.00350583537,0.002275800823,-0.002776527718,-0.007453629459,-0.004390819326,-0.0005655636884,0.001088079292,-0.0004079172689,-0.001459515143,-0.00600398708,-0.006306069134,-0.004056016044,-0.001707050028},
      {0.7282321033,0.4462745242,0.2036509838,0.05081732113,0.03188151669,0.00626745502,-0.02382800142,-0.03425856192,-0.02403116389,-0.01087287736,-0.0003763000661,0.005506303468,0.00687804629,0.005889624405,0.002273001308,-0.001191161037,-0.002104521305,0.000558825531,0.001885336248,0.0004073228462,-0.002349433626,-0.00706755821,-0.01013681185,-0.006745408358},
      {0.7173659549,0.4453879947,0.2094717243,0.04575709316,0.04236017959,0.01949379639,-0.003426296136,-0.03497457213,-0.02294028434,-0.00930823561,0.001036258832,0.007153276056,0.007840788187,0.008725868286,0.007477011843,0.003679847776,-0.002383741477,-0.006224927278,-0.003479244444,-0.002161385063,0.000198271591,0.001436022598,0.001281779726,0.00140355388},
    },
  },
  {
    {
      {0.2425435342,0.02916825343,-0.04200794636,-0.04788050318,-0.01137379835,0.009196017096,0.011627045,0.00314975354,0.01184537959,0.004864055293,0.002168330955,-0.009044453291,-0.006643520663,-0.0009200595482,-0.001793840451,0.2196747371,-0.00233175287,-0.00871544003,-0.01179838325,-0.01120418824,-0.0007669972922,-0.000386853277,0.001902339612,-0.005109292682},
      {0.418395238,0.1036372976,-0.02557176949,-0.05566944031,-0.03524632152,-0.01466601966,-0.005730014309,0.0008509485221,0.009259304428,0.01051667994,0.005262036736,0.00468435107,0.004818646653,0.0003781522403,-0.006015247862,-0.003660385101,-0.003972756762,-0.003818496438,-0.003879323003,-0.006867088793,-0.01026552052,-0.01276839991,-0.01024167194,-0.0154587795},
      {0.5757316108,0.1807632709,-0.01397970721,-0.06789114062,-0.04244902131,-0.01399149908,-0.005661753898,-0.007879559215,-0.01037900036,-0.008418161479,-0.003760663346,0.0009127550607,0.002895210772,0.0001061243781,-0.003484593022,-0.004542186577,-0.0008507844249,0.00518924104,0.009402834975,0.009766418431,0.005659355278,0.001943885694,0.0001058626241,-0.0008144045185},
      {0.5946782935,0.2234078386,0.01164133146,-0.06738794776,-0.0580597068,-0.03008437389,-0.01138998016,-0.0009392341949,0.001013783105,-0.001487482621,-0.003156661995,-0.003087013371,-0.003434712517,-0.005026973551,-0.00614979494,-0.00113074147,0.005689521844,0.007693327865,0.002625234247,-0.002134383435,-0.005073753813,-0.004622524866,-0.003407551207,-0.00034768853},
      {0.6697235072,0.2918722295,0.0376809227,-0.06272131453,-0.06829819016,-0.04507630436,-0.02196129272,-0.01062142943,-0.006792120307,-0.00588380568,-0.006343747827,-0.005423385473,-0.002239153676,0.003095064868,0.005507492451,0.006100531724,0.005753062151,0.004329269721,0.002695378017,0.004048360732,0.006474849651,0.007873984067,0.006421731214,0.004564460906},
      {0.6967927633,0.3403298222,0.06103398843,-0.05190229652,-0.06852470878,-0.05382673501,-0.03362130898,-0.01617271938,-0.00634467494,-0.001058745681,0.001808299666,0.002521645908,0.001462099001,-0.001672451899,-0.00314445061,-0.001337608767,0.002791118896,0.006631285779,0.007877634874,0.002399751874,-0.007140213019,-0.01397471716,-0.01411750276,-0.008050856489},
      {0.7089184682,0.3612178049,0.09711758737,-0.04502721255,-0.06747496281,-0.05545406484,-0.03805426138,-0.02702971722,-0.01461307095,-0.006248293265,-0.001583168741,0.0003308328712,0.001877799881,0.002408350174,0.001161051168,-0.001895758842,-0.005970905154,-0.006775535277,-0.003732046319,0.001039863949,0.005908513794,0.0102420594,0.01181013992,0.008772196736},
      {0.722414138,0.3780198476,0.1307798035,-0.03562798046,-0.062736635,-0.05743017939,-0.04389429777,-0.03304916835,-0.02829078487,-0.01597631969,-0.00813955957,-0.003010756357,-0.0005100881983,0.0003450979842,0.001246828882,0.002363454764,0.002381490979,-2.925494024e-05,-4.310311658e-05,0.001762970981,0.002467724098,0.005049939124,0.005846705467,0.005648801238},
      {0.7288545861,0.4060913215,0.1655198677,-0.005287586749,-0.06113140421,-0.05825088191,-0.04175455577,-0.0259660881,-0.02068449281,-0.01907305025,-0.009674625421,-0.003181955655,0.00124239258,0.0007305735235,-0.001921893535,-0.001798105496,-0.001092346553,0.0002220393637,0.001003254654,0.0005315693066,2.156010094e-07,-0.001171193061,0.0005548814721,0.002686004364},
      {0.734997077,0.4261261839,0.1828881569,0.01877457998,-0.05942564911,-0.05714424607,-0.04078259881,-0.02202697347,-0.01065264807,-0.01002451787,-0.01427109631,-0.007344487719,-0.003566195059,-0.001644477684,-0.0005298363192,-0.00262216693,-0.001385127955,0.001163257907,0.003071242607,0.004116475684,0.004334785392,0.001444465003,-0.001937961004,-0.006431847876},
      {0.7335756474,0.44046842,0.1830421008,0.0442996027,-0.03957347562,-0.06636673497,-0.05101121176,-0.03314951448,-0.0170539729,-0.01320630903,-0.01418194183,-0.01718069337,-0.008271130225,-0.001840197379,0.0003512597018,0.0005487452187,-0.000235464904,-0.0009853830596,-0.001747670143,-0.004478199684,-0.008166658534,-0.01051563524,-0.009219099113,-0.007354110315},
      {0.7384599092,0.4588545252,0.1934431144,0.06867753172,-0.00963917197,-0.06351521782,-0.04939345288,-0.03250473176,-0.01344031966,-0.001420055873,0.0001875593234,-0.002368822656,-0.008704942631,-0.00411151939,0.001562704868,0.004670451954,0.007591569266,0.008172810054,0.008606919276,0.007686433097,0.007782436978,0.0064905991,0.00338182585,7.702472972e-05},
      {0.7363198092,0.465874803,0.212401672,0.078064923,0.01182625631,-0.04564021445,-0.05862532903,-0.04151165999,-0.0232293165,-0.006818004941,-0.0008314356024,0.0006026430251,-0.00306123738,-0.01000590015,-0.009613996074,-0.008249866534,-0.00716543748,-0.006074111355,-0.003144948463,0.001071747493,0.003895737959,0.005834048975,0.006172442282,0.005374136678},
      {0.7313511694,0.4676250899,0.2320632006,0.08442929724,0.0378614026,-0.02027121836,-0.06098853975,-0.04438773863,-0.02853032022,-0.01189435378,-0.001152107418,-0.0003001181907,-0.001020944845,-0.007593765154,-0.01321403331,-0.008090062005,-0.003703135644,0.0001181536332,0.0004105369003,0.0003224425145,-0.002167997117,-0.002811726585,-0.000399963085,0.001826731104},
      {0.7295869056,0.4697180524,0.2457420074,0.08418783435,0.05082407372,0.00672234406,-0.03693924235,-0.04621646322,-0.03052436634,-0.01298719764,0.0006122169087,0.007964442328,0.004073212216,0.002775719994,-0.0008043482118,-0.003935125923,-0.00160301809,0.002144438196,0.004165100254,0.003355198515,0.0009606568965,-0.003074296251,-0.008319900025,-0.008722269854},
      {0.7211749028,0.4645657726,0.2504445983,0.07433964464,0.05389371838,0.01828476377,-0.0211679304,-0.05297402334,-0.03611914862,-0.01764029798,-0.003401878291,0.003926876429,0.005502840506,0.004771099179,0.003195712271,-0.00195066909,-0.009614822009,-0.01430369895,-0.008221251002,-0.005340108545,-0.002157810827,-0.001726893433,-0.002188610666,-0.0003974821343},
    },
    {
      {0.2368239982,0.02764551953,-0.04153721692,-0.04712330716,-0.009586740597,0.00968232561,0.01228785708,0.003450227444,0.01104914352,0.004960667931,0.002693931665,-0.009938862991,-0.00705783035,-0.00151901964,-0.003188741874,0.215080067,-0.002040541097,-0.005690234465,-0.01094637401,-0.01015278498,-0.0005365141925,-0.001587179503,0.002779583154,-0.002939848311},
      {0.4185020466,0.1012722206,-0.02534251848,-0.05495115584,-0.03332508973,-0.01293319953,-0.00424254295,0.001613147716,0.009462110925,0.01076588583,0.006070367813,0.004812829884,0.004860978638,0.0001511971391,-0.006243823588,-0.003392390684,-0.003035671038,-0.002277614484,-0.002991793692,-0.006290781377,-0.009212161235,-0.01029582437,-0.008280109008,-0.01438217457},
      {0.5543227662,0.171933818,-0.01437112616,-0.06485195951,-0.03725879275,-0.01032962296,-0.00329921544,-0.006061945149,-0.00889759678,-0.007086101225,-0.003242037969,0.0001109056484,0.002060473732,-0.0001317951289,-0.002734169686,-0.002959824521,0.001034418389,0.006809547526,0.01028958933,0.009671858156,0.004108691262,-0.0008299245783,-0.003627998609,-0.00285090164},
      {0.589212034,0.2177676232,0.01286993494,-0.06595480601,-0.05511720536,-0.02662044759,-0.009125598813,-0.0003500045708,0.0003697813645,-0.001612724377,-0.002424696459,-0.002076263737,-0.002041664608,-0.003959523693,-0.00554764733,-0.0006036071823,0.006789325314,0.008499121655,0.002461574451,-0.003274116866,-0.006056220994,-0.004730853099,-0.00195949487,0.001761829575},
      {0.6502711052,0.2777856878,0.03464900061,-0.05803235356,-0.06224593404,-0.0404972253,-0.01885045027,-0.008611587819,-0.005199407176,-0.004619380706,-0.005430900515,-0.005018926362,-0.002350246704,0.002644662518,0.004028545053,0.004156743029,0.004430273587,0.00402735092,0.002673240953,0.003443369481,0.006160288867,0.007397444532,0.005062530754,0.003429627638},
      {0.6792785901,0.3241213101,0.05600804223,-0.04691258518,-0.05895493939,-0.0460281,-0.02911005023,-0.01320009733,-0.003921448309,0.0003522444821,0.002359148031,0.002199746782,0.0007868020771,-0.002351594619,-0.003000478656,-0.0005728089274,0.003075073604,0.006297024474,0.007518526725,0.003218336869,-0.005078919696,-0.01065395847,-0.01087285361,-0.006752597871},
      {0.6933794077,0.3430451328,0.08967014288,-0.04252335784,-0.05825413205,-0.0461839669,-0.03324383182,-0.02589650759,-0.01504471633,-0.006504237159,-0.0009544970588,0.001021638169,0.002032614128,0.002118989711,0.000602124357,-0.002097061779,-0.004847422832,-0.004502992943,-0.0003928876136,0.003793978583,0.007524295844,0.009111974825,0.009327433592,0.006315441189},
      {0.7051746172,0.3612818535,0.1229810053,-0.03410815281,-0.05232473822,-0.04542307649,-0.03405700028,-0.02753156264,-0.0248045443,-0.0128440244,-0.005405542312,-0.001367898319,0.0004394528023,0.001067800508,0.002153492084,0.003135504551,0.001762344213,-0.0008032009478,-0.0001511735994,0.001337933938,0.001772151136,0.004107852835,0.004003108849,0.002345974201},
      {0.7172738154,0.3858167889,0.1508196461,-0.005718700232,-0.05223367323,-0.04495071274,-0.03052123701,-0.02065571705,-0.01990696102,-0.02067023025,-0.01141812037,-0.00335338249,0.002510141826,0.002699117514,0.0001508290921,-0.0002601659501,-0.0001522769439,0.0005752603564,0.001067004532,0.0006337632035,-0.0008866993339,-0.001765625676,-0.0009443589345,0.0004567191707},
      {0.7255548838,0.4085265067,0.1675240982,0.0178399059,-0.05259660743,-0.04627347455,-0.03013991294,-0.01474191936,-0.007143401051,-0.009131037171,-0.01437450629,-0.008185500451,-0.004241468979,-0.002429307707,-0.00131500018,-0.001820961404,0.0007366503435,0.003497454307,0.005503243874,0.005701263789,0.004027925872,-2.617590251e-05,-0.004272506525,-0.008900349882},
      {0.7261381612,0.4222681035,0.1679437956,0.0368412361,-0.03385901974,-0.05469833046,-0.03936294516,-0.02402234082,-0.01186306989,-0.01033317194,-0.01327075159,-0.01709176796,-0.008597557042,-0.001773590101,0.0009845360968,0.001655908554,0.000583785758,-0.0004210300443,-0.002215164684,-0.005282152243,-0.007716697258,-0.008276908234,-0.006694471179,-0.005670997773},
      {0.7304430653,0.4383356762,0.1756258914,0.05967174094,-0.003047687133,-0.05008112851,-0.03490059119,-0.01950427769,-0.00371717681,0.006252433597,0.005245966159,0.0006056443669,-0.007101915596,-0.004488237369,0.0005534189002,0.003673838712,0.006589789574,0.007607165416,0.008190465552,0.008741196083,0.009781192528,0.008146861331,0.005049153044,0.0005317882193},
      {0.7311479302,0.4503879401,0.1961433627,0.06970039125,0.01522341948,-0.03271630797,-0.043837625,-0.02855933451,-0.01283124999,0.0005144394004,0.004558072038,0.00322423606,-0.002046575973,-0.008900595122,-0.00862190588,-0.006242153138,-0.004171950893,-0.003001717789,-0.001506679082,0.0006100623472,0.001808141059,0.003950143027,0.004181017486,0.00454273266},
      {0.7276737811,0.4538095004,0.2151589929,0.07542719847,0.03710984018,-0.008702761648,-0.04639886919,-0.03117665838,-0.0179692743,-0.005353088252,0.002495470784,0.002911802848,0.001278522813,-0.006539294038,-0.01163186329,-0.006949236462,-0.001914235054,0.002196197374,0.001798376346,0.0008931652468,-0.002573110068,-0.0032903577,-0.001445573047,0.001231247306},
      {0.7286811809,0.4605546689,0.231665783,0.07758783301,0.05119929027,0.01594029598,-0.02195828782,-0.03245069952,-0.02054716668,-0.006879598459,0.003271382866,0.008154724764,0.005799782114,0.003892381078,-7.636504948e-05,-0.003670910287,-0.003577735246,0.000690769321,0.00260769045,0.001436165334,-0.001218106829,-0.005355510851,-0.009033052071,-0.006569701153},
      {0.7176502606,0.4542940802,0.234003451,0.06836460916,0.05533583033,0.02485618249,-0.007589796147,-0.0407889352,-0.02572359935,-0.009997994883,0.00173659782,0.007951832824,0.007392148888,0.005700384695,0.002851949109,-0.002759698914,-0.01008268755,-0.01410553036,-0.008817628331,-0.005833403227,-0.001634407117,0.00028773696,0.000485949087,0.0002917200884},
    },
    {
      {0.2280430751,0.025944217,-0.04041148497,-0.04585070295,-0.008282950911,0.00845012183,0.01241126722,0.003828121412,0.01020334672,0.005088828453,0.003863142927,-0.00966352568,-0.007358290405,-0.001897955943,-0.003854504346,0.2090200394,-0.002853346821,-0.003688270835,-0.01063413438,-0.009962781524,-0.0009569397495,-0.003546771375,0.002859626902,-0.002153945328},
      {0.417629729,0.09830533322,-0.02483519095,-0.05336644137,-0.03142581401,-0.0111646075,-0.002716203287,0.002374036509,0.009318159005,0.0109827066,0.0067439122,0.004256707967,0.005044718023,0.0001945936514,-0.005727303843,-0.002688864042,-0.001905769777,-0.0003942265922,-0.00204422766,-0.004929163347,-0.007516188591,-0.008028552213,-0.006893208357,-0.01310206092},
      {0.5296420121,0.1618287377,-0.01479517448,-0.06119706492,-0.03179595664,-0.007444979202,-0.002161896758,-0.004970327128,-0.007487555226,-0.005108906446,-0.001565074679,0.0002500771765,0.001811104941,-0.0003772347197,-0.002287823705,-0.002113324613,0.001317782665,0.006274957179,0.009035471305,0.008626570337,0.003452006167,-0.001252784351,-0.00409335994,-0.003410584338},
      {0.5831047607,0.2106998578,0.01483949878,-0.06320865979,-0.05088318744,-0.02292186234,-0.006958257004,0.0006862528463,0.0007193499102,-0.0005897347523,-0.000832100204,-0.0009464898581,-0.0006733904268,-0.002646477499,-0.004287102368,5.521663605e-05,0.006983991293,0.008696744149,0.00393336035,-0.001713725576,-0.004423570744,-0.003484209053,-0.001424247358,0.002355154436},
      {0.6280579004,0.2621233503,0.03198098633,-0.05232906286,-0.0555381039,-0.03574323306,-0.01547895901,-0.005543920805,-0.002204154452,-0.002476209755,-0.005008792245,-0.006160442044,-0.004065212673,0.0007627730327,0.002254143548,0.002216930109,0.002673680728,0.00250573795,0.0009476641016,0.001358807625,0.003764893857,0.005859240614,0.004411551186,0.00360026915},
      {0.6592687434,0.305580203,0.0502727884,-0.04177422514,-0.04836255181,-0.0373865526,-0.02430333124,-0.01125839213,-0.003920893877,-3.574638118e-05,0.002621625092,0.002871110688,0.001244089718,-0.001733278781,-0.002251984107,-0.0005002372803,0.00246662565,0.00495798837,0.006166512941,0.003662502488,-0.002672923087,-0.007329760512,-0.007663008347,-0.004518919419},
      {0.6772482394,0.3243006763,0.08214982943,-0.0393823416,-0.04754339291,-0.03503913284,-0.02619350949,-0.02213705035,-0.01325209131,-0.005911412715,-0.0008895091058,0.0006816348164,0.0009465881398,0.0002935484526,-0.000727387903,-0.002131991936,-0.003139418876,-0.001882189507,0.001534845268,0.003719165677,0.006394606463,0.007696898251,0.007368466616,0.004767463629},
      {0.6882463032,0.3441274151,0.1158781015,-0.03169489434,-0.04067118702,-0.03191343664,-0.02272491811,-0.02123974352,-0.02226573873,-0.01143717387,-0.004022432049,0.0005706568614,0.002978705077,0.003584876836,0.003642781018,0.003320786152,0.0006667550793,-0.001970036943,-0.001937092519,-0.0006820324321,-0.0003418219646,0.002409348967,0.003914544731,0.003608037117},
      {0.7048040372,0.3656221132,0.136968021,-0.005683670123,-0.04276031219,-0.0307524975,-0.01817968728,-0.01308767127,-0.01567797869,-0.0184902288,-0.009308861994,-0.001286114349,0.003684870996,0.003326760422,0.0008397036158,0.001217416808,0.002251536777,0.002963578127,0.002763794111,0.001000934026,-0.00186682151,-0.002154701166,-0.0005267307944,0.001991402087},
      {0.7137932083,0.3884139178,0.1512265735,0.01701036851,-0.04508679987,-0.03369162126,-0.01747903068,-0.00569354595,-0.001972780079,-0.006950634778,-0.01357547611,-0.006949607899,-0.002633002237,-0.0003407334679,0.0002121863148,-0.001243033775,0.0001736456164,0.00297194077,0.004909798344,0.004317218074,0.002607719904,-0.001515927167,-0.005899479394,-0.01039122786},
      {0.7179130536,0.4053806164,0.1553824454,0.03296224157,-0.02461534297,-0.03959587485,-0.02452726384,-0.01278663099,-0.005122223105,-0.006339004953,-0.01152670404,-0.01701483983,-0.00902565006,-0.002566193833,0.0005082248588,0.0001523925077,-0.0008475523703,-0.001550908723,-0.002785464185,-0.005813279816,-0.007142139845,-0.007038914133,-0.005573636886,-0.004930115528},
      {0.723174135,0.4203634354,0.1609023673,0.05279195929,0.004371804284,-0.03653456381,-0.02031448919,-0.006146094777,0.00640873055,0.01362838745,0.009370872767,0.001958068487,-0.006602754533,-0.003955946584,0.001141360205,0.004386664536,0.00723795058,0.00872439066,0.008765032641,0.008736810665,0.00860014936,0.00637883024,0.004631906194,0.001090609906},
      {0.726224094,0.4356303576,0.181076886,0.06190528169,0.01822044857,-0.02113830643,-0.03067068902,-0.01718239035,-0.003790510459,0.006565350864,0.008311484935,0.004384053276,-0.002283405307,-0.009530653155,-0.009121036139,-0.005796420344,-0.002899009741,-0.001258563408,-0.000496054127,0.0003060961825,-0.0003500884356,0.001736198065,0.002430656646,0.003981533573},
      {0.7247965414,0.4416186186,0.2003804937,0.06837613305,0.03742657367,0.00227627094,-0.03389217018,-0.0212054816,-0.01049409612,-0.0006640267089,0.005509206617,0.004970899726,0.001489824156,-0.006743035714,-0.01207657909,-0.00713911078,-0.001048367044,0.003207560779,0.002664457702,0.001548508947,-0.002415362065,-0.003587575481,-0.002403292959,0.0001206472631},
      {0.7263193533,0.4501001661,0.2164423923,0.07022554016,0.0523294405,0.02597141468,-0.006023469237,-0.01671282694,-0.007864362552,0.002534898829,0.008632473262,0.01033499582,0.008296909637,0.004269715318,-0.0008642502158,-0.005491314558,-0.005577228835,-0.0001018654943,0.002284473152,0.002188628867,0.0004164776092,-0.003949212246,-0.006629902345,-0.004494437851},
      {0.715984574,0.4462463737,0.219181763,0.06244346359,0.05750762794,0.03273604535,0.007402253726,-0.02745737797,-0.01438661178,-0.001895020125,0.006948042507,0.01116462725,0.009180754043,0.007145829491,0.003814268531,-0.001351071119,-0.008512806545,-0.01197171689,-0.007143509101,-0.00419641421,0.0007236373355,0.003856436857,0.004720753979,0.004397551067},
    },
  },
  {
    {
      {0.3106546531,0.04837124898,-0.04820027293,-0.05712967115,-0.01788938095,0.009338345076,0.01427342154,0.007424936633,0.01214306235,0.005157299317,-0.0007085138756,-0.008447145133,-0.005274636969,-0.0007590518362,-0.001450201691,0.1315739765,-0.003036806594,-0.007175273555,-0.008397111829,-0.006566076904,-0.0002608815802,-0.002048081645,0.0007790714068,-0.005830725307},
      {0.4782231774,0.1437227572,-0.01461922841,-0.06044671024,-0.04553372612,-0.02444701479,-0.01093229982,-0.001851697796,0.0066836199,0.009694675571,0.007720894598,0.007574741799,0.006389347325,0.001225830697,-0.005411227425,-0.004961578789,-0.003648576146,-0.002039373384,-0.002627096332,-0.00659383286,-0.01091022675,-0.01374687459,-0.01196599286,-0.0165247887},
      {0.6151100309,0.2294319214,0.007401674566,-0.06694450689,-0.05133332446,-0.0254882732,-0.01349013566,-0.01220842616,-0.01325902002,-0.01027164084,-0.005581654329,-0.001384803753,0.0006675981334,-0.001226299019,-0.003960440868,-0.003462523769,0.0009103857348,0.00726120226,0.01035048514,0.009304106399,0.00363886819,-0.0013991789,-0.003141222782,-0.002596596432},
      {0.631895601,0.2651985158,0.0426446586,-0.06149274806,-0.0658520671,-0.03969025561,-0.0187664617,-0.006371732844,-0.003404600466,-0.005217464234,-0.00717045484,-0.006972170926,-0.005818372035,-0.004700731194,-0.003684913932,0.000747470134,0.007030721735,0.008785296209,0.004409735271,0.0002629100861,-0.001567046378,0.0001195634367,0.002700170957,0.004750740154},
      {0.6877698023,0.3270234713,0.07253951759,-0.042434708,-0.06880862324,-0.05579140316,-0.03227297972,-0.01741003936,-0.0100825494,-0.008041971416,-0.008560002607,-0.00740086975,-0.004717500016,-0.0004753716486,0.001223685301,0.001931361646,0.003984943029,0.006024562869,0.005696638925,0.005199809912,0.005291969747,0.00436024233,0.00290229287,0.001977418672},
      {0.7072568204,0.3696111585,0.0915950951,-0.02545879965,-0.05556427097,-0.05694946975,-0.04344997866,-0.02414476661,-0.01193718804,-0.005310905388,-0.002466451261,-0.00219837239,-0.00180686632,-0.002291518139,-0.001479312445,0.0003961576788,0.003381605006,0.006346475987,0.007674187087,0.003641659806,-0.003500168212,-0.009471722058,-0.01028074435,-0.005273824275},
      {0.7146553477,0.3851010843,0.1258811536,-0.01831479824,-0.04740603445,-0.04945991288,-0.04588042622,-0.04063198682,-0.02494657667,-0.01232841039,-0.004216111648,-0.001264237121,-0.0007656224763,-0.000800433445,-0.001318575138,-0.002166797186,-0.003533118035,-0.003604871396,-0.001152569416,0.00237579459,0.004870283522,0.005890436595,0.005480893087,0.00236743918},
      {0.7217354115,0.3979866447,0.1557157833,-0.01372457068,-0.03763110289,-0.04044580176,-0.03752512764,-0.03617850341,-0.03739109625,-0.02211430768,-0.01153758781,-0.003680303676,0.0006174952965,0.001661363353,0.001859639972,0.002466609306,0.0009331303801,-0.00184325844,-0.001971859719,-0.0009397689568,-0.0004490056195,0.002648100843,0.005442861979,0.005143048571},
      {0.7296652943,0.4218542109,0.1885883243,0.01619015433,-0.03924251192,-0.03897164871,-0.02947402521,-0.02215256466,-0.02398536692,-0.02776334817,-0.01603406498,-0.006991148109,-0.0002962648339,0.000507269122,-0.001949186874,-0.001370126587,-0.0006521953734,0.001996148792,0.004924830928,0.00528572888,0.004485053726,0.002525056633,0.0004435592795,-0.002278290645},
      {0.7357071009,0.4411587495,0.2084562152,0.04228790378,-0.04052444875,-0.03722720261,-0.02485942851,-0.01208761249,-0.008827915087,-0.01583174513,-0.0249628036,-0.01454699081,-0.007281940714,-0.002564400941,0.0004111548306,-0.0006161935229,0.001086390559,0.002482698031,0.001873797145,0.001267386453,-9.235416546e-05,-0.004516365165,-0.008306247083,-0.01192525991},
      {0.7333479094,0.4504194904,0.2037517202,0.0658714838,-0.01912259582,-0.0472461683,-0.03422999142,-0.0209834628,-0.009274078368,-0.0119297612,-0.0176248531,-0.02375010432,-0.01229746715,-0.004413972695,-0.001640567117,-0.001155573132,-0.002584423724,-0.002767955459,-0.001897699427,-0.002722187644,-0.00427658423,-0.00507685329,-0.005751473469,-0.008874831637},
      {0.7360279336,0.4638146052,0.2143031159,0.09100803819,0.01456790769,-0.04461882828,-0.02928766623,-0.01390716508,0.001557843555,0.007764614594,0.0003676313834,-0.009685099891,-0.02036248126,-0.01384750837,-0.002871465421,0.002576966963,0.007484222678,0.007985147762,0.007452625645,0.005507863921,0.003491569458,0.00112212398,-0.0005709736044,-0.001640773306},
      {0.7333917486,0.4713112132,0.2338253857,0.10465808,0.04163350642,-0.02108917884,-0.03726050025,-0.02228463066,-0.008097030289,0.002827613135,0.001747087664,-0.002386789388,-0.01030323468,-0.02016873175,-0.01709825233,-0.01145886054,-0.006004981652,-0.002788839052,-0.0001709403025,0.002305210065,0.00411963474,0.005646476088,0.005629229211,0.005115095819},
      {0.7269540328,0.4684516956,0.2471339471,0.1085780525,0.06828261936,0.007439685774,-0.0414769691,-0.0255049224,-0.01262037463,0.0009289559582,0.008259586144,0.003020668922,-0.002392366589,-0.0132203123,-0.02014484316,-0.01236946168,-0.005188288915,0.0009686406875,0.003372593485,0.002712530956,0.0004216002963,-0.0007891076454,0.0008680616254,0.002854319994},
      {0.7257049711,0.471511633,0.2617874556,0.1153350349,0.08578915552,0.03920290249,-0.01272316649,-0.02680230367,-0.01363603733,0.001608241228,0.01190112861,0.01549929942,0.005378852562,-0.001110198818,-0.008914483559,-0.01306147034,-0.008824319637,-0.0007338646589,0.002919014852,0.003146853319,0.001682772146,-0.002157161175,-0.005325168836,-0.004870157139},
      {0.7178089945,0.4611104248,0.2589424316,0.09973691649,0.08222513699,0.04712824103,0.003089781644,-0.03550195925,-0.01824702021,-0.0008975403253,0.01147638275,0.01627555328,0.01612543439,0.01206872136,0.006799087361,-0.001924760089,-0.01178825053,-0.01571435141,-0.006470197397,-0.00118365881,0.002521366979,0.001488767307,-0.000828871366,-0.0008220759685},
    },
    {
      {0.3016998026,0.04557860913,-0.04734520749,-0.05562860211,-0.01547498949,0.009484080915,0.01461297341,0.007423934138,0.0115387349,0.005184687677,6.627024172e-05,-0.00819585497,-0.00458426562,-0.0005742343948,-0.002177428333,0.1277608206,-0.003204404755,-0.005308465767,-0.008165638999,-0.006325694743,-0.0003421064422,-0.002559758155,0.001114809124,-0.005750778747},
      {0.4788172859,0.1402358762,-0.01478546567,-0.058777254,-0.04316573302,-0.02252242209,-0.009242235212,-0.0006050546399,0.007484834942,0.01012960703,0.007454908251,0.005972543496,0.005110872936,-7.372179787e-05,-0.006091232402,-0.004315292742,-0.003156284988,-0.001322715967,-0.001427488711,-0.005185701253,-0.008582338287,-0.01086022478,-0.01118599981,-0.01618751391},
      {0.595164532,0.2182880634,0.004297326938,-0.06444684815,-0.0452698691,-0.02036165904,-0.01045645667,-0.01006588383,-0.01125948062,-0.008314960469,-0.004391012856,-0.001862998308,-0.0004310891882,-0.002516616487,-0.003660944015,-0.001604515116,0.002490913876,0.007934921952,0.009416447017,0.007829365413,0.002701933944,-0.001831455812,-0.003642057795,-0.003990765244},
      {0.6257249635,0.2595098968,0.04426574686,-0.05942179401,-0.0622437345,-0.03631886829,-0.01708708112,-0.006171904248,-0.004314475407,-0.005734582587,-0.006684624704,-0.006488594611,-0.005241583432,-0.004628933762,-0.003940353055,0.001336957642,0.008496539373,0.0106053875,0.006097486576,0.001129214458,-0.001261043274,0.0004936562261,0.002182408955,0.00424968862},
      {0.6716603618,0.3135905978,0.06859962375,-0.03944831006,-0.06325500071,-0.05049909999,-0.02750578369,-0.01375921845,-0.007882377977,-0.006754124315,-0.007649012205,-0.006552200981,-0.003765443417,0.0006089060164,0.002143283402,0.002185816916,0.003077011576,0.004036850331,0.003498289799,0.003217237506,0.004838348559,0.005209625507,0.003384890989,0.002020562503},
      {0.6928160437,0.3534069368,0.08466358387,-0.0226484719,-0.04721466831,-0.04838026941,-0.03706547038,-0.02032066011,-0.009507093966,-0.003376111431,-0.0006370707375,-0.0006397280512,-0.001163348449,-0.002125067293,-0.001469080433,-0.0002256663905,0.001795383646,0.003849853259,0.004957308424,0.002087172773,-0.003774365365,-0.008005812324,-0.007924734511,-0.003281919619},
      {0.7022433977,0.369058996,0.1172394118,-0.01693463407,-0.03871828442,-0.03893429494,-0.03787222588,-0.03591009543,-0.02244085361,-0.01134450148,-0.003832025114,-0.001247531248,-0.0005270605703,-0.0002987089551,-0.0004768561791,-0.001330089601,-0.002181045821,-0.001475893243,0.00207514649,0.00520729236,0.006984235034,0.00674115214,0.005501971472,0.002546682442},
      {0.70830121,0.3851332971,0.1486135067,-0.01143645378,-0.02668993631,-0.02793923062,-0.02714981719,-0.03048207297,-0.03427971805,-0.01950764574,-0.009048382104,-0.002279890881,0.001564494126,0.002803423204,0.003647282223,0.004715484355,0.002380756195,-0.0002019064158,-0.000309757797,-0.0001221897772,3.50749619e-05,0.001929410257,0.002902149234,0.001905574363},
      {0.7210002899,0.4055287755,0.174505124,0.01522119556,-0.03130947042,-0.02603438371,-0.01765462932,-0.01437331267,-0.01941635995,-0.0245663223,-0.01316043608,-0.003869762899,0.0026541728,0.00315237423,-3.102623606e-05,-0.0001118836114,-0.0003992280437,-2.900120391e-05,0.0009533065797,0.001192679842,0.0008355512746,0.001099418174,0.001157812515,0.0001991883822},
      {0.7272058762,0.4252574191,0.1925172274,0.03993904773,-0.03454079293,-0.02608829935,-0.01352226239,-0.004144619127,-0.004110062646,-0.01330237025,-0.02283148725,-0.01235942906,-0.005532996009,-0.001456146303,0.001272252304,-0.0002076612378,0.001263113451,0.002815410538,0.003247221836,0.00233586892,0.0002356096887,-0.004754491553,-0.008053606774,-0.01147358718},
      {0.7271828057,0.4353172221,0.1907010542,0.05818345811,-0.01407636451,-0.03591915629,-0.02188546943,-0.01034931159,-0.002745660572,-0.007203793522,-0.0145425134,-0.02156667198,-0.01066775012,-0.002741570825,0.0004237053055,0.0007814165212,-0.0007837217903,-0.001159123286,-0.001316322949,-0.003196481664,-0.005425730422,-0.00668513848,-0.007834605937,-0.01040656995},
      {0.7302741849,0.4481232092,0.1999897543,0.08203025147,0.01932681067,-0.03259563639,-0.01583530307,-0.001690090501,0.01006095127,0.01343551914,0.004111992891,-0.006578746429,-0.01705224992,-0.01182165525,-0.001323726002,0.003511096437,0.006578956325,0.006591460823,0.005866396255,0.004857634467,0.002850867967,0.0002450237044,-0.0008516552861,-0.001872133674},
      {0.7309392839,0.4607539777,0.2215259377,0.09654576996,0.04169523327,-0.01179740487,-0.02581291813,-0.01224366109,-0.0001745099409,0.008551311576,0.006905609109,0.0008288806085,-0.008110504617,-0.01780626692,-0.01603411351,-0.01045385676,-0.004489373233,-0.0006502498566,0.00244167517,0.003534948322,0.003744212962,0.005758369373,0.005675806731,0.006412887501},
      {0.7250853763,0.4589392714,0.2335369198,0.09950366308,0.06392359609,0.01493533172,-0.03023941978,-0.0150197304,-0.004387403458,0.005818981422,0.01136282295,0.006390340514,0.0002973495089,-0.01025331601,-0.01664213098,-0.008776748394,-0.001600478977,0.003400372842,0.004090069483,0.002372467303,-0.0006570067673,-0.00202979718,-0.0003828789736,0.002204950612},
      {0.7249190965,0.4640077721,0.2486181212,0.1068039996,0.08291502915,0.04506591317,0.0005728205003,-0.01258776081,-0.002225761412,0.009012014265,0.01565342448,0.01689376269,0.00872252031,0.001474201291,-0.006662321303,-0.01171063918,-0.010087044,-0.002998169151,-0.0001107987309,0.001037720041,0.001508474873,-0.001203098432,-0.003588976057,-0.003650060398},
      {0.7151588873,0.4536906703,0.2464461522,0.09501864324,0.08217112154,0.04991584874,0.01380091048,-0.02503834498,-0.008862299203,0.005736938303,0.01503220588,0.01875184849,0.016682033,0.0126760473,0.007244782361,-0.0006591666818,-0.01019323874,-0.01413735274,-0.006334927399,-0.002550400323,0.001247938511,0.0009438269524,-0.0003622737305,-0.001243551897},
    },
    {
      {0.2893015635,0.04187143745,-0.04656999118,-0.05378166932,-0.01339376832,0.009172361122,0.01407126178,0.006798548358,0.01055081373,0.005117906156,0.001431568035,-0.007172683295,-0.003887200623,-0.0003892346271,-0.002903285565,0.1229944226,-0.002958311031,-0.003841447184,-0.008654669563,-0.006592371847,-4.108041381e-05,-0.003205611751,0.001581234852,-0.00455505201},
      {0.477804041,0.1340921025,-0.01582302126,-0.05658856871,-0.03957187909,-0.01913087446,-0.006642385659,0.001311801315,0.008151021585,0.01007385215,0.007205014554,0.005311015418,0.004785258625,-7.993300403e-05,-0.005689203872,-0.00389950182,-0.002638301712,-0.0008842584431,-0.001805076289,-0.00491303381,-0.007382498724,-0.008083985733,-0.009309710271,-0.01367598478},
      {0.5727540565,0.206458037,0.001671805499,-0.06111101329,-0.03785460595,-0.01426839509,-0.006570243288,-0.007689440183,-0.009810294393,-0.007199742549,-0.003419510492,-0.00114873397,0.0005935749738,-0.0007325935459,-0.001437630022,3.174710087e-05,0.003394560373,0.008242272441,0.009517198419,0.007659832353,0.002253759728,-0.002497443235,-0.004717110157,-0.004894103866},
      {0.6181327091,0.251404583,0.04498746121,-0.05753917372,-0.05715794878,-0.03045001955,-0.01273567942,-0.003967729749,-0.003644831534,-0.005644634074,-0.006526848503,-0.006082787812,-0.005195258454,-0.004807658404,-0.003785435805,0.001338064168,0.008113994923,0.009573832967,0.005220938489,0.000756549418,-0.001111941206,0.0008325055275,0.002666915796,0.005840619038},
      {0.6537301983,0.2985211166,0.06403043291,-0.03577757497,-0.05642423583,-0.04357339937,-0.02137140132,-0.008796926003,-0.004512792005,-0.004793905426,-0.007373261448,-0.00717489462,-0.004483520318,3.44799964e-05,0.001320083395,0.0008405044503,0.001262750158,0.001876491458,0.001366859184,0.002201880263,0.005433869803,0.007643491193,0.006036883114,0.003852498834},
      {0.6763837957,0.3354306223,0.07657953571,-0.01994864312,-0.03857529603,-0.04007197877,-0.03150380808,-0.01635182678,-0.00667376027,-0.001460774092,0.0008706650798,0.0003173425706,-0.0004824566661,-0.001070603304,-0.0005144065392,3.418018607e-05,0.0007838600368,0.002088825208,0.003310923982,0.002245124053,-0.00182138176,-0.004949541248,-0.005032119393,-0.001543203447},
      {0.6893914502,0.3521419955,0.108358734,-0.01576860409,-0.03048331466,-0.02951884103,-0.03096992682,-0.03173314284,-0.01966014032,-0.009078535463,-0.001449907702,0.001039078909,0.0009714855591,2.311913405e-05,-0.0009845741938,-0.001440925939,-0.001378488386,-0.0007099313899,0.002002224375,0.003695837421,0.004854624964,0.005930645419,0.005641920832,0.002851390849},
      {0.6954949495,0.3710643868,0.1402843991,-0.01143595374,-0.01764140828,-0.01574048946,-0.01533697573,-0.0216209022,-0.0280523194,-0.01429797939,-0.004560309113,0.001877066966,0.004998905831,0.005305966665,0.00504198834,0.004346340315,0.0009877075672,-0.001628559552,-0.001402797077,-0.0007614922287,-0.0004480877148,0.001798289199,0.002828248797,0.002030843849},
      {0.7111173086,0.3886746621,0.1607640909,0.01418554712,-0.02320090553,-0.01335834687,-0.006749734363,-0.008016722729,-0.01585686083,-0.02195211986,-0.010116782,-0.000867200136,0.004565230636,0.004180935927,0.0001901547811,0.000728380864,0.001210999105,0.001578173939,0.002054615776,0.001541889946,0.001080001106,0.001599130246,0.0015530746,0.0006141935124},
      {0.7185868436,0.4090208058,0.1764778728,0.03757514199,-0.02830240902,-0.01480153647,-0.0017970197,0.003548079561,9.14597695e-05,-0.0117003076,-0.02190713695,-0.01114237791,-0.004040468993,-9.123715531e-05,0.001749293431,-9.338163594e-05,0.001299634074,0.003325605442,0.00456615561,0.003688654249,0.001669082218,-0.002925737472,-0.00726588351,-0.01252617901},
      {0.720284792,0.4208369716,0.1796543042,0.05369449782,-0.00548017445,-0.02155897115,-0.007591038368,0.0003934532864,0.00224353294,-0.004658052446,-0.01421714298,-0.02255712039,-0.01125129142,-0.002876792333,0.001556259661,0.001876422516,-2.721892673e-08,-0.0003680999449,-0.0008184344549,-0.002520619372,-0.004142894685,-0.004721525053,-0.005798657834,-0.007879522836},
      {0.7240342177,0.4330881667,0.1877012026,0.07542891732,0.02614369259,-0.02002142244,-0.001832574873,0.01100257905,0.0190734913,0.01997037424,0.009014945458,-0.002790281506,-0.0131563115,-0.007811563265,0.002189736777,0.006448770746,0.008878786635,0.008635819082,0.006813091063,0.004808151691,0.00247754353,0.0001385738538,0.0001610917473,-0.0004162634147},
      {0.7267186517,0.4480766662,0.2072392528,0.08729606606,0.04265715772,-0.0009616047061,-0.01251897621,0.0001482465198,0.009505681949,0.01484579709,0.01102599031,0.002274872057,-0.007861558985,-0.01740261905,-0.01571694011,-0.008862920152,-0.00224874643,0.001825916072,0.003729937325,0.002975370066,0.001260978538,0.002646744874,0.003159430574,0.003665768559},
      {0.7220701298,0.4487480755,0.2206788388,0.09258636851,0.06264787519,0.02461452593,-0.01773407876,-0.003292922726,0.005325532898,0.01191480502,0.01461630221,0.008678501383,0.001171975103,-0.009724367643,-0.01610505312,-0.007525096959,0.0008363270859,0.005936117955,0.00575419979,0.003761985582,0.0003389820163,-0.001598580702,-0.0009865672064,0.001506923984},
      {0.7243986394,0.4575940614,0.2373834525,0.1008575955,0.08210178121,0.05160358855,0.01312768533,2.9947483e-05,0.00854002765,0.01727947803,0.02089760418,0.01894642273,0.01157615753,0.002849851568,-0.00594460742,-0.01210114399,-0.01150830278,-0.003929516608,-6.793974537e-05,0.001857893782,0.002445674139,-2.624916426e-05,-0.001853101095,-0.001751077126},
      {0.7136750624,0.4472594359,0.2340491938,0.08904233226,0.0824734116,0.05380536439,0.02476826037,-0.01403033543,0.0009450961812,0.01267644312,0.01917495278,0.02088765546,0.01676502765,0.01338595283,0.007243127767,-0.000495119459,-0.01028936449,-0.0145196009,-0.005378739812,-0.0007384561912,0.003591381972,0.004767712945,0.003012595539,0.0005033988411},
    },
  },
  {
    {
      {0.3709896525,0.06653895302,-0.05365027272,-0.06601903998,-0.02375176928,0.009574672015,0.01715587122,0.01119594293,0.01219303018,0.004440193156,-0.003349940875,-0.00728679439,-0.003002396319,-0.0001616048449,-0.001630630168,0.06135450517,-0.004011888128,-0.006914352298,-0.006068328292,-0.002565151993,0.0002990074195,-0.002094723769,0.0004583699132,-0.00725537211},
      {0.5351580804,0.1825527972,-0.002891424834,-0.06455713277,-0.05605588457,-0.03469672505,-0.01667937646,-0.004597195039,0.0039264382,0.008266392422,0.008790451565,0.009083917836,0.006721284188,0.001251639262,-0.005673572923,-0.005150487395,-0.00240927648,0.0003951812259,0.0002034487974,-0.004726673572,-0.009495620402,-0.0134089277,-0.01335392524,-0.01462272841},
      {0.654623728,0.2804661033,0.03184460389,-0.0640594511,-0.05969780598,-0.03745970203,-0.0224954848,-0.017976759,-0.01659701343,-0.01249195553,-0.007518709918,-0.003913122857,-0.00206233042,-0.00319778193,-0.003901275741,-0.001517806216,0.001983172989,0.006428419901,0.006775041622,0.004965380977,0.0004479796212,-0.003499152691,-0.003801820491,-0.002949438571},
      {0.6739223331,0.3149863255,0.08155099644,-0.05145447412,-0.0735959073,-0.05248852451,-0.03120497476,-0.01614595413,-0.01105797341,-0.01113589183,-0.01178813364,-0.01079497576,-0.008167611664,-0.005677992039,-0.00353954915,0.0001001142827,0.004937000987,0.006349430559,0.003754638184,0.001905233601,0.002094015186,0.003931565075,0.005998727083,0.006858852502},
      {0.7085016827,0.3689545328,0.1153032645,-0.01604629161,-0.06731631265,-0.06768950455,-0.044985965,-0.02682973257,-0.01581694303,-0.01180631946,-0.01144562447,-0.009643425045,-0.006857401778,-0.002818925985,-0.000778696846,0.001466851204,0.004776603792,0.007139961937,0.00639787943,0.004960881125,0.004713518144,0.003154873143,0.001341256514,0.0003256292565},
      {0.7186218532,0.4048470939,0.1309653348,0.0104625567,-0.03584885752,-0.05894308317,-0.05578602506,-0.03547760571,-0.01976823058,-0.01008565036,-0.006324045991,-0.005717149729,-0.004368208423,-0.002830495852,-0.000342775347,0.0006944129151,0.001777981283,0.002358252493,0.003109040326,-8.497812988e-05,-0.004359187897,-0.008529506153,-0.008799033472,-0.006064921935},
      {0.7213562878,0.4143475616,0.1614852849,0.01619200878,-0.01972964367,-0.03776773542,-0.05083060812,-0.05339534537,-0.03374887631,-0.01780966365,-0.007120512514,-0.003142282626,-0.002700479465,-0.001272505743,-0.0002336882518,0.0001750487768,0.0003116701312,-2.749693849e-05,0.001262747521,0.002849384174,0.002940165984,0.002617483922,0.001615343663,-0.001020905786},
      {0.7235697838,0.4277165874,0.1920020524,0.01790301354,-0.003272531902,-0.01714668079,-0.02899707807,-0.04081903827,-0.05044639543,-0.03171747734,-0.0168825597,-0.005882621565,-0.000240719705,0.001015429164,0.001110173943,0.003232771165,0.003976353466,0.0031160944,0.003698025886,0.003436686927,0.001855920121,0.002787619295,0.00324884694,0.001078825998},
      {0.7308728024,0.4434968753,0.2197723817,0.04663804495,-0.006518817452,-0.008734062761,-0.009024369617,-0.01462734474,-0.02831669698,-0.03844527486,-0.02177309885,-0.009172809029,-9.907268155e-05,0.001929358405,-0.001155934541,-0.0009595088107,-0.002501808481,-0.001411879868,0.001110908012,0.001872198789,0.002622976899,0.002637677946,0.001009006809,-0.00227156738},
      {0.7367232739,0.4601537395,0.2405309773,0.07254359393,-0.01494986313,-0.01030872206,-0.003671396271,0.0003603530445,-0.007743898468,-0.0241729653,-0.03737313812,-0.02099381805,-0.008197864363,0.000461678412,0.005166407375,0.002430471904,0.001008392888,0.0003427954693,-0.0009172121425,-0.001142932134,-0.002573551644,-0.006022700688,-0.01005953784,-0.01374513436},
      {0.7315863882,0.4623058886,0.2314013639,0.09411898125,0.007039573171,-0.02337032266,-0.0128261408,-0.004816673305,0.0006919980307,-0.0112340383,-0.02495796688,-0.0366493154,-0.01961434859,-0.006812548813,-0.0001944768155,0.001774668578,1.386226929e-05,-0.0009175086128,-0.0007056447805,-0.001933760089,-0.00387738843,-0.003154111755,-0.003746884604,-0.006079494869},
      {0.7344718432,0.4730929877,0.2488059745,0.1261732021,0.04880454522,-0.02041954408,-0.003614718622,0.0106240576,0.02251294233,0.02262588672,0.00645320498,-0.01030428579,-0.02764543511,-0.02017478599,-0.005657336071,0.001866840998,0.006904362082,0.005457113009,0.004743265716,0.003141683724,0.0009797015109,-0.0007139233899,-0.002024983435,-0.00199096584},
      {0.7308061422,0.4793578622,0.2628811143,0.1381337303,0.07702460722,0.006277555345,-0.01428859387,1.827434427e-06,0.01019496916,0.01697529797,0.01011169416,8.782070297e-06,-0.01234652791,-0.02626762474,-0.02157618773,-0.01123186134,-0.001116326039,0.00386386513,0.00561776024,0.004973036242,0.005323506731,0.005489322462,0.004196568545,0.003002270533},
      {0.721572675,0.4705528891,0.2683623409,0.1415198888,0.1062540718,0.04013890146,-0.02096284415,-0.005125881869,0.005554335565,0.01648893571,0.02073388808,0.009186125539,-0.001566841364,-0.01603284776,-0.02526311484,-0.01325615936,-0.00337730335,0.003613254629,0.006561938687,0.003989733875,0.001418811578,-0.000353421188,0.002000582679,0.003707202486},
      {0.721677528,0.4744797709,0.2819581245,0.1540275534,0.1283302392,0.07929590772,0.01807644079,-0.001010835335,0.01211653456,0.02454886902,0.03090813522,0.03164728867,0.01357676607,0.001152903257,-0.01201900071,-0.02071547227,-0.01574268226,-0.005338213825,0.0001344262388,0.002834344739,0.002410745507,0.001602214535,0.0009930804185,0.003143938156},
      {0.714034574,0.4582080748,0.2742257912,0.1384006722,0.1231717314,0.08850869433,0.0377940678,-0.01079293022,0.0065117598,0.02277039616,0.03242621295,0.03353621762,0.02873210211,0.01719134794,0.005838814074,-0.007125307644,-0.01806519606,-0.02249420435,-0.00933382552,-0.001826408465,0.002845845058,0.002438615385,-0.0006318763731,-0.002780775495},
    },
    {
      {0.3587903153,0.06237534678,-0.0527156835,-0.06365320736,-0.02190026479,0.008508513911,0.01578914056,0.01067634665,0.01164057092,0.004975994836,-0.001785832696,-0.006403261995,-0.002392746172,0.0002605659914,-0.00135985019,0.05993665759,-0.004019607729,-0.006268349669,-0.007050752167,-0.003489881799,-0.0002094280395,-0.002817471269,0.0006619445707,-0.006434145571},
      {0.5345492394,0.1766901709,-0.003789393424,-0.06218233729,-0.05244596095,-0.03135857298,-0.01423680759,-0.002701469547,0.005450573843,0.009342355771,0.008859066791,0.008051788075,0.005665554395,-8.489378364e-05,-0.006593035463,-0.005749563492,-0.003300733921,-0.0006451794388,-0.0005650057557,-0.00401829658,-0.006608150764,-0.009115543889,-0.01057643659,-0.013518067},
      {0.6364887693,0.2674751688,0.02636437394,-0.06186072992,-0.05236939025,-0.03016396932,-0.01751132533,-0.01391981778,-0.01298502553,-0.009012475898,-0.004566995863,-0.002568330788,-0.001901281083,-0.003357032288,-0.003653035567,-0.0006831625637,0.003045352266,0.007575494751,0.0073962183,0.005932887978,0.001367798872,-0.002479624198,-0.003828107099,-0.004614550794},
      {0.6650755895,0.3063075045,0.08003361336,-0.05080992633,-0.06870301185,-0.04661076052,-0.0266300637,-0.01400147411,-0.01074917424,-0.01084243088,-0.01094581509,-0.009063229173,-0.005879838106,-0.003246527728,-0.001214486704,0.002267618491,0.006591818641,0.007588477138,0.005081943259,0.002192148063,0.00148623876,0.003907144642,0.006100409065,0.007523368622},
      {0.6959136093,0.3550528129,0.1085665416,-0.01615174697,-0.06191704508,-0.05955593456,-0.035980878,-0.01883984957,-0.01023526828,-0.008469702271,-0.01019235544,-0.009119504837,-0.006600154618,-0.002383569979,-0.0003717144844,0.001116129785,0.003017311977,0.00411792398,0.003241481196,0.002217230371,0.003607903712,0.003846858037,0.002847459003,0.002321547523},
      {0.7082707326,0.3893551335,0.1219542026,0.01076699523,-0.0293606472,-0.04971387171,-0.04729081768,-0.02851376974,-0.01457434346,-0.006712549162,-0.003861689302,-0.003857155236,-0.00304782019,-0.002023154838,-0.0002785883476,-6.521454033e-05,0.0004871231482,0.001828442929,0.00309631956,0.00122247866,-0.002599837533,-0.005812245664,-0.006265206275,-0.004573968293},
      {0.7139585564,0.4016976782,0.151919224,0.01523883231,-0.01429058077,-0.0300398382,-0.04373745433,-0.04822429723,-0.03089022587,-0.01670081476,-0.006544201357,-0.002809921272,-0.002910090983,-0.002631648944,-0.002354604851,-0.001334366726,-0.0003019447224,0.0003165171241,0.002802885642,0.003312204781,0.002837606279,0.001704322987,0.0005890520811,5.03500037e-06},
      {0.7139902284,0.4162559501,0.181213883,0.01695127725,0.004512379255,-0.006027881345,-0.01722626527,-0.03194282708,-0.04306929774,-0.02487515511,-0.01134890698,-0.00211948453,0.002225630061,0.002602831405,0.002104956637,0.00327895578,0.002900322955,0.001053177959,0.001461207576,0.001125281622,-0.0001016559942,0.0009985919955,0.001913244389,0.0009254419554},
      {0.7257564312,0.4316809105,0.2061584769,0.04356954859,-0.00186213632,0.000794153088,-0.0002999830251,-0.00906241464,-0.02401690773,-0.03443366206,-0.01849756043,-0.006803529196,0.0003631637841,0.001909843993,-0.000989057343,2.766590121e-05,1.42347135e-05,0.0007288562027,0.001964940068,0.001439548338,0.001228793533,0.002034352403,0.00200406184,0.0003806036099},
      {0.7306984324,0.447314808,0.2240616947,0.06784330349,-0.01159138039,-0.001476117555,0.006723956117,0.008121599859,-0.001834534625,-0.01965950939,-0.03365550565,-0.01849987477,-0.007306343609,-0.0009151325997,0.002146288848,-0.0009464778625,-0.001820334802,-0.001599977771,-0.001131615958,-0.001004268361,-0.002225266984,-0.00600222918,-0.01008325594,-0.01406762112},
      {0.7279413076,0.4520823704,0.2209065998,0.08562594779,0.01054019684,-0.01307816505,-0.0005056759256,0.005973143903,0.007062434671,-0.005530487785,-0.01960956134,-0.0315429946,-0.01571129711,-0.004148930545,0.002237507611,0.002783139912,8.142473806e-05,-0.0007669185638,-0.00148898757,-0.002544251979,-0.002782717369,-0.000233272828,-0.001806564264,-0.00487155144},
      {0.7306362835,0.4624357164,0.2370990909,0.1149823972,0.05002090696,-0.01159972632,0.009204590046,0.02369771264,0.03155151291,0.02824714985,0.009531004412,-0.008054269893,-0.02395839844,-0.0171897088,-0.002859745391,0.003678699764,0.00767701899,0.00577057282,0.004205815438,0.002906946194,0.001473518809,0.0009124447016,0.001032430365,0.001117474212},
      {0.7299512071,0.473981024,0.2547626665,0.1299405941,0.07441320982,0.01285485479,-0.004337103924,0.009678595267,0.01845033907,0.02290948743,0.01578514183,0.004441561534,-0.00848852751,-0.02167356753,-0.01874591408,-0.009612826285,-0.0004472184633,0.004231587938,0.006475967698,0.005117170577,0.004385107799,0.005598211097,0.005684987783,0.005803386903},
      {0.7210464104,0.4649840912,0.2582280483,0.1319836363,0.09793591669,0.04351648867,-0.01130423938,0.006695236923,0.01660279513,0.02381698241,0.02525075962,0.0131280113,0.001651865319,-0.01344366895,-0.02246399644,-0.0106432315,-0.0009591349804,0.006194925285,0.009169649983,0.007887108197,0.005357327712,0.003065960256,0.003907770871,0.005779463126},
      {0.7216898093,0.4712010813,0.2734148219,0.1466381396,0.1215244452,0.07806981086,0.02383103472,0.007194131627,0.01885014355,0.02902011431,0.03266854244,0.03063090537,0.01649203422,0.004328071416,-0.007539516361,-0.0153942766,-0.01420049929,-0.005220512674,-0.00089636958,0.002394800016,0.00332800503,0.002529946358,0.002427244224,0.004346431817},
      {0.7124808438,0.4543404162,0.2667633884,0.1353959048,0.1204503068,0.08416126473,0.04087484507,-0.00579350838,0.01295542033,0.02782761573,0.03414195446,0.03381655022,0.0266958103,0.0161594282,0.005415815161,-0.005939027636,-0.01543610133,-0.01845074293,-0.006516907233,-0.001001124666,0.003100145455,0.004700154019,0.003330639622,0.001355727077},
    },
    {
      {0.342368463,0.05695370137,-0.05127183407,-0.05990786251,-0.01741752374,0.009864079816,0.01577823383,0.009739638325,0.01045948803,0.004495021326,-0.001238861061,-0.006514573987,-0.00209367548,0.0008662768291,-0.0004935056533,0.05836927268,-0.002834236501,-0.003730500473,-0.005866377222,-0.002380726541,0.0007672496717,-0.003030828462,0.0004971892876,-0.005260388711},
      {0.5327845853,0.1686534666,-0.005642869107,-0.06004663711,-0.04899845309,-0.02763868379,-0.01109650476,-0.0007229681786,0.005965971306,0.008548721506,0.007733828116,0.006745015021,0.005081566742,-0.0001975549974,-0.006184595754,-0.005534265642,-0.003497533287,-0.0004879116047,-0.000463596008,-0.00376988166,-0.006041522446,-0.00746732545,-0.008999911122,-0.01220758371},
      {0.6158674503,0.2529833531,0.02076929702,-0.05971576832,-0.04525454409,-0.02341491938,-0.01260673103,-0.009864880914,-0.009197944723,-0.005820281241,-0.00233108015,-0.001436470664,-0.001284664835,-0.00190237804,-0.00135147935,0.001659114243,0.004190769733,0.006782436131,0.00486535288,0.003313329539,-0.0005648169531,-0.004276938096,-0.005241012812,-0.004885148195},
      {0.6537947084,0.2941214114,0.07815453042,-0.04873253475,-0.06150214935,-0.03846487355,-0.02046428088,-0.01079582989,-0.009384671466,-0.01002733167,-0.01035840266,-0.008892394591,-0.006327364254,-0.004037865607,-0.001350763418,0.002811739617,0.006649829695,0.006719515305,0.004324891811,0.001684015987,0.001992673469,0.005295717049,0.006818067361,0.008918218422},
      {0.68207089,0.3400751881,0.1016746066,-0.01565849105,-0.05683633744,-0.05185718585,-0.02755504597,-0.01134775382,-0.004893778795,-0.005495957675,-0.008851327923,-0.00849545929,-0.00611252824,-0.001703326928,0.0007107504851,0.00134861413,0.002023468337,0.002271503628,0.001081234534,0.0002678677078,0.003693581026,0.006032526023,0.005058451128,0.003694087012},
      {0.6970459943,0.3729825924,0.1125783765,0.01133937815,-0.02208184211,-0.03944701069,-0.03818141955,-0.02014868206,-0.007372568829,-0.0004368849989,0.001573234841,0.0001817004893,-0.00168905851,-0.001931583786,-0.000828303697,-0.0005194748516,-0.0001850682831,0.0009348767336,0.003032879559,0.002479258276,-0.0004303650621,-0.003157911949,-0.003569199952,-0.001831642496},
      {0.7044154524,0.3863722374,0.1402134373,0.0131011953,-0.008448682147,-0.02040498383,-0.03323623773,-0.03913165317,-0.02347997932,-0.01123559182,-0.002738650703,0.0008250635854,0.0009429130898,0.000640372476,-0.0007273334295,-0.0003761706861,0.0004443005561,0.001727834489,0.004234971358,0.0042899752,0.004144484133,0.003134368503,0.002068274403,0.0004037944412},
      {0.7059068899,0.4058053755,0.1719658834,0.01577531692,0.01132645515,0.004038779768,-0.006836057433,-0.02376694484,-0.03628066581,-0.01862007084,-0.005616213185,0.00255925758,0.005473124567,0.004952182127,0.003503616885,0.003002362349,0.001006950901,-0.000777062871,0.0005772988741,0.001859611484,0.00136269043,0.001797481135,0.0003967332474,-0.001437201325},
      {0.7193746898,0.4189512451,0.1922793752,0.04077921348,0.003953937129,0.01183377299,0.01067991935,-0.001270521173,-0.01856368557,-0.02992201489,-0.01471407235,-0.003293097692,0.00325194116,0.004287647117,0.001165168921,0.00208892639,0.00249005903,0.002298979436,0.002373920145,0.0008908696035,-8.996751338e-05,0.0006347799087,-0.0001845249839,-0.001958752347},
      {0.7244378895,0.4346639041,0.2079401983,0.06366199051,-0.006885645378,0.008753510566,0.0180935012,0.01564009719,0.003328573099,-0.0159947881,-0.02983115768,-0.0138768422,-0.002849620153,0.002561514496,0.003786854891,-0.0005508730906,-0.001639209974,-0.0004131483456,0.001598249482,0.001421662654,-0.001759331235,-0.007561743342,-0.01268458631,-0.01660701764},
      {0.7233255003,0.4422232722,0.2123054896,0.07938299457,0.01616999972,-0.001271948549,0.01319275494,0.01766491822,0.01339928604,-0.001262546113,-0.01723477885,-0.03025383477,-0.01465415549,-0.003089614846,0.003806479855,0.00440868248,0.001671893482,0.0002144571233,-0.001717412118,-0.003721352239,-0.004318840281,-0.003085520537,-0.003843008045,-0.006369296628},
      {0.7263545514,0.452696869,0.227466399,0.10607794,0.05326088877,-0.001688581805,0.02174429039,0.03555422376,0.03932158473,0.03310170384,0.01289150058,-0.005012938137,-0.02112772699,-0.01456606583,-0.001096537755,0.004942822761,0.008764062257,0.007551737646,0.0057511841,0.003737758228,0.001505945246,0.0003207027311,0.001076212634,0.001256037473},
      {0.7284520752,0.4680697253,0.2465687536,0.1227925526,0.07327313682,0.0213267864,0.007962415247,0.02209846949,0.02826070477,0.02915061082,0.02071253514,0.007810387515,-0.006383532192,-0.02032665406,-0.01754864853,-0.007233153999,0.002980186937,0.008616941077,0.01020303356,0.007361036859,0.003647512296,0.003220470806,0.003796634654,0.005158673079},
      {0.7198661388,0.4594392395,0.2494681179,0.1251926235,0.09186885717,0.04759159714,-0.002542008736,0.01640507329,0.02535363104,0.02952436309,0.02845313516,0.01626556539,0.003851747819,-0.01197879067,-0.02118260727,-0.008990816939,0.001080560211,0.007967300578,0.01010368772,0.008416531474,0.005229418135,0.004646007632,0.006188667556,0.008600826859},
      {0.7215008868,0.4676501174,0.2654602581,0.1411460233,0.1174998448,0.07937854326,0.03198314953,0.01801696558,0.02880355778,0.03650869323,0.03701018874,0.03165927919,0.02087303847,0.007728563471,-0.005169934839,-0.01358798382,-0.01396744176,-0.004432029449,0.0003411852882,0.003260889024,0.005049772262,0.004722983576,0.00423142487,0.006183920963},
      {0.7117315355,0.4520121172,0.2598322456,0.1318124279,0.1199446612,0.08389412627,0.04775004684,0.002866847224,0.02214159557,0.0352409691,0.03774014322,0.03417031847,0.02460777496,0.01622275461,0.006156819617,-0.004680694568,-0.01467945097,-0.01838653701,-0.006694610695,-0.0007047383196,0.00478101033,0.007647662722,0.007227790052,0.004526767039},
    },
  },
  {
    {
      {0.4176775324,0.08205997293,-0.05769645726,-0.07280586678,-0.02877074139,0.008332670604,0.01750457998,0.01303799992,0.01178471893,0.003874941985,-0.00462104144,-0.006298467703,-0.001789226253,-0.0001775138277,-0.001635390635,0.01761038796,-0.004309832561,-0.005738055333,-0.00309229633,0.001530119035,0.001510967724,-0.002940523324,-0.001498263901,-0.009211228319},
      {0.5804367796,0.2155406247,0.009113783133,-0.06723194348,-0.06538608389,-0.04335716313,-0.02060376514,-0.004696773187,0.003948194349,0.008872725116,0.01071974269,0.009954586687,0.006284486044,-0.0005572411781,-0.008004399967,-0.007154052675,-0.003247570857,0.0007330364625,0.0007405607874,-0.004259189846,-0.008487005841,-0.01175707758,-0.01324372235,-0.01432963738},
      {0.6864136592,0.3230698323,0.05327276797,-0.06049993804,-0.06671358983,-0.04816129378,-0.03010698939,-0.02147046206,-0.01759970757,-0.01333339324,-0.008737522106,-0.005317332191,-0.003381727388,-0.003548710995,-0.002955065571,0.0001298787541,0.003221278616,0.005598571012,0.003744215868,0.001164303156,-0.002848534419,-0.005932785871,-0.005462693502,-0.003673386575},
      {0.7099304308,0.3597672445,0.1171282977,-0.04175227967,-0.07963007451,-0.06419304355,-0.04352443716,-0.02730262578,-0.02057415534,-0.01892785619,-0.01854788821,-0.01624573028,-0.01136554787,-0.005733442974,-0.001181248565,0.002334764211,0.005312504116,0.005043943159,0.003346956698,0.00324115687,0.004968181506,0.008356605814,0.0111347535,0.01131283446},
      {0.7285796961,0.4103086636,0.1574273078,0.009279891477,-0.06718013256,-0.08137134782,-0.05890146532,-0.03650474755,-0.02033590981,-0.01323931238,-0.01193689731,-0.009247292752,-0.006940134186,-0.003747334284,-0.001985386555,0.0004301558072,0.002677482468,0.004253356004,0.003057702982,0.002036528248,0.004047184026,0.004834308138,0.003692454656,0.003170127997},
      {0.7301979501,0.4399129865,0.1707534748,0.04589316513,-0.01657803233,-0.06148458361,-0.06856206781,-0.04583694909,-0.02626771766,-0.01303206314,-0.008451675028,-0.008410759707,-0.006297574254,-0.003979094853,-0.0009648818074,-0.0009461634871,-0.0006691592607,0.0004480191465,0.002833901046,0.00206071579,-0.000448062288,-0.004225741132,-0.005099339299,-0.004160553051},
      {0.7289392786,0.4451772347,0.1994795263,0.05310953482,0.009690881806,-0.02582534014,-0.05614127307,-0.06623296098,-0.04360559311,-0.02418779427,-0.01099155859,-0.005801959434,-0.006083738244,-0.004961813024,-0.00379839584,-0.001868558356,-0.0007756206638,-0.0003764346381,7.627858841e-05,-0.001137327085,-0.002597053388,-0.003551950423,-0.004105441353,-0.002549975762},
      {0.725349898,0.4574365549,0.2274395101,0.04845702028,0.03080625093,0.006916045893,-0.01803370838,-0.04267920331,-0.06076206045,-0.03855251153,-0.01971845104,-0.006722736052,-0.001769255345,-0.002544303103,-0.004114405387,-0.00128456597,0.001625743983,0.003325585508,0.005815908008,0.005015895733,0.001967426959,0.0006786211153,-0.00156497542,-0.004599159373},
      {0.7315881043,0.4670585159,0.2543421956,0.07983397571,0.0284171299,0.02239315789,0.01059818479,-0.008558481087,-0.03434186269,-0.05248797339,-0.03095346351,-0.0148512559,-0.003523306643,-0.0003750568532,-0.003420299291,-0.002386253653,-0.002788640725,-0.0006127969666,0.001033170424,0.001062211591,0.001081291478,0.0007592723357,-0.001843694959,-0.004575513931},
      {0.7370514143,0.4810482457,0.2764443372,0.1061658348,0.0139608933,0.02127545264,0.02245786723,0.01769645312,-0.00206497321,-0.02922123635,-0.04936498251,-0.02792391834,-0.01208584808,-0.002225887352,0.002596505819,-0.001365676701,-0.003747181043,-0.003443119778,-0.004224783888,-0.002249459498,-0.002379585955,-0.004617210407,-0.006453783664,-0.00910424288},
      {0.7293168898,0.4760372897,0.2636677624,0.1280239091,0.03939966104,0.00694021272,0.01585160845,0.01848369691,0.01733589236,-0.005539746399,-0.02783905837,-0.04606168695,-0.02340161155,-0.004860175801,0.005475485971,0.007646850361,0.003515231425,0.001594156181,0.0001600901672,-0.001398882963,-0.00325812271,-0.001663755348,-0.002447443987,-0.002841628793},
      {0.7322805176,0.4827998796,0.288205287,0.1670320049,0.09054189863,0.01061099038,0.03019081615,0.04243031205,0.04923413684,0.04018037869,0.01121744212,-0.0153458642,-0.04002671257,-0.02870031308,-0.007184318553,0.004064080649,0.01102168496,0.0091969636,0.006737937246,0.004111108189,-0.001399907533,-0.005583074344,-0.006649595547,-0.005291278544},
      {0.7280354424,0.4890900296,0.298120418,0.1783025612,0.1203643027,0.04174238806,0.0164437794,0.02892617832,0.03451002011,0.03601754404,0.02119517037,0.002852410299,-0.01785842791,-0.03679828873,-0.02937270111,-0.0131986062,0.001321773559,0.007910370769,0.009449539654,0.008154426713,0.00670288731,0.006410754244,0.004389351899,0.002168668406},
      {0.7169258072,0.4756436714,0.2972899659,0.1829208494,0.1530204951,0.08223425288,0.009525387506,0.0269482829,0.03528677566,0.0422260951,0.04079030992,0.02052470541,0.001023736472,-0.02018732634,-0.03311054506,-0.01724554052,-0.002804836276,0.006564191058,0.01149987079,0.009952101046,0.007103108929,0.00538503189,0.007065163422,0.007813382004},
      {0.7164561957,0.4779015231,0.3067675299,0.2015904566,0.1805526612,0.1295206883,0.05670949377,0.03208390925,0.0452805059,0.05473823363,0.05791101449,0.05357143482,0.02533945894,0.00389471074,-0.01585482206,-0.02852063655,-0.02251018892,-0.006655870837,0.001418882805,0.005625563708,0.00664921731,0.006307274432,0.004931564479,0.003838805534},
      {0.7106070825,0.455588849,0.2952229461,0.1921236552,0.1795118603,0.144828898,0.08375968029,0.0190104954,0.03788950217,0.05359773496,0.06022014972,0.05651986848,0.04578708933,0.02498258119,0.007321814889,-0.009400983735,-0.02305372616,-0.02818978305,-0.01081254779,-0.0005847043499,0.006544205242,0.009540539646,0.006532075025,0.003733073667},
    },
    {
      {0.4020689286,0.07655335122,-0.05653669055,-0.06945145034,-0.02544085034,0.008914329366,0.01714463835,0.01289005867,0.01130702513,0.003903216411,-0.003909211792,-0.005797134265,-0.0006881316099,0.0009648023055,-0.0007445827036,0.01799061987,-0.003564874682,-0.004945148926,-0.003423452466,0.001240107153,0.001262234074,-0.002962569823,-0.001213617827,-0.007446372231},
      {0.577957013,0.2069730247,0.006869721948,-0.06489891837,-0.06122251551,-0.03930558546,-0.01800002213,-0.003491037168,0.004197083078,0.008094498751,0.009593836639,0.008598003953,0.005089641515,-0.001089110976,-0.00758432943,-0.006987623377,-0.00337844604,0.0002840178405,0.0005842944671,-0.003343309988,-0.006203992057,-0.008728644931,-0.01084984012,-0.0128742231},
      {0.6686157694,0.3068991513,0.0446609233,-0.05934632609,-0.05896430793,-0.04004931208,-0.02502148723,-0.01791407468,-0.01435497081,-0.009461864232,-0.00542297777,-0.003802270692,-0.003471693055,-0.003334569848,-0.001793067465,0.001859581615,0.004573019665,0.00602401422,0.002910298562,0.0002090732125,-0.002956249985,-0.005186582659,-0.004894533171,-0.00408553439},
      {0.6979045841,0.3478768567,0.1134869419,-0.04062223294,-0.07256223422,-0.05547420655,-0.03653157709,-0.02366596368,-0.01937029856,-0.01775786652,-0.01672771051,-0.0131789668,-0.007623287417,-0.002427105056,0.001338756493,0.004398670259,0.007143683935,0.007269480778,0.0053416476,0.003613228864,0.003750480911,0.007076203248,0.009649165546,0.01072361296},
      {0.7179468118,0.3941850398,0.1471051242,0.006148318598,-0.06142713867,-0.06991329867,-0.04608938848,-0.02575061277,-0.01394547126,-0.01100224256,-0.01270294465,-0.0107732879,-0.008196586433,-0.004256241281,-0.001492560278,0.0008522605904,0.002554025448,0.003051757716,0.001372627641,0.0001784095636,0.003860067555,0.006378354459,0.005854495837,0.005544699023},
      {0.7230183939,0.4235925408,0.1581668408,0.04282315394,-0.01251831616,-0.05188198232,-0.05846748436,-0.03724915501,-0.01913855945,-0.00838915079,-0.004886303837,-0.005751168894,-0.005617045667,-0.004358396223,-0.001443685218,-0.001509421178,-0.001179729957,9.708998887e-05,0.002725900699,0.002773021981,0.0006169920685,-0.001710132084,-0.002769149955,-0.002211544046},
      {0.7236288068,0.4321512362,0.1850697438,0.04717384137,0.01166236771,-0.01805100746,-0.04471756423,-0.05487224991,-0.03401588372,-0.01713799834,-0.005737458989,-0.001892234666,-0.002865635273,-0.002949715048,-0.003222965164,-0.001722517955,-0.0004487143411,-0.0003344164543,-0.0001090868078,-0.001812087315,-0.003012920423,-0.0045609064,-0.005574429277,-0.004909834205},
      {0.719822938,0.4468886162,0.2126218466,0.0432848129,0.03390723165,0.01426332903,-0.008758055098,-0.03474130228,-0.05282631903,-0.03154546786,-0.01441393682,-0.003409064002,0.000746046258,-0.0004431544158,-0.001809548567,0.0001809352211,0.002420946435,0.003415027397,0.005299161035,0.00506141032,0.001045635605,-0.0007212957907,-0.003209635156,-0.007236009788},
      {0.7293902618,0.4579169951,0.2390826711,0.07460054979,0.03149991111,0.03128205354,0.02022079343,-0.001364987882,-0.02836845177,-0.04523289687,-0.02480527729,-0.009355997501,0.0005316204972,0.003004816581,0.0004435508528,0.001722230614,0.002070267665,0.002223623016,0.00163357657,0.001070676381,0.0004985066972,0.000798424748,-0.0009925322637,-0.003871812993},
      {0.7342669838,0.4723102504,0.2595005958,0.09890835911,0.01443193486,0.02762675662,0.03139001305,0.02426406751,0.003757511078,-0.0231500464,-0.04235138952,-0.02206268106,-0.007166923694,0.000713516359,0.003770719215,-0.001166202148,-0.004085822302,-0.004250997749,-0.004405458645,-0.004163512725,-0.005759873163,-0.009076196236,-0.01184350036,-0.01349985795},
      {0.7288368713,0.4711405301,0.2558706915,0.1178634711,0.04048178794,0.01502256094,0.02651770643,0.02753709951,0.02063825673,-0.002387745324,-0.02509386631,-0.04206381957,-0.01980220166,-0.003159441079,0.006006026697,0.006918708692,0.002714951688,0.000226421717,-0.00164770912,-0.003397149086,-0.003838224538,-0.001969772243,-0.00218789144,-0.002618814773},
      {0.7309078556,0.4784149495,0.2794628898,0.1525914622,0.08641183787,0.01515066501,0.03966869681,0.05331241917,0.05645217691,0.04500661523,0.0161055102,-0.009460318871,-0.03226384392,-0.0221610771,-0.002523719157,0.007168168891,0.01229462299,0.009863522614,0.006721033606,0.004288335732,-0.0002451930509,-0.003172380486,-0.002918768325,-0.001402400789},
      {0.7300788538,0.489837318,0.2940873248,0.1690587682,0.1122906244,0.04315296735,0.02305501526,0.03797259951,0.04355485798,0.04251123856,0.02729736627,0.007729579838,-0.01387273144,-0.03205060712,-0.02628858934,-0.01034451481,0.003964154523,0.0108961599,0.01290122302,0.009822409909,0.008013305095,0.007936325524,0.007318066321,0.006883763847},
      {0.7180704249,0.4759921093,0.2927918216,0.1746345951,0.1395279155,0.07937778325,0.01487875991,0.03586458909,0.04438247731,0.04733510657,0.04264799353,0.02306633295,0.003718473488,-0.01776044993,-0.0299086062,-0.01311086079,0.001865718199,0.01061312914,0.01455684382,0.01342305802,0.01040308648,0.008703576336,0.009549603019,0.01044767307},
      {0.7170107727,0.4794971167,0.304825524,0.197935756,0.1733316683,0.1254683091,0.0606068021,0.04037609223,0.05295524004,0.05995606131,0.05943571028,0.05218721563,0.02912263146,0.009226418528,-0.008779984864,-0.0212264546,-0.02064125678,-0.005874103492,0.0009646287161,0.005204777528,0.007791451001,0.007084252881,0.005785978474,0.005949921897},
      {0.7102517644,0.456253221,0.2947385475,0.1914786719,0.1744889097,0.1337696219,0.08156450513,0.0230188709,0.04415066292,0.05898976777,0.06139836292,0.05510190134,0.04175305028,0.02429241665,0.007852849687,-0.007877940188,-0.02002925602,-0.02555007038,-0.008675325298,0.001147893585,0.007802282956,0.01146135478,0.009521661661,0.005208867799},
    },
    {
      {0.3817865754,0.06978515778,-0.05454527094,-0.0651148914,-0.02160176068,0.009045454566,0.01628462703,0.01158885585,0.009975808227,0.003705436299,-0.00335594332,-0.005541156519,-0.0005973993074,0.001485996348,0.0006825362895,0.01852360194,-0.002644809231,-0.003474421315,-0.003110197107,0.001583329836,0.001476396758,-0.003168055991,-0.0006805599969,-0.005879627641},
      {0.5743673197,0.1962363971,0.004513238253,-0.06196439221,-0.05645065627,-0.03501544607,-0.01491845655,-0.001228652835,0.005969261294,0.0088832966,0.009602342479,0.008211373097,0.004601828423,-0.001488867536,-0.007626515012,-0.00731791908,-0.004463789875,-0.001268378482,-0.001001485721,-0.0038333021,-0.004977590093,-0.006838792432,-0.008361127489,-0.01060531439},
      {0.6488094369,0.2895568309,0.03680378169,-0.05638793987,-0.04906452238,-0.03031837559,-0.01884828356,-0.01426076294,-0.01108094454,-0.005919824832,-0.001608183576,-0.0003012912709,-0.0005436616769,-0.0004967226163,0.0006173738141,0.003446191587,0.005497208121,0.007019863302,0.003071671921,-0.0004102139563,-0.003171461165,-0.004617008051,-0.004307305137,-0.005674939455},
      {0.6839455791,0.3331757087,0.1091180982,-0.03875863462,-0.06318957387,-0.04378950014,-0.02657608353,-0.01753307853,-0.01627789611,-0.01556531101,-0.01511733198,-0.0121244065,-0.007405821485,-0.002599411504,0.001432913795,0.004533533039,0.006594666238,0.006420752278,0.004848471673,0.003124037343,0.003457865471,0.007187970634,0.008987238258,0.01110538381},
      {0.7066973845,0.3780635346,0.1375857176,0.004306662646,-0.05547137353,-0.05880775722,-0.03348691702,-0.01502751909,-0.006672786643,-0.006968645023,-0.01095076496,-0.01040025663,-0.00822024159,-0.00414748245,-0.000988026394,0.001076039113,0.002183470284,0.002156671732,0.0009745567979,-0.0005667060762,0.002489472906,0.004868601997,0.004901912742,0.004741920952},
      {0.7148461813,0.4066167336,0.1454956189,0.0396717551,-0.007516242338,-0.04096183547,-0.04718734318,-0.02670023389,-0.01071847245,-0.001974895996,0.0002172468046,-0.001990491578,-0.004429387345,-0.004613877365,-0.002819958862,-0.002254496963,-0.002116716202,-0.0005608198689,0.002650406722,0.004423769828,0.003602809133,0.002161670671,0.001284888858,0.0015439554},
      {0.7172560239,0.4187045384,0.1717375843,0.04318361316,0.01603770003,-0.008389569307,-0.03209432792,-0.04329120626,-0.02370394872,-0.009401088105,-0.0003986223161,0.001962311545,0.0002653080003,-0.001006066731,-0.002570054468,-0.001332249916,9.929832501e-05,0.0005875283234,0.00145507241,-0.0005493697361,-0.002425287135,-0.004389670854,-0.005608637008,-0.004397454548},
      {0.7152279132,0.43745624,0.2001108482,0.03939257048,0.03778088892,0.0225322925,0.001147140812,-0.02580466952,-0.04381914537,-0.02291407068,-0.006702662347,0.002876097125,0.005287809693,0.003317515137,0.001349488172,0.001859657066,0.00231337007,0.002893315467,0.004978267247,0.006117462171,0.003608256443,0.001775714351,-0.000744864895,-0.004902580519},
      {0.7258577701,0.4481290716,0.2239904543,0.06944020848,0.03489105164,0.0407525044,0.03103615742,0.007918884649,-0.02008054021,-0.03743839976,-0.01722808025,-0.002796668967,0.005031816209,0.00560044026,0.002110664577,0.003032025193,0.003994285013,0.003461675609,0.001792459026,0.0008095150182,0.0004190582251,0.00205778603,0.001213941721,-0.001114048189},
      {0.7305776257,0.4626567126,0.2420744509,0.09132089364,0.01536872273,0.03494003004,0.04122245537,0.03149724818,0.01000348062,-0.01797562013,-0.03744276701,-0.01719693168,-0.002892539418,0.003704022636,0.005104121621,-0.0007609876206,-0.003357720815,-0.002525297225,-0.001136954221,-0.001761877187,-0.004712694569,-0.008961562818,-0.01275257137,-0.01379254988},
      {0.7277709834,0.4668672949,0.2499074388,0.1099973977,0.04309671705,0.02479095256,0.03926410786,0.03886261865,0.02639574325,0.002560344324,-0.02095933546,-0.03901151291,-0.01752767809,-0.001606672364,0.008015266892,0.009152273587,0.004336737943,0.001772070586,-0.0006726998916,-0.001751440135,-0.001792920331,-0.0004286278719,-0.0008807619688,-0.002116822777},
      {0.7295195719,0.47469713,0.271759198,0.1396126292,0.08315329293,0.0196196398,0.04855685789,0.0626769727,0.06194112695,0.04811546005,0.01893913733,-0.005947909179,-0.02806664754,-0.01771000764,0.0011902189,0.01024404266,0.01457927049,0.01168024469,0.008938707174,0.006020084674,0.002036629664,-0.0004963234485,0.0004874253078,0.002657766897},
      {0.7306453919,0.4888633044,0.2887260996,0.1594516506,0.1047418743,0.04492138952,0.0301805567,0.04716770738,0.05110801474,0.04639412517,0.03002047363,0.00956304763,-0.01169274981,-0.03014315619,-0.02434177508,-0.007651273034,0.006473290127,0.01343106718,0.0148703176,0.01147496634,0.007882310077,0.007062518545,0.006810565714,0.007281804709},
      {0.7190725515,0.476250394,0.2892982456,0.1691482016,0.1301123009,0.07922281713,0.02168133326,0.04583999261,0.05460134157,0.05412326214,0.04574649265,0.02569987053,0.006320930122,-0.01572977456,-0.02754365244,-0.01059576086,0.003995368312,0.01249183305,0.01504355853,0.01341834366,0.009728477553,0.008483765947,0.009338905414,0.01175441859},
      {0.7181978346,0.4809845902,0.302146921,0.1934791286,0.1655619741,0.1210198095,0.06469646472,0.04978952372,0.0620513956,0.06648789233,0.06169752031,0.04991283129,0.03272426569,0.0134585104,-0.00478589463,-0.01715871258,-0.01940905292,-0.004455810614,0.003864777278,0.008712867325,0.01201909087,0.01138172725,0.009744943206,0.008933376814},
      {0.7105423348,0.457741993,0.2927516802,0.188955245,0.1709082664,0.1262328737,0.08092220149,0.02645902672,0.0492997383,0.06279983569,0.06129659715,0.05249995398,0.03656322088,0.0224908444,0.007418526012,-0.006649359481,-0.01771407916,-0.02266624874,-0.006645492968,0.00212722049,0.008653479303,0.01318311261,0.01237428652,0.008085600338},
    },
  },
}
local GS_SYN_VAR9 = {
  {
    {0.006399893291,0.005425666646,0.004118347674,0.003611797223,0.002808591969,0.002309832779,0.001900118846,0.00163163376,0.001342785103,0.001166724705,0.0009777264749,0.0008539431023,0.0007533493117,0.0006566702897,0.0005806731242,0.0005334611904},
    {0.006703442361,0.005722696415,0.004604563755,0.003909832152,0.003204506206,0.002680889777,0.002240602618,0.001905813258,0.001621766534,0.001412923679,0.001210177437,0.001059516826,0.0009430497058,0.0008272850666,0.000735229973,0.0006807214438},
    {0.007205977419,0.006208966337,0.00535871499,0.004399446976,0.0038164316,0.003253167893,0.002763636699,0.002344751011,0.002049662506,0.001790635773,0.001567742414,0.001378377397,0.001235621878,0.001091947764,0.0009748942455,0.0009103632239},
  },
  {
    {0.006097158383,0.004860909692,0.003530952969,0.002951109774,0.002259649589,0.00183175158,0.00149572468,0.001275234285,0.001047484195,0.0009054465463,0.0007597249246,0.0006634261179,0.0005859232359,0.0005126205644,0.0004543164272,0.0004175757258},
    {0.006441398443,0.005180759296,0.003986832579,0.003244985706,0.002608357088,0.002147215377,0.001780623001,0.00150798338,0.001275081992,0.001104324242,0.0009445176006,0.0008267196677,0.0007348206812,0.0006465703343,0.0005747422682,0.0005314300598},
    {0.006999236811,0.005696751262,0.004692355654,0.003720118639,0.00314603127,0.002634120206,0.002220284996,0.001878999291,0.001624396783,0.001411447838,0.001230115118,0.001081283214,0.0009666751624,0.000855118355,0.0007631515592,0.000709969865},
  },
  {
    {0.006110497864,0.004542411158,0.003129694357,0.002461035127,0.001846234589,0.001463776715,0.001180770277,0.0009968250668,0.0008137150907,0.0006987525114,0.0005863008992,0.0005105666913,0.0004507834673,0.0003956367053,0.0003507370836,0.0003216266228},
    {0.006514011508,0.00490194666,0.00357666239,0.002760543894,0.002163394475,0.001737995625,0.001424036851,0.001200339222,0.001000910564,0.000861331543,0.0007333044819,0.000639585253,0.0005673877491,0.0004989908675,0.0004438821764,0.0004073999717},
    {0.00715821651,0.005472491338,0.004267512203,0.003240962739,0.002650663181,0.002161639039,0.001799851084,0.001521307807,0.001290275652,0.001114028454,0.0009619752912,0.0008414442544,0.0007502618465,0.0006614859282,0.0005905974749,0.0005439063303},
  },
  {
    {0.006441049848,0.004470706322,0.002914293097,0.002144162551,0.001567429845,0.001204619772,0.0009585981202,0.0007974329143,0.0006428221214,0.000546878734,0.0004572537362,0.0003960600805,0.0003495277565,0.0003067256169,0.0002717444197,0.00024857486},
    {0.006924180457,0.004887285532,0.003374917999,0.002462039249,0.001869469314,0.001454790886,0.001174048461,0.0009817898452,0.0008019746833,0.0006832559248,0.0005762529679,0.0004996352465,0.0004418210018,0.0003873684053,0.0003434094083,0.0003126599208},
    {0.007687374207,0.005543698439,0.004084676916,0.002967540778,0.002333159082,0.001843372036,0.001508015324,0.001270480222,0.001050207655,0.0008964897345,0.0007641089517,0.0006634518119,0.0005877207304,0.0005152012888,0.0004577664781,0.0004168434515},
  },
  {
    {0.007092445776,0.004647418299,0.002888171246,0.002004763318,0.001424893645,0.001064172304,0.0008324207338,0.0006814751921,0.0005423542762,0.0004554867267,0.0003797281737,0.0003271780984,0.000287181917,0.0002518221927,0.0002234214379,0.0002038801767},
    {0.007675948007,0.005141045287,0.003384845773,0.002352856766,0.001728955213,0.00130770941,0.00103512883,0.0008586001359,0.0006868646754,0.0005772259524,0.0004836359677,0.0004162144586,0.0003644995475,0.0003177466727,0.000281758067,0.0002541369545},
    {0.008591433532,0.00591267177,0.004148431778,0.002903138006,0.002196015857,0.001686928402,0.001352232603,0.00113425764,0.0009139865622,0.0007694973111,0.0006488590778,0.0005585180782,0.0004883260997,0.0004238716719,0.0003758690463,0.0003378345865},
  },
}
local GS_SYN_AC17 = {
  {
    {
      {0.20659818,0.04888961009,-0.001035277555,-0.01123187296,-0.01337948904,-0.01485083822,-0.009858192617,-0.01513050215,0.00456044931,0.003912419966,0.003998344593,-0.005284316201,-0.002817489777,-0.001858458183,0.001903773014,0.3075915408,0.006574864032,0.006091816804,-0.007741297605,-0.004936399396,0.0006664704095,-0.001283688637,0.006211496059,-0.01195280387},
      {0.4330980068,0.160859795,0.05300335807,0.007196091011,-0.02213545766,-0.03390423252,-0.03523008463,-0.0268921869,-0.006952376326,0.003806165949,0.002773457961,0.004142184017,0.006159187811,0.003078711753,0.001887525381,0.005605687329,0.003634881044,0.003131142795,0.0001028042411,-0.003574537682,-0.006174199654,-0.002613661469,0.003582164086,-0.01064125772},
      {0.6234926209,0.2820973571,0.1127952005,0.03000291492,-0.01314988473,-0.03626487629,-0.04694029421,-0.04263436968,-0.02604379147,-0.01325205521,-0.008604449916,-0.003566643239,0.004386181509,0.007550064362,0.005107466287,0.001390350078,0.0008029403446,0.002126100927,0.003952302183,0.004270275809,0.002216824364,0.001990385827,0.004649084783,0.001826357965},
      {0.6627952968,0.3548878675,0.1581402674,0.04823897179,-0.01114873886,-0.04066616559,-0.05150150229,-0.04857863888,-0.03800143641,-0.02719349259,-0.01867731479,-0.01453560802,-0.01110208286,-0.008567269246,-0.007738336552,-0.00470282878,0.0008806360131,0.004894683866,0.004784907854,0.003538183195,0.005457305381,0.01062585814,0.01531108405,0.01591397532},
      {0.7527495416,0.4502508175,0.2186254676,0.07890045408,-0.001657508792,-0.04443689368,-0.06006178155,-0.05645114324,-0.03953251063,-0.02264907267,-0.01184252577,-0.007444597868,-0.006123070685,-0.005755849283,-0.005839979697,-0.00457923534,-0.003163209049,-0.003505248606,-0.003537170252,0.0007010766435,0.007373671551,0.009919479425,0.008880527706,0.005067284044},
      {0.7897088482,0.5112917437,0.2648812519,0.1059582511,0.008002553058,-0.0446997427,-0.06552642572,-0.06224037101,-0.04658205915,-0.0305193104,-0.01713634553,-0.008579684637,-0.004376466288,-0.003958052372,-0.004716360099,-0.005538316099,-0.006593678371,-0.007723208439,-0.008182077517,-0.007914108713,-0.006910871727,-0.004676280677,-0.002725482555,-0.002378822074},
      {0.8133222562,0.5528981084,0.319853639,0.140768629,0.02810871078,-0.03799780736,-0.06999874242,-0.07697592894,-0.06433382436,-0.04705017416,-0.03043673128,-0.01802086879,-0.01014228041,-0.006516264629,-0.005518722343,-0.005215840425,-0.004154340892,-0.001191001759,0.002957407953,0.006127783683,0.006849492547,0.005065891643,0.001682796727,-0.003246478284},
      {0.8295752425,0.5755813157,0.3568634809,0.1656327439,0.04509370216,-0.02863919687,-0.06455951677,-0.07207864841,-0.06197468858,-0.04391731213,-0.02722409114,-0.01432331297,-0.007163616275,-0.003875653115,-0.003618758954,-0.005183889773,-0.006378946985,-0.008244661465,-0.008775417464,-0.005847820195,-0.0003517001541,0.003793107074,0.006963185393,0.009120639945},
      {0.841168361,0.6081217312,0.393778992,0.1990621354,0.05827604725,-0.02609639693,-0.06938020736,-0.08060028262,-0.07146582666,-0.05557421337,-0.03637400015,-0.02114707518,-0.01169021808,-0.006073075018,-0.002956457787,-0.001632640857,-0.001198831177,-0.0002434054547,0.0002717546067,-0.001102290181,-0.003815269397,-0.006266340331,-0.007925461702,-0.008465985705},
      {0.849779219,0.631077492,0.4174265631,0.2288839777,0.07729136492,-0.01000189803,-0.05851169429,-0.07413951506,-0.06692088453,-0.05373749222,-0.04123226244,-0.02767317858,-0.01926692733,-0.0150323998,-0.01266137213,-0.01128938016,-0.009771857751,-0.007487753141,-0.004252898575,-0.001476834938,-0.0004720384239,-0.0008537756542,-0.000983769238,-0.0008253559743},
      {0.8554917875,0.6512004992,0.4338631851,0.2592717771,0.1038216215,-0.0003071388324,-0.05447710822,-0.07478732322,-0.07044747615,-0.05675343908,-0.04103684046,-0.02828176538,-0.01569770561,-0.008238807396,-0.005138789011,-0.003535098938,-0.00342907658,-0.003695237999,-0.003051390833,-0.001216679133,0.0009125102102,0.002155822402,0.002376639834,0.0006789508573},
      {0.8635166673,0.6707164191,0.451719129,0.2868331974,0.1357146042,0.01918175225,-0.03986589116,-0.06703910241,-0.0684922351,-0.05794998252,-0.04299909555,-0.03077346609,-0.02232894075,-0.01455249144,-0.01035235312,-0.007746227815,-0.004859629576,-0.002306354796,-0.0006652080537,0.0009481027611,0.001787481854,0.002653625978,0.002505551014,0.002946951118},
      {0.8661727412,0.6801368487,0.4702607868,0.2999149222,0.1531916934,0.03332392036,-0.03897915872,-0.06869728306,-0.0718553394,-0.06280474319,-0.04868085369,-0.03487648299,-0.02589040897,-0.02137167921,-0.01776928678,-0.01466465489,-0.01171244657,-0.008587973215,-0.004882602552,-0.0007918386619,0.003069237416,0.005908325306,0.007661703663,0.009584721399},
      {0.8668658352,0.6858338456,0.4862146211,0.3132628738,0.1765686424,0.05623358626,-0.03094107872,-0.06529789149,-0.07241370838,-0.06604985805,-0.05032559453,-0.0340291975,-0.01967534594,-0.009070544131,-0.004771205909,-0.001832286641,-0.0002978812797,-0.0002696071814,-0.0004441534677,-0.0006513693915,-0.0004312664535,0.0003745711316,0.001404678325,0.00333212355},
      {0.8708767087,0.6964567643,0.5048056872,0.3222768239,0.1899833056,0.07426393118,-0.01479136518,-0.06175299579,-0.07230173485,-0.06833059313,-0.05486280477,-0.03763359169,-0.02310606734,-0.009460398881,-0.0003591117179,0.004397668352,0.005194678855,0.006735273382,0.005631202319,0.003576365103,0.001854309003,-0.0008305146351,-0.00277783525,-0.003737342666},
      {0.8684543284,0.6991384637,0.5167864914,0.3292296241,0.2026154145,0.09029305068,-0.0001542809564,-0.06137548462,-0.07410947945,-0.0740535326,-0.06497150944,-0.05084891148,-0.03742991445,-0.02704545956,-0.01865634807,-0.01570384422,-0.01621576333,-0.01825719864,-0.01749173596,-0.0188606265,-0.02067496063,-0.02207228983,-0.02287641909,-0.02230420805},
    },
    {
      {0.2012917204,0.04683532038,-0.001978247683,-0.01113280336,-0.01129211599,-0.01443034063,-0.008802230063,-0.01483957609,0.004263867285,0.003197144419,0.003138345004,-0.005862028222,-0.003199356513,-0.002632221442,0.0003549391913,0.3033820086,0.005420157294,0.00716937176,-0.00745433428,-0.004836166688,0.003585167408,-0.0009987210918,0.006532627952,-0.0104487876},
      {0.4296785858,0.1568727291,0.05166619206,0.006722815519,-0.02206107449,-0.03384030834,-0.03451048479,-0.02578710956,-0.006772845135,0.004127387651,0.002560024819,0.002991054952,0.005621469317,0.00309718979,0.001459599581,0.006220969362,0.003704224922,0.002986982991,-0.0009186613584,-0.003372287863,-0.005037282765,-0.002169753232,0.003575090747,-0.01040690648},
      {0.5991258451,0.2669148751,0.1050977782,0.02667148586,-0.01350658716,-0.03457846476,-0.04437397216,-0.04030507819,-0.02420290668,-0.0123401248,-0.008152957496,-0.003012668814,0.00515701566,0.008184530196,0.005666496542,0.0008290319835,-0.0008285978472,0.0005843762028,0.003126600224,0.003363828107,0.0006274120665,0.0004257029113,0.002667097089,-0.0002114149009},
      {0.6561809085,0.3462134612,0.1552253893,0.04712701244,-0.01066434095,-0.0385459596,-0.0485904669,-0.04496895647,-0.03400642823,-0.0238514442,-0.01627060003,-0.01258793767,-0.009423196542,-0.006253548269,-0.005157909916,-0.002618980334,0.002076787223,0.005575967404,0.005175752864,0.003819152446,0.005001463251,0.008980733617,0.01243376922,0.01265212739},
      {0.7317181127,0.4306630421,0.2074671235,0.0761369634,-0.001138064555,-0.04190507849,-0.05623892522,-0.05274814993,-0.03676172663,-0.02159345568,-0.0119489321,-0.00776850221,-0.006236945889,-0.005794648027,-0.005772425425,-0.004525214324,-0.00280482369,-0.002925744641,-0.00349693966,0.0004373087765,0.007435082969,0.01138047811,0.01179233587,0.00908548745},
      {0.7697857438,0.4883736455,0.2490762155,0.09965581582,0.008077999454,-0.04178023536,-0.06165768939,-0.05773666617,-0.04184938098,-0.02618690292,-0.01359009426,-0.005412014975,-0.001459700986,-0.0008288921728,-0.001260623864,-0.001929921546,-0.003610345047,-0.006079517269,-0.007494667508,-0.007655465964,-0.007411013559,-0.005360390584,-0.003284399328,-0.002195390221},
      {0.7958391508,0.5289802407,0.3022960426,0.1309735069,0.02593874101,-0.03546383128,-0.0656156363,-0.07166837972,-0.0583083432,-0.04146475521,-0.02624132531,-0.01518359281,-0.008158537039,-0.005166643527,-0.004513716407,-0.004123151244,-0.003016963713,0.0001910769199,0.004119677748,0.007030597612,0.007436426727,0.006013184987,0.003102086584,-0.001581857882},
      {0.8139623952,0.5573932751,0.3449897835,0.1590747036,0.0448955428,-0.02517589925,-0.05933500318,-0.06683089111,-0.05681398304,-0.03929487887,-0.02391701083,-0.01263699396,-0.006967581398,-0.004918346417,-0.004974316261,-0.006441207532,-0.007821316196,-0.009547871916,-0.009638281563,-0.00670604958,-0.001459258624,0.002479181462,0.006126017661,0.008860189534},
      {0.8273947574,0.5853714348,0.3739434779,0.1870055089,0.05287069718,-0.02567499731,-0.06527375948,-0.0746539051,-0.06497238591,-0.04957277155,-0.0311188344,-0.01707442784,-0.008641328378,-0.003714101685,-0.0009111922558,0.0004468107373,0.001043551863,0.001646468852,0.001301784843,-0.0007419738777,-0.004470303003,-0.008535852472,-0.01142819537,-0.01251881491},
      {0.8366871911,0.6088041733,0.3961140553,0.2157625981,0.0688825806,-0.0127344669,-0.05742814867,-0.07074743984,-0.06265742729,-0.04989546914,-0.03818150917,-0.02524109302,-0.01691123063,-0.01218444907,-0.009145585192,-0.007506456536,-0.005829214452,-0.00390099485,-0.001414517963,0.0002539651771,-0.0001574218421,-0.001545137515,-0.001981665532,-0.001276060999},
      {0.843876819,0.6290386749,0.4119465521,0.2436170543,0.09592078283,-0.002400239268,-0.05202654486,-0.06922070619,-0.06347946379,-0.05054875232,-0.03746181093,-0.02727023265,-0.01650921825,-0.009467526364,-0.005492251485,-0.002469787248,-0.0006964931514,0.0005046992197,0.002025565221,0.003350993831,0.004130527998,0.00396470264,0.00324828402,0.0006730085},
      {0.8529387029,0.6498568513,0.4295889829,0.2701509379,0.126956364,0.01495596864,-0.03904221474,-0.06202883564,-0.06064066224,-0.04913492245,-0.03532874157,-0.02465643385,-0.01820580652,-0.0121352182,-0.009572635556,-0.007419998396,-0.004397893871,-0.001381534816,0.0005654006991,0.002027719394,0.003106610114,0.004035432044,0.004361996617,0.003980475123},
      {0.856715009,0.6609113689,0.448203698,0.2827707127,0.1439271547,0.03049891223,-0.03691356926,-0.06272238682,-0.06363572293,-0.05460436103,-0.04204019755,-0.03084474792,-0.02391335115,-0.02046478259,-0.01758302076,-0.01477360175,-0.01162132128,-0.008327503193,-0.004622061123,-0.001044875575,0.001963818583,0.002976197227,0.002420501141,0.002449937383},
      {0.8577560986,0.6670193848,0.4630675826,0.2929511329,0.1617158627,0.04904313827,-0.03340262827,-0.06391880471,-0.06855760983,-0.06148990717,-0.04651796983,-0.03105417206,-0.01840210047,-0.009134732201,-0.004810031245,-0.001136708217,0.001561200836,0.00225658608,0.002430093543,0.002182865707,0.002083744523,0.001364151092,0.0002350319046,-0.000220835674},
      {0.8634685246,0.6810569697,0.4837668183,0.3031960513,0.1757804363,0.06640610649,-0.01662055451,-0.05902165338,-0.0660877403,-0.06048161317,-0.04694877832,-0.03145622074,-0.01840408614,-0.007112679579,0.0002484424856,0.004344327816,0.004113237597,0.006175668823,0.004550676165,0.001682581453,-0.0009357911681,-0.00380282529,-0.005203772446,-0.005644290206},
      {0.8588614182,0.681483494,0.4922745565,0.3070944006,0.1857093453,0.07788964543,-0.004022162867,-0.05998973362,-0.06857308787,-0.06627820942,-0.05647954571,-0.04331701489,-0.03201466358,-0.02355621089,-0.01726081574,-0.01547923077,-0.0160181472,-0.01684320106,-0.01487988675,-0.01554343615,-0.01618655383,-0.01716068643,-0.01780596262,-0.01730852443},
    },
    {
      {0.1926536429,0.04415716978,-0.00235886403,-0.010862062,-0.009214316945,-0.01382186634,-0.007681919145,-0.01381421939,0.004314861962,0.002832812548,0.002748239699,-0.006254567969,-0.003617262892,-0.002681545025,-0.001032664822,0.2984492626,0.003702709792,0.007067918089,-0.007630993988,-0.004872991046,0.005521389795,-0.001923369336,0.006132227381,-0.008173928895},
      {0.424555498,0.1511278536,0.04944172446,0.005975285807,-0.0222415973,-0.03318924846,-0.03337212345,-0.02472411442,-0.006376798504,0.005422454173,0.004131515385,0.004272229136,0.006945954752,0.004243413541,0.001048550534,0.006157205876,0.003439859855,0.002747969261,-0.001206475469,-0.003539140092,-0.004971435224,-0.001875599663,0.004576061855,-0.009222935832},
      {0.5694003301,0.2480743257,0.0956127965,0.02304139787,-0.01296014785,-0.03158312544,-0.04032640442,-0.03627391521,-0.02092192166,-0.01018340183,-0.006428370308,-0.001719489919,0.005958814922,0.007911937934,0.005098462137,0.0005233059163,-0.0009526700579,0.0006364249931,0.003004802271,0.002789946759,-0.0006372843457,-0.001238991198,0.00154248745,-0.0005781438452},
      {0.6471376059,0.3336740889,0.1507888977,0.04575053295,-0.009545380873,-0.03603188506,-0.045647349,-0.04237036597,-0.03177602718,-0.02248296069,-0.01579840666,-0.01315019791,-0.01074017737,-0.007583077839,-0.00616328822,-0.002960043571,0.001705873802,0.004540002306,0.00430259691,0.002357771228,0.002269017637,0.0060269548,0.009837607223,0.01076490215},
      {0.7066796734,0.4073712395,0.1934242981,0.07093331107,-0.002734645271,-0.04149669644,-0.05445265907,-0.05044654639,-0.03414188815,-0.01973392912,-0.01098798805,-0.007181567602,-0.005697065684,-0.005445710195,-0.005760109954,-0.005301621434,-0.003842961163,-0.003533659431,-0.003768061844,0.0004951010114,0.007542108627,0.01244515385,0.01291411909,0.009958367155},
      {0.746803141,0.4621088191,0.2307906648,0.09142591164,0.006903790701,-0.03994787649,-0.05905838041,-0.05463351339,-0.03842753268,-0.02389172503,-0.01260180442,-0.005166953647,-0.001131672054,0.0001994100087,0.0007121239117,0.0009539534355,-0.0008629924987,-0.004146719765,-0.006751498386,-0.00733345873,-0.007504302337,-0.005426019953,-0.003451780112,-0.002051202076},
      {0.7756144961,0.5010211506,0.2818677119,0.1194006954,0.02280949219,-0.03362003336,-0.0620181336,-0.06716400221,-0.05313389318,-0.03656599754,-0.02245717208,-0.01255041848,-0.006247906593,-0.003862636968,-0.003759185861,-0.003477728869,-0.002568263015,0.0007528651335,0.004435509236,0.006974478447,0.007348230847,0.006501034904,0.004057754443,-4.641815243e-05},
      {0.7950143448,0.5331872965,0.32790118,0.1479787758,0.0413289085,-0.024476433,-0.05720473023,-0.06489810166,-0.05531750661,-0.03846239506,-0.02390658337,-0.01338331747,-0.007831624676,-0.004880777307,-0.003517053021,-0.003665741429,-0.003857802401,-0.004991273573,-0.004921930597,-0.002631843132,0.002038863873,0.005292087342,0.008137037258,0.01040153965},
      {0.8112947814,0.5587074078,0.3508534101,0.1729435172,0.04644438772,-0.02519662364,-0.06066203923,-0.06818848184,-0.05827351878,-0.04363018621,-0.02625669294,-0.01338249572,-0.006035480239,-0.002162078091,-0.0004818344398,0.000468319958,0.001387483501,0.002314418497,0.002436192451,0.0009850263569,-0.002527419703,-0.00724953321,-0.01096684317,-0.01271880938},
      {0.8219903771,0.5841462946,0.3732856077,0.2031274341,0.062457964,-0.01324794409,-0.05403085703,-0.06547386462,-0.05701199122,-0.045229272,-0.0352968653,-0.0236718754,-0.01634816037,-0.01208763775,-0.009322778635,-0.007490534651,-0.005862116643,-0.004125700071,-0.001766021649,-0.0003701844191,-0.0009618485157,-0.001978861668,-0.002002612186,-0.001252902226},
      {0.8307693155,0.6043773517,0.3877637249,0.2261867767,0.08659469393,-0.005860583105,-0.05094815877,-0.0649537611,-0.05770929574,-0.04478290936,-0.03329529038,-0.02469049965,-0.01520322723,-0.008957901883,-0.005399834615,-0.002501836277,-0.000588994548,0.001314235461,0.003328904176,0.004870440072,0.005234271368,0.004618000552,0.003823797306,0.001107310331},
      {0.8418232707,0.6274486991,0.4062318441,0.253315376,0.1189179823,0.01199652712,-0.037842197,-0.05800683255,-0.05536517066,-0.04418458444,-0.03248008924,-0.02387549436,-0.0188729079,-0.01323519354,-0.01072254561,-0.008267796609,-0.005022641519,-0.001257179375,0.001589036223,0.003262679599,0.00420158038,0.004526571023,0.004415870544,0.003485499745},
      {0.8462335508,0.639917086,0.4241199085,0.2640698212,0.1335863372,0.02740992058,-0.03436591446,-0.05570935113,-0.05343866289,-0.04362495788,-0.03203448764,-0.02307935663,-0.01856564519,-0.0161852041,-0.01362722686,-0.01077643189,-0.007233138023,-0.004113430207,-0.0009406232865,0.001997476836,0.003476147689,0.002745903174,0.0003225978562,-0.000812068469},
      {0.8476131072,0.6466821837,0.4382689461,0.2715092288,0.1466907979,0.04225549225,-0.03471644046,-0.05990792214,-0.06026290712,-0.05102145845,-0.03620004723,-0.02218758583,-0.01219907554,-0.005954501408,-0.00370381546,-0.001899704891,0.0002575336794,0.0006508141222,0.001004118979,0.001299300591,0.00168229761,0.0003302610161,-0.001591853063,-0.003003102798},
      {0.8549364248,0.6636917275,0.4604546004,0.2818138638,0.1603706401,0.05755239683,-0.01933201251,-0.0571330266,-0.06087602439,-0.05356063753,-0.0397756264,-0.02569241098,-0.01357621787,-0.004190236774,0.001668708996,0.004594414811,0.003530575179,0.005645698437,0.004121312804,0.001418413154,-0.0009633353356,-0.003001624243,-0.003051026613,-0.002737409857},
      {0.8507242735,0.6654143403,0.469281406,0.2856553063,0.1700779584,0.06750753766,-0.005757907974,-0.0559861609,-0.06019887953,-0.05514937594,-0.04451108673,-0.03191671599,-0.0214488636,-0.01422654959,-0.01035343436,-0.01036330988,-0.01284947205,-0.0145290802,-0.01259988548,-0.01300790623,-0.01300575171,-0.01261132098,-0.01259315533,-0.01241459834},
    },
  },
  {
    {
      {0.2777528093,0.0761045504,0.004010217631,-0.01333462418,-0.01737499765,-0.01802792981,-0.01386661128,-0.01543091367,0.003927517491,0.004217750383,0.003234963091,-0.002884713873,-0.001442832358,-0.001088665244,0.000973193153,0.2125632098,0.00415117048,0.005303739321,-0.005053560084,-0.002980300545,0.002580646717,0.001598666089,0.006693625411,-0.01082520308},
      {0.5021848166,0.2199533257,0.08480683687,0.01900896387,-0.02205760182,-0.04164616411,-0.04512877651,-0.03519554663,-0.01456591791,-0.001277127149,0.002373215239,0.005452111393,0.00782279153,0.005705406633,0.003399337084,0.005345488807,0.004697777123,0.00485389847,0.00125066876,-0.002049727428,-0.004113735847,-0.002633585024,0.001418690116,-0.00875085531},
      {0.6704017751,0.3459618079,0.1556747648,0.05106795436,-0.005992956352,-0.03758954748,-0.0520516279,-0.05017974304,-0.03553984801,-0.0221715552,-0.01512083531,-0.008049879003,0.001234122524,0.005824760873,0.005397250461,0.003962803201,0.003995892052,0.00526958143,0.006404069163,0.006163258247,0.004472430344,0.004137588808,0.004798448001,0.001613452737},
      {0.7043980288,0.4103136414,0.2085611741,0.07937110617,0.00385246995,-0.03566921056,-0.05327022781,-0.05442995512,-0.04520350341,-0.03437081547,-0.02553792477,-0.02071630512,-0.01639622278,-0.0119734477,-0.008187437997,-0.003176215667,0.001831584483,0.004415203436,0.003726303864,0.003067407659,0.00554382656,0.01032966422,0.01350526961,0.01273865647},
      {0.775002073,0.4922236517,0.2654142847,0.1165546803,0.01946531376,-0.03575599687,-0.05856194921,-0.06019753971,-0.04734811729,-0.03277241947,-0.02199675719,-0.01569383685,-0.01160111439,-0.008976854555,-0.007197949259,-0.004890656379,-0.002711859299,-0.001753454675,-0.0006652246254,0.00353942264,0.009059005832,0.01141020278,0.01104263901,0.00807507738},
      {0.8047461097,0.545114327,0.3047167592,0.144431684,0.0360122476,-0.03023165416,-0.06101494918,-0.063003767,-0.05051697569,-0.03614839569,-0.0233720759,-0.014501608,-0.008590334371,-0.006230018462,-0.005462157995,-0.005994740333,-0.007728272169,-0.01005837719,-0.01168527268,-0.0118385108,-0.01111940591,-0.009102551014,-0.00655801255,-0.004936803807},
      {0.823499608,0.5784565627,0.3525990201,0.1743406969,0.05669454685,-0.01879478601,-0.06135876122,-0.07544315944,-0.06448189811,-0.04855761863,-0.0328619057,-0.02093256697,-0.01319661588,-0.009816181404,-0.008331982505,-0.007834489795,-0.00702967482,-0.004666810875,-0.002298197412,-0.0005823905258,-0.0007916517265,-0.002596316377,-0.004981134322,-0.007940109981},
      {0.8377556785,0.5995925655,0.3867164544,0.1953940538,0.07351127208,-0.007116310563,-0.05285614696,-0.07045380707,-0.06787259403,-0.05233378797,-0.03624335117,-0.02252639886,-0.01402811621,-0.008431733946,-0.005412896315,-0.004480385812,-0.004016057773,-0.004904258499,-0.004691926128,-0.001805496598,0.00265167828,0.005324300532,0.006782760435,0.007467548808},
      {0.846818528,0.6258350726,0.418966528,0.2266069675,0.08572652071,-0.001701825217,-0.05162720142,-0.07105456287,-0.06965252429,-0.06016721419,-0.04258152777,-0.02773864721,-0.01755208786,-0.01068662215,-0.006057730668,-0.002567942258,-0.0002742211025,0.001829724902,0.002723672253,0.001872776478,-0.001036387674,-0.004376261637,-0.006391613762,-0.006598616901},
      {0.8547667653,0.6458664508,0.4412142472,0.2556934115,0.1031108001,0.01468631147,-0.03923522422,-0.06238045774,-0.06273930351,-0.05653203977,-0.04938341378,-0.03549999708,-0.02572945595,-0.01966460637,-0.01548878419,-0.01243734065,-0.009793851266,-0.007033639054,-0.004179849802,-0.001575113367,-0.00105125746,-0.001971170288,-0.00210004023,-0.001936494527},
      {0.8585551328,0.6615850969,0.4533695147,0.2830728523,0.1284832077,0.02400782297,-0.03273477695,-0.05820684968,-0.05921075267,-0.05186772998,-0.04210593976,-0.03397997858,-0.02099612837,-0.01227914077,-0.008186817567,-0.005589774082,-0.00431125647,-0.00357754613,-0.003078625721,-0.002539305563,-0.002319073343,-0.002260299622,-0.002921500985,-0.004804221562},
      {0.8647387878,0.6768964723,0.4675902572,0.3058743356,0.1560461352,0.03781926706,-0.02112031894,-0.05058260817,-0.05596464413,-0.05049550882,-0.04144807235,-0.0340696031,-0.02939840271,-0.02087473809,-0.01501003368,-0.01046648174,-0.005904273244,-0.002028432217,-0.0004703765463,5.670271048e-05,-9.531473825e-05,-0.0003395531805,-0.001160252506,-0.001123061271},
      {0.8675850791,0.6855946619,0.4838079019,0.3184808093,0.174811147,0.05511042977,-0.01831942423,-0.04927393219,-0.0558392747,-0.05165996577,-0.04356535935,-0.03449616096,-0.02909508203,-0.02668053229,-0.02176826867,-0.01605410245,-0.01030137505,-0.005265051793,-0.0004328224754,0.00417006593,0.007658542708,0.008644579624,0.007674901301,0.006600215108},
      {0.8668331043,0.6887854519,0.4963630574,0.3286355492,0.1946311747,0.07493532199,-0.0137804711,-0.047095801,-0.0554943476,-0.05280894886,-0.04185327605,-0.03055557178,-0.0203318403,-0.01271043869,-0.009944165816,-0.006450008247,-0.003075871439,-0.001789408498,-0.0006953063483,-0.0007963772725,-0.001242133919,-0.002316807634,-0.003047685303,-0.001953117363},
      {0.8713367246,0.6998837352,0.5143140167,0.3375095738,0.206174575,0.09064084311,0.0001492201507,-0.0475624313,-0.05861231244,-0.05722322733,-0.04721652458,-0.03361231143,-0.0235113397,-0.0135674302,-0.00767942289,-0.006329193129,-0.007889423454,-0.004454710845,-0.003688456383,-0.003300400033,-0.003290356374,-0.003499164919,-0.003419083717,-0.002935921541},
      {0.8685494433,0.6999342977,0.5238047992,0.3435274093,0.2182438897,0.1074385967,0.01746912644,-0.04514489489,-0.05714063914,-0.05865378225,-0.05320738058,-0.0431965688,-0.03358261657,-0.02762146059,-0.02234325987,-0.02187498365,-0.02441396375,-0.02632290029,-0.02246369164,-0.02181835339,-0.0214712568,-0.02145768026,-0.02066675409,-0.01850930201},
    },
    {
      {0.2703917197,0.07240299487,0.002747724172,-0.01304830763,-0.01552857757,-0.01752651284,-0.01305512465,-0.01521135981,0.003322822554,0.00379864817,0.00235961453,-0.004220082769,-0.001593495314,-0.001368501596,0.0006099793133,0.2091489274,0.004289709644,0.005958708802,-0.005860895583,-0.004053299674,0.003323023922,0.0004352173378,0.005761865287,-0.009715691229},
      {0.499448059,0.2147554837,0.08233063293,0.0179835567,-0.02259986563,-0.04154584261,-0.04445579851,-0.03459926105,-0.01443957566,-0.0007605277615,0.002702818991,0.005191040159,0.007934706802,0.005811714147,0.00322468079,0.006225744813,0.005282917251,0.005200564351,0.001068518399,-0.001771410592,-0.003772137107,-0.002097276452,0.001371039966,-0.009378891918},
      {0.6480997628,0.3293751336,0.1453577558,0.04619223608,-0.006471308117,-0.03576119687,-0.04922660441,-0.04721136011,-0.03278775703,-0.02022772965,-0.01341514992,-0.006049825605,0.002775423563,0.006620881744,0.005682317171,0.003377604784,0.002027678929,0.002397643475,0.003250733897,0.003109839466,0.001474259043,0.001306374979,0.003176667113,0.001160660888},
      {0.6972174514,0.401376112,0.205373266,0.07789958577,0.004334750867,-0.03407883586,-0.05110611858,-0.0517337237,-0.04220343383,-0.03171100577,-0.02340795663,-0.01876075772,-0.01453324439,-0.01025225053,-0.006397512706,-0.001346808935,0.003315252431,0.005324712998,0.004696356703,0.003633610271,0.005236716664,0.009576478704,0.01304775844,0.01295494749},
      {0.7564367203,0.4729080598,0.2528414503,0.1112207575,0.01763557804,-0.03519934549,-0.05626036587,-0.05682893127,-0.04321093323,-0.02886201542,-0.01868545374,-0.0127893088,-0.009537197987,-0.00804312909,-0.007495685699,-0.006490607319,-0.004511448322,-0.003206110115,-0.002100547681,0.001934521909,0.007787849224,0.0110230109,0.01153508622,0.009570111584},
      {0.787449435,0.5233584749,0.2880418516,0.1360740415,0.03409382085,-0.02856455307,-0.05756703881,-0.05827224144,-0.04490888485,-0.03087532373,-0.01929612394,-0.01137846971,-0.00634394078,-0.004247325577,-0.003757140208,-0.004410972204,-0.006409417324,-0.009140259258,-0.0109891651,-0.01072328902,-0.009226555216,-0.005890508391,-0.002598280474,-0.00081608024},
      {0.8082862897,0.5567979242,0.3351245925,0.1629772714,0.05132665722,-0.02049275298,-0.06123559077,-0.07396489624,-0.06185361218,-0.04565419777,-0.03034616819,-0.01870552076,-0.01111242646,-0.008175660862,-0.006998012789,-0.006138989981,-0.004996823667,-0.002332952358,0.0005401165678,0.002534396422,0.002336932916,0.0008703151262,-0.001685533274,-0.00503880986},
      {0.8235059449,0.5828111197,0.3745329603,0.1882958478,0.07224656875,-0.005562263973,-0.05027620143,-0.0681302733,-0.06561721362,-0.05060893774,-0.03552622072,-0.02312601336,-0.01536760556,-0.009828677299,-0.006524396794,-0.004815264544,-0.0034390674,-0.003599415865,-0.003220135723,-0.00083604376,0.003102231327,0.005622154342,0.007370654405,0.008864170885},
      {0.8345753239,0.6055271196,0.3998458286,0.2139477579,0.079297157,-0.002239011792,-0.0480321498,-0.06501300826,-0.06229901683,-0.05252507062,-0.0356886837,-0.02187318392,-0.01279869331,-0.006794671881,-0.003036557088,-0.0001032288286,0.001727363847,0.003081478762,0.003225126932,0.001460506671,-0.002133888378,-0.006405302353,-0.009385930059,-0.0102473865},
      {0.8426603961,0.6260247046,0.421228418,0.2426310677,0.09416888554,0.0109164019,-0.03914147007,-0.05951368922,-0.05828004998,-0.0514283553,-0.04408362357,-0.02999020542,-0.01988189108,-0.01351131762,-0.009232180547,-0.006548869631,-0.004576633704,-0.003512927306,-0.002179542262,-0.001432176235,-0.002420659119,-0.004068246706,-0.004458133136,-0.004251591796},
      {0.8478804802,0.6419685789,0.4336570801,0.2675675477,0.1197847189,0.02051232314,-0.03170348288,-0.05387291031,-0.05376916242,-0.04742743421,-0.04013489993,-0.03397071447,-0.02256422089,-0.01402041153,-0.008526924023,-0.003834496875,-0.000179112391,0.002721997227,0.004857385668,0.005588979975,0.005003163221,0.003245446059,0.0008286399904,-0.003573461114},
      {0.856095338,0.6596906504,0.448874285,0.2910628436,0.1481609388,0.03368089661,-0.02229958998,-0.04949040747,-0.05351778224,-0.04742837623,-0.03882860221,-0.03178252924,-0.02713121812,-0.01859511138,-0.01302777589,-0.008827294091,-0.004151108641,0.000138303031,0.002942179459,0.004801606658,0.005785488672,0.006502378601,0.006623515844,0.006506517262},
      {0.8599267274,0.669823517,0.4649838423,0.302720735,0.1650023472,0.05061492619,-0.01849791931,-0.0459670836,-0.0495484386,-0.04432245656,-0.03646655134,-0.02899977689,-0.02527697478,-0.02372507228,-0.01925009142,-0.01406361434,-0.008102561183,-0.003054094269,0.001722540902,0.005878310946,0.008428095734,0.008608474486,0.006818333614,0.006117080712},
      {0.8590733976,0.6722601675,0.4754018325,0.3095985062,0.1795183163,0.06662466193,-0.01763827655,-0.04705275309,-0.05224615788,-0.0480026262,-0.03744915761,-0.02730680314,-0.01952007511,-0.01380027785,-0.01160208845,-0.008493346656,-0.004129091974,-0.001813244149,0.0004885812831,0.001748339667,0.00221298933,0.000872704414,-0.0007224136537,-0.001484029673},
      {0.8646697337,0.6865705696,0.4960431881,0.320536206,0.1935678428,0.08387001627,-0.0008045211976,-0.04462363632,-0.05288828773,-0.05046021313,-0.04054686077,-0.02908478454,-0.02005887901,-0.01232038814,-0.008259046569,-0.007067453522,-0.009640684418,-0.00585597326,-0.00542454027,-0.005846674346,-0.00636673323,-0.006792611837,-0.007293221862,-0.008257736971},
      {0.8602697704,0.6842798864,0.5019036806,0.3232465126,0.2016301214,0.093827831,0.01187845856,-0.04519037617,-0.05287025818,-0.05162808591,-0.04457988536,-0.03410570128,-0.0245200691,-0.0185187149,-0.01462955794,-0.01520124143,-0.01815322777,-0.01974876812,-0.01592717402,-0.01494706555,-0.0140152971,-0.01294113258,-0.01192776819,-0.009955678769},
    },
    {
      {0.2596691032,0.06800604057,0.001838563154,-0.01287914755,-0.0136782757,-0.0169440761,-0.01151059496,-0.01362478176,0.003962822576,0.003890593533,0.001910279542,-0.004403150829,-0.001255516274,-0.0008542556468,-0.0004699902467,0.2036733038,0.003058433789,0.005879222473,-0.00633884329,-0.003419017263,0.005206562048,-0.0004947296463,0.005711880728,-0.007152538435},
      {0.4947192454,0.2069762271,0.07845861855,0.01715875793,-0.02177135815,-0.0399455235,-0.0425478245,-0.03277706174,-0.01331108144,0.0009695039278,0.004870170087,0.007061627166,0.009481328436,0.007165945838,0.003956103264,0.007629061816,0.0059389748,0.005067836668,0.000567355432,-0.002084156902,-0.003613092861,-0.001797422541,0.002603981145,-0.007443493684},
      {0.6211580946,0.3093307623,0.1333273085,0.04073061624,-0.007368792914,-0.03417811242,-0.04663939567,-0.04381583928,-0.02874498572,-0.01624650237,-0.009346424817,-0.002229445361,0.005610230552,0.008305941087,0.006849142496,0.004158476587,0.0015632917,0.0007174183853,0.0007323046541,0.0002551697002,-0.001416435134,-0.0007798928786,0.002573900903,0.001999986255},
      {0.687661837,0.3882436476,0.1994847913,0.07414901618,0.003502950037,-0.03230912597,-0.04806574873,-0.0484908562,-0.03920278421,-0.0295276682,-0.02217842522,-0.01832252644,-0.01435192943,-0.009940856504,-0.005830997149,-0.001329577503,0.002408740851,0.004000697884,0.003482175062,0.003253033881,0.004694261097,0.008849922279,0.01260448749,0.01338108397},
      {0.7345821885,0.4503877831,0.2378222817,0.1041826801,0.01437348852,-0.03555609287,-0.05443146207,-0.05410865059,-0.0399332456,-0.0255399707,-0.01548404112,-0.01012640515,-0.007602296621,-0.006622151351,-0.006386603422,-0.00559313851,-0.003946649169,-0.002387645229,-0.001422962229,0.002142681141,0.007562740581,0.01081473296,0.0104248988,0.007324475135},
      {0.7677822733,0.4990414697,0.2694736023,0.1267777746,0.03148757126,-0.02771839529,-0.0550686922,-0.05426889945,-0.03951081766,-0.02529528798,-0.0142695805,-0.007509541599,-0.003645956389,-0.00233815437,-0.002307914993,-0.002971933407,-0.004643010175,-0.006902747547,-0.008261495816,-0.007448013561,-0.005461234595,-0.001491714505,0.002132356738,0.004500331357},
      {0.7913809867,0.5332031346,0.3176447659,0.1536716511,0.04990254902,-0.0175312938,-0.05698343145,-0.06974869723,-0.05816010094,-0.04327320452,-0.02936858826,-0.018713485,-0.01126511878,-0.008150857603,-0.006479154989,-0.004996141542,-0.003187215441,-0.0001223774208,0.002669067191,0.004757173978,0.004953812142,0.004708435061,0.002845842863,-0.0002169192662},
      {0.8081450201,0.5633854422,0.3599612861,0.1791782694,0.06996931992,-0.003776484007,-0.046318973,-0.06371141054,-0.06030833786,-0.04488480697,-0.02965877804,-0.01734400716,-0.01047371398,-0.006112644462,-0.003301296797,-0.002011936349,-0.001072419985,-0.0009782029611,-0.0001628083895,0.001408936192,0.004541320674,0.006228646249,0.00731314593,0.008835649305},
      {0.820287583,0.5818693357,0.3780495163,0.1998221014,0.07248319348,-0.002225728663,-0.04378740694,-0.0589160549,-0.05596708359,-0.04688612474,-0.03079630613,-0.01788114929,-0.009489717795,-0.004302304375,-0.001833859898,7.118194693e-05,0.001091022528,0.00180764454,0.002277486499,0.0009659317003,-0.002284408813,-0.006238858361,-0.008714104649,-0.008569363796},
      {0.8295209778,0.604037311,0.3996041068,0.2296474568,0.08667232011,0.009659956809,-0.03616842998,-0.05437889274,-0.05299291033,-0.04777524493,-0.04228165509,-0.02935196059,-0.019436665,-0.01244426466,-0.007049480669,-0.003613060363,-0.001379821185,-0.0002274444325,0.001379186467,0.001983516645,0.0004031387153,-0.00202208732,-0.003049849675,-0.00387119183},
      {0.8371921426,0.621930649,0.4136828322,0.2524495536,0.112061718,0.01826772852,-0.02986033001,-0.04962217015,-0.04843759006,-0.04216325179,-0.0364767494,-0.03220139171,-0.02188324072,-0.01378347424,-0.00815542391,-0.003731204264,-0.0005128264271,0.002279637875,0.004589372539,0.005268957111,0.00456454847,0.002635625715,0.0012909811,-0.001805903709},
      {0.8459549947,0.6396290724,0.4278411994,0.2750190368,0.1404056232,0.03099249498,-0.01978574811,-0.04298085835,-0.0445219108,-0.03789173112,-0.03069930081,-0.02541436311,-0.02248261949,-0.01456285512,-0.009452584455,-0.00501865705,-0.0001609280073,0.004398870377,0.008065669352,0.01010558872,0.01098502011,0.01094411636,0.01035208379,0.008703044043},
      {0.8503052834,0.6506721326,0.4427625269,0.2849075278,0.1549444173,0.04712998706,-0.01680296405,-0.04075340668,-0.04240073298,-0.03761917918,-0.03074633023,-0.02491840978,-0.02216329744,-0.02118203283,-0.0165090775,-0.01093838347,-0.005020201746,-0.0006971833853,0.002862437119,0.006528739767,0.007894530818,0.006253055438,0.001756768094,-0.0009964749437},
      {0.8506786532,0.655499961,0.4548457288,0.2915338507,0.1664268569,0.06112071141,-0.01774460559,-0.04218414989,-0.04382926055,-0.03846982736,-0.02882109542,-0.020143089,-0.01477884315,-0.01210705991,-0.0109926914,-0.008108966955,-0.003059859691,0.000165459053,0.00350978187,0.005637209901,0.006902181386,0.00527894441,0.002751174684,-0.0001668075624},
      {0.856570889,0.6708509505,0.4745685559,0.3005965686,0.1786378354,0.07565141928,-0.002158601042,-0.0405115848,-0.04478902804,-0.04032909796,-0.03057225337,-0.02094551569,-0.01323864136,-0.007746034593,-0.005393832295,-0.005117336531,-0.008552319577,-0.004932959408,-0.005027090668,-0.005964118095,-0.006345425038,-0.006814673199,-0.006186294817,-0.005256073848},
      {0.8525984964,0.6696199255,0.480847894,0.303502916,0.1862323181,0.08214211779,0.008147167252,-0.0438700362,-0.04725742346,-0.04330455198,-0.03503214751,-0.02487539344,-0.01596759177,-0.009950840592,-0.007314288727,-0.008917467055,-0.01229960574,-0.01434812826,-0.01020116956,-0.008807872581,-0.007269701555,-0.004720071327,-0.002775355065,0.0001024554436},
    },
  },
  {
    {
      {0.3516064827,0.1061092722,0.01003698701,-0.01601184456,-0.02198362804,-0.02166438023,-0.0185404954,-0.0163856611,0.003448552454,0.005374376431,0.002857483383,-0.001606895834,-0.0003069902126,-0.001101535528,0.0006436175916,0.1271425867,0.00462888594,0.005342652399,-0.002519584673,-0.001322875022,0.003424103113,0.001803508434,0.005014341359,-0.01013096332},
      {0.5746696706,0.2846939829,0.1215526727,0.03355701679,-0.02049492469,-0.04846818405,-0.0549327354,-0.0441213654,-0.02284491221,-0.006414377831,0.002325204909,0.007826520746,0.01060862096,0.008636203083,0.006138483614,0.00747426832,0.006923635418,0.006929013888,0.003213028866,-0.0003169148402,-0.002898936554,-0.00316427372,-0.0007305883583,-0.007466404266},
      {0.7200425985,0.4159888338,0.2053575449,0.07783123676,0.004417333025,-0.03806515086,-0.05766015964,-0.05863512081,-0.04560028935,-0.03129076491,-0.02024485234,-0.009971317419,0.0002055004783,0.00582880735,0.007492035474,0.007857004882,0.006868291864,0.00549852618,0.00323344856,0.001791047353,0.00116186046,0.003099656919,0.005814864915,0.005347955236},
      {0.7500491058,0.4725255164,0.2662567234,0.1159713257,0.02240215719,-0.02907276169,-0.0546419245,-0.05999472773,-0.05227067589,-0.041895875,-0.0326678039,-0.02606304969,-0.01948209249,-0.01330333316,-0.007577225837,-0.002009930372,0.001918706302,0.00301055476,0.002025635233,0.001877739816,0.004210495587,0.00834930775,0.01144746663,0.01098911395},
      {0.8009231515,0.5413580653,0.3199011726,0.1605542669,0.04509190622,-0.02417258378,-0.05523677628,-0.06263371684,-0.0538789844,-0.041342568,-0.03018935853,-0.02232317573,-0.017139371,-0.01407961018,-0.01242148626,-0.01037347649,-0.00806088649,-0.005681091031,-0.002980716469,0.001588880702,0.0069709834,0.009540359004,0.009596512705,0.007500026245},
      {0.8218584005,0.5841137948,0.3512632273,0.1904029849,0.07080999845,-0.0106860943,-0.05350247963,-0.06184269303,-0.0533006374,-0.04093118188,-0.02877595468,-0.01992485833,-0.01347635798,-0.01036096558,-0.008953123249,-0.009634593845,-0.01089299394,-0.01238576556,-0.01284985086,-0.01191131776,-0.01044221826,-0.00857549676,-0.007660486506,-0.007551708995},
      {0.8366045132,0.6109036101,0.3936440387,0.2160532777,0.09147262022,0.003077050888,-0.05390090801,-0.07863930613,-0.07234529454,-0.05890252897,-0.04341873883,-0.03003735482,-0.02019569812,-0.01485882391,-0.01179311527,-0.01001674469,-0.008444164487,-0.006069005907,-0.003576578202,-0.00185251478,-0.002604159392,-0.004809968244,-0.008074392452,-0.01182301895},
      {0.8477660848,0.6294095565,0.4249202563,0.2351838659,0.1126068407,0.02374750536,-0.03438418138,-0.06516847573,-0.07244465738,-0.06067887841,-0.04579743359,-0.03143612615,-0.02118159201,-0.0132790817,-0.008074392832,-0.004970709865,-0.002293458006,-0.001838759114,-0.0007697636691,0.001286666543,0.00365435867,0.003753272702,0.002414018221,0.00108301556},
      {0.8552443686,0.6501572469,0.4528312228,0.2634625945,0.1222988561,0.03100848985,-0.02770898321,-0.05840595057,-0.06737371853,-0.06642579167,-0.05115708292,-0.03638556333,-0.02513657761,-0.01658017645,-0.01007754537,-0.004730891732,-0.001384929335,0.001499733277,0.002994494288,0.002308426932,0.0002367907881,-0.002972630374,-0.005581794993,-0.006575329658},
      {0.8615295156,0.6656807684,0.4722982655,0.2897865528,0.1352797521,0.04477443527,-0.01559334287,-0.04727954307,-0.05645646403,-0.05748794005,-0.05509965552,-0.04013858726,-0.02848778207,-0.01963473476,-0.01263244218,-0.008163180271,-0.005392494751,-0.003953046892,-0.003048501836,-0.002187589912,-0.00336950165,-0.005396760298,-0.005702648077,-0.006108413117},
      {0.8631632723,0.6769805438,0.4806497602,0.3153265705,0.1614454287,0.05564608838,-0.005027212779,-0.0376499531,-0.04646757273,-0.04893472571,-0.04721695068,-0.04431466797,-0.03008248105,-0.0184066224,-0.01083720028,-0.004849406851,-0.0008307213681,0.002562965047,0.004444187282,0.005067808319,0.003979732996,0.002477715449,0.0001164202579,-0.004399806549},
      {0.868606652,0.6884596327,0.4927812755,0.3356624272,0.1874834673,0.0660723021,0.004970335865,-0.03009249649,-0.04263853426,-0.04564052506,-0.04485064435,-0.04313319874,-0.04125506443,-0.03010105585,-0.01983818901,-0.0115423467,-0.00411330455,0.001844971144,0.004958558802,0.005551463741,0.004323807638,0.001948313288,-0.0008659500353,-0.002278343033},
      {0.8713746787,0.6956750752,0.5052169489,0.3454993724,0.2047578698,0.08384943269,0.008790595432,-0.02432655745,-0.03552643411,-0.03811873647,-0.03710207385,-0.03365473122,-0.03186808103,-0.03192221062,-0.02554882729,-0.01749269502,-0.00958632696,-0.003856360598,0.0008553433037,0.004630703891,0.006718608939,0.006759636263,0.004901066956,0.003427589813},
      {0.8711800837,0.6989339436,0.5169610657,0.3559762316,0.2236268442,0.1025931629,0.01019721631,-0.02483314478,-0.03692412609,-0.03986533209,-0.03570059159,-0.03107908154,-0.02657392329,-0.0230885503,-0.02149508975,-0.01699896804,-0.009867970354,-0.004831891642,6.538940982e-05,0.003389651224,0.004624757852,0.003768189864,0.001686367518,0.0005958018942},
      {0.8726206792,0.7051297777,0.5284053737,0.3596895178,0.2308140622,0.1166306521,0.02520198505,-0.02311558099,-0.0351532259,-0.0376939478,-0.03355213608,-0.02646214802,-0.02433886972,-0.02156333788,-0.02188964054,-0.02351925632,-0.0248834181,-0.01778280916,-0.01309184413,-0.00941865849,-0.006569923933,-0.002969014599,-0.001288717991,-0.0008721245661},
      {0.870686315,0.7036949585,0.5356819183,0.3644336318,0.2397046696,0.1299054598,0.04040561487,-0.0238110784,-0.03464663401,-0.03772611854,-0.03585738286,-0.03002707464,-0.02353654623,-0.02138076612,-0.0194070949,-0.02167890904,-0.02624800037,-0.0295420107,-0.02417929636,-0.02242639674,-0.02006036339,-0.01738695372,-0.01401078401,-0.0100873382},
    },
    {
      {0.3409755157,0.1007079833,0.007986962581,-0.01581998977,-0.02025589578,-0.02131746229,-0.01751686148,-0.01532570684,0.003431219597,0.004704161919,0.002287597465,-0.002378029608,0.0001440239106,0.000559741716,0.001925172812,0.1248437064,0.004750439799,0.005620921876,-0.002426381415,-0.002175759462,0.003899097051,0.001402587797,0.004931462461,-0.008799327202},
      {0.5710148848,0.2765042592,0.1168579224,0.03178198947,-0.02101822092,-0.04799690853,-0.05376085512,-0.04242136023,-0.02124474071,-0.004720936134,0.003803369069,0.008180704787,0.01054930752,0.008353540038,0.004857455707,0.006779692657,0.00678261117,0.007151582219,0.003089824472,9.327771406e-05,-0.002510075198,-0.00245085509,0.0003339423114,-0.006848040139},
      {0.6992998924,0.3974114695,0.192210261,0.07085118743,0.002120199408,-0.03768659597,-0.05596410058,-0.05597354391,-0.04188278765,-0.02760205769,-0.01704851192,-0.007481095108,0.001608934655,0.006749920583,0.008223272513,0.008202875193,0.006399131175,0.004346520884,0.002152106259,0.001296671342,0.001420358716,0.004220630306,0.007923571025,0.00742520476},
      {0.741708704,0.4618122858,0.2603968521,0.1112077082,0.02030713007,-0.02882718768,-0.05289802195,-0.05720772128,-0.04932570065,-0.0392648519,-0.0305531827,-0.02472047528,-0.01897338564,-0.01311425941,-0.007201607498,-0.002012572576,0.001608262466,0.002974331805,0.002737277529,0.003037728566,0.005174924596,0.009745920852,0.01307972542,0.01338585588},
      {0.785641484,0.5232245672,0.3064032366,0.1524096987,0.03991110574,-0.02651904782,-0.05524123745,-0.06137960922,-0.05175258474,-0.03940199857,-0.029091819,-0.02159605399,-0.01686762543,-0.01409547897,-0.01216650978,-0.009935264817,-0.007571410092,-0.004472291075,-0.001389078681,0.002817281462,0.007471046629,0.009860856055,0.009745097918,0.007947017295},
      {0.8075150693,0.5636798103,0.3336258468,0.1793519025,0.06534094346,-0.01263313714,-0.05333251835,-0.05973087582,-0.04958069648,-0.03678424452,-0.02504141828,-0.01686549486,-0.0110845711,-0.008131565958,-0.007125012375,-0.008068465401,-0.009523175104,-0.0114845628,-0.01269679375,-0.01146193988,-0.009388003256,-0.005622462344,-0.003048795467,-0.001592304324},
      {0.8241562726,0.5925771411,0.3782776957,0.2069091088,0.08871269687,0.004201741932,-0.05067445565,-0.07411863144,-0.06677224566,-0.05355414347,-0.03888880475,-0.02651163715,-0.01718878384,-0.01251295229,-0.01021844658,-0.008837233028,-0.0076021511,-0.005351290478,-0.00282175117,-0.0009363625402,-0.001325830484,-0.002353266374,-0.004547251804,-0.00755660887},
      {0.8359546985,0.6147678444,0.4112746817,0.2248338835,0.1072794825,0.02148121416,-0.03400322854,-0.06263287226,-0.06770022186,-0.05445567515,-0.03922466582,-0.02514216138,-0.01592817805,-0.009316993901,-0.004984292054,-0.002711984397,-0.001252098551,-0.001382893601,-0.0005469663568,0.0005934774724,0.002627508939,0.002859921345,0.002081743458,0.002336530335},
      {0.844914858,0.6328618495,0.4351748927,0.2514940234,0.1164770139,0.03094540738,-0.02374621104,-0.05186641852,-0.05991251411,-0.05897563898,-0.04375599235,-0.02957260352,-0.01901984875,-0.01152224391,-0.006474431694,-0.002515362709,-0.0005536355431,0.000606195629,0.0007094948193,-0.001505975828,-0.00487043837,-0.009093211407,-0.01166890879,-0.01092451453},
      {0.8515352281,0.6495000995,0.4548965905,0.2787585139,0.1284596429,0.04326607257,-0.01304544952,-0.04177642533,-0.0491311157,-0.05010519105,-0.04879057467,-0.03527140559,-0.02481414435,-0.01735813958,-0.01142809168,-0.007338575101,-0.00454520491,-0.003294808434,-0.002349386331,-0.001621883753,-0.003717630774,-0.007445616093,-0.009303357391,-0.01120874131},
      {0.8548335037,0.6613361926,0.4643181508,0.3007364784,0.1525409113,0.05182129642,-0.004195062193,-0.03332725532,-0.04043861962,-0.04226630715,-0.041889509,-0.04090305372,-0.02907383666,-0.01903865996,-0.01221841367,-0.006075292045,-0.001216607282,0.003149722692,0.00661835658,0.007864581129,0.006751716501,0.003928735443,0.001866330318,-0.002527038356},
      {0.8619047218,0.6751162349,0.4778905002,0.3219882631,0.1799553063,0.0627873665,0.005859293818,-0.0257338827,-0.03605428808,-0.03811438607,-0.03786685832,-0.03756601054,-0.03698077924,-0.02692171878,-0.01764092125,-0.009903555993,-0.002170960826,0.00454979639,0.009517330011,0.01227043445,0.01275825642,0.01143222538,0.009819851081,0.007171364658},
      {0.864422522,0.6816028184,0.4877104771,0.3298532918,0.1945817671,0.07954113828,0.009825434004,-0.01970944875,-0.02782899649,-0.02908467378,-0.02737865794,-0.02497651654,-0.02483736803,-0.02614370487,-0.02175782236,-0.01576606472,-0.009417165897,-0.004800884033,-0.001123187388,0.002396771122,0.003991549266,0.003317549777,0.0002570307125,-0.001414469254},
      {0.8639260447,0.684770049,0.4991557475,0.3395113196,0.2102186884,0.09626486045,0.008852544037,-0.02195581916,-0.03092516214,-0.03269467105,-0.02913346549,-0.02546753944,-0.02332015568,-0.02226819108,-0.02108982453,-0.01732325316,-0.009813167844,-0.004190760396,0.001638825961,0.005767377494,0.008367488921,0.008196896279,0.006458940027,0.005645530548},
      {0.8664416019,0.6936513025,0.5121669944,0.3444042327,0.2178567165,0.1081212932,0.02167281301,-0.02248230945,-0.0315707091,-0.03262742281,-0.02831616331,-0.02249276135,-0.01984207768,-0.01784582746,-0.01817066663,-0.0195297592,-0.02237155713,-0.01488476573,-0.0106474523,-0.007808943291,-0.006158032052,-0.004708440557,-0.004827029057,-0.005447479367},
      {0.8639448046,0.6907636668,0.5175199805,0.3477011644,0.2255688477,0.1172848425,0.03481321613,-0.02506683266,-0.03304427147,-0.03430593818,-0.03170382855,-0.02581396616,-0.01987000483,-0.01680987766,-0.01540512618,-0.01772685693,-0.02183707801,-0.02361732948,-0.01752267489,-0.01517828441,-0.01249847893,-0.009081441246,-0.005852789834,-0.002275496286},
    },
    {
      {0.3261180732,0.09323573371,0.005405210787,-0.01583294359,-0.01883986883,-0.02047499341,-0.01591799321,-0.01409407366,0.003778862654,0.004816125999,0.002027688755,-0.002548498759,-0.0002738891934,0.0005751525988,0.001709448,0.1212687215,0.00414141105,0.005596432604,-0.002856923887,-0.001625319528,0.005704829813,0.001263666229,0.005555465738,-0.005833751621},
      {0.5656073481,0.2654184856,0.110580678,0.02952950017,-0.02126221422,-0.04669194314,-0.05122637267,-0.03966342977,-0.01915039434,-0.002786028391,0.005279678274,0.009115285732,0.01143089887,0.008736262234,0.004470035891,0.006931920177,0.006679097154,0.006683224674,0.002779321009,0.0004881055039,-0.001681594553,-0.001243132083,0.001389958005,-0.005728886567},
      {0.6750570439,0.3757757682,0.1770268644,0.06334458483,0.0004302002453,-0.03613844197,-0.05319420145,-0.05201773974,-0.03704087468,-0.02292008332,-0.0126311306,-0.003583091871,0.004205316606,0.008037190745,0.008628702397,0.007865473557,0.00553965916,0.002938874838,0.0005247685833,-0.0003109315343,-0.0003843535234,0.001706293988,0.005203547918,0.004998569391},
      {0.7306363319,0.4464302443,0.2514126256,0.1046359716,0.01754875837,-0.02813327763,-0.05036279446,-0.05403098072,-0.04561665316,-0.03517041363,-0.02637794372,-0.02097567378,-0.01566424459,-0.009926704495,-0.004126317691,0.0008374777401,0.003904435608,0.00445202984,0.004108794188,0.004277773014,0.004930070099,0.007928707116,0.01104913997,0.0125062582},
      {0.7672847617,0.5012784694,0.2899090004,0.1428230249,0.03426498037,-0.0287116893,-0.05409163033,-0.05786803318,-0.046783095,-0.03398920161,-0.02380569404,-0.01645309039,-0.01270858506,-0.01105605508,-0.009827242516,-0.008138568165,-0.00626214369,-0.003673676343,-0.002060358387,0.0006090753827,0.004661222276,0.006945997247,0.007073710431,0.004866707985},
      {0.7915036763,0.5416572643,0.3150497184,0.1682876769,0.05992991544,-0.01489906831,-0.05363401443,-0.05837593478,-0.0466953918,-0.03367826047,-0.02247816476,-0.01500604823,-0.009927648904,-0.007213833727,-0.006532596326,-0.007347216327,-0.008577447726,-0.01022067138,-0.0112786909,-0.009657732073,-0.007001793029,-0.003056012321,-0.0006046328852,0.0003716461376},
      {0.8106861721,0.5721435071,0.3604400222,0.1952227269,0.08387240408,0.004329279064,-0.04682927976,-0.06728197926,-0.05799685376,-0.04436182986,-0.03082217663,-0.02015640592,-0.01255524435,-0.009141181835,-0.007444112423,-0.006007126516,-0.004669150287,-0.002329348385,-0.0002759043757,0.0008655401831,-0.0001036519749,-0.0005778690066,-0.001624820804,-0.003850774443},
      {0.8227729805,0.5974258878,0.395669033,0.2136851294,0.1026884052,0.02126257245,-0.03077390876,-0.05740794597,-0.06122202825,-0.04759236026,-0.03330540956,-0.02104663437,-0.01349425919,-0.008335682983,-0.004685034963,-0.002490661713,-0.0006008893834,0.0001105470718,0.001642328934,0.002886659219,0.004786187766,0.005097586828,0.004048740904,0.002420983055},
      {0.8335579973,0.6133773817,0.4144393552,0.2357956227,0.1064930377,0.0270953701,-0.02310418027,-0.04823093446,-0.05425134588,-0.05228793904,-0.037329698,-0.02380468406,-0.01383736001,-0.00699928033,-0.003422132868,-0.001065974976,-0.0003617097815,-0.0003890416179,-0.0005511170847,-0.002154006517,-0.005096019181,-0.008478126307,-0.01055968891,-0.0106700126},
      {0.8401989435,0.6309941914,0.4348225593,0.2647667294,0.1182168463,0.03867098009,-0.0134875973,-0.03980633643,-0.04589862361,-0.04655512748,-0.04514496966,-0.0316307435,-0.02067126939,-0.01275324007,-0.006565521971,-0.003011850622,-0.00142803835,-0.001358603302,-0.001287367515,-0.001765049023,-0.004771202308,-0.008461715061,-0.009961178601,-0.01124536633},
      {0.8450167808,0.6432208621,0.4451612212,0.2835210998,0.1407948922,0.04471529911,-0.006630483608,-0.03185807032,-0.03656863788,-0.03686415457,-0.03645279917,-0.03678312541,-0.02647241533,-0.01727120735,-0.01066135629,-0.004645971092,0.000183719399,0.004175909326,0.007233313701,0.007736729174,0.006273932878,0.003111961223,0.0008522079577,-0.004005181231},
      {0.8532925077,0.6589835946,0.4600629481,0.3062253211,0.1709877784,0.05843053474,0.006778717915,-0.02067223522,-0.0279302319,-0.02859044455,-0.02876218462,-0.02951056478,-0.03020026075,-0.02106264467,-0.0128662838,-0.005748116014,0.001720234914,0.008174634258,0.01300836897,0.01554303193,0.01655677658,0.01610677677,0.01515884707,0.01308723996},
      {0.8560889977,0.6658542383,0.4685910407,0.3126618779,0.1822728903,0.07231880052,0.006742560611,-0.01884105047,-0.02382494761,-0.02379697729,-0.02202409519,-0.0200198903,-0.02039646101,-0.02190317784,-0.01796783797,-0.01183130357,-0.00566729156,-0.001425380732,0.001598909053,0.005236272661,0.007096765052,0.006143294117,0.002212385158,-0.0001146220646},
      {0.8560605415,0.6701307517,0.4807258483,0.3225175818,0.1963111019,0.08897617044,0.006398053366,-0.01986687948,-0.02555506964,-0.02576045756,-0.02253919853,-0.01942807909,-0.01858165455,-0.01948578448,-0.01900074666,-0.01543991286,-0.008186614415,-0.002993478418,0.002458425368,0.006009668249,0.008734284014,0.007989659734,0.006050117735,0.00457657299},
      {0.8605256262,0.6825240379,0.4968266134,0.3304043856,0.2072366244,0.1019285979,0.02081410115,-0.01933731864,-0.02535872206,-0.02470280724,-0.01995639611,-0.0156128687,-0.01283513241,-0.01213743956,-0.01346240953,-0.01506222404,-0.01873590812,-0.01150970457,-0.007730314208,-0.004960657972,-0.002391724628,-0.0007087784752,0.0002169314725,0.0007968169797},
      {0.8578492358,0.6791978795,0.5007627377,0.3323527345,0.2137557207,0.1081548213,0.03274669463,-0.02206283329,-0.02636298526,-0.02509450906,-0.02105313744,-0.01548855757,-0.01076998648,-0.007838332025,-0.00818328321,-0.01184973251,-0.01733147611,-0.02021670304,-0.01427311355,-0.01126288431,-0.008317676831,-0.004922945001,-0.001370903723,0.002945091082},
    },
  },
  {
    {
      {0.4171774492,0.1341823291,0.0152943284,-0.01880830303,-0.02652494947,-0.02586534727,-0.02284998535,-0.01674573156,0.002978743016,0.006759439893,0.003701460906,0.0005840184205,0.001725969346,0.0007372188527,0.001960304764,0.06178324313,0.003840202713,0.004791396689,0.0002130815541,0.000261259772,0.003812644646,0.002144338748,0.00321792745,-0.009511208773},
      {0.6386931044,0.3439801191,0.1570796789,0.04735162561,-0.02007604165,-0.05581594997,-0.06467739073,-0.05283332785,-0.03046651932,-0.01116084658,0.002018360351,0.008757567101,0.01142029008,0.01005714132,0.007669548348,0.008557722491,0.00904082036,0.01025072835,0.007833367067,0.004687396081,0.001502936288,-6.397243348e-05,1.587569831e-05,-0.00552296425},
      {0.7644157094,0.480586171,0.2535726403,0.1055702741,0.01614397948,-0.03776208489,-0.06303171804,-0.06650832899,-0.05393775721,-0.0379845894,-0.0236089617,-0.01136371198,-0.001354677924,0.004842693385,0.008351008319,0.01013975925,0.009264634106,0.006466753575,0.002832947958,0.001577294295,0.002304740242,0.005411809759,0.008009680851,0.007816552462},
      {0.7934272496,0.5336348895,0.3236952174,0.1530814175,0.04166307615,-0.02215485592,-0.05619343016,-0.06643152832,-0.06074285827,-0.05071664193,-0.04059028722,-0.03228675209,-0.02472996082,-0.01786138852,-0.01129550606,-0.005404473452,-0.001396528974,0.0003229728608,0.0009955393258,0.002723518067,0.005516551491,0.009128649295,0.01164086059,0.01181352709},
      {0.8265116387,0.5903624572,0.3748533137,0.2050241532,0.0704110312,-0.01372264561,-0.0540292592,-0.06792208199,-0.06301148512,-0.05224421702,-0.04101139028,-0.03123783239,-0.02452885407,-0.02041744821,-0.0179468602,-0.01457823834,-0.01137899585,-0.007735985083,-0.003543746551,0.001484498436,0.005964005927,0.008773651079,0.009565687785,0.008203080881},
      {0.8400878752,0.6253071906,0.4015198775,0.2397815429,0.1082103848,0.009431340423,-0.0476360958,-0.06440731895,-0.06154192489,-0.05236666425,-0.04107801278,-0.0313609688,-0.02265238402,-0.01655045299,-0.0130932361,-0.01319626804,-0.01391376664,-0.01493822712,-0.01506022929,-0.01389864852,-0.01227026205,-0.01046560556,-0.009912505171,-0.01019164634},
      {0.8514355877,0.6480673918,0.4424331122,0.2677805957,0.1371726954,0.03626879302,-0.03631852369,-0.07309421925,-0.07281362797,-0.06384633374,-0.05109940273,-0.03930966397,-0.02959620049,-0.02331444445,-0.01855412213,-0.01546674472,-0.01363665434,-0.01212008307,-0.0109231909,-0.01030975654,-0.01185087394,-0.01397551806,-0.01554809074,-0.01720316709},
      {0.8583229984,0.6617400508,0.4660100011,0.2779286711,0.1549401952,0.0575561578,-0.01330483135,-0.05818918868,-0.07665933485,-0.0689694548,-0.05600535779,-0.04162024411,-0.02992850897,-0.01973258023,-0.01214526543,-0.006835859742,-0.002851440007,-0.00140362605,0.0002808679902,0.00104675669,0.001333634606,-0.0009889793524,-0.004590017491,-0.007140987106},
      {0.8651702929,0.6781929142,0.4925610699,0.307966741,0.1674805172,0.0717557376,0.003319583333,-0.04031374771,-0.06192150165,-0.07152847656,-0.05984349424,-0.04635836501,-0.03475479984,-0.02452247197,-0.01707966411,-0.01125954088,-0.008184148735,-0.005666577978,-0.003571324006,-0.003431923997,-0.004691324211,-0.006938626336,-0.009028263281,-0.009836300633},
      {0.8712036991,0.6918626943,0.5125054398,0.3350426651,0.179521571,0.08699242379,0.01834452214,-0.02500270236,-0.04722053662,-0.05985584064,-0.06626626591,-0.05230192532,-0.03943237284,-0.02800663559,-0.01800229341,-0.01131779103,-0.006250159074,-0.003592018576,-0.00284147591,-0.002245071584,-0.004321069678,-0.007785469643,-0.00916119221,-0.0105378847},
      {0.8708876794,0.6975472417,0.5155754257,0.3559721138,0.2033245429,0.09649469617,0.03182155148,-0.008874539753,-0.02700517383,-0.04110201512,-0.04901618311,-0.0540839886,-0.04024433184,-0.02733813781,-0.01743256451,-0.009510825305,-0.003841301472,0.0004577144001,0.002124131666,0.0021494504,-0.0002214377016,-0.002570603867,-0.004658140737,-0.008291938251},
      {0.874485038,0.7046636193,0.5273955699,0.3757412617,0.2306173082,0.1068084323,0.04466885796,0.003719329257,-0.01748274694,-0.0311180955,-0.04113872109,-0.04778634853,-0.05139801278,-0.0393962366,-0.02523636287,-0.0127931918,-0.001308374192,0.00726110103,0.01240817251,0.01368444532,0.01220729154,0.00843873034,0.004154051875,0.001561315367},
      {0.8764298396,0.7092191951,0.5340914343,0.3820108454,0.2455583003,0.1241274279,0.04743598094,0.01078387201,-0.007057499251,-0.01880602388,-0.0285677899,-0.03466557446,-0.04112010144,-0.0473945969,-0.04224205094,-0.03269613851,-0.02251921992,-0.01427435423,-0.00809090066,-0.003033825241,0.0005375665365,0.001837008297,8.959945205e-06,-0.002509823603},
      {0.8753420662,0.7104450559,0.5424931962,0.3903513493,0.2610257329,0.1392439557,0.04321002995,0.007838127248,-0.007957606667,-0.01792319348,-0.02244211204,-0.02665289871,-0.03027174867,-0.03296591837,-0.0343755363,-0.02950165492,-0.01929641404,-0.01074007523,-0.002839887926,0.003250468998,0.00590864579,0.005510950455,0.003195147737,0.0002728135293},
      {0.8763206601,0.7146311853,0.5489229281,0.3904591761,0.2636760082,0.1496651988,0.05558035911,0.006679355583,-0.006176771865,-0.01299144692,-0.01536389113,-0.01526268998,-0.02035026795,-0.02349681899,-0.02849634973,-0.03424336257,-0.0369101855,-0.02842699433,-0.02176896135,-0.01565397855,-0.01115866065,-0.00613470619,-0.002588278612,-0.0005345818893},
      {0.8764484743,0.7135190533,0.5579544962,0.4008488575,0.2765556709,0.1675295761,0.07702247656,0.009152667418,-0.001594581848,-0.007798966071,-0.01234103743,-0.01410119874,-0.01526116661,-0.02070010666,-0.02517688309,-0.03317998446,-0.04131945351,-0.04574392182,-0.0367479365,-0.03046892491,-0.0236139161,-0.01822295267,-0.01310315977,-0.008939021104},
    },
    {
      {0.4028569755,0.1264351127,0.01224828744,-0.01868948113,-0.024577297,-0.02448447355,-0.02134305572,-0.01582168255,0.002756064842,0.005657798209,0.002583847801,5.753781573e-06,0.002327164402,0.002345486105,0.00360265845,0.06098623124,0.004418577121,0.005362081629,0.0002293448779,0.0001273718367,0.004317001047,0.001567443273,0.002931971144,-0.007862274923},
      {0.6339642535,0.3331281245,0.1504437983,0.04440663894,-0.02132001626,-0.05536677704,-0.06308807218,-0.05089606335,-0.02871607451,-0.0095048537,0.003360579949,0.009855213111,0.01241064392,0.01067191268,0.007340573248,0.008177122043,0.008213132982,0.008768371637,0.006042184817,0.003755278976,0.0007752604391,-0.000975787968,-0.000879239366,-0.005459500412},
      {0.7452898393,0.4605455559,0.2379682424,0.0971885678,0.0135427456,-0.0371697025,-0.06135115741,-0.06391808747,-0.05044279253,-0.03426939401,-0.0204326306,-0.00893268688,0.0001893291225,0.005936471859,0.008959664271,0.01053792601,0.009154615276,0.006231604018,0.002063380502,0.0008149087129,0.001979448601,0.005220635675,0.008209442438,0.008053552807},
      {0.7829857308,0.5197384449,0.3141105237,0.1454082784,0.03771230003,-0.02298359989,-0.05477309149,-0.06362230804,-0.05738506495,-0.04686815826,-0.03678304636,-0.02902037077,-0.0220126877,-0.01520836108,-0.008346254248,-0.002602568889,0.0005424177552,0.001501654838,0.002053498759,0.003764368306,0.00612438367,0.009814091354,0.01254443963,0.01309255526},
      {0.8138716493,0.5728346276,0.3605651223,0.1956878232,0.0647978185,-0.01597615961,-0.05353290001,-0.06584516767,-0.05979128465,-0.04829223804,-0.03693549491,-0.02699549805,-0.0203449889,-0.01659997203,-0.01416636061,-0.01137295477,-0.008690239128,-0.005480962844,-0.00263332507,0.0008613739936,0.00497135449,0.007461279601,0.007637741979,0.005772887477},
      {0.8286693456,0.6069024921,0.384258115,0.2281579889,0.1016639605,0.006867116062,-0.04758466314,-0.062019194,-0.05749907402,-0.04780566466,-0.03702320415,-0.02818098748,-0.02059712904,-0.01482704118,-0.01162161971,-0.01136776954,-0.01118558699,-0.01162885042,-0.01213655476,-0.01166614789,-0.01062556436,-0.008513970358,-0.007224224986,-0.007419196815},
      {0.8412499007,0.6306812899,0.4245071351,0.2538250589,0.1285215428,0.03166877669,-0.03727930466,-0.07112892187,-0.06856748271,-0.05891251791,-0.0462124251,-0.03459957913,-0.02494374136,-0.01863403246,-0.01462112863,-0.01214930247,-0.0105123854,-0.008684648238,-0.007241909716,-0.006329154441,-0.007085819264,-0.007852903891,-0.008327223001,-0.009074108556},
      {0.8488736909,0.6489632645,0.4516914259,0.2666772812,0.1480329483,0.05336731692,-0.01478209732,-0.05666453594,-0.07188441081,-0.06233080629,-0.04885718983,-0.03497696414,-0.02428864859,-0.01516193836,-0.008301788542,-0.003463967374,0.0002118359008,0.002023383775,0.00436780127,0.005149665845,0.005457710812,0.002913258236,-0.0009388927079,-0.004262911101},
      {0.8571162627,0.6640895377,0.4753815104,0.2939189298,0.1581617761,0.06725372872,0.00229286261,-0.03770590504,-0.05649323011,-0.06333722174,-0.04967460498,-0.03528216872,-0.02311402088,-0.01351990826,-0.007661166435,-0.004049997044,-0.003398708173,-0.004303228389,-0.004926608676,-0.006755399857,-0.009343012726,-0.01227100815,-0.01469666951,-0.01544622606},
      {0.8621072593,0.6779964839,0.4955661645,0.3219852577,0.1685348922,0.08085739057,0.01565343492,-0.02517910325,-0.04485287552,-0.05609890451,-0.06149203298,-0.04823556695,-0.03625219634,-0.02608768749,-0.01711644801,-0.0111147127,-0.006949129928,-0.004974186872,-0.004573967901,-0.005494854828,-0.009192559356,-0.01415118108,-0.01693003597,-0.01977027234},
      {0.8640987652,0.6857968026,0.5023618438,0.3411181535,0.1917001707,0.08836770242,0.02766955613,-0.009628476551,-0.02527082834,-0.03630770076,-0.04320747645,-0.04827640349,-0.03668145076,-0.025125776,-0.01635759882,-0.008496054056,-0.002579230555,0.002120570959,0.004344144558,0.004551114151,0.001847145188,-0.002197282323,-0.00588477637,-0.01171514646},
      {0.8671845595,0.6921522213,0.5118819919,0.3587244949,0.2184824073,0.0981407949,0.04078857452,0.003595818282,-0.01445735057,-0.02609456813,-0.03542401854,-0.04198713642,-0.04653810278,-0.03541030149,-0.02299800892,-0.01216493548,-0.001879032088,0.005789858062,0.0106411144,0.01199388142,0.01119781835,0.008552225351,0.005897703704,0.003701553013},
      {0.8724888271,0.7005425115,0.5213252818,0.3688294405,0.2353115062,0.1185011768,0.0457335215,0.01199006464,-0.002942828032,-0.01318300691,-0.02182920182,-0.02793527949,-0.03495498393,-0.04063097331,-0.03580098685,-0.02679571996,-0.0175936599,-0.01097684301,-0.006240949111,-0.001054294134,0.002203531127,0.002426552515,0.001011038038,1.914645607e-05},
      {0.8700361314,0.700383143,0.529337413,0.3763519024,0.2469138141,0.1305036117,0.03832924586,0.00691944063,-0.00558638841,-0.01391366253,-0.01820320979,-0.02199277506,-0.02596525879,-0.02991709129,-0.0315397708,-0.02787554418,-0.01810902858,-0.009804670219,-0.002418872748,0.00290368096,0.005366383677,0.005015357166,0.00251730539,-0.0001908207439},
      {0.8724347554,0.708352718,0.5389663512,0.3806921525,0.2543073926,0.1431712195,0.05395644761,0.008697951025,-0.002072411799,-0.007797995456,-0.01001667309,-0.01163109958,-0.01646167536,-0.02093841318,-0.02604752688,-0.03084835835,-0.03541512418,-0.0266155415,-0.01968316319,-0.01399612928,-0.009544503731,-0.005832006938,-0.003883376656,-0.002821724128},
      {0.8704257703,0.702599813,0.5427189132,0.3861538511,0.2626304246,0.1536766653,0.07020937536,0.007084746956,-0.0009599320164,-0.005346489391,-0.008512905845,-0.00972945429,-0.01137448135,-0.01589847427,-0.0204208633,-0.02792166812,-0.03438736155,-0.03577062044,-0.02600148417,-0.01931032304,-0.01217906195,-0.005510617179,0.0004350385861,0.005573195735},
    },
    {
      {0.3833926014,0.1162816172,0.009175905864,-0.01801874555,-0.02235655551,-0.02286934588,-0.01966616894,-0.01432624039,0.003130422706,0.005734231495,0.00254879655,-0.0001303379039,0.002122204658,0.002643519912,0.003442397776,0.05831052033,0.003415688344,0.005581884505,0.0005419421422,0.0001936494522,0.005104737617,0.0009744705845,0.002367674167,-0.006484878033},
      {0.6267271363,0.3180937602,0.1415354202,0.04072103037,-0.02214599499,-0.05370539402,-0.05988056551,-0.04707812514,-0.02483392229,-0.005706539916,0.006372300093,0.0119027216,0.01377567886,0.01087871973,0.005901344083,0.006478306112,0.00637290492,0.007111906519,0.004592010637,0.002763625676,-8.306494353e-05,-0.001860075071,-0.001885994533,-0.006153975166},
      {0.7224378316,0.4357459235,0.2178074301,0.08586884352,0.009670288803,-0.03644544642,-0.05818254486,-0.05922732166,-0.04496617567,-0.0293274815,-0.01652662727,-0.00576040102,0.002153868474,0.007443713432,0.009694515757,0.01059379207,0.008401278081,0.005495432426,0.001739044949,0.0007869156972,0.001571467187,0.004232738537,0.007748685497,0.008009197789},
      {0.7698997066,0.5019679044,0.3018695774,0.136008112,0.0330722597,-0.02386700247,-0.05364925161,-0.06166867127,-0.05501701451,-0.04398497424,-0.03355922968,-0.02545679154,-0.01793470086,-0.0107942106,-0.003866002873,0.001562420293,0.003924612082,0.003963601377,0.003627030484,0.003626156826,0.003930553993,0.006078550987,0.007755466227,0.008667654291},
      {0.7988945344,0.5520451288,0.3432397968,0.1845988532,0.05881994853,-0.01710935115,-0.05093109949,-0.06124805833,-0.05450693867,-0.04379041028,-0.0338214756,-0.02501673412,-0.01935698028,-0.01598186492,-0.01339683392,-0.0108916929,-0.008618723067,-0.00558749803,-0.003321703809,-0.001348839029,0.00155903262,0.00258661135,0.002080069504,0.0004273013789},
      {0.8164226114,0.5868801597,0.3650646053,0.2141833945,0.092384279,0.001490154158,-0.04919785014,-0.06007036589,-0.05283560012,-0.04202509656,-0.03124963791,-0.02285348362,-0.01608925441,-0.01086748558,-0.00785961007,-0.007492126024,-0.007732882394,-0.008822463481,-0.01012962117,-0.009828581401,-0.009279412535,-0.007087764998,-0.005865777865,-0.006029113307},
      {0.8303459165,0.612818347,0.4068690577,0.2410902441,0.1215003076,0.02895570001,-0.03610388498,-0.06671155951,-0.0615191791,-0.05114242114,-0.03907753118,-0.02866269423,-0.02065782135,-0.0162409191,-0.01393132196,-0.0122900714,-0.01077733818,-0.008757700581,-0.00741830924,-0.006738242848,-0.007550991833,-0.007320097889,-0.007035790429,-0.006635011718},
      {0.8389578253,0.6346409684,0.4355894417,0.2530028118,0.1392696531,0.0479992956,-0.01672338702,-0.05583968622,-0.06828468157,-0.05696691188,-0.04281094786,-0.02931958107,-0.01999024229,-0.01222759049,-0.006176723063,-0.001784698148,0.002619967294,0.005821560589,0.009394815503,0.01075578272,0.01108147586,0.008437818655,0.004135380519,0.000204222873},
      {0.8483050807,0.6480846165,0.4554825964,0.2769509866,0.1455335798,0.06000824059,-0.0003444983151,-0.0362736825,-0.05214978462,-0.05672987741,-0.04188598751,-0.02718303567,-0.01539898433,-0.007036430401,-0.001929916753,0.001088867343,0.00126582099,-0.0003812925045,-0.001683156433,-0.003672918469,-0.006894101846,-0.01010720808,-0.0126810398,-0.01330067703},
      {0.8531758925,0.6633417076,0.4770364651,0.3074554688,0.1572494169,0.07510302248,0.0140773263,-0.02400106229,-0.04141558927,-0.05167928969,-0.05620322602,-0.04266806149,-0.03008453531,-0.01984772493,-0.01080978031,-0.004719246347,-0.000836897973,0.000784112185,0.001282440068,0.0004781868873,-0.002722280618,-0.007048141475,-0.009772035917,-0.01245510484},
      {0.8566285458,0.6719932286,0.4865962848,0.3244143562,0.1786117912,0.07921827131,0.02322532068,-0.01015278648,-0.02299737778,-0.03105333377,-0.03698381887,-0.0417147413,-0.03072610959,-0.01989828574,-0.01167661323,-0.004778315313,0.0003703667696,0.004115775348,0.00614342876,0.005855374427,0.003357555435,-0.0005456043716,-0.00465556109,-0.01106511083},
      {0.8610336256,0.6812354399,0.498702228,0.344753626,0.2092368892,0.09251299826,0.03929319479,0.005480735047,-0.009950810318,-0.01983821693,-0.02864900671,-0.03585842898,-0.0414888092,-0.03160687546,-0.02132038623,-0.01277374829,-0.004532601013,0.002100956075,0.007353269177,0.01026370265,0.01197976774,0.01180782766,0.01066994764,0.009677986704},
      {0.8670172642,0.689928498,0.5067601556,0.3536283285,0.2225418437,0.1102078134,0.04194020624,0.01257203192,0.001499683644,-0.006485254844,-0.01356987882,-0.01902229375,-0.02555752923,-0.03084322396,-0.02637701396,-0.018561212,-0.01034593552,-0.004821193837,-0.0009888410091,0.002891428388,0.005099006011,0.004838621474,0.00262673306,0.001108377621},
      {0.8629294517,0.6878605009,0.5127674801,0.3592948661,0.2306639057,0.1201681605,0.03285533743,0.006867038297,-0.001346361292,-0.00730255528,-0.01127857705,-0.01532776299,-0.02021257749,-0.02569334665,-0.02773158124,-0.02450430464,-0.01433253357,-0.005722884612,0.001637266841,0.005970171506,0.007949035712,0.007116378266,0.004690842147,0.001551955696},
      {0.8674737908,0.6996203694,0.5260982995,0.3672077036,0.2407668047,0.1319495393,0.04712431979,0.005760709509,-0.001682949023,-0.005217533062,-0.006134633532,-0.007631103406,-0.01067539421,-0.01530126827,-0.02068143104,-0.02469390655,-0.02943857934,-0.01929295971,-0.01161572953,-0.005422413998,-2.860585183e-05,0.004473002286,0.006758398533,0.007478265656},
      {0.8653746526,0.6931094173,0.5287987705,0.372362644,0.2498657968,0.1411089717,0.06408395454,0.005988380096,0.001936109608,0.0006930557915,-0.0007434062649,-0.001681620831,-0.003677660566,-0.00744307357,-0.01265528474,-0.02076338699,-0.02781532907,-0.02919227844,-0.01943002047,-0.01223629562,-0.005412580252,0.0005691751091,0.005396297108,0.009346885832},
    },
  },
  {
    {
      {0.467093359,0.158137397,0.0202129094,-0.02073110772,-0.02960283321,-0.02889389433,-0.02542051639,-0.01632901554,0.002732516238,0.007628692947,0.004596441734,0.002788978355,0.003696181432,0.001962937909,0.001972270272,0.02036408137,0.00210200793,0.004466186207,0.003455356635,0.003266845369,0.004828273182,0.003291996378,0.003875508297,-0.006244348603},
      {0.6869147567,0.3909262091,0.1873083129,0.05958297925,-0.02009488788,-0.06267315071,-0.07375086105,-0.06137974343,-0.03800560861,-0.01618642203,0.0006575897089,0.009512462881,0.01308110727,0.01270005865,0.009862219457,0.00956297848,0.00966258669,0.01027470261,0.008104065295,0.004996653054,0.001752981988,0.0001619912135,0.0008038421885,-0.001214694931},
      {0.7962289368,0.5288745089,0.2913518515,0.1286983217,0.02628873313,-0.03755111283,-0.06904375406,-0.07556396573,-0.06400209908,-0.046662432,-0.02947436437,-0.01466906458,-0.003605195576,0.003564414799,0.008090013989,0.01076533125,0.009842434706,0.006676732279,0.002515087514,0.001384285165,0.002870069783,0.006103843134,0.008564321834,0.008559277985},
      {0.8265697523,0.5825876964,0.3712121434,0.1854877222,0.05973178335,-0.01476281774,-0.05669878834,-0.07237191933,-0.06928220544,-0.05986945224,-0.04909336769,-0.03888605663,-0.02952677861,-0.02102020975,-0.01315427062,-0.006301944434,-0.001677270684,0.001324471846,0.003532168875,0.005451846782,0.007239965897,0.009264099326,0.01010771547,0.009128591558},
      {0.8465130434,0.6298077223,0.4204808384,0.24389503,0.09462126213,-0.001413298324,-0.04974473628,-0.07017929379,-0.06969577569,-0.06095323061,-0.049773874,-0.03804121895,-0.02892037675,-0.0225088777,-0.01784331492,-0.01270054229,-0.008694316882,-0.004995781004,-0.001470421287,0.001666993706,0.004419023876,0.006122730179,0.006360904404,0.005367998541},
      {0.8561479803,0.6617618954,0.4473423065,0.2849894559,0.1429079693,0.02844617764,-0.04137933321,-0.06562312203,-0.06778964181,-0.06167121665,-0.0515716412,-0.04120511278,-0.03055215002,-0.02252531567,-0.01750657824,-0.01656515605,-0.01600085503,-0.01633268727,-0.01686314004,-0.016918796,-0.0166808108,-0.01606782705,-0.01624979959,-0.01712308305},
      {0.8645683012,0.680235603,0.485726915,0.3138808143,0.1778771713,0.06569900966,-0.02166137612,-0.06964504492,-0.07437519785,-0.0690298183,-0.05804149631,-0.04624454877,-0.03505834445,-0.02685057711,-0.02079253139,-0.01755921136,-0.01619195069,-0.01604353737,-0.01643634404,-0.01712144452,-0.01855975704,-0.01839088081,-0.01691412142,-0.01567713586},
      {0.868806555,0.6933523331,0.5077599997,0.3231756919,0.19867409,0.09265533287,0.008890022141,-0.05048125489,-0.07994040154,-0.07693080852,-0.0666995668,-0.05317286066,-0.04129232495,-0.03013613837,-0.02187383298,-0.01559211465,-0.01001931366,-0.007574698756,-0.005011059313,-0.005320200556,-0.006886004041,-0.01051899226,-0.01456722659,-0.01615353695},
      {0.8746989033,0.7046503485,0.5308136709,0.3512467804,0.2117345465,0.1118832926,0.03332267737,-0.02290437591,-0.0568462414,-0.0768048035,-0.06653317424,-0.05216950331,-0.03900403729,-0.02699737213,-0.01709577534,-0.009829930848,-0.006306806811,-0.004787489764,-0.005034486332,-0.007627331419,-0.01123958671,-0.01552397429,-0.01985107574,-0.02161090926},
      {0.8804189007,0.7173557808,0.5528227508,0.3814180292,0.2255827225,0.1330833801,0.05764958485,0.003424359614,-0.03128841366,-0.05573802233,-0.07186550782,-0.06079935462,-0.04906113193,-0.03798203234,-0.0276369624,-0.01910428678,-0.01212754555,-0.007752113439,-0.005664611665,-0.003914355162,-0.006061013524,-0.009975758598,-0.01293678667,-0.01612838082},
      {0.8777959717,0.717234332,0.5504691456,0.3974614838,0.2465594981,0.1384785221,0.06953266594,0.02036249041,-0.007736535016,-0.03339730206,-0.05101848218,-0.06370891237,-0.05078519792,-0.03680060821,-0.02541906235,-0.01625430358,-0.00899995363,-0.003244826675,-0.000289204087,0.0004534895818,-0.002398490019,-0.00599050577,-0.009482331106,-0.01452336134},
      {0.8796079582,0.7190761326,0.560037916,0.4133864065,0.2717772208,0.1446276208,0.08265598033,0.0363526767,0.00737588043,-0.01647945135,-0.03792132083,-0.05271254308,-0.06319739232,-0.05102900515,-0.03607093392,-0.02353157407,-0.011051769,-0.002344849716,0.004233570443,0.007067774685,0.007508610735,0.006242246345,0.003803622092,0.005034715713},
      {0.8838269856,0.7273704837,0.5691777322,0.4254103545,0.2929543782,0.1698876275,0.08996684716,0.0484709479,0.02282440408,0.0007501840333,-0.01999677346,-0.03580842598,-0.05009590968,-0.06188134622,-0.0561646973,-0.04442789499,-0.03201604206,-0.02204155621,-0.01469927419,-0.00826209471,-0.003161552363,-0.0007963246343,-0.0009090156892,-0.001925514648},
      {0.8798948596,0.7226572848,0.5705742476,0.4301323688,0.3056838709,0.1851253876,0.08665314033,0.05367492588,0.0357229064,0.01894599273,0.004989345236,-0.009343725027,-0.02328276147,-0.03393448965,-0.04042738467,-0.03685569552,-0.02473083958,-0.01423879523,-0.005917722266,0.000235505843,0.002109802396,0.002197987362,0.0004362552935,-0.002386702372},
      {0.8814038452,0.7275659014,0.5759883956,0.4296900256,0.3048676657,0.1908974076,0.09335799295,0.04252748455,0.02754151308,0.01485567369,0.003969677757,-0.005196201124,-0.02080303413,-0.03212840733,-0.04292765824,-0.05216018475,-0.05566448077,-0.04295146966,-0.03076025488,-0.01963989404,-0.01024578108,-0.002156446956,0.002840711244,0.005677183085},
      {0.8838968743,0.7254355756,0.5851937415,0.4454404951,0.32229881,0.2149780477,0.1231696442,0.0502301226,0.04002513589,0.02997023958,0.01758941347,0.006699980827,-0.003650070247,-0.01861647076,-0.0304241896,-0.04432207676,-0.05434965592,-0.05661155385,-0.04364825445,-0.03275107094,-0.02096450567,-0.01179162927,-0.0050732837,-0.0001717456997},
    },
    {
      {0.4493123101,0.148335875,0.01701127969,-0.01968562133,-0.02729722146,-0.02713982484,-0.02409044975,-0.01542929946,0.002435629196,0.006565035176,0.003567174596,0.001925748138,0.004061367716,0.003648887491,0.004117290219,0.02139589329,0.003246511114,0.005367386134,0.00381800733,0.003112208006,0.005138443668,0.002714092238,0.003409938885,-0.005076052309},
      {0.6798289022,0.3765196461,0.1782901843,0.05560790095,-0.021181809,-0.0614325504,-0.07115167208,-0.05849867953,-0.03508236263,-0.01330574712,0.002568789643,0.0102487225,0.01315801696,0.01207412812,0.008829347099,0.008940514848,0.009527620641,0.01059713054,0.008781435113,0.006345882932,0.003173667901,0.00105415777,0.0001165643446,-0.002925830957},
      {0.7782164895,0.5071637707,0.2732846158,0.1187878854,0.02296706314,-0.03711191072,-0.06667677028,-0.07161325023,-0.05874657506,-0.04109337134,-0.02441385962,-0.01072502156,-0.0009969572647,0.005161427365,0.008970493263,0.01121070288,0.01013255206,0.007199045912,0.003085770475,0.002121985816,0.003551875412,0.006894602333,0.009441819555,0.009589317789},
      {0.8142174061,0.5661654636,0.3585211398,0.1752145555,0.05449725631,-0.01583919214,-0.05517691487,-0.06939473426,-0.06574484435,-0.05551934417,-0.04400509131,-0.03357741039,-0.02455782643,-0.01664042745,-0.009050940679,-0.002565968202,0.001343804819,0.003389614561,0.004949776664,0.00648841836,0.008123726846,0.01044090125,0.01164143253,0.01155201042},
      {0.8355995393,0.611981822,0.4039650759,0.2313255799,0.08646656882,-0.005352223306,-0.05024111581,-0.0685129845,-0.06676393422,-0.05781155051,-0.04707420748,-0.03611352138,-0.0278640276,-0.02215786066,-0.01784029984,-0.01291965535,-0.008658432875,-0.004289626457,-0.0005134118547,0.002224511973,0.004645327347,0.005712699125,0.005452302203,0.003763810276},
      {0.8467294023,0.6436403759,0.4277064518,0.2690301627,0.1314333446,0.02205794633,-0.04356979772,-0.06437487218,-0.06412915357,-0.05654734894,-0.04552203206,-0.03525199515,-0.02560397106,-0.01835032365,-0.01353759908,-0.01268217055,-0.01221568513,-0.01247854387,-0.01274471511,-0.01299924829,-0.0138138197,-0.01364094386,-0.01375814148,-0.01442423659},
      {0.856051396,0.6643529656,0.4670551548,0.2980547658,0.1666935632,0.05897129653,-0.02276264327,-0.06567511616,-0.06714131946,-0.06074358306,-0.05044093562,-0.0399614002,-0.03045670358,-0.02408036161,-0.02015437796,-0.01790491293,-0.0161090399,-0.01441642593,-0.01359103039,-0.01313287768,-0.01328840171,-0.01167211009,-0.009215246853,-0.007363137725},
      {0.8610599255,0.6809727991,0.490486003,0.3075934441,0.186864432,0.08366211993,0.003260730495,-0.05167747896,-0.07702378796,-0.07267701946,-0.06231582685,-0.04941589743,-0.03877200699,-0.02862291672,-0.02059284836,-0.01469858867,-0.009334126699,-0.006052429148,-0.002108745259,-0.001757976416,-0.002634979807,-0.005702753862,-0.00978002503,-0.0118920822},
      {0.8676474301,0.6913169749,0.5114482768,0.3326855689,0.1972225471,0.102782586,0.02932799858,-0.02136034705,-0.05022583651,-0.06537150956,-0.05364921227,-0.03959882898,-0.0276272426,-0.01750599479,-0.01040587686,-0.006095524619,-0.005103482648,-0.00645542066,-0.008589556326,-0.01174872417,-0.01531541865,-0.01830648104,-0.02133918478,-0.02108051643},
      {0.8724517678,0.7050065114,0.5341503565,0.3640950431,0.2094657072,0.1207207596,0.04847204012,-0.002265933319,-0.03259980986,-0.0536541517,-0.06693151177,-0.05395031817,-0.04096208289,-0.0292905306,-0.01882055085,-0.01058693556,-0.004587511017,-0.001120408388,-0.0002656061825,-0.0002596953263,-0.003252213908,-0.007275398563,-0.01064178969,-0.013972028},
      {0.8730452764,0.7087568406,0.5388675803,0.3808801042,0.2315771134,0.126795686,0.06209035809,0.0172682579,-0.006901839614,-0.02766958763,-0.0429862422,-0.05423597594,-0.04301807266,-0.03079202047,-0.0211730921,-0.01316202966,-0.00662032309,-0.001774717003,0.0004671781682,0.0008668406287,-0.001993891844,-0.005996886997,-0.01050032,-0.01693164884},
      {0.8745061533,0.7115061597,0.5483321706,0.3972676473,0.2583789384,0.1344796592,0.07608066728,0.03321099182,0.007632405682,-0.01307828173,-0.03132352617,-0.04441981668,-0.05417606434,-0.04175458019,-0.02834564306,-0.01739764785,-0.006739430724,0.0008483534091,0.005803574493,0.007348102163,0.007691595753,0.006699198989,0.005351884818,0.005609663475},
      {0.8799027509,0.7196472449,0.5564004737,0.4094687492,0.277874622,0.1590210355,0.08434437875,0.0478947662,0.02681279263,0.007457817989,-0.01128262847,-0.02555763997,-0.03894702119,-0.04954888014,-0.04430526515,-0.03384025703,-0.02301822804,-0.01559146309,-0.01088965039,-0.006138922004,-0.002775622813,-0.002216743052,-0.00304924335,-0.003412565189},
      {0.8757614084,0.7156604962,0.5597804641,0.4158487946,0.2877698028,0.1708100368,0.07529259761,0.04513993158,0.02976039549,0.01480251105,0.00188780164,-0.01048022479,-0.02245072557,-0.03190395331,-0.03684592448,-0.0334691428,-0.02177559004,-0.01186204495,-0.004572324079,0.0006764041199,0.002003570976,0.002356017585,0.001687967368,7.230490127e-05},
      {0.8779982245,0.7230157353,0.5665843763,0.4175791792,0.2900143212,0.1769954607,0.08415048762,0.03789871606,0.02584851297,0.0154962148,0.006773975227,-0.00191109059,-0.01448484974,-0.02589196455,-0.03654175107,-0.0453131986,-0.05184216041,-0.03959857919,-0.02884084609,-0.01984777902,-0.01253285882,-0.006522844966,-0.003348499661,-0.0006660033042},
      {0.877994792,0.7155669566,0.5714848764,0.4299200264,0.3046502324,0.1941925532,0.1092203624,0.04196230956,0.03523153924,0.0284660164,0.0186510879,0.009776181487,0.0001571036901,-0.01198859924,-0.0233089845,-0.03611498128,-0.04381634079,-0.04347747199,-0.03082220357,-0.02037709991,-0.00949713935,-0.0006209521086,0.005640417531,0.009338791178},
    },
    {
      {0.4257785152,0.1355095489,0.01289571618,-0.01927805893,-0.02492895053,-0.02459282679,-0.02165621241,-0.01344329697,0.003531973441,0.00691993094,0.0031858014,0.001444684554,0.003107090397,0.003439463328,0.004007161188,0.02029448922,0.002263776016,0.003901535656,0.002361243055,0.002180661202,0.004668038803,0.001639339054,0.002440776523,-0.005559003316},
      {0.6700375566,0.3570112601,0.1658142322,0.04992950128,-0.0225205548,-0.05923454327,-0.0670364425,-0.05352092799,-0.02975877091,-0.00847226487,0.00678702723,0.01353083377,0.01564857645,0.01354285651,0.008912387597,0.007592782533,0.007022163315,0.007781164879,0.006306218107,0.005013242116,0.002351987068,0.0005283282852,-0.0004261888625,-0.003350504248},
      {0.7571247054,0.4814832776,0.251530846,0.1066072616,0.01918835375,-0.03610741804,-0.06385146962,-0.06759571154,-0.05356437099,-0.03581514291,-0.01986164551,-0.007292644865,0.001103606797,0.006647199865,0.009924689092,0.0117616218,0.009627780572,0.005943646992,0.001380150702,4.263431182e-05,0.0007339550549,0.00317366216,0.005608656893,0.006698176896},
      {0.7993075317,0.5458079317,0.3421385559,0.1621992544,0.04779005814,-0.0172349728,-0.05338418093,-0.06626059572,-0.06266404049,-0.05272031035,-0.04171567393,-0.03149339411,-0.02221445096,-0.0133846806,-0.004786451065,0.002139364067,0.005772528807,0.006615300865,0.006674261743,0.006738691664,0.006984048501,0.008867970566,0.01034749876,0.01097287046},
      {0.8230420116,0.5921485896,0.3863574266,0.2189226657,0.07966144746,-0.006451174139,-0.04612128954,-0.06112866204,-0.05734195265,-0.04799301048,-0.0381377084,-0.02824926365,-0.02145155831,-0.01743593732,-0.0141397572,-0.01033534154,-0.007026260731,-0.003563014152,-0.001383080147,-0.0002390317235,0.0009601862389,0.001685976386,0.001734063387,0.0007770022003},
      {0.8365383018,0.6240997534,0.4069354766,0.2528427306,0.1201944509,0.01608995908,-0.04462994985,-0.06058820324,-0.05700949024,-0.04798812882,-0.03699550011,-0.02789244056,-0.02048684159,-0.0152805039,-0.01252923732,-0.01320387071,-0.01373840575,-0.01450064071,-0.01523618911,-0.01520364791,-0.01523303872,-0.01351362413,-0.01171004934,-0.009538450095},
      {0.8476640822,0.6487230078,0.4483126915,0.2818722245,0.1552191707,0.05203769261,-0.02417885498,-0.06275542846,-0.06158636514,-0.05405812491,-0.04346628202,-0.03304719231,-0.02416573942,-0.01864287605,-0.0161868548,-0.01462994338,-0.01259681252,-0.01052255697,-0.01011561281,-0.01013289862,-0.01078331044,-0.008842650477,-0.006772591208,-0.004794665286},
      {0.8524879781,0.6664658524,0.4714914339,0.2904444368,0.1747865687,0.07578769423,0.0002593173145,-0.05010183504,-0.07052009208,-0.0621757276,-0.04949917117,-0.03609374493,-0.02587425666,-0.01644497478,-0.00928217409,-0.004358659454,0.0001434997863,0.003245234115,0.007036806847,0.007459895684,0.006209847296,0.002890525646,-0.001815847088,-0.005204931519},
      {0.8605701064,0.6785382325,0.492765522,0.3151099397,0.1831235738,0.09317805399,0.02345961046,-0.0228384586,-0.04801454225,-0.06007209059,-0.04749821622,-0.03347280644,-0.02154734409,-0.01184388036,-0.004868056804,-0.0001428499824,0.001148068168,-0.000650599258,-0.0030723132,-0.005780685461,-0.009544968627,-0.0129601249,-0.01695720135,-0.01837175551},
      {0.8644237966,0.6923594211,0.5159612377,0.3479683947,0.1955545,0.1121820961,0.04473319169,-0.001957171454,-0.02841591336,-0.04669644547,-0.05809580684,-0.04480246165,-0.03236625834,-0.0218411016,-0.01264845893,-0.005917045266,-0.001873027889,0.0004113477694,0.0002591705659,-0.0008916820577,-0.005331125227,-0.01019083145,-0.01391053497,-0.01750659776},
      {0.8669665897,0.6980062371,0.5244746738,0.3626563748,0.2159504114,0.1151355267,0.05556004858,0.01527225298,-0.004808049339,-0.02049471439,-0.03309696634,-0.04304456342,-0.03296452211,-0.02223746485,-0.01369354974,-0.00668361666,-0.0009204939122,0.002353413148,0.003753341933,0.003576646303,0.000795611493,-0.003780224354,-0.007667525039,-0.01340352996},
      {0.8695974776,0.7040263493,0.5378753083,0.3832764148,0.2476204706,0.1275898108,0.0737345024,0.03476605503,0.01183293835,-0.006601597841,-0.02306665438,-0.03584935871,-0.04606796426,-0.0351830998,-0.02339765231,-0.01415034693,-0.004615054657,0.002166483925,0.006691034727,0.008403170791,0.009318880952,0.009555071275,0.008992863982,0.008537534151},
      {0.8751840116,0.7122930628,0.5447864127,0.3946200335,0.2632338266,0.1485197872,0.079088418,0.04771467465,0.03138623912,0.01501313254,-0.0008477536436,-0.01340820351,-0.02600997252,-0.03711219895,-0.03368186211,-0.02515166,-0.01645722804,-0.01080161574,-0.006736935311,-0.002409403063,0.0007609907657,0.0004672404547,-0.001617079,-0.004329600772},
      {0.8708833308,0.707609346,0.5477181119,0.400740125,0.2700175019,0.1570364828,0.06562534029,0.04100671165,0.03028752946,0.01856116132,0.007318653398,-0.003590729032,-0.0143483938,-0.02400456324,-0.02914541744,-0.02585448571,-0.01484564139,-0.005424868487,0.001279895876,0.005268935292,0.006172311174,0.005652920097,0.003904311057,0.00171790071},
      {0.8746215952,0.7180188863,0.5580192927,0.4071584326,0.2771052026,0.1645759006,0.07587559435,0.03358440518,0.02484975919,0.01729682056,0.01055651144,0.002461105923,-0.00695144499,-0.01761338357,-0.0280812287,-0.03570773123,-0.0424308583,-0.03039214724,-0.0206449174,-0.0133199815,-0.007208907722,-0.00220937421,-0.0005984834652,0.000262970406},
      {0.8737401079,0.7085569375,0.5601810161,0.4168075069,0.2901765025,0.1777456605,0.09878553946,0.03724165145,0.03489357647,0.03183618832,0.02526969908,0.01832900222,0.009318218591,-0.0005135719096,-0.0121801258,-0.02580237708,-0.03406839469,-0.03441278021,-0.02248742868,-0.01268737235,-0.002857101242,0.005456017266,0.01155210053,0.01521430267},
    },
  },
}
local GS_SYN_VAR17 = {
  {
    {0.006638298605,0.006123446526,0.005112825676,0.004799978355,0.004103260378,0.003636406457,0.00322331787,0.002934865158,0.002583058155,0.002367917963,0.002099240204,0.00191863145,0.001724142525,0.001545217662,0.00138688271,0.001275363723},
    {0.006942600778,0.006431864813,0.00563135664,0.005138841819,0.00457028246,0.004085900323,0.003654224217,0.003304109285,0.002967255257,0.002721894998,0.00244618876,0.002241876336,0.002033032627,0.001836477812,0.001660982156,0.001538879923},
    {0.007446887625,0.006938213889,0.006435684884,0.005695467137,0.005290920998,0.004782841605,0.004319451088,0.003891258795,0.003556677544,0.00326573073,0.002977929427,0.002735681185,0.002504944211,0.002280298039,0.002080956865,0.001941721843},
  },
  {
    {0.006408384651,0.005751093996,0.004680189696,0.004213728101,0.003539536694,0.003066678439,0.002679543349,0.002395185924,0.002080821395,0.001887952112,0.001660399162,0.001508792404,0.001348086655,0.001204276199,0.00107996765,0.0009874311137},
    {0.00675082975,0.00608832224,0.005182691572,0.004565266469,0.00397588976,0.00347921905,0.003066270343,0.002733275128,0.002413392023,0.002190193669,0.001950346211,0.001776239326,0.001602200789,0.001439226512,0.001301230435,0.001198060183},
    {0.007307609029,0.006632912573,0.005962152153,0.005135722251,0.004647272694,0.004118143508,0.003663505042,0.003263939742,0.002925996303,0.002655203996,0.002397949428,0.002184379594,0.001990989944,0.001801757782,0.001644314941,0.001522364959},
  },
  {
    {0.006510977542,0.00567607095,0.004484845399,0.003844063731,0.003160728391,0.002657461252,0.00227267337,0.001983899418,0.001695168497,0.001514349525,0.001314289015,0.001181490204,0.001045900421,0.0009291566512,0.0008345841453,0.000754933504},
    {0.006913299202,0.006061922602,0.004996441698,0.004224565168,0.00358294632,0.003050705005,0.002631206465,0.002301679531,0.001995063873,0.001776744908,0.001563247798,0.001407037799,0.001256231164,0.001121008404,0.001015200391,0.0009241247005},
    {0.007555309702,0.006678523986,0.005788068069,0.004834069653,0.00423282299,0.003657145959,0.003182883933,0.002798476739,0.002456122825,0.002183847702,0.001947810612,0.001753095827,0.001581964155,0.001419386067,0.001297727867,0.001185668617},
  },
  {
    {0.006950682752,0.005897826168,0.004527127669,0.003693411936,0.002960171124,0.002410723514,0.00200564794,0.001701827727,0.001427150337,0.001246854231,0.001063557497,0.0009426529476,0.0008235966322,0.0007249805011,0.0006505036588,0.0005814474247},
    {0.007432034781,0.006353350128,0.005074996487,0.004115891246,0.003390431416,0.002803766525,0.00235360839,0.002012892169,0.001706878387,0.00148632771,0.001283768954,0.001137856428,0.001002675288,0.0008847017714,0.0008019814258,0.0007196916256},
    {0.008192752067,0.00707314053,0.005920738034,0.004786744757,0.00405261788,0.003407495433,0.002890533382,0.002496240585,0.002136993635,0.001857123978,0.00162648093,0.001441149953,0.001282373904,0.001137666384,0.001040210119,0.0009356352958},
  },
  {
    {0.007732205695,0.006421699268,0.004813702507,0.003765123632,0.002941581536,0.00232966813,0.001884690198,0.001557312638,0.001281636052,0.001092632817,0.0009166756408,0.0008004820113,0.0006873504903,0.0006000172406,0.0005353135587,0.0004725352253},
    {0.00831370155,0.006967120156,0.00542439998,0.004244919621,0.00340187442,0.002742273727,0.002244979678,0.001875965518,0.001556844914,0.001323190081,0.00112314113,0.0009818203826,0.0008499502362,0.0007428165015,0.0006691868564,0.0005926520827},
    {0.009226616029,0.007822551422,0.006367722571,0.005005612019,0.004108685758,0.003374452456,0.002798117796,0.002366732658,0.001982258726,0.00168394621,0.001447549823,0.001266453922,0.001107182489,0.0009719397374,0.0008832224513,0.0007833204384},
  },
}

local function gs_tab(mat, s, soft, msh)
    -- bracket helper over a level list; returns lo-index and fraction
    local function bracket(levels, x)
        x = math_max(levels[1], math_min(levels[#levels], x))
        if x >= levels[#levels] then return #levels - 1, 1.0 end
        local j = 1
        while levels[j + 1] < x do j = j + 1 end
        return j, (x - levels[j]) / (levels[j + 1] - levels[j])
    end
    local mi, mf = bracket(GS_MIX_LEVELS, msh or 0.0)
    local si, sf = bracket(GS_SOFT_LEVELS, soft or 1.0)
    local function at(m)
        local n = #GS_SYN_S
        if s <= GS_SYN_S[1] then return m[1] end
        if s >= GS_SYN_S[n] then return m[n] end
        local i = 1
        while GS_SYN_S[i + 1] < s do i = i + 1 end
        local f = (s - GS_SYN_S[i]) / (GS_SYN_S[i + 1] - GS_SYN_S[i])
        if type(m[1]) == "table" then
            local r, a, b = {}, m[i], m[i + 1]
            for j2 = 1, #a do r[j2] = a[j2] * (1 - f) + b[j2] * f end
            return r
        end
        return m[i] * (1 - f) + m[i + 1] * f
    end
    -- lerp softness inside each mix bracket, then lerp across mix
    local function at_soft(mmix)
        local lo = at(mmix[si])
        if sf == 0.0 then return lo end
        local hi = at(mmix[si + 1])
        if type(lo) == "table" then
            local r = {}
            for j2 = 1, #lo do r[j2] = lo[j2] * (1 - sf) + hi[j2] * sf end
            return r
        end
        return lo * (1 - sf) + hi * sf
    end
    local lo = at_soft(mat[mi])
    if mf == 0.0 then return lo end
    local hi = at_soft(mat[mi + 1])
    if type(lo) == "table" then
        local r = {}
        for j2 = 1, #lo do r[j2] = lo[j2] * (1 - mf) + hi[j2] * mf end
        return r
    end
    return lo * (1 - mf) + hi * mf
end

local function gs_sstep(e0, e1, x)
    local t = (x - e0) / (e1 - e0)
    t = math_max(0.0, math_min(1.0, t))
    return t * t * (3 - 2 * t)
end

--  luma_gain = luma_adapt x zone_sensitivity (photon-grain.lua, verbatim)
local function gs_luma_gain(l)
    local dev = (l - 0.40) / 0.45
    local la = math.exp(-dev * dev)
        + 0.12 * (1 - gs_sstep(0, 0.30, l))
        + 0.20 * gs_sstep(0.5, 0.85, l)
    la = math_max(0.0, math_min(1.05, la))
    local sw = 1 - gs_sstep(0, 0.15, l)
    local hw = gs_sstep(0.95, 1.0, l)
    local mw = math_max(0.0, math_min(1 - sw - hw, 1))
    return la * (sw * 1.8 + mw * 1.5 + hw * 2.7)
end

--  adapt scalar from the same scene feed the engine consumed (verbatim
--  terms; amount arrives rendered via the hud-state mirror).
local function gs_adapt(amount)
    local a = amount * (1.0 + 0.8 * (1.0 - photon_scene_smooth_peak))
    a = a * (1.0 - gs_sstep(0.05, 0.35, photon_scene_smooth_noise) * 0.5)
    a = a * (0.8 + 0.4 * photon_scene_motion)
    if is_hdr then a = a * 0.55 end
    return a
end

--  eff_size = GRAIN_SIZE_rendered x res profile x window comp x hdr mix.
--  res profile keys off the SCREENSHOT height: at //HOOK OUTPUT the
--  shader's input_size IS the output texture, so its scale_mult tracks
--  the window, not the source (its comment claims source; behavior is
--  window). Self-consistent with what the probe sees either way.
local function gs_eff_and_density(frame_h)
    if type(frame_h) ~= "number" then return nil end  -- no height: hold, never guess the profile
    local scale, dens
    if GR.res_adapt == 0 then scale, dens = 1.0, 1.0
    elseif frame_h < 700 then scale, dens = 2.0, 0.70
    elseif frame_h < 1100 then scale, dens = 1.0, 1.00
    else scale, dens = 0.5, 0.85 end
    local wc = math.sqrt(1600.0 / math_max(frame_h, 1.0))
    wc = math_max(0.4, math_min(0.8, wc))
    local hdr_mix = is_hdr and 0.75 or 1.0
    if GR.adaptive_mode and GR.size_coefficient and GR.size_coefficient > 0 then
        -- Same host coefficient sent to the shader; frame_h only selects legacy density.
        local eff = GR.size_rendered * GR.size_coefficient * hdr_mix
        GS.last_eff = eff
        -- The synthetic tables start at .5. Never silently clamp .4/.3 to .5.
        GS.eff_floor_clamped = false
        if eff < GS_SYN_S[1] and eff >= GS_SYN_S[1] * SIZE_GOV.convention.floor_tol then
            -- Explicit, flagged floor clamp (never silent): table row .5 stands in for .4-.5; below .4 still holds.
            -- tolerance = SIZE_GOV.convention.floor_tol (declared CONVENTION, see SIZE_GOV).
            GS.eff_floor_clamped = true
        elseif eff < GS_SYN_S[1] or eff > GS_SYN_S[#GS_SYN_S] then
            SIZE_GOV.hold("live", eff < GS_SYN_S[1]
                and "GS subtraction not available below effective size .5, adaptive path holds"
                or "GS subtraction not available above effective size 8, adaptive path holds")
            return nil
        end
        -- Same host density in subtraction, p5_sum and p5_tgt; no extra k ratio.
        return eff, GR.render_density or dens
    end
    GS.last_eff = GR.size_rendered * scale * wc * hdr_mix
    return GS.last_eff, dens
end

--  GS PROBE FRAME HELPERS — shared by the sample path and the flicker vote

-- One screenshot-raw frame → centered square luma crop + frame luma (for
-- cut detection) + full frame height (the res profile keys off it).
-- Same bgr0/stride contract as every screenshot-raw consumer in this file.
function GS.capture_luma_raw()
    local ok, shot = COST.shot("own")
    GS.shot_ok = ok and type(shot) == "table"
    GS.shot_h = type(shot) == "table" and shot.h or nil
    if not ok or type(shot) ~= "table" then
        GS.nil_why = string.format("shot-fail ok=%s type=%s", tostring(ok), type(shot)); return nil
    end
    if not shot.data or not shot.w or not shot.h then
        GS.nil_why = string.format("shot-fields data=%s w=%s h=%s", type(shot.data), tostring(shot.w), tostring(shot.h)); return nil
    end
    if type(shot.data) ~= "string" then GS.nil_why = "data-not-string type=" .. type(shot.data); return nil end
    local data, w, h = shot.data, shot.w, shot.h
    -- Validate the existing packed four-byte screenshot contract before
    -- arithmetic/indexing. Invalid captures are no measurement, not zero noise.
    local function positive_integer(v)
        return type(v) == "number" and v == v and v < math.huge
            and v > 0 and v == math_floor(v)
    end
    if not positive_integer(w) or not positive_integer(h) then
        GS.nil_why = "invalid-shot-dimensions"; return nil
    end
    local stride = shot.stride or (w * 4)
    if not positive_integer(stride) or stride < w * 4 then
        GS.nil_why = "invalid-shot-stride"; return nil
    end
    -- The last visible pixel must be present; trailing row padding is optional.
    local visible_bytes = (h - 1) * stride + w * 4
    if visible_bytes == math.huge or visible_bytes > #data then
        GS.nil_why = "short-shot-buffer"; return nil
    end

    local cw = math_min(w, GS.crop)
    local ch = math_min(h, GS.crop)
    GS.crop_w, GS.crop_h = cw, ch
    if cw < 96 or ch < 96 then GS.nil_why = string.format("crop<96 w=%s h=%s crop=%sx%s", tostring(w), tostring(h), tostring(cw), tostring(ch)); return nil end
    local ox = math_floor((w - cw) / 2)
    local oy = math_floor((h - ch) / 2)

    -- luma plane (frame luma accumulates for the strength normalizer)
    local L = {}
    local luma_sum = 0.0
    for y = 0, ch - 1 do
        local row = (oy + y) * stride + ox * 4
        local base = y * cw
        for x = 0, cw - 1 do
            local b, g, r = string.byte(data, row + x * 4 + 1, row + x * 4 + 3)
            if not r then GS.nil_why = string.format("short-row row=%s x=%s bytes=%s stride=%s", tostring(row), tostring(x), tostring(#data), tostring(stride)); return nil end
            local lum = 0.299 * r + 0.587 * g + 0.114 * b
            L[base + x] = lum
            luma_sum = luma_sum + lum
        end
    end
    return L, cw, ch, luma_sum / (cw * ch), h
end
GS.capture_luma = COST.wrap("GS", GS.capture_luma_raw)

-- Separable box-k high-pass over a luma plane. Returns the HP plane and
-- the kernel margin m.
function GS.highpass(L, cw, ch, k)
    local m = math_floor(k / 2)
    local T = {}
    for y = 0, ch - 1 do
        local base = y * cw
        for x = m, cw - 1 - m do
            local s = 0
            for o = -m, m do s = s + L[base + x + o] end
            T[base + x] = s / k
        end
    end
    local HP = {}
    for y = m, ch - 1 - m do
        local base = y * cw
        for x = m, cw - 1 - m do
            local s = 0
            for o = -m, m do s = s + T[base + o * cw + x] end
            HP[base + x] = L[base + x] - s / k
        end
    end
    return HP, m
end

-- 8x8 downsampled signature of one block's HP plane: the temporal-flicker
-- probe. Live grain re-randomizes every frame; MPEG blocking and static
-- content do not.
function GS.block_sig(HP, cw, bx, by)
    local sig = {}
    for sy = 0, 7 do
        local row = {}
        for sx = 0, 7 do
            local s4 = 0.0
            for dy = 0, 3 do
                local b4 = (by + sy * 4 + dy) * cw
                for dx = 0, 3 do
                    s4 = s4 + HP[b4 + bx + sx * 4 + dx]
                end
            end
            row[sx + 1] = s4 / 16.0
        end
        sig[sy + 1] = row
    end
    return sig
end

-- Actual producer/consumer handshake: one synchronous post-render readback.
-- No claim of decoded-source capture or calibrated synthetic basis.
function GS.tuple_finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
function GS.tuple_identity(v)
    return GS.tuple_finite(v) and v >= 0 and v < 9007199254740992 and v % 1 == 0
end
function GS.capture_tuple()
    local pos = mp.get_property_number("time-pos")
    if not GS.tuple_finite(pos) or not GS.tuple_identity(DOC.gen) or
       type(GR.enabled) ~= "boolean" or not GS.tuple_identity(GR.serial or 0) then return nil end
    local tuple = {generation=DOC.gen, observed_playback_position=pos,
        capture_api="screenshot-raw-own", frame_pts_status="UNAVAILABLE",
        shader_plane_status="UNVERIFIED", render_serial=GR.serial or 0,
        mirror_generation=GR.doc_gen, enabled=GR.enabled, amount=GR.amount_gpu,
        strength=GR.strength, size=GR.size_rendered, softness=GR.soft_rendered,
        weight=GR.weight_shift, source_h=GR.source_h, output_h=GR.output_h,
        effective_h=GR.effective_h}
    if GR.enabled and GR.doc_gen ~= DOC.gen then return nil end
    for _, key in ipairs({"amount", "strength", "size", "softness", "weight"}) do
        if not GS.tuple_finite(tuple[key]) then return nil end
    end
    for _, key in ipairs({"source_h", "output_h", "effective_h"}) do
        if tuple[key] ~= nil and (not GS.tuple_finite(tuple[key]) or tuple[key] <= 0) then return nil end
    end
    return tuple
end
function GS.same_tuple(a, b)
    if not a or not b then return false end
    -- Playback-position observations delimit a readback, not frame-owned PTS.
    for key, value in pairs(a) do
        if key ~= "observed_playback_position" and b[key] ~= value then return false end
    end
    for key, value in pairs(b) do
        if key ~= "observed_playback_position" and a[key] ~= value then return false end
    end
    return true
end

local function gs_sample_frame()
    GS.accepted_capture_tuple = nil
    GS.nil_why = nil
    GS.last_eff = nil
    GS.crop_w, GS.crop_h = nil, nil
    local capture_tuple = GS.capture_tuple()
    if not capture_tuple then GS.nil_why = "capture-tuple-unbound"; return nil end
    local capture_started = mp.get_time()
    local L, cw, ch, frame_luma, h = GS.capture_luma()
    local capture_finished = mp.get_time()
    local after_tuple = GS.capture_tuple()
    if not GS.same_tuple(capture_tuple, after_tuple) then
        GS.nil_why = "capture-tuple-changed"; return nil
    end
    if not L then GS.nil_why = GS.nil_why or "capture-no-luma"; return nil end
    if not GS.tuple_finite(h) or h <= 0 or h % 1 ~= 0 then GS.nil_why = "no-frame-height"; return nil end
    if not GS.tuple_finite(capture_started) or not GS.tuple_finite(capture_finished) or capture_finished < capture_started then
        GS.nil_why = "capture-observation-clock"; return nil
    end  -- no frame height: no measurement, hold (never guess the res profile)

    -- separable box-k high-pass at a given kernel size (shared helper:
    -- the flicker vote rebuilds the same plane on the pair frame)
    local function highpass(k) return GS.highpass(L, cw, ch, k) end

    -- cluster estimate from one HP plane: flat-third blocks, autocorr
    -- zero-crossing, THEN subtraction of the known synthetic field.
    -- Returns est (px), plus strength-top-up inputs.
    local function measure(HP, m, k)
        local bs = GS.block
        local blocks = {}
        local nb = 0
        for by = m, ch - bs - m, bs do
            for bx = m, cw - bs - m, bs do
                local sum, sum2 = 0.0, 0.0
                for y = by, by + bs - 1 do
                    local base = y * cw
                    for x = bx, bx + bs - 1 do
                        local v = HP[base + x]
                        sum = sum + v; sum2 = sum2 + v * v
                    end
                end
                local n = bs * bs
                nb = nb + 1
                blocks[nb] = {var = sum2 / n - (sum / n) * (sum / n), bx = bx, by = by}
            end
        end
        if nb < 6 then GS.nil_why = string.format("blocks<6 nb=%d crop=%dx%d block=%d", nb, cw, ch, GS.block); return nil end
        table.sort(blocks, function(a, b) return a.var < b.var end)
        local keep = math_max(4, math_floor(nb / 3))

        local lags = {}
        local den = 0.0
        local cnt = 0
        local kept = {}
        for i = 1, keep do
            local blk = blocks[i]
            if blk.var > 1e-6 then
                cnt = cnt + 1
                den = den + blk.var
                kept[cnt] = blk
                local bx, by = blk.bx, blk.by
                -- per-block mean luma + 3x3 texture density (stride-4
                -- sample of the shader's tex_variance term, post-grain:
                -- documented approximation, validated in the sim)
                local lsum, tsum, tn = 0.0, 0.0, 0
                for y = by + 1, by + bs - 2, 4 do
                    local base = y * cw
                    for x = bx + 1, bx + bs - 2, 4 do
                        local c0 = L[base + x] / 255.0
                        lsum = lsum + c0
                        local s9, s29 = 0.0, 0.0
                        for dy = -1, 1 do
                            local b9 = base + dy * cw
                            for dx = -1, 1 do
                                local v9 = L[b9 + x + dx] / 255.0
                                s9 = s9 + v9; s29 = s29 + v9 * v9
                            end
                        end
                        tsum = tsum + math_max(0.0, s29 / 9 - (s9 / 9) * (s9 / 9))
                        tn = tn + 1
                    end
                end
                blk.luma = lsum / tn
                blk.tex = 1.0 - gs_sstep(0.0, 0.008, tsum / tn) * 0.35
                -- 8x8 downsampled signature of this block's HP plane: the
                -- temporal-flicker probe. Live grain re-randomizes every
                -- frame; MPEG blocking and static content do not.
                blk.sig = GS.block_sig(HP, cw, bx, by)
                for lag = 1, GS.max_lag do
                    local sx, sy, nn = 0.0, 0.0, 0
                    for y = by, by + bs - 1 do
                        local base = y * cw
                        for x = bx, bx + bs - 1 - lag do
                            sx = sx + HP[base + x] * HP[base + x + lag]
                            nn = nn + 1
                        end
                    end
                    for y = by, by + bs - 1 - lag do
                        local base = y * cw
                        local base2 = (y + lag) * cw
                        for x = bx, bx + bs - 1 do
                            sy = sy + HP[base + x] * HP[base2 + x]
                        end
                    end
                    lags[lag] = (lags[lag] or 0.0) + (sx / nn + sy / nn) / 2
                end
            end
        end
        if cnt == 0 or den == 0 then
            GS.nil_why = string.format("zero-hp cnt=%d den=%.3g nb=%d keep=%d var_min=%.6g var_med=%.6g var_max=%.6g", cnt, den, nb, keep,
                blocks[1].var, (blocks[math_floor((nb + 1) / 2)].var + blocks[math_floor(nb / 2) + 1].var) / 2, blocks[nb].var)
            return nil
        end

        -- DECONVOLUTION: subtract the engine's own synthetic covariance.
        -- Per kept block the synthetic HP power is (255 x amp x DEV)^2 x
        -- cf2 x var_tab(eff); the corrected source curve is what remains.
        local live = GR.enabled and (mp.get_time() - GR.ts) < GR_STALE_S
        local var_src, cov = den, lags
        local psyn_sum, p5_sum, p5_tgt = 0.0, 0.0, 0.0
        if GR.enabled then
            if not live then
                GS.nil_why = string.format("stale-mirror age=%.1f", mp.get_time() - GR.ts)
                return nil
            end  -- stale mirror: hold, never guess
            local soft = GR.soft_rendered or 1.0
            -- mono mode or a manual softness below the table floor: the
            -- baked field no longer matches what the GPU draws. Hold --
            -- an extreme under uncertainty is the one banned outcome.
            if soft < 0.68 then GS.nil_why = string.format("soft<.68 soft=%.2f", soft); return nil end
            local eff, dens = gs_eff_and_density(h)
            if not eff then
                GS.nil_why = string.format("no-eff eff=%.3f h=%s size=%.2f coef=%s adaptive=%s",
                    GS.last_eff or -1, tostring(h), GR.size_rendered or -1, tostring(GR.size_coefficient), tostring(GR.adaptive_mode))
                return nil
            end  -- no frame height or unsupported size: hold
            local var_t = gs_tab(k == 9 and GS_SYN_VAR9 or GS_SYN_VAR17, eff, soft, GR.weight_shift)
            local ac_t = gs_tab(k == 9 and GS_SYN_AC9 or GS_SYN_AC17, eff, soft, GR.weight_shift)
            -- subtraction models what the GPU actually draws (clamped amount);
            -- the top-up target anchors at the amount WITHOUT his manual
            -- offset, so cranking density can never escalate strength.
            local adapt = gs_adapt(GR.amount_gpu)
            local adapt_t = gs_adapt(math_max(GR.amount_gpu - GR.user_offset, 0.05))
            for i = 1, cnt do
                local blk = kept[i]
                local lg = gs_luma_gain(blk.luma)
                local amp = lg * (GR.strength / 10.0)
                    * adapt * dens * blk.tex
                local p = (255 * amp * GR.dev_rendered) ^ 2 * GS.cf2 * var_t
                psyn_sum = psyn_sum + p
                local amp5 = lg * (GS.strength_default / 10.0)
                    * adapt * dens * blk.tex
                p5_sum = p5_sum + (255 * amp5 * GR.dev_rendered) ^ 2 * GS.cf2 * var_t
                local amp5_t = lg * (GS.strength_default / 10.0)
                    * adapt_t * dens * blk.tex
                p5_tgt = p5_tgt + (255 * amp5_t * GR.dev_rendered) ^ 2 * GS.cf2 * var_t
            end
            psyn_sum = psyn_sum * GS.sub_factor
            var_src = den - psyn_sum
            cov = {}
            for lag = 1, GS.max_lag do
                cov[lag] = lags[lag] - psyn_sum * ac_t[lag]
            end
        else
            -- engine off: everything measured is source; still compute the
            -- top-up basis for the strength hint at current params
            local eff, dens = gs_eff_and_density(h)
            if not eff then
                GS.nil_why = string.format("no-eff eff=%.3f h=%s size=%.2f coef=%s adaptive=%s",
                    GS.last_eff or -1, tostring(h), GR.size_rendered or -1, tostring(GR.size_coefficient), tostring(GR.adaptive_mode))
                return nil
            end  -- no frame height or unsupported size: hold
            local var_t = gs_tab(k == 9 and GS_SYN_VAR9 or GS_SYN_VAR17, eff,
                GR.soft_rendered or 1.0, GR.weight_shift)
            local adapt = gs_adapt(GR.amount_gpu)
            local adapt_t = gs_adapt(math_max(GR.amount_gpu - GR.user_offset, 0.05))
            for i = 1, cnt do
                local blk = kept[i]
                local lg = gs_luma_gain(blk.luma)
                local amp5 = lg * (GS.strength_default / 10.0)
                    * adapt * dens * blk.tex
                p5_sum = p5_sum + (255 * amp5 * GR.dev_rendered) ^ 2 * GS.cf2 * var_t
                local amp5_t = lg * (GS.strength_default / 10.0)
                    * adapt_t * dens * blk.tex
                p5_tgt = p5_tgt + (255 * amp5_t * GR.dev_rendered) ^ 2 * GS.cf2 * var_t
            end
        end

        local share = var_src / den
        -- strength top-up: re-body to the accepted target, never blind add.
        -- target = (6.25/5)^2 x power-at-default-strength; fill the gap
        -- between that and what the source already carries.
        local mult = nil
        GS.r_total = nil
        if p5_sum > 0 then
            local on = SIZE_GOV.program_on
            local look = on and (GS.look_R or GS.look_seed) or GS.look_seed
            local target = look * p5_tgt
            local fill = math_max(target - math_max(var_src, 0.0), 0.0)
            mult = math.sqrt(fill / p5_sum)
            if on then
                mult = math_max(GS.mult_floor, mult)
                if p5_tgt > 0 then GS.r_total = den / p5_tgt end
            else
                mult = math_max(GS.legacy_min, math_min(GS.legacy_max, mult))
            end
        end

        if var_src <= 0 or share < GS.src_share_min then
            GS.nil_why = var_src <= 0 and "over-corrected-source-power" or "source-share-below-floor"
            -- source ~= clean/dead (or correction noise): no size signal,
            -- but the top-up above stays valid (target = full body).
            return nil, mult, share, var_src
        end
        local est = nil
        if cov[1] <= 0 then
            GS.nil_why = "garbage-curve-over-corrected"
            return nil, mult, share, var_src  -- garbage curve: over-corrected
        elseif cov[1] / var_src <= 0.05 then
            est = 1.0  -- legit salt-fine source, not garbage
        else
            local prev_c = nil
            for lag = 1, GS.max_lag do
                local c = cov[lag] / var_src
                if c <= 0.05 then
                    local t = (prev_c - 0.05) / (prev_c - c)
                    est = (lag - 1) + t
                    break
                end
                prev_c = c
            end
        end
        if not est then GS.nil_why = "garbage-curve-no-crossing" end
        -- Arm the paired flicker vote: keep this sample's kept-block
        -- signatures (k==9 grid) so a ceiling-ward candidate in gs_tick
        -- can capture a second frame a few frames later and measure
        -- temporal flicker on the close pair. The r4 4s cross-sample
        -- chain could not vote on playing content: the picture drifts
        -- between samples and the vote was absent or washed out - the
        -- field's DVD committed hint=2.600 at n=8 with no decisive vote.
        if k == 9 then
            local sigs = {}
            for i = 1, cnt do
                local b = kept[i]
                sigs[i] = { bx = b.bx, by = b.by, sig = b.sig }
            end
            GS.pair = { cw = cw, ch = ch, luma = frame_luma, sigs = sigs }
        end
        return est, mult, share, var_src  -- est nil when no crossing: hold
    end

    -- Fine scale first (box9): accurate in the 1-4px band. Only when that
    -- saturates (correlation still alive at max lag = coarser cluster)
    -- pay for the coarse scale (box17), which reaches ~8-10px - S16 at
    -- 4K lives up there per the film-grain literature.
    local HP9, m9 = highpass(9)
    local est, mult, share, vsrc = measure(HP9, m9, 9)
    -- Saturation at box9 has two shapes with the same cause (cluster coarser
    -- than the fine window reaches): the crossing lands inside the last half
    -- lag (est >= max_lag - 0.5), or the curve never crosses within max_lag
    -- (est nil, why=garbage-curve-no-crossing). Both are the "correlation
    -- still alive at max lag" case the box17 retry exists for; the field log
    -- shows 736 no-crossing HOLDs that went straight to HOLD without it.
    local sat9 = (est ~= nil and est >= GS.max_lag - 0.5)
        or (est == nil and GS.nil_why == "garbage-curve-no-crossing")
    if sat9 then
        local HP17, m17 = highpass(17)
        GS.nil_why = nil  -- the retry supersedes box9's tag; box17 reports fresh
        local est2, mult2, share2, vsrc2 = measure(HP17, m17, 17)
        if est2 and est2 < GS.max_lag - 0.5 then
            est, mult, share, vsrc = est2, mult2, share2, vsrc2
        elseif est2 then
            est = nil  -- box17's crossing also sits at the rail: coarse, unresolved
            GS.nil_why = "garbage-curve-coarse-unresolved"
        else
            est = nil
            GS.nil_why = GS.nil_why or "garbage-curve-coarse-unresolved"
        end
    end
    if est ~= nil or mult ~= nil then
        GS.accepted_capture_tuple = {consistency=capture_tuple,
            position_before=capture_tuple.observed_playback_position,
            position_after=after_tuple.observed_playback_position,
            observed_started=capture_started, observed_finished=capture_finished,
            frame_height=h, crop_width=cw, crop_height=ch,
            frame_pts_status="UNAVAILABLE", shader_plane_status="UNVERIFIED"}
    end
    return est, mult, h, frame_luma, share, vsrc
end

-- PAIRED FLICKER VOTE: capture a second frame a few frames after the
-- probe sample and correlate the kept-block HP signatures of the pair.
-- Live grain re-randomizes between frames (s ~ 0); MPEG blocking and
-- frozen content persist (s ~ 1). The pair is close enough that normal
-- playback motion cannot wash the vote out - the failure mode that let
-- the field's DVD walk to the ceiling at n=8 (the 4s chain's vote was
-- absent or decorrelated by content drift). Returns s, or nil when no
-- vote exists (capture failed, resolution changed, cut between frames,
-- or fewer than 4 overlapping blocks): no vote, no extreme.
function GS.pair_flicker()
    local pair = GS.pair
    if not pair then return nil end
    local L2, cw2, ch2, luma2 = GS.capture_luma()
    if not L2 then return nil end
    if cw2 ~= pair.cw or ch2 ~= pair.ch then return nil end
    local base = math_max(pair.luma, 1.0)
    if math_abs(luma2 - pair.luma) / base > GS.luma_jump then return nil end  -- cut between frames
    local HP2 = GS.highpass(L2, cw2, ch2, 9)
    local sw, sc, sn = 0.0, 0.0, 0
    for i = 1, #pair.sigs do
        local b = pair.sigs[i]
        local sig2 = GS.block_sig(HP2, cw2, b.bx, b.by)
        local ma, mb, va, vb, cab = 0.0, 0.0, 0.0, 0.0, 0.0
        for y = 1, 8 do for x = 1, 8 do
            ma = ma + b.sig[y][x]; mb = mb + sig2[y][x]
        end end
        ma = ma / 64.0; mb = mb / 64.0
        for y = 1, 8 do for x = 1, 8 do
            local da, db = b.sig[y][x] - ma, sig2[y][x] - mb
            va = va + da * da; vb = vb + db * db; cab = cab + da * db
        end end
        if va > 1e-9 and vb > 1e-9 then
            local w = math.min(va, vb)
            sw = sw + w; sc = sc + (cab / math.sqrt(va * vb)) * w; sn = sn + 1
        end
    end
    if sw <= 0 or sn < 4 then return nil end
    return sc / sw
end


local function gs_median(t)
    local n = #t
    if n == 0 then return nil end
    local s = {}
    for i = 1, n do s[i] = t[i] end
    table.sort(s)
    if n % 2 == 1 then return s[(n + 1) / 2] end
    return (s[n / 2] + s[n / 2 + 1]) / 2
end

function GS.look_file()
    if GS.look_path == nil then
        local ok, path = pcall(mp.command_native, {"expand-path", "~~state/gor_look.txt"})
        GS.look_path = (ok and type(path) == "string" and path ~= "") and path or false
    end
    return GS.look_path
end
function GS.load_look()
    local path = GS.look_file()
    if not path then return end
    local f = io.open(path, "r")
    if not f then return end
    local v = tonumber(f:read("*l"))
    f:close()
    if v and v > 0 and v < 100 then GS.look_R = v end
end
function GS.save_look()
    local path = GS.look_file()
    if not path or not GS.look_R then return end
    local f = io.open(path, "w")
    if not f then return end
    f:write(string.format("%.4f\n", GS.look_R))
    f:close()
end
GS.load_look()
-- Explicit reset: forget the learned look and delete its file (back to the seed).
mp.register_script_message("photon-look-reset", function()
    GS.look_R = nil
    GS.look_learn = nil
    local path = GS.look_file()
    if path then os.remove(path) end
    mp.msg.info("photon: learned look reset; seed look applies")
end)

function GS.log_sample_contract()
    if not SIZE_GOV.program_on or GS.contract_logged then return end
    GS.contract_logged = true
    GS.sample_contract = mp.get_property_native("video-dec-params") or {}
    GS.sample_codec = mp.get_property("video-codec") or "unknown"
    GS.sample_format = mp.get_property("video-format") or "unknown"
    mp.msg.info(string.format(
        "photon: GS sample contract - decoder=%sx%s format=%s bpp=%s matrix=%s transfer=%s codec=%s format-id=%s provenance=post-render screenshot-raw; size neutral until confident source evidence",
        tostring(GS.sample_contract.w or "unknown"), tostring(GS.sample_contract.h or "unknown"),
        tostring(GS.sample_contract.pixelformat or "unknown"), tostring(GS.sample_contract["average-bpp"] or "unknown"),
        tostring(GS.sample_contract.colormatrix or "unknown"), tostring(GS.sample_contract.gamma or "unknown"),
        GS.sample_codec, GS.sample_format))
end

function DOC.log_header()
    if DOC.header then return end
    DOC.header = true
    DOC.append("photon-grain-size.log", string.format(
        "%s HEADER floor=%.2f window=%d deadband=%.2f slew=%.2f look_R=%.3f look_src=%s",
        os.date("%Y-%m-%dT%H:%M:%S%z"), GS.mult_floor, GS.window,
        GS.mult_deadband, GS.mult_slew, GS.look_R or GS.look_seed,
        GS.look_R and "learned" or "seed"))
end
function DOC.on_loaded()
    DOC.gen = DOC.gen + 1
    DOC.name = DOC.sanitize(mp.get_property("path"))
    DOC.active = true
    DOC.logged = false
    DOC.log_header()
    mp.commandv("script-message", "photon-grain-doc", tostring(DOC.gen), DOC.name)
end
function DOC.on_restart()
    if not DOC.active or DOC.logged then return end
    DOC.logged = true
    DOC.append("photon-grain-doc.log", string.format("%s doc_gen=%d file=%q",
        os.date("%Y-%m-%dT%H:%M:%S%z"), DOC.gen, DOC.name))
end

-- Evidence recorder window (display only). Counts PUBLISHED PROBES only: calls that reach
-- GS.publish_probe past the existing COST.media_telemetry gate, before the print throttle.
-- Reads existing values only; no governor input, threshold, table or flag is touched.
GS.evrec = {gen = nil}
function GS.evrec_reset(gen)
    GS.evrec = {gen = gen, n = 0, measured = 0, strength_only = 0, reason = 0, other = 0,
        outside = 0, unknown = 0, emin = nil, emax = nil, t0 = nil, t1 = nil}
end
-- Known-finite test on the RAW value. A finite -1 is a known value, not the printed nil fallback.
function GS.evrec_finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
function GS.evrec_count(est, mult, now)
    local r = GS.evrec
    if r.gen ~= DOC.gen or r.n == nil then GS.evrec_reset(DOC.gen); r = GS.evrec end
    r.n = r.n + 1
    -- Outcome class follows the same source priority as `status`, not any string prefix.
    if est then r.measured = r.measured + 1
    elseif mult then r.strength_only = r.strength_only + 1
    elseif GS.nil_why then r.reason = r.reason + 1
    else r.other = r.other + 1 end
    local e = GS.last_eff
    if GS.evrec_finite(e) then
        if e < GS_SYN_S[1] or e > GS_SYN_S[#GS_SYN_S] then r.outside = r.outside + 1 end
        if r.emin == nil or e < r.emin then r.emin = e end
        if r.emax == nil or e > r.emax then r.emax = e end
    else
        r.unknown = r.unknown + 1
    end
    if r.t0 == nil then r.t0 = now end
    r.t1 = now
end
function GS.evrec_fields()
    local r = GS.evrec
    return string.format("evrec_gen=%d evrec_n=%d evrec_measured=%d evrec_strength_only=%d evrec_reason=%d evrec_other=%d evrec_outside_table=%d evrec_eff_unknown=%d evrec_eff_min=%s evrec_eff_max=%s evrec_t0=%.1f evrec_t1=%.1f",
        r.gen, r.n, r.measured, r.strength_only, r.reason, r.other, r.outside, r.unknown,
        r.emin and string.format("%.3f", r.emin) or "none", r.emax and string.format("%.3f", r.emax) or "none",
        r.t0 or 0, r.t1 or 0)
end

-- Display/evidence only: does not change any governor input or threshold.
function GS.publish_probe(est, mult, h)
    local status = est and "measured" or (mult and "strength-only" or (GS.nil_why or "estimator-nil-after-measure"))
    mp.commandv("script-message", "photon-grain-measure-status", status)
    if not COST.media_telemetry then return end
    local now = mp.get_time()
    GS.evrec_count(est, mult, now)
    if GS.inputs_log_at and now - GS.inputs_log_at < 10 then return end
    GS.inputs_log_at = now
    COST.diag_mirror("GS INPUTS", string.format("h=%s eff_h=%s eff=%.3f size_rendered=%.3f size_coefficient=%s soft=%.3f gr_age=%.1f gr_en=%s is_hdr=%s adaptive_mode=%s crop=%sx%s shot_ok=%s %s why=%s",
        tostring(h or GS.shot_h), tostring(GR.effective_h), GS.last_eff or -1, GR.size_rendered or -1,
        tostring(GR.size_coefficient), GR.soft_rendered or -1, now - GR.ts, tostring(GR.enabled), tostring(is_hdr),
        tostring(GR.adaptive_mode), tostring(GS.crop_w), tostring(GS.crop_h), tostring(GS.shot_ok), GS.evrec_fields(), GS.nil_why or status))
    GS.evrec_reset(DOC.gen)
end

local function gs_tick()
    -- Same wall-clock gate as rg_tick (P0-3).
    if not (enabled and playback_active and DOC.active) then return end
    local tick_gen = DOC.gen
    local tick_control_revision = GR.control_revision
    common.trace_record("probe-start", {generation=tick_gen, revision=tick_control_revision or "unbound"})
    -- Stall guards (v14): a cache underrun keeps playback_active true
    -- while the same frame repeats, so the probe kept sampling and
    -- committed three escalating sizes mid-buffering (field run 1).
    -- No sampling and no committing on a frozen image.
    if RADAR_STATE.stream_frozen() then SIZE_GOV.hold("live","cache-stall"); return end
    local gs_pos = mp.get_property_number("time-pos")
    if gs_pos and GS.last_pos == gs_pos then SIZE_GOV.hold("live","time-pos-frozen"); return end
    GS.last_pos = gs_pos
    GS.log_sample_contract()
    local est, mult, frame_h, frame_luma, share, vsrc = gs_sample_frame()
-- PHOTON TELEMETRY ADDITION BEGIN
    if COST.media_telemetry then
    COST.trace_record("GRAIN_MEASUREMENT",{doc_gen=tick_gen,est=est,mult=mult,
        frame_h=frame_h,frame_luma=frame_luma,share=share,var_src=vsrc})
    end
-- PHOTON TELEMETRY ADDITION END
    -- Fence: a sample that finished after the document changed is dropped.
    if tick_gen ~= DOC.gen or not DOC.active then return end
    common.trace_record("probe-result", {generation=tick_gen, revision=tick_control_revision or "unbound",
        current_revision=GR.control_revision or "unbound", estimate=est or "none", multiplier=mult or "none"})
    GS.publish_probe(est, mult, frame_h)
    -- Scene cut: frame luma jumped hard - the HP plane is content, not
    -- grain, on a cut frame. Skip it; the window clears so the next scene
    -- re-estimates, but the last committed hint holds through the gap.
    if frame_luma and GS.prev_luma then
        local base = math_max(GS.prev_luma, 1.0)
        if math_abs(frame_luma - GS.prev_luma) / base > GS.luma_jump then
            -- DRAFT v2: samples are ~4 s apart, a luma step between them is not a
            -- cut (pan, fade, exposure). Skip THIS sample only; keep the windows
            -- so the estimate can fill. Reason renamed so logs stay distinguishable.
            GS.prev_luma = frame_luma
            GS.pair = nil
            SIZE_GOV.hold("live","luma-step",share)
            return
        end
    end
    if frame_luma then GS.prev_luma = frame_luma end

    -- STRENGTH top-up rides every valid sample (never waits on size):
    -- fill = target body - what the source already carries.
    -- B2: median of the last GS.window valid samples of this scene, deadband
    -- against the last applied value, slew-limited step. First apply of a
    -- document is unslewed (nothing to slew from).
    -- LOOK learning: if the engine's strength no longer matches what we sent,
    -- he changed it by hand. The frame he is looking at is the look: record the
    -- measured total/basis ratio over a few samples and adopt it as the set point.
    if SIZE_GOV.program_on and GS.last_mult and GR.enabled and GS.r_total then
        -- Numeric disagreement is not user intent: receiver defaults, rounding,
        -- or an automatic multiplier can differ without a manual control.
        -- Only the receiver's explicit manual source and control revision may
        -- authorize learning. Unknown/older mirrors keep the current look.
        local revision = GR.control_revision
        local manual = GR.strength_source == "manual" and GS.tuple_identity(revision)
            and revision > 0 and revision ~= GS.look_consumed_revision
        if manual then
            if GS.look_learn_revision ~= revision then
                GS.look_learn = nil
                GS.look_learn_revision = revision
            end
            GS.look_learn = GS.look_learn or {}
            GS.look_learn[#GS.look_learn + 1] = GS.r_total
            if #GS.look_learn >= 3 then
                GS.look_R = gs_median(GS.look_learn)
-- PHOTON TELEMETRY ADDITION BEGIN
    if COST.media_telemetry then
                COST.trace_record("LEGACY_NUMERIC_LEARN",{doc_gen=DOC.gen,
                    look_R=GS.look_R,strength=GR.strength,manual_identity_available=false})
    end
-- PHOTON TELEMETRY ADDITION END
                GS.look_learn = nil
                GS.look_consumed_revision = revision
                GS.look_learn_revision = nil
                GS.save_look()
                GS.last_mult = GR.strength / GS.strength_default
                GS.mhist = {}
                -- hand control back to the measurement: the manual value is now
                -- the learned look, so auto strength resumes from it.
                mp.commandv("script-message", "photon-grain-strength-resume",
                    tostring(DOC.gen), DOC.name)
                DOC.append("photon-grain-size.log", string.format(
                    "%s doc_gen=%d file=%q LOOK-LEARNED look_R=%.3f (from manual strength %.2f)",
                    os.date("%Y-%m-%dT%H:%M:%S%z"), DOC.gen, DOC.name, GS.look_R, GR.strength))
            end
            return
        else
            GS.look_learn = nil
            GS.look_learn_revision = nil
        end
    end
    -- 118h: a real noise reading feeds the scene feed (see
    -- photon_publish_scene_feed). share = source-noise share of measured
    -- HP power, the same validity rule the receiver's measured flag uses.
    if (vsrc or 0) > 0 and (share or 0) >= GS.src_share_min then
        GS.last_noise_share = share
        GS.last_noise_at = mp.get_time()
    else
        -- 118h: an invalid reading clears the cache at once - the feed
        -- must never republish a stale share as current. The 12s
        -- freshness window in publish is only a backstop for
        -- paused/frozen playback, where no new sample exists.
        GS.last_noise_share = nil
        GS.last_noise_at = nil
    end
    if mult then
        -- 118c (adaptive program only): the multiplier is relative to the
        -- delivered b7 look (x1.0 = GRAIN_STRENGTH_USER_DEFAULT). A valid
        -- noise reading moves it inside [0.5, 1.5], never zero. With no
        -- valid reading (over-corrected source power / source share below
        -- floor) the strength is the b7 look exactly - not a fixed
        -- 1.25/2.141 fallback. Legacy (program OFF) path unchanged.
        local measured = (vsrc or 0) > 0 and (share or 0) >= GS.src_share_min
        if measured or not SIZE_GOV.program_on then
            GS.mhist[#GS.mhist + 1] = SIZE_GOV.program_on and math_max(0.5, math_min(1.5, mult)) or mult
            if #GS.mhist > GS.window then table.remove(GS.mhist, 1) end
        end
        local target = (SIZE_GOV.program_on and not measured) and 1.0 or gs_median(GS.mhist)
        local nxt = nil
        if SIZE_GOV.program_on and not measured then
            -- No noise reading: return to the b7 look directly; slewing
            -- toward it would defend a value no measurement supported.
            if not GS.last_mult or math_abs(1.0 - GS.last_mult) > GS.mult_deadband then nxt = 1.0 end
        elseif not GS.last_mult then
            nxt = target
        elseif math_abs(target - GS.last_mult) / math_max(GS.last_mult, 0.05) > GS.mult_deadband then
            local d = target - GS.last_mult
            if d > GS.mult_slew then d = GS.mult_slew elseif d < -GS.mult_slew then d = -GS.mult_slew end
            nxt = GS.last_mult + d
        end
        if nxt then
            if SIZE_GOV.program_on then
                nxt = math_max(0.5, math_min(1.5, nxt))
            else
                nxt = math_max(GS.legacy_min, math_min(GS.legacy_max, nxt))
            end
            mp.commandv("script-message", "photon-grain-set-strength-mult",
                string.format("%.4f", nxt), tostring(DOC.gen), DOC.name,
                string.format("%.4f", vsrc or 0), string.format("%.3f", share or 0), tostring(#GS.mhist),
                ((vsrc or 0) > 0 and (share or 0) >= GS.src_share_min) and "1" or "0", tostring(tick_control_revision or ""))
            GS.last_mult = nxt
-- PHOTON TELEMETRY ADDITION BEGIN
    if COST.media_telemetry then
            COST.trace_record("LEGACY_SEND_INTENT",{doc_gen=DOC.gen,mult=nxt,
                receiver_ack_available=false,accepted_strength_unknown=true})
    end
-- PHOTON TELEMETRY ADDITION END
        end
    end

    if not est then
        SIZE_GOV.hold("live", string.format("no-estimate why=%s mult=%s gr_age=%.1f gr_en=%s soft=%.2f size=%.2f h=%s",
            GS.nil_why or "estimator-nil-after-measure", mult and string.format("%.3f", mult) or "none",
            mp.get_time() - GR.ts, tostring(GR.enabled), GR.soft_rendered or -1, GR.size_rendered or -1,
            tostring(frame_h)), share)
        return
    end
    GS.samples = GS.samples + 1
    GS.hist[#GS.hist + 1] = { e = est, s = share or 0.0 }
    if #GS.hist > GS.window then table.remove(GS.hist, 1) end
    if #GS.hist < GS.window then SIZE_GOV.hold("live","window-filling",share); return end
    local ests, min_share = {}, 1.0
    for i = 1, #GS.hist do
        ests[i] = GS.hist[i].e
        if GS.hist[i].s < min_share then min_share = GS.hist[i].s end
    end
    GS.est = gs_median(ests)
    -- hint against GRAIN_SIZE_BASE (1.2px HD ref): express the native-res
    -- estimate in 1080p-equivalent px, then ratio against the knob.
    -- Normalize by the probe's own frame height (screenshot-raw), never
    -- a video-params property: the property answered 480 for a
    -- 3840x1920 file and pinned the hint at max. Self-consistent only.
    local est_hd = GS.est * (1080 / frame_h)
    local raw_hint = est_hd / 1.2
    -- GS measures; the governor owns all gates, stepping, logging and send.
    local prior = SIZE_GOV.applied or SIZE_GOV.seed
    local needs_vote = SIZE_GOV.program_on or raw_hint > 2.2 or (prior and raw_hint > prior * 1.05)
    local pair_s = needs_vote and GS.pair_flicker() or nil
    if SIZE_GOV.propose("live", raw_hint,
        {share=min_share, vote=pair_s, frame_h=frame_h, reason="gs-probe", window=GS.window}) then
        mp.msg.info(string.format(
            "photon: grain-size probe — src=%.2fpx native (%.2f HD-ref) → hint=%.3f (n=%d, share=%.2f, vote=%s)",
            GS.est, est_hd, SIZE_GOV.applied, GS.samples, min_share,
            pair_s and string.format("%.2f", pair_s) or "none"))
        gr_gs_committed_hint = true
    end
end

-- No queued catch-up work after a slow ON sample/vote. OFF keeps the old cadence.
function GS.paced_tick()
    if not SIZE_GOV.program_on then gs_tick(); return end
    if GS.probe_running or (GS.next_probe_at and mp.get_time() < GS.next_probe_at) then return end
    GS.probe_running = true
    GS.probe_started = mp.get_time()
    GS.probe_ok, GS.probe_error = pcall(gs_tick)
    GS.probe_running = false
    if not GS.probe_ok then
        mp.msg.warn("photon: GS sample failed; next paced attempt remains enabled: " .. tostring(GS.probe_error))
    end
    if mp.get_time() - GS.probe_started > GS.interval then
        GS.next_probe_at = mp.get_time() + GS.interval
    else
        GS.next_probe_at = GS.probe_started + GS.interval
    end
end

GS.timer = mp.add_periodic_timer(GS.interval, GS.paced_tick)

-- 118b: the size decision is made at once, never after a wait - the 5s
-- bound is met by construction, not by a timer. At start (and when the
-- adaptive program is toggled on) commit the resolution-based size
-- provisionally (hint x1.0 - the receiver's raster coefficient scales the
-- base to the output), log the reason once per document, and the HUD
-- leaves "awaiting" immediately. The provisional value is NOT a governor
-- decision: SIZE_GOV.applied stays nil, so the first real measurement
-- still runs the governor's seeded first-commit path and refines the size
-- (last writer wins on the receiver). No new top-level locals: the main
-- chunk sits at the 200-local Lua limit.
SIZE_GOV.fallback_logged = false
function SIZE_GOV.commit_resolution_fallback(why)
    if not SIZE_GOV.program_on then return end
    if not SIZE_GOV.fallback_logged then
        SIZE_GOV.fallback_logged = true
        gs_log("COMMIT", "resolution-fallback", 1.0, 1.0, nil, nil,
            "provisional resolution-based size at " .. (why or "start") .. " (hint x1.0); live samples refine it")
    end
    SIZE_GOV.fallback_sent = true
    mp.commandv("script-message", "photon-grain-set-size-hint", "1.0000")
    mp.commandv("script-message", "photon-grain-size-evidence", "resolution-fallback")
end


local function bk_finalize(is_reprobe)
    local sp, sq = 0.0, 0.0
    for _, smp in ipairs(BK.samples) do
        sp = sp + smp.pair; sq = sq + smp.quilt
    end
    local pair  = sp / #BK.samples
    local quilt = sq / #BK.samples
    local pair_score  = smoothstep(1.35, 2.30, pair)
    local quilt_score = smoothstep(1.50, 3.00, quilt)
    local sample_block = math_max(pair_score, quilt_score)
    -- keep the worst reading: a clean segment must not wash out a harsh one
    photon_scene_block = math_max(photon_scene_block, sample_block)
    if is_reprobe then
        mp.msg.info(string.format(
            "photon: block re-probe #%d — pair=%.3f quilt=%.3f (n=%d) → sample=%.3f, file level=%.3f",
            BK.reprobes, pair, quilt, #BK.samples, sample_block, photon_scene_block))
    else
        mp.msg.info(string.format(
            "photon: block probe done — pair=%.3f quilt=%.3f (n=%d) → block=%.3f",
            pair, quilt, #BK.samples, photon_scene_block))
    end
end

-- Re-probe cadence counts PLAYBACK seconds, not wall seconds (P0-3): a
-- paused evening must not fire a probe burst on resume. The 5s cadence
-- is a boolean check while paused; only active playback accumulates.
local function bk_schedule_reprobe()
    if BK.timer then BK.timer:kill(); BK.timer = nil end
    BK.timer = mp.add_periodic_timer(5.0, function()
        if not (enabled and playback_active) then return end
        BK.play_elapsed = (BK.play_elapsed or 0) + 5.0
        if BK.play_elapsed >= BK.reprobe_interval then
            if BK.timer then BK.timer:kill(); BK.timer = nil end
            bk_reprobe()
        end
    end)
end

local function bk_run_probe()
    if BK.running or BK.done then return end
    if not enabled then return end  -- P0-3: no probe work while toggled off
    BK.running = true
    BK.samples = {}
    BK.gen = BK.gen + 1
    local my_gen = BK.gen
    local collected = 0

    local function tick()
        if BK.gen ~= my_gen then return end
        -- Paused or toggled off: a frozen frame is not a new measurement.
        -- Don't sample, don't count the tick, just re-arm (P0-3).
        if not (enabled and playback_active) then
            BK.timer = mp.add_timeout(BK.interval, tick)
            return
        end
        local s = bk_sample_frame()
        if BK.gen ~= my_gen then return end
        if s then BK.samples[#BK.samples + 1] = s end
        collected = collected + 1
        if collected >= BK.count then
            if BK.timer then BK.timer:kill() end
            BK.timer = nil
            BK.running = false
            BK.done = true
            if #BK.samples > 0 then
                bk_finalize(false)
            else
                mp.msg.warn("photon: block probe failed, no samples collected")
            end
            if BK.gen ~= my_gen then return end
            bk_schedule_reprobe()
            return
        end
        BK.timer = mp.add_timeout(BK.interval, tick)
    end
    tick()
end

-- Re-probe: the opening probe only sees ~20s of a file; a clean logo or
-- title card would otherwise issue a clean bill for the whole runtime.
-- Re-samples a few frames every BK.reprobe_interval seconds of playback
-- (screenshot-raw on live frames, so torrent streams are unaffected) and
-- bk_finalize keeps the worst reading.
bk_reprobe = function()
    if BK.running then return end
    BK.running = true
    BK.samples = {}
    BK.gen = BK.gen + 1
    local my_gen = BK.gen
    local collected = 0
    local function tick()
        if BK.gen ~= my_gen then return end
        -- Paused or toggled off: a frozen frame is not a new measurement.
        -- Don't sample, don't count the tick, just re-arm (P0-3).
        if not (enabled and playback_active) then
            BK.timer = mp.add_timeout(BK.interval, tick)
            return
        end
        local s = bk_sample_frame()
        if BK.gen ~= my_gen then return end
        if s then BK.samples[#BK.samples + 1] = s end
        collected = collected + 1
        if collected >= BK.reprobe_count then
            if BK.timer then BK.timer:kill() end
            BK.timer = nil
            BK.running = false
            BK.reprobes = BK.reprobes + 1
            if #BK.samples > 0 then
                bk_finalize(true)
            end
            if BK.gen ~= my_gen then return end
            bk_schedule_reprobe()
            return
        end
        BK.timer = mp.add_timeout(BK.interval, tick)
    end
    tick()
end

-- Extracts raw YAVG and a neighbor-diff (high-frequency approximation)
-- from a single screenshot-raw frame. Same bgr0/stride contract as
-- sample_screenshot_raw but kept separate — the output type differs
local gr_sample_live_frame
do
local function gr_sample_live_frame_raw()
    local ok, shot = COST.shot()
    if not ok or not shot or not shot.data or not shot.w or not shot.h then
        return nil
    end
    if type(shot.data) ~= "string" then return nil end
    local data, w, h = shot.data, shot.w, shot.h
    local stride = shot.stride or (w * 4)

    -- Collect luma values on the grid (bgr0: B,G,R,X byte order, same
    -- contract as sample_screenshot_raw).
    local luma_grid = {}
    for gy = 0, LG.grid - 1 do
        luma_grid[gy] = {}
        for gx = 0, LG.grid - 1 do
            local x = math_floor((gx + 0.5) * w / LG.grid)
            local y = math_floor((gy + 0.5) * h / LG.grid)
            local idx = y * stride + x * 4
            local b, g, r = string.byte(data, idx + 1, idx + 3)
            if r and g and b then
                -- Rec.601 luma approximation — same physical quantity as
                -- signalstats YAVG (weighted luma average).
                luma_grid[gy][gx] = 0.299 * r + 0.587 * g + 0.114 * b
            end
        end
    end

    -- raw: mean luma across the grid (signalstats YAVG equivalent).
    local sum, n = 0.0, 0
    for gy = 0, LG.grid - 1 do
        for gx = 0, LG.grid - 1 do
            local v = luma_grid[gy][gx]
            if v then sum = sum + v; n = n + 1 end
        end
    end
    if n == 0 then return nil end
    local raw_avg = sum / n

    -- hp: mean absolute difference between horizontally and vertically
    -- neighboring grid lumas — cheap Lua equivalent of unsharp's
    -- high-frequency isolation. Small on flat areas, large on textured
    local diff_sum, diff_n = 0.0, 0
    for gy = 0, LG.grid - 1 do
        for gx = 0, LG.grid - 1 do
            local v = luma_grid[gy][gx]
            if v then
                local right = luma_grid[gy][gx + 1]
                local down  = luma_grid[gy + 1] and luma_grid[gy + 1][gx]
                if right then diff_sum = diff_sum + math_abs(right - v); diff_n = diff_n + 1 end
                if down  then diff_sum = diff_sum + math_abs(down  - v); diff_n = diff_n + 1 end
            end
        end
    end
    if diff_n == 0 then return nil end
    local hp_diff = diff_sum / diff_n

    return { raw = raw_avg, diff = hp_diff }
end
gr_sample_live_frame = COST.wrap("LG", gr_sample_live_frame_raw)
end

-- seconds apart (screenshot-raw, no network/subprocess), averages the
-- diff, and hands it to gr_finalize_grain_analysis. Shares the
local function gr_run_live_grain_probe()
    if not DOC.active then return end
    if grain_analysis_running or grain_size_hint_sent then return end
    if not is_live then return end

    grain_analysis_running = true
    LG.samples = {}
    -- New generation: a number specific to this call. tick() captures it
    LG.gen = LG.gen + 1
    local my_gen = LG.gen
    local collected = 0

    local function tick()
        if LG.gen ~= my_gen then return end  -- old generation, cancelled
        local s = gr_sample_live_frame()
        if LG.gen ~= my_gen then return end  -- screenshot-raw may resolve
                                              -- async; re-check after it resolves.
        if s then LG.samples[#LG.samples + 1] = {d = s.diff, r = s.raw} end
        collected = collected + 1
        if collected >= LG.count then
            if LG.timer then LG.timer:kill() end
            LG.timer = nil
            grain_analysis_running = false
            grain_size_hint_sent = true
            if #LG.samples == 0 then
                mp.msg.warn("photon: live grain-probe failed, no frames sampled")
                return
            end
            local sum_d, sum_r = 0.0, 0.0
            for _, v in ipairs(LG.samples) do
                sum_d = sum_d + v.d
                sum_r = sum_r + v.r
            end
            local avg_diff = sum_d / #LG.samples
            local avg_raw  = sum_r / #LG.samples
            -- CAVEAT: this neighbor-diff method and the ffmpeg
            -- unsharp-YAVG method isolate different high-frequency bands,
            -- so even in relative units the live path's rel runs its own
            -- scale. Normalizing by raw luma removes the brightness/HDR
            -- distortion from both, but live thresholds may still want
            -- their own calibration once real live streams are measured.
            gr_finalize_grain_analysis(avg_diff, #LG.samples, "live-screenshot", avg_raw)
        end
    end

    tick()  -- first sample immediately, rest periodic
    if LG.gen == my_gen and collected < LG.count then
        LG.timer = mp.add_periodic_timer(LG.interval, function()
            if LG.gen ~= my_gen then return end  -- old generation, cancelled
            if not (enabled and playback_active) then return end  -- P0-3: no sample, no count while paused/off
            tick()
            if LG.gen == my_gen and LG.timer and collected >= LG.count then
                LG.timer:kill()
                LG.timer = nil
            end
        end)
    end
end

--  RADAR ENGINE

local function dispatch_radar()
    local path = mp.get_property("path")
    -- v14: hold the queue while the stream is starved (same underrun
    -- collision as the sdr probe); workers resume when playback does.
    if RADAR_STATE.stream_frozen() then return end
    if is_network_slow or RADAR_STATE.url_dead then return end  -- v15
    -- 118j: bound probe overlap by measured probe wall time. On a slow
    -- source (network/loopback: one -ss probe takes seconds) two
    -- permanent workers plus a 0.05s respawn held ffmpeg at ~2 cores
    -- continuously (field: radar=26 spawns/10s, 25-130s wall per 10s
    -- window). Slow probes self-limit to one at a time, spawned no
    -- faster than they complete; fast local files keep the original
    -- parallelism and throttle. Same queue, same priorities, same
    -- coverage - only the overlap is bounded.
    local wall_ema = RADAR_STATE.probe_wall_ema
    local max_workers = (is_network_slow or (wall_ema and wall_ema > 1.0)) and 1 or ANALYSIS_PARALLEL
    if not path or not is_sdr or RADAR_STATE.active_workers >= max_workers or #RADAR_STATE.pending_queue == 0 then return end
    if is_live then return end

    local now = mp.get_time()
    local throttle = math.max(DISPATCH_THROTTLE, wall_ema or 0)
    if now - RADAR_STATE.last_dispatch_t < throttle then return end
    RADAR_STATE.last_dispatch_t = now

    table.sort(RADAR_STATE.pending_queue, function(a, b) return a.priority < b.priority end)

    local job = table.remove(RADAR_STATE.pending_queue, 1)
    RADAR_STATE.in_pending[job.t] = nil
    RADAR_STATE.active_workers = RADAR_STATE.active_workers + 1
    job.spawned_at = now
    local worker_generation = RADAR_STATE.worker_generation

    COST.ff_inc("radar")
    local cmd = string.format(
        FFMPEG .. RADAR_STATE.net_opts() .. " -v 0 -nostats -threads 1 -hwaccel auto -ss %.3f -i %s -vframes 1 " ..
        -- -m 6: UAVG added for the warmth field (see calc_frame_profile's
        -- n_warmth comment). UAVG appears BEFORE HUEAVG in ffmpeg's
        -- stream order, so -m must cover 6 lines, not 5 — match order
        "-vf \"scale=128:-1,signalstats\" -f null - 2>&1",
        job.t, string.format("%q", path))

    mp.command_native_async({
        name = "subprocess", args = {"sh", "-c", cmd},
        capture_stdout = true, playback_only = false,
    }, function(success, res)
        -- An older file's probe may finish after file-loaded resets the
        -- counter and queue. Do not write its profile into this file.
        if worker_generation ~= RADAR_STATE.worker_generation then return end
        RADAR_STATE.active_workers = RADAR_STATE.active_workers - 1
        if job.spawned_at then
            local wall = mp.get_time() - job.spawned_at
            RADAR_STATE.probe_wall_ema = RADAR_STATE.probe_wall_ema
                and (0.7 * RADAR_STATE.probe_wall_ema + 0.3 * wall) or wall
        end
        RADAR_STATE.analyzed_times[job.t] = true
        if not success then
            mp.msg.warn("photon: radar subprocess failed at t=" .. job.t)
        elseif (not res) or (res.status or -1) ~= 0 then
            -- v14: surface ffmpeg's real error (tail), not just "failed".
            mp.msg.warn(string.format(
                "photon: radar probe error at t=%s (status=%s) — output tail: %s",
                tostring(job.t), tostring(res and res.status),
                (res and res.stdout and res.stdout ~= "" and res.stdout:sub(-200)) or "(empty)"))
        elseif res.stdout ~= "" then
            local profile = parse_frame_extended(res.stdout)
            if profile then buffer_insert(job.t, profile) end
        end
        mp.add_timeout(0.1, dispatch_radar)
    end)
end

local function flush_queue()
    RADAR_STATE.pending_queue = {}
    RADAR_STATE.in_pending    = {}
end

local function update_radar()
    if not is_sdr or not enabled then return end
    local pos      = mp.get_property_number("time-pos")
    local duration = mp.get_property_number("duration")
    if not pos or not duration then return end

    local gc_threshold = pos - GC_BEHIND
    -- PERF: RADAR_STATE.live_buffer is insertion-sorted by t (buffer_insert always
    -- binary-search-inserts), so RADAR_STATE.live_buffer[1] is always the oldest
    -- entry. If even the oldest entry is still within the GC window,
    if RADAR_STATE.live_buffer[1] and RADAR_STATE.live_buffer[1].t < gc_threshold then
        local new_buffer = {}
        for i = 1, #RADAR_STATE.live_buffer do
            if RADAR_STATE.live_buffer[i].t >= gc_threshold then
                new_buffer[#new_buffer + 1] = RADAR_STATE.live_buffer[i]
            else
                RADAR_STATE.analyzed_times[RADAR_STATE.live_buffer[i].t] = nil
            end
        end
        RADAR_STATE.live_buffer = new_buffer
    end

    -- Per-scene mini-calibration: live_buffer is already populated,
    -- so this adds no extra ffmpeg/subprocess cost.
    photon_sharp_update_scene_baseline(pos)

    -- v15: no background URL probes on network sources (screenshot feed
    -- fills the buffer as playback advances) or once the URL has 4xx'd.
    if is_network_slow or RADAR_STATE.url_dead then return end

    local velocity_norm = clamp(math.abs(SDR_STATE.pbs_velocity) / 15.0, 0, 1)
    local lookahead     = lerp(LOOKAHEAD_MIN, LOOKAHEAD_MAX, velocity_norm)
    local start_t       = math.floor(pos / ANALYSIS_INTERVAL) * ANALYSIS_INTERVAL
    local end_t         = math.min(start_t + lookahead, duration)

    for t = start_t, end_t, ANALYSIS_INTERVAL do
        local tk = math.floor(t * 10 + 0.5) / 10
        if not RADAR_STATE.analyzed_times[tk] and not RADAR_STATE.in_pending[tk] then
            local dist_pri = math.abs(tk - pos)
            local var_pri  = 100 - region_variance(tk)
            table.insert(RADAR_STATE.pending_queue, {t = tk, priority = dist_pri + var_pri * 0.1})
            RADAR_STATE.in_pending[tk] = true
        end
    end

    dispatch_radar()
end

--  PHOTON SCENE SMOOTHING — general-purpose EMA service
--  Lives here with a generic name, not in photon-sharp.lua, since
--  smoothing is a general service even though sharp is the only
local PHOTON_SCENE_TAU_ATTACK  = 0.70
local PHOTON_SCENE_TAU_RELEASE = 0.60
-- Same value as Category C's PHOTON_SHARP_REWRITE_INTERVAL (2.0) but
local PHOTON_SCENE_SMOOTH_INTERVAL = 2.0
local photon_scene_dyn_tau_release = nil
local photon_scene_last_smooth_t   = 0

-- asym_smooth defined in photon-common.lua — fix bugs there, not here.
local photon_scene_smooth = common.asym_smooth

-- Called at the common end of all 3 update_* paths, right before
-- photon_publish_scene_feed(). Updates smooth_peak/contrast/noise
-- against current raw values, so the feed carries real smoothed data.
local function photon_scene_update_smoothing()
    local now = mp.get_time()
    local dt = math_min(now - (photon_scene_last_smooth_t > 0 and photon_scene_last_smooth_t or now - PHOTON_SCENE_SMOOTH_INTERVAL), PHOTON_SCENE_SMOOTH_INTERVAL)
    photon_scene_last_smooth_t = now

    -- CUT BYPASS: on a real hard cut, snap straight to the raw value
    -- instead of easing into it — the same distinction photon-chrome.lua
    -- draws for ch_scene_hue_smoothed. Easing across a cut would smear
    if photon_scene_is_cut then
        photon_scene_smooth_peak     = photon_scene_peak
        photon_scene_smooth_contrast = photon_scene_contrast
        photon_scene_smooth_noise    = photon_scene_noise
        return
    end

    photon_scene_dyn_tau_release = PHOTON_SCENE_TAU_RELEASE * (1.0 - 0.25 * photon_scene_motion)
    photon_scene_dyn_tau_release = math_max(photon_scene_dyn_tau_release, PHOTON_SCENE_TAU_RELEASE * 0.25)

    photon_scene_smooth_peak = photon_scene_smooth(photon_scene_smooth_peak, photon_scene_peak,
        PHOTON_SCENE_TAU_ATTACK, photon_scene_dyn_tau_release, dt)
    photon_scene_smooth_contrast = photon_scene_smooth(photon_scene_smooth_contrast, photon_scene_contrast,
        PHOTON_SCENE_TAU_ATTACK, photon_scene_dyn_tau_release, dt)
    photon_scene_smooth_noise = photon_scene_smooth(photon_scene_smooth_noise, photon_scene_noise,
        PHOTON_SCENE_TAU_ATTACK * 0.5, photon_scene_dyn_tau_release * 0.5, dt)
end

-- PERF: FPS query stride — avoids polling container-fps/estimated-vf-fps/
-- fps on every tick. estimated-vf-fps can drift as playback timing
-- settles (a rolling window over the last ~10 frame durations), which is
local FPS_QUERY_STRIDE = 20
local fps_query_ticks_since = 0
-- nil, not a hardcoded default: forces an immediate real query on the
-- first call rather than reporting a stale 24.0 for the first
-- FPS_QUERY_STRIDE calls. Also keeps the mp.get_property_number calls
local cached_scene_fps = nil

--  PHOTON SCENE FEED — single broadcast point
--  Publishes photon's HDR/SDR/live scene signal (raw + smoothed) via a
--  single script-message. Adding a new consumer requires no change to
local photon_scene_kv_encode = common.scene_kv_encode

-- Grouped into one table to stay under Lua's 200 top-level-local limit
-- (same pattern as LG above).
-- Declared here, before its earliest reader: Lua resolves a name to
local LIVE_CALIB = {
    samples = {},
    warmup_misses = 0,
    profile = nil,
    last_capture = -math.huge,
    last_pbs = nil,
    last_profile_t = nil,
    capture_failed = false,
    cut_ramp = false,
    mode_logged = false,
    capture_interval = 2.5, -- seconds; 4K readback bounded, smoothing remains 4 Hz
}

-- Broadcasts raw HDR/SDR/scene numbers; photon-hud.lua builds the display
-- string itself, same as sharp/grain/chrome/negativ already do. Field
-- order must match the listener in photon-hud.lua exactly (positional).
-- Encode-time guard: a NaN or runaway value must never enter a broadcast
-- payload (the HUD/feed consumers format whatever arrives). Bounded values
-- pass through unchanged; garbage degrades to the fallback.
local function photon_safenum(x, fallback)
    if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge
        or math.abs(x) > 1e12 then
        return fallback
    end
    return x
end

local function photon_publish_hud_state()
    local out              = mp.get_property_native("video-out-params")
    local hdr_avg          = (out and out["avg-pq-y"]) or 0
    local hdr_max          = (out and out["max-pq-y"]) or 0
    local hdr_contrast     = math.max(0, hdr_max - hdr_avg)
    local hdr_cut_thr      = CUT_BASE * (0.5 + clamp(HDR_STATE.adapted_pq, 0, 0.6) * CUT_SCALE)
    local live_calib_ready = is_live and RADAR_STATE.calib_done

    mp.commandv("script-message", "photon-photon-hud-state",
        tostring(enabled),
        string.format("%.4f", photon_safenum(photon_scene_smooth_peak, 0.5)),
        string.format("%.4f", photon_safenum(photon_scene_smooth_contrast, 0.35)),
        string.format("%.4f", photon_safenum(photon_scene_smooth_noise, 0.1)),
        string.format("%.4f", photon_safenum(photon_scene_motion, 0.0)),
        tostring(photon_scene_has_feed),
        tostring(is_hdr),
        tostring(is_live),
        -- HDR fields (meaningless when is_hdr is false, HUD ignores them)
        string.format("%.4f", photon_safenum(HDR_STATE.adapted_peak, 203.0)),
        string.format("%.4f", photon_safenum(HDR_STATE.pq_velocity, 0.0)),
        string.format("%.4f", photon_safenum(hdr_avg, 0.35)),
        string.format("%.4f", photon_safenum(HDR_STATE.drive_pq, 0.35)),
        string.format("%.4f", photon_safenum(hdr_contrast, 0.1)),
        string.format("%.4f", photon_safenum(hdr_cut_thr, 0.16)),
        string.format("%.4f", photon_safenum(HDR_STATE.adapted_pq, 0.35)),
        string.format("%.4f", DARK_THRESH),
        string.format("%.4f", BRIGHT_THRESH),
        -- SDR fields (meaningless when is_hdr is true, HUD ignores them)
        string.format("%.4f", photon_safenum(SDR_STATE.adapted_pbs, 0.0)),
        string.format("%.4f", photon_safenum(SDR_STATE.pbs_velocity, 0.0)),
        string.format("%.4f", photon_safenum(SDR_STATE.adapted_gamma, 0.0)),
        string.format("%.4f", photon_safenum(RADAR_STATE.dynamic_neutral, 0.0)),
        tostring(live_calib_ready),
        string.format("%d", #LIVE_CALIB.samples),
        string.format("%d", CALIB_FRAMES),
        string.format("%d", #RADAR_STATE.live_buffer),
        tostring(RADAR_STATE.buffer_miss),
        -- RG probe fields (ring ratio + 0-1 damage level); appended last so
        -- older hud.lua builds simply never read them.
        string.format("%.4f", photon_safenum(photon_scene_ring, 0.0)),
        string.format("%.4f", photon_safenum(photon_scene_rlevel, 0.0)))
end

local function photon_publish_scene_feed()
    -- 118h: connect the grain noise feed to the GS probe's real
    -- measurement when fresh (<=12s). The radar/PQ proxies above only run
    -- when their own path is live; where no real reading exists the feed
    -- stays honestly off and grain falls back to the 118b/118c
    -- resolution-based values. Never label this path "measured".
    if GS.last_noise_at and (mp.get_time() - GS.last_noise_at) <= 12.0 then
        -- Raw AND smoothed: publish runs after the tick's smoothing pass, so
        -- retarget the smoothed value here or the receiver never sees it.
        local gs_noise = clamp(GS.last_noise_share or 0.10, 0.0, 1.0)
        photon_scene_noise = gs_noise
        photon_scene_smooth_noise = lerp(gs_noise, photon_scene_smooth_noise, 0.5)
        photon_scene_has_feed = true
    end
    fps_query_ticks_since = fps_query_ticks_since + 1
    if not cached_scene_fps or fps_query_ticks_since >= FPS_QUERY_STRIDE then
        fps_query_ticks_since = 0
        cached_scene_fps = mp.get_property_number("container-fps") or
                            mp.get_property_number("estimated-vf-fps") or
                            mp.get_property_number("fps") or 24.0
    end
    local payload = photon_scene_kv_encode({
        {"peak", photon_safenum(photon_scene_peak, 0.5), "num"},
        {"contrast", photon_safenum(photon_scene_contrast, 0.35), "num"},
        {"noise", photon_safenum(photon_scene_noise, 0.10), "num"},
        {"block", photon_safenum(photon_scene_block, 0.0), "num"},
        {"ring", photon_safenum(photon_scene_ring, 0.0), "num"},
        {"rlevel", photon_safenum(photon_scene_rlevel, 0.0), "num"},
        {"sat", photon_safenum(photon_scene_sat, -1.0), "num"},
        {"motion", photon_safenum(photon_scene_motion, 0.20), "num"},
        {"smooth_peak", photon_safenum(photon_scene_smooth_peak, 0.5), "num"},
        {"smooth_contrast", photon_safenum(photon_scene_smooth_contrast, 0.35), "num"},
        {"smooth_noise", photon_safenum(photon_scene_smooth_noise, 0.10), "num"},
        {"fps", photon_safenum(cached_scene_fps, 24.0), "num"},
        {"is_hdr", is_hdr, "bool"},
        {"is_cut", photon_scene_is_cut, "bool"},
        {"has_feed", photon_scene_has_feed, "bool"},
        -- Read only by sharp — produced by photon_sharp_update_scene_baseline,
        {"baseline_pbs", photon_sharp_scene_baseline_pbs, "num"},
        {"baseline_contrast", photon_sharp_scene_baseline_contrast, "num"},
        -- Can be nil (HDR path, or hue-less frames); if nil the key is
        -- omitted entirely, and the decoder's tonumber(nil-lookup) gives nil.
        {"hue", photon_scene_hue, "num"},
        -- Can be nil (HDR filter not yet configured, old ffmpeg lacking
        -- UAVG support, or a frame warmth genuinely can't be computed for).
        {"warmth", photon_scene_warmth, "num"},
    })
    mp.commandv("script-message", "photon-scene-feed", payload)

    -- This is the common exit point for all update_hdr/update_sdr/
    -- update_sdr_live paths, so publishing the HUD here covers every case.
    -- The scene feed above rides every tick (10Hz HDR), but the 29-field
    -- hud-state is display-only against a 4Hz redraw — cap it at 2Hz
    -- (A5). Toggles call photon_publish_hud_state directly, so user
    -- actions still publish immediately.
    local now_pub = mp.get_time()
    if now_pub - hud_state_last_pub >= 0.5 then
        hud_state_last_pub = now_pub
        photon_publish_hud_state()
    end
end

-- HDR hue: video-out-params only gives avg/max-pq-y by default, no per-
-- channel color, so hue needs two extra sources. SOURCE 1 (metadata,
-- below) is free but requires HDR10+ dynamic metadata; SOURCE 2

-- SOURCE 1: HDR10+ scene-max-r/g/b off the same video-out-params table
-- update_hdr already fetches. Returns (hue, warmth) or (nil, nil) if
local rgb_to_hue_deg = common.rgb_to_hue_deg

local function read_hdr_hue_from_metadata(out)
    local r, g, b = out["scene-max-r"], out["scene-max-g"], out["scene-max-b"]
    if not (r and g and b) then return nil, nil end
    -- Degenerate/near-black scene metadata (can legitimately be all-
    -- zero on a true-black scene) — avoid a 0/0 division below rather
    if r <= 0 and g <= 0 and b <= 0 then return nil, nil end
    -- Achromatic scene peak (R==G==B, e.g. a neutral-white highlight) —
    -- same "no meaningful hue" case signalstats' HUEAVG represents as
    -- absent for a near-gray frame; rgb_to_hue_deg already returns nil
    local h = rgb_to_hue_deg(r, g, b)
    local hue = h and clamp(h / 360.0, 0, 1) or nil
    -- warmth: R-vs-B balance of the scene's brightest region, same
    -- [-1, 1] convention as the SDR/UAVG-derived warmth elsewhere in
    -- this file (negative = cool/blue-leaning, positive = warm/red-
    local mx = math_max(r, g, b)
    local warmth = clamp((r - b) / mx, -1.0, 1.0)
    return hue, warmth
end

--  HDR HUE — SOURCE 2: mpv's own decoded frame (screenshot-raw)
--  Reads mpv's currently-decoded frame directly: no second network
--  connection, no seek argument to drift out of sync. flags="video"
local HDR_SAMPLE_GRID = 12  -- 144 points: cheap, dense enough that one
                            -- stray pixel can't skew the average.

-- circular_mean_hue: correct mean of a list of hue angles (0-360,
-- degrees) that respects the wraparound at 0/360 — implemented as the
-- angle of the mean unit vector (mean of cos/sin of each angle), the
local circular_mean_hue = common.circular_mean_hue


-- sample_screenshot_raw: does the actual mp.command_native call,
-- pixel sampling, and hue/warmth computation. Returns (hue_deg_or_nil,
-- warmth_or_nil). Never throws — any failure (command error, unexpected
local sample_screenshot_raw
do
local function sample_screenshot_raw_raw()
    local ok, shot = COST.shot()
    if not ok or not shot or not shot.data or not shot.w or not shot.h then
        return nil, nil
    end
    if type(shot.data) ~= "string" then
        -- Unexpected shape for this mpv build/binding — bail out
        -- cleanly rather than guessing at a different access pattern.
        return nil, nil
    end
    local data, w, h = shot.data, shot.w, shot.h
    local stride = shot.stride or (w * 4)
    -- bgr0: B is the LSB, i.e. byte order per pixel is B,G,R,X.
    -- byte_index (0-based) = y*stride + x*4, per mpv's own docs.
    local hues, warmth_sum, warmth_n = {}, 0.0, 0
    for gy = 0, HDR_SAMPLE_GRID - 1 do
        for gx = 0, HDR_SAMPLE_GRID - 1 do
            local x = math_floor((gx + 0.5) * w / HDR_SAMPLE_GRID)
            local y = math_floor((gy + 0.5) * h / HDR_SAMPLE_GRID)
            local idx = y * stride + x * 4  -- 0-based byte offset
            -- Lua strings are 1-indexed; string.byte's offsets are too.
            local b, g, r = string.byte(data, idx + 1, idx + 3)
            if r and g and b then
                local hue = rgb_to_hue_deg(r, g, b)
                if hue then hues[#hues + 1] = hue end
                warmth_sum = warmth_sum + (r - b)
                warmth_n = warmth_n + 1
            end
        end
    end
    if warmth_n == 0 then return nil, nil end
    local mean_hue = circular_mean_hue(hues)
    local warmth = clamp((warmth_sum / warmth_n) / 255.0, -1.0, 1.0)
    return mean_hue, warmth
end
sample_screenshot_raw = COST.wrap("HDRHUE", sample_screenshot_raw_raw)
end

-- read_hdr_hue_from_screenshot: public entry point for SOURCE 2. Throttled
-- throttled tick, returns whatever HDR_STATE.cached_hue/warmth already hold
local function read_hdr_hue_from_screenshot()
    if not enabled or not is_hdr then return nil, nil end
    local now = mp.get_time()
    if now - HDR_STATE.screenshot_last_t < HDR_SCREENSHOT_INTERVAL then
        return HDR_STATE.cached_hue, HDR_STATE.cached_warmth
    end
    HDR_STATE.screenshot_last_t = now
    local hue_deg, warmth = sample_screenshot_raw()
    if not hue_deg and not warmth then
        -- Nothing new this cycle — hold whatever was cached before
        -- (same contract as every other nil-producing path in this
        -- file), rather than collapsing a transient miss to nil.
        return HDR_STATE.cached_hue, HDR_STATE.cached_warmth
    end
    local hue = hue_deg and clamp(hue_deg / 360.0, 0, 1) or HDR_STATE.cached_hue
    local warmth_out = warmth or HDR_STATE.cached_warmth
    return hue, warmth_out
end

--  HDR UPDATE

local function update_hdr()
    if not enabled or not is_hdr then return end
    local out = mp.get_property_native("video-out-params")
    if not out then
        if photon_scene_has_feed then photon_scene_has_feed = false; photon_publish_scene_feed() end
        return
    end
    local avg_pq = out["avg-pq-y"]
    local max_pq = out["max-pq-y"]
    if not avg_pq or avg_pq <= 0 then
        if photon_scene_has_feed then photon_scene_has_feed = false; photon_publish_scene_feed() end
        return
    end
    if not max_pq or max_pq <= avg_pq then max_pq = avg_pq end

    local raw_vel       = HDR_STATE.prev_adapted_peak
                          and (HDR_STATE.adapted_peak - HDR_STATE.prev_adapted_peak) / UPDATE_INTERVAL
                          or 0
    HDR_STATE.prev_adapted_peak   = HDR_STATE.adapted_peak
    HDR_STATE.pq_velocity         = clamp(lerp(raw_vel, HDR_STATE.pq_velocity, HDR_VEL_SMOOTH), -5000, 5000)

    local dynamic_cut = CUT_BASE * (0.5 + clamp(HDR_STATE.adapted_pq, 0, 0.6) * CUT_SCALE)
    local cut_candidate = math.abs(avg_pq - HDR_STATE.adapted_pq) > dynamic_cut
    -- Requires the breach on two consecutive ticks before treating it as
    -- and revert on the next, which a genuine scene cut never does;
    local is_cut = cut_candidate and HDR_STATE.cut_pending
    HDR_STATE.cut_pending = cut_candidate

    HDR_STATE.adapted_pq = is_cut and avg_pq or lerp(avg_pq, HDR_STATE.adapted_pq, 0.75)

    local contrast_delta = math.max(0, max_pq - avg_pq)
    local delta_t        = clamp(contrast_delta / HDR_CONTRAST_SCALE, 0, 1)
    local contrast_w     = lerp(HDR_CONTRAST_WEIGHT_HIGH, HDR_CONTRAST_WEIGHT_LOW, delta_t)
    local total_w        = HDR_AVG_WEIGHT + HDR_MAX_WEIGHT + contrast_w
    local hybrid_pq      = (avg_pq * HDR_AVG_WEIGHT +
                            max_pq * HDR_MAX_WEIGHT +
                            contrast_delta * contrast_w) / total_w
    HDR_STATE.drive_pq             = is_cut and hybrid_pq or lerp(hybrid_pq, HDR_STATE.drive_pq, 0.65)

    local scene_t    = smoothstep(DARK_THRESH, BRIGHT_THRESH, HDR_STATE.drive_pq)
    local raw_target = lerp(DARK_PEAK, BRIGHT_PEAK, scene_t)

    raw_target = clamp(raw_target + HDR_STATE.pq_velocity * HDR_VEL_DAMP, DARK_PEAK, BRIGHT_PEAK)

    local inertia
    if is_cut then
        inertia = 0.5   -- DRAFT: short ramp instead of 0.0 (instant)
    elseif raw_target < HDR_STATE.adapted_peak then
        local vel_boost = clamp(math.abs(HDR_STATE.pq_velocity) * HDR_VEL_DAMP, 0, 0.08)
        inertia = math.min(0.96, HDR_INERTIA_DARK + vel_boost)
    else
        local vel_boost = clamp(math.abs(HDR_STATE.pq_velocity) * HDR_VEL_DAMP, 0, 0.08)
        inertia = math.max(0.0, HDR_INERTIA_BRIGHT - vel_boost)
    end

    HDR_STATE.adapted_peak = lerp(raw_target, HDR_STATE.adapted_peak, inertia)

    local peak_int = math.floor(HDR_STATE.adapted_peak + 0.5)
    -- ARCHITECTURE: mp.set_property("target-peak", ...) is believed to
    -- trigger an expensive re-tonemap/gamut-map LUT rebuild in libplacebo
    local steady_state_threshold = 18
    local peak_threshold = is_cut and 1 or steady_state_threshold
    if math.abs(peak_int - HDR_STATE.last_peak_set) >= peak_threshold then
        mp.set_property("target-peak", peak_int)
        HDR_STATE.last_peak_set = peak_int
    end

    -- PHOTON SCENE SIGNAL — HDR path. Feed is unconditional, not gated
    -- independently when sharp is off. video-out-params gives no
    photon_scene_peak     = clamp(avg_pq, 0, 1)
    photon_scene_contrast = clamp(contrast_delta / HDR_CONTRAST_SCALE, 0, 1)
    photon_scene_noise    = (clamp(contrast_delta, 0, 1) < 0.059) and 0.5 or 0.10
    photon_scene_sat      = -1.0
    -- Hue/warmth: see "HDR HUE SIGNAL" section above for the two-source
    -- architecture. Try SOURCE 1 first — free, same `out` table already
    local meta_hue, meta_warmth = read_hdr_hue_from_metadata(out)
    if meta_hue or meta_warmth then
        HDR_STATE.cached_hue, HDR_STATE.cached_warmth = meta_hue, meta_warmth
    else
        -- SOURCE 1 has nothing for this file (plain HDR10 with no
        -- dynamic metadata, or Dolby Vision — see "HDR HUE — SOURCE 2"
        -- above for why DV has no metadata path at all). SOURCE 2 is a
        -- screenshot-raw probe; throttle the retry (was every tick ~0.1s).
        local now_t = mp.get_time()
        if now_t - (HDR_STATE.hue_s2_last_try or -10) >= 2.0 then
            HDR_STATE.hue_s2_last_try = now_t
            HDR_STATE.cached_hue, HDR_STATE.cached_warmth = read_hdr_hue_from_screenshot()
        end
    end
    photon_scene_hue, photon_scene_warmth = HDR_STATE.cached_hue, HDR_STATE.cached_warmth
    photon_scene_motion   = clamp(math_abs(HDR_STATE.pq_velocity) / 10.0, 0.0, 1.0)
    photon_scene_is_cut   = is_cut
    photon_scene_has_feed = true

    -- fine_coarse/user_strength derivation lives entirely in sharp.lua's
    -- "photon-scene-feed" handler now, paralleling grain's
    -- gr_resolve_adaptive_params pattern: each consumer derives its own
    photon_scene_update_smoothing()
    photon_publish_scene_feed()
end

-- Generation/PTS-bound local cached profile planner. No new reader or request.
function RADAR_STATE.plan_gamma(pos)
    local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
    if not DOC.active or is_hdr or is_live or not enabled or is_network_slow or not finite(pos) then return nil end
    local before, after
    for _, sample in ipairs(RADAR_STATE.live_buffer) do
        if sample.generation == DOC.gen and finite(sample.t) and finite(sample.pbs) and sample.pbs >= 0 and sample.pbs <= 100 then
            if sample.t <= pos then before = sample
            elseif not after then after = sample; break end
        end
    end
    if not before or not after then return nil end
    local gap = after.t-before.t
    -- Relative machine precision only, not a perception or cadence threshold.
    if gap <= 0 or gap-ANALYSIS_INTERVAL > math.max(1,math.abs(after.t),math.abs(before.t))*2.220446049250313e-16 then return nil end
    local alpha=clamp((pos-before.t)/gap,0,1)
    local smooth=alpha*alpha*(3-2*alpha)
    local left,right=pbs_to_gamma(before.pbs),pbs_to_gamma(after.pbs)
    if not finite(left) or not finite(right) then return nil end
    return left+(right-left)*smooth
end

--  SDR SMOOTH UPDATE

local function update_sdr()
    if not enabled or not is_sdr then return end
    local pos = mp.get_property_number("time-pos")

    -- Cut is an observation of this update, not a latched scene state.
    -- A missing sample must not reuse the previous update's cut bypass.
    photon_scene_is_cut = false
    -- Chosen VOD contract: no valid current-generation local bracket means
    -- no gamma write. Network/live current-frame adaptation is a separate path.
    local planned_gamma = RADAR_STATE.plan_gamma(pos)
    if planned_gamma == nil then return end
    local current_pbs = (pos and #RADAR_STATE.live_buffer > 0) and buffer_lookup(pos) or nil
    local next_pbs    = (pos and #RADAR_STATE.live_buffer > 0) and buffer_lookup(pos + ANALYSIS_INTERVAL) or nil

    if current_pbs then
        RADAR_STATE.buffer_miss  = false
        SDR_STATE.has_data = true

        if SDR_STATE.prev_pbs then
            local raw_vel = (current_pbs - SDR_STATE.prev_pbs) / UPDATE_INTERVAL
            SDR_STATE.pbs_velocity  = lerp(raw_vel, SDR_STATE.pbs_velocity, 0.65)
        end
        SDR_STATE.prev_pbs = current_pbs

        local lookahead_delta = next_pbs and math.abs(next_pbs - current_pbs) or 0
        local cut_score       = clamp(lookahead_delta / SDR_STATE.sm.CUT_SPAN, 0, 1)
        photon_scene_is_cut   = (cut_score > SDR_STATE.sm.CUT_SCORE_MIN)
        -- DRAFT: pbs_velocity of a cut is not motion; drop it so the
        -- momentum term cannot cause a second dip right after the cut.
        if photon_scene_is_cut then SDR_STATE.pbs_velocity = 0 end
        -- The lookahead pair only straddles the cut for one interval while
        -- the gamma gap is seconds of travel: latch the cut ramp until the
        -- write quantum (0.01, the existing gamma_dec step) is all that
        -- remains. Without the latch the tail still crawls at TAU_DARK/
        -- BRIGHT (field: 8-9 s to settle after a dark->bright cut).
        if photon_scene_is_cut then SDR_STATE.cut_ramp = true end

        local target_g   = planned_gamma
        local going_dark = target_g > SDR_STATE.adapted_gamma
        local base_speed = going_dark and SDR_ADAPT_DARK or SDR_ADAPT_BRIGHT
        -- DRAFT v3: tau-based weight (tick independent); owner d62b already removed the cut snap.
        -- Cut ramp: CUT_RAMP_TAU was declared for exactly this and never
        -- wired - a detected cut took TAU_DARK/BRIGHT (3-4 s) to land. The
        -- exponential ramp decelerates, so it is smooth without the chase.
        local speed      = 1 - SDR_STATE.sm.tau_alpha(UPDATE_INTERVAL,
            SDR_STATE.cut_ramp and SDR_STATE.sm.CUT_RAMP_TAU
                or (going_dark and SDR_STATE.sm.TAU_DARK or SDR_STATE.sm.TAU_BRIGHT))

        -- While reset_cooldown_ticks is active: adapted_pbs stayed frozen
        -- during buffer_miss, so the gap between it and current_pbs may be
        -- larger than normal. speed is the weight given to adapted_pbs (the
        -- dominant — the instant jump this is meant to avoid.
        if RADAR_STATE.reset_cooldown_ticks > 0 then
            speed = 0.92
            RADAR_STATE.reset_cooldown_ticks = RADAR_STATE.reset_cooldown_ticks - 1
        end

        SDR_STATE.adapted_gamma = lerp(target_g, SDR_STATE.adapted_gamma, speed)
        SDR_STATE.adapted_pbs   = lerp(current_pbs, SDR_STATE.adapted_pbs, speed)
        -- Settled when only the write quantum remains (gamma writes are
        -- quantized to 0.01 anyway): release the latch, resume normal tau.
        if SDR_STATE.cut_ramp
            and math.abs(target_g - SDR_STATE.adapted_gamma) < 0.01 then
            SDR_STATE.cut_ramp = false
        end
    else
        RADAR_STATE.buffer_miss  = true
        SDR_STATE.pbs_velocity = 0
        SDR_STATE.prev_pbs     = nil
        -- reset_cooldown_ticks is deliberately not consumed here: this
        -- branch runs while current_pbs is nil (buffer miss), so no real
        -- data has arrived yet. Decrementing here would let the counter
        if not SDR_STATE.has_data then
            -- No data at all yet (radar not warmed up / probe failed) —
            -- leave the shader to its own local fallback estimate.
            if photon_scene_has_feed then photon_scene_has_feed = false; photon_publish_scene_feed() end
            return
        end
        local target_g   = pbs_to_gamma(SDR_STATE.adapted_pbs)
        local going_dark = target_g > SDR_STATE.adapted_gamma
        local speed      = 1 - SDR_STATE.sm.tau_alpha(UPDATE_INTERVAL, going_dark and SDR_STATE.sm.TAU_DARK or SDR_STATE.sm.TAU_BRIGHT)
        SDR_STATE.adapted_gamma    = lerp(target_g, SDR_STATE.adapted_gamma, speed)
    end

    local gamma_dec = math.floor(SDR_STATE.adapted_gamma * 100 + 0.5) / 100.0
    if gamma_dec ~= SDR_STATE.last_gamma_set then
        mp.set_property_number("gamma", gamma_dec)
        SDR_STATE.last_gamma_set = gamma_dec
    end

    -- PHOTON SCENE SIGNAL — SDR-VOD path
    photon_scene_has_feed = true
    local full = (pos and #RADAR_STATE.live_buffer > 0) and buffer_lookup_full(pos) or nil
    if full then
        photon_scene_peak     = clamp(full.pbs / 100.0, 0, 1)
        photon_scene_contrast = full.contrast or 0.35
        photon_scene_noise    = (full.noise) and 0.5 or 0.10
    else
        -- No full profile but old pbs data exists: update peak at least,
        photon_scene_peak     = clamp(SDR_STATE.adapted_pbs / 100.0, 0, 1)
        photon_scene_contrast = lerp(0.35, photon_scene_contrast, 0.5)
        photon_scene_noise    = lerp(0.10, photon_scene_noise, 0.5)
    end
    photon_scene_motion = clamp(math_abs(SDR_STATE.pbs_velocity) / 20.0, 0.0, 1.0)

    -- full.sat is already computed by calc_frame_profile/buffer_lookup_full
    photon_scene_sat = full and full.sat or 0.10

    -- can be a genuine nil (buffer_lookup_full returns nil when both
    -- neighbors lack hue), and Lua's and/or would collapse that to 0.10
    photon_scene_hue = full and full.hue or nil

    -- Same reasoning as hue above, not sat's "or <default>" pattern:
    -- full.warmth can be a genuine nil (older ffmpeg without UAVG, or
    -- buffer_lookup_full's neighbor-gap case), and a numeric fallback
    photon_scene_warmth = full and full.warmth or nil

    -- fine_coarse/user_strength derivation (including the scene-local
    -- mini-calibration offset) lives entirely in photon-sharp.lua's
    -- photon-scene-feed handler now. photon_sharp_scene_baseline_pbs is
    photon_scene_update_smoothing()
    photon_publish_scene_feed()
end

--  LIVE SDR UPDATE

-- LIVE_CALIB is declared above, before photon_publish_hud_state — see
-- that declaration's own comment for why.
-- The former @photon_live:signalstats ran on EVERY video frame and made
-- 4K SDR torrents select hwdec=no. Live profiles now use the existing
-- screenshot-raw sampler at bounded cadence, off the main video filter graph.
-- Keep removal for a stale filter surviving an older session/transition.
local function remove_vf_filter()
    local vf = mp.get_property_native("vf")
    if type(vf) ~= "table" then vf = {} end
    local found = vf_filter_active
    for _, filter in ipairs(vf) do
        if type(filter) == "table" and filter.label == "photon_live" then found = true; break end
    end
    if found then
        mp.commandv("vf", "remove", "@photon_live")
        mp.msg.info("photon: live vf filter removed")
    end
    vf_filter_active = false
end

local function update_live_calibration(pbs)
    if RADAR_STATE.calib_done then return end
    table.insert(LIVE_CALIB.samples, pbs)
    if #LIVE_CALIB.samples >= CALIB_FRAMES then
        local sorted = {}
        for _, v in ipairs(LIVE_CALIB.samples) do table.insert(sorted, v) end
        table.sort(sorted)
        local med = sorted[math.floor(#sorted / 2)]
        RADAR_STATE.dynamic_neutral = clamp(med, 10, 80)
        RADAR_STATE.calib_done      = true
        LIVE_CALIB.samples = {}
        print("gor-osd:" .. string.format("neutral: %.0f", RADAR_STATE.dynamic_neutral))
        mp.msg.info(string.format(
            "photon: live calibration done. median=%.1f neutral=%.1f",
            med, RADAR_STATE.dynamic_neutral))
    end
end

local function update_sdr_live()
    if not enabled or not is_sdr or not is_live then return end
    -- Same v14 stall guard as gs_tick/dispatch_radar: a cache underrun
    -- (magnet seek wait) serves repeated or transitional frames; adapting
    -- to them walked gamma and the scene feed while the waiting screen was
    -- static (owner log 0958 item 2: brightness pumping in the seek wait).
    if RADAR_STATE.stream_frozen() then return end

    local now = mp.get_time()
    if now - LIVE_CALIB.last_capture >= LIVE_CALIB.capture_interval then
        -- Start the interval BEFORE screenshot-raw: even failed readbacks
        -- must not spin or induce a 4K readback storm.
        local elapsed = LIVE_CALIB.last_profile_t and (now - LIVE_CALIB.last_profile_t) or LIVE_CALIB.capture_interval
        LIVE_CALIB.last_capture = now
        local profile = SDR_STATE.capture_frame_profile()
-- PHOTON TELEMETRY ADDITION BEGIN
    if COST.media_telemetry then
        LIVE_CALIB.trace_sample_id=(LIVE_CALIB.trace_sample_id or 0)+1
        COST.trace_record("LIVE_CAPTURE_RESULT",{doc_gen=DOC.gen,
            sample_id=LIVE_CALIB.trace_sample_id,capture_request_time=now,
            available=profile~=nil,frame_identity_bound=false})
    end
-- PHOTON TELEMETRY ADDITION END
        if profile then
            LIVE_CALIB.profile = profile
            LIVE_CALIB.last_profile_t = now
            LIVE_CALIB.capture_failed = false
            local pbs = profile.pbs
            update_live_calibration(pbs)
            SDR_STATE.has_data = true
            RADAR_STATE.buffer_miss = false
            if LIVE_CALIB.last_pbs then
                local raw_vel = (pbs - LIVE_CALIB.last_pbs) / math.max(elapsed, 0.1)
                SDR_STATE.pbs_velocity = lerp(raw_vel, SDR_STATE.pbs_velocity, 0.65)
                -- Live cut detect, shared convention (SDR_STATE.sm). Re-armed
                -- per capture so the whole inter-capture interval ramps on
                -- the cut tau. Cut velocity is not motion: zeroed like the
                -- VOD path so momentum cannot cause a second dip.
                LIVE_CALIB.cut_ramp = math.abs(pbs - LIVE_CALIB.last_pbs) / SDR_STATE.sm.CUT_SPAN > SDR_STATE.sm.CUT_SCORE_MIN
                if LIVE_CALIB.cut_ramp then SDR_STATE.pbs_velocity = 0 end
            end
            LIVE_CALIB.last_pbs = pbs
            SDR_STATE.prev_pbs = pbs
            SDR_STATE.adapted_pbs = pbs
            mp.msg.info(string.format("photon: live sample interval=%.1fs hwdec-current=%s pbs=%.1f",
                elapsed, mp.get_property("hwdec-current", "unavailable"), pbs))
        elseif not LIVE_CALIB.capture_failed then
            LIVE_CALIB.capture_failed = true
            mp.msg.warn("photon: live screenshot sample unavailable; holding last scene profile")
        end
    end
    local profile = LIVE_CALIB.profile
    if not profile then return end
    local pbs = profile.pbs

    photon_scene_is_cut = LIVE_CALIB.cut_ramp == true
    -- Low-pass the ~2.5 s pbs samples before the gamma mapping, then tau + output slew.
    -- On a detected cut the within-scene prefilter and the drift slew are
    -- pure lag (field: dark-to-bright ramped 10 s+); the cut tau ramp is
    -- exponential and decelerating - smooth without them.
    if LIVE_CALIB.cut_ramp then
        LIVE_CALIB.pbs_f = pbs
    else
        LIVE_CALIB.pbs_f = LIVE_CALIB.pbs_f and lerp(LIVE_CALIB.pbs_f, pbs, SDR_STATE.sm.tau_alpha(LIVE_UPDATE_INTERVAL, SDR_STATE.sm.PBS_TAU)) or pbs
    end
    local target_g   = pbs_to_gamma(LIVE_CALIB.pbs_f)
-- PHOTON TELEMETRY ADDITION BEGIN
    LIVE_CALIB.trace_previous_gamma=SDR_STATE.adapted_gamma
-- PHOTON TELEMETRY ADDITION END
    local going_dark = target_g > SDR_STATE.adapted_gamma
    local speed      = 1 - SDR_STATE.sm.tau_alpha(LIVE_UPDATE_INTERVAL,
        LIVE_CALIB.cut_ramp and SDR_STATE.sm.CUT_RAMP_TAU
            or (going_dark and SDR_STATE.sm.TAU_DARK or SDR_STATE.sm.TAU_BRIGHT))
    do
        local prev = SDR_STATE.adapted_gamma
        local step = lerp(target_g, prev, speed) - prev
        if not LIVE_CALIB.cut_ramp then
            local maxd = SDR_STATE.sm.SLEW_PER_S * LIVE_UPDATE_INTERVAL
            step = math.max(-maxd, math.min(maxd, step))
        end
        SDR_STATE.adapted_gamma = prev + step
    end
-- PHOTON TELEMETRY ADDITION BEGIN
    if COST.media_telemetry then
    COST.trace_record("LIVE_LEGACY_ACTUATOR",{doc_gen=DOC.gen,
        sample_id=LIVE_CALIB.trace_sample_id,profile_age=LIVE_CALIB.last_profile_t and now-LIVE_CALIB.last_profile_t,
        capture_failed=LIVE_CALIB.capture_failed,target=target_g,
        previous_gamma=LIVE_CALIB.trace_previous_gamma,proposed_gamma=SDR_STATE.adapted_gamma,
        cut=photon_scene_is_cut,cut_identity_bound=false})
    end
-- PHOTON TELEMETRY ADDITION END

    local gamma_dec = math.floor(SDR_STATE.adapted_gamma * 100 + 0.5) / 100.0
    if gamma_dec ~= SDR_STATE.last_gamma_set then
        mp.set_property_number("gamma", gamma_dec)
        SDR_STATE.last_gamma_set = gamma_dec
    end

    -- PHOTON SCENE SIGNAL — reuse the last sampled frame while 4 Hz
    -- smoothing continues. No full-resolution per-frame video filter.
    photon_scene_has_feed = true
    photon_scene_peak     = clamp(pbs / 100.0, 0, 1)
    photon_scene_contrast = profile.contrast or 0.35
    photon_scene_noise    = profile.noise and 0.5 or 0.10
    photon_scene_motion   = clamp(math_abs(SDR_STATE.pbs_velocity) / 20.0, 0.0, 1.0)
    photon_scene_sat      = profile.sat or 0.10
    -- profile.hue comes straight from calc_frame_profile — this path has
    -- no interpolation layer like buffer_lookup_full, just a single
    -- current frame read with no lerp between neighbors, so the VOD/
    photon_scene_hue      = profile.hue
    -- warmth: direct passthrough from profile.warmth (calc_frame_
    -- profile), same nil-preserving contract as hue directly above —
    -- no interpolation layer on this path (single-frame read, not
    photon_scene_warmth   = profile.warmth

    -- fine_coarse/user_strength derivation lives entirely in sharp.lua's
    -- "photon-scene-feed" handler.
    photon_scene_update_smoothing()
    photon_publish_scene_feed()
end

--  FALLBACK PROBE

-- v15: current-frame scene profile from mpv's OWN decoded output
-- (screenshot-raw), replacing ffmpeg URL re-opens on network sources.
-- Signed URLs expire mid-playback; mpv's connection is the only reliable
-- reader. Subsampled ~192x108 grid, bt601 luma/chroma, ffmpeg
-- signalstats-compatible stats (YAVG / YLOW 10th / YHIGH 90th / SATAVG /
-- HUEAVG atan2(v,u) deg / UAVG) fed through the same calc_frame_profile
-- as the ffmpeg path - downstream behavior is identical either way.
-- Known skew: bt601 vs the source's native matrix is a few percent on
-- luma, inside the pipeline's own adaptation noise.
function SDR_STATE.capture_frame_profile_raw()
    local ok, shot = COST.shot()
    if not ok or type(shot) ~= "table" or type(shot.data) ~= "string"
        or not shot.w or not shot.h then return nil end
    local data, w, h = shot.data, shot.w, shot.h
    local stride = shot.stride or (w * 4)
    local sx = math_max(1, math_floor(w / 192))
    local sy = math_max(1, math_floor(h / 108))
    local hist = {}
    for i = 0, 255 do hist[i] = 0 end
    local n = 0
    local sum_y, sum_u, sum_v, sum_sat, sum_hue = 0.0, 0.0, 0.0, 0.0, 0.0
    local atan2 = math.atan2 or math.atan  -- LuaJIT 5.1 vs 5.3+
    for y = 0, h - 1, sy do
        local row = y * stride
        for x = 0, w - 1, sx do
            local b, g, r = string.byte(data, row + x * 4 + 1, row + x * 4 + 3)
            if not r then return nil end
            local ly = 0.299 * r + 0.587 * g + 0.114 * b
            local u  = -0.14713 * r - 0.28886 * g + 0.436 * b
            local v  =  0.615   * r - 0.51499 * g - 0.10001 * b
            n = n + 1
            sum_y = sum_y + ly
            sum_u = sum_u + u
            sum_v = sum_v + v
            sum_sat = sum_sat + math.sqrt(u * u + v * v)
            local hd = math.deg(atan2(v, u))
            if hd < 0 then hd = hd + 360 end
            sum_hue = sum_hue + hd
            local bin = math_floor(ly + 0.5)
            if bin > 255 then bin = 255 end
            hist[bin] = hist[bin] + 1
        end
    end
    if n < 100 then return nil end
    local function pct(p)
        local target, acc = p * n, 0
        for i = 0, 255 do
            acc = acc + hist[i]
            if acc >= target then return i end
        end
        return 255
    end
    return calc_frame_profile(sum_y / n, pct(0.90), pct(0.10),
        sum_sat / n, sum_hue / n, sum_u / n + 128.0, 255)
end
SDR_STATE.capture_frame_profile = COST.wrap("SDRCAP", SDR_STATE.capture_frame_profile_raw)

local function probe_sdr_frame()
    if #RADAR_STATE.live_buffer > 0 and not RADAR_STATE.buffer_miss then return end
    -- Watchdog first: a hung network subprocess must not pin
    -- ffmpeg_running (and with it the whole scene feed) forever. The
    -- stale callback still clears harmlessly when the process exits.
    if SDR_STATE.ffmpeg_running then
        local stuck_for = mp.get_time() - (SDR_STATE.ffmpeg_started or 0)
        if stuck_for > (is_network_slow and 25 or 10) then
            SDR_STATE.ffmpeg_running = false
            SDR_STATE.probe_fails = (SDR_STATE.probe_fails or 0) + 1
            mp.msg.warn(string.format(
                "photon: sdr probe watchdog — ffmpeg still running after %.0fs, retrying", stuck_for))
        else
            return
        end
    end
    -- v14: don't probe into a cache underrun - the -ss read collides with
    -- mpv's own and returns a clean exit with zero frames (field run 2).
    -- Not counted as a failure: defer silently until playback resumes.
    if RADAR_STATE.stream_frozen() then return end
    if not is_sdr or not enabled then return end
    if is_live then return end
    local path = mp.get_property("path")
    local pos  = mp.get_property_number("time-pos")
    if not path or not pos then return end
    if path:find("pixeldrain") then return end  -- ★ skip for pixeldrain
    -- v15: network sources never re-open the URL (see
    -- SDR_STATE.capture_frame_profile). The capture fills the same
    -- rolling buffer the ffmpeg probe did; buffer_miss keeps driving
    -- re-captures as playback advances.
    if is_network_slow then
        local profile = SDR_STATE.capture_frame_profile()
        if profile then
            SDR_STATE.probe_fails = 0
            if not RADAR_STATE.analyzed_times[pos] then
                buffer_insert(pos, profile)
                RADAR_STATE.analyzed_times[pos] = true
            end
            SDR_STATE.adapted_pbs = profile.pbs
            SDR_STATE.has_data    = true
        end
        return
    end
    if RADAR_STATE.url_dead then return end  -- v15: 4xx is permanent, no retry
    local probe_generation = RADAR_STATE.worker_generation
    SDR_STATE.ffmpeg_running = true
    SDR_STATE.ffmpeg_started = mp.get_time()
    COST.ff_inc("sdrprobe")
    local cmd = string.format(
        FFMPEG .. RADAR_STATE.net_opts() .. " -threads 1 -ss %.3f -i %s -vframes 1 " ..
        -- UAVG added for the new warmth field (see calc_frame_profile's
        -- n_warmth comment). Full output captured, parsed in Lua.
        "-vf signalstats,metadata=print -f null - 2>&1",
        pos, string.format("%q", path))
    mp.command_native_async({
        name="subprocess", args={"sh","-c",cmd},
        capture_stdout=true, capture_stderr=false, playback_only=false,
    }, function(success, res)
        if probe_generation ~= RADAR_STATE.worker_generation then return end
        SDR_STATE.ffmpeg_running = false
        -- Bounded failure visibility: this probe failing silently is what
        -- left the field HUD on "no feed" / "waiting for photon.lua…" for
        -- a whole file with zero log lines. Warn once per 5-tick streak
        -- with ffmpeg's real output so the next field log discriminates.
        -- v14: classify before counting. A clean exit with no frame data
        -- is a stalled stream (rw_timeout/EOF before one frame), not an
        -- ffmpeg failure - the old log called status=0 runs "failed" and
        -- printed the version-banner head instead of the error tail.
        local out = (res and res.stdout) or ""
        RADAR_STATE.note_url_death(out)
        local profile = (success and out ~= "") and parse_frame_extended(out) or nil
        if not profile then
            SDR_STATE.probe_fails = (SDR_STATE.probe_fails or 0) + 1
            if SDR_STATE.probe_fails == 5 then
                local why
                if not success then
                    why = "subprocess spawn failed"
                elseif (res and res.status or -1) ~= 0 then
                    why = string.format("ffmpeg error (status=%s)", tostring(res and res.status))
                else
                    why = "clean exit but no frame data (stream stall/timeout)"
                end
                mp.msg.warn(string.format(
                    "photon: sdr probe failed 5 ticks in a row — %s — output tail: %s",
                    why, out ~= "" and out:sub(-300)
                        or "(empty - ffmpeg not found on PATH? see FFMPEG path line at load)"))
            end
            return
        end
        SDR_STATE.probe_fails = 0
        if not RADAR_STATE.analyzed_times[pos] then
            buffer_insert(pos, profile)
            RADAR_STATE.analyzed_times[pos] = true
        end
        SDR_STATE.adapted_pbs  = profile.pbs
        SDR_STATE.has_data = true
    end)
end

--  CALIBRATION

local function run_calibration(path, duration)
    local calibration_generation = RADAR_STATE.worker_generation
    if path:find("pixeldrain") then return end
    -- v15: a rejected URL never comes back - the neutral default stands.
    if RADAR_STATE.url_dead then
        RADAR_STATE.calib_attempted = true
        return
    end
    -- v14: defer while the stream is starved - probing into an underrun
    -- collides with mpv's own reads (field: 3/4 samples lost at startup).
    -- Bounded retries, then the neutral default stands. calib_attempted
    -- only marks a real spawn, so the file-open caller won't double us.
    if RADAR_STATE.stream_frozen() then
        RADAR_STATE.calib_deferrals = (RADAR_STATE.calib_deferrals or 0) + 1
        if RADAR_STATE.calib_deferrals <= 24 then
            if not RADAR_STATE.calib_retry_pending then
                RADAR_STATE.calib_retry_pending = true
                mp.add_timeout(5.0, function()
                    if calibration_generation ~= RADAR_STATE.worker_generation then return end
                    RADAR_STATE.calib_retry_pending = false
                    run_calibration(path, duration)
                end)
            end
        else
            RADAR_STATE.calib_attempted = true
            mp.msg.warn("photon: calibration deferred 2 minutes, stream still buffering - neutral default stands")
        end
        return
    end
    RADAR_STATE.calib_attempted = true
    -- Network sources get a quarter of the grid: every calibration frame
    -- is a ranged HTTP fetch and the grid runs serially there
    -- (max_active=1), so 12 frames could hog the probe budget for minutes
    -- at startup. 4 still yields a usable neutral median; the live buffer
    -- refines from there.
    local n_frames = is_network_slow and 4 or CALIB_FRAMES
    local calib_times = {}
    math.randomseed(os.time())
    for i = 1, n_frames do
        table.insert(calib_times, duration * 0.05 + math.random() * duration * 0.90)
    end

    local done = 0
    local pbs_q = {}
    local active = 0
    local max_active = is_network_slow and 1 or 4

    local function spawn_next()
        while active < max_active and #calib_times > 0 do
            local t = table.remove(calib_times)
            active = active + 1
            COST.ff_inc("calib")
            local cmd = string.format(
                FFMPEG .. RADAR_STATE.net_opts() .. " -threads 1 -ss %.3f -i %s -vframes 1 " ..
                -- UAVG added, third and final of the three parse paths
                -- (subprocess-job / live-position-sample / calibration)
                -- — see calc_frame_profile's n_warmth comment. Full
                -- output captured, parsed in Lua.
                "-vf signalstats,metadata=print -f null - 2>&1",
                t, string.format("%q", path))

            mp.command_native_async({
                name="subprocess", args={"sh","-c",cmd},
                capture_stdout=true, capture_stderr=false, playback_only=false,
            }, function(s, r)
                if calibration_generation ~= RADAR_STATE.worker_generation then return end
                active = active - 1
                done = done + 1
                RADAR_STATE.note_url_death(r and r.stdout)
                if s and r and r.stdout ~= "" then
                    local profile = parse_frame_extended(r.stdout)
                    if profile then
                        table.insert(pbs_q, profile.pbs)
                        if not RADAR_STATE.analyzed_times[t] then
                            buffer_insert(t, profile)
                            RADAR_STATE.analyzed_times[t] = true
                        end
                    end
                end
                if done >= n_frames and not RADAR_STATE.calib_done then
                    if #pbs_q > 0 then
                        table.sort(pbs_q)
                        local med = pbs_q[math.floor((#pbs_q + 1) / 2)]
                        RADAR_STATE.dynamic_neutral = clamp(med, 10, 80)
                        RADAR_STATE.calib_done      = true
                        print("gor-osd:" .. string.format("neutral: %.0f", RADAR_STATE.dynamic_neutral))
                        mp.msg.info(string.format(
                            "photon: calibration done. median=%.1f neutral=%.1f",
                            med, RADAR_STATE.dynamic_neutral))
                        if #pbs_q < n_frames then
                            mp.msg.warn(string.format(
                                "photon: calibration used %d/%d samples — most -ss probes failed for this source",
                                #pbs_q, n_frames))
                        end
                    end
                else
                    spawn_next()
                end
            end)
        end
    end
    spawn_next()
end

--  FORMAT DETECTION

local function detect_format(force)
    local params = mp.get_property_native("video-params")
    if not params then return end

    local g = params["gamma"] or ""
    local new_is_hdr = (g == "pq" or g == "hlg")
    if not force then
        if (new_is_hdr == is_hdr) and (is_hdr and HDR_STATE.timer or is_sdr and SDR_STATE.smooth_timer) then
            return
        end
    end

    is_hdr = new_is_hdr
    is_sdr = not new_is_hdr

    if is_hdr then
        if SDR_STATE.sdr_timer        then SDR_STATE.sdr_timer:kill();        SDR_STATE.sdr_timer        = nil end
        if SDR_STATE.smooth_timer then SDR_STATE.smooth_timer:kill(); SDR_STATE.smooth_timer = nil end
        if SDR_STATE.radar_timer      then SDR_STATE.radar_timer:kill();      SDR_STATE.radar_timer      = nil end

        if HDR_STATE.timer then HDR_STATE.timer:kill() end
        HDR_STATE.timer = mp.add_periodic_timer(UPDATE_INTERVAL, update_hdr)
        -- No vf-filter setup needed here: the HDR hue architecture
        -- (see "HDR HUE SIGNAL" above) reads video-out-params directly
        -- (source 1) and/or calls screenshot-raw from inside update_hdr
        if is_live then
            mp.msg.info("photon: hdr live mode initialized (video-out-params)")
        else
            mp.msg.info("photon: hdr mode initialized")
        end
    else
        is_hdr = false; is_sdr = true
        if HDR_STATE.timer then HDR_STATE.timer:kill(); HDR_STATE.timer = nil end

        if SDR_STATE.sdr_timer        then SDR_STATE.sdr_timer:kill() end
        if SDR_STATE.smooth_timer then SDR_STATE.smooth_timer:kill() end
        if SDR_STATE.radar_timer      then SDR_STATE.radar_timer:kill() end

        if is_live then
            SDR_STATE.sdr_timer        = nil
            SDR_STATE.radar_timer      = nil
            remove_vf_filter()
            SDR_STATE.smooth_timer = mp.add_periodic_timer(LIVE_UPDATE_INTERVAL, update_sdr_live)
            if not LIVE_CALIB.mode_logged then
                mp.msg.info(string.format("photon: sdr live mode screenshot sampling %.1fs, signalstats vf off", LIVE_CALIB.capture_interval))
                LIVE_CALIB.mode_logged = true
            end
        else
            SDR_STATE.sdr_timer        = mp.add_periodic_timer(SDR_PROBE_INTERVAL, probe_sdr_frame)
            SDR_STATE.smooth_timer = mp.add_periodic_timer(UPDATE_INTERVAL, update_sdr)
            SDR_STATE.radar_timer      = mp.add_periodic_timer(RADAR_TICK, update_radar)
            mp.msg.info("photon: sdr mode initialized")
            mp.add_timeout(0.5, update_radar)

            local path     = mp.get_property(PROP_PATH)
            local duration = mp.get_property_number(PROP_DURATION)
            if path and duration and duration > 10 and not RADAR_STATE.calib_attempted then
                run_calibration(path, duration)
            end
        end
    end
end

--  EVENTS

-- None of the feed-producing timers (HDR_STATE.timer/SDR_STATE.sdr_timer/
-- SDR_STATE.smooth_timer/SDR_STATE.radar_timer) check mpv's pause
-- property; they run on wall-clock, independent of playback position. On
mp.observe_property("pause", "bool", function(_, paused)
    if paused == nil then return end
    if paused then
        playback_active = false  -- P0-3: probes hold while paused
        if HDR_STATE.timer        then HDR_STATE.timer:kill();        HDR_STATE.timer        = nil end
        if SDR_STATE.sdr_timer        then SDR_STATE.sdr_timer:kill();        SDR_STATE.sdr_timer        = nil end
        if SDR_STATE.smooth_timer then SDR_STATE.smooth_timer:kill(); SDR_STATE.smooth_timer = nil end
        if SDR_STATE.radar_timer      then SDR_STATE.radar_timer:kill();      SDR_STATE.radar_timer      = nil end
        mp.msg.info("photon: paused - feed timers stopped")
    else
        playback_active = true  -- P0-3
        if HDR_STATE.timer or SDR_STATE.sdr_timer or SDR_STATE.smooth_timer or SDR_STATE.radar_timer then
            -- never stopped (e.g. observe_property's first call fires with
            -- paused=false before the file is loaded). Nothing to reinstall.
            return
        end
        detect_format(true)
        -- Safety net: if video-params isn't ready yet (rare — pause/resume
        -- fires before the file fully loads), detect_format silently no-ops
        if not (HDR_STATE.timer or SDR_STATE.sdr_timer or SDR_STATE.smooth_timer) then
            mp.msg.warn("photon: no feed timer after resume; retrying in 0.5s")
            mp.add_timeout(0.5, function() detect_format(true) end)
        end
        mp.msg.info("photon: resumed - feed timers restarted")
    end
end)

mp.register_event("file-loaded", function()
    photon_scene_is_cut = false -- a new document must not inherit the last cut
    HDR_STATE.adapted_pq          = 0.30
    HDR_STATE.drive_pq            = 0.30
    HDR_STATE.pq_velocity         = 0.0
    HDR_STATE.prev_adapted_peak   = nil
    HDR_STATE.adapted_peak        = (DARK_PEAK + BRIGHT_PEAK) / 2
    -- Reset with the rest of HDR state: a stale cut_pending=true from the
    -- previous file would make this file's first breach snap instantly,
    -- bypassing the one-tick confirmation cut detection depends on.
    HDR_STATE.cut_pending      = false
    HDR_STATE.last_peak_set       = -1
    SDR_STATE.adapted_gamma       = 0
    LIVE_CALIB.pbs_f = nil -- DRAFT v2: no stale filter state across documents
    SDR_STATE.adapted_pbs         = 50
    SDR_STATE.last_gamma_set      = -999
    SDR_STATE.ffmpeg_running      = false
    SDR_STATE.probe_fails           = 0
    SDR_STATE.has_data        = false
    SDR_STATE.pbs_velocity        = 0
    SDR_STATE.prev_pbs            = nil
    RADAR_STATE.calib_done          = false
    RADAR_STATE.calib_attempted     = false
    RADAR_STATE.calib_deferrals     = 0
    RADAR_STATE.calib_retry_pending = false
    RADAR_STATE.url_dead            = false
    RADAR_STATE.probe_wall_ema      = nil
    SIZE_GOV.seed = nil
    SIZE_GOV.applied = nil
    SIZE_GOV.ceiling = nil
    SIZE_GOV.source = nil
    SIZE_GOV.reset_history()
    SIZE_GOV.fallback_logged = false      -- 118b: provisional decision re-issued per document
    SIZE_GOV.fallback_sent = nil
    GS.last_noise_share = nil; GS.last_noise_at = nil   -- 118h: old file's reading is stale
    RADAR_STATE.dynamic_neutral     = CALIB_DEFAULT
    RADAR_STATE.live_buffer         = {}
    RG.ring                         = nil
    RG.samples                      = 0
    GS.est                          = nil
    GS.probe_running                = false
    GS.next_probe_at                = nil
    GS.contract_logged              = false
    GS.hist                         = {}
    GS.prev_luma                    = nil
    GS.pair                         = nil
    GS.samples                      = 0
    GS.last_pos                     = nil
    gr_gs_committed_hint            = false
    GS.last_mult                    = nil
    GS.look_learn = nil; GS.look_learn_revision = nil; GS.look_consumed_revision = nil
    GS.mhist                        = {}
    DOC.on_loaded()
    mp.commandv("script-message", "photon-grain-size-evidence", "unmeasured")
    SIZE_GOV.commit_resolution_fallback("start")   -- 118b: decided from t=0, <=5s by construction
    GR.ts                           = 0   -- stale until the engine's first publish
    GR.soft_rendered                = 1.0
    GR.weight_shift                 = 0.0
    GR.res_adapt                    = 1
    if not GS.timer then GS.timer = mp.add_periodic_timer(GS.interval, GS.paced_tick) end
    RG.last_bucket                  = nil
    RG.fail_streak                  = 0
    photon_scene_ring               = 0.0
    photon_scene_rlevel             = 0.0
    RADAR_STATE.buffer_miss         = false
    RADAR_STATE.analyzed_times      = {}
    flush_queue()
    RADAR_STATE.worker_generation   = RADAR_STATE.worker_generation + 1
    RADAR_STATE.active_workers      = 0
    -- Grain-size analysis: state resets per file, triggered with a short
    -- delay because duration is not yet available at file-loaded time
    -- (same wait pattern as radar's own first tick). The trigger is
    grain_analysis_generation = grain_analysis_generation + 1
    grain_analysis_running = false
    grain_analysis_samples = {}
    grain_size_hint_sent   = false
    grain_analysis_retries = 0
    LG.samples     = {}
    BK.samples     = {}
    BK.running     = false
    BK.done        = false
    BK.reprobes    = 0
    BK.gen         = BK.gen + 1
    if BK.timer then BK.timer:kill(); BK.timer = nil end
    photon_scene_block = 0.0
    LG.gen         = LG.gen + 1  -- invalidates any queued tick from the
                                  -- previous file's live-grain-probe
                                  -- closure so it can't write into this
                                  -- file's LG.samples.
    if LG.timer then LG.timer:kill(); LG.timer = nil end
    -- Both are called — their mutually exclusive is_live checks mean only
    -- one ever runs, so no timing assumption is needed about when
    -- set-live arrives. The set-live handler also triggers
    mp.add_timeout(0.5, gr_run_grain_size_analysis)
    mp.add_timeout(0.5, gr_run_live_grain_probe)
    mp.add_timeout(0.5, bk_run_probe)

    -- photon starts each video load based on photon_user_enabled, so the
    -- user's last F9 decision survives episode/channel changes. It is not
    -- reset in file-loaded; only the gor session ending (mpv process
    enabled = photon_user_enabled
    -- P0-3: standalone probes (RG/GS/BK/LG) run from here until
    -- end-file or pause flips the gate back.
    playback_active = true

    -- Same call F9 makes in its handler: if enabled is true on a fresh
    -- launch with no F9 press, photon_sync_bright_on_enable grants the
    -- adaptive-brightness permission (if the user never pressed B) and
    photon_sync_bright_on_enable(enabled)
    -- photon-sharp lives in its own VM now, so its enabled state cannot
    -- be read here. Same "declare target state" pattern as grain/chrome:
    -- sharp reads this in its own file-loaded and decides whether to
    mp.commandv("script-message", "photon-sharp-set-target-enabled", photon_user_enabled and "true" or "false")
    -- Grain follows the same pattern; it manages its own state in its
    -- own file-loaded. Script order is undefined, so this sets a target
    -- variable rather than a commanding message, mirroring the hud-state
    mp.commandv("script-message", "photon-grain-set-target-enabled", photon_user_enabled and "true" or "false")
    -- Same pattern, chrome's independent axis — never derived from
    -- photon_user_enabled. F9 must not move this.
    mp.commandv("script-message", "photon-chrome-set-target-enabled", chrome_user_enabled and "true" or "false")
    -- Same pattern again, negativ's independent axis.
    mp.commandv("script-message", "photon-negativ-set-target-enabled", negativ_user_enabled and "true" or "false")
    remove_vf_filter()
    LIVE_CALIB.profile = nil
    LIVE_CALIB.last_capture = -math.huge
    LIVE_CALIB.last_pbs = nil
    LIVE_CALIB.last_profile_t = nil
    LIVE_CALIB.capture_failed = false
    LIVE_CALIB.mode_logged = false
    LIVE_CALIB.samples = {}

    photon_scene_peak             = 0.50
    photon_scene_contrast         = 0.35
    photon_scene_noise            = 0.10
    photon_scene_motion           = 0.20
    photon_scene_smooth_peak      = 0.50
    photon_scene_smooth_contrast  = 0.35
    photon_scene_smooth_noise     = 0.10
    -- photon_sharp_* reset logic (user_strength/fine_coarse/user_offset/
    -- smooth_coarse/last_uniform_t/current_algo, plus the deliberate
    -- non-reset of shader_paths/shader_ready) lives in

    local path = mp.get_property("path") or ""
    local is_loopback = path:match("^https?://127%.0%.0%.1") or path:match("^https?://localhost")
    local is_any_network = path:match("^https?://") or path:match("^rtsp://") or path:match("^rtmp://")
    is_network_slow = is_any_network                         -- all network incl. loopback: gates worker throttle
    -- is_live is not auto-reset here. Swift sends an explicit set-live
    -- signal before loadfile on every load path (generic loader, IPTV,
    -- torrent); resetting here would overwrite it (torrent's localhost
    if is_any_network == nil then
        is_live = false
    end

    mp.set_property_number("gamma", 0)
    SDR_STATE.last_gamma_set      = 0
    -- Provisional first paint: publish immediately at file-loaded instead
    -- of waiting for the first probe to land. On network sources the
    -- first live_buffer entry can be minutes away; the HUD slot renders
    -- its "probe" state right away and refines as data arrives. (Placed
    -- here, not in detect_format: detect_format no-ops when the new
    -- file's mode matches the previous one, which would skip the paint.)
    photon_publish_hud_state()
    mp.add_timeout(0.5, detect_format)

    -- check + forced rewrite) lives entirely in photon-sharp.lua's own
    -- file-loaded now — sharp sees its own shader_ready state in its own
end)

mp.observe_property("time-pos", "number", function(_, pos)
    if pos then RADAR_STATE.last_known_pos = pos end
end)

mp.register_event("seek", function()
    if not is_sdr then return end
    -- Engine off: every consumer of the motion spike is
    -- target-disabled too, so skip the smoothing math and
    -- the broadcast (C3).
    if not enabled then return end

    local current_pos = mp.get_property_number("time-pos") or 0
    local diff = math.abs(current_pos - RADAR_STATE.last_known_pos)

    -- Seek motion spike — shared scene signal, all consumers (sharp, grain,
    -- chrome) see it via photon-scene-feed.
    photon_scene_motion = 1.0
    photon_scene_update_smoothing()
    photon_publish_scene_feed()
    mp.add_timeout(1.0, function()
        photon_scene_motion = 0.20
        photon_scene_update_smoothing()
        photon_publish_scene_feed()
    end)

    if diff < 2.0 then
        return
    end

    flush_queue()
    RADAR_STATE.buffer_miss  = true
    SDR_STATE.prev_pbs     = nil
    SDR_STATE.pbs_velocity = 0
    RADAR_STATE.reset_cooldown_ticks = RESET_COOLDOWN_TICKS
    mp.add_timeout(0.1, update_radar)
end)

-- 118h: a seek invalidates the cached noise reading (different scene);
-- the next real sample re-arms the feed. Separate handler: the SDR seek
-- handler above early-returns on HDR.
mp.register_event("seek", function()
    GS.last_noise_share = nil
    GS.last_noise_at = nil
end)

mp.observe_property("video-params/gamma", "string", function(_, g)
    if not g then return end
    detect_format()
end)

-- No hwdec observer needed: this codebase never changes hwdec at
-- runtime, so there's no transition for one to react to.

-- keep-open EOF fires end-file without unloading: a seek or replay
-- after it restarts playback without a new file-loaded, so re-arm the
-- probe gate here too or every probe stays dark for the resumed file.
mp.register_event("playback-restart", function()
    playback_active = true
    DOC.on_restart()
end)
-- Session fence: invalidate every in-flight grain analysis (ffmpeg path and
-- live-screenshot path) so a late callback cannot finalize/log under the
-- next document. EOF keep-open replay keeps its state (no fence).
function DOC.fence()
    DOC.active = false
    grain_analysis_generation = grain_analysis_generation + 1
    grain_analysis_running = false
    grain_analysis_samples = {}
    LG.gen = LG.gen + 1
    LG.samples = {}
    if LG.timer then LG.timer:kill(); LG.timer = nil end
end
mp.register_event("start-file", function() DOC.fence() end)
for _, ev_ in ipairs({"start-file", "end-file", "seek", "playback-restart", "file-loaded"}) do
    mp.register_event(ev_, function() SHARE.clear() end)
end

mp.register_event("end-file", function(ev)
    playback_active = false  -- P0-3: probes stop between files
    if not (ev and ev.reason == "eof") then DOC.fence() end
    -- Session ownership: a stop/quit/error/redirect ends this file's
    -- session, so every in-flight worker/probe/calibration callback and
    -- retry timer from it becomes stale. Bumping the same generation the
    -- file-loaded fence uses makes their existing guards reject result
    -- writes and spawn_next continuation. keep-open EOF ("eof") is not a
    -- session end: replay/seek resumes the same file without file-loaded.
    if not (ev and ev.reason == "eof") then
        RADAR_STATE.worker_generation   = RADAR_STATE.worker_generation + 1
        RADAR_STATE.active_workers      = 0
        RADAR_STATE.calib_retry_pending = false
        flush_queue()
    end
    if HDR_STATE.timer        then HDR_STATE.timer:kill();        HDR_STATE.timer        = nil end
    if SDR_STATE.sdr_timer        then SDR_STATE.sdr_timer:kill();        SDR_STATE.sdr_timer        = nil end
    if SDR_STATE.smooth_timer then SDR_STATE.smooth_timer:kill(); SDR_STATE.smooth_timer = nil end
    if SDR_STATE.radar_timer      then SDR_STATE.radar_timer:kill();      SDR_STATE.radar_timer      = nil end
    if is_sdr then mp.set_property_number("gamma", 0) end
    remove_vf_filter()
    SDR_STATE.ffmpeg_running = false
    -- SOURCE 2 (screenshot-raw) has no in-flight state to clean up: a
    -- synchronous in-process call has no subprocess or pending timer
end)

-- F9 needs to know if sharp/grain are already on before toggling them; both
-- live in their own VM now, so their enabled flag is mirrored from the same
-- hud-state broadcast the HUD itself consumes.
-- State lives in GR, not new main-chunk locals (LuaJIT local-limit margin).
GR.log_adaptive = function(event)
    local line = string.format("flag grain=%s sharp=%s src=%s out=%s eff=%s k=%s density=%s size=%s sharp_m=%s",
        tostring(GR.adaptive_mode), tostring(GR.sharp_adaptive_mode),
        tostring(GR.source_h), tostring(GR.output_h), tostring(GR.effective_h),
        tostring(GR.strength_k), tostring(GR.render_density), tostring(GR.size_coefficient), tostring(GR.sharp_multiplier))
    if event:find("toggle", 1, true) or line ~= GR.last_adaptive_log then
        GR.last_adaptive_log = line
        mp.msg.info("photon adaptive " .. event .. ": " .. line)
    end
end

local photon_sharp_enabled_mirror = false
local photon_grain_enabled_mirror = false
mp.register_script_message("photon-sharp-hud-state", function(enabled_str,
        _ready, _algo, _amount, _coarse, _factor, _halo, _texture, _fine, _medium, _band,
        _content, _temporal, _ring, _target, _src, _out, multiplier_s, mode_s)
    GR.sharp_multiplier = tonumber(multiplier_s)
    GR.sharp_adaptive_mode = mode_s == "true"
    GR.log_adaptive("state")
    photon_sharp_enabled_mirror = (enabled_str == "true")
end)
-- A user size trim changes the RENDERED size: probe history from the old
-- size is not comparable, so drop it (logged with the document).
mp.register_script_message("photon-grain-size-trim-state", function(trim_s, gen_s)
    -- Only a trim from the current document may clear its probe history.
    if tonumber(gen_s) ~= DOC.gen then
        DOC.append("photon-grain-size.log", string.format(
            "%s doc_gen=%d file=%q TRIM-HIST-KEPT trim=%s reason=stale-doc(grain=%s)",
            os.date("%Y-%m-%dT%H:%M:%S%z"), DOC.gen, DOC.name, tostring(trim_s), tostring(gen_s)))
        return
    end
    GS.hist = {}; GS.mhist = {}; GS.pair = nil
    DOC.append("photon-grain-size.log", string.format(
        "%s doc_gen=%d file=%q TRIM-HIST-CLEARED trim=%s",
        os.date("%Y-%m-%dT%H:%M:%S%z"), DOC.gen, DOC.name, tostring(trim_s)))
end)
mp.register_script_message("photon-grain-hud-state", function(enabled_str,
        amount_s, _fps, _sb, _hr, _hs, _hv, _hh, _hue, strength_s,
        _sr, _ss, _sv, size_r, dev_r, soft_r, amount_gpu_s, offset_s, weight_shift_s, res_adapt_s,
        _target, source_h_s, output_h_s, size_coefficient_s, strength_k_s, adaptive_mode_s, _strength_status, render_density_s, effective_h_s, _strength_source, _size_trim, producer_doc_s, producer_serial_s, control_revision_s)
    local producer_doc, producer_serial = tonumber(producer_doc_s), tonumber(producer_serial_s)
    if not GS.tuple_identity(producer_doc) or producer_doc ~= DOC.gen or not GS.tuple_identity(producer_serial) or producer_serial < 1 or
       producer_serial % 1 ~= 0 or (GR.doc_gen == producer_doc and producer_serial <= (GR.serial or 0)) then return end
    -- Reject a malformed mirror atomically. A valid producer identity does
    -- not make NaN/Inf parameters or an unknown boolean a render receipt.
    if enabled_str ~= "true" and enabled_str ~= "false" then return end
    if adaptive_mode_s ~= "true" and adaptive_mode_s ~= "false" then return end
    local required = {amount_s, strength_s, size_r, dev_r, soft_r,
        amount_gpu_s, offset_s, weight_shift_s, res_adapt_s}
    for index = 1, 9 do
        if not GS.tuple_finite(tonumber(required[index])) then return end
    end
    -- Above the supported raster range the host deliberately sends nil
    -- optional coefficients. Preserve that HOLD, never substitute a number.
    for _, value in ipairs({source_h_s or "", output_h_s or "",
            size_coefficient_s or "", strength_k_s or "",
            render_density_s or "", effective_h_s or ""}) do
        if value ~= "" and value ~= "nil" and not GS.tuple_finite(tonumber(value)) then return end
    end
    photon_grain_enabled_mirror = (enabled_str == "true")
    -- GS deconvolution mirror (see the GS probe): rendered grain state,
    -- timestamped so a stale mirror gates subtraction to hold-only.
    GR.enabled = photon_grain_enabled_mirror
    GR.amount = tonumber(amount_s) or GR.amount
    -- amount the GPU actually draws: the shader clamps GR_AMOUNT to 2.0,
    -- so the pre-clamp value would over-model the subtraction by (a/2)^2.
    GR.amount_gpu = tonumber(amount_gpu_s) or math.min(GR.amount, 2.0)
    GR.user_offset = tonumber(offset_s) or 0.0
    GR.strength = tonumber(strength_s) or GR.strength
    GR.size_rendered = tonumber(size_r) or GR.size_rendered
    GR.dev_rendered = tonumber(dev_r) or GR.dev_rendered
    GR.soft_rendered = tonumber(soft_r) or GR.soft_rendered
    GR.weight_shift = tonumber(weight_shift_s) or 0.0
    GR.res_adapt = tonumber(res_adapt_s) or 1
    GR.source_h = tonumber(source_h_s)
    GR.output_h = tonumber(output_h_s)
    GR.size_coefficient = tonumber(size_coefficient_s)
    GR.strength_k = tonumber(strength_k_s) -- nil above1080; render k never follows GS HOLD
    GR.render_density = tonumber(render_density_s) -- host-selected density, replaces static only when applied
    GR.adaptive_mode = adaptive_mode_s == "true"
    GR.effective_h = tonumber(effective_h_s)
    GR.control_revision = tonumber(control_revision_s)
    GR.strength_source = _strength_source
    GR.serial = producer_serial
    GR.doc_gen = producer_doc
    GR.ts = mp.get_time()
    GR.log_adaptive("state")
end)

--  F9: TOGGLE

-- photon_toggle_body(): F9's actual body, extracted so the HUD's "photon"
-- header click can trigger the same behavior via the new "photon-toggle"
-- script-message below. Key binding and script-message both call this —
local function photon_toggle_body()
    enabled = not enabled
    photon_user_enabled = enabled

    -- photon-hud.lua only learns `enabled` through this broadcast, and the
    -- regular call site (inside update_hdr/update_sdr) stops firing the
    -- instant enabled goes false. Publish here so the toggle is never
    photon_publish_hud_state()

    -- Adaptive brightness (Swift/ContentAdaptiveDimming) sync.
    -- Unlike sharp/grain, which are fully bound to F9, adaptive brightness has
    -- its own permission axis (the B key), which F9 must not override. Body
    photon_sync_bright_on_enable(enabled)

    if enabled then
        print("gor-osd:photon")

        -- photon-sharp and photon-grain follow F9 through ABSOLUTE target
        -- declarations (idempotent, storm-proof). The old mirror-conditional
        -- relative toggles flapped when a mirror was stale mid-file-open and
        -- let a subsystem's target diverge from master (field: grain
        -- re-enabled itself under a dead master).
        mp.commandv("script-message", "photon-sharp-set-target-enabled", "true")
        mp.commandv("script-message", "photon-grain-set-target-enabled", "true")
    else
        remove_vf_filter()
        if is_hdr then
            mp.set_property("target-peak", tostring(STATIC_PEAK))
            HDR_STATE.last_peak_set = STATIC_PEAK
            print("gor-osd:photoff  (" .. STATIC_PEAK .. " nit)")
        else
            mp.set_property_number("gamma", SDR_STATIC_GAMMA)
            SDR_STATE.last_gamma_set = SDR_STATIC_GAMMA
            print("gor-osd:photoff")
        end

        -- enabled=false stops new radar work (see update_radar), but
        -- dispatch_radar() ignores enabled and re-calls itself from its own async
        -- callback — it keeps spawning ffmpeg subprocesses as long as the queue
        flush_queue()

        mp.commandv("script-message", "photon-sharp-set-target-enabled", "false")
        mp.commandv("script-message", "photon-grain-set-target-enabled", "false")
    end
end

mp.add_key_binding("F9", "toggle-photon", photon_toggle_body)

-- HUD "photon" header click: SpineUI/PPController sends both
-- photon-hud-toggle-fold and photon-toggle, same pattern as
-- bright/sharp/grain/chrome/negativ. F9 is a key binding only (no
-- photon-toggle storm guard: in the field this message arrived in bursts
-- during the file-open window (4 toggles within ~2s around an F8 press +
-- loadfile, no F9 press - master flapped off/on/off/on). The burst source
-- is outside this script (F9 is the only local caller); photon-toggle
-- messages carry no sender identity, so this guard treats any burst as
-- invalid regardless of origin: repeats inside 1.5s are ignored and
-- logged. The F9 key binding stays undebounced for deliberate rapid
-- toggling.
local photon_toggle_last = -1e9
mp.register_script_message("photon-toggle", function()
    local now = mp.get_time()
    if now - photon_toggle_last < 1.5 then
        mp.msg.info(string.format(
            "photon: photon-toggle ignored (storm guard, %.2fs since last)", now - photon_toggle_last))
        return
    end
    photon_toggle_last = now
    photon_toggle_body()
end)

-- Compat shim (pass-5 #2): PPController addresses the photon section's
-- fold toggle to this script, but the fold handler lives in
-- photon-hud.lua. Forward until the Swift side retargets the message.
mp.register_script_message("photon-hud-toggle-fold", function(section)
    -- Target is photon_hud: mpv sanitizes script names (- -> _), so
    -- the dashed form is a dead address (field log shows [photon_hud]).
    mp.commandv("script-message-to", "photon_hud", "photon-hud-toggle-fold", section or "")
end)

--  B: ADAPTIVE BRIGHTNESS (Swift/ContentAdaptiveDimming) TOGGLE
--  Triggered by input.conf's "b script-message-to photon
--  photon-bright-toggle". cycle-values can't be used here (arbitrary
mp.register_script_message("photon-bright-toggle", function()
    local current = mp.get_property_bool("user-data/adaptive-brightness-enabled", false)
    local new_val = not current
    mp.set_property_native("user-data/adaptive-brightness-enabled", new_val)
    -- photon-hud.lua's bright section reads -active, not -enabled, so both
    -- must be written here. active is true only when the permission AND
    -- F9's global state are both true.
    mp.set_property_native("user-data/adaptive-brightness-active", new_val and enabled)
    -- Forces an immediate HUD re-read, same reason photon_toggle_body
    -- (F9) calls photon_publish_hud_state -- bright has no broadcast
    -- channel. Only fixes a stale read; see ambientWindowInterruptedUnsettled
    -- Same sanitization: photon_hud, not photon-hud (this forward
    -- never reached the HUD; masked because hud-state broadcasts carry
    -- the real updates).
    mp.commandv("script-message-to", "photon_hud", "photon-hud-force-redraw")
end)

-- photon state is bound to the gor session, not the mpv process.
-- AppDelegate.photonEnabled stores the user's last F9 decision across
mp.register_script_message("set-user-enabled", function(val)
    photon_user_enabled = (val == "true")
end)

-- Parallel contract for photon-chrome's independent 'c' toggle. Swift
-- syncs chrome_user_enabled the same way it syncs photon_user_enabled.
-- This listener was documented but never actually registered — Swift's
mp.register_script_message("set-chrome-user-enabled", function(val)
    chrome_user_enabled = (val == "true")
end)

-- Parallel contract for photon-negativ's independent 'n' toggle. Same
-- shape as chrome's listener above; forwarded to photon-negativ.lua in
-- file-loaded.
mp.register_script_message("set-negativ-user-enabled", function(val)
    negativ_user_enabled = (val == "true")
end)

-- (photon-sharp's 16 message handlers now live only in photon-sharp.lua.

--  LIVE MODE SIGNAL

mp.register_script_message("set-live", function(val)
    local new_live = (val == "true")
    if new_live == is_live then
        mp.msg.info("photon: set-live no-op (already " .. tostring(is_live) .. ")")
        return
    end
    is_live = new_live
    mp.msg.info("photon: is_live = " .. tostring(is_live))
    if SDR_STATE.sdr_timer then SDR_STATE.sdr_timer:kill(); SDR_STATE.sdr_timer = nil end
    if SDR_STATE.smooth_timer then SDR_STATE.smooth_timer:kill(); SDR_STATE.smooth_timer = nil end
    if SDR_STATE.radar_timer then SDR_STATE.radar_timer:kill(); SDR_STATE.radar_timer = nil end
    if is_live then
        LIVE_CALIB.samples = {}; RADAR_STATE.calib_done = false; RADAR_STATE.dynamic_neutral = CALIB_DEFAULT
        LIVE_CALIB.profile = nil; LIVE_CALIB.last_capture = -math.huge
        LIVE_CALIB.last_pbs = nil; LIVE_CALIB.last_profile_t = nil
        LIVE_CALIB.capture_failed = false; LIVE_CALIB.mode_logged = false
        mp.msg.info("photon: switched to sdr live mode")
        -- Race guard: is_live arrives via its own script-message,
        -- independent of file-loaded's 0.5s timeout — the native side may send
        gr_run_live_grain_probe()
    else
        remove_vf_filter()
        mp.msg.info("photon: switched to sdr vod mode")
    end
    detect_format(true)
end)

-- One shared mode writer. Hosts immediately push and publish their applied mode.
-- Test seam: not run, no native check; same-frame atomicity unverified.
local photon_adaptive_program = mp.get_opt("photon-adaptive-program") ~= "false"
local function photon_publish_adaptive_program()
    SIZE_GOV.program_on = photon_adaptive_program
    mp.commandv("script-message", "photon-adaptive-program-state", tostring(photon_adaptive_program))
end
function SIZE_GOV.toggle_body()
    photon_adaptive_program = not photon_adaptive_program
    GR.log_adaptive("toggle requested=" .. tostring(photon_adaptive_program))
    -- Reset geometry evidence and invalidate asynchronous work in both directions.
    SIZE_GOV.seed = nil; SIZE_GOV.applied = nil
    SIZE_GOV.ceiling = nil; SIZE_GOV.source = nil; SIZE_GOV.reset_history()
    GS.last_noise_share = nil; GS.last_noise_at = nil   -- 118h: mode change invalidates the reading
    SIZE_GOV.commit_resolution_fallback("adaptive-toggle")   -- 118b
    GS.hist = {}; GS.pair = nil; GS.last_mult = nil; GS.mhist = {}
    GS.probe_running = false; GS.next_probe_at = nil
    GS.est = nil; GS.samples = 0; GS.prev_luma = nil; GS.last_pos = nil
    grain_analysis_generation = grain_analysis_generation + 1
    grain_analysis_running = false; grain_analysis_samples = {}
    grain_size_hint_sent = false; grain_analysis_retries = 0
    gr_gs_committed_hint = false
    LG.gen = LG.gen + 1; LG.samples = {}
    if LG.timer then LG.timer:kill(); LG.timer = nil end
    photon_publish_adaptive_program()
    -- The receiver preserves a manual size override.
    mp.commandv("script-message", "photon-grain-set-size-hint", "1.0")
    mp.commandv("script-message", "photon-grain-size-evidence", photon_adaptive_program and "unmeasured" or "")
    mp.add_timeout(0.5, gr_run_grain_size_analysis)
    mp.add_timeout(0.5, gr_run_live_grain_probe)
end
mp.register_script_message("photon-adaptive-program-toggle", SIZE_GOV.toggle_body)
mp.add_key_binding("F10", "toggle-adaptive-program", SIZE_GOV.toggle_body)
mp.register_event("file-loaded", photon_publish_adaptive_program)
photon_publish_adaptive_program()

-- Publish the default-on family before the first file or key press.
photon_sync_bright_on_enable(enabled)
photon_publish_hud_state()


-- ---- COST METER reporter (observation only) ----
COST.cpu_prev = nil
COST.cpu_prev_t = nil
function COST.parse_cputime(s)
    local h, m, sec = s:match("^(%d+):(%d+):([%d%.]+)$")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec) end
    m, sec = s:match("^(%d+):([%d%.]+)$")
    if m then return tonumber(m) * 60 + tonumber(sec) end
    return nil
end
COST.procs = { "mpv", "gor", "ffmpeg", "WindowServer", "VTDecoderXPCService", "VTEncoderXPCService", "mediaanalysisd", "kernel_task" }
function COST.proc_line(cb)
    mp.command_native_async({
        name = "subprocess",
        args = {"ps", "-axo", "pid=,cputime=,comm="},
        capture_stdout = true, capture_stderr = false, playback_only = false,
    }, function(success, res)
        if not success or not res or res.status ~= 0 or type(res.stdout) ~= "string" then
            cb("proc=unavailable")
            return
        end
        local now = mp.get_time()
        local cur = {}
        COST.gor_best = nil
        for line in res.stdout:gmatch("[^\n]+") do
            local pid_, ct, comm = line:match("^%s*(%d+)%s+(%S+)%s+(.+)$")
            local secs = ct and COST.parse_cputime(ct)
            if secs then
                local base = comm:match("([^/]+)$") or comm
                if base == "gor" and (not COST.gor_best or secs >= COST.gor_best) then
                    COST.gor_best = secs
                    COST.gor_pid = tonumber(pid_)
                end
                for _, want in ipairs(COST.procs) do
                    if base == want or (want == "mpv" and base:find("^mpv")) then
                        cur[want] = (cur[want] or 0) + secs
                    end
                end
            end
        end
        local parts = {}
        if COST.cpu_prev and COST.cpu_prev_t and now > COST.cpu_prev_t then
            local dt = now - COST.cpu_prev_t
            for _, want in ipairs(COST.procs) do
                local a, b = COST.cpu_prev[want], cur[want]
                if a and b and b >= a then
                    parts[#parts + 1] = string.format("%s=%.0f%%", want, (b - a) / dt * 100)
                end
            end
        end
        COST.cpu_prev, COST.cpu_prev_t = cur, now
        cb("proc_cpu_pct(of one core)[" .. table.concat(parts, " ") .. "]")
    end)
end

-- gor-process sampler (diagnostic): the app process "gor" is the biggest
-- CPU user in the v2.2.4 run, but ps sees it only as one number. At about
-- 1, 3 and 6 minutes of playback the system tool /usr/bin/sample records
-- 3 s of its call stacks; the busiest functions and threads are copied as
-- "gor-sample" lines into /tmp/gor_diag.log, the raw file stays in
-- /tmp/gor_sample.txt (overwritten each time). Reads only; same flag.
COST.sample_on = true
COST.sample_ticks = { [6] = true, [18] = true, [36] = true }
COST.run_ticks = 0
COST.sample_busy = false
function COST.sample_gor()
    if not COST.sample_on or COST.sample_busy or not COST.gor_pid then return end
    COST.sample_busy = true
    local k = COST.run_ticks
    mp.command_native_async({
        name = "subprocess",
        args = {"/usr/bin/sample", tostring(COST.gor_pid), "3", "-file", "/tmp/gor_sample.txt"},
        capture_stdout = false, capture_stderr = true, playback_only = false,
    }, function(success, res)
        COST.sample_busy = false
        local ok_ = pcall(function()
            if not success or not res or res.status ~= 0 then
                COST.write("gor-sample[" .. k .. "] unavailable status=" .. tostring(res and res.status)
                    .. " err=" .. tostring(res and res.stderr or ""):sub(1, 160))
                return
            end
            local f = io.open("/tmp/gor_sample.txt", "r")
            if not f then COST.write("gor-sample[" .. k .. "] file missing") return end
            local txt = f:read("*a") or ""
            f:close()
            local n = 0
            for line in txt:gmatch("[^\n]+") do
                if line:match("^%s*%d+ Thread_%d+") then
                    n = n + 1
                    if n <= 12 then COST.write("gor-sample[" .. k .. "] thread " .. line:gsub("^%s+", ""):sub(1, 150)) end
                end
            end
            local i = txt:find("Sort by top of stack", 1, true)
            if i then
                local c = 0
                for line in txt:sub(i):gmatch("[^\n]+") do
                    c = c + 1
                    if c > 1 and c <= 31 then COST.write("gor-sample[" .. k .. "] top " .. line:gsub("^%s+", ""):sub(1, 150)) end
                end
            else
                COST.write("gor-sample[" .. k .. "] no top-of-stack section")
            end
        end)
        if not ok_ then COST.write("gor-sample[" .. k .. "] parse error") end
    end)
end
function COST.passes_line()
    local ok, passes = pcall(mp.get_property_native, "vo-passes")
    if not ok or type(passes) ~= "table" or type(passes.fresh) ~= "table" then
        return "vo-passes=unavailable"
    end
    local list = {}
    for _, p in ipairs(passes.fresh) do
        if type(p) == "table" and tonumber(p.avg) then
            list[#list + 1] = { desc = tostring(p.desc or "?"), avg = tonumber(p.avg), peak = tonumber(p.peak) or 0 }
        end
    end
    table.sort(list, function(a, b) return a.avg > b.avg end)
    local total, parts = 0, {}
    for _, p in ipairs(list) do total = total + p.avg end
    for i = 1, math.min(6, #list) do
        parts[#parts + 1] = string.format("%s=%.2fms(pk %.2f)", list[i].desc:sub(1, 32), list[i].avg / 1e6, list[i].peak / 1e6)
    end
    return string.format("vo-passes fresh n=%d sum=%.2fms top[%s]", #list, total / 1e6, table.concat(parts, " "))
end
function COST.diag_on() return COST.diag end
-- Isolated diagnostic log: /tmp/gor_diag.log (not the gor_direct stream).
-- Appends; stops writing past 20 MB so a long session cannot fill /tmp.
function COST.write(line)
    local f = io.open("/tmp/gor_diag.log", "a")
    if not f then return end
    -- Buffering must be set before any other operation on the stream.
    f:setvbuf("full", 8192)
    local size = f:seek("end") or 0
    if size < 20 * 1048576 then
        local prefix = os.date("%H:%M:%S") .. " "
        local text = tostring(line):gsub("[\r\n]", " ")
        local marker = "...[truncated]"
        local budget = 4096 - #prefix - 1
        if #text > budget then
            local stop = budget - #marker
            -- Move the cut before any UTF-8 continuation bytes.
            while stop > 0 and text:byte(stop + 1) >= 128 and text:byte(stop + 1) < 192 do
                stop = stop - 1
            end
            text = text:sub(1, stop) .. marker
        end
        -- One record, one write call: the buffer is larger than any record.
        f:write(prefix .. text .. "\n")
        f:flush()
    end
    f:close()
end
mp.add_periodic_timer(10, function()
  local ok_, err_ = pcall(function()
    local now = mp.get_time()
    local win = now - COST.window_start
    COST.window_start = now
    if not COST.diag_on() then
        COST.stats, COST.ff = {}, {}
        COST.cpu_prev, COST.cpu_prev_t = nil, nil
        return
    end
    local parts = {}
    local tags = {}
    for tag in pairs(COST.stats) do tags[#tags + 1] = tag end
    table.sort(tags)
    for _, tag in ipairs(tags) do
        local s = COST.stats[tag]
        if s.n > 0 or (s.shot_n or 0) > 0 or (s.reuse or 0) > 0 or (s.would or 0) > 0 then
            parts[#parts + 1] = string.format("%s n=%d shot=%.0fms pix=%.0fms max=%.0fms MB=%.0f fail=%d reuse=%d would=%d",
                tag, s.n, s.shot_ms, s.pix_ms, s.max_ms, s.bytes / 1048576, s.fail, s.reuse or 0, s.would or 0)
        end
        COST.stats[tag] = nil
    end
    local ff = {}
    for k, v in pairs(COST.ff) do ff[#ff + 1] = k .. "=" .. v end
    table.sort(ff)
    COST.ff = {}
    ff[#ff + 1] = string.format("wall_n=%d wall_ms=%.0f", COST.ffw_n, COST.ffw_ms)
    COST.ffw_n, COST.ffw_ms = 0, 0
    local w = tonumber((mp.get_property("video-params/w"))) or 0
    local h = tonumber((mp.get_property("video-params/h"))) or 0
    local state = string.format("photon_enabled=%s hdr=%s sdr=%s live=%s paused=%s res=%dx%d hwdec=%s shaders=%s",
        tostring(enabled), tostring(is_hdr), tostring(is_sdr), tostring(is_live),
        tostring(mp.get_property_native("pause")), w, h,
        tostring(mp.get_property("hwdec-current")),
        tostring(#(mp.get_property_native("glsl-shaders") or {})))
    local base = string.format("photon-cost: win=%.1fs %s | readback{%s} | ffmpeg_spawns{%s} | %s",
        win, state, table.concat(parts, " ; "), table.concat(ff, " "), COST.passes_line())
    COST.proc_line(function(procs)
        COST.write(base .. " | " .. procs)
    end)
    if mp.get_property_native("pause") == false then
        COST.run_ticks = COST.run_ticks + 1
        if COST.sample_ticks[COST.run_ticks] then COST.sample_gor() end
    end
  end)
  -- Diagnostics must never stop photon: a failure here is dropped, not raised.
  if not ok_ then COST.last_err = tostring(err_) end
end)
