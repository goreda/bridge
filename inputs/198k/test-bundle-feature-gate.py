#!/usr/bin/env python3
import importlib.util,tempfile,hashlib,json,subprocess,sys
sys.dont_write_bytecode=True
from pathlib import Path
spec=importlib.util.spec_from_file_location('gate',Path(__file__).with_name('bundle-feature-gate.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def photon_receipt(exe,resources):
 h='bc9a2a32e522a600cc24f08686f47932ba376eb7d99f79dfdd9beffe17c0ee8a'
 return dict(result='PASS',executable_sha256=m.sha(exe),resource_files_sha256=hashlib.sha256(json.dumps(m.inspect_resources(resources)['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest(),shipped_path=dict(source_pin='15acf95cec7bf0ea668b4eec1750d4f49455a82c',platform='Darwin',mpv_sha256='fixture-only',vo='gpu-next',gpu_api='fixture-only',mpv_conf_sha256='fixture-only'),all_photon_shader_hashes=[h,'synthetic-grain-sha'],shader_results=[dict(shader_sha256=h,parse_ok=False,compile_ok=False,max_delta_from_bypass=0),dict(shader_sha256='synthetic-grain-sha',parse_ok=True,compile_ok=True,max_delta_from_bypass=7)],glsl_shaders_after_load=['spatial-fallback'],changing_frame_fixture_sha256='fixture-only',history_result='NOT_PROVEN',lua_swift_twins='PASS',corrupt_shader_fixture=dict(fallback_role='sharp',log_association_verified=True,no_recursion_latch=True,grain=dict(shader_role='grain',shader_sha256='synthetic-grain-sha',parse_ok=True,compile_ok=True,entry_preserved_after_shared_set=True,max_delta_from_bypass=7),deliberately_corrupt=True,parse_failed=True,fallback_engaged=True,fallback_shader_sha256='aa949d3bf1eb4812c32589121e8f046ec6951f82c563270f4c91efa3b9312bdb',max_delta_from_bypass=19,warn_error_subscription=True,effective_shader_list_verified=True,state_failure_hash_recorded=True,hud_failure_shown=True,fallback_active_in_shader_list=True,raw_log_sha256='fixture-only'))

with tempfile.TemporaryDirectory()as d:
 p=Path(d);bundle=p/'gor.app';exe=bundle/'Contents/MacOS/gor';exe.parent.mkdir(parents=True);exe.write_text('synthetic executable')
 resources=p/'Resources';resources.mkdir();lua=resources/'photon.lua';lua.write_text('mp.register_script_message("photon-toggle", handler)\nlocal p=common.shader_path("photon-grain")\n');conf=resources/'input.conf';conf.write_text('g script-message photon-toggle\n')
 b=dict(status='BUILT_AND_RUNTIME_ATTESTED',built_bundle_files=['Contents/MacOS/gor'],resource_files={'Resources/photon.lua':'fixture','Resources/input.conf':'fixture'},input_bindings={'input.conf':['g script-message photon-toggle']},script_messages={'photon.lua':['photon-toggle']},photon_injected_shader_names={'photon.lua':['photon-grain']},runtime_features={'menus':['Photon grain'],'panels':['Photon'],'shader_names':['photon-grain']})
 runtime=dict(executable_sha256=m.sha(exe),features=b['runtime_features'],photon_no_silent_bypass=photon_receipt(exe,resources))
 assert m.compare(b,bundle,resources,runtime)['result']=='PASS';print('PASS complete synthetic closure and runtime fixture')
 for kind in ['file','binding','message','shader','menu','runtime-hash','baseline-attestation']:
  bb=json.loads(json.dumps(b));rr=json.loads(json.dumps(runtime));old=lua.read_text();oldc=conf.read_text()
  if kind=='file':lua.unlink()
  elif kind=='binding':conf.write_text('')
  elif kind=='message':lua.write_text(old.replace('mp.register_script_message','no_registration'))
  elif kind=='shader':lua.write_text(old.replace('common.shader_path','no_shader'))
  elif kind=='menu':rr['features']['menus']=[]
  elif kind=='runtime-hash':rr['executable_sha256']='wrong'
  else:bb['status']='SOURCE_ONLY'
  result=m.compare(bb,bundle,resources,rr);assert result['result']=='FAIL',kind;print('EXPECTED FAIL',kind,json.dumps({'removed':result['removed'],'errors':result['errors']}));lua.write_text(old);conf.write_text(oldc)
 print('PASS deliberately failing removal tests; fixture-only, no built product acceptance')

approved=m.approved_removals(Path(__file__).with_name('REMOVALS.md'))
assert approved=={'photon-grain-set-strength-hint','photon-grain-set-strength-mult','photon-grain-proxy-strength','photon-grain-set-size-hint'}
assert 'photon-grain-strength-resume' not in approved and 'photon-grain-set-strength-proxy' not in approved
print('PASS approved internal-name mapping only; resume and nonexistent proxy spelling excluded')

opts=m.approved_option_removals(Path(__file__).with_name('REMOVALS.md'))
assert opts=={'photon-grain_floor_480p','photon-grain_ceiling_480p'}
with tempfile.TemporaryDirectory()as d:
 p=Path(d);bundle=p/'gor.app';exe=bundle/'Contents/MacOS/gor';exe.parent.mkdir(parents=True);exe.write_text('fixture');resources=p/'Resources';resources.mkdir();lua=resources/'photon.lua';lua.write_text('local opts={ ["photon-grain_other_manual"]=1 }')
 b=dict(status='BUILT_AND_RUNTIME_ATTESTED',built_bundle_files=['Contents/MacOS/gor'],resource_files={'Resources/photon.lua':'fixture'},input_bindings={},script_messages={},photon_injected_shader_names={},runtime_features={'menus':['Photon']},script_options=sorted(opts))
 r=dict(executable_sha256=m.sha(exe),features={'menus':['Photon']},photon_no_silent_bypass=photon_receipt(exe,resources))
 assert m.compare(b,bundle,resources,r)['result']=='FAIL'
 assert m.compare(b,bundle,resources,r,approved_options=opts)['result']=='PASS'
 b['script_options'].append('photon-grain_other_manual');lua.write_text('')
 assert m.compare(b,bundle,resources,r,approved_options=opts)['result']=='FAIL'
 print('PASS exact two patch opts allowed; unapproved manual option removal refused')

with tempfile.TemporaryDirectory()as d:
 p=Path(d);exe=p/'gor';exe.write_text('fixture');resources=p/'Resources';resources.mkdir();(resources/'photon.lua').write_text('-- synthetic fixture')
 good=photon_receipt(exe,resources);actual=m.inspect_resources(resources)
 assert not m.no_silent_bypass_errors({'photon_no_silent_bypass':good},exe,actual)
 mutations=['missing','wrong-exe','wrong-closure','not-darwin','missing-phase2','table-incomplete','zero-delta','no-fallback','wrong-fallback','no-state','no-hud','no-logs','no-history','no-twins','grain-zero','grain-wrong-role','grain-missing-entry','no-latch']
 for kind in mutations:
  r=json.loads(json.dumps(good))
  if kind=='missing':r={}
  elif kind=='wrong-exe':r['executable_sha256']='wrong'
  elif kind=='wrong-closure':r['resource_files_sha256']='wrong'
  elif kind=='not-darwin':r['shipped_path']['platform']='Linux'
  elif kind=='missing-phase2':r['all_photon_shader_hashes']=[]
  elif kind=='table-incomplete':r['shader_results']=[]
  elif kind=='zero-delta':r['corrupt_shader_fixture']['max_delta_from_bypass']=0
  elif kind=='no-fallback':r['corrupt_shader_fixture']['fallback_engaged']=False
  elif kind=='wrong-fallback':r['corrupt_shader_fixture']['fallback_shader_sha256']='wrong'
  elif kind=='no-state':r['corrupt_shader_fixture']['state_failure_hash_recorded']=False
  elif kind=='no-hud':r['corrupt_shader_fixture']['hud_failure_shown']=False
  elif kind=='no-logs':r['corrupt_shader_fixture']['raw_log_sha256']=''
  elif kind=='no-history':r['history_result']=''
  elif kind=='no-twins':r['lua_swift_twins']='NOT_RUN'
  elif kind=='grain-zero':r['corrupt_shader_fixture']['grain']['max_delta_from_bypass']=0
  elif kind=='grain-wrong-role':r['corrupt_shader_fixture']['grain']['shader_sha256']='aa949d3bf1eb4812c32589121e8f046ec6951f82c563270f4c91efa3b9312bdb'
  elif kind=='grain-missing-entry':r['corrupt_shader_fixture']['grain']['entry_preserved_after_shared_set']=False
  elif kind=='no-latch':r['corrupt_shader_fixture']['no_recursion_latch']=False
  assert m.no_silent_bypass_errors({'photon_no_silent_bypass':r},exe,actual),kind
  print('EXPECTED FAIL no-silent-bypass',kind)
 print('PASS synthetic no-silent-bypass receipt validator mutants; no native evidence created')
