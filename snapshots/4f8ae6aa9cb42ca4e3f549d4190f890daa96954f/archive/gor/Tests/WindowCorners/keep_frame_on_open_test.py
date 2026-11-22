#!/usr/bin/env python3
"""Execute actual gor-fit Lua: new films adapt before Swift poll completion.
Needs lupa; absence is a failure, never a skipped PASS. Native window pixels
and backend interaction remain separate Darwin/owner acceptance.
"""
from pathlib import Path
import re,sys
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[2]
SOURCE=(ROOT/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text()

def exercise(source, mutate=False):
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute('''
now=0;props={['keepaspect-window']='yes',['auto-window-resize']='yes'}
props['user-data/gor/fit']='1440,900,1,0,0'
props['track-list']={{type='video',['demux-w']=1920,['demux-h']=1080}}
props['osd-dimensions']={w=800,h=450}
hooks={};observers={};messages={};timers={};writes={}
mp={msg={verbose=function()end,info=function()end,warn=function()end}}
function mp.get_property_native(k)return props[k]end
function mp.get_property(k)return props[k]end
function mp.get_property_bool(k,d)local v=props[k];if v==nil then return d end;return v end
function mp.get_property_number(k,d)return tonumber(props[k]) or d end
function mp.get_opt(k)return nil end
function mp.get_time()return now end
function mp.set_property(k,v)props[k]=v;writes[#writes+1]={k,v,now}end
mp.set_property_native=mp.set_property;mp.set_property_number=mp.set_property
function mp.add_hook(n,p,f)if p==50 then hooks[n]=f end end
function mp.register_script_message(n,f)messages[n]=f end
function mp.register_event(n,f)end
function mp.observe_property(n,t,f)observers[n]=f end
function mp.commandv(...)end
function mp.add_periodic_timer(d,f)local t={live=true,timeout=d};function t:kill()self.live=false end;t.f=f;timers[#timers+1]=t;return t end
function tick(n)for i=1,n do now=now+1/60;local count=#timers;for j=1,count do local t=timers[j];if t.live then t.f()end end end end
function video(w,h)props['track-list']={{type='video',['demux-w']=w,['demux-h']=h}}end
''')
    l.execute(source);g=l.globals();g.hooks['on_preloaded']()
    first=g.props['geometry'];assert first,'first-show size missing'
    g.props['user-data/gor/fit-anchor']='800x450+320+200'
    g.props['user-data/gor/media-transition']=True
    g.video(1080,1920);g.hooks['on_preloaded']()
    g.tick(2)
    assert g.props['geometry']!=first,'new portrait still stuck on previous format'
    g.tick(100);portrait=g.props['geometry'];assert portrait!=first
    assert portrait.endswith('+492+20'),portrait
    # A second format change while replacement is still marked pending must
    # replace the prior target immediately, not wait for polling/file-loaded.
    g.video(2390,1000);g.hooks['on_preloaded']();g.tick(100)
    wide=g.props['geometry'];assert wide!=portrait
    # Explicit/crop animations still cannot bypass media replacement.
    g.messages['animate']('300x300+0+0');g.tick(100);assert g.props['geometry']==wide
    g.props['user-data/gor/media-transition']=False
    g.messages['animate']('500x500+0+0');g.tick(2);assert g.props['geometry']!=wide
    g.messages['cancel']();stopped=g.props['geometry'];g.tick(100);assert g.props['geometry']==stopped
    # Fullscreen and PiP remain owned by their existing writers.
    for key in ['fullscreen','user-data/gor/pip-window-owned']:
        g.props[key]=True;g.video(1080,1920);g.hooks['on_preloaded']();g.tick(100)
        assert g.props['geometry']==stopped,key+' refit escaped'
        g.props[key]=False
    return True

exercise(SOURCE)
assert re.search(r'local OMEGA = 9\b',SOURCE),'window spring not slowed from delivered16'
# Analytic settling for the real critically damped zero-velocity formula.
# For a 500px change, the <0.5px and <6px/s stop criteria are both required.
import math
def settle(omega):
 for frame in range(1,600):
  t=frame/60;d=500*(1+omega*t)*math.exp(-omega*t);v=500*omega*omega*t*math.exp(-omega*t)
  if d<0.5 and v<6:return t
old,new=settle(16),settle(9)
assert new>old*1.5 and new<1.5,(old,new)
print('PASS actual Lua: immediate new-file portrait/wide retarget, transition-only bypass, explicit-fit block, cancel, fullscreen/PiP')
print('PASS actual spring formula: delivered16 settling %.3fs -> candidate9 %.3fs (500px), native pixels NOT_RUN'%(old,new))
# Mutation must reproduce the original suppression, not only inspect a marker.
mutant=SOURCE.replace('animate_to(g, true)','-- mutation: suppress new-file geometry')
try:exercise(mutant,True)
except AssertionError:print('PASS old new-file-suppression mutant refused')
else:raise AssertionError('old suppression mutant accepted')

recenter=SOURCE.replace('x, y)\n    animate_to(g, true)', '0, 0)\n    animate_to(g, true)')
assert recenter!=SOURCE
try:exercise(recenter)
except AssertionError:print('PASS recenter mutant refused')
else:raise AssertionError('recenter mutant accepted')
swift=(ROOT/'Sources/gor/Player/PPController.swift').read_text()
assert 'GorOpeningFit.clampGeometry(frame:win.frame,screen:screen)' in swift
assert 'return anchor + MPVCommand.make' in swift
print('PASS anchor comes from actual window via existing geometry conversion, before ordered loadfile')

# ---- window41 follow-up (A: replace/append split + live anchor on the single-command path,
# ---- B: nil-anchor fallback, E: mid-flight velocity carry) ----
SOURCE2=(ROOT/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text()

def boot(source):
    l=LuaRuntime(unpack_returned_tuples=True)
    l.execute('''
now=0;props={['keepaspect-window']='yes',['auto-window-resize']='yes'}
props['user-data/gor/fit']='1440,900,1,0,0'
props['track-list']={{type='video',['demux-w']=1920,['demux-h']=1080}}
props['osd-dimensions']={w=800,h=450}
hooks={};observers={};messages={};timers={};writes={}
mp={msg={verbose=function()end,info=function()end,warn=function()end}}
function mp.get_property_native(k)return props[k]end
function mp.get_property(k)return props[k]end
function mp.get_property_bool(k,d)local v=props[k];if v==nil then return d end;return v end
function mp.get_property_number(k,d)return tonumber(props[k]) or d end
function mp.get_opt(k)return nil end
function mp.get_time()return now end
function mp.set_property(k,v)props[k]=v;writes[#writes+1]={k,v,now}end
mp.set_property_native=mp.set_property;mp.set_property_number=mp.set_property
function mp.add_hook(n,p,f)if p==50 then hooks[n]=f end end
function mp.register_script_message(n,f)messages[n]=f end
function mp.register_event(n,f)end
function mp.observe_property(n,t,f)observers[n]=f end
function mp.commandv(...)end
function mp.add_periodic_timer(d,f)local t={live=true,timeout=d};function t:kill()self.live=false end;t.f=f;timers[#timers+1]=t;return t end
function tick(n)for i=1,n do now=now+1/60;local count=#timers;for j=1,count do local t=timers[j];if t.live then t.f()end end end end
function video(w,h)props['track-list']={{type='video',['demux-w']=w,['demux-h']=h}}end
''')
    l.execute(source)
    g=l.globals()
    g.hooks['on_preloaded']()
    first=g.props['geometry'];assert first,'first-show size missing'
    return g,first

def parse_g(gs):
    m=re.match(r'(-?\d+)x(-?\d+)\+(-?\d+)\+(-?\d+)',gs);return tuple(map(int,m.groups()))

def geom_writes(g):
    out=[];w=g['writes']
    for i in range(1,len(w)+1):
        e=w[i]
        if e[1]=='geometry':out.append(e[2])
    return out

def disp(a,b):
    pa,pb=parse_g(a),parse_g(b)
    return sum(abs(x-y) for x,y in zip(pa,pb))

def exercise_followup(source):
    g,first=boot(source)
    g.props['user-data/gor/fit-anchor']='800x450+320+200'
    # E: open a portrait, then a taller portrait 0.2s into the ~1.03s settle: mid-flight retarget.
    # No media-transition flag here on purpose: the local/IPTV batch open path sets none.
    g.video(1080,1920);g.hooks['on_preloaded']()
    g.tick(12)
    w0=geom_writes(g)
    assert len(w0)>=3,w0
    pre=disp(w0[-2],w0[-1])
    g.video(720,1920);g.hooks['on_preloaded']()
    g.tick(1)
    w1=geom_writes(g)
    post=disp(w1[-2],w1[-1])
    assert pre>0 and 0.5*pre<=post<=2*pre,('motion not continuous on mid-flight retarget (restart or snap)',pre,post)
    g.tick(400)
    settled=g.props['geometry'];g.tick(60)
    assert g.props['geometry']==settled,'never settled after mid-flight retarget'
    assert parse_g(settled)[0]!=parse_g(w0[-1])[0],'taller format never adopted'
    # B: no fit-anchor at all -> fall back to the last applied frame: size adapts, x-center stays.
    g2,first2=boot(source)
    assert g2.props['user-data/gor/fit-anchor'] is None
    g2.video(1080,1920);g2.hooks['on_preloaded']();g2.tick(200)
    fb=g2.props['geometry']
    assert fb!=first2,'nil anchor: no adaptation at all'
    g1,f=parse_g(first2),parse_g(fb)
    assert f[2]==g1[2]+(g1[0]-f[0])//2,('nil-anchor fallback recenters',g1,f)
    # Fence semantics retained: a transition beginning still parks in-flight motion.
    assert 'if pending then stop_anim() end' in source,'transition-begin park removed'
    return True

exercise_followup(SOURCE2)
print('PASS follow-up E: mid-flight new-file retarget keeps velocity (no restart, no size snap), settles at the new target')
print('PASS follow-up B: nil fit-anchor falls back to last applied frame (size adapts, center kept)')

# RED against window41 semantics, as mutants on the patched source:
mutE=SOURCE2.replace('    file_fresh = true\n    crop_owned = false\n','    file_fresh = true\n    stop_anim()\n    crop_owned = false\n')
assert mutE!=SOURCE2
try:exercise_followup(mutE)
except AssertionError:print('PASS follow-up E mutant refused: stop_anim restored (window41 writer) snaps the size back to stale osd dims')
else:raise AssertionError('E mutant accepted')

mutB=SOURCE2.replace('    if not anchor and cur then','    if false then -- mutant: no nil-anchor fallback')
assert mutB!=SOURCE2
try:exercise_followup(mutB)
except AssertionError:print('PASS follow-up B mutant refused: without the fallback a nil anchor skips adaptation')
else:raise AssertionError('B mutant accepted')

# A: Swift-side structural replace/append split + live anchor on the single-command channel (pins; Swift NOT_RUN).
swift=(ROOT/'Sources/gor/Player/PPController.swift').read_text()
assert 'static func isReplacingLoadfile(_ command: [Any]) -> Bool' in swift
assert 'return mode == "replace"' in swift
assert 'Self.isReplacingLoadfile(command)' in swift
assert 'func pushLiveFitAnchor()' in swift
assert 'beginMediaTransition()\n                pushLiveFitAnchor()' in swift
assert 'payload.contains("\\"loadfile\\"")' not in swift,'substring loadfile guard still present'
assert 'payload.contains("\\"append")' not in swift,'substring append guard still present'
assert swift.count('user-data/gor/fit-anchor')>=3,'anchor not pushed on all channels'
assert 'GorOpeningFit.clampGeometry(frame:win.frame,screen:screen)' in swift
assert 'return anchor + MPVCommand.make' in swift
assert 'let retiresActive = name != "loadfile" || Self.isReplacingLoadfile(command)' in swift,'active-file retirement not guarded by the classifier'
assert 'if retiresActive {' in swift
print('PASS follow-up A: structural replace/append split (no substring), live anchor pushed on the single-command loadfile path')
print('PASS follow-up A2: pose/WT/camera/dimming retirement guarded by isReplacingLoadfile (see loadfile_retirement_test.py for the compiled matrix)')
