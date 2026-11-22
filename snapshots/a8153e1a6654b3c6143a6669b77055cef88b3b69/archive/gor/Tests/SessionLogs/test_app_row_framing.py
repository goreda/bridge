import io,contextlib,pathlib,sys,tempfile,unittest,runpy
from unittest.mock import patch
TOOLS=pathlib.Path(__file__).resolve().parents[2]/'tools'
sys.path.insert(0,str(TOOLS))
import player_session_logs
class Frames(unittest.TestCase):
 def invoke(self,wire):
  seen=[];out=io.StringIO();err=io.StringIO()
  with tempfile.TemporaryDirectory() as d,patch.object(sys,'argv',['cli','--root',d,'app-row']),patch.object(sys,'stdin',io.TextIOWrapper(io.BytesIO(wire))),patch.object(player_session_logs,'fanout_app_row',side_effect=lambda b:seen.append(b) or 0),contextlib.redirect_stdout(out),contextlib.redirect_stderr(err):
   code=0
   try:runpy.run_path(str(TOOLS/'player_session_log_cli.py'),run_name='__main__')
   except SystemExit as e:code=e.code
  return code,seen,out.getvalue(),err.getvalue()
 def test_valid_zero_binary_max(self):
  for blob in [b'',b'A\x00\n\xff',b'x'*65536]:
   rc,seen,out,err=self.invoke(str(len(blob)).encode()+b'\n'+blob)
   self.assertEqual((rc,seen,out,err),(0,[blob],'0\n',''))
 def test_refusals_never_fanout(self):
  for wire in [b'',b'\n',b'+1\nx',b'1 \nx',b'123456\n',b'65537\n',b'4\nabc',b'2\nabc',b'9999999999999',b'1\n']:
   rc,seen,out,err=self.invoke(wire)
   self.assertEqual((rc,seen,out),(2,[],''),wire);self.assertTrue(err.startswith('error: '));self.assertNotIn('Traceback',err)
if __name__=='__main__':unittest.main(verbosity=2)
