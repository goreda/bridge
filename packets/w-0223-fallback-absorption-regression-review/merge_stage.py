"""Real-source-derived isolated first merge stage. No product thresholds.
Policy values are supplied by the caller. The later pairing stage is omitted.
fixed=False is the prior branch; fixed=True is the proposed fallback gate.
"""
def absorb(target: list, c: list) -> None:

    x0 = min(target[0], c[0]); y0 = min(target[1], c[1])
    x1 = max(target[0] + target[2], c[0] + c[2]); y1 = max(target[1] + target[3], c[1] + c[3])
    target[0], target[1], target[2], target[3] = x0, y0, x1 - x0, y1 - y0
    target[4] += c[4]



def merge_stage(comps, policy, fixed=False):
    if not comps:
        return comps
    bodies = [c for c in comps if c[3] >= policy["body_height"] or c[4] >= policy["body_area"]]
    fallback = not bodies
    if fallback:
        bodies = comps
    merged = []
    for c in comps:
        x, y, w, h, area = c
        is_dot = h < policy["dot_height"] and w < policy["dot_width"]
        if is_dot:
            cx = x + w / 2
            best, best_d = None, None
            for b in bodies:
                if b is c:
                    continue
                bx, by, bw2, bh2, _ = b
                contained = bx < x and by < y and x + w < bx + bw2 and y + h < by + bh2
                dot_above = by + bh2 >= y + h 
                dot_below = by + bh2 <= y     
                if not (contained or dot_above or dot_below):
                    continue
                if contained:
                    x_ok, vgap = True, 0
                elif dot_above:
                    x_ok = bx - policy["horizontal_margin"] <= cx <= bx + bw2 + policy["horizontal_margin"]
                    vgap = max(0, by - (y + h))
                else:
                    x_ok = (not fixed or not fallback) and bx <= cx <= bx + bw2 and (y - (by + bh2)) < policy["vertical_gap"]
                    vgap = max(0, y - (by + bh2))
                if x_ok:
                    d = abs(cx - (bx + bw2 / 2)) + vgap
                    if best_d is None or d < best_d:
                        best, best_d = b, d
            if best is not None:
                absorb(best, c)
                continue
        merged.append(c)
    return merged
