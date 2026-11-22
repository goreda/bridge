from pathlib import Path
import os,tempfile,subprocess
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/App/AppDelegate.swift').read_text();a=s.index('    func setCropDetectMenuStatus(');b=s.index('\n    func validateMenuItem',a);actual=s[a:b]
code='''import Foundation
final class MenuItem {var title="";var toolTip:String?}
final class Owner {var cropDetectMenuItem:MenuItem?=MenuItem()
'''+actual+'''
}
let o=Owner()
for status:String? in [nil,"searching for usable frames in a very long dark scene","complete"] {
 o.setCropDetectMenuStatus(status)
 precondition(o.cropDetectMenuItem!.title=="detect")
 precondition(o.cropDetectMenuItem!.title.split(separator:" ").count==1)
 precondition(o.cropDetectMenuItem!.toolTip==status)
}
print("PASS actual status setter:1-word title (detect, inside the crop submenu) fixed for nil/long/complete states, detail preserved in tooltip")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
assert 'item("detect",' in s
