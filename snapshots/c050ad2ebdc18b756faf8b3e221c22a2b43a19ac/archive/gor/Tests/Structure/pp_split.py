"""Reads the split PPController files. text(root, name) rebuilds the former PPController.swift or
PPController_Features.swift byte-exactly from the per-type files (preamble and per-file header line
counts are stored in pp-split-manifest.json). path(root, name) writes that text to a cache file and returns
its Path, so callers keep using read_text(). Falls back to the plain path when the split files are absent
(an older tree). Verification: sha256 of the rebuilt text must equal the stored sha256 of the original."""
import json,pathlib,hashlib,tempfile,importlib.util,re
PART_IMPORTS='import AppKit\nimport CoreImage\nimport Foundation\nimport IOKit\nimport IOKit.ps\nimport CoreGraphics\nimport Darwin\nimport QuartzCore\n'

def source_sections(root):
    root=pathlib.Path(root)
    spec=importlib.util.spec_from_file_location('pp_station_sections',root/'Tests/Structure/section_source.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def part_host(root,name):
    return source_sections(root).section_file(root,name)

def part_prefix(root,name):
    """Recorded part header. Edited parts retain their pinned historical header."""
    root=pathlib.Path(root)
    part=next(part for entry in _m(root).values() for part in entry['parts'] if part['file']==name)
    if 'historical_fixture' in part:
        data=(root/part['historical_fixture']).read_bytes()
        assert hashlib.sha256(data).hexdigest()==part['historical_sha256'],('historical fixture',name)
        prefix='\n'.join(data.decode().split('\n')[:part['header_lines']])+'\n'
        if name=='PPController.swift':
            # The pinned CURRENT file added CoreFoundation after the split.
            # header_lines still describes the HISTORICAL fixture, not the
            # current import count. Its whole current SHA remains checked.
            comments=''.join(line for line in prefix.splitlines(keepends=True) if not line.startswith('import '))
            prefix=comments+PART_IMPORTS.replace('import Foundation\n','import Foundation\nimport CoreFoundation\n')
        return prefix

    assert part['header_lines']==len(PART_IMPORTS.splitlines()),('unrecorded part header',name)
    return PART_IMPORTS

def part_text(root,name):
    """Exact former part view. Imports may be lifted only into a real MARK carrier."""
    root=pathlib.Path(root)
    if name in {'GeomTrace.swift','SeededRandomNumberGenerator.swift'} and (root/'Tests/Structure/199u-core-map.json').is_file():
        spec=importlib.util.spec_from_file_location('pp_core_source',root/'Tests/Structure/core_source.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        return module.unit_text(name,root)
    ss=source_sections(root);host=ss.section_file(root,name)
    text=ss.section_text_exact(root,name)
    if host==root/'Sources/gor/gor'/name:
        return text
    carrier=host.read_text();header=[]
    for line in carrier.splitlines():
        if ss.UNIT_MARK.match(line):break
        header.append(line)
    prefix=part_prefix(root,name)
    if name not in CONTROLLER_PINS and text.startswith(prefix):
        return text  # a byte-exact concatenation needs no import reconstruction
    required={line for line in prefix.splitlines() if line.startswith('import ')}
    assert required<=set(header),('carrier import union',name)
    if name in CONTROLLER_PINS:
        controller_body(root,name)  # retain the separately recorded Controller section pin
        assert text.startswith('\n'),('Controller separator',name)
        return prefix+text[1:]
    if not text.startswith(prefix):
        pattern=''.join('(?:'+re.escape(line)+')?' if line.startswith('import ') else re.escape(line)
                        for line in prefix.splitlines(keepends=True))
        match=re.match(pattern,text)
        assert match is not None,('unit header changed beyond import lifting',name)
        text=prefix+text[match.end():]
    return text
CONTROLLER_PINS = {
    "InputController.swift": "2f05e6767b9100f179122f6ef9904a5481f2436fa9e0ef7749dfda7763306f89",
    "DragDropHandler.swift": "16e217064f814b612115382f9bc593b1d21cd70ab0b7c09163e1ac6bed03dd50",
}
def controller_body(root,name):
    spec=importlib.util.spec_from_file_location("section_source",root/"Tests/Structure/section_source.py")
    ss=importlib.util.module_from_spec(spec);spec.loader.exec_module(ss)
    data=ss.pinned_bytes(root,"Sources/gor/Player/Input.swift#"+name)
    assert hashlib.sha256(data).hexdigest()==CONTROLLER_PINS[name],("Controller section pin",name)
    # Section separator is not a part of the old file body. Preserve every other byte.
    assert data.startswith(b"\n"),("Controller separator",name)
    return data[1:].decode().split("\n")[:-1]

def _m(root):
    return json.loads((pathlib.Path(root)/'Tests/Structure/pp-split-manifest.json').read_text())['files']
def text(root,name):
    root=pathlib.Path(root);e=_m(root)[name];g=root/'Sources/gor/gor'
    out=list(e['preamble'])
    for p in e['parts']:
        if 'historical_fixture' in p:
            src=root/p['historical_fixture']
            assert hashlib.sha256(src.read_bytes()).hexdigest()==p['historical_sha256'],('historical fixture',p['file'])
            content=src.read_text()
        else:
            content=part_text(root,p['file'])
        lines=content.split('\n')[:-1]
        body=lines[p['header_lines']:]
        assert len(body)==p['body_lines'],(p['file'],len(body),p['body_lines'])
        out+=body
    t='\n'.join(out)+'\n'
    assert hashlib.sha256(t.encode()).hexdigest()==e['sha256'],name
    return t
def path(root,name):
    root=pathlib.Path(root)
    if not (root/'Tests/Structure/pp-split-manifest.json').exists():
        return root/'Sources/gor/gor'/name
    t=text(root,name)
    d=pathlib.Path(tempfile.gettempdir())/('pp_split_'+hashlib.sha256(t.encode()).hexdigest()[:16])/'Sources/gor/gor'
    d.mkdir(parents=True,exist_ok=True)
    f=d/name
    if not f.exists() or f.read_text()!=t: f.write_text(t)
    return f
def dpath(d,name):
    """Same as path(), for callers holding the Sources/gor/gor directory instead of the repo root."""
    d=pathlib.Path(d)
    if d.parts[-3:]==('Sources','gor','gor'):
        return path(d.parents[2],name)
    return d/name
