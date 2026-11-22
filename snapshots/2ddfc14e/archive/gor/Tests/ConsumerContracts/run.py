#!/usr/bin/env python3
"""Execute actual current Swift bodies with recording collaborators. No AppKit/native claim."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys,tempfile
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
def source(name):
    hits=list((ROOT/'Sources/gor').rglob(name))
    if len(hits)!=1:raise AssertionError(('ambiguous current source',name,hits))
    return hits[0].read_text()
def function(text,signature):
    start=text.index(signature);brace=text.index('{',start);depth=0
    for i in range(brace,len(text)):
        if text[i]=='{':depth+=1
        elif text[i]=='}':
            depth-=1
            if depth==0:return text[start:i+1]
    raise AssertionError('unclosed '+signature)
def font():
    body=function(source('PhotonFont.swift'),'private static func cacheKey(').replace('private static func','static func',1)
    prefix='''import Foundation
struct Axis {let min:Double;let max:Double}
enum Font {
static let CacheQuantizationSteps:Double=128
static var _axisRanges:[Int:Axis]=[1:Axis(min:0,max:100)]
'''
    tests='''
}
func demand(_ ok:@autoclosure()->Bool){precondition(ok())}
let a=Font.cacheKey(vars:[2:0.5,1:50],size:12)
let b=Font.cacheKey(vars:[1:50,2:0.5],size:12)
demand(a==b)
demand(Font.cacheKey(vars:[:],size:12) != Font.cacheKey(vars:[:],size:13))
demand(Font.cacheKey(vars:[1:50],size:12) != Font.cacheKey(vars:[1:50],size:13))
demand(Font.cacheKey(vars:[1:50],size:12) == Font.cacheKey(vars:[1:50.01],size:12.01))
demand(Font.cacheKey(vars:[1:50],size:12) != Font.cacheKey(vars:[1:51],size:12))
demand(Font.cacheKey(vars:[:],size:12.1) == Font.cacheKey(vars:[:],size:12))
demand(Font.cacheKey(vars:[:],size:12.13) != Font.cacheKey(vars:[:],size:12))
for size in [CGFloat.nan,CGFloat.infinity,-CGFloat.infinity,CGFloat.greatestFiniteMagnitude,-CGFloat.greatestFiniteMagnitude] {
 demand(Font.cacheKey(vars:[:],size:size).hasPrefix("novars|raw:"))
 demand(Font.cacheKey(vars:[1:50],size:size).contains("|raw:"))
}
demand(Font.cacheKey(vars:[:],size:.infinity) != Font.cacheKey(vars:[:],size:-.infinity))
print("FONT ACTUAL CACHEKEY PASS")
'''
    mutants={
      'unsafe_cast':body.replace('if let integer = Int(exactly: quarter) {','if true { let integer = Int(quarter)'),
      'drop_size':body.replace('\\(sizeBucket)','constant'),
      'unsorted_tags':body.replace('vars.keys.sorted()','vars.keys.sorted().reversed()') ,
      'no_axis_normalization':body.replace('normalized = (v - r.min) / (r.max - r.min)','normalized = v'),
    }
    # Check canonical ascending representation too, not only dictionary order.
    tests=tests.replace('demand(a==b)','demand(a==b)\ndemand(a.hasPrefix("1:0.5,2:0.5|"))')
    return prefix,body,tests,mutants

def subtitle():
    s=source('PPControllerMenuQueries.swift');backend=source('MPVCommand.swift')
    make=function(backend,'static func make(_ args:');parse=function(backend,'static func parseFirst(')
    body=function(s,'func queryMenuPayload(')+'\n'+function(s,'func setSubtitlePositionPreset(')
    prefix='''import Foundation
enum MPVCommand {MAKE}
final class IPCClient {
var lines:[String]=[];var calls:[(String,Double)]=[]
func queryBatch(_ p:String,timeout:Double)->[String]{calls.append((p,timeout));return lines}
PARSE
}
final class View {var values:[Double]=[];func setSubtitlePosition(_ x:Double,force:Bool){precondition(force);values.append(x)}}
final class UI {var lines:[String]=[];func showMPVOSD(_ x:String,duration:Double,force:Bool){precondition(duration==1.5 && force);lines.append(x)}}
final class Host {
let ipcClient=IPCClient();let subtitleView=View();let spineUI=UI()
var pendingSubtitleModePosition:Int?=99;var embedded:Bool?=nil;var embeddedCalls:[Int]=[]
func applyEmbeddedSubtitlePositionPreset(_ p:Int)->Bool?{embeddedCalls.append(p);return embedded}
'''.replace('MAKE',make).replace('PARSE',parse)
    tests='''
}
func demand(_ x:@autoclosure()->Bool){precondition(x())}
for accepted in [true,false] {
 let h=Host();h.embedded=accepted
 demand(h.setSubtitlePositionPreset(30)==accepted)
 demand(h.embeddedCalls==[30] && h.ipcClient.calls.isEmpty && h.subtitleView.values.isEmpty && h.pendingSubtitleModePosition==99 && h.spineUI.lines.isEmpty)
}
let h=Host();h.ipcClient.lines=["{\\"error\\":\\"success\\"}","{\\"data\\":40.0,\\"error\\":\\"success\\"}"]
demand(h.setSubtitlePositionPreset(40))
demand(h.ipcClient.calls.count==1 && h.ipcClient.calls[0].1==0.3)
let rows=h.ipcClient.calls[0].0.split(separator:"\\n").map {try! JSONSerialization.jsonObject(with:Data($0.utf8)) as! [String:Any]}
demand(rows.count==2)
demand((rows[0]["command"] as! NSArray).isEqual(to:["set_property","sub-pos",40]))
demand((rows[1]["command"] as! NSArray).isEqual(to:["get_property","sub-pos"]))
demand(h.pendingSubtitleModePosition==nil && h.subtitleView.values==[40])
demand(h.spineUI.lines==["subtitle position: 40%"])
for reply in [[],["garbage"],["{\\"error\\":\\"failure\\"}"],["{\\"data\\":\\"bad\\"}"],["{\\"data\\":null}"]] {
 let f=Host();f.ipcClient.lines=reply
 demand(!f.setSubtitlePositionPreset(20));demand(f.pendingSubtitleModePosition==99 && f.subtitleView.values.isEmpty)
 demand(f.spineUI.lines==["subtitle control unavailable"])
}
print("SUBTITLE ACTUAL SETTER+QUERY PASS")
'''
    return prefix,body,tests,{
       'skip_embedded_route':body.replace('if let accepted=applyEmbeddedSubtitlePositionPreset(pos) {return accepted}',''),
       'omit_mode_clear':body.replace('pendingSubtitleModePosition=nil;',''),
       'wrong_deadline':body.replace('timeout:0.3','timeout:3'),
       'drop_readback':body.replace('+"\\n"+MPVCommand.make(["get_property","sub-pos"])',''),
    }
def subtitle_refusal():
    prefix,body,_,_=subtitle()
    tests=r'''
}
let host=Host()
host.ipcClient.lines=["{\"error\":\"property unavailable\"}","{\"error\":\"success\",\"data\":80.0}"]
let accepted=host.setSubtitlePositionPreset(20)
print("write refused, finite OLD readback: accepted=\(accepted), forcedView=\(host.subtitleView.values), mode=\(String(describing:host.pendingSubtitleModePosition))")
precondition(!accepted,"write refusal must not become successful preset from finite OLD readback")
precondition(host.subtitleView.values.isEmpty && host.pendingSubtitleModePosition==99)
print("SUBTITLE WRITE REFUSAL PASS")
'''
    return prefix,body,tests,{}

def block():
    pp=source('PPController.swift');mq=source('PPControllerMenuQueries.swift');backend=source('MPVCommand.swift')
    menu=function(pp,'func applyMenuCrop(')
    presentation=function(pp,'private func applyCropPresentation(').replace('private func','func',1)
    fits=function(mq,'static func fits(')
    prefix='''import Foundation
enum MPVCommand {MAKE}
CROP_SAMPLE
struct Operations {let command:(String)->Void
PUBLISH
}
enum CropInvariant {static func keptLine(_ s:String)->String{s}
FITS
}
final class Detector {var sourcePixelWidth=1920;var sourcePixelHeight=1080;var cancelled=0;func cancel(){cancelled+=1}}
final class UI {var messages:[String]=[];func showMPVOSD(_ s:String,force:Bool){messages.append(s)}}
final class Window {var frame=CGRect(x:1,y:2,width:3,height:4)}
final class VR {var clears=0;func clearMeasuredEyeAspect(){clears+=1}}
final class Host {
static let fullSourceCrop=CGRect(x:0,y:0,width:1,height:1)
var refuse=false;var embeddedBackend=false;var vrModeEnabled=false;var surfaceToolsEnabled=false
let cropDetector=Detector();let spineUI=UI();var manualRedetectInFlight=true
var manualMenuCropAspect:Double?;var menuCropOwnsSelection=false
var stereoRestorePending=true;var stereoMenuOriginalFrame:CGRect?;var window:Window?=Window()
var stereoProjectionBaseAspect:Double?;var nativeVideoAspect:Double?=2
var stereoMenuCropAspect:Double?;var vr180Controller:VR?=VR()
var sourceCropPropertyRequested=false;var cropLastCommandValue=""
var embeddedSourceCrop:((String,CGRect)->String?)?;var currentFilePath="/film"
var trace:[String]=[];var requested:[CGRect]=[];var refits:[Double]=[];var commands:[String]=[]
lazy var playbackOperations=Operations(command:{[weak self] in self?.commands.append($0)})
func refuseEmbedded(_ s:String)->Bool{trace.append("refuse");return refuse}
func requestRealCrop(_ r:CGRect,newIntent:Bool){precondition(newIntent);trace.append("request");requested.append(r)}
func refitWindowForCrop(aspect:Double){trace.append("refit");refits.append(aspect)}
func refreshStereoMenuGeometry(force:Bool){precondition(force);trace.append("stereo")}
func ipcCommand(_ s:String){commands.append(s)}
func publishSurfaceWindowCrop(x:Double,y:Double,cx:Double,cy:Double)->Bool{trace.append("surface");return true}
'''.replace('MAKE',function(backend,'static func make(_ args:')).replace('FITS',fits).replace('CROP_SAMPLE',function(backend,'enum PlayerCropSample {')).replace('PUBLISH',function(backend,'func publish(_ sample:PlayerCropSample)'))
    tests='''
}
func demand(_ x:@autoclosure()->Bool){precondition(x())}
let refused=Host();refused.refuse=true;demand(!refused.applyMenuCrop(aspect:1.5));demand(refused.cropDetector.cancelled==0 && refused.requested.isEmpty)
let mono=Host();demand(mono.applyMenuCrop(aspect:1.5));demand(mono.trace==["refuse","request","refit"])
demand(mono.manualMenuCropAspect==1.5 && mono.menuCropOwnsSelection && !mono.manualRedetectInFlight && mono.cropDetector.cancelled==1)
demand(mono.requested==[Host.fullSourceCrop] && mono.refits==[1.5] && mono.commands.isEmpty)
let vr=Host();vr.vrModeEnabled=true;demand(vr.applyMenuCrop(aspect:1.6))
demand(vr.requested.isEmpty && vr.refits.isEmpty && vr.stereoMenuCropAspect==1.6 && vr.stereoProjectionBaseAspect==1 && vr.stereoMenuOriginalFrame==vr.window!.frame && !vr.stereoRestorePending)
let h=Host();demand(h.applyCropPresentation(CGRect(x:0.1,y:0.2,width:0.5,height:0.5)))
demand(h.sourceCropPropertyRequested && h.cropLastCommandValue=="960x540+192+216")
let object=try! JSONSerialization.jsonObject(with:Data(h.commands[0].utf8)) as! [String:Any]
demand((object["command"] as! NSArray).isEqual(to:["set_property","video-crop","960x540+192+216"]))
let bad=Host();bad.cropDetector.sourcePixelWidth=0;demand(!bad.applyCropPresentation(CGRect(x:0,y:0,width:0.5,height:0.5)));demand(bad.commands.isEmpty)
let clear=Host();demand(clear.applyCropPresentation(Host.fullSourceCrop));demand(!clear.sourceCropPropertyRequested && clear.cropLastCommandValue=="")
let embedded=Host();embedded.embeddedBackend=true;embedded.embeddedSourceCrop={_,_ in "refused"}
demand(!embedded.applyCropPresentation(Host.fullSourceCrop));demand(embedded.commands.isEmpty && !embedded.spineUI.messages.isEmpty)
let absent=Host();absent.embeddedBackend=true;demand(!absent.applyCropPresentation(Host.fullSourceCrop))
let shader=Host();shader.vrModeEnabled=true;demand(shader.applyCropPresentation(Host.fullSourceCrop));demand(shader.vr180Controller!.clears==1 && shader.trace==["stereo"])
print("BLOCK185 ACTUAL MENU+PRESENTATION PASS")
'''
    body=menu+'\n'+presentation
    return prefix,body,tests,{
      'bypass_refusal':body.replace('if refuseEmbedded("video crop") {return false}',''),
      'omit_request':body.replace('requestRealCrop(CGRect(x:0,y:0,width:1,height:1),newIntent:true)',''),
      'window_first':body.replace('requestRealCrop(CGRect(x:0,y:0,width:1,height:1),newIntent:true)\n            refitWindowForCrop(aspect:aspect)','refitWindowForCrop(aspect:aspect)\n            requestRealCrop(CGRect(x:0,y:0,width:1,height:1),newIntent:true)'),
      'wrong_source_property':body.replace('send(.source(value))','send(.window(value,scripted:false,final:false))'),
    }

def run(contract):
    prefix,body,tests,mutants=globals()[contract]()
    compiler=os.environ.get('SWIFTC') or shutil.which('swiftc')
    if not compiler or not os.access(compiler,os.X_OK):
        print('NOT_RUN actual Swift '+contract+': executable swiftc unavailable');return 77
    records=[]
    with tempfile.TemporaryDirectory() as td:
        td=Path(td)
        for name,candidate in [('baseline',body)]+list(mutants.items()):
            p=td/'main.swift';p.write_text(prefix+candidate+tests)
            exe=td/'check'
            build=subprocess.run([compiler,'-swift-version','5',str(p),'-o',str(exe)],capture_output=True,text=True)
            if build.returncode:
                print(build.stdout+build.stderr);raise AssertionError('compile failed, not a killed mutant: '+name)
            result=subprocess.run([str(exe)],capture_output=True,text=True,timeout=10)
            good=result.returncode==0 if name=='baseline' else result.returncode!=0
            records.append({'name':name,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'exit':result.returncode,'expected_result':good})
            print(contract,name,'PASS' if good else 'FAIL',result.returncode)
            if name=='baseline': print(result.stdout)
            if not good:print(result.stdout+result.stderr);raise AssertionError(name)
    print(json.dumps({'contract':contract,'actual_body_sha256':hashlib.sha256(body.encode()).hexdigest(),'records':records,'scope':'Actual extracted Swift bodies, recording collaborators; no AppKit/socket/native/visual execution'},indent=2))
    return 0
if __name__=='__main__':sys.exit(run(sys.argv[1]))
