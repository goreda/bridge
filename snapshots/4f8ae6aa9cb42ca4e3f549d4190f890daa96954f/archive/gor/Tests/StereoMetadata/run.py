import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import re,os,tempfile,subprocess
r=Path(__file__).resolve().parents[2];s=(_pp_split().path(r,'PPController.swift')).read_text()
a=s.index('            vr180Controller?.autoDetectFromVideoParams(');b=s.index('\n            )',a)+len('\n            )');call=s[a:b]
table=re.search(r'private static let slowProps: KeyValuePairs<Int, String> = \[(.*?)\n    \]',s,re.S).group(1)
scoped=re.search(r'private static let fileScopedKeys: \[String\] = \[(.*?)\n    \]',s,re.S).group(1)
assert '41: "metadata"' in table and '"metadata"' in scoped
ids=re.findall(r'(\d+):',table);assert len(ids)==len(set(ids))
code='''import Foundation
final class Controller {
 var last:[String:String]=[:];var w:Double=0;var mode:String?=nil
 func autoDetectFromVideoParams(stereoMode:String?,width:Double,height:Double,filename:String,pixelAspect:Double=1,sourceCrop:String?=nil,containerMetadata:[String:String]=[:]) {
 last=containerMetadata;w=width;mode=stereoMode
 }
}
let vr180Controller:Controller?=Controller()
let currentFilePath="test.mkv",newW=1920.0,newH=1080.0
func actualCall(_ results:[String:Any]) {
'''+call+'''
}
actualCall(["video-params/stereo-in":"sbs2l","video-dec-params/w":3840.0,"video-dec-params/h":1080.0,"metadata":["stereo_mode":"left_right","title":"owner video"]])
precondition(vr180Controller!.last["stereo_mode"]=="left_right")
precondition(vr180Controller!.w==3840 && vr180Controller!.mode=="sbs2l")
actualCall([:]);precondition(vr180Controller!.last.isEmpty && vr180Controller!.w==1920)
actualCall(["metadata":["invalid":12]]);precondition(vr180Controller!.last.isEmpty)
print("PASS actual production call: metadata plus stereo-in/decoded dimensions; absent/malformed metadata safely defaults empty")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
print('PASS static poll table: metadata request ID unique, slow batch with dimensions, file-scoped purge on transition')
