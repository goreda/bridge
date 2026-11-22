import tempfile,os,json,zipfile,hashlib,re
from pathlib import Path
from unittest.mock import patch
from player_session_logs import allocate,Sessions
import bounded_log_archives as b
with tempfile.TemporaryDirectory() as d:
 root=Path(d);home=root/'home';home.mkdir()
 with patch('pathlib.Path.home',return_value=home):
  a=allocate('a'*32,os.getpid(),['d'],root/'sessions');c=allocate('b'*32,os.getpid(),['d'],root/'sessions')
 assert re.fullmatch(r'\d{8}-\d{6}-[a-f0-9]{4}',Path(a['root']).name)
 sa,sc=Sessions(a['root']),Sessions(c['root'])
 for s,t,x in [(sa,'a'*32,b'A'),(sc,'b'*32,b'B')]:
  s.admit_file(t,'gor_diag.log','d',cap=1024)
  assert s.append(t,'gor_diag.log',b'HEAD'+x*700)
  assert not s.append(t,'gor_diag.log',x*900+b'TAIL')
  blob=(s.parent/'gor_diag.log').read_bytes();assert blob.startswith(b'[GOR-SESSION]') and b'HEAD' in blob and blob.endswith(b'TAIL') and b'TRUNCATED ' in blob and len(blob)<=1024
  s.closing(t);s.drained(t,'d')
 pb=sc.finish('b'*32);before=Path(pb).read_bytes();pa=sa.finish('a'*32)
 assert pa!=pb and Path(pb).read_bytes()==before and not Path(a['root']).exists() and not Path(c['root']).exists()
 for p,x,y in [(pa,b'A',b'B'),(pb,b'B',b'A')]:
  with zipfile.ZipFile(p) as z:
   assert json.loads(z.read('STATUS.json'))['status']=='INCOMPLETE'
   body=z.read('gor_diag.log');assert x*50 in body and y*50 not in body
 print('PASS199bi id/rawroot, headtail/nativecaps, independent reverseorderZIP, B hash unchanged, rawcleanup only after ZIP')
with tempfile.TemporaryDirectory() as d:
 data=os.urandom(17*1024*1024)
 out=b.publish_199bi({'gor_diag.log':b'HEAD'+data+b'TAIL'},Path(d),identity='20261122-001000-abcd',token='c'*32,complete=True)
 assert Path(out).stat().st_size<=16*1024*1024
 with zipfile.ZipFile(out) as z:
  assert z.read('gor_diag.log').startswith(b'HEAD') and z.read('gor_diag.log').endswith(b'TAIL')
  assert json.loads(z.read('STATUS.json'))['status']=='INCOMPLETE' and b'TRUNCATED' in z.read('TRUNCATION.txt')
 print('PASS199bi incompressible17MiB archive fits16MiB with retained head/tail and honest INCOMPLETE')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);unknown=p/'foreign.zip';unknown.write_bytes(b'keep')
 old=b.publish_199bi({'x':os.urandom(5000)},p,identity='20261122-001000-aaaa',token='a'*32,complete=True,cap=10000)
 newer=b.publish_199bi({'x':os.urandom(5000)},p,identity='20261122-001001-bbbb',token='b'*32,complete=True,cap=10000)
 assert not Path(old).exists() and Path(newer).exists() and unknown.read_bytes()==b'keep'
 print('PASS199bi oldest-owned retention only, foreignZIP untouched')
from player_session_logs import fanout_app_row,recover_orphans
with tempfile.TemporaryDirectory() as d:
 root=Path(d);home=root/'home';home.mkdir();capture=root/'sessions'
 with patch('pathlib.Path.home',return_value=home):
  a=allocate('a'*32,os.getpid(),['d'],capture);c=allocate('b'*32,os.getpid(),['d'],capture)
 assert fanout_app_row(b'app-wide\n',capture)==2
 sa=Sessions(a['root']);sc=Sessions(c['root'])
 for s,t in [(sa,'a'*32),(sc,'b'*32)]:
  assert (s.parent/'app.log').read_bytes().endswith(b'app-wide\n')
 sa.closing('a'*32)
 assert fanout_app_row(b'only-B\n',capture)==1
 assert b'only-B' not in (sa.parent/'app.log').read_bytes() and b'only-B' in (sc.parent/'app.log').read_bytes()
 with sc.locked():r=sc.checked('b'*32);r['pid']=2147483647;r['state']='publishing';sc.save(r)
 recovered=recover_orphans(capture);assert len(recovered)==1 and not sc.parent.exists() and sa.parent.exists()
 with zipfile.ZipFile(recovered[0]) as z:assert json.loads(z.read('STATUS.json'))['status']=='INCOMPLETE'
 assert recover_orphans(capture)==[]
 print('PASS199bi app fanout open-only; orphan midpublish crashZIP INCOMPLETE; live A untouched; recovery idempotent')
with tempfile.TemporaryDirectory() as d:
 s=Sessions(d);s.begin('d'*32,os.getpid(),['d']);s.admit_file('d'*32,'gor_diag.log','d',cap=1024)
 assert not s.append('d'*32,'gor_diag.log',b'FIRST-HEAD'+b'x'*2000+b'LAST-TAIL')
 raw=(Path(d)/'gor_diag.log').read_bytes();assert b'FIRST-HEAD' in raw[:432] and raw.endswith(b'LAST-TAIL') and len(raw)<=1024
 print('PASS first oversized append retains real head+tail, never sparsezeros')
with tempfile.TemporaryDirectory() as d:
 out=b.publish_199bi({'gor_diag.log':os.urandom(17*1024*1024),'player-session-status.json':json.dumps({'complete':True,'state':'final'}).encode()},Path(d),identity='20261122-002000-eeee',token='e'*32,complete=True)
 with zipfile.ZipFile(out) as z:
  raw=json.loads(z.read('player-session-status.json'));assert raw['complete'] is False and raw['state']=='incomplete' and raw['archive_truncated']
 print('PASS archive-size truncation preserves valid metadataJSON and marks both statusmembers incomplete')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);real=os.link
 def fail_publish(src,dst,*a,**kw):
  if str(dst).endswith('.zip'):raise OSError('injected publication link refusal')
  return real(src,dst,*a,**kw)
 with patch('os.link',side_effect=fail_publish):
  try:b.publish_199bi({'x':b'original'},p,identity='20261122-002100-ffff',token='f'*32,complete=True);raise AssertionError()
  except OSError:pass
 assert not list(p.glob('*.zip'))
 out=b.publish_199bi({'x':b'original'},p,identity='20261122-002100-ffff',token='f'*32,complete=True)
 assert Path(out).exists() and len(list(p.glob('*.zip')))==1
 print('PASS reserved publication interrupted before link retries to exactly one owned ZIP')
with tempfile.TemporaryDirectory() as d:
 p=Path(d)
 old=b.publish_199bi({'x':os.urandom(5000)},p,identity='20261122-002200-0001',token='1'*32,complete=True,cap=20000)
 current=b.publish_199bi({'x':os.urandom(5000)},p,identity='20261122-002201-0002',token='2'*32,complete=True,cap=20000)
 before=Path(current).read_bytes()
 # Same receipt/output models crash after link before retention. Retry must
 # re-enforce the current budget rather than return early as already done.
 retried=b.publish_199bi({'x':b'unused'},p,identity='20261122-002201-0002',token='2'*32,complete=True,cap=10000)
 assert retried==current and not Path(old).exists() and Path(current).read_bytes()==before
 assert sum(q.stat().st_size for q in p.glob('*.zip'))<=10000
 print('PASS post-link retry re-enforces retention, immutable current ZIP unchanged')
