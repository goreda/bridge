import unittest,math,case_resolver as m

def r(h,x,b=200):return dict(x0=x,y0=b-h,x1=x+20,y1=b,ink_h=h)
class Extra(unittest.TestCase):
 def test_groups_geometric_only(self):
  regs=[r(h,i*30) for i,h in enumerate([60,90]*3)]
  out=m.resolve_line_case(regs)
  self.assertEqual([o['label'] for o in out],['lower_like','upper_like']*3)
  self.assertTrue(all('not_case_proof' in o['reason'] for o in out))
 def test_rotated_and_uneven(self):
  for bottoms in [[200+i*3 for i in range(6)],[200,220,180]*2]:
   self.assertTrue(all(o['label']=='unresolved' for o in m.resolve_line_case([r(h,i*30,b) for i,(h,b) in enumerate(zip([60,90]*3,bottoms))])))
 def test_flat_and_overlap(self):
  for heights in [[90]*6,[60,65,70,75,80,90],[60,60,60,60,60,90]]:
   self.assertTrue(all(o['label']=='unresolved' for o in m.resolve_line_case([r(h,i*30) for i,h in enumerate(heights)])))
 def test_invalid(self):
  for regs in [[r(float('nan'),0)],[r(float('inf'),0)],[dict(x0=1,y0=1,x1=0,y1=2,ink_h=1)],[{}]]:
   self.assertTrue(all(o['label']=='unresolved' and o['ratio'] is None for o in m.resolve_line_case(regs)))
 def test_scale_translation_order(self):
  a=[r(h,i*30) for i,h in enumerate([60,90]*3)];b=[{k:(v*3+100 if k!='ink_h' else v*3) for k,v in q.items()} for q in a]
  self.assertEqual(m.resolve_line_case(a),m.resolve_line_case(b));self.assertEqual(m.resolve_line_case(a)[::-1],m.resolve_line_case(a[::-1]))
if __name__=='__main__':unittest.main()
