import pathlib,subprocess,tempfile,sys
sys.dont_write_bytecode=True
r=pathlib.Path(__file__).resolve().parents[2];sys.path.insert(0,str(r/'Tests/UpdateInterruptedSwap'))
from replay import function
s=(r/'build.sh').read_text();functions=function(s,'gor_app_identity')+function(s,'gor_update_restore_current_swap')
for case in ['existing-unrelated','backup-replaced','running','inspection-failed','symlink-destination','last-promoted']:
 with tempfile.TemporaryDirectory() as td:
  p=pathlib.Path(td);stage=p/'.gor-stage';stage.mkdir();old=stage/'gor.app.last.tmp';old.mkdir();(old/'data').write_text('OLD');candidate=stage/'gor.app';candidate.mkdir();(candidate/'data').write_text('NEW');lock=p/'lock';lock.mkdir()
  setup=''
  if case=='existing-unrelated':setup='mkdir "$installed_app"; printf OTHER > "$installed_app/data"'
  if case=='backup-replaced':setup='mv "$stage_dir/gor.app.last.tmp" "$stage_dir/original"; mkdir "$stage_dir/gor.app.last.tmp"'
  if case=='symlink-destination':setup='ln -s "$stage_app" "$installed_app"'
  if case=='last-promoted':setup='mv "$stage_dir/gor.app.last.tmp" "$stage_dir/gor.app.last"; mv "$stage_app" "$installed_app"'
  probe='printf 123' if case=='running' else 'return 2' if case=='inspection-failed' else ':'
  script=functions+'''\nproject_root="$1"; stage_dir="$1/.gor-stage"; stage_app="$stage_dir/gor.app"; installed_app="$1/gor.app"; build_lock="$1/lock"
printf '%s\\n' $$ > "$build_lock/pid"
update_swap_completed=false; update_swap_token=test; update_stage=test
update_pending_old_identity=$(gor_app_identity "$stage_dir/gor.app.last.tmp")
update_pending_candidate_identity=$(gor_app_identity "$stage_app")
g or_pids() { :; }
'''.replace('g or_pids()', 'gor_pids()')+f'gor_pids() {{ {probe}; }}\n'+setup+'\ngor_update_restore_current_swap\n'
  q=subprocess.run(['bash','-c',script,'test',td],capture_output=True,text=True)
  if case=='last-promoted':assert q.returncode==0 and (p/'gor.app/data').read_text()=='OLD'
  else:
   assert q.returncode!=0,(case,q.stdout,q.stderr)
   if case=='existing-unrelated':assert (p/'gor.app/data').read_text()=='OTHER'
   if case=='symlink-destination':assert (p/'gor.app').is_symlink()
   if case in ['running','inspection-failed']:assert (old/'data').read_text()=='OLD' and not (p/'gor.app').exists()
  print(case+' exact-state refusal/restore PASS')
