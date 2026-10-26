#!/usr/bin/env python3
"""Synthetic single-model spacing reference. No font data or optical claims."""
from dataclasses import dataclass
from fractions import Fraction
import hashlib
import json
import re
import unicodedata
from functools import cached_property

SCHEMA='kni.synthetic-spacing-input.v1'
METHOD='synthetic-profile-squared-gap-v1'
# CONVENTION: no theory behind the number. Bound parsing, never truncate.
MAX_RATIONAL_TEXT_LENGTH=512
class SpacingError(ValueError):
    def __init__(self,code):self.code=code;super().__init__(code)
def reject(code):raise SpacingError(code)
def rational(value):
    if not isinstance(value,str):reject('rational_text_required')
    if len(value)>MAX_RATIONAL_TEXT_LENGTH:reject('rational_text_too_long')
    if re.fullmatch(r'(?:-?[0-9]+(?:\.[0-9]+)?|[0-9]+/[0-9]+)',value) is None:
        reject('rational_syntax_invalid')
    if '/' in value and int(value.split('/')[1])==0:reject('rational_denominator_zero')
    try:return Fraction(value)
    except (ValueError,ZeroDivisionError):reject('rational_value_invalid')
def valid_name(name):
    return isinstance(name,str) and bool(name) and name==name.strip() and all(unicodedata.category(c) not in ('Cc','Cf','Cs','Co','Cn','Zl','Zp') and (unicodedata.category(c)!='Zs' or c==' ') for c in name)

def canonical_hash(obj):return hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode('utf-8')).hexdigest()
@dataclass(frozen=True)
class Glyph:
    name:str
    ink_width:Fraction
    left:tuple
    right:tuple
@dataclass(frozen=True)
class Model:
    glyphs:tuple
    target:Fraction
    interaction:Fraction
    input_sha256:str
    @classmethod
    def from_input(cls,obj):
        if not isinstance(obj,dict) or set(obj)!={'schema','synthetic','frame','target_gap','interaction','glyphs'}:reject('input_fields')
        if obj['schema']!=SCHEMA or obj['synthetic'] is not True or obj['frame']!='synthetic-units':reject('synthetic_contract')
        if not isinstance(obj['glyphs'],list) or not obj['glyphs']:reject('empty_glyphset')
        target=rational(obj['target_gap']);interaction=rational(obj['interaction'])
        if target<0 or interaction<0:reject('negative_model_parameter')
        gs=[];seen=set();dimension=None
        for row in obj['glyphs']:
            if not isinstance(row,dict) or set(row)!={'name','ink_width','left_profile','right_profile'}:reject('glyph_fields')
            name=row['name']
            if not valid_name(name):reject('name_invalid')
            if name in seen:reject('name_duplicate')
            seen.add(name);width=rational(row['ink_width'])
            if width<0:reject('negative_ink_width')
            profiles=[]
            for key in ['left_profile','right_profile']:
                if not isinstance(row[key],list) or not row[key]:reject('invalid_profile')
                values=tuple(rational(v) for v in row[key])
                if dimension is None:dimension=len(values)
                if len(values)!=dimension:reject('profile_dimension')
                profiles.append(values)
            gs.append(Glyph(name,width,*profiles))
        return cls(tuple(sorted(gs,key=lambda g:g.name)),target,interaction,canonical_hash(obj))
    def pair_gap(self,left,right):
        # CONVENTION: authored metric profiles, not sampled outlines or Marini's formula.
        return self.target+self.interaction*sum((a-b)**2 for a,b in zip(left.right,right.left))/len(left.right)
    def derive(self):
        return self._derived
    @cached_property
    def _derived(self):
        # Complete ordered pair matrix. No sparse kern list or imported bearings.
        n=len(self.glyphs);s=tuple(tuple(self.pair_gap(a,b) for b in self.glyphs) for a in self.glyphs)
        grand=sum(sum(row) for row in s)/(n*n)
        # CONVENTION: least-squares additive decomposition with equal mean bearings.
        right=tuple(sum(row)/n-grand/2 for row in s)
        left=tuple(sum(s[i][j] for i in range(n))/n-grand/2 for j in range(n))
        kern=tuple(tuple(s[i][j]-right[i]-left[j] for j in range(n)) for i in range(n))
        return Result(self.input_sha256,self.glyphs,s,left,right,kern)
@dataclass(frozen=True)
class Result:
    model_sha256:str
    glyphs:tuple
    gaps:tuple
    left:tuple
    right:tuple
    kern:tuple

def scalar(x):return {'numerator':x.numerator,'denominator':x.denominator}
def report(model,result):
    # Reject a stale or externally supplied result, including invented residuals.
    if result!=model.derive():reject('result_not_from_model')
    _,binding=declared_adapter(model,result)
    return {'integer_bearings':binding['integer_bearings'],'realized_gap_errors':binding['realized_gap_errors'],'max_abs_realized_gap_error':binding['max_abs_realized_gap_error'],'unrounded_reference':True,'schema':'kni.synthetic-spacing-result.v1','method':METHOD,'synthetic':True,'frame':'synthetic-units','model_sha256':result.model_sha256,'status':'proposed','bearings':[{'glyph':g.name,'left':scalar(result.left[i]),'right':scalar(result.right[i]),'advance':scalar(g.ink_width+result.left[i]+result.right[i])} for i,g in enumerate(result.glyphs)],'pairs':[{'left':a.name,'right':b.name,'model_gap':scalar(result.gaps[i][j]),'bearing_gap':scalar(result.right[i]+result.left[j]),'kern_residual':scalar(result.kern[i][j]),'status':'proposed'} for i,a in enumerate(result.glyphs) for j,b in enumerate(result.glyphs)]}

def round_half_away(q):
    # CONVENTION: exact rational rounding, ties away from zero.
    sign=-1 if q<0 else 1;q=abs(q)
    return sign*((2*q.numerator+q.denominator)//(2*q.denominator))
def declared_adapter(model,result):
    """Planned writer values, not evidence that a GPOS table has been written."""
    import math
    if result!=model.derive():reject('result_not_from_model')
    left_int=tuple(round_half_away(x) for x in result.left);right_int=tuple(round_half_away(x) for x in result.right)
    if any(g.ink_width.denominator!=1 for g in result.glyphs):reject("integer_ink_width_required_for_hmtx")
    declared=[];exact=[];realized=[];counts={'written':0,'rounded':0,'rejected':0}
    for i,a in enumerate(result.glyphs):
        for j,b in enumerate(result.glyphs):
            q=result.gaps[i][j]-right_int[i]-left_int[j]
            try:requested=float(q)
            except OverflowError:reject('requested_not_json_finite')
            if not math.isfinite(requested):reject('requested_not_json_finite')
            if q < -32768 or q > 32767:
                written=None;status='rejected';reason='residual_out_of_int16'
            else:
                written=round_half_away(q)
                if not -32768<=written<=32767:reject('rounding_out_of_int16')
                status='written' if q.denominator==1 else 'rounded'
                # gposcheck computes status from requested's binary64 JSON number.
                if (requested==written)!=(status=='written'):reject('requested_precision_status_loss')
                reason='' if status=='written' else 'nearest_integer_ties_away_from_zero'
            error=None if written is None else Fraction(right_int[i]+left_int[j]+written)-result.gaps[i][j]
            if error is not None and abs(error)>Fraction(1,2):reject('realized_gap_error_exceeds_half')
            realized.append({'left':a.name,'right':b.name,'realized_gap_error':None if error is None else scalar(error),'status':'unavailable' if error is None else 'measured','reason':'residual_out_of_int16' if error is None else ''})
            counts[status]+=1
            declared.append({'left':a.name,'right':b.name,'requested':requested,'written':written,'status':status,'reason':reason})
            exact.append({'left':a.name,'right':b.name,'exact_residual':scalar(q),'binary64_requested':requested})
    binding={'schema':'kni.synthetic-spacing-adapter.v1','synthetic':True,'model_sha256':result.model_sha256,'evidence_class':'declared','status':'proposed','value_format1':4,'value_format2':0,'rounding':'nearest_integer_ties_away_from_zero','counts':counts,'integer_bearings':[{'glyph':g.name,'left':left_int[i],'right':right_int[i],'advance':int(g.ink_width)+left_int[i]+right_int[i]} for i,g in enumerate(result.glyphs)],'realized_gap_errors':realized,'max_abs_realized_gap_error':scalar(max((abs(Fraction(row['realized_gap_error']['numerator'],row['realized_gap_error']['denominator'])) for row in realized if row['realized_gap_error'] is not None),default=Fraction(0))) if any(row['realized_gap_error'] is not None for row in realized) else None,'exact_requests':exact,'declared_json_sha256':canonical_hash(declared)}
    return declared,binding

def main(argv=None):
    import argparse
    from pathlib import Path
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',required=True);p.add_argument('--output-dir',required=True);a=p.parse_args(argv)
    try:
        def pairs(items):
            obj={}
            for k,v in items:
                if k in obj:reject('duplicate_json_key')
                obj[k]=v
            return obj
        def constant(v):reject('nonfinite_json_constant')
        obj=json.loads(Path(a.input).read_text(encoding='utf-8'),object_pairs_hook=pairs,parse_constant=constant)
        model=Model.from_input(obj);r=model.derive();declared,binding=declared_adapter(model,r);out=Path(a.output_dir)
        if out.exists():reject('output_exists')
        import tempfile,os,shutil
        stage=Path(tempfile.mkdtemp(prefix='.spacing-reference-',dir=out.parent))
        try:
            for name,value in [('result.json',report(model,r)),('declared.json',declared),('adapter.json',binding)]:
                (stage/name).write_text(json.dumps(value,sort_keys=True,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
            if out.exists():reject('output_exists')
            os.rename(stage,out);stage=None
        finally:
            if stage is not None:shutil.rmtree(stage)
        return 0
    except SpacingError as e:
        print(json.dumps({'status':'error','reason':e.code}));return 2
    except UnicodeError:
        print(json.dumps({'status':'error','reason':'utf8_invalid'}));return 2
    except json.JSONDecodeError:
        print(json.dumps({'status':'error','reason':'json_invalid'}));return 2
    except OSError:
        print(json.dumps({'status':'error','reason':'io_error'}));return 2
    except RecursionError:
        print(json.dumps({'status':'error','reason':'input_recursion'}));return 2
    except ValueError:
        print(json.dumps({'status':'error','reason':'value_invalid'}));return 2
if __name__=='__main__':raise SystemExit(main())
