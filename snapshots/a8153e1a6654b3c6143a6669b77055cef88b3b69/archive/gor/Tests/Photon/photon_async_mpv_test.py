#!/usr/bin/env python3
"""Whole production script on real mpv GPU. Callback delivery delayed only by test seam.
Checks raw byte identity on paused frame, live frame pairs, fences and Lua responsiveness.
Not an owner-device drop/AVsync A/B result.
"""
from pathlib import Path
import os,subprocess,socket,json,time,tempfile,shutil
r=Path(__file__).resolve().parents[2];scripts=r/'Resources/vendor/mpv/scripts'
mpv=os.environ['GOR_TEST_MPV']
seam=r'''
-- Test-only seam appended to a disposable copy, never installed.
COST.test={};COST.test_delay=0.35
COST.test_native_async=mp.command_native_async
mp.command_native_async=function(command,callback)
 if command[1]=="screenshot-raw" then
  return COST.test_native_async(command,function(ok,res)
   mp.add_timeout(COST.test_delay,function()callback(not COST.test_fail and ok,res)end)
  end)
 end
 return COST.test_native_async(command,callback)
end
COST.test_beat=0
mp.add_periodic_timer(.025,function()COST.test_beat=COST.test_beat+1 end)
function COST.test_publish()mp.set_property_native("user-data/photon-async-test",COST.test)end
mp.register_script_message("async-test",function(kind)
 enabled=false;playback_active=false
 COST.read_budget={times={},deferred=0,requests=0};SHARE.clear()
 COST.test={kind=kind,done=false,errors=0};COST.test_fail=false
 local beat=COST.test_beat
 if kind=="raw" then
  local reference=mp.command_native({"screenshot-raw","video"})
  COST.spawn("TEST",function()
   local ok,shot=COST.shot("own")
   COST.test.identical=ok and shot.data==reference.data and shot.w==reference.w and shot.h==reference.h and shot.stride==reference.stride
   COST.test.beats=COST.test_beat-beat
  end,function(ok,err)COST.test.done=true;COST.test.ok=ok;COST.test.error=tostring(err);COST.test_publish()end)
 elseif kind=="luma" then
  local original,w,h,mean=GS.capture_luma()
  assert(original)
  COST.spawn("GS",function()
   local measured,mw,mh,mm=GS.capture_luma()
   local same=measured~=nil and w==mw and h==mh and mean==mm
   if same then
    for i=0,w*h-1 do
     if original[i]~=measured[i] then same=false end
    end
   end
   COST.test.identical=same
  end,function(ok,err)COST.test.done=true;COST.test.ok=ok;COST.test.error=tostring(err);COST.test_publish()end)
 elseif kind=="fence" then
  COST.spawn("TEST",function()COST.shot("own");COST.test.stale_body_ran=true end,
   function(ok,err)COST.test.done=true;COST.test.reason=tostring(err);COST.test_publish()end)
  mp.add_timeout(.10,function()SHARE.clear()end)
 elseif kind=="fence-probes" or kind=="failed-probes" then
  enabled=true;playback_active=true;is_sdr=true;is_live=true;DOC.active=true
  BK.running=false;BK.done=false;BK.count=1;BK.interval=1
  LG.count=1;LG.interval=1;grain_analysis_running=false;grain_size_hint_sent=false
  RG.fail_streak=2;LIVE_CALIB.capture_failed=false;LIVE_CALIB.last_capture=-10
  COST.test_fail=kind=="failed-probes"
  bk_run_probe()
  COST.read_budget={times={},deferred=0,requests=0}
  gr_run_live_grain_probe()
  COST.read_budget={times={},deferred=0,requests=0}
  COST.spawn("RG",RG.tick_body)
  COST.read_budget={times={},deferred=0,requests=0}
  COST.spawn("SDRLIVE",update_sdr_live)
  mp.add_timeout(.1,function()if kind=="fence-probes" then SHARE.clear() end;enabled=false;playback_active=false end)
  mp.add_timeout(.75,function()
   COST.test.bk_samples=#BK.samples;COST.test.bk_done=BK.done
   COST.test.lg_samples=#LG.samples;COST.test.lg_done=grain_size_hint_sent
   COST.test.rg_fail_streak=RG.fail_streak;COST.test.sdr_failed=LIVE_CALIB.capture_failed
   COST.test.bk_retry=BK.timer~=nil;COST.test.done=true;COST.test_publish()
  end)
 elseif kind=="pair" then
  COST.spawn("GS",function()
   local ok,a=COST.shot("own");assert(ok)
   COST.test.first_time=mp.get_property_number("time-pos")
   COST.test.reserved=not COST.capture_room(1)
   local good,b=COST.shot("own");assert(good)
   COST.test.second_time=mp.get_property_number("time-pos")
   COST.test.distinct=a.data~=b.data;COST.test.beats=COST.test_beat-beat
  end,function(ok,err)COST.test.done=true;COST.test.ok=ok;COST.test.error=tostring(err);COST.test_publish()end)
 elseif kind=="hdr" then
  enabled=true;is_hdr=true;HDR_STATE.hue_s2_last_try=-10;HDR_STATE.screenshot_last_t=-10
  COST.test_ticks=0;COST.test_real_get=mp.get_property_native
  mp.get_property_native=function(k,...)
   if k=="video-out-params" then return {["avg-pq-y"]=.3,["max-pq-y"]=.5}end
   return COST.test_real_get(k,...)
  end
  COST.test_hdr_timer=mp.add_periodic_timer(.1,function()COST.test_ticks=COST.test_ticks+1;update_hdr()end)
  mp.add_timeout(.24,function()COST.test.parked=COST._active.HDRHUE~=nil;COST.test.mid_ticks=COST.test_ticks end)
  mp.add_timeout(.8,function()
   COST.test_hdr_timer:kill();mp.get_property_native=COST.test_real_get
   enabled=false;is_hdr=false
   COST.test.ticks=COST.test_ticks;COST.test.done=true;COST.test_publish()
  end)
 end
end)
'''
with tempfile.TemporaryDirectory(prefix='photon-async-') as folder:
 d=Path(folder);(d/'photon.lua').write_text((scripts/'photon.lua').read_text()+seam)
 fixture=d/'fixture.mp4'
 subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i','testsrc2=size=640x360:rate=24','-t','20','-c:v','libx264','-y',str(fixture)],check=True)
 log=(d/'mpv.log').open('w')
 p=subprocess.Popen([mpv,'--no-config','--vo=gpu-next','--gpu-sw=yes','--gpu-api=opengl','--gpu-context=x11egl','--hwdec=no','--ao=null','--pause','--keep-open=yes','--loop-file=inf','--script='+str(d/'photon.lua'),'--script-opts=photon-scriptdir='+str(scripts),'--input-ipc-server='+str(d/'ipc'),str(fixture)],stdout=log,stderr=log)
 try:
  for _ in range(150):
   if (d/'ipc').exists():break
   time.sleep(.03)
  conn=socket.socket(socket.AF_UNIX);conn.settimeout(10);conn.connect(str(d/'ipc'));stream=conn.makefile('rb');rid=0
  def cmd(*args):
   global rid
   rid+=1;conn.sendall((json.dumps({'command':args,'request_id':rid})+'\n').encode())
   while True:
    row=json.loads(stream.readline())
    if row.get('request_id')==rid:
     if row['error']!='success':return None
     return row.get('data')
  time.sleep(1.2)
  for kind in ['raw','luma','fence','fence-probes','failed-probes','pair','hdr']:
   cmd('set_property','pause',kind!='pair');time.sleep(.2)
   cmd('script-message-to','photon','async-test',kind)
   deadline=time.monotonic()+8;row=None
   while time.monotonic()<deadline:
    row=cmd('get_property','user-data/photon-async-test')
    if isinstance(row,dict) and row.get('kind')==kind and row.get('done'):break
    time.sleep(.04)
   assert row and row.get('done'),(kind,row,(d/'mpv.log').read_text()[-500:])
   if kind=='raw':
    assert row['identical'] and row['beats']>=5,row
    if os.environ.get('GOR_TEST_SCREENSHOT'):cmd('screenshot-to-file',os.environ['GOR_TEST_SCREENSHOT'],'window')
   if kind=='luma':assert row['ok'] and row['identical'],row
   if kind=='fence':assert not row.get('stale_body_ran') and row['reason']=='capture-fenced',row
   if kind=='fence-probes':assert row['bk_samples']==0 and not row['bk_done'] and row['bk_retry'] and row['lg_samples']==0 and not row['lg_done'] and row['rg_fail_streak']==2 and not row['sdr_failed'],row
   if kind=='failed-probes':assert row['bk_samples']==0 and not row['bk_done'] and row['bk_retry'] and row['lg_samples']==0 and not row['lg_done'],row
   if kind=='pair':assert row['ok'] and row['distinct'] and row['reserved'] and row['second_time']>row['first_time'],row
   if kind=='hdr':assert row['parked'] and row['mid_ticks']>=2 and row['ticks']>=6,row
   print('PASS real mpv GPU',kind,json.dumps(row,sort_keys=True))
 finally:
  p.terminate();p.wait(timeout=10);log.close()
 print('PASS whole photon script loaded; no synchronous probe fallback on tested async paths')
 print('NOT_RUN owner-device drop/AVsync, HDR display pixels, GS temporal-distribution equivalence')
