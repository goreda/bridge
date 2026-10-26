import csv,importlib.util,json,tempfile,unittest
from pathlib import Path
P=Path(__file__).resolve().parent;S=P.parent/'real_fit_schema';D=P.parent/'descriptive_report';spec=importlib.util.spec_from_file_location('a',P/'adapter.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class AdapterTests(unittest.TestCase):
 def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.t=Path(self.tmp.name);self.out=self.t/'out'
 def tearDown(self):self.tmp.cleanup()
 def run_adapter(self,record=None,rs=None):return m.convert(record or S/'valid.json',S/'real-fit.schema.json',rs or D/'schema.json',D/'report.py',self.out)
 def change(self,fn):
  a=json.loads((S/'valid.json').read_text());fn(a);p=self.t/'record.json';p.write_text(json.dumps(a));return p
 def test_valid_e2e_null_vs_zero(self):
  rec=self.change(lambda a:a['ledger_rows'][0].update(resid_cand=0));self.run_adapter(rec)
  with (self.out/'ledger.tsv').open() as f:rs=list(csv.DictReader(f,delimiter='\t'))
  self.assertEqual(rs[0]['resid_cand'],'0');self.assertEqual(rs[1]['resid_cand'],'');self.assertEqual(rs[1]['cand_available'],'false')
  c=json.loads((self.out/'context.json').read_text());self.assertEqual(c['sealed_membership'],'UNVERIFIED');self.assertFalse(c['independence_verified'])
 def test_invalid_schema_no_output(self):
  with self.assertRaisesRegex(m.AdapterError,'JSON_SCHEMA_MISMATCH_STOP'):self.run_adapter(S/'invalid.json')
  self.assertFalse(self.out.exists())
 def test_duplicate_json_key(self):
  p=self.t/'a';p.write_text('{"mode":"DESCRIPTIVE ONLY","mode":"PASS"}')
  with self.assertRaisesRegex(m.AdapterError,'DUPLICATE_JSON_KEY'):self.run_adapter(p)
  self.assertFalse(self.out.exists())
 def test_nonfinite(self):
  p=self.t/'a';p.write_text('{"x": NaN}')
  with self.assertRaisesRegex(m.AdapterError,'NONFINITE_JSON'):self.run_adapter(p)
 def test_duplicate_pair(self):
  rec=self.change(lambda a:a['ledger_rows'][1].update(pair=a['ledger_rows'][0]['pair']))
  with self.assertRaisesRegex(m.AdapterError,'DUPLICATE_PAIR'):self.run_adapter(rec)
  self.assertFalse(self.out.exists())
 def test_mixed_partition(self):
  rec=self.change(lambda a:a['ledger_rows'][1].update(partition='other'))
  with self.assertRaisesRegex(m.AdapterError,'MIXED_CONTEXT'):self.run_adapter(rec)
 def test_empty_ledger(self):
  rec=self.change(lambda a:a.update(ledger_rows=[]))
  with self.assertRaisesRegex(m.AdapterError,'JSON_SCHEMA_MISMATCH_STOP'):self.run_adapter(rec)
 def test_existing_output_preserved(self):
  self.out.mkdir();(self.out/'sentinel').write_text('keep')
  with self.assertRaisesRegex(m.AdapterError,'OUTPUT_EXISTS'):self.run_adapter()
  self.assertEqual((self.out/'sentinel').read_text(),'keep')
 def test_schema_header_mapping(self):
  s=json.loads((D/'schema.json').read_text());s['columns']['resid_cand']['name']='candidate_residual';s['boolean_values']={'true':'1','false':'0'};p=self.t/'s';p.write_text(json.dumps(s));self.run_adapter(rs=p)
  with (self.out/'ledger.tsv').open() as f:r=csv.DictReader(f,delimiter='\t');rows=list(r)
  self.assertIn('candidate_residual',r.fieldnames);self.assertEqual(rows[1]['candidate_residual'],'');self.assertEqual(rows[0]['attempted'],'1')
 def test_tabs_quotes_refused(self):
  for value in ('a\tb','a\rb','a\nb','a"b','#comment','a\x00b','a\x7fb'):
   rec=self.change(lambda a:a['ledger_rows'][1].update(unavailable_reason_cand=value))
   with self.assertRaisesRegex(m.AdapterError,'TSV_UNSAFE_TEXT:unavailable_reason_cand'):self.run_adapter(rec)
   self.assertFalse(self.out.exists())
 def test_header_collision(self):
  s=json.loads((D/'schema.json').read_text());s['columns']['resid_cand']['name']='resid_base';p=self.t/'s';p.write_text(json.dumps(s))
  with self.assertRaisesRegex(m.AdapterError,'REPORT_HEADER_COLLISION'):self.run_adapter(rs=p)
 def test_zero_missing_literal(self):
  s=json.loads((D/'schema.json').read_text());s['abstention']['missing_error']='0';p=self.t/'s';p.write_text(json.dumps(s))
  with self.assertRaisesRegex(m.AdapterError,'MISSING_LITERAL_AMBIGUOUS'):self.run_adapter(rs=p)
 def test_replay_identical(self):
  self.run_adapter();first={p.name:p.read_bytes() for p in self.out.iterdir()};self.out=self.t/'second';self.run_adapter();self.assertEqual(first,{p.name:p.read_bytes() for p in self.out.iterdir()})
 def test_overflow_float_anywhere(self):
  p=self.t/'x';p.write_text('{"unknown":{"v":1e400}}')
  with self.assertRaisesRegex(m.AdapterError,'NONFINITE_JSON'):self.run_adapter(p)
  self.assertFalse(self.out.exists())
 def test_integer_token_and_usize(self):
  for v in (1.0,2**64):
   rec=self.change(lambda a:a['predictions'][0]['receipt'].update(part_glyph_count=v))
   with self.assertRaisesRegex(m.AdapterError,'JSON_SCHEMA_MISMATCH_STOP'):self.run_adapter(rec)
   self.assertFalse(self.out.exists())
 def test_bad_commit(self):
  rec=self.change(lambda a:a.update(source_commit='A'*40))
  with self.assertRaisesRegex(m.AdapterError,'JSON_SCHEMA_MISMATCH_STOP'):self.run_adapter(rec)
 def test_empty_predictions(self):
  rec=self.change(lambda a:a.update(predictions=[]))
  with self.assertRaisesRegex(m.AdapterError,'JSON_SCHEMA_MISMATCH_STOP'):self.run_adapter(rec)
 def test_duplicate_row_semantic(self):
  rec=self.change(lambda a:a['ledger_rows'].append(dict(a['ledger_rows'][0])))
  with self.assertRaisesRegex(m.AdapterError,'DUPLICATE_LEDGER_ROW'):self.run_adapter(rec)
 def test_true_empty_evidence(self):
  rec=self.change(lambda a:a['context'].update(independence_verified=True,independence_evidence_pin=''))
  with self.assertRaisesRegex(m.AdapterError,'JSON_SCHEMA_MISMATCH_STOP'):self.run_adapter(rec)
 def test_surrogate_keys_and_values(self):
  for text in ('{"\\ud800":1}','{"x":"\\udfff"}'):
   p=self.t/'x';p.write_text(text)
   with self.assertRaisesRegex(m.AdapterError,'INVALID_UNICODE'):self.run_adapter(p)
   self.assertFalse(self.out.exists())
 def test_deep_and_integer_limit(self):
  import sys
  p=self.t/'x';p.write_text('['*(sys.getrecursionlimit()*2)+'0'+']'*(sys.getrecursionlimit()*2))
  with self.assertRaisesRegex(m.AdapterError,'JSON_TOO_DEEP'):self.run_adapter(p)
  limit=sys.get_int_max_str_digits()
  if limit:
   p.write_text('1'*(limit+1))
   with self.assertRaisesRegex(m.AdapterError,'JSON_INTEGER_TOO_LARGE'):self.run_adapter(p)
 def test_text_fields_unsafe_and_case_preserved(self):
  for field in ('pair','family','partition'):
   rec=self.change(lambda a:a['ledger_rows'][0].update(**{field:'#unsafe'}))
   with self.assertRaisesRegex(m.AdapterError,'TSV_UNSAFE_TEXT:'+field):self.run_adapter(rec)
  rec=self.change(lambda a:a['ledger_rows'][1].update(pair='Synthetic-Pair-1'))
  self.run_adapter(rec)
  self.assertIn('Synthetic-Pair-1',(self.out/'ledger.tsv').read_text())
 def test_negative_zero_and_integer_binary64(self):
  for value,msg in [(-0.0,'NEGATIVE_ZERO'),(2**53+1,'UNREPRESENTABLE'),(-2**53-1,'UNREPRESENTABLE')]:
   rec=self.change(lambda a:a['ledger_rows'][0].update(resid_base=value))
   with self.assertRaisesRegex(m.AdapterError,msg):self.run_adapter(rec)
   self.assertFalse(self.out.exists())
 def test_safety_all_text_fields_direct(self):
  for field in ('pair','family','partition','namespace','unit','unavailable_reason_base','unavailable_reason_cand'):
   for value in ('a\tb','a\rb','a\nb','a"b','#comment','a\x00b',' a','a ',' '):
    with self.assertRaisesRegex(m.AdapterError,'TSV_UNSAFE_TEXT:'+field):m.safe_text(value,field)
 def test_positive_zero_and_exact_integer_boundary(self):
  for i,value in enumerate((0.0,2**53,-2**53)):
   self.out=self.t/str(i);rec=self.change(lambda a:a['ledger_rows'][0].update(resid_base=value));self.run_adapter(rec)
 def test_text_boundary_whitespace(self):
  for value in (' a','a ',' '):
   rec=self.change(lambda a:a['ledger_rows'][0].update(pair=value))
   with self.assertRaisesRegex(m.AdapterError,'TSV_UNSAFE_TEXT:pair'):self.run_adapter(rec)
   self.assertFalse(self.out.exists())
 def test_unicode_unsafe_categories(self):
  import unicodedata
  codes=('\u200b','\u202e','\u2028','\u2029','\u00a0','\u3000','\ue000','\u0378')
  self.assertEqual(unicodedata.category('\u0378'),'Cn')
  for char in codes:
   for field in ('pair','family','partition','namespace','unit','unavailable_reason_base','unavailable_reason_cand'):
    with self.assertRaisesRegex(m.AdapterError,'TSV_UNSAFE_TEXT:'+field):m.safe_text('a'+char+'b',field)
   rec=self.change(lambda a:a['ledger_rows'][0].update(pair='a'+char+'b'))
   with self.assertRaisesRegex(m.AdapterError,'TSV_UNSAFE_TEXT:pair'):self.run_adapter(rec)
   self.assertFalse(self.out.exists())
  with self.assertRaisesRegex(m.AdapterError,'TSV_UNSAFE_TEXT:pair'):m.safe_text('a\ud800b','pair')
 def test_ascii_internal_space_allowed(self):self.assertEqual(m.safe_text('a b','pair'),'a b')
if __name__=='__main__':unittest.main()
