#!/usr/bin/env python3
"""Stage a signature-verified CfT headless shell in the project vendor tree.

Invoked once per app run before first CDP launch. Requires --source-root, which
must point at the project containing build.sh and Resources/vendor/chromium.
Never modifies the running .app. A successful update takes effect on the next
build.sh, which must re-seal the complete app using MacDev. Any ambiguity fails
closed, keeping the old source and live binary.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

STABLE = 'https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json'
ROOT = 'https://storage.googleapis.com/chrome-for-testing-public/'
VERSION = re.compile(r'^\d+\.\d+\.\d+\.\d+$')
OUTPUT = re.compile(
    r'^(?:Google Chrome for Testing|Google Chrome|Chromium|HeadlessChrome|chrome-headless-shell)\s+'
    r'(\d+\.\d+\.\d+\.\d+)$', re.I
)
LIMIT = 500 * 1024 * 1024

def run(args, timeout=25):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=True)

def version_of(binary):
    try:
        result = run([str(binary), '--version'], timeout=12)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError(f'cannot read browser version from {binary}: {exc}') from exc
    lines = [line.strip() for stream in (result.stdout, result.stderr)
             for line in stream.splitlines() if line.strip()]
    matches = [OUTPUT.fullmatch(line) for line in lines]
    if len(matches) != 1 or matches[0] is None:
        raise RuntimeError(f'unparseable or ambiguous browser version from {binary}: {result.stdout.strip()!r} {result.stderr.strip()!r}')
    return matches[0].group(1)

def validate_official_adhoc_signature(binary):
    # The official CfT headless-shell ZIP has ad-hoc Mach-O CodeDirectory
    # signatures, not a Google Developer ID certificate chain. Verify the
    # exact signature mode observed in the official ZIP, for every Mach-O
    # executable and dylib. This is a local integrity check, not signer
    # authentication; source provenance relies on the exact HTTPS CfT URLs.
    for path in [binary] + sorted(binary.parent.rglob('*.dylib')):
        run(['/usr/bin/codesign', '--verify', '--strict', '--verbose=2', str(path)])
        info = run(['/usr/bin/codesign', '-dv', '--verbose=4', str(path)])
        combined = info.stdout + info.stderr
        if re.search(r'(?m)^Signature=adhoc\s*$', combined) is None:
            raise RuntimeError(f'expected official ad-hoc code signature: {path}')
        flags = re.search(r'(?m)^CodeDirectory v=\d+ .*?flags=0x([0-9a-fA-F]+)\(([^)]*)\)', combined)
        if flags is None or not (int(flags.group(1), 16) & 0x2) or 'adhoc' not in flags.group(2).split(','):
            raise RuntimeError(f'expected ad-hoc CodeDirectory flag: {path}')
        if re.search(r'(?m)^Authority=', combined):
            raise RuntimeError(f'unexpected certificate authority on headless shell: {path}')

def get_stable():
    with urllib.request.urlopen(urllib.request.Request(STABLE, headers={'User-Agent':'gor-chromium-updater/1'}), timeout=7) as response:
        if response.url != STABLE: raise RuntimeError('unexpected metadata redirect')
        return json.loads(response.read(3 * 1024 * 1024))['channels']['Stable']

def download(url, destination):
    n = 0
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'gor-chromium-updater/1'}), timeout=30) as response, open(destination, 'wb') as out:
        if response.url != url: raise RuntimeError('unexpected archive redirect')
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk: break
            n += len(chunk)
            if n > LIMIT: raise RuntimeError('archive exceeds size limit')
            out.write(chunk)

def unpack(archive, dest, platform_name):
    prefix = f'chrome-headless-shell-{platform_name}/'
    with zipfile.ZipFile(archive) as z:
        members = z.infolist()
        if sum(m.file_size for m in members) > 2 * 1024**3 or len(members) > 20000:
            raise RuntimeError('archive extraction limits exceeded')
        for m in members:
            mode = m.external_attr >> 16
            if not m.filename.startswith(prefix) or '..' in Path(m.filename).parts or (mode & 0o170000) == 0o120000:
                raise RuntimeError('unsafe archive member')
        z.extractall(dest)
    for m in members:
        path = dest / m.filename
        if path.is_file() and m.external_attr >> 16 & 0o111:
            path.chmod(path.stat().st_mode | ((m.external_attr >> 16) & 0o111))
    return dest / prefix

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--binary', required=True, help='actual bundled executable resolved by CDPSession')
    ap.add_argument('--source-root', required=True, help='project root, not running app')
    args = ap.parse_args()
    binary = Path(args.binary)
    if binary.name != 'chrome-headless-shell' or not binary.is_file():
        raise RuntimeError('bundled browser is not a discoverable chrome-headless-shell; no layout guess')
    current = version_of(binary)
    arch = platform.machine()
    if arch not in ('arm64', 'x86_64'): raise RuntimeError(f'unsupported architecture {arch}')
    target_platform = 'mac-arm64' if arch == 'arm64' else 'mac-x64'
    try: stable = get_stable()
    except Exception as exc:
        print(f'OFFLINE: using bundled {current}: {exc}')
        return
    latest = stable['version']
    if not VERSION.fullmatch(latest): raise RuntimeError('unparseable upstream Stable version')
    if tuple(map(int, latest.split('.'))) <= tuple(map(int, current.split('.'))):
        print(f'CURRENT: {current}')
        return
    assets = [x['url'] for x in stable['downloads']['chrome-headless-shell'] if x['platform'] == target_platform]
    expected = f'{ROOT}{latest}/{target_platform}/chrome-headless-shell-{target_platform}.zip'
    if assets != [expected]: raise RuntimeError('missing or unexpected Stable download URL')
    root = Path(args.source_root).resolve()
    vendor = root / 'Resources/vendor/chromium'
    if not (root / 'build.sh').is_file() or not vendor.is_dir() or vendor.is_symlink():
        raise RuntimeError('project source root not found; keeping bundled browser')
    # Bundle-relative executable path is authoritative; never infer source
    # layout from an empty vendor tree. Reject anything outside vendor/chromium.
    bundled_root = Path(args.binary).resolve().parents
    bundle_vendor = next((p for p in bundled_root if p.name == 'chromium' and
                          p.parent.name == 'vendor' and p.parent.parent.name == 'Resources'), None)
    if bundle_vendor is None: raise RuntimeError('binary outside bundled vendor/chromium')
    relative = binary.resolve().relative_to(bundle_vendor)
    if relative.name != 'chrome-headless-shell':
        raise RuntimeError(f'unsupported bundled executable {relative}')
    if relative.parent == Path('.'):
        raise RuntimeError('root-level browser layout requires atomic whole-vendor replacement; not supported')
    stage = root / '.build/chromium-update'
    stage.parent.mkdir(parents=True, exist_ok=True)
    if stage.exists():
        staged = stage / 'payload' / relative
        if not staged.is_file(): raise RuntimeError('incomplete existing stage; inspect before retry')
        staged_version = version_of(staged)
        if tuple(map(int, staged_version.split('.'))) >= tuple(map(int, latest.split('.'))):
            print(f'ALREADY_STAGED: {staged_version}')
            return
        raise RuntimeError('outdated stage exists; remove it manually before retry')
    with tempfile.TemporaryDirectory(prefix='.gor-chromium-', dir=stage.parent) as temp:
        work = Path(temp)
        archive = work / 'browser.zip'
        download(expected, archive)
        newtree = unpack(archive, work / 'extracted', target_platform)
        candidate = newtree / 'chrome-headless-shell'
        if version_of(candidate) != latest: raise RuntimeError('new browser smoke test failed')
        validate_official_adhoc_signature(candidate)
        prepared = work / 'prepared'
        destination = prepared / 'payload' / relative.parent
        destination.parent.mkdir(parents=True)
        newtree.rename(destination)
        (prepared / 'version.txt').write_text(latest + '\n')
        (prepared / 'binary-relative-path.txt').write_text(relative.as_posix() + '\n')
        prepared.rename(stage)
    print(f'STAGED: {latest} at {stage}; next signed build applies it; using bundled {current} now')

if __name__ == '__main__':
    try: main()
    except Exception as exc:
        print(f'CHROMIUM_UPDATE_ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
