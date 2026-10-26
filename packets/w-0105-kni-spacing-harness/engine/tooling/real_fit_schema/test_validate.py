import copy,json,subprocess,sys,tempfile,unittest
from pathlib import Path
import strict_json as sj
P=Path(__file__).resolve().parent;S=sj.load(P/'real-fit.schema.json');VALID=sj.load(P/'valid.json')
class StrictIntakeTests(unittest.TestCase):
 def setUp(self):self.a=copy.deepcopy(VALID)
 def reject(self,fn,msg):
  fn(self.a)
  with self.assertRaisesRegex(sj.StrictJSONError,msg):sj.validate(S,self.a)
 def test_valid(self):sj.validate(S,self.a)
 def test_nested_overflow(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'x';p.write_text('{"nested":[{"v":1e400}]}')
   with self.assertRaisesRegex(sj.StrictJSONError,'NONFINITE'):sj.load(p)
 def test_duplicate_key(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'x';p.write_text('{"v":1,"v":2}')
   with self.assertRaisesRegex(sj.StrictJSONError,'DUPLICATE_JSON_KEY'):sj.load(p)
 def test_source_final_newline(self):self.reject(lambda a:a.update(source_commit='a'*40+'\n'),'SCHEMA_MISMATCH')
 def test_source_uppercase(self):self.reject(lambda a:a.update(source_commit='A'*40),'SCHEMA_MISMATCH')
 def test_empty_predictions(self):self.reject(lambda a:a.update(predictions=[]),'SCHEMA_MISMATCH')
 def test_empty_ledger(self):self.reject(lambda a:a.update(ledger_rows=[]),'SCHEMA_MISMATCH')
 def test_capture_omitted_and_empty(self):
  self.a.pop('capture_outputs');sj.validate(S,self.a);self.a['capture_outputs']=[];sj.validate(S,self.a)
 def test_integer_float_syntax(self):self.reject(lambda a:a['predictions'][0]['prediction'].update(predicted=1.0),'SCHEMA_MISMATCH')
 def test_usize_float(self):self.reject(lambda a:a['predictions'][0]['receipt'].update(part_glyph_count=1.0),'SCHEMA_MISMATCH')
 def test_usize_upper(self):self.reject(lambda a:a['predictions'][0]['receipt'].update(part_glyph_count=2**64),'SCHEMA_MISMATCH')
 def test_i32_lower(self):self.reject(lambda a:a['observations'][0].update(kern=-2**31-1),'SCHEMA_MISMATCH')
 def test_duplicate_row(self):self.reject(lambda a:a['ledger_rows'].append(copy.deepcopy(a['ledger_rows'][0])),'DUPLICATE_LEDGER_ROW')
 def test_duplicate_pair(self):self.reject(lambda a:a['ledger_rows'][1].update(pair=a['ledger_rows'][0]['pair']),'DUPLICATE_PAIR')
 def test_partition_free_text(self):self.a['ledger_rows'][0]['partition']='future-free-label';sj.validate(S,self.a)
 def test_true_empty_independence(self):self.reject(lambda a:a['context'].update(independence_verified=True,independence_evidence_pin='  '),'SCHEMA_MISMATCH')
 def test_true_null_family(self):self.reject(lambda a:a['context'].update(family_disjoint_verified=True,family_binding_pin=None),'SCHEMA_MISMATCH')
 def test_true_nonblank_claim(self):self.a['context'].update(independence_verified=True,independence_evidence_pin='fixture');sj.validate(S,self.a)
 def test_cli_invalid_no_success(self):
  r=subprocess.run([sys.executable,str(P/'validate.py'),'--schema',str(P/'real-fit.schema.json'),'--record',str(P/'invalid.json')],capture_output=True,text=True)
  self.assertEqual(r.returncode,1);self.assertIn('resid_cand',r.stderr)
 def test_cli_overflow_and_duplicate(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'x'
   for text,msg in [('{"x":1e400}','NONFINITE'),('{"x":1,"x":2}','DUPLICATE')]:
    p.write_text(text);r=subprocess.run([sys.executable,str(P/'validate.py'),'--schema',str(P/'real-fit.schema.json'),'--record',str(p)],capture_output=True,text=True)
    self.assertEqual(r.returncode,1);self.assertIn(msg,r.stderr)
 def test_recursion_limit_typed(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'x';depth=sys.getrecursionlimit()*2;p.write_text('['*depth+'0'+']'*depth)
   with self.assertRaisesRegex(sj.StrictJSONError,'JSON_TOO_DEEP'):sj.load(p)
 def test_runtime_integer_limit_typed(self):
  limit=sys.get_int_max_str_digits()
  if not limit:self.skipTest('runtime integer limit disabled')
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'x';p.write_text('1'*(limit+1))
   with self.assertRaisesRegex(sj.StrictJSONError,'JSON_INTEGER_TOO_LARGE'):sj.load(p)
 def test_surrogate_everywhere(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'x'
   for text in ('{"\\ud800":1}','{"nested":["\\udfff"]}'):
    p.write_text(text)
    with self.assertRaisesRegex(sj.StrictJSONError,'INVALID_UNICODE'):sj.load(p)
 def test_non_bmp_unicode_valid(self):
  with tempfile.TemporaryDirectory() as td:
   p=Path(td)/'x';p.write_text('{"x":"\\ud83d\\ude00"}');self.assertEqual(sj.load(p)['x'],'😀')
if __name__=='__main__':unittest.main()
