import unittest,json,copy
from line_geometry_advisory import geometry_hints,note_suffix

def regions():return [dict(line=1,index=i,box=[i*30,200-h,20,h],ink_h=h,kind='whole_glyph',identity_boundary_qualified=True) for i,h in enumerate([60,90]*3)]
class T(unittest.TestCase):
 def test_real_11_all_suppressed(self):
  r=json.loads(open('composition-layout-sample.json').read())['regions'];h=geometry_hints(r)
  self.assertEqual(len(h),11);self.assertTrue(all(x['label']=='unresolved' for x in h));self.assertTrue(all(note_suffix(a,b)=='' for a,b in zip(r,h)))
 def test_xywh_to_endpoints_and_ratio(self):
  r=regions();h=geometry_hints(r);self.assertEqual([x['label'] for x in h],['lower_like','upper_like']*3)
  self.assertAlmostEqual(h[0]['ratio'],2/3);self.assertIn('not case evidence',note_suffix(r[0],h[0]))
 def test_one_bad_boundary_abstains_whole_line(self):
  r=regions();r[0]['kind']='unresolved_span';h=geometry_hints(r);self.assertTrue(all(x['label']=='unresolved' for x in h))
 def test_measured_ink_height_required(self):
  r=regions();del r[0]['ink_h'];self.assertTrue(all(x['label']=='unresolved' for x in geometry_hints(r)))
 def test_single_two_no_hints(self):
  for n in (1,2):self.assertTrue(all(x['label']=='unresolved' for x in geometry_hints(regions()[:n])))
 def test_nonmutation_order(self):
  r=regions()[::-1];before=copy.deepcopy(r);h=geometry_hints(r);self.assertEqual(r,before);self.assertEqual([x['label'] for x in h],['upper_like','lower_like']*3)
 def test_independent_lines_and_missing_line(self):
  r=regions();r.append(dict(box=[0,0,1,1]));h=geometry_hints(r);self.assertEqual(h[-1]['label'],'unresolved');self.assertEqual(h[0]['label'],'lower_like')
 def test_no_unqualified_suffix_even_forged_hint(self):
  self.assertEqual(note_suffix(dict(kind='preserved_component',identity_boundary_qualified=False),dict(label='upper_like',ratio=1)), '')
 def test_invalid_region_and_line_ids_abstain(self):
  for malformed in (None,[],42,'bad',dict(line=[]),dict(line={}),dict(line=True)):
   rr=[malformed];before=copy.deepcopy(rr);h=geometry_hints(rr)
   self.assertEqual(len(h),1);self.assertEqual(h[0]['label'],'unresolved');self.assertEqual(rr,before)
 def test_invalid_references_abstain(self):
  for refs in ([],[1],'bad',True,42,{1:[]},{1:True},{1:{'baseline_y':True,'top_y':0}},{1:{'baseline_y':200,'top_y':False}},{1:{}}):
   rr=regions();before=copy.deepcopy(rr);saved=copy.deepcopy(refs);h=geometry_hints(rr,refs)
   self.assertTrue(all(x['label']=='unresolved' for x in h));self.assertEqual(rr,before);self.assertEqual(refs,saved)
 def test_bool_geometry_rejected(self):
  for k in ('box','ink_h'):
   rr=regions()
   if k=='box':rr[0][k][0]=True
   else:rr[0][k]=False
   before=copy.deepcopy(rr);h=geometry_hints(rr);self.assertTrue(all(x['label']=='unresolved' for x in h));self.assertEqual(rr,before)
 def test_malformed_suffix(self):
  for r,h in ((None,{}),({},None),([],[])):self.assertEqual(note_suffix(r,h),'')
if __name__=='__main__':unittest.main()
