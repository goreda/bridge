import contextlib,importlib.util,io,json,os,subprocess,tempfile,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch,Mock
spec=importlib.util.spec_from_file_location('gor_runner',Path(__file__).with_name('runner.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class AutoInstall(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)/'gor-runner';p=patch.object(m,'ROOT',self.root);p.start();self.addCleanup(p.stop)
 def owned(self,registered=False):
  self.root.mkdir();(self.root/'.gor-owner').write_text(m.MARKER)
  if registered:(self.root/'.runner').write_text('{}')
 def darwin(self):
  a=patch.object(m.platform,'system',return_value='Darwin');b=patch.object(m.platform,'machine',return_value='arm64');a.start();b.start();self.addCleanup(a.stop);self.addCleanup(b.stop)
 def test_idle_registered_no_credential(self):
  self.darwin();self.owned(True)
  with patch.object(m,'service_running',return_value=True),patch.object(m,'api_token') as tok,patch.object(m,'setup_service') as svc:m.install()
  tok.assert_not_called();svc.assert_not_called()
 def test_owned_service_repair_no_token(self):
  self.darwin();self.owned(True)
  with patch.object(m,'service_running',return_value=False),patch.object(m,'api_token') as tok,patch.object(m,'setup_service') as svc,patch.object(m.subprocess,'run'):m.install()
  tok.assert_not_called();svc.assert_called_once()
 def test_unowned_and_symlink_refused(self):
  self.darwin();self.root.mkdir()
  with patch.object(m,'api_token') as tok,self.assertRaises(RuntimeError):m.install()
  tok.assert_not_called()
 def test_symlink_root_is_not_owned(self):
  target=Path(self.tmp.name)/'target';target.mkdir();(target/'.gor-owner').write_text(m.MARKER);self.root.symlink_to(target,target_is_directory=True)
  self.darwin()
  with patch.object(m,'api_token') as api,self.assertRaises(RuntimeError):m.install()
  api.assert_not_called();self.assertFalse(m.owned())
 def test_scope_missing_changes_nothing(self):
  self.darwin()
  with patch.object(m,'api_token',side_effect=m.ScopeMissing),self.assertRaises(m.ScopeMissing):m.install()
  self.assertFalse(self.root.exists())
 def test_partial_owned_reuses_official_config(self):
  self.darwin();self.owned();(self.root/'config.sh').write_text('official')
  with patch.object(m,'api_token',return_value='dummy-local-only'),patch.object(m,'config') as cfg,patch.object(m,'setup_service'),patch.object(m.urllib.request,'urlopen') as net,contextlib.redirect_stdout(io.StringIO()):m.install()
  cfg.assert_called_once_with('dummy-local-only');net.assert_not_called();self.assertTrue((self.root/'.gor-registered').exists())
 def test_token_request_local_stdin_only(self):
  reply=Mock();reply.__enter__=Mock(return_value=reply);reply.__exit__=Mock();reply.read.return_value=b'{"token":"dummy-registration"}'
  opener=Mock();opener.open.return_value=reply
  with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'username=local\npassword=dummy-credential\n','')) as run,patch.object(m.urllib.request,'build_opener',return_value=opener):self.assertEqual(m.api_token(),'dummy-registration')
  args=run.call_args;self.assertEqual(args.args[0],['git','credential','fill']);self.assertEqual(args.kwargs['input'],'protocol=https\nhost=github.com\n\n');req=opener.open.call_args.args[0];self.assertEqual(req.full_url,'https://api.github.com/repos/goreda/gorav/actions/runners/registration-token');self.assertEqual(req.get_method(),'POST')
 def test_scope_http_errors_sanitized(self):
  for code in (401,403,404):
   opener=Mock();opener.open.side_effect=urllib.error.HTTPError('private',code,'dummy-secret',{},None)
   with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'password=dummy-local\n','')),patch.object(m.urllib.request,'build_opener',return_value=opener),self.assertRaises(m.ScopeMissing):m.api_token()
 def test_no_redirect(self):self.assertIsNone(m.NoRedirect().redirect_request(None,None,None,None,None,None))
 def test_missing_credential_no_api(self):
  with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],1,'','')),patch.object(m.urllib.request,'build_opener') as api,self.assertRaises(m.ScopeMissing):m.api_token()
  api.assert_not_called()
 def test_config_token_environment_not_argv(self):
  with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0)) as run:m.config('dummy-secret')
  call=run.call_args;self.assertNotIn('dummy-secret',str(call.args));self.assertEqual(call.kwargs['stdout'],subprocess.DEVNULL);self.assertEqual(call.kwargs['stderr'],subprocess.DEVNULL)
 def test_trace_environment_removed(self):
  with patch.dict(os.environ,{'GIT_TRACE_CURL':'1','GIT_CONFIG_COUNT':'1','GIT_ASKPASS':'unsafe','ACTIONS_RUNNER_INPUT_TOKEN':'stale'}):
   env=m.local_env();self.assertFalse(any(k.startswith(('GIT_TRACE','GIT_CONFIG_','ACTIONS_RUNNER_INPUT_')) for k in env));self.assertNotIn('GIT_ASKPASS',env)
 def test_service_low_priority_and_preserves_env(self):
  self.owned();(self.root/'.env').write_text('KEEP=value\nACTIONS_RUNNER_HOOK_JOB_STARTED=old\n')
  with patch.object(m.subprocess,'run') as run:m.setup_service()
  import plistlib
  p=plistlib.loads((self.root/'service.plist').read_bytes());self.assertEqual(p['Nice'],10);self.assertIn('/usr/bin/taskpolicy',p['ProgramArguments']);self.assertIn('-b',p['ProgramArguments']);self.assertIn('KEEP=value',(self.root/'.env').read_text());self.assertEqual((self.root/'.env').read_text().count('ACTIONS_RUNNER_HOOK_JOB_STARTED='),1)
 def test_ac_only(self):
  for text,want in [("Now drawing from 'AC Power'",True),("Now drawing from 'Battery Power'",False)]:
   with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,text,'')):self.assertEqual(m.on_ac(),want)
  with patch.object(m.subprocess,'run',side_effect=OSError):self.assertFalse(m.on_ac())
 def test_failed_unregister_never_deletes(self):
  self.owned(True)
  with patch.object(m,'api_token',return_value='dummy-removal'),patch.object(m,'config',side_effect=RuntimeError),self.assertRaises(RuntimeError):m.remove()
  self.assertTrue(self.root.exists())
 def test_unowned_remove_never_calls_api(self):
  self.root.mkdir()
  with patch.object(m,'api_token') as api,self.assertRaises(RuntimeError):m.remove()
  api.assert_not_called()
 def test_loaded_service_without_pid_is_not_running(self):
  for output,want in [('state = waiting\n',False),('state = running\n  pid = 123\n',True)]:
   with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,output,'')):self.assertEqual(m.service_running(),want)
 def test_scope_missing_cli_is_exact_and_success(self):
  with patch.object(m,'install',side_effect=m.ScopeMissing),patch.object(m.sys,'argv',['runner.py','install']),contextlib.redirect_stdout(io.StringIO()) as out:
   try:m.main()
   except m.ScopeMissing:print('runner: credential scope missing')
  self.assertEqual(out.getvalue(),'runner: credential scope missing\n')
 def test_owned_unregistered_remove_only_own_folder(self):
  self.owned();outside=Path(self.tmp.name)/'unrelated';outside.write_text('keep')
  with patch.object(m,'api_token') as api,contextlib.redirect_stdout(io.StringIO()):m.remove()
  api.assert_not_called();self.assertFalse(self.root.exists());self.assertEqual(outside.read_text(),'keep')
 def test_update_calls_installed_helper_once(self):
  build=Path(__file__).parents[2].joinpath('build.sh').read_text();self.assertEqual(build.count('/usr/bin/python3 "$project_root/Tests/Runner/runner.py" install'),1);self.assertIn('|| :',build);self.assertLess(build.index('--install-runner|--remove-runner'),build.index('_gor_git_bin'))
if __name__=='__main__':unittest.main()
