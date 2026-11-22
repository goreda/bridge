#!/usr/bin/env python3
"""Delivered-source identity bound to installed bytes.

verified is derived only from git objects and the installed files: the
delivered commit's archive/gor tree is listed from the object database and
every listed file must be byte-identical (git blob id) in the installed
project. No local flag and no comparison of two mutable refs can produce it.
Anything unknown is a typed refusal, never a guessed value.
"""
import hashlib, json, re, subprocess, sys
from pathlib import Path

OPS = ('Sources', 'Package.swift', 'build.sh', 'gor-capture-channel.py', 'Tests', 'Resources', 'Packages',
       'scripts', 'tools', 'architecture', 'docs', 'ARCHITECTURE.md', 'VENDOR.md', 'ffmpeg-provider.lock',
       '.swift-format', 'plan', 'models')
VERIFIED = 'delivered-tree-installed-bytes'
RECORD = '.gor-delivery.json'
HEX40 = re.compile(r'[0-9a-f]{40}')
HEX64 = re.compile(r'[0-9a-f]{64}')


class Refusal(Exception):
    pass


def git(repo, *args, data=None):
    try:
        return subprocess.run(['git', '-C', str(repo), *args], input=data, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=60, check=True).stdout
    except (OSError, subprocess.SubprocessError) as error:
        raise Refusal('git ' + ' '.join(args[:2]) + ' failed') from error


def blob_id(data):
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


def commit_tree(repo, commit):
    if not HEX40.fullmatch(commit or ''):
        raise Refusal('commit is not a 40-hex object id')
    if git(repo, 'cat-file', '-t', commit).strip() != b'commit':
        raise Refusal('commit object missing')
    tree = git(repo, 'rev-parse', commit + ':archive/gor').decode().strip()
    if not HEX40.fullmatch(tree):
        raise Refusal('archive/gor tree unresolved')
    return tree


def tree_files(repo, commit):
    rows = git(repo, 'ls-tree', '-r', '-z', commit + ':archive/gor').split(b'\0')
    files = {}
    for row in rows:
        if not row:
            continue
        meta, path = row.split(b'\t', 1)
        mode, kind, blob = meta.decode().split()
        path = path.decode()
        if kind == 'blob' and path.split('/')[0] in OPS and mode in ('100644', '100755'):
            files[path] = blob
    if not files:
        raise Refusal('delivered tree lists no installable files')
    return files


# Local assets that may exist in the installed project without being delivered. Explicit and closed:
# only paths that are NOT compiled inputs belong here (models, vendored binaries). Arbitrary extra
# Swift or Packages files are never allowed, because they would be compiled into the build.
LOCAL_ASSET_PREFIXES = ('Resources/vendor/', 'models/')


def is_compiled_input(path):
    parts = path.split('/')
    if parts[-1] == '.DS_Store':
        return False
    if path in ('Package.swift', 'build.sh'):
        return True
    if path.startswith('Sources/gor/') and path.endswith('.swift'):
        return True
    return path.startswith('Packages/') and '.build' not in parts


def compiled_inputs(project):
    """Exactly the files build.sh feeds the Swift build (same enumeration as the source snapshot)."""
    root = Path(project)
    paths = [root / 'Package.swift', root / 'build.sh'] + sorted((root / 'Sources/gor').rglob('*.swift')) \
        + sorted(p for p in (root / 'Packages').rglob('*') if p.is_file() and '.build' not in p.parts and p.name != '.DS_Store')
    out = {}
    for path in paths:
        if path.is_symlink() or not path.is_file():
            raise Refusal('non-regular build input: ' + path.relative_to(root).as_posix())
        out[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    if len(out) < 3:
        raise Refusal('no Swift sources found')
    return out


def snapshot_text(project):
    return json.dumps(compiled_inputs(project), indent=2, sort_keys=True) + '\n'


def snapshot_sha256(text):
    return hashlib.sha256(text.encode() if isinstance(text, str) else text).hexdigest()


def blob_bytes(repo, ids):
    ids = sorted(set(ids))
    data = git(repo, 'cat-file', '--batch', data=''.join(i + '\n' for i in ids).encode())
    out, offset = {}, 0
    for i in ids:
        stop = data.index(b'\n', offset)
        header = data[offset:stop].split()
        if len(header) != 3 or header[1] != b'blob':
            raise Refusal('delivered blob unreadable: ' + i)
        size = int(header[2])
        out[i] = data[stop + 1:stop + 1 + size]
        offset = stop + size + 2
    return out


def bind_snapshot(repo, files, records):
    """The snapshot (build-id source) must be exactly the delivered tree's compiled inputs, by content."""
    expected = {p: b for p, b in files.items() if is_compiled_input(p)}
    if set(records) != set(expected):
        extra = sorted(set(records) - set(expected))[:3]
        missing = sorted(set(expected) - set(records))[:3]
        raise Refusal('snapshot input set differs from delivered tree (extra %s missing %s)' % (extra, missing))
    blobs = blob_bytes(repo, expected.values())
    for path, blob in expected.items():
        if hashlib.sha256(blobs[blob]).hexdigest() != records[path]:
            raise Refusal('snapshot entry differs from delivered blob: ' + path)


def manifest_sha256(files):
    return hashlib.sha256(''.join(p + '\t' + files[p] + '\n' for p in sorted(files)).encode()).hexdigest()


def verify_installed(repo, commit, project, snapshot_records=None):
    """Return (tree, tree_manifest_sha256, count, snapshot_sha256). Raises Refusal on any mismatch."""
    tree = commit_tree(repo, commit)
    files = tree_files(repo, commit)
    bad = []
    modes = tree_modes(repo, commit)
    for path, blob in files.items():
        target = Path(project) / path
        try:
            if target.is_symlink() or not target.is_file() or blob_id(target.read_bytes()) != blob \
                    or bool(target.stat().st_mode & 0o100) != (modes[path] == '100755'):
                bad.append(path)
        except OSError:
            bad.append(path)
    if bad:
        raise Refusal('installed bytes differ from delivered tree in %d file(s): %s' % (len(bad), ', '.join(sorted(bad)[:5])))
    # Closed compiled-input set: no installed build input may exist outside the delivered tree.
    installed = compiled_inputs(project)
    extra = sorted(p for p in installed if p not in files and not p.startswith(LOCAL_ASSET_PREFIXES))
    if extra:
        raise Refusal('installed build inputs not in the delivered tree (%d): %s' % (len(extra), ', '.join(extra[:5])))
    records = snapshot_records if snapshot_records is not None else installed
    bind_snapshot(repo, files, records)
    snap = snapshot_sha256(json.dumps(records, indent=2, sort_keys=True) + '\n')
    return tree, manifest_sha256(files), len(files), snap


def tree_modes(repo, commit):
    modes = {}
    for row in git(repo, 'ls-tree', '-r', '-z', commit + ':archive/gor').split(b'\0'):
        if row:
            meta, path = row.split(b'\t', 1)
            modes[path.decode()] = meta.decode().split()[0]
    return modes



# Explicit historical removals, never an absent-overlay deletion rule.
# Exact already-qualified owner-route AppDelegate preimage, in addition to the
# historical purestation preimage below. No other bytes gain adoption.
UPDATE_RETIREMENT_ALTERNATES = {
    'Sources/gor/AppDelegate.swift': {'72baa39bf94db09b27bd819ed0d2916a6538ce69fbf3485c1d4347121d298fe2'},
}

UPDATE_RETIREMENTS = {
    'Sources/gor/main.swift': ('2c2f4298d0a3ea01d59e716bb7f18860afda64af7034d204d045bca5d24e2436', ('Sources/gor/App/main.swift',)),
    'Sources/gor/AppDelegate.swift': ('32bf4a1a3b0df9c4b96a34d78499c6da3189726cd3746bda765bf2408e659f6b', ('Sources/gor/App/AppDelegate.swift',)),
    'Sources/gor/GorPlatformMac/IndependentDocumentRouter.swift': ('3a62584615656f3e3da906d9d64b2b67ec39660e3ccd9b1bbbdf376174358aa8', ('Sources/gor/App/IndependentDocumentRouter.swift',)),
    'Sources/gor/Core/Build.swift': ('175e9cd9c246cee3e95fe8e0a61da9d6d00b83091b26df993fac7c6ae10c4b9f', ('Sources/gor/App/Build.swift',)),
    'Sources/gor/gor/PPController.swift': ('7bd959a8e6bf574c2fb57f7da9e902ada69912ff3211f8a3892ef2b4961e09cf', ('Sources/gor/Player/PPController.swift',)),
    'Sources/gor/gor/PlayerViewStub.swift': ('8a9e5b71a22e874601fde41e8579f9210db7cc9f1511f931dbd31d91a20a5fb3', ('Sources/gor/Player/PlayerViewStub.swift',)),
    'Sources/gor/Controller/Input.swift': ('d2d8b3f407132907ff37b99c4fa7f4ccc8dae5c78786ee1eb3648da0e46c9378', ('Sources/gor/Player/Input.swift',)),
    'Sources/gor/GorUI/PPControllerEngineRefusalHUD.swift': ('19c4bb316c83aee30d8506524a7469336122f113b7e75b58875ea627d26e7b23', ('Sources/gor/Player/PPControllerEngineRefusalHUD.swift',)),
    'Sources/gor/GorUI/PPControllerMenuQueries.swift': ('1b3125518ba884128df777a7c0968d2576955fc69d719b7962d7750a40bc5e67', ('Sources/gor/Player/PPControllerMenuQueries.swift',)),
    'Sources/gor/GorPlaybackModel/EngineObservation.swift': ('c8ce37ab1ff7a734de70b76b8d1ba9cea64bd75031b98ac0fe2d4dc2bc83def6', ('Sources/gor/Player/EngineObservation.swift',)),
    'Sources/gor/GorMPVBackend/MPVCommand.swift': ('9158fbe3898b9dadea17e1470bc0ce8aee3dd54c962968dc920b33a4c0f8ad2b', ('Sources/gor/Engine/MPVCommand.swift',)),
    'Sources/gor/GorAVBackend/GorAVAppGate.swift': ('525dd07e46a622d560071d58883bd698dd78a984ae8dae54d1bf405b6a52ecff', ('Sources/gor/Engine/GorAVAppGate.swift',)),
    'Sources/gor/GorAVBackend/GorAVHostMotion.swift': ('74c7fe2edc868045d8903071a4000f466d17071402aed880d5eb6d3977d7ea19', ('Sources/gor/Engine/GorAVHostMotion.swift',)),
    'Sources/gor/GorAVBackend/GorAVHostWindow.swift': ('fff38e2579a418b46930dab72081efabedc3b44979a791cea1ec4a32f51c2a25', ('Sources/gor/Engine/GorAVHostWindow.swift',)),
    'Sources/gor/GorAVBackend/GorAVLocalOffer.swift': ('7af57f2ed18b7a64f250fe2f21f0f7d6351a3bd03b8837989d46f6513b29ff31', ('Sources/gor/Engine/GorAVLocalOffer.swift',)),
    'Sources/gor/GorAVBackend/GorAVNativeGate.swift': ('8c0c6abc1e60ac8b45c1ef6e607b76095c2edd81920c28251f43c9bb6d8e5c83', ('Sources/gor/Engine/GorAVNativeGate.swift',)),
    'Sources/gor/GorAVBackend/GorAVPlayerHost.swift': ('0bafe010ea57aa3a0809f1224ba6fc8f0a3fa28d9a5ef5f0b8cd7bff588df800', ('Sources/gor/Engine/GorAVPlayerHost.swift',)),
    'Sources/gor/GorAVBackend/GorAVPostOpenFallback.swift': ('73d66375596154e9df22649cd6d522911e7067d6dad4c18b434a48c408f0a33d', ('Sources/gor/Engine/GorAVPostOpenFallback.swift',)),
    'Sources/gor/GorAVBackend/GorAVStreamAdmission.swift': ('e3d95e54dd3c87a7c30864165d54c2e76d058f02ff1fc85a5de8d7170337c773', ('Sources/gor/Engine/GorAVStreamAdmission.swift',)),
    # Exact three Camera current-old inputs; real hashes only.
    'Sources/gor/gor/BlinkCommandRoute.swift': ('ff074e9dba8de9fe85143d204a9b3e1667ea41aaa90de19cd77770a3cb6534f7', ('Sources/gor/Camera/BlinkCommandRoute.swift',)),
    'Sources/gor/gor/CaptureConsumerRules.swift': ('56f5b0b802ca54baec6f05bdf2151b16cadb7811aab7f893d3d67cc03b68899a', ('Sources/gor/Camera/CaptureConsumerRules.swift',)),
    'Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift': ('a5b3ac4613179ef0c0c2a415c28ce7fe4c60d70e80cb1800f73c1777a2ad650a', ('Sources/gor/Camera/ScreenCaptureEngine.swift',)),
    # Exact nine UI migration inputs; first eight lab moves plus separately bound AdaptiveColor.
    'Sources/gor/GorUI/SpineUI.swift': ('e19af36d3bd31b97dc767e85c937742446efcdee4f3b9d6f732d36d6dfb00cca', ('Sources/gor/UI/SpineUI.swift',)),
    'Sources/gor/GorUI/SidebarUI.swift': ('a7e2274b755dffc4dd8f0090b790dd0fe01bead81e5ad8b61c3e41002ed8e6a1', ('Sources/gor/UI/SidebarUI.swift',)),
    'Sources/gor/GorUI/MenuActions.swift': ('6c65019bb0bbe68b6d22451166dc998e4f709df415dff5149141b00fec95507f', ('Sources/gor/UI/MenuActions.swift',)),
    'Sources/gor/GorEffectsModel/PhotonFont.swift': ('fa16facffeaea3719604f775628c2b6dc2b009acebf4b8da290ac560d0088eeb', ('Sources/gor/UI/PhotonFont.swift',)),
    'Sources/gor/GorEffectsModel/VariationBroadcaster.swift': ('2f762fe5ce7c091c6aba6f064845428d29eb187d315d6b791d5e3881f74fe1aa', ('Sources/gor/UI/VariationBroadcaster.swift',)),
    'Sources/gor/GorFit/IconBarFit.swift': ('52415ab0b3cf991afa2c5aac4afb89f1109fa87e4442b299d368717f3e7fc613', ('Sources/gor/UI/IconBarFit.swift',)),
    'Sources/gor/GorUI/FlatControlRefreshGate.swift': ('b990c0f7031831097bf94b52391e1cfa681ef845e9cbd85bd5aa86192455fd2a', ('Sources/gor/UI/FlatControlRefreshGate.swift',)),
    'Sources/gor/GorUI/PhotonActiveEngineHeader.swift': ('17e69da824f24bc73bf2786f85e5ef068aadc2ea0e14b1b275807d5bbff4cc08', ('Sources/gor/UI/PhotonActiveEngineHeader.swift',)),
    'Sources/gor/GorEffectsModel/AdaptiveColor.swift': ('2fd63b55e52d7e97a5b21a21856583137373c4fa8bfa52f167133d08bb5be1d6', ('Sources/gor/UI/AdaptiveColor.swift',)),
    # Exact12Media migration inputs, including current WT identity only.
    'Sources/gor/GorSources/ArchiveBrowser.swift': ('25472e0eb5da384cda6b5823dc851c8471e002c9223e1949937055b9e98608bb', ('Sources/gor/Media/ArchiveBrowser.swift',)),
    'Sources/gor/GorSources/ArchiveLibrary.swift': ('772942f9057fe2486eac455c145f544e7101238dc52e1693e0aee32cf5a6f1a3', ('Sources/gor/Media/ArchiveLibrary.swift',)),
    'Sources/gor/GorSources/ArchiveRandom.swift': ('d06654d43b0d6688beddf28e069826baaf864855e8f044c0e5363923ef98ee96', ('Sources/gor/Media/ArchiveRandom.swift',)),
    'Sources/gor/GorSources/CDPSession.swift': ('7907dc6d76f4b7aa00c4de736cd5914525ec9043020bffe9435b5c958655b05e', ('Sources/gor/Media/CDPSession.swift',)),
    'Sources/gor/GorSources/FileBrowser.swift': ('5787101f65b62c289efa436cd6a744cfbe7c8f67d6ddd392040132682eabfaae', ('Sources/gor/Media/FileBrowser.swift',)),
    'Sources/gor/GorSources/IPTV.swift': ('d3c1ed6bf012926e74425437d2b62270c39f1e209f293960a4909719ebc0e0e8', ('Sources/gor/Media/IPTV.swift',)),
    'Sources/gor/GorSources/MagnetBrowser.swift': ('172b3b240bfca5ac61a814ca744ea7d035520597c0e7f942a2fd481bc6f45e26', ('Sources/gor/Media/MagnetBrowser.swift',)),
    'Sources/gor/GorSources/MegaStreamManager.swift': ('950b772ebeab9c7591ffda65b0267e435f210a8275458899e81e922f2db774cc', ('Sources/gor/Media/MegaStreamManager.swift',)),
    'Sources/gor/GorSources/TorrentManager.swift': ('8bac5223b130774b31596b8f7ceeec4a660965fcc619913039ad3ae819e7c2b4', ('Sources/gor/Media/TorrentManager.swift',)),
    'Sources/gor/GorSources/TransferResolver.swift': ('b433e500e71a5ef7e120350112926466ef697e341c72ff2651fbafb3c9d44a3b', ('Sources/gor/Media/TransferResolver.swift',)),
    'Sources/gor/GorSources/TransferTicketContext.swift': ('561cba0c7d3a3956eba7faf6df5a5962a1adabe0cf90432c557f6696c97c9820', ('Sources/gor/Media/TransferTicketContext.swift',)),
    'Sources/gor/GorSources/WTSessionPipeDrain.swift': ('40fe8e5d458a5e55a5a25d021735601fd246ffef2ef039446861f4c962d67fd3', ('Sources/gor/Media/WTSessionPipeDrain.swift',)),
    # Exact Modes inputs, whole-file path-only moves.
    'Sources/gor/gor/MusicModeController.swift': ('4274ef855ba067960ee785fde4e49d3203068a6c177d3df1de29146fccc3b50b', ('Sources/gor/Modes/MusicModeController.swift',)),
    'Sources/gor/GorUI/MusicController.swift': ('69cfd7b3543e5904febd8b19b1d5101b6a85653e63a31912b9d26d1d2dce7b76', ('Sources/gor/Modes/MusicController.swift',)),
    'Sources/gor/GorUI/MusicPanel.swift': ('c671112da430988b090b17e1b9565d181c73993d60e7113365f05cfd4d2ab27f', ('Sources/gor/Modes/MusicPanel.swift',)),
    'Sources/gor/gor/MusicRowLabel.swift': ('2aed8a32c44f48c7aec5802ccf8b761904bb5dfa59500a36de2c8078f1e5c228', ('Sources/gor/Modes/MusicRowLabel.swift',)),
    'Sources/gor/gor/IPTVModeController.swift': ('54950012a42418e48e157012cdea762a44313054311c0e1d304578161a5b0b29', ('Sources/gor/Modes/IPTVModeController.swift',)),
    # Body review: whole LookToolsRoute to Stereo, AdaptiveColor waits at original path for UI.
    'Sources/gor/Picture/LookToolsRoute.swift': ('3208c01f3c9831bc4b97b5221f20a48e4e9e063fa208bdb89bde19b52d91ca13', ('Sources/gor/Stereo/LookToolsRoute.swift',)),
    'Sources/gor/Picture/AdaptiveColor.swift': ('2fd63b55e52d7e97a5b21a21856583137373c4fa8bfa52f167133d08bb5be1d6', ('Sources/gor/UI/AdaptiveColor.swift',)),
    # Exact prior inputs relocated to Stereo; no source-body changes.
    'Sources/gor/ThreeD/Source.swift': ('a71d98dfadb470e36fd55c5ce0dbb21c7f143955bab6fc60fa2d6ceb028f2743', ('Sources/gor/Stereo/Source.swift',)),
    'Sources/gor/ThreeD/Depth.swift': ('f011750b5b5572a8f4b3a55a64b77aa3b943326ee6b57a1eb0100361d1b3afa9', ('Sources/gor/Stereo/Depth.swift',)),
    'Sources/gor/ThreeD/Prepare.swift': ('fb6af20d863ab6e04d0e566490d85e5d693e0314c08e2fe668460a25b9acb06a', ('Sources/gor/Stereo/Prepare.swift',)),
    'Sources/gor/ThreeD/Render.swift': ('fe0e42e6e1e7e9ef4b5ddddb3a97e9bf776a026d91b93c733505b5646d47c98e', ('Sources/gor/Stereo/Render.swift',)),
    'Sources/gor/ThreeD/Control.swift': ('905d8052a1128dde00c4ebc1e20034777de369441038f36076f9cc34c0da0ce5', ('Sources/gor/Stereo/Control.swift',)),
    'Sources/gor/gor/VR180Controller.swift': ('4728c9b8773d28d81549c8d0a5435fbc7b197b8b5a03c121a9066a413cb5096d', ('Sources/gor/Stereo/VR180Controller.swift',)),
    'Sources/gor/gor/VRDistanceModel.swift': ('73bec20012095bcfda383fe6c1966907c1eef6eaeb9c17beeca07017254440e8', ('Sources/gor/Stereo/VRDistanceModel.swift',)),
    'Sources/gor/gor/VRStereoControlInput.swift': ('d10c210417045168bc2c879653a3cd5130fb4cb254e96049b5b236eefadf9846', ('Sources/gor/Stereo/VRStereoControlInput.swift',)),
    'Sources/gor/GorStereoUI/GazeCrosshairController.swift': ('a56fd57b99c9af56f88cbb03ab2e9759a9a3e2a55cae6f0a86482b0d3dab076e', ('Sources/gor/Stereo/GazeCrosshairController.swift',)),
    'Sources/gor/GorAVBackend/StereoLookNativeCommands.swift': ('7113a857ecb605bec22d606f1c833c56bf1c864e9f288d68b870b45c5dffa3f7', ('Sources/gor/Stereo/StereoLookNativeCommands.swift',)),
    'Sources/gor/GorAVBackend/StereoLookNativeInputOwner.swift': ('8cea18220eb0da5186d0bdc4e4a92e70688d24f4e03a6a976fffbe038c676bce', ('Sources/gor/Stereo/StereoLookNativeInputOwner.swift',)),
    'Sources/gor/GorAVBackend/StereoLookNativeIntentAdapter.swift': ('ceae955eb4c7414c9c885f33a765c71151f8069f2afb78d8ad3911fff42fa54a', ('Sources/gor/Stereo/StereoLookNativeIntentAdapter.swift',)),
    'Sources/gor/Session/RealtimeProbe.swift': ('e237e2976f6328a319482e9ae3f09d0e59b877535081118e5df2c3e9453c4a38', ('Sources/gor/Stereo/RealtimeProbe.swift',)),
    # Intermediate content-placement correction, whole Build waits for App tail.
    'Sources/gor/Session/Build.swift': ('175e9cd9c246cee3e95fe8e0a61da9d6d00b83091b26df993fac7c6ae10c4b9f', ('Sources/gor/App/Build.swift',)),
    # Exact prior owner inputs relocated to Picture; same bytes, new paths.
    'Sources/gor/Viewport/Viewport.swift': (
        '8fd512af160da3e9fda5a9da6e5c840e8850f7b2212af3f169af562d4b84ee19',
        ('Sources/gor/Picture/Viewport.swift',)),
    'Sources/gor/Viewport/CropDetector.swift': (
        'c0fec5c30bd87cb81e5273e719691dce73e44209e0e6b72989dbd5e6af2ab6f1',
        ('Sources/gor/Picture/CropDetector.swift',)),
    'Sources/gor/Display/Brightness.swift': (
        'bc6c5dac08ab5690e1f62f0660ee2aa0cb5e9692a99204326b657ee5fa46cd68',
        ('Sources/gor/Picture/Brightness.swift',)),
    'Sources/gor/GorEffectsModel/LookToolsRoute.swift': (
        '3208c01f3c9831bc4b97b5221f20a48e4e9e063fa208bdb89bde19b52d91ca13',
        ('Sources/gor/Stereo/LookToolsRoute.swift',)),
    # Exact prior owner inputs relocated to Session; same bytes, new paths.
    'Sources/gor/GorPlatformMac/PlayerSessionBarrierAdapter.swift': (
        '1284739f03fc3a4fbde17bbb5d1c484deeff4f01e5b8d81c24332f35eb4ade80',
        ('Sources/gor/Session/PlayerSessionBarrierAdapter.swift',)),
    'Sources/gor/GorPlatformMac/PlayerSessionContext.swift': (
        'ba0946edaaa7164957ddeb36de8562b3884b4bad4e40d06302351df79c30eeca',
        ('Sources/gor/Session/PlayerSessionContext.swift',)),
    'Sources/gor/GorPlatformMac/PlayerSessionDrainPlan.swift': (
        '67583dc90d38415f6c12559dcd91dbe8d49e19fb8c09e87c5f85f94a91791d14',
        ('Sources/gor/Session/PlayerSessionDrainPlan.swift',)),
    'Sources/gor/GorPlatformMac/PlayerSessionFileTransport.swift': (
        '90787950854b69c468485cd58179f652fdacebdd053dbc77969412a92f186885',
        ('Sources/gor/Session/PlayerSessionFileTransport.swift',)),
    'Sources/gor/GorPlatformMac/PlayerSessionNativeSink.swift': (
        '6dea9abe4df8db32fd5ac0f8c6c4cd92a085f4f9d4cf330608dd7cc994109315',
        ('Sources/gor/Session/PlayerSessionNativeSink.swift',)),
    'Sources/gor/GorPlatformMac/PlayerSessionPipeDrain.swift': (
        '5014113f7b6222e3fb40d30f01d16c90d0a0ce598ae94243867e68369dd4915b',
        ('Sources/gor/Session/PlayerSessionPipeDrain.swift',)),
    'Sources/gor/GorPlatformMac/PlayerRuntimeResources.swift': (
        '00f375e5ee4b41fab7e189eea8a89ca4abe4e863d7f1ac0f051ad5d16f4f8b0b',
        ('Sources/gor/Session/PlayerRuntimeResources.swift',)),
    'Sources/gor/GorPlatformMac/PlayerTorrentEndpoint.swift': (
        '9c6a162973b00c69a6552e8983d3623912cd0325389ba02bb03528abe6cce814',
        ('Sources/gor/Session/PlayerTorrentEndpoint.swift',)),
    'Sources/gor/GorPlatformMac/RealtimeProbe.swift': (
        'e237e2976f6328a319482e9ae3f09d0e59b877535081118e5df2c3e9453c4a38',
        ('Sources/gor/Stereo/RealtimeProbe.swift',)),
    'Sources/gor/Core/Diag.swift': (
        '28dad9f5d9dbaec5c1fb0702bf6ec3528c70e00f0a683a33f4a75f956bd1907e',
        ('Sources/gor/Session/Diag.swift',)),
    # Exact Core inputs must retire before the legacy updater re-execs.
    'Sources/gor/GorCore/Diag.swift': (
        'c8a9d49477962cb33ccc6bac0578c380fb309dd029797ee7df7dcf2ad895e121',
        ('Sources/gor/Session/Diag.swift',)),
    'Sources/gor/gor/GeomTrace.swift': (
        '6b4288e3f6f89b93220d7afd5f50bea7019ec477fbc22ae13d7e90f85484dddc',
        ('Sources/gor/Session/Diag.swift',)),
    'Sources/gor/GorPlatformMac/GORResources.swift': (
        'd94c3244ba7adc4ef87d85e94d9de573950d770c2885073d978b17c6a19484ac',
        ('Sources/gor/App/Build.swift',)),
    'Sources/gor/GorCore/BuildID.swift': (
        '544881ae92b8f6b4235ed47b70c14f4997ee10a05faa06d877d5bf8f3df80365',
        ('Sources/gor/App/Build.swift',)),
    'Sources/gor/GorCore/StableCacheKey.swift': (
        '06ab2fa85040c2ae44d953cfc29d583db2b804d59c7cc3e8abc4876e3a790ef5',
        ('Sources/gor/App/Build.swift',)),
    'Sources/gor/gor/SeededRandomNumberGenerator.swift': (
        '5c74f2097d44ae358decb04031097a6b83face3c34f7107a541838a6c24d058f',
        ('Sources/gor/App/Build.swift',)),
    # Exact current-path inputs absorbed by the Platform station.
    'Sources/gor/GorPlatformMac/QuitChildKiller.swift': (
        'ffbea2bab58dc393d3d0d74fad7752afef587c181c9f426013b4080b70fe607a',
        ('Sources/gor/Platform/QuitChildKiller.swift',)),
    'Sources/gor/GorPlatformMac/OverlaySpaceGate.swift': (
        'b78a82df465755b61f695a10f6121f13a081ba40ff9cf76da7c075e06125fff9',
        ('Sources/gor/Platform/Windowing.swift',)),
    'Sources/gor/GorPlatformMac/PanelFocus.swift': (
        'ed945c8ac1050e41949ad19f34c42fe176c74ef1ef5cc35bb91aa35e7796381b',
        ('Sources/gor/Platform/Windowing.swift',)),
    'Sources/gor/GorPlatformMac/PanelFocusTraversal.swift': (
        '3e1a34f112600388f6317285289c98669320dd8b5c3c85e14a7ce114693fd78f',
        ('Sources/gor/Platform/Windowing.swift',)),
    # Exact current-path inputs absorbed by the Subtitles station.
    'Sources/gor/GorSubtitlesUI/SubtitleView.swift': (
        '8eb5aaee942e087d92cba4644ac42ceef2c5decc488f76de51799585f8d29873',
        ('Sources/gor/Subtitles/SubtitleView.swift',)),
    'Sources/gor/Subtitles/SubtitleTiltGeometry.swift': (
        '204496360f173b50ed42f399e79b14cf77cb9d7b3c0833247f4e30d1af064abe',
        ('Sources/gor/Subtitles/SubtitleView.swift',)),
    'Sources/gor/Subtitles/SubtitlePreferences.swift': (
        'b9d27a54dc0af5dd37504f289bf2240deb923b0df3c14271a64d39eb6efece5f',
        ('Sources/gor/Subtitles/SubtitleView.swift',)),
    'Sources/gor/GorSubtitles/LiveCaptionController.swift': (
        'd749b6d29a80423faa9e66d8b274b7103b4ce477c57ee3c54c7ed861c4c04da3',
        ('Sources/gor/Subtitles/LiveCaption.swift',)),
    'Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift': (
        'fe3793cff08a472617ba1ca2170cca700ca919c5e7760f0bddfd64b6ed2f98da',
        ('Sources/gor/Subtitles/LiveCaption.swift',)),
    # Exact pre-Display current-path inputs; altered or unknown bytes remain refused.
    'Sources/gor/gor/BrightnessController.swift': (
        'b63c6bb391f53494fe740e4b3a964943426af74f9cda0534bb4c723d161bbdea',
        ('Sources/gor/Picture/Brightness.swift',)),
    'Sources/gor/gor/BrightnessReadCache.swift': (
        'e3b41206bfcdf56dfd88966bed799216e4beb5ae68fac9817801fd039367cd24',
        ('Sources/gor/Picture/Brightness.swift',)),
    'Sources/gor/gor/ContentAdaptiveDimming.swift': (
        'e9c99a7f4c90a796a7f46bbdbccf2d58e30d65ff30a41f72f17929e50d307c15',
        ('Sources/gor/Picture/Brightness.swift',)),
    # Exact nested-path monolith in delivered59 f0691de86 through delivered90.
    'Sources/gor/gor/ThreeD.swift': (
        '2b06e395bbe7dfbfaeb2a242336097f1b1db48e8d09da867f8ed6ce03e08a51e',
        ('Sources/gor/Stereo/Source.swift', 'Sources/gor/Stereo/Depth.swift',
         'Sources/gor/Stereo/Prepare.swift', 'Sources/gor/Stereo/Render.swift',
         'Sources/gor/Stereo/Control.swift')),
    'Sources/gor/CameraPrivacyGate.swift': (
        '128b9f382f6e4401f24056afe268de5988f1add68d6e305d9292f7eebabf3464',
        ('Sources/gor/Camera/ScreenCaptureEngine.swift',)),
    'Sources/gor/gor/PPController_Features.swift': (
        'ef8fc46feeb8bff1ae6b18bdd058c3a210fc028550f61ebf04feb0fd0b21e683',
        ('Sources/gor/Player/PPController.swift', 'Sources/gor/Stereo/VR180Controller.swift',
         'Sources/gor/Player/Input.swift', 'Sources/gor/Picture/Brightness.swift')),
    'Sources/gor/gor/InputController.swift': (
        '49b589859de42e38ffa05fea504d71c42d7d84f2679029dcced767740028f259',
        ('Sources/gor/Player/Input.swift',)),
    'Sources/gor/gor/DragDropHandler.swift': (
        '44f6b8ee47cc2a5bbf404cadafdb654c9dc002c1ed03bc2d2ce4942fde37b332',
        ('Sources/gor/Player/Input.swift',)),
}


def retire_update_sources(repo, commit, project):
    """Repair an old overlay runner before receipt creation. Never used by identity reads.

    Verify all incoming bytes/modes and the whole prospective compiled-input set first.
    Back up every exact historical extra, verify backups, journal rollback, then quarantine by rename.
    Unknown/edited extras stop before any source or receipt mutation. A failed retirement
    can leave only a backed-up subset retired; the normal gate still refuses until exact.
    """
    import datetime, os, shutil, stat
    root = Path(project).resolve(strict=True)
    files, modes = tree_files(repo, commit), tree_modes(repo, commit)
    for rel, blob in files.items():
        p = root / rel
        if p.is_symlink() or not p.is_file() or blob_id(p.read_bytes()) != blob or \
                bool(p.stat().st_mode & 0o100) != (modes[rel] == '100755'):
            raise Refusal('retirement preflight: delivered bytes/mode differ: ' + rel)
    installed = compiled_inputs(root)
    extras = sorted(set(installed) - set(files))
    plan = []
    for rel in extras:
        entry = UPDATE_RETIREMENTS.get(rel)
        if entry is None:
            raise Refusal('retirement preflight: unknown extra build input: ' + rel)
        digest, replacements = entry
        if installed[rel] not in ({digest} | UPDATE_RETIREMENT_ALTERNATES.get(rel, set())) or not all(p in files for p in replacements):
            raise Refusal('retirement preflight: edited source or missing replacement: ' + rel)
        p = root / rel
        if any((root / Path(*Path(rel).parts[:i])).is_symlink()
               for i in range(1, len(Path(rel).parts))):
            raise Refusal('retirement preflight: symlink ancestor: ' + rel)
        plan.append((rel, installed[rel], stat.S_IMODE(p.stat().st_mode)))
    bind_snapshot(repo, files, {p: h for p, h in installed.items() if p not in extras})
    if not plan:
        return
    backups = root / '.gor-backups'
    if backups.is_symlink():
        raise Refusal('retirement backup root is a symlink')
    backups.mkdir(exist_ok=True)
    candidates = sorted(backups.glob('*-pre-update'))
    if not candidates:
        raise Refusal('retirement requires the existing pre-update rollback journal')
    # Retry may have created a small backup on top of an earlier failed overlay.
    # Compose journals back to the PP split's add-set, then roll back in ONE step.
    merged = {}
    foundations = set()
    required_foundations = {
        marker for old, marker in (
            ('Sources/gor/gor/PPController_Features.swift', 'Sources/gor/Stereo/VR180Controller.swift'),
            ('Sources/gor/gor/ThreeD.swift', 'Sources/gor/Stereo/Source.swift'),
            ('Sources/gor/gor/InputController.swift', 'Sources/gor/Player/Input.swift'),
            ('Sources/gor/gor/DragDropHandler.swift', 'Sources/gor/Player/Input.swift'))
        if old in extras
    }
    # A retry may begin on top of a failed 199u overlay. Find the original
    # station add-set, not just the newest small backup, for one-step rollback.
    station_retired = {
        'Sources/gor/main.swift': 'Sources/gor/App/main.swift',
        'Sources/gor/AppDelegate.swift': 'Sources/gor/App/AppDelegate.swift',
        'Sources/gor/GorPlatformMac/IndependentDocumentRouter.swift': 'Sources/gor/App/IndependentDocumentRouter.swift',
        'Sources/gor/Core/Build.swift': 'Sources/gor/App/Build.swift',
        'Sources/gor/gor/PPController.swift': 'Sources/gor/Player/PPController.swift',
        'Sources/gor/gor/PlayerViewStub.swift': 'Sources/gor/Player/PlayerViewStub.swift',
        'Sources/gor/Controller/Input.swift': 'Sources/gor/Player/Input.swift',
        'Sources/gor/GorUI/PPControllerEngineRefusalHUD.swift': 'Sources/gor/Player/PPControllerEngineRefusalHUD.swift',
        'Sources/gor/GorUI/PPControllerMenuQueries.swift': 'Sources/gor/Player/PPControllerMenuQueries.swift',
        'Sources/gor/GorPlaybackModel/EngineObservation.swift': 'Sources/gor/Player/EngineObservation.swift',
        'Sources/gor/GorMPVBackend/MPVCommand.swift': 'Sources/gor/Engine/MPVCommand.swift',
        'Sources/gor/GorAVBackend/GorAVAppGate.swift': 'Sources/gor/Engine/GorAVAppGate.swift',
        'Sources/gor/GorAVBackend/GorAVHostMotion.swift': 'Sources/gor/Engine/GorAVHostMotion.swift',
        'Sources/gor/GorAVBackend/GorAVHostWindow.swift': 'Sources/gor/Engine/GorAVHostWindow.swift',
        'Sources/gor/GorAVBackend/GorAVLocalOffer.swift': 'Sources/gor/Engine/GorAVLocalOffer.swift',
        'Sources/gor/GorAVBackend/GorAVNativeGate.swift': 'Sources/gor/Engine/GorAVNativeGate.swift',
        'Sources/gor/GorAVBackend/GorAVPlayerHost.swift': 'Sources/gor/Engine/GorAVPlayerHost.swift',
        'Sources/gor/GorAVBackend/GorAVPostOpenFallback.swift': 'Sources/gor/Engine/GorAVPostOpenFallback.swift',
        'Sources/gor/GorAVBackend/GorAVStreamAdmission.swift': 'Sources/gor/Engine/GorAVStreamAdmission.swift',
        'Sources/gor/gor/BlinkCommandRoute.swift': 'Sources/gor/Camera/BlinkCommandRoute.swift',
        'Sources/gor/gor/CaptureConsumerRules.swift': 'Sources/gor/Camera/CaptureConsumerRules.swift',
        'Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift': 'Sources/gor/Camera/ScreenCaptureEngine.swift',
        'Sources/gor/GorUI/SpineUI.swift': 'Sources/gor/UI/SpineUI.swift',
        'Sources/gor/GorUI/SidebarUI.swift': 'Sources/gor/UI/SidebarUI.swift',
        'Sources/gor/GorUI/MenuActions.swift': 'Sources/gor/UI/MenuActions.swift',
        'Sources/gor/GorEffectsModel/PhotonFont.swift': 'Sources/gor/UI/PhotonFont.swift',
        'Sources/gor/GorEffectsModel/VariationBroadcaster.swift': 'Sources/gor/UI/VariationBroadcaster.swift',
        'Sources/gor/GorFit/IconBarFit.swift': 'Sources/gor/UI/IconBarFit.swift',
        'Sources/gor/GorUI/FlatControlRefreshGate.swift': 'Sources/gor/UI/FlatControlRefreshGate.swift',
        'Sources/gor/GorUI/PhotonActiveEngineHeader.swift': 'Sources/gor/UI/PhotonActiveEngineHeader.swift',
        'Sources/gor/GorEffectsModel/AdaptiveColor.swift': 'Sources/gor/UI/AdaptiveColor.swift',
        'Sources/gor/GorSources/ArchiveBrowser.swift': 'Sources/gor/Media/ArchiveBrowser.swift',
        'Sources/gor/GorSources/ArchiveLibrary.swift': 'Sources/gor/Media/ArchiveLibrary.swift',
        'Sources/gor/GorSources/ArchiveRandom.swift': 'Sources/gor/Media/ArchiveRandom.swift',
        'Sources/gor/GorSources/CDPSession.swift': 'Sources/gor/Media/CDPSession.swift',
        'Sources/gor/GorSources/FileBrowser.swift': 'Sources/gor/Media/FileBrowser.swift',
        'Sources/gor/GorSources/IPTV.swift': 'Sources/gor/Media/IPTV.swift',
        'Sources/gor/GorSources/MagnetBrowser.swift': 'Sources/gor/Media/MagnetBrowser.swift',
        'Sources/gor/GorSources/MegaStreamManager.swift': 'Sources/gor/Media/MegaStreamManager.swift',
        'Sources/gor/GorSources/TorrentManager.swift': 'Sources/gor/Media/TorrentManager.swift',
        'Sources/gor/GorSources/TransferResolver.swift': 'Sources/gor/Media/TransferResolver.swift',
        'Sources/gor/GorSources/TransferTicketContext.swift': 'Sources/gor/Media/TransferTicketContext.swift',
        'Sources/gor/GorSources/WTSessionPipeDrain.swift': 'Sources/gor/Media/WTSessionPipeDrain.swift',
        'Sources/gor/gor/MusicModeController.swift': 'Sources/gor/Modes/MusicModeController.swift',
        'Sources/gor/GorUI/MusicController.swift': 'Sources/gor/Modes/MusicController.swift',
        'Sources/gor/GorUI/MusicPanel.swift': 'Sources/gor/Modes/MusicPanel.swift',
        'Sources/gor/gor/MusicRowLabel.swift': 'Sources/gor/Modes/MusicRowLabel.swift',
        'Sources/gor/gor/IPTVModeController.swift': 'Sources/gor/Modes/IPTVModeController.swift',
        'Sources/gor/Picture/LookToolsRoute.swift': 'Sources/gor/Stereo/LookToolsRoute.swift',
        'Sources/gor/Picture/AdaptiveColor.swift': 'Sources/gor/UI/AdaptiveColor.swift',
        'Sources/gor/ThreeD/Source.swift': 'Sources/gor/Stereo/Source.swift',
        'Sources/gor/ThreeD/Depth.swift': 'Sources/gor/Stereo/Depth.swift',
        'Sources/gor/ThreeD/Prepare.swift': 'Sources/gor/Stereo/Prepare.swift',
        'Sources/gor/ThreeD/Render.swift': 'Sources/gor/Stereo/Render.swift',
        'Sources/gor/ThreeD/Control.swift': 'Sources/gor/Stereo/Control.swift',
        'Sources/gor/gor/VR180Controller.swift': 'Sources/gor/Stereo/VR180Controller.swift',
        'Sources/gor/gor/VRDistanceModel.swift': 'Sources/gor/Stereo/VRDistanceModel.swift',
        'Sources/gor/gor/VRStereoControlInput.swift': 'Sources/gor/Stereo/VRStereoControlInput.swift',
        'Sources/gor/GorStereoUI/GazeCrosshairController.swift': 'Sources/gor/Stereo/GazeCrosshairController.swift',
        'Sources/gor/GorAVBackend/StereoLookNativeCommands.swift': 'Sources/gor/Stereo/StereoLookNativeCommands.swift',
        'Sources/gor/GorAVBackend/StereoLookNativeInputOwner.swift': 'Sources/gor/Stereo/StereoLookNativeInputOwner.swift',
        'Sources/gor/GorAVBackend/StereoLookNativeIntentAdapter.swift': 'Sources/gor/Stereo/StereoLookNativeIntentAdapter.swift',
        'Sources/gor/Session/RealtimeProbe.swift': 'Sources/gor/Stereo/RealtimeProbe.swift',
        'Sources/gor/Session/Build.swift': 'Sources/gor/App/Build.swift',
        'Sources/gor/Viewport/Viewport.swift': 'Sources/gor/Picture/Viewport.swift',
        'Sources/gor/Viewport/CropDetector.swift': 'Sources/gor/Picture/CropDetector.swift',
        'Sources/gor/Display/Brightness.swift': 'Sources/gor/Picture/Brightness.swift',
        'Sources/gor/GorEffectsModel/LookToolsRoute.swift': 'Sources/gor/Stereo/LookToolsRoute.swift',
        'Sources/gor/GorPlatformMac/PlayerSessionBarrierAdapter.swift': 'Sources/gor/Session/PlayerSessionBarrierAdapter.swift',
        'Sources/gor/GorPlatformMac/PlayerSessionContext.swift': 'Sources/gor/Session/PlayerSessionContext.swift',
        'Sources/gor/GorPlatformMac/PlayerSessionDrainPlan.swift': 'Sources/gor/Session/PlayerSessionDrainPlan.swift',
        'Sources/gor/GorPlatformMac/PlayerSessionFileTransport.swift': 'Sources/gor/Session/PlayerSessionFileTransport.swift',
        'Sources/gor/GorPlatformMac/PlayerSessionNativeSink.swift': 'Sources/gor/Session/PlayerSessionNativeSink.swift',
        'Sources/gor/GorPlatformMac/PlayerSessionPipeDrain.swift': 'Sources/gor/Session/PlayerSessionPipeDrain.swift',
        'Sources/gor/GorPlatformMac/PlayerRuntimeResources.swift': 'Sources/gor/Session/PlayerRuntimeResources.swift',
        'Sources/gor/GorPlatformMac/PlayerTorrentEndpoint.swift': 'Sources/gor/Session/PlayerTorrentEndpoint.swift',
        'Sources/gor/GorPlatformMac/RealtimeProbe.swift': 'Sources/gor/Stereo/RealtimeProbe.swift',
        'Sources/gor/Core/Diag.swift': 'Sources/gor/Session/Diag.swift',
        'Sources/gor/GorCore/Diag.swift': 'Sources/gor/Session/Diag.swift',
        'Sources/gor/gor/GeomTrace.swift': 'Sources/gor/Session/Diag.swift',
        'Sources/gor/GorPlatformMac/GORResources.swift': 'Sources/gor/App/Build.swift',
        'Sources/gor/GorCore/BuildID.swift': 'Sources/gor/App/Build.swift',
        'Sources/gor/GorCore/StableCacheKey.swift': 'Sources/gor/App/Build.swift',
        'Sources/gor/gor/SeededRandomNumberGenerator.swift': 'Sources/gor/App/Build.swift',
        'Sources/gor/gor/BrightnessController.swift': 'Sources/gor/Picture/Brightness.swift',
        'Sources/gor/gor/BrightnessReadCache.swift': 'Sources/gor/Picture/Brightness.swift',
        'Sources/gor/gor/ContentAdaptiveDimming.swift': 'Sources/gor/Picture/Brightness.swift',
        'Sources/gor/GorSubtitlesUI/SubtitleView.swift': 'Sources/gor/Subtitles/SubtitleView.swift',
        'Sources/gor/Subtitles/SubtitleTiltGeometry.swift': 'Sources/gor/Subtitles/SubtitleView.swift',
        'Sources/gor/Subtitles/SubtitlePreferences.swift': 'Sources/gor/Subtitles/SubtitleView.swift',
        'Sources/gor/GorSubtitles/LiveCaptionController.swift': 'Sources/gor/Subtitles/LiveCaption.swift',
        'Sources/gor/GorSubtitles/SubtitleSampleGovernor.swift': 'Sources/gor/Subtitles/LiveCaption.swift',
        'Sources/gor/GorPlatformMac/QuitChildKiller.swift': 'Sources/gor/Platform/QuitChildKiller.swift',
        'Sources/gor/GorPlatformMac/OverlaySpaceGate.swift': 'Sources/gor/Platform/Windowing.swift',
        'Sources/gor/GorPlatformMac/PanelFocus.swift': 'Sources/gor/Platform/Windowing.swift',
        'Sources/gor/GorPlatformMac/PanelFocusTraversal.swift': 'Sources/gor/Platform/Windowing.swift',
    }
    required_foundations.update(marker for old, marker in station_retired.items() if old in extras)
    foundation = False
    for candidate in reversed(candidates):
        journal = candidate / 'changes.txt'
        if candidate.is_symlink() or journal.is_symlink() or not journal.is_file():
            raise Refusal('retirement rollback journal is missing or unsafe')
        raw = journal.read_text()
        if raw and not raw.endswith('\n'):
            raise Refusal('retirement rollback journal is incomplete')
        rows = {}
        for line in raw.splitlines():
            fields = line.split('\t')
            if len(fields) != 2:
                raise Refusal('retirement rollback journal malformed')
            kind, rel = fields
            if kind not in ('added', 'changed', 'deleted') or rel.startswith('/') or '..' in Path(rel).parts or rel in rows:
                raise Refusal('retirement rollback journal unsafe or duplicate')
            saved = candidate / rel
            if kind != 'added' and (saved.is_symlink() or not saved.is_file()):
                raise Refusal('retirement rollback source missing: ' + rel)
            rows[rel] = (kind, saved)
        merged.update(rows)  # earlier pre-state wins
        foundations.update(marker for marker in required_foundations if rows.get(marker, ('',))[0] == 'added')
        if required_foundations <= foundations:
            foundation = True
            break
    if not foundation:
        raise Refusal('retirement requires original failed-overlay rollback foundation')
    # Sort after the installer's same-second -pre-update backup for --rollback.
    stamp = datetime.datetime.now().strftime('%y%m%d-%H%M%S') + '-zz'
    final_park = backups / (stamp + '-pre-update-retire')
    park = backups / ('.pending-' + stamp + '-pre-update-retire')
    park.mkdir()
    for rel, (kind, saved) in merged.items():
        if kind == 'added':
            continue
        target = park / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(saved, target)
        if target.read_bytes() != saved.read_bytes() or stat.S_IMODE(target.stat().st_mode) != stat.S_IMODE(saved.stat().st_mode):
            raise Refusal('rollback foundation backup readback failed: ' + rel)
    for rel, _, _ in plan:
        if rel in merged:
            raise Refusal('retirement rollback foundation unexpectedly overlaps retired path: ' + rel)
    journal = park / 'changes.txt'
    for rel, digest, mode in plan:
        saved = park / rel
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / rel, saved)
        if hashlib.sha256(saved.read_bytes()).hexdigest() != digest or stat.S_IMODE(saved.stat().st_mode) != mode:
            raise Refusal('retirement backup readback failed: ' + rel)
        with saved.open('rb') as f:
            os.fsync(f.fileno())
    # All backups are durable before any source move. Existing --rollback understands deleted.
    # Publish one composed rollback journal, preserving the original backups unchanged.
    with journal.open('xb') as f:
        f.write(''.join(kind + '\t' + rel + '\n' for rel, (kind, _) in merged.items()).encode())
        f.write(''.join('deleted\t' + rel + '\n' for rel, _, _ in plan).encode())
        f.flush()
        os.fsync(f.fileno())
    for rel, digest, mode in plan:
        p = root / rel
        if p.is_symlink() or not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest() != digest or stat.S_IMODE(p.stat().st_mode) != mode:
            raise Refusal('retirement source changed after backup: ' + rel)
    park.rename(final_park)
    park = final_park
    moved = []
    try:
        for rel, _, _ in plan:
            target = park / 'quarantined-inputs' / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            (root / rel).rename(target)
            moved.append(rel)
    except OSError as error:
        for rel in reversed(moved):
            target = root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            (park / 'quarantined-inputs' / rel).rename(target)
        raise Refusal('retirement failed; historical sources restored; backup retained') from error
    print('update retirement: exact historical sources backed up at ' + str(park), file=sys.stderr)


def prune_empty_source_directories(project):
    """Remove only empty descendants of Sources, without following directory links."""
    import errno, os
    source = Path(project).resolve(strict=True) / 'Sources'
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    removed = []
    def visit(fd, relative):
        with os.scandir(fd) as entries:
            names = sorted(entry.name for entry in entries if entry.is_dir(follow_symlinks=False))
        for name in names:
            rel = relative / name
            try:
                child = os.open(name, flags, dir_fd=fd)
            except OSError as error:
                if error.errno in (errno.ENOENT, errno.ENOTDIR, errno.ELOOP):
                    continue  # A raced replacement or symlink is never traversed.
                raise Refusal('empty-source cleanup: cannot open ' + repr(str(rel)) + ': ' + str(error)) from error
            try:
                visit(child, rel)
            finally:
                os.close(child)
            try:
                os.rmdir(name, dir_fd=fd)  # Kernel refuses nonempty directories atomically.
            except OSError as error:
                if error.errno in (errno.ENOTEMPTY, errno.EEXIST, errno.ENOENT, errno.ENOTDIR):
                    continue
                raise Refusal('empty-source cleanup: rmdir failed for ' + repr(str(rel)) + ': ' + str(error)) from error
            removed.append(str(rel))
    try:
        root = os.open(source, flags)
    except OSError as error:
        raise Refusal('empty-source cleanup: Sources is missing, unsafe or unreadable: ' + str(error)) from error
    try:
        visit(root, Path('Sources'))
    finally:
        os.close(root)
    if removed:
        print('update: removed %d empty directories under Sources (rmdir only)' % len(removed), file=sys.stderr)
    return removed


def record_delivery(repo, project, branch):
    """Called by --update. Delivered commit = the object the fetch obtained, which must also be HEAD."""
    tip = git(repo, 'rev-parse', 'origin/' + branch + '^{commit}').decode().strip()
    head = git(repo, 'rev-parse', 'HEAD^{commit}').decode().strip()
    if tip != head:
        raise Refusal('sidecar HEAD is not the fetched tip of origin/' + branch)
    try:
        retire_update_sources(repo, tip, project)
    except OSError as error:
        raise Refusal('update retirement I/O failure; backups preserved: ' + str(error)) from error
    prune_empty_source_directories(project)
    tree, manifest, count, snap = verify_installed(repo, tip, project)
    record = {'version': 2, 'source_commit': tip, 'tree': tree, 'tree_manifest_sha256': manifest, 'source_snapshot_sha256': snap, 'file_count': count}
    (Path(project) / RECORD).write_text(json.dumps(record, sort_keys=True) + '\n')
    return record


def ensure_delivery(repo, project, branch):
    """Update continuation gate. Sidecar HEAD must equal the fetched tip (same rule as record_delivery) before a receipt
    is kept or recorded. A receipt is kept only if it names the tip and the installed bytes still verify against it;
    otherwise it is (re)recorded, which refuses on any mismatch. A refusal writes no new trusted receipt; an earlier
    receipt file is left untouched (history is not deleted) and the caller exits before any build."""
    tip = git(repo, 'rev-parse', 'origin/' + branch + '^{commit}').decode().strip()
    head = git(repo, 'rev-parse', 'HEAD^{commit}').decode().strip()
    if tip != head:
        raise Refusal('sidecar HEAD is not the fetched tip of origin/' + branch)
    try:
        record = json.loads((Path(project) / RECORD).read_text())
        if record.get('source_commit') == tip and record.get('version') == 2:
            tree, manifest, count, snap = verify_installed(repo, tip, project)
            if (record.get('tree'), record.get('tree_manifest_sha256'), record.get('source_snapshot_sha256'), record.get('file_count')) == (tree, manifest, snap, count):
                return record, False
    except (OSError, ValueError, AttributeError, Refusal):
        pass
    return record_delivery(repo, project, branch), True


def identity(repo, project, snapshot_file=None):
    """Typed identity re-derived now from objects and installed bytes; never from the record alone.
    snapshot_file: the build's own source snapshot, bound to the delivered tree when given."""
    try:
        record = json.loads((Path(project) / RECORD).read_text())
        commit = record['source_commit']
        records = json.loads(Path(snapshot_file).read_text()) if snapshot_file else None
        tree, manifest, count, snap = verify_installed(repo, commit, project, records)
        if snapshot_file and snapshot_sha256(Path(snapshot_file).read_bytes()) != snap:
            raise Refusal('snapshot file bytes are not the canonical snapshot')
        return {'verification': VERIFIED, 'source_commit': commit, 'tree': tree, 'tree_manifest_sha256': manifest,
                'source_snapshot_sha256': snap, 'file_count': count}
    except (OSError, ValueError, KeyError, TypeError, Refusal) as error:
        out = {'verification': 'unverified', 'reason': str(error)[:120].replace('\n', ' ')}
        try:
            out['source_snapshot_sha256'] = snapshot_sha256(snapshot_text(project)) if not snapshot_file else snapshot_sha256(Path(snapshot_file).read_bytes())
        except (OSError, Refusal):
            pass
        return out


def identity_line(ident, build=None):
    """build defaults to the receipt's own snapshot digest; callers pass the installed build-id when known."""
    snap = ident.get('source_snapshot_sha256')
    snap = snap if HEX64.fullmatch(snap or '') else 'unknown'
    build = build if HEX64.fullmatch(build or '') else snap
    if ident.get('verification') == VERIFIED:
        body = 'verification=%s source_commit=%s tree=%s tree_manifest=%s' % (
            VERIFIED, ident['source_commit'], ident['tree'], ident['tree_manifest_sha256'])
    else:
        body = 'verification=unverified reason=' + re.sub(r'\W+', '_', ident.get('reason', 'unknown'))[:60]
    return '[GOR-IDENTITY] v1 ' + body + ' snapshot=' + snap + ' build=' + build


def write_provenance(project, repo, resources, snapshot):
    ident = identity(repo, project, snapshot)
    receipt = {'version': 3}
    receipt.update(ident)
    try:
        relay = Path(project) / 'Resources/vendor/mega_relay/mega_relay.mjs'
        receipt['relay_sha256'] = hashlib.sha256(relay.read_bytes()).hexdigest()
    except OSError:
        pass
    Path(resources, 'gor-build-provenance.json').write_text(json.dumps(receipt, sort_keys=True) + '\n')
    return receipt


def first_line_matches(data, expected_line):
    return data.split(b'\n', 1)[0].decode(errors='replace') == expected_line


if __name__ == '__main__':
    try:
        cmd = sys.argv[1]
        if cmd == 'record-delivery':
            r = record_delivery(*sys.argv[2:5])
            print('provenance: verified source_commit=%s tree=%s tree_manifest=%s files=%d' % (
                r['source_commit'], r['tree'], r['tree_manifest_sha256'], r['file_count']))
        elif cmd == 'ensure-delivery':
            r, wrote = ensure_delivery(*sys.argv[2:5])
            print('provenance: delivery receipt %s source_commit=%s tree=%s files=%d' % (
                'recorded by the update continuation' if wrote else 'present and verified', r['source_commit'], r['tree'], r['file_count']))
        elif cmd == 'prune-empty-sources':
            prune_empty_source_directories(sys.argv[2])
        elif cmd == 'identity-line':
            print(identity_line(identity(sys.argv[2], sys.argv[3])))
        elif cmd == 'snapshot':
            Path(sys.argv[3]).write_text(snapshot_text(sys.argv[2]))
        elif cmd == 'write':
            write_provenance(*sys.argv[2:6])
        else:
            raise SystemExit('usage: record-delivery|ensure-delivery|identity-line|write')
    except Refusal as error:
        print('provenance REFUSED: ' + str(error), file=sys.stderr)
        sys.exit(1)
