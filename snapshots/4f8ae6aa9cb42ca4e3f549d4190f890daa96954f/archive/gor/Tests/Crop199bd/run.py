#!/usr/bin/env python3
"""Execute actual local crop scanner with controlled decoders, no AppKit claim."""
from pathlib import Path
import subprocess,tempfile,os
here=Path(__file__).resolve().parent
root=here.parents[1]
s=(root/'Sources/gor/Stereo/Source.swift').read_text()
a=s.index('enum SourcePixelBounds {');b=s.index('// BEGIN relocated CropHTTPReader.swift',a)
helpers=s[s.index('enum CropHTTPReader {'):s.index('// BEGIN relocated CropAcceptPolicy.swift')]
with tempfile.TemporaryDirectory(prefix='crop199bd-') as d:
 p=Path(d);(p/'bin').mkdir()
 for name in ['ffmpeg','ffprobe']:
  q=p/'bin'/name;q.write_text((here/(name+'.py')).read_text().replace('/tmp/crop-local-early-tests/',d+'/'));q.chmod(0o755)
 header='''import Foundation
import Glibc
enum GORResources {static func vendorPath(_ p:String)->String {"ROOT/bin/"+(p.contains("ffprobe") ? "ffprobe":"ffmpeg")}}
enum CropDetector {static func isWTPlayback(_ p:String)->Bool {false}}
enum TransferProbeAdmission {static func isSource(_ p:String)->Bool {false};static func admits(_ p:String)->Bool {true};static func cropBatch(_ p:[Double],index:Int,frameBytes:Int)->[Double] {[]};static func cropSelection(_ p:[Double])->String {""}}
enum GeomTrace {static func log(_ a:String,_ b:String){}}
'''.replace('ROOT',d)
 (p/'scanner.swift').write_text(header+s[a:b]+helpers)
 (p/'main.swift').write_text((here/'main.swift').read_text().replace('/tmp/crop-local-early-tests/',d+'/'))
 with (p/'compile.log').open('w') as log:subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'scanner.swift'),str(p/'main.swift'),'-o',str(p/'run')],stdout=log,stderr=log,check=True)
 for mode in ['agree','change','black','disagree','rgb','cancel','switch']:
  x=subprocess.run([str(p/'run'),mode],capture_output=True,text=True)
  if x.returncode:print(x.stdout,x.stderr);raise SystemExit(x.returncode)
  print('\n'.join(l for l in x.stdout.splitlines() if l.startswith('PASS')))
