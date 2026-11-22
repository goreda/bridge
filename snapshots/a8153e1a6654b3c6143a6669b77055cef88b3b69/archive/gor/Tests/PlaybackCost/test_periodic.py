
# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import importlib.util,tempfile,json,subprocess,types,sys
sys.dont_write_bytecode=True
root=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('periodic',root/'tools/gor-periodic-capture.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
secret='SECRET_TOKEN_PRIVATE'
assert not m.extract('gor_direct.log','path=/Users/private/movie token='+secret+' password=123456')
row='[ts=2026-11-07T13:29:07.450Z cpu_temp_c=91.4] [mpv] Audio device underrun detected. /Users/private/'+secret
assert m.extract('gor_direct.log',row)==['2026-11-07T13:29:07.450Z mpv-underrun cpu_temp_c=91.4']
wt='[2026-11-07T13:29:07.450Z] WT_DIAG:{"kind":"http-latency","bytes":99,"password":123456,"token":"'+secret+'","url":"http://private","rangeStart":100,"completed":false}'
assert secret not in str(m.extract('wt_full.log',wt)) and 'bytes' in str(m.extract('wt_full.log',wt))
# v22.18: the payload metric and the SELF row must survive the typed whitelist;
# unknown/private fields of the same rows must not.
wt_stats='[2026-11-07T13:29:07.450Z] STATS:{"session":123,"downloaded":50,"receivedPayloadBytes":80,"refetchedBytes":30,"receivedTotalBytes":90,"token":"'+secret+'"}'
out=str(m.extract('wt_full.log',wt_stats))
assert 'receivedPayloadBytes":80' in out and 'refetchedBytes":30' in out and 'receivedTotalBytes":90' in out and secret not in out
wt_self='[2026-11-07T13:29:07.450Z] WT_DIAG:{"kind":"self","pid":123,"sha256":"'+'a'*64+'","version":"v22.18-dev","path":"/Users/private","token":"'+secret+'"}'
out=str(m.extract('wt_full.log',wt_self))
assert 'kind":"self"' in out and 'sha256":"'+'a'*64+'"' in out and 'version":"v22.18-dev"' in out and 'pid":123' in out
assert '/Users' not in out and secret not in out
wt_self_bad='[2026-11-07T13:29:07.450Z] WT_DIAG:{"kind":"self","pid":123,"sha256":"nothex","version":"../../etc"}'
out=str(m.extract('wt_full.log',wt_self_bad))
assert 'kind":"self"' in out and 'nothex' not in out and 'etc' not in out
assert m.extract('gor-wt-lag-1-1.txt','  + 502 utp_napi_close(napi_env__*, napi_callback_info__*)  (in node.napi.node) +232 /Users/private')==['stack samples=502 symbol=utp_napi_close']
three = """background-result: 3D-CHECK v1 verdict=FAIL rc=2 seconds=498 cli_complete=True selftest_exit=2 errors=1 token=SECRET_TOKEN_PRIVATE
3d-load end package=bootstrap_fp16.mlpackage device=cpuOnly elapsed_ms=30000 outcome=timeout path=/Users/private
 gor3d-selftest v1 error /Users/secret password=12345
"""
evidence='\n'.join(m.extract('gor_direct.log',three))
assert 'verdict=FAIL' in evidence and 'package=bootstrap_fp16.mlpackage' in evidence and 'outcome=timeout' in evidence
assert secret not in evidence and '/Users' not in evidence and 'password' not in evidence
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp);(p/'.git').mkdir();(p/'project').mkdir();(p/'config').mkdir()
 config=dict(repo=str(p),project=str(p/'project'),source='a'*40)
 cfg=p/'config.json';cfg.write_text(json.dumps(config))
 (p/'wt_full.log').write_text('[2026-11-07T13:29:07.450Z] STATS:{"session":123,"loopLagMs":1700,"numPeers":76}')
 (p/'gor_direct.log').write_text(row)
 (p/'gor_diag.log').write_text('playback-cost gor=44.0 mpv=99.0 ffmpeg=0.0 ffmpegWorkers=0 token='+secret+' password=123456')
 (p/'config/photon-grain-size.log').write_text('[photon] hint=1.2 token='+secret)
 (p/'gor-wt-lag-123-1.txt').write_text('  + 502 utp_napi_close(napi_env__*, napi_callback_info__*)  (in node.napi.node) +232')
 (p/'project/.gor-3d-check-background.log').write_text(three)
 (p/'config/scripts/macos').mkdir(parents=True);(p/'config/scripts/macos/vr180-look.lua').write_text('return {}')
 (p/'kit').mkdir();(p/'kit/kit_manifest.json').write_text('{}');(p/'kit/dummy.mlpackage').mkdir()
 config['config']=str(p/'config');config['kit_dir']=str(p/'kit');data=m.collect(config,321,root=p)
 for key in ['BEGIN wt_full.log','BEGIN gor_direct.log','BEGIN gor_diag.log','BEGIN gor_sample.txt','BEGIN photon-grain-size.log','BEGIN photon-grain-doc.log','utp_napi_close','loopLagMs','mpv-underrun','package=bootstrap_fp16.mlpackage','verdict=FAIL']:assert key in data,key
 import hashlib
 assert 'installed-script-sha256=macos/vr180-look.lua='+hashlib.sha256(b'return {}').hexdigest() in data
 assert 'kit kit_manifest.json='+hashlib.sha256(b'{}').hexdigest()+' packages=1' in data
 for key in [secret,'/Users','password','123456','http://']:assert key not in data,key
 # Exercise real runner loop with fixture Channel. No remote write occurs in this test.
 (p/'gor-capture-channel.py').write_text('''from pathlib import Path
class Channel:
 def __init__(self,repo):self.repo=Path(repo)
 def send(self,path):
  assert path.is_file()
  (self.repo/'ack').write_text(path.read_text())
''')
 m.identity=lambda pid:'owner' if not (p/'ack').exists() else 'gone'
 sleeps=[];m.time.sleep=lambda n:sleeps.append(n)
 m.subprocess.check_output=lambda *a,**kw:b'https://github.com/goreda/instinct.git\n'
 m.subprocess.run=lambda *a,**kw:types.SimpleNamespace(stdout=b'100 321 /app/mpv\n')
 original=m.collect;m.collect=lambda c,pid:original(c,pid,root=p)
 m.run(str(cfg),321,str(p/'config'))
 assert sleeps==[120] and (p/'ack').is_file()
 assert not list((p/'.git/gor-periodic-pending').glob('*.txt'))
 # Refuse alternate remote, no upload or sleep, existing bytes retained.
 (p/'ack').unlink();m.subprocess.check_output=lambda *a,**kw:b'https://other.invalid/repo\n'
 m.run(str(cfg),321,str(p/'config'));assert not (p/'ack').exists()
print('PASS real periodic collector covers WT/mpv/photon/gor/stack/captureidentity, numeric+symbol redaction,120s owned-child gating, approvedremote, queue ACK unlink; native background upload NOT_RUN')
build=_core_read(root/'build.sh');helper=build.split("<<'GOR_SESSION_HELPER'",1)[1].split('\nGOR_SESSION_HELPER',1)[0];compile(helper,'helper','exec')
assert "with_name('gor-periodic-capture.py')" in helper and 'gor-periodic-config.json' in build
# VR heat telemetry: die-max temp and VR flag survive the numeric filter and exist in source.
assert m.extract('gor_direct.log','[ts=2026-11-07T13:29:07.450Z cpu_temp_c=91.4 cpu_temp_max_c=94.2] [mpv] Audio device underrun detected.')==['2026-11-07T13:29:07.450Z mpv-underrun cpu_temp_c=91.4 cpu_temp_max_c=94.2']
assert m.extract('gor_diag.log','playback-cost gor=44.0 mpv=99.0 ffmpeg=0.0 ffmpegWorkers=0 vr=1 sampleEvery_s=10')==['playback-cost gor=44.0 mpv=99.0 ffmpeg=0.0 ffmpegWorkers=0 vr=1 sampleEvery_s=10']
assert 'vr=%d' in _core_read(root/'Sources/gor/GorCore/Diag.swift') and 'ThreadCpuDiag.vrMode = vrModeEnabled' in _core_read(_pp_split().path(root,'PPController_Features.swift'))
assert 'cpu_temp_max_c=' in _core_read(root/'build.sh')
# Compile-error regression (812287c05): the referenced type must be the enum that declares vrMode.
import re
_d=_core_read(root/'Sources/gor/GorCore/Diag.swift')
_e=re.search(r'enum (\w+) \{(?:(?!\n\}).)*?static var vrMode',_d,re.S).group(1)
assert _core_read(_pp_split().path(root,'PPController_Features.swift')).count(_e+'.vrMode')==1 and ' Diag.vrMode' not in _core_read(_pp_split().path(root,'PPController_Features.swift')),_e
# Runtime registration must survive a long numeric capture without exposing model paths/errors.
registration='3d-depth-runtime registered runner=NativePrepareRunner verified_manifest=0123456789abcdef depth=VDA_MoGe synthesis=dibr_golden'
assert m.depth_runtime_row(registration+' path=/Users/private token='+secret)==registration.replace(' registered runner=', ' registered=1 runner=')
assert m.depth_runtime_row('3d-kit-read FAIL package=/Users/private reason=relative_prefix_mismatch token='+secret)=='3d-kit-read failed=1 reason=relative_prefix_mismatch'
assert m.depth_runtime_row('3d-kit-read FAIL package='+secret+' reason=file_open_PRIVATE_123')=='3d-kit-read failed=1'
assert m.depth_runtime_row('3d-kit-verify FAIL expected_sha='+secret+' actual_sha='+secret)=='3d-kit-verify failed=1'
assert m.depth_runtime_row(registration.replace('NativePrepareRunner',secret)) is None
assert m.depth_runtime_row(registration.replace('dibr_golden',secret)) is None
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp);(p/'project').mkdir();(p/'config').mkdir();(p/'kit').mkdir()
 direct=p/'gor_direct.log'
 direct.write_text(registration+' path=/Users/private token='+secret+'\n'+'x'*300000+'\n3d-kit-read FAIL package='+secret+' reason=relative_prefix_mismatch\n3d-kit-verify FAIL package='+secret+' expected_sha='+secret+'\n')
 assert registration not in m.tail(direct),'fixture did not evict startup registration'
 rows='\n'.join(m.depth_runtime_evidence(direct))
 assert 'registered=1' in rows and 'verified_manifest=0123456789abcdef' in rows
 assert 'kit_read_fail_count=1' in rows and 'kit_verify_fail_count=1' in rows and 'reason=relative_prefix_mismatch count=1' in rows
 data=original(dict(project=str(p/'project'),config=str(p/'config'),kit_dir=str(p/'kit')),321,root=p)
 assert 'registered=1' in data and 'kit_read_fail_count=1' in data
 assert all(value not in data for value in (secret,'/Users','expected_sha','actual_sha'))
 direct.write_text('nothing relevant\n')
 assert 'NOT_RUN no_observed_runtime_evidence' in m.depth_runtime_evidence(direct)[0]
 assert 'registered=0' not in m.depth_runtime_evidence(direct)[0]
 assert m.depth_runtime_evidence(p/'absent')==[]
print('PASS real collect retains startup registration outside262KB tail, exact prefix failure plus numeric fail counts; private path/error/token mutants suppressed; missing evidence NOT_RUN not registered=0')
for stage in ('cuts-reader-close','cuts-persist','depth-setup','depth-boundary','thermal-pause','thermal-resumed'):
 row='gor3d-selftest-cli v1 progress stage='+stage+' done=1 total=3 t=90.0 path=/Users/private token='+secret
 filtered='\n'.join(m.extract('gor_direct.log',row))
 assert 'stage='+stage in filtered and 'done=1' in filtered and secret not in filtered and '/Users' not in filtered
print('PASS new cuts handoff and thermal stages survive typed collector without private suffix')
with tempfile.TemporaryDirectory() as temp:
 p=Path(temp);row=dict(t=1.5,raw=[0]*6,filtered=[.1]*6,euro=[.2]*6,bands=[.002]*6,pupils=[10,20,30,40],confidence=.9,faceLost=False,path='/Users/'+secret,token=secret)
 (p/'current.jsonl').write_text(json.dumps(row)+'\n')
 data='\n'.join(m.pose_trace_evidence(p))
 assert 'pupils' in data and 'bands' in data and 'euro' in data
 assert secret not in data and '/Users' not in data and 'token' not in data
 row['pupils']=[secret]*4;(p/'current.jsonl').write_text(json.dumps(row)+'\n')
 assert 'pupils' not in '\n'.join(m.pose_trace_evidence(p))
print('PASS192d numeric pose/pupil trace allowlist, malformed arrays/private suffix rejected')

with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'current.jsonl';p.write_text(json.dumps({'t':1,'filtered':[0]*6,'eyeHold':True,'eyeApertures':[.01,.02],'distanceMode':0,'private':'do not collect'})+'\n')
 row='\n'.join(m.pose_trace_evidence(Path(d)))
 assert 'eyeHold' in row and 'eyeApertures' in row and 'distanceMode' in row and 'private' not in row
print('PASS blink-hold/aperture and distance-source numeric capture, no private strings')

with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'current.jsonl';p.write_text(json.dumps({'t':1,'filtered':[0]*6,'frameQuality':[24,180,12,.2,.8,.03,1,0],'structureReason':2,'private':'secret'})+'\n')
 out='\n'.join(m.pose_trace_evidence(Path(d)))
 assert 'frameQuality' in out and 'structureReason' in out and 'secret' not in out
print('PASS structural hold and frame-quality allowlist, no image content or private strings')

with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'current.jsonl'
 obj=dict(t=2,filtered=[0]*6,pairedPupils=[1,2,3,4],eyeGeometry=[1,2,3,4],eyeWidths=[5,6],faceBox=[10,20,100,140],landmarkBox=[11,21,98,138],poseAngles=[.1,.2,.3],framePTS=1.9,resetSequence=2,action='recenter',traceSession='12345678-1234-1234-1234-123456789abc',traceBuild='a'*64,private=secret)
 p.write_text(json.dumps(obj)+'\n');out='\n'.join(m.pose_trace_evidence(Path(d)))
 for key in ['pairedPupils','eyeGeometry','eyeWidths','faceBox','landmarkBox','poseAngles','framePTS','resetSequence','action','traceSession','traceBuild']:assert key in out,key
 assert secret not in out
 for key in ['action','traceSession','traceBuild']:obj[key]=secret
 obj['eyeGeometry']=[1,2,3];p.write_text(json.dumps(obj)+'\n');out='\n'.join(m.pose_trace_evidence(Path(d)))
 for key in ['action','traceSession','traceBuild','eyeGeometry']:assert key not in out,key
print('PASS synchronized geometry/build/session/reset allowlist; malformed identifiers, partial geometry and arbitrary strings rejected')

with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'gor-convergence.jsonl'
 p.write_text(json.dumps(dict(t=1,sessionBirth=2,vr_fov=2.3,vr_base_ipd=.1,vr_ipd_nudge=.002,vr_pack=3,internal=0,titleStatAvailable=0,path=secret,vr_d3_gain=secret))+'\n')
 out='\n'.join(m.convergence_evidence(p))
 assert 'vr_fov' in out and 'titleStatAvailable' in out and 'internal' in out
 assert secret not in out and 'path' not in out and 'vr_d3_gain' not in out
print('PASS convergence uniform numeric allowlist excludes arbitrary strings, shader text and private paths')

#193c route evidence survives both log surfaces, arbitrary values never do.
for name in ('gor_diag.log','gor_direct.log'):
 text='''[mpv] 3D-LUA sender=store-applier message=vr180-look-set-pack revision=6 vr_source_layout=1 vr_flat_mono=0 vr_pack=3 values=/private/movie.mp4
3D-REJECTED sender=legacy-plannedLook message=vr180-look-set-projection values=/private/movie.mp4 revision=5 reason=revision
3D-REJECTED sender=/private/token message=/private/movie revision=none reason=/private/error
'''
 rows=m.extract(name,text)
 assert len(rows)==3 and any('vr_source_layout=1' in x and 'vr_pack=3' in x for x in rows)
 assert any('sender=legacy-plannedLook' in x and 'reason=revision' in x for x in rows)
 assert all('/private' not in x and 'values=' not in x for x in rows)
 assert len(m.extract(name,text*1000))==1200
print('PASS193c typed route fields preserved on bothlogsurfaces, arbitrary values redacted and1200rowbound')

for name in ('gor_diag.log','gor_direct.log'):
 rows=m.extract(name,'[vr180_look] Lua error: /private/movie/vr180-look.lua:629: flat store kind crossed native engine')
 assert rows==['3D-LUA-FAIL reason=flat_store_kind_crossed_native_engine'],rows
print('PASS193e fatalrouteinvariant survives periodiccapture withoutpath/traceback')

for name in ('gor_diag.log','gor_direct.log'):
 rows=m.extract(name,'3D-FILE-RESET path=/private/film.mp4\n3D-DROPPED reason=identityEmpty storeFilm=/private/id recognitionFilm=/private/id revision=9\n3D-DECISION path=store_applier film=/private/id source=flat2D engine=flat_full_sbs output=full_sbs pack=3 userTouched=true')
 assert len(rows)==3 and all('/private' not in x for x in rows)
 assert 'revision=9' in rows[1] and 'engine=flat_full_sbs' in rows[2]
print('PASS193f sessionreset/drop/storedecision capture no private IDs/paths')

rows=m.extract('gor_diag.log','vrOpenRoute film=private-id file=secret.mp4 generation=2 probe=ok metadata=none tag=none detected=flat2D\nvrProbeResult file=secret.mp4 generation=2 status=ok projection=none sbs=false tb=false\n3D-DECISION path=store_applier film=private-id source=vr180SBS engine=flat_full_sbs output=full_sbs pack=3')
assert len(rows)==3 and 'film_sha256=' in rows[0] and 'film_sha256=' in rows[2]
assert rows[0].split('film_sha256=')[1].split()[0]==rows[2].split('film_sha256=')[1].split()[0]
assert all('secret.mp4' not in row and 'private-id' not in row for row in rows)
print('PASS193i route/probe/storecorrelation hashes retainclassificationwithoutprivatepath/id')

row='3D-VERIFIED file=/Users/private/'+secret+' generation=3 revision=10 output=off engine=flat_off verdict=FAIL verification=route_state layout=0 pack=0 enabled=false expected_layout=0 expected_pack=3 expected_enabled=false token='+secret
filtered='\n'.join(m.extract('gor_diag.log',row))
for field in ('file_sha256=','revision=10','verdict=FAIL','verification=route_state','expected_pack=3'):assert field in filtered,filtered
assert secret not in filtered and '/Users' not in filtered,filtered
for family in ('3D-TRANSITION','3D-CLOSE'):
 assert family in '\n'.join(m.extract('gor_diag.log',row.replace('3D-VERIFIED',family)))
print('PASS193k typed per-transition receipt/negative/close collection retains correlation without private filenames')

filtered='\n'.join(m.extract('gor_diag.log',row+' playing_file=/Users/private/'+secret))
assert 'playing_file_sha256=' in filtered and secret not in filtered and '/Users' not in filtered,filtered
print('PASS193k actual playing file separately hashed, not confused with parent/source identity')
#194b exact installed-slot receipts and scrubbed raw checker/error diagnoses.
shader='3D-SHADER reason=route expected=extended installed=extended sha256='+'a'*64+' entry=/Users/private/config/epoch-17/vr180-look-shader-b.glsl verdict=PASS verification=installed_shader'
rows='\n'.join(m.extract('gor_direct.log',shader+' token='+secret+'\n3D-SHADER-MISMATCH expected=pack installed=legacy'))
assert 'sha256='+'a'*64 in rows and 'expected=pack installed=legacy' in rows
assert 'entry_basename=vr180-look-shader-b.glsl' in rows and 'entry_sha256=' in rows
assert '/Users' not in rows and secret not in rows and 'epoch-17' not in rows
import ast
fixture=ast.parse(_core_read(root/'Tests/DepthAnalysis/test_mac_log_check.py'))
good=next(ast.literal_eval(n.value) for n in fixture.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='GOOD' for t in n.targets))
mutant='\n'.join(l for l in good.replace('nan=0 inf=0','nan=2 inf=0').splitlines() if 'key=render_key_v4' not in l and 'key=first_3d_frame_sha256' not in l)
error='gor3d-selftest v1 error i=0 msg=coreml_load model failed code=17 path=/Users/private/model token='+secret+' url=https://private.invalid/'+secret
mutant=mutant.replace('gor3d-selftest v1 end errors=0',error+'\ngor3d-selftest v1 end errors=1')
sys.path.insert(0,str(root/'tools/depth_analysis'))
import mac_log_check as mlc
families=mlc.check_log(mutant.splitlines(),json.loads(_core_read(Path(mlc.stc.EXPECTED))))[0]
raw='\n'.join('checker: '+line for family in families for line in family.render())+'\n'+error
captured='\n'.join(m.extract('.gor-3d-check-background.log',raw))
for text in ('depth stats','error bucketing','render_key_v4','first_3d_frame_sha256','nan=2','coreml_load model failed code=17'):
 assert text in captured,(text,captured)
assert 'MISSING' in captured and 'FAIL' in captured and all(x not in captured for x in ('/Users','https://',secret))
for sensitive in ['password="'+secret+'"','Authorization: Bearer '+secret,'api_key='+secret,'cookie='+secret,'user@example.invalid','C:\\Users\\private\\'+secret,'file:///private/'+secret,'/Users/private/My Private Film '+secret+' 1.mp4 code=42']:
 assert secret not in m.scrub_checker_line(sensitive) and 'example.invalid' not in m.scrub_checker_line(sensitive)
assert len(m.extract('gor_direct.log','\n'.join(['checker: '+'x'*2000]*200)))==160
assert max(map(len,m.extract('gor_direct.log','checker: '+'x'*2000)))<=1200
assert not m.extract('gor_direct.log','arbitrary raw log secret='+secret)
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'project').mkdir();(p/'config').mkdir()
 (p/'project/.gor-3d-check-background.log').write_text(raw)
 (p/'gor_direct.log').write_text(shader)
 payload=original(dict(project=str(p/'project'),config=str(p/'config')),321,root=p)
 assert 'checker:' in payload and 'nan=2' in payload and '3D-SHADER reason=route' in payload
 assert all(x not in payload for x in ('/Users','https://',secret))
print('PASS194b real checker FAIL/MISSING/error diagnoses survive collect; installed shader hash/variant/mismatch retained; paths, URLs, emails and credentials scrubbed;160x1200 bounds')

render='3D-RENDER v1 event=finished generation=12 shot=3 published=false current=false path=/Users/private token='+secret
receipt='GOR-RGBD-UNIFORM v1 '+json.dumps(dict(verdict='PASS',platform='Darwin',mpv='mpv v0.42.0',base_sha256='a'*64,changed_sha256='b'*64,restored_sha256='a'*64,rollout=False,path='/Users/private',token=secret))
filtered='\n'.join(m.extract('gor_direct.log',render+'\n'+receipt))
assert 'generation=12' in filtered and 'published=false' in filtered and 'Darwin' in filtered and 'base_sha256' in filtered
assert secret not in filtered and '/Users' not in filtered
print('PASS194b prepared render generations and platform-labelled default-off uniform receipt survive privacy filter')

import importlib
subprocess=importlib.reload(subprocess)
# Transfer attribution: preserve only typed CDN timings, never endpoints or addresses.
cdn=dict(event='family-body-summary',ip_family='IPv4',requests=16,bytes=4096,total_body_ms=8000,mean_body_ms=500,rolling_samples=16,rolling_median_body_ms=480,rolling_p95_body_ms=1000,body_bytes_per_second=512,family_preference='IPv4-first',ipv6_fallback=True,url='https://private.invalid/'+secret,remoteAddress='1.2.3.4',token=secret)
filtered='\n'.join(m.extract('gor_direct.log','[mega_relay] CDN-EVIDENCE:'+json.dumps(cdn)))
for field in ('family-body-summary','IPv4','rolling_median_body_ms','total_body_ms','IPv4-first'):assert field in filtered
assert all(x not in filtered for x in (secret,'https://','1.2.3.4','private.invalid'))
cdn.update(event='upstream-request',ip_family='IPv6',body_ms=450.5,first_byte_ms=22,agent=dict(family_preference='IPv4-first',ipv6_fallback=True,token=secret))
assert 'first_byte_ms' in m.cdn_row('CDN-EVIDENCE:'+json.dumps(cdn))
cdn['body_ms']=secret;cdn['ip_family']=secret
assert secret not in m.cdn_row('CDN-EVIDENCE:'+json.dumps(cdn))
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);log=p/'check.log'
 marker='3D-CHECK run run_id='+'a'*32+' supervisor_pid=89240 worker_pid=89241 build_manifest='+'b'*64
 log.write_text(marker+'\n'+'noise\n'*60000+'3D-CHECK v1 verdict=FAIL errors=1\n')
 rows=m.extract('.gor-3d-check-background.log',m.checker_tail(log))
 assert 'run_id='+'a'*32 in rows[-1] and 'verdict=FAIL' in rows[-1]
 log.write_text('3D-CHECK v1 verdict=FAIL errors=1\n'+marker+'\n3D-CHECK v1 verdict=PASS errors=0\n')
 rows=m.extract('.gor-3d-check-background.log',m.checker_tail(log))
 assert 'run_id=unbound' in rows[0] and 'run_id='+'a'*32 in rows[-1]
 print('PASS checker run binding survives tail eviction; earlier unbound verdict never borrows a later run')
# Real git fixture checks frozen commit and production bytes, not a mocked SHA.
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);repo=p/'repo';project=repo/'archive/gor';res=p/'resources'
 (project/'Resources/vendor/mega_relay').mkdir(parents=True);res.mkdir()
 relay=project/'Resources/vendor/mega_relay/mega_relay.mjs';relay.write_text('fixture relay')
 (project/'Package.swift').write_text('fixture sources')
 subprocess.run(['git','init','-q',str(repo)],check=True)
 subprocess.run(['git','-C',str(repo),'add','.'],check=True)
 subprocess.run(['git','-C',str(repo),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','-qm','fixture'],check=True)
 snap=p/'snapshot.json';snap.write_text(json.dumps({'Package.swift':hashlib.sha256(b'fixture sources').hexdigest()}))
 m.write_build_provenance(project,repo,res,snap)
 receipt=json.loads(_core_read(res/'gor-build-provenance.json'))
 assert receipt['verification']=='snapshot-inputs-and-relay' and len(receipt['source_commit'])==40
 (res/'build-id.txt').write_text('commit='+'c'*64+'\nidentity_kind=source-manifest-sha256\n')
 (res/'vendor').symlink_to(project/'Resources/vendor',target_is_directory=True)
 data='\n'.join(m.build_evidence(res))
 assert 'relay_matches=true' in data and 'source_manifest_sha256='+'c'*64 in data
 relay.write_text('mutated live relay')
 assert 'relay_matches=false' in '\n'.join(m.build_evidence(res))
 m.write_build_provenance(project,repo,res,snap)
 assert json.loads(_core_read(res/'gor-build-provenance.json'))['verification']=='unverified'
print('PASS typed family-body timing and frozen source/relay provenance; endpoint/token mutants stripped, modified relay cannot claim verified commit')

for event in ('lane-start','lane-end','downstream-close','downstream-pressure','priority-state'):
 obj=dict(event=event,upstream_id=3,mono_ms=15.25,active_upstream=6,queued_upstream=2,background=False,queue_ms=0.4,served_bytes=99,cache_hits=3,local_push_blocked_ms=50,token=secret,url='https://private.invalid')
 row=m.cdn_row('CDN-EVIDENCE:'+json.dumps(obj))
 assert 'mono_ms' in row and 'active_upstream' in row and 'served_bytes' in row
 assert secret not in row and 'https://' not in row
print('PASS monotonic lane IDs/start/end, queue/cache/served/pressure counts retained; secrets and endpoints stripped')

for mode in ('A6','B12','default12'):
 row=m.cdn_row('CDN-EVIDENCE:'+json.dumps(dict(event='lane-start',mode=mode,phase=2,lookahead_slots=12,diagnostic=True,token=secret)))
 assert mode in row and 'lookahead_slots' in row and 'diagnostic' in row and secret not in row
print('PASS AB mode/phase/slot tags survive typed collector without private data')

for decision in ('trial','gain','no_gain','retain'):
 row=m.cdn_row('CDN-EVIDENCE:'+json.dumps(dict(event='capacity-search',decision=decision,**{'from':6,'to':8,'rate_bps':2034000,'baseline_bps':2030000},token=secret,url='https://private.invalid')))
 assert decision in row and 'rate_bps' in row and 'baseline_bps' in row
 assert secret not in row and 'https://' not in row
row=m.cdn_row('CDN-EVIDENCE:'+json.dumps(dict(event='capacity-search',decision=secret,rate_bps=secret)))
assert secret not in row
print('PASS measured capacity decisions/numeric supply retained; endpoint, token and malformed values stripped')

row=m.cdn_row('CDN-EVIDENCE:'+json.dumps(dict(event='capacity-search',foreground_window_slots=24,background_window_slots=6,token=secret)))
assert 'foreground_window_slots' in row and '24' in row and 'background_window_slots' in row and secret not in row
print('PASS live-cap foreground/background window counts retained without private data')

transport=dict(event='upstream-request',connection_id=7,route_id=2,socket_request_index=9,socket_read_watermark=65536,response_read_watermark=16384,body_rate_bps=300000,body_chunks=120,body_chunk_min=1024,body_chunk_max=16384,body_gap_max_ms=54.5,tcp_receive_buffer_status='unsupported-node-tcp-api',remote_address='1.2.3.4',url='https://private.invalid',token=secret)
row=m.cdn_row('CDN-EVIDENCE:'+json.dumps(transport))
for key in transport:
 if key not in ('remote_address','url','token'):assert key in row
assert all(x not in row for x in ('1.2.3.4','https://',secret))
for key in transport:
 if key=='event':continue
 bad=dict(transport);bad[key]=secret
 assert secret not in m.cdn_row('CDN-EVIDENCE:'+json.dumps(bad))
print('PASS transport numeric route/socket/read/body stats; unsupported kernel-buffer status explicit; private endpoint/string mutants stripped')

for event in ['owner-acquire','owner-release','start-request','stop-request','stop-pending','delegate','state-stopping','hardware-stopped']:
 row='HEAD-CAPTURE event='+event+' owner=3 consumers=0 generation=44 attached=false elapsed_s=2 path=/Users/private token='+secret
 evidence=' '.join(m.extract('gor_diag.log',row))
 assert 'event='+event in evidence and 'owner=3' in evidence and 'attached=false' in evidence and 'elapsed_s=2' in evidence
 assert secret not in evidence and '/Users' not in evidence
print('PASS named numeric camera lifecycle receipts survive periodic redaction without paths/secrets')
