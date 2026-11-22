"""Current-tree transfer regression models. No Swift URLComponents/CDP execution."""
from pathlib import Path
from urllib.parse import urlsplit
import json,hashlib,itertools
root=Path(__file__).resolve().parents[3]
t=(root/'Sources/gor/Media/TransferResolver.swift').read_text();d=(root/'Sources/gor/Media/CDPSession.swift').read_text();a=(root/'Sources/gor/Media/ArchiveBrowser.swift').read_text()
checks=[]
def check(name,condition):
 assert condition,name
 checks.append(name)
gate=t[t.index('private static func isArchiveDownload('):t.index('func captureURL(',t.index('private static func isArchiveDownload('))]
for token in ['scheme == "https" || scheme == "http"','parts.host?.lowercased() == "archive.org"','parts.user == nil, parts.password == nil','parts.percentEncodedPath.split','path.count >= 4','!path[2].isEmpty','path[3...].allSatisfy { !$0.isEmpty }']:check('archive source gate '+token,token in gate)
capture=t[t.index('func captureURL('):t.index('func cancel()',t.index('func captureURL('))]
check('parsed gate used','if Self.isArchiveDownload(transferURL)' in capture)
check('historical substring gate absent','transferURL.contains("archive.org/download/")' not in capture)
# The behavior model is tied to the gates above, not the obsolete substring model.
def direct(value):
 try:
  u=urlsplit(value);p=u.path.split('/')
  return u.scheme.lower() in ['http','https'] and u.hostname and u.hostname.lower()=='archive.org' and u.username is None and u.password is None and len(p)>=4 and p[0]=='' and p[1]=='download' and bool(p[2]) and all(p[3:])
 except ValueError:return False
for value in ['https://archive.org/download/item/movie.mp4','https://ARCHIVE.ORG/download/item/a%20b.mkv?download=1','http://archive.org/download/item/sub/file.mkv']:check('allowed '+value,bool(direct(value)))
for value in ['https://unrelated.invalid/archive.org/download/item/movie.mp4','https://unrelated.invalid/?next=https://archive.org/download/item/movie.mp4','https://archive.org.evil.invalid/download/item/file','https://x@archive.org/download/item/file','ftp://archive.org/download/item/file','https://archive.org/download/item','https://archive.org/download//file','https://archive.org/download/item/']:check('rejected '+value,not direct(value))
for token in ['guard !request.finished else { return }','request.reusedSession?.cancelCapture(request.captureID)','captureID: request.captureID','15 + max(25, ArchiveConfig.urlCaptureTimeout)','owned.prepareCaptureTransport()','owned.retireCaptureTransport()']:check('capture source '+token,token in t)
fresh=capture[capture.index('let owned = CDPSession()'):];check('fresh no unbounded semaphore','sem.wait()' not in fresh)
for token in ['guard activeCaptureID == id else { return }','guard self.isCurrentCapture(captureID) else { return false }','pollXhrCDN(attemptsLeft: attemptsLeft - 1, captureID: captureID','waitForMd(attemptsLeft: attemptsLeft - 1, captureID: captureID']:check('CDP identity '+token,token in d)
class Shared:
 def __init__(self):self.current=None;self.handlers={};self.jar='same'
 def begin(self,n):self.current=n;self.handlers={'event':n}
 def cancel(self,n):
  if self.current!=n:return
  self.current=None;self.handlers={}
 def old_event(self,n):
  if self.current!=n:return
  self.handlers={}
for kind in ['timeout','retry','cookie','xhr','poll','event']:
 s=Shared();s.begin('A');s.cancel('A');s.begin('B');s.old_event('A');s.cancel('A');check('A-B-stale '+kind,s.handlers=={'event':'B'} and s.jar=='same')
s=Shared();s.begin('video');s.cancel('video');s.begin('subtitle');s.old_event('video');check('video-subtitle retains jar',s.handlers=={'event':'subtitle'} and s.jar=='same')
check('caller selection generation preserved','self.selectionGeneration == generation' in a)
print(json.dumps({'result':'PASS current source guards and models','checks':len(checks),'source_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in [('TransferResolver.swift',t),('CDPSession.swift',d),('ArchiveBrowser.swift',a)]},'historical_fixed':['archive substring direct-return gate','fresh capture semaphore wait','reused capture identity isolation'],'still_open':['native URLComponents semantics','real CDP callback/queue ordering','legacy listing startup/resource teardown','external provider reliability'],'scope':'Python models + source checks only; not Swift execution'},indent=2))
