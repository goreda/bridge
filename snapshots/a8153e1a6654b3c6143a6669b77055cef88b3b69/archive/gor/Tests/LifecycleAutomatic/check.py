from pathlib import Path
import ast,tempfile,subprocess,os,time
p=Path(__file__).resolve().parents[2]/'gor-selftest.sh'
s=p.read_text().split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0];tree=ast.parse(s)
common={n.name:n for n in tree.body if isinstance(n,ast.FunctionDef)}
assert {'spawn_detached','quit_instance'}<=common.keys()
# Execute the actual automatic post-feature l5/l6 path, isolating only the Mac app/process boundary.
start=s.index('    # l5: a detached');end=s.index('\nexcept Exception as error:',start)
segment='\n'.join(l[4:] if l.startswith('    ') else l for l in s[start:end].splitlines())
ns={'Path':Path,'subprocess':subprocess,'tempfile':tempfile,'os':os,'time':time}
for name in ['spawn_detached','quit_instance']:exec(compile(ast.Module(body=[common[name]],type_ignores=[]),str(p),'exec'),ns)
with tempfile.TemporaryFile() as log:
 ns.update(log=log)
 # Actual common spawn helper executes an owned harmless process. No app/mpv/screen required.
 pid=ns['spawn_detached'](['/bin/sleep','0.1']);assert pid>0
 events=[];owned=[];aliveCalls=[0]
 def isAlive(p):
  aliveCalls[0]+=1;return aliveCalls[0]==1
 class Boundary:
  @staticmethod
  def run(*a,**kw):return type('R',(),{'returncode':0})()
 ns.update(mpv=Path('/owned/mpv'),app=Path('/owned/gor.app'),clip=Path('/owned/clip'),owned=owned,
   identity=lambda p:('stamp',str(p)),ps=lambda p,f:'1',alive=isAlive,
   wait=lambda f,t:f(),note=lambda ok,n,d:events.append((ok,n)),note_skip=lambda n,d:events.append((None,n)),
   gor_pids=lambda:[123],stop_owned=lambda *a:None,subprocess=Boundary,
   spawn_detached=ns['spawn_detached'],quit_instance=lambda gp:events.append((True,'quit-called')))
 # Keep real helper call with OS subprocess while virtualizing AppKit boundary only.
 original=ns['spawn_detached'];ns['spawn_detached']=lambda cmd:original(['/bin/sleep','0.1'])
 ns['subprocess']=subprocess
 # Need app launch boundary only, not helper subprocess.run itself.
 realrun=subprocess.run
 def run(cmd,*a,**kw):
  if cmd and cmd[0]=='/usr/bin/open':return type('R',(),{'returncode':0})()
  return realrun(cmd,*a,**kw)
 subprocess.run=run
 try:exec(compile(segment,str(p), 'exec'),ns)
 finally:subprocess.run=realrun
 assert (True,'l5') in events and (None,'l6') in events,events
 print('PASS actual automatic l5/l6 branch reaches l5 verdict+l6skip, actual common detached helper executed; AppKit boundary stubbed, no native PASS')
# Cross-mode function audit: only helper refs shared after full branch must exist in common scope.
for n in ast.walk(tree):
 if isinstance(n,ast.If) and "GOR_LIFETIME_FULL" in ast.unparse(n.test) and len(n.body)>20:
  defs={x.name for x in n.body if isinstance(x,ast.FunctionDef)}
  for outer in ast.walk(tree):
   if hasattr(outer,'body') and isinstance(outer.body,list) and n in outer.body:
    calls={x.func.id for z in outer.body[outer.body.index(n)+1:] for x in ast.walk(z) if isinstance(x,ast.Call) and isinstance(x.func,ast.Name)}
    assert not (defs&calls),defs&calls
print('PASS full-mode helper definitions not referenced by later automatic branch')
