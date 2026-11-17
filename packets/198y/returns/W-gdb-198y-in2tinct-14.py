from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVCore/Boundary.swift'
s=SRC.read_text()
PIN='29e29ac1cf6dbb2e4a0552c9016347b2a3a5a4aaacceecda6d1b50b8c58fdfef'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('sessionid-decl', 'public struct SessionID: Hashable, Sendable {'), ('identity-authority-shared', 'public static let shared = PlaybackIdentityAuthority()'), ('sourcedescriptor-kind-six', 'public enum Kind: Equatable, Sendable { case local, remote, webTorrent, iptv, ytdl, archiveOrg }'), ('lifecycle-ended-stopreason', 'case idle, opening, ready, playing, paused, buffering, ended(StopReason), failed')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-sessionid-decl', 'rename', 'public struct SessionID: Hashable, Sendable {', 'public struct Sessi0nID: Hashable, Sendable {'), ('removed-kind-enum', 'remove', 'public enum Kind: Equatable, Sendable { case local, remote, webTorrent, iptv, ytdl, archiveOrg }', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-14: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-14: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
