#!/usr/bin/env python3
"""arch-198y: typed preview transport preserves the actual quit call and lifecycle."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
# Whole-file adoption proof stays historical, never a current-host freeze.
path = 'Sources/gor/Media/FileBrowser.swift'
after = (ROOT / path).read_text()
replacement = '{ HoverPreviewTransport.quit(socketPath: path) }'
assert after.count(replacement) == 1
start=after.index('private func stopPreview()')
brace=after.index('{',start);depth=0
for end in range(brace,len(after)):
    if after[end]=='{':depth+=1
    elif after[end]=='}':
        depth-=1
        if depth==0:break
stop=after[start:end+1].replace('private func','func',1)
for token in ['previewStart?.cancel()', 'PreviewGuard.terminate(process, gracefulQuit: socketPath.map', replacement,
              'previewWork?.cancel()', 'previewProcess = nil', 'previewSocketPath = nil', 'previewPollToken = nil']:
    assert token in stop, token
source = (ROOT / 'Sources/gor/Engine/MPVCommand.swift').read_text()
seam = source.split('// BEGIN hover preview quit transport (arch-198y)\n')[1].split('// END hover preview quit transport')[0]
# The actual quit operation now calls the backend serializer. Compile its real
# enum too, rather than weakening the established exact-byte contract.
a=source.index('enum MPVCommand {');i=source.index('{',a);depth=1;j=i+1
while depth:
    depth+=(source[j]=='{')-(source[j]=='}');j+=1
seam=source[a:j]+'\n'+seam

with tempfile.TemporaryDirectory() as directory:
    tmp = Path(directory)
    (tmp / 'main.swift').write_text('''import Foundation
var calls: [(String, String, TimeInterval, Bool)] = []
enum IPCClient {
    static func socketRoundtrip(path: String, payload: String, timeout: TimeInterval, sendOnly: Bool) -> [String] {
        calls.append((path, payload, timeout, sendOnly))
        return []
    }
}
''' + seam + '''
let path = "/tmp/preview socket.sock"
// Old closure and new typed closure must send the exact same one-message request.
let old = { _ = IPCClient.socketRoundtrip(path: path, payload: "{\\"command\\":[\\"quit\\"]}\\n", timeout: 0.25, sendOnly: true) }
old()
HoverPreviewTransport.quit(socketPath: path)
precondition(calls.count == 2)
precondition(calls[0].0 == calls[1].0 && calls[0].1 == calls[1].1)
precondition(calls[0].2 == calls[1].2 && calls[0].3 == calls[1].3)
precondition(calls[1].0 == path && calls[1].2 == 0.25 && calls[1].3)
print("PASS identical path/payload/timeout/sendOnly and one call per quit")
var lifecycle:[String]=[]
final class Work {let name:String;init(_ n:String){name=n};func cancel(){lifecycle.append(name)}}
enum PreviewGuard {
static func terminate(_ process:Int,gracefulQuit:(()->Void)?){lifecycle.append("terminate");gracefulQuit?()}
}
final class Host {
var previewStart:Work?=Work("start-cancel")
var lastPreviewSeek:Double=12
var previewPollToken:Int?=1
var previewProcess:Int?=42
var previewSocketPath:String?="/tmp/actual socket.sock"
var previewWork:Work?=Work("work-cancel")
''' + stop + "\n}\n" + ''' 
let host=Host();host.stopPreview()
precondition(lifecycle==["start-cancel","terminate","work-cancel"])
precondition(host.previewStart==nil && host.previewWork==nil && host.previewProcess==nil && host.previewSocketPath==nil && host.previewPollToken==nil && host.lastPreviewSeek==0)
precondition(calls.count==3 && calls.last!.0=="/tmp/actual socket.sock")
lifecycle=[];host.stopPreview();precondition(lifecycle.isEmpty && calls.count==3)
print("PASS actual stopPreview cancellation/reset/idempotent teardown, recorder boundary")
''')
    subprocess.run([os.environ.get('SWIFTC', 'swiftc'), '-O', str(tmp / 'main.swift'), '-o', str(tmp / 'test')], check=True)
    subprocess.run([str(tmp / 'test')], check=True)
print('PASS current exact quit closure and actual stopPreview recorder execution; no EOF/signal/native scheduling claim')

# Counter semantics use actual compiler-produced fixture graph, not implementation text.
import importlib.util
from collections import Counter
spec = importlib.util.spec_from_file_location('architecture_guard', ROOT / 'tools/architecture.py')
module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    fixture=Path(directory)
    (fixture/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name:"BoundaryFixture",targets:[.target(name:"gor",path:"Sources/gor")])
''')
    rows=[]
    paths=[('Sources/gor/GorMPVBackend/Owner.swift',True),('Sources/gor/GorMPVBackendFake/Owner.swift',False),('Sources/gor/Media/Browser.swift',False),('Sources/gor/Engine/MPVCommand.swift',True),('Sources/gor/Engine/GorAVAppGate.swift',False),('Sources/gor/Engine/Unlisted.swift',False)]
    for path,permitted in paths:
        target=fixture/path;target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text('let value = IPCClient.socketRoundtrip\nlet value = IPCClient.socketRoundtrip\n')
        rows.append([path,'swift','gor','GorMPVBackend','fixture','2',''])
    targets,errors=module.graph(fixture)
    assert not errors, errors
    counts=module.violations(fixture,rows,targets)
    assert isinstance(counts,Counter)
    for path,permitted in paths:
        mpv={rule:n for (file,rule),n in counts.items() if file==path and rule.startswith('mpv:')}
        assert (not mpv)==permitted, (path,counts)
        if not permitted:assert list(mpv.values())==[2],mpv
    unknown='Outside/Orphan.swift';(fixture/'Outside').mkdir();(fixture/unknown).write_text('let x=1\n')
    unresolved=module.violations(fixture,[[unknown,'swift','gor','gor','fixture','1','']],targets)
    assert unresolved[unknown,'membership:unassigned']==1
print('PASS exact backend prefix accepted; lookalike/browser rejected twice by Counter; real compiler graph; unassigned remains RED')
