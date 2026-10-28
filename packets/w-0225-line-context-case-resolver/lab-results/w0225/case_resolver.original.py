"""W-0225 interface. Reference stub: always unresolved (safe). Solver replaces resolve_line_case.
regions: list of dict(x0,y0,x1,y1,ink_h) for ONE text line, in page pixels, y down. ink_h = tight ink height.
line: optional dict(baseline_y:int, top_y:int) from the page; None if unknown. These are positional references, not semantic x-height/cap-height anchors.
Labels are geometric hints only, never proof of case.
Returns one dict per region, same order: label in {'lower_like','upper_like','unresolved'}, ratio float|None, reason str.
Never returns a letter, never a Unicode value."""
LABELS=('lower_like','upper_like','unresolved')
def resolve_line_case(regions,line=None):
    return [dict(label='unresolved',ratio=None,reason='reference_stub') for _ in regions]
