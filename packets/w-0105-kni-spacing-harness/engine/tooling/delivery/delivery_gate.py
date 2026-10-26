#!/usr/bin/env python3
"""Source-bound, fail-closed font delivery evidence. Does not invent missing glyphs."""
import argparse, hashlib, json, math
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen
from PIL import Image, ImageDraw, ImageFont
from baseline_provenance import validate as baseline_validate
from charstring_equiv import same_program
from vector_gate import validate as validate_vector_receipt

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def emit(path, data):
    Path(path).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')

def code(v):
    return int(v.removeprefix('U+'),16) if isinstance(v,str) else v

def evaluate(font_path, manifest_path, output, ppem, threshold, vector_receipt_path, reference_font_sha256):
    out=Path(output); out.mkdir(parents=True,exist_ok=True)
    manifest=json.loads(Path(manifest_path).read_text()); root=Path(manifest_path).parent
    font=TTFont(font_path); cmap=font.getBestCmap() or {}; gs=font.getGlyphSet()
    failures=[]; rows=[]; images=[]
    if not manifest.get('source_revision'): failures.append('missing source_revision')
    if not manifest.get('source_identity'): failures.append('missing source_identity')
    if manifest.get('font_sha256') != sha(font_path): failures.append('font sha256 mismatch')
    if 'CFF ' not in font: failures.append('CFF1 charstring audit required')
    # PN-3 kit hardening: nameID 10 FALLBACK-EXPORT-WARNING is written by the
    # engine's apply_fallback_warn_tag when a run exports with a non-empty
    # typed fallback ledger (--fallback-export-warn). Such a font shipped
    # with unresolved intended-curved regions and is never deliverable;
    # refuse it here even when every glyph-level check passes.
    for rec in font['name'].names:
        if rec.nameID == 10:
            try: val = rec.toUnicode()
            except Exception: val = ''
            if 'FALLBACK-EXPORT-WARNING' in val:
                failures.append('fallback-export warning tag in nameID 10: font exported with unresolved fallback spans; not deliverable')
                break
    vector_path = Path(vector_receipt_path)
    vector_gate = validate_vector_receipt(vector_path, reference_font_sha256, set(cmap))
    if vector_gate['status'] != 'PASS':
        failures.extend('vector gate: ' + item for item in vector_gate['failures'])
    else:
        (out / 'vector-gate-receipt.json').write_bytes(vector_path.read_bytes())
    expected={code(r['codepoint']):r for r in manifest.get('glyphs',[])}
    if len(expected)!=len(manifest.get('glyphs',[])): failures.append('duplicate source codepoint')
    if not rows and not manifest.get('glyphs'): failures.append('empty source cmap and manifest')
    if set(cmap)!=set(expected):
        failures.append('cmap mismatch: missing='+','.join(f'U+{c:04X}' for c in sorted(set(expected)-set(cmap)))+' unexpected='+','.join(f'U+{c:04X}' for c in sorted(set(cmap)-set(expected))))
    required={code(v) for v in manifest.get('required_codepoints',[])}
    missing=required-set(cmap)
    if missing: failures.append('required coverage missing: '+','.join(f'U+{c:04X}' for c in sorted(missing)))
    # One general rule set for all languages: declared coverage requirements
    # travel only through the general required_codepoints list. The removed
    # language-specific field is rejected fail-closed so a stale manifest
    # never silently loses a requirement it still declares.
    if 'require_turkish' in manifest:
        failures.append('language-specific requirement field require_turkish is not supported; declare the coverage in required_codepoints')
    upm=font['head'].unitsPerEm; scale=ppem/upm
    bounds={}
    for name in set(cmap.values()):
        pen=BoundsPen(gs); gs[name].draw(pen); bounds[name]=pen.bounds
    # Frame derives from actual ink and metrics, not a per-font cap-height constant.
    boxes=[b for b in bounds.values() if b]
    x0=min([0]+[b[0] for b in boxes]); x1=max([v[0] for v in font['hmtx'].metrics.values()]+[b[2] for b in boxes])
    y0=min([font['hhea'].descent]+[b[1] for b in boxes]); y1=max([font['hhea'].ascent]+[b[3] for b in boxes])
    pad=max(1,math.ceil(scale)); width=math.ceil((x1-x0)*scale)+2*pad; height=math.ceil((y1-y0)*scale)+2*pad
    renderer=ImageFont.truetype(str(font_path),ppem)
    for cp,name in sorted(cmap.items()):
        r=expected.get(cp,{}); problems=[]; capture=r.get('capture',{})
        if r.get('provenance')=='unchanged_baseline':
            fit={};cs_hash=None
            try:cs_hash=baseline_validate(r,root,cp,font,manifest.get('source_identity'))
            except (ValueError,KeyError,OSError) as e:problems.append(str(e))
            if r.get('charstring_sha256')!=cs_hash:problems.append('preserved charstring hash mismatch')
            capture={'status':r['preserved_baseline'].get('status'),'reason':r['preserved_baseline'].get('reason')}
        else:
            if capture.get('source_identity')!=manifest.get('source_identity') or not capture.get('source_identity'): problems.append('source font/style identity mismatch')
            if capture.get('synthetic') is not False: problems.append('synthetic or unclassified capture source')
            if capture.get('role')!='glyph': problems.append('capture is not a glyph source')
            tile=root/capture.get('path','__missing__')
            if not tile.is_file() or capture.get('sha256')!=sha(tile): problems.append('capture missing/hash mismatch')
            elif capture.get('status') not in ('ink','intentional_blank'): problems.append('capture status missing')
            else:
                source_pixels=list(Image.open(tile).convert('L').getdata())
                source_ink=sum(v<threshold for v in source_pixels)
                if capture['status']=='ink' and not source_ink: problems.append('declared source ink is blank')
                if capture['status']=='intentional_blank' and source_ink: problems.append('declared source blank has ink')
            fit=r.get('fit',{})
            for field in ('engine_revision','path','parameters','frame','measurement'):
                if field not in fit: problems.append('fit missing '+field)
            if fit.get('path')!='capture_png>fit_captured>integer_charstring': problems.append('noncanonical fit path')
            if not fit.get('parameters') or not fit.get('frame') or not fit.get('measurement'): problems.append('empty fit evidence')
            audit_ref=r.get('capture_audit',{})
            audit_path=root/audit_ref.get('path','__missing__')
            audit=None
            if not audit_path.is_file() or audit_ref.get('sha256')!=sha(audit_path): problems.append('capture audit missing/hash mismatch')
            else:
                audit=json.loads(audit_path.read_text())
                if audit.get('schema')!='kni.capture-audit.v1': problems.append('unsupported capture audit schema')
                for field in ('source_png_hex','path','parameters','frame','measurement','charstring_hex'):
                    if field not in audit: problems.append('capture audit missing '+field)
                if tile.is_file() and audit.get('source_png_hex')!=tile.read_bytes().hex(): problems.append('capture audit source bytes mismatch')
                for k in ('path','parameters','frame','measurement'):
                    if fit.get(k)!=audit.get(k): problems.append('capture audit disagreement '+k)
            cs_hash=None
            if 'CFF ' in font:
                cs=font['CFF '].cff.topDictIndex[0].CharStrings[name]
                cs.compile(); cs_hash=hashlib.sha256(cs.bytecode).hexdigest()
                if r.get('charstring_sha256')!=cs_hash: problems.append('charstring hash mismatch')
                if audit is not None and not same_program(audit.get('charstring_hex') or '',cs.bytecode): problems.append('canonical charstring does not match final font')
        im=Image.new('L',(width,height),255)
        ImageDraw.Draw(im).text((pad-x0*scale,pad+y1*scale),chr(cp),font=renderer,fill=0,anchor='ls')
        ink=sum(v<threshold for v in im.getdata())
        intentional=capture.get('status')=='intentional_blank'
        if intentional and (ink or bounds[name]): problems.append('declared blank has ink')
        if not intentional and (not ink or not bounds[name]): problems.append('unexpected blank')
        if intentional and not capture.get('reason'): problems.append('blank exception lacks source reason')
        png=f'U{cp:06X}.png'; im.save(out/png)
        audit_ref = r.get('capture_audit')
        row={'codepoint':f'U+{cp:04X}','glyph':name,'provenance':r.get('provenance','direct_capture'),'path_label':'image','preserved_baseline':r.get('preserved_baseline'),'capture':capture,'fit':fit,'capture_audit':audit_ref,'charstring_sha256':cs_hash,'audit_path':{'kind':'preserved_baseline' if r.get('provenance')=='unchanged_baseline' else 'captured_fit','source_available':r.get('provenance')!='unchanged_baseline','source_tile':capture.get('path'),'source_tile_sha256':capture.get('sha256'),'fit_parameters':fit.get('parameters'),'frame':fit.get('frame'),'measurement':fit.get('measurement'),'capture_audit':audit_ref,'preserved_baseline':r.get('preserved_baseline'),'final_charstring_sha256':cs_hash},'advance_lsb':font['hmtx'].metrics[name],'outline_bounds':bounds[name],'render_ink_pixels':ink,'render_sha256':sha(out/png),'render':png,'failures':problems}
        rows.append(row); images.append((cp,im)); failures.extend(f'U+{cp:04X}: {p}' for p in problems)
    # Individual images are authoritative. Sheets use square-root layout from count.
    cols=max(1,math.ceil(math.sqrt(len(images)))); label=ImageFont.load_default(); label_height=label.getbbox('U+0000')[3]+2*pad
    sheets=[]
    if images:
        sheet=Image.new('L',(cols*width, math.ceil(len(images)/cols)*(height+label_height)),255); d=ImageDraw.Draw(sheet)
        for i,(cp,im) in enumerate(images):
            x=(i%cols)*width; y=(i//cols)*(height+label_height)
            d.text((x+pad,y+pad),f'U+{cp:04X}',font=label,fill=0); sheet.paste(im,(x,y+label_height))
        sheet.save(out/'sweep.png'); sheets=['sweep.png']
    emit(out/'audit.json',{'schema':'kni.glyph-audit.v1','source_revision':manifest.get('source_revision'),'font_sha256':sha(font_path),'glyphs':rows})
    report={'schema':'kni.delivery-gate.v1','status':'PASS' if not failures and rows and vector_gate['status']=='PASS' else 'FAIL','font_sha256':sha(font_path),'manifest_sha256':sha(manifest_path),'cmap_count':len(cmap),'sweep_count':len(rows),'frame':{'ppem':ppem,'threshold':threshold,'bounds':[x0,y0,x1,y1],'canvas':[width,height]},'vector_gate':vector_gate,'failures':failures,'visual_review_required':True,'sheets':sheets}
    emit(out/'gate.json',report)
    emit(out/'SHA256SUMS.json',{p.name:sha(p) for p in sorted(out.iterdir()) if p.is_file() and p.name!='SHA256SUMS.json'})
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--font',required=True); p.add_argument('--manifest',required=True); p.add_argument('--output',required=True); p.add_argument('--ppem',type=int,required=True); p.add_argument('--threshold',type=int,required=True);p.add_argument('--vector-receipt',required=True);p.add_argument('--reference-font-sha256',required=True)
    a=p.parse_args()
    if a.ppem<=0 or not 0<a.threshold<256: p.error('positive ppem and threshold 1..255 required')
    result=evaluate(a.font,a.manifest,a.output,a.ppem,a.threshold,a.vector_receipt,a.reference_font_sha256)
    print(json.dumps(result)); raise SystemExit(0 if result['status']=='PASS' else 1)
