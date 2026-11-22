
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
import json,os,subprocess,tempfile
from PIL import Image,ImageFont,ImageDraw
r=Path(__file__).resolve().parents[2];s=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift');actual=s[s.index('enum SubtitlePresentation {'):]
out=Path(os.environ.get('OUTPUT_DIR','/downloads'));out.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as t:
 t=Path(t);(t/'main.swift').write_text('import Foundation\n'+actual+'''
var rows:[[String:Any]]=[]
for pip in [false,true] {for scale in [0.5,1.0,1.5] {
 let size=SubtitlePresentation.fontSize(userScale:1,proximity:0.5,pictureInPicture:pip,windowHeight:270)*scale
 rows.append(["mode":pip ? "pip":"normal","scale":scale,"size":size])
}}
print(String(data:try! JSONSerialization.data(withJSONObject:rows),encoding:.utf8)!)
''');subprocess.run([os.environ.get('SWIFTC','swiftc'),str(t/'main.swift'),'-o',str(t/'run')],check=True)
 rows=json.loads(subprocess.check_output([str(t/'run')]))
 canvas=Image.new('RGB',(880,510),'#181818');draw=ImageDraw.Draw(canvas);heights={}
 for i,row in enumerate(rows):
  # Oversample8x so the ±1px raster quantization cannot dominate half-size cap heights.
  font=ImageFont.truetype(str(r/'Resources/fonts/sixa/Exposure-VAR.ttf'),round(row['size']*8))
  ink=Image.new('L',(1600,600));d=ImageDraw.Draw(ink);d.text((20,20),'H',font=font,fill=255)
  box=ink.getbbox();height=box[3]-box[1];heights[row['mode'],row['scale']]=height
  textfont=ImageFont.truetype(str(r/'Resources/fonts/sixa/Exposure-VAR.ttf'),round(row['size']))
  y=25+i*80;draw.text((24,y),f"{row['mode']} scale {row['scale']}: {row['size']:.2f}pt",fill='white')
  draw.text((410,y-6),'HHH Subtitle',font=textfont,fill='white')
 for mode in ['normal','pip']:
  base=heights[mode,1.0]
  for scale in [.5,1,1.5]:
   ratio=heights[mode,scale]/base
   assert abs(ratio-scale)/scale<=.05,(mode,scale,ratio)
   print(f'PASS real Exposure font FreeType cap height {mode} sub-scale={scale}:ratio={ratio:.4f}, within5%')
 canvas.save(out/'gor-subtitle-scale-pixels.png')
 print('Linux FreeType pixels from production point-size policy, not native AppKit/CoreText bitmap acceptance')
