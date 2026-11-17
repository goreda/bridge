from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/ReadinessAnchorSession.swift'
s=SRC.read_text()
PIN='84ab7c80c17d441405756e2fe7d4ed61d54a7c9219c496c3fcf61a9b249e2db3'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('session-decl', 'public struct ReadinessAnchorSession: Sendable, Equatable {'), ('anchor-pending-default-true', 'public private(set) var anchorPending = true'), ('clockstart-gate-typed-refusal', 'guard !anchorPending else { return false }'), ('seek-bumps-generation', 'generation &+= 1')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-session-decl', 'rename', 'public struct ReadinessAnchorSession: Sendable, Equatable {', 'public struct ReadinessAnchorSessi0n: Sendable, Equatable {'), ('removed-clockstart-gate', 'remove', 'guard !anchorPending else { return false }', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-05: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-05: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
