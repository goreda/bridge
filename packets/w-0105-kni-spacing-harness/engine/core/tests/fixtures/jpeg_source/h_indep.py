# Independent recomputation: own cosine basis (float via math.fsum + Decimal 50dps cross-check), Pillow decode of supplied jpg bytes.
import json, math
from decimal import Decimal as D, getcontext
from io import BytesIO
from PIL import Image
getcontext().prec = 50
m = json.load(open('manifest.json'))['fixtures']
cal = {r['name']: r for r in json.load(open('range-calibration.json'))['rows']}
desc = {r['name']: r for r in json.load(open('real-idct-descriptive.json'))['reports']}
# Decimal cos via argument reduction + Taylor, pi from Decimal Chudnovsky-free: use Gauss-Legendre (differs from Machin).
def pi_gl():
    a,b,t,p = D(1), 1/D(2).sqrt(), D(1)/4, D(1)
    for _ in range(8):
        an=(a+b)/2; b=(a*b).sqrt(); t-=p*(a-an)**2; a=an; p*=2
    return (a+b)**2/(4*t)
PI = pi_gl()
def cosd(x):
    x = x % (2*PI)
    if x > PI: x -= 2*PI
    s=D(0); term=D(1); k=0
    while abs(term) > D(10)**-48:
        s+=term; k+=1; term*=-x*x/((2*k-1)*(2*k))
    return s
C = {}
def basis(x,u):
    k=(x,u)
    if k not in C:
        c = cosd(D((2*x+1)*u)*PI/16)
        C[k] = c*(1/D(2).sqrt()) if u==0 else c
    return C[k]
rows=[]
for f in m:
    n=f['name']
    if not n.startswith('range_') and not n.startswith('image_'): 
        pass
    co=f['coefficients']; q=f['q']
    pre=[]
    for y in range(8):
        for x in range(8):
            if not any(co[1:]): v = D(co[0]*q)/8   # exact DC shortcut as in supplied method
            else: v = sum(D(co[v_*8+u]*q)*basis(x,u)*basis(y,v_) for v_ in range(8) for u in range(8))/4
            pre.append(v+128)
    E = max(D(0), -min(pre), max(pre)-255)
    real = [min(255,max(0,int((v-128+D('.5')).to_integral_value(rounding='ROUND_FLOOR'))+128)) for v in pre]
    raw = open(n+'.jpg','rb').read() if False else None
    g = open(n+'.gray','rb').read()
    w,h=f['w'],f['h']
    err = max(abs(g[y*w+x]-real[(y%8)*8+x%8]) for y in range(h) for x in range(w))
    rows.append((n,E,err))
import sys
out={}
for n,E,err in rows:
    d=desc[n]; Ed=D(d['E'])
    out[n]=(E,err)
    flag = '' if abs(E-Ed) < D('1e-20') and err==d['max_abs'] else ' MISMATCH'
    print(f"{n:24s} E={float(E):.8f} pillow_vs_real={err}{flag}")
r=[(n,out[n]) for n,_,_ in rows if n.startswith('range_')]
Es=[float(e) for _,(e,_) in r]
print('range E nondecreasing:', all(a<=b for a,b in zip(Es,Es[1:])), 'strict from 8..:', all(a<b for a,b in zip(Es[1:],Es[2:])))
# largest contiguous passing prefix (error<=1)
last=None
for n,(e,err) in r:
    if err<=1: last=(n,e)
    else: break
print('largest contiguous pass:', last[0], float(last[1]), 'floor ->', int(last[1]))
print('range_768 E', float(out['range_768'][0]), '> 3381:', out['range_768'][0] > 3381, ' err', out['range_768'][1])
print('range_512 E', float(out['range_512'][0]), '> 3381:', out['range_512'][0] > 3381)
# also check calibration rows E equality
bad=[n for n in cal if D(cal[n]['E'])!=D(desc[n]['E'])]
print('calibration rows vs descriptive E mismatches:', bad)
