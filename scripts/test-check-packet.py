from pathlib import Path
import subprocess,json,re,tempfile,importlib.machinery
script=str(Path(__file__).with_name('check-packet'));mod=importlib.machinery.SourceFileLoader('gate',script).load_module()
with tempfile.TemporaryDirectory() as t:
 root=Path(t);repo=root/'repo';repo.mkdir()
 def g(*a):return subprocess.check_output(['git','-C',str(repo),*a],text=True).strip()
 g('init','-q');g('config','user.email','fixture@example.invalid');g('config','user.name','fixture');(repo/'base').write_text('base');g('add','.');g('commit','-qm','fixture')
 m=dict(code_owner='fixture',product_repo='fixture/product',product_sha=g('rev-parse','HEAD'),touched_files=[dict(path='base',excerpt_block='source')],interface={k:'fixture' for k in ['signatures','types','ownership_lifetime','caller','callee']},test=dict(command='python3 fixture.py',expected='fixture result',fixture_block='source'),target=dict(branch='fixture',paths=['fixture.py'],return_form='module'),run_recipe=dict(inline_files=[dict(path='fixture.py',block='proof_fixture')]))
 text='```packet-json\n'+json.dumps(m)+'\n```\n```text id=source\nfixture\n```\n'
 for kind,rc in [('module',0),('reproducer',1)]:
  b=text;mm=json.loads(json.dumps(m));b=re.sub(r'```packet-json\n.*?\n```',lambda _:'```packet-json\n'+json.dumps(mm)+'\n```',b,count=1,flags=re.S);b+=f'\n```python id=proof_fixture\nprint("EXPECTED_FIXTURE_RESULT")\nraise SystemExit({rc})\n```\n';p=root/(kind+'.md');p.write_text(b)
  r=subprocess.run(['python3',script,'--run-proof',str(p),str(repo),kind,str(rc),'EXPECTED_FIXTURE_RESULT'],capture_output=True,text=True);print(kind,r.returncode,r.stdout,r.stderr);assert r.returncode==0
  proven=Path(str(p)+'.run-proven.md').read_text();assert not mod.check(proven)
  assert mod.check(proven.replace('EXPECTED_FIXTURE_RESULT','TAMPERED_RESULT',1))
  mutated=json.loads(re.search(r'```packet-json\n(.*?)\n```',proven,re.S)[1]);mutated['run_proof']['exit_code']=17
  bad=re.sub(r'```packet-json\n.*?\n```',lambda _:'```packet-json\n'+json.dumps(mutated)+'\n```',proven,count=1,flags=re.S);assert mod.check(bad)
 assert mod.check(text)
 (repo/'dirty').write_text('dirty')
 r=subprocess.run(['python3',script,'--run-proof',str(p),str(repo),'reproducer','1','EXPECTED_FIXTURE_RESULT'],capture_output=True,text=True);assert r.returncode==1
 print('PASS positive module/reproducer actual execution; tamper and missing-proof negatives')
