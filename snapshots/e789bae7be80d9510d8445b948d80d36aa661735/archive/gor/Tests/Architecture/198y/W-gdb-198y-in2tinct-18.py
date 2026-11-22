from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]/'Packages/gorav'
SRC=ROOT/'Sources/GorAVPlaybackCore/ColorStage.swift'
s=SRC.read_text()
PIN='daf6de8af2d598408d621bb687b542d47583dc458f9a462ed4648720193be081'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('sourcetrc-decl', 'public enum SourceTRC: String, Equatable, Sendable {'), ('tonemapcurve-five', 'case none, clip, mobius, hable, reinhard'), ('sdr100-target', 'public static let sdr100 = DisplayTarget(targetTRC: .bt709, peakNits: 100)!'), ('plan-signature', 'public static func plan(source: SourceSignal, target: DisplayTarget,')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-sourcetrc-decl', 'rename', 'public enum SourceTRC: String, Equatable, Sendable {', 'public enum S0urceTRC: String, Equatable, Sendable {'), ('removed-sdr100-target', 'remove', 'public static let sdr100 = DisplayTarget(targetTRC: .bt709, peakNits: 100)!', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-18: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-18: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
