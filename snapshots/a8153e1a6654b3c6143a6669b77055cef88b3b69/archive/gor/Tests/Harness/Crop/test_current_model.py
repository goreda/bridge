"""Current-source-anchored 960px arithmetic/WT sequence model; no CG rasterization."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,hashlib,numpy as np
from PIL import Image
cell=Path(__file__).parent;s=(_pp_split().path(cell.resolve().parents[2],'PPController.swift')).read_text()
guards=['wtMinValidSamples = 4','wtBrightSampleCeiling = 32','wtMaxAttempts = 24','wtMaxElapsed: TimeInterval = 120.0','analysisMaxWidth = 960','autoBlackDominanceFraction = 0.55','autoNearBlackLuminance = 12.0','if changed < 4 { return false }','hConfidence >= 2.0 / 3.0','vConfidence >= 2.0 / 3.0','let margin      = min(topRatio, bottomRatio)','let margin     = min(leftRatio, rightRatio)','let topBottomRatio = topBlackRows == 0 && bottomBlackRows == 0 ? 1.0','guard isCurrent(filePath, state.generation) else { return }']
for g in guards:assert g in s,g
def analyze(path):
 a=np.asarray(Image.open(path).convert('RGB'),dtype=np.int64);h,w,_=a.shape;assert w==960 # no invented CoreGraphics resize parity
 l=(a*np.array([.299,.587,.114])).sum(2);integer=(a[:,:,0]*77+a[:,:,1]*150+a[:,:,2]*29)//256
 sig=[int(integer[(y*h+7)//8:((y+1)*h+7)//8,(x*w+7)//8:((x+1)*w+7)//8].mean())//8 for y in range(8) for x in range(8)]
 if (integer<=12).mean()>=.55:return False,None,sig
 center=l[h*2//10:h*8//10].mean()
 if center<15:return False,None,sig
 threshold=min(20,max(8,center*.2));row=l.mean(1);col=l.mean(0)
 def edge(v,n):
  for i,x in enumerate(v[:n]):
   if x>=threshold:return i
  return n
 top= edge(row,h//3);bottom=edge(row[::-1],h//3);left=edge(col,w//3);right=edge(col[::-1],w//3)
 ratio=lambda a,b:min(a,b)/max(a,b) if max(a,b) else 1
 unreliable=(top==h//3 or bottom==h//3) and left<w//3 and right<w//3
 y=min(top,bottom)/h if max(top,bottom)>6 and ratio(top,bottom)>.5 and not unreliable else 0
 x=min(left,right)/w if max(left,right)>6 and ratio(left,right)>.5 else 0
 crop=(x,y,1-2*x,1-2*y)
 return True,None if (crop[2]>=.98 and crop[3]>=.98) or min(crop[2:])<.5 else crop,sig
records={};summary={}
for case in json.loads((cell/'fixtures/cases.json').read_text())['cases']:
 sigs=[];votes=[];decision=None;first=None;clipped=0
 for f in sorted((cell/'fixtures/images').glob(case['id']+'-*.png')):
  eligible,c,sig=analyze(f)
  if c:
   a=np.asarray(Image.open(f).convert('RGB'));h,w,_=a.shape;x,y,cw,ch=c
   inside=(np.arange(h)[:,None]>=y*h)&(np.arange(h)[:,None]<(y+ch)*h)&(np.arange(w)[None,:]>=x*w)&(np.arange(w)[None,:]<(x+cw)*w)
   clipped=max(clipped,int(((a.min(2)>200)&~inside).sum()))
  if not eligible or any(sum(abs(a-b)>=2 for a,b in zip(sig,t))<4 for t in sigs):continue
  sigs.append(sig);votes.append(c)
  if first is None and len(votes)>=4:
   hv=[c for c in votes if c and c[0]>=.01 and c[2]<=.98];vv=[c for c in votes if c and c[1]>=.01 and c[3]<=.98]
   if len(hv)/len(votes)>=2/3 or len(vv)/len(votes)>=2/3:first=len(votes);decision='crop'
   elif sum(c is None for c in votes)/len(votes)>=2/3:first=len(votes);decision='no-crop'
 records[case['id']]={'independent_votes':len(votes),'first_decision':decision,'decision_vote':first,'max_bright_pixels_outside_candidate':clipped}
assert records['moving-letterbox']['first_decision']=='crop'
assert records['moving-no-bars']['first_decision']=='no-crop'
assert records['moving-title-card']['first_decision']=='crop'
assert records['moving-aspect-change']['decision_vote']==4
assert records['narrow-subtitle']['max_bright_pixels_outside_candidate']==567
print(json.dumps({'result':'PASS expected controls and known-red characterization','source_sha256':hashlib.sha256(s.encode()).hexdigest(),'guards':len(guards),'families':len(records),'records':records,'known_red':['moving title card false crop','moving aspect change early lock at four votes','narrow subtitle 567 pixels outside candidate'],'scope':'960px Python arithmetic port plus current source guards; no CGImage rasterization, mpv, UI or native timing'},indent=2))
