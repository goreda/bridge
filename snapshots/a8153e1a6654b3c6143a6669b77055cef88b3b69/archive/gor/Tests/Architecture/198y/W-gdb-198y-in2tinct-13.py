from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]/'Packages/gorav'
SRC=ROOT/'Sources/GorAVFFmpegAdapter/FrameObservation.swift'
s=SRC.read_text()
PIN='be334edb495a9558371d20bde9b301a35071bb43c1e2521dcc0ce5791ff3fa8b'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('frameobservation-decl', 'public struct FrameObservation: Equatable, Sendable {'), ('observationrefusal-decl', 'public enum ObservationRefusal: Error, Equatable, Sendable {'), ('foreign-or-stale-session-case', 'case foreignOrStaleSession'), ('sessiontracekind-terminal-cases', 'case terminalEOF, terminalInterrupted, terminalFailed, closed')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-frameobservation-decl', 'rename', 'public struct FrameObservation: Equatable, Sendable {', 'public struct FrameObservati0n: Equatable, Sendable {'), ('removed-observationrefusal-enum', 'remove', 'public enum ObservationRefusal: Error, Equatable, Sendable {', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-13: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-13: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
