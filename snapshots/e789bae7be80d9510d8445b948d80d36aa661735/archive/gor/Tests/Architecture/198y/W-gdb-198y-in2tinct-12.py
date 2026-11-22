from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]/'Packages/gorav'
SRC=ROOT/'Sources/GorAVSubtitles/SubtitleTrack.swift'
s=SRC.read_text()
PIN='d0e635a1ec87e20d75cfdb59dd75fb4f9aec24f7c54a2f88f84dab154518b969'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('subtitletrack-decl', 'public enum SubtitleTrack {'), ('load-signature', 'public static func load(path: String) throws -> Track {'), ('format-allowlist-guard', 'guard ext == "srt" || ext == "ass" || ext == "ssa" else { throw LoadError.unknownFormat(path: path) }'), ('track-decl', 'public struct Track: Equatable, Sendable {')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-track-decl', 'rename', 'public struct Track: Equatable, Sendable {', 'public struct Tr4ck: Equatable, Sendable {'), ('removed-load-func', 'remove', 'public static func load(path: String) throws -> Track {', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-12: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-12: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
