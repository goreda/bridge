#!/usr/bin/env python3
"""Only promote the exact named-diff candidate with all recorded gates and bundle evidence."""
import argparse,json,subprocess,sys,hashlib
from pathlib import Path
sys.dont_write_bytecode=True
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--candidate',required=True);p.add_argument('--proof',required=True);p.add_argument('--expected-gor',required=True);p.add_argument('--expected-mac',required=True);p.add_argument('--execute',action='store_true');a=p.parse_args()
def git(*v):return subprocess.check_output(['git','-C',a.repo,*v]).decode().strip()
try:
 candidate=git('rev-parse',a.candidate);b=json.loads(Path(a.proof).read_text());baseline=json.loads(Path(__file__).with_name('DELIVERED-BASELINE.json').read_text());assert b['candidate']==candidate,'Proof candidate mismatch'
 assert b['baseline']==baseline['source_commit'],'Delivered baseline mismatch'
 assert b['named_diffs'],'Named diff inventory missing'
 subprocess.run(['git','-C',a.repo,'merge-base','--is-ancestor',b['baseline'],candidate],check=True)
 for gate in ['darwin_compile','manifest_regeneration','updater_integrity','production_preinstall','photon_smoke']:
  r=b[gate];assert r['result']=='PASS' and r['candidate']==candidate,gate+' missing or not exact PASS'
 assert b['updater_integrity']['mismatches']==0,'Updater mismatch'
 # Re-run the built closure checker immediately before the atomic leased push.
 f=b['feature_presence'];checker=Path(__file__).with_name('bundle-feature-gate.py')
 args=[sys.executable,str(checker),'--baseline',str(Path(__file__).with_name('DELIVERED-BASELINE.json')),'--bundle',f['bundle'],'--resources',f['resources'],'--runtime',f['runtime'],'--removals',str(Path(__file__).with_name('REMOVALS.md')),'--out',f['out']]
 subprocess.run(args,check=True)
 refs={'refs/heads/gor/gorav-integration':a.expected_gor,'refs/heads/mac-source-sync-20261103':a.expected_mac}
 live=dict((row.split()[1],row.split()[0])for row in git('ls-remote','origin',*refs).splitlines());assert live==refs,'Remote refs changed; preserve lease'
 command=['git','-C',a.repo,'push','--atomic',*[f'--force-with-lease={ref}:{old}'for ref,old in refs.items()],'origin',*[candidate+':'+ref for ref in refs]]
 if a.execute:subprocess.run(command,check=True);print('Atomic leased push completed; parent must send same-turn owner command/changelog')
 else:print('DRY RUN gates PASS; atomic push not executed')
except (AssertionError,KeyError,ValueError,OSError,subprocess.CalledProcessError)as e:
 print('DELIVERY BLOCKED:',e,file=sys.stderr);raise SystemExit(1)
