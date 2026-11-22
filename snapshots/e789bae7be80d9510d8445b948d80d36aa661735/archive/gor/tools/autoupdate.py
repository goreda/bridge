#!/usr/bin/env python3
"""190k updater core. Inactive until native permission/lifecycle gates are recorded.

No build.sh hook, launch-agent, RELEASE publisher or background enablement is installed.
All deletions are confined to .gor-autoupdate/staging, .gor-autoupdate/releases/<commit> (neither current nor prev) and the single gor.app.prev.
"""
import argparse,ctypes,contextlib,datetime,fcntl,hashlib,json,os,plistlib,re,shutil,socket,stat,subprocess,sys,time
from pathlib import Path
POLL_SECONDS=3600
HEALTH_SECONDS=30
SHA40=re.compile(r'[a-f0-9]{40}')
TCC_KEYS=('screen_recording','camera','accessibility')
TCC_LINES={'screen_recording':"screen recording permission was reset by macOS; allow gor again in System Settings > Privacy. Automatic updates are disabled; manual updates still work.",'camera':"camera permission was reset by macOS; allow gor again in System Settings > Privacy. Automatic updates are disabled; manual updates still work.",'accessibility':"accessibility permission was reset by macOS; allow gor again in System Settings > Privacy. Automatic updates are disabled; manual updates still work."}
SOURCE_BRANCH='mac-source-sync-20261103'
ORIGINS={'https://github.com/goreda/instinct.git','git@github.com:goreda/instinct.git'}
class Refused(RuntimeError):pass

def require(condition,message):
    if not condition:raise Refused(message)

def parse_release(text):
    pairs={}
    for raw in text.splitlines():
        if not raw.strip():continue
        parts=raw.split(None,1)
        require(len(parts)==2,'malformed RELEASE line')
        key,value=parts
        require(key in {'commit','linux_gates','integrity','prepared_by'} and key not in pairs,'unknown/duplicate RELEASE field')
        pairs[key]=value.strip()
    require(set(pairs)=={'commit','linux_gates','integrity','prepared_by'},'incomplete RELEASE')
    require(bool(re.fullmatch(r'[a-f0-9]{40}',pairs['commit'])),'release commit must be exact SHA40')
    require(pairs['integrity']=='PASS','release integrity not PASS')
    require(bool(re.fullmatch(r'[A-Za-z0-9_.:/,+-]{1,512}',pairs['linux_gates'])),'invalid Linux gate run ids')
    require(bool(re.fullmatch(r'[A-Za-z0-9_.@+-]{1,80}',pairs['prepared_by'])),'invalid preparer')
    return pairs

def atomic_json(path,value):
    path=Path(path);temp=path.with_name(path.name+'.tmp')
    require(not path.is_symlink() and not temp.is_symlink(),'state symlink refused')
    with temp.open('w') as f:
        os.chmod(temp,0o600);json.dump(value,f,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
    os.replace(temp,path)

def read_json(path,default=None):
    require(not Path(path).is_symlink(),'state symlink refused')
    try:return json.loads(Path(path).read_text())
    except FileNotFoundError:return default

def app_tree_sha(app):
    app=Path(app);require(app.is_dir() and not app.is_symlink(),'real app directory required')
    digest=hashlib.sha256()
    for p in sorted(app.rglob('*'),key=lambda p:p.relative_to(app).as_posix().encode()):
        rel=p.relative_to(app).as_posix();mode=p.lstat().st_mode
        if stat.S_ISLNK(mode):
            target=os.readlink(p)
            require(not os.path.isabs(target),'absolute app symlink refused')
            resolved=(p.parent/target).resolve()
            require(resolved==app.resolve() or app.resolve() in resolved.parents,'escaping app symlink refused')
            row=[rel,'link',target]
        elif p.is_file():row=[rel,'file',bool(mode&0o111),hashlib.sha256(p.read_bytes()).hexdigest()]
        elif p.is_dir():row=[rel,'dir']
        else:raise Refused('special app file refused')
        digest.update((json.dumps(row,ensure_ascii=False,separators=(',',':'))+'\n').encode())
    return digest.hexdigest()

def atomic_exchange(left,right):
    """Native same-volume exchange. Never fall back to a rename pair."""
    left,right=Path(left),Path(right)
    require(left.is_dir() and right.is_dir() and left.stat().st_dev==right.stat().st_dev,'same-volume real apps required')
    lib=ctypes.CDLL(None,use_errno=True)
    if sys.platform=='darwin':
        fn=lib.renamex_np;fn.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_uint]
        rc=fn(os.fsencode(left),os.fsencode(right),2) # RENAME_SWAP
    elif sys.platform.startswith('linux'):
        fn=lib.renameat2;fn.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]
        rc=fn(-100,os.fsencode(left),-100,os.fsencode(right),2) # test-only RENAME_EXCHANGE
    else:raise Refused('atomic exchange unavailable')
    if rc:raise OSError(ctypes.get_errno(),'atomic exchange failed')

class Updater:
    def __init__(self,project,sidecar,runner=subprocess.run):
        self.project=Path(project).resolve();self.sidecar=Path(sidecar).resolve();self.run=runner
        require(self.project.is_dir() and self.sidecar.is_dir(),'project and sidecar required')
        self.base=self.project/'.gor-autoupdate';require(not self.base.is_symlink(),'updater root symlink refused')
        self.base.mkdir(mode=0o700,exist_ok=True)
        self.staging=self.base/'staging';self.next=self.project/'gor.app.next';self.app=self.project/'gor.app';self.prev=self.project/'gor.app.prev'
        self.releases=self.base/'releases';self.installed=self.base/'installed.json';self.pollfile=self.base/'poll.json';self.config=self.base/'config.json'
        self.ready=self.project/'.gor-next-ready';self.bad=self.project/'.gor-bad-releases';self.pending=self.base/'launch.json';self.journal=self.base/'swap.json'
        for p in [self.releases,self.installed,self.pollfile,self.config,self.staging,self.next,self.app,self.prev,self.ready,self.bad,self.pending,self.journal]:require(not p.is_symlink(),'managed path symlink refused')
    @contextlib.contextmanager
    def lock(self):
        path=self.project/'.gor-swap.lock';require(not path.is_symlink(),'lock symlink refused')
        with path.open('a') as f:
            try:fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise Refused('another updater operation is active')
            yield
    def command(self,args,**kw):
        result=self.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False,**kw)
        require(result.returncode==0,'subprocess gate failed')
        return result.stdout.decode().strip()
    def git(self,*args):return self.command(['git','-C',str(self.sidecar),*args],timeout=120)
    def fetch_release(self):
        require(self.git('remote','get-url','origin') in ORIGINS,'unexpected source origin')
        self.git('fetch','--no-tags','origin','refs/heads/'+SOURCE_BRANCH)
        tip=self.git('rev-parse','FETCH_HEAD');require(re.fullmatch(r'[a-f0-9]{40}',tip),'invalid source tip')
        release=parse_release(self.git('show',tip+':archive/gor/RELEASE'))
        self.git('merge-base','--is-ancestor',release['commit'],tip)
        return release
    def approved(self,release,requested):
        require(requested==release['commit'],'non-RELEASE commit refused')
        require(requested not in read_json(self.bad,[]),'known bad release refused')
        require(not (self.project/'.gor-build.lock').exists(),'manual build lock present')
    def permission_gate(self):
        record=read_json(self.base/'native-permissions.json',{})
        require(record.get('result')=='PASS' and record.get('screen_recording') is True and record.get('camera') is True and record.get('accessibility') is True,'U7 native permission retention not proven')
        require(record.get('strategy') in ['renamex_np-RENAME_SWAP','atomic-replace'] and record.get('bundle_id')=='com.gokcebalkan.gor','U7 strategy/bundle mismatch')
        require(record.get('mechanics_sha256')==hashlib.sha256(Path(__file__).read_bytes()).hexdigest() and record.get('project')==str(self.project),'U7 mechanics/path changed; bootstrap required')
        require(record.get('helper_sha256')==hashlib.sha256(Path(__file__).with_name('gor-quit-swap.py').read_bytes()).hexdigest(),'U7 helper changed; bootstrap required')
        matrix=record.get('probe_matrix',{})
        require(all(matrix.get(phase,{}).get(probe) is True for phase in ['pre','forward','reverse'] for probe in ['screen_recording','camera','accessibility','lifecycle']),'U7 both-direction functional probes incomplete')
        require(record.get('native_lifecycle_isolated') is True,'U4 same-bundle lifecycle isolation not proven')
        require(record.get('macos')==self.command(['/usr/bin/sw_vers','-productVersion'],timeout=5),'U7 macOS version mismatch')
        return record
    def processes(self):
        if sys.platform=='darwin':
            script="ObjC.import('AppKit'); var a=$.NSRunningApplication.runningApplicationsWithBundleIdentifier('com.gokcebalkan.gor'); var r=[]; for(var i=0;i<a.count;i++){r.push(a.objectAtIndex(i).processIdentifier)}; r.join('\\n')"
            out=self.command(['/usr/bin/osascript','-l','JavaScript','-e',script],timeout=5)
            require(all(x.isdigit() for x in out.splitlines()),'bundle process enumeration failed')
            return [int(x) for x in out.splitlines()]
        text=self.command(['/bin/ps','-axo','pid=,comm='],timeout=5)
        targets={str(p/'Contents/MacOS/gor') for p in [self.app,self.next,self.prev]}
        return [int(parts[0]) for line in text.splitlines() if len(parts:=line.strip().split(None,1))==2 and parts[1] in targets]
    def idle(self,ipc):
        # Missing/uncertain IPC is NOT evidence of idle. Pause with a loaded file is still playback.
        try:
            with socket.socket(socket.AF_UNIX) as s:
                s.settimeout(1);s.connect(str(ipc));s.sendall(b'{"command":["get_property","idle-active"],"request_id":19001}\n')
                data=b''
                while len(data)<16384:
                    chunk=s.recv(4096)
                    if not chunk:break
                    data+=chunk
                    for line in data.splitlines():
                        try:r=json.loads(line)
                        except ValueError:continue
                        if r.get('request_id')==19001:return r.get('error')=='success' and r.get('data') is True
        except (OSError,ValueError):pass
        return False
    def remove_owned_stage(self,path):
        path=Path(path)
        require(path in [self.staging,self.next,self.prev] and not path.is_symlink(),'delete outside explicit updater paths refused')
        if path.exists():shutil.rmtree(path)
    def release_root(self,commit):
        require(bool(SHA40.fullmatch(str(commit))),'release root needs exact SHA40')
        return self.releases/commit
    def remove_release(self,commit):
        """V1.4 exact-path deletion: only <base>/releases/<sha40>, never the current app's or .prev's set."""
        path=self.release_root(commit);require(not self.releases.is_symlink() and not path.is_symlink(),'release path symlink refused')
        keep=set(filter(None,[read_json(self.installed,{}).get('current'),read_json(self.installed,{}).get('prev')]))
        require(commit not in keep,'release resources of current or previous app are kept')
        if path.exists():shutil.rmtree(path)
    def prune_releases(self):
        if not self.releases.is_dir():return []
        ready=read_json(self.ready) if self.ready.exists() else None
        keep=set(filter(None,[read_json(self.installed,{}).get('current'),read_json(self.installed,{}).get('prev'),(ready or {}).get('commit')]));removed=[]
        for child in sorted(self.releases.iterdir()):
            if SHA40.fullmatch(child.name) and child.name not in keep:self.remove_release(child.name);removed.append(child.name)
        return removed
    def resources_ok(self,candidate,commit):
        root=self.release_root(commit);require(root.is_dir() and not root.is_symlink(),'release resource set missing')
        for p in root.rglob('*'):require(not p.is_symlink(),'resource symlink refused')
        marker=Path(candidate)/'Contents/Resources/gor-resource-root'
        require(marker.is_file() and not marker.is_symlink() and marker.read_text().strip()==str(root),'app resource root does not name its release set')
    def static_gates(self,candidate):
        """codesign + one no-UI bootcheck. No second app instance, no UI, no selftest in the owner session."""
        candidate=Path(candidate)
        self.command(['/usr/bin/codesign','--verify','--deep','--strict',str(candidate)],timeout=120)
        self.command([str(candidate/'Contents/MacOS/gor'),'--bootcheck'],timeout=30)
        return {'codesign':'PASS','bootcheck':'PASS'}
    def capture(self,event,commit,ok):
        require(event in ['prepare','swap','revert','launch-good','prepare-failed','permission-regressed'],'unknown updater event')
        # Existing append-only transport; never run source migration or print command output/secrets.
        queue=self.base/'captures';queue.mkdir(exist_ok=True)
        path=queue/(datetime.datetime.now().strftime('%y%m%d-%H%M%S')+'.txt')
        if path.exists():return
        path.write_text('gor-autoupdate event='+event+' commit='+commit+' ok='+str(bool(ok)).lower()+'\n');path.chmod(0o600)
        helper=self.project/'gor-capture-channel.py'
        if helper.is_file():
            try:self.command(['/usr/bin/python3',str(helper),'--repo',str(self.sidecar),'send','--file',str(path)],timeout=180)
            except (Refused,subprocess.SubprocessError):return
            path.unlink()
    def prepare(self,release,requested,builder,*,idle_check=lambda:False,permission_check=None,gates=None):
        with self.lock():
            self.approved(release,requested)
            require(idle_check(),'loaded playback or unknown idle state')
            proof=(permission_check or self.permission_gate)()
            require(not self.ready.exists() and not self.next.exists(),'candidate already staged')
            require(not self.staging.exists(),'incomplete staged files retained for recovery')
            self.staging.mkdir(mode=0o700)
            try:
                built=builder(self.staging,requested,idle_check)
                require(idle_check(),'playback started during preparation')
                candidate=Path(built[0] if isinstance(built,tuple) else built)
                require(self.staging in candidate.resolve().parents,'builder escaped staging')
                self.resources_ok(candidate,requested)
                gate=(gates or self.static_gates)(candidate)
                require(gate.get('codesign')=='PASS' and gate.get('bootcheck')=='PASS','codesign/bootcheck not PASS')
                sha=app_tree_sha(candidate)
                require(candidate.stat().st_dev==self.project.stat().st_dev,'candidate not same-volume')
                os.rename(candidate,self.next)
                atomic_json(self.ready,{'commit':requested,'app_sha256':sha,'gates':gate,'linux_gates':release['linux_gates'],'permission_strategy':proof['strategy'],'changelog':'The new version is ready for the next launch. If it fails to open, the previous version is restored. Rollback: --rollback.','created_at':datetime.datetime.now(datetime.timezone.utc).isoformat()})
                self.capture('prepare',requested,True)
                return read_json(self.ready)
            except Exception:
                # A failed build cannot change current app/project source. Candidate-only deletion.
                self.remove_owned_stage(self.staging)
                if self.next.exists() and not self.ready.exists():self.remove_owned_stage(self.next)
                if self.release_root(requested).exists() and requested not in set(read_json(self.installed,{}).values()):self.remove_release(requested)
                self.capture('prepare-failed',requested,False)
                raise
    def swap(self,*,permission_check=None,running=None):
        with self.lock():
            require(not (running or self.processes)(),'running app: next-launch swap refused')
            require(not (self.project/'.gor-build.lock').exists(),'manual build lock present')
            proof=(permission_check or self.permission_gate)()
            require(proof.get('strategy')=='renamex_np-RENAME_SWAP','atomic-replace strategy not implemented; rename refused')
            data=read_json(self.ready);require(isinstance(data,dict),'no ready candidate')
            require(data['commit'] not in read_json(self.bad,[]),'known bad release refused')
            gate=data.get('gates',{});require(gate.get('codesign')=='PASS' and gate.get('bootcheck')=='PASS','staged codesign/bootcheck evidence required')
            require(app_tree_sha(self.next)==data['app_sha256'],'ready app hash mismatch')
            require(self.app.is_dir() and not self.app.is_symlink(),'prior app required')
            require(self.app.stat().st_dev==self.next.stat().st_dev,'cross-volume swap refused')
            old_sha=app_tree_sha(self.app)
            atomic_json(self.journal,dict(operation='exchange',commit=data['commit'],old_sha256=old_sha,new_sha256=data['app_sha256']))
            # Final check immediately before syscall. Owner relaunch wins.
            require(not (running or self.processes)(),'owner relaunched: candidate waits for next quit')
            atomic_exchange(self.app,self.next)
            # app path never disappears. Only now rotate the single previous app.
            self.remove_owned_stage(self.prev)
            os.rename(self.next,self.prev)
            atomic_json(self.pending,dict(commit=data['commit'],app_sha256=data['app_sha256'],failures=0,started_at=None,good=False,changelog=data['changelog']))
            state=read_json(self.installed,{});atomic_json(self.installed,{'current':data['commit'],'prev':state.get('current')})
            self.ready.unlink();self.journal.unlink();self.capture('swap',data['commit'],True);self.prune_releases()
            return data
    def recover_swap(self,*,running=None):
        # Run before normal launch. Never replace a running process.
        with self.lock():
            require(not (running or self.processes)(),'running app: recovery refused')
            data=read_json(self.journal)
            if not data:return 'no-journal'
            require(self.app.is_dir(),'app path missing: preserve files')
            current=app_tree_sha(self.app)
            if data.get('operation')=='exchange':
                if current==data['old_sha256']:
                    self.journal.unlink();return 'prior-unchanged'
                require(current==data['new_sha256'],'ambiguous exchange: preserve files')
                if self.next.exists():
                    require(app_tree_sha(self.next)==data['old_sha256'],'previous hash mismatch')
                    self.remove_owned_stage(self.prev);os.rename(self.next,self.prev)
                require(self.prev.exists() and app_tree_sha(self.prev)==data['old_sha256'],'previous app absent')
                ready=read_json(self.ready);require(ready and ready['app_sha256']==current,'ready evidence missing')
                atomic_json(self.pending,dict(commit=ready['commit'],app_sha256=current,failures=0,started_at=None,good=False,changelog=ready['changelog']))
                state=read_json(self.installed,{})
                if state.get('current')!=ready['commit']:atomic_json(self.installed,{'current':ready['commit'],'prev':state.get('current')})
                self.ready.unlink();self.journal.unlink();return 'swap-completed'
            if data.get('operation')=='revert':
                if current==data['failed_sha256']:
                    self.journal.unlink();return 'revert-not-started'
                require(current==data['prior_sha256'],'ambiguous revert: preserve files')
                if self.prev.exists():
                    require(app_tree_sha(self.prev)==data['failed_sha256'] and not self.next.exists(),'ambiguous failed candidate')
                    os.rename(self.prev,self.next)
                bad=read_json(self.bad,[])
                if data['commit'] not in bad:bad.append(data['commit'])
                atomic_json(self.bad,bad)
                if self.pending.exists():self.pending.unlink()
                self.journal.unlink();self.capture('revert',data['commit'],True);return 'revert-completed'
            raise Refused('unknown journal mechanics: preserve all files')
    def begin_launch(self,now=None):
        with self.lock():
            data=read_json(self.pending);require(data and not data['good'],'no unqualified launch')
            require(data['started_at'] is None,'previous launch unresolved')
            data['started_at']=time.time() if now is None else now
            # Each launch gets a fresh nonce; an old lifecycle marker cannot qualify a new process.
            data['nonce']=os.urandom(16).hex();atomic_json(self.pending,data);return data
    def good_launch(self,commit,nonce,now=None):
        with self.lock():
            data=read_json(self.pending);now=time.time() if now is None else now
            require(data and data.get('commit')==commit and data.get('nonce')==nonce,'stale lifecycle marker')
            require(data['started_at'] is not None and 0<=now-data['started_at']<=HEALTH_SECONDS,'lifecycle marker outside30s')
            require(app_tree_sha(self.app)==data['app_sha256'],'launched app drift')
            data.update(good=True,failures=0);atomic_json(self.pending,data);self.capture('launch-good',commit,True)
            # docs/GOR-LAST-OWNER-UPDATE.json remains parent-owned: only the first-launch capture is evidence.
            return data['changelog']
    def fail_launch(self,now=None,*,running=None,deterministic=False):
        """deterministic=True: the first-launch fast subset reported a definite FAIL; revert at once, no retry.
        Timeout or crash (deterministic=False): retry once, then revert. Both blacklist the commit."""
        with self.lock():
            require(not (running or self.processes)(),'running app: revert refused')
            data=read_json(self.pending);now=time.time() if now is None else now
            require(data and not data['good'] and data['started_at'] is not None,'no pending launch')
            require(deterministic or now-data['started_at']>=HEALTH_SECONDS,'launch still within health window')
            data['failures']+=1;data['started_at']=None
            if not deterministic and data['failures']<2:atomic_json(self.pending,data);return 'retry-once'
            require(self.prev.is_dir() and not self.prev.is_symlink(),'previous app missing: preserve current')
            require(not self.next.exists(),'candidate slot occupied: preserve current')
            atomic_json(self.journal,dict(operation='revert',commit=data['commit'],failed_sha256=app_tree_sha(self.app),prior_sha256=app_tree_sha(self.prev)))
            require(not (running or self.processes)(),'owner relaunched: revert deferred')
            atomic_exchange(self.app,self.prev)
            os.rename(self.prev,self.next)
            bad=read_json(self.bad,[])
            if data['commit'] not in bad:bad.append(data['commit'])
            atomic_json(self.bad,bad);self.pending.unlink();self.journal.unlink()
            state=read_json(self.installed,{});atomic_json(self.installed,{'current':state.get('prev'),'prev':None})
            self.capture('revert',data['commit'],True);self.prune_releases()
            # Failed release remains in owned staging slot for diagnosis; never retried.
            return 'The new version failed its launch check; the previous version was restored.' if deterministic else 'The new version failed to open twice; the previous version was restored.'

    def bootstrap(self,spawn,*,running=None,own_pid=None):
        """V1.2 forced-quit fallback. Runs before any window. Recovers an interrupted swap, then, if a ready
        candidate exists and no other gor process is alive, hands off to the swap helper and the caller exits."""
        result=self.recover_swap(running=lambda:[p for p in (running or self.processes)() if p!=own_pid])
        if not self.ready.exists():return 'no-ready' if result=='no-journal' else result
        others=[p for p in (running or self.processes)() if p!=own_pid]
        require(not others,'other gor process alive: no swap helper')
        spawn(own_pid);return 'helper-spawned'
    def poll_due(self,now=None,*,at_launch=False):
        now=time.time() if now is None else now;last=read_json(self.pollfile,{}).get('last_poll')
        return last is None or now-last>=POLL_SECONDS
    def poll(self,now=None,*,at_launch=False,remote_tip=None,fetch=None):
        """V1.5: at launch, then every 60 min. Cheap tip check first; the release is fetched only when the tip moved,
        and nothing is prepared when the RELEASE commit equals the last seen one."""
        now=time.time() if now is None else now
        if not at_launch and not self.poll_due(now):return 'not-due'
        state=read_json(self.pollfile,{});state['last_poll']=now
        tip=(remote_tip or (lambda:self.git('ls-remote','origin','refs/heads/'+SOURCE_BRANCH).split()[0]))()
        require(bool(SHA40.fullmatch(tip)),'invalid remote tip')
        if tip==state.get('tip'):atomic_json(self.pollfile,state);return 'unchanged'
        release=(fetch or self.fetch_release)();state['tip']=tip
        new=release['commit']!=state.get('release');state['release']=release['commit'];atomic_json(self.pollfile,state)
        return 'new-release' if new else 'release-unchanged'
    def permission_check_launch(self,states,macos=None):
        """V1.3: compare passive launch states with the recorded baseline. granted->not granted turns auto-update off."""
        require(set(states)>=set(TCC_KEYS) and all(isinstance(states[k],bool) for k in TCC_KEYS),'passive permission states required')
        base=read_json(self.base/'tcc-baseline.json')
        if not base:atomic_json(self.base/'tcc-baseline.json',{'states':{k:states[k] for k in TCC_KEYS},'macos':macos});return {'regressed':[],'enabled':self.enabled()}
        lost=[k for k in TCC_KEYS if base['states'].get(k) is True and states[k] is not True]
        if lost:
            atomic_json(self.config,{'enabled':False,'reason':'permission-regressed','lost':lost});self.capture('permission-regressed','0'*40 if not self.pending.exists() else read_json(self.pending).get('commit','0'*40),False)
            return {'regressed':lost,'enabled':False,'message':TCC_LINES[lost[0]]}
        return {'regressed':[],'enabled':self.enabled()}
    def enabled(self):return read_json(self.config,{}).get('enabled') is True

class NativeBuilder:
    """No production selftest adapter until the architect chooses isolation.

    The current lifecycle harness quits by bundle id, and duplicate app startup
    exits within three seconds. Running it with the shipping bundle id in the
    owner's active login session can quit the owner's app. Do not bypass it by
    changing identity, marking tests PASS, or disabling duplicate protection.
    """
    def __init__(self,updater):self.updater=updater
    @staticmethod
    def validate_bundle_id(bundle_id,production=False):
        require(bundle_id in ['com.gokcebalkan.gor','com.gokcebalkan.gor.staging'],'explicit approved bundle id required')
        require(bundle_id!='com.gokcebalkan.gor' or production,'production bundle id requires explicit --production')
        require(bundle_id=='com.gokcebalkan.gor' or not production,'--production cannot qualify staging')
        return bundle_id
    def isolation_environment(self,worktree,bundle_id):
        self.validate_bundle_id(bundle_id)
        require(bundle_id=='com.gokcebalkan.gor.staging','background isolation requires staging id')
        worktree=Path(worktree).resolve()
        require(self.updater.staging in worktree.parents and worktree.is_dir(),'isolated worktree required')
        require(not (self.updater.project/'.gor-build.lock').exists(),'manual build wins')
        home=worktree/'staged-runtime/home';tmp=worktree/'staged-runtime/tmp'
        # No inherited auth, agent sockets, browser, credential-helper or developer overrides.
        env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LANG':'en_US.UTF-8',
             'HOME':str(home),'CFFIXED_USER_HOME':str(home),'TMPDIR':str(tmp)+'/',
             'GOR_SELFTEST_BUNDLE_ID':bundle_id,'GOR_SELFTEST_STAGED':'1',
             'GOR_VR_TEST_NO_CAMERA':'1','GOR_AUTUPDATE_NO_CREDENTIALS':'1',
             'GOR_SELFTEST_ROOT':str(worktree),'GOR_CAPTURE_DISABLED':'1','GOR_STAGED_PATH_PREFIX':str(worktree/'staged-runtime')}
        for path in [home,tmp,home/'Library/Logs/gor',home/'Library/Application Support/gor',home/'Downloads/gor-bbu',home/'Downloads/gor-repo-sync',home/'captures']:
            require(not path.is_symlink(),'isolation symlink refused');path.mkdir(parents=True,exist_ok=True,mode=0o700)
        return env
    def __call__(self,stage,commit,idle_check):
        raise Refused('native adapter disabled: app global-path and credential-free sandbox enforcement not qualified')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--project',required=True);p.add_argument('--sidecar',required=True)
    p.add_argument('action',choices=['status','fetch-release','selftest-adapter']);p.add_argument('--bundle-id');p.add_argument('--production',action='store_true');a=p.parse_args();u=Updater(a.project,a.sidecar)
    if a.action=='selftest-adapter':
        NativeBuilder.validate_bundle_id(a.bundle_id,a.production)
        NativeBuilder(u)(u.staging,'',lambda:False)
    elif a.action=='fetch-release':print(json.dumps(u.fetch_release(),sort_keys=True))
    else:print(json.dumps({'enabled':False,'poll_seconds':POLL_SECONDS,'ready':u.ready.exists(),'ship_blockers':['native permission baseline captures','owner-run first auto swap','Swift launch integration not compiled/run']},sort_keys=True))
if __name__=='__main__':
    try:main()
    except (Refused,OSError,subprocess.SubprocessError):print('autoupdate refused; prior app preserved',file=sys.stderr);sys.exit(1)
