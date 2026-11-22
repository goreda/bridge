#!/usr/bin/env python3
"""Test-only mutants for the U-G3 assertions. Does not change source checkout."""
import argparse,json,pathlib,shutil,tempfile
from ug3_test import run
p=argparse.ArgumentParser();p.add_argument('--scripts',type=pathlib.Path,required=True);a=p.parse_args();rows=[]
with tempfile.TemporaryDirectory(prefix='ug3-mutants-') as temp:
    for name,old,new in [
      ('restore-additive-resolve','gr_amount = clamp(base_amount * gr_user_ratio,','gr_amount = clamp(base_amount + gr_user_offset,'),
      ('omit-file-load-ratio-reset','    gr_user_ratio = 1.0  -- reset per-file; learned factor is replayed separately','    -- mutant: no ratio reset'),
      ('miss-late-raster-invalidation','        gr_raster_dirty = true','        -- mutant: no raster invalidation')]:
        target=pathlib.Path(temp)/name;shutil.copytree(a.scripts,target);f=target/'photon-grain.lua';s=f.read_text();assert s.count(old)==1,(name,s.count(old));f.write_text(s.replace(old,new))
        rc,r=run(target);assert rc==1,(name,r);rows.append({'mutant':name,'status':'KILLED','failed_cases':[s for s in r['cases']if '\tFAIL\t' in s]})
print(json.dumps(rows,indent=2))
