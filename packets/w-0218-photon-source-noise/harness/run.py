import pathlib,subprocess,time,os,json,threading
r=pathlib.Path(__file__).resolve().parent.parent;os.environ['LIBGL_ALWAYS_SOFTWARE']='1';os.environ['OMP_NUM_THREADS']='2';os.environ['LP_NUM_THREADS']='2'
# Each invocation owns and cleans its actual virtual display, no detached processes.
def run(h,on):
 tag=f'{h}-'+('photon'if on else'baseline');out=r/'results'/tag;out.mkdir(parents=True,exist_ok=True)
 xv=subprocess.Popen(['Xvfb',':118','-screen','0','2276x1280x24','-nolisten','tcp'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL);time.sleep(.4)
 env={**os.environ,'DISPLAY':':118'};cmd=[os.environ.get('MPV', 'mpv'),'--no-config','--no-audio','--vo=gpu-next','--gpu-api=opengl','--gpu-context=x11egl','--gpu-sw=yes','--vd-lavc-threads=2','--cache=no','--keep-open=yes','--script='+str(r/'harness/observer.lua'),'--script-opts=photon-scriptdir='+str(r/'source')+',harness-shot='+str(out/'frame.png'),'--log-file='+str(out/'mpv.log'),'--msg-level=all=warn,observer=info,photon=info,photon_grain=info,photon_sharp=info','--config-dir='+str(out/'config')]
 (out/'config').mkdir(exist_ok=True)
 if h==2160:cmd+=['--geometry=1956x1100+0+0','--autofit=1956x1100']
 else:cmd+=['--fullscreen=yes']
 if on:
  cmd+=['--script='+str(r/'source'/n)for n in ['photon.lua','photon-grain.lua','photon-sharp.lua','photon-hud.lua']]
 cmd+=[str(r/'media'/f'{h}p.mp4')]
 ticks=os.sysconf(os.sysconf_names['SC_CLK_TCK']);cpu=[];t0=time.monotonic()
 with open(out/'stdout.log','w')as f:
  p=subprocess.Popen(cmd,stdout=f,stderr=subprocess.STDOUT,env=env)
  prev=None
  try:
   while p.poll()is None and time.monotonic()-t0<75:
    now=time.monotonic()
    try:
     s=pathlib.Path(f'/proc/{p.pid}/stat').read_text().split();v=(int(s[13])+int(s[14]))/ticks
     if prev:cpu.append({'wall':now-t0,'cpu_one_core_pct':100*(v-prev[1])/(now-prev[0])})
     prev=(now,v)
    except:pass
    time.sleep(.5)
   if p.poll()is None:p.terminate();p.wait(timeout=5)
  finally:
   xv.terminate();xv.wait(timeout=5)
 (out/'cpu.json').write_text(json.dumps({'cmd':cmd,'cpu_samples':cpu,'returncode':p.returncode,'units':'100%=one logical core, mpv process only; software renderer included, Linux not Mac'},indent=2));print(tag,p.returncode,len(cpu),flush=True)
if __name__=='__main__':
 import sys;run(int(sys.argv[1]),sys.argv[2]=='on')
