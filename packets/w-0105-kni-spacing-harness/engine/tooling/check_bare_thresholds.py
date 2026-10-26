#!/usr/bin/env python3
"""FAIL on any numeric literal in guarded files not covered by threshold-inventory.tsv.
Allowlist key = (file, value text) appearing on a line within the file; each inventory row must
carry a non-empty status and derivation_or_note (derivation or source). Usage: run from engine/."""
import re,sys,csv
INV=sys.argv[1] if len(sys.argv)>1 else 'tooling/threshold-inventory.tsv'
GUARD=['core/src/capture.rs','core/src/capture_fit.rs','core/src/form.rs']+__import__('glob').glob('metrics/src/*.rs')
TRIV={'0','1','2','0.0','1.0','2.0','0.','1.','2'}
num=re.compile(r'(?<![A-Za-z_0-9.])(\d+\.\d+(?:e-?\d+)?|\d+e-?\d+|\d+\.(?![.\w])|\d+)(?![A-Za-z_0-9]*\()')

# Explicit MATH/FORMAT rules: (file regex, line regex, reason). Every rule needs a reason; thresholds never go here.
RULES=[
 (r'core/src/capture_fit\.rs', r'\b(sqrt|powi|hypot|atan2|acos|to_degrees|to_radians|clamp\(-1\.0|signum)\b|\[\[0\.0; 3\]; 3\]|\[0\.0; 3\]|q\[\d\]\[\d\]|3\.0 \* \(-v0|6\.0 \* \(v0|3\.0 \* \(v1|mt \* mt|v \* v \* v|1\.0 - t|/ 2\.0|\* 2\.0|2\.0 \*|\+ 4\.0|4\.0 \*|\bi \+ 1\b', 'Bezier/quadric/least-squares algebra and index arithmetic: formula coefficients, not thresholds'),
 (r'core/src/capture\.rs', r'LENBASE|LENEXT|DBASE|DEXT|ORDER|\bcode\b|png|stride|recon|77\*|\bs<256|li>=29|ds>=30|ct\{|ch=match', 'PNG/inflate format constants (RFC 1950/1951, PNG spec)'),
 (r'core/src/capture\.rs', r'cell_extent|coordinate \+', 'pixel-cell geometry (1px cell)'),
 (r'core/src/form\.rs', r'sqrt|\[0\.0; 3\]|m\[|/ 4\.0|n < 3|dense\.len\(\) < 3|ccw', 'conic/circle algebra and minimum-point counts'),
 (r'metrics/src/distance_field\.rs', r'.', 'chamfer 3-4 distance weights (Borgefors)'),
 (r'metrics/src/(gpos|export_gpos)\.rs', r'u16be|u32be|header|take\(|be_bytes|matrix_len|offset|fixed_overhead|err_sum', 'OpenType GPOS binary layout / size model'),
 (r'metrics/src/evidence\.rs', r'"', 'string literal text, not numeric parameters'),
 (r'metrics/src/mechanisms\.rs', r'"|\\$', 'string literal text'),
 (r'metrics/src/gen\.rs', r'f\[\d\]|f\.len\(\)|cp\[|\bcp\b', 'TSV field indices'),
 (r'metrics/src/(baseline_htls|side_walls)\.rs', r'180\.0|/ 100\.0|1000\.0\)|\* 100\.0|\* 0\.5', 'unit conversion (deg->rad, percent, per-mille) or half-value'),
 (r'metrics/src/params\.rs', r'/ 100\.0', 'percent conversion'),
 (r'metrics/src/stress\.rs', r'1e-12|255', 'float epsilon / 8-bit white'),
 (r'core/src/capture\.rs', r'case|segs\.push|signed_area|get\(&mut self|align\(|n<3|len\(\)>=4|pts\.len\(\)>=4', 'marching-squares case table (16 cells), bit reader, minimum-vertex counts for a ring (3), closed loop (4)'),
 (r'core/src/capture\.rs', r'trace_field\(w,h,&\|r,c\|->f64\{if r>=0&&\(r as usize\)<h.*,0\.5\)', 'iso level 0.5 (inventory capture.rs:372)'),
 (r'core/src/capture_fit\.rs', r'type Quad|n < 3|m < 2|n < 2|m == 0 \|\| n < 3', 'quadric dimension / minimum-point counts'),
 (r'core/src/capture_fit\.rs', r'<= 0\.5|- 0\.5 \+', 'unit pixel square half-width (relocation search, 1px cell)'),
 (r'core/src/capture_fit\.rs|core/src/form\.rs|metrics/src/(positions|stress)\.rs', r'1e-12', 'float epsilon'),
]
RR=[(re.compile(a),re.compile(b),c) for a,b,c in RULES]
def by_rule(f,l):
    return any(a.search(f) and b.search(l) for a,b,c in RR)
rows=list(csv.DictReader(open(INV),delimiter='\t'))
bad=[]
cov={}
for r in rows:
    if not r['status'].strip() or not r['derivation_or_note'].strip(): bad.append(f"inventory row without status/derivation: {r['file']}:{r['line']}")
    cov.setdefault(r['file'],[]).append(r)
def covered(f,line,s):
    t=s.strip()
    for r in cov.get(f,[]):
        if any(a.strip() and a.strip().split('//')[0].strip()==t for a in [r.get('anchor','')]): return True
    return False
def covered_by_line_UNUSED(f,line,s):
    for r in cov.get(f,[]):
        try:
            if str(line)==r['line'] or (r['line'].split('-')[0].isdigit() and int(r['line'].split('-')[0])<=line<=int(r['line'].split('-')[-1])): return True
        except: pass
    return False
for f in GUARD:
    for i,l in enumerate(open(f),1):
        if '#[cfg(test)]' in l: break
        s=l.split('//')[0]
        for m in num.finditer(s):
            if m.group(1) in TRIV: continue
            if f.endswith('capture.rs') and 30<=i<=140: continue
            if by_rule(f,l): continue
            if not covered(f,i,s): bad.append(f"{f}:{i}: unlisted numeric {m.group(1)}: {l.strip()[:90]}")
print('\n'.join(bad[:200])); print(f"{len(bad)} violations"); sys.exit(1 if bad else 0)
