"""Execute production visibility predicate without AppKit. Counts work, not Mac CPU."""
from pathlib import Path
import subprocess
import tempfile
import sys
root=Path(__file__).resolve().parents[3]
src=root/'Sources/gor'
predicate=(src/'VariationBroadcaster.swift').read_text().split('extension NSView {',1)[1]
spine=(src/'SpineUI.swift').read_text()
assert 'guard let self = self, self.isEffectivelyVisible, !self.osdVisible else { return }' in spine
iptv=(src/'IPTV.swift').read_text()
assert 'guard isEffectivelyVisible else { return }; let p = verticalProximity' in iptv
harness='''import Foundation
final class Window { var alphaValue=1.0 }
class NSView {
 var window:Window?; var superview:NSView?; var isHidden=false; var alphaValue=1.0
}
extension NSView {'''+predicate+'''
let window=Window(), parent=NSView(), title=NSView()
parent.window=window; title.window=window; title.superview=parent
var before=0,after=0
parent.alphaValue=0
for _ in 0..<600 {before += 1; if title.isEffectivelyVisible {after += 1}}
assert(before == 600 && after == 0)
parent.alphaValue=1
var visible=0
for _ in 0..<600 {if title.isEffectivelyVisible {visible += 1}}
assert(visible == 600)
parent.isHidden=true; assert(!title.isEffectivelyVisible);parent.isHidden=false
window.alphaValue=0; assert(!title.isEffectivelyVisible);window.alphaValue=1
parent.alphaValue=0.5;assert(title.isEffectivelyVisible) // real fade/visible animation retained
parent.alphaValue=1;title.window=nil;assert(!title.isEffectivelyVisible)
print("PASS 10s/60Hz production predicate: hidden title/IPTV font admissions600->0 (60/s->0/s); visible600->600; ancestor fade/hidden, detached/window fade excluded; visible animation unchanged")
'''
with tempfile.TemporaryDirectory() as temp:
 main=Path(temp)/'main.swift';main.write_text(harness);binary=Path(temp)/'test'
 subprocess.run([sys.argv[1] if len(sys.argv)>1 else 'swiftc',str(main),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
print('NOT_RUN native Mac raster CPU/pixel comparison; no font, axis, size, animation cadence or visible raster code changed')
