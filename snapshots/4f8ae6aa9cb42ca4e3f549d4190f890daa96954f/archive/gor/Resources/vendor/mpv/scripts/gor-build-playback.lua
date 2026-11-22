-- Report build-to-first-playback time, split at mpv's file-loaded event.
-- AppDelegate relays mpv stderr to /tmp/gor_direct.log.
local marker = "/tmp/gor-build-playback-start.marker"
local file_loaded_at = nil
local reported = false

mp.register_event("file-loaded", function()
    if not reported then file_loaded_at = os.time() end
end)

mp.register_event("playback-restart", function()
    if reported or not file_loaded_at then return end
    local loaded_at = file_loaded_at
    file_loaded_at = nil
    local f = io.open(marker, "r")
    if not f then return end
    local build_at = tonumber(f:read("*l"))
    f:close()
    if not build_at then return end
    local playing_at = os.time()
    -- A cancelled run must not turn a later manual launch into a build result.
    if loaded_at < build_at or playing_at < loaded_at or playing_at - build_at > 1800 then return end
    reported = true
    os.remove(marker)
    mp.msg.info(string.format(
        "[GOR BUILD] build-complete -> first mpv playback-restart: total=%ds; launch-to-file-loaded=%ds; stream/buffering=%ds (build=%d, file-loaded=%d, playback=%d)",
        playing_at - build_at, loaded_at - build_at, playing_at - loaded_at,
        build_at, loaded_at, playing_at))
end)
