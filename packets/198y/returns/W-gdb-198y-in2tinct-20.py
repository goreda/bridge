from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/CoreSeekDriver.swift'
s=SRC.read_text()
PIN='3fdb2fa68692956b72389c964dfb6dfee41f0a95581dc8928afa86cf6349adf5'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('admission-refusal-decl', 'public enum CoreSeekAdmissionRefusal: Sendable, Equatable {'), ('outcome-committed', 'case committed(receipt: SeekReceipt)      // nativeReady: ACK fired with the adopted revision'), ('driver-decl', 'public final class CoreSeekDriver: @unchecked Sendable {'), ('nosource-admission-gate', 'guard let binding = provider.currentBinding() else { return .admissionRefused(reason: .noSource) }')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-driver-decl', 'rename', 'public final class CoreSeekDriver: @unchecked Sendable {', 'public final class CoreSeekDriv3r: @unchecked Sendable {'), ('removed-nosource-gate', 'remove', 'guard let binding = provider.currentBinding() else { return .admissionRefused(reason: .noSource) }', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-20: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-20: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
