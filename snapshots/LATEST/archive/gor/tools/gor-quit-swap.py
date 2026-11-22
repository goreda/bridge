#!/usr/bin/env python3
"""Inactive quit-time swap actor. No application quit hook is installed yet.

Copies its code outside any bundle, waits for exact quit PID to disappear, then
runs the engine's fast preflight and atomic exchange. Never quits an app. Activation stays closed.
"""
import argparse,hashlib,os,shutil,subprocess,sys,tempfile,time
from pathlib import Path
from autoupdate import Updater,Refused,require,atomic_json,read_json

def pid_identity(pid):
    p=subprocess.run(['/bin/ps','-p',str(pid),'-o','lstart='],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5)
    if p.returncode:return None
    return p.stdout.decode().strip() or None

def wait_for_quit(pid,identity,*,probe=pid_identity,sleep=time.sleep,clock=time.monotonic,timeout=120):
    require(isinstance(pid,int) and pid>1 and bool(identity),'exact owner process identity required')
    deadline=clock()+timeout
    while clock()<deadline:
        found=probe(pid)
        if found is None or found!=identity:return True # PID reuse never authorizes signaling
        sleep(.2)
    return False

RELAUNCH=False
def copy_for_reexec(project,sidecar,pid,identity):
    project=Path(project).resolve();base=project/'.gor-autoupdate'
    require(base.is_dir() and not base.is_symlink(),'updater root required')
    # Owned runtime directory is kept for diagnostics; no broad temp cleanup.
    root=Path(tempfile.mkdtemp(prefix='quit-helper-',dir=base));root.chmod(0o700)
    for name in ['gor-quit-swap.py','autoupdate.py']:
        source=Path(__file__).resolve().parent/name;target=root/name
        shutil.copy2(source,target);target.chmod(0o600)
        require(hashlib.sha256(source.read_bytes()).digest()==hashlib.sha256(target.read_bytes()).digest(),'helper copy drift')
    args=[sys.executable,str(root/'gor-quit-swap.py'),'--reexec','--project',str(project),'--sidecar',str(sidecar),'--owner-pid',str(pid),'--owner-start',identity]+(['--relaunch'] if RELAUNCH else [])
    # A re-exec is essential: no Python file or executable remains in a bundle being exchanged.
    os.execv(sys.executable,args)

def after_quit(updater,pid,identity,*,wait=wait_for_quit,running=None,permission_check=None,relaunch=None):
    """Quit-time (or forced-quit fallback) swap. The first launch after the swap is the preflight (190l V1.1):
    no pre-swap probe runs here. Staged codesign + bootcheck evidence is checked inside swap()."""
    require(wait(pid,identity),'owner process still running: candidate waits')
    require(not (running or updater.processes)(),'production bundle still running: candidate waits')
    require(not (updater.project/'.gor-build.lock').exists(),'manual build wins')
    # Permission gate BEFORE any exchange.
    (permission_check or updater.permission_gate)()
    # swap rechecks every production-id process immediately before RENAME_SWAP.
    updater.swap(permission_check=permission_check,running=running)
    if relaunch:
        marker=updater.base/'relaunched.json'
        commit=read_json(updater.pending,{}).get('commit')
        if read_json(marker,{}).get('commit')!=commit: # once per swapped commit
            atomic_json(marker,{'commit':commit});relaunch(updater.app)
    return 'atomic-exchange-complete'

def open_app(app):
    subprocess.Popen(['/usr/bin/open',str(app)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--project',required=True);p.add_argument('--sidecar',required=True)
    p.add_argument('--owner-pid',required=True,type=int);p.add_argument('--owner-start',required=True);p.add_argument('--reexec',action='store_true');p.add_argument('--relaunch',action='store_true');a=p.parse_args()
    global RELAUNCH;RELAUNCH=a.relaunch
    if not a.reexec:copy_for_reexec(a.project,a.sidecar,a.owner_pid,a.owner_start)
    own=Path(__file__).resolve();project=Path(a.project).resolve()
    require(project/'.gor-autoupdate' in own.parents and '.app' not in ''.join(own.parts),'helper must execute outside bundle')
    after_quit(Updater(a.project,a.sidecar),a.owner_pid,a.owner_start,relaunch=open_app if a.relaunch else None)
if __name__=='__main__':
    try:main()
    except (Refused,OSError,subprocess.SubprocessError):print('quit-time updater refused; prior app preserved',file=sys.stderr);sys.exit(1)
