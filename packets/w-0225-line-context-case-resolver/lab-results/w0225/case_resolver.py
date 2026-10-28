"""W0225 v1 geometric relative ink-height hints, never semantic case/identity.
Positional line references cannot establish x-height or cap-height.
Pure stdlib; no assets, weights, network or Unicode mapping.
"""
import math,statistics
LABELS=('lower_like','upper_like','unresolved')
VERSION='w0225-geometry-v1'
# Prespecified on calibration only. No validation/test label tuning.
MIN_REGIONS=6
MIN_CLUSTER_SUPPORT=2
MIN_RELATIVE_GAP=.15
MAX_CLUSTER_RELATIVE_RANGE=.10
MAX_BOTTOM_RELATIVE_SPREAD=.06

def resolve_line_case(regions,line=None):
    def abstain(reason,ratios=None):
        return [dict(label='unresolved',ratio=None if ratios is None else ratios[i],reason=reason) for i in range(len(regions))]
    if not regions:return []
    clean=[]
    try:
        for r in regions:
            vals=[float(r[k]) for k in ('x0','y0','x1','y1','ink_h')]
            if not all(math.isfinite(v) for v in vals):return abstain('invalid_geometry')
            x0,y0,x1,y1,h=vals
            if x1<=x0 or y1<=y0 or h<=0 or h>y1-y0+1:return abstain('invalid_geometry')
            clean.append(vals)
        if line is not None:
            b,t=float(line['baseline_y']),float(line['top_y'])
            if not math.isfinite(b) or not math.isfinite(t) or b<=t:return abstain('invalid_positional_reference')
    except (KeyError,TypeError,ValueError,OverflowError):return abstain('invalid_geometry')
    heights=[r[4] for r in clean];scale=max(heights);ratios=[h/scale for h in heights]
    if len(clean)<MIN_REGIONS:return abstain('too_few_neighbours',ratios)
    # Ink bottoms inconsistent with a common line: descenders, tilt, baseline
    # irregularity are not distinguishable from boxes alone. Abstain, not infer.
    bottoms=[r[3] for r in clean]
    if max(bottoms)-min(bottoms)>MAX_BOTTOM_RELATIVE_SPREAD*scale:return abstain('uneven_or_rotated_ink_bottoms',ratios)
    ranked=sorted(range(len(heights)),key=lambda i:heights[i]);ordered=[heights[i] for i in ranked]
    cuts=range(MIN_CLUSTER_SUPPORT,len(heights)-MIN_CLUSTER_SUPPORT+1)
    split=max(cuts,key=lambda k:ordered[k]-ordered[k-1]);lo=ordered[:split];hi=ordered[split:]
    reference=statistics.median(hi)
    if (min(hi)-max(lo))/reference<MIN_RELATIVE_GAP:return abstain('height_groups_not_separated',ratios)
    if max(lo)-min(lo)>MAX_CLUSTER_RELATIVE_RANGE*reference or max(hi)-min(hi)>MAX_CLUSTER_RELATIVE_RANGE*reference:return abstain('height_groups_not_compact',ratios)
    low_indices=set(ranked[:split])
    return [dict(label='lower_like' if i in low_indices else 'upper_like',ratio=heights[i]/reference,reason='geometric_height_group_only_not_case_proof') for i in range(len(regions))]
