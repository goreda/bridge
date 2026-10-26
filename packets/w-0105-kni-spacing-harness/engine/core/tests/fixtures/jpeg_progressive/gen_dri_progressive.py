# Hand-written minimal progressive encoder (gray, 8-bit) used to make restart-interval
# (DRI) progressive fixtures.  mode=first: DC first(Al=1), DC refine, AC first(Al=0).
# mode=refine: DC first(Al=1), AC first(Al=1), DC refine, AC refine(Ah=1,Al=0).
# bad=end|restart: deliberately over-claims one EOB-run block at scan end / restart boundary.
# Huffman tables are fixed-length (valid, not optimal). Same coefficients are written
# with restart=0 and restart=R so decoder output must be identical; PIL/libjpeg is the
# independent reference (compared with a +-1 tolerance in the Rust test via .ref.gray).
import sys, numpy as np, io
from PIL import Image
ZZ=[0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63]
W,H=int(sys.argv[1]),int(sys.argv[2]); R=int(sys.argv[3]); out=sys.argv[4]; MODE=sys.argv[5]; BAD=sys.argv[6]
rng=np.random.default_rng(7)
y,x=np.mgrid[0:H,0:W]
img=np.clip((x*255//max(W-1,1)+(y*5)%60+rng.integers(-25,25,(H,W))),0,255).astype(float)
# smooth the right third so many all-zero AC blocks exist (exercises EOB runs)
img[:, 2*W//3:]=np.clip(img[:, 2*W//3:].mean(),0,255)
bw,bh=(W+7)//8,(H+7)//8
pad=np.pad(img,((0,bh*8-H),(0,bw*8-W)),mode='edge')-128
Q=np.full((8,8),6.0)
u=np.arange(8); C=np.where(u==0,1/np.sqrt(2),1.0)
basis=np.array([[C[k]*np.cos((2*n+1)*k*np.pi/16)*0.5 for n in range(8)] for k in range(8)])
blocks=[]
for by in range(bh):
    for bx in range(bw):
        b=pad[by*8:by*8+8,bx*8:bx*8+8]
        d=basis@b@basis.T
        q=np.rint(d/Q).astype(int).flatten()
        blocks.append([int(q[ZZ[k]]) for k in range(64)])
def seg(m,body): return bytes([0xff,m])+(len(body)+2).to_bytes(2,'big')+body
class BW:
    def __init__(s): s.b=bytearray(); s.acc=0; s.n=0
    def put(s,code,n):
        for i in range(n-1,-1,-1):
            s.acc=(s.acc<<1)|((code>>i)&1); s.n+=1
            if s.n==8: s.flush_byte()
    def flush_byte(s):
        s.b.append(s.acc); 
        if s.acc==0xff: s.b.append(0)
        s.acc=0; s.n=0
    def align(s):
        while s.n!=0: s.put(1,1)
bits=lambda v:abs(v).bit_length()
def val(v,n): return v if v>=0 else v+(1<<n)-1
def dht(cls,tid,syms):
    counts=[0]*16; L=4 if cls==0 else 8; counts[L-1]=len(syms)
    return seg(0xc4,bytes([(cls<<4)|tid])+bytes(counts)+bytes(syms)), {s:(i,L) for i,s in enumerate(syms)}
dc_syms=list(range(12)); ac_syms=sorted({0x00,0xf0}|{(r<<4)|s for r in range(16) for s in range(1,11)}|{r<<4 for r in range(1,15)})
dht_dc,dct=dht(0,0,dc_syms); dht_ac,act=dht(1,0,ac_syms)
assert len(ac_syms)<255
def scan(kind,restart,al=0):
    w=BW(); out=bytearray(); pred=0; rst=0; eobrun=0; BE=[]
    def flush_eob(over=0):
        nonlocal eobrun,BE
        if eobrun:
            run=eobrun+over
            r=run.bit_length()-1; c,n=act[r<<4]; w.put(c,n)
            if r: w.put(run-(1<<r),r)
            eobrun=0
            for bit in BE: w.put(bit,1)
            BE=[]
    for i,b in enumerate(blocks):
        if restart and i>0 and i%restart==0:
            flush_eob(1 if BAD=='restart' else 0); w.align(); out+=w.b; w.b=bytearray(); out+=bytes([0xff,0xd0+rst]); rst=(rst+1)%8; pred=0
        if kind=='dcfirst':
            v=b[0]>>al; d=v-pred; pred=v; n=bits(d); c,l=dct[n]; w.put(c,l)
            if n: w.put(val(d,n),n)
        elif kind=='dcrefine':
            w.put(b[0]&1,1)
        elif kind=='acfirst':
            mag=[abs(b[k])>>al for k in range(64)]
            last=max([k for k in range(1,64) if mag[k]]+[0])
            if last==0:
                eobrun+=1
                if eobrun==0x7fff: flush_eob()
                continue
            flush_eob(); run=0
            for k in range(1,last+1):
                if mag[k]==0: run+=1; continue
                while run>15: c,l=act[0xf0]; w.put(c,l); run-=16
                v=mag[k] if b[k]>0 else -mag[k]
                n=bits(v); assert n<=10; c,l=act[(run<<4)|n]; w.put(c,l); w.put(val(v,n),n); run=0
            if last<63: c,l=act[0x00]; w.put(c,l)
        else: # acrefine, Ah=1 Al=0
            mag=[abs(b[k]) for k in range(64)]
            EOB=max([k for k in range(1,64) if mag[k]==1]+[0])
            r=0; BR=[]
            for k in range(1,64):
                t=mag[k]
                if t==0: r+=1; continue
                while r>15 and k<=EOB:
                    flush_eob(); c,l=act[0xf0]; w.put(c,l); r-=16
                    for bit in BR: w.put(bit,1)
                    BR=[]
                if t>1: BR.append(t&1); continue
                flush_eob(); c,l=act[(r<<4)|1]; w.put(c,l); w.put(1 if b[k]>0 else 0,1)
                for bit in BR: w.put(bit,1)
                BR=[]; r=0
            if r>0 or BR:
                eobrun+=1; BE+=BR
                if eobrun==0x7fff or len(BE)>900: flush_eob()
    flush_eob(1 if BAD=='end' else 0); w.align(); out+=w.b
    return bytes(out)
sof=seg(0xc2,bytes([8])+H.to_bytes(2,'big')+W.to_bytes(2,'big')+bytes([1,1,0x11,0]))
dqt=seg(0xdb,bytes([0])+bytes(int(Q[0,0]) for _ in range(64)))
sos=lambda ss,se,ah,al: seg(0xda,bytes([1,1,0x00,ss,se,(ah<<4)|al]))
j=bytearray(b'\xff\xd8'+seg(0xe0,b'JFIF\0\x01\x01\0\0\x01\0\x01\0\0')+dqt+sof+dht_dc+dht_ac)
if R: j+=seg(0xdd,R.to_bytes(2,'big'))
if MODE=='first':
    j+=sos(0,0,0,1)+scan('dcfirst',R,1)+sos(0,0,1,0)+scan('dcrefine',R)+sos(1,63,0,0)+scan('acfirst',R,0)+b'\xff\xd9'
else:
    j+=sos(0,0,0,1)+scan('dcfirst',R,1)+sos(1,63,0,1)+scan('acfirst',R,1)+sos(0,0,1,0)+scan('dcrefine',R)+sos(1,63,1,0)+scan('acrefine',R)+b'\xff\xd9'
open(out,'wb').write(j)
im=Image.open(io.BytesIO(bytes(j))); im.load()
open(out.replace('.jpg','.ref.gray'),'wb').write(np.array(im.convert('L')).tobytes())
print(out,len(j),W,H,'dri',R,MODE,BAD)
