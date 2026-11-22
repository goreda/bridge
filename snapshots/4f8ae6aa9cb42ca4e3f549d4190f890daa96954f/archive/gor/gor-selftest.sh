#!/bin/bash
# External-only lifecycle checks. build.sh owns t1/t3/t3b/scratch and transport.
set -e
root="$(cd "$(dirname "$0")" && pwd -P)"
if [ "${1:-}" != --lifeline-only ]; then
    exec bash "$root/build.sh" --selftest "$@"
fi
exec /usr/bin/python3 - "$root" <<'PY'
import os,signal,subprocess,time,re,tempfile,glob,json,shutil,resource,traceback,math
from pathlib import Path
root=Path(os.sys.argv[1]);os.sys.path.insert(0,str(root/'tools'))
bundle_id=os.environ.get('GOR_SELFTEST_BUNDLE_ID','com.gokcebalkan.gor')
if not re.fullmatch(r'com\.gokcebalkan\.gor(?:\.staging)?',bundle_id):raise SystemExit('invalid selftest bundle id')
if os.environ.get('GOR_SELFTEST_STAGED')=='1' and bundle_id=='com.gokcebalkan.gor':raise SystemExit('staged selftest refuses production id')
from vr_pack_probe import hidden_flags;quit_script='if application id "'+bundle_id+'" is running then tell application id "'+bundle_id+'" to quit'
app=root/'gor.app'; binary=app/'Contents/MacOS/gor'
mpv=root/'Resources/vendor/mpv/bin/mpv'; results=root/'.gor-selftest-last.txt'
log=open(root/'.gor-selftest-build.log','ab',buffering=0)
passed=failed=0
harness_started=last_verdict=time.monotonic()
owned=[]
quit_helpers=[]
quit_stderr=[]
alternate_input_fd=None
stage="initialization"
def limit_quit_stderr():
    resource.setrlimit(resource.RLIMIT_FSIZE,(65536,65536))
def verdict_timing(name):
    global last_verdict
    now=time.monotonic()
    line='TIMING '+name+' elapsed_s=%.3f since_previous_verdict_s=%.3f'%(now-harness_started,now-last_verdict)
    print(line,flush=True)
    with results.open('a') as f:f.write(line+'\n')
    last_verdict=now
def note(ok,name,detail):
    global passed,failed
    verdict_timing(name)
    line=('PASS' if ok else 'FAIL')+' '+name+' '+detail
    print(line,flush=True)
    with results.open('a') as f:f.write(line+'\n')
    if ok:passed+=1
    else:failed+=1
def note_skip(name,detail):
    verdict_timing(name)
    line='INCONCLUSIVE '+name+' '+detail
    print(line,flush=True)
    with results.open('a') as f:f.write(line+'\n')
def ps(pid,field):
    p=subprocess.run(['/bin/ps','-ww','-p',str(pid),'-o',field+'='],capture_output=True,text=True)
    return p.stdout.strip() if p.returncode==0 else None
def rows():
    p=subprocess.run(['/bin/ps','-axo','pid=,ppid=,comm='],capture_output=True,text=True,check=True)
    out=[]
    for l in p.stdout.splitlines():
        f=l.strip().split(None,2)
        if len(f)==3:out.append((int(f[0]),int(f[1]),f[2]))
    return out
def gor_pids():return [int(pid) for pid in __import__('axes_acceptance').live_gor_instances(binary)]
def alive(pid):return ps(pid,'pid') is not None
def wait(predicate,seconds):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        value=predicate()
        if value:return value
        time.sleep(.01)
    return None
def identity(pid):return (ps(pid,'lstart'),ps(pid,'comm'))
def stop_owned(pid,stamp):
    # Test-created exact identity only; no name sweep.
    if identity(pid)!=stamp:return
    try:os.kill(pid,signal.SIGKILL)
    except ProcessLookupError:pass
def spawn_detached(cmd,input_path=None):
    global detached_error
    with tempfile.NamedTemporaryFile(prefix='gor-detached-err.') as ef:
        helper=subprocess.run(['/bin/bash','-c','( ulimit -f 64; exec "$@" <"$INPUT" >/dev/null ) & echo $!','bash']+cmd,stdout=subprocess.PIPE,stderr=ef,text=True,timeout=3,env=dict(os.environ,INPUT=str(input_path or '/dev/null')))
        if helper.returncode or not helper.stdout.strip().isdigit():raise RuntimeError('detached helper PID unavailable')
        pid=int(helper.stdout.strip());time.sleep(.05)
        ef.seek(0);detached_error=ef.read(8192).decode('utf-8','replace')
        if detached_error:log.write(detached_error.encode())
        return pid
def quit_instance(gp):
    stamp=identity(gp)
    subprocess.run(['/usr/bin/osascript','-e',quit_script],stdout=log,stderr=log)
    wait(lambda:not alive(gp),5);stop_owned(gp,stamp)
def clip_file():
    # Generate within test's temporary directory; preserve all existing media.
    tmp=tempfile.TemporaryDirectory(prefix='gor-lifeline-clip.')
    candidate=Path(tmp.name)/'clip.mp4'
    vendor=root/'Resources/vendor'
    # The vendor contains a DIRECTORY named ffmpeg as well as its executable.
    # Never execute a directory or change permissions on the user's assets.
    ff=next((p for p in vendor.rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
    if ff:
        try:
            r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i',
              'testsrc=duration=5:size=320x240:rate=10','-f','lavfi','-i',
              'sine=frequency=440:duration=5','-pix_fmt','yuv420p','-c:a','aac',str(candidate)],stdout=log,stderr=log,timeout=20)
            if r.returncode==0 and candidate.is_file() and candidate.stat().st_size:return tmp,candidate
        except (OSError,subprocess.TimeoutExpired):
            pass # Missing permission/dyld/timeout uses the existing-media fallback.
    for base in [root/'Resources/vendor',Path.home()/'Movies']:
        if base.exists():
            for p in base.rglob('*'):
                if p.is_file() and p.suffix.lower() in ['.mp4','.mkv','.mov','.webm','.m4v'] and p.stat().st_size>0:
                    return tmp,p
    return tmp,None
LUA_FOLD_HARNESS = r'''
local srcpath = os.getenv("GOR_FOLD_SRC")
local f = assert(io.open(srcpath, "r")); local src = f:read("*a"); f:close()
local sl = assert(src:match("(local function split_lines.-\nend)"), "split_lines not found")
local af = assert(src:match("(local function apply_fold.-\nend\n)"), "apply_fold not found")
local guard = "if totalLines > #lines then totalLines = #lines end"
local function build(chunk)
    local code = "local hud_fold_state = ...\n" .. sl .. "\n" .. chunk .. "\nreturn apply_fold"
    return assert(loadstring(code))
end
local function run(chunk)
    local apply_fold = build(chunk)({ photon = { revealed = 8, direction = 1, justFlipped = false } })
    local body = "phot1 photon\n  a\n  b\n  c"
    return pcall(apply_fold, body, "photon", 8)
end
local ok_new, res_new = run(af)
local af_old = af:gsub(guard .. "[^\n]*\n", "")
assert(not af_old:find("totalLines > #lines"), "old build still has guard")
local ok_old, res_old = run(af_old)
print("FOLDGUARD new_ok=" .. tostring(ok_new) .. " old_ok=" .. tostring(ok_old) .. " old_err=" .. tostring(res_old))
mp.commandv("quit", "0")
'''

def ipc_roundtrip(sock_path,payload,timeout=2.0):
    import socket as _s
    with _s.socket(_s.AF_UNIX) as u:
        u.settimeout(timeout);u.connect(sock_path)
        u.sendall(payload.encode()+b'\n')
        buf=b''
        while True:
            chunk=u.recv(65536)
            if not chunk:break
            buf+=chunk
            while b'\n' in buf:
                line,buf=buf.split(b'\n',1)
                try:m=json.loads(line)
                except ValueError:continue
                if 'error' in m:return m
    return {'error':'no-reply'}

def menu_rotate_json(selector):
    src=(root/"Sources/gor/GorUI/MenuActions.swift").read_text()
    m=re.search(r"func "+selector+r"\(\)\s*\{\s*cmd\(#\"(.+?)\"#\)",src)
    return m.group(1) if m else None

# r3 uses GOR_TRACE_GEOM=1 only on its own test app; never target an existing app.
if gor_pids():
    note(False,'l1','existing gor instance; lifecycle tests refused')
    os.sys.exit(1)
options=subprocess.run([str(mpv),'--list-options'],capture_output=True,text=True)
if options.returncode or not re.search(r'\binput-ipc-client\b',options.stdout):
    note(False,'l1','vendor input-ipc-client unsupported; no lifecycle launch')
    os.sys.exit(1)
cliptmp,clip=clip_file()
if clip is None:
    note(False,'l1','no clip')
    cliptmp.cleanup();os.sys.exit(1)
negative=subprocess.Popen(['/bin/sleep','900']);negative_stamp=identity(negative.pid)
try:
    cases=[('l1','kill'),('l2','term'),('l3-normal-1x','quit1')]
    if os.environ.get('GOR_LIFETIME_FULL')=='1':cases.append(('l3-normal-2x','quit2'))
    for name,mode in cases:
        if gor_pids():
            note(False,name,'prior gor remains; no additional launch');break
        r=subprocess.run(['/usr/bin/open','-g','-n',str(app),'--args','--gor-no-activate',str(clip)],stdout=log,stderr=log)
        gp=wait(lambda: next(iter(gor_pids()),None),10) if r.returncode==0 else None
        if not gp:
            note(False,name,'gor did not launch');continue
        gs=identity(gp);owned.append((gp,gs))
        def child():
            # pgrep name is only a candidate source; PPID + real vendor path
            # establish owned mpv for this case, never an unrelated player.
            ids=subprocess.run(['/usr/bin/pgrep','-x','mpv'],capture_output=True,text=True)
            for v in ids.stdout.split():
                pid=int(v)
                if ps(pid,'ppid')==str(gp) and os.path.realpath(ps(pid,'comm') or '')==os.path.realpath(mpv):return pid
            return None
        childpid=wait(child,15)
        if not childpid:
            note(False,name,'no mpv child of this gor');stop_owned(gp,gs);continue
        cs=identity(childpid);owned.append((childpid,cs))
        if identity(gp)!=gs or identity(childpid)!=cs:
            note(False,name,'gor/mpv identity changed before termination');continue
        start=time.monotonic_ns()
        helpers=[]
        helper_errors=[]
        if mode=='kill':os.kill(gp,signal.SIGKILL)
        elif mode=='term':os.kill(gp,signal.SIGTERM)
        else:
            for _ in range(1 if mode=='quit1' else 2):
                ef=tempfile.TemporaryFile();quit_stderr.append(ef);helper_errors.append(ef)
                helper=subprocess.Popen(['/usr/bin/osascript','-e',quit_script],stdout=log,stderr=ef,preexec_fn=limit_quit_stderr)
                helpers.append(helper);quit_helpers.append(helper)
        if mode in ['quit1','quit2']:
            # Parent-relative rule: pre-exit UI fades are informational only.
            gor_exit=mpv_exit=None
            deadline=start+10_000_000_000
            while time.monotonic_ns()<deadline:
                now=time.monotonic_ns()
                if gor_exit is None and not alive(gp):gor_exit=now
                if mpv_exit is None and not alive(childpid):mpv_exit=now
                if gor_exit is not None and mpv_exit is not None:break
                if gor_exit is not None and now-gor_exit>=300_000_000:break
                time.sleep(.01)
            delta=None if gor_exit is None or mpv_exit is None else (mpv_exit-gor_exit)//1_000_000
            case_ok=delta is not None and delta<=300
            detail='gor-exit-from-quit-ms='+str(None if gor_exit is None else (gor_exit-start)//1_000_000)+' mpv-exit-from-quit-ms='+str(None if mpv_exit is None else (mpv_exit-start)//1_000_000)+' mpv-after-gor-ms='+str(delta)
            if gor_exit is None:detail+='; gor exit unobserved within 10s'
            elif mpv_exit is None:detail+='; mpv still alive 300ms after gor exit'
        else:
            gone=wait(lambda:not alive(childpid),1)
            elapsed=(time.monotonic_ns()-start)//1_000_000
            case_ok=bool(gone) and elapsed<=1000
            detail=('mpv gone in %d ms'%elapsed) if gone else 'mpv alive at 1000 ms gor-alive='+str(alive(gp)).lower()+' mpv-ppid='+str(ps(childpid,'ppid'))
        helper_results=[]
        for helper,ef in zip(helpers,helper_errors):
            try:rc=helper.wait(timeout=2)
            except subprocess.TimeoutExpired:
                helper.kill();helper.wait();rc=None
            ef.seek(0);text=ef.read(8192).decode('utf-8','replace')
            helper_results.append((rc,text))
            log.write(('quit-helper-'+str(len(helper_results))+' rc='+str(rc)+' bounded-stderr\n').encode())
            if text:log.write(text.encode('utf-8','replace'))
        commands_ok=all(rc==0 for rc,text in helper_results)
        # A duplicate AppKit quit can be canceled after the first succeeds.
        # Only that exact redundant response is informational after both exit
        # observations pass; never forgive timeout or an unrelated error.
        duplicate_cancel=(mode=='quit2' and case_ok and len(helper_results)==2
            and helper_results[0][0]==0
            and helper_results[1][0] not in [None,0]
            and 'User canceled.' in helper_results[1][1] and '(-128)' in helper_results[1][1])
        if duplicate_cancel and not commands_ok:
            commands_ok=True;detail+='; second quit returned -128; primary accepted and both exits observed'
        if not commands_ok:detail+='; quit command failed or timed out'
        note(case_ok and commands_ok,name,detail)
        note(alive(negative.pid) and identity(negative.pid)==negative_stamp,'l4-'+name,'unrelated sleep survives')
        # Test-owned residue only; avoid another test-driven reopening loop.
        stop_owned(gp,gs);stop_owned(childpid,cs)
        wait(lambda:not alive(gp),2)
    if os.environ.get('GOR_LIFETIME_FULL')=='1':
        # r3: HUD geometry + scroll on the real app, driven end-to-end (Mac-only:
        # real gor.app, real window, real mpv). Launches gor with the
        # observational geometry trace (GOR_TRACE_GEOM=1; append-only writes, no
        # behavior change), reaches gor's live mpv socket (pp-<gor-pid>.sock in
        # the temp dir), drives the menu's own F8/zoom/pan JSON and gor's
        # test-only user-data scroll route, and emits three separate results so
        # an unmeasurable capability records INCONCLUSIVE instead of passing:
        #   r3-hud-baseline - decode, crop-bounds and HUD layout traces exist,
        #                     layout capacity >= 1, baseline HUD region inside
        #                     the crop bounds (the v8 four-edge clamp).
        #   r3-hud-zoom     - containment against mpv's OWN osd-dimensions
        #                     rendered-picture rect (ground truth; its margins
        #                     already include zoom/pan), during and after a
        #                     zoom+pan excursion. INCONCLUSIVE when the excursion
        #                     leaves the rendered rect unchanged - then zoom
        #                     containment was not actually exercised.
        #   r3-hud-scroll   - whole-row scroll driven through gor's native
        #                     test-only user-data route (same guard/clamp/layout
        #                     path as the wheel handler): exact row movement,
        #                     clamps at both ends, outward rejection at an end,
        #                     and the no-overflow guard when max == 0.
        #   v2-replicator   - block 180 3d / v2: VR stereo chrome replication.
        #                     VR is toggled through gor's test-only user-data
        #                     route; each replicator instance frame must sit
        #                     inside its eye's drawn rect, with the eye bands
        #                     computed HERE from the shipped vr180-look.lua gap
        #                     constant and mpv's own rendered rect (never the
        #                     app's constants), and the subtitle replica offset
        #                     must equal the depth dial value.
        #   ipd-vs-dial     - block 181 2: the ipd key still changes ipd and the
        #                     dial does not, and the dial changes the subtitle
        #                     depth without touching ipd (negative controls).
        # The appended trace bytes' sha256 lands in each leg's details so the
        # capture carries the diagnostics automatically. Block 180: negative
        # margins are accepted and the bounds track the rendered picture
        # intersected with the window. When the excursion drives margins
        # negative the leg also requires the bounds to come from the accepted
        # osd path (src != target), so a stale-bounds regression fails here.
        # Zoom containment itself is checked against mpv's own osd-dimensions
        # ground truth, never against the app's own bounds.
        r3trace=Path.home()/'Library/Application Support/gor/geom_trace.log'
        r3mark=r3trace.stat().st_size if r3trace.exists() else 0
        gproc=subprocess.Popen([str(binary),'--gor-no-activate',str(clip)],stdout=log,stderr=log,env=dict(os.environ,GOR_TRACE_GEOM='1',GOR_VR_TEST_NO_CAMERA='1'))
        gp=gproc.pid;gs=identity(gp);owned.append((gp,gs))
        try:
            gosock=os.path.join(tempfile.gettempdir(),'pp-%d.sock'%gp)
            if not wait(lambda:os.path.exists(gosock),15):
                note(False,'r3-hud-baseline','gor mpv socket never appeared')
            else:
                def gcmd(*a):return ipc_roundtrip(gosock,json.dumps({'command':list(a)}))
                hud_json=menu_rotate_json('menuPhotonHUD')
                end=time.monotonic()+12;decoded=False
                while time.monotonic()<end:
                    dw=gcmd('get_property','dwidth').get('data')
                    if isinstance(dw,(int,float)) and dw>0:decoded=True;break
                    time.sleep(.2)
                def new_trace(mark):
                    try:
                        with open(r3trace,'rb') as fh:
                            fh.seek(mark);return fh.read().decode('utf-8','replace').splitlines()
                    except FileNotFoundError:
                        return []
                def wait_trace(tag,mark,seconds):
                    end=time.monotonic()+seconds
                    while time.monotonic()<end:
                        hits=[l for l in new_trace(mark) if '"k":"%s"'%tag in l]
                        if hits:return hits
                        time.sleep(.25)
                    return []
                def wait_fresh_trace(tag,line_mark,seconds,predicate):
                    end=time.monotonic()+seconds
                    while time.monotonic()<end:
                        hits=[parse(tag,l) for l in new_trace(r3mark)[line_mark:] if '"k":"%s"'%tag in l]
                        hits=[h for h in hits if h and predicate(h)]
                        if hits:return hits
                        time.sleep(.2)
                    return []
                def parse(tag,line):
                    i=line.find('{"k":"%s"'%tag)
                    try:return json.loads(line[i:])
                    except ValueError:return {}
                def last_of(tag,mark):
                    ls=[parse(tag,l) for l in new_trace(mark) if '"k":"%s"'%tag in l]
                    ls=[x for x in ls if x]
                    return ls[-1] if ls else None
                def reg_ok(l):
                    return isinstance(l,dict) and all(k in l for k in ('x','w','top','bottom'))
                def region_inside(l,rect,tol=2.0):
                    x0,y0,x1,y1=rect
                    return (l['x']>=x0-tol and l['x']+l['w']<=x1+tol
                            and l['bottom']>=y0-tol and l['top']<=y1+tol)
                def osd_dims():
                    d=gcmd('get_property','osd-dimensions').get('data')
                    if not isinstance(d,dict):return None
                    need=('w','h','ml','mr','mt','mb')
                    if not all(isinstance(d.get(k),(int,float)) for k in need):return None
                    return {k:float(d[k]) for k in need}
                def visible_rect(od,win):
                    w,h=win
                    ow,oh=od['w'],od['h']
                    if ow<=1 or oh<=1 or w<=1 or h<=1:return None
                    sx,sy=w/ow,h/oh
                    x0=max(0.0,od['ml']*sx);x1=min(w,(ow-od['mr'])*sx)
                    y0=max(0.0,od['mb']*sy);y1=min(h,(oh-od['mt'])*sy)
                    if x1-x0<=1 or y1-y0<=1:return None
                    return (x0,y0,x1,y1)
                def trace_digest():
                    import hashlib
                    allnew=new_trace(r3mark)
                    return 'trace-lines=%d sha256=%s'%(len(allnew),hashlib.sha256(("\n".join(allnew)).encode()).hexdigest()[:16])
                def trace_tail(n=30):
                    keep=[l for l in new_trace(r3mark) if '"k":"hudCropBounds"' in l or '"k":"osdAccept"' in l or '"k":"osdBranch"' in l]
                    return 'trace-tail=[%s]'%' | '.join(l[:200] for l in keep[-n:])
                # r3-hud-baseline
                b1=wait_trace('hudCropBounds',r3mark,10)
                if hud_json is not None:
                    ipc_roundtrip(gosock,hud_json)
                lay1=wait_trace('hudLayout',r3mark,12)
                bl=last_of('hudCropBounds',r3mark);ll=last_of('hudLayout',r3mark)
                okb=decoded and bool(b1) and hud_json is not None and bool(lay1)
                base_detail='decoded=%s bounds=%d layout=%d'%(decoded,len(b1),len(lay1))
                if okb:
                    cap=ll.get('cap');r=bl.get('r') if bl else None
                    inside0=(reg_ok(ll) and isinstance(r,list) and len(r)==4 and
                             ll['x']>=r[0]-1 and ll['x']+ll['w']<=r[0]+r[2]+1 and
                             ll['bottom']>=r[1]-1 and ll['top']<=r[1]+r[3]+1)
                    okb=bool(inside0) and isinstance(cap,int) and cap>=1
                    base_detail+=' cap=%s region-in-bounds=%s win=%s'%(cap,inside0,bl.get('win') if bl else None)
                note(okb,'r3-hud-baseline',base_detail+' '+trace_digest())
                # r3-hud-zoom
                od0=osd_dims()
                win0=tuple(bl.get('win')) if bl and isinstance(bl.get('win'),list) and len(bl.get('win'))==2 else None
                if od0 is None or win0 is None:
                    note_skip('r3-hud-zoom','osd-dimensions or window size unavailable '+trace_digest())
                else:
                    ipc_roundtrip(gosock,'{"command":["add","video-zoom",0.5]}')
                    ipc_roundtrip(gosock,'{"command":["set_property","video-pan-x",0.05]}')
                    # block 180: the app accepts osd-dimensions on the 1 Hz slow
                    # poll; give it three cycles to accept + refit before reading.
                    time.sleep(3.0)
                    od1=osd_dims()
                    moved=(od1 is not None and any(abs(od1[k]-od0[k])>0.5 for k in od0))
                    if not moved:
                        ipc_roundtrip(gosock,'{"command":["set_property","video-zoom",0]}')
                        ipc_roundtrip(gosock,'{"command":["set_property","video-pan-x",0]}')
                        time.sleep(1.0)
                        note_skip('r3-hud-zoom','excursion ineffective: rendered rect unchanged '+trace_digest())
                    else:
                        l1=last_of('hudLayout',r3mark)
                        blD=last_of('hudCropBounds',r3mark)
                        v1=visible_rect(od1,win0)
                        srcD=blD.get('src') if isinstance(blD,dict) else None
                        neg=any(od1[k]<-0.5 for k in ('ml','mr','mt','mb'))
                        # block 180: under negative margins the bounds must come
                        # from the accepted osd path, never the stale-target
                        # fallback (the fixed reject path held them there).
                        fixed_path=(srcD in ('osd-floor','osd-mapped')) if neg else True
                        # block 180: fresh-feed contract. The capture must show an
                        # acceptance whose dims MATCH the excursion read (not a
                        # stale accept), and the osd-sourced bounds line must come
                        # at or after it in trace order. A bigger wait must never
                        # substitute for this evidence.
                        def feed_contract(od):
                            tl=new_trace(r3mark)
                            acc=[(i,parse('osdAccept',l)) for i,l in enumerate(tl) if '"k":"osdAccept"' in l]
                            acc=[(i,a) for i,a in acc if a and a.get('why')=='accepted' and all(k in a for k in ('ml','mr','mt','mb'))]
                            if not acc:return (False,None,-1,-1)
                            ai,a=acc[-1]
                            bounds_rows=[(i,parse('hudCropBounds',l)) for i,l in enumerate(tl) if '"k":"hudCropBounds"' in l]
                            matched=[(i,b) for i,b in bounds_rows if b and b.get('src') in ('osd-floor','osd-mapped') and b.get('osdSeq')==a.get('seq')]
                            bi=matched[-1][0] if matched else -1
                            fresh=all(abs(a[k]-od[k])<=2.0 for k in ('ml','mr','mt','mb'))
                            return (fresh and bi>=ai,a,ai,bi)
                        fc1,acc1,ai1,bi1=feed_contract(od1)
                        ok1=v1 is not None and reg_ok(l1) and region_inside(l1,v1) and fc1
                        ipc_roundtrip(gosock,'{"command":["set_property","video-zoom",0]}')
                        ipc_roundtrip(gosock,'{"command":["set_property","video-pan-x",0]}')
                        time.sleep(3.0)
                        od2=osd_dims()
                        l2=last_of('hudLayout',r3mark)
                        v2=visible_rect(od2,win0) if od2 else None
                        fc2,acc2,ai2,bi2=feed_contract(od2) if od2 else (False,None,-1,-1)
                        ok2=v2 is not None and reg_ok(l2) and region_inside(l2,v2) and fc2
                        bl3=last_of('hudCropBounds',r3mark)
                        zb=bool(blD and bl and blD.get('r')!=bl.get('r'))  # excursion, not reset-vs-baseline
                        note(ok1 and ok2 and fixed_path,'r3-hud-zoom',
                             'during=%s after-reset=%s fixed-path-under-neg-margins=%s src-during=%s zoom-bounds-changed=%s feed1=%s feed2=%s dims0=%.0fx%.0f dims1=%.0fx%.0f margins0=%s margins1=%s %s %s'%(
                                 ok1,ok2,fixed_path,srcD,zb,fc1,fc2,
                                 od0['w'],od0['h'],od1['w'],od1['h'],
                                 ','.join('%.0f'%od0[k] for k in ('ml','mr','mt','mb')),
                                 ','.join('%.0f'%od1[k] for k in ('ml','mr','mt','mb')),
                                 trace_digest(),trace_tail()))
                # r3-hud-scroll
                def set_scroll(v):
                    gcmd('set_property','user-data/gor-test-hud-scroll',v)
                def drive(v,seconds=5):
                    before=len([l for l in new_trace(r3mark) if '"k":"hudScroll"' in l])
                    mark=len(new_trace(r3mark))
                    set_scroll(v)
                    delivered=wait_fresh_trace('hudScrollDrive',mark,8,lambda h:h.get('v')==v)
                    if not delivered:return None
                    end=time.monotonic()+seconds
                    while time.monotonic()<end:
                        hs=[parse('hudScroll',l) for l in new_trace(r3mark) if '"k":"hudScroll"' in l]
                        hs=[h for h in hs if h]
                        if len(hs)>before:return hs[-1]
                        time.sleep(.2)
                    return None
                def drive_expect_no_line(v,seconds=3):
                    before=len([l for l in new_trace(r3mark) if '"k":"hudScroll"' in l])
                    set_scroll(v)
                    end=time.monotonic()+seconds
                    while time.monotonic()<end:
                        hs=[l for l in new_trace(r3mark) if '"k":"hudScroll"' in l]
                        if len(hs)>before:return False
                        time.sleep(.2)
                    return True
                l0=last_of('hudLayout',r3mark)
                if not isinstance(l0,dict) or 'max' not in l0 or 'first' not in l0:
                    note_skip('r3-hud-scroll','no layout trace '+trace_digest())
                else:
                    maxr=l0['max']
                    if maxr>=1:
                        drive(-99);time.sleep(0.8)   # settle at row 0 if the harness is live
                        l0b=last_of('hudLayout',r3mark)
                        f0=l0b['first'] if isinstance(l0b,dict) and 'first' in l0b else 0
                        m0=l0b.get('max',maxr) if isinstance(l0b,dict) else maxr
                        det=['f0=%s m0=%s'%(f0,m0)]
                        # block 181: regression-sensitive chain. The position must
                        # NEVER move without a hudScroll line explaining it: each
                        # line's own from must equal the position left by the
                        # previous step, and a no-line outcome is valid only when
                        # the pre-drive position is unchanged AND the drive is a
                        # clamp no-op against it. Movement that should occur but
                        # produces no line is a FAIL, never an adaptation.
                        g0=drive(2)
                        if g0 is None:
                            post=last_of('hudLayout',r3mark)
                            pf=post.get('first') if isinstance(post,dict) else None
                            pm=post.get('max') if isinstance(post,dict) else None
                            if pf==0 and isinstance(pm,int) and pm>=1:
                                note(False,'r3-hud-scroll','drive route dead: +2 produced no hudScroll line from settled f0=0 m=%s %s drive-trace=%s'%(pm,trace_digest(),[l[:280] for l in new_trace(r3mark) if 'hudScrollDrive' in l or 'hudScrollReject' in l or 'testPoll' in l][-12:]))
                            elif pm==0:
                                note_skip('r3-hud-scroll','content collapsed mid-leg (max=0) '+trace_digest())
                            else:
                                note(False,'r3-hud-scroll','silent state change: +2 no line, settled f0=%s but post f=%s m=%s %s'%(f0,pf,pm,trace_digest()))
                            g0='DEAD'
                        if g0!='DEAD' and g0 is not None:
                            ok0=(g0.get('from')==f0
                                 and g0.get('to')==min(max(f0+2,0),g0.get('max',0))
                                 and g0.get('to',-1)>g0.get('from',0)
                                 and g0.get('v')==2)
                            det.append('down2 v=%s from=%s to=%s max=%s ok=%s'%(g0.get('v'),g0.get('from'),g0.get('to'),g0.get('max'),ok0))
                            oks=ok0
                            prevpos=g0.get('to')
                            for v in (-2,99,-98):
                                pre=last_of('hudLayout',r3mark)
                                fp=pre['first'] if isinstance(pre,dict) and 'first' in pre else None
                                mp=pre['max'] if isinstance(pre,dict) and 'max' in pre else None
                                g=drive(v)
                                if g is not None:
                                    okv=(g.get('from')==prevpos
                                         and g.get('to')==min(max(g.get('from',0)+v,0),g.get('max',0))
                                         and g.get('v')==v)
                                    det.append('%s:line v=%s from=%s to=%s max=%s ok=%s'%(v,g.get('v'),g.get('from'),g.get('to'),g.get('max'),okv))
                                    prevpos=g.get('to')
                                else:
                                    chainok=(fp==prevpos)
                                    noopok=(fp is not None and mp is not None and min(max(fp+v,0),mp)==fp)
                                    okv=chainok and noopok
                                    det.append('%s:noline chain=%s noop=%s f=%s m=%s prev=%s'%(v,chainok,noopok,fp,mp,prevpos))
                                    prevpos=fp
                                oks=oks and okv
                            pre=last_of('hudLayout',r3mark)
                            fp=pre['first'] if isinstance(pre,dict) and 'first' in pre else None
                            chainend=(fp==prevpos)
                            if fp==0 and chainend:
                                rej=drive_expect_no_line(-77)
                                det.append('end-rejection=%s'%rej)
                                oks=oks and rej
                            else:
                                det.append('end-rejection=na first=%s prev=%s chain=%s'%(fp,prevpos,chainend))
                                oks=oks and chainend
                            lend=last_of('hudLayout',r3mark)
                            det.append('first-end=%s'%(lend.get('first') if isinstance(lend,dict) else None))
                            note(oks,'r3-hud-scroll',' '.join(det)+' '+trace_digest())
                    else:
                        rej=drive_expect_no_line(2)
                        lend=last_of('hudLayout',r3mark)
                        first_stays=(isinstance(lend,dict) and lend.get('first',0)==0)
                        note(rej and first_stays,'r3-hud-scroll',
                             'no-overflow: max=0 drive-rejected=%s first=%s %s'%(
                                 rej,lend.get('first') if isinstance(lend,dict) else None,
                                 trace_digest()))
                # v2-replicator + ipd-vs-dial (block 180 3d / v2 / 181 2, review r3)
                import re as _re
                def gset(name,val):gcmd('set_property',name,val)
                _m=_re.search(r'VR_PHYSICAL_GAP_FRAC\s*=\s*([0-9.]+)',
                              (root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
                _pl=_re.search(r'VR_PURE_LOOK_ENABLED\s*=\s*(\w+)',
                               (root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text())
                snap=last_of('vrSubDepth',r3mark)
                snap_ipd_l=last_of('vrIPD',r3mark)
                snap_vr_l=last_of('vrMode',r3mark)
                if not _m or (_pl and _pl.group(1)=='true'):
                    note_skip('v2-replicator','shipped lua gap constant unreadable or pure-look on '+trace_digest())
                    note_skip('ipd-vs-dial','lua gap unreadable (session state unverified) '+trace_digest())
                elif not snap or not snap_ipd_l or not snap_vr_l:
                    note_skip('v2-replicator','no vrSubDepth/vrIPD/vrMode rest snapshot from the app '+trace_digest())
                    note_skip('ipd-vs-dial','no vrSubDepth/vrIPD/vrMode rest snapshot '+trace_digest())
                else:
                    lua_gap=float(_m.group(1))
                    snap_dial=float(snap.get('dial',8.0));snap_had=int(snap.get('had',0))
                    snap_ipd=float(snap_ipd_l.get('v',0.0))
                    snap_vr=int(snap_vr_l.get('on',0))
                    try:
                        prior_gap=float(gcmd('get_property','user-data/vr180-look/physical-gap-frac').get('data'))
                    except (TypeError,ValueError):
                        prior_gap=None
                    gap_changed=False
                    exp_gap=prior_gap if prior_gap is not None else lua_gap
                    exp_gsrc='live' if prior_gap is not None else 'lua'
                    vc_epoch=[len(new_trace(r3mark))]
                    def wait_vc(pred,seconds):
                        end=time.monotonic()+seconds
                        while time.monotonic()<end:
                            hits=[parse('vrChrome',l) for l in new_trace(r3mark)[vc_epoch[0]:] if '"k":"vrChrome"' in l]
                            hits=[h for h in hits if h and pred(h)]
                            if hits:return hits[-1]
                            time.sleep(.25)
                        return None
                    def band_check(v,gap):
                        # bands computed HERE from mpv's own disp rect + the gap the
                        # TEST sourced (lua parse or the live value it published)
                        # The same committed vrChrome row owns both eye bands and source display rect.
                        disp=v.get('disp')
                        if not (isinstance(disp,list) and len(disp)==4 and disp[2]>1):return None,'no disp'
                        dx,dy,dw,dh=[float(z) for z in disp]
                        hg=gap*0.25
                        eL=[dx,dy,(0.5-hg)*dw,dh];eR=[dx+(0.5+hg)*dw,dy,(0.5-hg)*dw,dh]
                        # the traced bands must equal the independently computed ones
                        for tag,exp in (('eyeL',eL),('eyeR',eR)):
                            got=v.get(tag)
                            if not (isinstance(got,list) and len(got)==4):return None,'no '+tag
                            if any(abs(got[i]-exp[i])>2 for i in range(4)):return None,'%s %s != expected %s'%(tag,got,exp)
                        def inside(r,b,tol=2.0):
                            return (isinstance(r,list) and len(r)==4 and r[2]>0 and r[3]>0 and
                                    r[0]>=b[0]-tol and r[0]+r[2]<=b[0]+b[2]+tol and
                                    r[1]>=b[1]-tol and r[1]+r[3]<=b[1]+b[3]+tol)
                        def sh(r,tx):
                            return [r[0]+tx,r[1],r[2],r[3]] if isinstance(r,list) else None
                        det=[]
                        ok=True
                        hudTx=float(v.get('hudTx',0) or 0)
                        disparity=abs(float(v.get('subTx',0) or 0)-hudTx)
                        for s,txtag in (('hud','hudTx'),('spine','spineTx'),('sub','subTx')):
                            clip=v.get(s+'Clip');n=int(v.get(s+'N',0) or 0)
                            tx=float(v.get(txtag,0) or 0)
                            # No disparity allowance across the gap or outer edge:
                            # the actual subtitle safety mask must fit BOTH eyes.
                            cok=inside(clip,eL) and inside(sh(clip,tx),eR)
                            rok=True
                            if n>0:
                                c=v.get(s)
                                rok=inside(c,eL) and inside(sh(c,tx),eR)
                            det.append('%s:clip=%s,n=%d,rect=%s'%(s,bool(cok),n,bool(rok)))
                            ok=ok and cok and rok
                        return ok,'disparity=%.1f '%disparity+' '.join(det)
                    restore_note=None
                    try:
                        vc_epoch[0]=len(new_trace(r3mark))
                        gset('user-data/gor-test-vr-mode',1)
                        v=wait_vc(lambda h:h.get('on')==1 and h.get('rep')==1,8)
                        if not v:
                            note(False,'v2-replicator','no replicating vrChrome trace after VR drive '+trace_digest())
                        else:
                            # The ACTUAL prior publication is authoritative (it may
                            # be a legitimately tuned live value); the lua constant
                            # is the explicit fallback only when nothing was ever
                            # published. Source and value must both match that.
                            ok_gap=(v.get('gsrc')==exp_gsrc and abs(float(v.get('gap',-1))-exp_gap)<1e-9
                                    and int(v.get('clip',0))==1)
                            ok_b,bdet=band_check(v,exp_gap)
                            sd0=last_of('vrSubDepth',r3mark)
                            off=float(sd0.get('offset',0)) if sd0 else 0.0
                            sub_off=float(v.get('subTx',0) or 0)-float(v.get('hudTx',0) or 0)
                            ok_off=abs(sub_off-off)<0.75
                            note(bool(ok_gap and ok_b and ok_off),'v2-replicator',
                                 'gsrc=%s gap=%s clip=%s subTx-hudTx=%.1f offset=%.1f | %s %s'%(
                                     v.get('gsrc'),v.get('gap'),v.get('clip'),sub_off,off,bdet,trace_digest()))
                            # live publication CONSUMER path only: the prop says
                            # 0.02 while the shader still renders its own value, so
                            # this proves publication -> app regeometry, NOT
                            # shader/app render sync (that needs the real tune).
                            # Mutate ONLY when a real prior publication exists to
                            # restore - never fabricate state the shader never had.
                            if prior_gap is None:
                                note_skip('v2-replicator','live-gap consumer leg skipped: no prior publication exists to restore (publisher absent) '+trace_digest())
                            else:
                                vc_epoch[0]=len(new_trace(r3mark))
                                gset('user-data/vr180-look/physical-gap-frac','0.020000')
                                gap_changed=True
                                v2=wait_vc(lambda h:h.get('gsrc')=='live' and abs(float(h.get('gap',0))-0.02)<1e-9,6)
                                ok_live=False;ldet='no live vrChrome after publication'
                                if v2:
                                    ok_b2,ldet=band_check(v2,0.02)
                                    ok_live=bool(ok_b2)
                                note(ok_live,'v2-replicator','live gap publication 0.02 -> chrome regeometry (consumer-only, no render-sync claim): '+ldet+' '+trace_digest())
                        # subtitle depth magnitude drive (test-only setter route)
                        submark=len(new_trace(r3mark))
                        gset('user-data/gor-test-vr-sub-dial',14)
                        sdl=wait_fresh_trace('vrSubDepth',submark,8,lambda h:abs(h.get('dial',0)-14)<.01)
                        sdl=[s for s in sdl if s and abs(s.get('dial',0)-14.0)<0.01]
                        ipd_during_dial=[l for l in new_trace(r3mark)[submark:] if '"k":"vrIPD"' in l]
                        okd=False;det='no vrSubDepth dial=14 line'
                        if sdl:
                            s=sdl[-1]
                            expect=-14.0 if s.get('swap')==1 else 14.0
                            vc14=wait_vc(lambda h:abs(float(h.get('subTx',0) or 0)-float(h.get('hudTx',0) or 0)-expect)<0.75,4)
                            okd=(abs(s.get('offset',0)-expect)<0.01 and not ipd_during_dial and vc14 is not None)
                            det='dial=%s offset=%s swap=%s stray-vrIPD=%d chrome-subTx-match=%s'%(s.get('dial'),s.get('offset'),s.get('swap'),len(ipd_during_dial),vc14 is not None)
                        note(okd,'v2-replicator','subtitle dial: '+det+' '+trace_digest())
                        # ipd-vs-dial via the REAL key path: a fabricated NSEvent with
                        # the real key window's number through the app's own monitor.
                        km1=len(new_trace(r3mark))
                        gset('user-data/gor-test-vr-key','shift-alt-[')
                        dl=wait_fresh_trace('vrSubDepth',km1,8,lambda h:abs(h.get('dial',0)-12)<.01)
                        dl=[d for d in dl if d and abs(d.get('dial',0)-12.0)<0.01]
                        stray_ipd=[l for l in new_trace(r3mark)[km1:] if '"k":"vrIPD"' in l]
                        ok1=bool(dl) and not stray_ipd
                        km2=len(new_trace(r3mark))
                        key_delta=-0.02 if snap_ipd>0.27 else 0.02
                        key_spec='shift-[' if key_delta<0 else 'shift-]'
                        gset('user-data/gor-test-vr-key',key_spec)
                        ip=wait_fresh_trace('vrIPD',km2,8,lambda h:abs(h.get('v',0)-(snap_ipd+key_delta))<.001)
                        ip=[i for i in ip if i and abs(i.get('v',0)-(snap_ipd+key_delta))<0.001]
                        stray_dial=[l for l in new_trace(r3mark)[km2:] if '"k":"vrSubDepth"' in l]
                        ok2=bool(ip) and not stray_dial
                        note(ok1 and ok2,'ipd-vs-dial',
                             'realkey shift-alt-[ -> dial12=%s stray-vrIPD=%d; %s -> vrIPD=%s stray-vrSubDepth=%d %s'%(
                                 bool(dl),len(stray_ipd),key_spec,bool(ip),len(stray_dial),trace_digest()))
                    except Exception as e:
                        note(False,'v2-replicator','exception mid-leg: %r %s'%(e,trace_digest()))
                    finally:
                        # Independent cleanup steps, each in its own try so one
                        # failure cannot block the others; undo ONLY the effects
                        # this run actually caused and restore prior values exactly.
                        rst=[]
                        try:
                            restore_mark=len(new_trace(r3mark))
                            gset('user-data/gor-test-vr-ipd-restore',snap_ipd)
                            deadline=time.monotonic()+8
                            restored=False
                            while time.monotonic()<deadline:
                                time.sleep(0.2)
                                fresh=[parse('vrIPD',l) for l in new_trace(r3mark)[restore_mark:] if '"k":"vrIPD"' in l]
                                ripd=fresh[-1] if fresh else None
                                if ripd and abs(float(ripd.get('v',-99))-snap_ipd)<1e-9:
                                    restored=True;break
                            rst.append(('ipd',restored))
                        except Exception as e:rst.append(('ipd-exc',repr(e)))
                        try:
                            if snap_had==1:
                                scratch=10.0 if abs(snap_dial-10.0)>0.01 else 12.0
                                gset('user-data/gor-test-vr-sub-dial',scratch)
                                time.sleep(1.2)
                                gset('user-data/gor-test-vr-sub-dial',snap_dial)
                            else:
                                gset('user-data/gor-test-vr-sub-dial',-1)
                            time.sleep(1.2)
                            rest=last_of('vrSubDepth',r3mark)
                            rst.append(('dial',isinstance(rest,dict) and abs(float(rest.get('dial',-99))-snap_dial)<0.01
                                        and int(rest.get('had',-1))==snap_had))
                        except Exception as e:rst.append(('dial-exc',repr(e)))
                        try:
                            if gap_changed:
                                gset('user-data/vr180-look/physical-gap-frac',prior_gap)
                                time.sleep(0.8)
                                rg=gcmd('get_property','user-data/vr180-look/physical-gap-frac').get('data')
                                rst.append(('gap',abs(float(rg)-prior_gap)<1e-9))
                            else:
                                rst.append(('gap',True))
                        except Exception as e:rst.append(('gap-exc',repr(e)))
                        try:
                            gset('user-data/gor-test-vr-mode',snap_vr)
                            if snap_vr==0:
                                voff=wait_vc(lambda h:h.get('on')==0 and h.get('rep')==0 and h.get('hudClip') is None,6)
                            else:
                                voff=wait_vc(lambda h:h.get('on')==1,6)
                            rst.append(('vr',voff is not None))
                        except Exception as e:rst.append(('vr-exc',repr(e)))
                        note(all(v is True for _,v in rst),'v2-replicator','restore (independent steps, prior values exact): '+' '.join('%s=%s'%(k,v) for k,v in rst)+' '+trace_digest())
        finally:
            subprocess.run(['/usr/bin/osascript','-e',quit_script],stdout=log,stderr=log)
            wait(lambda:not alive(gp),5)
            stop_owned(gp,gs)
        # v1 (block 180 3a): VR shader PIXELS. Real mpv + the shipped vr180-look.lua on a
        # synthetic 2:1 SBS clip (left half red, right half blue), VR enabled, mpv
        # screenshot-to-file in window mode. The output-left/right pixel colour must come
        # from the left/right source half for cross-eye order 0 and from the opposite half
        # for order 1 (vr180-look-set-swap-eyes). Runs mpv only, never the gor app.
        def png_pixels(path):
            import zlib,struct
            d=Path(path).read_bytes()
            if d[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('not png')
            i=8;idat=b'';w=h=bd=ct=il=None
            while i<len(d):
                n,=struct.unpack('>I',d[i:i+4]);t=d[i+4:i+8];body=d[i+8:i+8+n];i+=12+n
                if t==b'IHDR':w,h,bd,ct,_,_,il=struct.unpack('>IIBBBBB',body)
                elif t==b'IDAT':idat+=body
            if bd not in (8,16) or ct not in (2,6) or il!=0:raise ValueError('unsupported png %s %s %s'%(bd,ct,il))
            sb=bd//8;ch=3 if ct==2 else 4;bpp=ch*sb;stride=w*bpp;raw=zlib.decompress(idat)
            rows=[];prev=bytearray(stride);p=0
            for _ in range(h):
                f=raw[p];line=bytearray(raw[p+1:p+1+stride]);p+=1+stride
                for x in range(stride):
                    a=line[x-bpp] if x>=bpp else 0;b=prev[x];c=prev[x-bpp] if x>=bpp else 0
                    if f==1:line[x]=(line[x]+a)&255
                    elif f==2:line[x]=(line[x]+b)&255
                    elif f==3:line[x]=(line[x]+((a+b)>>1))&255
                    elif f==4:
                        pa=abs(b-c);pb=abs(a-c);pc=abs(a+b-2*c)
                        pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                        line[x]=(line[x]+pr)&255
                rows.append(line);prev=line
            return w,h,lambda x,y:tuple(rows[y][x*bpp+k*sb] for k in range(3))
        def v1_run(extra_args,env=None):
            v1tmp=tempfile.TemporaryDirectory(prefix='gor-v1.')
            mp=None
            try:
                d=Path(v1tmp.name);sbs=d/'sbs.mp4'
                ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
                if ff is None:return None,'no vendor ffmpeg to build the SBS clip'
                r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=red:s=1024x1024:r=10:d=3',
                    '-f','lavfi','-i','color=c=blue:s=1024x1024:r=10:d=3','-filter_complex','[0][1]hstack,format=yuv420p',str(sbs)],
                    stdout=log,stderr=log,timeout=30)
                if r.returncode or not sbs.is_file():return None,'SBS clip generation failed'
                sock=str(d/'v1.sock');cfg=d/'cfg';cfg.mkdir()
                script=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
                mp=subprocess.Popen([str(mpv)]+hidden_flags(str(mpv))+['--no-config','--config-dir='+str(cfg),'--script='+str(script),'--vo=gpu-next','--ao=null','--no-audio',
                    '--pause','--loop-file=inf','--keep-open=yes','--force-window=yes','--no-border','--geometry=800x500','--no-osc',
                    '--input-ipc-server='+sock,str(sbs)]+extra_args,stdout=log,stderr=log,env=env)
                if not wait(lambda:os.path.exists(sock),10):return None,'mpv socket never appeared'
                def c(*a):return ipc_roundtrip(sock,json.dumps({'command':list(a)}))
                if not wait(lambda:isinstance(c('get_property','dwidth').get('data'),(int,float)),10):return None,'video never decoded'
                c('script-message-to','vr180_look','vr180-look-set-enabled','true');time.sleep(1.0)
                out={}
                for swap in ('0','1'):
                    c('script-message-to','vr180_look','vr180-look-set-swap-eyes',swap);time.sleep(1.2)
                    shot=d/('swap%s.png'%swap)
                    c('screenshot-to-file',str(shot),'window');wait(lambda:shot.exists() and shot.stat().st_size>0,5);time.sleep(.3)
                    w,h,px=png_pixels(shot);out[swap]=(px(w//4,h//2),px(3*w//4,h//2),w,h)
                return out,None
            finally:
                if mp is not None:
                    try:mp.terminate();mp.wait(timeout=5)
                    except Exception:mp.kill()
                v1tmp.cleanup()
        def is_red(p):return p[0]>=150 and p[2]<=100
        def is_blue(p):return p[2]>=150 and p[0]<=100
        try:
            v1res,v1err=v1_run([])
            if v1res is None:
                note_skip('v1-shader-pixels',v1err)
            else:
                (l0,r0,w,h),(l1,r1,_,_)=v1res['0'],v1res['1']
                ok=is_red(l0) and is_blue(r0) and is_blue(l1) and is_red(r1)
                note(ok,'v1-shader-pixels','window=%dx%d swap0 left=%s right=%s; swap1 left=%s right=%s (expect swap0 L=red R=blue, swap1 L=blue R=red)'%(w,h,l0,r0,l1,r1))
        except Exception as e:
            note_skip('v1-shader-pixels','not measurable: '+type(e).__name__+' '+str(e)[:120])
        try:
            import hashlib
            images=[parse('vrControlImage',l) for l in new_trace(r3mark) if '"k":"vrControlImage"' in l]
            images=[x for x in images if x and x.get('path')]
            generated_fixture = cliptmp is not None and Path(clip).resolve() == (Path(cliptmp.name)/'clip.mp4').resolve()
            if images and generated_fixture:
                image=Path(images[-1]['path'])
                expected=Path(tempfile.gettempdir())/('gor-vr-controls-%d.png'%gp)
                if image.resolve()!=expected.resolve() or image.is_symlink():raise ValueError('not this fixture process image')
                if image.stat().st_size > 8*1024*1024:raise ValueError('fixture image too large')
                data=image.read_bytes()
                if not data.startswith(b'\x89PNG\r\n\x1a\n'):raise ValueError('not PNG')
                artifacts=root/'.gor-selftest-artifacts';artifacts.mkdir(exist_ok=True)
                digest=hashlib.sha256(data).hexdigest()
                target=artifacts/('vr-controls-'+digest+'.png')
                if not target.exists():target.write_bytes(data)
                custody='ARTIFACT vr-controls.png sha256='+digest+' file='+str(target.relative_to(root))+' bytes='+str(len(data))
                with results.open('a') as f:f.write(custody+'\n')
                print('INFO '+custody,flush=True)
            else:note_skip('vr-controls-pixel-custody','no generated-fixture composite image; existing media never exported')
        except Exception as e:
            note_skip('vr-controls-pixel-custody','not measurable: '+type(e).__name__+' '+str(e)[:100])
        note_skip('vr-controls-visible-both-eyes','actual PNG custody is evidence for inspection, not an automated visual pass')
        # vr-distance-clamp (block 182 2): the distance-aware separation rule, on real mpv with the shipped
        # vr180-look.lua and synthetic distances (no camera, no gor). Reads user-data/vr180-look/distance-trace
        # (published by the script) and the pushed glsl-shader-opts. Asserts, independently of the script's own
        # arithmetic: (a) vergence demand 2*atan((63+s)/(2d)) <= the demand at d=500 with today's separation, i.e. the
        # cap, for d in 200..800; (b) no cap at d>=500 and without input; (c) the shader total (excess+base+nudge from
        # the pushed opts) equals the reported s_total in ndc; (d) hold 2 s then constant-mm; (e) dial offset enters
        # ipd_eff; (f) fallbacks are logged with a reason; (g) an unreachable shift is reported infeasible, never as a
        # met cap. LINUX mpv only; the d computation, filter and CGDisplayScreenSize are Swift and not exercised here.
        def dist_leg():
            dtmp=tempfile.TemporaryDirectory(prefix='gor-dist.')
            mp=None
            try:
                d=Path(dtmp.name);clip=d/'sbs.mp4'
                ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
                if ff is None:return note_skip('vr-distance-clamp','no vendor ffmpeg')
                r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=gray:s=1024x512:r=10:d=3,format=yuv420p',str(clip)],stdout=log,stderr=log,timeout=60)
                if r.returncode or not clip.is_file():return note_skip('vr-distance-clamp','clip generation failed')
                sock=str(d/'m.sock');cfg=d/'cfg';cfg.mkdir()
                script=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
                mp=subprocess.Popen([str(mpv)]+hidden_flags(str(mpv))+['--no-config','--config-dir='+str(cfg),'--script='+str(script),'--vo=gpu-next','--ao=null','--no-audio',
                    '--pause','--loop-file=inf','--keep-open=yes','--force-window=yes','--no-border','--geometry=1400x900','--no-osc','--input-ipc-server='+sock,str(clip)],stdout=log,stderr=log)
                if not wait(lambda:os.path.exists(sock),10):return note_skip('vr-distance-clamp','mpv socket never appeared')
                def c(*a):return ipc_roundtrip(sock,json.dumps({'command':list(a)}))
                if not wait(lambda:isinstance(c('get_property','dwidth').get('data'),(int,float)),10):return note_skip('vr-distance-clamp','video never decoded')
                c('script-message-to','vr180_look','vr180-look-set-enabled','true');time.sleep(1.0)
                def orient(dist,reason='',mmpx='',nudge='0',fov='135'):
                    c('script-message-to','vr180_look','vr180-look-set-orientation','0','0',fov,'0',nudge,'0','0','0',str(dist),reason,str(mmpx));time.sleep(.35)
                def trace():
                    t=c('get_property','user-data/vr180-look/distance-trace').get('data')
                    try:return json.loads(t)
                    except Exception:return None
                def opts():
                    o=c('get_property','glsl-shader-opts').get('data')
                    return o if isinstance(o,str) else ''
                def optval(k):
                    o=c('get_property','glsl-shader-opts').get('data')
                    if isinstance(o,dict):
                        for kk,vv in o.items():
                            if kk.endswith('/'+k):return float(vv)
                        return None
                    m=re.search(r'%s=([-0-9.eE+]+)'%k,str(o));return float(m.group(1)) if m else None
                res=[];ok=True;infeas=[]
                def chk(name,cond,det):
                    nonlocal ok
                    ok=ok and bool(cond);res.append('%s=%s(%s)'%(name,'ok' if cond else 'BAD',det))
                demand=lambda ipd,s,dd:2*math.atan((ipd+s)/(2.0*dd))
                orient('none','fov-unavailable','0.1118')
                t0=trace()
                if t0 is None:return note_skip('vr-distance-clamp','no distance trace published (osd size unavailable?)')
                chk('none',t0['reason']=='fov-unavailable' and not t0['capped'] and abs(t0['s_total_mm']-t0['s_today_mm'])<1e-3,'reason=%s capped=%s'%(t0['reason'],t0['capped']))
                c('script-message-to','vr180_look','vr180-look-set-ipd-mm','3.0');time.sleep(.3)
                ip=[]
                for mp_ in ('0.1118','0.2','0.05'):
                    orient('none','fov-unavailable',mp_);tt=trace();ip.append(tt['offset_mm'] if tt else None)
                chk('ipd-offset-mm-stable-across-display-scale',all(v is not None and abs(v-3.0)<1e-3 for v in ip),'offset_mm at mm/px .1118/.2/.05 = %s'%ip)
                c('script-message-to','vr180_look','vr180-look-set-ipd-mm','0.0');time.sleep(.3);orient('none','fov-unavailable','0.1118')
                for dist in (800,500,400,300,200):
                    orient(dist,'ok','0.1118');t=trace()
                    if t is None:return note_skip('vr-distance-clamp','trace missing at d=%d'%dist)
                    ref=demand(63.0+t['offset_mm'],t['s_today_mm'],500.0)
                    got=demand(63.0+t['offset_mm'],t['s_total_mm'],float(dist))
                    if t['infeasible']:
                        # the cap needs a shift beyond the shader's own +-0.8 clamp at this window size: reported, never counted as a met cap
                        infeas.append(dist);capok=(t['capped'] is True and t['cap_met'] is False)
                    else:
                        capok=got<=ref+1e-6 and (dist>=500 or t['capped']) and (dist<500 or not t['capped'])
                    chk('d%d'%dist+('-INFEASIBLE' if t['infeasible'] else ''),capok,'s_today=%.2f s_total=%.2f demand<=cap %.6f<=%.6f capped=%s infeasible=%s'%(t['s_today_mm'],t['s_total_mm'],got,ref,t['capped'],t['infeasible']))
                # shader total equals reported s_total (ndc), from the pushed opts: excess+base+nudge
                orient(300,'ok','0.1118');t=trace()
                base=optval('vr_base_ipd');nudge=optval('vr_ipd_nudge')
                half=t['eye_w_mm']/2.0
                mag=math.tan(math.radians(90.0)*0.5)/math.tan(math.radians(135.0)*0.5)
                excess=-0.4*(mag-1.0)*0.4
                total=excess+base+nudge if base is not None and nudge is not None else None
                chk('shader-total',total is not None and abs(total-t['s_total_mm']/half)<1e-4,'pushed excess+base+nudge=%s want %.6f'%(None if total is None else '%.6f'%total,t['s_total_mm']/half))
                # Block182: dial offsets anatomical IPD, not uncapped screen separation.
                orient('none','fov-unavailable','0.1118');before=trace()
                c('script-message-to','vr180_look','vr180-look-set-ipd-mm','3');time.sleep(.3)
                orient('none','fov-unavailable','0.1118');after=trace()
                chk('dial-fallback-screen-constant',abs(after['s_total_mm']-before['s_total_mm'])<1e-3 and abs(after['ipd_eff_mm']-66)<1e-3,'ipd=%.3f s=%.3f'%(after['ipd_eff_mm'],after['s_total_mm']))
                orient(300,'ok','0.1118');withdial=trace()
                c('script-message-to','vr180_look','vr180-look-set-ipd-mm','0');time.sleep(.3);orient(300,'ok','0.1118');nodial=trace()
                chk('dial-changes-cap',abs((withdial['s_cap_mm']-nodial['s_cap_mm'])-(-1.2))<1e-3,'cap delta=%.4f'%(withdial['s_cap_mm']-nodial['s_cap_mm']))
                # dial offset enters ipd_eff
                c('script-message-to','vr180_look','vr180-look-set-ipd','0.1');time.sleep(.3);orient(300,'ok','0.1118');t=trace()
                chk('dial-offset',abs(t['ipd_eff_mm']-(63.0+0.1*half))<1e-3 and t['offset_mm']>0,'ipd_eff=%.3f offset=%.3f'%(t['ipd_eff_mm'],t['offset_mm']))
                c('script-message-to','vr180_look','vr180-look-set-ipd','0');time.sleep(.3)
                # fallback mm/px source
                orient(300,'ok','0');t=trace()
                chk('mmpx-fallback',t['mm_per_px_src']=='macbook-227ppi' and abs(t['mm_per_px']-25.4/227.0)<1e-6,'src=%s'%t['mm_per_px_src'])
                # infeasible is reported, not a met cap
                orient(40,'ok','0.1118');t=trace()
                chk('infeasible',t['infeasible'] is True,'d=40 s_total=%.1f infeasible=%s'%(t['s_total_mm'],t['infeasible']))
                # hold then constant-mm
                orient(300,'ok','0.1118');time.sleep(2.7);t=trace()
                chk('hold-expired',t is not None and t['reason']=='no-face-hold-expired' and not t['capped'],'reason=%s capped=%s'%(t and t['reason'],t and t['capped']))
                note(ok,'vr-distance-clamp','; '.join(res)+(' | cap NOT achievable (shader shift limit) at d=%s: reported as infeasible, not as met'%infeas if infeas else '')+' (LINUX mpv, synthetic distances; Swift d/filter/CGDisplayScreenSize untested)')
            except Exception as e:
                note_skip('vr-distance-clamp','not measurable: '+type(e).__name__+' '+str(e)[:120])
            finally:
                if mp is not None:
                    try:mp.terminate();mp.wait(timeout=5)
                    except Exception:mp.kill()
                dtmp.cleanup()
        dist_leg()
        # These metrics are not supplied by the synthetic-distance mpv leg. Never turn a missing camera/display
        # or app-restart observation into a pass merely because the Lua cap controls passed.
        note_skip('vr-distance-native-camera', 'live camera hfov/face-width distance and one-euro output not measured by synthetic-distance leg')
        note_skip('vr-distance-native-display', 'CGDisplayScreenSize/Retina viewport physical-mm agreement not measured by synthetic-distance leg')
        note_skip('vr-ipd-native-persistence-reentry', 'app restart and VR re-entry persisted-mm roundtrip not measured; key routing/restoration test is separate')
        # v1c (block 181 3): the VR output fills the whole drawable at any aspect. Real mpv + the
        # shipped vr180-look.lua on a synthetic VR180 SBS clip (grey sky, one 15-degree-radius
        # yellow disc straight ahead per eye, built by ffmpeg geq), VR on, keepaspect=no (what
        # gor sets on VR entry), screenshot-to-file in window mode at 16:10, 16:9 and 4:3.
        # Asserts per size: no fully-black outer COLUMNS (pillarbox), and the
        # disc's bounding box stays round within 2% (a hard-coded 16:10 eye aspect would squash it).
        # 16:10 reference: the pre-change shader (selftest-fixtures/vr180-look-pre-fill.lua) with the old
        # video-aspect-override=16:10 must give a pixel-identical frame to the new shader at 16:10.
        # keepaspect: the script sets it to no on VR enable and restores the user's prior value on
        # disable (checked for prior yes and prior no). Runs mpv only, never gor.
        def v1c_run(sizes):
            v1ctmp=tempfile.TemporaryDirectory(prefix='gor-v1c.')
            try:
                d=Path(v1ctmp.name);clip=d/'disc.mp4'
                ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
                if ff is None:return None,'no vendor ffmpeg to build the disc clip'
                ex="gt(cos((0.5-Y/H)*PI)*cos((X/W-0.5)*PI),0.9659258)"
                geq="format=gbrp,geq=r='if(%s,255,90)':g='if(%s,255,90)':b='if(%s,0,90)'"%(ex,ex,ex)
                r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=gray:s=1024x1024:r=10:d=3,'+geq,
                    '-filter_complex','[0]split[a][b];[a][b]hstack,format=yuv420p',str(clip)],stdout=log,stderr=log,timeout=60)
                if r.returncode or not clip.is_file():return None,'disc clip generation failed'
                script=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
                fixture=root/'selftest-fixtures/vr180-look-pre-fill.lua'
                if not fixture.is_file():return None,'pre-fill reference script missing'
                (d/'ref').mkdir();shutil.copy(str(fixture),str(d/'ref'/'vr180-look.lua'));fixture=d/'ref'/'vr180-look.lua'  # script client name must stay vr180_look
                out={}
                for tag,(gw,gh,props,use_ref) in sizes.items():
                    sock=str(d/('%s.sock'%tag));cfg=d/('cfg-'+tag);cfg.mkdir();mp=None
                    try:
                        mp=subprocess.Popen([str(mpv)]+hidden_flags(str(mpv))+['--no-config','--config-dir='+str(cfg),'--script='+str(fixture if use_ref else script),'--vo=gpu-next','--ao=null','--no-audio',
                            '--pause','--loop-file=inf','--keep-open=yes','--force-window=yes','--no-border','--geometry=%dx%d'%(gw,gh),'--no-osc',
                            '--input-ipc-server='+sock,str(clip)],stdout=log,stderr=log)
                        if not wait(lambda:os.path.exists(sock),10):return None,'mpv socket never appeared'
                        def c(*a):return ipc_roundtrip(sock,json.dumps({'command':list(a)}))
                        if not wait(lambda:isinstance(c('get_property','dwidth').get('data'),(int,float)),10):return None,'video never decoded'
                        for k,v in props:c('set',k,v)
                        ka=[c('get_property','keepaspect').get('data')]
                        c('script-message-to','vr180_look','vr180-look-set-enabled','true');time.sleep(1.2)
                        ka.append(c('get_property','keepaspect').get('data'))
                        shot=d/(tag+'.png')
                        c('screenshot-to-file',str(shot),'window');wait(lambda:shot.exists() and shot.stat().st_size>0,5);time.sleep(.3)
                        c('script-message-to','vr180_look','vr180-look-set-enabled','false');time.sleep(.6)
                        ka.append(c('get_property','keepaspect').get('data'))
                        out[tag]=png_pixels(shot)+(ka,)
                    finally:
                        if mp is not None:
                            try:mp.terminate();mp.wait(timeout=5)
                            except Exception:mp.kill()
                return out,None
            finally:
                v1ctmp.cleanup()
        def v1c_measure(w,h,px):
            zero=lambda p:p[0]==0 and p[1]==0 and p[2]==0
            def black_run(n,line,along):
                k=0
                while k<n and all(zero(line(k,i)) for i in range(along)):k+=1
                return k
            cols_l=black_run(w,lambda k,i:px(k,i),h);cols_r=black_run(w,lambda k,i:px(w-1-k,i),h)
            rows_t=black_run(h,lambda k,i:px(i,k),w);rows_b=black_run(h,lambda k,i:px(i,h-1-k),w)
            box=[]
            for x0,x1 in ((0,w//2),(w//2,w)):
                xs=[];ys=[]
                for y in range(0,h,2):
                    for x in range(x0,x1,2):
                        p=px(x,y)
                        if p[0]>200 and p[1]>200 and p[2]<80:xs.append(x);ys.append(y)
                box.append(((max(xs)-min(xs)+2)/(max(ys)-min(ys)+2)) if xs else 0.0)
            return cols_l,cols_r,rows_t,rows_b,box
        try:
            v1c_sizes={'a1610':(960,600,[],False),'ref1610':(960,600,[('video-aspect-override','16:10')],True),
                       'b169':(960,540,[],False),'c43':(800,600,[],False),'prior_no':(960,600,[('keepaspect','no')],False)}
            v1cres,v1cerr=v1c_run(v1c_sizes)
            if v1cres is None:
                note_skip('v1-fill-round',v1cerr)
            else:
                det=[];okc=True;rows_zero=True;rowsz=[]
                for tag in ('a1610','b169','c43'):
                    w,h,px,_ka=v1cres[tag];cl,cr,rt,rb,box=v1c_measure(w,h,px)
                    good=(cl==0 and cr==0 and True and len(box)==2 and all(abs(b-1.0)<=0.02 for b in box))
                    okc=okc and good
                    rows_zero=rows_zero and rt==0 and rb==0;rowsz.append('%s %dx%d T/B=%d/%d'%(tag,w,h,rt,rb))
                    det.append('%s %dx%d black cols L/R=%d/%d rows T/B=%d/%d disc w/h L/R=%.3f/%.3f %s'%(tag,w,h,cl,cr,rt,rb,box[0],box[1],'ok' if good else 'BAD'))
                w1,h1,p1,_k1=v1cres['a1610'];w2,h2,p2,_k2=v1cres['ref1610']
                # block 182 1: pixel identity to the pre-change shader is dropped (the sharper single-resample hook
                # changes the pixels on purpose). At 16:10 the geometry must still match the pre-change shader:
                # each eye's drawn rect +-1 px, the optical (disc) center +-1 px, the effective h/v fov +-0.5 deg.
                # Disc edge at el=0 is az=+-15deg and at az=0 is el=+-15deg, so with ndc = px/(half eye extent):
                #   tan(hfov/2)=tan(15deg)*(eyeAspect/0.8)/ndc_x   tan(vfov_ref/2)=tan(15deg)*0.8/ndc_y (REF_EYE_ASPECT=0.8)
                def geo(px,w,h):
                    res=[]
                    for x0,x1 in ((0,w//2),(w//2,w)):
                        rx=[];ry=[];dx=[];dy=[]
                        for y in range(h):
                            for x in range(x0,x1):
                                p=px(x,y)
                                if p[0]+p[1]+p[2]>0:rx.append(x);ry.append(y)
                                if p[0]>200 and p[1]>200 and p[2]<80:dx.append(x);dy.append(y)
                        if not rx or not dx:return None
                        ew=x1-x0;asp=ew/float(h)
                        hw=(max(dx)-min(dx)+1)/2.0;hh=(max(dy)-min(dy)+1)/2.0
                        th=math.tan(math.radians(15.0))
                        hf=2*math.degrees(math.atan(th*(asp/0.8)/(hw/(ew/2.0))))
                        vf=2*math.degrees(math.atan(th*0.8/(hh/(h/2.0))))
                        res.append(dict(rect=(min(rx),max(rx),min(ry),max(ry)),cx=(max(dx)+min(dx))/2.0,cy=(max(dy)+min(dy))/2.0,hf=hf,vf=vf))
                    return res
                g1=geo(p1,w1,h1);g2=geo(p2,w2,h2)
                if g1 is None or g2 is None or (w1,h1)!=(w2,h2):
                    geo_ok=False;det.append('16:10 geometry vs pre-change reference not measurable (size %s/%s)'%((w1,h1),(w2,h2)))
                else:
                    geo_ok=True;legacy_y_ok=True;fillb_ok=True;gd=[]
                    for i,nm in enumerate('LR'):
                        a,b=g1[i],g2[i]
                        dr=max(abs(a['rect'][k]-b['rect'][k]) for k in range(4))  # full x AND y rect, against the pre-change baseline, no substitution
                        dxr=max(abs(a['rect'][k]-b['rect'][k]) for k in (0,1));dyr=max(abs(a['rect'][k]-b['rect'][k]) for k in (2,3))
                        dy_new=(a['rect'][2],a['rect'][3]);dy_ref=(b['rect'][2],b['rect'][3])
                        dc=max(abs(a['cx']-b['cx']),abs(a['cy']-b['cy']))
                        dh=abs(a['hf']-b['hf']);dv=abs(a['vf']-b['vf'])
                        ok1=dxr<=1 and dc<=1.0 and dh<=0.5 and dv<=0.5   # OPTICAL content geometry: rect x, optical center, h/v fov
                        geo_ok=geo_ok and ok1
                        legacy_y_ok=legacy_y_ok and dyr<=1
                        fillb_ok=fillb_ok and dy_new==(0,h1-1) and dyr<=max(dy_ref[0],h1-1-dy_ref[1])+1   # FILL bounds: new rect spans the drawable; its y change is only the removed margin rows (+-1)
                        gd.append('%s rect-d(x)=%d rect-d(y)=%d (y rows new=%s ref=%s: the removed black margin) center-d=%.2fpx hfov new/ref=%.2f/%.2f vfov new/ref=%.2f/%.2f %s'%(nm,dxr,dyr,dy_new,dy_ref,dc,a['hf'],b['hf'],a['vf'],b['vf'],'ok' if ok1 else 'BAD'))
                    det.append('16:10 geometry vs pre-change reference (optical rect x +-1px, center +-1px, fov +-0.5deg; raw rect-y separate literal verdict): '+'; '.join(gd))
                same=True   # geometry is its own leg below (v1-geometry-vs-pre-change); the fill leg does not absorb it
                geo_leg=(geo_ok,det.pop())
                fillb_leg=(locals().get('fillb_ok',False),'rect y rows new vs pre-change: raw delta %s px; pass = new rect spans all %d rows and the y change is only the removed margin rows of the baseline (the optical content geometry is the separate leg above)'%(gd and [x.split('rect-d(y)=')[1].split(' ')[0] for x in gd],h1))
                ka_yes=v1cres['a1610'][3];ka_no=v1cres['prior_no'][3]
                kok=(ka_yes==[True,False,True] and ka_no==[False,False,False])
                okc=okc and same and kok
                det.append('keepaspect prior-yes %s prior-no %s restore=%s'%(ka_yes,ka_no,kok))
                note(okc,'v1-fill-round','; '.join(det))
                note(fillb_leg[0],'v1-rect-y-fill-bounds',fillb_leg[1])
                note(locals().get('legacy_y_ok',False),'v1-legacy-rect-y-literal','legacy raw full-rect y delta <=1px, unwaived: '+fillb_leg[1])
                note(geo_leg[0],'v1-geometry-vs-pre-change',geo_leg[1]+' (optical content: rect x, center, h/v fov; the old margin rect-y change is asserted by v1-rect-y-fill-bounds with its raw delta, not dropped)')
                # Block 182 1.2: no black outer rows or columns at 16:10, 16:9 and 4:3 (full fill).
                note(rows_zero,'v1-fill-rows-literal','outer fully-black rows must be 0: '+', '.join(rowsz))
        except Exception as e:
            note_skip('v1-fill-round','not measurable: '+type(e).__name__+' '+str(e)[:120])
        # vr-distance-clamp (block 182 2): the distance-aware separation rule, on real mpv with the shipped
        # vr180-look.lua and synthetic distances (no camera, no gor). Reads user-data/vr180-look/distance-trace
        # (published by the script) and the pushed glsl-shader-opts. Asserts, independently of the script's own
        # arithmetic: (a) vergence demand 2*atan((63+s)/(2d)) <= the demand at d=500 with today's separation, i.e. the
        # cap, for d in 200..800; (b) no cap at d>=500 and without input; (c) the shader total (excess+base+nudge from
        # the pushed opts) equals the reported s_total in ndc; (d) hold 2 s then constant-mm; (e) dial offset enters
        # ipd_eff; (f) fallbacks are logged with a reason; (g) an unreachable shift is reported infeasible, never as a
        # met cap. LINUX mpv only; the d computation, filter and CGDisplayScreenSize are Swift and not exercised here.
        def dist_leg():
            dtmp=tempfile.TemporaryDirectory(prefix='gor-dist.')
            mp=None
            try:
                d=Path(dtmp.name);clip=d/'sbs.mp4'
                ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
                if ff is None:return note_skip('vr-distance-clamp','no vendor ffmpeg')
                r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=gray:s=1024x512:r=10:d=3,format=yuv420p',str(clip)],stdout=log,stderr=log,timeout=60)
                if r.returncode or not clip.is_file():return note_skip('vr-distance-clamp','clip generation failed')
                sock=str(d/'m.sock');cfg=d/'cfg';cfg.mkdir()
                script=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
                mp=subprocess.Popen([str(mpv)]+hidden_flags(str(mpv))+['--no-config','--config-dir='+str(cfg),'--script='+str(script),'--vo=gpu-next','--ao=null','--no-audio',
                    '--pause','--loop-file=inf','--keep-open=yes','--force-window=yes','--no-border','--geometry=1400x900','--no-osc','--input-ipc-server='+sock,str(clip)],stdout=log,stderr=log)
                if not wait(lambda:os.path.exists(sock),10):return note_skip('vr-distance-clamp','mpv socket never appeared')
                def c(*a):return ipc_roundtrip(sock,json.dumps({'command':list(a)}))
                if not wait(lambda:isinstance(c('get_property','dwidth').get('data'),(int,float)),10):return note_skip('vr-distance-clamp','video never decoded')
                c('script-message-to','vr180_look','vr180-look-set-enabled','true');time.sleep(1.0)
                def orient(dist,reason='',mmpx='',nudge='0',fov='135'):
                    c('script-message-to','vr180_look','vr180-look-set-orientation','0','0',fov,'0',nudge,'0','0','0',str(dist),reason,str(mmpx));time.sleep(.35)
                def trace():
                    t=c('get_property','user-data/vr180-look/distance-trace').get('data')
                    try:return json.loads(t)
                    except Exception:return None
                def opts():
                    o=c('get_property','glsl-shader-opts').get('data')
                    return o if isinstance(o,str) else ''
                def optval(k):
                    o=c('get_property','glsl-shader-opts').get('data')
                    if isinstance(o,dict):
                        for kk,vv in o.items():
                            if kk.endswith('/'+k):return float(vv)
                        return None
                    m=re.search(r'%s=([-0-9.eE+]+)'%k,str(o));return float(m.group(1)) if m else None
                res=[];ok=True;infeas=[]
                def chk(name,cond,det):
                    nonlocal ok
                    ok=ok and bool(cond);res.append('%s=%s(%s)'%(name,'ok' if cond else 'BAD',det))
                demand=lambda ipd,s,dd:2*math.atan((ipd+s)/(2.0*dd))
                orient('none','fov-unavailable','0.1118')
                t0=trace()
                if t0 is None:return note_skip('vr-distance-clamp','no distance trace published (osd size unavailable?)')
                chk('none',t0['reason']=='fov-unavailable' and not t0['capped'] and abs(t0['s_total_mm']-t0['s_today_mm'])<1e-3,'reason=%s capped=%s'%(t0['reason'],t0['capped']))
                for dist in (800,500,400,300,200):
                    orient(dist,'ok','0.1118');t=trace()
                    if t is None:return note_skip('vr-distance-clamp','trace missing at d=%d'%dist)
                    ref=demand(63.0+t['offset_mm'],t['s_today_mm'],500.0)
                    got=demand(63.0+t['offset_mm'],t['s_total_mm'],float(dist))
                    if t['infeasible']:
                        # the cap needs a shift beyond the shader's own +-0.8 clamp at this window size: reported, never counted as a met cap
                        infeas.append(dist);capok=(t['capped'] is True)
                    else:
                        capok=got<=ref+1e-6 and (dist>=500 or t['capped']) and (dist<500 or not t['capped'])
                    chk('d%d'%dist+('-INFEASIBLE' if t['infeasible'] else ''),capok,'s_today=%.2f s_total=%.2f demand<=cap %.6f<=%.6f capped=%s infeasible=%s'%(t['s_today_mm'],t['s_total_mm'],got,ref,t['capped'],t['infeasible']))
                # shader total equals reported s_total (ndc), from the pushed opts: excess+base+nudge
                orient(300,'ok','0.1118');t=trace()
                base=optval('vr_base_ipd');nudge=optval('vr_ipd_nudge')
                half=t['eye_w_mm']/2.0
                mag=math.tan(math.radians(90.0)*0.5)/math.tan(math.radians(135.0)*0.5)
                excess=-0.4*(mag-1.0)*0.4
                total=excess+base+nudge if base is not None and nudge is not None else None
                chk('shader-total',total is not None and abs(total-t['s_total_mm']/half)<1e-4,'pushed excess+base+nudge=%s want %.6f'%(None if total is None else '%.6f'%total,t['s_total_mm']/half))
                # dial offset enters ipd_eff
                c('script-message-to','vr180_look','vr180-look-set-ipd','0.1');time.sleep(.3);orient(300,'ok','0.1118');t=trace()
                chk('dial-offset',abs(t['ipd_eff_mm']-(63.0+0.1*half))<1e-3 and t['offset_mm']>0,'ipd_eff=%.3f offset=%.3f'%(t['ipd_eff_mm'],t['offset_mm']))
                c('script-message-to','vr180_look','vr180-look-set-ipd','0');time.sleep(.3)
                # fallback mm/px source
                orient(300,'ok','0');t=trace()
                chk('mmpx-fallback',t['mm_per_px_src']=='macbook-227ppi' and abs(t['mm_per_px']-25.4/227.0)<1e-6,'src=%s'%t['mm_per_px_src'])
                # infeasible is reported, not a met cap
                orient(40,'ok','0.1118');t=trace()
                chk('infeasible',t['infeasible'] is True,'d=40 s_total=%.1f infeasible=%s'%(t['s_total_mm'],t['infeasible']))
                # hold then constant-mm
                orient(300,'ok','0.1118');time.sleep(2.7);t=trace()
                chk('hold-expired',t is not None and t['reason']=='no-face-hold-expired' and not t['capped'],'reason=%s capped=%s'%(t and t['reason'],t and t['capped']))
                note(ok,'vr-distance-clamp','; '.join(res)+(' | cap NOT achievable (shader shift limit) at d=%s: reported as infeasible, not as met'%infeas if infeas else '')+' (LINUX mpv, synthetic distances; Swift d/filter/CGDisplayScreenSize untested)')
            except Exception as e:
                note_skip('vr-distance-clamp','not measurable: '+type(e).__name__+' '+str(e)[:120])
            finally:
                if mp is not None:
                    try:mp.terminate();mp.wait(timeout=5)
                    except Exception:mp.kill()
                dtmp.cleanup()
        dist_leg()
        # vr-param-default (block 182 1.3): the former #defines are now //!PARAMs whose defaults and pushed values are
        # exactly today's constants, so a PARAM conversion must change NO output at default. Real mpv, two scripts on
        # the same synthetic disc clip: the pre-conversion script (selftest-fixtures/vr180-look-pre-param.lua) and the
        # shipped one, at rest and with a pose/fov/ipd state; every pixel must be equal. Control: a live
        # vr180-look-set-tune vr_vignette_darken 0 must change pixels (the PARAM is really live). LINUX mpv, software GL.
        def param_leg():
            ptmp=tempfile.TemporaryDirectory(prefix='gor-param.')
            try:
                d=Path(ptmp.name);clip=d/'disc.mp4'
                ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
                if ff is None:return note_skip('vr-param-default','no vendor ffmpeg')
                ex="gt(cos((0.5-Y/H)*PI)*cos((X/W-0.5)*PI),0.9659258)"
                geq="format=gbrp,geq=r='if(%s,255,90)':g='if(%s,255,90)':b='if(%s,0,90)'"%(ex,ex,ex)
                r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=gray:s=1024x1024:r=10:d=3,'+geq,
                    '-filter_complex','[0]split[a][b];[a][b]hstack,format=yuv420p',str(clip)],stdout=log,stderr=log,timeout=60)
                if r.returncode or not clip.is_file():return note_skip('vr-param-default','clip generation failed')
                new=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
                (d/'ref').mkdir();shutil.copy(str(root/'selftest-fixtures/vr180-look-pre-param.lua'),str(d/'ref'/'vr180-look.lua'));old=d/'ref'/'vr180-look.lua'
                default_sources = {}
                def shot(script,w,h,msgs,tag):
                    sock=str(d/(tag+'.sock'));cfg=d/('cfg-'+tag);cfg.mkdir();mp=None
                    try:
                        mp=subprocess.Popen([str(mpv)]+hidden_flags(str(mpv))+['--no-config','--config-dir='+str(cfg),'--script='+str(script),'--vo=gpu-next','--ao=null','--no-audio',
                            '--pause','--loop-file=inf','--keep-open=yes','--force-window=yes','--no-border','--geometry=%dx%d'%(w,h),'--no-osc','--input-ipc-server='+sock,str(clip)],stdout=log,stderr=log)
                        if not wait(lambda:os.path.exists(sock),10):return None
                        def c(*a):return ipc_roundtrip(sock,json.dumps({'command':list(a)}))
                        if not wait(lambda:isinstance(c('get_property','dwidth').get('data'),(int,float)),10):return None
                        c('script-message-to','vr180_look','vr180-look-set-enabled','true');time.sleep(1.0)
                        for m in msgs:c('script-message-to','vr180_look',*m);time.sleep(.4)
                        time.sleep(.6);out=d/(tag+'.png');c('screenshot-to-file',str(out),'window');wait(lambda:out.exists() and out.stat().st_size>0,5);time.sleep(.3)
                        if tag in ('rest-old', 'rest-new'):
                            default_sources[tag] = (cfg/'shader'/'vr180-look-shader-a.glsl').read_bytes()
                        return png_pixels(out)
                    finally:
                        if mp is not None:
                            try:mp.terminate();mp.wait(timeout=5)
                            except Exception:mp.kill()
                scen=[('return',960,600,[['vr180-look-set-tune','vr_vignette_darken','0'],['vr180-look-set-tune','vr_vignette_darken','1']]),('rest',960,600,[]),('pose',800,600,[['vr180-look-set-orientation','0.3','0.1','110','0.05','0.02','0','0','0'],['vr180-look-set-ipd','0.05']])]
                res=[];ok=True
                for nm,w,h,msgs in scen:
                    a=shot(old,w,h,msgs,nm+'-old');b=shot(new,w,h,msgs,nm+'-new')
                    if a is None or b is None:return note_skip('vr-param-default','mpv did not start for '+nm)
                    diff=0;mx=0
                    for y in range(a[1]):
                        for x in range(a[0]):
                            pa=a[2](x,y);pb=b[2](x,y)
                            dd=max(abs(pa[i]-pb[i]) for i in range(3))
                            if dd:diff+=1;mx=max(mx,dd)
                    same=(a[0],a[1])==(b[0],b[1]) and diff==0
                    ok=ok and same;res.append('%s %dx%d differing px=%d max diff=%d'%(nm,a[0],a[1],diff,mx))
                source_same = default_sources.get('rest-old') is not None and default_sources.get('rest-old') == default_sources.get('rest-new')
                ok = ok and source_same; res.append('default-source byte-identical=%s'%source_same)
                ctl=shot(new,960,600,[['vr180-look-set-tune','vr_vignette_darken','0']],'ctl')
                base=shot(new,960,600,[],'ctlbase')
                live=ctl is not None and base is not None and any(ctl[2](x,y)!=base[2](x,y) for y in range(0,ctl[1],7) for x in range(0,ctl[0],7))
                ok=ok and live;res.append('live-tune control changes pixels=%s'%live)
                note(ok,'vr-param-default','; '.join(res)+' (LINUX mpv software GL; the Mac GPU is untested)')
            except Exception as e:
                note_skip('vr-param-default','not measurable: '+type(e).__name__+' '+str(e)[:120])
            finally:
                ptmp.cleanup()
        param_leg()
        # av-sync-vr (block 181 4): VR with a simulated pose stream must not move A/V sync. Real mpv, the
        # shipped vr180-look.lua, a 1024x512 SBS clip with a 440 Hz tone, played for 8 s three times:
        # base1 and base2 (VR off, measures the run-to-run noise), then vr (VR on and a 30 Hz stream of the
        # same vr180-look-set-orientation script-messages gor sends: still jitter, a 0.5 s turn, hold).
        # Sampled at 2 Hz: avsync (s), at the end total-avsync-change, frame-drop-count,
        # decoder-frame-drop-count, vo-delayed-frame-count, mistimed-frame-count. PASS when vr stays within
        # base spread: each counter <= max(base) + |base1-base2| + 1, mean |avsync| <= max(base mean |avsync|)
        # + |base1-base2 means| + 0.010 s (the +1 frame, +0.010 s and +0.05 s margins are NOT derived from a noise study:
        # they are placeholders that must be replaced by a measured baseline spread over many runs); playback-clock slip (time-pos advance minus wall time over the
        # window) <= max|base| + spread + 0.05 s, which is what any clock/speed change would break. Motion-to-photon lag is NOT measured here. Runs mpv only.
        def avs_run(vr):
            avtmp=tempfile.TemporaryDirectory(prefix='gor-avs.')
            mp=None
            try:
                d=Path(avtmp.name);clip=d/'av.mp4'
                ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
                if ff is None:return None,'no vendor ffmpeg'
                r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=s=1024x512:r=30:d=12',
                    '-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=12','-pix_fmt','yuv420p','-shortest',str(clip)],stdout=log,stderr=log,timeout=90)
                if r.returncode or not clip.is_file():return None,'AV clip generation failed'
                sock=str(d/'a.sock');cfg=d/'cfg';cfg.mkdir()
                script=root/'Resources/vendor/mpv/scripts/vr180-look.lua'
                mp=subprocess.Popen([str(mpv)]+hidden_flags(str(mpv))+['--no-config','--config-dir='+str(cfg),'--script='+str(script),'--vo=gpu-next','--ao=null',
                    '--keep-open=yes','--force-window=yes','--no-border','--geometry=480x300','--no-osc','--input-ipc-server='+sock,str(clip)],stdout=log,stderr=log)
                if not wait(lambda:os.path.exists(sock),10):return None,'mpv socket never appeared'
                def c(*a):return ipc_roundtrip(sock,json.dumps({'command':list(a)}))
                if not wait(lambda:isinstance(c('get_property','time-pos').get('data'),(int,float)),10):return None,'playback never started'
                if vr:c('script-message-to','vr180_look','vr180-look-set-enabled','true')
                before=c('get_property','time-pos').get('data');time.sleep(.3)
                after=c('get_property','time-pos').get('data')
                if not (isinstance(before,(int,float)) and isinstance(after,(int,float)) and after>before):
                    return None,'VR playback not advancing after enable: time-pos %s -> %s pause=%s eof=%s idle=%s cachePause=%s'%(before,after,c('get_property','pause'),c('get_property','eof-reached'),c('get_property','idle-active'),c('get_property','paused-for-cache'))
                tp0=after;t0=time.monotonic();n=0;seed=12345;av=[];nxt=t0
                def noise():
                    nonlocal seed
                    seed=(seed*1103515245+12345)&0x7fffffff
                    return seed/0x3fffffff-1.0
                while time.monotonic()-t0<8.0:
                    if vr:
                        sec=time.monotonic()-t0;ph=sec%6.5;turn=0.0 if ph<3.0 else min(1.0,(ph-3.0)/0.5)
                        c('script-message-to','vr180_look','vr180-look-set-orientation',str(0.5*turn+0.003*noise()),str(0.003*noise()),str(135.0*(1+0.0*noise())),str(0.002*noise()),'0','0','0','0')
                    n+=1
                    if n%15==0:
                        v=c('get_property','avsync').get('data')
                        if isinstance(v,(int,float)):av.append(float(v))
                    nxt+=1.0/30.0;time.sleep(max(0.0,nxt-time.monotonic()))
                tp1=c('get_property','time-pos').get('data');wall=time.monotonic()-t0
                def g(name):
                    v=c('get_property',name).get('data');return float(v) if isinstance(v,(int,float)) else None
                res={'avsync_mean_abs':(sum(abs(x) for x in av)/len(av)) if av else None,'avsync_n':len(av),
                     'total_avsync_change':g('total-avsync-change'),'drop':g('frame-drop-count'),'decdrop':g('decoder-frame-drop-count'),
                     'delayed':g('vo-delayed-frame-count'),'mistimed':g('mistimed-frame-count'),
                     'clock_slip':((float(tp1)-float(tp0))-wall) if isinstance(tp0,(int,float)) and isinstance(tp1,(int,float)) else None}
                return res,None
            finally:
                if mp is not None:
                    try:mp.terminate();mp.wait(timeout=5)
                    except Exception:mp.kill()
                avtmp.cleanup()
        try:
            b1,e1=avs_run(False)
            b2,e2=(avs_run(False) if b1 else (None,e1))
            v,e3=(avs_run(True) if b2 else (None,e2))
            if v is None or b1 is None or b2 is None or None in (b1['avsync_mean_abs'],b2['avsync_mean_abs'],v['avsync_mean_abs']):
                note_skip('av-sync-vr','not measurable: '+str(e1 or e2 or e3 or 'avsync property missing')+' b1=%s b2=%s vr=%s'%(b1,b2,v))
            else:
                bad=[];missing=[]
                for k in ('drop','decdrop','delayed'):
                    if None in (b1[k],b2[k],v[k]):missing.append(k);continue
                    allow=max(b1[k],b2[k])+abs(b1[k]-b2[k])+1
                    if v[k]>allow:bad.append('%s vr=%s allowed<=%s'%(k,v[k],allow))
                allow_av=max(b1['avsync_mean_abs'],b2['avsync_mean_abs'])+abs(b1['avsync_mean_abs']-b2['avsync_mean_abs'])+0.010
                if v['avsync_mean_abs']>allow_av:bad.append('mean|avsync| vr=%.4f allowed<=%.4f'%(v['avsync_mean_abs'],allow_av))
                if b1['total_avsync_change'] is not None and b2['total_avsync_change'] is not None and v['total_avsync_change'] is not None:
                    allow_t=max(abs(b1['total_avsync_change']),abs(b2['total_avsync_change']))+abs(b1['total_avsync_change']-b2['total_avsync_change'])+0.010
                    if abs(v['total_avsync_change'])>allow_t:bad.append('total-avsync-change vr=%.4f allowed<=%.4f'%(v['total_avsync_change'],allow_t))
                if None not in (b1['clock_slip'],b2['clock_slip'],v['clock_slip']):
                    allow_c=max(abs(b1['clock_slip']),abs(b2['clock_slip']))+abs(b1['clock_slip']-b2['clock_slip'])+0.05
                    if abs(v['clock_slip'])>allow_c:bad.append('clock slip vr=%.3f allowed<=%.3f'%(v['clock_slip'],allow_c))
                if b1['total_avsync_change'] is None or b2['total_avsync_change'] is None or v['total_avsync_change'] is None:missing.append('total_avsync_change')
                if None in (b1['clock_slip'],b2['clock_slip'],v['clock_slip']):missing.append('clock_slip')
                if missing and not bad:
                    note_skip('av-sync-vr','required metric(s) not exposed by this mpv: '+','.join(missing)+' (never a PASS without them) base1=%s base2=%s vr=%s'%(b1,b2,v))
                else:
                  note(not bad,'av-sync-vr','base1=%s base2=%s vr=%s %s'%(b1,b2,v,'; '.join(bad)))
        except Exception as e:
            note_skip('av-sync-vr','not measurable: '+type(e).__name__+' '+str(e)[:120])
        # vr-sync-source-guard (block 181 4, A/V hard rule): the pose and VR code may not touch the playback
        # clock, audio delay, video sync, interpolation or buffering. Static guard over the shipped sources:
        # (1) vr180-look.lua may only call set_property(_native) on glsl-shaders, keepaspect and the user-data gap publication (not playback), and commandv only
        # change-list glsl-shader-opts; (2) HeadTracker's pose path (applyObservation / filter / sim / blink
        # sections) and VR180Controller.applyHeadPose contain no mpv playback-clock property or command names.
        # This is source evidence only: it proves nothing about runtime behaviour (see av-sync-vr for that).
        try:
            lua=(root/'Resources/vendor/mpv/scripts/vr180-look.lua').read_text()
            props=set(re.findall(r'mp\.set_property(?:_native)?\(\s*"([^"]+)"',lua))
            cmds=re.findall(r'mp\.command(?:v|_native)?\(\s*"([^"]+)"(?:\s*,\s*"([^"]+)")?(?:\s*,\s*"([^"]+)")?',lua)
            bad_cmd=[c for c in cmds if c[:2]!=('change-list','glsl-shader-opts')]
            forbid=('audio-delay','video-sync','interpolation','audio-buffer','demuxer','cache','speed','autosync','video-timing-offset','hr-seek','time-pos','playback-time','"seek"','"pause"')
            swift_pf=(root/'Sources/gor/gor/PPController_Features.swift').read_text()
            a=swift_pf.index('private func applyHeadPose');b=swift_pf.index('func recenterHeadTracking',a)
            pose_vr=swift_pf[a:b]
            __import__('sys').path.insert(0,str(root/'Tests/Architecture'))
            from camera_source import read_source
            swift_sc=read_source(root/'Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift')
            a=swift_sc.index('struct OneEuro');b=swift_sc.index('// MARK: - Baseline (recenter)',a)
            c0=swift_sc.index('private func applyObservation');c1=swift_sc.index('func stopSimulatedPose',c0)
            k0=swift_sc.index('// MARK: - Blink measurement');k1=swift_sc.index('private let faceRequest',k0)
            pose_sc=swift_sc[a:b]+swift_sc[c0:c1]+swift_sc[k0:k1]  # includes the blink section
            # Match forbidden property tokens, not explanatory comments or speedFilterCutoffHz identifiers.
            def strip_line_comments(text):
                out=[]
                for line in text.splitlines():
                    quoted=False;escaped=False;cut=len(line)
                    for i,ch in enumerate(line):
                        if escaped:escaped=False;continue
                        if ch=='\\' and quoted:escaped=True;continue
                        if ch=='"':quoted=not quoted
                        if not quoted and line[i:i+2]=='//':cut=i;break
                    out.append(line[:cut])
                return '\n'.join(out)
            checked='\n'.join(strip_line_comments(blob) for blob in (pose_vr,pose_sc))
            hits=[k for k in forbid if re.search(r'(?<![A-Za-z0-9_])'+re.escape(k.strip('"'))+r'(?![A-Za-z0-9_])',checked)]
            okg=props<= {'glsl-shaders','keepaspect','user-data/vr180-look/physical-gap-frac','user-data/vr180-look/distance-trace','user-data/vr180-look/enabled'} and not bad_cmd and not hits
            note(okg,'vr-sync-source-guard','lua set_property names=%s non-shader-opts commands=%s forbidden names in pose code=%s (source scan only, not runtime proof)'%(sorted(props),bad_cmd,hits))
        except Exception as e:
            note_skip('vr-sync-source-guard','not measurable: '+type(e).__name__+' '+str(e)[:120])
        # vr-app-filter + av-sync-vr-app (block 181 4, app-driven): REAL gor.app, a 4096x2048 2:1 clip (VR auto-detect)
        # with a quiet 440 Hz tone (volume 0.02) so a/v sync is measurable. Seven runs of 8 s each: off1..off3 = VR OFF
        # (a 4096x2050 clip, just under the 2:1 auto-detect, same decode cost), nopose1/nopose2 = VR on, NO pose stream,
        # sim1/sim2 = VR on + GOR_VR_SIM_POSE=1 (head tracking is switched on by the sim path
        # only, the camera is never started) so the real HeadTracker filter, applyHeadPose and the real script-message
        # stream run. GOR_TRACE_GEOM=1 gives poseTrace lines (raw + filtered, timestamped) for the filter analysis;
        # mpv properties are read over gor's own mpv socket. Both legs are Mac-only; the analysis function was
        # validated on Linux against a Python replica of the filter (PASS) and against filter-off (FAIL).
        # a/v margins are the same PLACEHOLDERS as av-sync-vr (not derived from a noise study).
        import math,statistics
        # ---- analysis of poseTrace lines from the app-driven sim (GOR_VR_SIM_POSE=1), first 6.5 s cycle ----
        # Expected values are derived from the filter's own definition, not tuned on data:
        #  still head (0..3 s): the one-euro minCutoff is 0.35 Hz (tau 0.45 s; was 0.637 Hz). For the old 0.25 s tau and white noise sampled at 30 Hz
        #  the single-pole std ratio is sqrt(a/(2-a)), a=dt/(dt+tau)=0.1176 -> 0.25. The leg requires < 0.5 (2x margin).
        #  The fov channel (zOffset, tau 0.8 s) must reduce at least as much.
        #  turn (3.0..3.5 s ramp 0 -> 0.5 rad): the previous fixed filter lagged a ramp by its tau, 0.25 s. The new filter's
        #  half-level crossing may lag the raw crossing by at most that (never worse than before).
        #  hold: mean filtered yaw over the last 1 s of the 6.5 s cycle within 0.02 rad of the raw mean there.
        def analyze(lines):
            pts=[(l['t'],l['raw'],l['f']) for l in lines if l.get('k')=='poseTrace']
            if len(pts)<2:return 'INCONCLUSIVE','fewer than 2 poseTrace lines'
            t0=pts[0][0];cyc=[(t-t0,r,f) for t,r,f in pts if t-t0<6.5]
            gaps=[b[0]-a[0] for a,b in zip(cyc,cyc[1:]) if b[0]-a[0]>0.2]
            if gaps:return 'INCONCLUSIVE','gap(s) >0.2 s inside the first 6.5 s of the sim (restart or stall): %s'%['%.2f'%x for x in gaps]
            if len(cyc)<150:return 'INCONCLUSIVE','only %d poseTrace samples in the first 6.5 s (need >=150 of ~195)'%len(cyc)
            # Bind the assumed sim phase to the data: the raw yaw must be ~0 before 3 s and ~0.5 rad after 3.6 s.
            pre=[c[1][0] for c in cyc if c[0]<2.9];post=[c[1][0] for c in cyc if c[0]>3.7]
            if not pre or not post or abs(statistics.mean(pre))>0.01 or abs(statistics.mean(post)-0.5)>0.02:
                return 'INCONCLUSIVE','sim phase does not match the assumed 3 s still / 0.5 s turn / hold (raw yaw pre=%s post=%s)'%(statistics.mean(pre) if pre else None,statistics.mean(post) if post else None)
            names=['yaw','pitch','roll','x','y','z'];det=[];bad=[]
            still=[c for c in cyc if 0.5<=c[0]<3.0]
            for k in (0,1,2,5):
                sr=statistics.pstdev([c[1][k] for c in still]);sf=statistics.pstdev([c[2][k] for c in still])
                ratio=sf/sr if sr>0 else float('inf');det.append('%s still std raw=%.5f filt=%.5f ratio=%.2f'%(names[k],sr,sf,ratio))
                if not ratio<0.5:bad.append('%s still-head jitter ratio %.2f >= 0.5'%(names[k],ratio))
            def cross(idx,level):
                for c in cyc:
                    if c[0]>=3.0 and c[idx][0]>=level:return c[0]
                return None
            tr=cross(1,0.25);tf=cross(2,0.25)
            if tr is None or tf is None:bad.append('turn half-level crossing not found raw=%s filt=%s'%(tr,tf))
            else:
                lag=tf-tr;det.append('turn half-level lag %.3f s (raw crossing %.3f filt %.3f)'%(lag,tr,tf))
                if lag>0.25:bad.append('turn lag %.3f s > 0.25 s (the previous fixed filter)'%lag)
            hold=[c for c in cyc if c[0]>=5.5]
            d=abs(statistics.mean(c[2][0] for c in hold)-statistics.mean(c[1][0] for c in hold));det.append('hold |mean filt-raw| yaw %.4f'%d)
            if d>0.02:bad.append('hold offset %.4f > 0.02'%d)
            return ('FAIL' if bad else 'PASS'),'; '.join(det+bad)
        cleanup_problems=[]
        cleanup_completed=[]
        def pref_state():
            # (exit code, stdout, stderr): absent (rc!=0 'does not exist'), present value, or a tool error are distinct.
            try:
                r=subprocess.run(['/usr/bin/defaults','read',bundle_id,'gor.vr.headTracking'],capture_output=True,text=True,timeout=10)
                kind='present' if r.returncode==0 else ('absent' if 'does not exist' in r.stderr else 'error')
                return (kind,r.stdout.strip(),r.stderr.strip()[:80] if kind=='error' else '')
            except Exception as e:
                return ('error','',type(e).__name__)
        pref_before=pref_state()
        def app_run(mode):   # mode: 'off' = VR off (4096x2050, just under the 2:1 auto-detect), 'nopose' = VR on no pose, 'sim' = VR on + simulated pose
            sim=(mode=='sim');vroff=(mode=='off2050');matched=(mode=='off');state={}
            tmp=tempfile.TemporaryDirectory(prefix='gor-vapp.')
            proc=None
            try:
                d=Path(tmp.name);clip=d/('plain-av.mp4' if mode=='off2050' else 'fixture.VR180.mp4')
                ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
                if ff is None:return None,'no vendor ffmpeg'
                r=subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=duration=60:size=4096x%d:rate=5'%(2050 if vroff else 2048),
                    '-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=60','-af','volume=0.02','-pix_fmt','yuv420p','-shortest',str(clip)],stdout=log,stderr=log,timeout=240)
                if r.returncode or not clip.is_file():return None,'clip generation failed'
                trace=Path.home()/'Library/Application Support/gor/geom_trace.log'
                mark=trace.stat().st_size if trace.exists() else 0
                env=dict(os.environ,GOR_TRACE_GEOM='1',GOR_VR_TEST_NO_CAMERA='1')
                if sim:env['GOR_VR_SIM_POSE']='1'
                else:env.pop('GOR_VR_SIM_POSE',None)
                proc=subprocess.Popen([str(binary),'--gor-no-activate',str(clip)],stdout=log,stderr=log,env=env)
                gp=proc.pid;gs0=identity(gp);owned.append((gp,gs0));state['gp']=gp;state['gs']=gs0
                sock=os.path.join(tempfile.gettempdir(),'pp-%d.sock'%gp)
                if not wait(lambda:os.path.exists(sock),15):return None,'gor mpv socket never appeared'
                def own_child():
                    # Only the vendor mpv whose PPID is THIS gor: executable + parent, never a name sweep.
                    ids=subprocess.run(['/usr/bin/pgrep','-x','mpv'],capture_output=True,text=True)
                    for v in ids.stdout.split():
                        pid=int(v)
                        if ps(pid,'ppid')==str(gp) and os.path.realpath(ps(pid,'comm') or '')==os.path.realpath(mpv):return pid
                    return None
                kid=wait(own_child,15)
                if kid:state['kid']=kid;state['ks']=identity(kid);owned.append((kid,state['ks']))
                def c(*a):return ipc_roundtrip(sock,json.dumps({'command':list(a)}))
                def tlines():
                    try:
                        with open(trace,'rb') as fh:
                            fh.seek(mark);txt=fh.read().decode('utf-8','replace').splitlines()
                    except FileNotFoundError:return []
                    out=[]
                    for l in txt:
                        i=l.find('{"k":"')
                        if i>=0:
                            try:out.append(json.loads(l[i:]))
                            except ValueError:pass
                    return out
                if matched:
                    # IDENTICAL clip with VR off: let auto-detect enable VR, then drive the app's own 180d test hook
                    # (user-data/gor-test-vr-mode polled under GOR_TRACE_GEOM=1, setVRModeEnabled). The hook compares with its
                    # last value (0), so write 1 then 0. vrModeSetByAutoDetect stays set, so nothing re-enables VR for this file.
                    if not wait(lambda:any(x.get('k')=='vrCamera' and x.get('vr') is True for x in tlines()),25):return None,'vr=true never appeared before the matched VR-off step'
                    n0=len(tlines())
                    c('set_property','user-data/gor-test-vr-mode',1);time.sleep(1.0);c('set_property','user-data/gor-test-vr-mode',0)
                    if not wait(lambda:any(x.get('k')=='vrCamera' and x.get('vr') is False for x in tlines()[n0:]),10):return None,'MATCHED_OFF_UNAVAILABLE'
                    time.sleep(2.0)
                elif vroff:
                    if not wait(lambda:isinstance(c('get_property','dwidth').get('data'),(int,float)),25):return None,'VR-off clip never decoded'
                    time.sleep(2.0)
                else:
                    key=(lambda:any(x.get('k')=='poseTrace' for x in tlines())) if sim else (lambda:any(x.get('k')=='vrCamera' and x.get('vr') is True for x in tlines()))
                    if not wait(key,25):return None,'%s never appeared in the trace'%('poseTrace' if sim else 'vr=true')
                def g(name):
                    v=c('get_property',name).get('data');return float(v) if isinstance(v,(int,float)) else None
                # AppDelegate deliberately launches a new app paused. This fixture owns THAT app,
                # so explicitly start it once as setup, never retry/unpause a stalled measurement.
                if c('get_property','eof-reached').get('data') is True:return None,'fixture reached EOF before start'
                play_ack=c('set_property','pause',False)
                if play_ack.get('error')!='success':return None,'fixture playback start rejected: %s'%play_ack
                if not wait(lambda:c('get_property','pause').get('data') is False,5):return None,'fixture remained paused after acknowledged start'
                # Settle BEFORE the measured window: the VR entry / hook toggle / auto-fullscreen transition must not enter the
                # window. Settled = the mpv OSD size unchanged for 1.5 s (max 12 s). The cumulative counters at that point are
                # recorded as 'transition' and subtracted: the window values are END minus START, never run totals.
                def settle():
                    last=None;since=time.monotonic();end=time.monotonic()+12
                    while time.monotonic()<end:
                        cur=(c('get_property','osd-width').get('data'),c('get_property','osd-height').get('data'),c('get_property','fullscreen').get('data'))
                        valid=all(isinstance(v,(int,float)) and not isinstance(v,bool) and v>0 for v in cur[:2]) and isinstance(cur[2],bool)
                        if not valid:last=None;since=time.monotonic()
                        elif cur!=last:last=cur;since=time.monotonic()
                        elif time.monotonic()-since>=1.5:return True
                        time.sleep(0.3)
                    return False
                settled=settle()
                # Confirm the mode before the window: shader list matches the mode and playback is actually advancing.
                shl=c('get_property','glsl-shaders').get('data')
                want_vr=not (vroff or matched)
                if want_vr and not any('vr180' in str(s) for s in (shl or [])):return None,'VR run but no vr180 shader is loaded at window start'
                if not want_vr and any('vr180' in str(s) for s in (shl or [])):return None,'VR-off run but a VR180 shader is loaded at window start: %s'%shl
                ta=c('get_property','time-pos').get('data');time.sleep(0.6);tb=c('get_property','time-pos').get('data')
                if not (isinstance(ta,(int,float)) and isinstance(tb,(int,float)) and tb>ta):return None,'playback not advancing at window start (time-pos %s -> %s) pause=%s eof=%s idle=%s cachePause=%s'%(ta,tb,c('get_property','pause'),c('get_property','eof-reached'),c('get_property','idle-active'),c('get_property','paused-for-cache'))
                names={'drop':'frame-drop-count','decdrop':'decoder-frame-drop-count','delayed':'vo-delayed-frame-count','mistimed':'mistimed-frame-count','total_avsync_change':'total-avsync-change'}
                pre={k:g(v) for k,v in names.items()}
                tp0=c('get_property','time-pos').get('data');t0=time.monotonic();av=[]
                while time.monotonic()-t0<8.0:
                    v=c('get_property','avsync').get('data')
                    if isinstance(v,(int,float)):av.append(float(v))
                    time.sleep(0.5)
                tp1=c('get_property','time-pos').get('data');wall=time.monotonic()-t0
                post={k:g(v) for k,v in names.items()}
                eof=c('get_property','eof-reached').get('data');paused=c('get_property','pause').get('data')
                shl2=c('get_property','glsl-shaders').get('data')
                if eof is True or paused is True:return None,'playback hit EOF or paused inside the window (eof=%s pause=%s)'%(eof,paused)
                if sorted(shl2 or [])!=sorted(shl or []) or (want_vr and not any('vr180' in str(s) for s in (shl2 or []))):return None,'shader/mode changed during the window (start=%s end=%s)'%(shl,shl2)
                if not (isinstance(tp0,(int,float)) and isinstance(tp1,(int,float)) and tp1-tp0>0.5*wall):return None,'playback did not advance across the window (time-pos %s -> %s over %.1f s)'%(tp0,tp1,wall)
                dl=lambda k:(post[k]-pre[k]) if post[k] is not None and pre[k] is not None else None
                res={'avsync_mean_abs':(sum(abs(x) for x in av)/len(av)) if av else None,'avsync_n':len(av),
                     'total_avsync_change':dl('total_avsync_change'),'drop':dl('drop'),'decdrop':dl('decdrop'),
                     'delayed':dl('delayed'),'mistimed':dl('mistimed'),
                     'clock_slip':((float(tp1)-float(tp0))-wall) if isinstance(tp0,(int,float)) and isinstance(tp1,(int,float)) else None,
                     'settled':settled,'transition':pre,'window_s':round(wall,2),'window_start_mono':round(t0,2)}
                if not settled:return None,'playback never settled (OSD size/fullscreen kept changing) before the window'
                if sim:
                    # Camera must never start on the sim path; saved head-tracking preference is checked by the caller.
                    cam=[x for x in tlines() if x.get('k')=='vrCamera' and (x.get('sessionRequested') or x.get('sessionRunning') or x.get('camActive') or x.get('vrOwned',0)>0)]
                    res['camera_started']=cam[:1]
                    # Sim stop: when VR is switched off through the app hook, the pose stream must stop (hook may be absent: None).
                    nb=len([x for x in tlines() if x.get('k')=='poseTrace'])
                    c('set_property','user-data/gor-test-vr-mode',1);time.sleep(0.8);c('set_property','user-data/gor-test-vr-mode',0);time.sleep(1.0)
                    n1=len([x for x in tlines() if x.get('k')=='poseTrace']);time.sleep(1.5);n2=len([x for x in tlines() if x.get('k')=='poseTrace'])
                    offseen=any(x.get('k')=='vrCamera' and x.get('vr') is False for x in tlines())
                    res['sim_stops']=(n2==n1) if offseen else None
                res['ordinary_shaders']=sorted(str(s) for s in (shl2 or []) if 'vr180' not in str(s))
                res['lines']=tlines()
                if vroff and any(x.get('k')=='vrCamera' and x.get('vr') is True for x in res['lines']):return None,'VR turned on in the VR-off baseline (invalid baseline)'
                if matched:
                    vl=[x.get('vr') for x in res['lines'] if x.get('k')=='vrCamera']
                    if not vl or vl[-1] is not False:return None,'VR was not off at the end of the matched VR-off run (invalid baseline)'
                    shl=c('get_property','glsl-shaders').get('data')
                    if any('vr180' in str(s) for s in (shl or [])):return None,'a VR180 shader is still loaded in the matched VR-off run (invalid baseline): %s'%shl
                return res,None
            finally:
                if proc is not None:
                    # Terminate only the Popen we own (identity checked), reap it, then require the recorded owned
                    # mpv child to be gone. A leftover is killed only if its pid still has the recorded start time
                    # and the vendor mpv executable (pid reuse never gets a signal); death is verified.
                    prior_cleanup_errors=len(cleanup_problems)
                    gp=state.get('gp');gs=state.get('gs')
                    if gp is not None and identity(gp)==gs:
                        try:proc.terminate();proc.wait(timeout=8)
                        except Exception:
                            proc.kill()
                            try:proc.wait(timeout=5)
                            except Exception:cleanup_problems.append('gor pid %s did not exit after SIGKILL'%gp)
                    else:
                        cleanup_problems.append('gor pid %s identity changed before termination (no signal sent)'%gp)
                    kid=state.get('kid');ks=state.get('ks')
                    gsock=os.path.join(tempfile.gettempdir(),'pp-%d.sock'%proc.pid)
                    if kid is not None:
                        wait(lambda:not alive(kid),8)
                        if alive(kid):
                            if identity(kid)==ks and os.path.realpath(ps(kid,'comm') or '')==os.path.realpath(mpv):
                                try:os.kill(kid,signal.SIGKILL)
                                except ProcessLookupError:pass
                                if not wait(lambda:not alive(kid),5):cleanup_problems.append('owned mpv %d still alive after SIGKILL'%kid)
                                else:cleanup_problems.append('owned mpv %d outlived gor and was killed'%kid)
                            # else: pid reused by an unrelated process: not ours, no signal
                    else:
                        cleanup_problems.append('gor pid %s: no owned mpv child was identified, child cleanup unverified'%gp)
                    if os.path.exists(gsock):cleanup_problems.append('socket %s left behind'%gsock)
                    if kid is not None and gp is not None and not alive(gp) and not alive(kid) and not os.path.exists(gsock) and len(cleanup_problems)==prior_cleanup_errors:
                        cleanup_completed.append(mode)
                tmp.cleanup()
        try:
            runs={};errs=[]
            off_mode='off'   # matched clip through the 180d hook; falls back to the 4096x2050 clip when the hook is absent
            plan=(('off1',None),('off2',None),('off3',None),('nopose1','nopose'),('nopose2','nopose'),('sim1','sim'),('sim2','sim'))
            for name,mode in plan:
                mode=mode or off_mode
                r,e=app_run(mode)
                if r is None and e=='MATCHED_OFF_UNAVAILABLE' and off_mode=='off':
                    if any(k.startswith('off') for k in runs):
                        errs.append('%s: matched VR-off hook failed AFTER a matched baseline run succeeded; matched and unmatched baselines are never combined, required matched comparison aborted'%name);break
                    off_mode='off2050';r,e=app_run(off_mode)   # hook absent in this build: unmatched run, reported as PARTIAL only
                if r is None:errs.append('%s: %s'%(name,e));break
                if runs and r.get('ordinary_shaders')!=next(iter(runs.values())).get('ordinary_shaders'):
                    errs.append('%s: ordinary shader baseline changed; comparison invalid'%name);break
                runs[name]=r
            if len(runs)<len(plan):
                note_skip('vr-app-filter','not measurable: '+'; '.join(errs))
                note_skip('vr-app-guards','not measurable (runs incomplete, camera/sim-stop guards unproven): '+'; '.join(errs))
                note_skip('av-sync-vr-app','not measurable: '+'; '.join(errs))
            else:
                guard_fail=[];guard_incon=[]
                for s in ('sim1','sim2'):
                    if runs[s].get('camera_started'):guard_fail.append('%s: camera/session started under the sim pose: %s'%(s,json.dumps(runs[s]['camera_started'][0])))
                    if runs[s].get('sim_stops') is None:guard_incon.append('%s: sim-stop lifecycle unproven (no vr=false trace, hook absent)'%s)
                    if runs[s].get('sim_stops') is False:guard_fail.append('%s: poseTrace kept flowing after VR was switched off (sim not stopped)'%s)
                stray=[x for k in runs if not k.startswith('sim') for x in runs[k]['lines'] if x.get('k')=='poseTrace']
                results_f=[analyze(runs[k]['lines']) for k in ('sim1','sim2')]
                verdict=('FAIL' if any(v=='FAIL' for v,_ in results_f) else 'INCONCLUSIVE' if any(v=='INCONCLUSIVE' for v,_ in results_f) else 'PASS')
                detail=' | '.join('sim%d: %s'%(i+1,d) for i,(v,d) in enumerate(results_f))
                if stray:verdict,detail='FAIL','baseline runs (no sim pose) produced %d poseTrace lines; '%len(stray)+detail
                if verdict=='PASS' and guard_incon:verdict='INCONCLUSIVE';detail=detail+' | '+'; '.join(guard_incon)
                if verdict=='INCONCLUSIVE':note_skip('vr-app-filter',detail)
                else:note(verdict=='PASS','vr-app-filter',detail)
                # Camera / sim-stop guards are their own leg: a known failure is a FAIL whatever else is inconclusive.
                if guard_fail:note(False,'vr-app-guards','; '.join(guard_fail))
                elif guard_incon:note_skip('vr-app-guards','; '.join(guard_incon))
                else:note(True,'vr-app-guards','no camera/session under the sim pose, pose stream stopped with VR off (app-driven)')
                sm=lambda r:{k:r[k] for k in r if k!='lines'}
                metrics=('drop','decdrop','delayed','mistimed','avsync_mean_abs','total_avsync_change','clock_slip')
                def val(r,k):
                    x=r[k]
                    return None if x is None else (abs(x) if k in ('total_avsync_change','clock_slip') else x)
                def compare(bases,v):
                    # Tolerance DERIVED from the baseline runs themselves (no constant margin): a VR value may not exceed
                    # max(baseline) + (max(baseline)-min(baseline)) per metric. Needs >=3 baseline runs to mean anything.
                    bad=[];missing=[]
                    for k in metrics:
                        bv=[val(b,k) for b in bases];x=val(v,k)
                        if x is None or None in bv:missing.append(k);continue
                        hi=max(bv)+(max(bv)-min(bv))
                        if x>hi:bad.append('%s=%.4g > derived bound %.4g (baseline %s)'%(k,x,hi,['%.4g'%y for y in bv]))
                    return bad,missing
                offs=[runs['off1'],runs['off2'],runs['off3']];nops=[runs['nopose1'],runs['nopose2']]
                bad=[];missing=set()
                for s in ('sim1','sim2'):
                    b1,m1=compare(offs,runs[s])           # PRIMARY: VR off x3 vs VR on + sim
                    bad+=['%s vs VR-off: %s'%(s,x) for x in b1];missing|=set(m1)
                nop_note='VR-on-no-pose x2 (pose-stream isolation, reported only, n=2 gives no derived bound): '+' '.join('%s=%s'%(k,sm(r)) for k,r in (('nopose1',nops[0]),('nopose2',nops[1])))
                summ=' '.join('%s=%s'%(k,sm(runs[k])) for k in ('off1','off2','off3','sim1','sim2'))+' '+nop_note
                tail=' (VR-off baseline: %s; bounds derived'%('identical clip, VR switched off through the app test hook' if off_mode=='off' else '4096x2050 clip, same size class, NOT an identical clip')+' from 3 baseline runs; still a small sample, so a PASS means no excursion beyond the observed baseline spread, not a proven noise floor; motion-to-photon lag not measured)'
                if off_mode!='off':
                    # Required contract is the identical-clip VR-off baseline. Without the hook this is PARTIAL: never a PASS.
                    if bad:note(False,'av-sync-vr-app-unmatched-breach','known metric breach against the UNMATCHED 4096x2050 baseline (a real excursion beyond the observed spread, though not the required contract): '+'; '.join(bad))
                    note_skip('av-sync-vr-app','PARTIAL, required matched VR-off baseline unavailable (app test hook absent); 4096x2050 comparison would-be verdict: %s | %s'%('BREACH '+'; '.join(bad) if bad else ('missing '+','.join(sorted(missing)) if missing else 'within derived bounds'),summ))
                elif bad:note(False,'av-sync-vr-app','BREACH '+'; '.join(bad)+(' | missing metrics: '+','.join(sorted(missing)) if missing else '')+' | '+summ)
                elif missing:note_skip('av-sync-vr-app','required metric(s) missing (fail closed, never a PASS): '+','.join(sorted(missing))+' '+summ)
                else:note(True,'av-sync-vr-app',summ+tail)
        except Exception as e:
            note_skip('vr-app-filter','not measurable: '+type(e).__name__+' '+str(e)[:120])
            note_skip('vr-app-guards','not measurable (exception, camera/sim-stop guards unproven): '+type(e).__name__+' '+str(e)[:120])
            note_skip('av-sync-vr-app','not measurable: '+type(e).__name__+' '+str(e)[:120])
        pref_after=pref_state()   # always evaluated, also after an early failure or exception above
        if 'error' in (pref_before[0],pref_after[0]):note_skip('vr-app-pref','defaults read failed: before=%s after=%s'%(pref_before,pref_after))
        else:note(pref_before==pref_after,'vr-app-pref','saved head-tracking preference (gor.vr.headTracking) before=%s after=%s'%(pref_before[:2],pref_after[:2]))
        if cleanup_problems:
            note(False,'vr-app-cleanup','app-driven legs left processes/sockets behind: '+'; '.join(cleanup_problems))
        elif cleanup_completed:
            note(True,'vr-app-cleanup','owned app/child death + socket absence verified for %d actually started legs (%s)'%(len(cleanup_completed),','.join(cleanup_completed)))
        else:note_skip('vr-app-cleanup','no completed owned app/child/socket cleanup checks')
        # v3 (block 180 3b): opening a >=4000 wide 2:1 file auto-enables the VR shader but
        # must NOT start head tracking or a VR-owned capture session. Real gor.app with
        # GOR_TRACE_GEOM=1. The app writes a "vrCamera" line on every VR/head-tracking
        # change plus a 1 Hz "tick" sample while VR is on (vr, head, camActive,
        # sessionRequested, sessionRunning, consumers, ambient, vrOwned=consumers-ambient).
        # The leg observes a window of ticks AFTER VR entry (temporal absence, not a single
        # snapshot):
        #   Capture-session lifecycle events (any consumer start/stop and every camera state
        #   change, with consumer attribution) are also traced, so a brief session between
        #   ticks is recorded. Absence is claimed only as "no session event and no session
        #   seen in the ticks over the observed window", not as continuous sampling.
        #   FAIL         head/camActive true, any vrOwned>0, or a requested/running session
        #                with no known owner (ambient False and vrOwned 0).
        #   INCONCLUSIVE fewer than 4 post-entry ticks, or the session ran only because the
        #                separate ambient-dimming consumer held it (VR side clean, but
        #                "no capture" is not demonstrated).
        #   PASS         >=4 ticks, no VR-owned consumer, session never requested/running.
        v3tmp=tempfile.TemporaryDirectory(prefix='gor-v3.')
        v3gp=None
        try:
            v3ff=next((p for p in (root/'Resources/vendor').rglob('ffmpeg') if p.is_file() and os.access(p,os.X_OK)),None)
            v3clip=Path(v3tmp.name)/'vr4k.mp4'
            ok_gen=False
            if v3ff:
                # 4096x2048 (2:1, >=4000 wide, the auto-detect condition); 3 s at 5 fps keeps generation cheap.
                r=subprocess.run([str(v3ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc=duration=3:size=4096x2048:rate=5',
                    '-pix_fmt','yuv420p',str(v3clip)],stdout=log,stderr=log,timeout=30)
                ok_gen=r.returncode==0 and v3clip.is_file() and v3clip.stat().st_size>0
            if not ok_gen:
                note_skip('v3-camera-optin','4096x2048 clip could not be generated')
            else:
                v3trace=Path.home()/'Library/Application Support/gor/geom_trace.log'
                v3mark=v3trace.stat().st_size if v3trace.exists() else 0
                v3proc=subprocess.Popen([str(binary),'--gor-no-activate',str(v3clip)],stdout=log,stderr=log,env=dict(os.environ,GOR_TRACE_GEOM='1',GOR_VR_TEST_NO_CAMERA='1'))
                v3gp=v3proc.pid;v3gs=identity(v3gp);owned.append((v3gp,v3gs))
                def v3_lines():
                    try:
                        with open(v3trace,'rb') as fh:
                            fh.seek(v3mark);txt=fh.read().decode('utf-8','replace').splitlines()
                    except FileNotFoundError:return []
                    out=[]
                    for l in txt:
                        i=l.find('{"k":"vrCamera"')
                        if i>=0:
                            try:out.append(json.loads(l[i:]))
                            except ValueError:pass
                    return out
                vr_on=wait(lambda:[x for x in v3_lines() if x.get('vr') is True],20)
                if not vr_on:
                    note(False,'v3-camera-optin','VR auto-detect never enabled VR for the 4096x2048 file (no vrCamera vr=true trace) lines=%d'%len(v3_lines()))
                else:
                    n0=len(v3_lines())
                    wait(lambda:len([x for x in v3_lines() if x.get('why')=='tick'])>=4,12)
                    lines=v3_lines()
                    ticks=[x for x in lines if x.get('why')=='tick' and x.get('vr') is True]
                    bad=[x for x in lines if x.get('head') or x.get('camActive') or x.get('vrOwned',0)>0]
                    events=[x for x in lines if str(x.get('why','')).startswith('session-')]
                    running=[x for x in lines if x.get('sessionRunning') or x.get('sessionRequested') or str(x.get('why','')).startswith('session-consumer-start')]
                    unexplained=[x for x in running if not x.get('ambient') and x.get('vrOwned',0)<=0]
                    ambient_run=[x for x in running if x.get('ambient')]
                    detail='vr-enabled=1 lines=%d ticks=%d session-events=%d vr-owned-or-head=%s session-seen=%s ambient-held=%s unexplained=%s last=%s'%(
                        len(lines),len(ticks),len(events),bool(bad),bool(running),bool(ambient_run),bool(unexplained),json.dumps(lines[-1],sort_keys=True))
                    if bad or unexplained:note(False,'v3-camera-optin',detail)
                    elif len(ticks)<4:note_skip('v3-camera-optin','too few post-entry ticks to show absence over time '+detail)
                    elif ambient_run:note_skip('v3-camera-optin','VR side clean but the ambient-dimming consumer held the capture session; no-capture not demonstrated '+detail)
                    else:note(True,'v3-camera-optin',detail)
        finally:
            if v3gp is not None:
                subprocess.run(['/usr/bin/osascript','-e',quit_script],stdout=log,stderr=log)
                wait(lambda:not alive(v3gp),5)
                stop_owned(v3gp,v3gs)
            v3tmp.cleanup()
        if gor_pids():
            raise RuntimeError("prior test gor remains before l5/l6")
        # r2: gor's real crop path (gor 514), replayed with the exact filter form
        # from GorFit.swift (label + arg + add/remove JSON shapes), asserting the
        # app's own confirms() contract on video-out-params (w/h, crop-w/crop-h or
        # dw/dh at the cropped size), then full restore after remove.
        def gorfit_crop_templates():
            src=(root/'Sources/gor/GorFit.swift').read_text()
            return ('static let label = "gorcrop"' in src
                and 'crop=w=\\(w):h=\\(h):x=\\(x):y=\\(y)' in src
                and 'static func addCommand' in src
                and 'static func removeCommand' in src
                and '@\\(label):\\(f.arg)' in src)
        def ipc_cmd(sock_path,*args,timeout=2.0):
            return ipc_roundtrip(sock_path,json.dumps({'command':list(args)}),timeout)
        r2sock=str(root/'.gor-r2-crop.sock')
        try:os.unlink(r2sock)
        except FileNotFoundError:pass
        if not gorfit_crop_templates():
            note(False,'r2-crop-real','GorFit.swift crop templates not found in source')
        else:
            r2mpv=subprocess.Popen([str(mpv),'--no-config','--vo=null','--ao=null','--idle=yes','--force-window=no','--pause','--loop-file=inf','--keep-open=yes','--input-ipc-server='+r2sock,str(clip)],stdout=log,stderr=log)
            r2st=identity(r2mpv.pid);owned.append((r2mpv.pid,r2st))
            try:
                if not wait(lambda:os.path.exists(r2sock),10):
                    note(False,'r2-crop-real','vendor mpv ipc socket never appeared')
                else:
                    ok=True;detail=[]
                    end=time.monotonic()+8;vw=vh=0
                    while time.monotonic()<end:
                        dw=ipc_cmd(r2sock,'get_property','dwidth').get('data')
                        dh=ipc_cmd(r2sock,'get_property','dheight').get('data')
                        if isinstance(dw,(int,float)) and isinstance(dh,(int,float)) and dw>0 and dh>0:
                            vw,vh=int(dw),int(dh);break
                        time.sleep(.1)
                    if not vw:ok=False;detail.append('no-decode')
                    # even-aligned center-half crop, the same planner output class
                    cw,ch=vw//2 - (vw//2)%2, vh//2 - (vh//2)%2
                    cx,cy=(vw-cw)//2 - ((vw-cw)//2)%2,(vh-ch)//2 - ((vh-ch)//2)%2
                    filt='crop=w=%d:h=%d:x=%d:y=%d'%(cw,ch,cx,cy)
                    r=ipc_cmd(r2sock,'vf','add','@gorcrop:'+filt)
                    ok=ok and r.get('error')=='success'
                    # app confirms() contract: any of w/h, crop-w/crop-h, dw/dh at the cropped size
                    confirmed=False;seen={}
                    end=time.monotonic()+4
                    while time.monotonic()<end and not confirmed:
                        p=ipc_cmd(r2sock,'get_property','video-out-params').get('data') or {}
                        dw=ipc_cmd(r2sock,'get_property','dwidth').get('data');dh=ipc_cmd(r2sock,'get_property','dheight').get('data')
                        seen={'w':p.get('w'),'h':p.get('h'),'cw':p.get('crop-w'),'ch':p.get('crop-h'),'dw':dw,'dh':dh}
                        confirmed=(p.get('w')==cw and p.get('h')==ch) or (p.get('crop-w')==cw and p.get('crop-h')==ch) or (dw==cw and dh==ch)
                        if not confirmed:time.sleep(.15)
                    detail.append('crop%dx%d+%d+%d w=%s h=%s cw=%s ch=%s dw=%s dh=%s'%(cw,ch,cx,cy,seen.get('w'),seen.get('h'),seen.get('cw'),seen.get('ch'),seen.get('dw'),seen.get('dh')))
                    ok=ok and confirmed
                    r=ipc_cmd(r2sock,'vf','remove','@gorcrop')
                    ok=ok and r.get('error')=='success'
                    restored=False
                    end=time.monotonic()+4
                    while time.monotonic()<end and not restored:
                        p=ipc_cmd(r2sock,'get_property','video-out-params').get('data') or {}
                        restored=(p.get('w')==vw and p.get('h')==vh)
                        if not restored:time.sleep(.15)
                    detail.append('restore=%s'%restored)
                    ok=ok and restored
                    note(ok,'r2-crop-real',' '.join(detail))
            finally:
                stop_owned(r2mpv.pid,r2st)
                try:os.unlink(r2sock)
                except FileNotFoundError:pass

        # r4: photon-hud.lua fold guard, real lua inside the vendor mpv. The
        # harness extracts split_lines + apply_fold VERBATIM from the shipped
        # script and runs them with a fold state whose revealed/known count
        # exceeds the real body length - the exact caller mismatch the P4 guard
        # fixes. Negative control: the same bytes with the guard line textually
        # removed must crash (nil concat), proving the guard does the work.
        hudsrc=(root/'Resources/vendor/mpv/scripts/photon-hud.lua').read_text()
        if 'if totalLines > #lines then totalLines = #lines end' not in hudsrc:
            note(False,'r4-fold-guard','guard line absent from shipped photon-hud.lua')
        else:
            harness_dir=Path(tempfile.mkdtemp(prefix='gor-r4-fold.'))
            harness=harness_dir/'harness.lua'
            harness.write_text(LUA_FOLD_HARNESS)
            r=subprocess.run([str(mpv),'--no-config','--vo=null','--ao=null','--idle=yes','--script='+str(harness)],capture_output=True,text=True,timeout=30,env=dict(os.environ,GOR_FOLD_SRC=str(root/'Resources/vendor/mpv/scripts/photon-hud.lua')))
            out=(r.stdout or '')+(r.stderr or '')
            m=re.search(r'FOLDGUARD new_ok=(\w+) old_ok=(\w+)',out)
            ok=bool(m) and m.group(1)=='true' and m.group(2)=='false'
            detail=out[out.find('FOLDGUARD'):].splitlines()[0] if 'FOLDGUARD' in out else ('no FOLDGUARD line rc=%s tail=%s'%(r.returncode,out[-160:]))
            note(ok,'r4-fold-guard',detail)
            shutil.rmtree(harness_dir,ignore_errors=True)

        # r1: the video menu's three rotate actions, replayed verbatim from
        # MenuActions.swift against the vendor mpv, with behavior readback.
        # video-rotate is the option; video-params/rotate is the actual picture
        # state after the reinit. Both must converge for an action to be real.
        # History (owner 5xx): mpv 0.41 `add` on video-rotate does not wrap - +90
        # from 270 clamps to 359 and -90 from 0 selects the "no" choice, so the
        # items looked dead. cycle-values wraps and self-heals; this leg replays
        # the exact menu strings and catches a revert.
        rj=[menu_rotate_json(sel) for sel in ['menuRotateCW','menuRotateCCW','menuRotateReset']]
        if any(v is None for v in rj):
            note(False,'r1-rotate-menu','rotate JSON not found in MenuActions.swift')
        else:
            rsock=str(root/'.gor-r1-rotate.sock')
            try:os.unlink(rsock)
            except FileNotFoundError:pass
            rmpv=subprocess.Popen([str(mpv),'--no-config','--vo=null','--ao=null','--idle=yes','--force-window=no','--pause','--loop-file=inf','--keep-open=yes','--input-ipc-server='+rsock,str(clip)],stdout=log,stderr=log)
            rst=identity(rmpv.pid);owned.append((rmpv.pid,rst))
            try:
                if not wait(lambda:os.path.exists(rsock),10):
                    note(False,'r1-rotate-menu','vendor mpv ipc socket never appeared')
                else:
                    def sendj(j):return ipc_roundtrip(rsock,j)
                    def cmdf(*a):return sendj(json.dumps({'command':list(a)}))
                    def wait_prop(name,want,seconds=4.0):
                        end=time.monotonic()+seconds;last=None
                        while time.monotonic()<end:
                            last=cmdf('get_property',name).get('data')
                            if last==want:return True,last
                            time.sleep(.1)
                        return False,last
                    ok=True;detail=[]
                    up=False
                    end=time.monotonic()+8
                    while time.monotonic()<end:
                        dw=cmdf('get_property','dwidth').get('data')
                        if isinstance(dw,(int,float)) and dw>0:up=True;break
                        time.sleep(.1)
                    if not up:ok=False;detail.append('no-decode')
                    for want in [90,180,270,0]:
                        err=sendj(rj[0]).get('error')
                        g1,v1=wait_prop('video-rotate',want)
                        g2,v2=wait_prop('video-params/rotate',want)
                        detail.append('cw>%s/%s'%(v1,v2));ok=ok and err=='success' and g1 and g2
                    err=sendj(rj[1]).get('error')
                    g1,v1=wait_prop('video-rotate',270);g2,v2=wait_prop('video-params/rotate',270)
                    detail.append('ccw0>%s/%s'%(v1,v2));ok=ok and err=='success' and g1 and g2
                    err=sendj(rj[2]).get('error')
                    g1,v1=wait_prop('video-rotate',0);g2,v2=wait_prop('video-params/rotate',0)
                    detail.append('reset>%s/%s'%(v1,v2));ok=ok and err=='success' and g1 and g2
                    # negative control: poison to the stuck 359 state the old
                    # add-form could reach, then the menu CW action must recover.
                    cmdf('set_property','video-rotate',270);cmdf('add','video-rotate',90)
                    end=time.monotonic()+2;poisoned=None
                    while time.monotonic()<end:
                        poisoned=cmdf('get_property','video-rotate').get('data')
                        if poisoned==359:break
                        time.sleep(.05)
                    err=sendj(rj[0]).get('error')
                    g1,v1=wait_prop('video-rotate',90);g2,v2=wait_prop('video-params/rotate',90)
                    detail.append('poison359=%s recover>%s/%s'%(poisoned,v1,v2))
                    ok=ok and poisoned==359 and err=='success' and g1 and g2
                    cmdf('set_property','video-rotate',0)
                    note(ok,'r1-rotate-menu',' '.join(detail))
            finally:
                stop_owned(rmpv.pid,rst)
                try:os.unlink(rsock)
                except FileNotFoundError:pass
    else:
        for name in ['av-sync-vr', 'av-sync-vr-app', 'av-sync-vr-app-unmatched-breach', 'ipd-vs-dial', 'r1-rotate-menu', 'r2-crop-real', 'r3-hud-baseline', 'r3-hud-scroll', 'r3-hud-zoom', 'r4-fold-guard', 'v1-fill-round', 'v1-fill-rows-literal', 'v1-geometry-vs-pre-change', 'v1-legacy-rect-y-literal', 'v1-rect-y-fill-bounds', 'v1-shader-pixels', 'v2-replicator', 'v3-camera-optin', 'vr-app-cleanup', 'vr-app-filter', 'vr-app-guards', 'vr-app-pref', 'vr-controls-pixel-custody', 'vr-controls-visible-both-eyes', 'vr-distance-clamp', 'vr-distance-native-camera', 'vr-distance-native-display', 'vr-ipd-native-persistence-reentry', 'vr-param-default', 'vr-sync-source-guard']:
            note_skip(name,'disabled in automatic lifecycle-only update; run ./build.sh --selftest-full on demand; no feature PASS claimed')
    # l5: a detached VENDOR mpv (ppid 1) is swept within 1 s of gor launch.
    orphan=spawn_detached([str(mpv),'--no-config','--idle=yes','--force-window=no'])
    ost=identity(orphan)
    owned.append((orphan,ost))
    if not wait(lambda:ps(orphan,'ppid')=='1' and alive(orphan),2):
        note(False,'l5','setup invalid: detached vendor mpv not reparented');stop_owned(orphan,ost)
    else:
        t0=time.monotonic_ns()
        r=subprocess.run(['/usr/bin/open','-g','-n',str(app),'--args','--gor-no-activate',str(clip)],stdout=log,stderr=log)
        gp=wait(lambda: next(iter(gor_pids()),None),10) if r.returncode==0 else None
        if not gp:
            note(False,'l5','gor did not launch');stop_owned(orphan,ost)
        else:
            owned.append((gp,identity(gp)))
            gone=wait(lambda:not alive(orphan),1)
            ms=(time.monotonic_ns()-t0)//1_000_000
            note(bool(gone) and ms<=1000,'l5',('orphan vendor mpv swept in %d ms'%ms) if gone else 'orphan vendor mpv alive after 1000 ms')
            stop_owned(orphan,ost)
            quit_instance(gp)
    if os.environ.get('GOR_LIFETIME_FULL')=='1':
        # l6: self-contained same-name control. No vendor/dylib copying.
        l6tmp=tempfile.TemporaryDirectory(prefix='gor-l6.')
        l6dir=Path(l6tmp.name);l6mpv=l6dir/'mpv'
        stage='l6-copy-sleep-bytes'
        shutil.copyfile('/bin/sleep',l6mpv)
        stage='l6-set-own-copy-executable'
        l6mpv.chmod(0o755)
        stage='l6-probe-sleep-exec'
        exec_permission_error=None
        try:
            probe=subprocess.run([str(l6mpv),'0'],capture_output=True,timeout=3)
            if probe.returncode:raise RuntimeError('copied sleep startup rc='+str(probe.returncode))
        except PermissionError as error:
            exec_permission_error=error
            detail='INFO l6 call=exec path='+str(l6mpv)+' errno='+str(error.errno)+' traceback='+str(traceback.extract_tb(error.__traceback__)[-1].line)
            print(detail,flush=True)
            with results.open('a') as f:f.write(detail+'\n')
            log.write((''.join(traceback.format_exception(type(error),error,error.__traceback__))[-8192:]).encode())
        stage='l6-detached-start'
        foreign=spawn_detached([str(l6mpv),'900']) if exec_permission_error is None else -1
        stage='l6-baseline'
        fst=identity(foreign) if foreign>0 else (None,None)
        if foreign>0:owned.append((foreign,fst))
        setup6=foreign>0 and bool(wait(lambda:ps(foreign,'ppid')=='1' and alive(foreign),2))
        setup6=setup6 and all(fst) and fst[1]==str(l6mpv) and identity(foreign)==fst
        # Only an observed exec permission failure permits the owner's alternate
        # standalone vendor binary. A baseline mismatch is not that evidence.
        if not setup6 and exec_permission_error is not None:
            print('INFO l6 call=exec path='+str(l6mpv)+' errno=permission-denied; trying authorized standalone alternate',flush=True)
            for name in ['gifsicle','yt-dlp']:
                candidate=next((p for p in (root/'Resources/vendor').rglob(name) if p.is_file() and os.access(p,os.X_OK)),None)
                if candidate is None:continue
                if foreign>0:stop_owned(foreign,fst)
                shutil.copyfile(candidate,l6mpv);l6mpv.chmod(0o755)
                try:probe=subprocess.run([str(l6mpv),'--version'],capture_output=True,timeout=3)
                except (OSError,subprocess.TimeoutExpired):continue
                if probe.returncode:continue
                # FIFO supplies no bytes and keeps its writer open. gifsicle
                # waits for image stdin; yt-dlp waits for a batch-file line.
                fifo=l6dir/'idle-input';os.mkfifo(fifo)
                alternate_input_fd=os.open(fifo,os.O_RDWR|os.O_NONBLOCK)
                args=[str(l6mpv)] if name=='gifsicle' else [str(l6mpv),'--batch-file',str(fifo)]
                foreign=spawn_detached(args,fifo)
                time.sleep(.1)
                fst=identity(foreign);owned.append((foreign,fst))
                setup6=bool(wait(lambda:ps(foreign,'ppid')=='1' and alive(foreign),2)) and all(fst) and fst[1]==str(l6mpv)
                if setup6:break
                os.close(alternate_input_fd);alternate_input_fd=None;fifo.unlink()
        if not setup6:
            note(False,'l6','setup invalid: standalone control named mpv not alive with exact path and ppid1')
        else:
            stage='l6-gor-launch'
            r=subprocess.run(['/usr/bin/open','-g','-n',str(app),'--args','--gor-no-activate',str(clip)],stdout=log,stderr=log)
            gp=wait(lambda: next(iter(gor_pids()),None),10) if r.returncode==0 else None
            if not gp:note(False,'l6','gor did not launch')
            else:
                owned.append((gp,identity(gp)));time.sleep(2.0)
                ok=alive(foreign) and identity(foreign)==fst and ps(foreign,'ppid')=='1'
                note(ok,'l6','foreign same-name standalone control survives 2s after launch' if ok else 'foreign same-name control exited or identity changed after gor launch')
                quit_instance(gp)
        if foreign>0:stop_owned(foreign,fst)
        l6tmp.cleanup()
    else:
        note_skip('l6','not run: full lifecycle mode disabled (GOR_LIFETIME_FULL!=1)')
except Exception as error:
    frames=traceback.extract_tb(error.__traceback__)
    call=frames[-1] if frames else None
    detail='aborted stage='+stage+' category='+type(error).__name__+' errno='+str(getattr(error,'errno',None))+' path='+str(getattr(error,'filename',None))
    if call:detail+=' call='+str(call.line)+' line='+str(call.lineno)
    note(False,'lifecycle-harness',detail)
    log.write((''.join(traceback.format_exception(type(error),error,error.__traceback__))[-8192:]).encode())
finally:
    for helper in quit_helpers:
        if helper.poll() is None:
            helper.kill();helper.wait()
    for ef in quit_stderr:ef.close()
    if alternate_input_fd is not None:os.close(alternate_input_fd)
    for pid,stamp in owned:stop_owned(pid,stamp)
    if 'l6tmp' in locals():l6tmp.cleanup()
    if identity(negative.pid)==negative_stamp:negative.terminate()
    negative.wait()
    cliptmp.cleanup();log.close()
os.sys.exit(0 if failed==0 else 1)
PY
