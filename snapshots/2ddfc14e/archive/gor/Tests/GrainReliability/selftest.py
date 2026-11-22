#!/usr/bin/env python3
"""Mutation guards for the test, never change production files in place."""
import json, pathlib, shutil, subprocess, sys, tempfile
import reliability as r
scripts=pathlib.Path(sys.argv[1]).resolve(); mpv=sys.argv[2]; out=[]
with tempfile.TemporaryDirectory(prefix='grain-mutants-') as temp:
    root=pathlib.Path(temp)
    for name in ['zero-grain','forget-save','ignore-learned-solve']:
        copy=root/name; shutil.copytree(scripts,copy)
        if name=='zero-grain':
            f=copy/'photon-grain.lua'; s=f.read_text(); needle='return vec4(color.rgb + cg, color.a);'; assert s.count(needle)==1
            f.write_text(s.replace(needle,'return color;'))
        else:
            f=copy/'photon-look-learning.lua'; s=f.read_text()
            needle='return not not os.rename(self.path..\'.tmp\',self.path)' if name=='forget-save' else 'return .5*automatic+.5*target'
            assert s.count(needle)==1
            f.write_text(s.replace(needle,'return true' if name=='forget-save' else 'return automatic'))
        work=root/(name+'-work');work.mkdir();result={'grid':[]};caught=None
        try:
            if name=='zero-grain':r.pixel_grid(mpv,copy,work,result)
            else:
                r.fixtures(work);r.learning_relaunch(mpv,copy,work,result,None)
        except (AssertionError,FileNotFoundError) as e:caught=str(e)
        assert caught is not None,'SURVIVED '+name
        if name=='zero-grain':assert 'P0_ZERO_GRAIN' in caught,caught
        out.append({'mutant':name,'status':'KILLED','reason':caught[:1000]})
cmd=[sys.executable,str(pathlib.Path(r.__file__)), '--scripts',str(scripts),'--mpv','/definitely/missing/mpv']
p=subprocess.run(cmd,capture_output=True,text=True);assert p.returncode==2,(p.returncode,p.stdout,p.stderr)
assert json.loads(p.stdout)['result']=='NOT_RUN'
out.append({'guard':'missing-mpv','status':'PASS','exit':p.returncode})
print(json.dumps(out,indent=2))
