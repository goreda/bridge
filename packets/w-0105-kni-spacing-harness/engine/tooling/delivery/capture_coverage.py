#!/usr/bin/env python3
"""Plan missing source captures without composing or inventing outlines."""
import argparse,json,unicodedata
from pathlib import Path

def plan(manifest):
 available={int(r['codepoint'].removeprefix('U+'),16) if isinstance(r['codepoint'],str) else r['codepoint']:r for r in manifest.get('glyphs',[])}
 requested={int(v.removeprefix('U+'),16) if isinstance(v,str) else v for v in manifest.get('required_codepoints',[])}
 return [{'codepoint':f'U+{cp:04X}','character':chr(cp),'unicode_name':unicodedata.name(chr(cp),'UNASSIGNED'),'action':'CAPTURE_SOURCE' if cp not in available else 'VERIFY_CAPTURE','decomposition_reference':unicodedata.decomposition(chr(cp)),'compose_outline':False} for cp in sorted(requested)]
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--manifest',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 Path(a.output).write_text(json.dumps(plan(json.loads(Path(a.manifest).read_text())),indent=2,ensure_ascii=True)+'\n')
