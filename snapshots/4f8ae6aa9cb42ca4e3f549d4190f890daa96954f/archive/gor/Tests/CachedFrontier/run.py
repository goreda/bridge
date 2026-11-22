from pathlib import Path
import tempfile,subprocess,os
r=Path(__file__).resolve().parents[2];here=Path(__file__).parent
cc=os.environ.get('SWIFTC','swiftc')
with tempfile.TemporaryDirectory() as td:
 d=Path(td)
 for target,p in [('Source.swift.new','Sources/gor/Stereo/Source.swift'),('CropDetector.swift.new','Sources/gor/Picture/CropDetector.swift'),('PPController.swift.new','Sources/gor/Player/PPController.swift')]: (d/target).write_bytes((r/p).read_bytes())
 (d/'Source.swift.orig').write_bytes((here/'Source374c.swift.txt').read_bytes())
 subprocess.run(['python',str(here/'gen_harness.py'),str(d),str(d/'main.swift')],check=True)
 actual=(r/'Sources/gor/Picture/CropDetector.swift').read_text();a=actual.index('positions:{ [weak self]');b=actual.index(' },interim:',a);closure=actual[a+len('positions:'):b+2]
 fixture=(here/'state-callback.swift').read_text();assert closure in fixture,'callback fixture is not actual current body'
 coverage=next(x.strip() for x in actual.splitlines() if 'static func planProvesCoverage' in x);assert coverage in fixture
 baseline=(d/'main.swift').read_text();m8=baseline.replace('ps.allSatisfy { $0.isFinite && $0 >= 0 } && Set(ps).count >= 3','Set(ps.filter { $0.isFinite }).count >= 3');assert m8!=baseline
 for flags in [[],['-O']]:
  for name,body,rc in [('helpers',baseline,0),('M8',m8,1),('callback',fixture,0)]:
   p=d/(name+'.swift');p.write_text(body);exe=d/name;subprocess.run([cc,*flags,str(p),'-o',str(exe)],check=True);res=subprocess.run([str(exe)],capture_output=True,text=True);print(name,flags,res.returncode,res.stdout);assert res.returncode==rc
print('PASS actual helper/callback source binding, Debug/-O, M8 runtime killed; bounded seams not full PP lifecycle')
