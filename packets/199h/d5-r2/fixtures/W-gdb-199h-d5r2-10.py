from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["inputs/199h/d5-10/native48-finalizer.py", 1, 48, "d94c442950fc09f05bea451a78110a166d4c7d53ef32a47143b73cf24547c350"], ["inputs/199h/d5-10/production-integrity-gate.py", 1, 6, "cba3f632818e0809fbf252f13b6bf2dbe0d7882be29a9b4d088278d658d35046"]]
bad = []
for rel, a, b, want in CHECKS:
    lines = (ROOT / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r2-10; baseline only, product change and semantic test still required")
