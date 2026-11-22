#!/usr/bin/env python3
"""Compile actual production key-routing bodies with event-value shims, not Mac delivery."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import os,tempfile,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController_Features.swift')).read_text()
body=s[s.index('    private func gorMotionVectorCore('):s.index('    private func gorMotionMatches(')].replace('private func','func')
shim='''import Foundation
struct Flags:OptionSet {let rawValue:Int;static let command=Flags(rawValue:1),shift=Flags(rawValue:2),option=Flags(rawValue:4),control=Flags(rawValue:8),function=Flags(rawValue:16)}
struct NSEvent {typealias ModifierFlags=Flags;let modifierFlags:Flags;let keyCode:UInt16;let charactersIgnoringModifiers:String?}
struct CGEventSource {enum State {case combinedSessionState};static func flagsState(_ s:State)->Flags{.function}}
extension Flags {static let maskSecondaryFn=Flags.function}
class Probe {
'''
main='''}
let p=Probe()
for code:UInt16 in [43,47] {
 let e=NSEvent(modifierFlags:[.shift,.function],keyCode:code,charactersIgnoringModifiers:nil)
 let v=p.gorMotionVectorCore(e)!
 precondition(v.0==0 && v.1==0 && v.2==(code==43 ? 1:-1))
 print("PASS production fn+shift zoom physical keycode",code,"direction",v.2)
}
for (key,direction) in [("=","1"),("-","-1")] {
 let e=NSEvent(modifierFlags:[],keyCode:0,charactersIgnoringModifiers:key)
 let message=p.gorMotionStep(e)!
 let obj=try! JSONSerialization.jsonObject(with:Data(message.utf8)) as! [String:[String]]
 precondition(obj["command"] == ["script-message-to","gor_fit","zoom",direction])
 print("PASS production single-step zoom",key,direction)
}
precondition(p.gorMotionVectorCore(NSEvent(modifierFlags:[.command,.shift,.function],keyCode:43,charactersIgnoringModifiers:nil)) == nil)
print("PASS unrelated command modifier rejected; native Mac event arrival NOT_RUN")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(shim+body+main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'probe')],check=True)
 subprocess.run([str(p/'probe')],check=True)
