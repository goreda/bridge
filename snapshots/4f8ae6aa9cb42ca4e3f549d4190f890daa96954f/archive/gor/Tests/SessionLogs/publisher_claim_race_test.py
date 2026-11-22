#!/usr/bin/env python3
"""Deterministic first-claim interleavings against the real publisher; no sleeps or retries."""
from pathlib import Path
import types,tempfile
R=Path(__file__).resolve().parents[2]
SOURCE=(R/'tools/bounded_log_archives.py').read_text()
def probe(text,phase):
 m=types.ModuleType('publisher');exec(compile(text,'publisher-under-test','exec'),m.__dict__)
 real=m._owned;once=[False]
 with tempfile.TemporaryDirectory() as td:
  parent=Path(td)
  if phase=='marker':
   def owned(candidate):
    result=real(candidate)
    if not once[0] and candidate.name==m.BASE and not result:
     once[0]=True;m._claim_empty(candidate)
    return result
   m._owned=owned
  else:
   original=m.os.listdir
   def listing(candidate):
    if not once[0] and Path(candidate).name==m.BASE:
     once[0]=True;m._claim_empty(Path(candidate));(Path(candidate)/'.lock').touch()
    return original(candidate)
   m.os=types.SimpleNamespace(**{k:getattr(m.os,k) for k in dir(m.os) if not k.startswith('__')});m.os.listdir=listing
  out=m.publish({'a.txt':b'one'},parent,session='same');again=m.publish({'a.txt':b'two'},parent,session='same')
  return once[0] and out==again and len(list(parent.glob('*-gor-log.zip')))==1 and m.owned_root(parent).name==m.BASE and len([p for p in parent.iterdir() if p.is_dir()])==1
for phase in ['marker','listing']:assert probe(SOURCE,phase),phase
for phase,line in [('marker','                if _owned(candidate):return candidate # another publisher completed its claim\n'),('listing','            if _owned(candidate):return candidate # claim completed after the marker check\n')]:
 assert SOURCE.count(line)==1
 assert not probe(SOURCE.replace(line,''),phase),'surviving '+phase+' mutant'
 print('RED missing-'+phase+'-recheck')
print('PASS two deterministic claim interleavings, same-session one root/one ZIP, two mutants RED; portable only')
