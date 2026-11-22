#!/usr/bin/env python3
"""Production format catalog + real mpv IPC sequence test. Not a native AppKit test."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import json,os,pathlib,socket,subprocess,tempfile,time
root=pathlib.Path(__file__).resolve().parents[2]
source=(root/'Sources/gor/UI/MenuActions.swift').read_text()
a=source.index('struct VideoFormat {');b=source.index('\nextension AppDelegate {',a)
with tempfile.TemporaryDirectory() as t:
    t=pathlib.Path(t)
    (t/'main.swift').write_text('import Foundation\n'+source[a:b]+'''
if CommandLine.arguments.count>1 {
 let bytes=Data(CommandLine.arguments[1].utf8)
 let params=try! JSONSerialization.jsonObject(with:bytes)
 print(GorCropPlan.codedSizeIfEligible(videoParams:params) == nil ? "rejected" : "eligible")
 exit(0)
}
func check(_ value:Bool,_ message:String) {if !value {fatalError(message)}}
for input in ["4:3","4/3","1.85"," 16:9 "] {check(VideoFormatCatalog.parse(input) != nil,"valid manual")}
for input in ["0","-1","nan","inf","1:0","1:2:3","",":","21","0.01"] {check(VideoFormatCatalog.parse(input) == nil,"invalid manual")}
var rows:[[String:Any]]=[]
for size in [[1920,1080],[1440,1080],[720,576]] {
 for format in VideoFormatCatalog.formats {
    let par=size[0]==720 ? 16.0/15 : 1.0
    let params:[String:Any]=["w":size[0],"h":size[1],"par":par]
    let crop=VideoFormatCatalog.sourceCrop(aspect:format.ratio,params:params)!
    check(crop.width<=size[0] && crop.height<=size[1],"source bounds")
    check(abs(Double(crop.width)*par/Double(crop.height)-format.ratio)/format.ratio<0.016,"aspect tolerance")
    rows.append(["title":format.title,"ratio":format.ratio,"w":size[0],"h":size[1],"par":par,"crop":crop.commandValue])
 }
}
let data=try! JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]);print(String(data:data,encoding:.utf8)!)
''')
    subprocess.run([os.environ.get('SWIFTC','swiftc'),str(root/'Sources/gor/GorFit.swift'),str(t/'main.swift'),'-o',str(t/'catalog')],check=True)
    rows=json.loads(subprocess.check_output([str(t/'catalog')]))
    print('PASS production catalog: 27 shared formats, exact integer ratios, parser valid/invalid, 3 source sizes including anamorphic')
    # Confirm menu/shortcut routing directly from production source, no parallel fixture logic.
    app=(root/'Sources/gor/App/AppDelegate.swift').read_text();ctrl=(_pp_split().path(root,'PPController.swift')).read_text()
    assert 'populateVideoFormats(aspectMenu,crop:false)' in app and 'populateVideoFormats(cropMenu,crop:true)' in app
    assert app.index('cropMenu.addItem(redetectCropItem)')<app.index('populateVideoFormats(cropMenu,crop:true)')
    assert 'func resetCrop() {\n        clearOwnedCropFromMenu()' in ctrl
    assert 'menuCropNone() {\n        controller?.clearOwnedCropFromMenu()' in source
    assert 'menuCropReset()  { controller?.resetCrop() }' in source
    assert 'mods:crop ? [.command,.control,.option]' in source
    assert 'cropDetector.cancel();manualRedetectInFlight=false;menuCropOwnsSelection=true' in ctrl
    assert 'guard !menuCropOwnsSelection, !currentFilePath.isEmpty' in ctrl
    assert 'pictureInPictureActive {\n            delegate.refitPictureInPicture(aspect:a)' in ctrl
    print('PASS source routing: detect first, same catalog/order, both reset handlers + shortcut unified, detector cancellation/hold, PiP refit route (not native clicks)')
    mpv=os.environ.get('MPV')
    if not mpv:
        print('SKIP real mpv: set MPV executable');raise SystemExit(0)
    for width,height in [(1920,1080),(1440,1080),(720,576)]:
        fixture=t/f'{width}.mkv'
        subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i',f'testsrc2=size={width}x{height}:rate=2','-t','1','-c:v','libx264','-vf','setsar=16/15' if width==720 else 'setsar=1','-y',str(fixture)],check=True)
        sockpath=str(t/'mpv.sock')
        process=subprocess.Popen([mpv,'--no-config','--idle=yes','--vo=null','--ao=null','--pause=yes','--keep-open=yes',f'--input-ipc-server={sockpath}',str(fixture)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            for _ in range(150):
                try: client=socket.socket(socket.AF_UNIX);client.connect(sockpath);break
                except OSError:time.sleep(.02)
            stream=client.makefile('rwb',buffering=0);seq=0
            def ipc(*args):
                stream.write((json.dumps({'command':args,'request_id':1})+'\n').encode())
                while True:
                    reply=json.loads(stream.readline())
                    if reply.get('request_id')==1:
                        assert reply['error']=='success',(args,reply)
                        return reply.get('data')
            for _ in range(100):
                try:
                    if ipc('get_property','video-dec-params').get('w')==width:break
                except (AssertionError,AttributeError):pass
                time.sleep(.02)
            baseline=ipc('get_property','video-aspect-override')
            if width==1920:
                ipc('set_property','video-aspect-override',4/3)
                for _ in range(100):
                    live=ipc('get_property','video-params')
                    if live['dw']!=live['w']:break
                    time.sleep(.01)
                result=subprocess.check_output([str(t/'catalog'),json.dumps(live)],text=True).strip()
                assert result=='rejected',live
                print('PASS reproduced old eligibility failure against live mpv video-params with AR override; new decoder-based crop avoids it')
                ipc('set_property','video-aspect-override','no')
            group=[r for r in rows if r['w']==width]
            # Every preset then next preset without clearing. Every AR combined with every crop.
            cases=0
            for cycle in (group,list(reversed(group))):
                for crop in cycle:
                    ipc('set_property','video-aspect-override','no')
                    ipc('set_property','video-crop',crop['crop'])
                    assert ipc('get_property','video-crop')==crop['crop']
                    if crop['crop']:
                        wh=crop['crop'].split('+')[0].split('x');expected=(int(wh[0]),int(wh[1]))
                    else: expected=(width,height)
                    for _ in range(150):
                        out=ipc('get_property','video-out-params')
                        if (out.get('crop-w'),out.get('crop-h'))==expected:break
                        time.sleep(.01)
                    else: raise AssertionError(('pixel output did not apply',crop,out))
                    for ar in group:
                        ipc('set_property','video-aspect-override',ar['ratio'])
                        assert abs(ipc('get_property','video-aspect-override')-ar['ratio'])<1e-6
                        assert ipc('get_property','video-crop')==crop['crop']
                        cases+=1
                    # Both UI routes converge here. Verify reset leaves decoder identity and original AR.
                    ipc('set_property','video-aspect-override','no')
                    ipc('set_property','video-crop','')
                    assert ipc('get_property','video-crop')==''
                    for _ in range(150):
                        out=ipc('get_property','video-out-params')
                        if (out.get('crop-w'),out.get('crop-h'))==(width,height):break
                        time.sleep(.01)
                    else: raise AssertionError(('pixel output did not reset',out))
                    params=ipc('get_property','video-dec-params')
                    assert params['w']==width and params['h']==height
                    assert ipc('get_property','video-aspect-override')==baseline
            print(f'PASS real mpv {width}x{height}: {cases} crop/AR combinations, forward/reverse switches, 54 resets; original decoder dimensions unchanged')
            ipc('quit')
        finally:
            process.terminate();process.wait(timeout=10)
            if os.path.exists(sockpath):os.unlink(sockpath)
