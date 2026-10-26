#!/usr/bin/env python3
"""Final delivery seal requires numeric gate AND hash-bound visual review."""
import argparse, hashlib, json
from pathlib import Path

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def seal(pack, review):
 root=Path(pack);g=json.loads((root/'gate.json').read_text());r=json.loads(Path(review).read_text());sums=json.loads((root/'SHA256SUMS.json').read_text())
 if g['status']!='PASS':raise ValueError('numeric gate did not pass')
 if not r.get('reviewer') or r.get('status')!='APPROVED':raise ValueError('visual review not approved')
 if r.get('font_sha256')!=g['font_sha256'] or r.get('gate_sha256')!=sha(root/'gate.json'):raise ValueError('visual review is stale or for another font')
 for name,digest in sums.items():
  if sha(root/name)!=digest:raise ValueError('evidence hash mismatch: '+name)
 images={name:digest for name,digest in sums.items() if name.endswith('.png')}
 if not images or r.get('images')!=images:raise ValueError('visual review must bind every individual glyph and sweep image')
 return {'status':'DELIVERY_READY','font_sha256':g['font_sha256'],'gate_sha256':sha(root/'gate.json'),'review_sha256':sha(review),'evidence_hashes':sums}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--pack',required=True);p.add_argument('--review',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 try:result=seal(a.pack,a.review)
 except (ValueError,KeyError,OSError) as e:p.exit(1,str(e)+'\n')
 Path(a.output).write_text(json.dumps(result,indent=2)+'\n')
