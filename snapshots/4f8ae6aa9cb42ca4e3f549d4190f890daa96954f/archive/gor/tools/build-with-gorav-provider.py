#!/usr/bin/env python3
"""Build using the locked private FFmpeg provider, never system/Homebrew headers.
Invoked by the normal updater and by the native gate. No downloads or app install.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shlex
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
PROVIDER = ROOT / 'Packages/gorav-provider'
LIBRARIES = ['libavformat', 'libavcodec', 'libswscale', 'libswresample', 'libavutil']
# native87 A0: provider archives must target the app's macOS floor. Without an
# explicit pin the host default leaks in (minos 26.0 members on a macOS 26
# builder) and the archives cannot link into a 13.0 deployment target.
DEPLOYMENT_TARGET = '13.0'
# native88: kill the X11/XCB/xlib autodetect probes at configure level. On a
# Homebrew macOS builder they pick up 26.0/15.0 dylibs, leak -lX11 into
# EXTRALIBS-avutil, and trip the audit gate. These names are exactly the
# EXTERNAL_AUTODETECT_LIBRARY_LIST entries of the locked FFmpeg configure
# (xlib, libxcb, libxcb_shm, libxcb_shape, libxcb_xfixes).
DISABLE_AUTODETECT = ['--disable-xlib', '--disable-libxcb',
                      '--disable-libxcb-shm', '--disable-libxcb-shape',
                      '--disable-libxcb-xfixes']


# U1 (arch-196y): the provider of record is ffmpeg-7.1-full-codec per the engine
# ffmpeg-provider.lock (goreda/gorav@8786bfe3); the 8.0.1 cache is LEGACY, do
# not mix. Rollback stays intact: GORAV_PROVIDER=legacy-8.0.1 selects the old
# pinned inputs and reproduces the pre-U1 build exactly.
PROVIDERS = {
    '7.1-full-codec': ('ffmpeg-provider-source-lock-7.1.json',
                       'ffmpeg-7.1.tar.xz', 'ffmpeg-7.1-flags.txt'),
    'legacy-8.0.1': ('ffmpeg-provider-source-lock.json',
                     'ffmpeg-894da5ca-refetch.tar.xz', 'ffmpeg-flags.txt'),
}
PROVIDER_NAME = os.environ.get('GORAV_PROVIDER', '7.1-full-codec')
if PROVIDER_NAME not in PROVIDERS:
    raise RuntimeError('unknown GORAV_PROVIDER: ' + PROVIDER_NAME)


def output(args):
    return subprocess.check_output(args, text=True).strip()


def provision():
    lock_name, tar_name, flags_name = PROVIDERS[PROVIDER_NAME]
    lock = json.loads((PROVIDER / lock_name).read_text())
    tar = PROVIDER / tar_name
    flags = PROVIDER / flags_name
    for path, key in [(tar, 'tarball_sha256'), (flags, 'flags_sha256')]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != lock[key]:
            raise RuntimeError('locked private FFmpeg input mismatch: ' + path.name)
    source_id = lock.get('source_commit') or ('ffmpeg-' + lock['source_version'])
    identity = {'provider': PROVIDER_NAME,
                'source': source_id, 'tar': lock['tarball_sha256'],
                'flags': lock['flags_sha256'], 'arch': platform.machine(),
                'system': platform.system(), 'clang': output(['clang', '--version']),
                'swift': output(['swift', '--version'])}
    if platform.system() == 'Darwin':
        identity.update(sdk=output(['xcrun', '--show-sdk-version']),
                        sdk_path=output(['xcrun', '--show-sdk-path']),
                        deployment_target=DEPLOYMENT_TARGET,
                        disable_autodetect=DISABLE_AUTODETECT)
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()[:24]
    # Build artifacts are deliberately outside delivered Packages and rollback snapshots.
    cache = ROOT / '.build/gorav-provider' / key
    cache.mkdir(parents=True, exist_ok=True)
    with (cache / 'build.lock').open('a') as mutex:
        fcntl.flock(mutex, fcntl.LOCK_EX)
        with tarfile.open(tar) as archive:
            members = archive.getmembers()
            for member in members:
                name = PurePosixPath(member.name)
                if name.is_absolute() or '..' in name.parts:
                    raise RuntimeError('unsafe provider tar path')
                if member.issym() or member.islnk():
                    link = PurePosixPath(member.linkname)
                    if link.is_absolute() or '..' in link.parts:
                        raise RuntimeError('unsafe provider tar link')
            tops = {PurePosixPath(m.name).parts[0] for m in members if PurePosixPath(m.name).parts}
            if len(tops) != 1:
                raise RuntimeError('provider tar must have one top-level directory')
            source = cache / tops.pop()
            if not source.exists():
                archive.extractall(cache)
        configure = shlex.split(next(line for line in flags.read_text().splitlines()
                                     if line.startswith('./configure ')))
        configure = [arg.replace('--cc=gcc', '--cc=clang') for arg in configure]
        env = os.environ.copy()
        if platform.system() == 'Darwin':
            env['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
            configure += ['--extra-cflags=-mmacosx-version-min=' + DEPLOYMENT_TARGET,
                          '--extra-ldflags=-mmacosx-version-min=' + DEPLOYMENT_TARGET]
            configure += DISABLE_AUTODETECT
        if not (source / 'ffbuild/config.mak').exists():
            print('gorav private FFmpeg: configure pinned source', flush=True)
            subprocess.run(configure, cwd=source, check=True, env=env)
        print('gorav private FFmpeg: build/cache check', flush=True)
        subprocess.run(['make', '-j2'], cwd=source, check=True, env=env)
        assert (source / 'libavformat/avformat.h').is_file()
        assert all((source / name / (name + '.a')).is_file() for name in LIBRARIES)
        (cache / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
        (cache / 'ready.json').write_text(json.dumps({name: hashlib.sha256(
            (source / name / (name + '.a')).read_bytes()).hexdigest() for name in LIBRARIES}, indent=2) + '\n')
    return source


def main():
    source = provision()
    args = ['-Xcc', '-I' + str(source)]
    for name in LIBRARIES:
        args += ['-Xlinker', '-L' + str(source / name)]
    print('gorav private FFmpeg: headers+libraries verified; invoking Swift build', flush=True)
    # build.sh retains its original scratch/product/log/failure behavior.
    return subprocess.run(['swift', 'build'] + sys.argv[1:] + args).returncode


if __name__ == '__main__':
    raise SystemExit(main())
