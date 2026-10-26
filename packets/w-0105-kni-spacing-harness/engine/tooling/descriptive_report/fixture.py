from pathlib import Path
import csv,json
R=Path(__file__).resolve().parent
cols=['pair','family','partition','namespace','unit','resid_base','resid_cand','attempted','base_available','cand_available','paired_available','unavailable_reason_base','unavailable_reason_cand']
with (R/'synthetic-fit.tsv').open('w',newline='') as f:
 w=csv.writer(f,delimiter='\t');w.writerow(cols)
 for i in range(12):
  for j in range(2):w.writerow([f'p{i}_{j}',f'f{i}','fit','synthetic:descriptive-report','SYNTHETIC_U',2,1 if i%2 else 3,'true','true','true','true','',''])
 w.writerow(['missing','f0','fit','synthetic:descriptive-report','SYNTHETIC_U',2,'','true','true','false','false','','SYNTHETIC_MISSING_QUERY'])
(R/'context.json').write_text(json.dumps({'synthetic_only':True,'family_disjoint_verified':False,'independence_verified':False,'family_binding_pin':'','independence_evidence_pin':'','seed_CONVENTION':20261013},sort_keys=True,indent=2)+'\n')
