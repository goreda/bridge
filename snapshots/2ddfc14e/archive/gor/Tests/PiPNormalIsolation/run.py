
# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
from pathlib import Path
import subprocess,os,tempfile,json,sys,traceback
def _fixture_excepthook(t,v,tb):
 print('FIXTURE-FAILURE-TRACEBACK:',flush=True);traceback.print_exception(t,v,tb);traceback.print_exception(t,v,tb,file=sys.stdout)
 sys.exit(1)
sys.excepthook=_fixture_excepthook
def swiftc_checked(args,out):
 r=subprocess.run([os.environ.get('SWIFTC','swiftc'),*args,'-o',str(out)],capture_output=True,text=True)
 if r.returncode:
  print('FIXTURE-COMPILE-FAIL rc=%d:'%r.returncode,' '.join(map(str,args)),flush=True)
  print('--- swiftc stdout ---\n'+r.stdout+'--- swiftc stderr ---\n'+r.stderr,flush=True)
  r.check_returncode()
r=Path(__file__).resolve().parents[2];repo=r.parents[1];current=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
baseline=subprocess.check_output(['git','show','b7318c798cb3c97c55e9218badb5be50c4615dd3:archive/gor/Sources/gor/GorSubtitlesUI/SubtitleView.swift'],cwd=repo,text=True)
def method(s,key):
 i=s.index(key);j=s.index('{',i)+1;n=1
 while n:n+=(s[j]=='{')-(s[j]=='}');j+=1
 return s[i:j].replace('private func','func')
# The mode flag and setters cannot differ at all from the accepted baseline.
# SUPERSESSION 196w (2026-11-15, owner authorization relayed by main 20:27 +03):
# applySVFont intentionally diverges from b7318c79 - a 0.25pt-quantized skip
# replaces the exact-equality write guard (plus PiP skip-state invalidation) to
# stop the per-film-frame CATextLayer re-typeset pump (owner 20:17 session,
# gor.main ~50%+ on re-typeset). Behavioral parity for real writes is still
# proven below by the compiled baseline-vs-current output comparison.
for key in ['    func setSubtitleFontScale(','    private func resolvedFont(']:assert method(current,key)==method(baseline,key),key
base=_sub_read(r/'Tests/PiPSubtitleTypography/run.py');scope={'__file__':str(r/'Tests/PiPSubtitleTypography/run.py')};exec(base[:base.index('with tempfile.TemporaryDirectory()')],scope)
prefix=scope['program'].split('let view=ViewBoundary()')[0]
# Methods compiled from both revisions, not mirrored arithmetic in the test.
original=prefix
for key in ['    private func applySVFont(','    private func applyVariationDuringFade(']:original=original.replace(method(current,key),method(baseline,key))
rows='''
for width in [240.0,480,960,1712,2560] {for scale in [0.5,0.65,1,1.5,2.0] {for user in [1.0,2,2.5] {for distance in [0.0,300,1000,1500] {
 let v=ViewBoundary();v.userScale=user;v.subtitleFontScale=scale
 let point=SubtitlePresentation.fontSize(userScale:user,proximity:SubtitlePresentation.proximity(distance:distance))
 v.applySVFont(CTFont(point,[0:0.4,1:distance]),fontSize:point)
 let normalWidth=WIDTH
 let text=TEXT
 print("\\(width)|\\(scale)|\\(user)|\\(distance)|\\(v.textLayer.fontSize)|\\(v.textLayer.font!.size)|\\(normalWidth)|\\(text)")
}}}}
'''
programs=[original+rows.replace('WIDTH','(width/2)*user').replace('TEXT','"one two\\nthree four"'),prefix+rows.replace('WIDTH','SubtitleWrapping.width(windowWidth:width,fontSize:point,pictureInPicture:false,normalWidth:(width/2)*user)').replace('TEXT','SubtitleWrapping.text("one two\\nthree four",pictureInPicture:false)')]
with tempfile.TemporaryDirectory() as d:
 results=[]
 for i,program in enumerate(programs):
  p=Path(d)/str(i);p.mkdir();(p/'main.swift').write_text(program)
  swiftc_checked([str(p/'main.swift')],p/'run')
  results.append(subprocess.check_output([str(p/'run')]))
 assert results[0]==results[1],'non-PiP production output differs'
 print('PASS600 same-input normal output rows byte-identical to accepted b7318c79: point-size/font-copy/scale/width/text; font writer and mode setter source identical')
print('Linux production-output boundary only; no native CoreText pixels or current owner state established')
