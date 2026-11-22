
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
r=Path(__file__).resolve().parents[2];p=_sub_read(_pp_split().path(r,'PPController.swift'));a=p.index('    func toggleLiveCaption(languageCode:');b=p.index('\n    // MARK: - mpv event dispatch',a)
code='''import Foundation
enum GORResources {static var root:URL?;static func vendor()->URL?{root}}
final class ScreenCaptureEngine {static let shared=ScreenCaptureEngine();var pcmTapEnabled=false;var pcmHandler:((UnsafeBufferPointer<Float>)->Void)?}
final class LiveCaptionDiagnostics {func begin(model:String,threads:Int,window:Double,step:Double,language:String,vad:Bool){};func ingest(_ d:Data){}}
enum Diag {static func log(_ s:String){}}
final class SubtitleView {enum Config {static var liveCaptionActive=false};var isHidden=true;var moves=0;func show(text:String,duration:Double,at:Double){};func moveToDefaultPosition(_ n:Int){moves+=1}}
final class H {var subtitleView=SubtitleView();var currentTime=0.0
'''+p[a:b]+'''
}
let c=LiveCaptionController.shared,h=H();var errors:[String]=[];var shown:[String]=[]
c.onFailure={errors.append($0)};c.onCaption={text,_,_ in shown.append(text)}
GORResources.root=nil
precondition(!h.toggleLiveCaption() && !c.isActive && !SubtitleView.Config.liveCaptionActive && h.subtitleView.moves==0)
let root=URL(fileURLWithPath:CommandLine.arguments[1]);GORResources.root=root
precondition(!h.toggleLiveCaption() && !c.isActive && !SubtitleView.Config.liveCaptionActive)
let fm=FileManager.default
let whisper=root.appendingPathComponent("whisper"),models=whisper.appendingPathComponent("models")
try fm.createDirectory(at:models,withIntermediateDirectories:true)
let bin=whisper.appendingPathComponent("whisper-live")
try "#!/bin/sh\\nprintf '%s\\\\n' '{\\"type\\":\\"partial\\",\\"text\\":\\"real process caption\\"}'\\nsleep 3\\n".write(to:bin,atomically:true,encoding:.utf8)
try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:bin.path)
precondition(!h.toggleLiveCaption() && !c.isActive && !SubtitleView.Config.liveCaptionActive)
try Data([1]).write(to:models.appendingPathComponent("ggml-small.bin"))
precondition(h.toggleLiveCaption(languageCode:"tr") && c.isActive && SubtitleView.Config.liveCaptionActive)
precondition(c.preferredLanguage=="tr" && !h.subtitleView.isHidden && h.subtitleView.moves==1)
precondition(ScreenCaptureEngine.shared.pcmTapEnabled && ScreenCaptureEngine.shared.pcmHandler != nil)
let until=Date().addingTimeInterval(1)
while shown.isEmpty && Date()<until {RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
precondition(shown==["real process caption"])
precondition(!h.toggleLiveCaption() && !c.isActive && !SubtitleView.Config.liveCaptionActive)
precondition(!ScreenCaptureEngine.shared.pcmTapEnabled && ScreenCaptureEngine.shared.pcmHandler==nil)
try fm.removeItem(at:bin)
precondition(!h.toggleLiveCaption() && !SubtitleView.Config.liveCaptionActive)
precondition(errors.count==4)
print("PASS actual production controller + full LiveCaptionController: absent vendor/binary/model, real child JSON->caption, successful activation, hidden-subtitle recovery, stop/retry tap cleanup; no optimistic ON")
print("Linux process/renderer-boundary test only; no real audio capture or whisper model inference")
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(r/'Sources/gor/GorSubtitles/LiveCaptionController.swift')),str(t/'main.swift'),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test'),str(t/'vendor')],check=True)
assert 'self.spineUI.showMPVOSD("live caption: " + message)' in p
print('PASS static: actual startup failure reason also shown in existing OSD, not silently lost in logs')
