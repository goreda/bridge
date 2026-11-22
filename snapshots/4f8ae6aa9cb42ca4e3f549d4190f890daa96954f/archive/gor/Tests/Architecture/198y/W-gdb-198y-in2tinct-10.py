from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]/'Packages/gorav'
SRC=ROOT/'Sources/GorAVAudioClockSwift/AudioPacing.swift'
s=SRC.read_text()
PIN='d52e3f5e977f954717f63b65942782f4232c1dcbe1826e47bcbefe0bda717b3f'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('policy-decl', 'public final class AudioPacingPolicy {'), ('policy-failable-init', 'public init?(hostClock: @escaping @Sendable () -> Double, sampleRate: UInt32,'), ('setdelay-limit-guard', 'guard newDelay.isFinite, abs(newDelay) <= AudioDelay.limitSeconds else { return false }'), ('admission-stale-generation-gate', 'guard fenceActive == expectedGeneration else { return .staleGeneration }')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-policy-decl', 'rename', 'public final class AudioPacingPolicy {', 'public final class AudioPacingP0licy {'), ('removed-setdelay-guard', 'remove', 'guard newDelay.isFinite, abs(newDelay) <= AudioDelay.limitSeconds else { return false }', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-10: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-10: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
