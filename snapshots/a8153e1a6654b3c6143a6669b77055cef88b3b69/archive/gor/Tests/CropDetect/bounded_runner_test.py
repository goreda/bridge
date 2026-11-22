#!/usr/bin/env python3
"""Execute actual bounded runner/join code, including watchdog and typed errors."""
from pathlib import Path
import subprocess,tempfile,shutil,os
r=Path(__file__).resolve().parents[2]
s=(r/'Sources/gor/Stereo/Source.swift').read_text()
a=s.index('    // Typed execution seam.');b=s.index('\n    func scan(',a);body=s[a:b]
join=s[s.index('    func hasProgress() -> Bool'):s.index('    func dropCarry()')]
helpers=''
for name in ['FFmpegAnalysisThreads','CropHTTPReader']:
 a=s.index('enum '+name+' {');i=a;depth=0;start=s.index('{',a)
 for i in range(start,len(s)):
  depth+=(s[i]=='{')-(s[i]=='}')
  if depth==0:break
 helpers+=s[a:i+1]+'\n'
head='''import Foundation
#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif
'''+helpers+'''final class Runner {
 let lock=NSLock();var active:Process?;var epoch=0
 var liveSamples=0,scanStartedAt:Double=0,scanDeadlineAt:Double=0,lastProgressAt:Double=0
 func valid(_ e:Int)->Bool{lock.lock();defer{lock.unlock()};return epoch==e}
'''
tail='''
 func require(_ passed:Bool,_ name:String,_ detail:String="") {
  if !passed {
   FileHandle.standardError.write(Data(("FAIL runner "+name+" "+detail+"\\n").utf8))
   exit(86)
  }
 }
 private func diagnostic(_ value:ReadResult)->String {
  "status=\(value.status) failure=\(String(describing:value.failure)) stdout=\(String(decoding:value.stdout,as:UTF8.self)) stderr=\(String(decoding:value.stderr,as:UTF8.self))"
 }
 func test(_ binary:String) {
  let a=run(binary,["ok"],epoch:0,cap:100,killAfter:1)
  require(a.failure==nil && a.status==0 && String(decoding:a.stdout,as:UTF8.self)=="pixels","ok",diagnostic(a))
  let b=run(binary,["error"],epoch:0,cap:100,killAfter:1)
  require(b.failure == .exitStatus && b.status==7 && String(decoding:b.stderr,as:UTF8.self).contains("read failed"),"exit-status",diagnostic(b))
  let begin=ProcessInfo.processInfo.systemUptime
  let c=run(binary,["hang"],epoch:0,cap:100,killAfter:0.15)
  require(c.failure == .deadline && ProcessInfo.processInfo.systemUptime-begin < 0.7,"watchdog deadline under0.7s",diagnostic(c))
  let d=run(binary,["large"],epoch:0,cap:4,killAfter:1)
  require(d.failure == .oversized,"oversized",diagnostic(d))
  let e=run(binary,["ok"],epoch:99,cap:100,killAfter:1)
  require(e.failure == .cancelled,"cancelled",diagnostic(e))
  let f=run(binary,["ok"],epoch:0,cap:100,killAfter:0)
  require(f.failure == .deadline,"zero-deadline",diagnostic(f))
  let now=ProcessInfo.processInfo.systemUptime
  scanStartedAt=now-10;scanDeadlineAt=now+80;lastProgressAt=now;liveSamples=1
  require(hasProgress(),"fresh-progress")
  lastProgressAt=now-25;require(!hasProgress(),"stale/deadline/missing-progress")
  lastProgressAt=now;scanDeadlineAt=now+5;require(!hasProgress(),"stale/deadline/missing-progress")
  scanDeadlineAt=now+80;scanStartedAt=now-91;require(!hasProgress(),"stale/deadline/missing-progress")
  scanStartedAt=now-10;liveSamples=0;require(!hasProgress(),"stale/deadline/missing-progress")
  print("PASS11 real typed runner/deadline/progress-age checks")
 }
}
Runner().test(CommandLine.arguments[1])
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);fake=t/'reader';source=t/'reader.c'
 # A compiled child measures the runner, not cold Python startup at nice19.
 # Keep the production watchdog and elapsed-time assertions unchanged.
 source.write_text('''#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc,char **argv) {
 if(argc!=2)return 91;
 if(!strcmp(argv[1],"hang")) {usleep(1000000);return 0;}
 if(!strcmp(argv[1],"error")) {fputs("read failed",stderr);return 7;}
 if(!strcmp(argv[1],"large")) {fputs("too many bytes",stdout);return 0;}
 fputs("pixels",stdout);return 0;
}
''')
 subprocess.run([shutil.which('cc') or '/usr/bin/cc',str(source),'-o',str(fake)],check=True)

 swift=os.environ.get('SWIFTC',shutil.which('swiftc') or '/tmp/swift-install/usr/bin/swiftc')
 code=head+body+"\n"+join+tail
 variants=[('green',code),('red-stale-progress',code.replace('now-lastProgressAt <= 20','true')),('red-no-watchdog',code.replace('timedOut.append(Data([1]),cap:1); kill(p.processIdentifier,SIGKILL)','timedOut.append(Data([1]),cap:1)'))]
 for name,text in variants:
  p=t/'main.swift';p.write_text(text)
  subprocess.run([swift,'-swift-version','5',str(p),'-o',str(t/'test')],check=True)
  try:q=subprocess.run([str(t/'test'),str(fake)],capture_output=True,text=True,timeout=3)
  except subprocess.TimeoutExpired:
   raise AssertionError('runner exceeded3s even with bounded child fixture: '+name)
  assert (q.returncode==0)==(name=='green'),q.stdout+q.stderr
  print(name,q.stdout.strip() if q.returncode==0 else 'RED runtime assertion')
# Compile full actual scanner and exact bounds with only external service doubles.
section=s[s.index('enum SourcePixelBounds {'):s.index('// END relocated SourcePixelCrop.swift')]
stubs='''
enum CropDetector {static func isWTPlayback(_ p:String)->Bool{p.hasPrefix("http://localhost:2222")}}
enum TransferProbeAdmission {
 static func isSource(_ p:String)->Bool{false};static func admits(_ p:String)->Bool{true}
 static func cropBatch(_ p:[Double],index:Int,frameBytes:Int)->[Double]{[]}
 static func cropSelection(_ p:[Double])->String{""}
}
enum GORResources {static func vendorPath(_ p:String)->String{"/nonexistent/"+p}}
enum GeomTrace {static func log(_ a:String,_ b:String){}}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td)/'scanner.swift';p.write_text('import Foundation\n#if canImport(CoreGraphics)\nimport CoreGraphics\n#endif\n#if canImport(Darwin)\nimport Darwin\n#elseif canImport(Glibc)\nimport Glibc\n#endif\n'+stubs+section)
 subprocess.run([swift,'-swift-version','5','-typecheck',str(p)],check=True)
 print('PASS complete actual scanner+pixel bounds typecheck with external service doubles')
