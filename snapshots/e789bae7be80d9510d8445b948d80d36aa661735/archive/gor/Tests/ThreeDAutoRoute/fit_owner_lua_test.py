#!/usr/bin/env python3
"""Actual Lua fit owner, all tools/VR handoffs restore the saved player policy."""
from pathlib import Path
try:from lupa import LuaRuntime
except ImportError:
 print('NOT_RUN fit owner Lua interpreter unavailable');raise SystemExit(0)
r=Path(__file__).resolve().parents[2];s=(r/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
a=s.index('local vr_saved_keepaspect = nil');b=s.index('mp.register_script_message("vr180-look-tools-active"',a)
owner=s[a:b]
l=LuaRuntime(unpack_returned_tuples=True)
l.execute('enabled=false;tools_active=false;props={keepaspect=true};mp={get_property_native=function(k)return props[k]end,set_property_native=function(k,v)props[k]=v end}\n'+owner+'\nfunction reconcile(e,t)enabled=e;tools_active=t;vr_reconcile_fit_owner();return props.keepaspect end')
g=l.globals()
for initial in [True,False]:
 g.props['keepaspect']=initial
 for e,t,want in [(False,True,False),(True,True,False),(True,False,False),(False,False,initial),(False,False,initial),(True,False,False),(False,True,False),(False,False,initial)]:
  assert g.reconcile(e,t)==want,(initial,e,t,want)
print('PASS actual Lua fit writer tools/VR handoffs, repeated off, saved true/false')
assert '"video-scale-y","keepaspect"}' not in s,'raw restore is a competing fit writer'
assert 'if not enabled then mp.set_property_native("keepaspect",true)end' not in s
# Old tools handler does not call the owner, reproducing an inset on real mpv.
assert 'tools_active = val == "true"\n    vr_reconcile_fit_owner()' in s
print('PASS no competing raw-restore/full-fit keepaspect writer; tools activation goes through sole owner')
