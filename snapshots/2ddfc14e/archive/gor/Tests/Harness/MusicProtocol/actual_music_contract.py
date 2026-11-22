from pathlib import Path
import ast, hashlib, json, re, shutil, subprocess, sys, tempfile, os
ROOT=Path(__file__).resolve().parents[3]
s=(ROOT/'Sources/gor/Modes/MusicController.swift').read_text()
b=(ROOT/'Resources/vendor/mus2/mus2.py').read_text()
def body_after(text, marker):
 start=text.index(marker)+len(marker); depth=1; i=start
 while depth:
  if text[i]=='{': depth+=1
  elif text[i]=='}': depth-=1
  i+=1
 return text[start:i-1]
send=body_after(s,'func send(_ command: String) {')
reader=s[s.index('            // TRAP-11: buffer raw Data'):s.index('\n        do { try task.run()')]
reader=reader[:reader.rfind('\n        }')]
assert 'guard let self, !self.quitDetached, self.generation == gen else { return }' in s
# Execute actual parser assignments and the search/index/path branches only, not module startup.
tree=ast.parse(b); main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main')
loop=next(n for n in main.body if isinstance(n,ast.For))
branch=next(n for n in loop.body if isinstance(n,ast.If) and isinstance(n.test,ast.Compare) and ast.unparse(n.test)=='cmd == \'search\'')
assignments=[n for n in loop.body[:loop.body.index(branch)] if isinstance(n,ast.Assign)]
def run(command):
 calls=[];rows=[]
 cache=[{'source':'archive','title':x} for x in ['Miles Davis live','Miles alone','Björk live','Björk other']]
 env={'line':command,'cache':cache,'re':re,'ensure_archive_cache':lambda c:c,'search_bc_artist':lambda q:calls.append(('search',q)) or 'https://artist.bandcamp.com', 'fetch_bc_artist':lambda u:[{'source':'bandcamp','title':'provider result','domain':'artist.bandcamp.com'}], 'save_cache':lambda c:None,'items_with_idx':lambda a,c:a,'emit':rows.append,'log':lambda *a:None,'play_archive_track':lambda a,n:calls.append(('track',a['title'],n)), 'scan_local_path':lambda p:calls.append(('path',p)) or [],'os':os}
 selected=branch
 while isinstance(selected,ast.If):
  if ast.unparse(selected.test) in ["cmd == 'search'","cmd == 'play_track'","cmd == 'local_browse'"]:
   node=ast.If(test=selected.test,body=selected.body,orelse=[])
   exec(compile(ast.fix_missing_locations(ast.Module(body=assignments+[node],type_ignores=[])),'actual-search-parser','exec'),env)
  selected=selected.orelse[0] if len(selected.orelse)==1 else None
 return calls,rows
for query,expected in [('Miles Davis',['Miles Davis live']),('Björk live',['Björk live']),('Miles  Davis',[]),('', ['Miles Davis live','Miles alone','Björk live','Björk other'])]:
 calls,rows=run('search '+query)
 assert calls==[('search',query)],calls
 assert [a['title'] for a in rows[0]['items'] if a['source']=='archive']==expected
assert run('play_track 0 3')[0]==[('track','Miles Davis live',3)]
assert run('local_browse /music/Miles Davis/Live Set')[0]==[('path','/music/Miles Davis/Live Set')]
print('PASS actual parser/search/provider/index/path checks')
# Actual Swift method/reader bodies, with fake transport and deterministic lock-boundary restart.
harness='''import Foundation
final class Writer { var rows:[Data]=[]; func write(_ data:Data) { rows.append(data) } }
final class FakePipe { let fileHandleForWriting=Writer() }
final class HookLock {
 var locked=false; var onUnlock:(()->Void)?
 func lock(){ precondition(!locked); locked=true }
 func unlock(){ precondition(locked); locked=false; let hook=onUnlock;onUnlock=nil;hook?() }
}
final class Subject {
 var isRunning=true; var stdinPipe:FakePipe?=FakePipe()
 let stdoutLock=HookLock();var generation=1;var stdoutBuffer=Data();var lines:[String]=[]
 func handleJSON(_ line:String,gen:Int){if generation==gen {lines.append(line)}}
 func send(_ command:String){SEND}
 func read(_ data:Data,gen:Int){READER}
}
func check(_ ok:Bool,_ message:String){if !ok {fatalError(message)}}
let a=Subject()
for command in ["search Miles Davis","search café 😀","search jazz\\nquit","a\\rb\\r\\nc",""] {
 a.send(command)
 let expected=command.replacingOccurrences(of:"\\r",with:" ").replacingOccurrences(of:"\\n",with:" ")+"\\n"
 check(a.stdinPipe!.fileHandleForWriting.rows.last==Data(expected.utf8),"send preserves sanitized exact bytes")
 check(a.stdinPipe!.fileHandleForWriting.rows.last!.filter{$0==10}.count==1,"one line")
}
let count=a.stdinPipe!.fileHandleForWriting.rows.count;a.isRunning=false;a.send("quit");check(a.stdinPipe!.fileHandleForWriting.rows.count==count,"stopped no write")
a.isRunning=true;a.stdinPipe=nil;a.send("nil pipe")
let old=Subject();old.stdoutLock.onUnlock={old.generation=2;old.stdoutBuffer.removeAll()}
old.read(Data("OLD".utf8),gen:1);old.read(Data("new\\n".utf8),gen:2)
check(old.lines==["new"],"retired bytes must not prefix new process")
let stale=Subject();stale.generation=2;stale.read(Data("old".utf8),gen:1);check(stale.stdoutBuffer.isEmpty,"stale rejected before append")
let wire=Data("café 😀\\n".utf8)
for split in 0...wire.count {let x=Subject();x.read(Data(wire.prefix(split)),gen:1);x.read(Data(wire.dropFirst(split)),gen:1);check(x.lines==["café 😀"],"UTF8 byte split")}
let big=Subject();big.read(Data(repeating:65,count:4*1_048_576+1),gen:1);check(big.stdoutBuffer.isEmpty,"oversize reset")
print("PASS actual extracted Swift send and reader checks")
'''.replace('SEND',send).replace('READER',reader)
out=Path(os.environ.get('MUSIC_TEST_WORK',tempfile.gettempdir()))/'music-actual-harness.swift';out.write_text(harness)
compiler=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not compiler:
 print('Swift execution NOT_RUN; actual extracted harness:',out)
 sys.exit(2)
subprocess.run([compiler,str(out),'-o',str(out.with_suffix(''))],check=True)
subprocess.run([str(out.with_suffix(''))],check=True)
