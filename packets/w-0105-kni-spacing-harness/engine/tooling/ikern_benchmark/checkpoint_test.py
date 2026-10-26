from pathlib import Path
import subprocess, tempfile, shutil, struct, json, hashlib
import argparse, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import benchmark as b
parser=argparse.ArgumentParser()
parser.add_argument('--engine',required=True)
parser.add_argument('--reference',required=True)
parser.add_argument('--out',required=True)
a=parser.parse_args()
BIN=str(Path(a.engine).resolve());out=Path(a.out);out.mkdir(parents=True,exist_ok=False)
reference=Path(a.reference).read_bytes()
if b.digest(reference)!=b.PIN: raise ValueError('reference pin mismatch')
stripped,_=b.strip_reference(reference)
text,_=b.protocol(stripped,.25,set(map(ord,'Hnog')))
wire=str((out/'four-real-glyphs.tsv').resolve());Path(wire).write_text(text)
src=out/'cache'
base=[BIN,wire,'0','auto','4','1']
original=subprocess.run(base,check=True,capture_output=True).stdout
subprocess.run(base+['--context-cache',str(src),'--pair-range','prepare'],check=True,capture_output=True)
for v in ['7:16','0:1','1:7']:
 subprocess.run(base+['--context-cache',str(src),'--pair-range',v],check=True,capture_output=True)
sliced=subprocess.run(base+['--context-cache',str(src),'--pair-range','merge'],check=True,capture_output=True).stdout
assert original==sliced,'default/sliced full TSV mismatch'
(out/'default.tsv').write_bytes(original);(out/'sliced.tsv').write_bytes(sliced)
results=[dict(test='real_four_glyph_default_vs_sliced_full_TSV',sha256=hashlib.sha256(original).hexdigest(),passed=True)]
def call(root,mode='merge',lam='0'):
 return subprocess.run([BIN,wire,lam,'auto','4','1','--context-cache',str(root),'--pair-range',mode],capture_output=True)
def test(name,change,mode='merge',lam='0'):
 with tempfile.TemporaryDirectory() as tmp:
  root=Path(tmp)/'cache';shutil.copytree(src,root);change(root);r=call(root,mode,lam)
  assert r.returncode!=0,(name,r.stdout)
  results.append({'test':name,'exit':r.returncode,'error':r.stderr.decode().strip()})
test('executable_header_mismatch',lambda r:(r/'context.bin').write_bytes((r/'context.bin').read_bytes()[:4]+bytes(32)+(r/'context.bin').read_bytes()[36:]))
test('stale_policy',lambda r:None,lam='1')
test('unknown_schema',lambda r:(r/'context.bin').write_bytes(struct.pack('<I',99)+(r/'context.bin').read_bytes()[4:]))
test('input_mismatch',lambda r:(r/'context.bin').write_bytes((r/'context.bin').read_bytes()[:68]+bytes(32)+(r/'context.bin').read_bytes()[100:]))
test('policy_header_mismatch',lambda r:(r/'context.bin').write_bytes((r/'context.bin').read_bytes()[:100]+bytes(32)+(r/'context.bin').read_bytes()[132:]))
test('source_mismatch',lambda r:(r/'context.bin').write_bytes((r/'context.bin').read_bytes()[:36]+bytes(32)+(r/'context.bin').read_bytes()[68:]))
def corrupt(r):
 p=r/'context.bin';v=bytearray(p.read_bytes());v[-1]^=1;p.write_bytes(v)
test('corrupt_context',corrupt)
test('truncated_context',lambda r:(r/'context.bin').write_bytes(b'x'))
test('trailing_context',lambda r:(r/'context.bin').write_bytes((r/'context.bin').read_bytes()+b'x'))
def oversized(r):
 with (r/'context.bin').open('wb') as f:f.truncate(256*1024*1024+1)
test('file_length_bound',oversized)
test('missing_range',lambda r:next(r.glob('range-*')).unlink())
def duplicate(r):
 p=next(r.glob('range-*'));shutil.copy(p,r/'range-duplicate.bin')
test('duplicate_overlap',duplicate)
def corrupt_range(r):
 p=next(r.glob('range-*'));v=bytearray(p.read_bytes());v[-1]^=1;p.write_bytes(v)
test('range_hash_corrupt',corrupt_range)
test('range_bounds',lambda r:None,mode='0:17')
test('empty_range',lambda r:None,mode='1:1')
test('prepare_never_rebuilds',lambda r:None,mode='prepare')
other=out/'different-executable';other.write_bytes(Path(BIN).read_bytes()+b'CHECKPOINT-EXECUTABLE-CHANGE');other.chmod(0o755)
r=subprocess.run([str(other.resolve()),wire,'0','auto','4','1','--context-cache',str(src),'--pair-range','merge'],capture_output=True)
assert r.returncode!=0,'different executable accepted'
results.append(dict(test='different_actual_executable_refused',exit=r.returncode,error=r.stderr.decode()))
(out/'results.json').write_text(json.dumps(results,indent=2));print('PASS',len(results))
