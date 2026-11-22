"""Fail any literal build cp source outside the old install set and delivery inventory."""
from pathlib import Path
import ast,re,subprocess,tempfile,shutil,csv,importlib.util
root=Path(__file__).resolve().parents[2];build=(root/'build.sh').read_text()
tracked=ast.literal_eval(re.search(r'^TRACKED = (\[.*\])$',build,re.M)[1])
spec=importlib.util.spec_from_file_location('arch',root/'tools/architecture.py');arch=importlib.util.module_from_spec(spec);spec.loader.exec_module(arch)
# Explicit special installer copies are outside TRACKED but part of the real install set.
assert 'cp -p "$src/gor-selftest.sh" "$project_root/gor-selftest.sh.tmp"' in build
tracked += ['gor-selftest.sh']
delivery={row['path'] for row in csv.DictReader((root/'architecture/delivery.tsv').open(),delimiter='\t')}
paths=[]
for line in build.splitlines():
 for segment in line.split(';'):
  if not re.search(r'\bcp\s',segment):continue
  for rel in re.findall(r'"\$project_root/([^"$]+)"',segment):
   if rel.endswith('.tmp') or rel.startswith('.gor-'):continue
   #191b migration backs up an optional retired file, not an install input.
   if rel=='Sources/gor/ThreeDAxesAcceptance.swift' and not (root/rel).exists():
    assert 'if [ -f "$project_root/'+rel+'" ]; then axes_rb=' in build
    assert 'rm -f "$project_root/'+rel+'"' in build
    assert 'cp -p "$project_root/'+rel+'" "$axes_rb/'+rel+'"' in build
    continue
   assert (root/rel).exists(),('cp source missing',rel)
   assert any(rel==p or rel.startswith(p+'/') for p in tracked),('cp outside install list',rel)
   assert arch.deployed(rel) and rel in delivery,('cp outside delivery gate',rel)
   paths.append(rel)
assert 'tools/gor-periodic-capture.py' in paths
# The prior installer has no knowledge of a new root file. tools/ must reach destination unchanged.
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp);source=p/'source';dest=p/'dest';source.mkdir();dest.mkdir()
 for rel in paths:
  out=source/rel;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/rel,out)
 for item in tracked:
  old=source/item
  if old.is_dir():shutil.copytree(old,dest/item,dirs_exist_ok=True)
  elif old.is_file():shutil.copy2(old,dest/item)
 for rel in paths:assert (dest/rel).read_bytes()==(root/rel).read_bytes()
 assert (dest/'tools/gor-periodic-capture.py').is_file()
print('PASS every literal build cp project source exists in old TRACKED install set + exact delivery; prior install-set replay includes periodic helper')
