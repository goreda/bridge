-- ================================================================
--  photon-hud.lua - photon status HUD
--  Owns: fold state and status aggregation
--  Contract: photon bootstrap precedes require; live shader values use parameters
-- ================================================================
if mp.get_opt('gor-diag') == 'true' then
    local d = io.open("/tmp/gor_diag.log", "a")
    if d then d:write("photon-ident photon-hud.lua v2.2.17 loaded " .. os.date("%H:%M:%S") .. "\n"); d:close() end
end
local script_dir = mp.get_opt("photon-scriptdir")
if script_dir then
    local probe = io.open(script_dir .. "/photon-common.lua", "r")
    if probe then
        probe:close()
        package.path = script_dir .. "/?.lua;" .. package.path
    else
        mp.msg.error("photon-hud: photon-scriptdir invalid or photon-common.lua missing - checked: " .. script_dir .. "/photon-common.lua")
    end
end
local common_ok, common = pcall(require, "photon-common")
if not common_ok then
    mp.msg.error("photon-hud: could not load photon-common - " .. tostring(common) .. ". This script is disabled.")
    return
end
local PHOTON_HUD_REQUIRED_COMMON_VERSION = 1
if not common.check_version("photon-hud", PHOTON_HUD_REQUIRED_COMMON_VERSION) then
    return
end


-- Explain WHY, not what. Max 3 lines — one for a non-obvious default,


-- Display-boundary guard for every numeric field arriving via hud-state
-- script-messages. Plain tonumber trusts the sender; a corrupt payload
-- (NaN, inf, or a value outside the field's physical domain - e.g. the
-- x10^18 fixed-point garbage observed in the field) must never reach the
-- OSD. Out-of-domain values hold the last good sample instead and warn
-- once per field so the sender can be tracked down. In-domain values pass
-- through bit-identical to tonumber, and a nil arg keeps the caller's
-- original fallback exactly like "tonumber(s) or fallback" did.
local hud_guard = { last = {}, logged = {} }
function hud_guard.num(field, str, lo, hi, fallback)
    -- Empty string is "no value yet": senders emit "" for unset optional
    -- fields on their first broadcast (grain hint values, chrome/negativ
    -- hue). Same as absent — hold silently, no corrupt warn.
    if str == nil or str == "" then return fallback end
    local v = tonumber(str)
    if v == nil or v ~= v or v == math.huge or v == -math.huge or v < lo or v > hi then
        if not hud_guard.logged[field] then
            hud_guard.logged[field] = true
            mp.msg.warn(string.format(
                "photon-hud: ignoring corrupt %s value %s - holding last good",
                field, tostring(str)))
        end
        local last = hud_guard.last[field]
        if last ~= nil then return last end
        return fallback
    end
    hud_guard.last[field] = v
    return v
end

-- draw_hud is forward-declared: closures below capture it as an upvalue
-- before its body is assigned further down.
local draw_hud

local HUD_UPDATE_INTERVAL = 0.25

-- Grouped to stay under Lua's 200 top-level-local limit.
local HUD_STATE = {
    enabled       = false,
    grain_state   = nil,
    chrome_state  = nil,
    negativ_state = nil,
    photon_state  = nil,
    timer         = nil,
    cost_probe    = mp.get_opt("gor-hud-cost-probe") == "true",
    cost_frames   = 0,
    cost_rows     = 0,
    cost_bytes    = 0,
    cost_seconds  = 0,
    cost_same     = 0,
    cost_last     = nil,
}

-- State bridge is independent of HUD visibility and fold animation.
-- Deduplication avoids forwarding every scene-feed sample to the menu.
local menu_state = {}
local function publish_menu_state(key, enabled)
    if menu_state[key] == enabled then return end
    menu_state[key] = enabled
    print("gor-photon-menu:" .. key .. "=" .. (enabled and "1" or "0"))
end

local function publish_chrome_menu_state(enabled_str, manual_filter_str)
    local enabled = enabled_str == "true"
    publish_menu_state("chrome", enabled)
    publish_menu_state("chrome-filter", enabled and manual_filter_str == "true")
end

publish_menu_state("hud", HUD_STATE.enabled)
publish_menu_state("photon", mp.get_opt("photon-menu-enabled") ~= "false")
publish_menu_state("bright", mp.get_opt("photon-menu-enabled") ~= "false")
publish_menu_state("sharp", mp.get_opt("photon-menu-enabled") ~= "false")
publish_menu_state("grain", mp.get_opt("photon-menu-enabled") ~= "false")
publish_menu_state("chrome", false)
publish_menu_state("chrome-filter", false)
publish_menu_state("negativ", false)
mp.observe_property("user-data/adaptive-brightness-active", "bool", function(_, active)
    -- nil means the engine has not published yet, not an OFF decision.
    if active ~= nil then publish_menu_state("bright", active == true) end
end)

-- Indentation for HUD sub-parameter lines; centralized so all sections stay aligned.
local HUD_INDENT = string.rep(" ", 6)

-- Detailed grain/sharp telemetry is diagnostic output, never screen copy.
local last_adaptive_detail_at = -math.huge
local function log_adaptive_detail(sharp, grain)
    local now = mp.get_time()
    if now - last_adaptive_detail_at < 5 then return end
    last_adaptive_detail_at = now
    mp.msg.info("photon-adaptive-detail " .. sharp:gsub("\n", " | ")
        .. " || " .. grain:gsub("\n", " | "))
end


-- Per-section fold state. Keys must match the section-id prefix draw_hud
-- writes into each line (Swift's click handler reads that prefix, not a
-- separately maintained id). photon/bright default open, the rest default
local hud_fold_state = {
    photon  = { revealed = math.huge, direction = -1, timer = nil },
    bright  = { revealed = math.huge, direction = -1, timer = nil },
    sharp   = { revealed = math.huge, direction = -1, timer = nil },
    grain   = { revealed = math.huge, direction = -1, timer = nil },
    chrome  = { revealed = 0, direction = 1, timer = nil },
    negativ = { revealed = 0, direction = 1, timer = nil },
}

-- Splits a "\n  line1\n  line2..." body into individual lines.
local function split_lines(body)
    if body == "" then return {} end
    local out = {}
    for line in (body:sub(2) .. "\n"):gmatch("(.-)\n") do
        table.insert(out, line)
    end
    return out
end

-- Trims a "phot%s <name>\n  <sub-lines>" block to the section's fold state.
-- known_total_lines lets a caller skip building the full body when folded,
-- while still giving apply_fold the true line count it needs for clamp/flip.
local function apply_fold(info_text, section, known_total_lines)
    local nl = info_text:find("\n", 1, true)
    local title  = nl and info_text:sub(1, nl - 1) or info_text
    local body   = nl and info_text:sub(nl) or ""
    local prefix = section .. "\t"

    local state = hud_fold_state[section]
    if not state then
        -- Unknown section: fail open rather than silently dropping data.
        return prefix .. title .. body
    end

    local lines      = split_lines(body)
    local totalLines = known_total_lines or #lines
    state.justFlipped = false
    if state.revealed == totalLines and state.direction > 0 then
        state.direction    = -1
        state.justFlipped   = true
    elseif state.revealed == 0 and state.direction < 0 then
        state.direction    = 1
        state.justFlipped   = true
    end
    if state.revealed > totalLines then state.revealed = totalLines end
    if state.revealed < 0         then state.revealed = 0         end

    if state.revealed <= 0 then
        return prefix .. title
    end
    if state.revealed >= totalLines then
        local prefixed = {}
        for i = 1, totalLines do
            table.insert(prefixed, prefix .. lines[i])
        end
        return prefix .. title .. "\n" .. table.concat(prefixed, "\n")
    end
    local shown = {}
    for i = 1, state.revealed do
        table.insert(shown, prefix .. lines[i])
    end
    return prefix .. title .. "\n" .. table.concat(shown, "\n")
end

-- Animates fold/unfold at the same 0.04s cadence as SpineUI's typewriter
-- effect, one line per tick, so clicking doesn't jump-cut the section.
-- from_within_draw_hud=true skips the immediate draw_hud() call (used when
local function start_fold_animation(state, from_within_draw_hud)
    state.revealed = state.revealed + state.direction
    state.justFlipped = false
    if not from_within_draw_hud then
        draw_hud()
    end
    if (not from_within_draw_hud) and state.justFlipped then
        return
    end

    state.timer = mp.add_periodic_timer(0.04, function()
        -- A one-line section completes its fold inside the draw that STARTED
        -- the animation (the sync_fold path): apply_fold flips direction and
        -- sets justFlipped there, but the from-within branch above already
        -- skipped its guard, so without this check the first tick below fires
        -- with the flipped direction and instantly undoes the fold.
        if state.justFlipped then
            state.timer:kill()
            state.timer = nil
            return
        end
        state.revealed = state.revealed + state.direction
        draw_hud()
        if state.justFlipped then
            state.timer:kill()
            state.timer = nil
        end
    end)
end

-- Fired by a click on a section title/line (see PPController's onFoldToggle).
mp.register_script_message("photon-hud-toggle-fold", function(section)
    local state = hud_fold_state[section]
    if not state then return end

    if state.timer then
        -- Animation already running: just reverse direction, don't restart.
        state.direction = -state.direction
        return
    end

    start_fold_animation(state)
end)

-- Mirrors a subsystem's enabled state into its fold state (unfold on enable,
-- fold on disable) without overriding a manual click the user already made.
-- last_enabled starts nil so the initial hardcoded revealed/direction values
local function sync_fold_to_enabled_state(section, is_enabled)
    local state = hud_fold_state[section]
    if not state then return end

    if state.last_enabled == nil then
        state.last_enabled = is_enabled
        return
    end
    if state.last_enabled == is_enabled then return end
    state.last_enabled = is_enabled

    if state.timer then return end

    local needs_open  = is_enabled and state.revealed == 0
    local needs_close = (not is_enabled) and state.revealed > 0
    if not (needs_open or needs_close) then return end

    state.direction = is_enabled and 1 or -1
    start_fold_animation(state, true)
end

-- Listeners below receive each subsystem's own state via broadcast
-- script-message (not script-message-to), published by that subsystem's VM.

mp.register_event("file-loaded", function()
    HUD_STATE.grain_measure_status = nil
    HUD_STATE.grain_measure_at = nil
end)

mp.register_script_message("photon-grain-measure-status", function(value)
    HUD_STATE.grain_measure_status = value
    HUD_STATE.grain_measure_at = mp.get_time()
end)

function HUD_STATE.measure_reason(why)
    local function starts(prefix) return why:sub(1, #prefix) == prefix end
    if starts("shot-fail") or starts("shot-fields") or starts("data-not-string") or starts("short-row") then
        return "not measured: capture failed"
    elseif starts("crop<96") then return "not measured: frame too small"
    elseif starts("capture-no-luma") or starts("no-frame-height") then return "not measured: frame unreadable"
    elseif starts("blocks<6") then return "not measured: too few blocks"
    elseif starts("zero-hp") then return "not measured: frame too flat"
    elseif starts("stale-mirror") then return "not measured: stale grain mirror"
    elseif starts("soft<") then return "not measured: softness outside table"
    elseif starts("no-eff") then return "not measured: effective size outside table"
    elseif starts("over-corrected-source-power") or starts("garbage-curve") or starts("source-share-below-floor") then
        return "not measured: no valid size signal"
    end
    return "not measured: see log for reason"
end

mp.register_script_message("photon-grain-size-evidence", function(value)
    HUD_STATE.size_evidence = value
end)

mp.register_script_message("photon-grain-hud-state", function(
    enabled_str, amount_str, fps_str,
    size_base_str, hint_received_str, hint_suppressed_str, hint_value_str,
    hue_has_data_str, hue_str,
    strength_base_str, strength_hint_received_str, strength_hint_suppressed_str, strength_hint_value_str,
    size_rendered_str, development_rendered_str, softness_rendered_str,
    amount_rendered_str, user_offset_str, weight_shift_str, res_adapt_str, target_enabled_str,
    source_h_str, output_h_str, coefficient_str, strength_k_str, adaptive_mode_str, strength_status_str, render_density_str,
    effective_h_str, strength_src_str, size_trim_str, doc_gen_str, serial_str, control_revision_str, effective_size_str)
    publish_menu_state("grain", (target_enabled_str or enabled_str) == "true")
    HUD_STATE.grain_state = {
        enabled = (enabled_str == "true"),
        amount  = hud_guard.num("grain.amount", amount_str, 0.0, 1000.0, 0.0),
        fps     = hud_guard.num("grain.fps", fps_str, 0.0, 1000.0, 0.0),
        size_base       = hud_guard.num("grain.size_base", size_base_str, 0.0, 100.0, 0.0),
        size_rendered = hud_guard.num("grain.size_rendered", size_rendered_str, 0.0, 100.0, 0.0),
        effective_size = effective_size_str ~= "na" and hud_guard.num("grain.effective_size", effective_size_str, 0.0, 100.0, nil) or nil,
        hint_received   = (hint_received_str == "true"),
        hint_suppressed = (hint_suppressed_str == "true"),
        hint_value      = hud_guard.num("grain.hint_value", hint_value_str, 0.0, 100.0, nil),
        hue_has_data    = (hue_has_data_str == "true"),
        hue             = hud_guard.num("grain.hue", hue_str, 0.0, 360.0, 0.0),
        source_h = hud_guard.num("grain.source_h", source_h_str, 0.0, 100000.0, 0.0),
        output_h = hud_guard.num("grain.output_h", output_h_str, 0.0, 100000.0, 0.0),
        coefficient = hud_guard.num("grain.coefficient", coefficient_str, 0.0, 2.0, 0.0),
        strength_k = hud_guard.num("grain.strength_k", strength_k_str, 0.0, 2.0, nil),
        adaptive_mode = adaptive_mode_str == "true",
        strength_status = strength_status_str,
        render_density = hud_guard.num("grain.render_density", render_density_str, .0, 1.0, nil),
        strength_base            = hud_guard.num("grain.strength_base", strength_base_str, 0.0, 1000.0, 0.0),
        strength_src             = strength_src_str,
        size_trim                = hud_guard.num("grain.size_trim", size_trim_str, 0.0, 100.0, 1.0),
        strength_hint_received   = (strength_hint_received_str == "true"),
        strength_hint_suppressed = (strength_hint_suppressed_str == "true"),
        strength_hint_value      = hud_guard.num("grain.strength_hint_value", strength_hint_value_str, 0.0, 1000.0, nil),
    }
end)

mp.register_script_message("photon-chrome-hud-state", function(
    enabled_str, filter_idx_str, filter_strength_str, contrast_str, has_feed_str,
    hue_driven_str, hue_str, shadow_lift_str, highlight_rolloff_str, mono_grain_str,
    arc_clamped_str, manual_filter_str)
    publish_chrome_menu_state(enabled_str, manual_filter_str)
    HUD_STATE.chrome_state = {
        enabled           = (enabled_str == "true"),
        filter_idx        = hud_guard.num("chrome.filter_idx", filter_idx_str, 0.0, 100.0, 0),
        filter_strength   = hud_guard.num("chrome.filter_strength", filter_strength_str, 0.0, 100.0, 0.0),
        contrast_amount   = hud_guard.num("chrome.contrast", contrast_str, -100.0, 100.0, 0.0),
        has_feed          = (has_feed_str == "true"),
        hue_driven        = (hue_driven_str == "true"),
        hue               = hud_guard.num("chrome.hue", hue_str, 0.0, 360.0, nil),
        shadow_lift       = hud_guard.num("chrome.shadow_lift", shadow_lift_str, -100.0, 100.0, 0.0),
        highlight_rolloff = hud_guard.num("chrome.highlight_rolloff", highlight_rolloff_str, 0.0, 1000.0, 0.0),
        mono_grain        = (mono_grain_str == "true"),
        arc_clamped       = (arc_clamped_str == "true"),
    }
end)


mp.register_script_message("photon-negativ-hud-state", function(
    enabled_str, stock_idx_str, mask_gain_str, gamma_str, has_feed_str,
    hue_driven_str, hue_str, arc_clamped_str, mode_str)
    publish_menu_state("negativ", enabled_str == "true")
    HUD_STATE.negativ_state = {
        enabled     = (enabled_str == "true"),
        stock_idx   = hud_guard.num("negativ.stock_idx", stock_idx_str, 1.0, 100.0, 1),
        mask_gain   = hud_guard.num("negativ.mask_gain", mask_gain_str, 0.0, 1000.0, 0.0),
        gamma       = hud_guard.num("negativ.gamma", gamma_str, 0.0, 100.0, 0.0),
        has_feed    = (has_feed_str == "true"),
        hue_driven  = (hue_driven_str == "true"),
        hue         = hud_guard.num("negativ.hue", hue_str, 0.0, 360.0, nil),
        arc_clamped = (arc_clamped_str == "true"),
        mode        = mode_str or "mask",
    }
end)

local photon_sharp_hud_state = { enabled = false }
mp.register_script_message("photon-sharp-hud-state", function(
    enabled_str, shader_ready_str, current_algo_str, user_strength_str, smooth_coarse_str,
    global_factor_str, halo_guard_str, texture_bias_str,
    fine_strength_str, medium_strength_str, coarse_strength_str,
    content_adapt_str, temporal_mode_str, ring_damp_str, target_enabled_str,
    source_h_str, output_h_str, multiplier_str, adaptive_mode_str, applied_factor_str, base_amount_str)
    publish_menu_state("sharp", (target_enabled_str or enabled_str) == "true")
    photon_sharp_hud_state = {
        enabled          = (enabled_str == "true"),
        shader_ready     = (shader_ready_str == "true"),
        current_algo     = hud_guard.num("sharp.current_algo", current_algo_str, 0.0, 100.0, 0),
        user_strength    = hud_guard.num("sharp.user_strength", user_strength_str, 0.0, 1000.0, 0.0),
        smooth_coarse    = hud_guard.num("sharp.smooth_coarse", smooth_coarse_str, 0.0, 1000.0, 0.0),
        global_factor    = hud_guard.num("sharp.global_factor", global_factor_str, 0.0, 100.0, 0.0),
        halo_guard       = hud_guard.num("sharp.halo_guard", halo_guard_str, 0.0, 100.0, 0.0),
        texture_bias     = hud_guard.num("sharp.texture_bias", texture_bias_str, 0.0, 100.0, 0.0),
        fine_strength    = hud_guard.num("sharp.fine_strength", fine_strength_str, 0.0, 1000.0, 0.0),
        medium_strength  = hud_guard.num("sharp.medium_strength", medium_strength_str, 0.0, 1000.0, 0.0),
        coarse_strength  = hud_guard.num("sharp.coarse_strength", coarse_strength_str, 0.0, 1000.0, 0.0),
        content_adapt    = hud_guard.num("sharp.content_adapt", content_adapt_str, 0.0, 100.0, 0),
        temporal_mode    = hud_guard.num("sharp.temporal_mode", temporal_mode_str, 0.0, 100.0, 0),
        ring_damp        = hud_guard.num("sharp.ring_damp", ring_damp_str, 0.0, 100.0, 0.0),
        source_h = hud_guard.num("sharp.source_h", source_h_str, 0.0, 100000.0, 0.0),
        output_h = hud_guard.num("sharp.output_h", output_h_str, 0.0, 100000.0, 0.0),
        multiplier = hud_guard.num("sharp.multiplier", multiplier_str, 0.0, 100.0, 1.0),
        adaptive_mode = adaptive_mode_str == "true",
        applied_factor = hud_guard.num("sharp.applied_factor", applied_factor_str, 0.0, 100.0, nil),
        base_amount = hud_guard.num("sharp.base_amount", base_amount_str, 0.0, 1000.0, nil),
    }
end)

-- photon.lua's own HDR/SDR/scene state isn't reachable across VMs. Raw
-- values only — this VM builds its own display string below, same as
-- chrome/grain/negativ/sharp. Field order must match photon.lua's call.
mp.register_script_message("photon-photon-hud-state", function(
    enabled_str, scene_smooth_peak_str, scene_smooth_contrast_str,
    scene_smooth_noise_str, scene_motion_str, scene_has_feed_str,
    is_hdr_str, is_live_str,
    hdr_peak_str, hdr_vel_str, hdr_avg_str, hdr_drive_str,
    hdr_contrast_str, hdr_cut_thr_str, hdr_pq_str, hdr_dark_thresh_str, hdr_bright_thresh_str,
    sdr_pbs_str, sdr_vel_str, sdr_gamma_str, sdr_neutral_str,
    live_calib_ready_str, live_calib_samples_str, live_calib_frames_str,
    radar_buffer_len_str, radar_buffer_miss_str,
    ring_str, rlevel_str)
    publish_menu_state("photon", enabled_str == "true")
    HUD_STATE.photon_state = {
        enabled               = (enabled_str == "true"),
        scene_smooth_peak     = hud_guard.num("photon.scene_smooth_peak", scene_smooth_peak_str, 0.0, 1.0, 0.0),
        scene_smooth_contrast = hud_guard.num("photon.scene_smooth_contrast", scene_smooth_contrast_str, 0.0, 1.0, 0.0),
        scene_smooth_noise    = hud_guard.num("photon.scene_smooth_noise", scene_smooth_noise_str, 0.0, 1.0, 0.0),
        scene_motion          = hud_guard.num("photon.scene_motion", scene_motion_str, 0.0, 1.0, 0.0),
        scene_has_feed        = (scene_has_feed_str == "true"),
        is_hdr                = (is_hdr_str == "true"),
        is_live               = (is_live_str == "true"),
        hdr_peak              = hud_guard.num("photon.hdr_peak", hdr_peak_str, 0.0, 100000.0, 0.0),
        hdr_vel               = hud_guard.num("photon.hdr_vel", hdr_vel_str, -5000.0, 5000.0, 0.0),
        hdr_avg               = hud_guard.num("photon.hdr_avg", hdr_avg_str, 0.0, 1.0, 0.0),
        hdr_drive             = hud_guard.num("photon.hdr_drive", hdr_drive_str, 0.0, 1.0, 0.0),
        hdr_contrast          = hud_guard.num("photon.hdr_contrast", hdr_contrast_str, 0.0, 1.0, 0.0),
        hdr_cut_thr           = hud_guard.num("photon.hdr_cut_thr", hdr_cut_thr_str, 0.0, 1.0, 0.0),
        hdr_pq                = hud_guard.num("photon.hdr_pq", hdr_pq_str, 0.0, 1.0, 0.0),
        hdr_dark_thresh       = hud_guard.num("photon.hdr_dark_thresh", hdr_dark_thresh_str, 0.0, 1.0, 0.0),
        hdr_bright_thresh     = hud_guard.num("photon.hdr_bright_thresh", hdr_bright_thresh_str, 0.0, 1.0, 0.0),
        sdr_pbs               = hud_guard.num("photon.sdr_pbs", sdr_pbs_str, 0.0, 10000.0, 0.0),
        sdr_vel               = hud_guard.num("photon.sdr_vel", sdr_vel_str, -10000.0, 10000.0, 0.0),
        -- gamma adapts within +/-GAMMA_MAX (7.5) by design: negative
        -- darkens bright scenes. The 0..10 guard rejected every negative
        -- as "corrupt" (v14 field logs, -1.8750 on bright SDR content).
        sdr_gamma             = hud_guard.num("photon.sdr_gamma", sdr_gamma_str, -7.5, 7.5, 0.0),
        sdr_neutral           = hud_guard.num("photon.sdr_neutral", sdr_neutral_str, 0.0, 10000.0, 0.0),
        live_calib_ready      = (live_calib_ready_str == "true"),
        live_calib_samples    = hud_guard.num("photon.live_calib_samples", live_calib_samples_str, 0.0, 1000000.0, 0),
        live_calib_frames     = hud_guard.num("photon.live_calib_frames", live_calib_frames_str, 0.0, 1000000.0, 0),
        radar_buffer_len      = hud_guard.num("photon.radar_buffer_len", radar_buffer_len_str, 0.0, 10000000.0, 0),
        radar_buffer_miss     = (radar_buffer_miss_str == "true"),
        ring                  = hud_guard.num("photon.ring", ring_str, 0.0, 1000.0, 0.0),
        rlevel                = hud_guard.num("photon.rlevel", rlevel_str, 0.0, 1.0, 0.0),
    }
end)

draw_hud = function()
    if not HUD_STATE.enabled then return end
    local cost_started = HUD_STATE.cost_probe and os.clock() or nil

    -- Section 1: photon (HDR / SDR). photon.lua sends raw numbers only
    -- (its own state isn't reachable from this VM); this VM builds the
    -- display string itself, same pattern as sharp/grain/chrome/negativ.
    local pst          = HUD_STATE.photon_state
    local photon_status = pst and (pst.enabled and "on" or "off") or "?"
    local PHOTON_TOTAL_LINES = 4
    if pst then
        sync_fold_to_enabled_state("photon", pst.enabled)
    end
    local photon_info, photon_known_lines
    local photon_skip_fold = false
    if not pst then
        photon_info = "phot? photon\n" .. HUD_INDENT .. "waiting for photon.lua…"
        photon_skip_fold = true
    elseif hud_fold_state.photon.revealed <= 0 then
        photon_info = string.format("phot%s %s", photon_status, pst.is_hdr and "hdr" or "sdr")
        photon_known_lines = PHOTON_TOTAL_LINES
    elseif pst.is_hdr then
        local zone = pst.hdr_pq < pst.hdr_dark_thresh   and "dark"   or
                     pst.hdr_pq > pst.hdr_bright_thresh and "bright" or "mid"
        photon_info = string.format(
            "phot%s hdr%s\n"
         .. HUD_INDENT .. "peak: %d nit   vel: %+.1f nit/s\n"
         .. HUD_INDENT .. "avg-pq: %.4f   hybrid: %.4f\n"
         .. HUD_INDENT .. "contrast ∂: %.4f   cut@: %.4f\n"
         .. HUD_INDENT .. "scene: %s   ring: %.1f (lvl %.2f)",
            photon_status, pst.is_live and "  live" or "",
            math.floor(pst.hdr_peak), pst.hdr_vel,
            pst.hdr_avg, pst.hdr_drive, pst.hdr_contrast, pst.hdr_cut_thr, zone,
            pst.ring, pst.rlevel)
        photon_known_lines = PHOTON_TOTAL_LINES
    else
        local mode
        if pst.is_live then
            mode = string.format("live  vf-metadata  calib: %s",
                pst.live_calib_ready
                    and string.format("%.0f", pst.sdr_neutral)
                    or  string.format("%d/%d", pst.live_calib_samples, pst.live_calib_frames))
        elseif pst.radar_buffer_len > 0 and not pst.radar_buffer_miss then
            mode = string.format("radar  %d frames", pst.radar_buffer_len)
        elseif pst.radar_buffer_miss then
            mode = "seek → probe"
        else
            mode = "probe (warming up)"
        end
        local zone = pst.sdr_pbs < pst.sdr_neutral * 0.6 and "dark"   or
                     pst.sdr_pbs > pst.sdr_neutral * 1.4 and "bright" or "mid"
        photon_info = string.format(
            "phot%s sdr\n"
         .. HUD_INDENT .. "%s\n"
         .. HUD_INDENT .. "pbs: %.1f   vel: %+.1f/s\n"
         .. HUD_INDENT .. "gamma: %.2f   neutral: %.0f\n"
         .. HUD_INDENT .. "scene: %s   ring: %.1f (lvl %.2f)",
            photon_status, mode, pst.sdr_pbs, pst.sdr_vel, pst.sdr_gamma, pst.sdr_neutral, zone,
            pst.ring, pst.rlevel)
        photon_known_lines = PHOTON_TOTAL_LINES
    end

    -- Section 2: photon-sharp.
    local ss            = photon_sharp_hud_state
    local shader_status = (not ss.enabled) and "off"
        or (ss.shader_ready and "on" or "off")
    sync_fold_to_enabled_state("sharp", ss.enabled)
    local SHARP_TOTAL_LINES = 6
    local photon_sharp_info, sharp_known_lines
    if hud_fold_state.sharp.revealed <= 0 then
        photon_sharp_info = string.format("phot%s sharp", shader_status)
        sharp_known_lines = SHARP_TOTAL_LINES
    else
        local algo_names    = {"Hybrid", "Perceptual", "Structural", "Conservative", "Aggressive"}
        local algo_name     = algo_names[(ss.current_algo or 0) + 1] or "?"
        local temporal_name = (ss.temporal_mode == 1) and "Phase2(buf)" or "Phase1(EMA)"
        local content_name  = (ss.content_adapt == 1) and "on" or "off"
        local pst = HUD_STATE.photon_state or {}
        photon_sharp_info = string.format(
            "phot%s sharp\n"
         .. HUD_INDENT .. "global: %.2f   halo: %.2f   texture: %.2f\n"
         .. HUD_INDENT .. "peak: %.2f   contrast: %.2f   noise: %.2f\n"
         .. HUD_INDENT .. "motion: %.2f   amount: %.2f   fine-mix: %.2f%s\n"
         .. HUD_INDENT .. "algo: %s  bands  F: %.2f  M: %.2f  C: %.2f\n"
         .. HUD_INDENT .. "content-adapt: %s   temporal: %s",
            shader_status,
            ss.global_factor or 0.0, ss.halo_guard or 0.0, ss.texture_bias or 0.0,
            pst.scene_smooth_peak or 0.0, pst.scene_smooth_contrast or 0.0, pst.scene_smooth_noise or 0.0,
            pst.scene_motion or 0.0, ss.user_strength or 0.0, ss.smooth_coarse or 0.0,
            ((ss.ring_damp or 0.0) > 0.01
                and string.format("   ring: -%.0f%%", (ss.ring_damp or 0.0) * 55) or ""),
            algo_name, ss.fine_strength or 0.0, ss.medium_strength or 0.0, ss.coarse_strength or 0.0,
            content_name, temporal_name)
        if ss.adaptive_mode ~= nil then
            photon_sharp_info = photon_sharp_info .. "\n" .. HUD_INDENT .. string.format(
                "adaptive: %s   src/out: %.0f/%.0f   m: %.2f",
                ss.adaptive_mode and "on" or "off", ss.source_h or 0, ss.output_h or 0, ss.multiplier or 1)
        end
    end

    -- Section 3: photon-grain.
    local gs          = HUD_STATE.grain_state
    local gr_enabled  = gs and gs.enabled  or false
    local gr_status   = gr_enabled and "on" or "off"
    sync_fold_to_enabled_state("grain", gr_enabled)
    local GRAIN_TOTAL_LINES = 7
    local grain_info, grain_known_lines
    if hud_fold_state.grain.revealed <= 0 then
        grain_info = string.format("phot%s grain", gr_status)
        grain_known_lines = GRAIN_TOTAL_LINES
    else
        local pst = HUD_STATE.photon_state or {}
        local gr_amount   = gs and gs.amount   or 0.0
        local gr_fps_val  = gs and gs.fps      or 0.0
        local gr_feed_status = pst.scene_has_feed and "live" or "no feed"

        local size_base = gs and gs.size_base or 0.0
        local size_line = string.format("size: %.2f%s", size_base,
            gs and gs.hint_suppressed and " manual" or "")
        if gs and gs.size_trim and math.abs(gs.size_trim - 1.0) > 0.005 then
            size_line = size_line .. string.format("  trim x%.2f", gs.size_trim)
        end

        local hue_line
        if gs and gs.hue_has_data then
            hue_line = string.format("hue: %.0f°", gs.hue)
        else
            hue_line = "hue: off (no data)"
        end

        local strength_base = gs and gs.strength_base or 0.0
        local strength_line = string.format("strength: %.2f%s", strength_base,
            gs and gs.strength_hint_suppressed and " manual" or "")

        grain_info  = string.format(
            "phot%s grain\n"
         .. HUD_INDENT .. "amount: %.2f   fps: %.2f  feed: %s\n"
         .. HUD_INDENT .. "%s   %s\n"
         .. HUD_INDENT .. "%s\n"
         .. HUD_INDENT .. "scene → peak: %.2f   contrast: %.2f\n"
         .. HUD_INDENT .. "noise: %.2f   motion: %.2f",
            gr_status, gr_amount, gr_fps_val, gr_feed_status,
            size_line, hue_line,
            strength_line,
            pst.scene_smooth_peak or 0.0, pst.scene_smooth_contrast or 0.0,
            pst.scene_smooth_noise or 0.0, pst.scene_motion or 0.0)
        if gs then
            grain_info = grain_info .. "\n" .. HUD_INDENT .. string.format(
                "resolution scale: %s",
                (not gs.adaptive_mode) and "off"
                    or ((gs.coefficient or 0) > 0 and string.format("auto %.2fx", gs.coefficient)
                        or "pending"))
        end
    end

    -- Section 4: photon-chrome.
    local cs           = HUD_STATE.chrome_state
    local ch_enabled   = cs and cs.enabled  or false
    local ch_status    = ch_enabled and "on" or "off"
    sync_fold_to_enabled_state("chrome", ch_enabled)
    local CHROME_TOTAL_LINES = 3
    local chrome_info, chrome_known_lines
    if hud_fold_state.chrome.revealed <= 0 then
        chrome_info = string.format("phot%s chrome", ch_status)
        chrome_known_lines = CHROME_TOTAL_LINES
    else
        local ch_filter_names = {"red", "orange", "yellow", "green"}
        local ch_filter_name  = (cs and ch_filter_names[(cs.filter_idx or 0) + 1]) or "orange"
        local ch_filter_str   = cs and cs.filter_strength or 0.0
        local ch_contrast_str = cs and cs.contrast_amount or 0.0
        local ch_feed_status  = (cs and cs.has_feed) and "live" or (ch_enabled and "waiting" or "no feed")
        local ch_hue_driven   = cs and cs.hue_driven or false
        local ch_hue_str      = (cs and cs.hue) and string.format("%.3f", cs.hue) or "n/a"
        local ch_shadow_str   = cs and cs.shadow_lift or 0.0
        local ch_highlight_str = cs and cs.highlight_rolloff or 0.0
        local ch_mono_grain_status = (cs and cs.mono_grain) and "on" or "off"
        chrome_info = string.format(
            "phot%s chrome\n"
         .. HUD_INDENT .. "filter: %s   strength: %.2f  feed: %s\n"
         .. HUD_INDENT .. "contrast: %.2f   shadow: %.2f   highlight: %.2f\n"
         .. HUD_INDENT .. "hue-driven: %s   hue: %s   mono-grain: %s",
            ch_status, ch_filter_name, ch_filter_str, ch_feed_status, ch_contrast_str,
            ch_shadow_str, ch_highlight_str,
            ch_hue_driven and "on" or "off", ch_hue_str, ch_mono_grain_status)
    end

    -- Section 5: photon-negativ.
    local ns           = HUD_STATE.negativ_state
    local ng_enabled    = ns and ns.enabled  or false
    local ng_status     = ng_enabled and "on" or "off"
    local ng_mode_name = ns and ns.mode or "mask"
    sync_fold_to_enabled_state("negativ", ng_enabled)
    local NEGATIV_TOTAL_LINES = 2
    local negativ_info, negativ_known_lines
    if hud_fold_state.negativ.revealed <= 0 then
        negativ_info = string.format("phot%s negativ%s",
            ng_status, ng_enabled and (" — " .. ng_mode_name) or "")
        negativ_known_lines = NEGATIV_TOTAL_LINES
    else
        local ng_stock_names = {"ECN-2", "C-41", "vintage-warm"}
        local ng_stock_name  = (ns and ng_stock_names[(ns.stock_idx or 1) + 1]) or "C-41"
        local ng_mask_str    = ns and ns.mask_gain or 0.0
        local ng_gamma_str   = ns and ns.gamma or 0.0
        local ng_feed_status = (ns and ns.has_feed) and "live" or (ng_enabled and "waiting" or "no feed")
        local ng_hue_driven  = ns and ns.hue_driven or false
        local ng_hue_str     = (ns and ns.hue) and string.format("%.3f", ns.hue) or "n/a"
        local ng_arc_clamped_str = (ng_hue_driven and ns and ns.hue)
            and (ns.arc_clamped and "yes" or "no") or "n/a"
        negativ_info = string.format(
            "phot%s negativ%s\n"
         .. HUD_INDENT .. "stock: %s   mask: %.2f   gamma: %.2f  feed: %s\n"
         .. HUD_INDENT .. "hue-driven: %s   hue: %s   arc-clamped: %s",
            ng_status, ng_enabled and (" — " .. ng_mode_name) or "",
            ng_stock_name, ng_mask_str, ng_gamma_str, ng_feed_status,
            ng_hue_driven and "on" or "off", ng_hue_str, ng_arc_clamped_str)
    end

    -- Bright section reads Swift-written user-data properties directly —
    -- global mpv property store, no VM dependency, so this needed no
    -- broadcast bridge when it moved from photon.lua.
    local ab_active        = mp.get_property_bool("user-data/adaptive-brightness-active", false)
    local ab_status = ab_active and "on" or "off"
    sync_fold_to_enabled_state("bright", ab_active)
    local BRIGHT_TOTAL_LINES = 2
    local bright_info, bright_known_lines
    if hud_fold_state.bright.revealed <= 0 then
        bright_info = string.format("phot%s bright", ab_status)
        bright_known_lines = BRIGHT_TOTAL_LINES
    else
        local ab_backlight_raw = mp.get_property_number("user-data/adaptive-brightness-backlight")
        local ab_backlight_str = ab_backlight_raw and string.format("%.0f%%", ab_backlight_raw * 100) or "n/a"
        local ab_inertia_mode  = mp.get_property_native("user-data/adaptive-brightness-inertia-mode") or "n/a"
        local ab_is_cut        = mp.get_property_bool("user-data/adaptive-brightness-is-cut", false)
        local ab_ambient_raw   = mp.get_property_number("user-data/adaptive-brightness-ambient-level")
        local ab_window_open   = mp.get_property_bool("user-data/adaptive-brightness-ambient-window-open", false)
        local ab_ambient_str
        if ab_ambient_raw then
            ab_ambient_str = string.format("%.0f%%", ab_ambient_raw * 100)
        elseif ab_window_open then
            ab_ambient_str = "reading..."
        else
            ab_ambient_str = "n/a"
        end
        local ab_ambient_src   = mp.get_property_native("user-data/adaptive-brightness-ambient-source") or "n/a"
        local ab_lux_raw = mp.get_property_number("user-data/adaptive-brightness-ambient-lux")
        local ab_face_raw = mp.get_property_number("user-data/adaptive-brightness-ambient-face")
        local ab_room_raw = mp.get_property_number("user-data/adaptive-brightness-ambient-room")
        local ab_ambient_extra = ""
        if ab_ambient_src == "als" and ab_lux_raw then
            ab_ambient_extra = string.format(" als: %.0f lux", ab_lux_raw)
        elseif ab_ambient_src == "camera-room_face" then
            local face_str = ab_face_raw and string.format("%.0f%%", ab_face_raw * 100) or "n/a"
            local room_str = ab_room_raw and string.format("%.0f%%", ab_room_raw * 100) or "n/a"
            ab_ambient_extra = string.format(" face: %s room: %s", face_str, room_str)
        end
        local ab_feed_status = ab_backlight_raw and "live" or (ab_active and "waiting" or "no feed")
        bright_info = string.format(
            "phot%s bright\n"
         .. HUD_INDENT .. "backlight: %s   inertia: %s   cut: %s   feed: %s\n"
         .. HUD_INDENT .. "ambient: %s%s",
            ab_status, ab_backlight_str, ab_inertia_mode,
            ab_is_cut and "yes" or "no", ab_feed_status,
            ab_ambient_str, ab_ambient_extra)
    end

    -- sync_fold_to_enabled_state("photon", ...) now runs up near

    local divider = " "
    local full = (photon_skip_fold and ("photon\t" .. photon_info) or apply_fold(photon_info, "photon", photon_known_lines))
              .. "" .. divider .. "\n"
              .. apply_fold(bright_info, "bright", bright_known_lines)
              .. "" .. divider .. "\n"
              .. apply_fold(photon_sharp_info, "sharp", sharp_known_lines)
              .. "" .. divider .. "\n"
              .. apply_fold(grain_info, "grain", grain_known_lines)
              .. "" .. divider .. "\n"
              .. apply_fold(chrome_info, "chrome", chrome_known_lines)
              .. "" .. divider .. "\n"
              .. apply_fold(negativ_info, "negativ", negativ_known_lines)

    local escaped = full:gsub("\n", "‖")
    print("gor-osd:" .. escaped)
    if cost_started then
        HUD_STATE.cost_frames = HUD_STATE.cost_frames + 1
        HUD_STATE.cost_rows = HUD_STATE.cost_rows + 1 + select(2, full:gsub("\n", ""))
        HUD_STATE.cost_bytes = HUD_STATE.cost_bytes + #escaped
        HUD_STATE.cost_seconds = HUD_STATE.cost_seconds + (os.clock() - cost_started)
        if HUD_STATE.cost_last == escaped then HUD_STATE.cost_same = HUD_STATE.cost_same + 1 end
        HUD_STATE.cost_last = escaped
        if HUD_STATE.cost_frames % 64 == 0 then
            mp.msg.info(string.format(
                "gor-hud-source-cost frames=%d rows=%d bytes=%d same=%d lua_cpu_ms=%.3f render=unmeasured",
                HUD_STATE.cost_frames, HUD_STATE.cost_rows, HUD_STATE.cost_bytes,
                HUD_STATE.cost_same, HUD_STATE.cost_seconds * 1000))
        end
    end
end

-- Lets another VM force an immediate redraw between ticks (e.g. after
-- photon.lua's photon-bright-toggle writes user-data/adaptive-brightness-*).
-- Only re-reads existing values -- see ambientWindowInterruptedUnsettled
mp.register_script_message("photon-hud-force-redraw", function()
    if HUD_STATE.enabled then
        draw_hud()
    end
end)

mp.add_key_binding("F8", "toggle-hud", function()
    HUD_STATE.enabled = not HUD_STATE.enabled
    publish_menu_state("hud", HUD_STATE.enabled)
    if HUD_STATE.enabled then
        if not HUD_STATE.timer then
            HUD_STATE.timer = mp.add_periodic_timer(HUD_UPDATE_INTERVAL, draw_hud)
            -- mpv periodic timers fire only after one full interval; call once
            -- now so the HUD appears immediately instead of after 0.25s.
            draw_hud()
        end
    else
        if HUD_STATE.timer then HUD_STATE.timer:kill(); HUD_STATE.timer = nil end
        for _, state in pairs(hud_fold_state) do
            if state.timer then
                state.timer:kill()
                state.timer = nil
            end
        end
        print("gor-osd:" .. tostring("", 0))
    end
end)
