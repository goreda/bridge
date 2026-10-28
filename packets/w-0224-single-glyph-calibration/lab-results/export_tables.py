"""Flat CSV tables from canonical metric JSON, denominators in every rate row."""
import csv,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());out=p.parent
with (out/'per-class.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['cohort','class','support','font_count','measure','numerator','denominator','value','wilson95_low','wilson95_high','abstain','missing','rejected'])
 for co,s in d['cohorts'].items():
  if s.get('status')=='not_measured':continue
  for c,t in s['classes'].items():
   for key in ['all_input_recall','coverage','accepted_precision','accepted_only_recall']:
    r=t[key];ci=r['wilson95'] or [None,None];w.writerow([co,c,t['support'],t['font_count'],key,r['numerator'],r['denominator'],r['value'],*ci,t['abstain'],t['missing'],t['rejected']])
with (out/'reliability.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['cohort','variant','low','high','right_closed','count','correct','accuracy_denominator','accuracy','mean_confidence'])
 for co,s in d['cohorts'].items():
  if s.get('status')=='not_measured':continue
  for key in ['calibration_raw','calibration_fitted']:
   for b in s[key]['buckets']:w.writerow([co,key,b['low'],b['high'],b['right_closed'],b['count'],b['correct'],b['accuracy']['denominator'],b['accuracy']['value'],b['mean_confidence']])
with (out/'confusions.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(['cohort','truth','predicted','count'])
 for co,s in d['cohorts'].items():
  if s.get('status')=='not_measured':continue
  for r in s['confusion_pairs']:w.writerow([co,r['truth'],r['predicted'],r['count']])
