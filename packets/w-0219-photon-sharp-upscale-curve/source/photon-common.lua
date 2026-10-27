-- ================================================================
--  photon-common.lua - shared photon helpers
--  Owns: hue math, shader path, parameter and feed helpers
--  Answers: I40 · TRAP-09
--  Contract: photon bootstrap precedes require; live shader values use parameters
-- ================================================================
--  Rules: Callers bootstrap this module before it can be required.
--  Shared helper changes belong here, not in caller aliases.
local math_max, math_min = math.max, math.min

local M = {}

-- Bumped on breaking changes to public functions (signature change,
-- removal). Callers check after require() and refuse to run against an
-- unexpected version.
M.VERSION = 2
M.MIN_COMPATIBLE_VERSION = 1  -- lowest caller-expected VERSION this module satisfies

-- Post-require version check every caller used to inline (only the script
-- name in the error differed). Returns true if compatible, false after
-- logging via mp.msg.error. Callers must still `return` themselves on
function M.check_version(caller_name, required_version)
    if not M.VERSION or M.VERSION < required_version
        or (M.MIN_COMPATIBLE_VERSION or M.VERSION) > required_version then
        mp.msg.error(string.format(
            "%s: photon-common version mismatch - expected VERSION %d, loaded %s. This script is disabled.",
            caller_name, required_version, tostring(M.VERSION)))
        return false
    end
    return true
end

-- Adaptive test seam: not run, no native check.
-- Decoded h is the unrotated source raster; output h is the VO raster.
-- Decline rotated/missing/zero rasters, never substitute screenshot dimensions.
local adaptive_raster_log = nil
function M.adaptive_rasters()
    -- Assumed from mpv property naming, check on the Mac; not binary-confirmed.
    local function read(name)
        local ok, value = pcall(mp.get_property_native, name)
        return ok and type(value) == "table" and value or nil
    end
    local src, source = read("video-dec-params"), "video-dec-params"
    if not src or type(src.h) ~= "number" or src.h ~= src.h or src.h <= 0 or src.h == math.huge
        or type(src.w) ~= "number" or src.w ~= src.w or src.w <= 0 or src.w == math.huge then
        src, source = read("video-params"), "video-params"
    end
    local out = read("video-out-params")
    local function positive(v)
        return type(v) == "number" and v == v and v > 0 and v < math.huge
    end
    -- Rendered picture raster in physical (backing) pixels, mpv 0.41
    -- vo_gpu-next on macOS, source-verified call chain:
    --  video/out/vulkan/context_mac.m mac_vk_control(VO_EVENT_RESIZE)
    --    -> window.framePixel (backing px) -> ra_vk_ctx_resize
    --    (vulkan/context.c) sets vo->dwidth/dheight in backing pixels on
    --    every window resize. gpu-next has no other Cocoa RA context in
    --    v0.41 (gpu/context.c context list): macvk is the only mac path.
    --  vo_gpu_next resize() -> vo_get_src_dst_rects -> mp_get_src_dst_rects
    --    (aspect.c) computes the video dst rect and OSD borders from
    --    dwidth/dheight incl. keepaspect letterbox, zoom, pan, crop.
    --  osd-dimensions (command.c mp_property_osd_dim) exposes that mp_osd_res:
    --    w/h = window in backing px, ml/mr/mt/mb = borders. The picture area
    --    is w-ml-mr by h-mt-mb, already physical pixels: no hidpi multiplier.
    local osd = read("osd-dimensions")
    if type(osd) == "table" and positive(osd.w) and positive(osd.h) then
        local pw = osd.w - (tonumber(osd.ml) or 0) - (tonumber(osd.mr) or 0)
        local ph = osd.h - (tonumber(osd.mt) or 0) - (tonumber(osd.mb) or 0)
        if pw > 0 and ph > 0 then
            out = { w = pw, h = ph, osd_picture = true }
        end
    end
    if type(src) ~= "table" or type(out) ~= "table"
        or not positive(src.h) or not positive(src.w) or not positive(out.h)
        or (tonumber(src.rotate) or 0) % 360 ~= 0 then
        if adaptive_raster_log ~= "unavailable" then
            adaptive_raster_log = "unavailable"
            mp.msg.info("photon adaptive rasters: unavailable, static fallback mpv=" .. tostring(mp.get_property("mpv-version")))
        end
        return nil
    end
    -- Effective 16:9-equivalent source height avoids classifying cropped scope as SD.
    local effective_h = math.max(src.h, src.w * 9 / 16)
    local identity = source .. ":" .. tostring(src.w) .. "x" .. tostring(src.h)
        .. ":effective=" .. tostring(effective_h) .. ":out=" .. tostring(math.floor(out.w + 0.5))
        .. "x" .. tostring(math.floor(out.h + 0.5)) .. (out.osd_picture and "/osd-dimensions" or "/video-out-params")
    if identity ~= adaptive_raster_log then
        adaptive_raster_log = identity
        mp.msg.info("photon adaptive rasters: " .. identity .. " mpv=" .. tostring(mp.get_property("mpv-version")))
    end
    return src.h, out.h, source, effective_h, src.w, out.w
end

-- Instrument-derived, Mac-pending; measured rows only, no k above1080.
local ADAPTIVE_LOW_K = {{480, .70}, {720, .93}, {1080, 1.00}}
function M.adaptive_strength_k(h)
    if type(h) ~= "number" or h ~= h or h <= 0 or h >= 1080 then return nil end
    if h <= 480 then return .70 end
    for i = 2, #ADAPTIVE_LOW_K do
        local lo, hi = ADAPTIVE_LOW_K[i - 1], ADAPTIVE_LOW_K[i]
        if h <= hi[1] then
            local t = math.log(h / lo[1]) / math.log(hi[1] / lo[1])
            return math.max(.70, math.min(1.00, math.floor((lo[2] + t * (hi[2] - lo[2])) * 100 + .5) / 100))
        end
    end
    return nil
end

M.HUE_EMA_ALPHA = 0.08

function M.clamp(v, lo, hi)
    return math_max(lo, math_min(hi, v))
end

-- Lerp between two hues on the wraparound wheel, short way around
-- (e.g. 0.99 -> 0.01 crosses 0, not 0.5).
function M.lerp_hue(a, b, t)
    if a == nil or b == nil then return nil end
    local d = b - a
    if d > 0.5 then d = d - 1.0
    elseif d < -0.5 then d = d + 1.0 end
    local h = a + d * t
    if h < 0 then h = h + 1.0
    elseif h >= 1.0 then h = h - 1.0 end
    return h
end

-- Shortest circular distance between two hues (0..0.5).
function M.hue_circular_dist(a, b)
    local d = math_max(a, b) - math_min(a, b)
    if d > 0.5 then d = 1.0 - d end
    return d
end

-- RGB (0..1 each) to hue in degrees, 0=red/120=green/240=blue. nil on
-- gray/achromatic input (max==min), same "no hue" contract as every hue
-- source in this family.
function M.rgb_to_hue_deg(r, g, b)
    local mx, mn = math_max(r, g, b), math_min(r, g, b)
    local d = mx - mn
    if d <= 0 then return nil end
    if mx == r then return 60.0 * (((g - b) / d) % 6.0)
    elseif mx == g then return 60.0 * (((b - r) / d) + 2.0)
    else return 60.0 * (((r - g) / d) + 4.0) end
end

-- Circular mean of hue angles (0-360): mean of unit vectors, so
-- wraparound near 0/360 (red tones) doesn't average to ~180.
function M.circular_mean_hue(hues_deg)
    if #hues_deg == 0 then return nil end
    local sum_cos, sum_sin = 0.0, 0.0
    for _, h in ipairs(hues_deg) do
        local rad = h * math.pi / 180.0
        sum_cos = sum_cos + math.cos(rad)
        sum_sin = sum_sin + math.sin(rad)
    end
    local mean_deg = math.atan2(sum_sin, sum_cos) * 180.0 / math.pi
    if mean_deg < 0 then mean_deg = mean_deg + 360.0 end
    return mean_deg
end

-- <config-dir>/shader/, with trailing slash, or nil if unset.
function M.shader_dir()
    local dir = mp.get_property("config-dir")
    if not dir then return nil end
    return dir:gsub("[/\\]+$", "") .. "/shader/"
end

local shader_dir_ready = false

-- <config-dir>/shader/<name>.glsl for one fixed shader file. A shader
-- path must stay stable for the whole mpv session: vo_gpu_next caches
-- parsed user shaders by path, so rewriting a file under the same path
function M.shader_path(name)
    local dir = M.shader_dir()
    if not dir then return nil end
    if not shader_dir_ready then
        os.execute(string.format('mkdir -p "%s" 2>/dev/null || mkdir "%s" >nul 2>nul', dir, dir))
        shader_dir_ready = true
    end
    return dir .. name .. ".glsl"
end

-- Dedups the caller's own current path(s) in a glsl-shaders list and
-- strips legacy photon A/B slot files (photon-*-shader-a/b.glsl and
-- photon-negativ-*-a/b.glsl) left behind by the pre-PARAM scheme — no
function M.ensure_glsl_list_sane(shaders, paths)
    local own = {}
    for _, p in ipairs(paths) do
        if p then own[p] = true end
    end
    local seen, out = {}, {}
    for _, p in ipairs(shaders) do
        local base = p:match("([^/\\]+)$") or p
        if base:match("^photon%-.+%-shader%-[ab]%.glsl$")
            or base:match("^photon%-negativ%-.+%-[ab]%.glsl$") then
            -- legacy A/B slot file: drop
        elseif own[p] then
            if not seen[p] then table.insert(out, p); seen[p] = true end
        else
            table.insert(out, p)
        end
    end
    return out
end

-- Pushes one effect's live values into the shared glsl-shader-opts
-- key/value list, targeted per shader file as "basename/KEY=value".
-- Uses change-list ... add (upsert) so other scripts' keys survive;
local push_last_payload = {}
function M.push_params(prefix, fields, force)
    local parts, cmp = {}, {}
    for _, f in ipairs(fields) do
        local key, value, kind = f[1], f[2], f[3]
        if kind == "i" then
            parts[#parts + 1] = string.format("%s/%s=%d", prefix, key, value)
            cmp[#cmp + 1] = string.format("%s=%d", key, value)
        else
            parts[#parts + 1] = string.format("%s/%s=%.6f", prefix, key, value)
            cmp[#cmp + 1] = string.format("%s=%.5f", key, value)
        end
    end
    local cmp_payload = table.concat(cmp, ",")
    if not force and push_last_payload[prefix] == cmp_payload then return false end
    push_last_payload[prefix] = cmp_payload
    mp.commandv("change-list", "glsl-shader-opts", "add", table.concat(parts, ","))
    return true
end

-- Decodes a "key=value;key=value;..." photon-scene-feed payload. A
-- missing field is absent from the table, not nil-valued.
function M.scene_kv_decode(payload)
    local parsed = {}
    for key, value in payload:gmatch("([%w_]+)=([^;]*)") do
        parsed[key] = value
    end
    return parsed
end

-- Encodes a payload from {key, value, kind} triples, kind is "num"
-- (%.4f) or "bool"/nil (tostring). A nil value omits the key entirely —
-- absence is structural, not a magic empty value. Write side of the
function M.scene_kv_encode(fields)
    local parts = {}
    for _, f in ipairs(fields) do
        local key, value, kind = f[1], f[2], f[3]
        if value ~= nil then
            if kind == "num" then
                parts[#parts + 1] = key .. "=" .. string.format("%.4f", value)
            else
                parts[#parts + 1] = key .. "=" .. tostring(value)
            end
        end
    end
    return table.concat(parts, ";")
end

-- Smooths a hue toward a new sample, snapping on a cut or first sample.
-- scale converts to/from lerp_hue's native 0..1 range (360.0 for 0..360
-- callers).
function M.smooth_hue(current, raw, alpha, snap, scale)
    if snap or current == nil then return raw end
    scale = scale or 1.0
    return M.lerp_hue(current / scale, raw / scale, alpha) * scale
end

-- Fresh char_track state table with all four fields at the same neutral
-- default and no pending dwell. Completes the construct/track/reset trio.
function M.new_char_state(default)
    return {signal = default, committed = default, rendered = default, dwell_start = nil}
end

-- Resets one char_track state table to a neutral default, no pending
-- dwell. Callers that iterate several parameters keep the loop; only the
-- per-state body is shared.
function M.reset_char_state(state, default)
    state.signal = default; state.committed = default
    state.rendered = default; state.dwell_start = nil
end

-- Long-EMA's raw into state.signal, holds state.committed until signal
-- drifts past dead_zone for dwell_min seconds (or a cut), then eases
-- state.rendered toward committed (faster after a cut).
function M.char_track(state, raw, now, dt, is_cut, tau, dead_zone, dwell_min, ease_tau, cut_ease_tau)
    local alpha = 1.0 - math.exp(-dt / tau)
    state.signal = state.signal + alpha * (raw - state.signal)

    local drift = math_max(state.signal, state.committed) - math_min(state.signal, state.committed)
    if drift <= dead_zone and not is_cut then
        state.dwell_start = nil
    else
        if state.dwell_start == nil then state.dwell_start = now end
        local held = now - state.dwell_start
        if is_cut or held >= dwell_min then
            state.committed = state.signal
            state.dwell_start = nil
        end
    end

    local ease_alpha = 1.0 - math.exp(-dt / (is_cut and cut_ease_tau or ease_tau))
    state.rendered = state.rendered + ease_alpha * (state.committed - state.rendered)
    return state.rendered
end

-- Exponential smoothing, different time constant for rising
-- (tau_attack) vs falling (tau_release) target.
function M.asym_smooth(current, target, tau_attack, tau_release, dt)
    local tau = (target > current) and tau_attack or tau_release
    local alpha = 1.0 - math.exp(-dt / tau)
    return current + alpha * (target - current)
end

-- Provisional C trace: explicit opt-in, independent per-script rings.
-- No timer, screenshot or probe cadence change. Clean shutdown flush only.
local trace_rows, trace_dropped, trace_seq = {}, 0, 0
function M.trace_record(kind, fields)
    if mp.get_opt("gor-stress-trace") ~= "true" then return end
    trace_seq = trace_seq + 1
    local row = fields or {}
    row.kind, row.seq, row.uptime_s = kind, trace_seq, mp.get_time()
    row.script = mp.get_script_name()
    if #trace_rows == 512 then table.remove(trace_rows, 1); trace_dropped = trace_dropped + 1 end
    trace_rows[#trace_rows + 1] = row
end
function M.trace_flush()
    if mp.get_opt("gor-stress-trace") ~= "true" then return end
    local directory = mp.get_opt("gor-stress-trace-dir")
    if not directory or directory == "" then return end
    local utils = require "mp.utils"
    local path = directory .. "/" .. mp.get_script_name() .. "-" .. tostring(os.time()) .. ".jsonl"
    local file, err = io.open(path, "a")
    -- Append preserves prior evidence if two flushes share a wall-clock second.
    if not file then mp.msg.warn("C trace flush unavailable: " .. tostring(err)); return end
    for _, row in ipairs(trace_rows) do file:write(utils.format_json(row), "\n") end
    file:write(utils.format_json({kind="flush", dropped=trace_dropped,
        source_binding="UNINTEGRATED_BASELINE_PENDING", ipc_ack="NOT_BOUND"}), "\n")
    file:close()
end
mp.register_event("shutdown", M.trace_flush)

return M
