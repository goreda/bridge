"""Prepare annotation input from capture-audit v1; never write the audit or CFF.
The caller supplies independently bound source edges and node memberships.
No guide positions or semantic class guesses occur here.
"""
import argparse, hashlib, json, math, subprocess
from pathlib import Path

def prepare(audit, binding):
    if audit.get('schema') != 'kni.capture-audit.v1':
        raise ValueError('unsupported audit schema')
    frame = audit['frame']
    if frame['quantization'] != 'nearest_integer':
        raise ValueError('unsupported quantization')
    if binding['audit_frame'] != frame:
        raise ValueError('frame mismatch')
    scale = frame['scale']
    tx, ty = frame['translation']
    if not all(math.isfinite(v) for v in (scale, tx, ty)) or scale <= 0:
        raise ValueError('invalid frame')
    def field(x):
        x = str(x)
        if any(c in x for c in '\t\r\n'):
            raise ValueError('invalid sidecar field')
        return x
    def nearest_integer(x):
        # CONVENTION: reproduce Rust f64::round ties away from zero.
        fraction, integer = math.modf(x)
        return integer + (math.copysign(1.0, x) if abs(fraction) >= 0.5 else 0.0)
    s = binding['scope']
    lines = ['\t'.join(map(field, ['S', s['font'], s['master'], s['style'], s['frame'], binding['source_pin'], scale]))]
    lines += ['C\t' + field(c) for c in binding['classes']]
    for e in binding['edges']:
        lines.append('\t'.join(map(field, ['E', e['edge_id'], e['glyph'], e['class'], e['membership_evidence'], ','.join(map(str, e['source_y']))])))
    available = {}
    for ri, ring in enumerate(audit['float_rings']):
        pts = [ring['start']]
        for span in ring['spans']:
            pts.append(span['L'] if 'L' in span else span['C'][-1])
        for ni, p in enumerate(pts):
            if not all(math.isfinite(v) for v in p):
                raise ValueError('nonfinite audit point')
            available[f'{ri}:{ni}'] = nearest_integer(p[1] + ty)
    memberships = binding['node_memberships']
    if set(memberships) - set(available):
        raise ValueError('unknown audit node membership')
    for nid, y in available.items():
        lines.append('\t'.join(map(field, ['N', nid, binding['glyph'], y, memberships.get(nid, '')])))
    return '\n'.join(lines) + '\n'

def main():
    p=argparse.ArgumentParser();p.add_argument('audit');p.add_argument('bindings');p.add_argument('executable');a=p.parse_args()
    path=Path(a.audit);raw=path.read_bytes();binding=json.loads(Path(a.bindings).read_text())
    if binding['audit_sha256'] != hashlib.sha256(raw).hexdigest():
        raise ValueError('audit pin mismatch')
    stream=prepare(json.loads(raw),binding)
    r=subprocess.run([a.executable],input=stream,text=True,capture_output=True,check=True)
    if path.read_bytes()!=raw:
        raise RuntimeError('audit bytes changed')
    print(r.stdout,end='')
if __name__=='__main__':main()
