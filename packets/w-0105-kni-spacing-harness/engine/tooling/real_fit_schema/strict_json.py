"""Shared strict JSON intake and descriptive ledger semantic checks."""
import json,math
from pathlib import Path
from jsonschema import Draft202012Validator,validators
class StrictJSONError(ValueError):pass

def unicode_string(value):
 if any(0xD800<=ord(c)<=0xDFFF for c in value):raise StrictJSONError('INVALID_UNICODE')
def parse_integer(value):
 try:return int(value)
 except ValueError as e:raise StrictJSONError('JSON_INTEGER_TOO_LARGE') from e
def pairs(items):
 out={}
 for k,v in items:
  unicode_string(k)
  if k in out:raise StrictJSONError('DUPLICATE_JSON_KEY:'+k)
  out[k]=v
 return out
def constant(v):raise StrictJSONError('NONFINITE_JSON:'+v)
def finite_tree(value,path=()):
 if isinstance(value,str):unicode_string(value)
 if isinstance(value,float) and not math.isfinite(value):raise StrictJSONError('NONFINITE_JSON: /'+'/'.join(map(str,path)))
 if isinstance(value,dict):
  for k,v in value.items():
   unicode_string(k);finite_tree(v,path+(k,))
 elif isinstance(value,list):
  for i,v in enumerate(value):finite_tree(v,path+(i,))
def load(path):
 try:
  value=json.loads(Path(path).read_text(),object_pairs_hook=pairs,parse_constant=constant,parse_int=parse_integer)
  finite_tree(value);return value
 except RecursionError as e:raise StrictJSONError('JSON_TOO_DEEP') from e
# JSON Schema mathematically calls 1.0 integer. Rust projection requires the
# JSON integer token category, retained by json.loads as Python int, not float.
def integer(checker,value):return type(value) is int
StrictValidator=validators.extend(Draft202012Validator,type_checker=Draft202012Validator.TYPE_CHECKER.redefine('integer',integer))
def semantic(record):
 seen_pairs=set();seen_rows=set()
 for row in record.get('ledger_rows',[]):
  key=json.dumps(row,sort_keys=True,separators=(',',':'),allow_nan=False)
  if key in seen_rows:raise StrictJSONError('DUPLICATE_LEDGER_ROW')
  seen_rows.add(key)
  if row['pair'] in seen_pairs:raise StrictJSONError('DUPLICATE_PAIR')
  seen_pairs.add(row['pair'])
def validate(schema,record,label='SCHEMA_MISMATCH'):
 finite_tree(schema);finite_tree(record);StrictValidator.check_schema(schema)
 errors=sorted(StrictValidator(schema).iter_errors(record),key=lambda e:str(list(e.path)))
 if errors:raise StrictJSONError(label+': /'+'/'.join(map(str,errors[0].path))+': '+errors[0].message)
 semantic(record)
