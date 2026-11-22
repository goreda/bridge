
# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,os
r=Path(__file__).resolve().parents[2]
diag=_sub_read(r/'Sources/gor/GorCore/Diag.swift');diag=diag[diag.index('final class LiveCaptionDiagnostics'):];diag=diag[:diag.index('\n}\n')+3];  # stop before DisplayHeadroomDiag etc. (AppKit-only)

s=_sub_read(r/'Sources/gor/GorSubtitles/LiveCaptionController.swift').replace('private(set) ', '').replace('private ', '')
prefix='''import Foundation
enum StagedRunPaths {static func tmp(_ p:String)->String{p}}  // stub: non-staged run, path unchanged
struct GORResources {static func vendor()->URL?{nil}}
struct Diag {static func log(_ s:String){}}
final class ScreenCaptureEngine {static let shared=ScreenCaptureEngine();var pcmTapEnabled=false;var pcmHandler:((UnsafeBufferPointer<Float>)->Void)?}
'''
test='''
func check(_ x:Bool,_ label:String){precondition(x,label);print("PASS "+label)}
var b=LiveCaptionBlocks()
check(b.ingest("one two three",isFinal:false)=="one two three","first block")
check(b.ingest("one two three four",isFinal:false)=="one two three four","append preserves block beginning")
b.endUtterance()
check(b.ingest("one two three four",isFinal:false)==nil,"silence fences retained old decoder prefix")
check(b.ingest("one two three four new phrase",isFinal:false)=="new phrase","post silence starts new block without old words")
var long=LiveCaptionBlocks();let words=(0..<30).map{"w\\($0)"}.joined(separator:" ")
let page=long.ingest(words,isFinal:false)!
check(page.split(separator:" ").count==12 && page.hasPrefix("w0 "),"long transcript emits first bounded page not scrolling suffix")
check(long.ingest(words,isFinal:false)!.hasPrefix("w12 "),"next page advances atomically by entire block")
let c=LiveCaptionController.shared;c.isActive=true
var rendered:[String]=[];c.onCaption={text,_,_ in rendered.append(text)}
c.renderSubtitleBlock("old words",isFinal:false)
RunLoop.current.run(until:Date().addingTimeInterval(1.3))
c.renderSubtitleBlock("old words fresh words",isFinal:false)
check(rendered==["old words","fresh words"],"actual controller silence timer resets block and fences old prefix")
c.teardown();check(c.transcriptGapTimer==nil,"stop cancels gap timer and renderer state")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(prefix+diag+s+test)
 # Compile the real diagnostic dependencies, as LiveCaptionDiagnostics does.
 # Do not fake the disk writer: this fixture must track its production signature.
 dependencies=[]
 for name,source in [('DepthCacheBudget.swift','ThreeD.swift'),
                     ('BoundedDiskWriter.swift','Diag.swift'),
                     ('SharedDiagnosticRecord.swift','Diag.swift')]:
  text=_sub_read(_threed_split().path(r) if source=='ThreeD.swift' else r/'Sources/gor'/source)
  begin=text.index('// BEGIN relocated '+name+' ')
  end=text.index('// END relocated '+name+'\n',begin)
  unit=p/name;unit.write_text(text[begin:end]);dependencies.append(str(unit))
 subprocess.run([os.environ.get('SWIFTC','swiftc'),*dependencies,str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
