import os,pathlib,subprocess,sys,tempfile,unittest,zipfile
from unittest.mock import patch
TOOLS=pathlib.Path(__file__).resolve().parents[2]/'tools'
sys.path.insert(0,str(TOOLS))
import bounded_log_archives as b
from player_session_logs import allocate,fanout_app_row,recover_orphans,Sessions,SessionError
A='a'*32;B='b'*32
class Review(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.tmp.name);self.home=self.root/'home';self.home.mkdir();self.cap=self.root/'sessions'
 def tearDown(self):self.tmp.cleanup()
 def alloc(self,token=A):
  with patch('pathlib.Path.home',return_value=self.home):return allocate(token,os.getpid(),['d'],self.cap)
 def cli(self,*args,stdin=b''):
  env=dict(os.environ);env.pop('PYTHONPATH',None)
  return subprocess.run([sys.executable,str(TOOLS/'player_session_log_cli.py')]+list(args),input=stdin,capture_output=True,env=env)
 def test_app_row_is_stdin_only(self):
  r=self.cli('app-row','Zm9v');self.assertEqual(r.returncode,2) # a row on argv is refused
  r=self.cli('app-row',stdin=b'x'*65537);self.assertEqual(r.returncode,2);self.assertNotIn(b'Traceback',r.stderr);self.assertTrue(r.stderr.startswith(b'error:'))
 def test_group_or_world_accessible_session_dirs_are_ignored(self):
  a=self.alloc();d=pathlib.Path(a['root']);d.chmod(0o755)
  self.assertEqual(fanout_app_row(b'row\n',self.cap),0);self.assertEqual(recover_orphans(self.cap),[])
  self.assertFalse((d/'app.log').exists())
  d.chmod(0o700);self.assertEqual(fanout_app_row(b'row\n',self.cap),1)
 def test_sessions_root_must_be_private(self):
  self.cap.mkdir();self.cap.chmod(0o755)
  with self.assertRaises(SessionError):self.alloc()
  self.cap.chmod(0o700);self.alloc()
 def test_allocated_id_never_reuses_an_archive_owned_id(self):
  import datetime as dt
  class Fixed(dt.datetime):
   @classmethod
   def now(cls,tz=None):return cls(2026,11,22,0,10,0)
  seq=iter(['abcd','abcd','beef'])
  archive=self.home/'Library/Logs/gor';archive.mkdir(parents=True)
  (archive/'20261122-001000-abcd.zip').write_bytes(b'someone else')
  with patch('datetime.datetime',Fixed),patch('secrets.token_hex',lambda n:next(seq)):a=self.alloc()
  self.assertEqual(pathlib.Path(a['root']).name,'20261122-001000-beef')
  self.assertEqual((archive/'20261122-001000-abcd.zip').read_bytes(),b'someone else')
 def pub(self,parent,ident,token,cap):
  return b.publish_199bi({'x':os.urandom(5000)},parent,identity=ident,token=token,complete=True,cap=cap)
 def test_edited_old_output_does_not_block_new_zip_and_is_never_deleted(self):
  p=self.root/'out';old=self.pub(p,'20261122-001000-aaaa','a'*32,20000)
  with open(old,'ab') as f:f.write(b'x') # owner edited it
  edited=pathlib.Path(old).read_bytes()
  m=self.pub(p,'20261122-001001-bbbb','b'*32,20000);n=self.pub(p,'20261122-001002-cccc','c'*32,20000)
  o=self.pub(p,'20261122-001003-dddd','d'*32,20000)
  self.assertEqual(pathlib.Path(old).read_bytes(),edited)
  self.assertFalse(pathlib.Path(m).exists());self.assertTrue(pathlib.Path(n).exists() and pathlib.Path(o).exists())
 def test_corrupt_receipt_of_old_output_is_pinned_not_fatal(self):
  p=self.root/'out';old=self.pub(p,'20261122-001000-aaaa','a'*32,40000)
  receipt=[x for x in p.glob('.gor-log-archives-v2*/20261122-001000-aaaa.json')][0];receipt.write_text('{broken')
  new=self.pub(p,'20261122-001001-bbbb','b'*32,40000)
  self.assertTrue(pathlib.Path(old).exists() and pathlib.Path(new).exists())
 def test_sessions_root_outside_tmp_is_allowed_when_private(self):
  base=tempfile.mkdtemp(dir=os.path.expanduser('~'));self.addCleanup(__import__('shutil').rmtree,base)
  with patch('pathlib.Path.home',return_value=self.home):a=allocate(A,os.getpid(),['d'],pathlib.Path(base)/'sessions'/'x')
  self.assertTrue(pathlib.Path(a['root']).is_dir())
 def test_external_root_never_follows_existing_symlink_ancestor(self):
  base=pathlib.Path(tempfile.mkdtemp(dir=os.path.expanduser('~')));self.addCleanup(__import__('shutil').rmtree,base)
  real=base/'real';real.mkdir(mode=0o700);(base/'link').symlink_to(real,target_is_directory=True)
  with patch('pathlib.Path.home',return_value=self.home):
   with self.assertRaises(SessionError):allocate(A,os.getpid(),['d'],base/'link'/'sessions')
  self.assertEqual(list(real.iterdir()),[])
if __name__=='__main__':unittest.main(verbosity=2)

