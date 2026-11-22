#!/usr/bin/env python3
"""199bh preparation: owned per-player disk sessions, original paths, shared publisher lock.
Native producers/EOF barriers must call this API before it is a complete integration.
"""
from contextlib import contextmanager
from pathlib import Path
import fcntl,json,os,re,stat,time
import bounded_log_archives
from session_log_paths import NAMES
TOKEN=re.compile(r'^[0-9a-f]{32}$')
LAG=re.compile(r'^gor-wt-lag-[0-9]+-[1-4]\.txt$')
LAGPREV=re.compile(r'^gor-wt-lag-[0-9]+-[1-4]\.txt\.prev$')
STATES=('open','closing','publishing','final','incomplete')
MIN_CAP=256 # session marker plus the reserved refusal receipt
CAPS={'gor_diag.log':20*1024*1024,'gor_direct.log':10*1024*1024}
class SessionError(RuntimeError):pass
def private_dir(path):
 # Real directory (not a link), ours, closed to group and others.
 try:s=os.lstat(path)
 except OSError:return False
 return stat.S_ISDIR(s.st_mode) and s.st_uid==os.getuid() and not s.st_mode&0o077
class Sessions:
 def __init__(self,parent='/tmp',archive_parent=None):
  self.parent=Path(parent).resolve();self.root=bounded_log_archives.owned_root(self.parent)
  self.archive_parent=Path(archive_parent).resolve() if archive_parent is not None else None
 @contextmanager
 def locked(self):
  fd=os.open(self.root/'.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
  try:fcntl.flock(fd,fcntl.LOCK_EX);yield
  finally:fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
 def load(self):
  p=self.root/'player-session.json'
  if p.is_symlink():raise SessionError('unsafe session receipt')
  if not p.exists():return None
  try:r=json.loads(p.read_text())
  except (OSError,ValueError):raise SessionError('corrupt session receipt')
  if not isinstance(r,dict) or not isinstance(r.get('token'),str) or r.get('state') not in STATES or not isinstance(r.get('producers'),dict) or not isinstance(r.get('files'),dict) or not isinstance(r.get('caps'),list) or not isinstance(r.get('errors'),list):raise SessionError('corrupt session receipt')
  return r
 @staticmethod
 def sync_directory(path):
  fd=os.open(path,os.O_RDONLY|getattr(os,'O_DIRECTORY',0)|os.O_NOFOLLOW)
  try:os.fsync(fd)
  finally:os.close(fd)
 def save(self,r):
  # Metadata only, no raw spool. Shared lock serializes this private receipt.
  p=self.root/'player-session.json';q=self.root/'.player-session.pending'
  fd=os.open(q,os.O_WRONLY|os.O_CREAT|os.O_TRUNC|os.O_NOFOLLOW,0o600)
  with os.fdopen(fd,'w') as f:json.dump(r,f);f.flush();os.fsync(f.fileno())
  os.replace(q,p)
  self.sync_directory(self.root)
 @staticmethod
 def regular(p):
  try:s=p.lstat()
  except FileNotFoundError:return None
  if not stat.S_ISREG(s.st_mode) or s.st_nlink!=1:raise SessionError('unowned/unsafe log file: '+p.name)
  return s
 @staticmethod
 def integer(v):return isinstance(v,int) and not isinstance(v,bool)
 def owned_fd(self,p,m,flags):
  # Open without following links, then prove the descriptor is the admitted file.
  try:fd=os.open(p,flags|os.O_NOFOLLOW)
  except OSError:raise SessionError('file replaced')
  try:
   s=os.fstat(fd)
   if not stat.S_ISREG(s.st_mode) or s.st_nlink!=1 or (s.st_dev,s.st_ino)!=(m['dev'],m['ino']):raise SessionError('file replaced')
  except BaseException:os.close(fd);raise
  return fd,s
 def checked(self,token):
  r=self.load()
  if not r or r['token']!=token:raise SessionError('session identity mismatch')
  return r
 def begin(self,token,pid,producers):
  if not isinstance(token,str) or not TOKEN.fullmatch(token) or not self.integer(pid) or pid<=0:raise SessionError('invalid identity')
  if not isinstance(producers,(list,tuple)) or not producers or not all(isinstance(p,str) and p for p in producers) or len(set(producers))!=len(producers):raise SessionError('producer identities required')
  with self.locked():
   old=self.load()
   if self.archive_parent is not None and old:raise SessionError('immutable capture identity')
   if old and old['state'] not in ('final','incomplete'):raise SessionError('previous player not drained')
   paths=[self.parent/n for n in NAMES]+[p for p in self.parent.iterdir() if LAG.fullmatch(p.name)]
   # Validate all before the first rename. Unknown files and symlinks are never adopted.
   for p in paths:
    self.regular(p);self.regular(p.with_name(p.name+'.prev'))
   stale=[q for q in self.parent.iterdir() if LAGPREV.fullmatch(q.name)]
   for q in stale:self.regular(q)
   # Lag names carry a new pid every session; keep only the previous session's rollover like fixed names.
   for q in stale:q.unlink()
   for p in paths:
    if p.exists():os.replace(p,p.with_name(p.name+'.prev'))
   self.sync_directory(self.parent)
   r=dict(token=token,pid=pid,started=time.time(),state='open',producers={p:False for p in producers},files={},caps=[],errors=[])
   if self.archive_parent is not None:r['archive_parent']=str(self.archive_parent)
   self.save(r)
   return r
 def admit_file(self,token,name,producer,cap=None):
  if name not in NAMES and name not in ('app.log','mpv.log','av-session.jsonl','input-session.jsonl') and not LAG.fullmatch(name):raise SessionError('unlisted log')
  cap=CAPS.get(name,10*1024*1024) if cap is None else cap
  if not self.integer(cap) or cap<MIN_CAP:raise SessionError('invalid cap')
  with self.locked():
   r=self.checked(token)
   if r['state']!='open' or producer not in r['producers']:raise SessionError('not admitting work')
   if name in r['files']:
    if r['files'][name]['producer']!=producer:raise SessionError('file owned by another producer')
    return
   p=self.parent/name
   if os.path.lexists(p):raise SessionError('file already exists without session ownership')
   fd=os.open(p,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
   marker=('[GOR-SESSION] token='+token+' pid='+str(r['pid'])+'\n').encode()
   with os.fdopen(fd,'wb') as f:f.write(marker);f.flush();os.fsync(f.fileno())
   s=p.stat();r['files'][name]=dict(dev=s.st_dev,ino=s.st_ino,producer=producer,cap=cap);self.save(r)
 def append(self,token,name,data):
  if not isinstance(data,bytes):raise SessionError('bytes required')
  with self.locked():
   r=self.checked(token)
   if r['state'] not in ('open','closing') or name not in r['files']:raise SessionError('not an owned writer')
   m=r['files'][name]
   if r['producers'][m['producer']]:raise SessionError('producer already drained')
   p=self.parent/name
   # Reserve one refusal receipt inside the same cap, never grow beyond it.
   reserve=160
   fd,size=self.owned_fd(p,m,os.O_RDWR)
   with os.fdopen(fd,'r+b') as f:
    if name not in r['caps'] and size.st_size+len(data)<=m['cap']:
     f.seek(0,2);f.write(data);f.flush();return True
    body=m['cap']-reserve;head=body//2;tailcap=body-head
    f.seek(max(head,size.st_size-tailcap));previous=f.read(tailcap)
    tail=(previous+data)[-tailcap:]
    if name not in r['caps'] and size.st_size<head:
     f.seek(0,2);f.write(data[:head-size.st_size])
    dropped=m.get('dropped',0)+max(0,(body if name in r['caps'] else size.st_size)+len(data)-body)
    note=('\nTRUNCATED %d bytes\n'%dropped).encode().ljust(reserve,b' ')
    f.seek(head);f.write(note);f.write(tail);f.truncate();f.flush()
   m['dropped']=dropped
   if name not in r['caps']:r['caps'].append(name)
   self.save(r);return False

 def native_admission(self,token,name,producer):
  self.admit_file(token,name,producer)
  with self.locked():
   r=self.checked(token);m=r['files'][name]
   if r['state']!='open' or m['producer']!=producer or r['producers'][producer]:raise SessionError('not an owned native producer')
   fd,_=self.owned_fd(self.parent/name,m,os.O_RDONLY);os.close(fd)
   return dict(token=token,name=name,producer=producer,dev=m['dev'],ino=m['ino'],cap=m['cap'],stateRoot=str(self.root))
 def native_cap_reached(self,token,name,producer):
  with self.locked():
   r=self.checked(token)
   if r['state'] not in ('open','closing') or name not in r['files']:raise SessionError('not an owned native writer')
   m=r['files'][name]
   if m['producer']!=producer or r['producers'][producer]:raise SessionError('not an owned native producer')
   fd,s=self.owned_fd(self.parent/name,m,os.O_RDONLY)
   with os.fdopen(fd,'rb') as f:
    f.seek(max(0,s.st_size-160));tail=f.read(160)
   #199bi native sink retains bounded head+tail with an exact dropped-byte note.
   fd,s=self.owned_fd(self.parent/name,m,os.O_RDONLY)
   with os.fdopen(fd,'rb') as f:
    f.seek(max(0,(m['cap']-160)//2));note=f.read(160)
   if s.st_size>m['cap'] or not re.search(rb'TRUNCATED [0-9]+ bytes',note):raise SessionError('native truncation note missing')
   if name not in r['caps']:r['caps'].append(name);self.save(r)

 def register(self,token,producer):
  # Children born while the session is open (fallback, restart) join the barrier set.
  # Identity is immutable: a name is never re-registered, even after it drained.
  if not isinstance(producer,str) or not producer:raise SessionError('producer identity required')
  with self.locked():
   r=self.checked(token)
   if r['state']!='open':raise SessionError('not admitting producers')
   if producer in r['producers']:raise SessionError('producer identity already registered')
   r['producers'][producer]=False;self.save(r)
 def closing(self,token):
  with self.locked():
   r=self.checked(token)
   if r['state']!='open':raise SessionError('not open')
   r['state']='closing';self.save(r)
 def drained(self,token,producer):
  with self.locked():
   r=self.checked(token)
   if r['state']!='closing' or producer not in r['producers']:raise SessionError('invalid drain')
   r['producers'][producer]=True;self.save(r)
 def finish(self,token,crash=False):
  try:return self._finish(token,crash=crash)
  except BaseException as error:
   try:
    with self.locked():
     record=self.checked(token)
     if record['state']=='publishing':
      record['state']='incomplete';record['archive_error']=type(error).__name__;record['archive_errno']=getattr(error,'errno',None);self.save(record)
   except BaseException:record={}
   fallback=delivery_record_from_root(self.parent)
   if fallback:record=fallback
   report_delivery_failure(record,getattr(error,'gor_zip_step','crash-finish' if crash else 'normal-finish'),error)
   raise
 def _finish(self,token,crash=False):
  with self.locked():
   r=self.checked(token)
   if not crash and r['state'] not in ('open','closing') and not (r['state']=='incomplete' and r.get('archive_error')):raise SessionError('already finalized')
   if not crash and (r['state'] not in ('closing','incomplete') or not all(r['producers'].values())):raise SessionError('exit/EOF/diag barriers pending')
   entries={};r['errors']=[] # recomputed per attempt, a retry never duplicates
   r.pop('archive_error',None) # prior publication failure is cleared only by a fresh attempt
   for name,m in r['files'].items():
    p=self.parent/name
    try:fd,s=self.owned_fd(p,m,os.O_RDONLY)
    except SessionError:r['errors'].append('file changed '+name);continue
    with os.fdopen(fd,'rb') as f:data=f.read(m['cap']+1) # bounded even if a writer outside the API grew it
    if len(data)>m['cap']:r['errors'].append('file cap exceeded '+name);continue
    # Ownership is explicit. No timestamp cutting, mtime heuristic or legacy scan.
    entries[name]=data
   complete=not crash and not r['caps'] and not r['errors']
   # Status is published inside the ZIP: no device/inode identity, and the state it will end in.
   status=dict(r,complete=complete,state='final' if complete else 'incomplete',files={n:{k:v for k,v in m.items() if k not in ('dev','ino')} for n,m in r['files'].items()})
   entries['player-session-status.json']=json.dumps(status,sort_keys=True).encode()
   # Publisher takes this same flock itself. Release it only after status is frozen;
   # no new begin may replace files until state is published below.
   r['state']='publishing';self.save(r)
  try:
   if 'player_id' in r:output=bounded_log_archives.publish_199bi(entries,parent=Path(r['archive_parent']),identity=r['player_id'],token=token,complete=complete,delivery_parent=DELIVERY_PARENT)
   elif 'archive_parent' in r:output=bounded_log_archives.publish_player(entries,parent=Path(r['archive_parent']),session=token,started=r['started'])
   else:output=bounded_log_archives.publish(entries,parent=self.parent,session=token,started=r['started'])
  except BaseException as error:
   with self.locked():
    current=self.checked(token)
    # Raw ownership and the error stay durable. Do not trap every subsequent
    # player behind an already-drained publication that cannot fit the cap.
    # The same token may retry until the next begin rolls these files to .prev.
    current['state']='incomplete'
    current['archive_error']=type(error).__name__
    current.pop('zip',None)
    self.save(current)
   raise
  if 'player_id' in r:
   import zipfile
   with zipfile.ZipFile(output) as z:complete=complete and json.loads(z.read('STATUS.json'))['status']=='COMPLETE'
  delivery=str(DELIVERY_PARENT/(delivery_stem(r)+'.zip')) if 'player_id' in r else output
  with self.locked():
   current=self.checked(token);current['state']='final' if complete else 'incomplete';current['zip']=output;current['delivery_zip']=delivery;self.save(current)
  if 'player_id' in r:
   retire_delivery_failure(r)
   # Only this allocator-owned directory, after successful checked publication.
   import shutil
   if not crash and (self.parent/'.capture-owner').read_text()=='gor-player-capture-v1':shutil.rmtree(self.parent)
  return output


def allocate(token,pid,producers,parent='/tmp/gor/sessions',slots=16):
 from datetime import datetime
 import secrets
 parent=Path(parent)
 # The fixed /tmp/gor prefix must not follow another process's symlink or
 # foreign directory. Intermediate mkdir defaults must not weaken privacy.
 if not parent.is_absolute():raise SessionError('absolute sessions root required')
 current=Path('/tmp')
 strict=True
 try:parts=parent.relative_to(current).parts
 except ValueError:current=Path(parent.anchor);parts=parent.parts[1:];strict=False # macOS TMPDIR is not under /tmp
 for part in parts:
  current=current/part
  made=True
  try:current.mkdir(mode=0o700)
  except FileExistsError:made=False
  st=current.lstat()
  if not stat.S_ISDIR(st.st_mode):raise SessionError('unsafe sessions root')
  # Existing system ancestors may be root-owned, but never traverse a link.
  if (strict or made) and st.st_uid!=os.geteuid():raise SessionError('unsafe sessions root')
 if not private_dir(parent):raise SessionError('unsafe sessions root') # leaf: ours and closed to others
 archive=Path.home()/'Library/Logs/gor'
 archive.mkdir(mode=0o700,parents=True,exist_ok=True)
 while True:
  identity=datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+secrets.token_hex(2)
  # A finished player's id is free in the session root but still owns its ZIP and receipt.
  if os.path.lexists(archive/(identity+'.zip')) or any(archive.glob('.gor-log-archives-v2*/'+identity+'.json')):continue
  path=parent/identity
  try:path.mkdir(mode=0o700);break
  except FileExistsError:continue
 (path/'.capture-owner').write_text('gor-player-capture-v1')
 sessions=Sessions(path,archive_parent=archive)
 sessions.begin(token,pid,producers)
 with sessions.locked():
  r=sessions.checked(token);r['player_id']=identity;sessions.save(r)
 return dict(root=str(path),token=token,player_id=identity)


def fanout_app_row(data,parent='/tmp/gor/sessions'):
 if not isinstance(data,bytes) or len(data)>65536:raise SessionError('invalid app row')
 root=Path(parent)
 if not root.exists() or not private_dir(root):return 0
 accepted=0
 for path in list(root.iterdir()):
  if not private_dir(path):continue
  marker=path/'.capture-owner'
  if marker.is_symlink() or not marker.is_file() or marker.read_text()!='gor-player-capture-v1':continue
  try:
   s=Sessions(path)
   with s.locked():
    r=s.load()
    if not r or r['state']!='open':continue
    try:os.kill(r['pid'],0)
    except ProcessLookupError:continue
    token=r['token'];producer=next(iter(r['producers']))
   s.admit_file(token,'app.log',producer)
   s.append(token,'app.log',data);accepted+=1
  except (OSError,SessionError):continue
 return accepted


def recover_orphans(parent='/tmp/gor/sessions'):
 """Background worker only. Newest three dead-owned sessions are attempted.
 Older sessions are preserved until their resource writer safety is known.
 A PID that exists or cannot be inspected is never an orphan candidate.
 """
 root=Path(parent)
 if not root.exists() or not private_dir(root):return []
 candidates=[];results=[]
 for path in root.iterdir():
  if not private_dir(path) or not PLAYER_ID.fullmatch(path.name):continue
  record={'player_id':path.name}
  try:
   marker=path/'.capture-owner';st=marker.lstat()
   if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or marker.read_text()!='gor-player-capture-v1':continue
   if not any(bounded_log_archives._owned(path/(bounded_log_archives.BASE+('' if i==0 else '-%d'%i))) for i in range(8)):raise SessionError('owned raw root has no session receipt')
   sessions=Sessions(path)
   with sessions.locked():loaded=sessions.load()
   if not loaded or loaded.get('player_id')!=path.name or not isinstance(loaded.get('token'),str) or not TOKEN.fullmatch(loaded['token']):raise SessionError('invalid orphan identity receipt')
   record=loaded
   pid=record.get('pid')
   if not Sessions.integer(pid) or pid<=0:raise SessionError('invalid orphan owner receipt')
   try:os.kill(pid,0);continue
   except ProcessLookupError:pass
   except PermissionError:continue
   if verified_published_session(record):
    retire_delivery_failure(record)
    continue
   candidates.append((path.name,sessions,record))
  except (OSError,ValueError,SessionError) as error:
   report_delivery_failure({'player_id':path.name},'orphan-inspection',error)
 ordered=sorted(candidates,reverse=True)
 for _,sessions,record in ordered[3:]:
  import errno
  report_delivery_failure(record,'orphan-deferred-newest3',OSError(errno.EAGAIN,'orphan archive attempt deferred'))
 for _,sessions,record in ordered[:3]:
  try:results.append(sessions.finish(record['token'],crash=True))
  except BaseException as error:report_delivery_failure(record,'orphan-recovery',error)
 # Older/unknown resource roots are not rmtree candidates without writer proof.
 # This is an explicit residual, not a claim to satisfy destructive cleanup.
 return results

def report_recovery_error(parent,error):
 """One bounded owned worker error log when no player identity is available."""
 if not private_dir(parent):return
 fd=os.open(Path(parent)/'.recovery-errors.txt',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
 try:
  st=os.fstat(fd)
  if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1:return
  fcntl.flock(fd,fcntl.LOCK_EX)
  line=('step=recovery-worker errno=%s error=%s\n'%(getattr(error,'errno',None),type(error).__name__)).encode()[:256]
  if st.st_size+len(line)>65536:os.ftruncate(fd,0)
  os.lseek(fd,0,os.SEEK_END);os.write(fd,line);os.fsync(fd)
 finally:os.close(fd)

def start_orphan_recovery(parent='/tmp/gor/sessions'):
 """Constant launch-side work: nonblocking single-worker lease, no dir scan."""
 root=Path(parent)
 if not private_dir(root):return False
 lockfd=os.open(root/'.recovery.lock',os.O_RDWR|os.O_CREAT|os.O_NOFOLLOW,0o600)
 try:
  st=os.fstat(lockfd)
  if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1:return False
  try:fcntl.flock(lockfd,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:return False
  child=os.fork()
  if child==0:
   try:
    os.setsid();os.nice(19)
    null=os.open('/dev/null',os.O_RDWR)
    for fd in (0,1,2):os.dup2(null,fd)
    if null>2:os.close(null)
    recover_orphans(root)
   except BaseException as error:
    try:report_recovery_error(root,error)
    except BaseException:pass # the destination itself may also reject writes
   finally:os.close(lockfd)
   os._exit(0)
  # Closing the parent's fd does not unlock the child's inherited flock.
  return True
 finally:os.close(lockfd)


# 199bl user-visible close artifacts. Original archive retention is unchanged.
# DELIVERY_PARENT is a module-level test seam, never read from child environment.
DELIVERY_PARENT=Path('/tmp')
PLAYER_ID=re.compile(r'^[0-9]{8}-[0-9]{6}-[a-f0-9]{4}$')

def delivery_record_from_root(parent):
 """Recover only a path ID bound to a validated allocator-owned raw root."""
 path=Path(parent)
 if not PLAYER_ID.fullmatch(path.name) or not private_dir(path):return {}
 fd=None
 try:
  fd=os.open(path/'.capture-owner',os.O_RDONLY|os.O_NOFOLLOW)
  st=os.fstat(fd)
  if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or st.st_size!=len('gor-player-capture-v1'):return {}
  if os.read(fd,64)!=b'gor-player-capture-v1':return {}
  return {'player_id':path.name}
 except OSError:return {}
 finally:
  if fd is not None:os.close(fd)

def delivery_stem(record):
 from datetime import datetime
 identity=record.get('player_id','')
 if not PLAYER_ID.fullmatch(identity):raise SessionError('invalid delivery player identity')
 stamp=identity[:15]
 return 'gor-logs-'+stamp+'-'+identity

def verified_published_session(record):
 """Skip only exact recorded paths with matching checked ZIP identity/bytes.
 Merely existing arbitrary receipt paths never consume/escape recovery slots.
 """
 import zipfile,io,hashlib
 if record.get('state') not in ('final','incomplete') or record.get('archive_error'):return False
 try:
  identity=record['player_id'];token=record['token']
  expected=Path(record['archive_parent'])/(identity+'.zip')
  delivery=DELIVERY_PARENT/(delivery_stem(record)+'.zip')
  if record.get('zip')!=str(expected) or record.get('delivery_zip')!=str(delivery):return False
  digests=[]
  for path in (expected,delivery):
   fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
   with os.fdopen(fd,'rb') as f:
    st=os.fstat(f.fileno())
    if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or st.st_size>16*1024*1024:return False
    data=f.read(16*1024*1024+1)
   with zipfile.ZipFile(io.BytesIO(data)) as z:
    status=json.loads(z.read('STATUS.json'))
    if status.get('player_id')!=identity or status.get('token')!=token or z.testzip() is not None:return False
   digests.append(hashlib.sha256(data).digest())
  return digests[0]==digests[1]
 except (OSError,ValueError,KeyError,TypeError,zipfile.BadZipFile):return False

def retire_delivery_failure(record):
 """Remove only our bounded private FAILED receipt after verified publication.
 No wildcard/suffix deletion; foreign/symlink/edited markers stay untouched.
 """
 fd=None
 try:
  path=DELIVERY_PARENT/(delivery_stem(record)+'.FAILED.txt')
  fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW)
  fcntl.flock(fd,fcntl.LOCK_EX)
  st=os.fstat(fd);header=('GOR ZIP FAILED v2 player='+record['player_id']+'\n').encode()
  if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or st.st_mode&0o077 or st.st_size>512:return
  if os.read(fd,len(header))!=header:return
  current=path.lstat()
  if (current.st_dev,current.st_ino)!=(st.st_dev,st.st_ino):return
  path.unlink()
 except OSError:pass
 finally:
  if fd is not None:os.close(fd)

def report_delivery_failure(record,step,error):
 """Bounded reason, no raw log/token/paths. Never masks the original error.
 A full/unwritable delivery filesystem may also refuse the failure marker;
 stderr plus existing session receipt then remain the available evidence.
 """
 import sys
 number=getattr(error,'errno',None)
 line=('step=%s errno=%s error=%s\n'%(step,number if number is not None else 'unavailable',type(error).__name__)).encode()[:256]
 fd=None
 try:
  destination=DELIVERY_PARENT/(delivery_stem(record)+'.FAILED.txt')
  # Exactly one <=512-byte receipt per player. Repeated failures replace its
  # bounded body in place under flock, not temp-suffix accumulation.
  header=('GOR ZIP FAILED v2 player='+record['player_id']+'\n').encode()
  try:fd=os.open(destination,os.O_RDWR|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600);created=True
  except FileExistsError:fd=os.open(destination,os.O_RDWR|os.O_NOFOLLOW);created=False
  fcntl.flock(fd,fcntl.LOCK_EX)
  st=os.fstat(fd)
  if not stat.S_ISREG(st.st_mode) or st.st_uid!=os.getuid() or st.st_nlink!=1 or st.st_mode&0o077:raise SessionError('unsafe failure receipt')
  if not created and (st.st_size>512 or os.read(fd,len(header))!=header):raise SessionError('foreign failure receipt preserved')
  # The accepted header stays intact. An interrupted rewrite still leaves an
  # attributable FAILED file; repeated calls can repair the bounded body.
  if created:os.write(fd,header);os.fsync(fd)
  os.lseek(fd,len(header),os.SEEK_SET);os.write(fd,line);os.ftruncate(fd,len(header)+len(line));os.fsync(fd)
  return str(destination)
 except BaseException as marker_error:
  print(line.decode(errors='replace').strip()+' marker_errno='+str(getattr(marker_error,'errno',None)),file=sys.stderr,flush=True)
 finally:
  if fd is not None:os.close(fd)
 return None
