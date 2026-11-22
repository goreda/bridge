import pathlib,subprocess,tempfile,json,sys
root=pathlib.Path(__file__).resolve().parents[2];source=(root/'build.sh').read_text()
mutants=[('old-rename-no-backup-binding','update_pending_old_identity=$(gor_app_identity "$installed_app") || exit 1','update_pending_old_identity=""'),('candidate-rename-no-candidate-binding','update_pending_candidate_identity=$(gor_app_identity "$stage_app") || exit 1','update_pending_candidate_identity=""')]
for name,old,new in mutants:
 assert old in source
 with tempfile.TemporaryDirectory() as td:
  p=pathlib.Path(td);(p/'build.sh').write_text(source.replace(old,new,1))
  r=subprocess.run([sys.executable,str(root/'Tests/UpdateInterruptedSwap/replay.py'),'--source',str(p/'build.sh'),'--output',str(p/'out')],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  report=json.loads((p/'out/report.json').read_text());bad=[x['case'] for x in report['rows'] if x['result']=='FAIL']
  target='interrupt-after-old-rename' if name.startswith('old') else 'interrupt-after-candidate-rename'
  assert r.returncode and target in bad,(name,bad)
  print(name+' mutant rejected by '+target+' PASS')
