"""Solver replaces stub. reduce_rows(rows) -> {'cohorts':{cohort:{'per_class':{c:{'tp','n_truth','n_predicted_accepted','precision','recall'}},'negative_false_accept':{'numerator','denominator'},'missing':int,'abstained':int,'rejected':int}},'violations':list}
rows: list[{id,family,cohort,kind:'glyph'|'negative',truth:str|None,predicted:str|None,status:'prediction'|'abstain'|'missing',confidence:float|None,rejected:bool|None}]
Precision denominator includes accepted negatives predicted as that class. Recall denominator includes all truth-class rows, including rejected/missing/abstained. None for zero denominators.
Duplicate IDs, malformed values and family overlap across cohorts must raise ValueError, not silently skip. No training/policy fitting/threshold selection; cohorts never pooled.
"""
def reduce_rows(rows):raise NotImplementedError('reference_stub_not_implementation')
