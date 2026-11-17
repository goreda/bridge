from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVCore/OpenURLRouter.swift'
s=SRC.read_text()
PIN='0f3fa4238a8d7d9e3cff41bf625b20b1f9da28027667720f81f8424bf8c6ead6'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('openurlroute-decl', 'public enum OpenURLRoute: Equatable, Sendable {'), ('route-signature', 'public static func route(_ url: String) -> OpenURLRoute {'), ('reason-scheme-not-admitted', 'case schemeNotAdmitted'), ('magnet-missing-btih-refusal', 'guard let q = url.firstIndex(of: "?") else { return .refused(.magnetMissingBtih) }')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-openurlroute-decl', 'rename', 'public enum OpenURLRoute: Equatable, Sendable {', 'public enum OpenURLR0ute: Equatable, Sendable {'), ('removed-route-func', 'remove', 'public static func route(_ url: String) -> OpenURLRoute {', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-15: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-15: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
