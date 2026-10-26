"""Synthetic validation regression tests; no statistical setting selection."""
import argparse, itertools, json, subprocess, tempfile, unittest
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('--source-root', type=Path, required=True)
a,rest=p.parse_known_args(); ROOT=a.source_root.resolve()
NULL=ROOT/'engine/null-calibration/null_calibrate.py'; FOLD=ROOT/'engine/tooling/component_fold_assign.py'
ns={'__file__':str(NULL),'__name__':'edge_helpers'}
exec(compile(NULL.read_text().split('\np = argparse.ArgumentParser(); s =')[0],str(NULL),'exec'),ns)

class EdgeValidation(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.t=Path(self.tmp.name)
        self.inp=self.t/'components.tsv'; self.out=self.t/'manifest.tsv'; self.rc=self.t/'receipt.json'
        self.inp.write_text('component_id\tsize\na\t1\nb\t1\n')
    def tearDown(self): self.tmp.cleanup()
    def fold(self,*flags):
        return subprocess.run(['python3',str(FOLD),str(self.inp),str(self.out),str(self.rc),'--ratios','dev=1,calibration=1','--seed','23',*flags],capture_output=True,text=True)
    def ledger(self,cols,namespace='n',unit='u'):
        f=self.t/'ledger.tsv'; f.write_text('pair\tfamily\tpartition\tnamespace\tunit'+(''.join('\t'+c for c in cols))+'\n'+''.join(f'p{i}\tf{i}\tfit\t{namespace}\t{unit}'+('\t1'*len(cols))+'\n' for i in (1,2)))
        return f
    def test_all_error_column_subsets(self):
        cols=['resid_base','resid_cand','err_abs_base','err_abs_cand']
        good={frozenset(cols[:2]),frozenset(cols[2:])}
        for mask in itertools.product((False,True),repeat=4):
            subset=[c for c,yes in zip(cols,mask) if yes]
            with self.subTest(columns=subset):
                f=self.ledger(subset); before=f.read_bytes()
                if frozenset(subset) in good: self.assertEqual(ns['load'](f,('fit',))[0],{'f1':[0.0],'f2':[0.0]})
                else:
                    with self.assertRaises(SystemExit) as e: ns['load'](f,('fit',))
                    self.assertTrue(str(e.exception).startswith('ERROR_FORM:'))
                self.assertEqual(f.read_bytes(),before)
    def test_empty_and_whitespace_context(self):
        for field in ('namespace','unit'):
            for value in ('',' ','   '):
                with self.subTest(field=field,value=value):
                    f=self.ledger(['resid_base','resid_cand'],**{field:value})
                    before=f.read_bytes()
                    with self.assertRaises(SystemExit) as e: ns['load'](f,('fit',))
                    self.assertTrue(str(e.exception).startswith('EMPTY_CONTEXT:'))
                    self.assertEqual(f.read_bytes(),before)
    def test_nonempty_context_not_normalized(self):
        f=self.ledger(['err_abs_base','err_abs_cand'],namespace=' n ',unit=' u ')
        self.assertEqual(ns['load'](f,('fit',))[1:3],(' n ',' u '))
    def test_existing_manifest_preserved_no_receipt(self):
        self.out.write_bytes(b'KEEP\n');r=self.fold()
        self.assertNotEqual(r.returncode,0);self.assertIn('OUTPUT_EXISTS:',r.stderr)
        self.assertEqual(self.out.read_bytes(),b'KEEP\n');self.assertFalse(self.rc.exists())
    def test_existing_receipt_preserved_no_manifest(self):
        self.rc.write_bytes(b'KEEP RECEIPT\n');r=self.fold()
        self.assertNotEqual(r.returncode,0);self.assertIn('OUTPUT_EXISTS:',r.stderr)
        self.assertEqual(self.rc.read_bytes(),b'KEEP RECEIPT\n');self.assertFalse(self.out.exists())
    def test_both_existing_preserved(self):
        self.out.write_bytes(b'M\n');self.rc.write_bytes(b'R\n');r=self.fold()
        self.assertNotEqual(r.returncode,0);self.assertEqual(self.out.read_bytes(),b'M\n');self.assertEqual(self.rc.read_bytes(),b'R\n')
    def test_dangling_manifest_symlink_refused(self):
        missing=self.t/'missing';self.out.symlink_to(missing);r=self.fold()
        self.assertNotEqual(r.returncode,0);self.assertIn('OUTPUT_EXISTS:',r.stderr)
        self.assertTrue(self.out.is_symlink());self.assertFalse(missing.exists());self.assertFalse(self.rc.exists())
    def test_explicit_overwrite_and_assignment_unchanged(self):
        r=self.fold();self.assertEqual(r.returncode,0,r.stderr)
        old=self.out.read_bytes();self.out.write_bytes(b'OLD');self.rc.write_bytes(b'OLD')
        r=self.fold('--overwrite');self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.out.read_bytes(),old)
        self.assertEqual(json.loads(self.rc.read_text())['components'],2)
    def test_same_output_paths_refused(self):
        self.rc=self.out;r=self.fold('--overwrite')
        self.assertNotEqual(r.returncode,0);self.assertIn('OUTPUT_CONFLICT:',r.stderr);self.assertFalse(self.out.exists())
    def test_output_input_alias_refused(self):
        before=self.inp.read_bytes();self.out=self.inp;r=self.fold('--overwrite')
        self.assertNotEqual(r.returncode,0);self.assertIn('OUTPUT_CONFLICT:',r.stderr)
        self.assertEqual(self.inp.read_bytes(),before);self.assertFalse(self.rc.exists())

if __name__=='__main__':unittest.main(argv=['test_edge_validation.py']+rest)
