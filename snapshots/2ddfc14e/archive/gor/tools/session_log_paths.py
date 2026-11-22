#!/usr/bin/env python3
"""Owned new-session diagnostic paths. Never adopt or remove legacy logs.

Session cut (owner order 2026-11-15): when a session anchor is given, every
collected log is cut to the current gor session (from gor launch; wt_full.log
from its own last INIT marker). Files with no provable current-session content
are excluded from the ZIP with an explicit status line instead of shipping
stale multi-day history. Without an anchor (legacy callers) collection keeps
the historical whole-file behavior.
"""
from pathlib import Path
import json,os,re,stat,tempfile,sys
from datetime import datetime,timezone
NAMES=('gor_diag.log','gor_direct.log','gor_sample.txt','gor_mpv_sample.txt','gor_camera_helper_sample.txt','wt_full.log','photon-grain-size.log','photon-grain-doc.log','gor-quit-debug.log')
_INIT=re.compile(rb'\[[^\]\n]+\] INIT:v')
_SEED=re.compile(rb'(?m)^\d\d:\d\d:\d\d\.\d+ SEED OK ')
_STATS=re.compile(r'STATS:\{"session":(\d+)')
_SAMPLE_PID=re.compile(rb'\(pid (\d+)\)')
_ISO=re.compile(rb'^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)([+-]\d{4}|Z)')
_TS=re.compile(rb'^ts=(\d+(?:\.\d+)?)')
_MTIME_GATED={'gor_sample.txt','gor_mpv_sample.txt','gor_camera_helper_sample.txt'}
_IDENT=re.compile(rb'^\[GOR-IDENTITY\] v1 ')
_ENGINE=re.compile(rb'(?m)^\S+ \[GOR-ENGINE\] event=(open|switch) requested=(mpv|gorav) active=(mpv|gorav)(?: origin=(?:menu|environment|saved|default))?(?: env=[a-z0-9_-]{1,16} saved=[a-z0-9_-]{1,16} override=[a-z0-9_-]{1,16})?(?: fallback=\S+)?$')
_SKEW=5
def _iso(epoch):return datetime.fromtimestamp(epoch,timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def identity_tokens(line):
 """Typed identity fields of a [GOR-IDENTITY] line, without free-text reason or build."""
 if isinstance(line,bytes):line=line.decode(errors='replace')
 if not line.startswith('[GOR-IDENTITY] v1 '):return None
 fields=dict(x.split('=',1) for x in line.split()[2:] if '=' in x)
 return {k:fields.get(k) for k in ('verification','source_commit','tree','tree_manifest','snapshot','build')}
# The direct-log writer prefixes every runtime row with "[ts=... cpu_system_pct=... ...] "; the diag
# writer does not. Both are accepted, only in that exact known shape (key=value fields, no spaces in values).
_PFX=rb'(?:\[(?:[A-Za-z_]+=[^\s\]]*)(?: [A-Za-z_]+=[^\s\]]*)*\] )?'
_SESSION=re.compile(rb'(?m)^'+_PFX+rb'\[GOR-SESSION\] pid=(\d+) launch_epoch=(\d+) launch_id=([0-9a-f]{32}) build=([0-9a-f]{64}|unknown) tree=([0-9a-f]{40}|unknown)$')
_PROC_TOL=30
_CHUNK=1024*1024
def _matches_process(m,session):
 pid=(session or {}).get('pid');anchor=(session or {}).get('proc_start');tol=_PROC_TOL
 if anchor is None:anchor=(session or {}).get('started');tol=300
 return pid is not None and anchor is not None and int(m.group(1))==int(pid) and abs(int(m.group(2))-anchor)<=tol
def session_region(f,size,session):
 """Locate this process's session in an open file WITHOUT materializing it.
 Scans backwards in line-aligned chunks. The last marker with this pid and a launch time near the real
 process start gives launch_id L. The region starts at the EARLIEST marker carrying L (the launch
 marker; later re-emits do not shorten the cut) and ends at EOF. A marker of another launch ends the scan.
 Returns (start_offset, marker_fields) or None. Memory is one chunk; I/O is bounded by the file size."""
 L=None;start=None;first=None;hi=size
 while hi>0:
  lo=max(0,hi-_CHUNK);f.seek(lo);data=f.read(hi-lo)
  if lo>0:
   nl=data.find(b'\n')
   if nl<0:hi=lo;continue
   lo+=nl+1;data=data[nl+1:]
  for m in reversed(list(_SESSION.finditer(data))):
   if L is None:
    if _matches_process(m,session):L=m.group(3);start=lo+m.start();first=m.groups()
   elif m.group(3)==L:start=lo+m.start();first=m.groups()
   else:return start,first
  hi=lo
 return (start,first) if L is not None else None
def session_marker(data,session):
 """In-memory convenience over session_region; returns the marker fields of the bound launch or None."""
 import io
 got=session_region(io.BytesIO(data),len(data),session)
 return got[1] if got else None
def _materialize(f,start,size,session):
 limit=(session or {}).get('tail_limit')
 if not limit or size-start<=limit:
  f.seek(start);return f.read(size-start),''
 f.seek(start);head=f.readline(4096)
 pos=max(size-limit,start+len(head));f.seek(pos);tail=f.read(size-pos)
 if pos>start+len(head):
  cut=tail.find(b'\n');tail=tail[cut+1:] if cut>=0 else tail
 return head+tail,' TAIL-BOUNDED marker line plus last %d bytes'%limit
def _build_conflict(fields,session):
 want=(session or {}).get('build_id')
 got=fields[3].decode()
 return bool(want) and got!='unknown' and got!=want
def stream_cut(name,f,size,session):
 """Session-bound cut for gor_diag.log / gor_direct.log (bounded read). Returns (bytes|None, status)."""
 where=session_region(f,size,session)
 if where is None:return None,'EXCLUDED '+name+' (no [GOR-SESSION] marker for pid '+str((session or {}).get('pid'))+' and this process start; identity alone is not session binding)'
 start,fields=where
 if _build_conflict(fields,session):return None,'EXCLUDED '+name+' (session marker build differs from the installed build-id)'
 body,tail=_materialize(f,start,size,session)
 header=(session or {}).get('identity_line')
 if header:body=header.encode()+b'\n'+body
 label='marker launch_id='+fields[2].decode()+(' build='+('matches installed' if fields[3].decode()==(session or {}).get('build_id') else fields[3].decode()[:12]))
 return body,('CUT ' if name=='gor_diag.log' else 'BOUND ')+name+' from session '+label+tail+'; installed-build identity '+('first line' if header else 'NOT_AVAILABLE')
def read_bounded(path,limit=None):
 """Read a whole small file, or only its last `limit` bytes (line-aligned) when it is larger."""
 with open(path,'rb') as f:
  size=os.fstat(f.fileno()).st_size
  if not limit or size<=limit:return f.read()
  f.seek(size-limit);data=f.read(limit);cut=data.find(b'\n')
  return data[cut+1:] if cut>=0 else data
_HASHES={}
def sha256_cached(path):
 """Static-asset digest cached per (path,size,mtime_ns): unchanged installed scripts are hashed once."""
 import hashlib
 st=Path(path).stat();key=(str(path),st.st_size,st.st_mtime_ns)
 if key not in _HASHES:_HASHES[key]=hashlib.sha256(Path(path).read_bytes()).hexdigest()
 return _HASHES[key]
def _cut_from_last(data,rx):
 last=None
 for m in rx.finditer(data):last=m
 return (data[last.start():],last) if last else (None,None)
def cut_iso_rows(data,started):
 """Keep only rows whose leading ISO timestamp is >= started."""
 if started is None:return data,None
 kept=[]
 for line in data.splitlines(keepends=True):
  m=_ISO.match(line)
  if not m:continue
  try:ts=datetime.strptime((m.group(1)+m.group(2)).decode(),'%Y-%m-%dT%H:%M:%S%z').timestamp()
  except ValueError:continue
  if ts>=started-_SKEW:kept.append(line)
 if not kept:return None,'(no rows >= session start)'
 return b''.join(kept),'(%d rows >= session start)'%len(kept)
def cut_ts_rows(data,started):
 """Keep only rows whose ts=<epoch> field is >= started."""
 if started is None:return data,None
 kept=[]
 for line in data.splitlines(keepends=True):
  m=_TS.match(line)
  if not m:continue
  try:ts=float(m.group(1))
  except ValueError:continue
  if ts>=started-_SKEW:kept.append(line)
 if not kept:return None,'(no rows >= session start)'
 return b''.join(kept),'(%d rows >= session start)'%len(kept)
def cut_named(name,data,session):
 """Per-file session cut. Returns (bytes|None, status str)."""
 started=(session or {}).get('started')
 if started is None:return data,None
 if name=='wt_full.log':
  cut,_=_cut_from_last(data,_INIT)
  if cut is None:return None,'EXCLUDED wt_full.log (no INIT marker)'
  ts=re.match(rb'\[([^\]]+)\]',cut)
  return cut,'CUT wt_full.log from last INIT '+(ts.group(1).decode(errors='replace') if ts else '')
 if name in ('gor_diag.log','gor_direct.log'):
  import io
  return stream_cut(name,io.BytesIO(data),len(data),session)
 if name=='gor-quit-debug.log':
  cut,note=cut_ts_rows(data,started)
  if cut is None:return None,'EXCLUDED gor-quit-debug.log '+note
  return cut,'CUT gor-quit-debug.log '+note
 if name in ('photon-grain-size.log','photon-grain-doc.log'):
  cut,note=cut_iso_rows(data,started)
  if cut is None:return None,'EXCLUDED '+name+' '+note
  return cut,'CUT '+name+' '+note
 return data,None
def engine_status(entries):
 """Engine requested/active records at every open and switch, as found in the session-bound logs."""
 rows=[]
 for name in ('gor_diag.log','gor_direct.log'):
  rows+=[m for m in _ENGINE.finditer(entries.get(name,b''))]
 if not rows:return 'ENGINE-RECORD NOT_RECORDED (no open/switch rows in the session-bound logs)'
 last=rows[-1]
 return 'ENGINE-RECORD rows=%d last event=%s requested=%s active=%s'%(len(rows),last.group(1).decode(),last.group(2).decode(),last.group(3).decode())
class UnownedRoot(OSError):
 """Permanent refusal: a non-/tmp session log root without a valid .owner marker. Never retried, adopted, read or deleted."""
def valid(root):
 try:
  root=Path(root)
  return root.name.startswith('gor-log-session-') and not root.is_symlink() and root.is_dir() and not (root/'.owner').is_symlink() and (root/'.owner').read_text()=='gor-log-session-v1'
 except OSError:return False
def create(parent='/tmp'):
 if str(parent)=='/tmp':return Path('/tmp')
 root=Path(tempfile.mkdtemp(prefix='gor-log-session-',dir=parent));(root/'.owner').write_text('gor-log-session-v1');return root
def active():
 #195t B ignores obsolete active-session pointers, never adopts their logs.
 return Path('/tmp')
def resolve(path):return Path(path)
def entries(root,session=None):
 if Path(root)!=Path('/tmp') and not valid(root):raise UnownedRoot('unowned session log directory')
 result={};receipts={};status=[]
 started=(session or {}).get('started');owner=(session or {}).get('pid')
 # Only exact known basenames, plus bounded, PID-owned sampler names recorded
 # by this session's WT process. No scan of shared /tmp or old directories.
 paths=[Path(root)/name for name in (NAMES[:6] if Path(root)==Path("/tmp") else NAMES)]
 wt=Path(root)/'wt_full.log'
 if wt.is_file() and not wt.is_symlink():
  try:raw=read_bounded(wt,(session or {}).get('tail_limit'))
  except OSError:raw=b''
  if started is not None:
   cut,_=_cut_from_last(raw,_INIT)
   ids=_STATS.findall(cut.decode(errors='replace')) if cut else []
   if not ids:status.append('LAG-SAMPLES unavailable (no current-session wt window)')
  else:ids=_STATS.findall(raw.decode(errors='replace'))
  for pid in set(ids):paths += [Path(root)/('gor-wt-lag-%s-%d.txt'%(pid,i)) for i in range(1,5)]
 if started is not None:status.append('CUT-START gor-launch='+_iso(started)+' pid='+str(owner))
 else:status.append('CUT unavailable (no session anchor; whole-file collection)')
 for p in paths:
  try:
   fd=os.open(p,os.O_RDONLY|os.O_NOFOLLOW)
   with os.fdopen(fd,'rb') as f:
    st=os.fstat(f.fileno())
    if not stat.S_ISREG(st.st_mode) or st.st_size>32*1024*1024:continue
    if started is not None and (p.name in _MTIME_GATED or p.name.startswith('gor-wt-lag-')) and st.st_mtime<started-_SKEW:
     status.append('EXCLUDED '+p.name+' (mtime '+_iso(st.st_mtime)+' before session start)');continue
    if started is not None and p.name in ('gor_diag.log','gor_direct.log'):
     data,note=stream_cut(p.name,f,st.st_size,session)
     if data is None:status.append(note);continue
     status.append(note);result[p.name]=data;receipts[p.name]=(st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns);continue
    limit=(session or {}).get('tail_limit')
    if limit and st.st_size>limit:
     f.seek(st.st_size-limit);data=f.read(limit);cut=data.find(b'\n');data=data[cut+1:] if cut>=0 else data
     status.append('TAIL-BOUNDED '+p.name+' last %d bytes read'%limit)
    else:data=f.read()
  except FileNotFoundError:continue
  if started is not None:
   if p.name=='gor_sample.txt' and owner:
    m=_SAMPLE_PID.search(data[:4096])
    if not m or int(m.group(1))!=int(owner):status.append('EXCLUDED gor_sample.txt (sampler pid not session pid '+str(owner)+')');continue
   data,note=cut_named(p.name,data,session)
   if data is None:status.append(note);continue
   if note:status.append(note)
  result[p.name]=data;receipts[p.name]=(st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns)
 return result,receipts,status
def cleanup(root,receipts):
 if Path(root)==Path('/tmp'):return #shared raw logs are never deleted by ZIP publication
 if not valid(root):raise UnownedRoot('unowned session cleanup refused')
 for name,receipt in receipts.items():
  p=Path(root)/name
  try:
   st=p.lstat()
   if not stat.S_ISLNK(st.st_mode) and (st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns)==receipt:p.unlink()
  except FileNotFoundError:pass
 # Unknown or late-changing files are retained, never swept.
 if {p.name for p in Path(root).iterdir()}=={'.owner'}:(Path(root)/'.owner').unlink();Path(root).rmdir()
if __name__=='__main__':
 if sys.argv[1]=='create':print(create())
 else:print(resolve(sys.argv[1]))
