from copy import deepcopy
from merge_stage import merge_stage
POLICY = dict(body_height=8, body_area=80, dot_height=8, dot_width=8,
              horizontal_margin=2, vertical_gap=6)
CASES = {
    'empty': [],
    'fallback_vertical_pair': [[10,0,2,2,4], [10,3,2,2,4]],
    'fallback_vertical_pair_reversed': [[10,3,2,2,4], [10,0,2,2,4]],
    'fallback_separate_columns': [[0,0,2,2,4], [30,3,2,2,4]],
    'body_with_mark_above': [[10,0,2,2,4], [10,4,3,10,30]],
    'body_with_mark_below': [[10,0,3,10,30], [10,12,2,2,4]],
}
if __name__ == '__main__':
    import json
    out={}
    for name, case in CASES.items():
        out[name]={str(fixed):merge_stage(deepcopy(case),POLICY,fixed) for fixed in (False,True)}
    print(json.dumps(out,indent=2))
