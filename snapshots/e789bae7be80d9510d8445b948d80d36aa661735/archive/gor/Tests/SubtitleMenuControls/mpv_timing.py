
# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
from pathlib import Path
import json,os,socket,subprocess,tempfile,time
r=Path(__file__).resolve().parents[2];source=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift');timing=source[source.index('enum SubtitleMenuTiming {'):]
with tempfile.TemporaryDirectory() as tmp:
 t=Path(tmp);(t/'cue.srt').write_text('1\n00:00:02,000 --> 00:00:04,000\nTIMING CUE\n')
 subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=size=640x360:rate=10','-t','10','-y',str(t/'v.mkv')],check=True)
 p=subprocess.Popen([os.environ['MPV'],'--no-config','--vo=null','--ao=null','--pause=yes','--sub-visibility=no','--sub-file='+str(t/'cue.srt'),'--input-ipc-server='+str(t/'ipc'),str(t/'v.mkv')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 try:
  for _ in range(100):
   try:s=socket.socket(socket.AF_UNIX);s.connect(str(t/'ipc'));break
   except OSError:time.sleep(.02)
  f=s.makefile('rwb',buffering=0)
  def ipc(*args):
   f.write((json.dumps({'command':args,'request_id':1})+'\n').encode())
   while True:
    row=json.loads(f.readline())
    if row.get('request_id')==1:
     assert row['error']=='success',(args,row)
     return row.get('data')
  time.sleep(.2)
  # Replay exact command arrays produced by the real menu-handler/controller test.
  output=subprocess.check_output(['python3',str(r/'Tests/SubtitleMenuControls/run.py')],text=True)
  commands=json.loads(next(line[9:] for line in output.splitlines() if line.startswith('COMMANDS ')))
  for c in commands[:-2]:ipc(*c) # final pair is the intentional transport-failure test
  assert ipc('get_property','sub-scale')==1 and ipc('get_property','sub-delay')==0 and ipc('get_property','sub-pos')==100
  assert ipc('get_property','audio-delay')==0
  rows=[]
  for delay in [0,2,-1]:
   ipc('set_property','sub-delay',delay)
   for pos in [0.5,1.5,2.5,3.5,4.5,5.5,6.5]:
    ipc('seek',pos,'absolute+exact');time.sleep(.12)
    text=ipc('get_property','sub-text');active=2+delay<=pos<=4+delay
    assert bool(text)==active,(delay,pos,text)
    if text:
     start=ipc('get_property','sub-start');end=ipc('get_property','sub-end')
     assert start==2 and end==4,'mpv still returns original timestamps'
     rows.append({'delay':delay,'time':pos,'start':start,'end':end})
  (t/'rows.json').write_text(json.dumps(rows))
  (t/'main.swift').write_text('import Foundation\n'+timing+'''
let rows=try! JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [[String:Double]]
for row in rows {
 let w=SubtitleMenuTiming.displayWindow(start:row["start"]!,end:row["end"]!,delay:row["delay"]!)
 precondition(row["time"]!>=w.start && row["time"]!<=w.end)
 let clock=SubtitleMenuTiming.lookupTime(playbackTime:row["time"]!,delay:row["delay"]!,external:true)
 precondition(clock>=row["start"]! && clock<=row["end"]!)
}
print("PASS production delayed cue windows and independent external clocks on real mpv JSON, positive/zero/negative delay; original timestamps mapped once")
''')
  subprocess.run([os.environ.get('SWIFTC','swiftc'),str(t/'main.swift'),'-o',str(t/'run')],check=True)
  subprocess.run([str(t/'run'),str(t/'rows.json')],check=True)
  print('PASS real mpv0.41: exact menu commands scale/delay/position/audio +/- and resets; reset subtitles scale1/delay0/pos100;21 delayed/seek cue checks; audio unchanged except explicit actions')
 finally:p.terminate();p.wait()
