"""Explicit schema-validated JSON ledger_rows -> descriptive TSV adapter."""
import argparse,csv,hashlib,importlib.util,json,math,shutil,tempfile,unicodedata
from pathlib import Path
from jsonschema import Draft202012Validator
FIELDS=('pair','family','partition','namespace','unit','resid_base','resid_cand','attempted','base_available','cand_available','paired_available','unavailable_reason_base','unavailable_reason_cand')
class AdapterError(ValueError):pass

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
STRICT_PATH=Path(__file__).resolve().parent.parent/'real_fit_schema'/'strict_json.py'
_spec=importlib.util.spec_from_file_location('real_fit_strict_json',STRICT_PATH)
_strict=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_strict)
def load(p):
 try:return _strict.load(p)
 except _strict.StrictJSONError as e:raise AdapterError(str(e)) from e
def check(s,r,label):
 try:_strict.validate(s,r,label)
 except _strict.StrictJSONError as e:raise AdapterError(str(e)) from e
def safe_text(value,field):
 if value!=value.strip() or any(unicodedata.category(c) in ('Cc','Cf','Cs','Co','Cn','Zl','Zp') or (unicodedata.category(c)=='Zs' and c!=' ') for c in value) or '"' in value or value.startswith('#'):
  raise AdapterError('TSV_UNSAFE_TEXT:'+field)
 return value
def convert(record,json_schema,report_schema,report_module,out):
 # Final path is never touched before complete parse/structural/semantic validation.
 if out.exists() or out.is_symlink():raise AdapterError('OUTPUT_EXISTS')
 source=load(record);js=load(json_schema);ds=load(report_schema);check(js,source,'JSON_SCHEMA_MISMATCH_STOP')
 if not source['ledger_rows']:raise AdapterError('NO_LEDGER_ROWS')
 headers=[]
 for name in FIELDS:
  if name not in ds.get('columns',{}):raise AdapterError('REPORT_SCHEMA_MISSING:'+name)
  t=ds['columns'][name]['type'];expected='number' if name in ('resid_base','resid_cand') else ('boolean' if name in ('attempted','base_available','cand_available','paired_available') else 'string')
  if t!=expected:raise AdapterError('REPORT_SCHEMA_TYPE:'+name)
  headers.append(safe_text(ds['columns'][name]['name'],name))
 if len(set(headers))!=len(headers):raise AdapterError('REPORT_HEADER_COLLISION')
 missing=ds['abstention']['missing_error']
 if not isinstance(missing,str) or missing.strip() in ('0','0.0'):raise AdapterError('MISSING_LITERAL_AMBIGUOUS')
 safe_text(missing,'missing_error')
 for literal in ('true','false'):safe_text(ds['boolean_values'][literal],literal)
 if ds['boolean_values']['true']==ds['boolean_values']['false']:raise AdapterError('BOOLEAN_LITERAL_COLLISION')
 seen=set();context_keys=set();encoded=[]
 for row in source['ledger_rows']:
  if row['pair'] in seen:raise AdapterError('DUPLICATE_PAIR')
  seen.add(row['pair']);context_keys.add(tuple(row[n] for n in ('namespace','unit','partition')))
  if row['paired_available']!=(row['base_available'] and row['cand_available']):raise AdapterError('COVERAGE_CONFLICT')
  values=[]
  for name in FIELDS:
   v=row[name];t=ds['columns'][name]['type']
   if t=='number':
    if v is None:values.append(missing)
    else:
     if isinstance(v,float) and v==0.0 and math.copysign(1.0,v)<0:raise AdapterError('NEGATIVE_ZERO:'+name)
     if type(v) is int and abs(v)>2**53:raise AdapterError('UNREPRESENTABLE:'+name)
     try:ok=math.isfinite(v)
     except (OverflowError,TypeError):ok=False
     if not ok:raise AdapterError('NONFINITE_OR_UNREPRESENTABLE:'+name)
     values.append(str(v))
   elif t=='boolean':values.append(ds['boolean_values']['true' if v else 'false'])
   else:values.append(safe_text(v,name))
  encoded.append(values)
 if len(context_keys)!=1:raise AdapterError('MIXED_CONTEXT')
 context=dict(source['context'])
 context.update(mode='DESCRIPTIVE ONLY',source_commit=source['source_commit'],adapter_input_sha256=sha(record),real_fit_compatibility='UNVERIFIED')
 spec=importlib.util.spec_from_file_location('pinned_descriptive_report',report_module);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
 with tempfile.TemporaryDirectory(prefix='json-tsv-') as td:
  stage=Path(td);ledger=stage/'ledger.tsv';ctx=stage/'context.json'
  with ledger.open('w',newline='') as f:
   w=csv.writer(f,delimiter='\t',lineterminator='\n');w.writerow(headers);w.writerows(encoded)
  ctx.write_text(json.dumps(context,sort_keys=True,indent=2,allow_nan=False)+'\n')
  try:summary=mod.generate(ledger,ctx,stage/'dry-report',report_schema)
  except Exception as e:raise AdapterError('DESCRIPTIVE_INTAKE_MISMATCH_STOP:'+str(e)) from e
  receipt={'mode':'DESCRIPTIVE ONLY','input_sha256':sha(record),'json_schema_sha256':sha(json_schema),'report_schema_sha256':sha(report_schema),'report_module_sha256':sha(report_module),'adapter_sha256':sha(Path(__file__)),'strict_json_sha256':sha(STRICT_PATH),'ledger_sha256':sha(ledger),'context_sha256':sha(ctx),'rows':len(encoded),'family_count':summary['families_attempted'],'mapping':'ledger_rows only; JSON null -> configured missing_error, numeric zero preserved','real_writer_compatibility':'UNVERIFIED','sealed_membership':context['sealed_membership'],'dry_report_intake':'PASSED_DESCRIPTIVE_ONLY_NO_GATE'}
  (stage/'receipt.json').write_text(json.dumps(receipt,sort_keys=True,indent=2)+'\n')
  try:out.mkdir()
  except FileExistsError as e:raise AdapterError('OUTPUT_EXISTS') from e
  try:
   for name in ('ledger.tsv','context.json','receipt.json'):shutil.copyfile(stage/name,out/name)
  except Exception:
   shutil.rmtree(out);raise
 return receipt
if __name__=='__main__':
 p=argparse.ArgumentParser()
 for n in ('record','json-schema','report-schema','report-module','out'):p.add_argument('--'+n,type=Path,required=True)
 a=p.parse_args()
 try:print(json.dumps(convert(a.record,a.json_schema,a.report_schema,a.report_module,a.out),sort_keys=True,indent=2))
 except (AdapterError,ValueError) as e:p.exit(1,str(e)+'\n')
