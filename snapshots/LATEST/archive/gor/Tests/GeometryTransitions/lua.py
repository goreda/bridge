def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
from lupa import LuaRuntime
r=Path(__file__).resolve().parents[2]
l=LuaRuntime(unpack_returned_tuples=True)
l.execute('''props={fullscreen=false,["keepaspect-window"]="yes",["auto-window-resize"]="yes",["osd-dimensions"]={w=800,h=450},["video-params"]={dw=1920,dh=1080},["user-data/gor/fit"]="1920,1040,1,0,0"};handlers={};observers={};timers={};clock=0;writes={};mp={msg={info=function()end,warn=function()end,verbose=function()end}}
mp.get_property=function(k)return props[k]end;mp.get_property_number=mp.get_property;mp.get_property_native=mp.get_property;mp.get_property_bool=function(k,f)if props[k]==nil then return f end return props[k] end
mp.get_opt=function()return nil end
mp.set_property=function(k,v)props[k]=v;if k=="geometry" then writes[#writes+1]=v end end;mp.set_property_number=mp.set_property;mp.set_property_native=mp.set_property
mp.get_time=function()return clock end;mp.register_script_message=function(k,f)handlers[k]=f end
mp.add_periodic_timer=function(t,f)local timer={callback=f,active=true};timer.kill=function()timer.active=false end;timers[#timers+1]=timer;return timer end
mp.add_hook=function()end;mp.observe_property=function(k,t,f)observers[k]=f end;mp.commandv=function()end
function tick(n)for i=1,n do clock=clock+1/60;local count=#timers;for j=1,count do if timers[j].active then timers[j].callback() end end end end
''')
l.execute((r/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text());g=l.globals()
def animate(s):g.handlers.animate(s)
def notify(k,v):g.props[k]=v;g.observers[k](k,v)
def count():return len(g.writes)
# Test actual Lua callbacks, not a motion port.
for target in ['1200x675+30+40','400x800+-200+60','1600x450+0+0']:
 animate(target);l.eval('tick')(12)
 notify('fullscreen',True);c=count();l.eval('tick')(120)
 assert count()==c and g.props['keepaspect-window']=='yes'
 animate('400x300+0+0');l.eval('tick')(90);assert count()==c
 notify('fullscreen',False)
print('PASS actual Lua fullscreen observer cancels each active spring; no late timer writes and aspect-lock restored; fullscreen animate rejected')
notify('user-data/gor/window-transition',True)
g.props['video-params']=l.table_from({'dw':900,'dh':1600});g.observers['video-params']('video-params',g.props['video-params'])
c=count();l.eval('tick')(120);assert count()==c
print('PASS actual Lua aspect follower suppressed during native fullscreen transition')
# Explicit gor target uses same animate entry; follow_display_aspect yields to stereo ownership.
g.props['user-data/gor/stereo-window-owned']=True
animate('900x600+20+30');notify('user-data/gor/window-transition',False);l.eval('tick')(180)
assert g.writes[count()]=='900x600+20+30'
for _ in range(3):
 animate('400x800+20+30');l.eval('tick')(8);animate('900x600+20+30');l.eval('tick')(180)
 assert g.writes[count()]=='900x600+20+30'
print('PASS actual Lua mixed retarget/repeated sequence reaches exactly latest geometry without a queued old endpoint')

# Mono: an explicit latest aspect cannot be overwritten by the delayed opening proposal.
g.props['user-data/gor/stereo-window-owned']=False
notify('user-data/gor/window-transition',True)
g.props['video-params']=l.table_from({'dw':2390,'dh':1000})
animate('1195x500+20+30')
notify('user-data/gor/window-transition',False)
l.eval('tick')(300)
assert g.writes[count()]=='1195x500+20+30'
print('PASS actual Lua mono explicit aspect fit is not overwritten by delayed display-aspect opening proposal')

animate('1600x800+-40+-48');l.eval('tick')(240)
assert g.writes[count()]=='1600x800+-40+-48'
print('PASS actual Lua parser/spring/emitter preserves explicit negative offsets end-to-end')

#195k actual production fence callbacks. Failed/cancelled loads never lift the fence;
# the next successful file-loaded is the only release, supplied by Swift.
for scenario in ['magnet-open-mid-SBS','file-switch','load-failure','load-cancel','quick-reopen']:
 animate('1400x700+10+20');l.eval('tick')(8)
 notify('user-data/gor/media-transition',True)
 c=count()
 for height in [350,175,87,44]:
  animate('1400x%d+10+20'%height)
  g.props['video-params']=l.table_from({'dw':1400,'dh':height})
  g.observers['video-params']('video-params',g.props['video-params'])
  l.eval('tick')(60)
 assert count()==c and g.props['keepaspect-window']=='yes',scenario
 if scenario in ['load-failure','load-cancel']:
  l.eval('tick')(600);assert count()==c,scenario
 notify('user-data/gor/media-transition',False)
 animate('960x540+10+20');l.eval('tick')(180)
 assert g.writes[count()]=='960x540+10+20',scenario
 print('PASS actual Lua transition fence: '+scenario+' holds width/height and resumes only newest explicit fit')
sw=(_pp_split().path(r,'PPController.swift')).read_text()
torrent=(r/'Sources/gor/Media/TorrentManager.swift').read_text()
assert 'func streamTorrent(_ magnetOrURL: String) {\n        controller?.beginMediaTransition()' in torrent
assert 'guard !mediaTransitionPending else { return }' in sw
assert 'if musicModeController?.isMusicMode != true && !mediaTransitionPending' in sw
assert 'Double(bounds.width / bounds.height) * 0.5' not in sw
assert 'Double(bounds.width/bounds.height)*0.5' not in sw
assert 'finishMediaTransition()' in sw and 'mediaTransitionPending && mediaTransitionLoaded' in sw
assert '!ThreeDRecognitionBridge.internalMedia(path)' in sw
co=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(r)).read_text())
assert 'guard !mediaTransitionPending else { return }' in co
assert 'preparedLoadID=UUID();preparedLoadPending=false' in co
print('PASS Swift wiring pins: intent fence, metadata/refit hold, no window-to-source feedback, native-task invalidation, internal-shot exclusion')
