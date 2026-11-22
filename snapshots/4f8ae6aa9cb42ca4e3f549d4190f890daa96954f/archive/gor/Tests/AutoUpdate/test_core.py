"""190k U9 production state machine tests. No native/macOS claim."""
import importlib.util,json,os,shutil,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('autoupdate',ROOT/'tools/autoupdate.py')
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
SHA='a'*40
RELEASE=f'commit {SHA}\nlinux_gates 12345,12346\nintegrity PASS\nprepared_by gdb\n'
PROOF={'strategy':'renamex_np-RENAME_SWAP'}
GATES={'codesign':'PASS','bootcheck':'PASS'}
SHA2='b'*40

class Core(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.project=self.root/'project';self.sidecar=self.root/'sidecar'
  self.project.mkdir();self.sidecar.mkdir();self.u=a.Updater(self.project,self.sidecar)
  self.bundle(self.u.app,'old');self.old=a.app_tree_sha(self.u.app);self.release=a.parse_release(RELEASE)
  (self.project/'private-user-file').write_text('do not touch')
 def tearDown(self):
  self.assertEqual((self.project/'private-user-file').read_text(),'do not touch');self.tmp.cleanup()
 def bundle(self,p,label):
  (p/'Contents/MacOS').mkdir(parents=True);(p/'Contents/MacOS/gor').write_text(label);(p/'Contents/MacOS/gor').chmod(0o755)
  (p/'Contents/Resources/vendor').mkdir(parents=True);(p/'Contents/Resources/vendor/leaf').write_text('fixture')
  return p
 def builder(self,stage,sha,idle):
  app=self.bundle(stage/'gor.app','new');root=self.u.release_root(sha);(root/'vendor').mkdir(parents=True);(root/'vendor/leaf').write_text('r');(app/'Contents/Resources/gor-resource-root').write_text(str(root)+'\n')
  return app
 def prepare(self,**kw):return self.u.prepare(self.release,SHA,kw.pop('builder',self.builder),idle_check=kw.pop('idle_check',lambda:True),permission_check=lambda:PROOF,gates=kw.pop('gates',lambda c:GATES),**kw)
 def swap(self):
  return self.u.swap(permission_check=lambda:PROOF,running=lambda:[])
 def test_release_strict(self):
  self.assertEqual(a.parse_release(RELEASE)['commit'],SHA)
  for value in [RELEASE+'commit '+SHA,RELEASE.replace('PASS','FAIL'),RELEASE.replace(SHA,'HEAD'),RELEASE.replace('prepared_by gdb\n',''),RELEASE+'next evil\n',RELEASE.replace('12345,12346','$(touch bad)')]:
   with self.assertRaises(a.Refused):a.parse_release(value)
 def test_nonrelease_and_badlist(self):
  with self.assertRaises(a.Refused):self.u.approved(self.release,'b'*40)
  a.atomic_json(self.u.bad,[SHA])
  with self.assertRaises(a.Refused):self.prepare()
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_stage_failure_preserves_source_and_app(self):
  def failed(stage,sha,idle):self.bundle(stage/'gor.app','bad');raise a.Refused('simulated build failure')
  with self.assertRaises(a.Refused):self.prepare(builder=failed)
  self.assertFalse(self.u.staging.exists());self.assertFalse(self.u.next.exists());self.assertFalse(self.u.ready.exists());self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_bad_bootcheck_refused(self):
  def failed(stage,sha,idle):return self.builder(stage,sha,idle)
  with self.assertRaises(a.Refused):self.prepare(builder=failed,gates=lambda c:{'codesign':'PASS','bootcheck':'FAIL'})
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_loaded_playback_or_unknown_never_prepares(self):
  with self.assertRaises(a.Refused):self.prepare(idle_check=lambda:False)
  checks=iter([True,False])
  with self.assertRaises(a.Refused):self.prepare(idle_check=lambda:next(checks))
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_build_lock_blocks_prepare_and_swap(self):
  lock=self.project/'.gor-build.lock';lock.mkdir()
  with self.assertRaises(a.Refused):self.prepare()
  lock.rmdir();self.prepare();lock.mkdir()
  with self.assertRaises(a.Refused):self.swap()
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_ready_hash_and_no_running_swap(self):
  self.prepare()
  with self.assertRaises(a.Refused):self.u.swap(permission_check=lambda:PROOF,running=lambda:[123])
  (self.u.next/'Contents/MacOS/gor').write_text('changed')
  with self.assertRaises(a.Refused):self.swap()
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_swap_twice_bad_revert_blacklist(self):
  prior=self.bundle(self.u.prev,'older');self.prepare();self.swap()
  self.assertEqual(a.app_tree_sha(self.u.prev),self.old)
  first=self.u.begin_launch(now=100)
  with self.assertRaises(a.Refused):self.u.fail_launch(now=129,running=lambda:[])
  self.assertEqual(self.u.fail_launch(now=131,running=lambda:[]),'retry-once')
  second=self.u.begin_launch(now=200)
  self.assertNotEqual(first['nonce'],second['nonce'])
  with self.assertRaises(a.Refused):self.u.good_launch(SHA,first['nonce'],now=201)
  self.assertIn('the previous version',self.u.fail_launch(now=231,running=lambda:[]))
  self.assertEqual(a.app_tree_sha(self.u.app),self.old);self.assertIn(SHA,a.read_json(self.u.bad))
  with self.assertRaises(a.Refused):self.u.approved(self.release,SHA)
  self.assertFalse(self.u.prev.exists());self.assertTrue(self.u.next.exists())
 def test_good_launch_requires_exact_app_nonce_and_window(self):
  self.prepare();self.swap();data=self.u.begin_launch(now=100)
  for commit,nonce,now in [('b'*40,data['nonce'],101),(SHA,'wrong',101),(SHA,data['nonce'],131)]:
   with self.assertRaises(a.Refused):self.u.good_launch(commit,nonce,now=now)
  note=self.u.good_launch(SHA,data['nonce'],now=120)
  self.assertIn('Rollback',note);self.assertTrue(a.read_json(self.u.pending)['good'])
  with self.assertRaises(a.Refused):self.u.fail_launch(now=140,running=lambda:[])
 def test_delete_fence_exact_paths(self):
  for target in [self.u.app,self.project,self.sidecar,self.project/'private-user-file',self.u.base,self.u.staging/'nested']:
   with self.assertRaises(a.Refused):self.u.remove_owned_stage(target)
  self.u.staging.symlink_to(self.sidecar,target_is_directory=True)
  with self.assertRaises(a.Refused):self.u.remove_owned_stage(self.u.staging)
  self.assertTrue(self.sidecar.exists())
 def test_app_hash_mode_and_symlink_fence(self):
  exe=self.u.app/'Contents/MacOS/gor';exe.chmod(0o644);self.assertNotEqual(a.app_tree_sha(self.u.app),self.old)
  (self.u.app/'escape').symlink_to(self.project/'private-user-file')
  with self.assertRaises(a.Refused):a.app_tree_sha(self.u.app)
 def test_native_ship_gate_missing_refuses(self):
  with self.assertRaises(a.Refused):self.u.permission_gate()
  with self.assertRaises(a.Refused):self.u.prepare(self.release,SHA,self.builder,idle_check=lambda:True)
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_interrupted_exchange_before_syscall_keeps_prior(self):
  self.prepare();a.atomic_json(self.u.journal,{'commit':SHA,'operation':'exchange','old_sha256':self.old,'new_sha256':a.app_tree_sha(self.u.next)})
  self.assertEqual(self.u.recover_swap(running=lambda:[]),'prior-unchanged');self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_interrupted_candidate_exchange_finishes(self):
  self.prepare();a.atomic_json(self.u.journal,{'commit':SHA,'operation':'exchange','old_sha256':self.old,'new_sha256':a.app_tree_sha(self.u.next)})
  a.atomic_exchange(self.u.app,self.u.next)
  self.assertTrue(self.u.app.exists());self.assertTrue(self.u.next.exists())
  self.assertEqual(self.u.recover_swap(running=lambda:[]),'swap-completed');self.assertTrue(self.u.pending.exists());self.assertEqual(a.app_tree_sha(self.u.prev),self.old)
 def test_atomic_replace_proof_cannot_authorize_rename(self):
  self.prepare()
  with self.assertRaises(a.Refused):self.u.swap(permission_check=lambda:{'strategy':'atomic-replace'},running=lambda:[])
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_interrupted_revert_completes_and_blacklists(self):
  self.prepare();self.swap()
  a.atomic_json(self.u.journal,dict(operation='revert',commit=SHA,failed_sha256=a.app_tree_sha(self.u.app),prior_sha256=self.old))
  a.atomic_exchange(self.u.app,self.u.prev)
  self.assertEqual(self.u.recover_swap(running=lambda:[]),'revert-completed')
  self.assertEqual(a.app_tree_sha(self.u.app),self.old);self.assertIn(SHA,a.read_json(self.u.bad))
 def test_missing_gate_evidence_refuses_swap(self):
  self.prepare();d=a.read_json(self.u.ready);d.pop('gates');a.atomic_json(self.u.ready,d)
  with self.assertRaises(a.Refused):self.u.swap(permission_check=lambda:PROOF,running=lambda:[])
  self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_bundle_id_and_production_guard(self):
  for value,production in [(None,False),('other.app',False),('com.gokcebalkan.gor',False),('com.gokcebalkan.gor.staging',True)]:
   with self.assertRaises(a.Refused):a.NativeBuilder.validate_bundle_id(value,production)
  self.assertEqual(a.NativeBuilder.validate_bundle_id('com.gokcebalkan.gor',True),'com.gokcebalkan.gor')
  self.assertEqual(a.NativeBuilder.validate_bundle_id('com.gokcebalkan.gor.staging'),'com.gokcebalkan.gor.staging')
 def test_native_adapter_refuses_same_bundle_session(self):
  with self.assertRaises(a.Refused):a.NativeBuilder(self.u)(self.u.staging,SHA,lambda:True)

class IsolationAndActor(unittest.TestCase):
 setUp=Core.setUp
 tearDown=Core.tearDown
 bundle=Core.bundle
 builder=Core.builder
 prepare=Core.prepare
 swap=Core.swap
 def test_isolated_env_drops_credentials_and_global_paths(self):
  work=self.u.staging/'project';work.mkdir(parents=True)
  os.environ['GITHUB_TOKEN']='dummy-no-leak';os.environ['SSH_AUTH_SOCK']='/private/agent'
  try:env=a.NativeBuilder(self.u).isolation_environment(work,'com.gokcebalkan.gor.staging')
  finally:os.environ.pop('GITHUB_TOKEN');os.environ.pop('SSH_AUTH_SOCK')
  self.assertNotIn('GITHUB_TOKEN',env);self.assertNotIn('SSH_AUTH_SOCK',env)
  for k in ['HOME','CFFIXED_USER_HOME','TMPDIR','GOR_SELFTEST_ROOT']:self.assertTrue(str(work) in env[k])
  self.assertEqual(env['GOR_SELFTEST_STAGED'],'1');self.assertEqual(env['GOR_SELFTEST_BUNDLE_ID'],'com.gokcebalkan.gor.staging')
 def test_relaunch_at_exchange_boundary_leaves_old_and_ready(self):
  self.prepare()
  checks=iter([[],[999]])
  with self.assertRaises(a.Refused):self.u.swap(permission_check=lambda:PROOF,running=lambda:next(checks))
  self.assertEqual(a.app_tree_sha(self.u.app),self.old);self.assertTrue(self.u.ready.exists());self.assertTrue(self.u.next.exists())
 def test_production_staged_harness_refusal_before_any_native_side_effect(self):
  body=(ROOT/'gor-selftest.sh').read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
  # Compile the REAL embedded Python; execute only prefix before native IO.
  compile(body,'gor-selftest','exec')
  prefix=body.split("app=root/'gor.app'",1)[0]
  env=dict(os.environ,GOR_SELFTEST_STAGED='1',GOR_SELFTEST_BUNDLE_ID='com.gokcebalkan.gor')
  import subprocess
  r=subprocess.run(['python3','-c',prefix,str(self.project)],env=env,capture_output=True,text=True)
  self.assertNotEqual(r.returncode,0);self.assertIn('staged selftest refuses production id',r.stderr)
  self.assertEqual(body.count("application id"),2) # centralized quit_script only
  self.assertIn("'/usr/bin/defaults','read',bundle_id",body)
 def test_pid_wait_and_quit_actor(self):
  import sys
  sys.path.insert(0,str(ROOT/'tools'))
  spec=importlib.util.spec_from_file_location('quit_actor',ROOT/'tools/gor-quit-swap.py');q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
  seq=iter(['same',None]);self.assertTrue(q.wait_for_quit(123,'same',probe=lambda pid:next(seq),sleep=lambda n:None))
  self.assertTrue(q.wait_for_quit(123,'same',probe=lambda pid:'reused',sleep=lambda n:None))
  self.prepare()
  result=q.after_quit(self.u,123,'same',wait=lambda *x:True,running=lambda:[],permission_check=lambda:PROOF)
  self.assertEqual(result,'atomic-exchange-complete');self.assertEqual(a.app_tree_sha(self.u.prev),self.old)
  self.assertNotIn('kill(',Path(q.__file__).read_text());self.assertNotIn('tell application',Path(q.__file__).read_text())

class V1(unittest.TestCase):
 """190l V1.1-V1.5 on Linux fake bundles. No native/macOS claim."""
 setUp=Core.setUp
 tearDown=Core.tearDown
 bundle=Core.bundle
 builder=Core.builder
 prepare=Core.prepare
 swap=Core.swap
 def swapped(self):
  self.prepare();self.swap();return self.u.begin_launch(now=100)
 def test_static_gates_run_codesign_then_bootcheck_no_ui(self):
  calls=[]
  class R:returncode=0;stdout=b''
  u=a.Updater(self.project,self.sidecar,runner=lambda args,**k:calls.append(args) or R())
  self.assertEqual(u.static_gates(self.u.app),GATES)
  self.assertEqual(calls[0][:4],['/usr/bin/codesign','--verify','--deep','--strict']);self.assertEqual(calls[1],[str(self.u.app/'Contents/MacOS/gor'),'--bootcheck'])
  class F:returncode=1;stdout=b''
  bad=a.Updater(self.project,self.sidecar,runner=lambda args,**k:F())
  with self.assertRaises(a.Refused):bad.static_gates(self.u.app)
 def test_prepare_requires_resource_set_and_marker(self):
  def nores(stage,sha,idle):return self.bundle(stage/'gor.app','new')
  with self.assertRaises(a.Refused):self.prepare(builder=nores)
  def wrong(stage,sha,idle):
   app=self.builder(stage,sha,idle);(app/'Contents/Resources/gor-resource-root').write_text('/elsewhere\n');return app
  with self.assertRaises(a.Refused):self.prepare(builder=wrong)
  self.assertFalse(self.u.release_root(SHA).exists());self.assertEqual(a.app_tree_sha(self.u.app),self.old)
 def test_deterministic_preflight_fail_reverts_at_once_and_blacklists(self):
  self.bundle(self.u.prev,'older');self.swapped()
  note=self.u.fail_launch(now=101,running=lambda:[],deterministic=True)
  self.assertIn('the previous version',note);self.assertEqual(a.app_tree_sha(self.u.app),self.old);self.assertIn(SHA,a.read_json(self.u.bad))
  self.assertFalse(self.u.pending.exists());self.assertFalse(self.u.release_root(SHA).exists())
 def test_timeout_or_crash_retries_once_then_reverts_and_blacklists(self):
  self.swapped()
  self.assertEqual(self.u.fail_launch(now=131,running=lambda:[]),'retry-once');self.assertEqual(a.app_tree_sha(self.u.app),a.read_json(self.u.pending)['app_sha256'])
  self.assertNotIn(SHA,a.read_json(self.u.bad,[]));self.u.begin_launch(now=200)
  self.assertIn('twice',self.u.fail_launch(now=231,running=lambda:[]));self.assertEqual(a.app_tree_sha(self.u.app),self.old);self.assertIn(SHA,a.read_json(self.u.bad))
 def test_deterministic_fail_needs_started_launch(self):
  self.prepare();self.swap()
  with self.assertRaises(a.Refused):self.u.fail_launch(now=1,running=lambda:[],deterministic=True)
 def test_quit_path_swap_and_relaunch_once(self):
  import sys;sys.path.insert(0,str(ROOT/'tools'))
  spec=importlib.util.spec_from_file_location('quit_actor',ROOT/'tools/gor-quit-swap.py');q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
  self.prepare();opened=[]
  self.assertEqual(q.after_quit(self.u,123,'same',wait=lambda *x:True,running=lambda:[],permission_check=lambda:PROOF,relaunch=opened.append),'atomic-exchange-complete')
  self.assertEqual(opened,[self.u.app]);self.assertEqual(a.app_tree_sha(self.u.prev),self.old)
  self.assertEqual(a.read_json(self.u.base/'relaunched.json')['commit'],SHA)
 def test_quit_helper_waits_when_owner_alive_and_never_swaps(self):
  import sys;sys.path.insert(0,str(ROOT/'tools'))
  spec=importlib.util.spec_from_file_location('quit_actor2',ROOT/'tools/gor-quit-swap.py');q=importlib.util.module_from_spec(spec);spec.loader.exec_module(q)
  self.prepare()
  with self.assertRaises(q.Refused):q.after_quit(self.u,123,'same',wait=lambda *x:False,running=lambda:[],permission_check=lambda:PROOF)
  with self.assertRaises(q.Refused):q.after_quit(self.u,123,'same',wait=lambda *x:True,running=lambda:[77],permission_check=lambda:PROOF)
  self.assertEqual(a.app_tree_sha(self.u.app),self.old);self.assertTrue(self.u.ready.exists())
 def test_forced_quit_fallback_bootstrap_spawns_helper_once_ready(self):
  self.assertEqual(self.u.bootstrap(lambda pid:self.fail('no ready candidate'),running=lambda:[]),'no-ready')
  self.prepare();spawned=[]
  self.assertEqual(self.u.bootstrap(spawned.append,running=lambda:[55,56],own_pid=None) if False else self.u.bootstrap(spawned.append,running=lambda:[55],own_pid=55),'helper-spawned')
  self.assertEqual(spawned,[55]);self.assertEqual(a.app_tree_sha(self.u.app),self.old)
  with self.assertRaises(a.Refused):self.u.bootstrap(spawned.append,running=lambda:[55,99],own_pid=55)
  self.assertEqual(spawned,[55])
 def test_kill_mid_rename_then_bootstrap_recovers_before_anything(self):
  self.prepare();a.atomic_json(self.u.journal,{'commit':SHA,'operation':'exchange','old_sha256':self.old,'new_sha256':a.app_tree_sha(self.u.next)})
  a.atomic_exchange(self.u.app,self.u.next) # killed here: exchange done, nothing after it
  r=self.u.bootstrap(lambda pid:self.fail('must not spawn after recovery'),running=lambda:[])
  self.assertEqual(r,'swap-completed');self.assertFalse(self.u.journal.exists());self.assertEqual(a.app_tree_sha(self.u.prev),self.old)
  self.assertEqual(a.read_json(self.u.installed)['current'],SHA);self.assertTrue(self.u.pending.exists())
 def test_kill_after_exchange_before_rotation_with_prev_present(self):
  self.bundle(self.u.prev,'older');self.prepare()
  a.atomic_json(self.u.journal,{'commit':SHA,'operation':'exchange','old_sha256':self.old,'new_sha256':a.app_tree_sha(self.u.next)})
  a.atomic_exchange(self.u.app,self.u.next)
  self.assertEqual(self.u.recover_swap(running=lambda:[]),'swap-completed');self.assertEqual(a.app_tree_sha(self.u.prev),self.old)
 def test_release_set_pruned_only_for_non_current_non_prev(self):
  for c in [SHA,SHA2,'c'*40]:(self.u.release_root(c)).mkdir(parents=True)
  a.atomic_json(self.u.installed,{'current':SHA,'prev':SHA2})
  self.assertEqual(self.u.prune_releases(),['c'*40]);self.assertTrue(self.u.release_root(SHA).exists() and self.u.release_root(SHA2).exists())
  for keep in (SHA,SHA2):
   with self.assertRaises(a.Refused):self.u.remove_release(keep)
  for bad in ['../x','abc','A'*40,'/etc']:
   with self.assertRaises(a.Refused):self.u.remove_release(bad)
  self.assertTrue((self.project/'private-user-file').exists())
 def test_release_remove_refuses_symlink(self):
  self.u.releases.mkdir(exist_ok=True);self.u.release_root(SHA).symlink_to(self.sidecar,target_is_directory=True)
  with self.assertRaises(a.Refused):self.u.remove_release(SHA)
  self.assertTrue(self.sidecar.exists())
 def test_swap_tracks_current_prev_and_prunes_old_sets(self):
  self.prepare();self.swap();self.assertEqual(a.read_json(self.u.installed),{'current':SHA,'prev':None})
  self.u.begin_launch(now=1);self.u.good_launch(SHA,a.read_json(self.u.pending)['nonce'],now=5)
  (self.u.release_root('d'*40)).mkdir(parents=True);self.assertEqual(self.u.prune_releases(),['d'*40]);self.assertTrue(self.u.release_root(SHA).exists())
 def test_poll_launch_then_hourly_and_unchanged_fetches_nothing(self):
  fetched=[];tip=lambda:SHA;rel=lambda:fetched.append(1) or {'commit':SHA2}
  self.assertEqual(self.u.poll(100,at_launch=True,remote_tip=tip,fetch=rel),'new-release');self.assertEqual(len(fetched),1)
  self.assertEqual(self.u.poll(200,remote_tip=tip,fetch=rel),'not-due')
  self.assertEqual(self.u.poll(100+a.POLL_SECONDS,remote_tip=tip,fetch=rel),'unchanged');self.assertEqual(len(fetched),1)
  self.assertEqual(self.u.poll(100+2*a.POLL_SECONDS,remote_tip=lambda:SHA2,fetch=rel),'release-unchanged')
  self.assertEqual(self.u.poll(150+2*a.POLL_SECONDS,at_launch=True,remote_tip=lambda:SHA2,fetch=rel),'unchanged')
 def test_permission_baseline_then_regression_disables_with_turkish_line(self):
  ok={'screen_recording':True,'camera':True,'accessibility':True}
  self.assertEqual(self.u.permission_check_launch(ok,'14.5')['regressed'],[]);self.assertFalse(self.u.enabled())
  a.atomic_json(self.u.config,{'enabled':True})
  self.assertEqual(self.u.permission_check_launch(ok)['regressed'],[]);self.assertTrue(self.u.enabled())
  r=self.u.permission_check_launch(dict(ok,screen_recording=False))
  self.assertEqual(r['regressed'],['screen_recording']);self.assertFalse(self.u.enabled());self.assertIn('screen recording permission',r['message']);self.assertIn('manual updates still work',r['message'])
 def test_permission_never_granted_is_not_a_regression(self):
  self.u.permission_check_launch({'screen_recording':False,'camera':True,'accessibility':True})
  self.assertEqual(self.u.permission_check_launch({'screen_recording':False,'camera':True,'accessibility':True})['regressed'],[])
  with self.assertRaises(a.Refused):self.u.permission_check_launch({'camera':True})

if __name__=='__main__':unittest.main(verbosity=2)
