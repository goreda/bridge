import pathlib,subprocess,tempfile,sys
sys.dont_write_bytecode=True
sys.path.insert(0,str(pathlib.Path(__file__).parent))
from replay import function
root=pathlib.Path(__file__).resolve().parents[2]
source=(root/'build.sh').read_text()
def check(text, mode):
 funcs=''.join(function(text,n) for n in ['gor_pids','gor_app_identity','gor_update_restore_current_swap'])
 with tempfile.TemporaryDirectory() as td:
  p=pathlib.Path(td);(p/'.gor-stage/gor.app.last.tmp').mkdir(parents=True);(p/'.gor-stage/gor.app.last.tmp/old').write_text('OLD');(p/'lock').mkdir()
  script=funcs+'''\nproject_root="$1";stage_dir="$1/.gor-stage";installed_app="$1/gor.app";stage_app="$stage_dir/gor.app";build_lock="$1/lock";app_bundle="$installed_app";app_name=gor;build_uid=1
printf '%s\\n' $$ > "$build_lock/pid"
update_swap_completed=false;update_swap_token=test;update_stage=test
update_pending_old_identity=$(gor_app_identity "$stage_dir/gor.app.last.tmp")
pgrep() {
 case " $* " in
  *" -x "*) printf '123\\n';;
  *) MODE_BODY ;;
 esac
}
ps() { return 2; }
gor_update_restore_current_swap
'''.replace('MODE_BODY',{'present':"printf '123\\n456\\n'",'vanished':"printf '456\\n'",'unknown':'return 2'}[mode])
  q=subprocess.run(['bash','-c',script,'probe',td],capture_output=True,text=True)
  restored=(p/'gor.app/old').exists()
  return q.returncode,restored
for mode in ['present','unknown','vanished']:
 rc,restored=check(source,mode)
 assert (rc==0 and restored) if mode=='vanished' else (rc!=0 and not restored),(mode,rc,restored)
 print('real gor_pids '+mode+' process inspection PASS')
old='live=$(gor_pids --recovery-strict)';assert old in source
rc,restored=check(source.replace(old,'live=$(gor_pids)',1),'present')
assert rc==0 and restored,'strict-inspection mutant not reproduced'
print('non-strict recovery mutant rejected PASS')
# Normal update enumeration still tolerates per-PID inspection failure.
fn=function(source,'gor_pids')
q=subprocess.run(['bash','-c',fn+'\nbuild_uid=1;app_name=gor;app_bundle=/tmp/gor.app;pgrep() { printf "123\\n"; };ps() { return 2; };gor_pids'],capture_output=True,text=True)
assert q.returncode==0 and not q.stdout
print('normal update advisory enumeration unchanged PASS')
