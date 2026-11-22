#!/usr/bin/env python3
from pathlib import Path
import json,socket,subprocess,sys,tempfile,time

def query(path,name):
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
  s.settimeout(1);s.connect(str(path));s.sendall((json.dumps({'command':['get_property',name],'request_id':333})+'\n').encode())
  data=b''
  while len(data)<65536:
   block=s.recv(4096)
   if not block:break
   data+=block
   for line in data.splitlines():
    try:r=json.loads(line)
    except ValueError:continue
    if r.get('request_id')==333:return {'error':r.get('error'),'data':r.get('data')}
  return {'error':'missing response'}

def capture(project,tmp=None):
 tmp=Path(tmp or tempfile.gettempdir())
 print('BEGIN subtitle probe (all subtitle modes, not only live caption)')
 identity=project/'gor.app/Contents/Resources/build-id.txt'
 try:print('INSTALLED source-manifest identity '+identity.read_text()[:2048].strip())
 except OSError:print('INSTALLED identity unavailable')
 state=tmp/'gor-subtitle-state.json'
 try:
  row=json.loads(state.read_text());print('APP_STATE age_s='+str(round(time.time()-row['timestamp'],1))+' '+json.dumps(row,ensure_ascii=True)[:12000])
 except Exception as e:print('APP_STATE unavailable '+type(e).__name__+' (not evidence of visibility)')
 # Real current mpv state. Do not alter tracks/visibility or load media.
 sockets=sorted(tmp.glob('pp-*.sock'),key=lambda p:p.stat().st_mtime,reverse=True)[:4]
 for path in sockets:
  print('IPC '+path.name)
  for key in ['track-list','current-tracks/sub/id','secondary-sid','current-tracks/sub/codec','sub-text','sub-start','sub-end','sub-visibility','secondary-sub-visibility']:
   try:
    result=query(path,key)
    if key=='track-list' and isinstance(result.get('data'),list):result['data']=[t for t in result['data'] if t.get('type')=='sub']
    print(key+' '+json.dumps(result,ensure_ascii=True)[:8000])
   except Exception as e:print(key+' UNAVAILABLE '+type(e).__name__);break
 if not sockets:print('IPC unavailable: no gor player socket')
 print('END subtitle probe')
if __name__=='__main__':capture(Path(sys.argv[1]))
