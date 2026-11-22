
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
import json,os,subprocess,tempfile,re,sys,traceback
from PIL import Image,ImageDraw,ImageFont
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
r=Path(__file__).resolve().parents[2];s=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift');actual=s[s.index('enum SubtitleWrapping {'):]
spine=_sub_read(r/'Sources/gor/UI/SpineUI.swift');sidebar=_sub_read(r/'Sources/gor/UI/SidebarUI.swift')
# Compile exact production block-width accessors with metric-boundary values.
# chrome* mirrors production PhotonFont at chromeScale=1 (chromeX = X * chromeScale).
access='enum PhotonFont {static var pad:CGFloat=12;static var charW:CGFloat=14;static var gap:CGFloat=6;static var twoDigitW:CGFloat=28;static var chromePad:CGFloat{pad};static var chromeCharW:CGFloat{charW};static var chromeGap:CGFloat{gap};static var chromeTwoDigitW:CGFloat{twoDigitW}}\n'
access+='struct Spine {var PAD:CGFloat{PhotonFont.pad};var BTN_W:CGFloat{PhotonFont.charW+PhotonFont.gap};'+re.search(r'var spineWidth: CGFloat \{[^}]+\}',spine).group(0)+'}\n'
access+='struct Sidebar {'+re.search(r'var sidebarWidth: CGFloat \{[^}]+\}',sidebar).group(0)+'}\n'
actual=access+actual
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text('import Foundation\n#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\n'+actual+'''
precondition(SubtitleWrapping.text("one two\\nthree four",pictureInPicture:true)=="one two three four")
precondition(SubtitleWrapping.text("- one\\n- two",pictureInPicture:true)=="- one\\n- two")
precondition(SubtitleWrapping.text("one\\n\\ntwo",pictureInPicture:true)=="one\\n\\ntwo")
precondition(SubtitleWrapping.text("one\\ntwo",pictureInPicture:false)=="one\\ntwo")
// Actual production UI block width formulas (measured font values passed by harness).
for width in [160.0,240,480,720] {for font in [10.8,21.6,32.4] {
 let spine=CGRect(x:0,y:0,width:Spine().spineWidth,height:270)
 let sidebar=CGRect(x:width-Sidebar().sidebarWidth,y:0,width:Sidebar().sidebarWidth,height:270)
 let area=SubtitleWrapping.usableArea(windowWidth:width,fontSize:font,left:spine,right:sidebar,gap:Double(PhotonFont.pad*2))
 precondition(area.minX>=spine.maxX+PhotonFont.pad*2)
 precondition(area.maxX<=sidebar.minX-PhotonFont.pad*2)
 let shifted=SubtitleWrapping.usableArea(windowWidth:width,fontSize:font,left:spine.offsetBy(dx:20,dy:0),right:sidebar.offsetBy(dx:-20,dy:0),gap:Double(PhotonFont.pad*2))
 precondition(shifted.width<=area.width)
 precondition(area.intersection(spine).isNull && area.intersection(sidebar).isNull,"overlap must be zero")
}}
var rows:[[String:Double]]=[]
for w in [240.0,360,480,720] {for f in [10.8,21.6,32.4] {
 let width=Double(SubtitleWrapping.usableArea(windowWidth:w,fontSize:f,left:CGRect(x:0,y:0,width:Spine().spineWidth,height:270),right:CGRect(x:w-Sidebar().sidebarWidth,y:0,width:Sidebar().sidebarWidth,height:270),gap:Double(PhotonFont.pad*2)).width)
 precondition(width>0 && width<w)
 precondition(SubtitleWrapping.width(windowWidth:w,fontSize:f,pictureInPicture:false,normalWidth:123)==123)
 rows.append(["window":w,"font":f,"width":width])
}}
print(String(data:try! JSONSerialization.data(withJSONObject:rows),encoding:.utf8)!)
''');swiftc_checked([str(p/'main.swift')],p/'run');rows=json.loads(subprocess.check_output([str(p/'run')]))
canvas=Image.new('RGB',(800,820),'#181818');draw=ImageDraw.Draw(canvas)
text='When the subtitle font gets smaller more words should fit on each line of this picture in picture window'
counts={}
for row in rows:
 font=ImageFont.truetype(str(r/'Resources/fonts/sixa/Exposure-VAR.ttf'),round(row['font']*8))
 lines=[];line=''
 for word in text.split():
  candidate=(line+' '+word).strip()
  if line and font.getlength(candidate)>row['width']*8:lines.append(line);line=word
  else:line=candidate
 if line:lines.append(line)
 counts[row['window'],row['font']]=len(lines[0].split())
 if row['window']==480:
  i=[10.8,21.6,32.4].index(row['font']);y=20+i*245
  draw.text((20,y),f"PiP480px font {row['font']:.1f}pt wrap {row['width']:.1f}px first row {len(lines[0].split())} words",fill='white')
  f=ImageFont.truetype(str(r/'Resources/fonts/sixa/Exposure-VAR.ttf'),round(row['font']))
  for j,line in enumerate(lines):draw.text((20,y+25+j*round(row['font']*1.4)),line,font=f,fill='white')
for w in [240.0,360,480,720]:
 assert counts[w,10.8]>counts[w,21.6]>=counts[w,32.4],(w,counts)
 print('PASS real Exposure advances: PiP width',w,'first-line words small/default/large',[counts[w,f] for f in [10.8,21.6,32.4]])
out=os.environ.get('GOR_PIP_WRAP_PIXELS') or str(Path(tempfile.gettempdir())/'gor-pip-wrap-pixels.png')
canvas.save(out);print('pixels saved:',out)
assert s.count('let targetW = wrappingWidth(font:font)')==2 and 'let subW = wrappingWidth(font:font)' in s
assert 'SubtitleWrapping.text(text,pictureInPicture:pictureInPictureTypography)' in s
assert 'vrSubtitleSafeMask.frame=CGRect(x:area.minX' in s
assert 'pipBlockGap:CGFloat {PhotonFont.pad * 2}' in s
assert 'convert($0.bounds,from:$0)' in s and '$0 is SpineUI' in s and '$0 is SidebarUI' in s
print('PASS exact production spineWidth/sidebarWidth accessors with live-coordinate converted frames exclude both blocks plus existing PhotonFont.pad*2 gap; normal width untouched')
print('PASS actual Swift width/text policy, preserves normal and dialogue/paragraph boundaries; painting/measurement/face-placement share width; Linux FreeType, native CoreText unverified')
