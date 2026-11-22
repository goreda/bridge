"""Compile the exact production reducer and key/dispatch methods with boundary spies."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
menu = (root / 'Sources/gor/UI/MenuActions.swift').read_text()
features = (_pp_split().path(root,'PPController_Features.swift')).read_text()

def block(source, key):
    start = source.index(key)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end].replace('private func', 'func')

code = '''import Foundation
func NSRectFromString(_ text: String) -> CGRect { NSRectFromStringBoundary.value }
enum NSRectFromStringBoundary { static var value = CGRect.zero }
class NSScreen { static var main: NSScreen?; var frame: CGRect; init(_ f: CGRect) { frame=f } }
class Window { var frame: CGRect; var screen: NSScreen?; init(_ f: CGRect, _ s: NSScreen) {frame=f;screen=s} }
struct Flags: OptionSet {
 let rawValue: Int
 static let command=Flags(rawValue:1), shift=Flags(rawValue:2), option=Flags(rawValue:4), control=Flags(rawValue:8)
 static let function=Flags(rawValue:16), maskSecondaryFn=Flags(rawValue:32)
}
class NSEvent { var keyCode: UInt16=123; var modifierFlags=Flags.function }
enum CGEventSource {
 enum State { case combinedSessionState }
 static var held=Flags()
 static func flagsState(_ state: State) -> Flags { held }
}
struct App {var delegate: AnyObject?}; var NSApp=App()
''' + block(menu, 'enum PlayerWindowPlacement {') + '\n' + block(menu, 'enum PlayerPictureInPicture {') + '''
class AppDelegate {
 var pictureInPictureActive=true, windowGeometryTransitionActive=false
 var overlayWin: Window?; var writes: [CGRect]=[]
 func snapPictureInPicture(_ frame: CGRect) {
  writes.append(frame); NSRectFromStringBoundary.value=frame
  UserDefaults.standard.set("fixture", forKey:"gor.pip.preferredFrame")
 }
''' + block(menu, '    func movePictureInPicture(direction:') + '''
}
class Input {
 var focus=true
 func hasPlayerKeyFocus(_ event:NSEvent)->Bool {focus}
''' + block(features, '    private func handlePictureInPictureCornerKey(') + '''
}
let bounds = [CGRect(x:0,y:0,width:1920,height:1080), CGRect(x:-1920,y:-250,width:1920,height:1080)]
let table: [(String, [(PlayerPictureInPicture.Direction, String)])] = [
 ("bottom-left",[(.left,"bottom-left"),(.right,"bottom-right"),(.down,"bottom-left"),(.up,"top-left")]),
 ("bottom-right",[(.left,"bottom-left"),(.right,"bottom-right"),(.down,"bottom-right"),(.up,"top-right")]),
 ("top-left",[(.left,"top-left"),(.right,"top-right"),(.down,"bottom-left"),(.up,"top-left")]),
 ("top-right",[(.left,"top-left"),(.right,"top-right"),(.down,"bottom-right"),(.up,"top-right")])
]
var cases=0
for screen in bounds {
 for size in [CGSize(width:480,height:270),CGSize(width:240,height:420)] {
  for (corner, arrows) in table {
   let current=PlayerWindowPlacement.frame(mode:corner,current:CGRect(origin:.zero,size:size),visible:screen)
   for (direction, expected) in arrows {
    let result=PlayerPictureInPicture.directionalFrame(current:current,screen:screen,direction:direction)
    let wanted=PlayerWindowPlacement.frame(mode:expected,current:current,visible:screen)
    precondition(result==wanted && result.size==size, "all4 corners x all4 directions, keep size/aspect")
    precondition(PlayerPictureInPicture.directionalFrame(current:result,screen:screen,direction:direction)==result, "edge repeat no-op")
    cases+=1
   }
  }
 }
}
for (code, expected): (UInt16,PlayerPictureInPicture.Direction) in [(115,.left),(119,.right),(121,.down),(116,.up),(123,.left),(124,.right),(125,.down),(126,.up)] {
 precondition(PlayerPictureInPicture.direction(keyCode:code,fnHeld:true)==expected)
 precondition(PlayerPictureInPicture.direction(keyCode:code,fnHeld:false)==nil,"plain arrow/Home/Page keys remain untouched")
}
let screen=NSScreen(bounds[0])
let original=CGRect(x:0,y:0,width:480,height:270)
let app=AppDelegate(); app.overlayWin=Window(original,screen); NSApp.delegate=app
let input=Input(), event=NSEvent()
UserDefaults.standard.removeObject(forKey:"gor.pip.preferredFrame")
event.keyCode=126;CGEventSource.held=[]
precondition(!input.handlePictureInPictureCornerKey(event),"arrows' synthetic function flag alone is not physical fn")
CGEventSource.held = .maskSecondaryFn
precondition(input.handlePictureInPictureCornerKey(event) && app.writes.last!.minX==0 && app.writes.last!.maxY==1080)
event.keyCode=124
precondition(input.handlePictureInPictureCornerKey(event) && app.writes.last!.maxX==1920 && app.writes.last!.maxY==1080,"up then right uses committed corner before animation settles")
let writes=app.writes.count
precondition(input.handlePictureInPictureCornerKey(event) && app.writes.count==writes,"already right consumes no write")
for modifiers in [Flags.command,.shift,.option,.control] {
 event.modifierFlags=modifiers
 precondition(!input.handlePictureInPictureCornerKey(event))
}
event.modifierFlags = .function
input.focus=false;precondition(!input.handlePictureInPictureCornerKey(event));input.focus=true
app.pictureInPictureActive=false;precondition(!input.handlePictureInPictureCornerKey(event));app.pictureInPictureActive=true
app.windowGeometryTransitionActive=true;precondition(!input.handlePictureInPictureCornerKey(event));app.windowGeometryTransitionActive=false
precondition(app.writes.count==writes)
UserDefaults.standard.removeObject(forKey:"gor.pip.preferredFrame")
let opening=PlayerPictureInPicture.frame(current:original,visible:bounds[0])
precondition(opening.minX==0 && opening.minY==0,"bottom-left opening stays unchanged")
print("PASS \\(cases) production directional corner reducer cases (16 table x2 sizes x2 screens), edge no-op, physical fn aliases, ordinary arrow isolation, focus/modifier/mode guards, rapid up-right target, default bottom-left")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(code)
    subprocess.run([os.environ.get('SWIFTC', 'swiftc'), str(path / 'main.swift'), '-o', str(path / 'check')], check=True)
    subprocess.run([str(path / 'check')], check=True)
body = block(features, '    private func handleSpecialKeyCommands(')
assert body.index('handlePictureInPictureCornerKey(event)') < body.index('if keyCode == 123')
print('PASS actual key ownership source: PiP corner route precedes volume/seek, normal snapped windows unchanged; Linux only, native key events/window motion not proven')
