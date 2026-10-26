import csv,importlib.util,json,tempfile,unittest
from pathlib import Path
P=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('r',P/'report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ReportTests(unittest.TestCase):
 def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.t=Path(self.tmp.name)
 def tearDown(self):self.tmp.cleanup()
 def run_report(self,ledger=None,schema=None,context=None):return m.generate(ledger or P/'synthetic-fit.tsv',context or P/'context.json',self.t/'out',schema or P/'schema.json')
 def test_e2e_abstention_no_gate(self):
  r=self.run_report();self.assertEqual(r['mode'],'DESCRIPTIVE ONLY');self.assertEqual(r['families_scored'],12)
  self.assertEqual(r['family_mean_difference'],0);self.assertFalse(r['independence_bound']);self.assertEqual(r['threshold_policy'],'NONE; no decision gate')
  self.assertIn('prerequisites missing',r['warnings'][1]);self.assertNotIn('winner',r)
  with (self.t/'out/family_differences.tsv').open() as f:rows=list(csv.DictReader(f,delimiter='\t'))
  x=next(x for x in rows if x['family']=='f0');self.assertEqual(x['attempted'],'3');self.assertEqual(x['paired'],'2')
 def test_schema_only_header_change(self):
  s=json.loads((P/'schema.json').read_text());s['columns']['resid_cand']['name']='candidate_error';s['boolean_values']={'true':'1','false':'0'}
  sp=self.t/'schema.json';sp.write_text(json.dumps(s));l=self.t/'input.tsv'
  t=(P/'synthetic-fit.tsv').read_text().replace('resid_cand','candidate_error').replace('\ttrue','\t1').replace('\tfalse','\t0');l.write_text(t)
  self.assertEqual(self.run_report(l,sp)['family_mean_difference'],0)
 def test_mixed_units_refused(self):
  l=self.t/'l';l.write_text((P/'synthetic-fit.tsv').read_text().replace('SYNTHETIC_U','OTHER',1))
  with self.assertRaisesRegex(ValueError,'MIXED_CONTEXT'):self.run_report(l)
 def test_unavailable_not_zero(self):
  l=self.t/'l';l.write_text((P/'synthetic-fit.tsv').read_text().replace('SYNTHETIC_U\t2\t\ttrue','SYNTHETIC_U\t2\t0\ttrue'))
  with self.assertRaisesRegex(ValueError,'UNAVAILABLE_HAS_ERROR'):self.run_report(l)
 def test_partial_form_refused(self):
  l=self.t/'l';l.write_text((P/'synthetic-fit.tsv').read_text().replace('resid_cand','other'))
  with self.assertRaisesRegex(ValueError,'ERROR_FORM'):self.run_report(l)
 def test_verified_flags_do_not_create_inference(self):
  c=self.t/'c';c.write_text(json.dumps({'family_disjoint_verified':True,'family_binding_pin':'fixture','independence_verified':True,'independence_evidence_pin':'fixture'}))
  r=self.run_report(context=c);self.assertTrue(r['independence_bound']);self.assertEqual(r['mode'],'DESCRIPTIVE ONLY')
if __name__=='__main__':unittest.main()
