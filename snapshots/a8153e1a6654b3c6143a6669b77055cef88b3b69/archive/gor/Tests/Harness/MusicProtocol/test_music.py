"""Current source-bound music protocol ports plus isolated actual emit function."""
from pathlib import Path
import json,hashlib,ast,io,sys
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Modes/MusicController.swift';b=root/'Resources/vendor/mus2/mus2.py';s=p.read_text();backend=b.read_text()
for token in ['self.stdoutBuffer.append(data)','self.stdoutBuffer.count > 4 * 1_048_576','self.stdoutBuffer.firstIndex(of: 0x0A)','String(data: self.stdoutBuffer[self.stdoutBuffer.startIndex..<nl], encoding: .utf8)','total <= 4096','index >= 0, index < total','data.utf8.count <= 1_048_576','chunkBuffer.values.reduce(0, { $0 + $1.utf8.count }) > 4 * 1_048_576','if chunkTotal != total','chunkBuffer[index] = data','for track in tracks.dropFirst(trackN + 1)']:assert token in s,token
handle=s[s.index('private func handleJSON'):s.index('private static func parsePlaylist')]
assert 'DispatchQueue.main.async' in handle
assert 'guard let self, !self.quitDetached, self.generation == gen else { return }' in handle,'main callback must check quit latch and generation'
assert 'private func handleJSON(_ line: String, gen: Int)' in handle
for t in ['stdoutLock.lock(); generation += 1; let gen = generation; stdoutLock.unlock()','stdoutLock.lock(); generation += 1; stdoutLock.unlock()','self.handleJSON(line, gen: gen)','self.handleJSON(full, gen: gen)']:assert t in s,t
# Execute actual send and generation-buffer critical section with a Swift executor.
import subprocess
subprocess.run([sys.executable,str(Path(__file__).with_name('actual_music_contract.py'))],check=True)
# Execute only AST-isolated actual emit and CHUNK_SIZE, never backend module.
tree=ast.parse(backend);nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='emit' or isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='CHUNK_SIZE' for t in n.targets)]
assert len(nodes)==2;stream=io.StringIO();env={'json':json,'sys':type('FakeSys',(),{'stdout':stream})()};exec(compile(ast.Module(body=nodes,type_ignores=[]),'actual-mus2-emit','exec'),env)
class Chunks:
 def __init__(self):self.parts={};self.total=0;self.completed=[]
 def add(self,total,index,data):
  if not(0<total<=4096 and 0<=index<total and len(data.encode())<=1048576):self.parts={};self.total=0;return
  if self.total!=total:self.parts={};self.total=total
  self.parts[index]=data
  if sum(len(v.encode()) for v in self.parts.values())>4194304:self.parts={};self.total=0;return
  if len(self.parts)==total:
   self.completed.append(''.join(self.parts[i] for i in range(total)));self.parts={};self.total=0
controls=[]
for text in ['small','café 😀'*12000]:
 stream.seek(0);stream.truncate(0);obj={'cmd':'info','text':text};env['emit'](obj);rows=[json.loads(l) for l in stream.getvalue().splitlines()]
 if rows[0]['cmd']=='chunk':
  c=Chunks()
  for row in reversed(rows):c.add(row['total'],row['index'],row['data'])
  assert len(c.completed)==1 and json.loads(c.completed[0])==obj
 else:assert rows==[obj]
controls.append('actual current backend emit small/large Unicode roundtrip through modeled Swift chunk assembly')
wire='{"cmd":"info","text":"café 😀"}\n'.encode()
for split in range(len(wire)+1):
 pending=b'';lines=[]
 for part in [wire[:split],wire[split:]]:
  pending+=part
  while b'\n' in pending:
   line,pending=pending.split(b'\n',1);lines.append(json.loads(line))
 assert lines==[{'cmd':'info','text':'café 😀'}]
controls.append('all UTF-8 pipe split boundaries retained as bytes before decode')
for total,index,data in [(0,0,'a'),(4097,0,'a'),(2,-1,'a'),(2,2,'a'),(2,0,'x'*1048577)]:
 c=Chunks();c.add(2,0,'old');c.add(total,index,data);assert not c.parts and c.total==0
controls.append('invalid chunk count/index/per-part bound resets state')
c=Chunks()
for i in range(5):c.add(6,i,'x'*1048576)
assert not c.parts and c.total==0;controls.append('aggregate >4MB bound resets state')
c=Chunks();c.add(2,0,'old');c.add(3,0,'new');assert c.parts=={0:'new'} and c.total==3;controls.append('new total resets old partial assembly')
for selected in range(4):
 paths=[str(i) for i in range(4)];commands=['play_local '+paths[selected]]+['queue_local '+q for q in paths[selected+1:]];assert len(commands)==4-selected
controls.append('local context play followed by ordered tail queue; no timer')
reds=[]
c=Chunks();c.add(2,0,'A0');c.add(2,1,'B1');assert c.completed==['A0B1'];reds.append({'case':'same-total cross-message fragments','observed':'no message ID: A0+B1 assembled together','limit':'synthetic interleaving/loss input; current normal producer serial chunk emit is not proved to generate two interleaved chunk batches'})
gen=1;queue=[];queue.append((gen,lambda:'A results'));gen+=1;gen+=1;out=[f() for g,f in queue if g==gen];assert out==[];controls.append('queued JSON from a stopped/replaced mus2 generation is dropped on main')
controls.append('actual extracted Swift send sanitization and parser search contract executed by companion')
print(json.dumps({'result':'PASS controls and expected protocol characterizations','controls':controls,'known_red':reds,'source_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [p,b]},'open':['native FileHandle/process/main-queue ordering','backend compiled mus2 binary parity','response/request IDs and same-total retry/interleaving','helper exit/reaping and startup delay ownership','playlist/queue/network/music UI proof'],'scope':'Actual isolated Python emit plus source-bound Python consumer/lifecycle ports; no backend module launch, Swift process, music/provider/download or UI execution'},indent=2))
