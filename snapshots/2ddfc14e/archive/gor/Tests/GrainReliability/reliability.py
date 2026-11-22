#!/usr/bin/env python3
"""Grain reliability: real product Lua + real mpv window pixels; no CPU shader model.
Exit 0 PASS, 1 measured/assertion failure, 2 NOT_RUN (missing capability).
"""
import argparse, hashlib, json, os, pathlib, shutil, socket, subprocess, sys, tempfile, time

class NotRun(Exception): pass

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def need(ok, why):
    if not ok: raise AssertionError(why)

class Player:
    def __init__(self, executable, scripts, root, extra=(), video=None, render=True):
        self.root=root; self.sock=root/'ipc'; self.log=root/'mpv.log'; self.fp=self.log.open('wb')
        config=root/'config'; config.mkdir(); (config/'shader').mkdir()
        env=dict(os.environ)
        if sys.platform.startswith('linux'): env['LIBGL_ALWAYS_SOFTWARE']='1'
        def limits():
            import resource
            resource.setrlimit(resource.RLIMIT_FSIZE,(2*1024*1024,2*1024*1024))
            resource.setrlimit(resource.RLIMIT_CPU,(20,20))
        for key, value in [('HOME',root/'home'),('TMPDIR',root/'tmp'),('XDG_CACHE_HOME',root/'cache'),('XDG_STATE_HOME',root/'state')]:
            value.mkdir(exist_ok=True); env[key]=str(value)
        args=[executable,'--load-scripts=no','--config-dir='+str(config),'--input-ipc-server='+str(self.sock),
              '--ao=null','--idle=yes','--keep-open=yes','--osc=no','--osd-level=0','--input-default-bindings=no',
              '--input-terminal=no','--terminal=yes','--msg-level=all=warn','--script-opts=photon-scriptdir='+str(scripts),
              '--watch-later-options=','--save-position-on-quit=no']
        if render:
            args+=['--vo=gpu-next','--pause=yes','--image-display-duration=inf','--geometry=256x144',
                   '--autofit=256x144','--border=no','--dither-depth=no','--deband=no','--interpolation=no']
            if sys.platform.startswith('linux'): args+=['--gpu-context=x11egl','--gpu-sw=yes']
        else: args+=['--vo=null']
        args+=list(extra)
        if video: args.append(str(video))
        self.proc=subprocess.Popen(args,env=env,stdout=self.fp,stderr=subprocess.STDOUT,preexec_fn=limits)
        self.conn=None; self.stream=None; self.seq=0
        deadline=time.monotonic()+10
        while time.monotonic()<deadline:
            if self.proc.poll() is not None: raise NotRun('mpv exited at startup: '+self.read_log())
            try:
                self.conn=socket.socket(socket.AF_UNIX); self.conn.settimeout(5); self.conn.connect(str(self.sock)); self.stream=self.conn.makefile('rb'); break
            except (OSError,FileNotFoundError):
                if self.conn: self.conn.close()
                time.sleep(.05)
        else: raise NotRun('mpv IPC startup timeout')
    def read_log(self):
        self.fp.flush(); detail=self.root/'detail.log'; return (detail.read_text(errors='replace') if detail.exists() else self.log.read_text(errors='replace'))[-12000:]
    def cmd(self,*cmd):
        self.seq+=1; rid=self.seq; self.conn.sendall((json.dumps({'command':list(cmd),'request_id':rid})+'\n').encode())
        while True:
            raw=self.stream.readline(2*1024*1024)
            if not raw: raise RuntimeError('mpv IPC closed: '+self.read_log())
            event=json.loads(raw)
            if event.get('request_id')==rid:
                need(event.get('error')=='success','mpv command failed: '+json.dumps(event)); return event.get('data')
    def close(self):
        if self.proc.poll() is None:
            try: self.cmd('quit')
            except Exception: pass
            try: self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired: self.proc.kill(); self.proc.wait()
        if self.stream: self.stream.close()
        if self.conn: self.conn.close()
        self.fp.close()


def fixtures(root):
    import numpy as np
    from PIL import Image
    y,x=np.indices((144,256)); results=[]
    for label,level in [('low',32),('mid',128),('high',224)]:
        for kind in ['flat','near-flat','gradient']:
            a=np.full((144,256),level,dtype=float)
            if kind=='near-flat': a+=((x*17+y*31)%3)-1
            if kind=='gradient': a+=np.linspace(-12,12,256)[None,:]
            a=np.rint(a).astype('uint8'); need(a.min()>0 and a.max()<255,'clipped fixture')
            path=root/(kind+'-'+label+'.png'); Image.fromarray(np.repeat(a[:,:,None],3,axis=2)).save(path)
            results.append((kind,label,path))
    return results

def pixel_grid(executable,scripts,root,report):
    import numpy as np
    from PIL import Image
    cases=[(kind,label,path,'default',[]) for kind,label,path in fixtures(root)]
    controls=[('manual-strength-zero',[('photon-grain-set-strength','0')]),
              ('zone-sensitivity-zero',[(name,'0') for name in ['photon-grain-set-shadow-sensitivity','photon-grain-set-midtone-sensitivity','photon-grain-set-highlight-sensitivity']]),
            ('offset-floor',[('photon-grain-set-amount','.9')]*48),
              ('compat-toggle-off',[('photon-grain-set-amount','1.0')])]
    if not report.get('defaults_only'):
        cases.extend(('flat','mid',root/'flat-mid.png',name,commands) for name,commands in controls)
    failures=[]
    for kind,label,fixture,control,commands in cases:
        session=root/(kind+'-'+label+'-'+control); session.mkdir(); p=None
        try:
            p=Player(executable,scripts,session,extra=['--script='+str(scripts/'photon-grain.lua')],video=fixture)
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                paths=p.cmd('get_property','glsl-shaders')
                try: ready=p.cmd('get_property','video-out-params')
                except AssertionError: ready=None
                if paths and ready: break
                time.sleep(.05)
            else: raise AssertionError('grain shader not active: '+p.read_log())
            # No strength, amount, size, shader text or source-noise overrides.
            # Full production script pushes its default engine controls.
            for name,value in commands: p.cmd('script-message',name,value)
            time.sleep(.25)
            on=session/'on.png'; p.cmd('screenshot-to-file',str(on),'window')
            opts=p.cmd('get_property','glsl-shader-opts')
            optmap=opts if isinstance(opts,dict) else dict(x.split('=',1) for x in opts)
            default_strength=float(__import__('re').search(r'local GRAIN_BASE_STRENGTH\s*=\s*([\d.]+)',(scripts/'photon-grain.lua').read_text()).group(1))
            observed_strength=[float(v) for k,v in optmap.items() if k.endswith('/BASE_STRENGTH')]
            if control=='default':need(observed_strength and all(v==default_strength for v in observed_strength),'not default grain strength')
            p.cmd('script-message','photon-grain-set-target-enabled','false'); time.sleep(.25)
            need(not p.cmd('get_property','glsl-shaders'),'grain shader still active after OFF')
            off=session/'off.png'; p.cmd('screenshot-to-file',str(off),'window')
            off2=session/'off2.png'; p.cmd('screenshot-to-file',str(off2),'window')
            a=np.array(Image.open(on).convert('RGB'),dtype=float); b=np.array(Image.open(off).convert('RGB'),dtype=float)
            c=np.array(Image.open(off2).convert('RGB'),dtype=float)
            need(a.shape==b.shape==c.shape==(144,256,3),'output dimensions changed or wrong picture area')
            # Whole image, every RGB sample. OFF/OFF rejects unrelated render noise.
            need(np.array_equal(b,c),'OFF output is not deterministic')
            delta=a-b; sigma=float(delta.std()); luma=delta@np.array([.299,.587,.114]); luma_sigma=float(luma.std())
            row=dict(kind=kind,luma=label,control=control,sigma_rgb_levels=sigma,sigma_luma_levels=luma_sigma,
                     changed_samples=int(np.count_nonzero(delta)),pixels=int(a.shape[0]*a.shape[1]),
                     output_wh=[a.shape[1],a.shape[0]],input_sha256=sha(fixture),
                     on_sha256=sha(on),off_sha256=sha(off),shader_opts=opts)
            report['grid'].append(row)
            if report.get('evidence_dir'):
                out=pathlib.Path(report['evidence_dir']); out.mkdir(parents=True,exist_ok=True)
                for name,path in [('on',on),('off',off),('input',fixture)]:
                    shutil.copyfile(path,out/(kind+'-'+label+'-'+control+'-'+name+'.png'))
            need(np.isfinite(delta).all(),'nonfinite output')
            if control=='default':
                row['scope']='default-nonzero-required'
                if not (sigma>0 and luma_sigma>0 and row['changed_samples']>0):
                    failures.append('P0_ZERO_GRAIN '+kind+' '+label+' '+control)
            elif control in ['offset-floor','compat-toggle-off']:
                row['scope']='explicit-user-OFF-must-stay-zero'
                if sigma!=0 or row['changed_samples']!=0:failures.append('EXPLICIT_OFF_NOT_ZERO '+control)
            else:
                row['scope']='known-separate-P0-candidate-explicit-user-setting-nonblocking'
                row['zero_observed']=sigma==0
            log=p.read_log().lower()
            need(not any(s in log for s in ['lua error','failed to compile','shader compilation failed','error loading hook']),'shader/script error: '+log)
        finally:
            if p: p.close()
    if failures:
        report['gpu_pixels']='FAIL'; report['p0_findings']=failures
        raise AssertionError('; '.join(failures))
    report['gpu_pixels']='PASS'


def learning_relaunch(executable,scripts,root,report,g2_path):
    encoder=shutil.which('ffmpeg')
    if not encoder: raise NotRun('ffmpeg required for lossless decoded learning fixture')
    video=root/'learning.mkv'
    subprocess.run([encoder,'-v','error','-loop','1','-i',str(root/'flat-mid.png'),'-t','2','-r','24','-c:v','ffv1','-y',str(video)],check=True,timeout=10)
    source=(scripts/'photon.lua').read_text()
    start=source.index('-- U-G2: schema/event learner')
    end=source.index('\nfunction GS.look_file()',start)
    product_slice=source[start:end]
    report['learning_source_slice_sha256']=hashlib.sha256(product_slice.encode()).hexdigest()
    # Real emitter/manual receivers run in the complete grain script. Only the
    # master learner/solver slice is loaded, avoiding unrelated master services.
    # No renderer math is reproduced here.
    vectors=[dict(mode=mode,strength=[7.2,8.4,9.0],size=[.88,.96,1.04]) for mode in ['on','off']]
    if g2_path:
        data=json.loads(g2_path.read_text())
        need(isinstance(data,list) and 0<len(data)<=16,'G2 vectors must be 1..16 cases')
        for case in data:
            need(set(case)=={'mode','strength','size'},'G2 vector keys invalid')
            need(case['mode'] in ['on','off'],'G2 mode invalid')
            for key in ['strength','size']:
                need(isinstance(case[key],list) and len(case[key])==3,'G2 requires three distinct manual invocations')
                need(all(isinstance(v,(float,int)) and 0<v<=(60 if key=='strength' else 64) for v in case[key]),'G2 value invalid')
        vectors+=data; report['g2_vectors']=dict(status='CONNECTED',sha256=sha(g2_path),cases=len(data))
    report['learning_cases']=[]
    for index,case in enumerate(vectors):
        state_root=root/('learning-'+str(index)); state_root.mkdir(); state=state_root/'gor_look.txt'
        automatic=None; persisted=None
        for phase in ['train','restart']:
            run=state_root/phase; run.mkdir(); harness=run/'relaunch.lua'
            prelude="""local mp=require('mp')
local utils=require('mp.utils')
package.path=__SCRIPTS__..'/?.lua;'..package.path
local native=mp.command_native
mp.command_native=function(c)
 if c[1]=='expand-path' and c[2]=='~~state/gor_look.txt' then return __STATE__ end
 return native(c)
end
local math_max,math_min=math.max,math.min
local DOC={active=true,gen=1,name='reliability-fixture'}
local SIZE_GOV={program_on=__ON__}
local GS={mult_floor=.35,legacy_min=.4,legacy_max=1.25,seed_look=function()return 1 end}
""".replace('__SCRIPTS__',json.dumps(str(scripts))).replace('__STATE__',json.dumps(str(state))).replace('__ON__','true' if case['mode']=='on' else 'false')
            tail="""
local function snapshot()
 local class=GS.learning_class(); assert(class,'missing real decoded class')
 local target,count=GS.learning:target(class,'strength')
 local starget,scount=GS.learning:target(class,'size')
 local solve=GS.solve_mult(1,1,.25,1,SIZE_GOV.program_on)
 local size=SIZE_GOV.ug2_solve(1)
 return {class=class,strength_count=count,size_count=scount,target=target,size_target=starget,solve=solve,size_solve=size}
end
local ready_timer
ready_timer=mp.add_periodic_timer(.1,function()
 if not GS.learning_class() then return end
 ready_timer:kill()
 local before=snapshot()
 mp.commandv('script-message','photon-grain-doc','1','reliability-fixture')
 mp.add_timeout(.15,function()
  __TRAIN__
  mp.add_timeout(.4,function()
   local after=snapshot()
   -- Pure solve probes cannot create new manual events.
   for i=1,12 do GS.solve_mult(1,1,.25,1,SIZE_GOV.program_on) end
   local stable=snapshot();assert(stable.strength_count==after.strength_count)
   mp.set_property_native('user-data/grain-reliability',{before=before,after=after,stable=stable})
  end)
 end)
end)
"""
            train=''
            if phase=='train':
                for value in case['strength']: train+="mp.commandv('script-message','photon-grain-set-strength',"+json.dumps(str(value))+")\n"
                for value in case['size']: train+="mp.commandv('script-message','photon-grain-set-size',"+json.dumps(str(value))+")\n"
            harness.write_text(prelude+product_slice+tail.replace('__TRAIN__',train))
            p=None
            try:
                p=Player(executable,scripts,run,extra=['--script='+str(scripts/'photon-grain.lua'),'--script='+str(harness),
                    '--script-opts-append=photon-adaptive-program='+('true' if case['mode']=='on' else 'false')],
                    video=video)
                deadline=time.monotonic()+8; result=None
                while time.monotonic()<deadline:
                    try: result=p.cmd('get_property','user-data/grain-reliability')
                    except AssertionError: pass
                    if result: break
                    time.sleep(.05)
                need(result is not None,'learning harness timed out: '+p.read_log())
                a=result['after']; b=result['before']
                need(a['strength_count']==a['size_count']==3,'three manual events did not persist: '+json.dumps(result))
                stored=json.loads(state.read_text())['classes'][a['class']]
                need(len({e['id'] for e in stored['strength']})==3,'event IDs not distinct')
                need(all(e['mode']==case['mode'] for rows in stored.values() for e in rows),'manual mode mismatch')
                if phase=='train':
                    need(b['strength_count']==0,'dirty initial learning state'); automatic=b['solve']
                    need(a['solve']!=automatic,'learned next adaptive solve unchanged')
                    values=p.cmd('get_property','glsl-shader-opts')
                    # Current manual strength is still live, never resumed by learning.
                    opts=values if isinstance(values,dict) else dict(x.split('=',1) for x in values)
                    strength=[float(v) for k,v in opts.items() if k.endswith('/BASE_STRENGTH')]
                    need(strength and all(abs(v-case['strength'][-1])<1e-5 for v in strength),'learning overwrote current manual strength')
                    persisted=state.read_bytes()
                    report['learning_cases'].append(dict(vector=case,train=result))
                else:
                    need(state.read_bytes()==persisted,'restart changed persisted bytes')
                    train_result=report['learning_cases'][-1]['train']['after']
                    need(a==train_result and b==train_result,'new process did not restore actual solve/counts')
                    need(a['solve']!=automatic,'relaunch adaptive solve ignored learning')
                    report['learning_cases'][-1]['restart']=result
                    report['learning_cases'][-1]['persisted_sha256']=sha(state)
                need('lua error' not in p.read_log().lower(),'Lua error: '+p.read_log())
            finally:
                if p:p.close()
    report['learning_relaunch']='PASS'

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--scripts',type=pathlib.Path)
    ap.add_argument('--mpv',default=os.environ.get('GRAIN_RELIABILITY_MPV'))
    ap.add_argument('--report',type=pathlib.Path); ap.add_argument('--g2-vectors',type=pathlib.Path)
    ap.add_argument('--evidence-dir',type=pathlib.Path)
    args=ap.parse_args(); scripts=(args.scripts or pathlib.Path(__file__).resolve().parents[2]/'Resources/vendor/mpv/scripts').resolve()
    r=dict(schema=1,result='NOT_RUN',source_hashes={},platform=sys.platform,gpu_pixels='NOT_RUN',learning_relaunch='NOT_RUN',grid=[],g2_vectors='NOT_CONNECTED')
    if args.evidence_dir: r['evidence_dir']=str(args.evidence_dir.resolve())
    code=2
    try:
        try: import numpy; import PIL
        except ImportError as e: raise NotRun('Install test-only requirements.txt: '+str(e))
        for name in ['photon-grain.lua','photon-common.lua','photon-shader-recovery.lua','photon-look-learning.lua','photon.lua']:
            p=scripts/name
            if not p.is_file(): raise NotRun('Missing production dependency '+str(p))
            r['source_hashes'][name]=sha(p)
        executable=args.mpv or shutil.which('mpv')
        if not executable or not pathlib.Path(executable).is_file(): raise NotRun('Set GRAIN_RELIABILITY_MPV to exact candidate mpv executable')
        r['mpv_sha256']=sha(pathlib.Path(executable)); r['mpv_version']=subprocess.run([executable,'--version'],capture_output=True,text=True,timeout=8).stdout[:4096]
        if sys.platform.startswith('linux') and not os.environ.get('DISPLAY'): raise NotRun('Linux render requires DISPLAY (use xvfb-run -a)')
        with tempfile.TemporaryDirectory(prefix='grain-reliability-') as temp:
            root=pathlib.Path(temp)
            errors=[]
            from ug3_test import run as ug3_run
            ug3_rc,ug3_report=ug3_run(scripts);r['ug3_ratio']=ug3_report
            if ug3_rc:errors.append('U-G3 state regressions failed: '+ug3_report['detail'])
            try: pixel_grid(executable,scripts,root,r)
            except AssertionError as e: errors.append(str(e))
            try: learning_relaunch(executable,scripts,root,r,args.g2_vectors)
            except AssertionError as e: errors.append(str(e))
            if errors: raise AssertionError('; '.join(errors))
        r['result']='PASS'; code=0
    except NotRun as e: r['reason']=str(e)
    except Exception as e: r['result']='FAIL'; r['reason']=str(e); code=1
    text=json.dumps(r,sort_keys=True,indent=2)+'\n'
    if args.report: args.report.write_text(text)
    print(text,end=''); return code

if __name__=='__main__': sys.exit(main())
