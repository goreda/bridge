import copy
from dataclasses import replace
from fractions import Fraction
import unittest
from spacing_reference import *
def fixture():return {'schema':SCHEMA,'synthetic':True,'frame':'synthetic-units','target_gap':'20','interaction':'2','glyphs':[{'name':'SyntheticA','ink_width':'50','left_profile':['0'],'right_profile':['0']},{'name':'SyntheticB','ink_width':'60','left_profile':['2'],'right_profile':['2']}]}
class ReferenceTests(unittest.TestCase):
 def test_hand_calculated_matrix_bearings_residual(self):
  model=Model.from_input(fixture());r=model.derive();self.assertEqual(r.gaps,((20,28),(28,20)));self.assertEqual(r.left,(12,12));self.assertEqual(r.right,(12,12));self.assertEqual(r.kern,((-4,4),(4,-4)))
  obj=report(model,r);self.assertEqual(len(obj['pairs']),4);self.assertEqual(obj['status'],'proposed');self.assertNotIn('pass',obj)
 def test_same_model_reconstruction_and_zero_row_column_residual(self):
  obj=fixture();obj['glyphs'][1]['right_profile']=['3'];m=Model.from_input(obj);r=m.derive()
  for i in range(2):
   for j in range(2):self.assertEqual(r.right[i]+r.left[j]+r.kern[i][j],r.gaps[i][j])
  self.assertTrue(all(sum(row)==0 for row in r.kern));self.assertTrue(all(sum(r.kern[i][j] for i in range(2))==0 for j in range(2)))
 def test_independent_kern_input_rejected(self):
  obj=fixture();obj['kern']=[['SyntheticA','SyntheticB',-100]]
  with self.assertRaises(SpacingError):Model.from_input(obj)
 def test_forged_residual_or_cross_model_result_rejected(self):
  m=Model.from_input(fixture());r=m.derive()
  with self.assertRaises(SpacingError):report(m,replace(r,kern=((0,0),(0,0))))
  obj=fixture();obj['target_gap']='21';other=Model.from_input(obj)
  with self.assertRaises(SpacingError):report(other,r)
 def test_parameter_changes_flow_to_same_model(self):
  obj=fixture();a=Model.from_input(obj).derive();obj['interaction']='3';b=Model.from_input(obj).derive();self.assertNotEqual(a.model_sha256,b.model_sha256);self.assertNotEqual(a.left,b.left);self.assertNotEqual(a.kern,b.kern)
 def test_profiles_are_not_semantic_roles(self):
  obj=fixture();obj['glyphs'][0]['role']='accepted'
  with self.assertRaises(SpacingError):Model.from_input(obj)
 def test_duplicate_dimension_negative_and_nonfinite(self):
  mutations=[lambda o:o['glyphs'][1].update(name='SyntheticA'),lambda o:o['glyphs'][1].update(left_profile=['0','1']),lambda o:o.update(target_gap='-1'),lambda o:o.update(interaction='NaN'),lambda o:o['glyphs'][0].update(ink_width='-1')]
  for change in mutations:
   obj=fixture();change(obj)
   with self.assertRaises(SpacingError):Model.from_input(obj)
 def test_zero_residual_single_and_fraction_exact(self):
  obj=fixture();obj['glyphs']=obj['glyphs'][:1];obj['target_gap']='1/3';r=Model.from_input(obj).derive();self.assertEqual(r.kern,((0,),));self.assertEqual(r.left,(Fraction(1,6),))
 def test_no_real_font_contract(self):
  for k,v in [('synthetic',False),('frame','font-units'),('font_path','anything')]:
   obj=fixture();obj[k]=v
   with self.assertRaises(SpacingError):Model.from_input(obj)
class AdapterTests(unittest.TestCase):
 def test_exact_declared_shape_full_matrix_zero_and_format(self):
  m=Model.from_input(fixture());rows,b=declared_adapter(m,m.derive());self.assertEqual(len(rows),4);self.assertEqual(rows[0],{'left':'SyntheticA','right':'SyntheticA','requested':-4.0,'written':-4,'status':'written','reason':''});self.assertEqual((b['value_format1'],b['value_format2']),(4,0));self.assertEqual(b['evidence_class'],'declared')
  o=fixture();o['interaction']='0';m=Model.from_input(o);rows,b=declared_adapter(m,m.derive());self.assertTrue(all(r['written']==0 for r in rows));self.assertEqual(b['counts']['written'],4)
 def test_rounding_positive_negative_ties(self):
  o=fixture();o['interaction']='1/4';m=Model.from_input(o);rows,b=declared_adapter(m,m.derive());self.assertEqual([r['written'] for r in rows],[0,1,1,0]);self.assertTrue(all(r['status']=='written' for r in rows));self.assertEqual(b['counts']['written'],4)
 def test_out_of_int16_rejection_has_reason_no_wrap(self):
  o=fixture();o['interaction']='20000';m=Model.from_input(o);rows,b=declared_adapter(m,m.derive());self.assertTrue(all(r['written'] is None and r['reason']=='residual_out_of_int16' for r in rows));self.assertEqual(b['counts']['rejected'],4)
 def test_boundaries_rounding_and_fraction_receipt(self):
  self.assertEqual(round_half_away(Fraction(-32768)),-32768);self.assertEqual(round_half_away(Fraction(32767)),32767);self.assertEqual(round_half_away(Fraction(-1,2)),-1);self.assertEqual(round_half_away(Fraction(1,2)),1)
  o=fixture();o['interaction']='1/3';m=Model.from_input(o);rows,b=declared_adapter(m,m.derive());self.assertEqual(b['exact_requests'][0]['exact_residual'],{'numerator':0,'denominator':1})
 def test_forged_result_rejected_by_adapter(self):
  m=Model.from_input(fixture())
  with self.assertRaises(SpacingError):declared_adapter(m,replace(m.derive(),kern=((0,0),(0,0))))
 def test_cli_outputs_and_duplicate_key(self):
  import tempfile,json
  from pathlib import Path
  with tempfile.TemporaryDirectory() as t:
   root=Path(t);p=root/'input';p.write_text(json.dumps(fixture()),encoding='utf-8');self.assertEqual(main(['--input',str(p),'--output-dir',str(root/'out')]),0);self.assertTrue((root/'out/declared.json').is_file());self.assertEqual(main(['--input',str(p),'--output-dir',str(root/'out')]),2)
   p.write_text('{"schema":1,"schema":2}',encoding='utf-8');self.assertEqual(main(['--input',str(p),'--output-dir',str(root/'other')]),2);self.assertFalse((root/'other').exists())


class AdapterBoundaryTests(unittest.TestCase):
 def test_actual_adapter_signed_int16_boundaries(self):
  obj=fixture();obj['interaction']='16384';m=Model.from_input(obj);rows,b=declared_adapter(m,m.derive());self.assertEqual([r['written'] for r in rows],[-32768,None,None,-32768]);self.assertEqual(b['counts'],{'written':2,'rounded':0,'rejected':2})
  obj['interaction']='32767/2';m=Model.from_input(obj);rows,b=declared_adapter(m,m.derive());self.assertEqual([r['written'] for r in rows],[-32768,32766,32766,-32768])
 def test_adapter_precision_loss_fails_not_misclassified(self):
  obj=fixture();obj['interaction']='1/'+str(10**400);m=Model.from_input(obj)
  with self.assertRaises(SpacingError):declared_adapter(m,m.derive())


class IntegerBearingTests(unittest.TestCase):
 def test_fractional_reference_vs_integer_residual(self):
  obj=fixture();obj['target_gap']='21/2';obj['interaction']='0';m=Model.from_input(obj);r=m.derive();rows,b=declared_adapter(m,r)
  self.assertEqual(r.left,(Fraction(21,4),)*2);self.assertTrue(all(x['left']==5 and x['right']==5 for x in b['integer_bearings']));self.assertTrue(all(x['requested']==.5 and x['written']==1 for x in rows));self.assertEqual(b['max_abs_realized_gap_error'],{'numerator':1,'denominator':2})
 def test_realized_error_at_most_half_many_metrics(self):
  for target in ['0','1/3','21/2','-0']:
   for interaction in ['0','1/4','1/3','2']:
    o=fixture();o['target_gap']=target;o['interaction']=interaction;m=Model.from_input(o);rows,b=declared_adapter(m,m.derive())
    for row in b['realized_gap_errors']:
     e=row['realized_gap_error'];self.assertIsNotNone(e);self.assertLessEqual(abs(Fraction(e['numerator'],e['denominator'])),Fraction(1,2))
 def test_fractional_ink_rejected_for_integer_advance(self):
  o=fixture();o['glyphs'][0]['ink_width']='1/2';m=Model.from_input(o)
  with self.assertRaises(SpacingError):declared_adapter(m,m.derive())


class InputHardening(unittest.TestCase):
 def test_ascii_rational_grammar(self):
  for value in ['+1',' 1','1 ','1\n','١','１','1e2','1E2','1_0','.5','1.','-1/2','1/-2','NaN','Infinity','', '1/2/3']:
   with self.subTest(value=value):
    with self.assertRaises(SpacingError) as e:rational(value)
    self.assertEqual(e.exception.code,'rational_syntax_invalid')
  for value in ['0','-0','-1','1.25','-1.25','1/2','0/1','001/002']:self.assertEqual(rational(value),Fraction(value))
 def test_length_and_denominator(self):
  self.assertEqual(rational('1'*512),Fraction('1'*512))
  with self.assertRaises(SpacingError) as e:rational('1'*513)
  self.assertEqual(e.exception.code,'rational_text_too_long')
  with self.assertRaises(SpacingError) as e:rational('1/000')
  self.assertEqual(e.exception.code,'rational_denominator_zero')
  self.assertEqual(rational('1/'+str(10**400)),Fraction(1,10**400))
 def test_every_metric_input_rejects_bad_syntax(self):
  for field in ['target_gap','interaction','ink_width','left_profile','right_profile']:
   obj=fixture()
   if field in ('target_gap','interaction'):obj[field]='1e2'
   elif field=='ink_width':obj['glyphs'][0][field]='1e2'
   else:obj['glyphs'][0][field]=['1e2']
   with self.assertRaises(SpacingError) as e:Model.from_input(obj)
   self.assertEqual(e.exception.code,'rational_syntax_invalid')
 def test_names_invalid_duplicate_case_distinct(self):
  for name in ['', ' A','A ','A\n','A\x00','A\x7f','A\u0085','\ud800','A\udfff']:
   obj=fixture();obj['glyphs'][0]['name']=name
   with self.assertRaises(SpacingError) as e:Model.from_input(obj)
   self.assertEqual(e.exception.code,'name_invalid')
  obj=fixture();obj['glyphs'][1]['name']=obj['glyphs'][0]['name']
  with self.assertRaises(SpacingError) as e:Model.from_input(obj)
  self.assertEqual(e.exception.code,'name_duplicate')
  obj=fixture();obj['glyphs'][1]['name']='synthetica';self.assertEqual(len(Model.from_input(obj).derive().glyphs),2)
 def test_derive_once_through_report_and_adapter(self):
  from unittest.mock import patch
  m=Model.from_input(fixture());original=Model.pair_gap;calls=[]
  def counted(self,a,b):calls.append((a.name,b.name));return original(self,a,b)
  with patch.object(Model,'pair_gap',counted):
   r=m.derive();self.assertIs(m.derive(),r);report(m,r);declared_adapter(m,r)
  self.assertEqual(len(calls),4)
 def test_cli_typed_errors_not_generic(self):
  import contextlib,io,json,tempfile
  from pathlib import Path
  with tempfile.TemporaryDirectory() as t:
   root=Path(t);p=root/'input'
   for content,reason in [(b'\xff','utf8_invalid'),(b'{','json_invalid')]:
    p.write_bytes(content);output=io.StringIO()
    with contextlib.redirect_stdout(output):code=main(['--input',str(p),'--output-dir',str(root/'out')])
    self.assertEqual(code,2);self.assertEqual(json.loads(output.getvalue())['reason'],reason)
   obj=fixture();obj['glyphs'][0]['name']='\ud800';p.write_text(json.dumps(obj),encoding='utf-8');output=io.StringIO()
   with contextlib.redirect_stdout(output):code=main(['--input',str(p),'--output-dir',str(root/'out')])
   self.assertEqual(code,2);self.assertEqual(json.loads(output.getvalue())['reason'],'name_invalid');self.assertFalse((root/'out').exists())


class UnicodeNameValidation(unittest.TestCase):
 def test_disallowed_categories_anywhere(self):
  for char in ['\u200b','\u202e','\u2028','\u2029','\u00a0','\u3000','\ue000','\u0378']:
   for name in [char+'A','A'+char+'B','A'+char]:
    with self.subTest(name=repr(name)):
     obj=fixture();obj['glyphs'][0]['name']=name
     with self.assertRaises(SpacingError) as e:Model.from_input(obj)
     self.assertEqual(e.exception.code,'name_invalid')
 def test_internal_ascii_space_is_allowed(self):
  obj=fixture();obj['glyphs'][0]['name']='Synthetic A';self.assertEqual(len(Model.from_input(obj).derive().glyphs),2)
if __name__=='__main__':unittest.main()
