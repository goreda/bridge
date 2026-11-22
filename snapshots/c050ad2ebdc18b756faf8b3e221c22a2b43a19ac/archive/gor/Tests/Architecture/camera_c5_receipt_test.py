#!/usr/bin/env python3
"""Exact C5 receipts only; reject unrelated Camera source drift."""
from pathlib import Path
import subprocess
from camera_c5_receipt import before_c5,CHANGES
r=Path(__file__).resolve().parents[2]
base='408752f7427425c5c55c0fc55cdf6f27f06c8c40'
for rel,(old,new) in CHANGES.items():
 expected=subprocess.check_output(['git','-C',str(r),'show',base+':archive/gor/'+rel],text=True)
 assert expected.count(old)==1
 candidate=expected.replace(old,new,1)
 assert before_c5(rel,expected)==expected
 assert before_c5(rel,candidate)==expected
 for mutant in [candidate+'\n// extra change\n',candidate.replace('generation','wrongGeneration',1),candidate.replace(new,new+' ',1)]:
  assert before_c5(rel,mutant)!=expected,rel
 print('PASS exact allowed C5 change + 3 rejected mutants:',rel)
print('PASS exact C5 receipt normalization; no arbitrary source drift allowed')
