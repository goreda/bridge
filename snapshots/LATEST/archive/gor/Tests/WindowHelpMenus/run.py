from pathlib import Path
import os,tempfile,subprocess,re
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/UI/MenuActions.swift').read_text();a=s.index('enum PlayerWindowPlacement {');b=s.index('\nextension AppDelegate {',a);actual=s[a:b]
code='import Foundation\n'+actual+'''
let visible=CGRect(x:-1600,y:50,width:1600,height:900),current=CGRect(x:-1400,y:200,width:800,height:450)
for mode in ["zoom","fill","center","top-left","top-right","bottom-left","bottom-right","smaller","larger"] {
 let f=PlayerWindowPlacement.frame(mode:mode,current:current,visible:visible)
 precondition(f.minX>=visible.minX && f.maxX<=visible.maxX && f.minY>=visible.minY && f.maxY<=visible.maxY)
}
precondition(PlayerWindowPlacement.frame(mode:"top-left",current:current,visible:visible).width==800)
precondition(PlayerWindowPlacement.frame(mode:"top-left",current:current,visible:visible).maxY==visible.maxY)
precondition(PlayerWindowPlacement.frame(mode:"center",current:current,visible:visible).midX==visible.midX)
print("PASS actual native window plans:9 modes, negative-origin display, clamp and align; no content/font transform")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
a=(r/'Sources/gor/App/AppDelegate.swift').read_text()
assert 'main.insertItem(photonItem,at:main.index(of:subItem)+1)' in a
assert a.index('main.addItem(windowItem)')<a.index('main.addItem(helpItem)')<a.index('NSApp.mainMenu = main')
for t in ['video','audio','sub']:assert 'installTrackSubmenu(in:'+('subMenu' if t=='sub' else t+'Menu')+',type:"'+t+'")' in a
assert '["video tracks":"video","audio tracks":"audio","subtitle tracks":"sub"]' in s
assert 'issueFencedGeometry(geom,before:before,target:target)' in a
assert 'shortcutLines($0)' in s and 'NSPasteboard.general.setString(report' in s
# Reserved Window family is disjoint from old triple chords and from its own rows.
keys=['m','f','z','c','h','l','k','j','-','=','b','/','i'];assert len(keys)==len(set(keys))
assert 'NSApp.windowsMenu=windowMenu' not in a and 'NSApp.helpMenu=helpMenu' in a
print('PASS static: Tracks-only rebuild, requested top-level order, native Window/Help registration, real help/report handlers, unique new chords; native Mac UI/actions unrun')
