#!/usr/bin/env python3
"""Schema-versioned, frame-isolated canonical per-style table builder."""
import argparse
import csv
import hashlib
import io
import json
import math
import re
import os
import tempfile
from pathlib import Path
from statistics import mean, median
from enum import Enum

FIELDS = ['block','record_type','family','style','engine','pool','frame','sample_base',
          'frame_scale_K_diag','render_K','canonical_K','UPM','construction_K','construction_label','construction_revision','grounding','translation','quantization',
          'tile_size','cap_units','cap_units_status','lineage','profile','domain','n',
          'mean_iou','median_iou','mean_nodes','median_nodes','mean_lines','mean_cubics',
          'C2_missing_extrema','C2_stationary_inflections','C7_zero','C7_duplicate','C7_open',
          'C1','C3','C4','overall','node_definition','autotrace_pin','IoU_role','source_files',
          'source_sha256','source_rows','perstyle_source_json','note']
SCHEMA_VERSION = 'canonical-table-input-v1'
class ErrorCode(str, Enum):
    SCHEMA = 'schema'
    CHECKSUM = 'checksum'
    ROW = 'row'
    KEY = 'key'
    COVERAGE = 'coverage'
    NUMERIC = 'numeric'
    MISMATCH = 'mismatch'
    IO = 'io'
class BuildError(Exception):
    def __init__(self, code, message):
        self.code = code
        self.message = message
        super().__init__(f'{code.value}: {message}')
def fail(code, message):
    raise BuildError(code, message)
def digest(payload):
    return hashlib.sha256(payload).hexdigest()
class JsonNumberText(str):
    """Numeric JSON token, not an ordinary string binding."""

def number(value):
    # CONVENTION: ASCII fixed-point transport, no exponent or whitespace.
    if type(value) is int:
        try:
            value = str(value)
        except ValueError:
            fail(ErrorCode.NUMERIC, 'invalid number')
    if not isinstance(value, str) or re.fullmatch(r'[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)', value) is None:
        fail(ErrorCode.NUMERIC, 'invalid number')
    try:
        x = float(value)
    except (ValueError, TypeError, OverflowError):
        fail(ErrorCode.NUMERIC, 'invalid number')
    if not math.isfinite(x):
        fail(ErrorCode.NUMERIC, 'nonfinite number')
    if x == 0.0 and math.copysign(1.0, x) < 0:
        fail(ErrorCode.NUMERIC, 'negative zero')
    return x
def natural(value):
    if type(value) is int:
        try:
            value = str(value)
        except ValueError:
            fail(ErrorCode.NUMERIC, 'integer too large')
    if not isinstance(value, str) or re.fullmatch(r'[0-9]+', value) is None:
        fail(ErrorCode.NUMERIC, 'expected ASCII nonnegative integer')
    try:
        return int(value)
    except ValueError:
        fail(ErrorCode.NUMERIC, 'integer too large')
def cp(value):
    if not isinstance(value, str) or not value:
        fail(ErrorCode.ROW, 'missing codepoint')
    raw = value.removeprefix('U+')
    # Transport convention: exactly four or six ASCII hexadecimal digits.
    if len(raw) not in (4, 6) or any(c not in '0123456789abcdefABCDEF' for c in raw):
        fail(ErrorCode.ROW, 'invalid hexadecimal codepoint')
    n = int(raw, 16)
    if n < 0 or n > 0x10ffff or 0xd800 <= n <= 0xdfff:
        fail(ErrorCode.ROW, 'invalid Unicode scalar')
    return f'{n:04X}'
def read_tsv(payload, spec):
    try:
        reader = csv.DictReader(io.StringIO(payload.decode('utf-8'), newline=''), delimiter='\t')
        if reader.fieldnames != spec['header'] or len(set(reader.fieldnames)) != len(reader.fieldnames):
            fail(ErrorCode.SCHEMA, 'TSV header differs from manifest')
        if 'schema_version' not in reader.fieldnames:
            fail(ErrorCode.SCHEMA, 'TSV schema_version column missing')
        rows = list(reader)
    except (UnicodeError, csv.Error) as e:
        fail(ErrorCode.ROW, str(e))
    for row in rows:
        if None in row or None in row.values():
            fail(ErrorCode.ROW, 'malformed TSV row')
        if row['schema_version'] != SCHEMA_VERSION:
            fail(ErrorCode.SCHEMA, 'TSV row schema_version mismatch')
    return rows

def lookup(obj, path):
    # Paths are lists of keys, so metadata keys containing punctuation are literal.
    if not isinstance(path, list):
        fail(ErrorCode.SCHEMA, 'metadata path must be a list')
    for part in path:
        if not isinstance(obj, dict) or part not in obj:
            fail(ErrorCode.SCHEMA, 'missing metadata key')
        obj = obj[part]
    if isinstance(obj, (dict, list)) or obj is None:
        fail(ErrorCode.SCHEMA, 'metadata field must be scalar')
    return str(obj)

def fields_from(config, context, metadata):
    out = {}
    for field, rule in config.items():
        if field not in FIELDS:
            fail(ErrorCode.SCHEMA, 'unknown output field')
        if isinstance(rule, str) and not isinstance(rule, JsonNumberText):
            out[field] = rule
        elif isinstance(rule, dict) and set(rule) == {'context'}:
            key = rule['context']
            if key not in context:
                fail(ErrorCode.SCHEMA, 'missing context field')
            out[field] = str(context[key])
        elif isinstance(rule, dict) and set(rule) == {'metadata'}:
            # A context token in a metadata path selects the engine-specific key.
            path = [context[p['context']] if isinstance(p, dict) and set(p) == {'context'}
                    else p for p in rule['metadata']]
            out[field] = lookup(metadata, path)
        else:
            fail(ErrorCode.SCHEMA, 'invalid output field binding')
    return out

MEANS = ('nodes', 'lines', 'cubics')
SUMS = ('C2_missing_extrema', 'C2_stationary_inflections', 'C7_zero', 'C7_duplicate', 'C7_open')
LABELS = ('profile','domain','lineage','node_definition','overall','C1','C3','C4','autotrace_pin','IoU_role')
def aggregate(rows, columns):
    ids = [cp(r[columns['codepoint']]) for r in rows]
    if len(ids) != len(set(ids)):
        fail(ErrorCode.KEY, 'duplicate codepoint in one group')
    ious = [number(r[columns['iou']]) for r in rows]
    if any(not 0 <= x <= 1 for x in ious):
        fail(ErrorCode.NUMERIC, 'IoU outside [0,1]')
    out = {'n':str(len(rows)), 'mean_iou':str(mean(ious)), 'median_iou':str(median(ious))}
    for src in MEANS:
        if src in columns:
            vals = [number(r[columns[src]]) for r in rows]
            if any(x < 0 or not x.is_integer() for x in vals):
                fail(ErrorCode.NUMERIC, f'invalid {src}')
            out['mean_'+src] = str(mean(vals))
            if src == 'nodes':
                out['median_nodes'] = str(median(vals))
    for dest in SUMS:
        if dest in columns:
            out[dest] = str(sum(natural(r[columns[dest]]) for r in rows))
    for dest in LABELS:
        if dest in columns:
            values = {r[columns[dest]] for r in rows}
            if len(values) != 1:
                fail(ErrorCode.MISMATCH, f'mixed {dest} in one group')
            value = next(iter(values))
            if value:
                out[dest] = value
    return out

def load(manifest_path, input_dir):
    manifest = json.loads(Path(manifest_path).read_text(encoding='utf-8'), parse_float=JsonNumberText, parse_int=JsonNumberText)
    if manifest.get('schema_version') != SCHEMA_VERSION:
        fail(ErrorCode.SCHEMA, 'manifest schema_version mismatch')
    tolerance = manifest['numeric_comparison']
    if tolerance['label'] != 'CONVENTION':
        fail(ErrorCode.SCHEMA, 'numeric tolerance requires CONVENTION label')
    rel, absolute = number(tolerance['relative_tolerance']), number(tolerance['absolute_tolerance'])
    if rel < 0 or absolute < 0:
        fail(ErrorCode.NUMERIC, 'negative tolerance')
    root = Path(input_dir).resolve()
    data = {}
    for name, spec in manifest['files'].items():
        # Source IDs, not filenames, determine provenance order.
        path = (root / spec['path']).resolve()
        if not path.is_relative_to(root):
            fail(ErrorCode.SCHEMA, 'input path escapes input directory')
        payload = path.read_bytes()
        if digest(payload) != spec['sha256']:
            fail(ErrorCode.CHECKSUM, f'input checksum mismatch: {name}')
        if spec['kind'] == 'tsv':
            data[name] = read_tsv(payload, spec)
        elif spec['kind'] == 'json':
            obj = json.loads(payload)
            if obj.get('schema_version') != SCHEMA_VERSION:
                fail(ErrorCode.SCHEMA, 'metadata schema_version mismatch')
            data[name] = obj
        else:
            fail(ErrorCode.SCHEMA, 'unknown input kind')
    for check in manifest['metadata_checks']:
        value = lookup(data[check['file']],check['path'])
        expected = manifest['files'][check['equals_source_sha']]['sha256'] if 'equals_source_sha' in check else check['equals_literal']
        if value != expected:
            fail(ErrorCode.MISMATCH, 'metadata binding mismatch')
    return manifest, data, rel, absolute

def build_impl(manifest_path, input_dir):
    m, data, rel, absolute = load(manifest_path, input_dir)
    pools = {}
    if len(set(m['files'])) != len(m['files']):
        fail(ErrorCode.SCHEMA, 'duplicate source ID')
    for row in m['style_pools']:
        key = (row['family'], row['style'])
        if key in pools or not all(type(row[k]) is str and row[k] for k in ('family','style','pool')):
            fail(ErrorCode.KEY, 'invalid/duplicate style pool key')
        pools[key] = row['pool']
    output = []
    def provenance(names):
        if not isinstance(names, list) or len(set(names)) != len(names):
            fail(ErrorCode.SCHEMA, 'invalid provenance list')
        return {'source_files':';'.join(m['files'][n]['path'] for n in names),
                'source_sha256':';'.join(m['files'][n]['sha256'] for n in names)}
    def context(key):
        family, style, engine = key
        if (family,style) not in pools:
            fail(ErrorCode.COVERAGE, 'style has no manifest pool')
        return {'family':family,'style':style,'engine':engine,'pool':pools[(family,style)]}
    def compare(a,b,label):
        if not math.isclose(number(a),number(b),rel_tol=rel,abs_tol=absolute):
            fail(ErrorCode.MISMATCH, label)
    for block in m['blocks']:
        kind = block['kind']
        common = block['fields']
        sources = block['source_files']
        if kind == 'frames':
            frames = {}
            for row in data[block['file']]:
                key = tuple(row[block['style_column']].split('|'))
                if len(key) != 2 or key in frames:
                    fail(ErrorCode.KEY, 'invalid/duplicate frame family|style key')
                frames[key] = row
            expected = {tuple(x) for x in block['expected_styles']}
            if len(expected) != len(block['expected_styles']) or set(frames) != expected:
                fail(ErrorCode.COVERAGE, 'frame styles mismatch')
            for key in sorted(frames):
                row = frames[key]
                ctx = context((*key,''))
                out = {'record_type':'frame','family':key[0],'style':key[1],'pool':ctx['pool']}
                extra=fields_from(common,{**row,**ctx},{})
                if any(k in out and out[k]!=v for k,v in extra.items()):
                    fail(ErrorCode.MISMATCH, 'frame binding changes identity')
                out.update(extra)
                out.update(provenance(sources))
                output.append(out)
        elif kind == 'perstyle':
            if block['join'] not in ('family_style_engine','engine_metadata'):
                fail(ErrorCode.SCHEMA, 'unknown join contract')
            engines = block['engines']
            if not engines or len(set(engines)) != len(engines):
                fail(ErrorCode.SCHEMA, 'engine keyset missing/duplicate')
            expected = {tuple(x) for x in block['expected_styles']}
            if not expected or len(expected) != len(block['expected_styles']):
                fail(ErrorCode.SCHEMA, 'style keyset missing/duplicate')
            metadata = data[block['metadata_file']] if block.get('metadata_file') else {}
            grouped = {}
            columns = block['columns']
            for row in data[block['components']]:
                family = row[columns['family']] if block['join'] == 'family_style_engine' else block['identity']['family']
                style = row[columns['style']] if block['join'] == 'family_style_engine' else block['identity']['style']
                key = (family,style,row[columns['engine']])
                grouped.setdefault(key,[]).append(row)
            expected_keys = {(*style,e) for style in expected for e in engines}
            if set(grouped) != expected_keys:
                fail(ErrorCode.COVERAGE, 'component style/engine keyset mismatch')
            ps = {}
            if block.get('perstyle'):
                for row in data[block['perstyle']]:
                    key = (row['family'],row['style'],row['engine'])
                    if key in ps:
                        fail(ErrorCode.KEY, 'duplicate perstyle key')
                    ps[key] = row
                if set(ps) != expected_keys:
                    fail(ErrorCode.COVERAGE, 'perstyle/component key mismatch')
            for key, rows in sorted(grouped.items()):
                if len(rows) != natural(block['rows_per_group']) or not rows:
                    fail(ErrorCode.COVERAGE, 'rows_per_group mismatch')
                ctx = context(key)
                for field, value in block['required_values'].items():
                    if any(r[field] != value for r in rows):
                        fail(ErrorCode.MISMATCH, 'required input value mismatch')
                # Source pool columns, if present, must agree with external assignment.
                for row in rows + ([ps[key]] if key in ps else []):
                    if 'pool' in row and row['pool'] != ctx['pool']:
                        fail(ErrorCode.MISMATCH, 'source pool differs from manifest')
                stats = aggregate(rows, columns)
                if key in ps:
                    for metric in block['compare_metrics']:
                        if metric not in stats or metric not in ps[key]:
                            fail(ErrorCode.SCHEMA, 'comparison metric missing')
                        compare(stats[metric],ps[key][metric],f'perstyle/component mismatch: {metric}')
                out = dict(stats,record_type='perstyle',family=key[0],style=key[1],engine=key[2],pool=ctx['pool'],source_rows=str(len(rows)))
                for binding in (common,block['engine_fields'][key[2]],block.get('style_fields',{}).get(key[0]+'|'+key[1],{})):
                    extra = fields_from(binding,ctx,metadata)
                    if any(k in out and out[k] != v for k,v in extra.items()):
                        fail(ErrorCode.MISMATCH, 'field binding changes aggregate or identity')
                    out.update(extra)
                if key in ps:
                    original = {k:v for k,v in ps[key].items() if k != 'schema_version'}
                    out['perstyle_source_json'] = json.dumps(original,ensure_ascii=False,sort_keys=True,separators=(',',':'))
                out.update(provenance(sources))
                output.append(out)
            # Optional engine-only input is cross-check data, never a source of invented engines.
            for check in block['crosschecks']:
                key = tuple(check['key'])
                if key not in grouped:
                    fail(ErrorCode.COVERAGE, 'crosscheck target missing')
                left = {}
                for row in data[check['file']]:
                    if row[check['engine_column']] != key[2]:
                        fail(ErrorCode.COVERAGE, 'crosscheck engine mismatch')
                    code = cp(row[check['codepoint_column']])
                    if code in left:
                        fail(ErrorCode.KEY, 'duplicate crosscheck codepoint')
                    left[code] = row[check['iou_column']]
                right = {cp(r[columns['codepoint']]):r[columns['iou']] for r in grouped[key]}
                if left.keys() != right.keys():
                    fail(ErrorCode.COVERAGE, 'crosscheck codepoint mismatch')
                for code in left:
                    compare(left[code],right[code],'crosscheck IoU mismatch')
        elif kind == 'exclusions':
            styles = block['expected_styles']
            if len({tuple(s) for s in styles}) != len(styles):
                fail(ErrorCode.KEY, 'duplicate exclusion style')
            for key in styles:
                ctx = context((*key,''))
                out = dict(record_type='exclusion',family=key[0],style=key[1],pool=ctx['pool'])
                extra=fields_from(common,ctx,{})
                if any(k in out and out[k]!=v for k,v in extra.items()):
                    fail(ErrorCode.MISMATCH, 'exclusion binding changes identity')
                out.update(extra)
                out.update(provenance(sources))
                output.append(out)
        else:
            fail(ErrorCode.SCHEMA, 'unknown block kind')
    for row in output:
        if any(k not in row for k in ('block','family','style')):
            fail(ErrorCode.SCHEMA, 'output sort identity missing')
        if any(not isinstance(v,str) for v in row.values()):
            fail(ErrorCode.SCHEMA, 'output field is not a string')
    output.sort(key=lambda r:(r['block'],r['family'],r['style'],r.get('engine','')))
    keys = [(r['block'],r['family'],r['style'],r.get('engine','')) for r in output]
    if len(keys) != len(set(keys)):
        fail(ErrorCode.KEY, 'duplicate output sort key')
    if len(output) != natural(m['expected_output_rows']):
        fail(ErrorCode.COVERAGE, 'output row count mismatch')
    return output

def build(manifest_path, input_dir):
    try:
        return build_impl(manifest_path,input_dir)
    except BuildError:
        raise
    except OSError as e:
        fail(ErrorCode.IO, str(e))
    except KeyError:
        fail(ErrorCode.SCHEMA, 'missing configuration or input key')
    except (TypeError,ValueError,IndexError,AttributeError) as e:
        fail(ErrorCode.SCHEMA, f'malformed configuration or input: {e}')
def render(rows):
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream,fieldnames=FIELDS,delimiter='\t',lineterminator='\n',extrasaction='raise')
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode('utf-8')
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--input-dir',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    try:
        payload = render(build(args.manifest,args.input_dir))
        # Replace only after successful validation and write, never publish a partial table.
        with tempfile.NamedTemporaryFile(dir=args.output.parent,delete=False) as f:
            temp = Path(f.name)
            try:
                f.write(payload)
                f.flush()
                os.fsync(f.fileno())
            except BaseException:
                temp.unlink(missing_ok=True)
                raise
        try:
            os.replace(temp,args.output)
        finally:
            temp.unlink(missing_ok=True)
        print(digest(payload))
        return 0
    except BuildError as e:
        print(json.dumps({'error':e.code.value,'message':e.message},sort_keys=True),file=__import__('sys').stderr)
        return 2
    except OSError as e:
        print(json.dumps({'error':ErrorCode.IO.value,'message':str(e)},sort_keys=True),file=__import__('sys').stderr)
        return 2
if __name__ == '__main__':
    raise SystemExit(main())
