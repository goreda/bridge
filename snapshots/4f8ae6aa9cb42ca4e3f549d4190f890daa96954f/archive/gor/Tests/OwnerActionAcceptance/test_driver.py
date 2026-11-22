import sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
import owner_action_acceptance as d
now=time.time();action=dict(pid=123,build='abc',timestamp=now,menu_driven=True,source='flat2D',revision=4)
props={d.SWIFT_RECEIPT:dict(pid=123,build='abc',timestamp=now*1000,revision=4,stereoSource='flat',engine='flat_full_sbs',output='full_sbs',vr_mode=True),d.LUA_RECEIPT:dict(source_layout=0,flat_pack=3,plan_lock=None,enabled=True,revision=4,completed_revision=4),'user-data/vr180-look/enabled':True}
assert d.evaluate('sbs',action,props,123,'abc',now-1)[0]=='PASS'
assert d.evaluate('sbs',action,{},123,'abc',now-1)[0]=='NOT_RUN'
assert d.evaluate('sbs',action,props,999,'abc',now-1)[0]=='FAIL'
props[d.SWIFT_RECEIPT]['engine']='nativeVR180'
assert d.evaluate('sbs',action,props,123,'abc',now-1)[0]=='FAIL'
props[d.SWIFT_RECEIPT].update(engine='flat_off',output='off',vr_mode=False)
assert d.evaluate('off',action,props,123,'abc',now-1)[0]=='FAIL'
props[d.LUA_RECEIPT].update(enabled=False,flat_pack=0);props['user-data/vr180-look/enabled']=False
assert d.evaluate('off',action,props,123,'abc',now-1)[0]=='PASS'
assert d.evaluate('ordinary_off',action,props,123,'abc',now-1)[0]=='PASS'
props[d.SWIFT_RECEIPT].update(engine='flat_half_sbs',output='half_sbs',vr_mode=True)
props[d.LUA_RECEIPT].update(enabled=True,flat_pack=3);props['user-data/vr180-look/enabled']=True
assert d.evaluate('twoD_to_threeD',action,props,123,'abc',now-1)[0]=='PASS'
props[d.SWIFT_RECEIPT].update(engine='twoDVR180',output='vr180')
assert d.evaluate('twoD_to_threeD',action,props,123,'abc',now-1)[0]=='FAIL'
assert d.evaluate('vr180',action,props,123,'abc',now-1)[0]=='PASS'
props[d.LUA_RECEIPT]['flat_pack']=4
assert d.evaluate('vr180',action,props,123,'abc',now-1)[0]=='FAIL'
props[d.SWIFT_RECEIPT].update(stereoSource='vr180',engine='nativeVR180',output='vr180',vr_mode=True)
props[d.LUA_RECEIPT].update(source_layout=3,flat_pack=0,enabled=True)
assert d.evaluate('native_vr180',action,props,123,'abc',now-1)[0]=='PASS'
props[d.LUA_RECEIPT]['flat_pack']=4
assert d.evaluate('native_vr180',action,props,123,'abc',now-1)[0]=='FAIL'
props[d.LUA_RECEIPT]['flat_pack']=0
props['glsl-shaders']=['/tmp/vr180-look-shader-b.glsl']
props['glsl-shader-opts']={'vr180-look-shader-b/vr_roll':'0.174532925'}
assert d.evaluate('roll_legacy',action,props,123,'abc',now-1)[0]=='PASS'
props['glsl-shader-opts']['vr180-look-shader-b/vr_roll']='0.01'
assert d.evaluate('roll_extended',action,props,123,'abc',now-1)[0]=='FAIL'
print('PASS 15 owner-action verdict cases')

source=(Path(__file__).resolve().parents[2]/"tools/owner_action_acceptance.py").read_text()
assert "'ipc.json','complete.json'" in source, "failed applied-state checks must retain actual IPC receipts"

props[d.SWIFT_RECEIPT].update(timestamp=(now-100)*1000)
assert d.evaluate("roll_legacy",action,props,123,"abc",now-1)==("FAIL","applied_receipt_stale")
props[d.SWIFT_RECEIPT]["timestamp"]=now # seconds mistakenly published into millisecond contract
assert d.evaluate("roll_legacy",action,props,123,"abc",now-1)==("FAIL","applied_receipt_stale")
print("PASS millisecond schema rejects stale and wrong-unit receipts")

# Real 14:06:53 Mac receipt: raw Off keeps source identity but clears presentation.
import copy
props[d.SWIFT_RECEIPT].update(timestamp=now*1000,stereoSource='vr180',engine='flat_off',output='off',vr_mode=False)
props[d.LUA_RECEIPT].update(source_layout=0,flat_pack=0,plan_lock=None,enabled=False)
props['user-data/vr180-look/enabled']=False
props['glsl-shaders']=['/tmp/photon-grain.glsl','/tmp/photon-sharp.glsl']
assert d.evaluate('native_off',action,props,123,'abc',now-1)[0]=='PASS'
for key,value in [('source_layout',3),('flat_pack',3),('enabled',True),('plan_lock','off')]:
 bad=copy.deepcopy(props);bad[d.LUA_RECEIPT][key]=value
 assert d.evaluate('native_off',action,bad,123,'abc',now-1)[0] in ('FAIL','NOT_RUN'),(key,value)
bad=copy.deepcopy(props);bad['glsl-shaders'].append('/tmp/vr180-look-shader-b.glsl')
assert d.evaluate('native_off',action,bad,123,'abc',now-1)==('FAIL','native_off_look_shader_still_installed')
bad=copy.deepcopy(props);del bad['glsl-shaders']
assert d.evaluate('native_off',action,bad,123,'abc',now-1)[0]=='NOT_RUN'
print('PASS native raw-Off receipt and six stale/missing/installed-shader mutants')

# 192z real Mac failure: SBS had applied, then a live eye-gesture seek60 changed
# the short fixture to a different queued film. Do not report that as an SBS error.
import os
before=dict(os.environ)
os.environ['GOR_VR_TEST_NO_CAMERA']='0'
for native in (False,True):
 child=d.child_environment('/tmp/action-fixture',native)
 assert child['GOR_VR_TEST_NO_CAMERA']=='1' and child['GOR_NO_ACTIVATE']=='1'
 assert child['GOR_OWNER_ACTION_NATIVE']==('1' if native else '0')
 assert os.environ['GOR_VR_TEST_NO_CAMERA']=='0','child isolation mutated parent environment'
os.environ.clear();os.environ.update(before)
fixture='/tmp/tos_input_320x180_48f.mp4'
props[d.SWIFT_RECEIPT].update(stereoSource='flat',engine='flat_full_sbs',output='full_sbs',vr_mode=True)
props[d.LUA_RECEIPT].update(source_layout=0,flat_pack=3,enabled=True)
props['user-data/vr180-look/enabled']=True
props['path']=fixture
assert d.evaluate('sbs_return',action,props,123,'abc',now-1,fixture)==('PASS','applied_state_matches_action')
props['path']='/tmp/tos_t1_mlbw_l2_inpaint_video.mp4'
props[d.SWIFT_RECEIPT].update(engine='flat_off',output='off',vr_mode=False)
assert d.evaluate('sbs_return',action,props,123,'abc',now-1,fixture)==('FAIL','fixture_path_changed')
del props['path']
assert d.evaluate('sbs_return',action,props,123,'abc',now-1,fixture)==('NOT_RUN','fixture_path_missing')
assert 'fixture=fixture' in source,'real runner must verify the launched fixture path'
print('PASS192z isolated child inputs, unchanged parent environment and wrong/missing fixture mutants')

#193d a completed same-revision route, not elapsed time, gates acceptance.
props['path']=fixture
props[d.SWIFT_RECEIPT].update(engine='flat_full_sbs',output='full_sbs',vr_mode=True,timestamp=now*1000)
for target,key,value in [(d.SWIFT_RECEIPT,'revision',3),(d.LUA_RECEIPT,'revision',3),(d.LUA_RECEIPT,'completed_revision',None)]:
 bad=copy.deepcopy(props);bad[target][key]=value
 assert d.evaluate('sbs',action,bad,123,'abc',now-1,fixture)==('NOT_RUN','route_revision_incomplete')
bad=copy.deepcopy(props);bad[d.LUA_RECEIPT]['enabled']=False
assert d.evaluate('twoD_to_threeD',action,bad,123,'abc',now-1,fixture)==('NOT_RUN','route_enabled_incoherent')
print('PASS193d stale/midbatch/incoherent receipts never acceptancePASS')

#193g later recognition revisions may supersede the action, never mix receipts.
props[d.SWIFT_RECEIPT].update(revision=6)
props[d.LUA_RECEIPT].update(revision=6,completed_revision=6)
assert d.evaluate('sbs',action,props,123,'abc',now-1,fixture)[0]=='PASS'
props[d.SWIFT_RECEIPT].update(engine='flat_off',output='off',vr_mode=False)
props[d.LUA_RECEIPT].update(enabled=False,flat_pack=0);props['user-data/vr180-look/enabled']=False
assert d.evaluate('sbs',action,props,123,'abc',now-1,fixture)[0]=='FAIL'
print('PASS193g coherentlaterrevision accepted, laterwrongmode stillFAIL')
