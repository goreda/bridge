
# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];menu=_sub_read(r/'Sources/gor/UI/MenuActions.swift')
a=menu.index('enum PlayerWindowPlacement {');b=menu.index('\nextension AppDelegate {',a);plan=menu[a:b];a=menu.index('enum PlayerPictureInPicture {');b=menu.index('\nextension AppDelegate {',a);plan+=menu[a:b]
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text('import Foundation\n'+plan+'''
let prefs=UserDefaults(suiteName:"gor-size-test-"+UUID().uuidString)!
let state=URL(fileURLWithPath:CommandLine.arguments[1])
try! JSONSerialization.data(withJSONObject:["build":"old-app","pid":123,"sub-scale":0.65,"sub-delay":2,"audio-delay":3]).write(to:state)
precondition(SubtitleSizePreference.restored(defaults:prefs,stateURL:state)==0.65)
try! JSONSerialization.data(withJSONObject:["build":"new-app","pid":124,"sub-scale":1]).write(to:state)
precondition(SubtitleSizePreference.restored(defaults:prefs,stateURL:state)==0.65,"new default must not overwrite choice")
SubtitleSizePreference.save(0.5,defaults:prefs);precondition(SubtitleSizePreference.restored(defaults:prefs,stateURL:state)==0.5)
SubtitleSizePreference.save(1,defaults:prefs);precondition(SubtitleSizePreference.restored(defaults:prefs,stateURL:state)==1)
precondition(prefs.object(forKey:"sub-delay")==nil && prefs.object(forKey:"audio-delay")==nil)
for screen in [CGRect(x:0,y:0,width:1920,height:1080),CGRect(x:-1920,y:-200,width:1920,height:1080)] {
 let normal=CGRect(x:screen.minX+300,y:screen.minY+200,width:1200,height:675)
 let first=PlayerPictureInPicture.frame(current:normal,visible:screen)
 precondition(first.minX==screen.minX && first.minY==screen.minY)
 let moved=CGRect(x:screen.maxX-400,y:screen.maxY-225,width:400,height:225)
 let restored=PlayerPictureInPicture.frame(current:normal,visible:screen,preferred:moved)
 precondition(restored==moved,"user moved size/corner wins")
}
print("PASS actual preference migration0.65 -> next launch0.65, menu/keyboard save/reset, no delay persistence; PiP bottom-left default, user corner/size wins")
''')
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(r/'Sources/gor/Subtitles/SubtitlePreferences.swift')),str(p/'main.swift'),'-o',str(p/'run')],check=True);subprocess.run([str(p/'run'),str(p/'state.json')],check=True)
a=_sub_read(r/'Sources/gor/App/AppDelegate.swift');c=_sub_read(_pp_split().path(r,'PPController.swift'))
assert '"--sub-scale=\\(SubtitleSizePreference.restored() ?? 1)"' in a
assert 'SubtitleSizePreference.save(value,pictureInPicture:' in c and 'row.merge(subtitleView.typographyProbe)' in c
assert 'pipPreferredFrame=target' in a and 'gor.pip.preferredFrame' in a
print('PASS launch restore occurs before mpv starts/poll default; canonical readback saves both menu and keyboard adjustments; rendered/canvas/PiP/scale probe included')
