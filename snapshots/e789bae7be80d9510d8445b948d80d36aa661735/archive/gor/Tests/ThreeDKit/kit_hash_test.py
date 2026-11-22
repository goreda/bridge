#!/usr/bin/env python3
"""Production Swift KitHash against Python canonical fixtures, plus source pins."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import hashlib, json, os, pathlib, sys, tempfile, shutil, subprocess
root = pathlib.Path(__file__).resolve().parents[2]; sys.path.insert(0, str(root / 'tools/depth_analysis'))
import kit_hash
def _sec_file(root,name):
    import tempfile,pathlib
    b=(_threed_split().path(root)).read_text()
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'KitHash.swift'+' '):_b.index('// END relocated '+'KitHash.swift'+'\n')])((_threed_split().path(root)).read_text()); kit = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDKit.swift'+' '):_b.index('// END relocated '+'ThreeDKit.swift'+'\n')])((_threed_split().path(root)).read_text()); sh = (root / 'tools/gor-fetch-models.sh').read_text()
bad = 0
def check(n, c):
    global bad; print(('PASS ' if c else 'FAIL ') + n); bad += (not c)
def model(pkg):  # the Swift steps: regular files, rel path '/'-separated, bytewise sort, path NUL bytes NUL; symlink -> None
    recs = []
    for r, ds, fs in os.walk(pkg):
        for n in ds + fs:
            if os.path.islink(os.path.join(r, n)): return None
        for n in fs: recs.append(os.path.relpath(os.path.join(r, n), pkg).replace(os.sep, '/'))
    h = hashlib.sha256(); size = 0
    for rel in sorted(recs, key=lambda s: list(s.encode())):
        b = open(os.path.join(pkg, rel), 'rb').read(); h.update(rel.encode() + b'\0' + b + b'\0'); size += len(b)
    return h.hexdigest(), size
with tempfile.TemporaryDirectory() as d:
    p = pathlib.Path(d) / 'x_fp16.mlpackage'
    files = {'Manifest.json': b'{}', 'Data/com.apple.CoreML/weights/weight.bin': os.urandom(3000), 'Data/com.apple.CoreML/model.mlmodel': b'model', 'a/B': b'1', 'a/b': b'2', 'a/\u00e9': b'3', '.hidden': b'h', 'z': b''}
    for k, v in files.items():
        f = p / k; f.parent.mkdir(parents=True, exist_ok=True); f.write_bytes(v)
    ref = kit_hash.content_sha256(str(p)); m = model(str(p))
    check('model equals kit_hash.py (nested, dotfile, empty file, uppercase/lowercase/non-ascii bytewise order)', m is not None and m[0] == ref and m[1] == kit_hash.package_size(str(p)))
    mf = pathlib.Path(d) / 'kit_manifest.json'; mf.write_text(json.dumps({'packages': {p.name: {'content_sha256': ref, 'size_bytes': m[1]}}}))
    check('reference --verify passes on the fixture kit dir', kit_hash.verify(d))
    (p / 'z').write_bytes(b'x'); check('a changed byte fails the hash and the size', model(str(p))[0] != ref and not kit_hash.verify(d))
    (p / 'z').write_bytes(b''); os.symlink('/etc/hostname', p / 'link')
    check('symlink: model returns nil', model(str(p)) is None)
    try: kit_hash.content_sha256(str(p)); raised = False
    except ValueError: raised = True
    check('reference raises on a symlink (Swift files() returns nil)', raised)
check('Swift: bytewise sort of UTF-8, NUL framing, symlink nil, dotfiles included (options: [])', 'lexicographicallyPrecedes' in sw and 'Array($0.rel.utf8)' in sw and 'h.update(Data([0]))' in sw and 'isSymbolicLink == true { return reject(' in sw and 'options: []' in sw)
check('Swift: checks content_sha256 AND size_bytes per package named by the manifests', 'got.sha == want, got.size == size' in sw and '"content_sha256"' in sw and '"size_bytes"' in sw)
check('CryptoKit streaming 1 MiB reads', 'import CryptoKit' in sw and '1 << 20' in sw)
check('script keeps a per-archive manifest copy; Swift reads kit_manifest.<id>.json first', 'kit_manifest.$1.json' in sh and 'hasPrefix("kit_manifest.")' in sw)
check('registration waits for verification (async, utility), marks .verified-<manifest sha16>, reports failures by name once', 'KitHash.verify(kitDir: kd)' in kit and '.verified-' in kit and 'failed verification' in kit and 'qos: .utility' in kit and kit.index('KitHash.verify') < kit.index('ThreeDRunnerRegistry.runner = r'))
check('registration emits runtime proof after verified runner assignment', '3d-depth-runtime registered runner=NativePrepareRunner' in kit and kit.index('3d-depth-runtime registered') > kit.index('ThreeDRunnerRegistry.runner = r'))
check('enumeration uses canonical root after root symlink check', 'fm.enumerator(at: canonical,' in sw and sw.index('root.isSymbolicLink != true') < sw.index('let canonical = package.resolvingSymlinksInPath()'))
swiftc = os.environ.get('SWIFTC') or shutil.which('swiftc')
if swiftc:
    with tempfile.TemporaryDirectory() as d:
        folder = pathlib.Path(d)
        package = folder / 'models with spaces' / 'kit' / 'test.mlpackage'
        for rel, data in {'Manifest.json':b'{}', 'Data/weights/weight.bin':b'fixture', '.hidden':b'h', 'z':b''}.items():
            path=package/rel; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(data)
        digest, size = kit_hash.content_sha256(str(package)), kit_hash.package_size(str(package))
        sha=(lambda _b: _b[_b.index('// BEGIN relocated '+'PrepareSupport.swift'+' '):_b.index('// END relocated '+'PrepareSupport.swift'+'\n')])((_threed_split().path(root)).read_text()).split('enum PrepareSupport {',1)[0]
        (folder/'Hash.swift').write_text(sha)
        main=r'''import Foundation
let package=URL(fileURLWithPath:CommandLine.arguments[1])
let want=CommandLine.arguments[2], size=Int(CommandLine.arguments[3])!
let fm=FileManager.default
let got=KitHash.contentSha256(package:package)!
precondition(got.sha == want && got.size == size)
for path in [package.path + "/",package.path.replacingOccurrences(of:"/kit/",with:"/kit/./"),package.path.replacingOccurrences(of:"/kit/",with:"//kit//")] {
    precondition(KitHash.contentSha256(package:URL(fileURLWithPath:path))?.sha == want)
}
let alias=package.deletingLastPathComponent().appendingPathComponent("alias.mlpackage")
try! fm.createSymbolicLink(at:alias,withDestinationURL:package)
precondition(KitHash.contentSha256(package:alias) == nil)
let ancestor=package.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("alias-kit")
try! fm.createSymbolicLink(at:ancestor,withDestinationURL:package.deletingLastPathComponent())
precondition(KitHash.contentSha256(package:ancestor.appendingPathComponent(package.lastPathComponent))?.sha == want)
// The canonical root and enumerated children must use the same URL basis.
let canonical=ancestor.appendingPathComponent(package.lastPathComponent).resolvingSymlinksInPath().standardizedFileURL
precondition(canonical.path == package.resolvingSymlinksInPath().standardizedFileURL.path)
precondition(KitHash.contentSha256(package:canonical)?.sha == want)
let missing=package.appendingPathComponent("missing.mlpackage")
precondition(KitHash.contentSha256(package:missing) == nil)
let unreadable=package.appendingPathComponent("unreadable")
try! Data("private".utf8).write(to:unreadable)
try! fm.setAttributes([.posixPermissions:0],ofItemAtPath:unreadable.path)
precondition(KitHash.contentSha256(package:package) == nil)
try! fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:unreadable.path)
try! fm.removeItem(at:unreadable)
try! fm.createSymbolicLink(at:package.appendingPathComponent("escape"),withDestinationURL:URL(fileURLWithPath:"/etc/hostname"))
precondition(KitHash.contentSha256(package:package) == nil)
print("PASS compiled production KitHash canonical bytes, spaces, dot/double-slash paths, ancestor symlink; rejects root/child symlink, missing root and unreadable file")
'''
        (folder/'main.swift').write_text(main)
        subprocess.run([swiftc,str(_sec_file(root,'KitHash.swift')),str(folder/'Hash.swift'),str(folder/'main.swift'),'-o',str(folder/'run')],check=True)
        result=subprocess.run([str(folder/'run'),str(package),digest,str(size)],text=True,capture_output=True,check=True)
        print(result.stdout,end='')
        check('failure diagnostic excludes owner path', str(folder) not in result.stdout)
else:
    print('NOT_RUN compiled KitHash: swiftc unavailable')
sys.exit(1 if bad else 0)
