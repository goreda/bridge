from pathlib import Path
import argparse,json,subprocess,sys
p=argparse.ArgumentParser();p.add_argument('--adapter',nargs=argparse.REMAINDER,required=True);a=p.parse_args();root=Path(__file__).resolve().parent
if not a.adapter or not any('{case}' in x for x in a.adapter):p.error('supply a read-only adapter command with {case} placeholder')
results=[]
for case in json.loads((root/'cases.json').read_text()):
 path=root/case['case'];cmd=[x.replace('{case}',str(path)).replace('{product}',str(path.parent/'product')) for x in a.adapter]
 try:
  q=subprocess.run(cmd,capture_output=True,text=True,timeout=15);code=q.returncode;ok=(code==0)==case['expect_zero'];detail=q.stdout+q.stderr
 except subprocess.TimeoutExpired:code=124;ok=False;detail='timeout is not a valid policy refusal'
 results.append({'name':case['name'],'exit':code,'pass':ok,'detail':detail});print(case['name'],code,'PASS' if ok else 'FAIL')
(root/'adapter-results.json').write_text(json.dumps({'synthetic':True,'results':results},indent=2)+'\n');sys.exit(0 if all(x['pass'] for x in results) else 1)
