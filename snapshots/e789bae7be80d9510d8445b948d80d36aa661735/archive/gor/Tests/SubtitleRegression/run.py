
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
r=Path(__file__).resolve().parents[2]
code='''import Foundation
// Exact real-mpv state: primary option false, secondary option true, no tracks,
// secondary-sid false. Old OR(options) hid the custom compositor.
precondition(!SubtitleRendererOwnership.nativeVisible(primaryVisible:false,secondaryVisible:true,primaryID:nil,secondaryID:false))
for primary in [false,true] {for secondary in [false,true] {
 precondition(!SubtitleRendererOwnership.nativeVisible(primaryVisible:primary,secondaryVisible:secondary,primaryID:nil,secondaryID:false))
 precondition(SubtitleRendererOwnership.nativeVisible(primaryVisible:primary,secondaryVisible:secondary,primaryID:3,secondaryID:false)==primary)
 precondition(SubtitleRendererOwnership.nativeVisible(primaryVisible:primary,secondaryVisible:secondary,primaryID:nil,secondaryID:4)==secondary)
}}
precondition(!SubtitleRendererOwnership.nativeVisible(primaryVisible:true,secondaryVisible:true,primaryID:"auto",secondaryID:"no"))
precondition(SubtitleRendererOwnership.nativeVisible(primaryVisible:false,secondaryVisible:true,primaryID:nil,secondaryID:"2"))
print("PASS production renderer ownership: exact mpv empty-secondary/default-true regression, all visibility/selected-track combinations, string IDs, no/auto options")
'''
sv=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift');a=sv.index('    func setNativeSubtitleRendererActive(');b=sv.index('    private let vrSubtitleReplicator',a)
code+='\nenum CATransaction {static func begin(){};static func setDisableActions(_ b:Bool){};static func commit(){}}\nfinal class Layer {var isHidden=false}\nfinal class Renderer {var vrSubtitleReplicator=Layer()\n'+sv[a:b]+"}\nlet renderer=Renderer()\nrenderer.setNativeSubtitleRendererActive(true)\nprecondition(renderer.vrSubtitleReplicator.isHidden)\nrenderer.setNativeSubtitleRendererActive(SubtitleRendererOwnership.nativeVisible(primaryVisible:false,secondaryVisible:true,primaryID:nil,secondaryID:false))\nprecondition(!renderer.vrSubtitleReplicator.isHidden)\nprint(\"PASS actual production compositor gate unhides subtitle layer for empty secondary track and retains hide for real native track\")\n"
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/Engine/MPVCommand.swift'),str(t/'main.swift'),'-o',str(t/'test')],check=True);subprocess.run([str(t/'test')],check=True)
p=_sub_read(_pp_split().path(r,'PPController.swift'))
assert 'let nativeReported=primaryNative || secondaryNative' not in p
assert 'SubtitleRendererOwnership.nativeVisible(' in p and '125: "secondary-sid"' in p
assert 'vr180Controller?.vrModeEnabled == true || LiveCaptionController.shared.isActive' in p
assert 'recordSubtitleProbe(results: results, nativeReported: nativeReported)' in p
print('PASS production integration: selected-track-qualified compositor gate; live captions request custom ownership; both live native keys subscribed; state capture wired')
print('Linux only; no native AppKit subtitle bitmap/render or real mpv run in this test')
