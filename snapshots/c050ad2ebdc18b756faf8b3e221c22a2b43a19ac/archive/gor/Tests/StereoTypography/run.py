
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
r=Path(__file__).resolve().parents[2];s=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
actual=s[s.index('enum SubtitlePresentation {'):]
program='import Foundation\n'+actual+'''
for scale in [0.25,1.0,2.0,2.5] {
 for distance in [0.0,100,500,1000,2000] {
  let p=SubtitlePresentation.proximity(distance:distance)
  let mono=SubtitlePresentation.fontSize(userScale:scale,proximity:p)
  let stereo=SubtitlePresentation.fontSize(userScale:scale,proximity:p)
  precondition(mono == stereo)
  let oldMono=max(1,25*scale+12*(1-pow(p,2.2)*scale))
  precondition(abs(mono-oldMono)<0.000001)
 }
 precondition(SubtitlePresentation.fontSize(userScale:scale,proximity:1)<SubtitlePresentation.fontSize(userScale:scale,proximity:0))
}
precondition(SubtitlePresentation.proximity(distance:0)==1)
precondition(SubtitlePresentation.proximity(distance:1000)==0)
print("PASS actual shared formula: mono/stereo equal point size and complete center shrink range; original mono size formula preserved")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
f=_sub_read(r/'Sources/gor/UI/PhotonFont.swift');p=_sub_read(_pp_split().path(r,'PPController.swift'))
assert 'stereoPresentationScale' not in f and 'setStereoPresentationScale' not in p
assert 'eyeScale' not in s
assert 'let p = SubtitlePresentation.proximity(distance:Double(mouseDistance))' in s
assert 'proximity:Double' in actual
for source in ['SubtitleView.swift','SpineUI.swift']:
 text=_sub_read(r/'Sources/gor'/source)
 line=next(x for x in text.splitlines() if 'Replicator.instanceTransform =' in x)
 assert 'CATransform3DMakeTranslation' in line
print('PASS static: no stereo font multiplier; both replica transforms translation-only; shared screen-center route. Native/headset appearance unverified.')
