#!/usr/bin/env python3
"""Source-bound typed torrent profile. Actual Swift encoder/operations plus recording composition."""
from pathlib import Path
import os,shutil,subprocess,tempfile,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
def unit(text,signature):
 start=text.index(signature);brace=text.index('{',start);depth=0
 for i in range(brace,len(text)):
  if text[i]=='{':depth+=1
  elif text[i]=='}':
   depth-=1
   if depth==0:return text[start:i+1]
 raise AssertionError(signature)
manager=(ROOT/'Sources/gor/Media/TorrentManager.swift').read_text()
menu=(ROOT/'Sources/gor/UI/MenuActions.swift').read_text()
backend=(ROOT/'Sources/gor/Engine/MPVCommand.swift').read_text()
assert 'controller?.ipcCommand(' not in manager
assert '"command"' not in manager, 'torrent intent must not construct wire commands'
assert manager.count('torrentPlaybackOperations.applyStreamingProfile(cacheSeconds:cacheSecs,demuxerMaxBytes:demuxerMaxBytes)')==1
assert manager.count('torrentPlaybackOperations.endSession()')==1
stream=manager[manager.index('} else if l.hasPrefix("STREAM:")'):]
assert stream.index('owner.torrentProcess === p')<stream.index('PlayerTorrentEndpoint.admit(url)')<stream.index('restoreDefaultProfile()')<stream.index('torrentPlaybackOperations.applyStreamingProfile')<stream.index('torrentBrowserPanel?.removeFromSuperview()')
teardown=manager[manager.index('guard hadActiveSession else { return }'):]
assert teardown.index('hideStreamControls()')<teardown.index('torrentPlaybackOperations.endSession()')
composition=unit(menu,'var torrentPlaybackOperations:TorrentPlaybackOperations')
assert '[weak self]' in composition and 'self?.controller?.ipcCommand($0)' in composition
operations=unit(backend,'struct TorrentPlaybackOperations {')
make=unit(backend,'static func make(_ args:')
prefix='''import Foundation
'''+ 'enum MPVCommand {\n'+make+'\n}\n'
tests=r'''
func demand(_ x:@autoclosure()->Bool){precondition(x())}
func decoded(_ lines:[String])->[[String]] {
 lines.map { line in
  let value=try! JSONSerialization.jsonObject(with:Data(line.utf8)) as! [String:Any]
  return value["command"] as! [String]
 }
}
for (cache,bytes) in [(0,0),(120,250000000),(Int.max,Int.max),(-1,-1000001)] {
 var calls:[String]=[]
 let operations=TorrentPlaybackOperations(command:{calls.append($0)})
 operations.applyStreamingProfile(cacheSeconds:cache,demuxerMaxBytes:bytes)
 let expected:[[String]]=[
 ["set","cache","yes"],["set","cache-secs",String(cache)],["set","cache-pause-initial","yes"],
 ["set","demuxer-readahead-secs",String(cache)],["set","demuxer-max-bytes","\(bytes / 1_000_000)M"],
 ["set","hwdec","auto-safe"],["set","cache-pause","no"],["set","vd-lavc-skiploopfilter","all"]]
 demand(decoded(calls)==expected)
 demand(calls.allSatisfy{!$0.contains("\n") && !$0.contains("\r")})
 operations.endSession()
 demand(decoded(Array(calls.suffix(2)))==[["script-message-to","photon","set-live","false"],["set","hwdec","auto-safe"]])
 demand(calls.count==10)
}
final class Controller {var calls:[String]=[];func ipcCommand(_ s:String){calls.append(s)}}
final class Host {
 var controller:Controller?
COMPOSITION
}
let sink=Controller();var host:Host?=Host();host!.controller=sink
let operation=host!.torrentPlaybackOperations
operation.endSession();demand(sink.calls.count==2)
host!.controller=nil;operation.endSession();demand(sink.calls.count==2)
host!.controller=sink;host=nil;operation.endSession();demand(sink.calls.count==2)
print("PASS actual typed profile/teardown exact8+2args/order/units, boundary values, weak composition")
'''.replace('COMPOSITION',composition)
mutants={
 'cache_pause':operations.replace('["set","cache-pause","no"]','["set","cache-pause","yes"]'),
 'units':operations.replace('demuxerMaxBytes / 1_000_000','demuxerMaxBytes / 1024'),
 'teardown_live':operations.replace('["script-message-to","photon","set-live","false"]','["script-message-to","photon","set-live","true"]'),
 'teardown_order':operations.replace('command(MPVCommand.make(["script-message-to","photon","set-live","false"]))\n        command(MPVCommand.make(["set","hwdec","auto-safe"]))','command(MPVCommand.make(["set","hwdec","auto-safe"]))\n        command(MPVCommand.make(["script-message-to","photon","set-live","false"]))')}
compiler=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not compiler:raise SystemExit('NOT_RUN Swift compiler unavailable')
records=[]
with tempfile.TemporaryDirectory() as directory:
 tmp=Path(directory)
 for name,candidate in [('baseline',operations)]+list(mutants.items()):
  if name!='baseline':assert candidate!=operations
  swift=tmp/'main.swift';swift.write_text(prefix+candidate+tests)
  for opt in ['-Onone','-O']:
   binary=tmp/'check'
   build=subprocess.run([compiler,'-swift-version','5',opt,str(swift),'-o',str(binary)],capture_output=True,text=True)
   assert build.returncode==0,build.stdout+build.stderr
   result=subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
   assert (result.returncode==0)==(name=='baseline'),(name,result.stdout,result.stderr)
   records.append({'name':name,'opt':opt,'exit':result.returncode,'swift_sha256':hashlib.sha256(swift.read_bytes()).hexdigest()})
   print(name,opt,result.returncode,result.stdout.strip())
print(json.dumps({'records':records,'scope':'actual encoder+typed operations+weak composition; source guards unchanged; native torrent/helper/AppKit playback NOT_RUN'},indent=2))
