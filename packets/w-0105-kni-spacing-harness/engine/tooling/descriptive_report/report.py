"""Descriptive ledger adapter; no inference, decision gate or win field."""
import argparse,csv,hashlib,itertools,json,math
from pathlib import Path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def flag(s):
 if s not in ('true','false'):raise ValueError('BOOLEAN_REQUIRED: true/false')
 return s=='true'
def generate(ledger,context,out,schema_path):
 meta=json.loads(context.read_text());schema=json.loads(schema_path.read_text());h=[]
 with ledger.open(newline='') as f:r=csv.DictReader(f,delimiter='\t');h=r.fieldnames or [];rows=list(r)
 mapping={v['name']:logical for logical,v in schema['columns'].items()}
 h=[mapping.get(x,x) for x in h]
 rows=[{mapping.get(key,key):value for key,value in row.items()} for row in rows]
 if len(h)!=len(set(h)):raise ValueError('DUPLICATE_MAPPED_HEADER')
 for logical,spec in schema['columns'].items():
  if spec['type'] not in ('number','string','boolean'):raise ValueError('SCHEMA_TYPE')
  if spec['type']=='boolean':
   for row in rows:
    if logical in row:
     if row[logical]==schema['boolean_values']['true']:row[logical]='true'
     elif row[logical]==schema['boolean_values']['false']:row[logical]='false'
     else:raise ValueError('BOOLEAN_REQUIRED:'+logical)
 missing=schema['abstention']['missing_error']
 for row in rows:
  for logical,spec in schema['columns'].items():
   if spec['type']=='number' and logical in row and row[logical]==missing:row[logical]=''
 need={'pair','family','partition','namespace','unit'}
 if not need<=set(h):raise ValueError('MISSING_COLUMNS')
 cols=set(h)&{'resid_base','resid_cand','err_abs_base','err_abs_cand'}
 if cols not in ({'resid_base','resid_cand'},{'err_abs_base','err_abs_cand'}):raise ValueError('ERROR_FORM')
 signed='resid_base' in cols;b,c=('resid_base','resid_cand') if signed else ('err_abs_base','err_abs_cand')
 cov={'attempted','base_available','cand_available','paired_available'}<=set(h)
 seen=set();fam={};ns=set();units=set();parts=set();diffrows=[]
 for x in rows:
  for k in need:
   if not x[k].strip():raise ValueError('EMPTY_CONTEXT:'+k)
  if x['pair'] in seen:raise ValueError('DUPLICATE_PAIR')
  seen.add(x['pair']);ns.add(x['namespace']);units.add(x['unit']);parts.add(x['partition'])
  d=fam.setdefault(x['family'],{'attempted':0,'base_available':0,'cand_available':0,'paired':0,'diffs':[]})
  if cov:
   attempted=flag(x['attempted']);ba=flag(x['base_available']);ca=flag(x['cand_available']);pa=flag(x['paired_available'])
   if pa!=(ba and ca) or ((ba or ca) and not attempted):raise ValueError('COVERAGE_CONFLICT')
   d['attempted']+=attempted;d['base_available']+=ba;d['cand_available']+=ca
   if not pa:
    if (not ba and x[b]) or (not ca and x[c]):raise ValueError('UNAVAILABLE_HAS_ERROR')
    diffrows.append([x['pair'],x['family'],'','UNAVAILABLE']);continue
  elif not x[b] or not x[c]:raise ValueError('MISSING_ERROR_WITHOUT_COVERAGE')
  vb,vc=float(x[b]),float(x[c])
  if not all(math.isfinite(z) for z in (vb,vc)):raise ValueError('NONFINITE')
  if not signed and (vb<0 or vc<0):raise ValueError('NEGATIVE_ABSOLUTE')
  diff=abs(vc)-abs(vb);d['diffs'].append(diff);d['paired']+=1
  diffrows.append([x['pair'],x['family'],diff,'SCORED'])
 if len(ns)!=1 or len(units)!=1 or len(parts)!=1:raise ValueError('MIXED_CONTEXT')
 warnings=['DESCRIPTIVE ONLY: no inference, significance, proof, adoption or winner.']
 disjoint=meta.get('family_disjoint_verified') is True and bool(meta.get('family_binding_pin'))
 independent=meta.get('independence_verified') is True and bool(meta.get('independence_evidence_pin'))
 if not disjoint or not independent:warnings.append('DESCRIPTIVE ONLY: family-disjoint/independent binding prerequisites missing or unverified.')
 codes={x.get(c,'') for x in rows for c in ('unavailable_reason_base','unavailable_reason_cand') if x.get(c,'')}
 unknown=codes-set(schema['abstention']['codes'])
 if unknown:warnings.append('Unlisted abstention codes retained: '+','.join(sorted(unknown)))
 warnings.append('Evidence flags/pins are supplied provenance, not independently validated by this adapter.')
 means=[sum(d['diffs'])/len(d['diffs']) for _,d in sorted(fam.items()) if d['diffs']]
 k=len(means);neg=sum(v<0 for v in means);pos=sum(v>0 for v in means);zero=k-neg-pos;n=neg+pos
 meanp=None;reason=''
 if 0<k<=16:
  obs=sum(means);count=sum(sum(s*v for s,v in zip(sign,means))<=obs for sign in itertools.product((1,-1),repeat=k));meanp=count/(2**k)
 else:reason='NO_SCORED_FAMILIES' if not k else 'EXACT_ENUMERATION_SCOPE_EXCEEDED'
 signp=sum(math.comb(n,j) for j in range(neg,n+1))/(2**n) if n else 1.
 summary={'mode':'DESCRIPTIVE ONLY','warnings':warnings,'ledger_sha256':sha(ledger),'context_sha256':sha(context),'schema_sha256':sha(schema_path),'namespace':next(iter(ns)),'unit':next(iter(units)),'partition':next(iter(parts)),'families_attempted':len(fam),'families_scored':k,'family_mean_difference':sum(means)/k if k else None,'negative_family_count':neg,'positive_family_count':pos,'zero_family_count':zero,'mean_signflip_p_descriptive':meanp,'sign_binomial_p_descriptive':signp if k else None,'p_unavailable_reason':reason,'holm':'NOT_APPLIED_SINGLE_COMPARISON; complete prelisted contrast family required','threshold_policy':'NONE; no decision gate','coverage':'MEASURED_ATTEMPTED_ROWS' if cov else 'NOT_MEASURED','input_error_form':'signed_abs_explicit' if signed else 'absolute','family_disjoint_bound':disjoint,'independence_bound':independent,'real_fit_schema_compatibility':'UNVERIFIED; contract-v2 adapter','supplied_metadata':meta}
 out.mkdir(exist_ok=False)
 def tsv(name,header,rs):
  with (out/name).open('w',newline='') as f:w=csv.writer(f,delimiter='\t');w.writerow(header);w.writerows(rs)
 tsv('pair_differences.tsv',['pair','family','cand_abs_minus_base_abs','status'],diffrows)
 tsv('family_differences.tsv',['family','attempted','base_available','cand_available','paired','mean_difference','negative_pair_count','positive_pair_count','zero_pair_count'],[[f,d['attempted'] if cov else '',d['base_available'] if cov else '',d['cand_available'] if cov else '',d['paired'],sum(d['diffs'])/len(d['diffs']) if d['diffs'] else '',sum(v<0 for v in d['diffs']),sum(v>0 for v in d['diffs']),sum(v==0 for v in d['diffs'])] for f,d in sorted(fam.items())])
 (out/'summary.json').write_text(json.dumps(summary,sort_keys=True,indent=2)+'\n')
 (out/'REPORT.md').write_text('# Descriptive fit report\n\nDESCRIPTIVE ONLY\n\n'+'\n'.join(warnings)+'\n\nPer-pair differences: pair_differences.tsv. Per-family differences and counts: family_differences.tsv. Family-equal mean, two descriptive p-values and context: summary.json.\n\nNegative is lower candidate absolute error, not a win. No threshold or inference gate. No Holm after incomplete comparison-family inputs.\n')
 return summary
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--ledger',type=Path,required=True);p.add_argument('--context',type=Path,required=True);p.add_argument('--schema',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 print(json.dumps(generate(a.ledger,a.context,a.out,a.schema),sort_keys=True,indent=2))
