"""Fixture-only safety tests (pure geometry, no fonts, no images). Must pass for any solver.
Accuracy on OFL-rendered lines is measured by the solver with its own harness on calibration/validation families only."""
import unittest,case_resolver as m
def R(h,x=0,base=100): return dict(x0=x,y0=base-h,x1=x+30,y1=base,ink_h=h)
def run(regs,line=None):
    out=m.resolve_line_case(regs,line);assert len(out)==len(regs);return out
class Safety(unittest.TestCase):
    def test_shape_and_labels(self):
        for o in run([R(60),R(90),R(60)]):
            self.assertIn(o['label'],m.LABELS);self.assertEqual(set(o),{'label','ratio','reason'})
            self.assertTrue(o['ratio'] is None or o['ratio']==o['ratio'])
    def test_single_glyph_unresolved(self):
        self.assertEqual(run([R(90)])[0]['label'],'unresolved')
    def test_two_glyphs_without_anchor_unresolved(self):
        self.assertTrue(all(o['label']=='unresolved' for o in run([R(60),R(90,40)])))
    def test_all_same_height_never_forced(self):
        for h in(60,90):
            self.assertTrue(all(o['label']=='unresolved' for o in run([R(h,i*40) for i in range(6)])))
    def test_empty_and_degenerate(self):
        self.assertEqual(run([]),[]);run([dict(x0=0,y0=0,x1=0,y1=0,ink_h=0)])
    def test_no_identity_in_output(self):
        for o in run([R(60),R(90,40),R(60,80)]): self.assertFalse(any(k in o for k in('char','unicode','codepoint')))
    def test_deterministic(self):
        a=[R(60),R(90,40),R(60,80)];self.assertEqual(run(a),run(a))
    def test_positional_reference_geometric_height_order(self):
        # Geometry consistency only: a positional reference and two clusters do NOT prove case.
        o=run([R(60),R(90,40),R(60,80),R(90,120)],dict(baseline_y=100,top_y=10))
        for lab,h in zip((x['label'] for x in o),(60,90,60,90)):
            if lab!='unresolved': self.assertEqual(lab,'lower_like' if h==60 else 'upper_like')
if __name__=='__main__':unittest.main()
