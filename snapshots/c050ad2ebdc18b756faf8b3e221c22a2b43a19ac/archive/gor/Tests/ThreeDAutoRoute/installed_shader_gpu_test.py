"""Real mpv0.42 gpu-next slot/receipt/pixel transitions. Run under Xvfb."""
from pathlib import Path
import os,json,socket,subprocess,tempfile,time,hashlib
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2];MPV=os.environ['GOR_TEST_MPV']
with tempfile.TemporaryDirectory(prefix='gor-installed-') as folder:
 d=Path(folder);script=d/'vr180_look.lua';source=(ROOT/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
 if os.environ.get('GOR_SHADER_NEGATIVE'):
  source=source.replace('local legacy = source_layout>=3 and flat_pack<=0','local legacy = flat_pack<=0').replace('vr_shader_variant=nil;vr_shader_written=false;VR180_LOOK_SOURCE=nil\n        vr_active_slot=1;vr_delete_slot_files()','-- negative control: retained prior file slots')
 script.write_text(source)
 image=Image.new('RGB',(512,256));draw=ImageDraw.Draw(image)
 for y in range(256):draw.line((0,y,511,y),fill=(y,255-y,y//2))
 draw.rectangle((10,10,120,90),fill='red');draw.ellipse((280,60,490,240),fill='cyan');image.save(d/'flat.png');image.save(d/'native.png')
 log=(d/'log').open('w');p=subprocess.Popen([MPV,'--no-config','--config-dir='+str(d),'--vo=gpu-next','--gpu-sw=yes','--gpu-api=opengl','--gpu-context=x11egl','--hwdec=no','--pause','--keep-open=yes','--idle=yes','--force-window=yes','--no-border','--geometry=512x256','--osd-level=0','--dither-depth=no','--input-ipc-server='+str(d/'ipc'),str(d/'flat.png')],stdout=log,stderr=log)
 try:
  for _ in range(200):
   if (d/'ipc').exists():break
   time.sleep(.03)
  conn=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);conn.settimeout(15);conn.connect(str(d/'ipc'));stream=conn.makefile('rb');rid=0;rev=0;kind='flat-2d3d'
  def cmd(*args):
   global rid
   rid+=1;conn.sendall((json.dumps({'command':args,'request_id':rid})+'\n').encode())
   while True:
    row=json.loads(stream.readline())
    if row.get('request_id')==rid:
     assert row['error']=='success',(args,row);return row.get('data')
  def msg(name,*args):cmd('script-message-to','vr180_look',name,*map(str,args));time.sleep(.04)
  def route(kind0,pack,on=True):
   global rev,kind
   kind=kind0;rev+=1;msg('vr180-look-store-revision',rev,kind,'store-applier')
   for name,args in [('plan-lock',['off','false']),('set-projection',[kind,2]),('set-pack',[pack,1,.5,1,0]),('set-enabled',['true' if on else 'false'])]:msg('vr180-look-'+name,*args,rev,'store-applier')
   msg('vr180-look-route-complete',rev,'store-applier')
  def screenshot(name):
   time.sleep(.2);cmd('screenshot-to-file',str(d/(name+'.png')),'window');return np.asarray(Image.open(d/(name+'.png')).convert('RGB')).astype(int)
  def receipt(expected):
   # script-message IPC acknowledges enqueue, not handler completion. Hashing
   # and repair can exceed40ms; wait for current evidence, never accept stale PASS.
   deadline=time.monotonic()+5;row=None;last_error=None
   while time.monotonic()<deadline:
    row=cmd('get_property','user-data/vr180-look/installed-shader')
    try:
     assert row['verdict']=='PASS' and row['expected']==expected and row['revision']==rev,row
     if expected!='none':
      entry=Path(row['entry'])
      assert row['sha256']==hashlib.sha256(entry.read_bytes()).hexdigest(),row
      assert row['entry'] in cmd('get_property','glsl-shaders'),row
     print('PASS installed variant/hash/list/current-revision',expected,row['variant'],flush=True)
     return row
    except (AssertionError,FileNotFoundError,KeyError,TypeError) as error:
     last_error=repr(error);time.sleep(.02)
   raise AssertionError(('no current consistent installed receipt within5s',row,last_error))
  for _ in range(100):
   try:
    if cmd('get_property','video-params'):break
   except Exception:pass
   time.sleep(.03)
  baseline=screenshot('baseline');cmd('load-script',str(script));time.sleep(.2)
  route('vr180',0);receipt('native');native=screenshot('native');assert np.any(native!=baseline)
  cmd('loadfile',str(d/'flat.png'),'replace');time.sleep(.25);route('mono',0);receipt('extended');plain=screenshot('plain');Image.fromarray(plain.astype('uint8')).save('/downloads/shader-plain.png');Image.fromarray(baseline.astype('uint8')).save('/downloads/shader-baseline.png');assert np.array_equal(plain,baseline),(plain.shape,baseline.shape,np.abs(plain-baseline).max())
  route('flat-sbs',0);receipt('extended');flat=screenshot('sbs')
  for i in range(2):
   route('vr180',0);receipt('native');assert np.array_equal(screenshot('native-loop'+str(i)),native)
   route('flat-sbs',0);receipt('extended');assert np.array_equal(screenshot('sbs-loop'+str(i)),flat)
  route('flat-sbs',0,False);receipt('none');assert np.array_equal(screenshot('off'),baseline)
  msg('vr180-look-tools-active','true');receipt('extended');assert np.array_equal(screenshot('head-off'),baseline)
  route('flat-sbs',0);receipt('extended');assert np.array_equal(screenshot('sbs-head'),flat)
  # Corrupt the actual installed slot: route receipt must detect and rewrite.
  row=cmd('get_property','user-data/vr180-look/installed-shader');Path(row['entry']).write_text('corrupted shader')
  msg('vr180-look-route-complete',rev,'store-applier');receipt('extended');repaired=screenshot('repaired');Image.fromarray(repaired.astype('uint8')).save('/downloads/shader-repaired.png');Image.fromarray(flat.astype('uint8')).save('/downloads/shader-sbs.png');assert np.array_equal(repaired,flat),(np.abs(repaired-flat).max(),np.count_nonzero(np.any(repaired!=flat,axis=2)))
  cmd('stop');cmd('loadfile',str(d/'flat.png'),'replace');time.sleep(.3);route('flat-sbs',0);receipt('extended');assert np.array_equal(screenshot('reopened'),flat)
  route('flat-2d3d',3);receipt('pack');budget_off=screenshot('budget-off')
  msg('gor3d-budget','on=yes conv=0 comp=0.35');receipt('pack');affine=screenshot('affine-budget-on');assert np.any(affine!=budget_off),'new affine preset did not change pixels'
  msg('gor3d-budget','on=yes conv=-0.08 comp=0.65');receipt('pack');budget_on=screenshot('budget-on');Image.fromarray(budget_off.astype('uint8')).save('/downloads/d3-budget-real-mpv-off.png');Image.fromarray(budget_on.astype('uint8')).save('/downloads/d3-budget-real-mpv-on.png')
  assert np.any(budget_on!=budget_off),'explicit D did not change pixels'
  msg('gor3d-budget','on=no');receipt('pack');assert np.array_equal(screenshot('budget-off-restored'),budget_off),'D off did not restore exact pixels'
  for n in range(5):
   msg('gor3d-budget','on=yes conv=0 comp=0.35');receipt('pack');assert np.array_equal(screenshot('repeat-on'+str(n)),affine),'reused shader path served wrong ON pixels'
   msg('gor3d-budget','on=no');receipt('pack');assert np.array_equal(screenshot('repeat-off'+str(n)),budget_off),'repeated OFF did not restore pixels'
  assert len(list(d.glob('shader/epoch-*/*.glsl')))<=2,'retired shader files leaked'
  print('PASS 5 repeated ON/OFF cycles exact pixels; <=2 live shader files')
  route('flat-sbs',0);baked=screenshot('baked-budget-off')
  msg('gor3d-budget','on=yes conv=0.1');receipt('extended');assert np.array_equal(screenshot('baked-budget-on'),baked),'D changed baked source'
  msg('gor3d-budget','on=no')
  print('PASS real gpu-next D on/off installed receipt; off restores pixels0; baked SBS bypass pixels0')
  assert '3D-SHADER-MISMATCH' in (d/'log').read_text()
  print('PASS gpu-next native->plain->SBS->Off->head->SBS->reopen pixels0; installed-slot corruption detected/repaired')
  route('flat-2d3d',3);receipt('pack')
  msg('vr180-look-set-pack',3,1,.5,.6,0,rev,'store-applier')
  cmd('set_property','video-zoom',-.6)
  cmd('set_property','video-scale-x',.75)
  before=screenshot('fit-before')
  cmd('script-message-to','vr180_look','vr180-look-smooth-fit')
  time.sleep(.12)
  cmd('screenshot-to-file','/downloads/195k-fit-mid.png','window')
  middle=np.asarray(Image.open('/downloads/195k-fit-mid.png').convert('RGB')).astype(int)
  after=screenshot('fit-after')
  cmd('script-message-to','vr180_look','vr180-look-full-fit')
  manual=screenshot('manual-reset')
  print('pixel deltas',np.count_nonzero(before!=middle),np.count_nonzero(middle!=after),np.count_nonzero(after!=manual))
  Image.fromarray(before.astype('uint8')).save('/downloads/195k-fit-before.png')
  Image.fromarray(after.astype('uint8')).save('/downloads/195k-fit-after.png')
  assert np.any(before!=middle) and np.any(middle!=after)
  assert np.array_equal(after,manual),'smooth endpoint differs from actual Shift+R geometry'
  canvas=Image.new('RGB',(1536,290),'#202020');draw=ImageDraw.Draw(canvas)
  for x,img,title in [(0,before,'SBS before automatic fit'),(512,middle,'During 0.3s eased fit'),(1024,after,'Completed = manual Shift+R pixels')]:
   canvas.paste(Image.fromarray(img.astype('uint8')),(x,28));draw.text((x+12,8),title,fill='white')
  canvas.save('/downloads/195k-smooth-fit.png')
  print('PASS real mpv gpu-next captures intermediate change and exact manual Shift+R endpoint')

 finally:
  p.terminate();p.wait(timeout=10)
  if __import__('sys').exc_info()[0]:print((d/'log').read_text()[-5000:],flush=True)
