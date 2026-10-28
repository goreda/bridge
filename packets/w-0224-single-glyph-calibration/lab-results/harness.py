"""W0224 frozen-source intake, plugin scoring and denominator-explicit tables.
No network training or production weights. See README.md before use.
"""
import argparse,collections,dataclasses,hashlib,importlib.util,json,math,pathlib,sys
from PIL import Image,ImageDraw,ImageFont
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parent
for _pin in json.loads((ROOT/'PINS.json').read_text()):
 _bytes=(ROOT/_pin['path']).read_bytes()
 if len(_bytes)!=_pin['bytes'] or hashlib.sha256(_bytes).hexdigest()!=_pin['sha256']:raise ValueError('IntakePinMismatch:'+_pin['path'])
LABELS=json.loads((ROOT/'labels-62.json').read_text())['classes']
assert len(LABELS)==62 and len(set(LABELS))==62

def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def write_json(p,x):
 p=pathlib.Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(x,indent=2,allow_nan=False)+'\n')
def load_preprocess():
 p=ROOT/'source/w6trainer-src/data.py';want=next(r['sha256'] for r in json.loads((ROOT/'PINS.json').read_text()) if r['path']=='source/w6trainer-src/data.py')
 if sha(p)!=want: raise ValueError('PinnedPreprocessMismatch')
 spec=importlib.util.spec_from_file_location('w0224_pinned_data',p);mod=importlib.util.module_from_spec(spec);sys.modules[spec.name]=mod;spec.loader.exec_module(mod)
 decl=mod.PackManifest('packet-declarations',**json.loads((ROOT/'pack-declarations.json').read_text()),families=())
 return mod,decl

def intake(frame):
 """Identity cleaner, then exact <128 ink crop; blank gets typed abstain."""
 gray=frame.convert('L');a=np.asarray(gray);ys,xs=np.where(a<128)
 if len(xs)==0:return None,None
 box=(int(xs.min()),int(ys.min()),int(xs.max())+1,int(ys.max())+1)
 return gray.crop(box),box

@dataclasses.dataclass(frozen=True)
class Prediction:
 char:str
 confidence:float
 reject_score:float|None=None
 rejected:bool=False
 reject_available:bool=False
@dataclasses.dataclass(frozen=True)
class Abstain:
 code:str
 reason:str

def normalize(value):
 if value is None:return None
 if isinstance(value,Abstain):return value
 if hasattr(value,'pack_refused') and value.pack_refused:return Abstain('PackRefused','scorer pack refusal')
 if not hasattr(value,'char') and hasattr(value,'code'):return Abstain(str(value.code),str(getattr(value,'reason','typed abstain')))
 if isinstance(value,Prediction):p=value
 elif hasattr(value,'char'):
  p=Prediction(value.char,float(value.confidence),getattr(value,'reject_score',None),bool(getattr(value,'rejected',False)),hasattr(value,'rejected') and getattr(value,'reject_score',None) is not None)
 elif isinstance(value,(tuple,list)) and len(value) in (2,3):
  # Tuple item 3 is ambiguous in the packet: seg402 emits log probability.
  # Preserve raw tuple externally, never call item 3 a reject-head score.
  p=Prediction(value[0],float(value[1]))
 else:raise ValueError('UnsupportedPredictionType')
 if p.char not in LABELS or not math.isfinite(p.confidence) or not 0<=p.confidence<=1:raise ValueError('InvalidPrediction')
 if p.reject_score is not None and not math.isfinite(p.reject_score):raise ValueError('InvalidRejectScore')
 if p.rejected and not p.reject_available:raise ValueError('RejectedWithoutExplicitRejectHead')
 return p

def rate(num,den):
 """Wilson 95% descriptive interval, not family-cluster inference."""
 if not den:return dict(numerator=num,denominator=den,value=None,wilson95=None)
 p=num/den;z=1.959963984540054;d=1+z*z/den;c=(p+z*z/(2*den))/d;h=z*math.sqrt(p*(1-p)/den+z*z/(4*den*den))/d
 return dict(numerator=num,denominator=den,value=p,wilson95=[max(0,c-h),min(1,c+h)])
def accepted(r):return r['status']=='prediction' and not r['rejected']
def correct(r):return r['truth'] is not None and r.get('predicted')==r['truth']
def bucket(p,edges):return min(len(edges)-2,max(0,next((i for i in range(len(edges)-1) if edges[i]<=p<edges[i+1]),len(edges)-2)))

def fit_calibration(rows,edges):
 if not rows:raise ValueError('CalibrationAbsent')
 if any(r['cohort']!='calibration' for r in rows):raise ValueError('CalibrationLeakage')
 if not any(r['truth'] is not None and accepted(r) for r in rows):raise ValueError('NoCalibrationPredictions')
 bins=[[] for _ in edges[:-1]]
 for r in rows:
  if r['truth'] is not None and accepted(r):bins[bucket(r['confidence'],edges)].append(int(correct(r)))
 return {'edges':edges,'values':[sum(b)/len(b) if b else None for b in bins],'support':[len(b) for b in bins], 'fitted_cohort':'calibration','target':'P(top label correct | accepted glyph prediction, confidence bin)'}
def reliability(rows,edges,calibrator=None):
 # Selective calibration: never silently drop abstains from E2E denominators.
 pos=[r for r in rows if r['truth'] is not None];sc=[r for r in pos if accepted(r)];bins=[[] for _ in edges[:-1]]
 for r in sc:
  p=r['confidence']
  if calibrator:
   v=calibrator['values'][bucket(p,calibrator['edges'])];p=p if v is None else v
  bins[bucket(p,edges)].append((p,int(correct(r))))
 table=[];gap=0;brier=0
 for i,items in enumerate(bins):
  n=len(items);avg=sum(x for x,y in items)/n if n else None;acc=sum(y for x,y in items)/n if n else None
  if n:gap+=n*abs(avg-acc);brier+=sum((p-y)**2 for p,y in items)
  table.append(dict(low=edges[i],high=edges[i+1],right_closed=i==len(bins)-1,count=n,correct=sum(y for p,y in items),accuracy=rate(sum(y for p,y in items),n),mean_confidence=avg))
 return {'scope':'accepted positive glyph top-label predictions only; not multiclass ECE/Brier','buckets':table,'ece':{'numerator_weighted_abs_gap':gap,'denominator':len(sc),'value':gap/len(sc) if sc else None},'top_label_brier':{'numerator_squared_error':brier,'denominator':len(sc),'value':brier/len(sc) if sc else None},'all_positive_inputs':len(pos),'accepted_predictions':len(sc),'unscored_or_unaccepted':len(pos)-len(sc)}

def summary(rows,edges,calibrator):
 pos=[r for r in rows if r['truth'] is not None];neg=[r for r in rows if r['truth'] is None];ap=[r for r in pos if accepted(r)];cp=[r for r in ap if correct(r)]
 classes={}
 for c in LABELS:
  truth=[r for r in pos if r['truth']==c];ta=[r for r in truth if accepted(r)];pred=[r for r in rows if accepted(r) and r.get('predicted')==c];tp=sum(correct(r) for r in pred)
  classes[c]={'support':len(truth),'font_count':len(set(r['family'] for r in truth)),'all_input_recall':rate(tp,len(truth)),'coverage':rate(len(ta),len(truth)),'accepted_precision':rate(tp,len(pred)),'accepted_only_recall':rate(tp,len(ta)),'abstain':sum(r['status']=='abstain' for r in truth),'missing':sum(r['status']=='missing' for r in truth),'rejected':sum(r['status']=='prediction' and r['rejected'] for r in truth),'calibration_raw':reliability([r for r in pos if r.get('predicted')==c],edges),'calibration_fitted':reliability([r for r in pos if r.get('predicted')==c],edges,calibrator)}
 conf=collections.Counter((r['truth'],r.get('predicted')) for r in ap if not correct(r)); head=any(r.get('reject_available',False) for r in rows);wrong=[r for r in ap if not correct(r)];na=[r for r in neg if accepted(r)]
 return {'inputs':len(rows),'positive_inputs':len(pos),'non_glyph_inputs':len(neg),'font_count':len(set(r['family'] for r in rows)),'counts':dict(collections.Counter(r['status'] for r in rows)),'all_input_recall':rate(len(cp),len(pos)),'coverage':rate(len(ap),len(pos)),'accepted_precision':rate(len(cp),len(ap)+len(na)),'all_input_failure_or_nonacceptance':rate(len(pos)-len(cp),len(pos)),'wrong_label_acceptance':rate(len(wrong),len(pos)),'non_glyph_acceptance':rate(len(na),len(neg)),'reject_head_available':head,'reject_head_false_accept':{'non_glyph':rate(len(na),len(neg)),'wrong_identity':rate(len(wrong),len(pos))} if head and all(r.get('reject_available') or r['status']!='prediction' for r in rows) else None,'classes':classes,'confusion_pairs':[{'truth':a,'predicted':b,'count':n} for (a,b),n in sorted(conf.items(),key=lambda t:(-t[1],t[0]))],'calibration_raw':reliability(rows,edges),'calibration_fitted':reliability(rows,edges,calibrator),'interval_caveat':'Wilson95 treats inputs as independent; repeated glyphs/render sizes within font are correlated. These are descriptive, not population-level or family-cluster intervals.'}

def validate_rows(rows,manifest=None,fixture=False,missing_families=None):
 if not rows:raise ValueError('EmptyInputs')
 allowed={'calibration','validation','test'}
 if any(r.get('cohort') not in allowed for r in rows):raise ValueError('UnknownCohort')
 declared_missing=set(missing_families or [])
 if fixture and declared_missing:raise ValueError('FixtureMissingFamiliesNotSupported')
 family_cohorts={};sha_cohorts={};seen_ids=set()
 membership={f['family']:f for f in manifest['fonts']} if manifest else {}
 if manifest:
  if len(membership)!=len(manifest['fonts']):raise ValueError('ManifestDuplicateFamily')
  sha_splits={}
  for f in manifest['fonts']:
   if f['cohort'] not in allowed:raise ValueError('ManifestUnknownCohort')
   if f['sha256'] in sha_splits and sha_splits[f['sha256']]!=f['cohort']:raise ValueError('ManifestBinaryOverlap')
   sha_splits[f['sha256']]=f['cohort']
 if not fixture and not manifest:raise ValueError('ManifestRequired')
 if declared_missing-set(membership):raise ValueError('UnknownMissingFamily')
 if not fixture:
  present={r.get('family') for r in rows}
  if present & declared_missing:raise ValueError('MissingFamilyHasRows')
  if set(membership)-present != declared_missing:raise ValueError('UndeclaredMissingFamily')
 missing_cohorts=[c for c in sorted(allowed) if not any(r['cohort']==c for r in rows)]
 if missing_cohorts and (fixture or not declared_missing):raise ValueError('MissingCohort')
 for c in missing_cohorts:
  expected={f['family'] for f in manifest['fonts'] if f['cohort']==c}
  if not expected or not expected<=declared_missing:raise ValueError('UndeclaredMissingCohort')
 for r in rows:
  co=r['cohort'];family=r.get('family');digest=r.get('font_sha256')
  if not family or not digest:raise ValueError('MissingFontProvenance')
  if family in family_cohorts and family_cohorts[family]!=co:raise ValueError('FamilySplitOverlap')
  if digest in sha_cohorts and sha_cohorts[digest]!=co:raise ValueError('FontShaSplitOverlap')
  family_cohorts[family]=co;sha_cohorts[digest]=co
  if r.get('truth') is not None and r['truth'] not in LABELS:raise ValueError('UnknownTruth')
  if r.get('status') not in ('prediction','missing','abstain'):raise ValueError('UnknownStatus')
  if not fixture:
   f=membership.get(family)
   if f is None or f['cohort']!=co or f['sha256']!=digest:raise ValueError('ManifestAssignmentMismatch')
  else:
   if r.get('fixture_provenance')!='w0224-synthetic-oracle-v1':raise ValueError('FixtureProvenanceMissing')
  if r.get('id') in seen_ids or not r.get('id'):raise ValueError('DuplicateOrMissingRowId')
  seen_ids.add(r['id'])
 calibration_usable=any(r['cohort']=='calibration' and r['truth'] is not None and accepted(r) for r in rows)
 if not calibration_usable and (fixture or not declared_missing):raise ValueError('NoCalibrationPredictions')
 return {'missing_families':sorted(declared_missing),'missing_cohorts':missing_cohorts,'calibration_usable':calibration_usable,'partial':bool(declared_missing),'input_rows':len(rows),'cohort_rows':{c:sum(r['cohort']==c for r in rows) for c in sorted(allowed)},'source':'explicit synthetic fixture' if fixture else 'verified font manifest'}

def evaluate(rows,manifest=None,fixture=False,missing_families=None):
 validation=validate_rows(rows,manifest,fixture,missing_families)
 if not validation['calibration_usable']:
  return {'schema':'w0224-metrics-v1','status':'partial_refusal','reason':'CalibrationAbsentOrUnscored','input_reconciliation':validation,'calibrator':None,'cohorts':{c:{'status':'not_measured','metrics':None} for c in ['validation','test']}}
 edges=[i/10 for i in range(11)] # Prespecified, never tuned on validation/test.
 cal=fit_calibration([r for r in rows if r['cohort']=='calibration'],edges)
 results={'status':'partial' if validation['partial'] else 'complete','missing_families':validation['missing_families'],'input_reconciliation':validation,'schema':'w0224-metrics-v1','bucket_rule':'Fixed deciles prespecified before any held-out outcome; last interval includes 1.0. No identity/reject cutoff fitted or recommended.','calibrator':cal,'cohorts':{}}
 for co in ['validation','test']:
  rs=[r for r in rows if r['cohort']==co]
  if not rs:
   results['cohorts'][co]={'status':'not_measured','missing_families':[f['family'] for f in manifest['fonts'] if f['cohort']==co],'metrics':None}
   continue
  results['cohorts'][co]=summary(rs,edges,cal)
  results['cohorts'][co]['per_font']={f:summary([r for r in rs if r['family']==f],edges,cal) for f in sorted(set(r['family'] for r in rs))}
  results['cohorts'][co]['per_render_size']={str(s):summary([r for r in rs if r['frame_size']==s],edges,cal) for s in sorted(set(r['frame_size'] for r in rs))}
 assert sum(validation['cohort_rows'].values())==len(rows)
 assert sum(results['cohorts'][c].get('inputs',0) for c in ['validation','test'])==len(rows)-validation['cohort_rows']['calibration']
 return results

class FixtureScorer:
 """Deliberate metadata oracle, NOT an image recognizer or accuracy claim.
 100 cases per identity: 70 correct accepted, 10 next-class confusions,
 10 rejected correct, 5 typed abstain, 5 missing. Top confidence always .9.
 """
 def __init__(self,truth,draw,kind='glyph'):self.truth=truth;self.draw=draw;self.kind=kind
 def score(self,image):
  d=self.draw
  if self.kind!='glyph':
   if d%4==0:return Prediction('A',.9,.1,False,True)
   if d%4==1:return Prediction('A',.9,.9,True,True)
   if d%4==2:return Abstain('FixtureAbstain','known non-glyph abstain')
   return None
  if d<70:return Prediction(self.truth,.9,.1,False,True)
  if d<80:return Prediction(LABELS[(LABELS.index(self.truth)+1)%62],.9,.1,False,True)
  if d<90:return Prediction(self.truth,.9,.9,True,True)
  if d<95:return Abstain('FixtureAbstain','known fixture abstain')
  return None

def record(meta,value):
 p=normalize(value);r=dict(meta)
 if p is None:r.update(status='missing')
 elif isinstance(p,Abstain):r.update(status='abstain',abstain_code=p.code,abstain_reason=p.reason)
 else:r.update(status='prediction',predicted=p.char,confidence=p.confidence,rejected=p.rejected,reject_score=p.reject_score,reject_available=p.reject_available)
 return r

def fixture_rows():
 rows=[]
 for co in ['calibration','validation','test']:
  for c in LABELS:
   for d in range(100):
    meta=dict(id=f'{co}:{c}:{d}',fixture_provenance='w0224-synthetic-oracle-v1',font_sha256=hashlib.sha256(('synthetic-'+co).encode()).hexdigest(),cohort=co,family='synthetic-'+co,truth=c,draw=d,kind='glyph',frame_size=384)
    rows.append(record(meta,FixtureScorer(c,d).score(None)))
  for d in range(40):
   meta=dict(id=f'{co}:negative:{d}',fixture_provenance='w0224-synthetic-oracle-v1',font_sha256=hashlib.sha256(('synthetic-'+co).encode()).hexdigest(),cohort=co,family='synthetic-'+co,truth=None,draw=d,kind='non_glyph',frame_size=384)
   rows.append(record(meta,FixtureScorer(None,d,'non_glyph').score(None)))
 return rows

def verify_fixture(out):
 rows=fixture_rows();res=evaluate(rows,fixture=True)
 for co in ['validation','test']:
  s=res['cohorts'][co];assert s['positive_inputs']==6200;assert s['coverage']['numerator']==4960;assert s['all_input_recall']['numerator']==4340
  assert s['counts']=={'prediction':5600,'abstain':320,'missing':320}
  assert math.isclose(s['all_input_recall']['value'],.7);assert s['non_glyph_acceptance']['value']==.25
  assert math.isclose(s['calibration_raw']['ece']['value'],.025,abs_tol=1e-10)
  assert math.isclose(s['calibration_fitted']['ece']['value'],0,abs_tol=1e-10)
  assert math.isclose(s['calibration_raw']['top_label_brier']['value'],.11,abs_tol=1e-10)
  for c in LABELS:
   t=s['classes'][c];assert t['all_input_recall']['value']==.7;assert t['coverage']['value']==.8;assert t['accepted_only_recall']['value']==.875
   # 10 false non-glyph accepts predict A, lowering A precision only.
   expected=70/90 if c=='A' else 70/80;assert math.isclose(t['accepted_precision']['value'],expected)
 write_json(out/'fixture-results.json',res);write_json(out/'fixture-rows.json',rows)
 write_json(out/'fixture-verification.json',{'passed':True,'known_per_class_all_input_recall':'70/100','known_per_class_coverage':'80/100','accepted_only_recall':'70/80','accepted_precision':'70/80 except A:70/90 with ten non-glyph false accepts','raw_ece':'.025','fitted_ece':'0 on identical synthetic mechanism, not real generalization','top_label_brier':'.11','non_glyph_false_accept':'10/40','counts_per_heldout_cohort':res['cohorts']['test']['counts']})
 return res

def verify_preprocess(out):
 mod,decl=load_preprocess();checks=[]
 # Synthetic geometry only; no result font rendering before manifest gate.
 for wh,box in [((384,384),(101,72,180,290)),((256,256),(20,110,232,145)),((512,512),(200,200,201,201))]:
  frame=Image.new('L',wh,255);ImageDraw.Draw(frame).rectangle((box[0],box[1],box[2]-1,box[3]-1),fill=0)
  crop,actual=intake(frame);assert actual==box
  t=mod.preprocess(crop,decl);assert tuple(t.shape)==(1,105,105)
  # Independently construct expected rectangle scaling and centered white pad.
  w,h=crop.size;nw,nh=max(1,round(w*105/h)),105
  if nw>105:nw,nh=105,max(1,round(h*105/w))
  expected=np.ones((105,105),dtype=np.float32);x=(105-nw)//2;y=(105-nh)//2;expected[y:y+nh,x:x+nw]=0
  assert np.array_equal(t.numpy()[0],expected)
  checks.append(dict(frame=list(wh),bbox=list(actual),scaled=[nw,nh],passed=True))
 try:mod.preprocess(Image.new('L',(20,20),255),decl);raise AssertionError('blank did not refuse')
 except mod.PackRefusal as e:assert str(e)=='TileNoInk'
 assert intake(Image.new('L',(384,384),255))==(None,None)
 write_json(out/'preprocess-verification.json',{'passed':True,'checks':checks,'blank':'typed TileNoInk; no made-up prediction','data_py_sha256':sha(ROOT/'source/w6trainer-src/data.py'),'cleaning':'identity, clean renders only'})

def render(manifest,cache,out,gate):
 g=json.loads(pathlib.Path(gate).read_text());m=json.loads(pathlib.Path(manifest).read_text())
 if g.get('manifest_sha256')!=sha(manifest) or not g.get('publication_url') or g.get('same_id')!='W-0224' or g.get('response') not in ('manifest ok','drop/replace'):raise ValueError('RenderGateNotSatisfied: resolved approved manifest and same-id manifest ok receipt required')
 rows=[]
 if any(name not in {f['family'] for f in m['fonts']} for name in g.get('drop_families',[])):raise ValueError('UnknownDropFamily')
 if g['response']=='drop/replace' and (not isinstance(g.get('drop_families'),list) or not g['drop_families']):raise ValueError('DropListMissing')
 for f in m['fonts']:
  if g.get('response')=='drop/replace' and f['family'] in g.get('drop_families',[]):continue
  p=cache/f['slug']/f['file_name']
  if sha(p)!=f['sha256']:raise ValueError('FontHashMismatch')
  for size,em in [(256,170),(384,256),(512,341)]:
   font=ImageFont.truetype(str(p),em)
   for c in LABELS:
    frame=Image.new('L',(size,size),255);d=ImageDraw.Draw(frame);bbox=d.textbbox((0,0),c,font=font);w,h=bbox[2]-bbox[0],bbox[3]-bbox[1]
    d.text(((size-w)//2-bbox[0],(size-h)//2-bbox[1]),c,font=font,fill=0)
    crop,inkbox=intake(frame)
    if crop is None or min(inkbox[0],inkbox[1],size-inkbox[2],size-inkbox[3])<size//12:raise ValueError('RenderMarginFailure:'+f['family']+':'+c)
    kinds={'glyph':frame,'half_glyph':Image.new('L',(size,size),255),'two_glyph':Image.new('L',(size,size),255)}
    half=frame.copy();ImageDraw.Draw(half).rectangle((size//2,0,size,size),fill=255);kinds['half_glyph']=half
    small=crop.resize((max(1,crop.width//2),max(1,crop.height//2)),Image.Resampling.BILINEAR);two=kinds['two_glyph'];two.paste(small,(size//4-small.width//2,size//2-small.height//2));two.paste(small,(3*size//4-small.width//2,size//2-small.height//2))
    # Small negatives: A/a/0 only, plus one blank per family/size.
    for kind,im in kinds.items():
     if kind!='glyph' and c not in ['A','a','0']:continue
     rel=pathlib.Path('frames')/f['slug']/str(size)/(f'{ord(c):04X}-{kind}.png');path=out/rel;path.parent.mkdir(parents=True,exist_ok=True);im.save(path)
     rows.append(dict(id=str(rel),path=str(rel),family=f['family'],cohort=f['cohort'],truth=c if kind=='glyph' else None,source_char=c,kind=kind,frame_size=size,em_size=em,image_sha256=sha(path),font_sha256=f['sha256']))
   path=out/'frames'/f['slug']/str(size)/'blank.png';Image.new('L',(size,size),255).save(path);rel=path.relative_to(out)
   rows.append(dict(id=str(rel),path=str(rel),family=f['family'],cohort=f['cohort'],truth=None,source_char=None,kind='blank',frame_size=size,em_size=em,image_sha256=sha(path),font_sha256=f['sha256']))
 write_json(out/'dataset.json',{'rows':rows,'gate':g,'manifest_sha256':sha(manifest),'font_manifest':m,'missing_families':sorted(g.get('drop_families',[]) if g['response']=='drop/replace' else []),'cleaning':'identity'})

def score_dataset(dataset,plugin,out,manifest_path):
 p=pathlib.Path(dataset);doc=json.loads(p.read_text());manifest=json.loads(pathlib.Path(manifest_path).read_text())
 if doc.get('manifest_sha256')!=sha(manifest_path) or doc.get('font_manifest')!=manifest:raise ValueError('DatasetManifestHashMismatch')
 if not manifest:raise ValueError('DatasetManifestMissing')
 # Preflight all provenance before invoking any scorer.
 preflight=[{**r,'status':'missing'} for r in doc['rows']]
 for r in preflight:
  if r.get('cohort') not in ('calibration','validation','test'):raise ValueError('UnknownCohort')
 # validate_rows requires actual calibration predictions; use placeholders only for preflight validation.
 for r in preflight:
  if r['truth'] is not None:r.update(status='prediction',predicted=r['truth'],confidence=0.0,rejected=False)
 validate_rows(preflight,manifest,missing_families=doc.get('missing_families',[]))
 mod,decl=load_preprocess();spec=importlib.util.spec_from_file_location('w0224_plugin',plugin);pl=importlib.util.module_from_spec(spec);sys.modules[spec.name]=pl;spec.loader.exec_module(pl);scorer=pl.create_scorer();rows=[]
 for meta in doc['rows']:
  path=p.parent/meta['path'];assert sha(path)==meta['image_sha256'];frame=Image.open(path);crop,bbox=intake(frame)
  if crop is None:value=Abstain('TileNoInk','intake blank; production intake refuses before scorer')
  else:
   tensor=mod.preprocess(crop,decl) # EXACT pinned data.py, called on tight crop.
   tensor_hash=hashlib.sha256(tensor.numpy().tobytes()).hexdigest()
   value=scorer.score(crop) # Image interface; production scorer repeats same preprocess.
   meta={**meta,'recognition_bbox':bbox,'preprocessed_sha256':tensor_hash}
  rows.append(record(meta,value))
 write_json(out/'predictions.json',rows)
 results=evaluate(rows,manifest,missing_families=doc.get('missing_families',[]));write_json(out/'results.json',results)
 header=['# W-0224 results status', '', 'Status: '+results['status'], 'Missing families: '+(', '.join(results['input_reconciliation']['missing_families']) or 'none'), 'Missing cohorts: '+(', '.join(results['input_reconciliation']['missing_cohorts']) or 'none'), 'Calibration usable: '+str(results['input_reconciliation']['calibration_usable']), 'Not measured means unavailable, not zero support or zero performance.']
 if results.get('reason'):header.append('Typed refusal: '+results['reason']+'; no calibration fitted and no metric tables fabricated.')
 (out/'RESULTS-STATUS.md').write_text('\n'.join(header)+'\n')

def hash_outputs(root):
 write_json(root/'OUTPUT-SHA256.json',{str(p.relative_to(root)):sha(p) for p in sorted(root.rglob('*')) if p.is_file() and p.name!='OUTPUT-SHA256.json'})

def main():
 a=argparse.ArgumentParser();a.add_argument('command',choices=['verify','render','score']);a.add_argument('--out',type=pathlib.Path,required=True);a.add_argument('--manifest',default=str(ROOT/'font-manifest.json'));a.add_argument('--cache',type=pathlib.Path,default=ROOT/'font-cache');a.add_argument('--gate');a.add_argument('--dataset');a.add_argument('--plugin');x=a.parse_args();x.out.mkdir(parents=True,exist_ok=True)
 if x.command=='verify':verify_fixture(x.out);verify_preprocess(x.out)
 elif x.command=='render':render(x.manifest,x.cache,x.out,x.gate)
 elif x.command=='score':score_dataset(x.dataset,x.plugin,x.out,x.manifest)
 hash_outputs(x.out)
if __name__=='__main__':main()
