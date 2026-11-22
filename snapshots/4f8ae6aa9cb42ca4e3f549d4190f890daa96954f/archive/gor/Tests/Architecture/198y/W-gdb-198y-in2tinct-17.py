from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]/'Packages/gorav'
SRC=ROOT/'Sources/GorAVPlaybackCore/ChromeStateModel.swift'
s=SRC.read_text()
PIN='d84e80064f7536d1135227044348ceee2377c9da3883fcbceac0544dd2d627e7'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('chromestatemodel-decl', 'public struct ChromeStateModel: Equatable, Sendable {'), ('chrome-filter-default-orange', 'public static let chromeFilter = 1.0               // orange default'), ('hue-ema-alpha', 'public static let hueEmaAlpha = 0.08               // photon-common HUE_EMA_ALPHA'), ('filter-names-four', 'public static let filterNames = ["red", "orange", "yellow", "green"]')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-chromestatemodel-decl', 'rename', 'public struct ChromeStateModel: Equatable, Sendable {', 'public struct ChromeStateM0del: Equatable, Sendable {'), ('removed-filter-names', 'remove', 'public static let filterNames = ["red", "orange", "yellow", "green"]', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-17: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-17: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
