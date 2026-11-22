"""Generated inventory, A2 checks and count-ratcheted architecture debt.

The compiler enforces product boundaries. This supplementary gate reports legacy
violations honestly; report mode preserves the architecture assessment exit status.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import argparse
import fnmatch
import csv
import hashlib
import os
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'architecture/manifest.tsv'
BASELINE = 'architecture/arch-baseline.tsv'
DELIVERY = 'architecture/delivery.tsv'
POLICY = 'architecture/policy.tsv'
HEADER = ['path', 'kind', 'current target', 'lines']
INTERNAL = ['path', 'kind', 'current target', 'planned target', 'responsibility', 'lines', 'flags']
ALLOWED = {
    'GorCore': set(), 'GorPlaybackModel': {'GorCore'},
    **{n: {'GorCore', 'GorPlaybackModel'} for n in ['GorSubtitles', 'GorStereo', 'GorFit', 'GorSources', 'GorEffectsModel', 'GorCaptureModel']},
    'GorSubtitlesUI': {'GorSubtitles', 'GorCore'}, 'GorStereoUI': {'GorStereo', 'GorCore'},
    'GorPlatformMac': {'GorCore', 'GorPlaybackModel'},
    'GorMPVBackend': {'GorCore', 'GorPlaybackModel'},
    'GorAVBackend': {'GorCore', 'GorPlaybackModel', 'GorAV'},
}
ALLOWED['GorUI'] = set(ALLOWED) - {'GorPlatformMac', 'GorMPVBackend', 'GorAVBackend'}
# GorAVEmbeddedShell: deliberate native87 embed architecture (architect verdict
# 2026-11-15); the facade re-route is a separate refactor, not gate noise.
ALLOWED['gor'] = set(ALLOWED) | {'GorUI', 'GorAVEmbeddedShell'}
ARCHIVED = {'work', 'deliveries', 'harness', 'harness-recovery', 'history', 'candidates', 'custody', 'test-kits', 'test-logs', 'evidence', 'research', 'studies', 'zips', 'intel-port', 'subtitle-bugs-handoff', 'src', 'var', 'wt'}
MPV = re.compile(r'\b(?:MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf', re.I)

# arch-199bv Engine station: nine files moved byte-identical from their backend
# folders. This CLOSED map preserves each moved file's immediately prior source
# path for path-sensitive rule evaluation only. It grants no new import or
# token authority: ALLOWED tables, current-target derivation and all import
# checks keep evaluating the actual current path/target. An Engine file absent
# from this map inherits NO backend exemption.
ENGINE_LEGACY_PATHS = {
    'Sources/gor/Engine/MPVCommand.swift': 'Sources/gor/GorMPVBackend/MPVCommand.swift',
    'Sources/gor/Engine/GorAVAppGate.swift': 'Sources/gor/GorAVBackend/GorAVAppGate.swift',
    'Sources/gor/Engine/GorAVHostMotion.swift': 'Sources/gor/GorAVBackend/GorAVHostMotion.swift',
    'Sources/gor/Engine/GorAVHostWindow.swift': 'Sources/gor/GorAVBackend/GorAVHostWindow.swift',
    'Sources/gor/Engine/GorAVLocalOffer.swift': 'Sources/gor/GorAVBackend/GorAVLocalOffer.swift',
    'Sources/gor/Engine/GorAVNativeGate.swift': 'Sources/gor/GorAVBackend/GorAVNativeGate.swift',
    'Sources/gor/Engine/GorAVPlayerHost.swift': 'Sources/gor/GorAVBackend/GorAVPlayerHost.swift',
    'Sources/gor/Engine/GorAVPostOpenFallback.swift': 'Sources/gor/GorAVBackend/GorAVPostOpenFallback.swift',
    'Sources/gor/Engine/GorAVStreamAdmission.swift': 'Sources/gor/GorAVBackend/GorAVStreamAdmission.swift',
}
SCRIPT = {'.sh', '.py'}


DEPLOY_ROOTS = {'Sources', 'Packages', 'Tests', 'Resources', 'scripts', 'tools',
                'architecture', 'docs', 'plan', 'selftest-fixtures'}
DEPLOY_FILES = {'models/models.lock.tsv', 'Package.swift', 'build.sh', 'gor-selftest.sh', 'gor-capture-channel.py',
                'ARCHITECTURE.md', 'VENDOR.md', 'ffmpeg-provider.lock', '.swift-format'}


def deployed(path):
    return path in DEPLOY_FILES or Path(path).parts[0] in DEPLOY_ROOTS


def installed_overlay(root):
    result = subprocess.run(['git', '-C', str(root), 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    return result.returncode != 0


def tracked(root):
    result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '.'], capture_output=True)
    if result.returncode == 0:
        names = result.stdout.decode().split('\0')
        return sorted({n for n in names if n and ((root / n).is_file() or (root / n).is_symlink()) and '__pycache__' not in n and not n.endswith('.pyc')})
    # Installed overlay: declared revision is authoritative; local models and
    # private logs are not silently added to the delivery manifest.
    with (root / MANIFEST).open() as handle:
        return [row['path'] for row in csv.DictReader(handle, delimiter='\t') if deployed(row['path']) and ((root / row['path']).is_file() or (root / row['path']).is_symlink())]


def kind(path):
    p = Path(path)
    if p.parts[0] in ARCHIVED or p.parts[0] in {'docs', 'design', 'engine', 'plan', 'manifests'}:
        return 'generated'
    if 'vendor' in p.parts or p.parts[0] == 'whisper-cpp-src':
        return 'vendor'
    if path == 'build.sh':
        return 'updater'
    if p.parts[0] in {'tools', 'scripts'} or path == 'gor-capture-channel.py':
        return 'gate' if ('arch' in path or 'model-tests' in path) else 'build-tool'
    if p.parts[0] == 'Tests':
        return 'dev-tool'
    if p.suffix == '.swift':
        return 'swift'
    if p.suffix in SCRIPT:
        return 'script'
    if p.parts[0] in {'Resources', 'selftest-fixtures', 'fixtures'}:
        return 'runtime-asset'
    return 'generated'


def destination(path):
    name = Path(path).stem
    if name in {'PlayerProtocol', 'MPVCommand'}:
        return ('GorPlaybackModel' if name == 'PlayerProtocol' else 'GorMPVBackend', 'M2' if name == 'PlayerProtocol' else 'M5')
    if '/Stereo/' in path:
        return 'GorStereo', 'M3'
    if name in {'GorFit', 'SourcePixelCrop'}:
        return 'GorFit', 'M3'
    if 'Subtitle' in name or name == 'LiveCaptionController':
        return ('GorSubtitlesUI' if name == 'SubtitleView' else 'GorSubtitles', 'M4')
    if name in {'IPTV', 'CDPSession', 'ArchiveLibrary', 'ArchiveRandom', 'MagnetBrowser', 'MegaStreamManager', 'MusicController', 'TorrentManager', 'TransferResolver'}:
        return 'GorSources', 'M7'
    if name == 'AdaptiveColor':
        return 'GorEffectsModel', 'M7'
    if name in {'ScreenCaptureEngine', 'Diag', 'MenuActions', 'GORResources', 'PanelFocus', 'PanelFocusTraversal', 'QuitChildKiller'}:
        return 'GorPlatformMac', 'M6'
    return ('gor' if name in {'main', 'BuildID', 'AppDelegate'} else 'GorUI'), 'M6'


class TargetGraph(dict):
    """Display target paths plus package-scoped compiler membership, never privileges by directory."""
    def __init__(self):
        super().__init__()
        self.members = []
        self.complete = True

    def owners(self, path):
        result = []
        if Path(path).suffix != '.swift':
            return result
        for target in self.members:
            prefix = target['path']
            if not path.startswith(prefix + '/'):
                continue
            relative = path[len(prefix) + 1:]
            def inside(item):
                return relative == item or relative.startswith(item.rstrip('/') + '/')
            if any(inside(item) for item in target['exclude'] + target['resources']):
                continue
            if target['sources'] is not None and not any(inside(item) for item in target['sources']):
                continue
            result.append(target)
        return result


def graph(root):
    root = root.resolve()
    targets, errors = TargetGraph(), []
    # Follow only declared in-tree local packages. Unrelated manifests cannot
    # lend their target identities or dependencies to a source file.
    pending, packages = [root / 'Package.swift'], {}
    while pending:
        package = pending.pop(0).resolve()
        if package in packages:
            continue
        try:
            package.relative_to(root)
        except ValueError:
            errors.append('local package outside scan root: ' + str(package))
            targets.complete = False
            continue
        if not package.is_file():
            errors.append('declared local Package.swift missing: ' + str(package.relative_to(root)))
            targets.complete = False
            continue
        try:
            proc = subprocess.run([os.environ.get('ARCH_SWIFT', 'swift'), 'package', '--package-path', str(package.parent), 'dump-package'], capture_output=True, text=True)
        except OSError as error:
            errors.append('swift unavailable: ' + type(error).__name__ + '; compiler graph NOT_RUN')
            targets.complete = False
            continue
        if proc.returncode:
            errors.append('Package.swift graph unavailable: ' + str(package.relative_to(root)))
            targets.complete = False
            continue
        try:
            data = json.loads(proc.stdout)
        except (ValueError, TypeError):
            errors.append('Package.swift graph invalid JSON: ' + str(package.relative_to(root)))
            targets.complete = False
            continue
        if not isinstance(data, dict) or not isinstance(data.get('targets'), list) or not isinstance(data.get('dependencies', []), list):
            errors.append('Package.swift graph malformed metadata: ' + str(package.relative_to(root)))
            targets.complete = False
            continue
        valid = True
        for target in data['targets']:
            if not isinstance(target, dict) or not isinstance(target.get('name'), str) or not isinstance(target.get('type'), str):
                valid = False; break
            if target.get('path') is not None and not isinstance(target['path'], str):
                valid = False; break
            for field in ['sources', 'exclude']:
                value = target.get(field)
                if value is not None and (not isinstance(value, list) or not all(isinstance(item, str) and not Path(item).is_absolute() and '..' not in Path(item).parts for item in value)):
                    valid = False
            if not isinstance(target.get('dependencies', []), list) or not isinstance(target.get('resources', []), list):
                valid = False
                continue
            for dep in target.get('dependencies', []):
                if not isinstance(dep, dict) or not dep or any(key not in {'target', 'byName', 'product'} or not isinstance(value, list) or not value or not isinstance(value[0], str) for key, value in dep.items()):
                    valid = False
            for resource in target.get('resources', []):
                if not isinstance(resource, dict) or not isinstance(resource.get('path'), str):
                    valid = False
        if not valid:
            errors.append('Package.swift graph malformed target metadata: ' + str(package.relative_to(root)))
            targets.complete = False
            continue
        if not all(isinstance(dep, dict) and isinstance(dep.get('fileSystem', []), list) and all(isinstance(local, dict) and isinstance(local.get('path'), str) for local in dep.get('fileSystem', [])) for dep in data.get('dependencies', [])):
            errors.append('Package.swift graph malformed package dependencies: ' + str(package.relative_to(root)))
            targets.complete = False
            continue
        packages[package] = data
        for dep in data.get('dependencies', []):
            for local in dep.get('fileSystem', []):
                pending.append(Path(local['path']) / 'Package.swift')
    for package, data in packages.items():
        local_names = {target['name'] for target in data['targets']}
        package_id = package.parent.relative_to(root).as_posix()
        for target in data['targets']:
            name = target['name']
            prefix = package.parent / (target.get('path') or (('Tests/' if target['type'] == 'test' else 'Sources/') + name))
            try:
                prefix = prefix.resolve().relative_to(root).as_posix()
            except ValueError:
                errors.append('target path outside scan root: ' + package_id + ':' + name)
                targets.complete = False
                continue
            key = name if name not in targets else package_id + ':' + name
            targets[key] = prefix
            deps = {value[0] for d in target.get('dependencies', []) for kind, value in d.items() if kind in {'target', 'byName', 'product'}}
            resources = [resource['path'] for resource in target.get('resources', [])]
            member = dict(key=key, name=name, module=re.sub(r'[^A-Za-z0-9_]', '_', name), package=package_id, path=prefix,
                          sources=target.get('sources'), exclude=target.get('exclude', []), resources=resources,
                          dependencies=deps, local_names=local_names, type=target['type'])
            targets.members.append(member)
            if package_id != 'Packages/gorav':
                # Keep the established production host policy. Test membership
                # is recorded, but test dependencies were never production edges.
                if target['type'] != 'test':
                    for dependency in deps - ALLOWED.get(name, set()):
                        errors.append(name + ' forbidden dependency: ' + dependency)
            else:
                # An internal import needs an actual same-package target and a
                # direct declaration, not a union of every module in the package.
                for dependency in deps - local_names:
                    errors.append(package_id + ':' + name + ' unresolved nonlocal dependency: ' + dependency)
    return targets, errors

def policy_rows(root):
    if not (root / POLICY).exists():
        return []
    with (root / POLICY).open() as handle:
        return list(csv.DictReader(handle, delimiter='\t'))


def reviewed(path, policy):
    exact = next((p for p in policy if p['path'] == path), None)
    if exact:
        return exact
    # Archive wildcards cannot approve new executable/product material.
    if Path(path).suffix.lower() in {'.swift', '.sh', '.py', '.lua', '.js', '.mjs', '.metal', '.c', '.h', '.png', '.jpg', '.jpeg', '.webp', '.ttf', '.otf', '.wav', '.mp4', '.metallib'}:
        return None
    matches = [p for p in policy if fnmatch.fnmatchcase(path, p['path'])]
    return max(matches, key=lambda p: len(p['path'])) if matches else None


def policy_assignment(policy, names):
    exact = {row['path']: row for row in policy if not any(c in row['path'] for c in '*?[')}
    bulk = sorted((row for row in policy if row['path'] not in exact), key=lambda row: len(row['path']), reverse=True)
    return {name: exact.get(name) or reviewed(name, bulk) for name in names}


def bulk_measure(root, entry, policy, names, assignment=None):
    # Count/hash only files classified by this exact bulk row. Explicit reviewed
    # file rows supersede it, so adding a real review can remove a bulk member.
    if assignment is None:
        assignment = policy_assignment(policy, names)
    selected = [name for name in names if assignment.get(name) is entry]
    digest = hashlib.sha256()
    # Canonical UTF-8 JSON-lines [path,kind,lowercase-sha256,exec-flag].
    # Paths sorted bytewise (UTF-8); JSON escapes tabs/newlines unambiguously.
    # Regular bytes hashed raw; symlinks hash os.readlink bytes, never targets.
    # No dirs/FIFO/socket entries. Empty listing hashes SHA256(empty).
    for name in sorted(selected, key=lambda value: value.encode('utf-8')):
        path = root / name
        link = path.is_symlink()
        content = os.fsencode(os.readlink(path)) if link else path.read_bytes()
        record = [name, 'symlink' if link else 'file', hashlib.sha256(content).hexdigest(),
                  '-' if link else ('x' if path.stat().st_mode & 0o111 else '-')]
        digest.update((json.dumps(record, ensure_ascii=True, separators=(',', ':')) + '\n').encode('utf-8'))
    return str(len(selected)), digest.hexdigest()


def bulk_errors(root, policy, names):
    errors = []
    product = ('Sources/', 'Packages/', 'Resources/', 'Tests/', 'scripts/')
    assignment = policy_assignment(policy, names)
    for entry in policy:
        if not any(char in entry['path'] for char in '*?['):
            continue
        prefix = entry['path'].split('*')[0]
        if prefix.startswith(product) or prefix.startswith(('build.sh', 'gor-')):
            errors.append('product root forbids bulk policy: ' + entry['path'])
        count, digest = bulk_measure(root, entry, policy, names, assignment)
        if entry.get('bulk_file_count') != count or entry.get('bulk_tree_sha256') != digest:
            errors.append('bulk classification changed: ' + entry['path'] + ' count=' + count + ' sha256=' + digest)
    return errors


def inventory(root, targets):
    rows = []
    policy = policy_rows(root)
    names = tracked(root)
    assignment = policy_assignment(policy, names)
    for path in names:
        p = root / path
        entry = assignment.get(path)
        k = (entry['vendor class'] if entry and entry['vendor class'] else kind(path))
        owners = targets.owners(path) if isinstance(targets, TargetGraph) else []
        current = owners[0]['key'] if len(owners) == 1 else '-' 
        planned = entry['planned target'] if entry else '-'
        responsibility = entry['responsibility'] if entry else 'UNREVIEWED'
        flags = ('allowed-small: ' + entry['allowed-small reason'] if entry and entry['allowed-small reason'] else '')
        if entry and entry['baseline id']:
            flags += '; baseline: ' + entry['baseline id']
        lines = len(p.read_bytes().splitlines())
        if path in {MANIFEST, BASELINE, DELIVERY, POLICY}:
            lines = 0
        rows.append([path, k, current, planned, responsibility, str(lines), flags])
    return rows


def violations(root, rows, targets=None):
    if targets is None:
        targets, _ = graph(root)
    found = Counter()
    for path, k, current, planned, responsibility, length, flags in rows:
        if k in {'vendor', 'generated'}:
            continue
        p = root / path
        text = p.read_text(errors='replace')
        # arch196g: file/line counts are inventory, never an acceptance gate.
        # Station ownership is tested independently from physical placement.
        if k != 'swift' or Path(path).name == 'Package.swift':
            continue
        imports = re.findall(r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|package)\s+)?import\s+(?:(?:class|struct|enum|protocol|func|let|var|typealias)\s+)?(\w+)', text, re.M)
        owners = targets.owners(path) if isinstance(targets, TargetGraph) else []
        owner = owners[0] if len(owners) == 1 else None
        if not targets.complete:
            found[path, 'membership:graph-not-run'] += 1
        if owner is None:
            found[path, 'membership:' + ('overlap' if owners else 'unassigned')] += 1
        gorav_member = targets.complete and owner is not None and owner['package'] == 'Packages/gorav'
        direct = owner['dependencies'] if owner else set()
        local = owner['local_names'] if owner else set()
        allowed_internal = direct & local if gorav_member else set()
        for imported in imports:
            if imported.startswith('Gor') and imported not in (allowed_internal if gorav_member else ALLOWED.get(current, set())):
                found[path, 'edge:' + imported] += 1
            if '/GorKit/' in '/' + path and imported in {'AppKit', 'Metal', 'CoreAudio', 'MetalKit'}:
                found[path, 'platform:' + imported] += 1
            if imported in {'CFFmpeg', 'GorAVCAtomics', 'GorAVAudioClock', 'GorAVDVRPU'} and imported not in allowed_internal:
                found[path, 'gorav-cmodule:' + imported] += 1
            if imported.startswith('GorAV') and not (imported in allowed_internal or (current == 'GorAVBackend' and imported == 'GorAV')):
                found[path, 'gorav-internal:' + imported] += 1
        legacy = ENGINE_LEGACY_PATHS.get(path, path)
        if current != 'GorMPVBackend' and not legacy.startswith('Sources/gor/GorMPVBackend/'):
            for line in text.splitlines():
                if not line.lstrip().startswith('//') and MPV.search(line):
                    found[path, 'mpv:' + hashlib.sha256(line.strip().encode()).hexdigest()[:16]] += 1
    return +found


def write_tsv(path, header, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', newline='') as handle:
        writer = csv.writer(handle, delimiter='\t', lineterminator='\n')
        writer.writerow(header)
        writer.writerows(rows)


def same_git_mode(path, declared):
    # Git trees preserve executable-vs-nonexecutable, not writable/group bits.
    # macOS checkout/umask/ACL tooling may legally produce0444/0664 for100644.
    return bool(path.stat().st_mode & 0o111) == bool(int(declared, 8) & 0o111)


def integrity(root):
    errors = []
    if not (root / DELIVERY).is_file():
        return ['release manifest missing']
    with (root / DELIVERY).open() as handle:
        for item in csv.DictReader(handle, delimiter='\t'):
            p = root / item['path']
            if not p.is_file():
                errors.append('delivery file missing: ' + item['path'])
                continue
            actual = hashlib.sha256(p.read_bytes()).hexdigest()
            if actual != item['sha256']:
                errors.append('delivery checksum mismatch: ' + item['path'] + ' expected=' + item['sha256'] + ' actual=' + actual)
            if not same_git_mode(p, item['mode']):
                errors.append('delivery executable-bit mismatch: ' + item['path'] + ' expected=' + item['mode'] + ' actual=' + oct(p.stat().st_mode & 0o777))
    return errors


def provider_errors(root):
    path = root / 'ffmpeg-provider.lock'
    if not path.exists():
        return []  # fixtures without a provider integration
    data = path.read_bytes()
    marker = b'gorav_lock_source: '
    if marker not in data:
        return ['FFmpeg provider source missing; pin bump/M2b prohibited']
    upstream, source = data.rsplit(marker, 1)
    match = re.fullmatch(rb'goreda/gorav@([0-9a-f]{40}):ffmpeg-provider.lock ([0-9a-f]{40})\n', source)
    if not match:
        return ['FFmpeg provider source malformed']
    blob = hashlib.sha1(b'blob ' + str(len(upstream)).encode() + b'\0' + upstream).hexdigest()
    errors = []
    if blob != match[2].decode():
        errors.append('FFmpeg upstream lock blob mismatch; pin bump/M2b prohibited')
    pins = []
    for package in [root / 'Package.swift', root / 'Packages/GorKit/Package.swift']:
        if not package.exists():
            continue
        # Match a complete declaration, including ordinary multiline manifests.
        for declaration in re.findall(r'\.package\s*\((.*?)\)', package.read_text(), re.S):
            if re.search(r'gorav', declaration, re.I):
                pin = re.search(r'revision:\s*"([0-9a-f]+)"', declaration)
                pathdep = re.search(r'path:\s*"([^"]+)"', declaration)
                if pin:
                    pins.append(('pin', pin[1]))
                elif pathdep:
                    # Vendored path dependency (architect verdict 2026-11-15,
                    # option A): the verified marker revision must equal the
                    # vendored revision recorded in <path>/source-lock.json.
                    pins.append(('path', pathdep[1]))
                else:
                    pins.append(('unpinned', None))
    if not pins:
        print('provider-pin: ABSENT (no gorav dependency declared); lock-bytes checked only; pin bump/M2b BLOCKED until exact pin is declared and verified')
    else:
        for kind, value in pins:
            if kind == 'pin':
                if value != match[1].decode():
                    errors.append('gorav dependency pin differs from verified provider lock revision')
            elif kind == 'path':
                lock = root / value / 'source-lock.json'
                if not lock.exists():
                    errors.append('gorav path dependency without source-lock.json; pin bump/M2b prohibited')
                    continue
                try:
                    vendored = json.loads(lock.read_text()).get('revision')
                except (ValueError, OSError):
                    vendored = None
                if vendored != match[1].decode():
                    errors.append('vendored gorav revision differs from verified provider lock revision')
            else:
                errors.append('gorav dependency declares neither revision pin nor vendored path; pin bump/M2b prohibited')
        print('provider-pin: ' + ('MISMATCH; pin bump/M2b BLOCKED' if errors else 'MATCH; exact declared revision equals lock source'))
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--emit', action='store_true')
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--report', action='store_true')
    parser.add_argument('--status-file', type=Path, help='machine-readable architecture assessment, not compiler/test success')
    parser.add_argument('--integrity-only', action='store_true')
    parser.add_argument('--seed-baseline', action='store_true', help='reviewed initial snapshot only; never run automatically in CI/update')
    args = parser.parse_args()
    root = args.root.resolve()
    def menu_preservation_errors():
        ledger=root/'Tests/MenuStructure/required-items.json'
        if not ledger.exists():return ['menu required-items ledger missing']
        data=json.loads(ledger.read_text());result=[]
        previous=subprocess.run(['git','show','HEAD:archive/gor/Tests/MenuStructure/required-items.json'],cwd=root,capture_output=True,text=True)
        if previous.returncode==0:
            prior=json.loads(previous.stdout)
            old_ids={o['message_id'] for o in prior.get('orders',[])}
            for removed in set(prior['required'])-set(data['required']):
                if not any(r.get('item')==removed and r.get('owner_order_id') not in old_ids and any(o.get('message_id')==r.get('owner_order_id') and removed in o.get('removed_items',[]) and o.get('verbatim') for o in data['orders']) for r in data.get('removals',[])):
                    result.append('required item deleted without new named owner order: '+removed)
        for item,(path,token) in data['required'].items():
            if not (root/path).exists() or token not in (root/path).read_text():result.append('required menu item missing: '+item)
        menu=(lambda _b: _b[_b.index('// BEGIN relocated ThreeDMenu.swift '):_b.index('// END relocated ThreeDMenu.swift\n')])((_threed_split().path(root)).read_text())
        if 'advanced: true' in menu:result.append('menu controls hidden without owner removal entry')
        if 'isHidden' in menu:
            allowed = any(o.get('message_id')=='phonemsg-01M70VCE8AZ8SH2K2ACMKKVPV1' and o.get('hidden_items')==['qualityBest','qualityFast'] and o.get('verbatim') for o in data['orders'])
            hidden = [line.strip() for line in menu.splitlines() if 'isHidden' in line]
            if not allowed or hidden != ['i.isHidden = ThreeDRunnerRegistry.runner == nil   // B4: unbuilt tiers are hidden, re-checked every menu open']:
                result.append('menu controls hidden outside191b unavailable-quality-only grant')
        return result
    if args.integrity_only:
        errors = integrity(root)+menu_preservation_errors()
        for error in errors:
            print('INTEGRITY ' + error)
        return 1 if errors else 0
    targets, errors = graph(root)
    errors += menu_preservation_errors()
    errors += provider_errors(root)
    rows = inventory(root, targets)
    previous = {}
    if (root / MANIFEST).exists():
        with (root / MANIFEST).open() as handle:
            previous = {r['path']: r for r in csv.DictReader(handle, delimiter='\t')}
    generated = [[r[0], r[1], r[2], r[5]] for r in rows]
    if args.emit:
        write_tsv(root / MANIFEST, HEADER, generated)
    policy = policy_rows(root)
    overlay = installed_overlay(root)
    if not overlay:
        errors += bulk_errors(root, policy, [row[0] for row in rows])
    else:
        previous = {path: value for path, value in previous.items() if deployed(path)}
        print('installed overlay: repository-only archive/bulk inventory NOT_APPLICABLE; release integrity remains checked')
    assignment = policy_assignment(policy, [row[0] for row in rows])
    for row in rows:
        if not assignment.get(row[0]):
            errors.append('unreviewed policy: ' + row[0])
    counts = violations(root, rows, targets)
    if args.seed_baseline:
        write_tsv(root / BASELINE, ['path', 'rule', 'count', 'queue id', 'removal condition'],
                  [[p, rule, n, ('M5' if rule.startswith('mpv:') else destination(p)[1]) if p.startswith('Sources/') else 'D2', 'queue item complete; remove debt row'] for (p, rule), n in sorted(counts.items())])
    baseline = {}
    if (root / BASELINE).exists():
        with (root / BASELINE).open() as handle:
            baseline = {(r['path'], r['rule']): r for r in csv.DictReader(handle, delimiter='\t')}
    queue = (root / 'plan/QUEUE.md').read_text() if (root / 'plan/QUEUE.md').exists() else ''
    for key, value in counts.items():
        old = baseline.get(key)
        closed = old and re.search(r'^##\s+' + re.escape(old['queue id']) + r'\s*\|\s*(DONE|COMPLETED|CANCELLED)\b', queue, re.M | re.I)
        if not old or value > int(old['count']) or closed:
            errors.append(str(key) + ': count ' + str(value) + ' exceeds active baseline')
    if not args.emit:
        expected = {r[0]: r for r in generated}
        if set(previous) != set(expected):
            errors.append('unmapped=' + str(len(set(previous) ^ set(expected))))
        for path in set(previous) & set(expected):
            if list(previous[path].values()) != expected[path]:
                errors.append('stale manifest: ' + path)
    if args.emit:
        delivery = []
        for path, k, *_ in rows:
            if not deployed(path) or path == DELIVERY or k == 'generated' and not path.startswith(('architecture/', 'docs/adr/')) and path not in {'ARCHITECTURE.md', '.swift-format', 'VENDOR.md', 'ffmpeg-provider.lock', 'Package.swift', 'Packages/.keep', 'Tests/Architecture/prior-installer.sh', 'models/models.lock.tsv'}:
                continue
            p = root / path
            delivery.append([path, hashlib.sha256(p.read_bytes()).hexdigest(), oct(p.stat().st_mode & 0o777)])
        write_tsv(root / DELIVERY, ['path', 'sha256', 'mode'], delivery)
    integrity_errors = integrity(root) if not args.emit else []
    if args.integrity_only:
        for error in integrity_errors:
            print('INTEGRITY ' + error)
        return 1 if integrity_errors else 0
    errors += integrity_errors
    edges = sum('dependency' in e or 'edge:' in e or 'internal:' in e for e in errors)
    print('arch-check: unmapped=' + str(len(set(previous) ^ {r[0] for r in rows})) + ' new-forbidden-edges=' + str(edges) + ' debt-current=' + str(sum(counts.values())) + '/baseline=' + str(sum(int(b['count']) for b in baseline.values())) + ' targets=' + str(len(targets)) + ' files=' + str(len(rows)))
    print('tests: declared-test-targets=' + str(sum(t['type'] == 'test' for t in targets.members)) + ' ran=0 skipped=not-run-by-architecture-gate; compiler/lifecycle coverage separate')
    for error in errors:
        print('FAIL ' + error)
    assessment = 'FAIL' if errors or counts else 'PASS'
    graph_status = 'PASS' if targets.complete else 'NOT_RUN'
    status = dict(schema=1, assessment=assessment, graph=graph_status, findings=len(errors),
                  current_debt=sum(counts.values()), violation_rows=len(counts), ratchet='FAIL' if errors else 'PASS', target_count=len(targets), file_count=len(rows),
                  tests='NOT_RUN', compiler='NOT_RUN', lifecycle='NOT_RUN')
    print('ARCHITECTURE assessment=' + assessment + ' graph=' + graph_status + ' findings=' + str(len(errors)) + '; compiler/lifecycle/product tests NOT_RUN by this scanner')
    if args.status_file:
        args.status_file.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.status_file.with_name(args.status_file.name + '.tmp')
        temporary.write_text(json.dumps(status, sort_keys=True) + '\n')
        os.replace(temporary, args.status_file)
    if counts:
        print('ARCHITECTURE unresolved-violation-rows=' + str(len(counts)) + ' occurrences=' + str(sum(counts.values())) + '; grandfathered ratchet counts are not a health PASS')
    if args.report:
        print('Architecture report preserves failure status; compilation, installation and lifecycle are separate outcomes')
    return 1 if errors or counts else 0


if __name__ == '__main__':
    sys.exit(main())
