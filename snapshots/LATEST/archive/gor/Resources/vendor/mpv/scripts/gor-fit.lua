-- Receiver protocol experiment, not integrated sender source.
local crop_nonce=mp.get_opt("gor_fit-crop-session")
local crop_state=mp.get_property_native("user-data/gor/crop-epoch-state")
local crop_epoch=nil
local crop_seek_generation=0
local function valid_count(n) return type(n)=="number" and n>=0 and n<9007199254740990 and n==math.floor(n) end
local nonce_ok=type(crop_nonce)=="string" and #crop_nonce==36 and crop_nonce:match("^[%x%-]+$")
if nonce_ok then
  if crop_state==nil then crop_epoch=0
  elseif type(crop_state)=="table" and crop_state.session==crop_nonce and valid_count(crop_state.count) then crop_epoch=crop_state.count;crop_seek_generation=crop_state.seek_generation or 0 end
end
local function rotate_crop_epoch(reason)
  if not crop_epoch or not valid_count(crop_epoch) then crop_epoch=nil;return end
  if not valid_count(crop_seek_generation) then crop_epoch=nil;return end
  crop_epoch=crop_epoch+1
  if reason=="seek" then crop_seek_generation=crop_seek_generation+1 end
  local ok=mp.set_property_native("user-data/gor/crop-epoch-state",{session=crop_nonce,count=crop_epoch,path=mp.get_property("path"),reason=reason or "transport",seek_generation=crop_seek_generation})
  local saved=mp.get_property_native("user-data/gor/crop-epoch-state")
  if ok~=true or type(saved)~="table" or saved.session~=crop_nonce or saved.count~=crop_epoch then crop_epoch=nil end
end
rotate_crop_epoch("reload") -- Reload invalidates prior instance tokens before another opening.
mp.add_hook("on_load",40,function() rotate_crop_epoch("opening") end)
local function crop_token() if crop_epoch then return crop_nonce..":"..string.format("%.0f",crop_epoch) end end
-- Load lifecycle publication is separate from seek/intent token rotation.
-- A reconnect may query this state when it missed file-loaded, never infer ready from dimensions.
local load_saved=mp.get_property_native("user-data/gor/crop-load-state")
local load_count=0
local load_ready=false
local load_challenge=nil
if nonce_ok and type(load_saved)=="table" and load_saved.session==crop_nonce and valid_count(load_saved.opening) then
  load_count=load_saved.opening;load_ready=load_saved.ready==true
end
local function publish_load(ready,new_opening)
  if not nonce_ok then return end
  if new_opening then load_count=load_count+1 end
  if not valid_count(load_count) then return end
  load_ready=ready
  mp.set_property_native("user-data/gor/crop-load-state",{session=crop_nonce,opening=load_count,path=mp.get_property("path"),ready=ready,challenge=load_challenge})
end
publish_load(load_ready,false)
mp.register_script_message("crop-load-challenge",function(challenge)
  if type(challenge)~="string" or #challenge<1 or #challenge>200 then return end
  load_challenge=challenge
  publish_load(load_ready,false) -- fresh internal lifecycle, not a read/copy of retained property bytes
end)
mp.register_event("start-file",function() publish_load(false,true) end)
mp.register_event("file-loaded",function() publish_load(true,false) end)
mp.register_event("end-file",function() publish_load(false,false) end)
-- gor-fit.lua: one place that sizes the mpv window for a video.
--  * first show / new file: the final size is set in on_preloaded, before the VO sizes the window
--  * every later size change gor asks for (aspect change, crop, clamp): critically damped spring motion, retargetable
-- It does nothing until gor has pushed the screen metrics (user-data/gor/fit), so without the
-- matching gor build mpv behaves exactly as before.
-- Metrics string from gor: usableW,usableH,backingScale,chromeW,chromeTop (points, AppKit visibleFrame)
local msg = mp.msg
local FLOOR_FRACTION = 0.40     -- landscape/square: long side floor = 40% of usable width (as before)
local TALL_HEIGHT_FRACTION = 0.90 -- portrait: content height = 90% of usable height

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

local function parse_metrics(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub('^"', ""):gsub('"$', "")
  if s == "" then return nil end
  local a = {}
  for n in s:gmatch("[^,;]+") do a[#a + 1] = tonumber(n) end
  if #a ~= 5 then return nil end
  for i = 1, 5 do if not a[i] or a[i] ~= a[i] then return nil end end
  if a[1] < 2 or a[2] < 2 or a[3] < 1 or a[4] < 0 or a[5] < 0 then return nil end
  return { w = a[1], h = a[2], scale = a[3], chromeW = a[4], chromeTop = a[5] }
end

-- contain a frame (fw x fh) in (aw x ah): shrink only, centered
local function contain(fw, fh, aw, ah)
  local cw, ch
  if fw <= aw and fh <= ah then cw, ch = fw, fh
  elseif aw * fh <= ah * fw then cw = aw; ch = floor(fh * aw / fw)
  else ch = ah; cw = floor(fw * ah / fh) end
  if cw < 1 or ch < 1 then return nil end
  return { x = floor((aw - cw) / 2), y = floor((ah - ch) / 2), w = cw, h = ch }
end

-- content size proposal in points
local function proposal(vw, vh, m)
  if vw >= vh then
    local floor_t = m.w * FLOOR_FRACTION
    local long_t = floor(max(floor_t, floor_t * sqrt(max(vw, vh) / 1280)))
    return max(1, long_t), max(1, floor(long_t * vh / vw))
  end
  local h = max(1, floor(m.h * TALL_HEIGHT_FRACTION))
  return max(1, floor(h * vw / vh)), h
end

-- absolute mpv geometry "WxH+X+Y" (device pixels, content rect, relative to usable top-left)
local function geometry_for(vw, vh, m)
  if not (vw > 0 and vh > 0) then return nil end
  local pw, ph = proposal(vw, vh, m)
  local fitted = contain(pw + m.chromeW, ph + m.chromeTop, floor(m.w), floor(m.h))
  if not fitted then return nil end
  local cw, ch = fitted.w - m.chromeW, fitted.h - m.chromeTop
  if cw < 1 or ch < 1 or fitted.w < 160 or fitted.h < 90 then return nil end
  local W, H = floor(cw * m.scale), floor(ch * m.scale)
  local X, Y = floor(fitted.x * m.scale), floor((fitted.y + m.chromeTop) * m.scale)
  if W < 1 or H < 1 then return nil end
  return string.format("%dx%d+%d+%d", W, H, X, Y)
end

-- A source command is not a window fit. If Swift could not plan a frame
-- (for example decoder dimensions preceded its overlay window), plan here
-- from original decoder metadata and the actual window width, never from a
-- guessed square-pixel crop or the resolution-sensitive opening-size rule.
local function crop_fallback_geometry(value)
  local m = parse_metrics(mp.get_property_native("user-data/gor/fit") or mp.get_opt("gor_fit-metrics"))
  local od = mp.get_property_native("osd-dimensions")
  local p = mp.get_property_native("video-dec-params")
  if not m or type(od)~="table" or not od.w or od.w<=0 or type(p)~="table" then return nil end
  local w,h=tonumber(p.w),tonumber(p.h)
  if not w or not h or w<=0 or h<=0 then return nil end
  local par=tonumber(p.par)
  if not par and p.dw and p.dh and p.dw>0 and p.dh>0 then par=(p.dw/p.dh)/(w/h) end
  if not par or par<=0 then return nil end
  if value~="" then
    local cw,ch=value:match("^(%d+)x(%d+)%+%d+%+%d+$")
    w,h=tonumber(cw),tonumber(ch)
    if not w or not h or w<=0 or h<=0 then return nil end
  end
  local vp=mp.get_property_native("video-params") or p
  local aspect=w*par/h
  if ((vp.rotate or 0)%180)==90 then aspect=1/aspect end
  local pw=od.w/m.scale
  local f=contain(pw+m.chromeW,pw/aspect+m.chromeTop,floor(m.w),floor(m.h))
  if not f or f.w<=m.chromeW or f.h<=m.chromeTop then return nil end
  return string.format("%dx%d+%d+%d",floor((f.w-m.chromeW)*m.scale),
    floor((f.h-m.chromeTop)*m.scale),floor(f.x*m.scale),floor((f.y+m.chromeTop)*m.scale))
end

local function parse_geom(g)
  local w, h, x, y = tostring(g):match("^(%d+)x(%d+)%+(-?%d+)%+(-?%d+)$")
  if not w then return nil end
  return { tonumber(w), tonumber(h), tonumber(x), tonumber(y) }
end

-- effective (display) video size from the demuxer track: rotation and pixel aspect applied
local function read_metrics()
  -- gor pushes fresh metrics as user-data; the launch value (script-opt, ";"-separated) is the fallback
  return mp.get_property_native("user-data/gor/fit") or mp.get_opt("gor_fit-metrics")
end

local function demux_dims()
  for _, t in ipairs(mp.get_property_native("track-list") or {}) do
    if t.type == "video" and not t.albumart and t["demux-w"] and t["demux-h"] then
      local w, h = t["demux-w"], t["demux-h"]
      local par = t["demux-par"]
      if par and par > 0 and par ~= 1 then
        if par > 1 then w = w * par else h = h / par end
      end
      local rot = t["demux-rotation"]
      if rot and (rot % 180) == 90 then w, h = h, w end
      return w, h
    end
  end
end

local anim = nil
local cur = nil          -- last geometry gor-fit applied {W,H,X,Y}
local last_aspect = nil
local last_animate_at = -10

-- Window motion: a critically damped spring per component (x, y, w, h), like Apple's non-bouncy springs.
-- Starts with zero velocity and no snap, never overshoots, never stops dead (velocity decays smoothly), and a new
-- target in mid-motion keeps the current position AND velocity, so rapid aspect/crop changes flow into each other
-- instead of restarting or queueing (speed toward a new, nearer target is capped so it never passes it). OMEGA (rad/s) sets the pace; it is a feel constant, not an owner-measured value.
local OMEGA = 9  -- owner Nov20: the window transformation must remain visible
local st = nil   -- {pos={..4}, vel={..4}, tgt={..4}, t=last step time, shown={..4}}

-- While the window morphs between two aspects, mpv's own aspect lock (keepaspect-window) would snap it to the new
-- video's aspect at once (landscape -> a narrow strip at the old height) and fight every in-between size.
-- So the lock is released for the motion and restored (to whatever it was) when the motion ends or is cancelled.
local orig_kaw = mp.get_property("keepaspect-window") or "yes"
local kaw_released = false
local function release_kaw() if not kaw_released then kaw_released = true; mp.set_property("keepaspect-window", "no") end end
local function restore_kaw() if kaw_released then kaw_released = false; mp.set_property("keepaspect-window", orig_kaw) end end

local opening_motion = false
local crop_owned = false
local last_crop_packet=nil
local crop_after_source=nil
local crop_after_source_timer=nil
local function clear_crop_after_source()
  crop_after_source=nil
  if crop_after_source_timer then crop_after_source_timer:kill();crop_after_source_timer=nil end
end
local function stop_anim() clear_crop_after_source(); if anim then anim:kill(); anim = nil end st = nil; crop_owned = false; opening_motion = false; restore_kaw() end

local function apply_now(g)
  cur = parse_geom(g) or cur
  return mp.set_property("geometry", g) == true
end

local function step()
  if not opening_motion and mp.get_property_native("user-data/gor/media-transition") == true then stop_anim(); return end
  if mp.get_property_bool("fullscreen", false) then stop_anim(); return end
  local now = mp.get_time()
  local dt = min(0.05, max(0, now - st.t)); st.t = now
  local e = math.exp(-OMEGA * dt)
  local settled = true
  for i = 1, 4 do
    local d = st.pos[i] - st.tgt[i]
    local B = st.vel[i] + OMEGA * d
    local nd = (d + B * dt) * e
    st.vel[i] = (st.vel[i] - OMEGA * B * dt) * e
    st.pos[i] = st.tgt[i] + nd
    if math.abs(nd) >= 0.5 or math.abs(st.vel[i]) >= 6 then settled = false end
  end
  local v = {}
  if settled then v = { st.tgt[1], st.tgt[2], st.tgt[3], st.tgt[4] }
  else for i = 1, 4 do v[i] = floor(st.pos[i] + 0.5) end end
  v[1] = max(1, v[1]); v[2] = max(1, v[2])
  if not (st.shown and st.shown[1] == v[1] and st.shown[2] == v[2] and st.shown[3] == v[3] and st.shown[4] == v[4]) then
    st.shown = { v[1], v[2], v[3], v[4] }
    apply_now(string.format("%dx%d+%d+%d", v[1], v[2], v[3], v[4]))
  end
  if settled then if anim then anim:kill(); anim = nil end st = nil; crop_owned=false; opening_motion = false; restore_kaw() end
end

local function animate_to(g, opening)
  if not opening and mp.get_property_native("user-data/gor/media-transition") == true then return end
  opening_motion = opening == true
  local to = parse_geom(g)
  if not to then return end
  last_animate_at = mp.get_time()
  if st and anim then            -- retarget: keep position and velocity
    st.tgt = { to[1], to[2], to[3], to[4] }
    -- A critically damped spring crosses its target only if it is already heading there faster than OMEGA * distance.
    -- Cap just that component (speed toward the target <= OMEGA * remaining distance); speed away from the target,
    -- position and all other velocity stay, so reversals keep flowing and nothing passes the target and comes back.
    for i = 1, 4 do
      local d = st.pos[i] - st.tgt[i]
      if d > 0 then st.vel[i] = max(st.vel[i], -OMEGA * d)
      elseif d < 0 then st.vel[i] = min(st.vel[i], -OMEGA * d)
      else st.vel[i] = 0 end
    end
    return
  end
  local from = { to[1], to[2], to[3], to[4] }
  local od = mp.get_property_native("osd-dimensions")
  if od and od.w and od.h and od.w > 0 and od.h > 0 then from[1], from[2] = od.w, od.h end
  if cur then from[3], from[4] = cur[3], cur[4] end
  if from[1] == to[1] and from[2] == to[2] and from[3] == to[3] and from[4] == to[4] then
    apply_now(g); return
  end
  release_kaw()
  st = { pos = { from[1], from[2], from[3], from[4] }, vel = { 0, 0, 0, 0 }, tgt = { to[1], to[2], to[3], to[4] },
         t = mp.get_time(), shown = nil }
  anim = mp.add_periodic_timer(1 / 60, step)
end

local shown = false
local file_fresh = false   -- a new file opened into an owner-placed window: dims/aspect arrivals must not refit it
local orig_awr = mp.get_property("auto-window-resize") or "yes"   -- whatever mpv.conf/launch args set
local function restore_awr() mp.set_property("auto-window-resize", orig_awr) end
local opening_dims_pending = false
local function fit_opening_dims(vw, vh, m)
  local g = geometry_for(vw, vh, m)
  if not g then stop_anim(); restore_awr(); return end
  last_aspect = vw / vh
  mp.set_property("auto-window-resize", "no")      -- gor-fit owns sizing now
  if not shown then
    shown = true
    apply_now(g)                                    -- first show: final size, no animation
    msg.info("first-show geometry " .. g)
  else
    -- Owner Nov20: a new film must adopt its format immediately, not inherit
    -- the previous film's width/height. Demux display geometry is available
    -- before file-loaded/poll completion. This is the new-file writer only;
    -- old crop/explicit-fit writers remain fenced during media replacement.
    -- window41-followup E: no stop_anim() here - a new-file retarget keeps the
    -- in-flight position and velocity like every other retarget in animate_to;
    -- only the previous file's crop ownership ends with it.
    file_fresh = true
    crop_owned = false
    -- Swift provides actual current frame in the same ordered loadfile batch,
    -- using the existing screen/device-pixel geometry conversion. Never guess
    -- an mpv property for it.
    local anchor = parse_geom(mp.get_property_native("user-data/gor/fit-anchor"))
    local target = parse_geom(g)
    if not target then return end
    if not anchor and cur then
      -- window41-followup B: no anchor from Swift at all (a dropped push, an
      -- open path without one). Fall back to the last frame this script
      -- applied itself: the size still adapts, the center stays where the
      -- window was last put. Stale after an owner drag, which is why Swift
      -- pushes the live frame on every replacing loadfile; this is the last
      -- resort, not the source.
      anchor = { cur[1], cur[2], cur[3], cur[4] }
    end
    if not anchor then return end
    local x = floor(anchor[3] + (anchor[1] - target[1]) / 2)
    local y = floor(anchor[4] + (anchor[2] - target[2]) / 2)
    x = max(0, min(x, floor(m.w * m.scale) - target[1]))
    y = max(floor(m.chromeTop * m.scale), min(y, floor(m.h * m.scale) - target[2]))
    g = string.format("%dx%d+%d+%d", target[1], target[2], x, y)
    stop_anim()
    apply_now(g) -- preloaded: new film geometry before its first frame, never animate from old aspect
    msg.info("new-file geometry " .. g)
  end
end
mp.add_hook("on_preloaded", 50, function()
  stop_anim()
  mp.set_property("video-crop", "")
  last_crop_packet=nil
  opening_dims_pending = true
  file_fresh = false
  crop_owned = false
  local m = parse_metrics(read_metrics())
  if not m or mp.get_property_bool("fullscreen", false) or mp.get_property_native("user-data/gor/pip-window-owned") == true then
    opening_dims_pending = false
    stop_anim(); restore_awr(); return
  end
  local vw, vh = demux_dims()
  if not vw then stop_anim(); restore_awr(); return end
  opening_dims_pending = false
  fit_opening_dims(vw, vh, m)
end)

-- gor asks for a window frame (clamp, crop refit, aspect change): animate there
mp.register_script_message("animate", function(g)
  if mp.get_property_bool("fullscreen", false) then return end
  if not parse_geom(g) then msg.warn("bad geometry " .. tostring(g)); return end
  -- Swift's explicit aspect/crop target supersedes the corresponding display notification.
  -- Otherwise the delayed follower would replay its opening-size proposal after this fit.
  local p = mp.get_property_native("video-params")
  if p and p.dw and p.dh and p.dw > 0 and p.dh > 0 then
    last_aspect = ((p.rotate or 0) % 180) == 90 and p.dh / p.dw or p.dw / p.dh
  end
  animate_to(g)
end)

-- Each crop and window sample comes from one Swift clock. Never start the
-- independent geometry spring, or the window would trail the source crop.
local function apply_crop_frame(g, state)
  if mp.get_property_bool("fullscreen", false) then stop_anim(); return "skipped-fullscreen" end
  if mp.get_property_native("user-data/gor/window-transition") == true then stop_anim(); return "skipped-transition" end
  if not parse_geom(g) then return "invalid-geometry" end
  if not crop_owned then stop_anim(); release_kaw(); crop_owned = true end
  local accepted = apply_now(g)
  if state == "done" then crop_owned = false; restore_kaw() end
  return accepted and "accepted" or "setter-failed"
end
mp.register_script_message("crop-frame", apply_crop_frame)
-- Validate both owned commands before changing either source or geometry.
mp.register_script_message("crop-packet", function(payload, source_path, opening_epoch)
  if type(opening_epoch) ~= "string" or not crop_token() or opening_epoch~=crop_token() then return end
  if type(source_path) ~= "string" or source_path == "" or mp.get_property("path") ~= source_path then return end
  local ok, envelope = pcall(require("mp.utils").parse_json, payload)
  if not ok or type(envelope) ~= "table" then return end
  local function identity(v)
    return type(v)=="string" and #v>0 and #v<=20 and v:match("^%d+$") and (#v==1 or v:sub(1,1)~="0") and (#v<20 or v<="18446744073709551615")
  end
  if not identity(envelope.intent) or not identity(envelope.motion) or not identity(envelope.sequence) or type(envelope.final)~="boolean" then return end
  local rows=envelope.commands
  if type(rows)~="table" or #rows<1 or #rows>2 then return end
  if type(rows[1])~="table" then return end
  local source = rows[1].command
  if type(source) ~= "table" or #source ~= 3 or source[1] ~= "set_property" or source[2] ~= "video-crop" or type(source[3]) ~= "string" then return end
  if #rows==2 and (type(rows[2])~="table" or type(rows[2].command)~="table") then return end
  local frame = rows[2] and rows[2].command
  if frame and (type(frame) ~= "table" or #frame ~= 5 or frame[1] ~= "script-message-to" or frame[2] ~= "gor_fit" or frame[3] ~= "crop-frame" or not parse_geom(frame[4]) or (frame[5] ~= "moving" and frame[5] ~= "done")) then return end
  if frame and ((frame[5]=="done")~=envelope.final) then return end
  local function less(a,b) return #a<#b or (#a==#b and a<b) end
  if last_crop_packet and last_crop_packet.token==opening_epoch and last_crop_packet.path==source_path then
    if less(envelope.intent,last_crop_packet.intent) or less(envelope.motion,last_crop_packet.motion) or not less(last_crop_packet.sequence,envelope.sequence) then return end
  end
  local function receipt(source_status,geometry_status)
    mp.set_property_native("user-data/gor/crop-packet-receipt",{
      token=opening_epoch,path=source_path,intent=envelope.intent,motion=envelope.motion,
      sequence=envelope.sequence,final=envelope.final,crop=source[3],source=source_status,geometry=geometry_status})
  end
  if mp.get_property_native("user-data/gor/media-transition") == true then return end
  if mp.get_property_native("user-data/gor/window-transition") == true then return end
  last_crop_packet={token=opening_epoch,path=source_path,intent=envelope.intent,motion=envelope.motion,sequence=envelope.sequence}
  if not crop_owned then stop_anim(); release_kaw(); crop_owned = true end
  clear_crop_after_source()
  -- One final source crop, followed by observed new source layout or500ms.
  -- Window animation never writes an intermediate source crop.
  local window_geometry=frame and frame[4] or crop_fallback_geometry(source[3])
  local crop_ok=mp.set_property("video-crop",source[3])
  if crop_ok~=true then crop_owned=false;restore_kaw();receipt("setter-failed","not-attempted");return end
  if mp.get_property("video-crop")~=source[3] then crop_owned=false;restore_kaw();receipt("readback-failed","not-attempted");return end
  if mp.get_property_bool("fullscreen",false) then
    crop_owned=false;restore_kaw();receipt("accepted","skipped-fullscreen");return
  end
  if not window_geometry then
    crop_owned=false;restore_kaw();receipt("accepted","not-attempted");return
  end
  local target=parse_geom(window_geometry)
  local mine={token=opening_epoch,path=source_path,expires=mp.get_time()+0.5}
  crop_after_source=mine
  local function window_after_source(timeout)
    if crop_after_source~=mine then return end
    if crop_token()~=mine.token or mp.get_property("path")~=mine.path or
       mp.get_property_native("user-data/gor/media-transition")==true or
       mp.get_property_native("user-data/gor/window-transition")==true then
      clear_crop_after_source();crop_owned=false;restore_kaw();return
    end
    if mp.get_property_bool("fullscreen",false) then
      clear_crop_after_source();crop_owned=false;restore_kaw();receipt("accepted","skipped-fullscreen");return
    end
    local dw=mp.get_property_number("dwidth",0)
    local dh=mp.get_property_number("dheight",0)
    local matches=dw>0 and dh>0 and math.abs((dw/dh)/(target[1]/target[2])-1)<=0.005
    if not timeout and not matches then return end
    clear_crop_after_source()
    animate_to(window_geometry)
    if not anim then crop_owned=false;restore_kaw() end
    -- Window command scheduled, not a same-display-frame or physical landing claim.
    receipt("accepted","accepted")
  end
  mine.check=window_after_source
  crop_after_source_timer=mp.add_periodic_timer(1/60,function()
    if mp.get_time()>=mine.expires then window_after_source(true) end
  end)

end)

-- gor: the user grabbed the window; stop moving it
mp.register_script_message("cancel", function() stop_anim() end)
-- Unlike motion-only cancel, a receiver seek boundary invalidates packets already on another socket.
local function crop_seek_boundary()
  stop_anim();rotate_crop_epoch("seek")
end
mp.register_event("seek",crop_seek_boundary)
mp.register_script_message("crop-seek-fence",crop_seek_boundary)
mp.register_script_message("crop-intent-fence",function() stop_anim();rotate_crop_epoch("invalidate") end)

-- Follow display changes without assuming the VO physically rotates its output frames.
-- GPU VOs apply rotation during rendering, so video-out-params can retain the old
-- width/height. video-params carries the current display dimensions and rotation.
local aspect_retry = nil
local function follow_display_aspect()
  if crop_owned then return end
  if mp.get_property_native("user-data/gor/media-transition") == true then return end
  if aspect_retry then aspect_retry:kill(); aspect_retry = nil end
  if mp.get_property_native("user-data/gor/window-transition") == true then return end
  if mp.get_property_native("user-data/gor/pip-window-owned") == true then return end
  if mp.get_property_native("user-data/gor/stereo-window-owned") == true then return end
  local p = mp.get_property_native("video-params")
  if not p or not p.dw or not p.dh or p.dw <= 0 or p.dh <= 0 then return end
  local w, h = p.dw, p.dh
  if ((p.rotate or 0) % 180) == 90 then w, h = h, w end
  local a = w / h
  if opening_dims_pending then
    local m = parse_metrics(read_metrics())
    if not m then return end
    opening_dims_pending = false
    fit_opening_dims(w, h, m)
    return
  end
  if not last_aspect or math.abs(a / last_aspect - 1) < 0.02 then return end
  if file_fresh then last_aspect = a; return end   -- same rule: opening a stream never recenters/resizes
  local crop = mp.get_property("video-crop")
  if crop and crop ~= "" then return end
  -- Keep gor's crop geometry authoritative, including delayed filter notifications.
  for _, f in ipairs(mp.get_property_native("vf") or {}) do
    if f.label == "gorcrop" then return end
  end
  if mp.get_property_bool("fullscreen", false) then return end
  local m = parse_metrics(read_metrics())
  if not m then return end
  local remaining = 1.5 - (mp.get_time() - last_animate_at)
  if remaining > 0 then
    -- Do not drop a rapid change during a crop/clamp animation. Re-read the latest
    -- state after its ownership window, never replay a captured old aspect.
    aspect_retry = mp.add_periodic_timer(remaining + 0.01, follow_display_aspect)
    return
  end
  local g = geometry_for(w, h, m)
  if g then last_aspect = a; animate_to(g) end
end
-- Native fullscreen owns geometry until Swift confirms a stable windowed receipt.
-- Cancel even if a native double-click reaches Lua before the app's property receipt.
mp.observe_property("fullscreen", "bool", function(_, full)
  if full then stop_anim() end
end)
mp.observe_property("user-data/gor/window-transition", "native", function(_, active)
  if active then stop_anim() else follow_display_aspect() end
end)
mp.observe_property("video-rotate", "native", function() file_fresh = false end)   -- rotate is an owner command
mp.observe_property("video-params", "native", follow_display_aspect)
mp.observe_property("video-out-params", "native", follow_display_aspect)


-- ---------------------------------------------------------------------------------------------
-- Smooth picture move / zoom for the video MENU ITEMS (one click = one step). Each click moves a TARGET; the
-- value follows it with the same critically damped spring as the window motion: no tick-tick-tick, no overshoot,
-- no backlog (the target never runs more than a step and a half ahead of what is shown, so letting go of the key stops
-- within a few frames of easing, with nothing left queued). Anything else that changes the property (reset zoom
-- and pan, a new crop) is noticed and simply wins: the motion drops its target and follows the new value.
-- ---------------------------------------------------------------------------------------------
local MOVE_OMEGA = 20
local PAN_STEP, ZOOM_STEP = 0.05, 0.1          -- same step sizes as the menu items had
local mv = {}                                   -- per property: {cur, vel, tgt, last}
local mv_timer, mv_t = nil, 0
local pip_zoom_active = false
local normal_zoom = nil
local MV_PROPS = { "video-pan-x", "video-pan-y", "video-zoom" }
local MV_ALL = { "video-pan-x", "video-pan-y", "video-zoom", "panscan" }   -- panscan only moves with the reset
local MV_EPS = { ["video-pan-x"] = 5e-4, ["video-pan-y"] = 5e-4, ["video-zoom"] = 3e-3, ["panscan"] = 3e-3 }

local function mv_sync(p)
  local actual = mp.get_property_number(p)
  if actual == nil then return nil end
  local s = mv[p]
  if not s or math.abs(actual - s.last) > 1e-6 then   -- first use, or someone else changed it
    s = { cur = actual, vel = 0, tgt = actual, last = actual }
    mv[p] = s
  end
  return s
end

local function mv_stop()
  if mv_timer then mv_timer:kill(); mv_timer = nil end
end

local function mv_step()
  local now = mp.get_time()
  local dt = min(0.05, max(0, now - mv_t)); mv_t = now
  local e = math.exp(-MOVE_OMEGA * dt)
  local busy = false
  for _, p in ipairs(MV_ALL) do
    local s = mv[p]
    if s then
      local actual = mp.get_property_number(p)
      if actual == nil or math.abs(actual - s.last) > 1e-6 then   -- changed by someone else: let go
        mv[p] = nil
      else
        local d = s.cur - s.tgt
        local B = s.vel + MOVE_OMEGA * d
        local nd = (d + B * dt) * e
        s.vel = (s.vel - MOVE_OMEGA * B * dt) * e
        s.cur = s.tgt + nd
        if math.abs(nd) < MV_EPS[p] and math.abs(s.vel) < MV_EPS[p] * 8 then
          s.cur = s.tgt; s.vel = 0
        else
          busy = true
        end
        if s.cur ~= s.last then s.last = s.cur; mp.set_property_number(p, s.cur) end
      end
    end
  end
  if not busy then mv_stop() end
end

local function mv_nudge(p, delta, step)
  local s = mv_sync(p)
  if not s then return end
  local lead = 1.5 * step
  local t = s.tgt + delta
  if t > s.cur + lead then t = s.cur + lead elseif t < s.cur - lead then t = s.cur - lead end
  if p == "video-zoom" and pip_zoom_active then t = max(0, t) end
  -- keep the speed toward the target within what a critically damped spring can follow without overshoot
  s.tgt = t
  local d = s.cur - s.tgt
  if d > 0 then s.vel = max(s.vel, -MOVE_OMEGA * d) elseif d < 0 then s.vel = min(s.vel, -MOVE_OMEGA * d) else s.vel = 0 end
  if not mv_timer then
    mv_t = mp.get_time()
    mv_timer = mp.add_periodic_timer(1 / 60, mv_step)
  end
end

local function vr_motion(kind, x, y, z)
  if mp.get_property_native("user-data/vr180-look/enabled") ~= true then return false end
  mp.commandv("script-message-to", "vr180_look", "vr180-look-motion", kind, tostring(x or 0), tostring(y or 0), tostring(z or 0))
  return true
end

mp.register_script_message("move", function(dx, dy)
  dx, dy = tonumber(dx) or 0, tonumber(dy) or 0
  if vr_motion("step", dx, dy, 0) then return end
  if dx ~= 0 then mv_nudge("video-pan-x", dx * PAN_STEP, PAN_STEP) end
  if dy ~= 0 then mv_nudge("video-pan-y", dy * PAN_STEP, PAN_STEP) end
end)
mp.register_script_message("zoom", function(dz)
  dz = tonumber(dz) or 0
  if vr_motion("step", 0, 0, dz) then return end
  if dz ~= 0 then mv_nudge("video-zoom", dz * ZOOM_STEP, ZOOM_STEP) end
end)

-- ---------------------------------------------------------------------------------------------
-- Held keys (fn+shift+arrows, fn+shift+comma/period). Swift sends "hold dx dy dz" on every key press and key repeat
-- and "hold 0 0 0" when the key comes up, the modifiers change or the app loses focus. While a direction is held the
-- picture runs at a steady speed (eased in); when it is released the speed eases to zero over about a quarter of a
-- second. No target is ever queued: what you see is only the current speed, so nothing is left to run after release.
-- If the release never arrives (lost key-up) nothing refreshes the hold and it stops by itself after HOLD_WATCHDOG.
-- ---------------------------------------------------------------------------------------------
local HOLD_TAU = 0.045                     -- speed easing time constant (s): ~0.15 s from rest to full, ~0.2 s to stop
local HOLD_WATCHDOG = 0.6                  -- s without a refresh = treat as released
local HOLD_SPEED = { ["video-pan-x"] = 0.6, ["video-pan-y"] = 0.6, ["video-zoom"] = 1.0 }   -- units per second
local HOLD_LIMIT = { ["video-pan-x"] = { -1.5, 1.5 }, ["video-pan-y"] = { -1.5, 1.5 }, ["video-zoom"] = { -1.0, 4.0 } }
local hold = { dir = { ["video-pan-x"] = 0, ["video-pan-y"] = 0, ["video-zoom"] = 0 }, last = 0 }
local hold_s = {}                           -- per property: {cur, vel, last}
local hold_timer, hold_t = nil, 0

local function hold_step()
  local now = mp.get_time()
  local dt = min(0.05, max(0, now - hold_t)); hold_t = now
  local expired = now - hold.last > HOLD_WATCHDOG
  local k = 1 - math.exp(-dt / HOLD_TAU)
  local busy = false
  for _, p in ipairs(MV_PROPS) do
    local dir = expired and 0 or hold.dir[p]
    local s = hold_s[p]
    if s then
      local actual = mp.get_property_number(p)
      if actual == nil or math.abs(actual - s.last) > 1e-6 then     -- changed by someone else (reset, crop): it wins
        s.cur = actual or s.cur; s.vel = 0; s.last = s.cur
      end
      s.vel = s.vel + (dir * HOLD_SPEED[p] - s.vel) * k
      if dir == 0 and math.abs(s.vel) < MV_EPS[p] * 4 then s.vel = 0 end
      local nxt = s.cur + s.vel * dt
      local lim = HOLD_LIMIT[p]
      if p == "video-zoom" and pip_zoom_active then lim = { 0, lim[2] } end
      if nxt < lim[1] then nxt = lim[1]; s.vel = 0 elseif nxt > lim[2] then nxt = lim[2]; s.vel = 0 end
      if nxt ~= s.cur then s.cur = nxt; s.last = nxt; mp.set_property_number(p, nxt) end
      if s.vel ~= 0 or dir ~= 0 then busy = true end
    end
  end
  if not busy then
    if hold_timer then hold_timer:kill(); hold_timer = nil end
    for _, p in ipairs(MV_PROPS) do hold.dir[p] = 0 end
  end
end

mp.register_script_message("hold", function(dx, dy, dz)
  dx, dy, dz = tonumber(dx) or 0, tonumber(dy) or 0, tonumber(dz) or 0
  if vr_motion("hold", dx, dy, dz) then return end
  hold.dir["video-pan-x"], hold.dir["video-pan-y"], hold.dir["video-zoom"] = dx, dy, dz
  hold.last = mp.get_time()
  if dx == 0 and dy == 0 and dz == 0 then return end                 -- release: the running timer eases to a stop
  for _, p in ipairs(MV_PROPS) do
    mv[p] = nil                                                      -- a click-step spring in flight yields to the held key
    local actual = mp.get_property_number(p)
    local s = hold_s[p]
    if actual ~= nil and (not s or math.abs(actual - s.last) > 1e-6) then hold_s[p] = { cur = actual, vel = 0, last = actual } end
  end
  mv_stop()
  if not hold_timer then
    hold_t = mp.get_time()
    hold_timer = mp.add_periodic_timer(1 / 60, hold_step)
  end
end)

-- PiP shares the displayed-mode receipt with Swift's visible-picture UI.
-- Only zoom is mode-local here; crop, aspect and content pan retain their owners.
local function set_mode_zoom(value)
  mv["video-zoom"] = nil
  hold_s["video-zoom"] = nil
  hold.dir["video-zoom"] = 0
  mp.set_property_number("video-zoom", value)
end

local function enter_pip_zoom()
  local state = mv_sync("video-zoom")
  normal_zoom = state and state.tgt or mp.get_property_number("video-zoom", 0)
  set_mode_zoom(max(0, normal_zoom))
end

mp.register_script_message("pip-mode", function(mode)
  local active = mode == "yes"
  if active == pip_zoom_active then return end
  pip_zoom_active = active
  if active then
    enter_pip_zoom()
  elseif normal_zoom ~= nil then
    set_mode_zoom(normal_zoom)
    normal_zoom = nil
  end
end)

-- Keyboard/native property writes cannot shrink an already small PiP picture.
mp.observe_property("video-zoom", "number", function(_, value)
  if pip_zoom_active and value and value < 0 then set_mode_zoom(0) end
end)

-- A new playback never inherits the preceding file's suspended zoom.
mp.add_hook("on_preloaded", 60, function()
  normal_zoom = nil
  mv["video-zoom"] = nil
  hold_s["video-zoom"] = nil
  hold.dir["video-zoom"] = 0
  if pip_zoom_active then enter_pip_zoom() end
end)

-- reset zoom & pan: every moved property eases to 0 (the target is absolute, no lead limit; the same overshoot-free spring).
mp.register_script_message("reset", function()
  normal_zoom = nil
  if vr_motion("reset", 0, 0, 0) then return end
  -- Reset owns motion until a new move command; an old held-key timer must not fight it.
  if hold_timer then hold_timer:kill(); hold_timer = nil end
  hold_s = {}
  for _, p in ipairs(MV_PROPS) do hold.dir[p] = 0 end
  for _, p in ipairs(MV_ALL) do
    local s = mv_sync(p)
    if s and s.tgt ~= 0 then
      s.tgt = 0
      local d = s.cur
      if d > 0 then s.vel = max(s.vel, -MOVE_OMEGA * d) elseif d < 0 then s.vel = min(s.vel, -MOVE_OMEGA * d) else s.vel = 0 end
    end
  end
  if not mv_timer then
    mv_t = mp.get_time()
    mv_timer = mp.add_periodic_timer(1 / 60, mv_step)
  end
end)

-- self test hook: script-message gor-fit-selftest (prints one line per case)
mp.register_script_message("selftest", function(ms, vw, vh)
  local m = parse_metrics(ms)
  local g = m and geometry_for(tonumber(vw), tonumber(vh), m)
  msg.info("SELFTEST " .. tostring(vw) .. "x" .. tostring(vh) .. " -> " .. tostring(g))
end)

-- A failed/cancelled replacement holds the last window until actual media loads.
mp.observe_property("user-data/gor/media-transition","native",function(_,pending) if pending then stop_anim() else follow_display_aspect() end end)

local function crop_source_layout_event()
  if crop_after_source then crop_after_source.check(false) end
end
mp.observe_property("video-out-params","native",crop_source_layout_event)
mp.observe_property("dwidth","number",crop_source_layout_event)
mp.observe_property("dheight","number",crop_source_layout_event)
