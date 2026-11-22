-- ================================================================
--  block_fonts.lua - font drop filter
--  Owns: pre-load extension guard
--  Answers: TRAP-04
--  Contract: keep state and code paths unchanged
-- ================================================================
-- block_fonts.lua
-- Font files that slip past the overlay (window edge gap) are silently rejected.
-- mpv has no native extension filter for drag-drop; this hook fires before
local blocked = {
    ttf=true, otf=true,
    woff=true, woff2=true,
    pfb=true, pfa=true, fon=true,
}

mp.add_hook("on_load", 50, function()
    local path = mp.get_property("path") or ""
    local ext = path:match("%.([^%.]+)$")
    if ext and blocked[ext:lower()] then
        mp.msg.warn("[block_fonts] rejected font drop: " .. path)
        mp.commandv("stop")
    end
end)
