#!/usr/bin/env python3
"""Real Lua output-stage replay harness: direct Swift pose and explicit full-fit.
Synthetic source noise/rates, not live Vision/camera or Mac proof."""
import re,math,random,statistics,tempfile,sys
from pathlib import Path
from lupa import LuaRuntime
root=Path(__file__).resolve().parents[2]
prefix=(root/'Tests/ThreeDAutoRoute/preview_pack_lua_test.py').read_text().split('packed = run(1)')[0]
# Reuse exact mpv boundary spies, but retain live handlers/timers for time-domain replay.
mock=prefix.split("l.execute('''",1)[1].split("''')",1)[0]
fails=[]
def check(name,ok):
 print(('PASS ' if ok else 'FAIL ')+name)
 if not ok:fails.append(name)
class Replay:
 def __init__(self,flat=False,source=None):
  self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute(mock);self.g=self.lua.globals();self.tmp=tempfile.TemporaryDirectory()
  def native(request):
   import hashlib
   args=request['args']
   if request['name']=='subprocess' and args and args[1]=='shasum':
    return self.lua.table_from({'status':0,'stdout':hashlib.sha256(Path(args[4]).read_bytes()).hexdigest()})
   return self.lua.table()
  self.g.mp.command_native=native
  self.g.props['config-dir']=self.tmp.name;self.g.props['osd-width']=960;self.g.props['osd-height']=600
  self.lua.execute(source if source is not None else (root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text());self.msg('vr180-look-set-enabled','true')
  if flat:self.msg('vr180-look-set-projection','flat-2d3d',str(16/9))
  self.now=0
 def msg(self,name,*args):
  args=list(map(str,args))
  counts={'vr180-look-set-pack':5,'vr180-look-set-projection':2,'vr180-look-set-enabled':1,'vr180-look-set-output':1,'vr180-look-plan-lock':2}
  if self.g.handlers['vr180-look-store-revision'] is not None and name in counts:
   # Boundary helper represents a current store transaction. Raw rejection tests
   # invoke handlers directly and never pass through this convenience method.
   if len(args)==counts[name]+2:self.g.handlers[name](*args);return
   if name=='vr180-look-set-projection':self.g.props['test-kind']=args[0]
   self.g.handlers['vr180-look-store-revision']('0',self.g.props['test-kind'] or 'vr180','store-applier')
   while len(args)<counts[name]:args.append('false' if name=='vr180-look-plan-lock' else '1')
   args+=['0','store-applier']
  self.g.handlers[name](*args)
 def pose(self,yaw=0,pitch=0,roll=0,x=0,y=0,z=0,fov=135):
  self.msg('vr180-look-set-orientation',yaw,pitch,fov,roll,0,x,y,z)
 def tick(self,t):
  self.now=t;self.g.clock=t
  # The motion/stabilization timer is the 60Hz registration immediately after full-fit.
  # Other registered timers are self-heal/diagnostics and do not advance cinema state.
  for i in range(1,len(self.g.timers)+1):self.g.timers[i]()
 def values(self):
  vals={}
  for i in range(max(1,len(self.g.cmds)-20),len(self.g.cmds)+1):
   for j in range(1,len(self.g.cmds[i])+1):
    for name,v in re.findall(r'/([a-zA-Z0-9_]+)=([-+0-9.eE]+)',str(self.g.cmds[i][j])):vals[name]=float(v)
  return vals
# Independent seeded legacy lock gates superseded by owner192d D1.
if __name__=='__main__':
 import runpy
 runpy.run_path(str(root/'Tests/ThreeDAutoRoute/pipeline192d_gpu_test.py'),run_name='__main__')
