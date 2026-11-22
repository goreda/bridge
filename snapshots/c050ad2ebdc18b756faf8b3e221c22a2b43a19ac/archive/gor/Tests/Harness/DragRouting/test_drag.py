"""Source-bound drag gesture/routing model. No AppKit or real file actions."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().path(root,'PPController_Features.swift');q=_pp_split().path(root,'PPController.swift');s=p.read_text();other=q.read_text();a=s[s.index('final class DragDropHandler'):s.index('// MARK: - MusicModeController')]
for t in ['sqrt(dx*dx + dy*dy) > 10','currentChangeCount != self.lastDragChangeCount','win.isVisible, win.isOnActiveSpace','win.frame.contains(NSEvent.mouseLocation)','urls != self.lastDraggedURLs','if hasNonFont { self.stopTorrent() }','MPVCommand.make(["sub-add", url.path])','let mode = isFirst ? "replace" : "append-play"','MPVCommand.make(["loadfile", url.path, mode])']:assert t in a,t
assert a.count('NSEvent.addGlobalMonitorForEvents')==3
assert 'removeMonitor' not in a,'monitor lifetime changed; review model'
open_source=other[other.index('func openMediaFile'):other.index('func togglePlay()')]
for t in ['restoreDefaultProfile()','MPVCommand.make(["loadfile", path])','TunnelForBlockedHosts.shared.willLoad(path)']:assert t in open_source,t
fonts={'ttf','otf','woff','woff2'};subs={'srt','ass','ssa','vtt','sub'};images={'jpg','jpeg','png','gif','bmp','webp','tiff','tif','ico','heic','heif','avif'}
class Drag:
 def __init__(self):self.last=[]
 def drop(self,paths,moved=True,changed=True,visible=True,active=True,inside=True):
  if not(moved and changed and visible and active and inside) or not paths or paths==self.last:return []
  self.last=list(paths);out=[];first=True
  ext=lambda p:p.rsplit('.',1)[-1].lower() if '.' in p else ''
  if any(ext(p) not in fonts for p in paths):out.append(('stopTorrent',))
  for p in paths:
   e=ext(p)
   if e in fonts:out.append(('font',p));continue
   if e in subs:out.append(('sub-add',p));continue
   if e=='torrent':out.append(('torrent',p));continue
   if e in images:out.append(('open',p));continue
   out.append(('open',p) if first else ('append-play',p));first=False
  return out
controls=[]
for option in ['moved','changed','visible','active','inside']:
 x=Drag();assert x.drop(['movie.mkv'],**{option:False})==[]
controls.append('gesture/change/visibility/active-space/window-location guards')
x=Drag();assert x.drop(['font.TTF','font.otf'])==[('font','font.TTF'),('font','font.otf')];controls.append('font-only loads without torrent stop')
x=Drag();assert x.drop(['a.mkv','b.mp4'])==[('stopTorrent',),('open','a.mkv'),('append-play','b.mp4')];controls.append('first ordinary media replace then append-play')
x=Drag();assert x.drop(['a.srt'])==[('stopTorrent',),('sub-add','a.srt')];controls.append('current subtitle routing and current stop side effect reproduced')
x=Drag();assert x.drop(['a.torrent'])==[('stopTorrent',),('torrent','a.torrent')];controls.append('torrent source uses stream route')
x=Drag();assert x.drop(['a.png'])==[('stopTorrent',),('open','a.png')];controls.append('image delegates to paired openMediaFile')
x=Drag();x.drop(['a.mkv']);assert x.drop(['b.mkv'])==[('stopTorrent',),('open','b.mkv')];controls.append('different later gesture allowed')
reds=[]
x=Drag();x.drop(['a.mkv']);assert x.drop(['a.mkv'])==[];reds.append({'case':'same URLs in later deliberate gesture','observed':'suppressed across gestures because lastDraggedURLs never cleared','scope':'source/model action suppression, native drag event ordering unverified'})
x=Drag();out=x.drop(['a.srt']);assert out[0]==('stopTorrent',);reds.append({'case':'subtitle-only while torrent plays','observed':'stopTorrent precedes sub-add','scope':'confirmed route side effect, actual playback disruption unverified'})
x=Drag();out=x.drop(['a.png','b.mkv']);assert ('open','a.png') in out and ('open','b.mkv') in out;reds.append({'case':'image then ordinary media','observed':'both use replace/open because image does not consume isFirst','scope':'mixed-file routing characterization; owner intent unresolved'})
x=Drag();out=x.drop(['a.torrent','b.mkv']);assert ('torrent','a.torrent') in out and ('open','b.mkv') in out;reds.append({'case':'torrent then ordinary media','observed':'torrent stream then media open; paired open stops torrent again','scope':'mixed-file ordering characterization, not native stream race proof'})
reds.append({'case':'repeated start() monitor registration','observed':'three unretained global monitor registrations per start; no teardown','scope':'source lifecycle gap; production repeated start/deallocation not proved'})
print(json.dumps({'result':'PASS controls and expected drag characterizations','controls':controls,'characterizations':reds,'source_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [p,q]},'scope':'Python routing model/current Swift source guards; no AppKit event/drag/file/font/torrent/mpv/UI execution'},indent=2))
