"""One source image is one complete glyph. Never segments or invents identity.
Keep the complete shared cleaned canvas, including disconnected marks and spacing
around the drawing. Recognition may inspect a tight view, but drawing never uses it.
"""
import hashlib,json,shutil
from pathlib import Path
from PIL import Image
import numpy as np

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def prepare(source,output,scorer=None):
    from kni_clear.intake import prepare_shared_page
    source=Path(source);output=Path(output)
    output.mkdir(parents=True,exist_ok=False)
    preserved=output/('original'+source.suffix.lower());shutil.copyfile(source,preserved)
    gray,clear=prepare_shared_page(source,output/'clear')
    tile=output/'whole.png';shutil.copyfile(output/'clear/clean-gray.png',tile)
    pixels=np.array(gray.convert('L'));ink=pixels<128
    if not ink.any():raise ValueError('single-glyph source has no visible ink; preserved')
    ys,xs=np.where(ink);box=(int(xs.min()),int(ys.min()),int(xs.max())+1,int(ys.max())+1)
    crop=gray.crop(box);scored=output/'recognition-view.png';crop.save(scored)
    score=None
    if scorer is not None:
        s=scorer.score(crop);score=dict(char=s.char,confidence=s.confidence,reject_score=s.reject_score,
            rejected=s.rejected,pack_refused=s.pack_refused,segmentation_abstain=False,
            crop_sha256=sha(scored),source_sha256=sha(source),crop='recognition-view.png')
    with Image.open(source) as original:original_dims=list(original.size)
    receipt=dict(schema='kni-single-glyph-intake-v1',semantics='one_image_one_complete_glyph',
        original_source=str(source.resolve()),preserved_source=str(preserved.resolve()),source_sha256=sha(source),tile=str(tile.resolve()),tile_sha256=sha(tile),
        tile_dimensions=list(gray.size),whole_clean_frame=True,segmentation='NOT_RUN',
        recognition_view=str(scored.resolve()),recognition_bbox=list(box),recognition_sha256=sha(scored),score=score,
        cleaned_png_sha256=clear['cleaned_png_sha256'],original_to_cleaned=clear['original_to_cleaned'],
        original_pixel_dimensions=original_dims)
    (output/'single-glyph-receipt.json').write_text(json.dumps(receipt,indent=2,allow_nan=False)+'\n')
    return tile,receipt
