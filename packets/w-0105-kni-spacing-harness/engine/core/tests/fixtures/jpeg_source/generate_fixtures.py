from pathlib import Path
from io import BytesIO
from PIL import Image,features
import hashlib,json,sys,platform,math
root=Path(__file__).resolve().parent;root.mkdir(parents=True,exist_ok=True)
ZZ=[0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63]
def seg(m,b):return bytes([255,m])+(len(b)+2).to_bytes(2,'big')+b
def jpeg(coeffs,q=1,sampling=(1,1),color=False,restart=False):
 n=3 if color else 1;hh,vv=sampling;w=8*hh*(2 if restart else 1);h=8*vv
 out=b'\xff\xd8'+seg(0xe0,b'JFIF\0\x01\x01\0\0\x01\0\x01\0\0')+seg(0xdb,b'\0'+bytes([q])*64)
 sof=bytes([8])+h.to_bytes(2,'big')+w.to_bytes(2,'big')+bytes([n])+bytes([1,(hh<<4)|vv,0])
 if color:sof+=bytes([2,0x11,0,3,0x11,0])
 out+=seg(0xc0,sof)
 # Complete deterministic map DC category 0..11 codes length4, AC all legal run/size length8.
 symbols=[0,0xf0]+[(r<<4)|s for r in range(16) for s in range(1,11)]
 out+=seg(0xc4,b'\0'+bytes([0,0,0,12]+[0]*12)+bytes(range(12))+b'\x10'+bytes([0]*7+[len(symbols)]+[0]*8)+bytes(symbols))
 if restart:out+=seg(0xdd,b'\0\x01')
 out+=seg(0xda,bytes([n])+b''.join(bytes([i+1,0]) for i in range(n))+bytes([0,63,0]))
 def block(c,previous):
  bits='';v=c[0]-previous;s=abs(v).bit_length();a=v if v>=0 else v+(1<<s)-1;bits+=f'{s:04b}'+(f'{a:0{s}b}' if s else '')
  run=0
  for k in range(1,64):
   v=c[ZZ[k]]
   if v==0:run+=1;continue
   while run>=16:bits+=f'{symbols.index(0xf0):08b}';run-=16
   s=abs(v).bit_length();a=v if v>=0 else v+(1<<s)-1
   bits+=f'{symbols.index((run<<4)|s):08b}'+f'{a:0{s}b}';run=0
  if run:bits+=f'{symbols.index(0):08b}'
  return bits
 bits='';zero=[0]*64
 for m in range(2 if restart else 1):
  for _ in range(hh*vv):bits+=block(coeffs,0 if _==0 else coeffs[0])
  if color:bits+=block(zero,0)+block(zero,0)
  if restart and m==0:
   bits+='1'*((-len(bits))%8);out+=bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8)).replace(b'\xff',b'\xff\0')+b'\xff\xd0';bits=''
 bits+='1'*((-len(bits))%8);out+=bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8)).replace(b'\xff',b'\xff\0')+b'\xff\xd9'
 return out,w,h
cases=[]
definitions=[
 ('gray_dc0',[0]*64,1,(1,1),False,False),
 ('gray_dc_half_negative',[-4]+[0]*63,1,(1,1),False,False),
 ('gray_ac1',[0,12]+[0]*62,1,(1,1),False,False),
 ('gray_dense',[30]+[(-1 if i%2 else 1)*(i%7+1) for i in range(1,64)],1,(1,1),False,False),
 ('gray_dense_max',[0]+[1023 if i%2 else -1023 for i in range(1,64)],255,(1,1),False,False),
 ('gray_dense_domain',[0]+[1023 if i%2 else -1023 for i in range(1,64)],2,(1,1),False,False),
 ('gray_clip_hi',[2047]+[0]*63,255,(1,1),False,False),
 ('gray_clip_lo',[-2047]+[0]*63,255,(1,1),False,False),
 ('ycbcr_444',[80]+[0]*63,1,(1,1),True,False),
 ('ycbcr_422',[80]+[0]*63,1,(2,1),True,False),
 ('ycbcr_420',[80]+[0]*63,1,(2,2),True,False),
 ('gray_restart',[80]+[0]*63,1,(1,1),False,True),
]
for amplitude,quant in [(255,1),(511,1),(1023,1),(1023,2),(512,4),(819,5),(819,10),(257,255)]:
 definitions.append((f'bisect_{amplitude*quant}',[0]+[amplitude if i%2 else -amplitude for i in range(1,64)],quant,(1,1),False,False))
for amplitude in [0,8,16,24,32,48,64,96,128,192,256,384,512,768,1023]:
 definitions.append((f'range_{amplitude}',[0]+[amplitude if i%2 else -amplitude for i in range(1,64)],1,(1,1),False,False))
for name,c,q,sampling,color,rst in definitions:
 raw,w,h=jpeg(c,q,sampling,color,rst)
 im=Image.open(BytesIO(raw));im.draft('L',im.size)
 assert im.mode=='L' and im.size==(w,h) and im.decoderconfig==(1,0)
 pixels=im.tobytes();(root/(name+'.jpg')).write_bytes(raw);(root/(name+'.gray')).write_bytes(pixels)
 # High precision oracle pending; Python math descriptive preliminary only.
 cases.append({'name':name,'original_sha256':hashlib.sha256(raw).hexdigest(),'gray_sha256':hashlib.sha256(pixels).hexdigest(),'w':w,'h':h,'q':q,'coefficients':c,'max_abs_dequant':max(abs(v*q) for v in c),'oracle_domain':max(abs(v*q) for v in c)<=2047})

manifest={'license':'CC0-1.0; newly authored synthetic marker/coefficient fixtures, no font/corpus data','oracle':{'Pillow':Image.__version__,'libjpeg_turbo':features.version_feature('libjpeg_turbo'),'DCT':'library default; not independently proven','mode':'L at decode via draft(full_size), decoderconfig=(1,0), no RGB conversion','python':sys.version,'platform':platform.platform(),'arch':platform.machine(),'wheel_sha256':'f0606c8bf2cdefea14a43530f7657cbbb7ecf1c4222512492ef4a4434a9501ec','bundle_sha256':'6d7c754529b30aff22efaaf88ba02061714591702c03f297f00ccb32ee6d9d9a'},'fixtures':cases}
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('FROZEN',len(cases),'fixtures')
