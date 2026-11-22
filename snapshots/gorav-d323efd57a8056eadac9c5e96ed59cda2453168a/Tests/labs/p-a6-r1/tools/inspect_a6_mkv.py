#!/usr/bin/env python3
"""Inspect track CodecID/CodecDelay presence without decoding codec payloads."""
import json
import sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
b=(root/'Tests/BridgeDemuxTests/Fixtures'/ (sys.argv[1] if len(sys.argv)>1 else 'a6-hevc-eac3.mkv')).read_bytes()
def elements(start,end):
 while start<end:
  o=start; n=1; mask=128
  while not b[o]&mask: n+=1; mask>>=1
  ident=int.from_bytes(b[o:o+n],'big');o+=n
  n=1;mask=128
  while not b[o]&mask:n+=1;mask>>=1
  size=int.from_bytes(b[o:o+n],'big') & ((1<<(7*n))-1)
  begin=o+n;finish=begin+size
  assert finish<=end
  yield ident,begin,finish
  start=finish
def find(start,end,ident):
 return next((s,e) for i,s,e in elements(start,end) if i==ident)
seg=find(0,len(b),0x18538067);tracks=find(*seg,0x1654ae6b)
out=[]
for ident,s,e in elements(*tracks):
 if ident!=0xae:continue
 record={'CodecDelayPresent':False}
 for field,a,z in elements(s,e):
  if field==0xd7:record['trackNumber']=int.from_bytes(b[a:z],'big')
  if field==0x86:record['codecID']=b[a:z].decode()
  if field==0x56aa:record.update(CodecDelayPresent=True,CodecDelayNanoseconds=int.from_bytes(b[a:z],'big'))
 out.append(record)
print(json.dumps(out,indent=2,sort_keys=True))
