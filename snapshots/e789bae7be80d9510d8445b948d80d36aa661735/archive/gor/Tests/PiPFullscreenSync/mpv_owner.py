"""Run production Lua against real mpv IPC; no native Cocoa/AX claim."""
from pathlib import Path
import json,os,socket,subprocess,tempfile,time
r=Path(__file__).resolve().parents[2];lua=(r/'Resources/vendor/mpv/scripts/gor-fit.lua').read_text()
mpv=os.environ.get('MPV');assert mpv,'Set MPV executable'
with tempfile.TemporaryDirectory() as tmp:
 t=Path(tmp);fixture=t/'video.mkv'
 subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=black:size=1280x720:rate=2','-t','1','-c:v','libx264','-y',str(fixture)],check=True)
 results=[]
 for fixed in [False,True]:
  script=t/('fixed.lua' if fixed else 'before.lua')
  old=lua.replace('  if mp.get_property_native("user-data/gor/pip-window-owned") == true then return end\n','').replace(' or mp.get_property_native("user-data/gor/pip-window-owned") == true','')
  script.write_text(lua if fixed else old)
  path=str(t/'ipc.sock');log=open(t/('fixed.log' if fixed else 'before.log'),'w')
  proc=subprocess.Popen([mpv,'--no-config','--idle=yes','--vo=null','--ao=null','--pause=yes','--keep-open=yes','--input-ipc-server='+path,'--script='+str(script)],stdout=log,stderr=log)
  try:
   for _ in range(150):
    try:client=socket.socket(socket.AF_UNIX);client.connect(path);break
    except OSError:time.sleep(.02)
   stream=client.makefile('rwb',buffering=0)
   def ipc(*args):
    stream.write((json.dumps({'command':args,'request_id':42})+'\n').encode())
    while True:
     row=json.loads(stream.readline())
     if row.get('request_id')==42:
      assert row['error']=='success',(args,row)
      return row.get('data')
   ipc('set_property','user-data/gor/fit','1920,1080,1,0,0')
   ipc('loadfile',str(fixture))
   for _ in range(100):
    try:
     if ipc('get_property','video-params')['w']==1280:break
    except (AssertionError,TypeError):pass
    time.sleep(.02)
   time.sleep(.1)
   ipc('set_property','geometry','480x270+1440+810')
   ipc('set_property','user-data/gor/pip-window-owned',True)
   ipc('set_property','user-data/gor/window-transition',True)
   ipc('set_property','fullscreen',True)
   ipc('set_property','video-aspect-override',4/3)
   time.sleep(.1)
   ipc('set_property','fullscreen',False)
   ipc('set_property','user-data/gor/window-transition',False)
   time.sleep(1.8)
   geometry=ipc('get_property','geometry');results.append(geometry)
   if fixed:assert geometry=='480x270+1440+810',geometry
   else:assert geometry!='480x270+1440+810',geometry
   ipc('quit')
  finally:
   proc.terminate();proc.wait(timeout=10);log.close()
   if os.path.exists(path):os.unlink(path)
 print('PASS real mpv Lua before/after: fullscreen/AR/transition callbacks while PiP owned; old follower overwrote saved PiP geometry to',results[0],'; fixed retains',results[1])
 print('Linux headless property/real Lua proof only, not native fullscreen or overlay pixels')
