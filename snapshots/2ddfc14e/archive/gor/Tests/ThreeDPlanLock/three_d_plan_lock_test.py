"""193b replaces secondary sender plan locks with revision-owned store routes."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json
r=Path(__file__).resolve().parents[2]
f=r/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
p=ns['Replay']();g=p.g;logs=[];g.mp.msg.warn=lambda text:logs.append(str(text))
g.handlers['vr180-look-store-revision']('12','flat-sbs','store-applier')
def raw(name,*args):g.handlers['vr180-look-'+name](*map(str,args))
raw('plan-lock','off','false',12,'store-applier')
raw('set-projection','flat-sbs',16/9,12,'store-applier')
raw('set-output','full_sbs',12,'store-applier');raw('set-enabled','true',12,'store-applier')
raw('plan-lock','on','true',12,'store-applier')
for file in ['/cache/render_shot_00001.mp4','/source/film.mp4']:
 g.props['path']=file;g.events['start-file']()
 raw('set-projection','vr180',0)
 raw('set-projection','vr180',0,11,'legacy-plannedLook')
 raw('set-projection','vr180',0,12,'store-applier')
 assert json.loads(g.props['user-data/vr180-look/applied-state'])['source_layout']==(1 if 'render_shot_' in file else 0)
raw('set-enabled','false',12,'store-applier')
assert g.props['user-data/vr180-look/enabled'] is False
assert len(logs)==3,'reject-once contract failed across file starts'
source=(lambda _b: _b[_b.index('// BEGIN relocated '+'RenderedShotMPV.swift'+' '):_b.index('// END relocated '+'RenderedShotMPV.swift'+'\n')])((_threed_split().path(r)).read_text())
assert 'struct Look:' in source and 'script-message' not in source
print('PASS193b current revision owns route across shot/source starts; stale/unversioned/wrong-kind ignored and logged once; plannedLook emits no messages')

#193c production mpv uses LuaJIT/Lua5.1; default lupa is Lua5.4 and hid table.unpack.
from lupa.luajit21 import LuaRuntime as LuaJIT
from lupa.lua51 import LuaRuntime as Lua51
from lupa.lua54 import LuaRuntime as Lua54
import tempfile,subprocess
source=(r/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
def replay(runtime,source):
 l=runtime(unpack_returned_tuples=True);l.execute(ns['mock']);g=l.globals()
 with tempfile.TemporaryDirectory() as folder:
  g.props['config-dir']=folder;g.props['osd-width']=960;g.props['osd-height']=600
  l.execute(source)
  def send(name,args,revision):g.handlers['vr180-look-'+name](*map(str,[*args,revision,'store-applier']))
  for revision,(kind,output,pack,enabled) in enumerate([('flat-2d3d','off',0,False),('flat-2d3d','full_sbs',3,True),('flat-sbs','full_sbs',3,True),('flat-2d3d','off',0,False),('vr180','vr180',0,True),('vr180','off',0,False),('vr180-tb','vr180',0,True)],1):
   g.handlers['vr180-look-store-revision'](str(revision),kind,'store-applier')
   send('plan-lock',['off','false'],revision);send('set-enabled',['false'],revision)
   if enabled:
    send('set-projection',[kind,16/9],revision);send('set-output',[output],revision)
    send('set-enabled',['true'],revision);send('set-pack',[pack,1,.5,1,0],revision)
   receipt=json.loads(g.props['user-data/vr180-look/applied-state'])
   assert g.props['user-data/vr180-look/enabled']==enabled
   assert receipt['source_layout']==(0 if not enabled or kind=='flat-2d3d' else {'flat-sbs':1,'vr180':3,'vr180-tb':4}[kind])
   assert receipt['flat_pack']==pack
   assert receipt['revision']==revision and receipt['completed_revision'] is None
   g.handlers['vr180-look-route-complete'](str(revision-1),'store-applier')
   assert json.loads(g.props['user-data/vr180-look/applied-state'])['completed_revision'] is None
   g.handlers['vr180-look-route-complete'](str(revision),'other-sender')
   assert json.loads(g.props['user-data/vr180-look/applied-state'])['completed_revision'] is None
   g.handlers['vr180-look-route-complete'](str(revision),'store-applier')
   assert json.loads(g.props['user-data/vr180-look/applied-state'])['completed_revision']==revision
   old=g.props['user-data/vr180-look/applied-state']
   g.handlers['vr180-look-set-projection']('vr180','0',str(revision-1),'old-sender')
   assert g.props['user-data/vr180-look/applied-state']==old
for runtime in (LuaJIT,Lua51,Lua54):
 replay(runtime,source)
 print('PASS193c actualLua7ordinary/prepared/nativeSBS/nativeTB/Off transitions +staleguards runtime',runtime.__module__)
# Negative control must reproduce shipped193b failure in production-compatible runtime.
broken=subprocess.check_output(['git','show','69dceb3:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
try:replay(LuaJIT,broken)
except Exception as error:
 assert "unpack" in str(error) and 'nil' in str(error),error
 print('PASS193c negativecontrol193b LuaJIT fails at routewrapper table.unpack before enabledreceipt')
else:raise AssertionError('193b negativecontrol unexpectedly passed onLuaJIT')

#193e optional REAL mpv subprocess leg. Set binary/fixture explicitly; no download
# or owner-file access is implied. Transport owns actual mpv IPC and script death.
import os,socket,time,shutil
binary=os.environ.get('MPV_RUNTIME_BIN');fixture=os.environ.get('MPV_RUNTIME_FIXTURE')
if binary and fixture:
 for label,lua_source in [('negative193d',subprocess.check_output(['git','show','7d2f306:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)),('fixed193e',source),('reopened193k',source)]:
  with tempfile.TemporaryDirectory(prefix='gor193e-realmpv-') as folder:
   folder=Path(folder);script=folder/'vr180-look.lua';script.write_text(lua_source)
   native=folder/'SIVR-416-B.mp4';ordinary=folder/'Eden West.mp4'
   shutil.copyfile(fixture,native);shutil.copyfile(fixture,ordinary)
   sockpath=str(folder/'socket');log=folder/'runtime.log'
   with log.open('w') as output:
    player=subprocess.Popen([binary,'--no-config','--idle=yes','--vo=null','--ao=null','--pause','--loop-file=inf','--script='+str(script),'--input-ipc-server='+sockpath,str(native)],stdout=output,stderr=output)
    try:
     for _ in range(100):
      if Path(sockpath).exists():break
      time.sleep(.02)
     time.sleep(.2)
     def ipc(command):
      client=socket.socket(socket.AF_UNIX);client.settimeout(2);client.connect(sockpath)
      client.sendall((json.dumps({'command':command})+'\n').encode());client.shutdown(socket.SHUT_WR)
      while client.recv(65536):pass
      client.close();time.sleep(.02)
     def message(*args):ipc(['script-message-to','vr180_look',*args])
     for rev,(kind,pack,enabled) in enumerate([('vr180',0,True),('flat-2d3d',0,False),('flat-2d3d',3,True),('flat-sbs',3,True),('flat-tb',1,True),('flat-2d3d',0,False),('vr180',0,True),('flat-2d3d',0,False)],1):
      if rev==2:ipc(['loadfile',str(ordinary),'replace'])
      expected_layout=0 if not enabled else {'vr180':3,'flat-2d3d':0,'flat-sbs':1,'flat-tb':2}[kind]
      output_mode='off' if not enabled else ('vr180' if kind=='vr180' else ('over_under' if pack==1 else 'full_sbs'))
      message('vr180-look-store-revision',str(rev),kind,'store-applier',str(enabled).lower(),str(expected_layout),str(pack),output_mode,'nativeVR180' if kind=='vr180' else 'flat_full_sbs','2' if rev>=2 else '1',ordinary.name if rev>=2 else native.name)
      message('vr180-look-plan-lock','off','false',str(rev),'store-applier')
      message('vr180-look-set-enabled','false',str(rev),'store-applier')
      if enabled:
       message('vr180-look-set-projection',kind,str(16/9),str(rev),'store-applier')
       message('vr180-look-set-output','vr180' if kind=='vr180' else ('over_under' if pack==1 else 'full_sbs'),str(rev),'store-applier')
       message('vr180-look-set-enabled','true',str(rev),'store-applier')
       message('vr180-look-set-pack',str(pack),'1','.5','1','0',str(rev),'store-applier')
      message('vr180-look-route-complete',str(rev),'store-applier')
     if label!='negative193d':
      # Deliberately wrong expectation must FAIL without changing route behavior.
      message('vr180-look-store-revision','9','flat-2d3d','store-applier','false','0','3','off','flat_off','2',ordinary.name)
      message('vr180-look-route-complete','9','store-applier')
      # Same film close/reopen, followed by different film, in the same process.
      ipc(['stop']);ipc(['loadfile',str(ordinary),'replace'])
      message('vr180-look-store-revision','10','flat-2d3d','store-applier','false','0','0','off','flat_off','3',ordinary.name)
      message('vr180-look-route-complete','10','store-applier')
      ipc(['stop']);ipc(['loadfile',str(native),'replace'])
      message('vr180-look-store-revision','11','flat-2d3d','store-applier','false','0','0','off','flat_off','4',native.name)
      message('vr180-look-route-complete','11','store-applier')
     time.sleep(.1)
    finally:player.terminate();player.wait(timeout=5)
   text=log.read_text()
   if label=='negative193d':
    assert 'flat store kind crossed native engine' in text and 'message=vr180-look-set-enabled revision=8' not in text,text
   else:
    assert 'Lua error' not in text and 'message=vr180-look-set-enabled revision=8 vr_source_layout=0 vr_flat_mono=0 vr_pack=0' in text,text
    assert '3D-FILE-RESET path=Eden West.mp4' in text,text
    verified=[line for line in text.splitlines() if '3D-VERIFIED ' in line]
    assert len(verified)==11 and sum('verdict=PASS ' in l for l in verified)==10 and sum('verdict=FAIL ' in l for l in verified)==1,verified
    assert 'revision=9 output=off engine=flat_off verdict=FAIL' in '\n'.join(verified),verified
    durable=Path('/tmp/gor_diag.log').read_text()
    for line in verified:assert line.split('3D-VERIFIED ',1)[1].strip() in durable,line
    assert '3D-CLOSE file=' in text and 'generation=3 revision=10 output=off engine=flat_off verdict=PASS' in text,text
    print('PASS193k REALmpv durable route-state10PASS + deliberate mismatch1FAIL; samefilmclose/reopen+differentfilm; process',label)
    for rev,layout,pack in [(3,0,3),(4,1,3),(5,2,1),(7,3,0)]:
     assert f'message=vr180-look-set-pack revision={rev} vr_source_layout={layout}' in text,text
   print('PASS193e REALmpv',label,'nativefile→ordinaryfile→2D3D→SBS→TB→Off→native→Off; oldscriptdies/fixedscriptlives')
else:print('NOT_RUN193e realmpvprocess requires MPV_RUNTIME_BIN and MPV_RUNTIME_FIXTURE; pureLua+compiledapplier tests above still run')
