"""Test-only Core source reconstruction, using the existing MARK resolver.

No second lookup algorithm: section_source owns carrier and exact-unit lookup.
The map records only the import lines lifted by the pure Core move, so readers
and portable compiler fixtures recover the byte-identical prior source unit.
"""
from pathlib import Path
import hashlib, importlib.util, json
ROOT=Path(__file__).resolve().parents[2]
_spec=importlib.util.spec_from_file_location('core_station_sections',ROOT/'Tests/Structure/section_source.py')
_sections=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_sections)

def unit_text(name,root=ROOT):
    root=Path(root);name=Path(name).name
    records=json.loads((root/'Tests/Structure/199u-core-map.json').read_text())['sections']
    if name not in records:raise KeyError('not a Core source unit: '+name)
    record=records[name];text=_sections.section_text_exact(root,name)
    if hashlib.sha256(text.encode()).hexdigest()==record['source_sha256']:return text
    if hashlib.sha256(text.encode()).hexdigest()!=record['body_sha256']:
        raise ValueError('Core unit body changed: '+name)
    lines=text.splitlines(keepends=True)
    for item in record['lifted_import_lines']:
        lines.insert(item['line']-1,item['text'])
    restored=''.join(lines)
    if hashlib.sha256(restored.encode()).hexdigest()!=record['source_sha256']:
        raise ValueError('Core import reconstruction changed: '+name)
    return restored

def read_source(path,*args,**kwargs):
    path=Path(path)
    try:path.relative_to(ROOT/'Sources/gor')
    except ValueError:return path.read_text(*args,**kwargs)
    names={'Diag.swift','GeomTrace.swift','GORResources.swift','BuildID.swift','StableCacheKey.swift','SeededRandomNumberGenerator.swift'}
    if path.name not in names:return path.read_text(*args,**kwargs)
    # These pinned Swift inputs are UTF-8. Do not silently reinterpret an encoding.
    encoding=kwargs.get('encoding',args[0] if args else 'utf-8')
    if encoding not in (None,'utf-8','utf8'):raise ValueError('Core source is UTF-8')
    return unit_text(path.name)

def read_bytes(path):
    path=Path(path)
    try:path.relative_to(ROOT/'Sources/gor')
    except ValueError:return path.read_bytes()
    if path.name in {'Diag.swift','GeomTrace.swift','GORResources.swift','BuildID.swift','StableCacheKey.swift','SeededRandomNumberGenerator.swift'}:
        return unit_text(path.name).encode()
    return path.read_bytes()

def materialize(path,destination):
    destination=Path(destination);destination.write_text(read_source(path));return destination
