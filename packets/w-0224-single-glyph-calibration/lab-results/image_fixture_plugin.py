"""Deterministic metadata oracle for image-pipeline verification, NOT recognition.
Checks that score(image) receives the exact expected tight crop before using truth.
Blank intake abstains without calling this plugin, as in product intake.
"""
import json,pathlib,hashlib
from PIL import Image
from harness import FixtureScorer,intake
R=pathlib.Path(__file__).parent

def crop_sha(im):return hashlib.sha256(str(im.size).encode()+im.tobytes()).hexdigest()
class ImageFixture:
 def __init__(self):
  doc=json.loads((R/'approved15-dataset/dataset.json').read_text());families=sorted({r['family'] for r in doc['rows']});self.queue=[]
  for r in doc['rows']:
   crop,_=intake(Image.open(R/'approved15-dataset'/r['path']))
   if crop is None:continue
   # Different deterministic draw per class/font/size without training or randomness.
   draw=(7*families.index(r['family'])+11*([256,384,512].index(r['frame_size']))+13*ord(r['source_char']))%100
   self.queue.append((crop_sha(crop),r['truth'],draw,r['kind']))
  self.i=0
 def score(self,image):
  want,truth,draw,kind=self.queue[self.i];self.i+=1
  if crop_sha(image)!=want:raise ValueError('FixtureImageOrderOrCropMismatch')
  return FixtureScorer(truth,draw,kind).score(image)
def create_scorer():return ImageFixture()
