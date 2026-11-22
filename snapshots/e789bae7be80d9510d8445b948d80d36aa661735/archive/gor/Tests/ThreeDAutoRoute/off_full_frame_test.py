"""Actual mpv + production Lua Off recovery. Software GL, not owner Mac playback.
Runs with xvfb-run. Requires GOR_TEST_MPV path to the mpv executable.
Optional GOR_OFF_REF selects a historical Lua revision for the same measurement.
"""
import json, os, socket, subprocess, tempfile, time
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
REF=os.environ.get('GOR_OFF_REF')
MPV=os.environ['GOR_TEST_MPV']
failures=[]
from off_route_commands import commands as compiled_commands
routes=compiled_commands() if not REF else []
def check(name,ok,detail=''):
 print(('PASS ' if ok else 'FAIL ')+name+' '+str(detail),flush=True)
 if not ok:failures.append(name)
with tempfile.TemporaryDirectory(prefix='gor-off-') as folder:
 d=Path(folder);script=d/'vr180_look.lua'
 script.write_bytes(subprocess.check_output(['git','show',REF+':archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],cwd=ROOT) if REF else (ROOT/'Resources/vendor/mpv/scripts/vr180-look.lua').read_bytes())
 # Unequal SBS circles plus nonblack corner markers: a half crop cannot match.
 image=Image.new('RGB',(512,256),(31,55,83));pen=ImageDraw.Draw(image)
 pen.ellipse((8,8,248,248),fill=(200,90,50));pen.ellipse((264,8,504,248),fill=(50,170,200))
 for x,y,c in [(0,0,'red'),(492,0,'green'),(0,236,'blue'),(492,236,'white')]:pen.rectangle((x,y,x+19,y+19),fill=c)
 image.save(d/'source.png')
 log=(d/'mpv.log').open('w')
 p=subprocess.Popen([MPV,'--no-config','--config-dir='+str(d),'--vo=gpu','--gpu-api=opengl','--gpu-context=x11egl','--hwdec=no','--pause','--keep-open=yes','--idle=yes','--force-window=yes','--no-border','--geometry=960x480','--osd-level=0','--input-ipc-server='+str(d/'ipc'),str(d/'source.png')],stdout=log,stderr=log)
 try:
  for _ in range(200):
   if (d/'ipc').exists():break
   if p.poll() is not None:raise RuntimeError((d/'mpv.log').read_text())
   time.sleep(.05)
  s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(10);s.connect(str(d/'ipc'));stream=s.makefile('rb');rid=0;test_revision=0;test_kind="flat-2d3d"
  def cmd(*args):
   global rid,test_revision,test_kind
   # One long-lived player now enforces revision-owned routes. Remap only revision
   # tokens across independent compiled scenarios; payloads and handlers stay real.
   if not REF and len(args)>2 and args[0]=='script-message-to':
    if args[2]=='vr180-look-store-revision':
     test_revision+=1;test_kind=args[4];args=(*args[:3],str(test_revision),*args[4:])
    elif args[2] in route_arity and args[-1]=='store-applier':
     args=(*args[:-2],str(test_revision),'store-applier')
   off=not REF and len(args)>=4 and args[:4]==('script-message-to','vr180_look','vr180-look-set-enabled','false')
   if off:cmd('set_property','user-data/vr180-look/off-properties','await-handler')
   rid+=1;s.sendall((json.dumps({'command':list(args),'request_id':rid})+'\n').encode())
   while True:
    row=json.loads(stream.readline())
    if row.get('request_id')==rid:
     if row.get('error')!='success':raise RuntimeError((args,row))
     result=row.get('data');break
   if off:
    for _ in range(200):
     if cmd('get_property','user-data/vr180-look/off-properties')!='await-handler':break
     time.sleep(.01)
    else:raise RuntimeError('Lua Off handler did not finish')
   return result
  route_arity={'vr180-look-set-projection':2,'vr180-look-set-output':1,'vr180-look-set-pack':5,'vr180-look-set-enabled':1,'vr180-look-plan-lock':2}
  def msg(name,*args):
   args=list(map(str,args))
   if not REF and name in route_arity:
    kind=args[0] if name=='vr180-look-set-projection' else test_kind
    cmd('script-message-to','vr180_look','vr180-look-store-revision','0',kind,'store-applier')
    while len(args)<route_arity[name]:args.append('true')
    args += [str(test_revision),'store-applier']
   cmd('script-message-to','vr180_look',name,*args);time.sleep(.03)
  def shot(name):
   time.sleep(.2);cmd('screenshot-to-file',str(d/(name+'.png')),'window');return np.asarray(Image.open(d/(name+'.png')).convert('RGB')).astype(int)
  # Wait for file and window to be fully rendered before measuring the reference.
  for _ in range(100):
   try:
    if cmd('get_property','video-params'):break
   except RuntimeError:pass
   time.sleep(.05)
  time.sleep(.3);baseline=shot('baseline')
  baseline_props={k:cmd('get_property',k) for k in ('video-crop','video-aspect-override','video-zoom','video-pan-x','video-pan-y','panscan','video-scale-x','video-scale-y','keepaspect')}
  cmd('load-script',str(script));time.sleep(.1)
  props={'video-crop':'','video-aspect-override':'no','video-zoom':0,'video-pan-x':0,'video-pan-y':0,'panscan':0,'video-scale-x':1,'video-scale-y':1,'keepaspect':True}
  # Both enabled -> Off and already-Off -> Off must recover stale real player state.
  for tools in (False,True):
   for projection in ('flat-2d3d','flat-sbs','flat-tb','vr180','vr180-tb'):
    for repeated in (False,True):
     # Establish a clean source reference, then reproduce real stale geometry.
     for key,value in props.items():cmd('set_property',key,value)
     msg('vr180-look-plan-lock','off');msg('vr180-look-tools-active',str(tools).lower())
     msg('vr180-look-set-projection',projection,2);msg('vr180-look-set-output','full_sbs');msg('vr180-look-set-enabled','true')
     msg('vr180-look-menu-crop','.7|.65|1200','.6|.4|800')
     # Controls can be left by pre-store output/aspect/crop paths. Measure actual IPC readbacks.
     for key,value in {'video-crop':'256x256+0+0','video-aspect-override':'1.0','video-zoom':.8,'video-pan-x':.2,'video-pan-y':-.1,'panscan':.6,'video-scale-x':1.2,'video-scale-y':.8}.items():cmd('set_property',key,value)
     msg('vr180-look-set-enabled','false')
     # A separate explicit ToolsON after Off is allowed, but only as plain 2D (owner193e).
     msg('vr180-look-tools-active',str(tools).lower())
     if repeated:
      # Recovery scenario: stale geometry injected after first Off, explicit Off must repair it again.
      cmd('set_property','video-crop','256x256+256+0');cmd('set_property','video-zoom',1)
      msg('vr180-look-set-enabled','false')
     got={k:cmd('get_property',k) for k in props};shaders=cmd('get_property','glsl-shaders')
     independent_tools=tools and not repeated
     if independent_tools:
      receipt=json.loads(cmd('get_property','user-data/vr180-look/applied-state'))
      check('explicit independent tools remain plain layout0/pack0/disabled',receipt['source_layout']==0 and receipt['flat_pack']==0 and receipt['enabled'] is False)
     else:check('own shader option keys removed',not any(k.startswith('vr180-look-shader-') for k in cmd('get_property','glsl-shader-opts')))
     name=projection+' tools='+str(tools)+' repeat='+str(repeated)
     geometry=all((got[k]==baseline_props[k]) for k,v in props.items())
     check(name+' native full-frame geometry',geometry,got)
     check(name+' shader gate',(len(shaders)==1 and 'vr180-look' in shaders[0]) if independent_tools else not any('vr180-look' in x for x in shaders),shaders)
     frame=shot('after');delta=np.abs(frame-baseline);changed=int((delta.max(axis=2)>2).sum())
     check(name+' full normal source pixels',changed==0,{'changed_px_gt2':changed,'max_delta':int(delta.max())})
     if os.environ.get('GOR_OFF_EVIDENCE') and projection=='flat-sbs' and tools and not repeated:
      canvas=Image.new('RGB',(baseline.shape[1]*2,baseline.shape[0]));canvas.paste(Image.fromarray(baseline.astype('uint8')),(0,0));canvas.paste(Image.fromarray(frame.astype('uint8')),(baseline.shape[1],0));canvas.save(os.environ['GOR_OFF_EVIDENCE'])
  # Real compiled menu/key/reducer/applier/enable bytes, not a modeled action.
  for row in (r for r in routes if not r.get('matrix')):
   for key,value in props.items():cmd('set_property',key,value)
   msg('vr180-look-plan-lock','off');msg('vr180-look-set-projection','flat-2d3d',2);msg('vr180-look-set-output','full_sbs');msg('vr180-look-set-enabled','true')
   cmd('set_property','video-crop','256x256+0+0');cmd('set_property','video-zoom',.8)
   for command in row['commands']:cmd(*command)
   time.sleep(.1)
   got={k:cmd('get_property',k) for k in props}
   check('compiled '+row['source']+' '+row['route']+' native geometry',got==baseline_props,got)
   check('compiled '+row['source']+' '+row['route']+' 0px',np.array_equal(shot('compiled'),baseline))
   check('compiled '+row['route']+' no projection/pack while Off',not any(len(c)>2 and c[2] in ('vr180-look-set-pack','vr180-look-set-projection') for c in row['commands']))
  # L2: actual compiled live vs fresh command streams, same physical player.
  def apply_commands(commands):
   for c in commands:cmd(*c)
   time.sleep(.08)
  def snapshot():
   receipt=json.loads(cmd('get_property','user-data/vr180-look/applied-state'));receipt.pop('revision',None);receipt.pop('completed_revision',None)
   return ({k:cmd('get_property',k) for k in props},receipt)
  for row in (r for r in routes if r.get('matrix')):
   msg('vr180-look-set-enabled','false')
   for key,value in props.items():cmd('set_property',key,value)
   apply_commands(row['before']);apply_commands(row['live'])
   live_props,live_receipt=snapshot();live_frame=shot('live')
   msg('vr180-look-set-enabled','false')
   for key,value in props.items():cmd('set_property',key,value)
   apply_commands(row['fresh'])
   fresh_props,fresh_receipt=snapshot();fresh_frame=shot('fresh')
   name='pair '+row['from']+' -> '+row['to']
   check(name+' native properties',live_props==fresh_props)
   check(name+' Lua receipt',live_receipt==fresh_receipt,(live_receipt,fresh_receipt))
   delta=np.abs(live_frame-fresh_frame);check(name+' 0px',int(delta.max())==0,{'changed':int((delta.max(axis=2)>0).sum()),'max':int(delta.max())})
   if row['to']=='off':check(name+' raw baseline',np.array_equal(live_frame,baseline))
   if row['to']=='2D-to-SBS':check(name+' SBS not VR180',live_receipt['source_layout']==0 and live_receipt['flat_pack']==3)
  msg('vr180-look-set-enabled','false')
  # O1: nondefault user settings from BEFORE 3D are restored rather than hardcoded.
  original={'video-zoom':.25,'video-pan-x':.1,'video-pan-y':-.05,'panscan':.2,'video-scale-x':1.1,'video-scale-y':.9}
  for key,value in original.items():cmd('set_property',key,value)
  original={k:cmd('get_property',k) for k in props};original_frame=shot('original')
  msg('vr180-look-set-projection','vr180',1);msg('vr180-look-set-enabled','true');msg('vr180-look-full-fit')
  msg('vr180-look-set-enabled','false')
  check('O1 pre-3D user geometry restored',{k:cmd('get_property',k) for k in props}==original)
  check('O1 pre-3D user pixels restored',np.array_equal(shot('restored'),original_frame))
  msg('vr180-look-set-enabled','false')
  check('O1 repeated Off preserves restored user values',{k:cmd('get_property',k) for k in props}==original)
  for key,value in props.items():cmd('set_property',key,value)
  msg('vr180-look-set-projection','vr180',1);msg('vr180-look-set-enabled','true')
  msg('vr180-look-set-enabled','false')
  cmd('loadfile',str(d/'source.png'),'replace');time.sleep(.3)
  msg('vr180-look-tools-active','true');msg('vr180-look-set-enabled','false')
  relaunched=shot('reopened')
  check('file relaunch Off raw pixels',np.array_equal(relaunched,baseline))
  check('file relaunch Off shader absent',not any('vr180-look' in x for x in cmd('get_property','glsl-shaders')))
  other=d/'other.glsl';other.write_text('//!HOOK MAIN\n//!BIND HOOKED\nvec4 hook(){return HOOKED_tex(HOOKED_pos); }\n')
  cmd('set_property','glsl-shaders',[str(other)]);other_baseline=shot('other-baseline')
  msg('vr180-look-set-projection','flat-sbs',1);msg('vr180-look-set-enabled','true');msg('vr180-look-set-enabled','false')
  check('Off preserves unrelated shader entries',cmd('get_property','glsl-shaders')==[str(other)])
  check('Off preserves unrelated shader baseline pixels',np.array_equal(shot('unrelated'),other_baseline))
  print('Off actual-player failures',len(failures),flush=True)
 finally:
  p.terminate()
  try:p.wait(timeout=5)
  except subprocess.TimeoutExpired:p.kill();p.wait()
  log.close()
raise SystemExit(bool(failures))
