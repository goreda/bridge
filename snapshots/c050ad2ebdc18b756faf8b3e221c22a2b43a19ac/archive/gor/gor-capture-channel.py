#!/usr/bin/env python3
"""Block185: Mac-only append-file captures, verified remote ACK, guarded one-time migration."""
import argparse,datetime,hashlib,json,os,subprocess,sys,tempfile,time
from pathlib import Path
BRANCH='gor-capture-mac'
def environment():
    env=os.environ.copy()
    for key in list(env):
        if key.startswith(('GIT_TRACE', 'GIT_TRACE2')) or key in {'GIT_CURL_VERBOSE', 'GIT_TRANSFER_TRACE', 'BASH_ENV', 'ENV', 'SHELLOPTS'}:env.pop(key,None)
    for k in ['GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE']:env.pop(k,None)
    env.update(GIT_PAGER='cat',GIT_TERMINAL_PROMPT='0',GIT_EDITOR='true',GIT_MERGE_AUTOEDIT='no')
    return env
class Channel:
    def __init__(self,repo):self.repo=str(Path(repo).resolve());self.env=environment()
    def git(self,*args,input=None,env=None,check=True):
        p=subprocess.run(['git','-c','core.pager=cat','-C',self.repo,*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env or self.env,timeout=45)
        if check and p.returncode:
            # Transport diagnostics can contain credentials, private hosts and paths.
            # Preserve a useful command class and exit status, never raw argv/stderr.
            verb=args[0] if args and args[0] in {'fetch','push','ls-remote','show','cat-file','rev-parse','update-ref','commit-tree','read-tree','write-tree','hash-object','update-index','diff','rev-list','symbolic-ref','ls-tree','merge-base'} else 'operation'
            raise RuntimeError('git '+verb+' failed (rc='+str(p.returncode)+'); transport details withheld; local state preserved')
        return p
    def text(self,*a):return self.git(*a).stdout.decode().strip()
    def remote_tip(self,branch):
        rows=self.text('ls-remote','--heads','origin','refs/heads/'+branch).splitlines()
        return rows[0].split()[0] if rows else None
    def fetch_tip(self,branch):
        tip=self.remote_tip(branch)
        if tip:
            self.git('fetch','--no-tags','origin','refs/heads/'+branch)
            if self.text('rev-parse','FETCH_HEAD')!=tip:raise RuntimeError('remote changed during fetch')
        return tip
    def send(self,path):
        path=Path(path);data=path.read_bytes();digest=hashlib.sha256(data).hexdigest()
        # Queue metadata stays local. Retries and next update reuse the exact path/bytes.
        stamp=path.stem
        if not __import__('re').fullmatch(r'\d{6}-\d{6}',stamp):raise RuntimeError('capture filename must be yymmdd-hhmmss.txt')
        target='captures/'+stamp+'.txt'
        for attempt in range(3):
            try:
                tip=self.fetch_tip(BRANCH)
            except RuntimeError as fetch_error:
                # A fetch hiccup must not re-block a capture the branch
                # already holds (owner's 15:52 rc=1 drain stop). ls-remote
                # alone names the remote tip, and when its objects are
                # already local (this machine created and pushed them) the
                # byte readback still proves delivery. A genuinely new
                # capture re-raises: without a fetch its upload cannot be
                # verified (fail-closed, unchanged).
                try: remote=self.remote_tip(BRANCH)
                except RuntimeError: raise fetch_error
                if not remote or self.git('cat-file','-e',remote,check=False).returncode: raise fetch_error
                existing=self.git('show',remote+':'+target,check=False)
                if existing.returncode==0 and existing.stdout==data:
                    print('CAPTURE_ACK',remote,target,digest,flush=True);return remote
                raise fetch_error
            if tip:
                existing=self.git('show',tip+':'+target,check=False)
                if existing.returncode==0:
                    if existing.stdout!=data:raise RuntimeError('capture timestamp collision; local bytes retained')
                    print('CAPTURE_ACK',tip,target,digest,flush=True);return tip
            with tempfile.TemporaryDirectory() as d:
                env=self.env.copy();env['GIT_INDEX_FILE']=str(Path(d)/'index')
                self.git('read-tree',tip if tip else '--empty',env=env)
                blob=self.git('hash-object','-w','--stdin',input=data).stdout.decode().strip()
                self.git('update-index','--add','--cacheinfo','100644,'+blob+','+target,env=env)
                tree=self.git('write-tree',env=env).stdout.decode().strip()
                # Full candidate-tree guard: one exact addition, every old entry/mode retained.
                before=self.git('ls-tree','-r','-z',tip).stdout if tip else b''
                after=self.git('ls-tree','-r','-z',tree).stdout
                def entries(raw):return {x.split(b'\t',1)[1]:x.split(b'\t',1)[0] for x in raw.split(b'\0') if x}
                b,a=entries(before),entries(after)
                if set(a)-set(b)!={target.encode()} or set(b)-set(a) or any(a[k]!=v for k,v in b.items()):raise RuntimeError('capture full tree guard failed')
                if a[target.encode()]!=('100644 blob '+blob).encode():raise RuntimeError('capture entry mode/blob mismatch')
                env.update(GIT_AUTHOR_NAME='gor-update',GIT_AUTHOR_EMAIL='gor-update@localhost',GIT_COMMITTER_NAME='gor-update',GIT_COMMITTER_EMAIL='gor-update@localhost')
                args=['commit-tree',tree]+(['-p',tip] if tip else [])
                commit=self.git(*args,input=('gor capture '+stamp+'\n').encode(),env=env).stdout.decode().strip()
                push=self.git('push','origin',commit+':refs/heads/'+BRANCH,check=False)
                if push.returncode:
                    if self.remote_tip(BRANCH)==tip:raise RuntimeError('capture transport failure; queue retained')
                    time.sleep(1+attempt*2);continue # non-FF only: rebuild on new tip.
                ack=self.fetch_tip(BRANCH)
                if ack!=commit:raise RuntimeError('capture ACK differs; queue retained')
                if self.git('show',ack+':'+target).stdout!=data:raise RuntimeError('capture readback bytes differ')
                print('CAPTURE_ACK',ack,target,digest,flush=True);return ack
        raise RuntimeError('capture non-FF retries exhausted; local queue retained')
    def migrate(self,source,queue):
        remote=self.fetch_tip(source)
        if not remote:raise RuntimeError('source branch missing')
        if self.text('symbolic-ref','--short','HEAD')!=source:raise RuntimeError('wrong source branch')
        if self.git('diff','--quiet',check=False).returncode or self.git('diff','--cached','--quiet',check=False).returncode:raise RuntimeError('tracked source changes; migration stopped')
        local=self.text('rev-parse','HEAD');commits=self.text('rev-list','--reverse',remote+'..HEAD').splitlines()
        captures=[]
        for c in commits:
            parents=self.text('rev-list','--parents','-n','1',c).split()[1:];body=self.git('show','-s','--format=%B',c).stdout
            if len(parents)==1 and body.startswith(b'gor-update '):
                if self.text('rev-parse',c+'^{tree}')!=self.text('rev-parse',parents[0]+'^{tree}'):raise RuntimeError('nonempty local source commit')
                captures.append((c,body))
            elif len(parents)==2 and self.text('rev-parse',c+'^{tree}')==self.text('rev-parse',parents[1]+'^{tree}') and self.git('merge-base','--is-ancestor',parents[1],remote,check=False).returncode==0:pass
            else:raise RuntimeError('unrecognized local source history; preserved')
        queue=Path(queue);queue.mkdir(parents=True,exist_ok=True)
        # Recover original commit-message bytes as git exposes them, one append-only file each.
        for c,body in captures:
            subject=body.splitlines()[0].decode();stamp=subject.split()[1]
            out=queue/(stamp+'.txt')
            if out.exists() and out.read_bytes()!=body:raise RuntimeError('local capture collision; preserved')
            out.write_bytes(body);ack=self.send(out)
            (queue/(stamp+'.ack')).write_text(ack+'\n'+hashlib.sha256(body).hexdigest()+'\n')
        if commits:
            # Owner185 explicitly permits this one-time local move ONLY after all capture readbacks.
            # Keep the exact old tip as an additional local ref; never delete history or sidecars.
            self.git('update-ref','refs/gor-preserved/pre185-'+local,local)
            if self.remote_tip(source)!=remote:raise RuntimeError('source changed before migration; retry next update')
            self.git('reset','--keep',remote) # refuses overlapping local edits, untracked files untouched.
        self.git('fetch','origin',source)
        self.git('pull','--ff-only','origin',source)
        print('SOURCE_READY',self.text('rev-parse','HEAD'),flush=True)
def main():
    p=argparse.ArgumentParser();p.add_argument('--repo',required=True);sub=p.add_subparsers(dest='mode',required=True)
    q=sub.add_parser('send');q.add_argument('--file',required=True)
    q=sub.add_parser('update');q.add_argument('--source',required=True);q.add_argument('--queue',required=True)
    a=p.parse_args();ch=Channel(a.repo)
    if a.mode=='send':
        ack=ch.send(a.file)
        # Record the same .ack the drain would write (build.sh result-commit
        # path): the readback above already proved delivery, so the next
        # update's drain skips this file instead of re-sending it. Until
        # this landed, EVERY update re-sent the previous update's capture
        # through the drain - the exact surface the 15:52 rc=1 hit.
        try:
            f=Path(a.file)
            f.with_suffix('.ack').write_text(ack+'\n'+hashlib.sha256(f.read_bytes()).hexdigest()+'\n')
        except OSError: pass
    else:
        ch.migrate(a.source,a.queue)
        for f in sorted(Path(a.queue).glob('*.txt')):
            if not f.with_suffix('.ack').exists():ack=ch.send(f);f.with_suffix('.ack').write_text(ack+'\n')
if __name__=='__main__':
    try:main()
    except (Exception,subprocess.TimeoutExpired) as e:print('CAPTURE/UPDATE_STOP',str(e),file=sys.stderr);sys.exit(1)
