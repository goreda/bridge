#!/usr/bin/env python3
"""Linux dummy bundle replay of exact updater swap/restore shell functions."""
from pathlib import Path
import argparse,json,hashlib,subprocess,tempfile,importlib.util,os

def function(text,name):
    # Same anchored function extraction as the updater v4 harness.
    import re
    m=re.search(r'^'+re.escape(name)+r'\(\) \{.*?^\}',text,re.M|re.S)
    if not m:raise ValueError('missing '+name)
    return m.group()+'\n'

def tree(root):
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file() and not p.is_symlink()}

def bundle(root,value,sealed=False):
    p=root/'Contents/MacOS/gor';p.parent.mkdir(parents=True);p.write_text(value+' executable fixture\n')
    p=root/'Contents/Info.plist';p.write_text(value+' plist fixture\n')
    p=root/'Contents/Resources/payload.txt';p.parent.mkdir();p.write_text(value+' resource fixture\n')
    if sealed:(p.parent/'vendor').mkdir()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    text=a.source.read_text();names=['gor_pids','stop_running_gor','gor_require_mpv_lifeline','gor_app_identity','gor_swap_install','gor_update_restore_current_swap']
    funcs=''.join(function(text,n) for n in names)
    cases=['normal-swap','postswap-rollback','marker-tamper-refused','backup-replaced-refused','lock-busy-refused','park-collision-refused','install-rename-failure','partial-install-failure','interrupt-after-old-rename','interrupt-after-candidate-rename','sealed-first-run','missing-lifeline-refused']
    rows=[]
    for case in cases:
      with tempfile.TemporaryDirectory(prefix='gor-swap-linux-') as td:
        root=Path(td);project=root/'project';project.mkdir();stage=project/'.gor-stage';stage.mkdir();old=project/'gor.app';new=stage/'gor.app'
        bundle(old,'OLD',case=='sealed-first-run');bundle(new,'NEW');oldhash=tree(old);newhash=tree(new)
        mpv=project/'Resources/vendor/mpv/bin/mpv';mpv.parent.mkdir(parents=True);mpv.write_text('#!/bin/sh\nprintf "%s\\n" " --input-ipc-client fixture"\n');mpv.chmod(0o755)
        if case=='missing-lifeline-refused':mpv.unlink()
        lock=project/'.build-lock';lock.mkdir();status=root/'status.json'
        # Real mv unless the chosen filesystem fault boundary is reached.
        adapter='''mv() {
 if [ "$1" = "$installed_app" ] && [ "$2" = "$stage_dir/gor.app.last.tmp" ] && [ "$CASE" = interrupt-after-old-rename ]; then
  command mv "$@" || return $?
  kill -TERM $$
 fi
 if [ "$1" = "$stage_app" ] && [ "$2" = "$installed_app" ]; then
  if [ "$CASE" = install-rename-failure ]; then return 77; fi
  if [ "$CASE" = partial-install-failure ]; then mkdir -p "$installed_app/Contents"; printf partial > "$installed_app/Contents/partial"; return 78; fi
 fi
 if [ "$1" = "$stage_app" ] && [ "$2" = "$installed_app" ] && [ "$CASE" = interrupt-after-candidate-rename ]; then
  command mv "$@" || return $?
  kill -TERM $$
 fi
 command mv "$@"
}
'''
        command='''set -e
project_root="$1"; stage_dir="$project_root/.gor-stage";stage_app="$stage_dir/gor.app";installed_app="$project_root/gor.app";app_bundle="$installed_app";app_name=gor;build_uid=$(id -u)
build_lock="$project_root/.build-lock";printf '%s\\n' $$ > "$build_lock/pid"
update_mode=true;update_t0=1;update_swap_token="fixture-$$";update_swap_completed=false;update_stage=fixture;update_backup_identity="";update_candidate_identity=""
trap 'exit 143' TERM
command_not_found_handle() { printf 'UNDEFINED:%s\\n' "$1" >&2;return 127; }
'''+funcs+adapter+'''
trap 'rc=$?; trap - EXIT; if [ "$rc" -ne 0 ]; then gor_update_restore_current_swap || true; printf "%s\\n" "$update_restore_detail"; fi; exit "$rc"' EXIT
gor_swap_install
printf 'SWAP_COMPLETED\\n'
case "$CASE" in
 postswap-rollback) gor_update_restore_current_swap ;;
 marker-tamper-refused) printf alien > "$stage_dir/.swap-done";gor_update_restore_current_swap ;;
 backup-replaced-refused) command mv "$stage_dir/gor.app.last" "$stage_dir/original-backup";mkdir "$stage_dir/gor.app.last";gor_update_restore_current_swap ;;
 lock-busy-refused) printf other > "$build_lock/pid";gor_update_restore_current_swap ;;
 park-collision-refused) mkdir "$stage_dir/gor.app.failed-update-$update_swap_token";gor_update_restore_current_swap ;;
esac
printf '%s\\n' "${update_restore_detail:-NO_RESTORE_REQUESTED}"
'''
        proc=subprocess.run(['bash','-c',command,'swap-replay',str(project)],env={**os.environ,'CASE':case},capture_output=True,text=True,timeout=30)
        output=proc.stdout+proc.stderr;(a.output/(case+'.log')).write_text(output)
        installed=tree(old) if old.exists() else None;backup=tree(stage/'gor.app.last') if (stage/'gor.app.last').exists() else None;errors=[]
        if 'UNDEFINED:' in output:errors.append('undefined shell dependency')
        if case in ['normal-swap','sealed-first-run']:
          if proc.returncode!=0 or installed!=newhash:errors.append('new app not installed exactly')
          if case=='normal-swap' and backup!=oldhash:errors.append('old app backup differs')
          if case=='sealed-first-run' and not any(tree(p)==oldhash for p in project.glob('gor.app.instinct-*')):errors.append('sealed app aside missing')
        elif case=='postswap-rollback':
          if proc.returncode!=0 or installed!=oldhash:errors.append('previous app not restored exactly')
          if not any(tree(p)==newhash for p in stage.glob('gor.app.failed-update-*')):errors.append('failed candidate not preserved')
        elif case in ['install-rename-failure','partial-install-failure','interrupt-after-old-rename','interrupt-after-candidate-rename','missing-lifeline-refused']:
          if proc.returncode==0:errors.append('injected interruption/failure not reported')
          if installed!=oldhash:errors.append('old installed app not restored at original path')
          if case=='partial-install-failure' and not list(stage.glob('gor.app.partial-*')):errors.append('partial candidate not preserved')
        else:
          if proc.returncode==0:errors.append('unsafe restore accepted')
          if installed!=newhash:errors.append('current candidate changed on refused restore')
        row={'case':case,'result':'FAIL' if errors else 'PASS','exit':proc.returncode,'errors':errors,'installed_old':installed==oldhash,'installed_new':installed==newhash,'paths':sorted(str(p.relative_to(project)) for p in project.rglob('*')),'bundle_hashes':{'old_expected':oldhash,'new_expected':newhash,'installed':installed,'last':backup,'last_tmp':tree(stage/'gor.app.last.tmp') if (stage/'gor.app.last.tmp').exists() else None},'log_sha256':hashlib.sha256(output.encode()).hexdigest()};rows.append(row);print(json.dumps(row),flush=True)
    report={'result':'FAIL' if any(r['errors'] for r in rows) else 'PASS','build_sha256':hashlib.sha256(text.encode()).hexdigest(),'functions':{n:hashlib.sha256(function(text,n).encode()).hexdigest() for n in names},'rows':rows,'scope':'actual shell swap/restore with dummy app bytes and mpv option fixture; real rename operations; explicit filesystem fault adapter only','not_run':['Darwin signing/build/launch','playback guard','live app termination','top-level update exit reporting/result push','power-loss recovery']}
    (a.output/'report.json').write_text(json.dumps(report,indent=2)+'\n');return int(report['result']!='PASS')
if __name__=='__main__':raise SystemExit(main())
