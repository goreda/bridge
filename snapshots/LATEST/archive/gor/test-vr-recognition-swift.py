#!/usr/bin/env python3
"""Execute actual recognition methods and probe parser with Foundation-only host stubs. Not AppKit."""
from pathlib import Path
import subprocess,tempfile,os
r=Path(__file__).resolve().parent
swift=os.environ.get('SWIFTC','swiftc')
features=(r/'Sources/gor/PPController_Features.swift').read_text()
methods=features[features.index('    // Block184 restores the owner-selected metadata/token/geometry recognition contract.'):features.index('    /// GOR_VR_SIM_POSE')]
probe=(r/'Sources/gor/Stereo/StereoDetection.swift').read_text()
if os.name=='posix' and __import__('sys').platform!='darwin':probe=probe.replace('import Darwin','import Glibc')
pre='''import Foundation
struct GORResources { static func vendorPath(_ p:String)->String { return "/missing/"+p } }
struct GeomTrace { static func log(_ t:String,_ s:String){};static func logChanged(_ t:String,_ s:String){} }
struct Diag { static func log(_ s:String){} }
final class Subject {
 var projectionKind="vr180"
 var isTopBottom:Bool {projectionKind=="flat-tb"}
 var blinkControlPreferred=false
 func showBlinkOSD(_ s:String){}

 var flatAutoEyeAspect:Double=0
 var flatStereoFile=false, projectionKey="", vrModeSetByAutoDetect=false, vrModeEnabled=false
 var sent:[String]=[]
 func ipcCommand(_ s:String){sent.append(s)}
 func setVRModeEnabled(_ b:Bool){vrModeEnabled=b}
 func simulatePoseIfRequested(){}
'''
post='''
func load(_ name:String,_ stereo:String?=nil,_ w:Double=2000,_ h:Double=1000) {
 if recognitionPath != name {probeProjection=nil;probeStereoSBS=false;probeEyeCrop=nil;probeEyeAspect=nil;projectionKey=""}
 recognitionPath=name;recognitionIdentity=VRRecognition.fileIdentity(name);probeStarted=true;probeFinished=true;autoDetectFromVideoParams(stereoMode:stereo,width:w,height:h,filename:name)
}
func test() {
 precondition(knownEyeAspect(kind:"flat-sbs",filename:"x.HSBS.mkv",width:1920,height:1080)==1920.0/1080)
 precondition(knownEyeAspect(kind:"flat-sbs",filename:"x.FSBS.mkv",width:3840,height:1080)==1920.0/1080)
 precondition(knownEyeAspect(kind:"flat-sbs",filename:"x.SBS.mkv",width:2048,height:2048)==1)
 precondition(knownEyeAspect(kind:"flat-sbs",filename:"x.HSBS.mkv",width:1440,height:1080)==4.0/3)
 print("known packing source DAR / HSBS / FSBS / anamorphic source DAR / measured square half-SBS fallback PASS")
 // Callbacks are asynchronous and not run by this logic-only executable.
 load("movie.SBS.mkv");precondition(flatStereoFile && vrModeEnabled)
 load("movie.VR180.SBS.mkv");precondition(!flatStereoFile)
 selectProjection("flat-sbs");load("movie.VR180.SBS.mkv");precondition(flatStereoFile)
 let manualCount=sent.count;probeProjection="vr180";load("movie.VR180.SBS.mkv");precondition(flatStereoFile && sent.count==manualCount)
 manualProjection=nil;projectionKey="";recognitionPath="unknown.mkv";probeProjection="unsupported";probeStarted=true
 load("unknown.mkv","sbs2l");precondition(projectionKey.isEmpty)
 probeProjection=nil;load("unknown.mkv","sbs2l");precondition(projectionKey.isEmpty)
 probeProjection="vr180";load("unknown.mkv","sbs2l");precondition(!flatStereoFile && !projectionKey.isEmpty)
 manualProjection=nil;projectionKey="";vrModeEnabled=true;load("second.SBS.mkv");precondition(flatStereoFile)
 noteManualEnabled(false);load("second.SBS.mkv");precondition(!vrModeEnabled)
 noteManualEnabled(true);noteManualEnabled(false);load("second.SBS.mkv");precondition(!vrModeEnabled)
 print("actual Swift recognition: filename/explicit180/manual/late override/unknown layout/manual VR-ON PASS")
}
}
let subject = Subject();subject.test()
for (json,expected,stereo) in [
 (#"{"streams":[{"side_data_list":[{"side_data_type":"Spherical Mapping","projection":"half equirectangular"}]}]}"#, "vr180",false),
 (#"{"streams":[{"side_data_list":[{"side_data_type":"Spherical Mapping","projection":"equirectangular"},{"side_data_type":"Stereo 3D","type":"side by side"}]}]}"#, "unsupported",true),
 (#"{"streams":[{"side_data_list":[{"side_data_type":"Stereo 3D","type":"side by side"}]}]}"#, "unknown",true),
 (#"{"streams":[{"side_data_list":[{"side_data_type":"Spherical Mapping","projection":"rectilinear"}]}]}"#, "flat-sbs",false)
] {
 let result=VRProjectionProbe.parse(Data(json.utf8));precondition((result.projection ?? "unknown")==expected && result.stereoSBS==stereo)
}
precondition(VRProjectionProbe.parse(Data("invalid".utf8)).status=="invalidProbeJSON")
print("actual Swift projection JSON parser: half180/unsupported360/layout-only/rectilinear/invalid PASS")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'main.swift';p.write_text(pre+methods+post+'\n'+probe)
 subprocess.run([swift,'-swift-version','5',str(p),str(r/'Sources/gor/Stereo/StereoGeometry.swift'),'-o',d+'/check'],check=True)
 subprocess.run([d+'/check'],check=True)
print('Foundation host only; no macOS AppKit/TCC/camera/mpv-hook acceptance.')
