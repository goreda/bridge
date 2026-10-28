"""Product-side W-0225 consumer. Frozen resolver unchanged. No identity assignment.
Input region.box is page x,y,width,height. ink_h must be measured before crop/resize,
not inferred from bbox or resolver output. A whole line abstains if any boundary is
unqualified, so dropping unresolved regions never silently changes the clustering.
"""
import math
from collections import defaultdict
from case_resolver import resolve_line_case

def geometry_hints(regions,line_references=None):
    """Return parallel list, same order/cardinality. No mutation or sorting of input."""
    out=[dict(label='unresolved',ratio=None,reason='boundary_unqualified') for _ in regions]
    lines=defaultdict(list)
    if line_references is not None and not isinstance(line_references,dict):
        return [dict(label='unresolved',ratio=None,reason='invalid_line_references') for _ in regions]
    for i,r in enumerate(regions):
        if not isinstance(r,dict):
            out[i]=dict(label='unresolved',ratio=None,reason='invalid_region');continue
        line=r.get('line')
        if isinstance(line,bool) or not isinstance(line,(int,str)):
            out[i]=dict(label='unresolved',ratio=None,reason='invalid_line_identifier');continue
        lines[line].append((i,r))
    for line,entries in lines.items():
        if line is None or any(r.get('identity_boundary_qualified') is not True or r.get('kind')!='whole_glyph' for i,r in entries):continue
        converted=[]
        try:
            for i,r in entries:
                raw=list(r['box'])
                if len(raw)!=4 or any(isinstance(v,bool) for v in raw+[r['ink_h']]):raise ValueError()
                x,y,w,h=map(float,raw);ink=float(r['ink_h'])
                if not all(math.isfinite(v) for v in (x,y,w,h,ink)):raise ValueError()
                converted.append(dict(x0=x,y0=y,x1=x+w,y1=y+h,ink_h=ink))
        except (KeyError,TypeError,ValueError,OverflowError):
            for i,r in entries:out[i]=dict(label='unresolved',ratio=None,reason='missing_or_invalid_page_geometry')
            continue
        ref=(line_references or {}).get(line)
        if ref is not None:
            if not isinstance(ref,dict) or any(isinstance(ref.get(k),bool) for k in ('baseline_y','top_y')):
                for i,r in entries:out[i]=dict(label='unresolved',ratio=None,reason='invalid_line_reference')
                continue
        hints=resolve_line_case(converted,ref)
        for (i,r),hint in zip(entries,hints):out[i]=hint
    return out

def note_suffix(region,hint):
    """No semantic case words, letter guesses or confidence mapping."""
    if not isinstance(region,dict) or not isinstance(hint,dict):return ''
    if region.get('identity_boundary_qualified') is not True or region.get('kind')!='whole_glyph':return ''
    ratio=hint.get('ratio')
    if hint.get('label') not in ('lower_like','upper_like') or isinstance(ratio,bool) or not isinstance(ratio,(int,float)) or not math.isfinite(ratio) or ratio<=0:return ''
    return ' Relative ink height / taller-group median: '+format(ratio,'.4g')+'; relative size only, not case evidence.'
