import unittest,copy
from evaluation_reducer import reduce_rows

def r(i,**kw):
 d=dict(id=i,family='synthetic-A',cohort='validation',kind='glyph',truth='A',predicted='A',status='prediction',confidence=.9,rejected=False);d.update(kw);return d
class T(unittest.TestCase):
 def test_precision_includes_negative_and_recall_all_truth(self):
  a=[r('1'),r('2',kind='negative',truth=None),r('3',status='missing',predicted=None,confidence=None,rejected=None),r('4',rejected=True)]
  c=reduce_rows(a)['cohorts']['validation'];p=c['per_class']['A'];self.assertEqual((p['tp'],p['n_truth'],p['n_predicted_accepted']),(1,3,2));self.assertEqual(p['precision'],.5);self.assertAlmostEqual(p['recall'],1/3);self.assertEqual(c['negative_false_accept'],dict(numerator=1,denominator=1))
 def test_zero_denominator(self):
  p=reduce_rows([r('1',rejected=True)])['cohorts']['validation']['per_class']['A'];self.assertIsNone(p['precision']);self.assertEqual(p['recall'],0)
 def test_cohorts_separate(self):
  o=reduce_rows([r('1'),r('2',cohort='test',family='synthetic-B')]);self.assertEqual(set(o['cohorts']),{'validation','test'})
 def test_overlap_and_duplicate_rejected(self):
  for a in ([r('1'),r('1')],[r('1'),r('2',cohort='test')]):
   with self.assertRaises(ValueError):reduce_rows(a)
 def test_nonmutation(self):
  a=[r('1')];b=copy.deepcopy(a);reduce_rows(a);self.assertEqual(a,b)
 def test_invalid_scores(self):
  for v in (True,float('nan'),float('inf'),-1,2):
   with self.assertRaises(ValueError):reduce_rows([r('1',confidence=v)])
if __name__=='__main__':unittest.main()
