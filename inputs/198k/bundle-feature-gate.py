#!/usr/bin/env python3
"""Fail-closed built app and resolved external resource closure feature loss gate."""
import argparse,hashlib,json,re
from pathlib import Path

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inspect_resources(root):
 files={str(p.relative_to(root)):sha(p)for p in root.rglob('*')if p.is_file()}
 bindings=[];messages=[];shaders=[];options=[]
 for name in files:
  p=root/name
  if p.name=='input.conf':bindings.extend(x.strip()for x in p.read_text().splitlines()if x.strip()and not x.lstrip().startswith('#'))
  if p.suffix=='.lua':
   s=p.read_text();options+=re.findall(r'[\"\x27](photon-[a-z0-9]+_[a-z0-9_]+)[\"\x27]',s);messages+=re.findall(r'mp\.register_script_message\(\s*["\x27]([^"\x27]+)',s);shaders+=re.findall(r'(?:common\.)?shader_path\(\s*["\x27]([^"\x27]+)',s)
 return dict(files=files,script_options=sorted(set(options)),input_bindings=sorted(set(bindings)),script_messages=sorted(set(messages)),shader_names=sorted(set(shaders)))
def approved_removals(path):
 text=Path(path).read_text();return {name for name,source in re.findall(r"^\| script_messages \| ([a-z0-9-]+) \| (phonemsg-[A-Z0-9]+) \|$",text,re.M) if source=="phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB" and name in {"photon-grain-set-strength-hint","photon-grain-set-strength-mult","photon-grain-proxy-strength","photon-grain-set-size-hint"}}
def approved_option_removals(path):
 text=Path(path).read_text()
 return {name for name,source in re.findall(r"^\| script_options \| ([a-z0-9_-]+) \| (phonemsg-[A-Z0-9]+) \|$",text,re.M) if source=="phonemsg-01M7JZ4W1HWK0RZXFD8Z44C3BB" and name in {"photon-grain_floor_480p","photon-grain_ceiling_480p"}}
def no_silent_bypass_errors(runtime,executable,actual):
 errors=[];r=(runtime or {}).get('photon_no_silent_bypass',{})
 def need(ok,why):
  if not ok:errors.append('Photon no-silent-bypass: '+why)
 need(r.get('result')=='PASS','native smoke receipt missing or not PASS')
 need(executable.is_file() and r.get('executable_sha256')==sha(executable),'wrong executable binding')
 need(r.get('resource_files_sha256')==hashlib.sha256(json.dumps(actual['files'],sort_keys=True,separators=(',',':')).encode()).hexdigest(),'wrong resolved resource closure binding')
 path=r.get('shipped_path',{})
 need(path.get('source_pin')=='15acf95cec7bf0ea668b4eec1750d4f49455a82c','shipped-path reference is not exact delivered baseline')
 need(path.get('platform')=='Darwin' and all(path.get(k) for k in ('mpv_sha256','vo','gpu_api','mpv_conf_sha256')),'actual shipped mpv/config/backend witness missing')
 rows=r.get('shader_results',[]);inventory=r.get('all_photon_shader_hashes',[])
 need(bool(inventory) and len(inventory)==len(set(inventory)),'complete photon shader hash inventory missing or duplicated')
 need({x.get('shader_sha256')for x in rows}==set(inventory) and len(rows)==len(inventory),'parse/delta table does not cover photon shader inventory exactly')
 need('bc9a2a32e522a600cc24f08686f47932ba376eb7d99f79dfdd9beffe17c0ee8a' in inventory,'exact delivered SHARP Phase2 witness missing')
 for x in rows:
  need(isinstance(x.get('parse_ok'),bool) and isinstance(x.get('compile_ok'),bool) and isinstance(x.get('max_delta_from_bypass'),(int,float)),'incomplete parser/compiler/delta row')
 need(r.get('glsl_shaders_after_load') and r.get('changing_frame_fixture_sha256'),'actual active shader list or changing-frame fixture hash missing')
 need(r.get('history_result') in ('PREVIOUS_FRAME_PROVEN','CURRENT_FRAME_REUSE','NOT_PROVEN'),'explicit changing-frame history result missing')
 need(r.get('lua_swift_twins')=='PASS','Lua/Swift mechanism twin witness missing')
 f=r.get('corrupt_shader_fixture',{})
 need(f.get('deliberately_corrupt') is True and f.get('parse_failed') is True,'deliberate corrupt-shader rejection not witnessed')
 need(f.get('fallback_engaged') is True and f.get('fallback_shader_sha256')=='aa949d3bf1eb4812c32589121e8f046ec6951f82c563270f4c91efa3b9312bdb','proven SHARP spatial fallback not witnessed')
 delta=f.get('max_delta_from_bypass');need(isinstance(delta,(int,float)) and not isinstance(delta,bool) and delta>0,'corrupt SHARP fallback output is bypass or unmeasured')
 need(f.get('fallback_role')=='sharp','spatial fallback misidentified as grain')
 grain=f.get('grain',{});gd=grain.get('max_delta_from_bypass')
 need(grain.get('shader_role')=='grain' and grain.get('shader_sha256') in inventory and grain.get('shader_sha256') not in ('bc9a2a32e522a600cc24f08686f47932ba376eb7d99f79dfdd9beffe17c0ee8a','aa949d3bf1eb4812c32589121e8f046ec6951f82c563270f4c91efa3b9312bdb'),'separate actual grain shader identity missing')
 need(grain.get('parse_ok') is True and grain.get('compile_ok') is True and grain.get('entry_preserved_after_shared_set') is True,'grain parse/compile/list preservation not witnessed')
 need(isinstance(gd,(int,float)) and not isinstance(gd,bool) and gd>0,'grain output delta is zero or unmeasured independently of sharp')
 need(f.get('log_association_verified') is True and f.get('no_recursion_latch') is True,'error association or recursion guard not witnessed')
 for k in ('warn_error_subscription','effective_shader_list_verified','state_failure_hash_recorded','hud_failure_shown','fallback_active_in_shader_list'):
  need(f.get(k) is True,k+' witness missing')
 need(bool(f.get('raw_log_sha256')),'corrupt-shader raw log hash missing')
 g=r.get('corrupt_grain_fixture',{});need(g.get('shader_role')=='grain','independent corrupt grain fixture missing')
 for k in ('deliberately_corrupt','parse_failed','fallback_engaged','fallback_parse_ok','fallback_compile_ok','fallback_active_in_shader_list','sharp_entry_preserved','log_association_verified','no_recursion_latch','state_failure_hash_recorded','hud_failure_shown'):
  need(g.get(k) is True,'grain corrupt fixture '+k+' missing')
 gh=g.get('fallback_shader_sha256');need(isinstance(gh,str) and len(gh)==64 and gh not in ('bc9a2a32e522a600cc24f08686f47932ba376eb7d99f79dfdd9beffe17c0ee8a','aa949d3bf1eb4812c32589121e8f046ec6951f82c563270f4c91efa3b9312bdb'),'grain own fallback identity missing or sharp shader misused')
 gd=g.get('grain_only_max_delta_from_bypass');need(isinstance(gd,(int,float)) and not isinstance(gd,bool) and gd>0,'independent corrupt-grain fallback output is zero or unmeasured')
 need(bool(g.get('raw_log_sha256')),'independent corrupt-grain raw log missing')
 return errors

def compare(baseline,bundle,resources,runtime,approved=frozenset(),approved_options=frozenset()):
 errors=[];removed={};actual=inspect_resources(resources)
 for name in baseline['resource_files']:
  n=name.removeprefix('Resources/')
  if n not in actual['files']:removed.setdefault('resource_files',[]).append(name)
 required={'script_options':baseline.get('script_options',[]),'input_bindings':sorted(set(x for v in baseline['input_bindings'].values()for x in v)),'script_messages':sorted(set(x for v in baseline['script_messages'].values()for x in v)),'shader_names':sorted(set(x for v in baseline['photon_injected_shader_names'].values()for x in v))}
 for kind,values in required.items():
  lost=sorted(set(values)-set(actual[kind])-(set(approved)if kind=='script_messages'else set(approved_options)if kind=='script_options'else set()))
  if lost:removed[kind]=lost
 executable=bundle/'Contents/MacOS/gor'
 if not executable.is_file():errors.append('Built executable missing')
 if not baseline.get('built_bundle_files'):errors.append('Baseline built-bundle file inventory not yet attested')
 else:
  for name in baseline['built_bundle_files']:
   if not (bundle/name).is_file():removed.setdefault('bundle_files',[]).append(name)
 if runtime is None:errors.append('Runtime semantic feature receipt missing')
 else:
  if not executable.is_file()or runtime.get('executable_sha256')!=sha(executable):errors.append('Runtime receipt not bound to exact built executable')
  expected=baseline.get('runtime_features')
  if not expected:errors.append('Baseline runtime menu/panel/registration manifest not yet attested')
  else:
   for kind,values in expected.items():
    lost=sorted(set(values)-set(runtime.get('features',{}).get(kind,[]))-(set(approved)if kind=='script_messages'else set(approved_options)if kind=='script_options'else set()))
    if lost:removed['runtime_'+kind]=lost
 if any('photon' in name and name.endswith('.lua') for name in actual['files']):errors.extend(no_silent_bypass_errors(runtime,executable,actual))
 if baseline.get('status')!='BUILT_AND_RUNTIME_ATTESTED':errors.append('Baseline source-only; complete built/runtime baseline required')
 return dict(result='FAIL'if errors or removed else 'PASS',errors=errors,removed=removed,actual_resource_files=actual['files'],executable_sha256=sha(executable)if executable.is_file()else None,scope='Actual built app plus explicit resolved external Resources closure. Source static presence is supplemental. Only four exact internal transports and two V1 patch options cited in REMOVALS.md can be omitted. No file, binding, menu or shader removal exemption.')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--baseline',required=True);p.add_argument('--bundle',required=True);p.add_argument('--resources',required=True);p.add_argument('--installed');p.add_argument('--installed-resources');p.add_argument('--runtime');p.add_argument('--removals',required=True);p.add_argument('--out',required=True);a=p.parse_args()
 b=json.loads(Path(a.baseline).read_text());r=json.loads(Path(a.runtime).read_text())if a.runtime else None
 allowed=approved_removals(a.removals);allowed_options=approved_option_removals(a.removals)
 # Approval applies only to an actual same-build v4 replacement, never merely an absent old hook.
 replacement=(r or {}).get('photon_v4_replacement',{})
 actual_exe=Path(a.bundle)/'Contents/MacOS/gor'
 replacement_ok=actual_exe.is_file() and replacement.get('executable_sha256')==sha(actual_exe) and replacement.get('result')=='PASS' and replacement.get('lua_swift_twin_byte_equal') is True and replacement.get('v7_invariants')=='PASS' and replacement.get('manual_recall_sequence')=='PASS' and all(replacement.get('implemented',{}).get('V'+str(i)) is True for i in range(1,8))
 if not replacement_ok:allowed=set();allowed_options=set()
 result=compare(b,Path(a.bundle),Path(a.resources),r,allowed,allowed_options)
 if a.installed:
  old=Path(a.installed)
  lost=[str(x.relative_to(old))for x in old.rglob('*')if x.is_file()and not (Path(a.bundle)/x.relative_to(old)).is_file()]
  if lost:result['removed']['installed_bundle_files']=sorted(lost)
 if a.installed_resources:
  old=inspect_resources(Path(a.installed_resources));new=inspect_resources(Path(a.resources))
  for kind in old:
   lost=sorted(set(old[kind])-set(new[kind])-(allowed if kind=='script_messages'else allowed_options if kind=='script_options'else set()))
   if lost:result['removed']['installed_'+kind]=lost
 if result['removed']:result['result']='FAIL'
 result['baseline_sha256']=sha(Path(a.baseline));Path(a.out).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(result['result']!='PASS')
