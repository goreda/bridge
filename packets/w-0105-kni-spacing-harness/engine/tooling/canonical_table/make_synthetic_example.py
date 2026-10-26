#!/usr/bin/env python3
"""Generate a small synthetic manifest and headed inputs, not measurement data."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
from canonical_table_build import SCHEMA_VERSION

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,required=True)
    args=parser.parse_args()
    args.directory.mkdir(parents=True,exist_ok=False)
    header=['schema_version','family','style','engine','cp','iou']
    rows=[dict(schema_version=SCHEMA_VERSION,family='Synthetic',style='Example',engine='engine_example',cp=c,iou=v) for c,v in [('0041','0.5'),('0042','1.0')]]
    path=args.directory/'components.tsv'
    with path.open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,header,delimiter='\t',lineterminator='\n');w.writeheader();w.writerows(rows)
    manifest=dict(schema_version=SCHEMA_VERSION,numeric_comparison=dict(label='CONVENTION',relative_tolerance='0',absolute_tolerance='0'),files={'components':dict(path=path.name,kind='tsv',header=header,sha256=hashlib.sha256(path.read_bytes()).hexdigest())},metadata_checks=[],style_pools=[dict(family='Synthetic',style='Example',pool='synthetic_pool')],expected_output_rows=1,blocks=[dict(kind='perstyle',join='family_style_engine',components='components',perstyle='',metadata_file='',engines=['engine_example'],expected_styles=[['Synthetic','Example']],rows_per_group=2,columns=dict(family='family',style='style',engine='engine',codepoint='cp',iou='iou'),required_values={},compare_metrics=[],fields=dict(block='SYNTHETIC_EXAMPLE',frame='synthetic_frame'),engine_fields={'engine_example':{}},source_files=['components'],crosschecks=[])])
    (args.directory/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
