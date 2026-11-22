#!/usr/bin/env python3
"""Actual collector/publisher zip header proof. Portable only, native NOT_RUN."""
from pathlib import Path
import sys,types,tempfile,json,zipfile,importlib.util
R=Path(__file__).resolve().parents[2];sys.path.insert(0,str(R/'tools'))
import bounded_log_archives as publisher
build=(R/'build.sh').read_text();helper=build.split("<<'GOR_SESSION_HELPER'",1)[1].split('\nGOR_SESSION_HELPER',1)[0]
def run(text):
 ns={};exec(compile(text.split("if sys.argv[1]=='arm':",1)[0],'collector','exec'),ns)
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);res=p/'bundle/Contents/Resources';res.mkdir(parents=True)
  receipt=dict(verification='delivered-tree-installed-bytes',source_commit='a'*40,tree='b'*40,tree_manifest_sha256='c'*64,source_snapshot_sha256='d'*64)
  (res/'build-id.txt').write_text('commit='+'d'*64+'\n');original=publisher.publish
  def pub(entries,**kwargs):return original(entries,p,**kwargs)
  publisher.publish=pub
  try:
   for verified in [True,False]:
    f=res/'gor-build-provenance.json'
    if verified:f.write_text(json.dumps(receipt))
    else:f.unlink()
    for mode in ['initial','live','final']:
     record=dict(id=str(verified)+mode,bundle=str(p/'bundle'),config=str(p/'missing-config'),pid=99999999,identity='non-live',started=1,log_root=None)
     out=ns['archive'](record,mode,final=mode=='final',live=mode=='live')
     with zipfile.ZipFile(out) as z:
      line=z.read('gor-delivery-identity.txt').decode().strip();status=z.read('collection-status.txt').decode().splitlines()[0]
      assert line==status and line.startswith('[GOR-IDENTITY] v1 ')
      if verified:assert 'source_commit='+'a'*40 in line and 'verification=delivered-tree-installed-bytes' in line and 'tree_manifest='+'c'*64 in line
      else:assert 'verification=unverified' in line and 'source_commit=' not in line
  finally:publisher.publish=original
run(helper)
for label,text in [('no-identity-entry',helper.replace("    entries['gor-delivery-identity.txt']=(ident_line+'\\n').encode()",'')),('no-status-header',helper.replace('    status.insert(0,ident_line)',''))]:
 try:run(text)
 except (KeyError,AssertionError):print('RED',label)
 else:raise AssertionError('surviving mutant '+label)
print('PASS 6 actual published zips: verified/unverified x initial/live/final, including no runtime logs; 2 mutants RED; native NOT_RUN')
