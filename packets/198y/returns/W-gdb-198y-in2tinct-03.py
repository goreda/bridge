from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/ObservationSurface.swift'
s=SRC.read_text()
PIN='206cbc0e2af2bea0070e31212cc17a1af06a7f58e455f0244b540c5135cb53fd'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('observationvalue-decl', 'public enum ObservationValue: Equatable, Sendable {'), ('property-rawvalue-timepos', 'case timePos = "time-pos"'), ('property-rawvalue-hwdec', 'case hwdecCurrent = "hwdec-current"'), ('property-enum-string-raw', 'public enum ObservationProperty: String, CaseIterable, Sendable {')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-observationvalue-decl', 'rename', 'public enum ObservationValue: Equatable, Sendable {', 'public enum ObservationValu3: Equatable, Sendable {'), ('removed-timepos-property', 'remove', 'case timePos = "time-pos"', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-03: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-03: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
