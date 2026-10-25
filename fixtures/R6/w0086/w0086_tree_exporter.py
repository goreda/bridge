#!/usr/bin/env python3
"""W-0086 requester-supplied fixture: toy versioned-tree exporter, seed 13.
Builds 30 commits of mixed text/binary edits across 5 files, then exports one
full bundle at commit 6 and 4 incrementals at commits 12/18/24/30.

BUNDLE FORMAT (REQUESTER-STATED, per the published R6-6 "tar or git-bundle
format stated" contract): tar (ustar), deterministic - sorted members,
mtime=0, uid/gid=0, uname/gname="", no pax headers, so shas reproduce.

Repaired 2026-10-25 under independent review W86: the previous export used a
JSON format ("r6bundle/1") that matched NEITHER of the published contract's
enumerated formats (tar or git-bundle). This repair emits actual tar via the
standard library only; no git dependency. Tree construction, seed, per-tip
file trees, delete semantics and the single-byte corruption are unchanged.

Archive layout:
  r6chain.txt      first member; plain-text chain header "base: <int|none>" /
                   "tip: <int>" - in-band continuity data for reorder detection
  .wh.<path>       empty whiteout member = delete <path> (overlayfs convention)
  <path>           full current content of each file changed in (base, tip]
Incrementals carry FULL per-file snapshots (last-writer-wins), NOT deltas.
CONSEQUENCE (honest caveat): a corruption in link k is healed by any later
link that rewrites the same file, so a verifier that checks ONLY the final
tip can pass despite a corrupt link. The verifier MUST check EVERY tip
position byte-identically against the manifest, never the final tip only.

Also emits inc-3-24-CORRUPTED.tar: inc-3-24.tar with ONE byte flipped inside
the first file payload (blob.bin data block). Tar data blocks are not
checksummed, so the archive still opens and extracts; content-sha mismatch
against the manifest is the detection path, exactly as published.
True tip file sha256s and bundle shas are recorded in chain_truth.json.
"""
import hashlib, io, json, random, sys, tarfile

FILES = ["notes.txt", "data.bin", "index.md", "table.csv", "blob.bin"]
CHAIN_HEADER = "r6chain.txt"

def build_commits():
    rng = random.Random(13)
    tree = {f: b"" for f in FILES}
    commits = []
    for c in range(1, 31):
        diff = {}
        for f in rng.sample(FILES, rng.randint(1, 3)):
            if rng.random() < 0.15 and tree[f]:
                diff[f] = None  # delete
                tree[f] = b""
            else:
                blob = (f"commit {c} {f} " + "".join(rng.choice("abcdef0123456789") for _ in range(40))).encode()
                if f.endswith(".bin"):
                    blob += bytes(rng.getrandbits(8) for _ in range(64))
                tree[f] = tree[f] + blob
                diff[f] = tree[f]
        commits.append(diff)
    return commits

def tip_tree(commits, tip):
    tree = {}
    for d in commits[:tip]:
        for f, content in d.items():
            if content is None:
                tree.pop(f, None)
            else:
                tree[f] = content
    return tree

def _add_member(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mtime = 0
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))

def bundle(base, tip, files):
    """files: {path: content bytes | None for delete}. Returns deterministic ustar bytes."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        hdr = f"base: {'none' if base is None else base}\ntip: {tip}\n".encode()
        _add_member(tar, CHAIN_HEADER, hdr)
        for p in sorted(files):
            if files[p] is None:
                _add_member(tar, ".wh." + p, b"")
        for p in sorted(files):
            if files[p] is not None:
                _add_member(tar, p, files[p])
    return buf.getvalue()

def run(outdir):
    commits = build_commits()
    tips = [6, 12, 18, 24, 30]
    shas = {}
    # full bundle at tip 6: complete file tree
    b = bundle(None, 6, tip_tree(commits, 6))
    open(f"{outdir}/full-06.tar", "wb").write(b)
    shas["full-06.tar"] = (len(b), hashlib.sha256(b).hexdigest())
    # incrementals: last-writer-wins union of diffs in (prev, tip]
    for i, tip in enumerate(tips[1:], 1):
        merged = {}
        for d in commits[tips[i - 1]:tip]:
            for f, content in d.items():
                merged[f] = content
        b = bundle(tips[i - 1], tip, merged)
        name = f"inc-{i}-{tip:02d}.tar"
        open(f"{outdir}/{name}", "wb").write(b)
        shas[name] = (len(b), hashlib.sha256(b).hexdigest())
    # corrupted copy of inc-3-24: flip ONE byte inside the blob.bin data block.
    # Tar data blocks carry no checksum, so the tar stays valid; the restored
    # content sha mismatch is the detection path (NOT a parse failure).
    raw = bytearray(open(f"{outdir}/inc-3-24.tar", "rb").read())
    with tarfile.open(f"{outdir}/inc-3-24.tar") as t:
        pos = t.getmember("blob.bin").offset_data
    raw[pos] = ord("A") if raw[pos] != ord("A") else ord("B")
    open(f"{outdir}/inc-3-24-CORRUPTED.tar", "wb").write(bytes(raw))
    shas["inc-3-24-CORRUPTED.tar"] = (len(raw), hashlib.sha256(bytes(raw)).hexdigest())
    truth = {"seed": 13, "commits": 30, "tips": tips,
             "format": "tar (ustar), deterministic: sorted members, mtime=0, uid/gid=0, uname/gname='', no pax",
             "chain_header_member": CHAIN_HEADER,
             "delete_convention": "empty whiteout member .wh.<path> (overlayfs convention)",
             "incremental_semantics": "full per-file snapshots, last-writer-wins; NOT deltas - check EVERY tip, a later link can heal a corrupt earlier one",
             "tip_file_sha256": {str(t): {p: hashlib.sha256(c).hexdigest() for p, c in sorted(tip_tree(commits, t).items())} for t in tips},
             "corrupt_link": "inc-3-24-CORRUPTED.tar",
             "bundles": {k: {"bytes": v[0], "sha256": v[1]} for k, v in shas.items()}}
    with open(f"{outdir}/chain_truth.json", "w") as f:
        json.dump(truth, f, indent=1)
    print("w0086 OK format=tar tips=6,12,18,24,30 corrupted=inc-3-24")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
