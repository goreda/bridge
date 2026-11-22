#!/usr/bin/env python3
"""Fresh-process Mac reproduction: ordinary2D -> 2D3D -> SBS -> Off. No ffprobe dependency."""
import hashlib,json,os,subprocess,sys,time
from pathlib import Path
from axes_acceptance import live_gor_instances,FIXTURE_SHA
STEPS=('ordinary_off','twoD_to_threeD','sbs','vr180','sbs_return','off')
SWIFT_RECEIPT='user-data/gor/3d-applied-state'
LUA_RECEIPT='user-data/vr180-look/applied-state'

def child_environment(directory,native):
    # Menu/route acceptance owns its inputs. Live eye gestures can seek past the
    # short fixture into another queued film. Keep blink state/callbacks installed,
    # but use the existing test-only camera opt-out, never an owner preference.
    return dict(os.environ,GOR_NO_ACTIVATE="1",GOR_VR_TEST_NO_CAMERA="1",
                GOR_OWNER_ACTION_DIR=str(directory),GOR_OWNER_ACTION_NATIVE='1' if native else '0')

def evaluate(step,action,properties,pid,manifest,launched,fixture=None):
    if action.get('pid')!=pid or action.get('build')!=manifest or action.get('timestamp',0)<launched:
        return 'FAIL','fresh_process_identity_mismatch'
    if not action.get('menu_driven'):return 'FAIL','menu_action_not_driven'
    if fixture is not None:
        if 'path' not in properties:return 'NOT_RUN','fixture_path_missing'
        if properties['path']!=str(fixture):return 'FAIL','fixture_path_changed'

    for field in (SWIFT_RECEIPT,LUA_RECEIPT,'user-data/vr180-look/enabled'):
        if field not in properties:return 'NOT_RUN','ipc_missing_'+field
    # Applied schemas are mandatory, not inferred from sent commands.
    applied,lua=properties[SWIFT_RECEIPT],properties[LUA_RECEIPT]
    if isinstance(applied,str):
        try:applied=json.loads(applied)
        except ValueError:return 'NOT_RUN','swift_receipt_invalid'
    if isinstance(lua,str):
        try:lua=json.loads(lua)
        except ValueError:return 'NOT_RUN','lua_receipt_invalid'
    required=('pid','build','timestamp','stereoSource','engine','output','vr_mode')
    if not isinstance(applied,dict) or any(k not in applied for k in required):return 'NOT_RUN','swift_receipt_schema_missing'
    if not isinstance(lua,dict) or any(k not in lua for k in ('source_layout','flat_pack','plan_lock','enabled')):return 'NOT_RUN','lua_receipt_schema_missing'
    if applied['pid']!=pid or applied['build']!=manifest or applied['timestamp']/1000<(launched if step.startswith('roll_') else action['timestamp']-2):return 'FAIL','applied_receipt_stale'
    revision=action.get('revision')
    if revision is None or not isinstance(applied.get('revision'),int) or applied['revision']<revision or lua.get('revision')!=applied['revision'] or lua.get('completed_revision')!=applied['revision']:return 'NOT_RUN','route_revision_incomplete'
    if lua['enabled']!=properties['user-data/vr180-look/enabled']:return 'NOT_RUN','route_enabled_incoherent'
    if step.startswith('roll_'):
        if applied['engine']!='nativeVR180' or lua['source_layout']!=3 or lua['flat_pack']!=0:return 'FAIL','roll_not_native_pack_zero'
        shaders=properties.get('glsl-shaders');options=properties.get('glsl-shader-opts')
        if not isinstance(shaders,list) or not isinstance(options,dict):return 'NOT_RUN','shader_options_schema_missing'
        active=[Path(path).stem for path in shaders if Path(path).stem in ('vr180-look-shader-a','vr180-look-shader-b')]
        if len(active)!=1:return 'NOT_RUN','active_shader_slot_unresolved'
        value=options.get(active[0]+'/vr_roll')
        if value is None:return 'NOT_RUN','active_shader_roll_missing'
        try:roll=float(value)
        except (ValueError,TypeError):return 'NOT_RUN','roll_invalid'
        if abs(roll-(0 if step=='roll_zero' else 0.174532925))>1e-6:return 'FAIL','raw_roll_not_immediate'
        return 'PASS','raw_roll_matches_0_or_10deg_no_optical_verdict'
    if step.startswith('native_'):
        if applied['stereoSource']!='vr180':return 'FAIL','native_source_identity_mismatch'
        if step=='native_off':
            #191u raw Off removes presentation geometry; remembered film source remains VR180.
            if applied['output']!='off' or applied['engine']!='flat_off' or applied['vr_mode'] or lua['source_layout']!=0 or lua['flat_pack']!=0 or lua['plan_lock'] is not None or lua['enabled'] or properties['user-data/vr180-look/enabled']:return 'FAIL','native_off_not_applied'
            shaders=properties.get('glsl-shaders')
            if not isinstance(shaders,list):return 'NOT_RUN','native_off_shader_receipt_missing'
            if any(Path(path).stem.startswith('vr180-look') for path in shaders):return 'FAIL','native_off_look_shader_still_installed'
        else:
            if lua['source_layout']!=3 or lua['flat_pack']!=0:return 'FAIL','native_projection_or_pack_mismatch'
            if applied['engine']!='nativeVR180' or applied['output']!='vr180' or not applied['vr_mode'] or not lua['enabled']:return 'FAIL','native_enable_not_applied'
        return 'PASS','native_state_matches_action'
    if action.get('source')!='flat2D':return 'FAIL','store_source_not_flat2d'
    if applied['stereoSource']!='flat' or applied['engine']=='nativeVR180':return 'FAIL','ordinary_film_became_native_vr180'
    if lua['source_layout']!=0:return 'FAIL','lua_source_not_flat2d'
    if step in ('ordinary_off','off'):
        if applied['output']!='off' or applied['engine']!='flat_off' or applied['vr_mode'] or lua['flat_pack']!=0 or lua['plan_lock'] is not None or lua['enabled'] or properties['user-data/vr180-look/enabled']:return 'FAIL','off_not_applied'
    if step in ('sbs','sbs_return'):
        if applied['output']!='full_sbs' or applied['engine']!='flat_full_sbs' or not applied['vr_mode'] or lua['flat_pack']!=3 or not lua['enabled'] or not properties['user-data/vr180-look/enabled']:return 'FAIL','sbs_not_applied'
    if step=='vr180':
        if applied['output']!='vr180' or applied['engine']!='twoDVR180' or not applied['vr_mode'] or not lua['enabled']:return 'FAIL','twoD_vr180_not_flat_virtual_screen'
        if lua['flat_pack']!=3:return 'FAIL','twoD_vr180_not_flat_sbs_pack'
    if step=='twoD_to_threeD':
        if applied['output'] not in ('full_sbs','half_sbs') or applied['engine']!='flat_'+applied['output'] or not applied['vr_mode'] or lua['flat_pack']!=3 or not lua['enabled'] or not properties['user-data/vr180-look/enabled']:return 'FAIL','enable_not_flat_sbs'
    return 'PASS','applied_state_matches_action'

def run(root,native=False):
    root=Path(root).resolve();binary=root/'gor.app/Contents/MacOS/gor'
    fixture=root/'tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4'
    for label,path in [('binary',binary),('fixture',fixture),('build_id',root/'gor.app/Contents/Resources/build-id.txt')]:
        if not path.is_file():raise ValueError('missing_'+label)
    if hashlib.sha256(fixture.read_bytes()).hexdigest()!=FIXTURE_SHA:raise ValueError('fixture_hash_mismatch')
    if live_gor_instances(binary):raise ValueError('interactive_gor_running_refused')
    manifest=next((line[7:].strip() for line in (root/'gor.app/Contents/Resources/build-id.txt').read_text().splitlines() if line.startswith('commit=')),None)
    if not manifest:raise ValueError('installed_manifest_missing')
    directory=root/'.gor-owner-action'/str(time.time_ns());directory.mkdir(parents=True)
    steps=('native_vr180','native_off','native_reenable','roll_zero','roll_legacy','roll_extended') if native else STEPS
    if native:
        from store_acceptance import mp4_spherical_patch
        tagged=directory/'tagged_public_vr180.mp4';tagged.write_bytes(mp4_spherical_patch(fixture.read_bytes()));fixture=tagged
    launched=time.time()
    # The fixture is a test-only path; no owner film or global fine-tune preference is changed.
    with (directory/'runner.log').open('w') as log:
        child=subprocess.Popen([str(binary),str(fixture)],env=child_environment(directory,native),stdin=subprocess.DEVNULL,stdout=log,stderr=log,start_new_session=True)
        start_text=subprocess.check_output(['ps','-p',str(child.pid),'-o','lstart='],text=True,timeout=3).strip()
        identity=dict(pid=child.pid,process_start=start_text,launch_timestamp=launched,installed_manifest=manifest,binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest())
        (directory/'launch.json').write_text(json.dumps(identity,indent=2))
        try:
            deadline=time.monotonic()+60
            while not (directory/'complete.json').is_file():
                if child.poll() is not None:raise ValueError('fresh_process_exited')
                if time.monotonic()>deadline:raise ValueError('action_deadline')
                time.sleep(.2)
            complete=json.loads((directory/'complete.json').read_text())
            if complete.get('verdict')=='NOT_RUN':raise ValueError(complete.get('reason','readiness_unknown'))
            flush_deadline=time.monotonic()+8
            while time.monotonic()<flush_deadline and any(not (directory/step/'frame.png').is_file() for step in steps):time.sleep(.2)
            verdicts=[]
            for step in steps:
                action=json.loads((directory/step/'action.json').read_text());receipt=json.loads((directory/step/'ipc.json').read_text())
                fields=receipt['fields'];props={fields[int(row['request_id'])-1]:row.get('data') for row in receipt['replies'] if row.get('error')=='success' and isinstance(row.get('request_id'),int) and 0<int(row['request_id'])<=len(fields)}
                verdict,reason=evaluate(step,action,props,child.pid,manifest,launched,fixture=fixture)
                if not (directory/step/'frame.png').is_file() and verdict=='PASS':verdict,reason='NOT_RUN','frame_missing'
                verdicts.append(dict(step=step,verdict=verdict,reason=reason))
                print('3D-OWNER-ACTION step=%s verdict=%s reason=%s pid=%s build=%s'%(step,verdict,reason,child.pid,manifest),flush=True)
            from owner_action_capture_grep import collect
            (directory/'routing-grep.txt').write_text(collect([directory/'runner.log','/tmp/gor_diag.log','/tmp/gor_direct.log']))
            (directory/'verdict.json').write_text(json.dumps(dict(identity=identity,steps=verdicts),indent=2))
            return 0 if all(v['verdict']=='PASS' for v in verdicts) else 1
        finally:
            # Always retain progress and diagnostics, including a readiness/action timeout.
            print('3D-OWNER-ACTION evidence='+str(directory),flush=True)
            for partial in sorted(directory.rglob('*.json')):
                if partial.name in ('readiness.json','action.json','ipc.json','complete.json'):
                    print('3D-OWNER-ACTION partial=%s data=%s'%(partial.relative_to(directory),partial.read_text().replace('\n',' ')),flush=True)
            from owner_action_capture_grep import collect
            diagnostic=collect([directory/'runner.log','/tmp/gor_diag.log','/tmp/gor_direct.log'])
            (directory/'routing-grep.txt').write_text(diagnostic)
            print(diagnostic,flush=True)
            if child.poll() is None:
                child.terminate()
                try:child.wait(timeout=10)
                except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
if __name__=='__main__':
    try:sys.exit(run(sys.argv[1],native='--native' in sys.argv[2:]))
    except Exception as error:print('3D-OWNER-ACTION verdict=NOT_RUN reason='+str(error),flush=True);sys.exit(2)
