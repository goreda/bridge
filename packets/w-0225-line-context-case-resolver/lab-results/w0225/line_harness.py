"""OFL synthetic one-line geometry harness, no recognizer or case inference.
Development stage restricted to5 calibration, one validation pass after freeze,
and a single descriptive29-font test pass after final code freeze.
"""
import argparse,pathlib,json,hashlib,collections,statistics,importlib.util,sys
import numpy as np
from PIL import Image,ImageFont,ImageDraw
import case_resolver as resolver
R=pathlib.Path(__file__).parent
SCENARIOS={
 'mixed_scale_pairs':'cCoOsSuUvVwWxXzZ',
 'mixed_ascenders':'aAbBdDhHlLkKtT',
 'all_lower_xonly':'acosuvwxzacosuvwxz',
 'all_upper':'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
 'single':'o',
 'two':'oO',
 'descender_heavy':'pgqyjPgQyJpgqyj',
 'rotated':'cCoOsSuUvVwWxXzZ',
 'uneven_baseline':'cCoOsSuUvVwWxXzZ',
 'mixed_all62':'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789',
}
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def write(p,x):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,indent=2,allow_nan=False)+'\n')
def fonts(assets,stage):
 b=json.loads((assets/'font-manifest.json').read_text())['fonts']
 if stage=='test':b+=json.loads((assets/'extension-stage1b.json').read_text())['fonts']
 return [f for f in b if f['cohort']==stage and f['slug']!='sairaextracondensed']

def generate(assets,f,scenario,size,em,out):
 folder=assets/('font-cache' if (assets/'font-cache'/f['slug']).exists() else 'extension-cache')/f['slug'];fontpath=folder/f['file_name'];assert sha(fontpath)==f['sha256']
 font=ImageFont.truetype(str(fontpath),em);text=SCENARIOS[scenario];glyphs=[];x=size//8;base=em+size//4;tops=[]
 for j,c in enumerate(text):
  bb=font.getbbox(c,anchor='ls');w,h=bb[2]-bb[0],bb[3]-bb[1];tile=Image.new('L',(w+8,h+8),255);ImageDraw.Draw(tile).text((4-bb[0],4-bb[1]),c,font=font,anchor='ls',fill=0)
  a=np.asarray(tile);yy,xx=np.where(a<128);box=(int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1);crop=tile.crop(box);offset=round(j*em*.025) if scenario=='rotated' else (round((j%3-1)*em*.1) if scenario=='uneven_baseline' else 0)
  # y position corresponds to glyph's page baseline before tight crop.
  y=base+bb[1]-4+box[1]+offset
  if scenario=='rotated':
   crop=crop.rotate(-5,resample=Image.Resampling.BICUBIC,expand=True,fillcolor=255)
   rotated_ink=crop.point(lambda v:255 if v<128 else 0).getbbox();crop=crop.crop(rotated_ink)
  region=dict(x0=x,y0=y,x1=x+crop.width,y1=y+crop.height,ink_h=crop.height)
  glyphs.append((c,crop,region));x+=max(crop.width,round(em*.25))+round(em*.15);tops.append(y)
 height=max(size,max(r['y1'] for c,im,r in glyphs)+size//8);frame=Image.new('L',(x+size//8,height),255)
 for c,im,r in glyphs:frame.paste(im,(r['x0'],r['y0']))
 regs=[r for c,im,r in glyphs];line=dict(baseline_y=base,top_y=min(tops));hints=resolver.resolve_line_case(regs,line)
 path=out/'lines'/f['slug']/str(size)/(scenario+'.png');path.parent.mkdir(parents=True,exist_ok=True);frame.save(path)
 rows=[]
 for j,((c,im,r),hint) in enumerate(zip(glyphs,hints)):
  # Render-case labels are external descriptive associations only.
  expected='upper_like' if 'A'<=c<='Z' else 'lower_like' if 'a'<=c<='z' else None
  rows.append(dict(family=f['family'],font_sha256=f['sha256'],cohort=f['cohort'],scenario=scenario,frame_size=size,em_size=em,glyph_index=j,render_char=c,known_render_case=expected,region=r,hint=hint,line_path=str(path.relative_to(out)),line_sha256=sha(path)))
 return rows

def metrics(rows):
 n=len(rows);h=[r for r in rows if r['hint']['label']!='unresolved'];alpha=[r for r in h if r['known_render_case'] is not None];match=sum(r['hint']['label']==r['known_render_case'] for r in alpha)
 return dict(regions=n,hinted=len(h),unresolved=n-len(h),geometric_coverage={'numerator':len(h),'denominator':n,'value':len(h)/n if n else None},abstention={'numerator':n-len(h),'denominator':n,'value':(n-len(h))/n if n else None},descriptive_render_case_association={'numerator':match,'denominator':len(alpha),'value':match/len(alpha) if alpha else None,'scope':'only hinted alphabetic render labels, not case classification/recognition correctness'},reasons=dict(collections.Counter(r['hint']['reason'] for r in rows)))

def cluster_ci(rows,seed=2252026,B=3000):
 families=sorted(set(r['family'] for r in rows));stats=[]
 for f in families:
  m=metrics([r for r in rows if r['family']==f]);stats.append([m['hinted'],m['regions'],m['descriptive_render_case_association']['numerator'],m['descriptive_render_case_association']['denominator']])
 a=np.array(stats);rng=np.random.default_rng(seed);s=a[rng.integers(0,len(a),(B,len(a)))].sum(axis=1);result={}
 for name,num,den in [('geometric_coverage',0,1),('descriptive_render_case_association',2,3)]:
  ok=s[:,den]>0;v=s[ok,num]/s[ok,den];result[name]=dict(percentile95=np.quantile(v,[.025,.975]).tolist() if len(v) else None,valid_replicates=int(ok.sum()))
 return dict(method='Whole-family percentile bootstrap, all sizes/scenarios within family resampled together; descriptive only, not independent glyph intervals.',families=len(families),seed=seed,replicates=B,intervals=result)

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--assets',type=pathlib.Path,required=True);ap.add_argument('--stage',choices=['calibration','validation','test'],required=True);ap.add_argument('--out',type=pathlib.Path,required=True);ap.add_argument('--freeze');args=ap.parse_args()
 if args.stage!='calibration':
  if not args.freeze:raise ValueError('FreezeReceiptRequired')
  receipt=json.loads(pathlib.Path(args.freeze).read_text());assert receipt['module_sha256']==sha(R/'case_resolver.py');assert receipt['harness_sha256']==sha(__file__)
 if args.out.exists():raise ValueError('StageAlreadyRunOutputExists')
 fs=fonts(args.assets,args.stage);assert len(fs)==(29 if args.stage=='test' else 5);rows=[]
 for f in fs:
  for size,em in [(256,170),(384,256),(512,341)]:
   for scenario in SCENARIOS:rows.extend(generate(args.assets,f,scenario,size,em,args.out))
 result=dict(stage=args.stage,module_sha256=sha(R/'case_resolver.py'),harness_sha256=sha(__file__),scope='GEOMETRIC GROUPING ONLY, never case/Unicode identity',overall=metrics(rows),per_family={f['family']:metrics([r for r in rows if r['family']==f['family']]) for f in fs},per_scenario={s:metrics([r for r in rows if r['scenario']==s]) for s in SCENARIOS},per_family_scenario={f['family']:{s:metrics([r for r in rows if r['family']==f['family'] and r['scenario']==s]) for s in SCENARIOS} for f in fs},family_clustered_intervals=cluster_ci(rows))
 write(args.out/'rows.json',rows);write(args.out/'results.json',result);write(args.out/'OUTPUT-SHA256.json',{str(p.relative_to(args.out)):sha(p) for p in sorted(args.out.rglob('*')) if p.is_file() and p.name!='OUTPUT-SHA256.json'});print(json.dumps(result['overall']))
if __name__=='__main__':main()
