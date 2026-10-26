"""Explicit unchanged-baseline evidence. Not a claim of captured source support."""
import hashlib
from pathlib import Path
from fontTools.ttLib import TTFont

def validate(record,root,cp,final_font,identity):
 p=record['preserved_baseline'];path=(Path(root)/p['path']).resolve()
 if hashlib.sha256(path.read_bytes()).hexdigest()!=p['sha256']:raise ValueError('baseline font hash mismatch')
 if p.get('source_identity')!=identity:raise ValueError('baseline font identity mismatch')
 if not p.get('reason') or p.get('source_available') is not False:raise ValueError('pass-through requires explicit source-unavailable caveat')
 base=TTFont(path);bc=base.getBestCmap() or {};fc=final_font.getBestCmap() or {}
 if cp not in bc or cp not in fc or bc[cp]!=fc[cp]:raise ValueError('baseline cmap identity mismatch')
 for f in (base,final_font):
  if 'CFF ' not in f:raise ValueError('CFF1 baseline required')
 a=base['CFF '].cff.topDictIndex[0].CharStrings[bc[cp]];b=final_font['CFF '].cff.topDictIndex[0].CharStrings[fc[cp]];a.compile();b.compile()
 def subrs(seq):
  out=[]
  for cs in seq:
   cs.compile();out.append(cs.bytecode.hex())
  return out
 if a.private.rawDict!=b.private.rawDict or subrs(getattr(a.private,'Subrs',[]))!=subrs(getattr(b.private,'Subrs',[])) or subrs(a.globalSubrs)!=subrs(b.globalSubrs):raise ValueError('baseline/final CFF interpretation context changed')
 digest=hashlib.sha256(b.bytecode).hexdigest()
 if a.bytecode!=b.bytecode or p['charstring_sha256']!=digest:raise ValueError('baseline/final charstring mismatch')
 if base['head'].unitsPerEm!=final_font['head'].unitsPerEm or base['hmtx'].metrics[bc[cp]]!=final_font['hmtx'].metrics[fc[cp]]:raise ValueError('baseline/final metrics changed')
 return digest
