#!/usr/bin/env python3
"""Compile and execute the exact production Process runner, not parse-only."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,shutil
r=Path(__file__).resolve().parents[2];s=(lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(r)).read_text())
a=s.index('    // Typed execution seam.');b=s.index('\n    func scan(',a);method=s[a:b]
spc=(lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(r)).read_text())
head='import Foundation\n'+spc.split('// BEGIN relocated FFmpegAnalysisThreads.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated FFmpegAnalysisThreads.swift',1)[0]+spc.split('// BEGIN relocated CropHTTPReader.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated CropHTTPReader.swift',1)[0]+'''
final class Runner {var epoch=0;let lock=NSLock();var active:Process?;func valid(_ e:Int)->Bool{epoch==e}
'''
tail='''
 func test(_ path:String){
 let result=run(path,["-v","error","-f","lavfi","-i","color=black:s=32x32:r=1:d=1","-frames:v","1","-pix_fmt","gray16le","-f","rawvideo","pipe:1"],epoch:0,cap:4096)
 let expected=try! Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
 precondition(result.failure==nil && result.status==0 && result.stdout==expected && result.stdout.count==2048)
 print("PASS exact production source-pixel Process runner typechecked and executed real FFmpeg frame; native AppKit target NOT_RUN")
 }
}
Runner().test(CommandLine.arguments[1])
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(head+method+tail)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(t/'main.swift'),'-o',str(t/'test')],check=True)
 expected=subprocess.check_output(['ffmpeg','-v','error','-filter_threads','1','-filter_complex_threads','1','-f','lavfi','-i','color=black:s=32x32:r=1:d=1','-frames:v','1','-pix_fmt','gray16le','-f','rawvideo','pipe:1'])
 (t/'expected.raw').write_bytes(expected)
 subprocess.run([str(t/'test'),shutil.which('ffmpeg'),str(t/'expected.raw')],check=True,timeout=20)
 # Negative control proves this catches the owner's build failure.
 mutant=(head+method+tail).replace('let readerArgs = CropHTTPReader.arguments(args)','let args = CropHTTPReader.arguments(args)').replace('FFmpegAnalysisThreads.arguments(readerArgs) : readerArgs','FFmpegAnalysisThreads.arguments(args) : args')
 (t/'mutant.swift').write_text(mutant.replace('Runner().test(CommandLine.arguments[1])',''))
 result=subprocess.run([swift,'-typecheck',str(t/'mutant.swift')],capture_output=True,text=True)
 assert result.returncode!=0 and "invalid redeclaration of 'args'" in result.stderr
 print('PASS original duplicate-local build-break mutant rejected by Swift typechecker')
