"""Strict JSON syntax, Rust projection types and ledger duplicate checks."""
import argparse
from pathlib import Path
from strict_json import load,validate,StrictJSONError
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--schema',type=Path,required=True);p.add_argument('--record',type=Path,required=True);a=p.parse_args()
 try:validate(load(a.schema),load(a.record))
 except (StrictJSONError,ValueError) as e:p.exit(1,str(e)+'\n')
 print('SCHEMA_VALID_DESCRIPTIVE_ONLY; source/semantics/real writer compatibility unverified')
