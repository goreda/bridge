from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/UI/MenuActions.swift').read_text();a=s.index('enum PlayerWindowPlacement {');b=s.index('\nextension AppDelegate {',a)
code='import Foundation\n'+s[a:b]+'''
let screen=CGRect(x:-1920,y:-200,width:1920,height:1080),visible=CGRect(x:-1920,y:-150,width:1920,height:1000)
let hidden=PlayerWindowPlacement.usableFrame(screen:screen,visible:visible,menuAutoHides:true)
precondition(hidden.maxY==screen.maxY && hidden.minY==visible.minY)
precondition(PlayerWindowPlacement.usableFrame(screen:screen,visible:visible,menuAutoHides:false)==visible)
for bounds in [visible,hidden] {
 for size in [CGSize(width:800,height:450),CGSize(width:4000,height:2250)] {
  let current=CGRect(origin:CGPoint(x:-1500,y:20),size:size)
  for mode in ["top-left","top-right","bottom-left","bottom-right","center"] {
   let result=PlayerWindowPlacement.frame(mode:mode,current:current,visible:bounds)
   precondition(abs(result.width/result.height-current.width/current.height)<0.000001)
   if size.width<=bounds.width {precondition(result.size==size)}
   if mode.contains("left"){precondition(abs(result.minX-bounds.minX)<0.000001)}
   if mode.contains("right"){precondition(abs(result.maxX-bounds.maxX)<0.000001)}
   if mode.contains("top"){precondition(abs(result.maxY-bounds.maxY)<0.000001)}
   if mode.contains("bottom"){precondition(abs(result.minY-bounds.minY)<0.000001)}
   if mode=="center" {precondition(abs(result.midX-bounds.midX)<0.000001 && abs(result.midY-bounds.midY)<0.000001)}
  }
 }
}
print("PASS actual corner plans: size/aspect preserved, oversize uniform fit, flush edges/center, negative origins, menu auto-hide true screen top, Dock exclusion retained")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
a=(r/'Sources/gor/App/AppDelegate.swift').read_text();assert '_HIHideMenuBar' not in a and 'menuAutoHides:false' in a
for label in ['left half','right half','top half','bottom half']:assert '"'+label+'"' not in a
print('PASS static: native menu corner labels/chords replace halves, private auto-hide read removed (menuAutoHides:false); native macOS placement unverified')
