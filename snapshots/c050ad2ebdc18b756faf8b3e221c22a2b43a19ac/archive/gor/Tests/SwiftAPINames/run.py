from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
# Known Swift-renamed Foundation/AppKit constants must never be made to pass
# Linux tests by declaring a stub with the obsolete spelling.
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
for filename in ['AppDelegate.swift','MenuActions.swift','PPController.swift','SpineUI.swift','SidebarUI.swift']:
 s=(_pp_split().path(r,filename) if filename=='PPController.swift' else r/'Sources/gor'/filename).read_text()
 for obsolete in ['NSGlobalDomain','NSOnState','NSOffState','NSMixedState','NSAlertFirstButtonReturn','NSBorderlessWindowMask']:
  assert obsolete not in s,(filename,obsolete)
a=(r/'Sources/gor/App/AppDelegate.swift').read_text()
assert '_HIHideMenuBar' not in a
code='import Foundation\nlet domain=UserDefaults.globalDomain\n_ = UserDefaults.standard.persistentDomain(forName:domain)\nprint("PASS real Foundation globalDomain API, no stubbed legacy constant")\n'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
print('PASS static renamed-API guard across owned sources; not an AppKit SDK typecheck')
