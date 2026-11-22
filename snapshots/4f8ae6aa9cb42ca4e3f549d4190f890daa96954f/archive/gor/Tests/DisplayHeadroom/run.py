from pathlib import Path
import importlib.util
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
_spec=importlib.util.spec_from_file_location('display_headroom_sections',r/'Tests/Structure/section_source.py')
_sections=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_sections)
s=_sections.section_text_exact(r,'Diag.swift')
method=_sections.func_text(r,'static func line(reason:',within='Diag.swift')
code='import Foundation\nenum Probe {\n'+method+'\n}\nprecondition(Probe.line(reason:"launch",index:1,potential:4,current:1.25)=="display-edr reason=launch screen=1 potential=4.000 current=1.250")\nprint("PASS exact production EDR formatting; launch + screen notifications wired, native screen sampling unverified")'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'run')],check=True);subprocess.run([str(p/'run')],check=True)
assert 'NSApplication.didChangeScreenParametersNotification' in s and 'NSWindow.didChangeScreenNotification' in s
assert 'DisplayHeadroomDiag.start()' in _sections.section_text_exact(r,'AppDelegate.swift')
