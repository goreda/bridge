from pathlib import Path
import hashlib, sys
ROOT=Path(__file__).resolve().parents[3]
SRC=ROOT/'Sources/GorAVPlaybackCore/ArchiveItemSource.swift'
s=SRC.read_text()
PIN='b3ceab524aed7067e6744c6885cf14f343cf52b09300bb87e6a676ae4c5781bd'
failures=[]
def check(name,cond):
    print(('PASS' if cond else 'FAIL'),name)
    if not cond: failures.append(name)

# A1 source identity (baseline, kept)
check('A1-source-pin-sha256', hashlib.sha256(s.encode()).hexdigest()==PIN)
# declaration assertions on the shown production declarations (packet-specific)
DECLS=[('archiveitemsource-decl', 'public enum ArchiveItemSource {'), ('max-metadata-8mib', 'public static let maxMetadataBytes = 8 * 1024 * 1024'), ('identifier-charset-guard', 'guard !id.isEmpty, id != ".", id != "..", id.unicodeScalars.allSatisfy(allowed.contains) else {'), ('duplicate-file-refusal', 'guard matches.count == 1 else { throw ArchiveItemSourceError.duplicateFile }')]
for name,frag in DECLS:
    check('D-'+name, frag in s)
# A3 byte-drift mutant rejected (baseline, kept)
check('A3-byte-drift-mutant-rejected', hashlib.sha256((s+'// mutant').encode()).hexdigest()!=PIN)
# mutant rejection self-checks: the characterization must reject renamed/removed declarations
def decl_fail_count(text):
    return sum(1 for _,frag in DECLS if frag not in text)
MUTS=[('renamed-archiveitemsource-decl', 'rename', 'public enum ArchiveItemSource {', 'public enum ArchiveItemS0urce {'), ('removed-max-metadata-cap', 'remove', 'public static let maxMetadataBytes = 8 * 1024 * 1024', '')]
for name,kind,old,new in MUTS:
    if kind=='rename':
        m=s.replace(old,new,1)
        check('M-'+name, m!=s and decl_fail_count(m)>=1)
    else:
        lines=[l for l in s.splitlines() if old not in l]
        m='\n'.join(lines)
        check('M-'+name, len(lines)<len(s.splitlines()) and decl_fail_count(m)>=1)
if failures:
    print('CHARACTERIZATION_FAIL W-gdb-198y-in2tinct-16: '+','.join(failures)); sys.exit(1)
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-16: source identity, 4 named declaration assertions, 2 removed/renamed-declaration mutants rejected; source-only, not runtime')
