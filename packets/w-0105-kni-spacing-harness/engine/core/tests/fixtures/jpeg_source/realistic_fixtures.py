"""Offline synthetic pixels -> independently defined FDCT/quantization -> JPEG.
Not a production encoder. Outputs CC0 synthetic fixtures. No runtime test oracle.
"""
from pathlib import Path
from io import BytesIO
import math,json,random,hashlib
from PIL import Image
import generate_fixtures as g
root=Path(__file__).resolve().parent
j=json.loads((root/'manifest.json').read_text())
rng=random.Random(47391)
patterns={'image_checker':[255 if (x+y)%2 else 0 for y in range(8) for x in range(8)],'image_gradient':[round(255*x/7) for y in range(8) for x in range(8)],'image_noise':[rng.randrange(256) for _ in range(64)]}
for name,pixels in patterns.items():
 q=8;coeff=[]
 for v in range(8):
  for u in range(8):
   cu=1/math.sqrt(2) if u==0 else 1;cv=1/math.sqrt(2) if v==0 else 1
   value=cu*cv/4*sum((pixels[y*8+x]-128)*math.cos((2*x+1)*u*math.pi/16)*math.cos((2*y+1)*v*math.pi/16) for y in range(8) for x in range(8))
   coeff.append(math.floor(value/q+.5))
 raw,w,h=g.jpeg(coeff,q);im=Image.open(BytesIO(raw));im.draft('L',im.size);assert im.decoderconfig==(1,0)
 gray=im.tobytes();(root/(name+'.jpg')).write_bytes(raw);(root/(name+'.gray')).write_bytes(gray);(root/(name+'.source-gray')).write_bytes(bytes(pixels))
 j['fixtures'].append({'name':name,'original_sha256':hashlib.sha256(raw).hexdigest(),'gray_sha256':hashlib.sha256(gray).hexdigest(),'w':w,'h':h,'q':q,'coefficients':coeff,'source_gray_sha256':hashlib.sha256(bytes(pixels)).hexdigest(),'encoder':'direct mathematical FDCT binary64, quant8 half-up; coefficient array frozen','max_abs_dequant':max(abs(v*q) for v in coeff)})
(root/'manifest.json').write_text(json.dumps(j,indent=2)+'\n')
