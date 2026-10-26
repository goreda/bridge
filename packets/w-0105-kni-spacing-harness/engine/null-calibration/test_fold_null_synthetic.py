"""Pinned-source synthetic mechanics tests. No real data or policy selection."""
import argparse, csv, hashlib, itertools, json, random, subprocess, tempfile, unittest
from pathlib import Path

P = argparse.ArgumentParser()
P.add_argument('--source-root', type=Path, required=True)
ARGS, REST = P.parse_known_args()
ROOT = ARGS.source_root.resolve()
FOLD = ROOT / 'engine/tooling/component_fold_assign.py'
NULL = ROOT / 'engine/null-calibration/null_calibrate.py'
# Isolate pure helpers without executing the CLI dispatch. Exact source remains
# unchanged; tests bind its full hash, not a hand-copied implementation.
NS = {'__file__': str(NULL), '__name__': 'tested_null_helpers'}
text = NULL.read_text()
exec(compile(text.split('\np = argparse.ArgumentParser(); s =')[0], str(NULL), 'exec'), NS)

class FoldMechanics(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def run_fold(self, records, ratios='dev=1,calibration=1', seed='23', label='a'):
        p = self.root / (label+'.tsv'); out = self.root/(label+'-out.tsv'); rc = self.root/(label+'.json')
        p.write_text('component_id\tsize\n'+''.join(f'{c}\t{s}\n' for c,s in records))
        r = subprocess.run(['python3',str(FOLD),str(p),str(out),str(rc),'--ratios',ratios,'--seed',seed],capture_output=True,text=True)
        return r,out,rc,p
    def test_permutation_manifest_invariance_input_pin_changes(self):
        rows=[('ceA',2),('ceB',1),('ceC',3),('ceD',1)]
        a,ao,ar,ap=self.run_fold(rows,label='a'); b,bo,br,bp=self.run_fold(list(reversed(rows)),label='b')
        self.assertEqual(a.returncode,0,a.stderr);self.assertEqual(b.returncode,0,b.stderr)
        self.assertEqual(ao.read_bytes(),bo.read_bytes())
        self.assertNotEqual(json.loads(ar.read_text())['input_sha256'],json.loads(br.read_text())['input_sha256'])
    def test_largest_deficit_and_tie_order(self):
        r,out,rc,_=self.run_fold([('a',1),('b',1)],ratios='first=1,second=1')
        self.assertEqual(r.returncode,0,r.stderr)
        order=sorted(['a','b'],key=lambda x:hashlib.sha256(('23|'+x).encode()).hexdigest())
        got={x['component_id']:x['fold'] for x in csv.DictReader(out.open(),delimiter='\t')}
        self.assertEqual(got[order[0]],'first');self.assertEqual(got[order[1]],'second')
        receipt=json.loads(rc.read_text());self.assertEqual(receipt['script_sha256'],hashlib.sha256(FOLD.read_bytes()).hexdigest())
    def test_component_weight_stays_atomic(self):
        r,out,rc,_=self.run_fold([('linked',9),('b',1),('c',1),('d',1)])
        self.assertEqual(r.returncode,0,r.stderr)
        rows=list(csv.DictReader(out.open(),delimiter='\t'))
        self.assertEqual(len([x for x in rows if x['component_id']=='linked']),1)
        self.assertEqual(sum(v['size'] for v in json.loads(rc.read_text())['folds'].values()),12)
    def test_invalid_inputs_leave_no_outputs(self):
        cases=[([('x',1),('x',2)],'dev=1,calibration=1','23'),([('',1)],'dev=1','23'),([('x',0)],'dev=1','23'),([('x',1)],'dev=nan','23'),([('x',1)],'dev=0','23'),([('x',1)],'dev=1,dev=1','23'),([('x',1)],'dev=1','bad')]
        for i,(rows,rat,seed) in enumerate(cases):
            r,out,rc,_=self.run_fold(rows,ratios=rat,seed=seed,label=str(i))
            self.assertNotEqual(r.returncode,0);self.assertFalse(out.exists());self.assertFalse(rc.exists())
    def test_insufficient_components(self):
        r,out,rc,_=self.run_fold([('x',1)])
        self.assertNotEqual(r.returncode,0);self.assertIn('INSUFFICIENT_COMPONENTS',r.stderr)
        self.assertFalse(out.exists());self.assertFalse(rc.exists())

class NullMechanics(unittest.TestCase):
    def test_same_arm_placebo_never_improves(self):
        # Synthetic counts are mechanics fixtures, not production settings.
        self.assertFalse(NS['improves']([0.0]*6,20,random.Random(3),.2))
    def test_exact_signflip_preserves_input_and_symmetric_support(self):
        x=[1.0,2.0,4.0];before=x.copy()
        nd,mode=NS['null_signflip'](x,7,10)
        self.assertEqual(x,before);self.assertEqual(mode,'exact');self.assertEqual(len(nd),8)
        expected=sorted(sum(a*b for a,b in zip(s,x))/3 for s in itertools.product([1,-1],repeat=3))
        self.assertEqual(nd,expected);self.assertEqual(nd,sorted(-v for v in nd))
    def test_monte_carlo_fixed_seed_replay(self):
        x=list(range(1,18));a=NS['null_signflip'](x,31,20);b=NS['null_signflip'](x,31,20)
        self.assertEqual(a,b);self.assertEqual(a[1],'monte_carlo');self.assertEqual(len(a[0]),20)
    def test_equal_family_weight_not_pair_weight(self):
        self.assertEqual(NS['fm']({'b':[0]*9,'a':[10]}),[10,0])
        self.assertEqual(NS['st'](NS['fm']({'b':[0]*9,'a':[10]})),5)
    def test_signed_load_explicit_abs_and_input_immutable(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'s.tsv';p.write_text('pair\tfamily\tpartition\tnamespace\tunit\tresid_base\tresid_cand\na\tf1\tfit\tn\tu\t-3\t1\nb\tf2\tfit\tn\tu\t3\t-1\n')
            before=p.read_bytes();fam,ns,un,n=NS['load'](p,('fit',))
            self.assertEqual(fam,{'f1':[-2.0],'f2':[-2.0]});self.assertEqual(p.read_bytes(),before)
            self.assertEqual(NS['ERROR_FORM'],'signed_residual_abs_taken_explicitly')
            p.write_text(p.read_text().replace('\tfit\t','\tdecision\t'))
            with self.assertRaises(SystemExit):NS['load'](p,('fit',))
    def test_lower_tail_tie_handling(self):
        self.assertIsNone(NS['lower_tail_crit']([-1,-1,1,1],.25))
        self.assertEqual(NS['lower_tail_crit']([-1,-1,1,1],.5),-1)

if __name__=='__main__':unittest.main(argv=['test_synthetic_mechanics.py']+REST)
