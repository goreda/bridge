from pathlib import Path
import re,os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];methods=[]
for name in ['SpineUI.swift','SidebarUI.swift','SubtitleView.swift']:
 s=(r/'Sources/gor'/name).read_text()
 for m in re.finditer(r'final class (\w+): NSView \{',s):
  end=s.find('final class ',m.end());b=s[m.end():end if end>=0 else len(s)]
  if 'override func mouseDown' not in b:continue
  method=re.search(r'override func acceptsFirstMouse\(for event:NSEvent\?\)->Bool \{ true \}',b)
  assert method,m[1]
  methods.append('final class '+m[1]+': NSView {'+method[0]+'}')
code='class NSEvent {}\nclass NSView {func acceptsFirstMouse(for event:NSEvent?)->Bool {false}}\n'+'\n'.join(methods)+'\n'
for method in methods:
 name=method.split()[2].split(':')[0];code+='precondition('+name+'().acceptsFirstMouse(for:nil))\n'
code+='print("PASS actual activating-click overrides for every owned interactive custom NSView; no font/layout changes")\n'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
s=(r/'Sources/gor/App/AppDelegate.swift').read_text();assert s.index('NSApp.activate(ignoringOtherApps: true)')<s.index('super.sendEvent(event)')
print('PASS static window activation-before-dispatch retained; native macOS inactive-app click test unrun')
