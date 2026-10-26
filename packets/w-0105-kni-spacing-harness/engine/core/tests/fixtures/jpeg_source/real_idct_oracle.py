from decimal import Decimal as D,localcontext,ROUND_FLOOR
from pathlib import Path
import json
root=Path(__file__).resolve().parent
j=json.loads((root/'manifest.json').read_text())
def pi():
 # Machin formula, independent exact-decimal series.
 def atan(x):
  v=x;s=v;k=1
  while True:
   v*=-(x*x);term=v/D(2*k+1);old=s;s+=term
   if s==old:return s
   k+=1
 return 16*atan(D(1)/5)-4*atan(D(1)/239)
def cosine(x):
 term=D(1);s=term;k=1
 while True:
  term*=-(x*x)/D((2*k-1)*(2*k));old=s;s+=term
  if s==old:return s
  k+=1
reports=[]
for c in j['fixtures']:
 blocks=[];ranges=[]
 for prec in (70,100):
  with localcontext() as ctx:
   ctx.prec=prec;p=pi();basis=[[cosine(D((2*x+1)*u)*p/16)*(D(1)/D(2).sqrt() if u==0 else 1) for u in range(8)] for x in range(8)]
   values=[];pre_values=[]
   for y in range(8):
    for x in range(8):
     value=D(c['coefficients'][0]*c['q'])/8 if not any(c['coefficients'][1:]) else sum(D(c['coefficients'][v*8+u]*c['q'])*basis[x][u]*basis[y][v] for v in range(8) for u in range(8))/4
     pre_values.append(value+128)
     values.append(min(255,max(0,int((value+D('.5')).to_integral_value(rounding=ROUND_FLOOR))+128)))
   blocks.append(bytes(values));ranges.append((min(pre_values),max(pre_values)))
 if blocks[0]!=blocks[1]:raise RuntimeError(c['name']+' precision unstable')
 expected=(root/(c['name']+'.gray')).read_bytes();errors=[abs(expected[y*c['w']+x]-blocks[-1][(y%8)*8+x%8]) for y in range(c['h']) for x in range(c['w'])]
 (root/(c['name']+'.real-gray')).write_bytes(bytes(blocks[-1][(y%8)*8+x%8] for y in range(c['h']) for x in range(c['w'])))
 reports.append({'pre_min':str(ranges[-1][0]),'pre_max':str(ranges[-1][1]),'E':str(max(0,-ranges[-1][0],ranges[-1][1]-255)),'precision_note':'70/100dps stability, not interval-certified','name':c['name'],'max_abs':max(errors),'mean_abs':sum(errors)/len(errors),'histogram':{str(e):errors.count(e) for e in sorted(set(errors))}})
(root/'real-idct-descriptive.json').write_text(json.dumps({'method':'Decimal Machin pi + Taylor cosine at 70/100 decimal precision, identical rounded output; stability evidence not certified interval enclosure or exact-real proof','reports':reports},indent=2)+'\n')
print(reports)
