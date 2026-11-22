from pathlib import Path
s=(Path(__file__).resolve().parents[3]/'Sources/gor/Media/ArchiveBrowser.swift').read_text()
f=(Path(__file__).resolve().parents[3]/'Sources/gor/Media/FileBrowser.swift').read_text()
class Nav:
 def __init__(self):self.epoch=0;self.screen='library';self.commits=[]
 def open(self,name):self.epoch+=1;self.screen=f'loading {name}';return self.epoch
 def back(self):self.epoch+=1;self.screen='library'
 def complete(self,request,name):
  if self.epoch==request:self.screen=name;self.commits.append(name)
n=Nav();a=n.open('A');n.back();n.complete(a,'A');assert n.screen=='library';assert not n.commits
n=Nav();a=n.open('A');b=n.open('B');n.complete(a,'A');n.complete(b,'B');assert n.commits==['B']
n=Nav();a=n.open('A');n.complete(a,'A');assert n.commits==['A']
for name in ('selectTitle','selectArchiveOrgProfile','selectArchiveOrgList','selectArchiveOrgAllLists','selectArchiveOrgItem'):
 sig=('func ' if name=='selectTitle' else 'private func ')+name+'('
 a=s.index(sig);b=s.index('\n    }',a)+6;sec=s[a:b]
 assert 'selectionGeneration += 1' in sec, name
 assert 'openingGeneration = selectionGeneration' in sec, name
 assert 'self.selectionGeneration == openingGeneration' in sec, name
assert 'entry.path.lowercased().hasSuffix(".torrent") ? nil : entry.path' in f
assert f.count('"torrent","mkv"')==2
print('navigation epoch transitions and scoped torrent UI checks PASS')
