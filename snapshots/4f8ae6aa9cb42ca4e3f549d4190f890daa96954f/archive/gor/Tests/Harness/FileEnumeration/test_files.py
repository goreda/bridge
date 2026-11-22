"""Source-derived FileBrowser admission/cap model, not filesystem/AppKit."""
from pathlib import Path
import json,hashlib,re
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/FileBrowser.swift';s=p.read_text();folder=s[s.index('func loadPath'):s.index('// Recursive case-insensitive')];search=s[s.index('private func performSearch'):s.index('private func goUp')]
def extensions(body):
 line=next(l for l in body.splitlines() if 'let playableExts:' in l);return set(re.findall(r'"([a-z0-9]+)"',line))
exts=extensions(folder);assert exts==extensions(search)
for t in ['if name.hasPrefix(".") { continue }','fm.fileExists(atPath: full, isDirectory: &isDir)','self.renderEntries(dirs + files)']:assert t in folder,t
for t in ['let maxResults = 500','options: [.skipsHiddenFiles]','dirs.count + files.count >= maxResults','name.lowercased().contains(needle)','dirs.sort { $0.name.lowercased() < $1.name.lowercased() }']:assert t in search,t
assert re.search(r'let maxResults = 500\s*\n',search)
assert 'guard fm.fileExists' not in folder,'exists admission changed; review port'
def allowed(name,is_dir):return is_dir or name.split('.')[-1].lower() in exts
def folder_model(entries):
 dirs=[];files=[]
 for name,is_dir,exists in sorted(entries):
  if name.startswith('.'):continue
  if is_dir:dirs.append(name)
  elif allowed(name,False):files.append(name) # current source ignores exists Bool
 return dirs+files
def search_model(entries,query):
 dirs=[];files=[]
 for name,is_dir,hidden in entries:
  if hidden:continue
  if len(dirs)+len(files)>=500:break
  if query.lower() not in name.lower():continue
  if is_dir:dirs.append(name)
  elif allowed(name,False):files.append(name)
 return sorted(dirs,key=str.lower)+sorted(files,key=str.lower)
controls=[]
for e in exts:assert allowed('movie.'+e.upper(),False)
controls.append({'case':'all current extension types case-insensitive','count':len(exts)})
assert folder_model([('z',True,True),('a.mkv',False,True),('.hidden.mkv',False,True),('b.txt',False,True)])==['z','a.mkv'];controls.append({'case':'directory-first, hidden skip, nonplayable filter'})
assert search_model([('Album',True,False),('ALBUM.mkv',False,False),('hidden.mkv',False,True)],'album')==['Album','ALBUM.mkv'];controls.append({'case':'case-insensitive query, directory-first, hidden omission'})
rows=[('f'+str(i)+'.mkv',False,False) for i in range(650)];assert len(search_model(rows,''))==500;controls.append({'case':'500 admitted result bound'})
assert search_model([('notes.txt',False,False)]*1000+[('movie.mkv',False,False)],'')==['movie.mkv'];controls.append({'case':'unplayable entries do not consume admitted result cap'})
assert not search_model(rows,'absent');controls.append({'case':'no match stays empty'})
reds=[]
assert folder_model([('deleted.mkv',False,False)])==['deleted.mkv'];reds.append({'case':'removed file after directory listing','observed':'ignored fileExists return admits stale playable name','scope':'synthetic TOCTOU, real FileManager race unverified'})
a=[('Z'+str(i)+'.mkv',False,False) for i in range(500)]+[('A.mkv',False,False)];b=list(reversed(a));assert 'A.mkv' not in search_model(a,'') and 'A.mkv' in search_model(b,'');reds.append({'case':'cap before alphabetical sort','observed':'first enumerated 500 admitted; globally earlier matching item can be omitted','scope':'bounded-search policy characterization, enumeration order native dependent'})
assert folder_model([])==[];reds.append({'case':'enumeration error represented as no contents','observed':'try? branch renders empty rows with no error state here','scope':'source path, actual permission failure/UI message not executed'})
print(json.dumps({'result':'PASS admission/cap controls and source characterizations','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['actual FileManager symlink/permission/race/enumerator semantics','sorting Unicode/localized expectations','generation IO cancellation native timing','row/image/title/preview UI (not covered)'],'scope':'Python enumeration/admission port + current Swift source guards, no filesystem/Swift/AppKit/UI scan'},indent=2))
