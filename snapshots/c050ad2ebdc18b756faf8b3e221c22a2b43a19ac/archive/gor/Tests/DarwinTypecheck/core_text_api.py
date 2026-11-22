"""Compile extracted production ink measurement with real CF cast and Foundation key semantics.
Linux has no CoreText. An imported CF opaque type preserves Swift's CF downcast rule;
Foundation supplies the real NSAttributedString attributes-key signature. This is not
an SDK/AppKit or full-app compile. macOS uses the actual CoreText/CATextLayer APIs.
"""
from pathlib import Path
import os,subprocess,tempfile,sys

def body(text):
    start=text.index('private func measureInk(');brace=text.index('{',start);depth=1;i=brace+1
    while depth:
        depth+=(text[i]=='{')-(text[i]=='}');i+=1
    return text[start:i]

def run():
    root=Path(__file__).resolve().parents[2]
    source=body((root/'Sources/gor/Modes/MusicPanel.swift').read_text())
    native=sys.platform=='darwin'
    preamble='import Foundation\n'
    if native:
        preamble+='import QuartzCore\nimport CoreText\nclass Probe { let textLayer=CATextLayer()\n'
    else:
        preamble+='''import CoreFoundation
typealias CTFont=CFBinaryHeap
let kCTFontAttributeName=CFStringCreateWithCString(nil,"NSFont",CFStringBuiltInEncodings.UTF8.rawValue)!
func CTLineCreateWithAttributedString(_ s:NSAttributedString)->Int {0}
func CTLineGetTypographicBounds(_ l:Int,_ a:UnsafeMutablePointer<CGFloat>?,_ b:UnsafeMutablePointer<CGFloat>?,_ c:UnsafeMutablePointer<CGFloat>?)->Double {0}
struct CTLineBoundsOptions:OptionSet {let rawValue:Int;static let useGlyphPathBounds=Self(rawValue:1)}
func CTLineGetBoundsWithOptions(_ l:Int,_ o:CTLineBoundsOptions)->CGRect {.zero}
extension NSAttributedString.Key {static let font=Self("NSFont")}
struct TextLayer {var font:AnyObject?}
class Probe { let textLayer=TextLayer()
'''
    def compile(method):
        if not native:
            # The explicit toll-free bridge is Darwin-only; preserve the resulting String type.
            method=method.replace('kCTFontAttributeName as String','"NSFont"')
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'ink-api.swift';p.write_text(preamble+method+'\n}\n')
            return subprocess.run([os.environ.get('SWIFTC','swiftc'),'-typecheck','-swift-version','5',str(p)],capture_output=True,text=True)
    # Independent mutants pin the two actual 14:20 Mac compiler errors.
    cast='private func measureInk(_ s:String)->CGFloat { guard let font=textLayer.font as? CTFont else{return 0};return 0 }'
    key='private func measureInk(_ s:String)->CGFloat { let font=textLayer.font as! CTFont;_ = NSAttributedString(string:s,attributes:[kCTFontAttributeName:font]);return 0 }'
    for name,mutant,diagnostic in [('CF cast',cast,'conditional downcast to CoreFoundation type'),('attribute key',key,"expected dictionary key type 'NSAttributedString.Key'")]:
        bad=compile(mutant)
        assert bad.returncode!=0 and diagnostic in bad.stderr,(name,bad.stderr)
    actual=compile(source)
    if actual.returncode:raise AssertionError('production measureInk API probe:\n'+actual.stderr)
    print('PASS C1 extracted CoreText ink API: production compiles; real CF-cast and attributes-key mutants rejected; '+('macOS SDK' if native else 'Linux CF/Foundation signature probe, NOT full macOS compile'))

if __name__=='__main__':run()
