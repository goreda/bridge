#!/usr/bin/env python3
"""gor-heat-kit run against a fake mpv: report shape, probes/sec parse, cleanup, no install mutation, refusal while running.
Linux-only fake; says nothing about macOS ps -M / sample output or real mpv heat."""
import hashlib, os, pathlib, stat, subprocess, sys, tempfile
root = pathlib.Path(__file__).resolve().parents[2]; kit = root / 'tools' / 'gor-heat-kit.sh'
fails = []
def check(n, c):
    print(('PASS ' if c else 'FAIL ') + n)
    if not c: fails.append(n)
t = pathlib.Path(tempfile.mkdtemp()); home = t / 'home'; inst = home / 'Library/Application Support/gor/mpv'
(inst / 'scripts').mkdir(parents=True); (inst / 'mpv.conf').write_text('vo=gpu-next\n'); (inst / 'scripts/photon.lua').write_text('-- x\n')
(inst / 'scripts/other.lua').write_text('-- y\n')
fake = t / 'mpv'
fake.write_text('''#!/usr/bin/env python3
import sys, time, os
a = sys.argv[1:]
if '--version' in a: print('mpv 0.41.0 fake'); sys.exit(0)
cfg = [x.split('=',1)[1] for x in a if x.startswith('--config-dir=')]
if cfg and os.path.exists(cfg[0] + '/scripts/photon.lua'):
    open(os.environ['GOR_KIT_DIAG'], 'a').write('12:00:00 photon-cost: win=10.0s x | readback{ring n=4 shot=1ms pix=1ms ; BK n=6 shot=1ms} | ffmpeg_spawns{}\\n')
    open(os.environ['GOR_KIT_MPV_SAMPLE'], 'w').write('Call graph:\\n    5 Thread_1  DispatchQueue_1\\nSort by top of stack, same collapsed\\n  mach_msg  (in libsystem) 5\\n')
time.sleep(60)
''')
fake.chmod(0o755)
film = t / 'film.mkv'; film.write_bytes(b'0' * 21_000_000)
(home / 'Movies').mkdir(); film.rename(home / 'Movies' / 'film.mkv'); film = home / 'Movies' / 'film.mkv'
app = t / 'gor.app/Contents/MacOS'; app.mkdir(parents=True); cmdlog = t / 'ipc-cmds.txt'; sock = t / 'pp.sock'
(app / 'gor').write_text('''#!/usr/bin/env python3
import os, socket, subprocess, sys, json, signal
log = os.environ['FAKE_CMDLOG']; sp = os.environ['GOR_KIT_IPC']
open(log, 'a').write('ARGV ' + ' '.join(sys.argv[1:]) + '\\n')
print('[VB][next] tick=1 fanouts=2 listeners=3 [heat] main_load=0.42 proc_cpu_pct=17 governed=false governor=on hidden_skips=9 top_sites_10s=[HUD:55,Music:3] font_changed_over_same_10s=[HUD 40/60] mpv_cpu_pct=1 vision_frames=0', flush=True)
child = subprocess.Popen(['sleep', '100'])
signal.signal(signal.SIGTERM, lambda *a: (child.kill(), os._exit(0)))
if os.path.exists(sp): os.unlink(sp)
s = socket.socket(socket.AF_UNIX); s.bind(sp); s.listen(5)
while True:
    c, _ = s.accept(); d = c.recv(4096).decode()
    open(log, 'a').write(d)
    try: k = json.loads(d)['command']
    except Exception: k = []
    v = {'pid': child.pid, 'video-params/w': 1920, 'video-params/h': 800, 'video-codec': 'hevc', 'hwdec-current': 'videotoolbox', 'time-pos': 12.5}.get(k[1] if len(k) > 1 else '', 0)
    c.sendall((json.dumps({'data': v, 'error': 'success'}) + '\\n').encode()); c.close()
'''); (app / 'gor').chmod(0o755)
def h(): return hashlib.sha256(b''.join(p.read_bytes() for p in sorted(inst.rglob('*')) if p.is_file())).hexdigest()
env = dict(os.environ, GOR_KIT_HOME=str(home), GOR_MPV=str(fake), GOR_KIT_SCALE='0.04', GOR_KIT_FORCE='1', GOR_KIT_NO_PUBLISH='1',
           GOR_KIT_DIAG=str(t / 'diag.log'), GOR_KIT_MPV_SAMPLE=str(t / 'ms.txt'), GOR_KIT_REPORT=str(t / 'report.txt'), GOR_KIT_PYTHON=sys.executable, GOR_APP=str(t / 'gor.app'), GOR_KIT_IPC=str(sock), FAKE_CMDLOG=str(cmdlog))
before = h(); tmpbefore = set(os.listdir(tempfile.gettempdir()))
r = subprocess.run(['bash', str(kit)], env=env, capture_output=True, text=True, timeout=110)
rep = (t / 'report.txt').read_text() if (t / 'report.txt').exists() else ''
check('kit rc0', r.returncode == 0)
for s in ['idle-1-no-config', 'idle-2-shipped-mpv.conf', 'idle-3-conf+photon.lua', 'idle-4-full-installed-config', 'real-1-playing', 'real-2-playing-mouse-moving', 'real-3-paused', 'real-3b-paused-settled', 'real-4-seeking']:
    check('stage ' + s, '[' + s + ']' in rep)
cmds = cmdlog.read_text() if cmdlog.exists() else ''
check('real app launched with film path', 'ARGV ' + str(film) in cmds)
check('unpause, pause and seek sent over ipc', '"pause", false' in cmds and '"pause", true' in cmds and '"seek"' in cmds)
check('real stage reports both pids and film props', 'gor cpu=' in rep and 'mpv cpu=' in rep and 'codec=hevc' in rep and 'hwdec=videotoolbox' in rep)
check('VB 10s line captured per stage', any(l.strip().startswith('VB10s') and 'main_load=0.42' in l and 'proc_cpu_pct=17' in l and 'hidden_skips=9' in l for l in rep.splitlines()) and '  top_sites_10s=[HUD:55,Music:3]' in rep)
check('hot gor frames and keyframes parser present', 'hot_frames' in kit.read_text() and 'gorframe' in kit.read_text())
check('gor app terminated', subprocess.run(['pgrep', '-f', 'gor.app/Contents/MacOS/gor'], capture_output=True).returncode != 0)
check('mpv version line', 'mpv 0.41.0 fake' in rep)
check('probes per second parsed (10 per 10 s windows)', 'probes=10 over 10.0s = 1.0/s' in rep)
check('COST.sample_mpv file parsed', 'COST.sample_mpv: top mach_msg' in rep)
check('installed config untouched', h() == before)
check('temp dirs removed', not [d for d in set(os.listdir(tempfile.gettempdir())) - tmpbefore if d.startswith('gor-heat-kit-')])
check('no fake mpv left running', subprocess.run(['pgrep', '-f', str(fake)], capture_output=True).returncode != 0)
check('report is small', len(rep.splitlines()) <= 200)
env2 = dict(env); env2.pop('GOR_KIT_FORCE'); busy = subprocess.Popen(['bash', '-c', 'exec -a "mpv/bin/mpv" sleep 30'])
r2 = subprocess.run(['bash', str(kit)], env=env2, capture_output=True, text=True, timeout=30); busy.kill()
check('refuses while mpv runs', r2.returncode == 2 and 'quit gor first' in r2.stdout)
src = kit.read_text()
check('no write to installed config or defaults', 'defaults write' not in src and 'rmtree(INST' not in src and 'writes' not in src.split('PY')[1][:0])
check('idle stages start paused like the app (photon idle sample needs pause)', "([] if play else ['--pause'])" in src)
check('ipc is request_id matched with 6 s timeout', "'request_id': rid" in src and 'settimeout(6)' in src)
check('play stats fall back to photon-cost line', "' (photon-cost)'" in src)
sys.exit(1 if fails else 0)
