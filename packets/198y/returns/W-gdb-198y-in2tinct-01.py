from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/AudioTrackPlan.swift'
s=SRC.read_text()
PIN='24d8e9f53b044811f39268299767fad5a2bf788982133439138f5269c5678c31'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('audiotrackinfo-decl', 'public struct AudioTrackInfo: Equatable, Sendable {'), ('select-signature', 'public static func select(_ selector: AudioTrackSelector, from tracks: [AudioTrackInfo])'), ('audiodelay-limit-600', 'public static let limitSeconds = 600.0'), ('refusal-requested-language-absent', 'case requestedLanguageAbsent(String)')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-audiotrackinfo-decl', 'rename', 'public struct AudioTrackInfo: Equatable, Sendable {', 'public struct AudioTrackInf0: Equatable, Sendable {'), ('removed-audiodelay-limit', 'remove', 'public static let limitSeconds = 600.0', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-01: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-01: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
