import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,os
r=Path(__file__).resolve().parents[2];s=(_pp_split().path(r,'PPController_Features.swift')).read_text()
a=s.index('            if e.modifierFlags.intersection([.command, .option, .control, .shift])')
b=s.index('            if let message = self.grainSizeTrimMessage',a)
body=s[a:b]
program='''import Foundation
struct Flags:OptionSet {let rawValue:Int;static let command=Flags(rawValue:1),option=Flags(rawValue:2),control=Flags(rawValue:4),shift=Flags(rawValue:8),capsLock=Flags(rawValue:16)}
struct Event {let modifierFlags:Flags;let keyCode:UInt16}
final class Probe {var commands:[String]=[];func ipcCommand(_ s:String){commands.append(s)}
func route(_ e:Event)->Event? {
'''+body+'''return e
}}
let p=Probe()
precondition(p.route(Event(modifierFlags:[.command,.option],keyCode:8))==nil && p.commands.count==1)
precondition(p.route(Event(modifierFlags:[.command,.option,.capsLock],keyCode:8))==nil && p.commands.count==2)
for key:UInt16 in [1,46,9,8,5,6,7,31,3] {
 precondition(p.route(Event(modifierFlags:[.command,.control,.option],keyCode:key)) != nil)
}
precondition(p.commands.count==2)
print("PASS actual clip routing: Cmd+Opt+C unchanged; CapsLock irrelevant; Cmd+Ctrl+Opt+S/M/V and all six old clip keys pass through")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True)
