"""Production Swift staged-path policy + AppDelegate side-effect routing.

No AppKit runtime, native sandbox, focus, TCC or keychain proof is claimed.
"""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
from pathlib import Path
import subprocess,tempfile,re,os
root=Path(__file__).resolve().parents[2]
resources=_core_read(root/'Sources/gor/GorPlatformMac/GORResources.swift')
policy=resources[resources.index('struct StagedPathPolicy {'):resources.index('enum StagedRunPaths')]
body=r'''
let prod=StagedPathPolicy(bundleID:"com.gokcebalkan.gor",environment:["GOR_STAGED_PATH_PREFIX":"/evil","GOR_SELFTEST_STAGED":"1"])
let original=URL(fileURLWithPath:"/Users/owner/Library/Application Support")
precondition(!prod.active && prod.valid)
for p in ["/tmp/gor_direct.log","/tmp/gor_diag.log","/tmp/gor_watch_later","/tmp/webtorrent_stream","/tmp/hidden_mpv_1.sock"] {precondition(prod.temp(p)==p)}
precondition(prod.home(original)==original)
let prefix=NSTemporaryDirectory()+"fixture/.gor-autoupdate/staging/project/staged-runtime"
let stage=StagedPathPolicy(bundleID:"com.gokcebalkan.gor.staging",environment:["GOR_STAGED_PATH_PREFIX":prefix])
precondition(stage.active && stage.valid)
for p in ["/tmp/gor_direct.log","/tmp/gor_diag.log","/tmp/gor_watch_later","/tmp/webtorrent_stream","/tmp/hidden_mpv_1.sock"] {precondition(stage.temp(p)==prefix+p)}
precondition(stage.home(original).path==prefix+"/home")
precondition(stage.temp("/Users/owner/secret")=="/dev/null")
for p in ["", "/tmp/global", "/tmp/.gor-autoupdate/staging/../escape"] {
 let invalid=StagedPathPolicy(bundleID:"com.gokcebalkan.gor.staging",environment:["GOR_STAGED_PATH_PREFIX":p]);precondition(!invalid.valid)
}
let missing=StagedPathPolicy(bundleID:"com.gokcebalkan.gor.staging",environment:[:]);precondition(!missing.valid)
print("PASS actual Swift path policy: production output byte-identical including malicious overrides; staging prefix/invalid-root refusal; home/config isolation")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text('import Foundation\n'+policy+'\n'+body)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
a=_core_read(root/'Sources/gor/App/AppDelegate.swift')
# B1 production policy unchanged; B2 real embedded Python guard is executed by test_core.
assert re.search(r'guard StagedRunPaths\.prepare\(\) else \{(?: quitDebug\("staged prepare failed"\);)? exit\(1\) \}',a)
assert 'guard !Self.hasLaunched else { return }' in a
# B3 logs, script seeding and asset-support writes use explicit prefix, not HOME inference.
assert a.count('StagedRunPaths.support(')==3
assert 'guard !StagedRunPaths.active else { return }' in a.split('private func armStartupExitLogCollector',1)[1][:150]
assert '["--output", logPath]' in a
# B4 harness uses staged defaults id; native UserDefaults/TCC remain NOT_RUN.
h=_core_read(root/'gor-selftest.sh')
assert "'/usr/bin/defaults','read',bundle_id" in h
# B5 no foreground activate, duplicate-id activation, device listeners or event taps in staged mode.
for line in a.splitlines():
 if 'NSApp.activate(ignoringOtherApps' in line or 'existing.activate(options:' in line:assert '!StagedRunPaths.active' in line,line
assert 'setActivationPolicy(StagedRunPaths.active ? .prohibited : .regular)' in a
assert 'if !StagedRunPaths.active { setupEventTap() }' in a
# B6 no prefix enumeration or global process kill in staged mode. Preserve production argv.
assert a.count('if !StagedRunPaths.active, let tmpItems =')==2
assert 'if !StagedRunPaths.active { OrphanSweep.sweep(' in a
start=a.index('if !StagedRunPaths.active {\n        let cleanup = Process()');end=a.index('try? killChrome.run()',start)+len('try? killChrome.run()\n        }');kill=a[start:end]
assert 'cleanup.arguments = ["-f", "WorkflowServiceRunner"]' in kill
assert 'killChrome.arguments = ["-9", "chrome-headless-shell"]' in kill
assert kill.rstrip().endswith('}')
for f in ['AppDelegate.swift','Diag.swift']:
 text=_core_read(root/'Sources/gor'/f)
 for line in text.splitlines():
  if 'Darwin.open(' in line and '/tmp/gor_diag.log' in line:assert 'StagedRunPaths.tmp(' in line
# B7 isolated/manual lock and B8 environment stripping are actual runtime core tests.
assert "'GOR_STAGED_PATH_PREFIX':str(worktree/'staged-runtime')" in _core_read(root/'tools/autoupdate.py')
print('PASS staged startup/quit isolation guards at production sites; B7/B8 env tests in test_core; native keychain/sandbox/global child coverage remains NOT_RUN, adapter stays disabled')
