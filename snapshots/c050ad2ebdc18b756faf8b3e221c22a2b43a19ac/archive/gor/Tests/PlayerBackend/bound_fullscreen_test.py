#!/usr/bin/env python3
"""Execute actual double-click handler and backend operation. Swift required for PASS."""
import json,pathlib,re,shutil,subprocess,tempfile,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]

def declaration(text,mark):
    start=text.index(mark); op=text.index('{',start); level=1;i=op+1
    # These selected declarations have balanced braces in their strings/comments.
    while level:
        if text[i]=='{':level+=1
        elif text[i]=='}':level-=1
        i+=1
    return text[start:i]

host=(ROOT/'Sources/gor/Player/PlayerViewStub.swift').read_text()
backend=(ROOT/'Sources/gor/Engine/MPVCommand.swift').read_text()
handler=declaration(host,'func toggleFullScreen()')
assert 'ipcCommand' not in handler and 'MPVCommand' not in handler,'UI still owns transport'
assert 'controller?.playbackOperations.toggleFullscreen()' in handler,'bound typed intent missing'
pieces=[declaration(backend,x) for x in ['enum MPVCommand {','enum PlayerCropSample {','struct PlayerCropPacket {','struct PlayerPlaybackOperations {']]
swift=shutil.which('swiftc')
if not swift:
    print('NOT_RUN: actual Swift runtime unavailable; no behavioral PASS');sys.exit(77)
program='''import Foundation
'''+ '\n'.join(pieces)+'''
var bound:[String]=[]
var global:[String]=[]
var otherTransport=0
func operations(_ capture:@escaping(String)->Void)->PlayerPlaybackOperations {
 PlayerPlaybackOperations(command:capture,persistent:{_ in otherTransport += 1},packet:{_,_,_ in otherTransport += 1},reset:{_ in otherTransport += 1})
}
final class Controller {let playbackOperations:PlayerPlaybackOperations;init(_ value:PlayerPlaybackOperations){playbackOperations=value}}
final class AppDelegate {var controller:Controller?;init(_ value:Controller?){controller=value};func menuFullscreen(){controller?.playbackOperations.toggleFullscreen()}}
final class Application {var delegate:AnyObject?}
let NSApp=Application()
final class Adapter {weak var controller:Controller?
'''+handler+'''
}
func require(_ v:Bool,_ message:String){if !v {fatalError(message)}}
let adapter=Adapter()
let globalController=Controller(operations{global.append($0)})
NSApp.delegate=AppDelegate(globalController)
adapter.toggleFullScreen()
require(bound.isEmpty && global.isEmpty,"nil bound controller must not fall through to global")
let boundController=Controller(operations{bound.append($0)})
adapter.controller=boundController
adapter.toggleFullScreen()
require(bound.count==1 && global.isEmpty,"must target bound controller, never global")
let value=try! JSONSerialization.jsonObject(with:Data(bound[0].utf8)) as! [String:Any]
require(value["command"] as? [String] == ["cycle","fullscreen"],"exact command")
require(!bound[0].contains("\\n") && otherTransport==0,"single frame on original command route")
adapter.controller=nil
adapter.toggleFullScreen()
require(bound.count==1 && global.isEmpty,"nil remains no-op with live different global")
print("PASS actual bound adapter: correct target, nil/different-global, exact one command frame")
'''
with tempfile.TemporaryDirectory() as d:
    d=pathlib.Path(d);(d/'main.swift').write_text(program)
    subprocess.run([swift,str(d/'main.swift'),'-o',str(d/'test')],check=True)
    subprocess.run([str(d/'test')],check=True)
    mutants={
        'global-reroute':(handler,handler.replace('controller?.playbackOperations.toggleFullscreen()','(NSApp.delegate as? AppDelegate)?.menuFullscreen()')),
        'wrong-command':('MPVCommand.make(["cycle","fullscreen"])','MPVCommand.make(["cycle","pause"])'),
        'double-dispatch':('func toggleFullScreen()  { controller?.playbackOperations.toggleFullscreen() }','func toggleFullScreen() {controller?.playbackOperations.toggleFullscreen();controller?.playbackOperations.toggleFullscreen()}'),
        'wrong-transport':('func toggleFullscreen() {command(','func toggleFullscreen() {persistent('),
    }
    for name,(old,new) in mutants.items():
        assert old in program,name
        mutant=program.replace(old,new,1)
        (d/'main.swift').write_text(mutant)
        subprocess.run([swift,str(d/'main.swift'),'-o',str(d/'mutant')],check=True,capture_output=True)
        result=subprocess.run([str(d/'mutant')],capture_output=True)
        assert result.returncode != 0,'SURVIVED '+name
        print('KILLED runtime mutant '+name)
print('PASS source-bound bound-controller fullscreen behavior')
