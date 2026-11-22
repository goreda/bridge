from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]/'Packages/gorav'
SRC=ROOT/'Sources/GorAVCore/AdmissionTable.swift'
s=SRC.read_text()
PIN='ed59ce0f6b3a89fc2290fb5a11ae71f30ded122d99caea68f5962d7c19ab049a'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('admissiontable-decl', 'public enum AdmissionTable {'), ('containers-allowlist', 'public static let containers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts", "wav"]'), ('video-codecs-allowlist', 'public static let videoCodecs: Set<String> = ["mpeg4", "h264", "hevc", "av1", "vp9"]'), ('remote-schemes-http-https', 'public static let admittedRemoteSchemes: [String] = ["http", "https"]')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-admissiontable-decl', 'rename', 'public enum AdmissionTable {', 'public enum Admissi0nTable {'), ('removed-video-codecs', 'remove', 'public static let videoCodecs: Set<String> = ["mpeg4", "h264", "hevc", "av1", "vp9"]', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-07: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-07: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
