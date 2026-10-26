import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from vector_v2 import *
class SyntheticV2(unittest.TestCase):
 def setUp(self):
  self.ctx={'reference_font_sha256':'a'*64,'candidate_font_sha256':'b'*64,'upm':1000,'params':{'grid':0.5,'margin':1},'method':METHOD,'scope':'outlines-only'}
  self.manifest={'schema':MANIFEST,**copy.deepcopy(self.ctx),'codepoints':[65,66]}
  self.rows=[{'codepoint':cp,'path_label':'vector','symmetric_difference_area':0.25,'area_floor':1,'hausdorff':0.1,'distance_floor':0.5} for cp in [65,66]]
  self.measurements={'schema':MEASUREMENT,**copy.deepcopy(self.ctx),'n_a_count':0,'glyphs':copy.deepcopy(self.rows)}
 def build(self):return build_receipt(self.manifest,self.measurements,[65,66],'c'*64)
 def test_pass(self):self.assertEqual(self.build()['status'],'PASS')
 def test_na_never_pass_or_zero(self):
  self.measurements['glyphs'][1]={'codepoint':66,'status':'n/a','reason':'empty outline'};self.measurements['n_a_count']=1
  r=self.build();self.assertEqual(r['status'],'N/A');self.assertEqual(len(r['glyphs']),2);self.assertEqual(len(r['table_rows']),2);self.assertNotIn('hausdorff',r['glyphs'][1])
 def test_numeric_failure_with_na(self):
  self.measurements['glyphs'][0]['hausdorff']=5;self.measurements['glyphs'][1]={'codepoint':66,'status':'n/a','reason':'reader'};self.measurements['n_a_count']=1;self.assertEqual(self.build()['status'],'FAIL')
 def test_duplicate_measurement(self):
  self.measurements['glyphs'][1]=copy.deepcopy(self.measurements['glyphs'][0])
  with self.assertRaises(InputError):self.build()
 def test_missing_and_extra(self):
  for cps in [[65],[65,67]]:
   self.measurements['glyphs']=[dict(self.rows[0],codepoint=c) for c in cps]
   with self.assertRaises(InputError):self.build()
 def test_count_mismatch(self):
  self.measurements['n_a_count']=1
  with self.assertRaises(InputError):self.build()
 def test_each_binding(self):
  for key,value in [('reference_font_sha256','d'*64),('candidate_font_sha256','e'*64),('upm',2000),('params',{'grid':1,'margin':2}),('method','unknown'),('scope','full')]:
   m=copy.deepcopy(self.measurements);m[key]=value
   with self.assertRaises(InputError):build_receipt(self.manifest,m,[65,66],'c'*64)
 def test_v1_rejected(self):
  self.measurements['schema']='kni.vector-measurements.v1'
  with self.assertRaises(InputError):self.build()
 def test_invalid_number_bool_and_nonfinite(self):
  for v in [True,float('nan'),float('inf'),-1]:
   self.measurements['glyphs'][0]['hausdorff']=v
   with self.assertRaises(InputError):self.build()
 def test_na_numeric_field_rejected(self):
  self.measurements['glyphs'][1]={'codepoint':66,'status':'n/a','reason':'empty','hausdorff':0};self.measurements['n_a_count']=1
  with self.assertRaises(InputError):self.build()
 def test_independent_cmap_required(self):
  for cps in [[65],[65,66,66],[65,67]]:
   with self.assertRaises(InputError):build_receipt(self.manifest,self.measurements,cps,'c'*64)
 def test_duplicate_manifest(self):
  self.manifest['codepoints']=[65,65]
  with self.assertRaises(InputError):self.build()
 def test_transport_producer_gate_and_tampering(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t);ref=root/'ref';candidate=root/'candidate';ref.write_bytes(b'synthetic reference byte stream');candidate.write_bytes(b'synthetic candidate byte stream')
   for k,p in [('reference_font_sha256',ref),('candidate_font_sha256',candidate)]:self.manifest[k]=self.measurements[k]=sha(p)
   paths=[root/n for n in ['manifest.json','measurement.json','cmap.json']];objects=[self.manifest,self.measurements,{'schema':'kni.measured-cmap.v2','reference_font_sha256':sha(ref),'codepoints':[65,66]}]
   for p,o in zip(paths,objects):p.write_text(json.dumps(o))
   args=(*paths,ref,candidate);receipt=root/'receipt.json';produce(*args,receipt);self.assertEqual(gate(receipt,*args)['status'],'PASS')
   r=read(receipt);r['status']='FAIL';receipt.write_text(json.dumps(r));self.assertEqual(gate(receipt,*args)['status'],'FAIL')
   produce(*args,receipt);candidate.write_bytes(b'changed');self.assertEqual(gate(receipt,*args)['status'],'FAIL')
 def test_strict_json(self):
  with tempfile.TemporaryDirectory() as t:
   p=Path(t)/'x';
   for text in ['{"x":1,"x":2}','{"x":NaN}','{"x":Infinity}']:
    p.write_text(text)
    with self.assertRaises(InputError):read(p)
if __name__=='__main__':unittest.main()
