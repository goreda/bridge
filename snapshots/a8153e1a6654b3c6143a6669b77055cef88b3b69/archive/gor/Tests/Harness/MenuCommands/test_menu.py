"""Validate source-extracted static IPC JSON, never call menu actions."""
from pathlib import Path
import json,re,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/UI/MenuActions.swift';s=p.read_text()
commands=[];excluded=[]
for match in re.finditer(r'cmd\(#"(.*?)"#\)',s,re.S):
 text=match.group(1)
 if '\\#(' in text:excluded.append({'offset':match.start(),'reason':'dynamic Swift interpolation'});continue
 obj=json.loads(text);assert isinstance(obj,dict) and isinstance(obj.get('command'),list) and obj['command'];assert isinstance(obj['command'][0],str);commands.append({'offset':match.start(),'command':obj['command']})
assert len(commands)>=30
mapping={}
for m in re.finditer(r'@objc func (menu\w+)\(\)\s*\{\s*cmd\(#"(.*?)"#\)',s):mapping[m.group(1)]=json.loads(m.group(2))['command']
expected={'menuReload':['playlist-play-index','current'],'menuStop':['stop'],'menuPlayPause':['cycle','pause'],'menuSeekF5':['seek','5','relative'],'menuSeekB5':['seek','-5','relative'],'menuSeekF60':['seek','60','relative'],'menuSeekB60':['seek','-60','relative'],'menuSeekStart':['seek','0','absolute'],'menuSpeedDouble':['multiply','speed',2.0],'menuSpeedHalf':['multiply','speed',.5],'menuSpeedReset':['set','speed',1.0],'menuFrameNext':['frame-step'],'menuFramePrev':['frame-back-step']}
for name,want in expected.items():assert mapping[name]==want,name
assert 'cmd(#"{"command":["stop"]}"#); TunnelForBlockedHosts.shared.stopOrQuit()' in s
aspect=s[s.index('private func applyAspectPreset'):] if 'private func applyAspectPreset' in s else s[s.index('var currentAspectPreset:'):s.index('// MARK:',s.index('var currentAspectPreset:'))]
assert 'video-aspect-override' in aspect
print(json.dumps({'result':'PASS source-extracted static command JSON and action controls','static_commands_validated':len(commands),'action_mapping_controls':len(expected),'commands':commands,'dynamic_exclusions':excluded,'limits':['JSON validity does not establish installed mpv command/version acceptance','dynamic string commands, full menu dispatch/wiring and action reachability not executed','aspect/VR/media/profile/companion behavior not covered by static extraction'],'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scope':'Current Swift text extraction/JSON validation only, no Swift/menu/mpv/UI execution'},indent=2))
