#!/usr/bin/env python3
"""Linux fixture preflight. Syntax checks are lint, never Darwin compilation."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import argparse,ast,hashlib,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True
VERSION=1
GENERATED={'.DS_Store','__pycache__'}
CG=re.compile(r'\b(?:CGFloat|CGPoint|CGSize|CGRect|CGVector|CGAffineTransform|CGColor|CGPath|CGMutablePath|CGImage|CGContext|CGDataProvider|CGColorSpace)\b')
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def carrier(root,manifest):
 root=Path(root);m=json.loads(Path(manifest).read_text());errors=[]
 for p in root.rglob('*'):
  if p.is_symlink():errors.append('symlink not supported '+str(p.relative_to(root)));continue
  if p.name in GENERATED or p.suffix=='.pyc':errors.append('generated '+str(p.relative_to(root)))
 files=m.get('files')
 if not isinstance(files,dict) or not m.get('source_pin'):return errors+['manifest requires files map and source_pin']
 for n,h in files.items():
  if Path(n).is_absolute() or '..' in Path(n).parts or not re.fullmatch('[0-9a-f]{64}',str(h)):return errors+['invalid manifest entry '+n]
 expected={n for n in files if n.startswith('payload/gor/')};actual={str(p.relative_to(root)) for p in (root/'payload/gor').rglob('*') if p.is_file()}
 for n in sorted(actual-expected):errors.append('envelope extra '+n)
 for n in sorted(expected-actual):errors.append('envelope missing '+n)
 for n,h in files.items():
  p=root/n
  if not p.is_file():errors.append('manifest missing '+n)
  elif digest(p)!=h:errors.append('manifest hash '+n)
 return errors
# Lexer preserves line numbers and removes comments/string contents. Swift nested
# block comments and common raw/multiline strings are handled, no type inference.
def code(s):
 out=list(s);i=0;n=len(s)
 def erase(a,b):
  for j in range(a,b):
   if out[j]!='\n':out[j]=' '
 while i<n:
  if s.startswith('//',i):
   b=s.find('\n',i);b=n if b<0 else b;erase(i,b);i=b
  elif s.startswith('/*',i):
   a=i;i+=2;depth=1
   while i<n and depth:
    if s.startswith('/*',i):depth+=1;i+=2
    elif s.startswith('*/',i):depth-=1;i+=2
    else:i+=1
   erase(a,i)
  elif s[i]=='"' or (s[i]=='#' and re.match(r'#+"',s[i:])):
   a=i;m=re.match(r'(#+)?("""|")',s[i:]);hashes=m[1] or '';q=m[2];i+=len(m[0]);end=q+hashes
   while i<n:
    if s.startswith('\\'+hashes,i):i+=len(hashes)+2
    elif s.startswith(end,i):i+=len(end);break
    else:i+=1
   erase(a,min(i,n))
  else:i+=1
 return ''.join(out)
def condition(expr,target):
 expr=expr.strip()
 if '||' in expr:
  vals=[condition(x,target) for x in expr.split('||')]
  return True if True in vals else (None if None in vals else False)
 if '&&' in expr:
  vals=[condition(x,target) for x in expr.split('&&')]
  return False if False in vals else (None if None in vals else True)
 if expr.startswith('!'):
  v=condition(expr[1:],target);return None if v is None else not v
 if expr in ('canImport(Darwin)','os(macOS)','canImport(CoreGraphics)','canImport(AppKit)'):return target=='darwin'
 if expr in ('canImport(Glibc)','os(Linux)'):return target=='linux'
 if expr=='true':return True
 if expr=='false':return False
 return None

def active(s,target='darwin',definite=False):
 def land(a,b):return False if a is False or b is False else True if a is True and b is True else None
 def lor(a,b):return True if a is True or b is True else False if a is False and b is False else None
 def neg(a):return None if a is None else not a
 stack=[];on=True;out=[]
 for l in s.splitlines(True):
  m=re.match(r'\s*#(if|elseif|else|endif)\b(.*)',l)
  if m:
   op,expr=m.groups()
   if op=='if':
    c=condition(expr,target);stack.append([on,c]);on=land(on,c)
   elif op=='elseif' and stack:
    parent,taken=stack[-1];c=condition(expr,target);on=land(parent,land(neg(taken),c));stack[-1][1]=lor(taken,c)
   elif op=='else' and stack:parent,taken=stack[-1];on=land(parent,neg(taken));stack[-1][1]=True
   elif op=='endif' and stack:on=stack.pop()[0]
   else:raise ValueError('unbalanced conditional')
   out.append('\n')
  else:out.append(l if (on is True if definite else on is not False) else '\n')
 if stack:raise ValueError('unclosed conditional')
 return ''.join(out)
def actor_types(s):
 return set(re.findall(r'@MainActor\s+(?:(?:public|private|final|internal|open|static|nonisolated|unsafe)\s+)*(?:class|struct|enum|func)\s+(\w+)',code(s)))
def swift(s,actors=()):
 errors=[];clean=code(s)
 try:d=active(clean)
 except ValueError as e:return [str(e)]
 if re.search(r'\bimport\s+Glibc\b',d):errors.append('darwin-import: Glibc active for Darwin')
 if CG.search(d) and not re.search(r'\bimport\s+CoreGraphics\b',active(clean,definite=True)):errors.append('coregraphics-import: explicit import CoreGraphics missing')
 # Scoped actor lint, not a Swift typechecker. No inference through alias calls,
 # extensions, protocols or imported SDK symbols. Supply actor sources explicitly.
 names=set(actors)|actor_types(s);variables=set();scopes=[];pending=False
 tokens=list(re.finditer(r'@MainActor|MainActor\.assumeIsolated|[A-Za-z_][A-Za-z_0-9]*|[{}().=;]',d))
 previous=''
 for idx,m in enumerate(tokens):
  word=m[0];following=tokens[idx+1][0] if idx+1<len(tokens) else ''
  if word=='@MainActor':
   # Closure isolation is written after its opening brace, unlike a type/func attribute.
   if previous=='{' and scopes:scopes[-1]=True
   else:pending=True
  elif word=='MainActor.assumeIsolated':pending=True
  elif word=='{':scopes.append(pending or any(scopes));pending=False
  elif word=='}':
   if scopes:scopes.pop()
  elif word==';':pending=False
  elif word in names and following in ('(','.') and previous not in ('class','struct','enum','func'):
   if not any(scopes):errors.append(f'actor-scope:{clean.count(chr(10),0,m.start())+1}: unisolated reference to {word}')
   # Track simple local aliases created from this constructor for later calls.
   prior=clean[max(0,m.start()-150):m.start()]
   alias=re.search(r'\b(?:let|var)\s+(\w+)\s*=\s*$',prior)
   if alias:variables.add(alias[1])
  elif word in variables and following=='.' and not any(scopes):
   # Only a method call, not a read of a nonisolated value, is flagged here.
   if idx+3<len(tokens) and tokens[idx+3][0]=='(':errors.append(f'actor-scope:{clean.count(chr(10),0,m.start())+1}: unisolated call through {word}')
  previous=word

 return errors
def swift_units(path):
 p=Path(path);text=p.read_text()
 if p.suffix=='.swift':return [(str(p),text)]
 if p.suffix=='.json':
  obj=json.loads(text);return [(str(p)+':'+k,v) for k,v in obj.items() if isinstance(v,str) and re.search(r'\bimport\s+',v)]
 if p.suffix=='.py':
  tree=ast.parse(text);units=[]
  for node in ast.walk(tree):
   if isinstance(node,ast.Constant) and isinstance(node.value,str) and re.search(r'\bimport\s+(?:Foundation|AppKit|Glibc|Darwin|CoreGraphics)\b',node.value):units.append((str(p)+':string@'+str(node.lineno),node.value))
  return units
 return []
def callback_declarations(source,owner):
 """Extract callback variable declarations from the named current class only."""
 s=code(Path(source).read_text());m=re.search(r'\b(?:class|struct)\s+'+re.escape(owner)+r'\b[^\{]*\{',s)
 if not m:raise ValueError('callback owner absent '+owner)
 start=m.end();depth=1;i=start
 while i<len(s) and depth:depth+=(s[i]=='{')-(s[i]=='}');i+=1
 body=s[start:i-1];slots={}
 for m in re.finditer(r'\bvar\s+(\w+)\s*:',body):
  # A declaration must be directly in this class, not in a nested fixture/type.
  prefix=body[:m.start()]
  if prefix.count('{')!=prefix.count('}'):continue
  j=m.end();start=j;parens=brackets=angles=0;seen=False
  while j<len(body):
   ch=body[j]
   if ch=='(':parens+=1
   elif ch==')':parens-=1
   elif ch=='[':brackets+=1
   elif ch==']':brackets-=1
   elif ch=='<':angles+=1
   elif ch=='>' and j>0 and body[j-1]!='-' and angles>0:angles-=1
   if parens==brackets==angles==0 and (ch in '=;{' or (ch=='\n' and seen)):break
   if not ch.isspace():seen=True
   j+=1
  typ=body[start:j].strip()
  if m[1].startswith('embedded') and '->' in typ and typ.endswith('?'):slots[m[1]]=' '.join(typ.split())

 if not slots:raise ValueError('no embedded callback slots found in '+owner)
 return dict(sorted(slots.items()))
def callback_slots(source,owner):return list(callback_declarations(source,owner))
def generated_slots(source,owner):
 # Preserve callback function shapes, labels, results, and optionality. Only
 # host-owned opaque delivery payload types retain the historical Int double.
 return '\n'.join(' var '+n+':'+re.sub(r'\bGorAVPlayerHost\.\w+\b','Int',typ) for n,typ in callback_declarations(source,owner).items())
def write_callback_manifest(source,owner,output):
 text=generated_slots(source,owner)+'\n';Path(output).write_text(text)
 receipt={'generator':'predispatch.callback_slots/v1','source_sha256':digest(source),'owner':owner,'output_sha256':digest(output),'slots':callback_slots(source,owner)}
 Path(str(output)+'.json').write_text(json.dumps(receipt,indent=2)+'\n');return receipt
def callbacks(source,owner,output,receipt):
 expected=generated_slots(source,owner)+'\n';errors=[];m=json.loads(Path(receipt).read_text())
 if m.get('generator')!='predispatch.callback_slots/v1':errors.append('callback: generator receipt absent')
 if m.get('source_sha256')!=digest(source):errors.append('callback: current source changed')
 if Path(output).read_text()!=expected:errors.append('callback: slot list not source-generated/current')
 if m.get('output_sha256')!=digest(output):errors.append('callback: output receipt stale')
 if m.get('slots')!=callback_slots(source,owner):errors.append('callback: slot receipt differs from source')
 return errors

def fixture_callbacks(path,source,owner='PPController'):
 """Audit the executable Python generator, not a promise in a comment."""
 tree=ast.parse(Path(path).read_text());errors=[];literals=[]
 for n in ast.walk(tree):
  if isinstance(n,ast.Constant) and isinstance(n.value,str):literals.append(n.value)
 hand=set()
 for value in literals:
  if 'class Chrome' in value:
   hand.update(re.findall(r'\bvar\s+(embedded\w+)\s*:',code(value)))
 if hand:errors.append('callback: handwritten slot list '+','.join(sorted(hand)))
 calls=[n for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id=='generated_slots']
 imports=[n for n in ast.walk(tree) if isinstance(n,ast.ImportFrom) and n.module=='predispatch' and any(x.name=='generated_slots' for x in n.names)]
 if len(calls)!=1 or not imports:errors.append('callback: must import and call source generator once')
 if not any('// SOURCE_GENERATED_CHROME_CALLBACKS' in v for v in literals):errors.append('callback: generated insertion marker absent')
 if calls and (len(calls[0].args)!=2 or not isinstance(calls[0].args[1],ast.Constant) or calls[0].args[1].value!=owner):errors.append('callback: owner not literal current class')
 # Constrain the actual splice expression. A dead call, alternate source, or
 # hardcoded replacement must not pass solely because a call exists elsewhere.
 canonical=ast.parse("stubs=stubs.replace('// SOURCE_GENERATED_CHROME_CALLBACKS',generated_slots(_pp_split().path(c,'PPController.swift'),'PPController'))").body[0]
 splices=[n for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='stubs' for t in n.targets)]
 initial=[n for n in splices if isinstance(n.value,ast.Constant) and isinstance(n.value.value,str)]
 if len(splices)!=2 or len(initial)!=1 or ast.dump(splices[-1])!=ast.dump(canonical):errors.append('callback: live source splice must be canonical and unfiltered')
 if initial:
  text=initial[0].value.value;marker='// SOURCE_GENERATED_CHROME_CALLBACKS'
  if text.count(marker)!=1:errors.append('callback: exactly one insertion marker required')
  else:
   start=text.find('class Chrome');brace=text.find('{',start);at=text.find(marker)
   if start<0 or brace<0 or at<brace or code(text[brace:at]).count('{')-code(text[brace:at]).count('}')!=1:errors.append('callback: insertion marker must be directly inside Chrome')
 return errors

def main():
 a=argparse.ArgumentParser();sp=a.add_subparsers(dest='command',required=True)
 p=sp.add_parser('plan');p.add_argument('config')
 p=sp.add_parser('carrier');p.add_argument('root');p.add_argument('manifest')
 p=sp.add_parser('fixture-callbacks');p.add_argument('fixture');p.add_argument('source');p.add_argument('--owner',default='PPController')
 p=sp.add_parser('swift');p.add_argument('paths',nargs='+');p.add_argument('--actor-source',action='append',default=[]);p.add_argument('--actor-name',action='append',default=[])
 for name in ['generate-slots','callbacks']:
  p=sp.add_parser(name);p.add_argument('source');p.add_argument('owner');p.add_argument('output')
  if name=='callbacks':p.add_argument('receipt')
 x=a.parse_args();errors=[]
 try:
  if x.command=='plan':
   cfg=json.loads(Path(x.config).read_text());root=Path(x.config).resolve().parent
   def path(n):return root/n
   for key in ['carrier','swift','callbacks']:
    if not cfg.get(key):raise ValueError('plan requires '+key)
   if not cfg.get('actor_sources') and not cfg.get('actor_names'):raise ValueError('plan requires actor_sources or actor_names')
   errors.extend(carrier(path(cfg['carrier']['root']),path(cfg['carrier']['manifest'])))
   actors=set(cfg.get('actor_names',[]))
   for n in cfg.get('actor_sources',[]):actors.update(actor_types(path(n).read_text()))
   for n in cfg['swift']:
    units=swift_units(path(n))
    if not units:errors.append('no Swift units found in '+n)
    for name,text in units:errors.extend(name+': '+e for e in swift(text,actors))
   for entry in cfg['callbacks']:errors.extend(fixture_callbacks(path(entry['fixture']),path(entry['source']),entry.get('owner','PPController')))
  elif x.command=='carrier':errors=carrier(x.root,x.manifest)
  elif x.command=='swift':
   actors=set(x.actor_name).union(*(actor_types(Path(p).read_text()) for p in x.actor_source))
   for p in x.paths:
    units=swift_units(p)
    if not units:errors.append('no Swift units found in '+p)
    for name,s in units:errors.extend(name+': '+e for e in swift(s,actors))
  elif x.command=='fixture-callbacks':errors=fixture_callbacks(x.fixture,x.source,x.owner)
  elif x.command=='generate-slots':print(json.dumps(write_callback_manifest(x.source,x.owner,x.output),indent=2));return 0
  else:errors=callbacks(x.source,x.owner,x.output,x.receipt)
 except Exception as e:errors.append(type(e).__name__+': '+str(e))
 print(json.dumps({'version':VERSION,'scope':'Linux syntax/integrity lint, not native compile','result':'FAIL' if errors else 'PASS','errors':errors},indent=2));return bool(errors)
if __name__=='__main__':raise SystemExit(main())
