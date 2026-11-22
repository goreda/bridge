from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]/'Packages/gorav'
SRC=ROOT/'Sources/GorAVFFmpegAdapter/L3Admission.swift'
s=SRC.read_text()
PIN='a99be5ffe4480da5ebdf1565c4baf65038fc35c90f7fe5dcf46b93efb107f2b6'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('pixelclass-decl', 'public enum L3PixelClass: Equatable, Sendable {'), ('classification-signature', 'public static func classification(_ format: Int32) -> L3PixelClass {'), ('refuse-case', 'case refuse'), ('ten-bit-preserved-allowlist', 'case AV_PIX_FMT_YUV420P10LE.rawValue, AV_PIX_FMT_P010LE.rawValue:')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-pixelclass-decl', 'rename', 'public enum L3PixelClass: Equatable, Sendable {', 'public enum L3PixelCl4ss: Equatable, Sendable {'), ('removed-classification-func', 'remove', 'public static func classification(_ format: Int32) -> L3PixelClass {', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-08: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-08: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
