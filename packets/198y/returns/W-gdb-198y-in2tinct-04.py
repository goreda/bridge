from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/PreparedShotSession.swift'
s=SRC.read_text()
PIN='d7e6636475d4e1565e43b9741d7946e8d6615642ec92325c457ffd079d3ffb74'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('sourceref-decl', 'public struct SourceRef: Hashable, Sendable {'), ('sourceref-equality', 'public static func == (a: SourceRef, b: SourceRef) -> Bool {'), ('preparedshot-decl', 'public struct PreparedShot: Sendable {'), ('hash-six-kind-buckets', 'case .archiveOrg: h.combine(5)')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-sourceref-decl', 'rename', 'public struct SourceRef: Hashable, Sendable {', 'public struct S0urceRef: Hashable, Sendable {'), ('removed-sourceref-equality', 'remove', 'public static func == (a: SourceRef, b: SourceRef) -> Bool {', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-04: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-04: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
