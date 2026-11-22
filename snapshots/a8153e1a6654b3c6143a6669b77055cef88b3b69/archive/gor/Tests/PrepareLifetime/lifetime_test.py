#!/usr/bin/env python3
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,signal,subprocess,tempfile,time,json
r=Path(__file__).resolve().parents[2];sw=os.environ.get('SWIFTC','/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);exe=p/'lifetime'
 blob=_threed_split().path(r).read_text()  # 195y: the satellite files are BEGIN/END relocated spans inside ThreeD.swift
 def sec(n):
  for tag in (' (195y owner-order 3D consolidation, behavior unchanged)',' (195y G2, behavior unchanged)'):
   b=f'// BEGIN relocated {n}.swift{tag}\n'
   if b in blob:return blob[blob.index(b)+len(b):blob.index(f'// END relocated {n}.swift\n')]
  raise KeyError(n)
 # the launcher names DepthCacheBudget.failure/DepthCachePaths.root in its report path
 for n in ['PrepareProcessLifetime','PrepareInputRemux','ThreeDPrepareLauncher','DepthCacheBudget','FilmPrepareStatus']:
  (p/f'{n}.swift').write_text('import Foundation\n'+sec(n))
 subprocess.run([sw]+[str(p/f'{n}.swift') for n in ['PrepareProcessLifetime','PrepareInputRemux','ThreeDPrepareLauncher','DepthCacheBudget','FilmPrepareStatus']]+[str(Path(__file__).with_name('main.swift')),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
 parent=subprocess.Popen([str(exe),'--parent'],stdout=subprocess.PIPE,text=True)
 child=int(parent.stdout.readline().split()[1]);parent.kill();parent.wait()
 def living(pid):
  try:return Path(f'/proc/{pid}/stat').read_text().split()[2]!='Z'
  except FileNotFoundError:return False
 for _ in range(50):
  if not living(child):break
  time.sleep(.02)
 assert not living(child),'orphan model probe survived owner death'
 print('PASS real subprocess probe exits after parent SIGKILL')
 a=subprocess.Popen([str(exe),'--lane',d],stdout=subprocess.PIPE,text=True);assert a.stdout.readline().strip()=='ENTER'
 start=time.monotonic();b=subprocess.Popen([str(exe),'--lane',d],stdout=subprocess.PIPE,text=True)
 assert b.stdout.readline().strip()=='ENTER';assert time.monotonic()-start>.3
 a.wait();b.wait();print('PASS real cross-process model lane serializes load stacks')
 src=p/'input.mkv';out=p/'output.mp4'
 subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=24','-frames:v','24','-c:v','libx264',str(src)],check=True)
 argv=subprocess.check_output([str(exe),'--remux',str(src),str(out)],text=True).splitlines()
 subprocess.run(['ffmpeg',*argv],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 def frames(f):return subprocess.check_output(['ffmpeg','-v','error','-i',str(f),'-map','0:v:0','-f','framemd5','-'])
 assert frames(src)==frames(out),'remux changed decoded frames'
 print('PASS actual production stream-copy args preserve all decoded MKV fixture frames')
