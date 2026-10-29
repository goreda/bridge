import unittest,copy
from qualification_gate import qualify
P='1'*64;C='2'*64;M='3'*64;PRE='4'*64;B='5'*64;POL='6'*64
class T(unittest.TestCase):
 def setUp(self):
  self.p=dict(source_sha256=P,crop_sha256=C,model_sha256=M,preprocess_sha256=PRE,char='A',confidence=.97,rejected=False,pack_refused=False)
  self.c=dict(source_sha256=P,crop_sha256=C,boundary_qualified=True,boundary_evidence_pin=B,policy_pin=POL)
  self.t={POL:dict(model_sha256=M,preprocess_sha256=PRE,eligible_classes=['A'],threshold=.95)}
 def q(self):return qualify(self.p,self.c,self.t)
 def test_positive_qualified_path_required(self):
  self.assertEqual(self.q()['status'],'accepted');self.assertEqual(self.q()['codepoint'],65)
 def test_rejection_not_confidence(self):
  self.p.update(rejected=True,confidence=.99999);self.assertEqual(self.q()['status'],'abstained')
 def test_no_external_self_trust(self):
  self.t={};self.p['trusted']=True;self.assertEqual(self.q()['status'],'abstained')
 def test_source_crop_model_preprocess_binding(self):
  for k in ('source_sha256','crop_sha256','model_sha256','preprocess_sha256'):
   old=self.p[k];self.p[k]='7'*64;self.assertEqual(self.q()['status'],'abstained');self.p[k]=old
 def test_boundary_unknown(self):
  for v in (False,None,'true',1):
   self.c['boundary_qualified']=v;self.assertEqual(self.q()['status'],'abstained')
 def test_below_tier(self):
  self.p['confidence']=.94;self.assertEqual(self.q()['status'],'abstained')
 def test_no_mutation(self):
  a=copy.deepcopy((self.p,self.c,self.t));self.q();self.assertEqual((self.p,self.c,self.t),a)
 def test_malformed_typed_abstention(self):
  for p in (None,{},[],dict(self.p,confidence=float('nan')),dict(self.p,confidence=True),dict(self.p,char='AB')):
   r=qualify(p,self.c,self.t);self.assertEqual(r['status'],'abstained');self.assertIsNone(r['codepoint']);self.assertIsInstance(r['reason'],str)
if __name__=='__main__':unittest.main()
