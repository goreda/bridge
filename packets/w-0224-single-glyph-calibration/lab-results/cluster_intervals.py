"""Family-cluster percentile bootstrap for image-fixture heldout metrics.
Resample whole families with replacement, keeping all glyphs/sizes/negatives.
Frozen calibration map is NOT refitted from heldout data.
"""
import json,pathlib,numpy as np,collections
R=pathlib.Path(__file__).parent
rows=json.loads((R/'approved15-fixture/predictions.json').read_text());res=json.loads((R/'approved15-fixture/results.json').read_text());rng=np.random.default_rng(2242026);B=5000

def measures(rs):
 pos=[r for r in rs if r['truth'] is not None];neg=[r for r in rs if r['truth'] is None];ap=[r for r in pos if r['status']=='prediction' and not r['rejected']];an=[r for r in neg if r['status']=='prediction' and not r['rejected']];tp=sum(r['predicted']==r['truth'] for r in ap)
 return dict(all_input_recall=tp/len(pos) if pos else None,coverage=len(ap)/len(pos) if pos else None,accepted_precision=tp/(len(ap)+len(an)) if ap or an else None,non_glyph_acceptance=len(an)/len(neg) if neg else None,raw_top_label_ece=abs(.9-tp/len(ap)) if ap else None)
def bootstrap(rs):
 families=sorted(set(r['family'] for r in rs));groups=[[r for r in rs if r['family']==f] for f in families];vals=collections.defaultdict(list)
 for _ in range(B):
  sample=[r for i in rng.integers(0,len(groups),len(groups)) for r in groups[i]]
  for key,v in measures(sample).items():
   if v is not None:vals[key].append(v)
 return {k:dict(point=measures(rs)[k],percentile95=np.quantile(v,[.025,.975]).tolist(),valid_replicates=len(v)) for k,v in vals.items()}
out={'scope':'IMAGE-PIPELINE FIXTURE ORACLE ONLY, NOT RECOGNIZER PERFORMANCE','seed':2242026,'replicates':B,'method':'Resample five whole families per heldout cohort with replacement, preserving all rows including render-size repeats and negatives. Fixed calibration map never refit. Percentile 95%, exploratory with only five independent families; not a population guarantee.','cohorts':{}}
for co in ['validation','test']:
 rs=[r for r in rows if r['cohort']==co];out['cohorts'][co]={'font_count':len(set(r['family'] for r in rs)),'metrics':bootstrap(rs),'per_class':{}}
 for c in res['cohorts'][co]['classes']:
  # Precision denominator must also retain other-truth false predictions and negatives.
  family_stats=[]
  for f in sorted(set(r['family'] for r in rs)):
   rr=[r for r in rs if r['family']==f];truth=[r for r in rr if r['truth']==c];acc=[r for r in truth if r['status']=='prediction' and not r['rejected']];pred=[r for r in rr if r['status']=='prediction' and not r['rejected'] and r['predicted']==c];tp=sum(r['truth']==c for r in pred);family_stats.append([tp,len(truth),len(acc),len(pred)])
  a=np.array(family_stats);sample=a[rng.integers(0,len(a),(B,len(a)))].sum(axis=1);ci={}
  for key,n,d in [('all_input_recall',0,1),('coverage',2,1),('accepted_precision',0,3),('accepted_only_recall_conditional',0,2)]:
   valid=sample[:,d]>0;v=sample[valid,n]/sample[valid,d];ci[key]={'percentile95':np.quantile(v,[.025,.975]).tolist() if len(v) else None,'valid_replicates':int(valid.sum())}
  out['cohorts'][co]['per_class'][c]=ci
(R/'approved15-fixture/family-clustered-intervals.json').write_text(json.dumps(out,indent=2,allow_nan=False)+'\n')
