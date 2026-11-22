#!/usr/bin/env python3
"""Add explicit video/audio CodecDelay to generated MKV via EBML reconstruction.
No payload changes; retain original element ID and size width when possible.
SeekHead/Cues offset tables removed so no stale byte positions survive edits.
"""
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'Tests/BridgeDemuxTests/Fixtures'
b=(root/'a6-hevc-eac3.mkv').read_bytes()
def elements(data):
 o=0
 while o<len(data):
  begin=o;n=1;mask=128
  while not data[o]&mask:n+=1;mask>>=1
  ident=data[o:o+n];o+=n
  n=1;mask=128
  while not data[o]&mask:n+=1;mask>>=1
  size=int.from_bytes(data[o:o+n],'big')&((1<<(7*n))-1);o+=n
  assert o+size<=len(data)
  yield int.from_bytes(ident,'big'),ident,n,data[o:o+size]
  o+=size

def encode(ident,width,body):
 while len(body)>=(1<<(7*width))-1:width+=1
 return ident+((1<<(7*width))|len(body)).to_bytes(width,'big')+body

def rebuild(data,level=0):
 out=b''
 for eid,ident,width,body in elements(data):
  if eid in (0x114d9b74,0x1c53bb6b,0xbf):continue # indexes and CRC
  if eid in (0x18538067,0x1654ae6b):body=rebuild(body,level+1)
  if eid==0xae:
   fields=list(elements(body)); kind=next(int.from_bytes(p,'big') for i,_,_,p in fields if i==0x83)
   delay=10000000 if kind==1 else 32000000
   body=b''.join(encode(i,w,p) for field,i,w,p in fields if field not in (0x56aa,0xbf))
   body+=encode(bytes.fromhex('56aa'),1,delay.to_bytes(4,'big'))
  out+=encode(ident,width,body)
 return out
(root/'a6-hevc-eac3-delay.mkv').write_bytes(rebuild(b))
