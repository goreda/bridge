from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/ControlBus.swift'
s=SRC.read_text()
PIN='eded915407feb11e4e2c57245b2f7a58b0fcc255e6cc6c8fe35f6c4cbd615eb3'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('normalizedrect-decl', 'public struct NormalizedRect: Equatable, Sendable {'), ('normalizedrect-full', 'public static let full = NormalizedRect(x: 0, y: 0, w: 1, h: 1)!'), ('routeplan-pack-guard', 'guard (0...255).contains(pack), aspect.isFinite, aspect >= 0 else { return nil }'), ('stale-revision-refusal', 'case staleRevision(current: ParameterBlockRevision)')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-normalizedrect-decl', 'rename', 'public struct NormalizedRect: Equatable, Sendable {', 'public struct NormalizedR3ct: Equatable, Sendable {'), ('removed-routeplan-guard', 'remove', 'guard (0...255).contains(pack), aspect.isFinite, aspect >= 0 else { return nil }', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-19: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-19: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
