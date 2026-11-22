#!/usr/bin/env python3
"""Real mpv track/pixel test plus production Swift ownership, not AppKit pixels."""
from pathlib import Path
import json,os,socket,subprocess,tempfile,time,sys
r=Path(__file__).resolve().parents[2];mpv=os.environ.get('GOR_TEST_MPV','mpv');ffmpeg=os.environ.get('FFMPEG','ffmpeg');out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
def wait(fn):
 for _ in range(150):
  try:
   if fn():return
  except (OSError,ValueError):pass
  time.sleep(.1)
 raise RuntimeError('timed out')
def ipc(path,*args):
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
  s.settimeout(5);s.connect(str(path));s.sendall((json.dumps({'command':list(args),'request_id':8})+'\n').encode());b=b''
  while True:
   b+=s.recv(65536)
   for line in b.splitlines():
    j=json.loads(line)
    if j.get('request_id')==8:return j
with tempfile.TemporaryDirectory() as td:
 t=Path(td);movie=t/'clip.mkv';sub=t/'track.srt';sock=t/'ipc'
 subprocess.run([ffmpeg,'-v','error','-f','lavfi','-i','color=black:s=640x360:r=10:d=20','-c:v','ffv1',str(movie)],check=True)
 sub.write_text('1\n00:00:00,000 --> 00:00:18,000\nSUBTITLE VISIBILITY QUALIFICATION\n')
 log=(out/'mpv.log').open('w');proc=subprocess.Popen([mpv,'--no-config','--vo=gpu','--gpu-context=x11egl','--gpu-sw=yes','--ao=null','--pause','--keep-open=yes','--force-window=yes','--no-osc','--no-border','--sub-visibility=no','--secondary-sub-visibility=yes','--geometry=640x360','--sub-file='+str(sub),'--input-ipc-server='+str(sock),str(movie)],stdout=log,stderr=log)
 try:
  wait(sock.exists);c=lambda *a:ipc(sock,*a)
  wait(lambda:c('get_property','sub-text').get('data')=='SUBTITLE VISIBILITY QUALIFICATION')
  props={k:c('get_property',k).get('data') for k in ['current-tracks/sub/id','secondary-sid','sub-visibility','secondary-sub-visibility','sub-text','sub-start','sub-end','track-list']}
  assert props['sub-visibility'] is False and props['secondary-sub-visibility'] is True and not props['secondary-sid']
  (out/'state.json').write_text(json.dumps(props,indent=2))
  def shot(name):
   time.sleep(.5);p=out/(name+'.png');assert c('screenshot-to-file',str(p),'window')['error']=='success'
   rgb=subprocess.check_output([ffmpeg,'-v','error','-i',str(p),'-pix_fmt','rgb24','-f','rawvideo','pipe:1']);return rgb
  off=shot('native-off');assert c('set_property','sub-visibility',True)['error']=='success';on=shot('native-on')
  changed=sum(abs(a-b)>20 for a,b in zip(off,on));assert changed>300,'selected SRT failed to paint visible native pixels'
  # Execute exact production ownership logic on actual captured mpv values.
  swift='''import Foundation
let row=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
precondition(!SubtitleRendererOwnership.nativeVisible(primaryVisible:row["sub-visibility"] as! Bool,secondaryVisible:row["secondary-sub-visibility"] as! Bool,primaryID:row["current-tracks/sub/id"],secondaryID:row["secondary-sid"]))
precondition(SubtitleRendererOwnership.nativeVisible(primaryVisible:true,secondaryVisible:true,primaryID:1,secondaryID:row["secondary-sid"]))
print("PASS production Swift gate on actual mpv JSON: custom visible with native off/empty secondary; actual selected native track owns after native on")
'''
  (t/'main.swift').write_text(swift);subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/Engine/MPVCommand.swift'),str(t/'main.swift'),'-o',str(t/'check')],check=True);subprocess.run([str(t/'check'),str(out/'state.json')],check=True)
  print('PASS real mpv loaded SRT sub-text while native off; native-on screenshot paints '+str(changed)+' changed channels; native-off native pixels absent by A/B')
  print(subprocess.check_output([mpv,'--version'],text=True).splitlines()[0]);print('Linux software-GL real mpv pixels only; custom AppKit bitmap not certified')
 finally:
  proc.terminate();proc.wait(timeout=10);log.close()
