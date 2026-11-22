from pathlib import Path
import re,csv
r=Path(__file__).resolve().parents[4]; base=r/'archive/gor';rows=set()
def add(kind,name,p,line,typ):rows.add((kind,name,str(p.relative_to(r))+':'+str(line),typ))
def value_type(v):
 v=v.strip()
 if v.startswith('"') and not '\\(' in v:return 'string'
 if v.startswith(('true','false')):return 'bool'
 if re.match(r'^-?\d+(\.\d+)?',v):return 'number'
 if v.startswith('['):return 'array'
 return 'dynamic/unresolved'
for p in sorted((base/'Sources/gor').glob('*.swift')):
 text=p.read_text()
 for ln,orig in enumerate(text.splitlines(),1):
  if orig.lstrip().startswith('//'):continue
  line=orig.replace('\\"','"')
  # Every literal command array, JSON-encoded or MPVCommand/jsonCommand construction.
  for m in re.finditer(r'(?:"command"\s*:\s*\[|(?:MPVCommand\.make|jsonCommand)\s*\(\s*\[)\s*"([^"\n]+)"(?=([^\n]*))',line):
   cmd,tail=m.groups();add('command',cmd,p,ln,'command-array')
   vals=re.match(r'\s*,\s*"([^"\n]+)"(.*)',tail)
   if cmd in ['get_property','set_property','set','add','multiply','cycle','cycle-values','observe_property']:
    if cmd=='observe_property':vals=re.match(r'\s*,[^,]+,\s*"([^"\n]+)"(.*)',tail)
    if vals:
     name,rest=vals.groups();kind='property-get' if cmd=='get_property' else 'property-observe' if cmd=='observe_property' else 'property-set' if cmd in ['set','set_property'] else 'property-mutate'
     if '\\(' in name:kind+='-dynamic'
     add(kind,name,p,ln,value_type(rest.lstrip(', ')) if cmd not in ['get_property','observe_property'] else 'mpv-native/unresolved')
  # Runtime poll/observer tables resolve generic makeBatch/subscribeBatch.
  if p.name=='PPController.swift':
   match=re.match(r'\s*\d+:\s*"([^"]+)"',orig)
   if match:
    offset=sum(len(x)+1 for x in text.splitlines()[:ln-1]);prior=text[:offset]
    table=re.findall(r'let (fastProps|slowProps|cacheProps|observedProps):',prior)
    if table and prior.rfind('let '+table[-1]+':')>prior.rfind('\n    ]'):
     add('property-observe' if table[-1]=='observedProps' else 'property-get',match[1],p,ln,'mpv-native/unresolved')
for p in sorted((base/'Resources/vendor/mpv/scripts').rglob('*.lua')):
 for ln,line in enumerate(p.read_text(errors='replace').splitlines(),1):
  if line.lstrip().startswith('--'):continue
  for m in re.finditer(r'(?:pcall\(\s*)?mp\.(get_property(?:_native|_bool|_number|_osd)?|set_property(?:_native|_bool|_number)?|observe_property)\s*(?:\(\s*|,\s*)([^,)]+)([^\n]*)',line):
   op,arg,tail=m.groups();literal=re.fullmatch(r'''["']([^"']+)["']''',arg.strip());name=literal[1] if literal else arg.strip()
   kind='property-observe' if op=='observe_property' else 'property-get' if op.startswith('get_') else 'property-set'
   if not literal:kind+='-dynamic'
   typ='number' if '_number' in op else 'bool' if '_bool' in op else 'native' if '_native' in op else 'string'
   if op=='observe_property':
    typm=re.match(r'''\s*,\s*["']([^"']+)["']''',tail);typ=typm[1] if typm else 'dynamic/unresolved'
   add(kind,name,p,ln,typ)
  for m in re.finditer(r'''(?:pcall\(\s*)?mp\.(commandv|command_native_async|command_native|command)\s*(?:\(\s*|,\s*)(?:\{\s*)?["']([^"']+)["']''',line):
   op,name=m.groups();name=name.split()[0] if op=='command' else name;add('command',name,p,ln,'lua-'+op)
# Native map commands (subprocess) and dynamic invocations stay explicit.
for p in sorted((base/'Resources/vendor/mpv/scripts').rglob('*.lua')):
 text=p.read_text(errors='replace');lines=text.splitlines()
 for ln,line in enumerate(lines,1):
  if line.lstrip().startswith('--'):continue
  for m in re.finditer(r"name\s*=\s*[\"']([^\"']+)[\"']",line):
   # Only map fields inside a local mp.command_native_async window.
   if 'mp.command_native' in '\n'.join(lines[max(0,ln-5):ln]):add('command',m[1],p,ln,'native command map')
  if re.search(r'mp\.(?:commandv|command_native(?:_async)?|command)\s*\(',line):
   if not any(x[2]==str(p.relative_to(r))+':'+str(ln) and x[0]=='command' for x in rows):
    add('command-dynamic',line.strip(),p,ln,'dynamic/unresolved')
p=base/'Resources/vendor/mpv/input.conf'
for ln,line in enumerate(p.read_text().splitlines(),1):
 line=line.strip()
 if not line or line.startswith('#'):continue
 parts=line.split();cmd=parts[1] if len(parts)>1 else ''
 if cmd:add('command',cmd,p,ln,'input.conf tokens')
 if cmd in ['add','set','cycle','cycle-values','multiply'] and len(parts)>2:add('property-mutate',parts[2],p,ln,'input.conf tokens')
# Resolve constant-name Lua aliases without guessing a runtime target.
for kind,name,site,typ in list(rows):
 if not kind.endswith('-dynamic'):continue
 path=site.rsplit(':',1)[0];p=r/path
 if p.suffix!='.lua':continue
 text=p.read_text(errors='replace')
 aliases=re.findall(r"(?:local\s+)?"+re.escape(name)+r"\s*=\s*[\"']([^\"']+)[\"']",text) if re.fullmatch(r'[A-Za-z_]\w*',name) else []
 if len(set(aliases))==1:rows.add((kind.removesuffix('-dynamic'),aliases[0],site,typ+' (source constant)'))
# Swift propertyCommand callers pass the concrete property at the call site.
for p in sorted((base/'Sources/gor').glob('*.swift')):
 for ln,line in enumerate(p.read_text().splitlines(),1):
  if line.lstrip().startswith('//'):continue
  for m in re.finditer(r'propertyCommand\(\s*"([^"\n]+)"',line):add('property-get',m[1],p,ln,'mpv-native/unresolved')
out=base/'Tests/PlayerBackend/mpv-surface.tsv'
with out.open('w') as f:
 w=csv.writer(f,delimiter='\t',lineterminator='\n');w.writerow(['kind','name','call site file:line','value type']);w.writerows(sorted(rows))
print('rows',len(rows),'literal commands',len({x[1] for x in rows if x[0]=='command'}),'dynamic sites',sum('dynamic' in x[0] for x in rows))
