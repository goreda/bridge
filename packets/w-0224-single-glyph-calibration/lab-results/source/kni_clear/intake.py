"""Shared KNI Clear page intake seam, no separate per-crop cleanup."""
from pathlib import Path
import csv,hashlib,json
import numpy as np
from PIL import Image
try:
    from .kni_clear import process
except ImportError:
    from kni_clear import process

class IntakeRefusal(RuntimeError):
    def __init__(self,code,message):self.code=code;super().__init__(message)

def prepare_shared_page(source,output):
    try:r=process(source,output)
    except (ValueError,OSError,Image.DecompressionBombError) as e:
        raise IntakeRefusal(type(e).__name__,str(e)) from e
    root=Path(output);clean=root/'clean-gray.png';encoded=hashlib.sha256(clean.read_bytes()).hexdigest()
    r.update(cleaned_png_sha256=encoded,original_to_cleaned=r['original_to_oriented'])
    with (root/'clean-receipt.tsv').open('w',newline='') as f:
        w=csv.writer(f,delimiter='\t');w.writerow(['key','value_json'])
        for k,v in r.items():w.writerow([k,json.dumps(v,separators=(',',':'))])
    (root/'receipt.json').write_text(json.dumps(r,indent=2)+'\n')
    with Image.open(clean) as im:gray=im.copy()
    return gray,r

def save_shared_crop(image,receipt,bbox,path):
    x,y,w,h=map(int,bbox)
    if min(x,y)<0 or min(w,h)<1 or x+w>image.width or y+h>image.height:
        raise IntakeRefusal('CROP_BOUNDS','Crop must be fully inside shared cleaned frame')
    path=Path(path);image.crop((x,y,x+w,y+h)).save(path)
    return {'original_page_sha256':receipt['source_sha256'],
            'cleaned_page_sha256':receipt['cleaned_png_sha256'],
            'clean_px_bbox':[x,y,w,h],
            'original_to_cleaned':receipt['original_to_cleaned'],
            'cleaned_to_original':np.linalg.inv(np.array(receipt['original_to_cleaned'])).tolist(),
            'cleaned_crop_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'crop_path':str(path.name),'ocr_source_equals_kni_source':True}
