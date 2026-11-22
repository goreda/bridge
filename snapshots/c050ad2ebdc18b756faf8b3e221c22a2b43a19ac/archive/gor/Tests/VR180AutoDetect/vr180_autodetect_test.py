#!/usr/bin/env python3
"""Production regex + policy-model fixtures. NOT native Swift execution, real-file accuracy or renderer proof."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import re,sys,json
from pathlib import Path
root=Path(__file__).resolve().parents[2]
sw=(root/'Sources/gor/Stereo/StereoDetection.swift').read_text();bad=[];rows=[]
def choose(rem=None,p=None,sbs=False,tb=False,name='movie.mkv',w=1920,h=1080):
 if rem is not None:return rem,'remembered'
 if p in ('vr180','vr180-tb','vr360-mono','vr360-tb','flat-sbs','flat-tb','mono'):return p,'projectionMetadata'
 if p=='unsupported':return 'mono','unsupportedProjectionMetadata'
 if sbs:return 'flat-sbs','stereoMetadata'
 if tb:return 'flat-tb','topBottomEvidence'
 return 'mono','monoNegative'
def check(n,ok):
 print(('PASS ' if ok else 'FAIL ')+n)
 if not ok:bad.append(n)
check('remembered including OFF dominates every signal','if let r = remembered { return Choice(kind:r' in sw)
check('geometry and generic3d no longer decide source','reason:"geometryFullSBS"' not in sw and 'reason:"geometryEquiSBS180"' not in sw and 'reason:"filename180"' not in sw)
check('TB evidence no longer overwrites projection/filename180','if stereoTB' in sw and 'choice=VRRecognition.Choice' not in (_pp_split().path(root,'PPController_Features.swift')).read_text())
cases=[]
for name in ('plain.mkv','film.3D.mkv','film_1080.mkv','name1800_3dprint.mkv'):
 for w,h in ((1920,1080),(3840,1080),(3840,1920)):
  cases.append(('2D',dict(name=name,w=w,h=h),'mono'))
for tag in ('SBS','FSBS','HSBS','LR'):
 cases.append(('half-SBS' if tag=='HSBS' else 'SBS',dict(name='movie_'+tag+'.mkv'),'mono'))
for tag in ('TB','HTB','OU','HOU','top-bottom','over_under'):
 cases.append(('TB',dict(name='movie_'+tag+'.mkv'),'mono'))
for tag in ('vr180','180','180x180_3dh','180_LR','180SBS','vr180sbs'):
 for evidence in ({},{'sbs':True},{'tb':True}):cases.append(('VR180',dict(name='trip_'+tag+'.mp4',**evidence),'flat-tb' if evidence.get('tb') else 'flat-sbs' if evidence.get('sbs') else 'mono'))
for tag in ('360','vr360'):
 cases.append(('VR360 mono',dict(name='trip_'+tag+'.mp4'),'mono'))
cases.extend([('VR180',dict(p='vr180',sbs=True,name='film_sbs.mkv'),'vr180'),('SBS',dict(sbs=True,w=5760,h=2880),'flat-sbs'),('TB',dict(tb=True),'flat-tb'),('VR360 unsupported',dict(p='unsupported',sbs=True,name='x_180.mp4'),'mono')])
for group,kwargs,expected in cases:
 got,reason=choose(**kwargs);rows.append(dict(group=group,input=kwargs,expected=expected,got=got,reason=reason,pass_=got==expected));check(group+' '+str(kwargs),got==expected)
for rem in ('mono','flat-sbs','flat-tb','vr180'):
 for p in ('vr180','unsupported','flat-sbs'):
  check('manual '+rem+' beats '+p,choose(rem=rem,p=p,sbs=True,tb=True,name='x_180.mp4')[0]==rem)
summary={g:dict(passed=sum(r['pass_'] for r in rows if r['group']==g),total=sum(r['group']==g for r in rows)) for g in sorted({r['group'] for r in rows})}
print('FIXTURE_TABLE',json.dumps(summary,sort_keys=True));print('Policy model only; untagged metadata-free VR180/360 remains ambiguous, native classification NOT_RUN.')
sys.exit(bool(bad))
