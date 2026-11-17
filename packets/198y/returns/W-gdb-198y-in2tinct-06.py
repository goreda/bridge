from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/TapCropDetector.swift'
s=SRC.read_text()
PIN='648d03d4fd0cdfff34cabd7f52e97e6c8282963b8ba2e6cab018ab6892423f53'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('lumaplane-decl', 'public struct LumaPlane: Equatable, Sendable {'), ('lumaplane-init-guard', 'guard width > 0, height > 0, strideBytes >= width else { return nil }'), ('detect-signature', 'public static func detect(_ p: LumaPlane, config: BorderScanConfig = BorderScanConfig())'), ('bar-max-luma-default-16', 'public var barMaxLuma: Int = 16')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-lumaplane-decl', 'rename', 'public struct LumaPlane: Equatable, Sendable {', 'public struct LumaPl4ne: Equatable, Sendable {'), ('removed-bar-max-luma', 'remove', 'public var barMaxLuma: Int = 16', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-06: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-06: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
