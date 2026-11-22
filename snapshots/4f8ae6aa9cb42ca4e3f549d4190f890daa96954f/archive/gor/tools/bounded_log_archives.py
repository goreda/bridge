#!/usr/bin/env python3
"""One bounded timecoded session ZIP in /tmp. Unknown/legacy files are never adopted."""
from pathlib import Path
import datetime, fcntl, hashlib, io, json, os, tempfile, time, zipfile

class LimitReached(OSError): pass

class LimitedFile:
    def __init__(self, file, limit): self.file,self.limit=file,limit
    def write(self, data):
        if self.file.tell()+len(data)>self.limit: raise LimitReached('gor archive byte cap')
        return self.file.write(data)
    def __getattr__(self, key): return getattr(self.file,key)

OWNER='gor-log-archives-v2'
BASE='.gor-log-archives-v2'
def _owned(candidate):
    """True when candidate is a real directory carrying our owner marker."""
    marker=candidate/'.owner'
    if candidate.is_symlink() or not candidate.is_dir() or marker.is_symlink():return False
    try:return marker.read_text()==OWNER
    except OSError:return False
def _claim_empty(candidate):
    """Write the owner marker atomically (content is complete the moment the name exists)."""
    fd,tmp=tempfile.mkstemp(prefix='.owner-',dir=candidate)
    try:
        with os.fdopen(fd,'w') as f:f.write(OWNER);f.flush();os.fsync(f.fileno())
        try:os.link(tmp,candidate/'.owner')
        except FileExistsError:pass
    finally:os.unlink(tmp)
def owned_root(parent,tries=8):
    """Return a private owned archive state directory.
    Reuses an already-owned directory. A directory with no marker is initialized only when it is
    provably empty (a crashed first publish or a wiped state); any other markerless, foreign or
    symlinked directory is left untouched and a fresh private state name is used instead.
    Nothing unknown is deleted or adopted."""
    for i in range(tries):
        candidate=parent/(BASE if i==0 else BASE+'-%d'%i)
        for _ in range(3): # re-examine after losing a race with another publisher
            if candidate.is_symlink():break
            if not os.path.lexists(candidate):
                try:candidate.mkdir(mode=0o700)
                except FileExistsError:continue
            if not candidate.is_dir():break
            if _owned(candidate):return candidate
            if (candidate/'.owner').exists() or (candidate/'.owner').is_symlink():
                if _owned(candidate):return candidate # another publisher completed its claim
                break # wrong marker: foreign
            try:entries=os.listdir(candidate)
            except OSError:break
            if all(e.startswith('.owner-') for e in entries): # empty, or only a racing publisher's marker scratch
                try:_claim_empty(candidate)
                except OSError:continue
                if _owned(candidate):return candidate
                continue
            if _owned(candidate):return candidate # claim completed after the marker check
            break # non-empty without a marker: unproven, never adopted
    raise LimitReached('no private archive state available; unknown directories preserved')

def publish(entries, parent=None, *, session=None, started=None, cap=64*1024*1024, per_file=16*1024*1024, count=16):
    parent=Path(parent) if parent is not None else Path('/tmp').resolve()
    parent.mkdir(mode=0o700,parents=True,exist_ok=True)
    if parent.is_symlink():raise LimitReached('unsafe log destination directory')
    root=owned_root(parent);marker=root/'.owner'
    lock=os.open(root/'.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
    temporary=None
    try:
        fcntl.flock(lock,fcntl.LOCK_EX)
        receipt=root/'current.json'
        if receipt.is_symlink():raise LimitReached('unsafe archive receipt')
        old=json.loads(receipt.read_text()) if receipt.exists() else None
        session=session or str(time.time_ns());started=started if started is not None else time.time()
        previous=None
        if old:
            if Path(old['name']).name!=old['name']:raise LimitReached('unsafe archive name')
            previous=parent/old['name']
            if previous.is_symlink():raise LimitReached('unsafe owned archive')
            if previous.exists():
                st=previous.stat()
                if (st.st_dev,st.st_ino,st.st_size)!=(old['dev'],old['ino'],old['size']) or hashlib.sha256(previous.read_bytes()).hexdigest()!=old['sha256']:raise LimitReached('owned archive changed; preserved')
            else:previous=None
            if session!=old['session'] and started<old['started']:return str(parent/old['name'])
        if old and session==old['session']:
            output=parent/old['name']
        else:
            while True:
                output=parent/(datetime.datetime.now().strftime('%y%m%d-%H%M%S')+'-gor-log.zip')
                if not os.path.lexists(output):break
                time.sleep(1)
        # Build/CRC in bounded memory before touching the last valid ZIP.
        raw=io.BytesIO()
        with zipfile.ZipFile(LimitedFile(raw,min(per_file,cap//2)),'w',zipfile.ZIP_DEFLATED) as z:
            for key,data in entries.items():z.writestr(key,data)
        data=raw.getvalue()
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            if z.testzip() is not None:raise OSError('archive CRC failure')
        # Hidden transaction scratch is not another ZIP or an alias. The only
        # published ZIP keeps its name for this session, even during playback.
        fd,path=tempfile.mkstemp(prefix='.pending-',dir=root);temporary=Path(path)
        with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
        if previous and previous!=output:
            previous.rename(output) # exactly one published ZIP throughout session rollover
        os.replace(temporary,output);temporary=None
        st=output.stat();identity=dict(name=output.name,session=session,started=started,dev=st.st_dev,ino=st.st_ino,size=st.st_size,sha256=hashlib.sha256(data).hexdigest())
        fd,path=tempfile.mkstemp(prefix='.receipt-',dir=root);temporary=Path(path)
        with os.fdopen(fd,'w') as f:json.dump(identity,f)
        os.replace(temporary,receipt);temporary=None
        print('GOR-LOG-ZIP path='+str(output),flush=True)
        return str(output)
    finally:
        if temporary:temporary.unlink(missing_ok=True)
        fcntl.flock(lock,fcntl.LOCK_UN);os.close(lock)


def publish_player(entries,parent,*,session,started,cap=64*1024*1024,per_file=16*1024*1024,count=16):
    """Immutable per-player completion ZIPs. No sibling rename or deletion.
    Reservations make crash recovery count against the same existing limits.
    The shared flock protects a short commit transaction, not close ordering.
    """
    import re
    if not re.fullmatch('[0-9a-f]{32}',session):raise LimitReached('invalid player token')
    parent=Path(parent).resolve();root=owned_root(parent)
    lock=os.open(root/'.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
    scratch=None
    def syncdir(path):
        fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|getattr(os,'O_DIRECTORY',0))
        try:os.fsync(fd)
        finally:os.close(fd)
    def save(path,value):
        fd,tmp=tempfile.mkstemp(prefix='.player-receipt-',dir=root)
        try:
            with os.fdopen(fd,'w') as f:json.dump(value,f);f.flush();os.fsync(f.fileno())
            os.replace(tmp,path);syncdir(root)
        finally:
            if os.path.exists(tmp):os.unlink(tmp)
    try:
        fcntl.flock(lock,fcntl.LOCK_EX)
        receipt=root/('player-'+session+'.json')
        identities=[]
        for path in list(root.glob('player-*.json'))+[root/'current.json']:
            if not os.path.lexists(path):continue
            if path.is_symlink():raise LimitReached('unsafe player archive receipt')
            item=json.loads(path.read_text());name=item.get('name','')
            if not name or Path(name).name!=name:raise LimitReached('invalid player archive name')
            output=parent/name
            if os.path.lexists(output):
                st=output.lstat()
                import stat
                if not stat.S_ISREG(st.st_mode) or st.st_nlink!=1:raise LimitReached('unsafe player archive')
                if st.st_size!=item['size'] or hashlib.sha256(output.read_bytes()).hexdigest()!=item['sha256']:raise LimitReached('player archive changed; preserved')
            elif item.get('phase')!='reserved':
                # Owner moved/deleted a published output. Its metadata is not
                # permission to delete anything else; release only this slot.
                if path==receipt:raise LimitReached('published player archive missing')
                continue
            identities.append((path,item))
        raw=io.BytesIO()
        with zipfile.ZipFile(LimitedFile(raw,min(per_file,cap//2)),'w',zipfile.ZIP_DEFLATED) as z:
            for key,blob in entries.items():
                if Path(key).name!=key or key.startswith('.'):raise LimitReached('unsafe ZIP member')
                info=zipfile.ZipInfo(key,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
                z.writestr(info,blob)
        data=raw.getvalue();digest=hashlib.sha256(data).hexdigest()
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            if z.testzip() is not None:raise OSError('archive CRC failure')
        previous=next((i for p,i in identities if p==receipt),None)
        if previous:
            if previous['size']!=len(data) or previous['sha256']!=digest:raise LimitReached('player ZIP is immutable')
            output=parent/previous['name']
            if output.exists():
                previous['phase']='published';save(receipt,previous)
                return str(output)
            identity=previous
        else:
            if len(identities)>=count or sum(i['size'] for _,i in identities)+len(data)>cap:raise LimitReached('player archive store full; preserved')
            # Microseconds plus the full immutable token prevents equal-clock
            # completions from sharing a name. O_EXCL link below is final proof.
            name=datetime.datetime.now().strftime('%y%m%d-%H%M%S-%f')+'-'+session+'-gor-log.zip'
            output=parent/name
            if os.path.lexists(output):raise LimitReached('player archive destination exists')
            identity=dict(name=name,session=session,started=started,size=len(data),sha256=digest,phase='reserved')
            save(receipt,identity)
        fd,tmp=tempfile.mkstemp(prefix='.player-pending-',dir=root);scratch=Path(tmp)
        with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
        os.link(scratch,output) # no replacement of an existing file, ever
        scratch.unlink();scratch=None;syncdir(parent)
        identity['phase']='published';save(receipt,identity)
        print('GOR-LOG-ZIP path='+str(output),flush=True)
        return str(output)
    finally:
        if scratch:scratch.unlink(missing_ok=True)
        fcntl.flock(lock,fcntl.LOCK_UN);os.close(lock)


def publish_199bi(entries,parent,*,identity,token,complete,cap=64*1024*1024,per_file=16*1024*1024,delivery_parent=Path('/tmp')):
    """199bi only: token-owned immutable outputs, bounded head/tail, oldest retention.
    The registry is the ownership proof. Unknown ZIPs are never deleted.
    """
    import re,stat
    if not re.fullmatch(r'[0-9]{8}-[0-9]{6}-[a-f0-9]{4}',identity):raise LimitReached('invalid player id')
    parent=Path(parent);parent.mkdir(parents=True,mode=0o700,exist_ok=True)
    if parent.is_symlink():raise LimitReached('unsafe archive destination')
    root=owned_root(parent);lock=os.open(root/'.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
    scratch=None;stage='archive-admission'
    def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
    def write_receipt(path,value):
        fd,tmp=tempfile.mkstemp(prefix='.bi-receipt-',dir=root)
        try:
            with os.fdopen(fd,'w') as f:json.dump(value,f);f.flush();os.fsync(f.fileno())
            os.replace(tmp,path)
        finally:
            if os.path.exists(tmp):os.unlink(tmp)
    delivery_parent=Path(delivery_parent)
    delivery=delivery_parent/('gor-logs-'+identity[:15]+'-'+identity+'.zip')
    def enforce_budget(current,reserve=0):
        # Conservative logical byte budget across both locations, under the
        # SAME existing publisher lock. No hardlinks: old single-link ownership
        # validation remains valid. Unknown files count but are never removed.
        owned=[];known=set()
        for rp in root.glob('????????-??????-????.json'):
            p=parent/(rp.stem+'.zip')
            try:
                if rp.is_symlink():continue
                v=json.loads(rp.read_text());paths=[]
                expected=[p]
                if v.get('delivery')==str(delivery_parent/('gor-logs-'+rp.stem[:15]+'-'+rp.stem+'.zip')):
                    expected.append(Path(v['delivery']))
                for q in expected:
                    if not os.path.lexists(q):continue
                    st=q.lstat()
                    if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or st.st_size!=v['size'] or digest(q)!=v['sha256']:raise ValueError('changed')
                    paths.append((q,st.st_size))
                known.update(q for q,_ in paths)
                closed=v.get('closed',0)
                owned.append((closed if isinstance(closed,(int,float)) and not isinstance(closed,bool) else 0,paths,rp))
            except (OSError,ValueError,KeyError,TypeError):continue
        universe=set(parent.glob('*.zip'))|set(delivery_parent.glob('gor-logs-*.zip'))
        foreign=sum(p.lstat().st_size for p in universe if p not in known)
        total=sum(size for _,paths,_ in owned for _,size in paths)+foreign+reserve
        for _,paths,rp in sorted(owned,key=lambda x:(x[0],x[2].name)):
            if total<=cap:break
            if any(p==current for p,_ in paths):continue
            for p,size in paths:p.unlink();total-=size
            rp.unlink()
        if total>cap:raise LimitReached('archive budget occupied by unowned outputs; preserved')
    def deliver(data,receipt,value):
        nonlocal scratch,stage
        if delivery.is_symlink():raise LimitReached('unsafe delivery output')
        if os.path.lexists(delivery):
            st=delivery.lstat()
            if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or st.st_size!=len(data) or digest(delivery)!=hashlib.sha256(data).hexdigest():raise LimitReached('delivery collision')
            return
        stage='delivery-copy-write'
        fd,tmp=tempfile.mkstemp(prefix='.bi-copy-',dir=delivery_parent);scratch=Path(tmp)
        with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
        stage='delivery-publish-link'
        os.link(scratch,delivery);scratch.unlink();scratch=None
        for folder in (parent,delivery_parent):
            fd=os.open(folder,os.O_RDONLY|getattr(os,'O_DIRECTORY',0))
            try:os.fsync(fd)
            finally:os.close(fd)
    try:
        fcntl.flock(lock,fcntl.LOCK_EX)
        receipt=root/(identity+'.json');output=parent/(identity+'.zip')
        if receipt.is_symlink() or output.is_symlink():raise LimitReached('unsafe player output')
        if receipt.exists():
            old=json.loads(receipt.read_text())
            if old['token']!=token:raise LimitReached('player output identity collision')
            if output.exists():
                if output.stat().st_size!=old['size'] or digest(output)!=old['sha256']:raise LimitReached('player output changed')
                # Retry can finish a missing mirror, without regenerating ZIP bytes.
                missing=not os.path.lexists(delivery)
                enforce_budget(output,old['size'] if missing else 0)
                old['delivery']=str(delivery);write_receipt(receipt,old)
                deliver(output.read_bytes(),receipt,old)
                enforce_budget(output)
                return str(output)
        elif os.path.lexists(output):raise LimitReached('unowned player output exists')
        payload=dict(entries);notes={};budget=per_file
        while True:
            raw=io.BytesIO()
            try:
                with zipfile.ZipFile(LimitedFile(raw,per_file),'w',zipfile.ZIP_DEFLATED) as z:
                    for name,blob in payload.items():
                        if Path(name).name!=name or name.startswith('.'):raise LimitReached('unsafe member')
                        z.writestr(name,blob)
                    z.writestr('TRUNCATION.txt','\n'.join('TRUNCATED %d bytes %s'%(n,k) for k,n in sorted(notes.items())) or 'No archive-size truncation')
                    z.writestr('STATUS.json',json.dumps(dict(player_id=identity,token=token,status='COMPLETE' if complete and not notes else 'INCOMPLETE',truncated=notes)))
                break
            except LimitReached:
                # Preserve both ends of each member; compressibility is not
                # assumed. Each retry halves the retained aggregate bytes.
                budget//=2
                if budget<1024:raise
                protected={'player-session-status.json'}
                fixed=sum(len(v) for k,v in entries.items() if k in protected)
                total=sum(len(v) for k,v in entries.items() if k not in protected) or 1
                for name,blob in entries.items():
                    if name in protected:continue
                    keep=max(64,int(max(0,budget-fixed)*len(blob)/total))
                    if len(blob)>keep:
                        n=len(blob)-keep;head=keep//2
                        payload[name]=blob[:head]+('\nTRUNCATED %d bytes\n'%n).encode()+blob[-(keep-head):]
                        notes[name]=n
                if 'player-session-status.json' in payload:
                    status=json.loads(entries['player-session-status.json'])
                    status.update(complete=False,state='incomplete',archive_truncated=dict(notes))
                    payload['player-session-status.json']=json.dumps(status,sort_keys=True).encode()
        data=raw.getvalue()
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            if z.testzip() is not None:raise OSError('CRC failure')
        # Existing retention is expanded only for the explicit second location.
        # Unknown archives remain counted and preserved. A full foreign budget
        # refuses this publication before any new disk bytes are committed.
        # Reserve both real copies before any output/scratch bytes are written.
        stage='archive-budget-reserve'
        enforce_budget(output,2*len(data))
        stage='archive-primary-write'
        fd,tmp=tempfile.mkstemp(prefix='.bi-pending-',dir=root);scratch=Path(tmp)
        with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
        # Reserve identity before publishing the filename. A crash between
        # link and receipt update can be recovered without adopting a stranger.
        write_receipt(receipt,dict(token=token,size=len(data),sha256=hashlib.sha256(data).hexdigest(),closed=time.time(),phase='reserved',delivery=str(delivery)))
        stage='archive-primary-publish'
        os.link(scratch,output);scratch.unlink();scratch=None
        write_receipt(receipt,dict(token=token,size=len(data),sha256=hashlib.sha256(data).hexdigest(),closed=time.time(),phase='published',delivery=str(delivery)))
        deliver(data,receipt,None)
        enforce_budget(output)
        return str(output)
    except BaseException as error:
        error.gor_zip_step=stage
        raise
    finally:
        if scratch:scratch.unlink(missing_ok=True)
        fcntl.flock(lock,fcntl.LOCK_UN);os.close(lock)
