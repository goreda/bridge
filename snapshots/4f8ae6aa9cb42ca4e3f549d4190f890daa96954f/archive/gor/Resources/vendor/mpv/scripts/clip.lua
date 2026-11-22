-- ================================================================
--  clip.lua - mpv clip and GIF export
--  Owns: capture segments, ffmpeg workers and result notices
--  Contract: keep state and code paths unchanged
-- ================================================================

local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

-- AYARLAR / CONFIGURATION
local SETTINGS = {
    generate_srt    = true,
    burn_image_subs = true,
    keep_mkv        = false,
    keep_log        = true,
    keep_temp       = false,
    log_retention   = 7
}

local MAX_SESSION_DURATION = 3600 -- 60-minute limit

-- ── capture state ──
local state = {
    is_recording = false,
    is_gif_mode = false,
    enable_fade = true,
    fade_color = "black",
    segments = {},
    current_seg_start = nil,
    last_video_pos = nil,
    last_osd_text = "",
    platform = "unknown",
    script_ext = ".sh",
    pid = utils.getpid(),
    last_random_dir = "",
    eof_streak = 0
}


math.randomseed(os.time() * 1000 + state.pid + (mp.get_time() * 1000))

local osd_overlay = mp.create_osd_overlay("ass-events")

-- ================================================================
--  1. PLATFORM & PATH UTILITIES
-- ================================================================

local function timestamp()
    return os.date("%y%m%d%H%M%S")
end

local function detect_platform()
    local dir_sep = package.config:sub(1,1)
    if dir_sep == "\\" then return "windows" end
    local home = os.getenv("HOME")
    if home and home:find("/Users/") then return "darwin" end
    return "linux"
end

state.platform = detect_platform()
state.script_ext = (state.platform == "windows") and ".ps1" or ".sh"

-- Uniform Path Joiner
local function join_path_safe(p1, p2)
    local p = utils.join_path(p1, p2)
    if state.platform == "windows" then
        return p:gsub("/", "\\")
    end
    return p
end

-- Robust Path Splitter
local function split_path_safe(path)
    if not path then return nil, nil end
    local sep = (state.platform == "windows") and "\\" or "/"
    if state.platform == "windows" then path = path:gsub("/", "\\") end
    
    local dir, file = path:match("(.*" .. sep .. ")(.*)")
    if not dir then return "", path end
    return dir, file
end

local function get_file_info(path)
    if not path then return nil, "unknown", "" end
    local dir, file = split_path_safe(path)
    local ext = file:match("^.+(%.%w+)$") or ""
    local name = file:gsub("%.%w+$", "")
    return dir, name, ext:lower()
end


local function is_stream_path(path)
    if not path then return true end
    if path:match("^%a[%w+.-]*://") then return true end
    return false
end

local function get_downloads_dir()
    if state.platform == "windows" then
        local up = os.getenv("USERPROFILE")
        return up and join_path_safe(up, "Downloads") or nil
    else
        local home = os.getenv("HOME")
        return home and join_path_safe(home, "Downloads") or nil
    end
end

local function resolve_clip_dir(path)
    if path and not is_stream_path(path) then
        local dir = split_path_safe(path)
        if dir and dir ~= "" then
            return join_path_safe(dir, " clip"), false
        end
    end
    local base = get_downloads_dir() or (state.platform == "windows" and (os.getenv("USERPROFILE") or "C:\\") or (os.getenv("HOME") or "/tmp"))
    return join_path_safe(base, "gor_clip"), true
end

-- Contract: ffmpeg runs separately; pass mpv headers and user agent only for HTTP.
local function get_network_auth()
    local headers = mp.get_property_native("http-header-fields")
    local ua = mp.get_property("user-agent")
    if not (headers and type(headers) == "table" and #headers > 0) then headers = nil end
    if not ua or ua == "" then ua = nil end
    return headers, ua
end

local function ps_dquote_escape(str)
    if not str then return "" end
    str = str:gsub("`", "``")
    str = str:gsub('"', '`"')
    str = str:gsub("%$", "`$")
    return str
end

-- Guard: encode CR/LF in PowerShell strings as literal backtick-r and backtick-n.
local function ps_header_escape(str)
    if not str then return "" end
    local s = ps_dquote_escape(str)
    s = s:gsub("\r", "`r"):gsub("\n", "`n")
    return s
end

-- UNC Path Converter
local function to_unc(path)
    if state.platform == "windows" then
        path = path:gsub("/", "\\")
        if path:sub(1,4) == "\\\\?\\" then return path end
        if #path > 240 or path:match("^\\\\") then return "\\\\?\\" .. path end
    end
    return path
end

-- String Escaping
local function ps_escape(str)
    if not str then return "" end
    return str:gsub("'", "''")
end

local function bash_escape(str)
    if not str then return "" end
    return str:gsub("'", "'\\''")
end

local function sanitize_filename(str)
    if not str then return " clip" end
    local safe = str:gsub("[^a-zA-Z0-9%.%-]", "_")
    safe = safe:gsub("_+", "_")
    return safe
end

local function format_time(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
end

-- ================================================================
--  2. OSD & STATE LOGIC
-- ================================================================

local last_osd_update_time = 0
local function safe_reset_state()
    state.is_recording = false
    osd_overlay:remove()
    state.last_osd_text = ""
    
    state.segments = {}
    state.current_seg_start = nil
    state.last_video_pos = nil
    state.eof_streak = 0
    last_osd_update_time = 0
end

local function get_total_recorded_duration()
    local total = 0
    for _, seg in ipairs(state.segments) do
        total = total + (seg.ending - seg.start)
    end
    if state.current_seg_start then
        local current_pos = mp.get_property_number("time-pos")
        if current_pos then
            local diff = current_pos - state.current_seg_start
            if diff > 0 then total = total + diff end
        end
    end
    return total
end

local function update_overlay()
    if not state.is_recording then return end
    
    local duration = get_total_recorded_duration()
    local color = state.is_gif_mode and "&H00FFFF&" or "&H3C14DC&"
    local mode_label = state.is_gif_mode and "[GIF] " or ""
    
    local seg_count = #state.segments + 1
    local text = string.format("{\\an8\\fs16\\b1\\c%s}%s%s ● (%d)", color, mode_label, format_time(duration), seg_count)
    
    if text ~= state.last_osd_text then
        local plain = text:gsub('{[^}]*}', '')
        print('gor-osd:' .. plain)
        state.last_osd_text = text
    end
end

-- ================================================================
--  3. FFMPEG INTELLIGENCE
-- ================================================================

local function get_video_params()
    if state.platform == "darwin" then
        return "h264_videotoolbox", "-b:v 6000k"
    else
        return "libx264", "-crf 23 -preset medium"
    end
end

local function get_active_audio_index()
    local tracks = mp.get_property_native("track-list")
    if not tracks then return nil end
    
    for _, t in ipairs(tracks) do
        if t.type == "audio" and t.selected then
            return t["ff-index"]
        end
    end

    for _, t in ipairs(tracks) do
        if t.type == "audio" then
            return t["ff-index"]
        end
    end
    
    return nil
end

local function get_sub_map()
    local tracks = mp.get_property_native("track-list")
    if not tracks then return nil, false end
    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.selected and not t.external then
            local codec = t.codec or ""
            local is_img = (codec == "hdmv_pgs_subtitle" or codec == "dvd_subtitle")
            return "-map 0:" .. tostring(t["ff-index"] or 0), is_img
        end
    end
    return nil, false
end

-- ================================================================
--  4. NOTIFICATION SYSTEM
-- ================================================================
local function send_notification(msg_text)
    if state.platform == "darwin" then
        mp.command_native_async({
            name = "subprocess", detach = true, args = {"osascript", "-e", 'display notification "' .. msg_text .. '" with title "MPV Montage"'}
        })
    elseif state.platform == "linux" then
        mp.command_native_async({
            name = "subprocess", detach = true, args = {"notify-send", "MPV Montage", msg_text}
        })
    else
        print("gor-osd:" .. tostring(msg_text))
    end
end

-- ================================================================
--  5. LOGIC FIXED TIMER
-- ================================================================

local MIN_SEGMENT_DURATION = 0.4
local stop_and_process -- The timer is registered before the implementation below.

mp.add_periodic_timer(0.1, function()
    if not state.is_recording then return end

    -- Guard: stream buffering can report transient EOF; require five consecutive polls.
    if mp.get_property_bool("eof-reached") then
        state.eof_streak = state.eof_streak + 1
        if state.eof_streak < 5 then return end
        stop_and_process()
        return
    else
        state.eof_streak = 0
    end

    local current_pos = mp.get_property_number("time-pos")
    if not current_pos then return end

    if not state.last_video_pos then state.last_video_pos = current_pos end
    if not state.current_seg_start then state.current_seg_start = current_pos end

    local diff = math.abs(current_pos - state.last_video_pos)
    
    if diff > 0.4 then
        local seg_duration = state.last_video_pos - state.current_seg_start
        
        if seg_duration >= MIN_SEGMENT_DURATION then
            table.insert(state.segments, {
                start = state.current_seg_start,
                ending = state.last_video_pos
            })
        else
        end
        
        state.current_seg_start = current_pos
    end

    state.last_video_pos = current_pos

    local total_dur = get_total_recorded_duration()
    if total_dur > MAX_SESSION_DURATION then
        stop_and_process()
        return
    end

    local current_int_sec = math.floor(total_dur)
    if current_int_sec > last_osd_update_time then
        update_overlay()
        last_osd_update_time = current_int_sec
    end
end)

local function undo_last_segment()
    if #state.segments > 0 then
        table.remove(state.segments)
        update_overlay()
        print("gor-osd:" .. tostring("↩ undo last segment"))
    else
        print("gor-osd:" .. tostring("nothing to undo"))
    end
end

-- ================================================================
--  6. PROCESSING
-- ================================================================
stop_and_process = function()
    if not state.is_recording then return end
    
    local current_pos = mp.get_property_number("time-pos") or state.last_video_pos
    
    if current_pos and state.current_seg_start then
        local dur = current_pos - state.current_seg_start
        if dur >= MIN_SEGMENT_DURATION then
            table.insert(state.segments, {start = state.current_seg_start, ending = current_pos})
        end
    end

    local recorded_segments = state.segments
    safe_reset_state()

    if #recorded_segments == 0 then
        print("gor-osd:" .. tostring("❌ no valid segments"))
        return
    end

    local path = mp.get_property("path")
    local net_headers, net_ua = get_network_auth()
    local dir, raw_name, ext = get_file_info(path)
    local main_clip_dir, is_fallback = resolve_clip_dir(path)
    local unique_id = string.format("%s_%d_%d", os.date("%H%M%S"), math.random(10000, 99999), state.pid)
    local tstamp = timestamp()

    local cache_dur = mp.get_property_number("demuxer-cache-duration")
    local cache_idle = mp.get_property_native("demuxer-cache-idle")
    local paused_for_cache = mp.get_property_native("paused-for-cache")
    local cache_diag = string.format(
        "cache_dur=%s cache_idle=%s paused_for_cache=%s",
        cache_dur ~= nil and tostring(cache_dur) or "nil",
        cache_idle ~= nil and tostring(cache_idle) or "nil",
        paused_for_cache ~= nil and tostring(paused_for_cache) or "nil"
    )

    local safe_name, out_basename
    if is_fallback then
        local title = mp.get_property("media-title") or raw_name
        title = title and title:gsub("%.%w+$", "") or title
        safe_name = sanitize_filename(title)
        out_basename = string.format("%s_%s", os.date("%y%m%d-%H%M%S"), safe_name)
    else
        safe_name = sanitize_filename(raw_name)
        out_basename = string.format("%s_%s_%s", tstamp, safe_name, unique_id)
    end

    local temp_dir_name = string.format("temp_%s_%s", tstamp, unique_id)
    local work_dir = join_path_safe(main_clip_dir, temp_dir_name)
    
    local concat_video_file = join_path_safe(work_dir, "concat_vid.txt")
    
    local f_final = join_path_safe(main_clip_dir, out_basename .. ".mp4")
    local f_srt = join_path_safe(main_clip_dir, out_basename .. ".srt")
    local f_log = join_path_safe(main_clip_dir, string.format("log_%d_%s.txt", state.pid, unique_id))
    
    local f_ts_concat = join_path_safe(work_dir, "combined.ts")
    local f_full_source_srt = join_path_safe(work_dir, "source_dump.srt")
    local f_merged_srt_temp = join_path_safe(work_dir, "merged_final.srt") -- TEK SRT DOSYASI

    if state.platform == "windows" then
        mp.command_native({name="subprocess", args={"cmd", "/c", 'mkdir "'..to_unc(main_clip_dir)..'" 2>nul'}})
    else
        mp.command_native({name="subprocess", args={"mkdir", "-p", main_clip_dir}})
    end

    local audio_map = get_active_audio_index()
    local sub_map, is_img_sub = get_sub_map()
    local do_subs = (not state.is_gif_mode and SETTINGS.generate_srt and sub_map and not is_img_sub)

    print("gor-osd:" .. tostring(string.format("⚙️ processing %d segments...", #recorded_segments)))

    local script_lines = {}
    local is_win = (state.platform == "windows")
    local ff_silent = "-nostats -hide_banner"

    if is_win then
        table.insert(script_lines, '$ErrorActionPreference = "Stop"')
        table.insert(script_lines, 'trap { Write-Error $_.Exception.Message; exit 1 }')
        table.insert(script_lines, string.format('New-Item -ItemType Directory -Force -Path "%s" | Out-Null', to_unc(work_dir)))
        table.insert(script_lines, string.format('New-Item -ItemType File -Force -Path "%s" | Out-Null', to_unc(concat_video_file)))
        if do_subs then
             table.insert(script_lines, string.format('New-Item -ItemType File -Force -Path "%s" | Out-Null', to_unc(f_merged_srt_temp)))
        end
    else
        table.insert(script_lines, '#!/bin/sh')
        table.insert(script_lines, 'export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"')
        table.insert(script_lines, string.format('mkdir -p "%s"', work_dir))
        table.insert(script_lines, string.format('touch "%s"', concat_video_file))
        if do_subs then
            table.insert(script_lines, string.format('touch "%s"', f_merged_srt_temp))
        end
    end

    -- Guard: mpv may set user-agent for local files; never pass it to local ffmpeg input.
    local is_http_stream = path and (path:match("^https?://") ~= nil)
    local ff_net_args = ""
    local header_str = nil
    if is_http_stream and net_headers and type(net_headers) == "table" and #net_headers > 0 then
        header_str = table.concat(net_headers, "\r\n") .. "\r\n"
    end

    if is_win then
        if header_str then
            table.insert(script_lines, string.format('$env:GOR_FF_HEADERS = "%s"', ps_header_escape(header_str)))
            ff_net_args = ff_net_args .. '-headers "$env:GOR_FF_HEADERS" '
        end
        if is_http_stream and net_ua then
            table.insert(script_lines, string.format('$env:GOR_FF_UA = "%s"', ps_dquote_escape(net_ua)))
            ff_net_args = ff_net_args .. '-user_agent "$env:GOR_FF_UA" '
        end
    else
        if header_str then
            table.insert(script_lines, string.format("export GOR_FF_HEADERS='%s'", bash_escape(header_str)))
            ff_net_args = ff_net_args .. '-headers "$GOR_FF_HEADERS" '
        end
        if is_http_stream and net_ua then
            table.insert(script_lines, string.format("export GOR_FF_UA='%s'", bash_escape(net_ua)))
            ff_net_args = ff_net_args .. '-user_agent "$GOR_FF_UA" '
        end
    end

    local diag_line = string.format(
        "[gor_clip] DIAG: net_headers=%d count, net_ua=%s, %s",
        (net_headers and type(net_headers) == "table") and #net_headers or 0,
        net_ua and "present" or "absent",
        cache_diag
    )
    if is_win then
        table.insert(script_lines, string.format('Add-Content -Path "%s" -Value "%s"', to_unc(f_log), diag_line))
    else
        table.insert(script_lines, string.format('echo "%s" >> "%s"', diag_line, f_log))
    end

    -- Guard: permanent HTTP 4xx stops later segments; 429/5xx remain retryable.
    if is_win then
        table.insert(script_lines, '$Gor403Hit = $false')
    else
        table.insert(script_lines, 'GOR_403_HIT=0')
    end

    if do_subs then
        local ff_input = to_unc(path)
        local ff_full_srt = to_unc(f_full_source_srt)
        local dump_cmd = string.format('ffmpeg %s %s-y -i "%s" %s -c:s srt "%s"', ff_silent, ff_net_args, ff_input, sub_map, ff_full_srt)
        if is_win then table.insert(script_lines, "& " .. dump_cmd .. " 2>> $null")
        else table.insert(script_lines, dump_cmd .. " >> /dev/null 2>&1") end
    end

    -- ── STEP 1 PARALLEL GENERATION DYNAMIC FADE & M1 TURBO ──
    local running_duration = 0.0
    local audio_idx = get_active_audio_index()

    -- ENCODER AYARI (M1 Mac Optimization)
    local v_codec = "libx264 -preset veryfast -crf 23"
    if state.platform == "darwin" then
        v_codec = "h264_videotoolbox -b:v 6000k"
    end

    for i, seg in ipairs(recorded_segments) do
        local duration = seg.ending - seg.start
        
        if duration > 0.1 then
            local seg_name_ts = string.format("seg_%03d.ts", i)
            local seg_path_ts = join_path_safe(work_dir, seg_name_ts)
            
            local fade_len = duration * 0.15
            if fade_len > 1.0 then fade_len = 1.0 end
            if fade_len < 0.1 then fade_len = 0.1 end
            if (fade_len * 2) >= duration then fade_len = (duration / 2) - 0.05 end
            if fade_len < 0 then fade_len = 0 end
            
            local filter_complex = ""
            local map_audio_args = ""
            local audio_codec_args = ""

            if state.enable_fade then
                local f_col = state.fade_color

                if audio_idx then
                    local audio_source = string.format("[0:%d]", audio_idx)
                    filter_complex = string.format(
                        "[0:v]setpts=PTS-STARTPTS,fade=t=in:st=0:d=%.3f:c=%s,fade=t=out:st=%.3f:d=%.3f:c=%s[v];%sasetpts=PTS-STARTPTS,afade=t=in:st=0:d=%.3f,afade=t=out:st=%.3f:d=%.3f[a]",
                        fade_len, f_col, duration - fade_len, fade_len, f_col, -- Video Fade (Color eklendi)
                        audio_source,                                          -- Audio Source
                        fade_len, duration - fade_len, fade_len                -- Audio Fade
                    )
                    map_audio_args = '-map "[a]"'
                    audio_codec_args = '-c:a aac -ar 44100 -ac 2'
                else
                    -- Video-only fade
                    filter_complex = string.format(
                        "[0:v]setpts=PTS-STARTPTS,fade=t=in:st=0:d=%.3f:c=%s,fade=t=out:st=%.3f:d=%.3f:c=%s[v]",
                        fade_len, f_col, duration - fade_len, fade_len, f_col
                    )
                    map_audio_args = ""
                    audio_codec_args = ""
                end
            else
                if audio_idx then
                    local audio_source = string.format("[0:%d]", audio_idx)
                    filter_complex = string.format(
                        "[0:v]setpts=PTS-STARTPTS[v];%sasetpts=PTS-STARTPTS[a]",
                        audio_source
                    )
                    map_audio_args = '-map "[a]"'
                    audio_codec_args = '-c:a aac -ar 44100 -ac 2'
                else
                    filter_complex = "[0:v]setpts=PTS-STARTPTS[v]"
                    map_audio_args = ""
                    audio_codec_args = ""
                end
            end
            
            local ff_input = to_unc(path)
            local ff_output_ts = to_unc(seg_path_ts)
            
            local cmd_vid = string.format(
                'ffmpeg %s %s-y -ss %f -i "%s" -t %f -filter_complex "%s" -map "[v]" %s -c:v %s -pix_fmt yuv420p %s -video_track_timescale 90000 -muxdelay 0 -muxpreload 0 "%s"',
                ff_silent, ff_net_args, seg.start, ff_input, duration, filter_complex, map_audio_args, v_codec, audio_codec_args, ff_output_ts
            )
            
            if is_win then
                local run_line = "& " .. cmd_vid .. " 2>> \"" .. to_unc(f_log) .. "\""
                local exists_check = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', to_unc(seg_path_ts), to_unc(seg_path_ts))
                table.insert(script_lines, string.format([[
if ($Gor403Hit) {
    Add-Content -Path "%s" -Value "[gor_clip] seg skipped (not retried after earlier permanent HTTP error): %s"
} else {
    for ($GorTry = 1; $GorTry -le 2; $GorTry++) {
        %s
        if (%s) { break }
        $GorHttpMatch = Select-String -Path "%s" -Pattern "HTTP error (\d+)" -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($GorHttpMatch) {
            $GorHttpCode = $GorHttpMatch.Matches.Groups[1].Value
            switch ($GorHttpCode) {
                {$_ -in @("400","401","403","404","405","409","410","422")} { $Gor403Hit = $true }
            }
        }
        if ($Gor403Hit) { break }
        Start-Sleep -Seconds 1
    }
    if (%s) {
        Add-Content -Path "%s" -Value "file '%s'" -Encoding UTF8
    } else {
        Add-Content -Path "%s" -Value "[gor_clip] seg download failed (HTTP $GorHttpCode): %s"
    }
}]], to_unc(f_log), ps_escape(seg_path_ts), run_line, exists_check, to_unc(f_log), exists_check, to_unc(concat_video_file), ps_escape(seg_path_ts), to_unc(f_log), ps_escape(seg_path_ts)))
            else
                local run_line = cmd_vid .. " >> \"" .. f_log .. "\" 2>&1"
                table.insert(script_lines, string.format([[
if [ "$GOR_403_HIT" = "1" ]; then
    echo "[gor_clip] seg skipped (not retried after earlier permanent HTTP error): %s" >> "%s"
else
    for GOR_TRY in 1 2; do
        %s
        [ -s "%s" ] && break
        GOR_HTTP_CODE=$(tail -c 2000 "%s" 2>/dev/null | sed -n 's/.*HTTP error \([0-9][0-9]*\).*/\1/p' | tail -1)
        case "$GOR_HTTP_CODE" in
            400|401|403|404|405|409|410|422) GOR_403_HIT=1; break ;;
        esac
        sleep 1
    done
    if [ -s "%s" ]; then
        echo "file '%s'" >> "%s"
    else
        echo "[gor_clip] seg download failed (HTTP %s): %s" >> "%s"
    fi
fi]], bash_escape(seg_path_ts), f_log, run_line, seg_path_ts, f_log, seg_path_ts, bash_escape(seg_path_ts), concat_video_file, seg_path_ts, "$GOR_HTTP_CODE", seg_path_ts, f_log))
            end

            if do_subs then
                local ff_full_srt = to_unc(f_full_source_srt)
                local ff_merged_srt = to_unc(f_merged_srt_temp)
                

                if is_win then
                    table.insert(script_lines, string.format([[
$segStart = %f
$segEnd = %f
$globalOffset = %f
$srtFile = "%s"
$mergedFile = "%s"
if (Test-Path $srtFile) {
    $content = Get-Content -Raw -Path $srtFile -Encoding UTF8
    $pattern = '(?s)(\d+)\r?\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\r?\n(.*?)\r?\n\r?\n'
    $result = ""
    if ($content -match $pattern) {
        $matches = [Regex]::Matches($content, $pattern)
        foreach ($match in $matches) {
            $subStart = [TimeSpan]::Parse($match.Groups[2].Value.Replace(',', '.'))
            $subEnd = [TimeSpan]::Parse($match.Groups[3].Value.Replace(',', '.'))
            $subStartSec = $subStart.TotalSeconds
            $subEndSec = $subEnd.TotalSeconds
            if ($subEndSec -gt $segStart -and $subStartSec -lt $segEnd) {
                $clipStart = [Math]::Max($subStartSec, $segStart)
                $clipEnd = [Math]::Min($subEndSec, $segEnd)
                $newStart = ($clipStart - $segStart) + $globalOffset
                $newEnd = ($clipEnd - $segStart) + $globalOffset
                if ($newEnd - $newStart -gt 0.05) {
                    $newStartStr = "{0:00}:{1:00}:{2:00},{3:000}" -f [Math]::Floor($newStart/3600), [Math]::Floor(($newStart%%3600)/60), [Math]::Floor($newStart%%60), [Math]::Floor(($newStart - [Math]::Floor($newStart))*1000)
                    $newEndStr = "{0:00}:{1:00}:{2:00},{3:000}" -f [Math]::Floor($newEnd/3600), [Math]::Floor(($newEnd%%3600)/60), [Math]::Floor($newEnd%%60), [Math]::Floor(($newEnd - [Math]::Floor($newEnd))*1000)
                    $result += "0`r`n{0} --> {1}`r`n{2}`r`n`r`n" -f $newStartStr, $newEndStr, $match.Groups[4].Value
                }
            }
        }
    }
    if ($result.Length -gt 0) { Add-Content -Path $mergedFile -Value $result -Encoding UTF8 }
}
]], seg.start, seg.ending, running_duration, ff_full_srt, ff_merged_srt))
                else
                    -- PYTHON BLOCK
                    local python_script = join_path_safe(work_dir, string.format("process_seg_%03d.py", i))
                    table.insert(script_lines, string.format('cat > "%s" << \'PYEOF\'', python_script))
                    table.insert(script_lines, string.format([[
import re
def parse_time(t):
    h, m, s = t.strip().split(':')
    s, ms = s.split(',')
    return int(h)*3600 + int(m)*60 + int(s) + int(ms)/1000.0
def format_time(sec):
    ms = int((sec - int(sec)) * 1000)
    s = int(sec)
    return f"{s//3600:02d}:{(s%%3600)//60:02d}:{s%%60:02d},{ms:03d}"
seg_start = %f
seg_end = %f
global_offset = %f
srt_file = "%s"
output_file = "%s"
try:
    with open(srt_file, 'r', encoding='utf-8') as f: content = f.read()
    result = []
    pattern = r'(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\n(.*?)\n\n'
    for match in re.finditer(pattern, content, re.DOTALL):
        start_sec = parse_time(match.group(2))
        end_sec = parse_time(match.group(3))
        if end_sec > seg_start and start_sec < seg_end:
            clip_start = max(start_sec, seg_start)
            clip_end = min(end_sec, seg_end)
            new_start = (clip_start - seg_start) + global_offset
            new_end = (clip_end - seg_start) + global_offset
            if new_end - new_start > 0.05:
                result.append("0\n" + format_time(new_start) + " --> " + format_time(new_end) + "\n" + match.group(4).strip() + "\n")
    with open(output_file, 'a', encoding='utf-8') as f: f.write('\n'.join(result) + '\n\n')
except: pass
]], seg.start, seg.ending, running_duration, ff_full_srt, ff_merged_srt))
                    table.insert(script_lines, "PYEOF")
                    table.insert(script_lines, string.format('python3 "%s"', python_script))
                end
            end
            
            running_duration = running_duration + duration
        end
    end

    local ff_concat_vid = to_unc(concat_video_file)
    local ff_ts_concat = to_unc(f_ts_concat)
    local ff_final = to_unc(f_final)
    local ff_merged_srt = to_unc(f_merged_srt_temp)
    local ff_srt_final = to_unc(f_srt)

    
    if state.is_gif_mode then
        local f_gif = ff_final:gsub("%.mp4$", ".gif")
        
        local vid_params = mp.get_property_native("video-params")
        local tonemap_filter = ""
        
        -- AYARLAR & PASS SAYACI
        local FFMPEG_PASS_COUNT = 26
        local RES_W = 480
        local GIF_COLORS = 256
        local NOISE_C0 = 6
        local NOISE_C12 = 3

        local LOSSY_L0 = FFMPEG_PASS_COUNT
        local LOSSY_L1 = LOSSY_L0 + (LOSSY_L0 * 2)
        local LOSSY_L2 = LOSSY_L0 + (LOSSY_L0 * 3)
        local LOSSY_L3 = LOSSY_L0 + (LOSSY_L0 * 4)

        local target_saturation = 0.92
        local target_contrast = 0.92
        local target_gamma = 2.2
        local GAMMA_R = 0.972
        local GAMMA_G = 0.9634
        local GAMMA_B = 0.9735
        
        if vid_params then
            local p = vid_params.primaries or ""
            local tr = vid_params["gamma"] or ""
            
            -- HDR detection (BT.2020 or PQ/HLG)
            if p == "bt.2020" or tr == "pq" or tr == "hlg" then
                print("gor-osd:" .. tostring("🌈 HDR GIF: tone mapping in progress..."))
                
                -- check zscale availability; referencing a missing filter breaks all of filter_complex
                local filters_res = mp.command_native({
                    name = "subprocess", capture_stdout = true,
                    args = {"ffmpeg", "-hide_banner", "-filters"}
                })
                local has_zscale = filters_res and filters_res.stdout
                    and filters_res.stdout:find("zscale", 1, true) ~= nil

                if has_zscale then
                    tonemap_filter = "zscale=t=linear:npl=120,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p,"
                else
                    print("gor-osd:" .. tostring("⚠️ zscale unavailable; using approximate HDR compensation"))
                end
                
                target_saturation = 2.4
                target_contrast = 1.25
                target_gamma = 3.8
                GAMMA_R = 0.969
                GAMMA_G = 0.9637
                GAMMA_B = 0.9743
            end
        end

        local gif_vf = tonemap_filter .. "fps=6,scale=" .. RES_W .. ":-2:flags=neighbor,eq=saturation=" .. target_saturation .. ":contrast=" .. target_contrast .. ":gamma=" .. target_gamma .. ",noise=c0s=" .. NOISE_C0 .. ":c1s=" .. NOISE_C12 .. ":c2s=" .. NOISE_C12 .. ":allf=t+u,split[s0][s1];[s0]palettegen=max_colors=" .. GIF_COLORS .. ":reserve_transparent=0:stats_mode=diff[pal];[s1][pal]paletteuse=dither=heckbert:diff_mode=rectangle:new=1"
        local fry_vf = "eq=gamma_r=" .. GAMMA_R .. ":gamma_g=" .. GAMMA_G .. ":gamma_b=" .. GAMMA_B .. ",split[s0][s1];[s0]palettegen=max_colors=" .. GIF_COLORS .. ":stats_mode=single[pal];[s1][pal]paletteuse=dither=heckbert:diff_mode=rectangle:new=1"

        -- ── PASS 1 INITIAL GENERATION ──
        -- GUARD: concat_video_file (concat_vid.txt) is always created (touch/New-Item); the nonempty check below gates ffmpeg
        local gif_cmd = string.format(
            'ffmpeg %s -y -f concat -safe 0 -i "%s" -filter_complex "%s" -gifflags +transdiff -loop 0 "%s"',
            ff_silent, ff_concat_vid, gif_vf, f_gif
        )
        if is_win then
            local concat_nonempty = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', ff_concat_vid, ff_concat_vid)
            table.insert(script_lines, string.format([[
if (%s) {
    & %s 2>> "%s"
} else {
    Add-Content -Path "%s" -Value "[gor_clip] concat list empty: no segments downloaded, gif creation skipped"
}]], concat_nonempty, gif_cmd, to_unc(f_log), to_unc(f_log)))
        else
            table.insert(script_lines, string.format([[
if [ -s "%s" ]; then
    %s >> "%s" 2>&1
else
    echo "[gor_clip] concat list empty: no segments downloaded, gif creation skipped" >> "%s"
fi]], concat_video_file, gif_cmd, f_log, f_log))
        end

        local pass_chain_lines = {}

        for i = 1, FFMPEG_PASS_COUNT do
            local pass_label = string.format("Pass 2.%d: FFmpeg Fry...", i)
            local temp_fry = f_gif .. ".temp_fry.gif"
            if is_win then
                local pass2_cmd = string.format('Write-Host "%s"; & ffmpeg -y -v error -i "%s" -filter_complex "%s" -gifflags +transdiff -loop 0 "%s"; Move-Item -Path "%s" -Destination "%s" -Force', pass_label, to_unc(f_gif), fry_vf, to_unc(temp_fry), to_unc(temp_fry), to_unc(f_gif))
                table.insert(pass_chain_lines, pass2_cmd .. " 2>> \"" .. to_unc(f_log) .. "\"")
            else
                local pass2_cmd = string.format('echo "%s"; ffmpeg -y -v error -i "%s" -filter_complex "%s" -gifflags +transdiff -loop 0 "%s" && cat "%s" > "%s" && rm "%s"', pass_label, f_gif, fry_vf, temp_fry, temp_fry, f_gif, temp_fry)
                table.insert(pass_chain_lines, pass2_cmd .. " >> \"" .. f_log .. "\" 2>&1")
            end
        end

        -- ── PASS 3 GIFSICLE OPTIMIZATION - LEVEL 1 ──
        if is_win then
             local gifsicle_cmd = string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { Write-Host "Pass 3: Gifsicle Opt..."; & gifsicle -O1 --lossy=' .. LOSSY_L1 .. ' --no-warnings --colors ' .. GIF_COLORS .. ' -i "%s" -o "%s.opt.gif"; Move-Item -Path "%s.opt.gif" -Destination "%s" -Force }', to_unc(f_gif), to_unc(f_gif), to_unc(f_gif), to_unc(f_gif))
             table.insert(pass_chain_lines, gifsicle_cmd .. " 2>> \"" .. to_unc(f_log) .. "\"")
        else
            local gifsicle_cmd = string.format('if command -v gifsicle >/dev/null 2>&1; then echo "Pass 3: Gifsicle Opt..."; gifsicle -O1 --lossy=' .. LOSSY_L1 .. ' --no-warnings --colors ' .. GIF_COLORS .. ' -i "%s" -o "%s.opt.gif" && cat "%s.opt.gif" > "%s" && rm "%s.opt.gif"; fi', f_gif, f_gif, f_gif, f_gif, f_gif)
            table.insert(pass_chain_lines, gifsicle_cmd .. " >> \"" .. f_log .. "\" 2>&1")
        end

        -- ── PASS 4 PRE-FINAL CRUNCH - LEVEL 2 ──
        if is_win then
            local gifsicle_pass4 = string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { Write-Host "Pass 4: Final Crunch..."; & gifsicle -O2 --lossy=' .. LOSSY_L2 .. ' --colors ' .. GIF_COLORS .. ' --no-warnings -i "%s" -o "%s.final.gif"; Move-Item -Path "%s.final.gif" -Destination "%s" -Force }', to_unc(f_gif), to_unc(f_gif), to_unc(f_gif), to_unc(f_gif))
            table.insert(pass_chain_lines, gifsicle_pass4 .. " 2>> \"" .. to_unc(f_log) .. "\"")
        else
            local gifsicle_pass4 = string.format('if command -v gifsicle >/dev/null 2>&1; then echo "Pass 4: Final Crunch..."; gifsicle -O2 --lossy=' .. LOSSY_L2 .. ' --colors ' .. GIF_COLORS .. ' --no-warnings -i "%s" -o "%s.final.gif" && cat "%s.final.gif" > "%s" && rm "%s.final.gif"; fi', f_gif, f_gif, f_gif, f_gif, f_gif)
            table.insert(pass_chain_lines, gifsicle_pass4 .. " >> \"" .. f_log .. "\" 2>&1")
        end

        -- ── PASS 5 FINAL CRUNCH - LEVEL 3 MAX ──
        if is_win then
            local gifsicle_pass5 = string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { Write-Host "Pass 5: Final Crunch..."; & gifsicle -O3 --lossy=' .. LOSSY_L3 .. ' --colors ' .. GIF_COLORS .. ' --no-warnings -i "%s" -o "%s.final.gif"; Move-Item -Path "%s.final.gif" -Destination "%s" -Force }', to_unc(f_gif), to_unc(f_gif), to_unc(f_gif), to_unc(f_gif))
            table.insert(pass_chain_lines, gifsicle_pass5 .. " 2>> \"" .. to_unc(f_log) .. "\"")
        else
            local gifsicle_pass5 = string.format('if command -v gifsicle >/dev/null 2>&1; then echo "Pass 5: Final Crunch..."; gifsicle -O3 --lossy=' .. LOSSY_L3 .. ' --colors ' .. GIF_COLORS .. ' --no-warnings -i "%s" -o "%s.final.gif" && cat "%s.final.gif" > "%s" && rm "%s.final.gif"; fi', f_gif, f_gif, f_gif, f_gif, f_gif)
            table.insert(pass_chain_lines, gifsicle_pass5 .. " >> \"" .. f_log .. "\" 2>&1")
        end

        if is_win then
            local gif_nonempty = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', to_unc(f_gif), to_unc(f_gif))
            table.insert(script_lines, string.format('if (%s) {', gif_nonempty))
            for _, l in ipairs(pass_chain_lines) do table.insert(script_lines, l) end
            table.insert(script_lines, string.format('} else { Add-Content -Path "%s" -Value "[gor_clip] gif empty/missing: fry/gifsicle optimization chain skipped" }', to_unc(f_log)))
        else
            table.insert(script_lines, string.format('if [ -s "%s" ]; then', f_gif))
            for _, l in ipairs(pass_chain_lines) do table.insert(script_lines, l) end
            table.insert(script_lines, string.format('else\n    echo "[gor_clip] gif empty/missing: fry/gifsicle optimization chain skipped" >> "%s"\nfi', f_log))
        end

    else

        -- 2a. VIDEO
        -- GUARD: concat_video_file (concat_vid.txt) is always created (touch/New-Item); the nonempty check below gates ffmpeg
        local vid_cat_cmd = string.format(
            'ffmpeg %s -y -f concat -safe 0 -i "%s" -c copy "%s"',
            ff_silent, ff_concat_vid, ff_ts_concat
        )
        if is_win then
            local concat_nonempty = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', ff_concat_vid, ff_concat_vid)
            table.insert(script_lines, string.format([[
if (%s) {
    & %s 2>> "%s"
} else {
    Add-Content -Path "%s" -Value "[gor_clip] concat list empty: no segments downloaded, video merge skipped"
}]], concat_nonempty, vid_cat_cmd, to_unc(f_log), to_unc(f_log)))
        else
            table.insert(script_lines, string.format([[
if [ -s "%s" ]; then
    %s >> "%s" 2>&1
else
    echo "[gor_clip] concat list empty: no segments downloaded, video merge skipped" >> "%s"
fi]], concat_video_file, vid_cat_cmd, f_log, f_log))
        end

        if do_subs then
            local ff_cmd = string.format(
                'ffmpeg -nostats -hide_banner -y -i "%s" -c:s srt "%s"',
                ff_merged_srt, ff_srt_final
            )
            if is_win then
                table.insert(script_lines, "& " .. ff_cmd .. " 2>nul")
            else
                table.insert(script_lines, ff_cmd .. " >/dev/null 2>&1")
            end
        end
    end

    -- ── STEP 3 FINAL REMUX ──
    if not state.is_gif_mode then
        -- Guard: remux needs an existing, nonempty combined input.
        local final_cmd = string.format(
            'ffmpeg %s -y -i "%s" -c copy -bsf:a aac_adtstoasc -brand mp42 -movflags +faststart "%s"',
            ff_silent, ff_ts_concat, ff_final
        )
        if is_win then
            local ts_nonempty = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', ff_ts_concat, ff_ts_concat)
            table.insert(script_lines, string.format([[
if (%s) {
    & %s 2>> "%s"
} else {
    Add-Content -Path "%s" -Value "[gor_clip] combined.ts empty/missing: final remux skipped"
}]], ts_nonempty, final_cmd, to_unc(f_log), to_unc(f_log)))
        else
            table.insert(script_lines, string.format([[
if [ -s "%s" ]; then
    %s >> "%s" 2>&1
else
    echo "[gor_clip] combined.ts empty/missing: final remux skipped" >> "%s"
fi]], f_ts_concat, final_cmd, f_log, f_log))
        end
    end

    -- Contract: detached worker writes a result sentinel before reporting success.
    local f_result = join_path_safe(main_clip_dir, "result_" .. unique_id .. ".txt")
    local expected_output = state.is_gif_mode and (ff_final:gsub("%.mp4$", ".gif")) or ff_final
    if is_win then
        local out_ok = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', expected_output, expected_output)
        table.insert(script_lines, string.format([[
if (%s) {
    Set-Content -Path "%s" -Value "SUCCESS" -Encoding ascii -NoNewline
} else {
    Set-Content -Path "%s" -Value "FAIL:output_file_not_created" -Encoding ascii -NoNewline
}]], out_ok, to_unc(f_result), to_unc(f_result)))
    else
        table.insert(script_lines, string.format([[
if [ -s "%s" ]; then
    echo "SUCCESS" > "%s"
else
    echo "FAIL:output_file_not_created" > "%s"
fi]], expected_output, f_result, f_result))
    end

    -- CLEANUP
    if not SETTINGS.keep_temp then
        if is_win then
            table.insert(script_lines, string.format([[
$retry = 0
while (Test-Path "%s") {
    Remove-Item -Path "%s" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 200
    $retry++
    if ($retry -gt 10) { break }
}
]], to_unc(work_dir), to_unc(work_dir)))
        else
            table.insert(script_lines, string.format('rm -rf "%s"', work_dir))
        end
    end
    
    if not SETTINGS.keep_log then
        if is_win then table.insert(script_lines, string.format('Remove-Item -Path "%s" -Force', to_unc(f_log)))
        else table.insert(script_lines, string.format('rm "%s"', f_log)) end
    end
    
    if is_win then
        table.insert(script_lines, 'Remove-Item -Path $MyInvocation.MyCommand.Path -Force')
    else
        table.insert(script_lines, 'rm "$0"')
    end

    local script_path = join_path_safe(main_clip_dir, "worker_" .. unique_id .. state.script_ext)
    local f = io.open(script_path, "w")
    if f then
        if is_win then
            f:write('\239\187\191')
            f:write('#Requires -Version 3.0\n')
        end
        for _, l in ipairs(script_lines) do f:write(l .. "\n") end
        f:close()
        
        if is_win then
            mp.command_native({
                name = "subprocess", detach = true, playback_only = false,
                args = {"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path}
            })
        else
            mp.command_native({
                name = "subprocess", detach = true, playback_only = false,
                args = {"/bin/sh", script_path}
            })
        end

        -- Guard: poll result sentinel; never announce unconditional success.
        local poll_count = 0
        local MAX_POLLS = 90
        local function poll_result()
            poll_count = poll_count + 1
            local res_f = io.open(f_result, "r")
            if res_f then
                local content = res_f:read("*a")
                res_f:close()
                content = content and content:gsub("%s+$", "") or ""
                if content == "SUCCESS" then
                    send_notification("montage saved: " .. safe_name)
                    print("gor-osd:" .. tostring("✓ saved"))
                elseif content:match("^FAIL:") then
                    print("gor-osd:" .. tostring("❌ could not save (see log: 403/network)"))
                else
                    print("gor-osd:" .. tostring("⚠️ processing finished; check result"))
                end
                os.remove(f_result)
                return
            end
            if poll_count >= MAX_POLLS then
                print("gor-osd:" .. tostring("⏳ still processing; check folder"))
                return
            end
            mp.add_timeout(0.5, poll_result)
        end
        mp.add_timeout(0.5, poll_result)
    else
        print("gor-osd:" .. tostring("❌ IO Error"))
    end
end

local function process_static_image_to_gif(path)
    local net_headers, net_ua = get_network_auth()
    local dir, raw_name, ext = get_file_info(path)
    local main_clip_dir, is_fallback = resolve_clip_dir(path)
    local unique_id = string.format("%s_%d_%d", os.date("%H%M%S"), math.random(10000, 99999), state.pid)
    local tstamp = timestamp()

    local safe_name, out_basename
    if is_fallback then
        local title = mp.get_property("media-title") or raw_name
        title = title and title:gsub("%.%w+$", "") or title
        safe_name = sanitize_filename(title)
        out_basename = string.format("%s_%s", os.date("%y%m%d-%H%M%S"), safe_name)
    else
        safe_name = sanitize_filename(raw_name)
        out_basename = string.format("%s_%s_%s", tstamp, safe_name, unique_id)
    end

    local f_gif = join_path_safe(main_clip_dir, out_basename .. ".gif")
    local f_log = join_path_safe(main_clip_dir, string.format("log_img_%d_%s.txt", state.pid, unique_id))
    
    if state.platform == "windows" then
        mp.command_native({name="subprocess", args={"cmd", "/c", 'mkdir "'..to_unc(main_clip_dir)..'" 2>nul'}})
    else
        mp.command_native({name="subprocess", args={"mkdir", "-p", main_clip_dir}})
    end

    print("gor-osd:" .. tostring("🎞️ applying parallel cinematic emulsion..."))

    local script_lines = {}
    local is_win = (state.platform == "windows")
    local ff_silent = "-nostats -hide_banner"

    if is_win then
        table.insert(script_lines, '$ErrorActionPreference = "Stop"')
        table.insert(script_lines, 'trap { Write-Error $_.Exception.Message; exit 1 }')
    else
        table.insert(script_lines, '#!/bin/sh')
        table.insert(script_lines, 'export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"')
    end

    local is_http_stream = path and (path:match("^https?://") ~= nil)
    local ff_net_args = ""
    local header_str = nil
    if is_http_stream and net_headers and type(net_headers) == "table" and #net_headers > 0 then
        header_str = table.concat(net_headers, "\r\n") .. "\r\n"
    end

    if is_win then
        if header_str then
            table.insert(script_lines, string.format('$env:GOR_FF_HEADERS = "%s"', ps_header_escape(header_str)))
            ff_net_args = ff_net_args .. '-headers "$env:GOR_FF_HEADERS" '
        end
        if is_http_stream and net_ua then
            table.insert(script_lines, string.format('$env:GOR_FF_UA = "%s"', ps_dquote_escape(net_ua)))
            ff_net_args = ff_net_args .. '-user_agent "$env:GOR_FF_UA" '
        end
    else
        if header_str then
            table.insert(script_lines, string.format("export GOR_FF_HEADERS='%s'", bash_escape(header_str)))
            ff_net_args = ff_net_args .. '-headers "$GOR_FF_HEADERS" '
        end
        if is_http_stream and net_ua then
            table.insert(script_lines, string.format("export GOR_FF_UA='%s'", bash_escape(net_ua)))
            ff_net_args = ff_net_args .. '-user_agent "$GOR_FF_UA" '
        end
    end

    local FFMPEG_PASS_COUNT = 2
    local GIF_COLORS = 256
    local FINAL_OUTPUT_W = 480

    local FPS = 12
    local TARGET_SMOOTH_FPS = 120
    local DURATION = 0.5
    
    local MAX_RES_W = FINAL_OUTPUT_W
    local MIN_RES_W = 2

    local FINAL_COLORS = math.floor(GIF_COLORS / 2)

    local FINAL_LOSSY_LIGHT = 1000000 * 50
    local FINAL_LOSSY_DARK = 200

    -- fry_vf parameters
    local t_saturation = 1.2
    local t_contrast = 1.025
    local t_gamma = 1.0
    local G_R = 0.985
    local G_G = 0.98
    local G_B = 1.00

    local y_avg = 128
    local sat_avg = 0

    local stats_args = {"ffmpeg", "-v", "error"}
    if header_str then
        table.insert(stats_args, "-headers")
        table.insert(stats_args, header_str)
    end
    if is_http_stream and net_ua then
        table.insert(stats_args, "-user_agent")
        table.insert(stats_args, net_ua)
    end
    for _, a in ipairs({"-i", path, "-vf", "scale=64:64,format=yuv444p,signalstats,metadata=print:file=-", "-vframes", "1", "-f", "null", "-"}) do
        table.insert(stats_args, a)
    end
    local stats_res = mp.command_native({name = "subprocess", capture_stdout = true, args = stats_args})
    
    if stats_res and stats_res.stdout then
        local y_match = stats_res.stdout:match("YAVG=([%d%.]+)")
        local sat_match = stats_res.stdout:match("SATAVG=([%d%.]+)")
        if y_match then y_avg = tonumber(y_match) end
        if sat_match then sat_avg = tonumber(sat_match) end
    end
    
-- ================================================================
--  7. LUMA
-- ================================================================
    local luma_weight = math.max(0, math.min(222, y_avg)) / 222.0
    
-- ================================================================
--  8. SATURATION
-- ================================================================
    local sat_weight = math.max(0, math.min(90, sat_avg)) / 90.0
    
    local intensity = (sat_weight * 0.5) + (luma_weight * 0.5)
    
    local final_factor = math.pow(intensity, 3.5)
    
    local FINAL_LOSSY = math.floor(FINAL_LOSSY_DARK + ((FINAL_LOSSY_LIGHT - FINAL_LOSSY_DARK) * final_factor) + 0.5)
    
    mp.msg.info(string.format("Image Luma: %.1f, Saturation: %.1f -> Calculated FINAL_LOSSY: %d", y_avg, sat_avg, FINAL_LOSSY))

    local LAYERS = {
        { enable = true, opacity = 0.5, blend = "normal", c0 = 100, c12 = 0 },
        { enable = true, opacity = 0.25, blend = "normal", c0 = 90, c12 = 0 },
        { enable = true, opacity = 0.125, blend = "normal", c0 = 80, c12 = 0 },
        { enable = true, opacity = 0.5, blend = "normal", c0 = 50, c12 = 0 },
        { enable = true, opacity = 0.25, blend = "normal", c0 = 80, c12 = 0 },
        { enable = true, opacity = 0.125, blend = "normal", c0 = 90, c12 = 0 },
        { enable = true, opacity = 0.0625, blend = "normal", c0 = 100, c12 = 40 },
    }

    local active_layers = {}
    for _, layer in ipairs(LAYERS) do
        if layer.enable then table.insert(active_layers, layer) end
    end

    local active_count = #active_layers
    if active_count == 0 then
        print("gor-osd:" .. tostring("❌ At least one layer must be active!"))
        return
    end

    local res_step = 0
    if active_count > 1 then
        res_step = (MAX_RES_W - MIN_RES_W) / (active_count - 1)
    end

    local filter_chain = string.format("[0:v]format=yuv420p,setpts=N/FRAME_RATE/TB,fps=%d,split=%d", FPS, active_count + 1)
    for i = 1, active_count do
        filter_chain = filter_chain .. string.format("[src%d]", i)
    end
    filter_chain = filter_chain .. "[base_src];"

    filter_chain = filter_chain .. string.format("[base_src]scale=%d:-2:flags=lanczos[base0];", FINAL_OUTPUT_W)

    for i, layer in ipairs(active_layers) do
        local current_res = math.floor(MAX_RES_W - ((i - 1) * res_step))
        current_res = current_res - (current_res % 2)
        
        local safe_opacity = string.format("%.2f", layer.opacity):gsub(",", ".")
        
        local s0, s1, s2 = math.random(1000, 9999), math.random(1000, 9999), math.random(1000, 9999)
        
        filter_chain = filter_chain .. string.format("[src%d]scale=%d:-2:flags=lanczos,noise=c0s=%d:c1s=%d:c2s=%d:allf=t+u:c0_seed=%d:c1_seed=%d:c2_seed=%d[noisy_raw%d];",
            i, current_res, layer.c0, layer.c12, layer.c12, s0, s1, s2, i)
            
        filter_chain = filter_chain .. string.format("[noisy_raw%d][base%d]scale2ref=flags=lanczos[layer%d][base_ref%d];",
            i, i - 1, i, i - 1)
        
        filter_chain = filter_chain .. string.format(
            "[layer%d][base_ref%d]blend=all_expr='if(lte(B,224), A*(%s)+B*(1-%s), B)':all_opacity=1[base%d];",
            i, i - 1, safe_opacity, safe_opacity, i
        )
    end

    -- LIQUID NOISE / SMOOTH SLOW MOTION BLENDING
    
    local gif_vf_initial = filter_chain .. string.format(
        "[base%d]framerate=fps=%d:interp_start=0:interp_end=255:scene=100,split[s0][s1];[s0]palettegen=max_colors=%d:reserve_transparent=0:stats_mode=diff[pal];[s1][pal]paletteuse=dither=heckbert:diff_mode=rectangle:new=1",
        active_count, TARGET_SMOOTH_FPS, GIF_COLORS
    )
    
    local fry_vf = string.format(
        "eq=saturation=" .. t_saturation .. ":contrast=" .. t_contrast .. ":gamma=" .. t_gamma .. ":gamma_r=" .. G_R .. ":gamma_g=" .. G_G .. ":gamma_b=" .. G_B .. ",split[s0][s1];[s0]palettegen=max_colors=%d:stats_mode=diff[pal];[s1][pal]paletteuse=dither=heckbert:diff_mode=rectangle:new=1",
        GIF_COLORS
    )
    local gif_cmd = string.format(
        'ffmpeg %s %s-y -loop 1 -t ' .. DURATION .. ' -i "%s" -filter_complex "%s" -vsync cfr -an -gifflags +transdiff -loop 0 "%s"',
        ff_silent, ff_net_args, to_unc(path), gif_vf_initial, to_unc(f_gif)
    )
    
    if is_win then table.insert(script_lines, "& " .. gif_cmd .. " 2>> \"" .. to_unc(f_log) .. "\"")
    else table.insert(script_lines, gif_cmd .. " >> \"" .. f_log .. "\" 2>&1") end

    -- Guard: downstream GIF passes need nonempty first-pass output.
    local pass_chain_lines2 = {}

    for i = 1, FFMPEG_PASS_COUNT do
        local pass_label = string.format("Pass 2.%d: FFmpeg Fry...", i)
        local temp_fry = f_gif .. ".temp_fry.gif"
        if is_win then
            local pass2_cmd = string.format('Write-Host "%s"; & ffmpeg -y -v error -i "%s" -filter_complex "%s" -gifflags +transdiff -loop 0 "%s"; Move-Item -Path "%s" -Destination "%s" -Force', pass_label, to_unc(f_gif), fry_vf, to_unc(temp_fry), to_unc(temp_fry), to_unc(f_gif))
            table.insert(pass_chain_lines2, pass2_cmd .. " 2>> \"" .. to_unc(f_log) .. "\"")
        else
            local pass2_cmd = string.format('echo "%s"; ffmpeg -y -v error -i "%s" -filter_complex "%s" -gifflags +transdiff -loop 0 "%s" && cat "%s" > "%s" && rm "%s"', pass_label, f_gif, fry_vf, temp_fry, temp_fry, f_gif, temp_fry)
            table.insert(pass_chain_lines2, pass2_cmd .. " >> \"" .. f_log .. "\" 2>&1")
        end
    end

    local GLITCH_DIR = "down"
    
    local active_dir = GLITCH_DIR

    if active_dir == "random" then
        local dirs = {"right", "left", "down", "up", "alldir"}
        local new_dir = ""
        
        repeat
            new_dir = dirs[math.random(1, #dirs)]
        until new_dir ~= state.last_random_dir
        
        state.last_random_dir = new_dir
        active_dir = new_dir
        mp.msg.info("🎨 Random Direction Selected: " .. string.upper(active_dir))
    end

    if active_dir == "alldir" then
        mp.msg.info("🎨 Spawning Omnidirectional Glitch Matrix...")
        local dirs = {
            {name="right", pre="", post=""},
            {name="left",  pre="--flip-horizontal", post="--flip-horizontal"},
            {name="down",  pre="--rotate-270", post="--rotate-90"},
            {name="up",    pre="--rotate-90", post="--rotate-270"}
        }
        
        local dir_files_win = {}
        local dir_files_mac = {}
        local ff_inputs_win = ""
        local ff_inputs_mac = ""

        for _, d in ipairs(dirs) do
            local out_win = to_unc(f_gif) .. "." .. d.name .. ".gif"
            local out_mac = f_gif .. "." .. d.name .. ".gif"
            
            table.insert(dir_files_win, out_win)
            table.insert(dir_files_mac, out_mac)
            
            ff_inputs_win = ff_inputs_win .. string.format(' -i "%s"', out_win)
            ff_inputs_mac = ff_inputs_mac .. string.format(' -i "%s"', out_mac)

            if is_win then
                local t1 = to_unc(f_gif) .. "." .. d.name .. ".t1.gif"
                local t2 = to_unc(f_gif) .. "." .. d.name .. ".t2.gif"
                if d.name == "right" then
                    local cmd = string.format('& gifsicle -O3 --lossy=%d --colors %d --no-warnings -i "%s" -o "%s"', FINAL_LOSSY, FINAL_COLORS, to_unc(f_gif), out_win)
                    table.insert(pass_chain_lines2, string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { Write-Host "Crunching %s..."; %s }', string.upper(d.name), cmd))
                else
                    local cmd = string.format('& gifsicle %s --no-warnings -i "%s" -o "%s"; & gifsicle -O3 --lossy=%d --colors %d --no-warnings -i "%s" -o "%s"; & gifsicle %s --no-warnings -i "%s" -o "%s"; Remove-Item -Path "%s", "%s" -ErrorAction SilentlyContinue', d.pre, to_unc(f_gif), t1, FINAL_LOSSY, FINAL_COLORS, t1, t2, d.post, t2, out_win, t1, t2)
                    table.insert(pass_chain_lines2, string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { Write-Host "Crunching %s..."; %s }', string.upper(d.name), cmd))
                end
            else
                local t1 = f_gif .. "." .. d.name .. ".t1.gif"
                local t2 = f_gif .. "." .. d.name .. ".t2.gif"
                if d.name == "right" then
                    local cmd = string.format('gifsicle -O3 --lossy=%d --colors %d --no-warnings -i "%s" -o "%s"', FINAL_LOSSY, FINAL_COLORS, f_gif, out_mac)
                    table.insert(pass_chain_lines2, string.format('if command -v gifsicle >/dev/null 2>&1; then echo "Crunching %s..."; %s; fi', string.upper(d.name), cmd))
                else
                    local cmd = string.format('gifsicle %s --no-warnings -i "%s" -o "%s" && gifsicle -O3 --lossy=%d --colors %d --no-warnings -i "%s" -o "%s" && gifsicle %s --no-warnings -i "%s" -o "%s" && rm "%s" "%s"', d.pre, f_gif, t1, FINAL_LOSSY, FINAL_COLORS, t1, t2, d.post, t2, out_mac, t1, t2)
                    table.insert(pass_chain_lines2, string.format('if command -v gifsicle >/dev/null 2>&1; then echo "Crunching %s..."; %s; fi', string.upper(d.name), cmd))
                end
            end
        end

        -- MATRIX BLENDING
        local mix_filter = "mix=inputs=4[mx];[mx]split[s0][s1];[s0]palettegen=max_colors=256:reserve_transparent=0:stats_mode=diff[p];[s1][p]paletteuse=dither=heckbert"

        if is_win then
            local final_mixed = to_unc(f_gif) .. ".final.gif"
            local ff_mix = string.format('& ffmpeg %s %s -filter_complex "%s" -y "%s"', ff_silent, ff_inputs_win, mix_filter, final_mixed)
            
            table.insert(pass_chain_lines2, 'Write-Host "Omnidirectional Matrix Blending..."')
            table.insert(pass_chain_lines2, ff_mix .. " 2>> \"" .. to_unc(f_log) .. "\"")
            
            local loop_cmd = string.format('& gifsicle -O3 --loop=0 --no-warnings -i "%s" -o "%s"', final_mixed, to_unc(f_gif))
            table.insert(pass_chain_lines2, string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { %s }', loop_cmd))
            
            table.insert(pass_chain_lines2, string.format('Remove-Item -Path "%s" -ErrorAction SilentlyContinue', final_mixed))
            for _, df in ipairs(dir_files_win) do
                table.insert(pass_chain_lines2, string.format('Remove-Item -Path "%s" -ErrorAction SilentlyContinue', df))
            end
        else
            local final_mixed_mac = f_gif .. ".final.gif"
            local ff_mix = string.format('ffmpeg %s %s -filter_complex "%s" -y "%s"', ff_silent, ff_inputs_mac, mix_filter, final_mixed_mac)
            
            table.insert(pass_chain_lines2, 'echo "Omnidirectional Matrix Blending..."')
            table.insert(pass_chain_lines2, ff_mix .. " >> \"" .. f_log .. "\" 2>&1")
            
            local loop_cmd = string.format('gifsicle -O3 --lossy=%d --loop=0 --no-warnings -i "%s" -o "%s"', final_mixed_mac, f_gif)
            table.insert(pass_chain_lines2, string.format('if command -v gifsicle >/dev/null 2>&1; then %s; fi', loop_cmd))
            
            table.insert(pass_chain_lines2, string.format('rm "%s"', final_mixed_mac))
            local rm_cmd = "rm"
            for _, df in ipairs(dir_files_mac) do rm_cmd = rm_cmd .. string.format(' "%s"', df) end
            table.insert(pass_chain_lines2, rm_cmd)
        end

    else
        mp.msg.info("🎨 Spawning Unidirectional Glitch Artifacts: " .. string.upper(active_dir))
        
        local pre_tf, post_tf = "", ""
        if active_dir == "left" then
            pre_tf = "--flip-horizontal"; post_tf = "--flip-horizontal"
        elseif active_dir == "down" then
            pre_tf = "--rotate-270"; post_tf = "--rotate-90"
        elseif active_dir == "up" then
            pre_tf = "--rotate-90"; post_tf = "--rotate-270"
        end

        if is_win then
            local gifsicle_cmd = ""
            if active_dir == "right" then
                gifsicle_cmd = string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { Write-Host "Final Gifsicle Crunch (RIGHT)..."; & gifsicle -O3 --loop=0 --lossy=%d --colors %d --no-warnings -i "%s" -o "%s.final.gif"; Move-Item -Path "%s.final.gif" -Destination "%s" -Force }', FINAL_LOSSY, FINAL_COLORS, to_unc(f_gif), to_unc(f_gif), to_unc(f_gif), to_unc(f_gif))
            else
                gifsicle_cmd = string.format('if (Get-Command gifsicle -ErrorAction SilentlyContinue) { Write-Host "Final Gifsicle Crunch (%s)..."; & gifsicle %s --no-warnings -i "%s" -o "%s.t1.gif"; & gifsicle -O3 --lossy=%d --colors %d --no-warnings -i "%s.t1.gif" -o "%s.t2.gif"; & gifsicle -O3 --loop=0 %s --no-warnings -i "%s.t2.gif" -o "%s.final.gif"; Move-Item -Path "%s.final.gif" -Destination "%s" -Force; Remove-Item -Path "%s.t1.gif", "%s.t2.gif" -ErrorAction SilentlyContinue }', string.upper(active_dir), pre_tf, to_unc(f_gif), to_unc(f_gif), FINAL_LOSSY, FINAL_COLORS, to_unc(f_gif), to_unc(f_gif), post_tf, to_unc(f_gif), to_unc(f_gif), to_unc(f_gif), to_unc(f_gif), to_unc(f_gif), to_unc(f_gif))
            end
            table.insert(pass_chain_lines2, gifsicle_cmd .. " 2>> \"" .. to_unc(f_log) .. "\"")
        else
            local gifsicle_cmd = ""
            if active_dir == "right" then
                gifsicle_cmd = string.format('if command -v gifsicle >/dev/null 2>&1; then echo "Final Gifsicle Crunch (RIGHT)..."; gifsicle -O3 --loop=0 --lossy=%d --colors %d --no-warnings -i "%s" -o "%s.final.gif" && cat "%s.final.gif" > "%s" && rm "%s.final.gif"; fi', FINAL_LOSSY, FINAL_COLORS, f_gif, f_gif, f_gif, f_gif, f_gif)
            else
                gifsicle_cmd = string.format('if command -v gifsicle >/dev/null 2>&1; then echo "Final Gifsicle Crunch (%s)..."; gifsicle %s --no-warnings -i "%s" -o "%s.t1.gif" && gifsicle -O3 --lossy=%d --colors %d --no-warnings -i "%s.t1.gif" -o "%s.t2.gif" && gifsicle -O3 --loop=0 %s --no-warnings -i "%s.t2.gif" -o "%s.final.gif" && cat "%s.final.gif" > "%s" && rm "%s.t1.gif" "%s.t2.gif" "%s.final.gif"; fi', string.upper(active_dir), pre_tf, f_gif, f_gif, FINAL_LOSSY, FINAL_COLORS, f_gif, f_gif, post_tf, f_gif, f_gif, f_gif, f_gif, f_gif, f_gif, f_gif, f_gif)
            end
            table.insert(pass_chain_lines2, gifsicle_cmd .. " >> \"" .. f_log .. "\" 2>&1")
        end
    end

    if is_win then
        local gif_nonempty2 = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', to_unc(f_gif), to_unc(f_gif))
        table.insert(script_lines, string.format('if (%s) {', gif_nonempty2))
        for _, l in ipairs(pass_chain_lines2) do table.insert(script_lines, l) end
        table.insert(script_lines, string.format('} else { Add-Content -Path "%s" -Value "[gor_clip] gif empty/missing (PASS1 failed): optimization/direction chain skipped" }', to_unc(f_log)))
    else
        table.insert(script_lines, string.format('if [ -s "%s" ]; then', f_gif))
        for _, l in ipairs(pass_chain_lines2) do table.insert(script_lines, l) end
        table.insert(script_lines, string.format('else\n    echo "[gor_clip] gif empty/missing (PASS1 failed): optimization/direction chain skipped" >> "%s"\nfi', f_log))
    end

    -- Contract: detached worker writes a result sentinel before reporting success.
    local f_result_img = join_path_safe(main_clip_dir, "result_" .. unique_id .. ".txt")
    if is_win then
        local out_ok2 = string.format('((Test-Path "%s") -and ((Get-Item "%s").Length -gt 0))', to_unc(f_gif), to_unc(f_gif))
        table.insert(script_lines, string.format([[
if (%s) {
    Set-Content -Path "%s" -Value "SUCCESS" -Encoding ascii -NoNewline
} else {
    Set-Content -Path "%s" -Value "FAIL:output_file_not_created" -Encoding ascii -NoNewline
}]], out_ok2, to_unc(f_result_img), to_unc(f_result_img)))
    else
        table.insert(script_lines, string.format([[
if [ -s "%s" ]; then
    echo "SUCCESS" > "%s"
else
    echo "FAIL:output_file_not_created" > "%s"
fi]], f_gif, f_result_img, f_result_img))
    end

    if not SETTINGS.keep_log then
        if is_win then table.insert(script_lines, string.format('Remove-Item -Path "%s" -Force', to_unc(f_log)))
        else table.insert(script_lines, string.format('rm "%s"', f_log)) end
    end
    if is_win then table.insert(script_lines, 'Remove-Item -Path $MyInvocation.MyCommand.Path -Force')
    else table.insert(script_lines, 'rm "$0"') end

    local script_path = join_path_safe(main_clip_dir, "worker_img_" .. unique_id .. state.script_ext)
    local f = io.open(script_path, "w")
    if f then
        if is_win then f:write('\239\187\191\n#Requires -Version 3.0\n') end
        for _, l in ipairs(script_lines) do f:write(l .. "\n") end
        f:close()
        
        if is_win then mp.command_native({name = "subprocess", detach = true, playback_only = false, args = {"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path}})
        else mp.command_native({name = "subprocess", detach = true, playback_only = false, args = {"/bin/sh", script_path}}) end

        local ok_msg = active_dir == "alldir" and "✓ omnidirectional emulsion saved" or "✓ directional emulsion saved"
        local poll_count_img = 0
        local MAX_POLLS_IMG = 90
        local function poll_result_img()
            poll_count_img = poll_count_img + 1
            local res_f = io.open(f_result_img, "r")
            if res_f then
                local content = res_f:read("*a")
                res_f:close()
                content = content and content:gsub("%s+$", "") or ""
                if content == "SUCCESS" then
                    print("gor-osd:" .. tostring(ok_msg))
                elseif content:match("^FAIL:") then
                    print("gor-osd:" .. tostring("❌ could not save (see log)"))
                else
                    print("gor-osd:" .. tostring("⚠️ processing finished; check result"))
                end
                os.remove(f_result_img)
                return
            end
            if poll_count_img >= MAX_POLLS_IMG then
                print("gor-osd:" .. tostring("⏳ still processing; check folder"))
                return
            end
            mp.add_timeout(0.5, poll_result_img)
        end
        mp.add_timeout(0.5, poll_result_img)
    else
        print("gor-osd:" .. tostring("❌ IO Error"))
    end
end

-- INPUT BINDINGS
local function start_rec(gif)
    local path = mp.get_property("path")
    if not path then return end
    -- Worker generation below interpolates paths into shell, Python and
    -- ffconcat syntaxes. Fail closed on names those contexts cannot quote.
    local clip_dir = resolve_clip_dir(path)
    if path:find('["`$\n\r]') or path:find("'", 1, true)
        or clip_dir:find('["`$\n\r]') or clip_dir:find("'", 1, true) then
        print("gor-osd:unsupported filename for clip export")
        return
    end
    
    local _, _, ext = get_file_info(path)
    if ext == ".jpg" or ext == ".jpeg" or ext == ".png" or ext == ".webp" then
        if gif then
            process_static_image_to_gif(path)
        else
            print("gor-osd:" .. tostring("🚫 Video clip not supported for images"))
        end
        return
    end

    if state.is_recording then stop_and_process()
    else
        local pos = mp.get_property_number("time-pos")
        if pos then
            state.is_recording = true
            state.is_gif_mode = gif
            state.current_seg_start = pos
            state.last_video_pos = pos
            state.segments = {}
            update_overlay()
            print("gor-osd:" .. tostring(gif and "● GIF REC START" or "● VIDEO REC START"))
        end
    end
end

mp.add_key_binding("Meta+Alt+c", "clip_video", function() start_rec(false) end)
mp.add_key_binding("Meta+Alt+g", "clip_gif", function() start_rec(true) end)
mp.add_key_binding("Meta+Alt+z", "clip_undo", undo_last_segment)
mp.add_key_binding("Meta+Alt+x", "clip_abort", function()
    if state.is_recording then
        print("gor-osd:" .. tostring("🚫 aborted"))
        safe_reset_state()
    end
end)

mp.add_key_binding("Meta+Alt+o", "clip_open", function()
    local path = mp.get_property("path")
    local clip_dir = resolve_clip_dir(path)
    print("gor-osd:" .. tostring("📂 opening..."))
    
    if state.platform == "windows" then
        mp.command_native({name="subprocess", detach=true, args={"explorer", clip_dir}})
    elseif state.platform == "darwin" then
        mp.command_native({name="subprocess", detach=true, args={"open", clip_dir}})
    else
        mp.command_native({name="subprocess", detach=true, args={"xdg-open", clip_dir}})
    end
end)

mp.add_key_binding("Meta+Alt+f", "toggle_fade", function()
    state.enable_fade = not state.enable_fade
    local status = state.enable_fade and "ON" or "OFF"
    print("gor-osd:" .. tostring("🌓 Fade Effect: " .. status))
end)

mp.add_key_binding("Meta+Alt+Shift+f", "toggle_fade_color", function()
    if state.fade_color == "black" then
        state.fade_color = "white"
        print("gor-osd:" .. tostring("⚪ Fade Color: WHITE"))
    else
        state.fade_color = "black"
        print("gor-osd:" .. tostring("⚫ Fade Color: BLACK"))
    end
end)
