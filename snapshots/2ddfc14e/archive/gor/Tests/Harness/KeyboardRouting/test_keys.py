"""Current keyboard ownership source port, not native NSEvent injection."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().path(root,'PPController_Features.swift');q=root/'Resources/vendor/mpv/input.conf';s=p.read_text();cfg=q.read_text();a=s[s.index('func startKeyboardMonitor'):s.index('// MARK: - Mouse',s.index('func startKeyboardMonitor'))]
for t in ['self.musicModeActive()','self.iptvModeActive()','self.isShowingInputPanel()','if e.modifierFlags.contains(.command) { return e }','seekRelative(60)','seekRelative(-60)','max(0, volume() - 0.05)','min(1, volume() + 0.05)','moveSubtitleToDefaultPosition(number)','parts.joined(separator: "+")']:assert t in a,t
bindings={}
for line in cfg.splitlines():
 l=line.strip()
 if l and not l.startswith('#'):
  key,*rest=l.split();bindings[key]=' '.join(rest)
for k,v in {'LEFT':'add volume -5','RIGHT':'add volume 5','UP':'seek 60','DOWN':'seek -60'}.items():assert bindings[k]==v
special={36:'ENTER',48:'TAB',51:'BS',53:'ESC',123:'LEFT',124:'RIGHT',125:'DOWN',126:'UP'}
def forwarded(code,char,mods):
 key=special.get(code) or {' ':'SPACE','\t':'TAB','\r':'ENTER','\n':'ENTER','\x1b':'ESC'}.get(char,char.lower())
 return '+'.join([m for m in ['Ctrl','Alt','Shift'] if m in mods]+[key]) if key else ''
def route(code,char,mods,entry='monitor',panel=False):
 if entry=='monitor':
  if panel:return ('pass',)
  if 'Cmd' in mods:
   clips={8:'c',5:'g',6:'z',7:'x',31:'o',3:'f'}
   if 'Alt' in mods and code in clips:return ('keypress','Meta+Alt+'+clips[code])
   return ('pass',)
 if code in [123,124,125,126] and 'Cmd' not in mods and 'Shift' not in mods:return ('volume' if code in [123,124] else 'seek',code)
 if 'Shift' in mods:
  if char in ['0','[',']'] or char.lower() in ['v','h','r'] or char in '123456789' and len(char)==1:return ('swift',char)
 return ('keypress',forwarded(code,char,mods))
controls=[]
for code in [123,124,125,126]:assert route(code,'',set())[0] in ['volume','seek']
controls.append('arrow ownership and current input.conf mappings')
for ch in ['0','1','9','v','h','r','[',']']:assert route(0,ch,{'Shift'})==('swift',ch)
controls.append('shift subtitle/VR/IPD ownership')
assert route(8,'c',{'Cmd','Alt'})==('keypress','Meta+Alt+c');assert route(8,'c',{'Cmd'})==('pass',);controls.append('monitor command pass-through and command-option clip route')
assert route(0,'a',set(),panel=True)==('pass',);controls.append('panel/mode monitor ownership bypass')
assert forwarded(123,'',{'Ctrl','Alt','Shift'})=='Ctrl+Alt+Shift+LEFT';assert forwarded(0,'A',set())=='a';assert forwarded(0,' ',set())=='SPACE';controls.append('modifier order/special key/character forwarding')
for vol in [0,.01,.98,1]:assert 0<=max(0,vol-.05)<=1 and 0<=min(1,vol+.05)<=1
controls.append('volume endpoint clamps')
reds=[]
assert route(0,'a',{'Cmd'},entry='view')==('keypress','a');reds.append({'case':'view-keyDown command modifier','observed':'direct handler lacks monitor Cmd gate and mpvKeyName does not emit Cmd/Meta','scope':'requires direct handler reachability, native event chain not executed'})
assert route(123,'',{'Ctrl'})==('volume',123);assert route(126,'',{'Alt'})==('seek',126);reds.append({'case':'control/option arrows','observed':'Swift arrow checks exclude Cmd/Shift only, so Ctrl/Alt arrows still use plain volume/seek','scope':'policy characterization, intended modifier behavior unknown'})
char='a\x01b';escaped=char.replace('\\','\\\\').replace('"','\\"');payload='{"command":["keypress","'+escaped+'"]}'
try:json.loads(payload);valid=True
except json.JSONDecodeError:valid=False
assert not valid;reds.append({'case':'embedded control in forwarded characters','observed':'quote/backslash-only escaping can yield invalid JSON','scope':'synthetic text; native NSEvent character reachability unverified'})
print(json.dumps({'result':'PASS keyboard controls and scoped characterizations','controls':controls,'characterizations':reds,'source_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [p,q]},'open':['native monitor/responder/key layout ownership','input.conf installed parity and shortcut intent','special media/function key parity','event injection/control-character reachability'],'scope':'Python event-routing port + live source/config checks, no Swift/NSEvent/mpv/UI execution'},indent=2))
