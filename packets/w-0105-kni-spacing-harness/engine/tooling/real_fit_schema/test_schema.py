import copy,json,unittest
from pathlib import Path
from jsonschema import Draft202012Validator
R=Path(__file__).resolve().parent;schema=json.loads((R/'real-fit.schema.json').read_text());v=Draft202012Validator(schema)
class SchemaTests(unittest.TestCase):
 def setUp(self):self.a=json.loads((R/'valid.json').read_text())
 def rejects(self,change):change(self.a);self.assertTrue(list(v.iter_errors(self.a)))
 def test_schema_and_valid(self):Draft202012Validator.check_schema(schema);v.validate(self.a)
 def test_invalid(self):self.assertTrue(list(v.iter_errors(json.loads((R/'invalid.json').read_text()))))
 def test_inference_mode(self):self.rejects(lambda x:x.update(mode='PASS'))
 def test_sealed_verified(self):self.rejects(lambda x:x['context'].update(sealed_membership='VERIFIED'))
 def test_extra_win_column(self):self.rejects(lambda x:x['ledger_rows'][0].update(winner=True))
 def test_unavailable_zero(self):self.rejects(lambda x:x['ledger_rows'][1].update(resid_cand=0))
 def test_partial_error(self):self.rejects(lambda x:x['ledger_rows'][0].pop('resid_base'))
 def test_mixed_absolute(self):self.rejects(lambda x:x['ledger_rows'][0].update(err_abs_base=1))
 def test_available_null(self):self.rejects(lambda x:x['ledger_rows'][0].update(resid_cand=None))
 def test_bad_prediction_pin(self):self.rejects(lambda x:x['predictions'][0]['prediction'].update(query_outline_pins=['not-a-pin']))
 def test_unavailable_reason_missing(self):self.rejects(lambda x:x['predictions'][1]['prediction'].update(unavailable_reason=None))
 def test_i32_overflow(self):self.rejects(lambda x:x['predictions'][0]['prediction'].update(predicted=2147483648))
 def test_boolean_not_text(self):self.rejects(lambda x:x['ledger_rows'][0].update(attempted='true'))
 def test_coverage_inconsistent(self):self.rejects(lambda x:x['ledger_rows'][0].update(paired_available=False))
 def test_capture_tuple_order(self):self.rejects(lambda x:x['capture_outputs'][0].__setitem__(2,0))
 def test_capture_tuple_extra(self):self.rejects(lambda x:x['capture_outputs'][0].append('extra'))
 def test_span_invalid_variant(self):self.rejects(lambda x:x['capture_outputs'][0][0][0]['spans'][0].update(variant='Quadratic'))
 def test_span_missing_end(self):self.rejects(lambda x:x['capture_outputs'][0][0][0]['spans'][0].pop('end'))
 def test_source_commit_identity_not_fixed(self):
  self.a['source_commit']='d'*40;v.validate(self.a)
 def test_source_commit_bad_identity(self):self.rejects(lambda x:x.update(source_commit='not-a-commit'))
if __name__=='__main__':unittest.main()
