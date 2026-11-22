from pathlib import Path
import json
s=(Path(__file__).resolve().parents[3]/'Sources/gor/Media/ArchiveBrowser.swift').read_text()
for t in ['self.selectionGeneration == generation','let companions = currentFiles.filter { $0.isGofileSubtitle && $0.gofileFolderID == video.gofileFolderID }','!urls.contains(signedURL)','resolveNext(index + 1)','attemptsLeft: Int = 3']: assert t in s,t
rows=[{'name':'movie.en.srt','folder':'A','sub':True},{'name':'other-film.srt','folder':'A','sub':True},{'name':'movie.fr.srt','folder':'B','sub':True},{'name':'movie.mkv','folder':'A','sub':False}]
companions=[r for r in rows if r['sub'] and r['folder']=='A'];assert len(companions)==2
urls=[]
for value in ['signed-1',None,'signed-1','signed-2']:
 if value is not None and value not in urls:urls.append(value)
assert urls==['signed-1','signed-2']
generation=1;captured=generation;generation+=1;played=[]
if captured==generation:played.append('stale')
assert not played
print(json.dumps({'normal_result':'PASS','cases':['same-folder subtitle selection','missing and duplicate signed URL handling','stale selected-file completion suppressed'],'source_guards':5,'characterization':'Companion matching is folder-only, not video basename. A different film subtitle in same folder is included. Could be intentional owner behavior; no production change or playback bug claimed.','scope':'Python port/source checks, no CDP/Swift/subtitle rendering'},indent=2))
