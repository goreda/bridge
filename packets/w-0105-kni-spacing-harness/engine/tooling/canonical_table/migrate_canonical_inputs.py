#!/usr/bin/env python3
"""Explicit transport migration into a supplied versioned table contract."""
import argparse
import csv
import io
import json
import os
from pathlib import Path
import shutil
import tempfile
from canonical_table_build import BuildError, ErrorCode, SCHEMA_VERSION, digest

PLAN_VERSION = 'canonical-table-migration-v1'
class NumberText(str): pass
def strict_load(raw):
    def pairs(items):
        obj={}
        for k,v in items:
            if k in obj: raise ValueError('duplicate JSON key')
            obj[k]=v
        return obj
    def constant(v): raise ValueError('nonfinite JSON number: '+v)
    return json.loads(raw,parse_float=NumberText,parse_int=NumberText,parse_constant=constant,object_pairs_hook=pairs)
def encode(obj):
    if isinstance(obj,NumberText): return str(obj)
    if isinstance(obj,dict): return '{'+','.join(json.dumps(k,ensure_ascii=False)+':'+encode(v) for k,v in sorted(obj.items()))+'}'
    if isinstance(obj,list): return '['+','.join(encode(v) for v in obj)+']'
    return json.dumps(obj,ensure_ascii=False,allow_nan=False)
def embedded_strings(obj,path=()):
    if isinstance(obj,dict):
        for k,v in obj.items(): yield from embedded_strings(v,path+(k,))
    elif isinstance(obj,list):
        for i,v in enumerate(obj): yield from embedded_strings(v,path+(i,))
    elif isinstance(obj,str) and not isinstance(obj,NumberText): yield path,obj

def reject(code, message):
    raise BuildError(code,message)
def migrate(plan_path, target_manifest_path, input_dir, output_dir):
    """Validate a schema-only migration; publish only into a new output directory.

    The target manifest is an explicit contract, never inferred from old labels,
    filenames, family names, engine sets, row counts or measurement values.
    No builder or measurement is run. Source rows and scalar metadata stay text.
    """
    staging = None
    try:
        plan=strict_load(Path(plan_path).read_bytes())
        target=strict_load(Path(target_manifest_path).read_bytes())
        if plan['schema_version']!=PLAN_VERSION or target['schema_version']!=SCHEMA_VERSION:
            reject(ErrorCode.SCHEMA,'migration/target schema version mismatch')
        root=Path(input_dir).resolve();output=Path(output_dir)
        if output.exists():reject(ErrorCode.IO,'output directory already exists')
        if set(plan['sources'])!=set(target['files']):reject(ErrorCode.COVERAGE,'source IDs differ from target contract')
        rewrites=plan.get('metadata_sha_rewrites',[])
        payloads={};receipts=[];paths=set()
        for source_id,source in plan['sources'].items():
            spec=target['files'][source_id]
            path=(root/source['path']).resolve()
            if not path.is_relative_to(root):reject(ErrorCode.SCHEMA,'source path escapes input directory')
            raw=path.read_bytes()
            if spec.get('sha256')!=digest(raw):reject(ErrorCode.CHECKSUM,'target manifest current source checksum mismatch')
            if digest(raw)!=source['sha256']:reject(ErrorCode.CHECKSUM,'legacy source checksum mismatch')
            rel=Path(spec['path'])
            if rel.is_absolute() or '..' in rel.parts or str(rel) in paths or str(rel) in ('manifest.json','migration-receipt.json'):
                reject(ErrorCode.SCHEMA,'invalid or colliding target path')
            paths.add(str(rel))
            if spec['kind']=='tsv':
                bom=b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b''
                body=raw[len(bom):];lines=body.splitlines(keepends=True)
                if not lines:reject(ErrorCode.ROW,'empty TSV')
                def fields(line): return line.rstrip(b'\r\n').decode('utf-8').split('\t')
                header=fields(lines[0])
                if header!=source['header'] or not header or len(set(header))!=len(header) or 'schema_version' in header:
                    reject(ErrorCode.SCHEMA,'legacy header mismatch or already versioned')
                if spec['header']!=['schema_version']+header:reject(ErrorCode.SCHEMA,'target header must only prepend schema_version')
                for line in lines[1:]:
                    if line.rstrip(b'\r\n')==b'' or len(fields(line))!=len(header):reject(ErrorCode.ROW,'blank or malformed physical TSV row')
                row_count=len(lines)-1
                if 'rows' not in source or int(source['rows'])!=row_count:reject(ErrorCode.ROW,'declared legacy row count mismatch')
                converted=bom+b'schema_version\t'+lines[0]+b''.join(SCHEMA_VERSION.encode()+b'\t'+line for line in lines[1:])
            elif spec['kind']=='json':
                obj=strict_load(raw)
                if not isinstance(obj,dict) or 'schema_version' in obj:reject(ErrorCode.SCHEMA,'legacy metadata is not an unversioned object')
                converted=(encode(dict(schema_version=SCHEMA_VERSION,**obj))+'\n').encode('utf-8');row_count=None
            else:reject(ErrorCode.SCHEMA,'unknown target source kind')
            payloads[rel]=converted
            spec['sha256']=digest(converted)
            receipts.append(dict(source_id=source_id,input_sha256=digest(raw),output_sha256=digest(converted),rows=row_count,change='schema_version_only_values_preserved'))
        seen=set()
        for binding in rewrites:
            sid=binding['file'];ref=binding['source_sha'];keys=binding['path']
            if target['files'][sid]['kind']!='json' or not keys or (sid,tuple(keys)) in seen:
                reject(ErrorCode.SCHEMA,'invalid/duplicate metadata rewrite')
            seen.add((sid,tuple(keys)));rel=Path(target['files'][sid]['path']);obj=strict_load(payloads[rel]);current=obj
            for key in keys[:-1]:current=current[key]
            if current[keys[-1]]!=plan['sources'][ref]['sha256']:
                reject(ErrorCode.MISMATCH,'legacy embedded SHA does not match declared source')
            if target['files'][ref]['kind']!='tsv':
                reject(ErrorCode.SCHEMA,'metadata SHA rewrite references must be TSV sources')
            current[keys[-1]]=target['files'][ref]['sha256']
            payloads[rel]=(encode(obj)+'\n').encode('utf-8')
            target['files'][sid]['sha256']=digest(payloads[rel])
            for receipt in receipts:
                if receipt['source_id']==sid:
                    receipt['output_sha256']=digest(payloads[rel]);receipt['change']='schema_version_and_explicit_source_sha_binding'
        # Every embedded occurrence of a migrated legacy digest must be gone.
        old_hashes={v['sha256'] for v in plan['sources'].values()}
        for sid,spec in target['files'].items():
            if spec['kind']=='json':
                for keys,value in embedded_strings(strict_load(payloads[Path(spec['path'])])):
                    if any(h in value for h in old_hashes):reject(ErrorCode.MISMATCH,'unlisted stale embedded source SHA')
        for check in target['metadata_checks']:
            obj=strict_load(payloads[Path(target['files'][check['file']]['path'])])
            for key in check['path']:obj=obj[key]
            expected=target['files'][check['equals_source_sha']]['sha256'] if 'equals_source_sha' in check else check['equals_literal']
            if str(obj)!=expected:reject(ErrorCode.MISMATCH,'target metadata binding not satisfied')
        staging=Path(tempfile.mkdtemp(prefix='.canonical-migration-',dir=output.parent))
        for rel,body in payloads.items():
            path=staging/rel;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(body)
        (staging/'manifest.json').write_text(encode(target)+'\n',encoding='utf-8')
        (staging/'migration-receipt.json').write_text(json.dumps(dict(schema_version=PLAN_VERSION,sources=sorted(receipts,key=lambda r:r['source_id']),measurement_run=False),sort_keys=True,indent=2)+'\n',encoding='utf-8')
        # Publish a new directory; an existing destination must never be overwritten.
        if output.exists():reject(ErrorCode.IO,'output directory appeared during migration')
        os.rename(staging,output);staging=None
        return receipts
    except BuildError:raise
    except OSError as e:reject(ErrorCode.IO,str(e))
    except (KeyError,ValueError,TypeError,AttributeError,UnicodeError,csv.Error) as e:reject(ErrorCode.SCHEMA,str(e))
    finally:
        if staging is not None:shutil.rmtree(staging)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ('plan','target-manifest','input-dir','output-dir'):parser.add_argument('--'+name,type=Path,required=True)
    args=parser.parse_args()
    try:migrate(args.plan,args.target_manifest,args.input_dir,args.output_dir);return 0
    except BuildError as e:
        print(json.dumps({'error':e.code.value,'message':e.message},sort_keys=True),file=__import__('sys').stderr);return 2
if __name__=='__main__':raise SystemExit(main())
