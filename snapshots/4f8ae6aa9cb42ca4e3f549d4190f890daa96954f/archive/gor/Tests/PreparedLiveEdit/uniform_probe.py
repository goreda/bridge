"""Default-off minimal gpu-next uniform probe, independent of RGB-D rollout.
Opt in with GOR_RGBD_UNIFORM_PROBE=1 and MPV_RUNTIME_BIN=/path/to/mpv.
Writes a numeric/hash receipt. A Linux pass is never Mac evidence.
"""
from pathlib import Path
import hashlib,json,os,platform,socket,struct,subprocess,tempfile,time,zlib

def pixels(path):
 data=Path(path).read_bytes();at=8;compressed=b'';channels=None
 while at<len(data):
  n=struct.unpack('>I',data[at:at+4])[0];kind=data[at+4:at+8];body=data[at+8:at+8+n];at+=12+n
  if kind==b'IHDR':
   w,h,depth,color,*_=struct.unpack('>IIBBBBB',body)
   assert depth in (8,16) and color in (2,6),(depth,color)
   channels=(3 if color==2 else 4)*(depth//8)
  if kind==b'IDAT':compressed+=body
 raw=zlib.decompress(compressed);stride=w*channels;out=bytearray();prior=bytearray(stride);at=0
 for _ in range(h):
  kind=raw[at];row=bytearray(raw[at+1:at+1+stride]);at+=1+stride
  for x in range(stride):
   a=row[x-channels] if x>=channels else 0;b=prior[x];c=prior[x-channels] if x>=channels else 0
   if kind==1:predict=a
   elif kind==2:predict=b
   elif kind==3:predict=(a+b)//2
   elif kind==4:
    p=a+b-c;pa,pb,pc=abs(p-a),abs(p-b),abs(p-c);predict=a if pa<=pb and pa<=pc else (b if pb<=pc else c)
   else:assert kind==0;predict=0
   row[x]=(row[x]+predict)&255
  out.extend(row);prior=row
 return bytes(out)

def run():
 if os.environ.get('GOR_RGBD_UNIFORM_PROBE')!='1':
  print('GOR-RGBD-UNIFORM v1 verdict=NOT_RUN reason=default_off');return
 executable=os.environ.get('MPV_RUNTIME_BIN') or os.environ.get('GOR_TEST_MPV')
 assert executable,'MPV_RUNTIME_BIN is required'
 with tempfile.TemporaryDirectory(prefix='gor-uniform-') as folder:
  d=Path(folder);(d/'frame.ppm').write_bytes(b'P6\n128 64\n255\n'+bytes([120,180,240])*128*64)
  (d/'rgbdprobe.glsl').write_text('//!PARAM live_gain\n//!TYPE float\n//!MINIMUM 0.0\n//!MAXIMUM 1.0\n0.25\n//!HOOK MAIN\n//!BIND HOOKED\nvec4 hook(){return vec4(HOOKED_tex(HOOKED_pos).rgb*live_gain,1.0);}\n')
  log=(d/'log').open('w');args=[executable,'--no-config','--vo=gpu-next','--pause','--keep-open=yes','--idle=yes','--force-window=yes','--osd-level=0','--dither-depth=no','--input-ipc-server='+str(d/'ipc'),'--glsl-shaders='+str(d/'rgbdprobe.glsl'),str(d/'frame.ppm')]
  if platform.system()=='Linux':args[1:1]=['--gpu-sw=yes','--gpu-api=opengl','--gpu-context=x11egl']
  proc=subprocess.Popen(args,stdout=log,stderr=log)
  try:
   for _ in range(200):
    if (d/'ipc').exists():break
    time.sleep(.025)
   conn=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);conn.settimeout(15);conn.connect(str(d/'ipc'));stream=conn.makefile('rb');rid=0
   def cmd(*args):
    nonlocal rid
    rid+=1;conn.sendall((json.dumps(dict(command=args,request_id=rid))+'\n').encode())
    while True:
     row=json.loads(stream.readline())
     if row.get('request_id')==rid:assert row['error']=='success',row;return row.get('data')
   time.sleep(.5);version=cmd('get_property','mpv-version')
   hashes=[]
   for i,gain in enumerate((.25,1,.25)):
    cmd('set_property','glsl-shader-opts',{'rgbdprobe/live_gain':str(gain)})
    time.sleep(.2);path=d/f'frame{i}.png';cmd('screenshot-to-file',str(path),'window');hashes.append(hashlib.sha256(pixels(path)).hexdigest())
    if os.environ.get('GOR_PROBE_EVIDENCE_DIR'):
     import shutil
     shutil.copy(path,Path(os.environ['GOR_PROBE_EVIDENCE_DIR'])/f'uniform-probe-{i}.png')
   assert hashes[0]!=hashes[1] and hashes[0]==hashes[2],hashes
   print('GOR-RGBD-UNIFORM v1 '+json.dumps(dict(verdict='PASS',platform=platform.system(),mpv=version,base_sha256=hashes[0],changed_sha256=hashes[1],restored_sha256=hashes[2],rollout=False),sort_keys=True))
  finally:
   proc.terminate();proc.wait(timeout=10)
   if __import__('sys').exc_info()[0]:print((d/'log').read_text()[-4000:])
if __name__=='__main__':run()
