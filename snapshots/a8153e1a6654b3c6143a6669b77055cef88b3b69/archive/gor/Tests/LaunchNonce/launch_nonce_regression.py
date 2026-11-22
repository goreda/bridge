#!/usr/bin/env python3
"""Extract and execute launch argv + actual Lua epoch code. No product changes here."""
import argparse, pathlib, subprocess, tempfile, json, hashlib, shutil
from lupa import LuaRuntime

def function(text, marker):
    start=text.index(marker); brace=text.index('{',start); depth=1; i=brace+1
    # These selected functions contain no literal unmatched braces.
    while depth:
        if text[i]=='{': depth+=1
        elif text[i]=='}': depth-=1
        i+=1
    return text[start:i]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--app',required=True); ap.add_argument('--lua',required=True); ap.add_argument('--pp',required=True); ap.add_argument('--swiftc',default='swiftc'); ap.add_argument('--out',required=True); ap.add_argument('--expect-unrepaired',action='store_true',help='Diagnostic baseline only, never candidate qualification'); a=ap.parse_args()
    out=pathlib.Path(a.out);out.mkdir(parents=True,exist_ok=True)
    app=pathlib.Path(a.app).read_text();lua=pathlib.Path(a.lua).read_text();pp=pathlib.Path(a.pp).read_text()
    block=app[app.index('        var args: [String] = [',app.index('private func launchMPVImplementation')):app.index('        p.arguments = args',app.index('private func launchMPVImplementation'))]
    assert block.count('--script-opts=ytdl_hook-ytdl_path=')+block.count('--script-opts-add=ytdl_hook-ytdl_path=')==1
    actual_source_additive=(block.count('--script-opts-add=ytdl_hook-ytdl_path=')==1 and block.count('--script-opts=ytdl_hook-ytdl_path=')==0)
    if a.expect_unrepaired:
        assert not actual_source_additive, 'Diagnostic baseline expected unrepaired source'
    else:
        assert actual_source_additive, 'Candidate DISQUALIFIED: actual source must contain additive ytdl option and no replacing ytdl assignment'
    if a.expect_unrepaired:
        positive_body=block.replace('--script-opts=ytdl_hook-ytdl_path=','--script-opts-add=ytdl_hook-ytdl_path=') # counterfactual baseline only
    else:
        positive_body=block # candidate runs actual additive input UNCHANGED
        assert positive_body==block
    mutant=positive_body.replace('--script-opts-add=ytdl_hook-ytdl_path=','--script-opts=ytdl_hook-ytdl_path=')
    # Real FileManager branch, UUID, argv interpolation and concatenation execute in Swift.
    pre='''import Foundation
class PPController { static var cropPacketSession=""; static var defaultVolume=0.6 }
struct GorOpeningFit { static func fitScriptOptSuffix()->String { ",gor_fit-metrics=1900;1100;2;0;28" } }
struct SubtitleSizePreference { static func restored()->Double? { 1.25 } }
struct AppDelegate { static var path=""; static func stagedYtDlpPath()->String { path } }
struct Diag { static var mediaTelemetryEnabled=false }
func launch(_ found:Bool,_ photonEnabled:Bool,_ diag:Bool)->[String] {
let configDir="/tmp/nonce-config",ipcPath="/tmp/nonce-ipc",watchLater="/tmp/nonce-watch"
let file:String?="/tmp/local-fixture.mkv"
AppDelegate.path="/tmp/nonce-ytdlp-"+UUID().uuidString
if found { FileManager.default.createFile(atPath:AppDelegate.path,contents:Data()) }
defer { try? FileManager.default.removeItem(atPath:AppDelegate.path) }
Diag.mediaTelemetryEnabled=diag
PPController.cropPacketSession=UUID().uuidString
'''
    post='''
return args
}
var rows:[[String:Any]]=[]
for found in [false,true] { for photon in [false,true] { for diag in [false,true] {
let argv=launch(found,photon,diag)
rows.append(["found":found,"photon":photon,"diag":diag,"session":PPController.cropPacketSession,"argv":argv])
} } }
let data=try! JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys])
print("RESULT "+String(data:data,encoding:.utf8)!)
'''
    valid=function(pp,'private func validatedCropReceiverCount')
    accept=function(pp,'private func acceptCropPacketToken')
    seek=function(pp,'private func noteReceiverCropSeek')
    # Only the receiving callback's downstream resumption is a recorder seam.
    receiver='''import Foundation
import CoreFoundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
final class PPController {
static var cropPacketSession=""
var cropBoundLaunchSession=""
var cropPacketLocalStamp:UInt64=7
var mediaTransitionPending=false
var currentFilePath="/tmp/local-fixture.mkv"
var cropReceiverCount:Int64=0,cropReceiverSeekGeneration:Int64=0
var cropPacketIntentGen:UInt64=1
var cropPacketPending:(id:Int,stamp:UInt64,path:String,rect:CGRect,gen:UInt64)?
var cropPacketToken:String?
var resumed=0,retries=0
var cropReceiverSeekToken:String?
var cropSeekFenceActive=false
func fenceCropMeasurementForSeek() {}
func scheduleCropFreshFollowthrough() {}
func requestRealCrop(_ rect:CGRect,resuming:UInt64?) { resumed+=1 }
func retryCropPacketIntent() { retries+=1 }
'''+valid+'\n'+seek+'\n'+accept+'''
func receive(_ data:Any?,_ stamp:UInt64=7,_ session:String)->[String:Any] {
Self.cropPacketSession=session;cropBoundLaunchSession=session
cropPacketPending=(9196000001,7,currentFilePath,CGRect(x:0,y:0.1,width:1,height:0.8),1)
acceptCropPacketToken(9196000001,true,data,stamp)
acceptCropPacketToken(9196000001,true,data,stamp)
return ["token":cropPacketToken as Any? ?? NSNull(),"resumed":resumed,"retries":retries]
}
}
let input=try! JSONSerialization.jsonObject(with:FileHandle.standardInput.readDataToEndOfFile()) as! [String:Any]
let h=PPController()
let result=h.receive(input["state"],7,input["session"] as! String)
print(String(data:try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
'''
    epoch=lua[:lua.index('-- Load lifecycle publication')]
    receipts=[]
    for opt in ['', '-O']:
        suffix='debug' if not opt else 'optimized'
        rs=out/('receiver-'+suffix+'.swift');rs.write_text(receiver);rx=out/('receiver-'+suffix)
        subprocess.run([a.swiftc,*([opt] if opt else []),str(rs),'-o',str(rx)],check=True,capture_output=True)
        for variant,body in [('actual-candidate' if not a.expect_unrepaired else 'counterfactual-repaired-baseline',positive_body),('replacement-mutant',mutant)]:
            src=out/(variant+'-'+suffix+'.swift');src.write_text(pre+body+post);exe=src.with_suffix('')
            subprocess.run([a.swiftc,*([opt] if opt else []),str(src),'-o',str(exe)],check=True,capture_output=True)
            stdout=subprocess.check_output([str(exe)],text=True)
            rows=json.loads(stdout.split('RESULT ',1)[1])
            for row in rows:
                # mpv v0.41 string-list option semantics: plain assignment replaces, add appends.
                opts={}
                for arg in row['argv']:
                    if arg.startswith('--script-opts='): opts={}; payload=arg.split('=',1)[1]
                    elif arg.startswith('--script-opts-add='): payload=arg.split('=',1)[1]
                    else:continue
                    for item in payload.split(','):
                        k,v=item.split('=',1);opts[k]=v
                rt=LuaRuntime(unpack_returned_tuples=True)
                rt.globals().nonce=opts.get('gor_fit-crop-session')
                rt.execute('''state=nil;hooks={};mp={}
function mp.get_opt(k) return nonce end
function mp.get_property_native(k) return state end
function mp.get_property(k) return "/tmp/local-fixture.mkv" end
function mp.set_property_native(k,v) state=v;return true end
function mp.add_hook(k,n,f) hooks[k]=f end
''')
                rt.execute(epoch+'\nfunction test_token() return crop_token() end')
                reload_token=rt.eval('test_token()');rt.execute('hooks.on_load()');token=rt.eval('test_token()')
                table=rt.globals().state;state=None if table is None else {k:v for k,v in table.items()}
                result=json.loads(subprocess.check_output([str(rx)],input=json.dumps({'state':state,'session':row['session']}),text=True))
                positive=variant!='replacement-mutant' or not row['found']
                if positive:
                    assert opts['osc-visibility']=='never' and opts['gor_fit-metrics']=='1900;1100;2;0;28'
                    assert opts['photon-scriptdir']=='/tmp/nonce-config/scripts'
                    assert opts['photon-menu-enabled']==str(row['photon']).lower()
                    assert opts['gor-diag']==str(row['diag']).lower()
                    assert ('--msg-time=yes' in row['argv'])==row['diag']
                    assert ('ytdl_hook-ytdl_path' in opts)==row['found']
                    assert reload_token==row['session']+':1' and token==row['session']+':2'
                    assert state['count']==2 and state['seek_generation']==0 and state['reason']=='opening'
                    assert result['resumed']==1 and result['token']==token
                else:
                    assert 'gor_fit-crop-session' not in opts and 'gor_fit-metrics' not in opts and 'osc-visibility' not in opts
                    assert reload_token is None and token is None and state is None
                    assert result['resumed']==0 and result['token'] is None
                receipts.append({'mode':suffix,'variant':variant,'ytdlp':row['found'],'photon':row['photon'],'diag':row['diag'],'keys':sorted(opts),'epoch':state,'receiver':result,'expected_positive':positive,'pass':True})
    report={'candidate_qualified':actual_source_additive and not a.expect_unrepaired,'actual_source_additive':actual_source_additive,'positive_body_unchanged':positive_body==block,'extracted_argv_sha256':hashlib.sha256(block.encode()).hexdigest(),'positive_argv_sha256':hashlib.sha256(positive_body.encode()).hexdigest(),'diagnostic_baseline_only':a.expect_unrepaired,'source_sha256':{str(p):hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in [a.app,a.lua,a.pp]},'cases':receipts,'count':len(receipts),'scope':'Actual extracted Swift argv, actual first Lua epoch block, actual PP validator/accept callback. Option-map fold follows pinned mpv semantics, not an mpv process. Screen metrics are stubbed. requestRealCrop continuation is a recorder, not window planning or physical landing proof.'}
    (out/'receipts.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'PASS {len(receipts)} launch/Lua/receiver cases; candidate_qualified={report["candidate_qualified"]}; replacement mutant rejected when yt-dlp exists; Debug and -O')
if __name__=='__main__':main()
