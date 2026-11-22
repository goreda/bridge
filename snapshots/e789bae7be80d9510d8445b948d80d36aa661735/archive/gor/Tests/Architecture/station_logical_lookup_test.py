#!/usr/bin/env python3
"""Exact PP/ThreeD logical views survive filename retirement and MARK placement.

This is a source-read witness, not a station-map, native-build or Step0 GO.
Historical fixtures and all current/historical manifest hashes stay unchanged.
"""
from pathlib import Path
import importlib.util
import json
import shutil
import tempfile

ROOT=Path(__file__).resolve().parents[2]

def load(root,name):
    spec=importlib.util.spec_from_file_location(name,root/'Tests/Structure'/(name+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def views(root):
    pp=load(root,'pp_split');td=load(root,'threed_split')
    result={name:pp.text(root,name) for name in pp._m(root)}
    result['ThreeD-current']=td.text(root)
    result['ThreeD-historical']=td.historical_text(root)
    result['ThreeD-crop-span']=td.span(root,'SourcePixelCrop.swift')
    result['parts']={part['file']:pp.part_text(root,part['file'])
                     for entry in pp._m(root).values() for part in entry['parts']}
    return result

expected=views(ROOT)
with tempfile.TemporaryDirectory(prefix='station-logical-') as directory:
    root=Path(directory)
    shutil.copytree(ROOT/'Sources',root/'Sources')
    shutil.copytree(ROOT/'Tests/Structure',root/'Tests/Structure',ignore=shutil.ignore_patterns('__pycache__'))
    pp=load(root,'pp_split');td=load(root,'threed_split')
    manifests={name:(root/'Tests/Structure'/name).read_bytes() for name in
               ('pp-split-manifest.json','threed-split-manifest.json','retirements.json')}
    folder=root/'Sources/gor/ScratchStation';folder.mkdir()
    names=[part['file'] for entry in pp._m(root).values() for part in entry['parts']]
    prefixes={name:pp.part_prefix(root,name) for name in names}
    imports=dict.fromkeys(line for prefix in prefixes.values() for line in prefix.splitlines(keepends=True) if line.startswith('import '))
    pp_carrier=folder/'PP.swift';merged=''.join(imports);raw_merged='';removed=[]
    for entry in pp._m(root).values():
        for part in entry['parts']:
            name=part['file']
            if name in pp.CONTROLLER_PINS:continue  # already under the real pinned Controller/Input host
            path=root/'Sources/gor/gor'/name
            prefix=prefixes[name]
            before=path.read_text();assert before.startswith(prefix),name
            assert before.endswith('\n'),name
            kept=''.join(line for line in prefix.splitlines(keepends=True) if not line.startswith('import '))
            raw_merged+='// MARK: - '+name+'\n'+before
            merged+='// MARK: - '+name+'\n'+kept+before[len(prefix):]
            path.unlink();removed.append(path)
    lifted_merged=merged;pp_carrier.write_text(lifted_merged)
    td_carrier=folder/'ThreeD.swift';merged=''
    for station in td._m(root)['stations'].values():
        path=root/station['file'];before=path.read_text();assert before.endswith('\n')
        merged+='// MARK: - '+path.name+'\n'+before
        path.unlink();removed.append(path)
    td_carrier.write_text(merged)
    assert len(removed)==19 and all(not path.exists() for path in removed)
    pp_carrier.write_text(raw_merged)
    assert views(root)==expected,'logical source bytes changed after plain MARK concatenation'
    pp_carrier.write_text(lifted_merged)
    assert views(root)==expected,'logical source bytes changed after MARK moves/import lifting'
    for name,before in manifests.items():assert (root/'Tests/Structure'/name).read_bytes()==before,name
    assert pp.path(root,'PPController.swift').read_text()==expected['PPController.swift']
    assert td.path(root).read_text()==expected['ThreeD-current']
    print('PASS literal-path RED: 19 former files absent; PP path no longer depends on VRStereoControlInput.swift')
    print('PASS moved GREEN: both PP reconstructions, all 16 live parts, current/historical ThreeD and crop span byte-identical')
    print('PASS unchanged manifests, fixture paths, whole/section/current/historical pins')

    def rejected(label,change,check):
        backups={path:path.read_bytes() for path in change}
        try:
            for path,transform in change.items():path.write_text(transform(path.read_text()))
            try:check()
            except (AssertionError,KeyError,FileNotFoundError,IndexError):pass
            else:raise AssertionError('mutant accepted: '+label)
        finally:
            for path,before in backups.items():path.write_bytes(before)
        print('PASS mutant RED:',label)

    rejected('PP moved source mutation',
             {pp_carrier:lambda text:text.replace('enum GeomTrace {','enum GeomTraceChanged {',1)},
             lambda:pp.text(root,'PPController.swift'))
    rejected('ThreeD moved source mutation',
             {td_carrier:lambda text:text.replace('enum SourcePixelBounds','enum SourcePixelBoundsChanged',1)},
             lambda:td.text(root))
    rejected('lifted carrier import missing',
             {pp_carrier:lambda text:text.replace('import IOKit\n','',1)},
             lambda:pp.text(root,'PPController.swift'))
    rejected('unit missing, no stale-path fallback',
             {pp_carrier:lambda text:text.replace('// MARK: - VRStereoControlInput.swift','// MARK: - MissingUnit.swift',1)},
             lambda:pp.path(root,'PPController.swift'))
    rejected('bytes outside ThreeD recorded sections',
             {td_carrier:lambda text:text+'// unrecorded source tail\n'},
             lambda:td.text(root))
    pp_fixture=next(part['historical_fixture'] for entry in pp._m(root).values()
                    for part in entry['parts'] if 'historical_fixture' in part)
    td_fixture=next(station['historical_fixture'] for station in td._m(root)['stations'].values()
                    if 'historical_fixture' in station)
    rejected('PP historical fixture tamper',{root/pp_fixture:lambda text:text+'\n'},
             lambda:pp.text(root,'PPController.swift') if pp_fixture in
             [part.get('historical_fixture') for part in pp._m(root)['PPController.swift']['parts']]
             else pp.text(root,'PPController_Features.swift'))
    rejected('ThreeD historical fixture tamper',{root/td_fixture:lambda text:text+'\n'},
             lambda:td.historical_text(root))
    duplicate=folder/'Duplicate.swift'
    duplicate.write_text('// MARK: - VRStereoControlInput.swift\nstruct Duplicate {}\n')
    try:
        try:pp.text(root,'PPController.swift')
        except KeyError:pass
        else:raise AssertionError('ambiguous PP unit accepted')
    finally:duplicate.unlink()
    print('PASS mutant RED: ambiguous MARK carriers')
    assert views(root)==expected,'mutant restoration changed the reference tree'

# Legacy fallback is permitted only when the split manifest itself is absent.
with tempfile.TemporaryDirectory(prefix='station-legacy-') as directory:
    root=Path(directory)
    assert load(ROOT,'pp_split').path(root,'PPController.swift')==root/'Sources/gor/gor/PPController.swift'
    assert load(ROOT,'threed_split').path(root)==root/'Sources/gor/gor/ThreeD.swift'
print('PASS legacy-without-manifest fallback; Swift/native build NOT_RUN; station-map acceptance NOT_CLAIMED')
