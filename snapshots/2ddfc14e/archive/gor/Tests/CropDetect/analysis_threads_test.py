#!/usr/bin/env python3
"""Exact real-FFmpeg parity for analysis worker bounds. No picture-quality trade."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,shutil,json,re,time
r=Path(__file__).resolve().parents[2]
swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
from lupa import lua51
photon=(r/'Resources/vendor/mpv/scripts/photon.lua').read_text()
line=next(s for s in photon.splitlines() if s.startswith('local FFMPEG = '))
lua=lua51.LuaRuntime();prefix=lua.execute('function find_ffmpeg() return "ffmpeg" end\n'+line+'\nreturn FFMPEG')
assert '-filter_threads 1 -filter_complex_threads 1' in prefix
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text('import Foundation\nlet a=Array(CommandLine.arguments.dropFirst());let b=FFmpegAnalysisThreads.arguments(a);FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject:b))\n')
 relocated=t/'FFmpegAnalysisThreads.swift';relocated.write_text((lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(r)).read_text()).split('// BEGIN relocated FFmpegAnalysisThreads.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated FFmpegAnalysisThreads.swift',1)[0])
 subprocess.run([swift,str(relocated),str(t/'main.swift'),'-o',str(t/'args')],check=True)
 def bounded(a):return json.loads(subprocess.check_output([str(t/'args')]+a))
 def run(a):
  p=subprocess.Popen(['ffmpeg']+a,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
  out,err=p.communicate(timeout=40)
  assert p.returncode==0,err.decode(errors='replace')[-1000:]
  return out,err.decode(errors='replace')
 def meta(s):return re.findall(r'lavfi\.[^\r\n]+',s)
 def crops(s):return re.findall(r'crop=\d+:\d+:\d+:\d+',s)
 measured=[]
 for pix in ['yuv420p','yuv420p10le','yuv444p16le','gray16le','gbrp10le']:
  src=t/(pix+'.mkv')
  subprocess.run(['ffmpeg','-v','error','-y','-filter_threads','1','-f','lavfi','-i','testsrc2=s=640x360:r=12:d=1','-vf','drawbox=x=0:y=0:w=iw:h=24:color=black:t=fill,drawbox=x=0:y=336:w=iw:h=24:color=black:t=fill','-threads','1','-pix_fmt',pix,'-c:v','ffv1',str(src)],check=True)
  base=['-hide_banner','-nostdin','-noautorotate','-hwaccel','none','-threads','2','-ss','0.25','-i',str(src),'-map','0:v:0','-an','-sn','-dn']
  for fmt,vf in [('yuv444p16le','cropdetect=limit=18:round=2:reset=0:skip=0'),('gray16le','cropdetect=limit=18:round=2:reset=0:skip=0,format=yuv444p16le,extractplanes=y')]:
   for batch in [False,True]:
    graph=("select='eq(n,0)+eq(n,2)+eq(n,4)'," if batch else '')+vf
    args=base+['-vf',graph,'-vsync','0','-frames:v','3' if batch else '1','-pix_fmt',fmt,'-f','rawvideo','pipe:1']
    before=run(args);after=run(bounded(args));assert before[0]==after[0] and crops(before[1])==crops(after[1]),(pix,fmt,batch)
  # Actual Photon simple graphs, including grain high-pass and unscaled SDR probe.
  for vf in ['scale=128:-1,signalstats,metadata=print','scale=128:-1,unsharp=5:5:-1.5:5:5:0.0,signalstats,metadata=print','signalstats,metadata=print']:
   args=base+['-vf',vf,'-frames:v','1','-f','null','-']
   before=run(args);after=run(['-filter_threads','1','-filter_complex_threads','1']+args)
   assert meta(before[1]) and meta(before[1])==meta(after[1]),(pix,vf)
  print('PASS exact raw sample/batch bytes, crop bounds and Photon metadata for',pix)
 # UHD reference exercises full-resolution conversion without changing chosen pixels.
 src=t/'uhd.mkv'
 subprocess.run(['ffmpeg','-v','error','-y','-f','lavfi','-i','testsrc2=s=3840x2160:r=12:d=0.5','-threads','1','-c:v','libx264','-preset','ultrafast',str(src)],check=True)
 args=['-hide_banner','-nostdin','-threads','2','-i',str(src),'-an','-vf','cropdetect=limit=18:round=2:reset=0:skip=0,format=yuv444p16le,extractplanes=y','-frames:v','1','-pix_fmt','gray16le','-f','rawvideo','pipe:1']
 for mode,a in [('auto',args),('bounded',bounded(args))]:
  start=time.monotonic();out,err=run(a);measured.append((mode,time.monotonic()-start,out,crops(err)))
 assert measured[0][2:]==measured[1][2:]
 print('PASS UHD exact raw bytes/crop metadata; Linux wall seconds',[(m[0],round(m[1],3)) for m in measured])
 assert bounded(['-version'])[:4]==['-filter_threads','1','-filter_complex_threads','1']
sp=(lambda _b: _b[_b.index('// BEGIN relocated '+'SourcePixelCrop.swift'+' '):_b.index('// END relocated '+'SourcePixelCrop.swift'+'\n')])((_threed_split().path(r)).read_text());assert 'FFmpegAnalysisThreads.arguments(readerArgs)' in sp
print('PASS production source-crop runner and actual Lua FFMPEG prefix wired; native thermal outcome NOT_RUN')
