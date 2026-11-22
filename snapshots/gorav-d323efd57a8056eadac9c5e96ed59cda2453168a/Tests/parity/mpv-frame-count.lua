-- INVALID - DO NOT USE (finding L12-F2). Retained for audit only; the u8
-- harness does NOT invoke this script.
--
-- This u7 hook queried mpv property "decoder-frame-count", which does NOT
-- exist in any checked upstream mpv (v0.34.1..v0.39.0 + master: property
-- table player/command.c and DOCS/man/input.rst; zero upstream commits).
-- On real mpv 0.34.1 it wrote null for every clip (team 3 run 2026-11-01).
-- The u8 reference metric is ffprobe -count_frames stream.nb_read_frames per
-- the gdb ruling (peer-attributed via coordination).

local function num(v)
    if v == nil then return "null" end
    return string.format("%d", v)
end

local function write_out()
    local out = mp.get_property("MPV_FRAME_OUT")
    if out == nil or out == "" then return end
    local frames = mp.get_property_number("decoder-frame-count")
    local drops = mp.get_property_number("frame-drop-count")
    local f = io.open(out, "w")
    if f == nil then return end
    f:write('{"decoder_frame_count": ' .. num(frames)
        .. ', "frame_drop_count": ' .. num(drops) .. '}\n')
    f:close()
end

mp.register_event("end-file", write_out)
mp.register_event("shutdown", write_out)
