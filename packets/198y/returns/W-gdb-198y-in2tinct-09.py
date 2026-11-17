from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/AudioMasterScheduler/SeekQueueCoordinator.swift'
s=SRC.read_text()
PIN='fced02bd5c04f511aa29836684624ce9ba2c938f5e09d1a2548f833b6aff9f10'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('coordinator-decl', 'public struct SeekQueueCoordinator: Sendable {'), ('decide-signature', 'public func decide(frame: EnqueuedVideoFrame, hostTime: Double) -> VideoDecision {'), ('seekqueueerror-invalidtarget', 'public enum SeekQueueError: Error { case invalidTarget }'), ('finite-nonnegative-guard', 'guard seconds.isFinite, seconds >= 0, hostTime.isFinite else {')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-coordinator-decl', 'rename', 'public struct SeekQueueCoordinator: Sendable {', 'public struct SeekQueueCoordinat0r: Sendable {'), ('removed-decide-func', 'remove', 'public func decide(frame: EnqueuedVideoFrame, hostTime: Double) -> VideoDecision {', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-09: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-09: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
