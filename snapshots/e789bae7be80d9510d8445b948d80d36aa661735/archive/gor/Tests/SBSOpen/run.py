from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
s=(r/'Sources/gor/Stereo/StereoDetection.swift').read_text().replace('import Darwin','import Glibc').replace('private static func inspectSync','static func inspectSync')
s=s.replace('[GORResources.vendorPath("ffmpeg/bin/ffprobe"), "/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]','[GORResources.vendorPath("missing-ffprobe")]')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);ff=p/'ffmpeg';ff.write_text('''#!/usr/bin/env python3
import sys,random
from pathlib import Path
p=Path(__file__).with_name('calls');p.open('a').write('frame\\n')
r=random.Random(43);half=bytes(r.randrange(40,220) for _ in range(160*90))
sys.stdout.buffer.write(b''.join(half[y*160:(y+1)*160]+half[y*160+2:(y+1)*160]+half[y*160:y*160+2] for y in range(90)))
''');ff.chmod(0o755)
 prefix='import Foundation\nenum GORResources {static func vendorPath(_ name:String)->String {name.contains("ffprobe") ? "'+d+'/absent":"'+str(ff)+'"}}\n'
 main='''
VRProjectionProbe.inspectSync("local-film.mkv") {result in
  precondition(!result.stereoSBS && result.projection==nil && result.suggestedLayout=="side-by-side" && result.status=="suggestionOnly-side-by-side")
 let choice=VRRecognition.choose(remembered:nil,projection:result.projection,stereoSBS:result.stereoSBS,filename:"local-film.mkv",width:320,height:90)
 precondition(choice.kind=="mono")
 let metadata=Data(#"{"streams":[{"side_data_list":[{"side_data_type":"Stereo 3D","type":"side by side"}]}]}"#.utf8)
 let explicit=VRProjectionProbe.parse(metadata)
 precondition(explicit.stereoSBS)
 precondition(VRRecognition.choose(remembered:nil,projection:explicit.projection,stereoSBS:explicit.stereoSBS,filename:"local-film.mkv",width:320,height:90).kind=="flat-sbs")
 precondition(VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:true,filename:"film_180sbs.mkv",width:3840,height:1920).kind=="flat-sbs")
 precondition(VRRecognition.choose(remembered:nil,projection:nil,stereoSBS:false,filename:"film_180sbs.mkv",width:3840,height:1920).kind=="mono")
 print("PASS actual probe: eight pair-matched frames only suggest SBS; untagged SOURCE remains2D; explicit metadata promotes SBS")
 exit(0)
}
dispatchMain()
'''
 (p/'main.swift').write_text(prefix+s+main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),str(r/'Sources/gor/Stereo/StereoGeometry.swift'),'-o',d+'/test'],check=True)
 subprocess.run([d+'/test'],check=True,timeout=15)
 assert len((p/'calls').read_text().splitlines())==8
