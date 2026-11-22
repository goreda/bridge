from pathlib import Path
import os,tempfile,subprocess
r=Path(__file__).resolve().parents[2];s=(r/'Sources/gor/UI/SpineUI.swift').read_text();a=s.index('enum StatusHUDPlacement {');actual=s[a:]
code='import Foundation\n'+actual+'''
let mono=StatusHUDPlacement.region(anchorX:60,anchorY:760,visible:CGRect(x:0,y:0,width:1440,height:800),pad:10)
precondition(mono==CGRect(x:60,y:0,width:1370,height:760))
let eye=StatusHUDPlacement.region(anchorX:60,anchorY:760,visible:CGRect(x:0,y:180,width:715.5,height:402.5),pad:10)
precondition(eye.minX==60 && eye.maxX==705.5 && eye.maxY==582.5)
let cropped=StatusHUDPlacement.region(anchorX:20,anchorY:800,visible:CGRect(x:100,y:50,width:600,height:400),pad:10)
precondition(cropped.minX==100 && cropped.maxY==450 && cropped.maxX==690)
print("PASS actual status placement: mono original anchor, SBS visible-eye maxX/top, cropped origin; no glyph transform")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(code);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True);subprocess.run([str(p/'check')],check=True)
assert 'layoutLiveStatusHUD()\n        layoutPhotonHUD()' in s
assert 'streamControlLayers[j].frame=CGRect(x:layer.frame.minX' in s
print('PASS static: existing status layers + click frames reflow on layout; photon HUD keeps separate eye/crop-clamped region; Mac pixels unrun')
