"""Numeric syntax guards at each consumer, synthetic only."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import canonical_table_build as b
from test_canonical_table_negative_paths import Fx
BAD_NUMBER=('1_0',' 1','1 ','+ 1','1\n','١','1e2','inf','nan')
BAD_NATURAL=BAD_NUMBER+('+1','-1','1.0')
class Syntax(unittest.TestCase):
 def test_number_syntax(self):
  for s in BAD_NUMBER:
   with self.assertRaises(b.BuildError):b.number(s)
  for s in ['0','-1','+1','1.5','.5','-.5','+.5']:self.assertEqual(b.number(s),float(s))
  with self.assertRaises(b.BuildError):b.number('9'*400)
 def test_negative_zero_and_oversized_integers_are_typed(self):
  for s in ['-0','-0.0','-.0']:
   with self.assertRaises(b.BuildError):b.number(s)
  self.assertEqual(b.number('0'),0.0);self.assertEqual(b.number('+0'),0.0)
  for call in (b.natural,b.number):
   for v in ['1'+'0'*5000,10**5000]:
    with self.assertRaises(b.BuildError):call(v)
 def test_natural_syntax(self):
  for s in BAD_NATURAL:
   with self.assertRaises(b.BuildError):b.natural(s)
  for s in ['0','001','123']:self.assertEqual(b.natural(s),int(s))
class Consumers(Fx):
 def reject_at(self,mutate,bad=BAD_NUMBER):
  for v in bad:
   self.setUp();mutate(v);self.expect(b.ErrorCode.NUMERIC)
 def test_iou(self):self.reject_at(lambda v:self.edit('components',lambda r:r[0].update(iou=v)))
 def test_nodes_lines_cubics(self):
  for field in ['nodes','lines','cubics']:
   def change(v):
    self.per['columns'][field]=field;rows,h=self.rows('components');h=h if field in h else h+[field]
    for r in rows:r[field]='2'
    rows[0][field]=v;self.write('components',h,rows)
   self.reject_at(change)
 def test_each_diagnostic_sum(self):
  for field in b.SUMS:
   def change(v):
    self.per['columns'][field]=field;rows,h=self.rows('components');h=h+[field]
    for r in rows:r[field]='0'
    rows[0][field]=v;self.write('components',h,rows)
   self.reject_at(change,BAD_NATURAL)
 def test_relative_tolerance(self):self.reject_at(lambda v:self.m['numeric_comparison'].update(relative_tolerance=v))
 def test_absolute_tolerance(self):self.reject_at(lambda v:self.m['numeric_comparison'].update(absolute_tolerance=v))
 def test_compare_left_and_right(self):
  self.reject_at(lambda v:self.edit('perstyle',lambda r:r[0].update(mean_iou=v)))
  # Component side is separately validated in aggregate before comparison.
  self.reject_at(lambda v:self.edit('components',lambda r:r[0].update(iou=v)))
 def test_rows_per_group(self):self.reject_at(lambda v:self.per.update(rows_per_group=v),BAD_NATURAL)
 def test_expected_output_rows(self):self.reject_at(lambda v:self.m.update(expected_output_rows=v),BAD_NATURAL)
 def test_json_numeric_exponent_preserved_for_rejection(self):
  self.save();text=self.manifest.read_text();text=text.replace('"expected_output_rows": 4','"expected_output_rows": 4e0');self.manifest.write_text(text)
  with self.assertRaises(b.BuildError):b.build(self.manifest,self.root)
 def test_current_fixture_passes(self):self.assertEqual(len(self.run_build()),4)
 def test_synthetic_example_still_builds(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t)/'example';subprocess.run([sys.executable,str(Path(__file__).parent/'make_synthetic_example.py'),'--directory',str(root)],check=True)
   self.assertEqual(len(b.build(root/'manifest.json',root)),1)
if __name__=='__main__':unittest.main()
