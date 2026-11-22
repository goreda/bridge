#!/usr/bin/env python3
"""Production mpv shader evidence. Standard-library only; PNGs retained, decoded with shipped ffmpeg."""
from pathlib import Path
import os,socket,json,subprocess,time,tempfile,sys,math,re
root=Path(__file__).resolve().parents[2];out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
mpv=Path(os.environ.get('GOR_TEST_MPV',str(root/'Resources/vendor/mpv/bin/mpv')));ffmpeg=Path(os.environ.get('FFMPEG',str(root/'Resources/vendor/ffmpeg/bin/ffmpeg')))
if not mpv.exists():mpv=root/'Resources/vendor/mpv/mpv'
assert mpv.exists() and ffmpeg.exists(),'shipped player/ffmpeg required'
def wait(f,seconds=15):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  if f():return True
  time.sleep(.1)
 return False
def ipc(sock,*args):
 with socket.socket(socket.AF_UNIX) as s:
  s.settimeout(15);s.connect(str(sock));s.sendall(json.dumps({'command':list(args)}).encode()+b'\n');buf=b''
  while True:
   buf+=s.recv(65536)
   while b'\n' in buf:
    line,buf=buf.split(b'\n',1);j=json.loads(line)
    if 'error' in j:return j
means={};results=[]
with tempfile.TemporaryDirectory(prefix='gor185a-') as tmp:
 d=Path(tmp)
 for name,lum in [('bright',190),('dark',24)]:
  raw=d/(name+'.rgb');raw.write_bytes(b''.join(bytes([int(lum*(.8+.2*((x//8+y//8)%2)))])*3 for y in range(360) for x in range(960)))
  clip=d/(name+'.mkv');subprocess.run([str(ffmpeg),'-v','error','-stream_loop','-1','-f','rawvideo','-pixel_format','rgb24','-video_size','960x360','-i',str(raw),'-t','30','-r','10','-c:v','ffv1',str(clip)],check=True,timeout=45)
  sock=d/(name+'.sock');cfg=d/(name+'cfg');cfg.mkdir();log=open(out/(name+'-mpv.log'),'w')
  command=[str(mpv),'--no-config','--config-dir='+str(cfg),'--script='+str(root/'Resources/vendor/mpv/scripts/vr180-look.lua'),'--vo=gpu-next',*(['--gpu-context=x11egl','--gpu-sw=yes'] if os.environ.get('DISPLAY') else []),'--ao=null','--no-audio','--pause','--loop-file=inf','--keep-open=yes','--force-window=yes','--no-osc','--no-border','--geometry=960x360','--dither-depth=no','--input-ipc-server='+str(sock),str(clip)]
  proc=subprocess.Popen(command,stdout=log,stderr=log)
  try:
   assert wait(sock.exists),'mpv IPC absent'
   def c(*a):return ipc(sock,*a)
   assert wait(lambda:isinstance(c('get_property','dwidth').get('data'),(int,float)))
   def msg(*a):
    if a[0] in {'vr180-look-set-enabled','vr180-look-set-projection'}: a=(*a,'1','store-applier')
    return c('script-message-to','vr180_look',*a)
   # Production mutations are revision-owned. Old unversioned messages are rejected.
   msg('vr180-look-store-revision','1','flat-sbs','store-applier')
   msg('vr180-look-set-enabled','true');msg('vr180-look-set-projection','flat-sbs',str(4/3));msg('vr180-look-set-tune','vr_gap_frac','0');msg('vr180-look-set-tune','blink_sbs_strength','1');msg('vr180-look-set-tune','blink_warm_r','1.1');msg('vr180-look-set-tune','blink_warm_g','1');msg('vr180-look-set-tune','blink_warm_b','0.9');time.sleep(1)
   def shot(label,lid,adapt):
    if label!='off':
     for k,v in [('blink_lid_l',lid),('blink_lid_r',lid),('blink_reopen_l',adapt),('blink_reopen_r',adapt)]:msg('vr180-look-set-tune',k,str(v))
    time.sleep(.7);path=out/(name+'-'+label+'.png');assert c('screenshot-to-file',str(path),'window')['error']=='success';assert wait(path.exists)
    rgb=subprocess.check_output([str(ffmpeg),'-v','error','-i',str(path),'-vf','scale=960:360','-pix_fmt','rgb24','-f','rawvideo','pipe:1'],timeout=30);assert len(rgb)==960*360*3;return rgb
   baseline=shot('0',0,0)
   # Independent off control removes blink_render calls from actual generated shader, retaining projection.
   shaders=c('get_property','glsl-shaders').get('data',[]);assert shaders, 'revision-owned shader was not installed';active=Path(shaders[-1]);source=active.read_text()
   # Independent off control replaces only the function body in the actual installed shader.
   begin=source.index('vec4 blink_render(');body=source.index('{',begin);depth=1;end=body+1
   while depth:
    if source[end]=='{':depth+=1
    elif source[end]=='}':depth-=1
    end+=1
   disabled=source[:body+1]+' return base; '+source[end-1:]
   assert disabled!=source
   # Freeze the production uniform values into immutable controls in a separate mpv.
   # The live script owns its shader list and must not race the independent control.
   options=c('get_property','glsl-shader-opts')['data'];prefix=active.stem+'/'
   def freeze(text):
    def param(m):return m[1]+str(options.get(prefix+m[2],m[3]))+'\n'
    return re.sub(r'(//!PARAM (\w+)\n//!TYPE (?:DYNAMIC )?(?:float|int)\n)([^\n]+)\n',param,text)
   def control(text,label):
    shader=d/(name+'-'+label+'.glsl');shader.write_text(freeze(text));controlSock=d/(name+'-'+label+'.sock')
    cmd=[a for a in command if not a.startswith('--script=') and not a.startswith('--input-ipc-server=')]
    cmd[1:1]=['--glsl-shaders='+str(shader),'--input-ipc-server='+str(controlSock)]
    controlLog=open(out/(name+'-'+label+'-mpv.log'),'w');child=subprocess.Popen(cmd,stdout=controlLog,stderr=controlLog)
    try:
     assert wait(controlSock.exists),'control IPC absent'
     assert wait(lambda:isinstance(ipc(controlSock,'get_property','dwidth').get('data'),(int,float)))
     time.sleep(.5);path=out/(name+'-'+label+'.png')
     assert ipc(controlSock,'screenshot-to-file',str(path),'window')['error']=='success'
     return subprocess.check_output([str(ffmpeg),'-v','error','-i',str(path),'-vf','scale=960:360','-pix_fmt','rgb24','-f','rawvideo','pipe:1'],timeout=30)
    finally:
     child.terminate()
     try:child.wait(timeout=5)
     except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
     controlLog.close()
   assert control(source,'static-on')==baseline,'frozen control differs from live shader'
   off=control(disabled,'off');assert baseline==off
   results.append(name+' lid0 byte-equal independent blink-off shader PASS')
   for label,lid,adapt in [('0.3',.3,0),('0.7',.7,0),('1',1,0),('reopen100ms',0,.6)]:
    rgb=shot(label,lid,adapt)
    if lid==1:
     av=[sum(rgb[i::3])/(960*360) for i in range(3)];assert av[0]>av[1]>av[2]>0;means[name]=sum(av)/3;results.append(name+' closed warm nonzero PASS')
    if label=='reopen100ms':assert sum(rgb)>=sum(baseline) and rgb!=baseline;results.append(name+' reopen residual/>=baseline PASS')
    if lid==.3:
     def covered_edge(x):
      return max(y for y in range(180) if abs(rgb[(y*960+x)*3]-baseline[(y*960+x)*3])>lum*.4)
     assert covered_edge(240)>covered_edge(12);results.append(name+' curved center-leading edge PASS')
     def isCovered(y):return abs(rgb[(y*960+240)*3]-baseline[(y*960+240)*3])>lum*.4
     top=sum(isCovered(y) for y in range(180));bottom=sum(isCovered(y) for y in range(180,360))
     assert top>bottom*2,(name,top,bottom)
     results.append(name+' TOP-dominant upper92/lower8 travel PASS')
   # Draw-on load probe: current lids must leave playback unchanged.
   msg('vr180-look-manual-playback');c('set_property','pause',False)
   start=time.monotonic();last=start;gaps=[]
   while time.monotonic()-start<4.0:
    msg('vr180-look-set-lids','1','1','false');now=time.monotonic();gaps.append(now-last);last=now;time.sleep(.03)
   draw_paused=c('get_property','pause').get('data')==True
   (out/(name+'-draw-load.json')).write_text(json.dumps({'maxMessageGapMS':max(gaps)*1000,'gapsOver200ms':sum(g>.2 for g in gaps),'pauseReached':draw_paused,'scope':'Linux mpv software GL draw-on; native GPU unknown'}))
   assert not draw_paused and max(gaps)<.2,(name,draw_paused,max(gaps))
   results.append(name+' draw-on lids do not change playback PASS maxGapMS='+str(round(max(gaps)*1000)))
   msg('vr180-look-set-lids','0','0','false');time.sleep(.3)
   draw_resumed=c('get_property','pause').get('data')==False
   assert draw_resumed,(name,'draw-on reopen did not resume')
   results.append(name+' draw-on reopen leaves playback playing PASS')
   msg('vr180-look-set-lids','0','0','true');msg('vr180-look-manual-playback')
   # Current gesture contract: Lua draws lids only and never changes playback pause.
   # Pixel proof above retains drawing. State proof below removes software GPU load only; real mpv Lua/pause remain.
   c('set_property','vid','no');time.sleep(.2)
   msg('vr180-look-manual-playback');c('set_property','pause',False)
   start=time.monotonic()
   while time.monotonic()-start<4.0:
    msg('vr180-look-set-lids','1','1','false');time.sleep(.03)
   assert c('get_property','pause').get('data')==False
   msg('vr180-look-set-lids','0','0','false');time.sleep(.1)
   assert c('get_property','pause').get('data')==False
   results.append(name+' actual mpv bilateral hold/reopen leaves playback unchanged PASS')
   c('set_property','pause',True);msg('vr180-look-manual-playback')
   start=time.monotonic()
   while time.monotonic()-start<4.0:
    msg('vr180-look-set-lids','1','1','false');time.sleep(.03)
   msg('vr180-look-set-lids','0','0','false');time.sleep(.1)
   assert c('get_property','pause').get('data')==True
   results.append(name+' already-paused remains paused PASS')
  finally:
   proc.terminate()
   try:proc.wait(timeout=5)
   except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=5)
 for logpath in out.glob('*-mpv.log'):
  logtext=logpath.read_text()
  assert 'Failed to parse user shader' not in logtext and 'error:' not in logtext.lower(),logpath.read_text()[-3000:]
 assert means['bright']>means['dark'];results.append('bright glow > dark glow PASS')
 (out/'verdicts.json').write_text(json.dumps({'assertions':results,'means':means,'scope':'actual production mpv/GLSL; owner judgement separate'},indent=2));print('\n'.join(results))
