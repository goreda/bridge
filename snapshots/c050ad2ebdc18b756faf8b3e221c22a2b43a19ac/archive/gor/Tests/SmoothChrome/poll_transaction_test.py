#!/usr/bin/env python3
"""Compile the exact final poll UI block: same values, one outer commit."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController.swift')).read_text();a=s.index('    private func handlePollResults(');b=s.index('    // MARK: - Crop',a);block=s[a:b];a=block.index('        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }; applyVideoFrame(bounds: bounds)');body=block[a:block.rfind('    }')]
pre='''import Foundation
enum CATransaction {static var depth=0,commits=0;static func begin(){depth+=1};static func setDisableActions(_ b:Bool){precondition(b)};static func commit(){precondition(depth>0);depth-=1;if depth==0{commits+=1}}}
final class Sidebar {var values:[Double]=[];func update(currentTime:Double,duration:Double,progress:Double,volume:Float){CATransaction.begin();defer{CATransaction.commit()};values=[currentTime,duration,progress,Double(volume)]}}
final class Controller {let sidebarUI=Sidebar();var isTorrentStopped=false;var frames=0
 func applyVideoFrame(bounds:Int){CATransaction.begin();defer{CATransaction.commit()};frames+=1}
 func currentProgress()->Double{0.25}
 func apply(){let bounds=1,currentTime=10.0,duration=40.0,volume:Float=0.75
'''
post='''
 }
}
let c=Controller();c.apply();precondition(CATransaction.depth==0 && CATransaction.commits==1 && c.frames==1 && c.sidebarUI.values==[10,40,0.25,0.75])
c.isTorrentStopped=true;c.apply();precondition(CATransaction.depth==0 && CATransaction.commits==2 && c.frames==2 && c.sidebarUI.values==[0,0,0,0.75])
print("PASS exact poll UI block: three nested UI writes, one outer commit per poll, stopped/live values unchanged; native pixels/performance NOT_RUN")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(pre+body+post)
 subprocess.run([shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc',str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
