#!/bin/bash
# gor-heat-kit v2: ONE heat measurement on this Mac.
# Part 1: standalone vendored mpv, idle, throw-away config copies (isolation).
# Part 2: the REAL gor.app launched with a REAL film (argument, else the newest
# film found in Movies/Downloads/Desktop): playing, HUD/mouse moving, paused, seeking;
# samples the gor main process and its mpv child (ps cputime, ps -M threads,
# /usr/bin/sample 3 s, CoreText/CATextLayer share of the main thread).
# Never edits the app, its config, defaults or logs (appends photon lines to /tmp/gor_diag.log).
# Quit gor first. About 7 minutes. Rollback: delete this file.
# Usage: bash tools/gor-heat-kit.sh [/path/to/film]
export GOR_LOG_PATH_TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${GOR_KIT_PYTHON:-/usr/bin/python3}" - "$@" <<'PY'
import glob, json, os, pty, re, shutil, signal, socket, subprocess, sys, tempfile, threading, time
HOME = os.environ.get('GOR_KIT_HOME', os.path.expanduser('~'))
F = float(os.environ.get('GOR_KIT_SCALE', '1'))      # test scale only
sys.path.insert(0,os.environ['GOR_LOG_PATH_TOOLS'])
from session_log_paths import resolve
DIAG = os.environ.get('GOR_KIT_DIAG', str(resolve('/tmp/gor_diag.log')))
MSAMPLE = os.environ.get('GOR_KIT_MPV_SAMPLE', str(resolve('/tmp/gor_mpv_sample.txt')))
REPORT = os.environ.get('GOR_KIT_REPORT', os.path.join(HOME, 'Downloads', 'gor-heat-report.txt'))
def sh(args, t=20):
    try: return subprocess.run(args, capture_output=True, text=True, timeout=t).stdout
    except Exception: return ''
def running():
    out = sh(['/usr/bin/pgrep', '-fl', 'mpv/bin/mpv']) + sh(['/usr/bin/pgrep', '-x', 'gor'])
    return [l for l in out.splitlines() if l.strip() and 'gor-heat-kit' not in l]
if running() and os.environ.get('GOR_KIT_FORCE') != '1':
    print('kit: gor or its mpv is running; quit gor first, then run again. Nothing was measured.'); sys.exit(2)
def find_mpv():
    c = [os.environ.get('GOR_MPV', '')]
    try:
        root = open(os.path.join(HOME, 'Library/Application Support/gor/dev-source-root.txt')).readline().strip()
        c.append(os.path.join(root, 'Resources/vendor/mpv/bin/mpv'))
    except OSError: pass
    c += ['/Applications/gor.app/Contents/Resources/vendor/mpv/bin/mpv', os.path.join(HOME, 'Applications/gor.app/Contents/Resources/vendor/mpv/bin/mpv'),
          os.path.join(HOME, 'Downloads/gor/Resources/vendor/mpv/bin/mpv')]
    c += glob.glob('/Applications/*.app/Contents/Resources/vendor/mpv/bin/mpv')
    for p in c:
        if p and os.path.isfile(p) and os.access(p, os.X_OK): return p
MPV = find_mpv()
if not MPV:
    print('kit: vendored mpv not found (set GOR_MPV=/path/to/mpv). Nothing was measured.'); sys.exit(3)
INST = os.path.join(HOME, 'Library/Application Support/gor/mpv')
if not os.path.isdir(INST): INST = os.path.dirname(os.path.dirname(MPV))
TMP = tempfile.mkdtemp(prefix='gor-heat-kit-')
def cpu(pid):
    s = sh(['/bin/ps', '-o', 'time=', '-p', str(pid)]).strip()
    if not s: return None
    d = 0
    if '-' in s: d, s = s.split('-', 1); d = int(d)
    parts = [float(x) for x in s.split(':')]
    sec = 0.0
    for x in parts: sec = sec * 60 + x
    return d * 86400 + sec
def rss(pid):
    s = sh(['/bin/ps', '-o', 'rss=', '-p', str(pid)]).strip()
    return int(s) // 1024 if s.isdigit() else None
def threads(pid):
    rows = []
    for l in sh(['/bin/ps', '-M', '-p', str(pid)]).splitlines()[1:]:
        m = re.search(r'\b(\d+\.\d)\b', l)
        if m: rows.append((float(m.group(1)), re.sub(r'\s+', ' ', l.strip())[:110]))
    rows.sort(reverse=True)
    return len(rows), rows[:6]
def parse_sample(txt):
    out, n = [], 0
    for l in txt.splitlines():
        if re.match(r'^\s*\d+ Thread_\d+', l) and n < 8: out.append('thread ' + re.sub(r'\s+', ' ', l.strip())[:130]); n += 1
    i = txt.find('Sort by top of stack')
    if i >= 0: out += ['top ' + re.sub(r'\s+', ' ', l.strip())[:120] for l in txt[i:].splitlines()[1:11] if l.strip()]
    return out
def own_sample(pid):
    f = os.path.join(TMP, 'own-sample.txt')
    sh(['/usr/bin/sample', str(pid), '3', '-file', f], 30)
    try: return parse_sample(open(f, errors='replace').read())
    except OSError: return ['sample unavailable']
IPC_N = [0]
def ipc(path, cmd):
    """request_id-matched mpv ipc call; events on the socket are skipped; 2 tries, 6 s each (v1 lost props to a 2 s timeout)"""
    for _ in range(2):
        IPC_N[0] += 1; rid = IPC_N[0]
        try:
            s = socket.socket(socket.AF_UNIX); s.settimeout(6); s.connect(path)
            s.sendall((json.dumps({'command': cmd, 'request_id': rid}) + '\n').encode()); buf = b''
            while True:
                for l in buf.split(b'\n'):
                    try: o = json.loads(l)
                    except Exception: continue
                    if o.get('request_id') == rid or (o.get('error') is not None and 'request_id' not in o and 'event' not in o):
                        s.close(); return o.get('data') if o.get('error') == 'success' else None
                buf += s.recv(65536)
        except Exception: continue
    return None
def diag_size():
    try: return os.path.getsize(DIAG)
    except OSError: return 0
def diag_since(off):
    try:
        with open(DIAG, 'rb') as f: f.seek(off); return f.read().decode('utf-8', 'replace').splitlines()
    except OSError: return []
COMMON = ['--idle=yes', '--force-window=yes', '--keep-open=yes', '--no-native-fs', '--no-border', '--no-osc', '--osd-level=0',
          '--geometry=+50%+50%', '--autofit=40%x90%', '--macos-app-activation-policy=prohibited', '--no-terminal', '--audio-wait-open=0.5']
def mkcfg(name, conf, lua, full=False):
    d = os.path.join(TMP, name); os.makedirs(d if full else os.path.join(d, 'scripts'))
    if full:
        for e in os.listdir(INST):
            if e in ('shader', 'cache', 'shaders'): continue
            s = os.path.join(INST, e)
            (shutil.copytree if os.path.isdir(s) else shutil.copy)(s, os.path.join(d, e)) if not os.path.exists(os.path.join(d, e)) else None
        return d
    if conf and os.path.isfile(os.path.join(INST, 'mpv.conf')): shutil.copy(os.path.join(INST, 'mpv.conf'), d)
    for n in lua:
        s = os.path.join(INST, 'scripts', n)
        if os.path.isfile(s): shutil.copy(s, os.path.join(d, 'scripts', n))
    if lua and os.path.isdir(os.path.join(INST, 'script-opts')): shutil.copytree(os.path.join(INST, 'script-opts'), os.path.join(d, 'script-opts'))
    return d
def stage(name, cfg, win_end, total, play=None, photon=False):
    r = {'name': name}; ipcp = os.path.join(TMP, name + '.sock')
    args = [MPV] + (['--no-config'] if cfg is None else ['--config-dir=' + cfg]) + COMMON + ([] if play else ['--pause']) + ['--input-ipc-server=' + ipcp]
    if photon and cfg:
        args += ['--script-opts-add=photon-scriptdir=' + cfg + '/scripts', '--script-opts-add=photon-menu-enabled=true', '--script-opts-add=gor-diag=true']
    if play: args.append(play)
    off = diag_size(); t0 = time.time()
    try: p = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError as e: r['error'] = 'spawn failed %s' % e; return r
    try:
        time.sleep(5 * F)
        if p.poll() is not None: r['error'] = 'mpv exited early rc=%s' % p.returncode; return r
        c1, w1 = cpu(p.pid), time.time()
        time.sleep(max(0, win_end * F - (time.time() - t0)))
        c2, w2 = cpu(p.pid), time.time()
        if c1 is not None and c2 is not None and w2 > w1: r['cpu_pct'] = round(100 * (c2 - c1) / (w2 - w1), 1)
        r['window_s'] = round(w2 - w1, 1); r['rss_mb'] = rss(p.pid)
        r['thread_count'], r['hot_threads'] = threads(p.pid)
        if play:
            for k in ['time-pos', 'estimated-vf-fps', 'frame-drop-count', 'vo-delayed-frame-count', 'mistimed-frame-count', 'hwdec-current']:
                r[k] = ipc(ipcp, ['get_property', k])
        if not photon or total <= win_end: r['sample'] = own_sample(p.pid)
        time.sleep(max(0, total * F - (time.time() - t0)))
        if photon:
            try:
                if os.path.getmtime(MSAMPLE) >= t0: r['photon_sample'] = parse_sample(open(MSAMPLE, errors='replace').read())
            except OSError: pass
            if 'photon_sample' not in r: r['photon_sample'] = ['COST.sample_mpv wrote no file in this stage']; r['sample'] = own_sample(p.pid)
            lines = diag_since(off); wins = n = 0.0; ex = []
            for l in lines:
                m = re.search(r'photon-cost: win=([\d.]+)s', l)
                if m:
                    wins += float(m.group(1)); rb = re.search(r'readback\{([^}]*)\}', l)
                    n += sum(int(x) for x in re.findall(r'\bn=(\d+)', rb.group(1))) if rb else 0
                    ex = [re.sub(r'\s+', ' ', l)[:300]]
                elif 'mpv-sample[' in l and 'top ' in l and len(ex) < 4: ex.append(re.sub(r'\s+', ' ', l)[:160])
            r['photon_windows_s'] = round(wins, 1); r['probes_total'] = int(n); r['probes_per_s'] = round(n / wins, 3) if wins else None
            r['photon_last'] = ex[:1]
    finally:
        try: os.killpg(p.pid, signal.SIGTERM); p.wait(timeout=4)
        except Exception:
            try: os.killpg(p.pid, signal.SIGKILL)
            except Exception: pass
    return r
def find_app():
    for p in [os.environ.get('GOR_APP', ''), os.path.join(HOME, 'Downloads/gor/gor.app'), '/Applications/gor.app', os.path.join(HOME, 'Applications/gor.app')]:
        b = os.path.join(p, 'Contents/MacOS/gor')
        if p and os.path.isfile(b) and os.access(b, os.X_OK): return p, b
    return None, None
def pick_film():
    if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]): return sys.argv[1]
    c = []
    for d in ['Movies', 'Downloads', 'Desktop']:
        for pat in ['*', '*/*']:
            for f in glob.glob(os.path.join(HOME, d, pat)):
                if f.lower().endswith(('.mkv', '.mp4', '.mov', '.m4v', '.avi', '.webm')) and os.path.isfile(f) and os.path.getsize(f) > 20e6: c.append((os.path.getmtime(f), f))
    return max(c)[1] if c else None
def children(pid):
    return [int(x) for x in sh(['/usr/bin/pgrep', '-P', str(pid)]).split()]
def main_share(txt):
    """share of the gor main-thread samples whose stacks contain text layout symbols"""
    blocks = re.split(r'\n(?=\s*\d+ Thread_\d+)', txt); best = None
    for b in blocks:
        h = b.splitlines()[0] if b.strip() else ''
        if 'main-thread' in h or 'com.apple.main' in h or 'Main Thread' in h:
            m = re.match(r'\s*(\d+) Thread', h); tot = int(m.group(1)) if m else 0
            rx = re.compile(r'^\s*[+!:| ]*(\d+) .*(CATextLayer|CTFramesetter|CTTypesetter|CTLine|CTRun|TextLayout|NSLayoutManager|NSTextStorage|CTFontCreate)')
            hit = max([int(x.group(1)) for x in map(rx.match, b.splitlines()) if x] or [0])
            names = sorted({x.group(2) for x in map(rx.match, b.splitlines()) if x})
            best = (tot, hit, names)
    return best
IDLE_TOP = ('__workq_kernreturn', 'mach_msg', 'semaphore_wait', 'read ', 'poll ', '__psynch_cvwait', 'kevent', '__ulock_wait', '_pthread_wqthread', 'select ')
KEYS = ('CGWindowListCreateImage', 'CGSHWCaptureWindowList', 'VNImageRequestHandler', 'VNDetect', 'CATextLayer', 'CTTypesetter', 'CTFramesetter', 'CTFontCreate', 'CoreML', 'MLModel', 'E5Runner', 'ANE', 'AVCapture', 'CVMetal', 'MTLCommandBuffer', 'screenshot', 'NSImage', 'CIContext', 'CA::Transaction::commit', 'CA::Layer::display_if_needed', 'layoutSubviews', 'NSTextView', 'NSLayoutManager', 'AXUIElement')
def hot_frames(txt, label):
    """named-code evidence: busiest frames inside gor's own binary (symbol + File.swift:line) and busiest keyword frames, per thread name"""
    out = []; thread = '?'; best = {}; kb = {}
    for l in txt.splitlines():
        m = re.match(r'^\s*(\d+) (Thread_\d+)\s*(.*)', l)
        if m: thread = (m.group(3) or 'unnamed')[:34]; continue
        m = re.match(r'^[ +!:|]*(\d+) (.+?)\s+\(in ([^)]+)\)(.*)$', l)
        if not m: continue
        c, sym, mod, rest = int(m.group(1)), re.sub(r'\s+', ' ', m.group(2))[:60], m.group(3), m.group(4)
        fl = re.search(r'([A-Za-z0-9_+]+\.(?:swift|m|mm|c|cpp)):(\d+)', rest)
        if mod == 'gor' and fl and c >= 8:
            k = (sym, fl.group(1) + ':' + fl.group(2)); 
            if c > best.get(k, (0, ''))[0]: best[k] = (c, thread)
        for kw in KEYS:
            if kw in sym and c >= 8:
                if c > kb.get(kw, (0, ''))[0]: kb[kw] = (c, thread)
    for (sym, fl), (c, th) in sorted(best.items(), key=lambda x: -x[1][0])[:12]: out.append('gorframe %d %s %s [%s]' % (c, sym, fl, th))
    for kw, (c, th) in sorted(kb.items(), key=lambda x: -x[1][0])[:8]: out.append('keyframe %d %s [%s]' % (c, kw, th))
    return out
def sample_proc(pid, label, secs=3):
    f = os.path.join(TMP, 'real-%s-%s.txt' % (label, pid)); sh(['/usr/bin/sample', str(pid), str(secs), '-file', f], 40)
    try: txt = open(f, errors='replace').read()
    except OSError: return ['sample unavailable'], None
    top = [l for l in parse_sample(txt) if l.startswith('top ') and not any(x in l for x in IDLE_TOP)]
    return hot_frames(txt, label) + [l for l in parse_sample(txt) if l.startswith('thread ')][:5] + top[:6], main_share(txt)
def mouse_wiggle(secs):
    try:
        import ctypes
        cg = ctypes.CDLL('/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices')
        cg.CGEventCreateMouseEvent.restype = ctypes.c_void_p
    except Exception: return False
    class P(ctypes.Structure): _fields_ = [('x', ctypes.c_double), ('y', ctypes.c_double)]
    try:
        cg.CGEventCreateMouseEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, P, ctypes.c_uint32]; cg.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
        import math
        t0 = time.time()
        while time.time() - t0 < secs:
            a = (time.time() - t0) * 2.5
            e = cg.CGEventCreateMouseEvent(None, 5, P(900 + 300 * math.cos(a), 500 + 200 * math.sin(a)), 0); cg.CGEventPost(0, e); time.sleep(1 / 30)
        return True
    except Exception: return False
def window(pids, secs, extra=None):
    c1 = {p: cpu(p) for p in pids}; w1 = time.time()
    if extra: extra()
    else: time.sleep(secs)
    c2 = {p: cpu(p) for p in pids}; w2 = time.time()
    return {p: (round(100 * (c2[p] - c1[p]) / (w2 - w1), 1) if c1[p] is not None and c2[p] is not None else None) for p in pids}, round(w2 - w1, 1)
def real_part(film):
    app, binp = find_app(); R = {'film': '%s %.0fMB' % (os.path.splitext(film)[1], os.path.getsize(film) / 1e6)}
    if not binp: R['error'] = 'gor.app not found (set GOR_APP)'; return R
    off = diag_size(); t0 = time.time()
    mfd, sfd = pty.openpty()      # a tty keeps gor's print() line-buffered, so the [VB][next] lines arrive while it runs
    g = subprocess.Popen([binp, film], stdin=subprocess.DEVNULL, stdout=sfd, stderr=sfd, start_new_session=True); os.close(sfd)
    OUT = []
    def drain():
        buf = b''
        while True:
            try: d = os.read(mfd, 65536)
            except OSError: return
            if not d: return
            buf += d
            while b'\n' in buf:
                l, buf = buf.split(b'\n', 1); OUT.append((time.time(), l.decode('utf-8', 'replace')))
    threading.Thread(target=drain, daemon=True).start()
    R['prefs'] = [l[:100] for l in sh(['/usr/bin/defaults', 'read', 'com.gokcebalkan.gor']).splitlines() if re.search(r'sub|face|heat|blink|vr|axis|govern', l, re.I)][:20]
    try:
        ipcp = os.environ.get('GOR_KIT_IPC') or (os.environ.get('TMPDIR', '/tmp').rstrip('/') + '/pp-%d.sock' % g.pid)
        mpvp = None
        tw = time.time()
        while time.time() - tw < 40:
            time.sleep(min(1.0, max(0.2, F)))
            if g.poll() is not None: R['error'] = 'gor exited early rc=%s' % g.returncode; return R
            k = children(g.pid)
            if k and os.path.exists(ipcp) and ipc(ipcp, ['get_property', 'pid']) is not None: mpvp = k[0]; break
        if not mpvp: R['error'] = 'gor started but its mpv/ipc never appeared'; return R
        R['pids'] = 'gor=%d mpv=%d' % (g.pid, mpvp)
        for k in ['video-params/w', 'video-params/h', 'video-codec', 'hwdec-current', 'container-fps']: R[k] = ipc(ipcp, ['get_property', k])
        R['hdr'] = ipc(ipcp, ['get_property', 'video-params/primaries'])
        pids = [g.pid, mpvp]; R['stages'] = []
        def st(name, setup, secs, sample=True, extra=None):
            s = {'name': name}
            if setup: setup()
            time.sleep(6 * F); o = diag_size(); ts0 = time.time()
            s['cpu'], s['win'] = window(pids, secs * F, extra)
            s['rss'] = {p: rss(p) for p in pids}
            vb = [l for t_, l in OUT if t_ >= ts0 and '[VB][next] tick=' in l]
            if not vb:
                allv = [(t_, l) for t_, l in OUT if '[VB][next] tick=' in l]
                if allv: vb = [allv[-1][1]]; s['vb_stale_s'] = round(time.time() - allv[-1][0])
            s['vb'] = vb[-1] if vb else None; s['vb_n'] = len(vb)
            s['threads'] = {p: threads(p) for p in pids}
            for k in ['time-pos', 'pause', 'estimated-vf-fps', 'frame-drop-count', 'vo-delayed-frame-count', 'mistimed-frame-count']: s[k] = ipc(ipcp, ['get_property', k])
            if sample:
                s['gor_sample'], s['gor_share'] = sample_proc(g.pid, name); s['mpv_sample'], _ = sample_proc(mpvp, name)
            wins = n = 0.0; last = ''
            for l in diag_since(o):
                m = re.search(r'photon-cost: win=([\d.]+)s', l)
                if m:
                    last = l
                    wins += float(m.group(1)); rb = re.search(r'readback\{([^}]*)\}', l); n += sum(int(x) for x in re.findall(r'\bn=(\d+)', rb.group(1))) if rb else 0
            s['probes_per_s'] = round(n / wins, 3) if wins else None
            for k, rk in (('estimated-vf-fps', 'estimated_vf_fps'), ('frame-drop-count', 'frame_drop_count'), ('vo-delayed-frame-count', 'vo_delayed'), ('mistimed-frame-count', 'mistimed')):
                m = re.search(rk + r'=(\S+)', last)
                if s.get(k) is None and m: s[k] = m.group(1) + ' (photon-cost)'
            R['stages'].append(s)
        play = lambda: ipc(ipcp, ['set_property', 'pause', False])
        st('real-1-playing', play, 25)
        st('real-2-playing-mouse-moving', None, 25, extra=lambda: R.__setitem__('mouse_ok', mouse_wiggle(25 * F)))
        st('real-3-paused', lambda: ipc(ipcp, ['set_property', 'pause', True]), 20)
        st('real-3b-paused-settled', lambda: time.sleep(15 * F), 20)
        def seeks():
            for i in range(6):
                ipc(ipcp, ['seek', [10, 60, 30, 80, 20, 50][i], 'absolute-percent', 'keyframes']); time.sleep(3 * F)
        st('real-4-seeking', play, 20, sample=False, extra=seeks)
        R['vb_total'] = len([1 for _, l in OUT if '[VB][next]' in l]); R['out_tail'] = [l[:160] for _, l in OUT[-3:]]
        R['photon_total_lines'] = len([l for l in diag_since(off) if 'photon-cost:' in l])
    finally:
        try: os.kill(g.pid, signal.SIGTERM); g.wait(timeout=12)
        except Exception:
            try: os.killpg(g.pid, signal.SIGKILL)
            except Exception: pass
        for k in children(g.pid): 
            try: os.kill(k, signal.SIGKILL)
            except Exception: pass
    return R
res = []
try:
    lua = ['photon.lua', 'photon-common.lua', 'photon-grain.lua', 'photon-hud.lua']
    cA = None; cB = mkcfg('b', True, []); cC = mkcfg('c', True, lua); cD = mkcfg('d', True, [], full=True)
    res.append(stage('idle-1-no-config', cA, 25, 28))
    res.append(stage('idle-2-shipped-mpv.conf', cB, 25, 28))
    res.append(stage('idle-3-conf+photon.lua', cC, 27, 45, photon=True))
    res.append(stage('idle-4-full-installed-config', cD, 27, 45, photon=True))
    film = pick_film(); REAL = real_part(film) if film else {'error': 'no film found in Movies/Downloads/Desktop; rerun with: bash tools/gor-heat-kit.sh /path/film'}
finally:
    shutil.rmtree(TMP, ignore_errors=True)
L = ['gor-heat-kit v1 %s' % time.strftime('%Y-%m-%d %H:%M:%S'),
     'mac %s | %s' % (sh(['/usr/bin/sw_vers', '-productVersion']).strip(), sh(['/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string']).strip()),
     'mpv %s' % (sh([MPV, '--version']).splitlines() or ['?'])[0][:80], 
     'cpu_pct = one core = 100%; window excludes the 5 s start; tool-based, not a thermal claim']
for r in res:
    if 'error' in r: L.append('[%s] ERROR %s' % (r['name'], r['error'])); continue
    L.append('[%s] cpu=%s%% win=%ss rss=%sMB threads=%s' % (r['name'], r.get('cpu_pct'), r.get('window_s'), r.get('rss_mb'), r.get('thread_count')))
    for c, t in r.get('hot_threads', [])[:4]: L.append('  hot %s' % t)
    if 'probes_per_s' in r: L.append('  photon probes=%s over %ss = %s/s' % (r['probes_total'], r['photon_windows_s'], r['probes_per_s']))
    for k in ['photon_sample', 'sample']:
        for l in r.get(k, [])[:14]: L.append('  %s: %s' % ('COST.sample_mpv' if k == 'photon_sample' else 'sample', l))
    for l in r.get('photon_last', []): L.append('  ' + l)
L.append('=== REAL gor.app + real film ===')
if 'error' in REAL: L.append('ERROR ' + REAL['error'])
else:
    L.append('film %s %sx%s codec=%s hwdec=%s fps=%s primaries=%s | %s' % (REAL['film'], REAL.get('video-params/w'), REAL.get('video-params/h'), REAL.get('video-codec'), REAL.get('hwdec-current'), REAL.get('container-fps'), REAL.get('hdr'), REAL.get('pids')))
    for s in REAL['stages']:
        gp, mp_ = list(s['cpu'])
        L.append('[%s] gor cpu=%s%% mpv cpu=%s%% win=%ss rss=%s/%sMB probes/s=%s pos=%s pause=%s fps=%s drop=%s delayed=%s mistimed=%s' % (s['name'], s['cpu'][gp], s['cpu'][mp_], s['win'], s['rss'][gp], s['rss'][mp_], s['probes_per_s'], s.get('time-pos'), s.get('pause'), s.get('estimated-vf-fps'), s.get('frame-drop-count'), s.get('vo-delayed-frame-count'), s.get('mistimed-frame-count')))
        for pid, tag in ((gp, 'gor'), (mp_, 'mpv')):
            n, rows = s['threads'][pid]; L.append('  %s threads=%s hot: %s' % (tag, n, ' | '.join(t[:70] for c, t in rows[:3])))
        if s.get('vb'):
            vbl = s['vb']; keys = ['main_load', 'proc_cpu_pct', 'governed', 'hidden_skips', 'mpv_cpu_pct', 'vision_frames']
            L.append('  VB10s%s ' % (' (STALE %ss, none in stage)' % s['vb_stale_s'] if s.get('vb_stale_s') else '') + ' '.join('%s=%s' % (k, (re.search(k + r'=(\S+)', vbl) or [0, '?'])[1]) for k in keys))
            for k in ['top_sites_10s', 'font_changed_over_same_10s']:
                m = re.search(k + r'=\[(.*?)\]( |$)', vbl); L.append('  %s=[%s]' % (k, (m.group(1) if m else '?')[:360]))
        else: L.append('  VB10s none in this stage (%s lines)' % s.get('vb_n'))
        if s.get('gor_share'): L.append('  gor MAIN thread samples=%s, with CATextLayer/CoreText layout stacks max=%s (%s%%) %s' % (s['gor_share'][0], s['gor_share'][1], round(100.0 * s['gor_share'][1] / s['gor_share'][0]) if s['gor_share'][0] else None, ','.join(s['gor_share'][2])))
        for l in s.get('gor_sample', [])[:26]: L.append('  gor sample: ' + l)
        for l in s.get('mpv_sample', [])[:6]: L.append('  mpv sample: ' + l)
    L.append('prefs(defaults): ' + ' ; '.join(REAL.get('prefs', [])) + ' | subPosRandom/faceAvoidance are not persisted: launch default random=false, so the 2 Hz Vision face pass guard is false')
    L.append('VB lines total=%s tail=%s' % (REAL.get('vb_total'), REAL.get('out_tail')))
    L.append('mouse wiggle posted: %s | photon-cost lines: %s' % (REAL.get('mouse_ok'), REAL.get('photon_total_lines')))
text = '\n'.join(L) + '\n'
try:
    os.makedirs(os.path.dirname(REPORT), exist_ok=True); open(REPORT, 'w').write(text)
except OSError: pass
print(text); print('report file:', REPORT)
if os.environ.get('GOR_KIT_NO_PUBLISH') != '1':
    side = os.path.join(HOME, 'Downloads/gor-repo-sync'); br = 'mac-source-sync-20261103'
    g = lambda *a: subprocess.run(['git', '-C', side] + list(a), capture_output=True, text=True)
    ok = os.path.isdir(os.path.join(side, '.git')) and g('symbolic-ref', '--quiet', '--short', 'HEAD').stdout.strip() == br \
        and g('diff', '--cached', '--quiet').returncode == 0 and os.access(os.path.join(side, 'sync.sh'), os.X_OK)
    if ok:
        g('-c', 'user.name=gor-update', '-c', 'user.email=gor-update@localhost', 'commit', '--allow-empty', '-qm', 'gor-heat-report %s\n%s' % (time.strftime('%y%m%d-%H%M%S'), text[:20000]))
        print('published as an empty result commit; gated push:'); subprocess.run([os.path.join(side, 'sync.sh'), 'push'])
    else: print('not published (sidecar missing, wrong branch or staged content); the report file above is the result')
PY
