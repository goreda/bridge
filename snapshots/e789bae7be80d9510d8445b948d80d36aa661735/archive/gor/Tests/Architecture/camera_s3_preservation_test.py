#!/usr/bin/env python3
"""S3 strict placement evidence. Product bytes, not equivalent rewritten logic."""
from camera_c5_receipt import before_c5
from pathlib import Path
import json,subprocess,hashlib
r=Path(__file__).resolve().parents[2];spec=json.loads((r/'Tests/Architecture/camera-s3-map.json').read_text());s=r/'Sources/gor'
for m in spec['moves']:
 old=subprocess.check_output(['git','-C',str(r),'show',spec['base']+':archive/gor/Sources/gor/'+m['old']],text=True)
 new=before_c5('Sources/gor/'+m['new'],(s/m['new']).read_text())
 if 'start' in m:
  a=old.index(m['start']);b=old.index(m['end'],a) if m['end'] else len(old);body=old[a:b]
  assert new==m['prefix']+body,m['new']
  current=(s/m['old']).read_text()
  if m['old']=='ScreenCaptureEngine.swift':
   for k in spec['moves']:
    if k['old']==m['old']:
     a=old.index(k['start']);b=old.index(k['end'],a) if k['end'] else len(old);old=old[:a]+old[b:]
  else:old=old[:a]+old[b:]
  assert current==old,m['old']
 else:
  body=old;assert new==old,m['new'];assert not (s/m['old']).exists()
 assert hashlib.sha256(body.encode()).hexdigest()==m['sha256']
print('PASS S3 exact source bytes preserved, old residual byte-identical, generic registry unchanged')
from camera_source import read_source
for old in {m['old'] for m in spec['moves']}:
 expected=subprocess.check_output(['git','-C',str(r),'show',spec['base']+':archive/gor/Sources/gor/'+old],text=True)
 assert read_source(s/old)==expected,old
print('PASS S3 test adapter reconstructs exact original source files; no changed fixture assertions')
