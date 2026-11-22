from pathlib import Path
import importlib.util,subprocess,tempfile,shutil,json,os,hashlib
R=Path(__file__).resolve().parents[2];TOOL=R/'tools/gor_provenance.py';REPO=os.environ.get('GOR_OBJECT_REPO', str(R));BASE='e04a3000fd4181ffbe8a2ee56a11c580293c35f8'
spec=importlib.util.spec_from_file_location('p',TOOL);p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
def git(*a):return subprocess.check_output(['git','-C',REPO,*a])
# Small faithful closed-tree fixture, real stale blobs, actual legacy exit call syntax tested separately.
def case(name):
 with tempfile.TemporaryDirectory() as td:
  td=Path(td);repo=td/'repo';root=repo/'archive/gor';root.mkdir(parents=True)
  data={'Package.swift':b'// package\n','build.sh':b'echo fixture\n','Sources/gor/a.swift':b'let a=1\n','Packages/p/Sources/p.swift':b'let p=1\n'}
  for old,(_,repls) in p.UPDATE_RETIREMENTS.items():
   source='c1c5da2781d7c6e195ff444130808f2b84ca9dd0' if old.endswith('/ThreeD.swift') else BASE
   for rel in repls:
    if rel in {'Sources/gor/App/main.swift','Sources/gor/App/AppDelegate.swift','Sources/gor/App/IndependentDocumentRouter.swift','Sources/gor/Player/PPController.swift','Sources/gor/Player/PlayerViewStub.swift','Sources/gor/Player/PPControllerEngineRefusalHUD.swift','Sources/gor/Player/PPControllerMenuQueries.swift','Sources/gor/Player/EngineObservation.swift','Sources/gor/Engine/MPVCommand.swift','Sources/gor/Engine/GorAVAppGate.swift','Sources/gor/Engine/GorAVHostMotion.swift','Sources/gor/Engine/GorAVHostWindow.swift','Sources/gor/Engine/GorAVLocalOffer.swift','Sources/gor/Engine/GorAVNativeGate.swift','Sources/gor/Engine/GorAVPlayerHost.swift','Sources/gor/Engine/GorAVPostOpenFallback.swift','Sources/gor/Engine/GorAVStreamAdmission.swift','Sources/gor/Camera/BlinkCommandRoute.swift','Sources/gor/Camera/CaptureConsumerRules.swift','Sources/gor/Camera/ScreenCaptureEngine.swift','Sources/gor/UI/SpineUI.swift','Sources/gor/UI/SidebarUI.swift','Sources/gor/UI/MenuActions.swift','Sources/gor/UI/PhotonFont.swift','Sources/gor/UI/VariationBroadcaster.swift','Sources/gor/UI/IconBarFit.swift','Sources/gor/UI/FlatControlRefreshGate.swift','Sources/gor/UI/PhotonActiveEngineHeader.swift','Sources/gor/Media/ArchiveBrowser.swift','Sources/gor/Media/ArchiveLibrary.swift','Sources/gor/Media/ArchiveRandom.swift','Sources/gor/Media/CDPSession.swift','Sources/gor/Media/FileBrowser.swift','Sources/gor/Media/IPTV.swift','Sources/gor/Media/MagnetBrowser.swift','Sources/gor/Media/MegaStreamManager.swift','Sources/gor/Media/TorrentManager.swift','Sources/gor/Media/TransferResolver.swift','Sources/gor/Media/TransferTicketContext.swift','Sources/gor/Media/WTSessionPipeDrain.swift','Sources/gor/Modes/MusicModeController.swift','Sources/gor/Modes/MusicController.swift','Sources/gor/Modes/MusicPanel.swift','Sources/gor/Modes/MusicRowLabel.swift','Sources/gor/Modes/IPTVModeController.swift','Sources/gor/Stereo/Source.swift','Sources/gor/Stereo/Depth.swift','Sources/gor/Stereo/Prepare.swift','Sources/gor/Stereo/Render.swift','Sources/gor/Stereo/Control.swift','Sources/gor/Stereo/VR180Controller.swift','Sources/gor/Stereo/VRDistanceModel.swift','Sources/gor/Stereo/VRStereoControlInput.swift','Sources/gor/Stereo/GazeCrosshairController.swift','Sources/gor/Stereo/StereoLookNativeCommands.swift','Sources/gor/Stereo/StereoLookNativeInputOwner.swift','Sources/gor/Stereo/StereoLookNativeIntentAdapter.swift','Sources/gor/Picture/Viewport.swift','Sources/gor/Picture/CropDetector.swift','Sources/gor/UI/AdaptiveColor.swift','Sources/gor/Stereo/LookToolsRoute.swift','Sources/gor/Session/PlayerSessionBarrierAdapter.swift','Sources/gor/Session/PlayerSessionContext.swift','Sources/gor/Session/PlayerSessionDrainPlan.swift','Sources/gor/Session/PlayerSessionFileTransport.swift','Sources/gor/Session/PlayerSessionNativeSink.swift','Sources/gor/Session/PlayerSessionPipeDrain.swift','Sources/gor/Session/PlayerRuntimeResources.swift','Sources/gor/Session/PlayerTorrentEndpoint.swift','Sources/gor/Stereo/RealtimeProbe.swift','Sources/gor/App/Build.swift','Sources/gor/Session/Diag.swift','Sources/gor/Picture/Brightness.swift','Sources/gor/Subtitles/SubtitleView.swift','Sources/gor/Subtitles/LiveCaption.swift','Sources/gor/Platform/QuitChildKiller.swift','Sources/gor/Platform/Windowing.swift'}:data[rel]=(R/rel).read_bytes()
    elif rel=='Sources/gor/Player/Input.swift':data[rel]=(R/rel).read_bytes()
    else:data[rel]=git('show',source+':archive/gor/'+rel)
  for rel,b in data.items():q=root/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(b)
  env=dict(os.environ,GIT_AUTHOR_NAME='t',GIT_AUTHOR_EMAIL='t@t',GIT_COMMITTER_NAME='t',GIT_COMMITTER_EMAIL='t@t')
  def sh(*a):return subprocess.check_output(a,env=env,stderr=subprocess.STDOUT)
  sh('git','init','-q','-b','main',str(repo));sh('git','-C',str(repo),'add','.');sh('git','-C',str(repo),'commit','-qm','fixture');sh('git','-C',str(repo),'update-ref','refs/remotes/origin/main','HEAD')
  project=td/'project';shutil.copytree(root,project)
  stale={'Sources/gor/CameraPrivacyGate.swift':git('show','360851e6ea^:archive/gor/Sources/gor/CameraPrivacyGate.swift'),'Sources/gor/gor/PPController_Features.swift':git('show','f0691de86:archive/gor/Sources/gor/gor/PPController_Features.swift')}
  stale['Sources/gor/gor/ThreeD.swift']=git('show','f0691de86:archive/gor/Sources/gor/gor/ThreeD.swift')
  for old in ('InputController.swift','DragDropHandler.swift'):
   stale['Sources/gor/gor/'+old]=git('show','6d868ca794d1029a8d8ae77726d2e70ade04bcf7:archive/gor/Sources/gor/gor/'+old)
  if name=='controller-two-retry':stale={k:v for k,v in stale.items() if k.endswith(('InputController.swift','DragDropHandler.swift'))}
  for rel,b in stale.items():q=project/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(b)
  (project/'Packages/.DS_Store').write_bytes(b'mac junk')
  backup=project/'.gor-backups/261119-132538-pre-update';backup.mkdir(parents=True);(backup/'changes.txt').write_text('added\tSources/gor/Stereo/VR180Controller.swift\nadded\tSources/gor/Stereo/Source.swift\nadded\tSources/gor/Player/Input.swift\n')
  if name=='missing-controller-foundation':(backup/'changes.txt').write_text('added\tSources/gor/Stereo/VR180Controller.swift\nadded\tSources/gor/Stereo/Source.swift\n')
  if name=='controller-two-retry':
   (backup/'changes.txt').write_text('added\tSources/gor/Player/Input.swift\n')
   retry=project/'.gor-backups/261120-132538-pre-update';retry.mkdir(parents=True)
   (retry/'changes.txt').write_text('changed\tSources/gor/Player/Input.swift\n')
   saved=retry/'Sources/gor/Player/Input.swift';saved.parent.mkdir(parents=True);saved.write_bytes(data['Sources/gor/Player/Input.swift'])
  if name=='edited-threed':(project/'Sources/gor/gor/ThreeD.swift').write_bytes(b'edited')
  if name=='wrong-threed-replacement':(project/'Sources/gor/Stereo/Depth.swift').write_bytes(b'wrong')
  if name=='missing-threed-foundation':(backup/'changes.txt').write_text('added\tSources/gor/Stereo/VR180Controller.swift\n')
  if name=='edited-input':(project/'Sources/gor/gor/InputController.swift').write_bytes(b'edited')
  if name=='edited-dragdrop':(project/'Sources/gor/gor/DragDropHandler.swift').write_bytes(b'edited')
  if name=='wrong-controller-replacement':(project/'Sources/gor/Player/Input.swift').write_bytes(b'wrong')
  if name=='edited-pp':(project/'Sources/gor/gor/PPController_Features.swift').write_bytes(b'edited')
  if name=='edited-camera':(project/'Sources/gor/CameraPrivacyGate.swift').write_bytes(b'edited')
  if name=='unknown-swift':(project/'Sources/gor/unknown.swift').write_bytes(b'let u=1')
  if name=='unknown-package':(project/'Packages/unknown.dat').write_bytes(b'x')
  if name=='wrong-replacement':(project/'Sources/gor/Stereo/VR180Controller.swift').write_bytes(b'wrong')
  if name=='symlink':q=project/'Sources/gor/CameraPrivacyGate.swift';q.unlink();q.symlink_to(root/'Sources/gor/a.swift')
  if name=='backup-failure':shutil.rmtree(project/'.gor-backups');(project/'.gor-backups').write_text('not a directory')
  if name=='internal-directory-symlink':
   original=project/'Sources/gor'; moved=td/'external-gor';original.rename(moved);original.symlink_to(moved,target_is_directory=True)
  if name in ('symlink-project-root','symlink-external-ancestor'):
   if name=='symlink-project-root':
    alias=td/'project-alias';alias.symlink_to(project,target_is_directory=True);project=alias
   else:
    alias=td/'tmp-alias';alias.symlink_to(td,target_is_directory=True);project=alias/'project'
  before={str(x.relative_to(project)):x.read_bytes() for x in project.rglob('*') if x.is_file()}
  tip=sh('git','-C',str(repo),'rev-parse','HEAD').decode().strip()
  if name=='baseline-red':
   try:p.verify_installed(repo,tip,project)
   except p.Refusal:print('PASS',name);return
   raise AssertionError(name)
  ok=name in ('exact-green','controller-two-retry','symlink-project-root','symlink-external-ancestor')
  original_copy=shutil.copy2
  if name=='copy-failure':
   def fail_copy(*a,**k):raise OSError('injected backup failure')
   shutil.copy2=fail_copy
  try:r=p.record_delivery(repo,project,'main')
  except (p.Refusal,OSError):
   shutil.copy2=original_copy
   assert not ok,name
   assert not (project/p.RECORD).exists(),name
   after={str(x.relative_to(project)):x.read_bytes() for x in project.rglob('*') if x.is_file()}
   assert before==after,(name,'mutation on refusal')
   print('PASS',name);return
  assert ok,name
  for rel,b in stale.items():assert not (project/rel).exists()
  backup=sorted((project/'.gor-backups').glob('*-pre-update-retire'))[-1]
  journal=(backup/'changes.txt').read_text()
  for rel,b in stale.items():assert (backup/rel).read_bytes()==b;assert 'deleted\t'+rel+'\n' in journal
  p.verify_installed(repo,tip,project);prior=(project/p.RECORD).read_bytes();p.record_delivery(repo,project,'main');assert (project/p.RECORD).read_bytes()==prior
  assert (project/'Packages/.DS_Store').exists();assert 'Packages/.DS_Store' not in p.compiled_inputs(project)
  # Exercise existing rollback journal contract: added -> parked; deleted -> restored.
  for line in journal.splitlines():
   kind,rel=line.split('\t');q=project/rel
   if kind=='added' and q.exists():q.rename(td/('parked-'+q.name))
   elif kind=='deleted':q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(backup/rel,q)
  for rel,b in stale.items():assert (project/rel).read_bytes()==b
  if name=='controller-two-retry':assert not (project/'Sources/gor/Player/Input.swift').exists()
  else:assert not (project/'Sources/gor/Stereo/VR180Controller.swift').exists()
  print('PASS exact-green idempotence backup readback combined rollback .DS_Store filter')
for name in ['baseline-red','exact-green','edited-threed','wrong-threed-replacement','missing-threed-foundation','missing-controller-foundation','controller-two-retry','edited-pp','edited-input','edited-dragdrop','wrong-controller-replacement','edited-camera','unknown-swift','unknown-package','wrong-replacement','symlink','backup-failure','copy-failure','internal-directory-symlink','symlink-project-root','symlink-external-ancestor']:case(name)
legacy=git('show','f0691de86:archive/gor/build.sh').decode();assert '"$src_root/tools/gor_provenance.py" record-delivery "$sync_dir" "$project_root" "$branch"' in legacy
print('PASS native59 old-runner invokes NEW record-delivery before reexec')
