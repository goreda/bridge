def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,json,math,os
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
rows=[]
for w,h in [(320,180),(640,360),(960,540),(1280,720),(1920,1080),(600,800)]:
 for mode in ['2D','SBS','TB','anaglyph']:
  r=ns['Replay'](flat=True);r.g.props['osd-width']=w;r.g.props['osd-height']=h
  if mode=='2D':r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-tools-active','true')
  else:r.msg('vr180-look-set-pack',{'SBS':3,'TB':1,'anaglyph':2}[mode],0,.5,1,0)
  r.msg('vr180-look-full-fit');r.pose(roll=0,fov=135)
  frame=dict(r.g.props['user-data/vr180-look/film-frame'])
  rows.append((mode,w,h,frame['frameW']*w,frame['frameH']*h))
# Same measured font dimensions as the committed owner's mockup fixture. These
# are fixture inputs, not a claim about the owner's current variable-font state.
font=(root/'Sources/gor/UI/PhotonFont.swift').read_text()
a=font.index('    static let chromeSmallRailUplift: CGFloat');b=font.index('\n    static func setChromeLayoutScale',a)
helper=font[a:b]
program='import Foundation\nenum FontProbe {static let chromeDesignCanvasSize = CGSize(width:960,height:540)\n'+helper+'\n}\nvar failures=0\n'

program+='let rows:[(String,Double,Double,Double,Double)]=['+','.join('('+json.dumps(m)+','+','.join(map(str,[w,h,fw,fh]))+')' for m,w,h,fw,fh in rows)+']\n'
program+='''
for (mode,w,h,fw,fh) in rows {
 let scale=Double(FontProbe.chromeLayoutScale(for:CGRect(x:0,y:0,width:fw,height:fh)))
 let layout=CornerTuneLayout(charW:17.4*scale,lineH:32.3*scale,pad:16*scale)
 let full=CornerTuneRect(x:0,y:0,w:fw,h:fh)
 let sw=(16.0*2+17.4)*scale,sidew=(34.8+16*2)*scale
 let content=CornerTuneLayout.clearContent(full,chrome:[CornerTuneRect(x:0,y:0,w:sw,h:fh),CornerTuneRect(x:fw-sidew,y:0,w:sidew,h:fh)],pad:16*scale)
 let controls=layout.controls(in:content,subtitleBand:nil,values:[:])
 var outside=0,overlaps=0
 for c in controls {for f in c.frames {if f.x < 0 || f.y < 0 || f.maxX > fw || f.maxY > fh {outside+=1}}}
 for i in 0..<controls.count {for j in (i+1)..<controls.count {for a in controls[i].frames {for b in controls[j].frames {if a.intersects(b){overlaps+=1}}}}}
 if outside>0 || overlaps>0 {failures+=1}
 // Panel clearances and frame bounds must use the same local font scale.
 let padL=40*scale,padR=(40+34.8-17.4)*scale,top=9*scale
 if fw-padL-padR <= 0 || fh-2*top <= 0 || abs((padL-sw)-(padR-sidew))>1e-8 {failures+=1}
 for c in controls {for f in c.frames {
  let row:[String:Any]=["mode":mode,"w":w,"h":h,"fw":fw,"fh":fh,"scale":scale,"rect":[f.x,f.y,f.w,f.h]]
  let data=try! JSONSerialization.data(withJSONObject:row,options:.sortedKeys);print(String(data:data,encoding:.utf8)!)
 }}
 print("\\(mode) \\(Int(w))x\\(Int(h)) rail=\\(fw)x\\(fh) outside=\\(outside) cross-control-overlaps=\\(overlaps)")
}
precondition(failures==0,"windowed chrome outside/overlap/panel clearance")
print("PASS24 compiled windowed rail cases, actual PhotonFont helper + CornerTuneLayout,0outside/0overlap")
'''
with tempfile.TemporaryDirectory() as t:
 p=Path(t);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sec_file(root,'ThreeDCornerTuneLayout.swift')),str(p/'main.swift'),'-o',str(p/'probe')],check=True)
 output=subprocess.check_output([str(p/'probe')],text=True)
 print(output)
 Path('/tmp/windowed-chrome194m-layout.json').write_text(json.dumps([json.loads(x) for x in output.splitlines() if x.startswith('{')]))
