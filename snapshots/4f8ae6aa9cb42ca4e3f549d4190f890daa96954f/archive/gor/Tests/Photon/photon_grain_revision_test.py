#!/usr/bin/env python3
"""Execute exact strength receiver callbacks: stale user-control revisions have no effect."""
from pathlib import Path
from lupa import lua51
s=(Path(__file__).resolve().parents[2]/'Resources/vendor/mpv/scripts/photon-grain.lua').read_text()
a=s.index('mp.register_script_message("photon-grain-set-strength-mult",');b=s.index('-- Learned look adopted:',a)
body=s[a:b]
for proxy in (False,True):
 l=lua51.LuaRuntime();l.execute('''
messages={};mp={register_script_message=function(k,f) messages[k]=f end,get_time=function() return 10 end,msg={info=function() end}}
common={trace_record=function() end}
function gr_doc_accept(gen,name) return gen=='1' and name=='test' end
function clamp(v,a,b) return math.max(a,math.min(b,v)) end
function gr_push_params() end;function gr_publish_hud_state() end;function gr_str_log() end
gr_control_revision=5;gr_seek_epoch=3;gr_adaptive_mode=true
GRAIN_STRENGTH_USER_DEFAULT=6;GRAIN_BASE_STRENGTH=6
'''+body)
 cb=l.eval('messages["photon-grain-proxy-strength"]' if proxy else 'messages["photon-grain-set-strength-mult"]')
 def send(revision,gen='1',epoch='3'):
  args=['2',gen,'test']+([epoch] if proxy else [])+['0','1','5','1',revision]
  cb(*args)
 for rev in ('4','6','bogus'):
  send(rev);assert l.eval('gr_str_blend') is None
  assert l.eval('GRAIN_BASE_STRENGTH')==6 and l.eval('gr_strength_hint_received') is None
 send('5',gen='0');assert l.eval('gr_str_blend') is None
 if proxy:send('5',epoch='2');assert l.eval('gr_str_blend') is None
 send('5');assert l.eval('gr_str_blend.target')==12
 # A previously accepted result cannot overwrite a later user's control revision.
 l.execute('gr_control_revision=6;gr_str_blend=nil');send('5');assert l.eval('gr_str_blend') is None
 send('6');assert l.eval('gr_str_blend.target')==12
 # Missing optional revision keeps older sender compatibility, within doc/epoch gates.
 l.execute('gr_str_blend=nil');send(None);assert l.eval('gr_str_blend.target')==12
print('PASS exact mult/proxy callbacks: old/future/malformed revision rejected with no strength/blend writes, matching revision accepted, doc/epoch rejection unchanged, omitted revision legacy-compatible; no native GPU claim')
