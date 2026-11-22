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

host=(ROOT/'Sources/gor/Media/FileBrowser.swift').read_text()
menu=(ROOT/'Sources/gor/UI/MenuActions.swift').read_text()
row=host[host.index('class RowSnapScrollView:'):]
handler=declaration(row,'override func mouseDown(with event: NSEvent)')
assert 'ipcCommand' not in handler and 'MPVCommand' not in handler,'UI still owns transport'
assert '?.menuFullscreen()' in handler,'canonical menu intent missing'
pieces=[declaration(menu,x).replace('@objc ','') for x in ['@objc func menuFullscreen()', 'func cmd(_ json: String)']]
swift=shutil.which('swiftc')
if not swift:
    print('NOT_RUN: actual Swift runtime unavailable; no behavioral PASS');sys.exit(77)
program='''import Foundation
'''+'''
var sent:[String]=[]
var nonCommandCalls=0
final class Controller {func ipcCommand(_ value:String){sent.append(value)}}
final class AppDelegate {var controller:Controller?;init(_ value:Controller?){controller=value}
'''+ '\n'.join(pieces)+'''
}
final class Application {var delegate:AnyObject?}
let NSApp=Application()
struct NSEvent {let clickCount:Int}
class ScrollBase {var supers:[Int]=[];func mouseDown(with event:NSEvent){supers.append(event.clickCount)}}
final class ActualHandler:ScrollBase {
'''+handler+'''
}
func require(_ value:Bool,_ text:String){if !value {fatalError(text)}}
let view=ActualHandler()
NSApp.delegate=AppDelegate(Controller())
for clicks in [0,1,3,4] {view.mouseDown(with:NSEvent(clickCount:clicks))}
require(view.supers == [0,1,3,4],"single/triple/other clicks must pass to super")
require(sent.isEmpty,"non-double clicks must not emit")
view.mouseDown(with:NSEvent(clickCount:2))
require(sent.count==1,"double must emit exactly once")
require(view.supers == [0,1,3,4],"double must not invoke super")
let data=sent[0].data(using:.utf8)!
let value=try! JSONSerialization.jsonObject(with:data) as! [String:Any]
require(value["command"] as? [String] == ["cycle","fullscreen"],"exact prior command")
require(!sent[0].contains("\\n"),"single frame only")
require(nonCommandCalls==0,"must use command route, not persistent/crop/reset")
NSApp.delegate=AppDelegate(nil)
view.mouseDown(with:NSEvent(clickCount:2))
NSApp.delegate=nil
view.mouseDown(with:NSEvent(clickCount:2))
NSApp.delegate=Application()
view.mouseDown(with:NSEvent(clickCount:2))
require(sent.count==1 && view.supers == [0,1,3,4],"absent/wrong delegate or controller remain no-op on double")
print("PASS actual handler + actual menuFullscreen + actual cmd: click routing, one exact JSON frame, same command transport, nil/wrong delegate, no super on double")
'''
with tempfile.TemporaryDirectory() as d:
    d=pathlib.Path(d);(d/'main.swift').write_text(program)
    subprocess.run([swift,str(d/'main.swift'),'-o',str(d/'test')],check=True)
    subprocess.run([str(d/'test')],check=True)
    mutants={
        'single-click-steals':('event.clickCount == 2','event.clickCount == 1'),
        'wrong-command':('cycle","fullscreen','cycle","pause'),
        'double-dispatch':('?.menuFullscreen()','?.menuFullscreen(); (NSApp.delegate as? AppDelegate)?.menuFullscreen()'),
        'missing-command':('controller?.ipcCommand(json)','_ = json'),
    }
    for name,(old,new) in mutants.items():
        assert old in program,name
        mutant=program.replace(old,new,1)
        (d/'main.swift').write_text(mutant)
        subprocess.run([swift,str(d/'main.swift'),'-o',str(d/'mutant')],check=True,capture_output=True)
        result=subprocess.run([str(d/'mutant')],capture_output=True)
        assert result.returncode != 0,'SURVIVED '+name
        print('KILLED runtime mutant '+name)
print('PASS source-bound FileBrowser fullscreen behavior')
