"""Current-tree catalogue regression; no frozen baseline source fallback."""
from pathlib import Path
import json,hashlib,copy
s=(Path(__file__).resolve().parents[3]/'Sources/gor/Media/TransferResolver.swift').read_text()
step2=s[s.index('// Step 2: facets'):s.index('// Step 3: file links')]
assert 'guard !missing.isEmpty else { return }' not in step2,'historical worker early return regressed'
for token in ['let missing = identifiers.filter','for identifier in missing','let missingFiles = identifiers.filter { catalogue(for: key).entries[$0]?.files == nil }','guard !missingFiles.isEmpty else { return }','if !files.isEmpty','cat.entries[identifier] = entry','Thread.sleep(forTimeInterval: Self.interRequestDelay)','defer { notifyProgress(key: key) }','notifyProgress(key: key, finished: true)']:assert token in s,token
# Current Step2 is an optional iteration, not a prerequisite for Step3.
def worker(entries,facets,replies):
 entries=copy.deepcopy(entries);ids=['a'];facet_requests=[i for i in ids if i not in entries]
 for i in facet_requests:
  if facets.get(i):entries[i]=copy.deepcopy(facets[i])
 file_requests=[i for i in ids if entries.get(i,{}).get('files') is None]
 for i in file_requests:
  if replies.get(i):entries.setdefault(i,{'title':i})['files']=replies[i]
 return facet_requests,file_requests,entries
cases=[('cached facet missing files',{'a':{'title':'A','files':None}},{},{'a':['video']},[],['a']),('populated cache',{'a':{'title':'A','files':['old']}},{},{},[],[]),('empty list is cached',{'a':{'title':'A','files':[]}},{},{},[],[]),('new facet',{}, {'a':{'title':'A','files':None}},{'a':['video']},['a'],['a']),('missing facet reply',{}, {}, {},['a'],['a'])]
results=[]
for name,e,f,r,wf,wl in cases:
 facet,files,state=worker(e,f,r);assert facet==wf and files==wl,name;results.append({'case':name,'facet_requests':facet,'file_requests':files,'result':'PASS'})
_,_,e=worker({'a':{'title':'A','files':None}}, {}, {});_,files,e=worker(e,{}, {'a':['video']});assert files==['a'] and e['a']['files']==['video']
# Persisted-state/refresh/year concerns have not been fixed by backfill patch.
open_anchors={'disk_write_after_unlock':'stateLock.unlock()\n        writeToDisk(username, current)' in s,'worker_refresh_joins_running':'guard !alreadyRunning else { return }' in s,'year_repair_done_unconditional':'mutate(key) { cat in cat.yearRepairDone = true }' in s}
print(json.dumps({'result':'PASS current backfill source/model regression','cases':results,'next_run_failed_file_retry':'PASS','source_sha256':hashlib.sha256(s.encode()).hexdigest(),'historical_fixed':['Step2 cached facets early return blocked Step3 file backfill'],'still_open_source_characterizations':open_anchors,'scope':'Python control-flow model + source guards, not native concurrency/disk/network proof'},indent=2))
